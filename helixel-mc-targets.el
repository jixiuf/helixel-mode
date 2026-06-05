;;; helixel-mc-targets.el --- Compute mc spawn targets from selections -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

;; Author: jixiuf
;; Keywords: convenience

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;;; Commentary:

;; Target-computation layer for multi-cursor spawning.
;;
;; (toggle, add-here, mark-next-like-this, rotate, merge, …) live
;; in mc-spawn.el and depend on the smaller surface here.
;;
;; Exports:
;;   helixel-mc--make-target        — (point . mark) marker pair
;;   helixel-mc--free-targets
;;   helixel-mc--realize-targets    — install targets as cursors
;;   helixel-mc--make-dummy-tx      — minimal event for advance fns
;;   helixel-mc--walk-advance       — fallback for unregistered kinds
;;   helixel-mc-spawn-from-sel      — generic dispatcher (kind → fn)
;;   helixel-mc-spawn-from-line / -from-rect / -from-find-char
;;   helixel-mc--register-default-spawn-fns
;;
;; Strategy: a kind may provide `:mc-spawn-fn' in the kind registry
;; for a custom buffer-wide scan; otherwise we walk the kind's
;; `:advance' function from `point-min' collecting every advance
;; landing point.  See `helixel-mc--walk-advance' for the snapshot
;; / restore discipline that keeps event-tracking globals clean
;; during the walk.

;;; Code:

(require 'cl-lib)
(require 'helixel-core)
(require 'helixel-mc-core)

(declare-function helixel--recreate-selection "helixel-repeat")

;; Special vars from helixel-repeat / helixel-search — must be `defvar'
;; so the `let' binding below is treated as dynamic, not lexical.
(defvar helixel--pending-sel)
(defvar helixel--last-action)
(defvar helixel--live-action)
(defvar helixel--raw-selection-type)

;; ── Helpers ──

(defsubst helixel-mc--make-target (point &optional mark)
  "Return a (POINT . MARK) marker pair for a spawn target."
  (cons (copy-marker point t)
        (copy-marker (or mark point) t)))

(defun helixel-mc--free-targets (targets)
  "Release marker pairs in TARGETS."
  (dolist (p targets)
    (when (markerp (car p)) (set-marker (car p) nil))
    (when (markerp (cdr p)) (set-marker (cdr p) nil))))

(defun helixel-mc--realize-targets (targets)
  "Create one fake cursor per (POINT . MARK) pair in TARGETS.
The target whose range contains the real point (or, failing that,
the target nearest to point) is treated as the \"real\" target:
its (POINT . MARK) is installed on the real cursor (mark-active
on if the pair is a real range), and a fake cursor is NOT created
for it.  Every other target becomes a fake cursor.

This means the real cursor and every fake cursor end up with the
same `point' / `mark' direction and the same `mark-active' state,
so commands like `i' / `a' / `d' / `c' behave identically across
them.

Returns count of fake cursors created."
  (when (null targets)
    (user-error "No multi-cursor targets"))
  (let* ((real (point))
         (range-pos (lambda (p)
                      (let* ((a (marker-position (car p)))
                             (b (and (cdr p)
                                     (marker-position (cdr p)))))
                        (cons (min a (or b a)) (max a (or b a))))))
         ;; Prefer a target whose [beg..end] contains real point.
         (containing
          (cl-find-if (lambda (p)
                        (let ((r (funcall range-pos p)))
                          (and (<= (car r) real) (<= real (cdr r)))))
                      targets))
         ;; Fallback: nearest by min-distance to either edge.
         (closest
          (or containing
              (cl-reduce
               (lambda (a b)
                 (let ((ra (funcall range-pos a))
                       (rb (funcall range-pos b)))
                   (if (< (min (abs (- (car ra) real))
                               (abs (- (cdr ra) real)))
                          (min (abs (- (car rb) real))
                               (abs (- (cdr rb) real))))
                       a b)))
               targets)))
         (count 0))
    (dolist (p targets)
      (unless (eq p closest)
        (helixel-mc-create-fake-cursor
         (marker-position (car p))
         (and (cdr p)
              (/= (marker-position (cdr p))
                  (marker-position (car p)))
              (marker-position (cdr p))))
        (cl-incf count)))
    ;; Install chosen target on the real cursor.
    (let* ((cpt (marker-position (car closest)))
           (cmk (and (cdr closest) (marker-position (cdr closest)))))
      (goto-char cpt)
      (cond
       ((and cmk (/= cmk cpt))
        (set-marker (mark-marker) cmk)
        (setq mark-active t))
       (t
        (setq mark-active nil))))
    (helixel-mc--free-targets targets)
    count))

;; ── Advance-walk fallback ──

(defun helixel-mc--make-dummy-tx (sel)
  "Build a minimal `helixel-action' carrying SEL for advance fns."
  (let ((m (point-marker)))
    (make-helixel-action
     :sel sel :op nil :payload nil
     :mark-region (cons m (copy-marker m t))
     :timestamp (float-time)
     :buffer (current-buffer))))

