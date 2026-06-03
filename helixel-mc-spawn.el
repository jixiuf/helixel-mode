;;; helixel-mc-spawn.el --- High-level multi-cursor commands -*- lexical-binding: t; -*-

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

;; High-level multi-cursor user commands.
;;
;; Target computation (spawn-from-* + advance walk + kind registry
;; hooks) lives in `helixel-mc-targets'.  This file builds the
;; interactive layer on top:
;;
;;   helixel-mc-toggle                — spawn from sel / clear
;;   helixel-mc-add-cursor-here / -up
;;   helixel-mc-edit-lines
;;   helixel-mc-mark-next-like-this / -previous-like-this
;;   helixel-mc-skip-next / -skip-previous
;;   helixel-mc-unmark-next / -unmark-previous
;;   helixel-mc-remove-primary / -keep-primary
;;   helixel-mc-rotate-primary-forward / -backward
;;   helixel-mc-rotate-content-forward / -backward
;;   helixel-mc-keep-matching / -remove-matching
;;   helixel-mc-merge / -trim / -align
;;   helixel-mc-split-on-regex
;;   helixel-mc-restore-cursors       — g v history
;;
;; Step 13 of docs/REFACTOR_PLAN.md split the original 1316-line
;; helixel-mc-spawn.el into mc-targets (target computation) and
;; this file (user-facing commands).

;;; Code:

(require 'cl-lib)
(require 'helixel-core)
(require 'helixel-mc-core)
(require 'helixel-mc-targets)

(declare-function helixel--recreate-selection "helixel-repeat")

;; Special vars from helixel-repeat — must be `defvar' so the `let'
;; bindings below are treated as dynamic, not lexical.
(defvar helixel--pending-sel)
(defvar helixel--last-event)
(defvar helixel--live-event)
(defvar helixel--raw-selection-type)
(defvar helixel--inhibit-action-track)
(defvar helixel--inhibit-repeat-record)

;; ── High-level entry points ──

(defun helixel-mc-toggle ()
  "Toggle multi-cursor: spawn from last selection, or clear if any.

If fake cursors exist → clear them.
Otherwise spawn from:
  1. `helixel--pending-sel' (most recent selection) if non-nil
  2. `helixel--last-event' sel (last edit's selection)
  3. signal `user-error' if neither has a usable selection."
  (interactive)
  (cond
   ((helixel-mc-any-p) (helixel-mc-clear-all))
   (t
    (let ((sel (or (and (boundp 'helixel--pending-sel)
                        helixel--pending-sel)
                   (and (boundp 'helixel--last-event)
                        helixel--last-event
                        (helixel-event-sel helixel--last-event)))))
      (unless sel
        (user-error "No selection to spawn cursors from"))
      (let ((n (helixel-mc-spawn-from-sel sel)))
        (message "helixel-mc: %d fake cursor%s spawned"
                 n (if (= n 1) "" "s")))))))

;; ── Incremental cursor manipulation ──

(defun helixel-mc--copy-cursor-to-direction (direction)
  "Snapshot real cursor to a fake, then move real to next line.
DIRECTION is +1 (down) or -1 (up).

Mirrors Helix `C' / `Alt-C':
  - if a region is active, the region is copied to the next line
    keeping the same column span (point/mark direction preserved);
  - otherwise the point is copied to the next line, same column.