(defun helixel-mc--walk-advance (sel)
  "Walk SEL's :advance function from `point-min', collect target pairs.
Returns a list of (POINT . MARK) marker pairs.  Each iteration
captures the current region (if any) or point as a target.
Detects in-place recreate (where :advance moves no cursor — common
for textobj) and force-advances point past the last region so the
next iteration lands on a fresh target.  Bounded by
`helixel-mc-max-cursors' to avoid runaways.

Fully isolates helixel's event / selection / tracking globals so
the walk does NOT pollute `helixel--last-action',
`helixel--pending-sel', `helixel--live-action' or
`helixel--raw-selection-type'.  Without this, textobj advance
functions (which internally re-run the textobj command and
capture `this-command') would clobber `helixel--last-action'
with a sel whose `:command' is the outer mc command (e.g.
`helixel-mc-toggle' with an accumulated `:count' equal to the
number of walk iterations), breaking dot-repeat at fake cursors."
  (let* ((kind (helixel-sel-kind sel))
         (advance-fn (helixel--kind-advance kind))
         (limit (or helixel-mc-max-cursors 1000))
         (targets nil)
         (last-key nil))
    (unless advance-fn
      (user-error "No mc-spawn / advance for kind `%s'" kind))
    (helixel-mc-with-saved-state
      (save-excursion
        (helixel-with-replay-as 'dot
            (deactivate-mark)
            (goto-char (point-min))
            ;; Search-advance scratch lives on the replay ctx the macro
            ;; just bound — no need to bind globals here.
            (let ((tx (helixel-mc--make-dummy-tx sel)))
        (catch 'done
          (while (< (length targets) limit)
            (let ((before (point)))
              ;; Clean slate before each advance so we cannot read a
              ;; stale `(mark t)' value left over from the previous
              ;; iteration.  Setting the mark-marker to point ensures
              ;; `have-range' below truly reflects what THIS iter set.
              (deactivate-mark)
              (set-marker (mark-marker) (point))
              (unless (condition-case nil
                          (funcall advance-fn tx)
                        (error nil))
                (throw 'done nil))
              (let* ((mrk (mark t))
                     ;; `have-range' demands a mark AND `mark-active'
                     ;; (so the advance fn truly selected something).
                     ;; The mark-marker reset above means `mrk' can
                     ;; only be "real" data set by the advance fn.
                     (have-range (and mrk mark-active
                                      (/= mrk (point))))
                     (pt (point))
                     (mk (if have-range mrk pt))
                     (rb (min pt mk))
                     (re (max pt mk))
                     (key (cons rb re))
                     (no-progress (and (eq pt before) (not have-range))))
                ;; Same range as last time → no progress, bail.
                (when (equal key last-key)
                  (throw 'done nil))
                (setq last-key key)
                ;; Skip degenerate single-point targets that come from
                ;; an in-place recreate that didn't actually find
                ;; anything (e.g. textobj with no word at point), and
                ;; pure-whitespace targets that textobj walkers tend to
                ;; produce when running off the last word.
                ;;
                ;; Also skip targets that OVERLAP any earlier target:
                ;; textobj fallbacks at EOB (no thing at point) return
                ;; `(point-min . point-max)' as the "inner word", which
                ;; would otherwise produce a spurious huge cursor
                ;; spanning the whole buffer.
                (let ((overlaps-prior
                       (and have-range
                            (cl-some
                             (lambda (tg)
                               (let ((a (marker-position (car tg)))
                                     (b (marker-position (cdr tg))))
                                 (let ((tb (min a b)) (te (max a b)))
                                   (and (< rb te) (< tb re)))))
                             targets))))
                  (unless (or no-progress
                              overlaps-prior
                              (and have-range
                                   (string-match-p
                                    "\\`[ \t\n\r\f]*\\'"
                                    (buffer-substring-no-properties
                                     rb re))))
                    ;; Store as (point . mark) so create-fake-cursor
                    ;; gets the same point/mark direction the advance fn
                    ;; produced.
                    (push (helixel-mc--make-target pt mk) targets)))
                ;; In-place recreate (textobj): jump past the region
                ;; so the next iteration can land on a fresh target.
                (when (<= (point) before)
                  (deactivate-mark)
                  (goto-char (max re (1+ before)))
                  (when (>= (point) (point-max))
                    (throw 'done nil))))))))))
      (nreverse targets))))

;; ── Generic dispatcher ──

(defun helixel-mc-spawn-from-sel (sel)
  "Spawn fake cursors for SEL.
If SEL's kind has `:mc-spawn-fn' in the registry, use it;
otherwise walk the kind's `:advance' function over the whole
buffer.  Returns count of fake cursors created.

The real cursor is repositioned by `helixel-mc--realize-targets'
to the chosen target (the one nearest / containing point), so its
point / mark / `mark-active' end up matching every fake cursor.

If the chosen target is degenerate (point-only, no range), the
pre-spawn real cursor (point, mark, `mark-active') is restored so
that e.g. `/foo<RET> s s' leaves the original `foo' match active
for the subsequent `i' / `a' / operator to land in the same
region-relative position as on every fake."
  (unless (helixel-sel-p sel)
    (user-error "No selection to spawn from"))
  (let* ((kind (helixel-sel-kind sel))
         (spawn-fn (helixel--kind-mc-spawn-fn kind))
         ;; Snapshot real cursor BEFORE the walk so we can restore
         ;; the region if the chosen target ends up degenerate.
         (saved-pt (point))
         (saved-mk (and (mark t) (marker-position (mark-marker))))
         (saved-active mark-active)
         (targets (if spawn-fn
                      (funcall spawn-fn sel)
                    (helixel-mc--walk-advance sel)))
         (n (helixel-mc--realize-targets targets)))
    ;; If after realize the real cursor lost its prior region (because
    ;; the chosen target was a single-point one), restore it.
    (when (and saved-active saved-mk
               (= (point) saved-pt)
               (not mark-active))
      (set-marker (mark-marker) saved-mk)
      (setq mark-active t))
    n))

;; ── Column spawn (line / rect) ──

(defun helixel-mc-spawn-from-line (_sel)
  "Spawn one fake cursor per line of the active line selection.
_SEL is the originating `line' selection (used only for dispatch).
Each cursor SELECTS its own line: mark at bol, point at eol,
`mark-active' on — the same state a single `x' produces.  This
way operators like `i' / `a' / `d' / `c' act per-line independently
\(`i' → own bol, `a' → own eol, `d' → delete own line, etc.)
rather than treating the whole multi-line region as one block.

The real cursor is repositioned by `helixel-mc--realize-targets'
to the line that contains its current point."
  (unless (use-region-p)
    (user-error "Need an active region to spawn line cursors"))
  (let* ((rb (region-beginning))
         (re (region-end))
         (start-line (line-number-at-pos rb))
         (end-line (line-number-at-pos re))
         (lines (1+ (- end-line start-line)))
         (targets nil))
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- start-line))
      (dotimes (_ lines)
        (unless (eobp)
          (let ((bol (line-beginning-position))
                (eol (line-end-position)))
            ;; (point . mark) = (eol . bol) mimics helixel-select-line.
            (push (helixel-mc--make-target eol bol) targets))
          (forward-line 1))))
    (let ((result (nreverse targets)))
      (unless result
        (user-error "No line targets"))
      result)))

(defun helixel-mc-spawn-from-rect (sel)
  "Spawn column cursors at every line of a rectangle region SEL.
Falls back to `helixel-mc-spawn-from-line' semantics for now."
  (helixel-mc-spawn-from-line sel))

(defun helixel-mc-spawn-from-find-char (sel)
  "Spawn one fake cursor at every occurrence of SEL's :char.
SEL must be a `find-char' selection.  For `:type next' each
cursor lands AFTER the match (mimicking `fx' which leaves point
past the char); for `:type till' each cursor lands ON the char.
No mark / region — the user typically follows up with their own
motion or operator."
  (let* ((ctx (helixel-sel-ctx sel))
         (char (plist-get ctx :char))
         (type (or (plist-get ctx :type) 'next))
         (case-fold-search (if (and char (char-uppercase-p char))
                               nil case-fold-search))
         (needle (and char (char-to-string char)))
         (targets nil))
    (unless needle
      (user-error "Find-char selection has no :char"))
    (save-excursion
      (goto-char (point-min))
      (while (search-forward needle nil t)
        (let ((pos (if (eq type 'till) (1- (point)) (point))))
          (push (helixel-mc--make-target pos) targets))))
    (let ((result (nreverse targets)))
      (unless result
        (user-error "No find-char matches in buffer"))
      result)))

;; ── Kind registrations: hook spawn fns into existing kinds ──

(defun helixel-mc--register-default-spawn-fns ()
  "Attach :mc-spawn-fn to kinds with sane defaults.
Idempotent — re-registering merges via `helixel-register-kind'."
  ;; line / rect → per-line / per-row cursors with own region.
  (puthash 'line
           (plist-put (gethash 'line helixel--kind-registry)
                      :mc-spawn-fn #'helixel-mc-spawn-from-line)
           helixel--kind-registry)
  (puthash 'rect
           (plist-put (gethash 'rect helixel--kind-registry)
                      :mc-spawn-fn #'helixel-mc-spawn-from-rect)
           helixel--kind-registry)
  ;; find-char → scan all char occurrences (advance-walk would only
  ;; visit from origin so we need a buffer-wide scan).
  (puthash 'find-char
           (plist-put (or (gethash 'find-char helixel--kind-registry) nil)
                      :mc-spawn-fn #'helixel-mc-spawn-from-find-char)
           helixel--kind-registry)
  ;; search / textobj / movement inherit the advance-walk fallback
  ;; automatically (no entry needed).
  )

(helixel-mc--register-default-spawn-fns)


(provide 'helixel-mc-targets)
;;; helixel-mc-targets.el ends here