Lines too short to host the column / region span are skipped.
No-op (returns nil) if no suitable target line exists."
  (let* ((had-region (use-region-p))
         (pt-col (current-column))
         (mk (mark t))
         (mk-col (and had-region
                      (save-excursion (goto-char mk) (current-column))))
         (target-pt nil)
         (target-mk nil))
    (save-excursion
      (cl-loop while (zerop (forward-line direction))
               when (and (= (move-to-column pt-col) pt-col)
                         (not (and had-region
                                   (save-excursion
                                     (beginning-of-line)
                                     (end-of-line)
                                     (< (current-column)
                                        (max pt-col mk-col))))))
               return (setq target-pt (point))))
    (when target-pt
      (when had-region
        (save-excursion
          (goto-char target-pt)
          (forward-line 0)
          (move-to-column mk-col)
          (setq target-mk (point))))
      ;; Snapshot the current real position as a fake (unless a fake
      ;; already exists exactly there).
      (unless (cl-find-if
               (lambda (ov)
                 (= (point) (marker-position
                             (overlay-get ov 'helixel-mc-point))))
               (helixel-mc-all-cursors))
        (helixel-mc-create-fake-cursor
         (point) (and had-region mk)))
      ;; Move real to the new target.
      (when had-region (deactivate-mark))
      (goto-char target-pt)
      (when (and had-region target-mk)
        (set-mark target-mk)
        (activate-mark))
      t)))

(defun helixel-mc-add-cursor-here ()
  "Copy current selection / cursor to the line below (Helix `C').

Snapshot the real cursor (with its region, if any) as a fake at
the current position, then move the real cursor to the next line
at the same column.  Repeated invocations stack cursors down the
buffer — the typical Helix multi-cursor entry point.

If the target line is too short to host the column / region
span, skip ahead to the first line that fits.  Signals
`user-error' when no such line exists."
  (interactive)
  (unless (helixel-mc--copy-cursor-to-direction 1)
    (user-error "No line below fits this column/selection")))

(defun helixel-mc-add-cursor-here-up ()
  "Copy current selection / cursor to the line above (Helix `Alt-C').

Like `helixel-mc-add-cursor-here' but moves the real cursor up
instead of down."
  (interactive)
  (unless (helixel-mc--copy-cursor-to-direction -1)
    (user-error "No line above fits this column/selection")))

;;;###autoload
(defun helixel-mc-edit-lines (&optional beg end)
  "Create one cursor per line of the region BEG..END.
With no region, signals `user-error'.

Behavior depends on `helixel--raw-selection-type':

- Line-wise selection (`x'): each cursor gets a full-line REGION
  spanning BOL..EOL of its line.  Apply edits to whole lines (`d',
  `c', `~', etc.) and have them affect each line independently.
  This is the Helix `Alt-s' (split-into-lines) semantics.

- Character-wise selection: each cursor sits at `current-column'
  on its line as a single POINT (no region).  This is mc.el-style
  column editing — useful for inserting / aligning at the same
  visual column.  Lines shorter than that column are skipped.

The line nearest to point keeps the real cursor; every other
line becomes a fake cursor."
  (interactive (when (use-region-p)
                 (list (region-beginning) (region-end))))
  (unless (and beg end) (user-error "Region required"))
  (let* ((line-mode (eq helixel--raw-selection-type 'line))
         (col (and (not line-mode)
                   (save-excursion (goto-char (point)) (current-column))))
         (sl (line-number-at-pos beg))
         (el (line-number-at-pos end))
         ;; If the region ends exactly at BOL of a line, that line
         ;; isn't really part of the selection (line-mode `x' may
         ;; behave that way after the last full line).
         (el (if (and (> el sl)
                      (save-excursion
                        (goto-char end) (bolp)))
                 (1- el)
               el))
         (targets nil))
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- sl))
      (dotimes (_ (1+ (- el sl)))
        (unless (eobp)
          (save-excursion
            (cond
             (line-mode
              ;; Full-line region: point=EOL, mark=BOL (forward).
              (let ((b (line-beginning-position))
                    (e (line-end-position)))
                (push (helixel-mc--make-target e b) targets)))
             (t
              (move-to-column col)
              (when (and (= (current-column) col)
                         (not (eolp)))
                (push (helixel-mc--make-target (point)) targets)))))
          (forward-line 1))))
    (deactivate-mark)
    (when line-mode
      ;; Line-mode entered via `x' sets this; clear so subsequent
      ;; commands don't treat the now-deactivated region as line-wise.
      (setq helixel--raw-selection-type nil))
    (helixel-mc--realize-targets (nreverse targets))))

;; ── Mark next / previous like this ──

(defun helixel-mc--region-text ()
  "Return the active region text, or signal `user-error'."
  (unless (use-region-p)
    (user-error "Need an active region (e.g. `miw') to mark like this"))
  (buffer-substring-no-properties (region-beginning) (region-end)))

(defun helixel-mc--search-for-next (text dir)
  "Search for TEXT in direction DIR (1 forward, -1 backward).
Returns (BEG . END) marker pair on success, nil on failure.
Does not move point."
  (save-excursion
    (let ((case-fold-search nil))
      (when (if (> dir 0)
                (search-forward text nil t)
              (search-backward text nil t))
        (helixel-mc--make-target (match-beginning 0) (match-end 0))))))

(defun helixel-mc--mark-like-this (dir)
  "Add a fake cursor at the next occurrence of region text in DIR.
DIR is 1 (forward) or -1 (backward).  The fake cursor is placed at
the new match; the real cursor stays at its current selection.

Successive calls walk further outward because the search start
point is taken from the most recently spawned fake (highest match
position for forward, lowest for backward), not from the real
cursor — so real never moves and never collides with a fake."
  (let* ((text (helixel-mc--region-text))
         ;; Use the FARTHEST edge (mark or point) of any existing
         ;; fake as the new search anchor so each `s n' lands on a
         ;; fresh occurrence and never re-finds the most recent one.
         (anchor-end
          (cl-loop for ov in (helixel-mc-all-cursors)
                   for p = (marker-position
                            (overlay-get ov 'helixel-mc-point))
                   for m = (marker-position
                            (overlay-get ov 'helixel-mc-mark))
                   for hi = (max p m)
                   for lo = (min p m)
                   when (> dir 0) maximize hi into fwd
                   when (< dir 0) minimize lo into bwd
                   finally return (if (> dir 0) fwd bwd)))
         (start (or anchor-end
                    (if (> dir 0) (region-end) (region-beginning))))
         (target (save-excursion
                   (goto-char start)
                   (helixel-mc--search-for-next text dir))))
    (unless target
      (user-error "No more matches for `%s'" text))
    ;; Direction-consistency: if real has point at region-END (forward
    ;; selection — `miw' leaves it like that), fake gets point=match-end
    ;; / mark=match-begin.  If real has point at region-BEGIN (backward
    ;; — e.g. after `b' then `miw'), fake gets point=match-begin /
    ;; mark=match-end.  Otherwise insert at start (`i') and append at
    ;; end (`a') behave inconsistently across cursors.
    (let* ((tb (marker-position (car target)))
           (te (marker-position (cdr target)))
           (forward-p (>= (point) (mark t))))
      (helixel-mc-create-fake-cursor
       (if forward-p te tb)
       (if forward-p tb te)))
    (helixel-mc--free-targets (list target))))

;;;###autoload
(defun helixel-mc-mark-next-like-this ()
  "Add a fake cursor at the next occurrence of the region text."
  (interactive)
  (helixel-mc--mark-like-this 1))

;;;###autoload
(defun helixel-mc-mark-previous-like-this ()
  "Add a fake cursor at the previous occurrence of the region text."
  (interactive)
  (helixel-mc--mark-like-this -1))

;;;###autoload
(defun helixel-mc-skip-next ()
  "Skip the next occurrence of the region text without adding a cursor."
  (interactive)
  (let* ((text (helixel-mc--region-text))
         (re (region-end))
         (target (save-excursion
                   (goto-char re)
                   (helixel-mc--search-for-next text 1))))
    (unless target (user-error "No more matches"))
    (goto-char (marker-position (car target)))
    (push-mark (marker-position (cdr target)) t t)
    (helixel-mc--free-targets (list target))))

;;;###autoload
(defun helixel-mc-skip-previous ()
  "Skip the previous occurrence of the region text without adding a cursor."
  (interactive)
  (let* ((text (helixel-mc--region-text))
         (rb (region-beginning))
         (target (save-excursion
                   (goto-char rb)
                   (helixel-mc--search-for-next text -1))))
    (unless target (user-error "No more matches"))
    (goto-char (marker-position (car target)))
    (push-mark (marker-position (cdr target)) t t)
    (helixel-mc--free-targets (list target))))

;;;###autoload
(defun helixel-mc-remove-primary ()
  "Remove the primary cursor and promote the nearest neighbor.
This matches Helix `A-,' semantics.

Swaps real with the nearest fake (next-by-distance cursor),
then deletes the fake that now sits at real's former position.
The net effect: the cursor at real's position is deleted, and
real moves to the nearest remaining cursor — exactly how Helix
removes the primary selection and promotes the next.

After `)` / `(` rotation this deletes the position the user
navigated to, then real moves back to the nearest neighbor
\(typically the cursor they just rotated from)."
  (interactive)
  (unless (helixel-mc-any-p)
    (user-error "No fake cursors"))
  (let* ((sorted (helixel-mc-all-cursors :sort))
         (real-pos (point))
         (nearest nil)
         (nearest-dist most-positive-fixnum))
    ;; Find the nearest fake — this will become the new primary
    ;; after the current one is deleted.
    (dolist (ov sorted)
      (let* ((fp (marker-position (overlay-get ov 'helixel-mc-point)))
             (dist (abs (- fp real-pos))))
        (when (< dist nearest-dist)
          (setq nearest ov
                nearest-dist dist))))
    (unless nearest
      (user-error "No fake cursor to remove"))
    ;; Step 1: swap real with nearest fake.
    ;;   real moves to the neighbor's position (new primary).
    ;;   The old real position (the one to delete) becomes a fake.
    (helixel-mc--swap-real-and-fake nearest)
    ;; Step 2: delete the fake at the position real just vacated
    ;;   (the former primary position).
    (helixel-mc-delete-fake-cursor nearest)))

;;;###autoload
(defun helixel-mc-keep-primary ()
  "Remove all fake cursors except the real cursor (Helix `,' equivalent).
Keeps only the current primary (real cursor) and discards every
other fake cursor."
  (interactive)
  (helixel-mc-clear-all))

(defun helixel-mc-unmark-next ()
  "Remove the next fake cursor after point.
Prefer `helixel-mc-remove-primary' for interactive use — it
matches the Helix `A-,' workflow and is bound to `M-,'."
  (interactive)
  (let ((cursor
         (cl-find-if
          (lambda (ov)
            (> (marker-position (overlay-get ov 'helixel-mc-point))
               (point)))
          (helixel-mc-all-cursors :sort))))
    (unless cursor (user-error "No fake cursor after point"))
    (helixel-mc-delete-fake-cursor cursor)))

;;;###autoload
(defun helixel-mc-unmark-previous ()
  "Remove the fake cursor at the previous match-position before point."
  (interactive)
  (let ((cursor
         (cl-loop for ov in (helixel-mc-all-cursors :sort)
                  when (< (marker-position
                           (overlay-get ov 'helixel-mc-point))
                          (point))
                  collect ov into acc
                  finally return (car (last acc)))))
    (unless cursor (user-error "No fake cursor before point"))
    (helixel-mc-delete-fake-cursor cursor)))

;; Whitelist: helixel-mc commands themselves run only at real cursor.
(helixel-mc-mark-all-for-real-cursor-only
 '(helixel-mc-toggle
   helixel-mc-add-cursor-here
   helixel-mc-add-cursor-here-up
   helixel-mc-edit-lines
   helixel-mc-mark-next-like-this
   helixel-mc-mark-previous-like-this
   helixel-mc-skip-next
   helixel-mc-skip-previous
   helixel-mc-unmark-next
   helixel-mc-unmark-previous
   helixel-mc-remove-primary
   helixel-mc-keep-primary
   helixel-mc-keep-matching
   helixel-mc-remove-matching
   helixel-mc-rotate-primary-forward
   helixel-mc-rotate-primary-backward
   helixel-mc-rotate-content-forward
   helixel-mc-rotate-content-backward
   helixel-mc-merge
   helixel-mc-align
   helixel-mc-trim
   helixel-mc-split-on-regex
   helixel-mc-restore-cursors))

;; ── Helix-style selection management ──
;;
;; These commands mirror Helix's native multi-selection ops and
;; hel-mode's `hel-multiple-cursors-mode-map' bindings.  They are
;; meaningful only when fake cursors exist; outside an mc session
;; they are no-ops (with a `user-error' message).

(defun helixel-mc--cursor-region-text (ov)
  "Return `buffer-substring' of fake cursor OV's selection.
When OV's mark is inactive or degenerate, returns an empty string."
  (let ((p (marker-position (overlay-get ov 'helixel-mc-point)))
        (m (marker-position (overlay-get ov 'helixel-mc-mark)))
        (a (overlay-get ov 'mark-active)))
    (if (and a (/= p m))
        (buffer-substring-no-properties (min p m) (max p m))
      "")))

(defun helixel-mc--current-real-region-text ()
  "Return `buffer-substring' of the real cursor's region, or \"\"."
  (if (use-region-p)
      (buffer-substring-no-properties (region-beginning) (region-end))
    ""))

(defun helixel-mc--filter-cursors (keep-p regex)
  "Keep or remove cursors whose selection text matches REGEX.
When KEEP-P is non-nil, keep cursors matching REGEX (inverse of
`helixel-mc-remove-matching').  When KEEP-P is nil, remove
cursors matching REGEX (inverse of `helixel-mc-keep-matching').

The real cursor is also tested; if it fails the predicate it is
replaced by the first surviving fake (or all cleared if none
survive).  Errors outside an mc session."
  (unless (helixel-mc-any-p)
    (user-error "No fake cursors"))
  (let* ((real-keep
          (if keep-p
              (string-match-p regex
                              (helixel-mc--current-real-region-text))
            (not (string-match-p
                  regex (helixel-mc--current-real-region-text)))))
         (survivors
          (if keep-p
              (cl-remove-if-not
               (lambda (ov)
                 (string-match-p regex (helixel-mc--cursor-region-text ov)))
               (helixel-mc-all-cursors))
            (cl-remove-if
             (lambda (ov)
               (string-match-p regex (helixel-mc--cursor-region-text ov)))
             (helixel-mc-all-cursors)))))
    (dolist (ov (helixel-mc-all-cursors))
      (unless (memq ov survivors)
        (helixel-mc-delete-fake-cursor ov)))
    (unless real-keep
      (if (null survivors)
          (helixel-mc-clear-all)
        (helixel-mc--promote-fake-to-real (car survivors))))
    (message "helixel-mc: %d cursor%s remain"
             (1+ (length (helixel-mc-all-cursors)))
             (if (= 0 (length (helixel-mc-all-cursors))) "" "s"))))

;;;###autoload
(defun helixel-mc-keep-matching (regex)
  "Keep only cursors whose selection text matches REGEX.
Real cursor is also tested; if it fails to match it is REPLACED
by the first surviving fake (or all cleared if none survive).
No-op outside an mc session.

Delegates to `helixel-mc--filter-cursors' with KEEP-P = t."
  (interactive
   (list (read-regexp "Keep cursors matching: ")))
  (helixel-mc--filter-cursors t regex))

;;;###autoload
(defun helixel-mc-remove-matching (regex)
  "Remove cursors whose selection text matches REGEX.
Inverse of `helixel-mc-keep-matching'.  No-op outside mc.

Delegates to `helixel-mc--filter-cursors' with KEEP-P = nil."
  (interactive
   (list (read-regexp "Remove cursors matching: ")))
  (helixel-mc--filter-cursors nil regex))

(defun helixel-mc--promote-fake-to-real (ov)
  "Move real cursor onto fake OV's state, then delete OV.
If the resulting set has no fakes left, fully disables mc mode."
  (let ((p (marker-position (overlay-get ov 'helixel-mc-point)))
        (m (marker-position (overlay-get ov 'helixel-mc-mark)))
        (a (overlay-get ov 'mark-active)))
    (helixel-mc-delete-fake-cursor ov)
    (goto-char p)
    (set-marker (mark-marker) m)
    (setq mark-active a)))

(defun helixel-mc--rotate-primary (dir)
  "Rotate the primary cursor one step in direction DIR.
DIR is a comparison operator (`>', `<', `<=', `>=').
`>' moves forward to the next fake (by buffer position);
`<' moves backward to the previous fake.  Returns non-nil when a
rotation was performed, nil when there are no fakes.

After rotation, the old primary becomes a fake at its position
and the new primary takes over all per-cursor state."
  (unless (helixel-mc-any-p)
    (user-error "No fake cursors"))
  (let* ((sorted (helixel-mc-all-cursors :sort))
         (real (point))
         (candidates (if (eq dir '<) (reverse sorted) sorted))
         (next (or (cl-find-if
                    (lambda (ov)
                      (funcall dir
                               (marker-position
                                (overlay-get ov 'helixel-mc-point))
                               real))
                    candidates)
                   (car sorted))))
    (helixel-mc--swap-real-and-fake next)))

;;;###autoload
(defun helixel-mc-rotate-primary-forward (&optional count)
  "Make the NEXT fake cursor (by buffer position) the primary one.
The old primary becomes a fake at its previous position.  Wraps
from last fake back to first.  Prefix COUNT repeats.

Delegates to `helixel-mc--rotate-primary'."
  (interactive "p")
  (dotimes (_ (or count 1))
    (helixel-mc--rotate-primary '>)))

;;;###autoload
(defun helixel-mc-rotate-primary-backward (&optional count)
  "Make the PREVIOUS fake cursor (by buffer position) the primary one.
Wraps from first fake back to last.  Prefix COUNT repeats.

Delegates to `helixel-mc--rotate-primary'."
  (interactive "p")
  (dotimes (_ (or count 1))
    (helixel-mc--rotate-primary '<)))

(defun helixel-mc--swap-real-and-fake (ov)
  "Swap (point, mark, `mark-active') between real cursor and fake OV.
Leaves a fake at the old real position, and moves real onto OV's
position.  Per-cursor `helixel-mc-cursor-vars' (kill-ring,
pending-sel, etc.) are also swapped."
  (let ((rp (point))
        (rm (mark t))
        (ra mark-active)
        (rvars (mapcar (lambda (v)
                         (cons v (and (boundp v)
                                      (symbol-value v))))
                       helixel-mc-cursor-vars))
        (fp (marker-position (overlay-get ov 'helixel-mc-point)))
        (fm (marker-position (overlay-get ov 'helixel-mc-mark)))
        (fa (overlay-get ov 'mark-active))
        (fvars (mapcar (lambda (v) (cons v (overlay-get ov v)))
                       helixel-mc-cursor-vars)))
    ;; Install fake state on real.
    (goto-char fp)
    (set-marker (mark-marker) fm)
    (setq mark-active fa)
    (dolist (cell fvars)
      (when (boundp (car cell)) (set (car cell) (cdr cell))))
    ;; Install real state on fake overlay.
    (set-marker (overlay-get ov 'helixel-mc-point) rp)
    (set-marker (overlay-get ov 'helixel-mc-mark) rm)
    (overlay-put ov 'mark-active ra)
    (dolist (cell rvars)
      (overlay-put ov (car cell) (cdr cell)))
    (helixel-mc--update-fake-region ov)
    (helixel-mc--paint-cursor-overlay ov rp)))

;;;###autoload
(defun helixel-mc-rotate-content-forward (&optional count)
  "Cyclically shift each cursor's selection text FORWARD by one cursor.
Every cursor (real included) must have an active non-degenerate
region.  Selection regions must be non-overlapping.  Prefix COUNT
repeats."
  (interactive "p")
  (helixel-mc--rotate-content (or count 1) 'forward))

;;;###autoload
(defun helixel-mc-rotate-content-backward (&optional count)
  "Cyclically shift each cursor's selection text BACKWARD by one cursor.
Inverse of `helixel-mc-rotate-content-forward'.  Prefix COUNT repeats."
  (interactive "p")
  (helixel-mc--rotate-content (or count 1) 'backward))

(defun helixel-mc--collect-all-cursors-sorted ()
  "Return all cursors (real as virtual entry) sorted by region begin.
Each entry is a plist:
  (:cursor OV-OR-NIL :beg MARKER :end MARKER :forward BOOL)
BEG/END are fresh markers (begin insertion-type nil, end
insertion-type t) so they bracket their region across
delete+insert.  :forward is t when point > mark for that cursor.
The real cursor has :cursor nil."
  (let ((all
         (cons
          (let* ((p (point)) (m (mark t))
                 (b (min p m)) (e (max p m)))
            (list :cursor nil
                  :beg (copy-marker b nil)
                  :end (copy-marker e t)
                  :forward (> p m)))
          (mapcar (lambda (ov)
                    (let* ((p (marker-position
                               (overlay-get ov 'helixel-mc-point)))
                           (m (marker-position
                               (overlay-get ov 'helixel-mc-mark)))
                           (b (min p m)) (e (max p m)))
                      (list :cursor ov
                            :beg (copy-marker b nil)
                            :end (copy-marker e t)
                            :forward (> p m))))
                  (helixel-mc-all-cursors)))))
    (sort all (lambda (a b)
                (< (marker-position (plist-get a :beg))
                   (marker-position (plist-get b :beg)))))))

(defun helixel-mc--rotate-content (count dir)
  "Shift content of every cursor's region by COUNT positions in DIR.
DIR is `forward' or `backward'.  All cursors must have active
regions.  Implementation: snapshot every region's text, then
replace each region with the text of its DIR-rotated neighbor.
Regions are processed RIGHT-to-LEFT to keep marker positions
stable across replacements.  Region activation (real and fake
`mark-active') is preserved across the rotation so the command
can be pressed repeatedly."
  (unless (helixel-mc-any-p)
    (user-error "No fake cursors"))
  (unless (use-region-p)
    (user-error "Real cursor must have a region"))
  (dolist (ov (helixel-mc-all-cursors))
    (unless (and (overlay-get ov 'mark-active)
                 (/= (marker-position (overlay-get ov 'helixel-mc-point))
                     (marker-position (overlay-get ov 'helixel-mc-mark))))
      (user-error "Every cursor must have a non-degenerate region")))
  (let ((deactivate-mark nil))
    (dotimes (_ count)
      (let* ((entries (helixel-mc--collect-all-cursors-sorted))
             (n (length entries))
             (texts (mapcar (lambda (e)
                              (buffer-substring-no-properties
                               (marker-position (plist-get e :beg))
                               (marker-position (plist-get e :end))))
                            entries))
             (new-texts (mapcar
                         (lambda (i)
                           (let ((src (if (eq dir 'forward)
                                          (mod (1- i) n)
                                        (mod (1+ i) n))))
                             (nth src texts)))
                         (number-sequence 0 (1- n))))
             (pairs (cl-mapcar #'cons entries new-texts)))
        ;; Replace right-to-left so earlier markers stay valid.
        (dolist (cell (reverse pairs))
          (let* ((entry (car cell))
                 (txt (cdr cell))
                 (b (marker-position (plist-get entry :beg)))
                 (e (marker-position (plist-get entry :end))))
            (save-excursion
              (goto-char b)
              (delete-region b e)
              (insert txt))))
        ;; Re-anchor each cursor onto its rotated region and
        ;; reaffirm mark-active.  BEG / END markers above were
        ;; created with the right insertion-types so they now
        ;; bracket the freshly inserted text.
        (dolist (entry entries)
          (let* ((ov (plist-get entry :cursor))
                 (b (marker-position (plist-get entry :beg)))
                 (e (marker-position (plist-get entry :end)))
                 (fwd (plist-get entry :forward)))
            (if ov
                (let ((pm (overlay-get ov 'helixel-mc-point))
                      (mm (overlay-get ov 'helixel-mc-mark)))
                  (if fwd
                      (progn (set-marker pm e) (set-marker mm b))
                    (set-marker pm b) (set-marker mm e))
                  (overlay-put ov 'mark-active t)
                  (helixel-mc--update-fake-region ov))
              ;; Real cursor.
              (if fwd
                  (progn (goto-char e) (set-marker (mark-marker) b))
                (goto-char b) (set-marker (mark-marker) e))
              (setq mark-active t))))
        ;; Free temp markers.
        (dolist (entry entries)
          (set-marker (plist-get entry :beg) nil)
          (set-marker (plist-get entry :end) nil))))))

;;;###autoload
(defun helixel-mc-merge ()
  "Merge real + every fake cursor into ONE big selection.
The merged region spans from the leftmost cursor edge to the
rightmost cursor edge.  All fakes are cleared."
  (interactive)
  (unless (helixel-mc-any-p)
    (user-error "No fake cursors"))
  (let* ((all-pos
          (cl-loop
           for ov in (helixel-mc-all-cursors)
           append (list (marker-position (overlay-get ov 'helixel-mc-point))
                        (marker-position (overlay-get ov 'helixel-mc-mark)))))
         (lo (apply #'min (point) (mark t) all-pos))
         (hi (apply #'max (point) (mark t) all-pos)))
    (helixel-mc-clear-all)
    (goto-char hi)
    (set-marker (mark-marker) lo)
    (setq mark-active t)))

;;;###autoload
(defun helixel-mc-trim ()
  "Trim leading and trailing whitespace from every cursor's region.
Each cursor's mark/point pair is shrunk to the inner non-whitespace
span.  No-op if a region is empty or all-whitespace."
  (interactive)
  (let ((process
         (lambda (beg end)
           "Return (TRIMMED-BEG . TRIMMED-END) for [beg, end)."
           (save-excursion
             (let* ((s (buffer-substring-no-properties beg end))
                    (lead (if (string-match "\\`[ \t\r\n]+" s)
                              (match-end 0) 0))
                    (trail (if (string-match "[ \t\r\n]+\\'" s)
                               (- (length s) (match-beginning 0)) 0)))
               (cons (+ beg lead) (- end trail)))))))
    ;; Real cursor
    (when (use-region-p)
      (let* ((trimmed (funcall process (region-beginning) (region-end)))
             (lo (car trimmed)) (hi (cdr trimmed)))
        (when (< lo hi)
          (let ((forward (> (point) (mark t))))
            (if forward (progn (goto-char hi) (set-marker (mark-marker) lo))
              (progn (goto-char lo) (set-marker (mark-marker) hi)))
            (setq mark-active t)))))
    ;; Fakes
    (dolist (ov (helixel-mc-all-cursors))
      (let* ((p (marker-position (overlay-get ov 'helixel-mc-point)))
             (m (marker-position (overlay-get ov 'helixel-mc-mark)))
             (a (overlay-get ov 'mark-active)))
        (when (and a (/= p m))
          (let* ((trimmed (funcall process (min p m) (max p m)))
                 (lo (car trimmed)) (hi (cdr trimmed)))
            (when (< lo hi)
              (let ((forward (> p m)))
                (if forward
                    (progn
                      (set-marker (overlay-get ov 'helixel-mc-point) hi)
                      (set-marker (overlay-get ov 'helixel-mc-mark) lo))
                  (set-marker (overlay-get ov 'helixel-mc-point) lo)
                  (set-marker (overlay-get ov 'helixel-mc-mark) hi)))
              (helixel-mc--update-fake-region ov))))))))

;;;###autoload
(defun helixel-mc-align ()
  "Insert spaces to align all cursor columns.
For each line that has multiple cursors, pads earlier ones with
spaces so every cursor sits at the rightmost cursor's column on
its group of lines.  Simpler than hel-mode's full multi-column
align, but covers the common case of column-aligning a vertical
column-of-cursors created via `s a' / `xs'."
  (interactive)
  (unless (helixel-mc-any-p)
    (user-error "No fake cursors"))
  (let* ((points
          (sort (cons (copy-marker (point) t)
                      (mapcar (lambda (ov)
                                (copy-marker
                                 (marker-position
                                  (overlay-get ov 'helixel-mc-point))
                                 t))
                              (helixel-mc-all-cursors)))
                (lambda (a b) (< (marker-position a)
                                 (marker-position b)))))
         ;; Compute max column across all points.
         (max-col
          (cl-loop for p in points
                   maximize (save-excursion
                              (goto-char (marker-position p))
                              (current-column)))))
    ;; Right-to-left so insertions don't shift earlier markers.
    (dolist (p (reverse points))
      (save-excursion
        (goto-char (marker-position p))
        (let ((need (- max-col (current-column))))
          (when (> need 0)
            (insert (make-string need ?\s))))))
    (dolist (p points) (set-marker p nil))))

;; ── Split selection on regex / into lines ──

(defun helixel-mc--regions-of-all-cursors ()
  "Return list of (CURSOR-OR-NIL BEG END FORWARD) for all cursors.
Real cursor's CURSOR is nil.  Only non-degenerate, active
regions are included.  Result is sorted by BEG."
  (let (acc)
    (when (use-region-p)
      (push (list nil (region-beginning) (region-end)
                  (> (point) (mark t)))
            acc))
    (dolist (ov (helixel-mc-all-cursors))
      (let ((p (marker-position (overlay-get ov 'helixel-mc-point)))
            (m (marker-position (overlay-get ov 'helixel-mc-mark)))
            (a (overlay-get ov 'mark-active)))
        (when (and a (/= p m))
          (push (list ov (min p m) (max p m) (> p m)) acc))))
    (sort acc (lambda (a b) (< (nth 1 a) (nth 1 b))))))

(defun helixel-mc--install-regions (region-specs)
  "Replace all cursors with regions described by REGION-SPECS.
REGION-SPECS is a list of (BEG END FORWARD) triples.  The FIRST
spec is installed on the real cursor; the rest become fakes.
All existing fakes are cleared first.  If REGION-SPECS is empty
the mc session is fully disabled."
  (helixel-mc-clear-all)
  (cond
   ((null region-specs)
    nil)
   (t
    (let* ((first (car region-specs))
           (b (nth 0 first)) (e (nth 1 first)) (fwd (nth 2 first)))
      (if fwd (progn (goto-char e) (set-marker (mark-marker) b))
        (goto-char b) (set-marker (mark-marker) e))
      (setq mark-active t))
    (dolist (spec (cdr region-specs))
      (let* ((b (nth 0 spec)) (e (nth 1 spec)) (fwd (nth 2 spec))
             (p (if fwd e b)) (m (if fwd b e))
             (ov (helixel-mc-create-fake-cursor p m)))
        (when ov
          (overlay-put ov 'mark-active t)
          (helixel-mc--update-fake-region ov)))))))

;;;###autoload
(defun helixel-mc-split-on-regex (regex)
  "Split every cursor's selection on REGEX into multiple cursors.
For each existing selection, replaces it with one cursor per
REGEX match found inside it.  Selections with no match are
removed.  If the resulting set is empty the mc session is
disabled."
  (interactive (list (read-regexp "Split on regex: ")))
  (let* ((entries (helixel-mc--regions-of-all-cursors))
         (new-specs
          (cl-loop
           for entry in entries
           for b = (nth 1 entry)
           for e = (nth 2 entry)
           for fwd = (nth 3 entry)
           append
           (save-excursion
             (goto-char b)
             (let (matches)
               (while (re-search-forward regex e t)
                 (when (> (match-end 0) (match-beginning 0))
                   (push (list (match-beginning 0)
                               (match-end 0)
                               fwd)
                         matches)))
               (nreverse matches))))))
    (helixel-mc--push-history)
    (helixel-mc--install-regions new-specs)
    (message "helixel-mc: split into %d cursor%s"
             (length new-specs)
             (if (= 1 (length new-specs)) "" "s"))))

;;;###autoload

;; ── Restore cursor layout history (g v) ──

(defvar helixel-mc--history nil
  "List of past cursor-layout snapshots.
Most-recent first.  Each entry is a list of (P M ACTIVE) triples
\(first entry is the real cursor at snapshot time).")

(defcustom helixel-mc-history-max 16
  "Maximum number of cursor-layout snapshots remembered for `g v'."
  :type 'integer
  :group 'helixel-mc)

(defun helixel-mc--snapshot-layout ()
  "Return current layout as a list of (P M ACTIVE) triples.
First entry is the real cursor.  Returns nil when there are no
fake cursors AND no real region (nothing worth remembering)."
  (let ((entries
         (cons (list (point) (mark t) (and mark-active t))
               (mapcar
                (lambda (ov)
                  (list (marker-position
                         (overlay-get ov 'helixel-mc-point))
                        (marker-position
                         (overlay-get ov 'helixel-mc-mark))
                        (and (overlay-get ov 'mark-active) t)))
                (helixel-mc-all-cursors)))))
    (when (or (cdr entries)
              (cadar entries)) ; real has mark
      entries)))

(defun helixel-mc--push-history ()
  "Snapshot current layout (if any) and push onto history.
No-op unless the snapshot contains at least one FAKE cursor
\(real-only layouts aren't worth restoring).  Dedupes against
most recent entry.  Caps at `helixel-mc-history-max'.  Callers
that want to suppress recording locally can rebind
`helixel-mc-before-clear-hook' to nil around their work."
  (let ((snap (helixel-mc--snapshot-layout)))
    (when (and snap
               (cdr snap)             ; require >= 1 fake
               (not (equal snap (car helixel-mc--history))))
      (push snap helixel-mc--history)
      (when (> (length helixel-mc--history) helixel-mc-history-max)
        (setq helixel-mc--history
              (cl-subseq helixel-mc--history
                         0 helixel-mc-history-max))))))

;;;###autoload
(defun helixel-mc-restore-cursors ()
  "Restore the most recent cursor layout snapshot.
Useful after `,' / `s ,' / `s SPC' (clear-all): press `g v' to
bring back the prior set of fakes.  Repeated `g v' walks deeper
into history."
  (interactive)
  (let ((snap (pop helixel-mc--history)))
    (unless snap
      (user-error "No previous multi-cursor layout to restore"))
    (let ((helixel-mc-before-clear-hook nil))
      ;; Snapshot CURRENT layout first so user can re-redo by
      ;; pushing it back.  We push it onto the END so successive
      ;; `g v' calls walk back through history, not bounce.
      (let ((cur (helixel-mc--snapshot-layout)))
        (when cur
          (setq helixel-mc--history
                (append helixel-mc--history (list cur)))
          (when (> (length helixel-mc--history) helixel-mc-history-max)
            (setq helixel-mc--history
                  (cl-subseq helixel-mc--history
                             0 helixel-mc-history-max)))))
      (helixel-mc-clear-all)
      (let* ((real (car snap))
             (rp (nth 0 real)) (rm (nth 1 real)) (ra (nth 2 real)))
        (goto-char rp)
        (set-marker (mark-marker) (or rm rp))
        (setq mark-active (and ra (numberp rm) (/= rp rm))))
      (dolist (entry (cdr snap))
        (let* ((p (nth 0 entry)) (m (nth 1 entry)) (a (nth 2 entry))
               (ov (helixel-mc-create-fake-cursor p (or m p))))
          (when ov
            (overlay-put ov 'mark-active (and a (numberp m) (/= p m)))
            (helixel-mc--update-fake-region ov)))))))

;; Auto-snapshot before `clear-all' destroys cursors.  Done via
;; `helixel-mc-before-clear-hook' (cleaner than advice).  The
;; recursive call from `(helixel-multi-cursor-mode -1)' inside
;; `clear-all' is harmless: `--push-history' requires at least
;; one fake cursor in the snapshot, and by that point the fakes
;; have already been deleted.
(add-hook 'helixel-mc-before-clear-hook #'helixel-mc--push-history)

(provide 'helixel-mc-spawn)
;;; helixel-mc-spawn.el ends here
