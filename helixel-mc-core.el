;;; helixel-mc-core.el --- Multi-cursor core for helixel-mode -*- lexical-binding: t; -*-

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

;; Real fake-cursor multi-cursor implementation, inspired by
;; `multiple-cursors.el' (hel-multiple-cursors-core) and
;; `meow-beacons.el'.  Each fake cursor has real state — point,
;; mark, mark-active, and helixel-specific data (pending-sel,
;; last-event, active-search) — and dispatches commands at every
;; cursor via `post-command-hook'.
;;
;; Public API:
;;   helixel-multi-cursor-mode      buffer-local minor mode (auto)
;;   helixel-mc-create-fake-cursor  create one fake cursor
;;   helixel-mc-clear-all           remove all fake cursors
;;   helixel-mc-all-cursors         list of overlays
;;   helixel-mc-num-cursors         number of cursors (real + fake)
;;   helixel-mc-with-each-cursor    macro: run body at every cursor
;;
;; Whitelist:
;;   (put 'CMD 'multiple-cursors t)    run for all cursors
;;   (put 'CMD 'multiple-cursors nil)  run only at real cursor
;;   absent                            consult `helixel-mc-default-policy'

;;; Code:

(require 'cl-lib)
(require 'helixel-core)
(require 'helixel-replay)

(defvar helixel-multi-cursor-mode)        ; forward decl — defined below
(defvar helixel--current-state)           ; from `helixel-state'
(declare-function helixel-enter-normal-state "helixel-state" (&rest _))

;; ── Faces ──

(defface helixel-mc-fake-cursor
  '((((class color) (background dark))
     :background "#ffb74d" :foreground "#1c1c1c"
     :box (:line-width -1 :color "#ff8f00"))
    (((class color) (background light))
     :background "#ff8f00" :foreground "white"
     :box (:line-width -1 :color "#e65100"))
    (t :inverse-video t))
  "Face for fake cursors at end-of-line / single-char positions.
Defaults to a high-contrast amber block so fake cursors are
immediately distinguishable from the real cursor."
  :group 'helixel)

(defface helixel-mc-fake-cursor-bar
  '((((class color) (background dark)) :background "#ffb74d")
    (((class color) (background light)) :background "#ff8f00")
    (t :inherit cursor))
  "Face for fake-cursor bar overlay (eol)."
  :group 'helixel)

(defface helixel-mc-fake-region
  '((((class color) (background dark))
     :background "#5d4037" :extend t)
    (((class color) (background light))
     :background "#ffe0b2" :extend t)
    (t :inherit region))
  "Face for fake-cursor active regions.
Distinct hue from the standard `region' face so the real
cursor's selection stands out among fake selections."
  :group 'helixel)

;; ── Customization ──

(defcustom helixel-mc-default-policy 'all
  "What to do when a command has no `multiple-cursors' symbol property.
\=`all'    — run at every cursor (default — recommended for modal use)
\=`once'   — run at real cursor only
\=`prompt' — ask once, store decision via `put'."
  :type '(choice (const all) (const once) (const prompt))
  :group 'helixel)

(defcustom helixel-mc-mode-line-indicator " mc:%d"
  "Mode-line format string for `helixel-multi-cursor-mode'.
%d is replaced by the total cursor count (real + fake)."
  :type 'string
  :group 'helixel)

(defcustom helixel-mc-max-cursors 200
  "Maximum number of fake cursors before refusing to create more.
Nil disables the check."
  :type '(choice (const :tag "Unlimited" nil) integer)
  :group 'helixel)

;; ── Per-cursor state vars ──
;;
;; When dispatching a command for a fake cursor, these variables are
;; restored from / saved to the overlay properties so each cursor has
;; an independent view of state.

(defvar helixel-mc-cursor-vars nil
  "List of variables persisted per fake cursor.
Restored before dispatching a command at a cursor and saved
back into the overlay afterwards.  Populated via
`helixel-mc-register-cursor-var' — do not push directly.

NOTE: `mark-active' is intentionally NOT registered — it is
stored as the overlay's `mark-active' property and managed
separately by `helixel-mc--enter-cursor' / `…--leave-cursor'.")

(defun helixel-mc-register-cursor-var (var &optional _doc)
  "Register VAR as per-fake-cursor state.  Optional _DOC is unused.
When a fake cursor's command is dispatched, VAR is restored from
the overlay before the call and snapshotted back after.  Adds
VAR to `helixel-mc-cursor-vars' (idempotent).  Third-party code
can register their own state to ride along."
  (unless (memq var helixel-mc-cursor-vars)
    (push var helixel-mc-cursor-vars))
  var)

;; Built-in per-cursor state.  Each cursor needs its own kill ring
;; (so cross-cursor yank doesn't leak), its own pending selection
;; (for chain/repeat), its own last-event (for per-cursor `.'), and
;; its own active search (for substituted `;' — see
;; `helixel-mc--fake-substitute-alist').
(helixel-mc-register-cursor-var 'kill-ring
  "Per-cursor paste history.  Isolated so `y' at cursor A doesn't\
 leak into `p' at cursor B.")
(helixel-mc-register-cursor-var 'kill-ring-yank-pointer
  "Per-cursor yank pointer (paired with `kill-ring').")
(helixel-mc-register-cursor-var 'mark-ring
  "Per-cursor mark history.")
(helixel-mc-register-cursor-var 'helixel--pending-sel
  "Per-cursor pending selection descriptor (for chain / repeat).")
(helixel-mc-register-cursor-var 'helixel--last-action
  "Per-cursor last edit transaction (replayed by `.').")
(helixel-mc-register-cursor-var 'helixel--active-search
  "Per-cursor active search state (pattern + direction).")
(helixel-mc-register-cursor-var 'helixel--event-ring
  "Per-cursor event ring for `;' cycling.  Each fake builds its
own private history of motions/edits run AFTER spawn.  Capped
by `helixel-action-ring-max'.")
(helixel-mc-register-cursor-var 'helixel--live-action
  "Per-cursor in-progress `helixel-action' (committed at the
next `helixel--tracking-open').  Required so each fake's events
go into its OWN ring rather than the shared buffer-local one.")
(helixel-mc-register-cursor-var 'helixel--action-pos
  "Per-cursor `;' cycling position into the fake's own event ring.")

;; ── Cursors table (per buffer) ──

(defvar-local helixel-mc--cursors nil
  "List of fake-cursor overlays in the current buffer.
Each overlay has properties:
  `helixel-mc-cursor'    t (type tag)
  `helixel-mc-point'     point marker
  `helixel-mc-mark'      mark marker
  `helixel-mc-region'    fake-region overlay or nil
  plus per-cursor state under each symbol in
  `helixel-mc-cursor-vars'.")

(defsubst helixel-mc-fake-cursor-p (ov)
  "Return non-nil if OV is a fake-cursor overlay."
  (and (overlayp ov) (overlay-get ov 'helixel-mc-cursor)))

(defun helixel-mc-all-cursors (&optional sort)
  "Return the list of fake-cursor overlays.
Filters out dead overlays (detached from buffer) and zombie
overlays whose `helixel-mc-point' marker has been nulled — either
condition would crash `helixel-mc--enter-cursor's `goto-char'.
When SORT is non-nil, return them sorted by buffer position."
  (let ((cursors
         (cl-remove-if-not
          (lambda (ov)
            (and (overlay-buffer ov)
                 (let ((m (overlay-get ov 'helixel-mc-point)))
                   (and m (marker-position m)))))
          (copy-sequence helixel-mc--cursors))))
    (if sort
        (sort cursors
              (lambda (a b)
                (< (marker-position (overlay-get a 'helixel-mc-point))
                   (marker-position (overlay-get b 'helixel-mc-point)))))
      cursors)))

(defun helixel-mc-num-cursors ()
  "Return the number of cursors (real + fake) in the buffer."
  (1+ (length (helixel-mc-all-cursors))))

(defun helixel-mc-any-p ()
  "Return non-nil if any fake cursors exist in the current buffer."
  (cl-some #'overlay-buffer helixel-mc--cursors))

;; ── Overlay rendering ──

(defvar helixel-mc--eol-cursor-string nil
  "Cached propertized string for end-of-line fake-cursor overlays.
Lazily built on first use; rebuilt automatically when the
`helixel-mc-fake-cursor' face is customised at runtime.  Set to
nil to force a rebuild on the next paint.")

(defun helixel-mc--get-eol-cursor-string ()
  "Return the cached eol cursor string, building it if needed."
  (or helixel-mc--eol-cursor-string
      (setq helixel-mc--eol-cursor-string
            (propertize " " 'face 'helixel-mc-fake-cursor))))

(defun helixel-mc--paint-cursor-overlay (ov pos)
  "Paint fake-cursor overlay OV at buffer position POS.
At end-of-line uses an `after-string' (newline overlays expand
across the whole window); elsewhere covers the single char at POS."
  (save-excursion
    (goto-char pos)
    (cond
     ((or (eobp) (eolp))
      (move-overlay ov pos pos)
      (overlay-put ov 'after-string
                   (helixel-mc--get-eol-cursor-string))
      (overlay-put ov 'face nil))
     (t
      (move-overlay ov pos (1+ pos))
      (overlay-put ov 'after-string nil)
      (overlay-put ov 'face 'helixel-mc-fake-cursor)))))

(defun helixel-mc--update-fake-region (cursor)
  "Update the fake-region overlay associated with CURSOR."
  (let* ((pnt (marker-position (overlay-get cursor 'helixel-mc-point)))
         (mrk (marker-position (overlay-get cursor 'helixel-mc-mark)))
         (active (overlay-get cursor 'mark-active))
         (region-ov (overlay-get cursor 'helixel-mc-region)))
    (if (and active mrk (/= pnt mrk))
        (let ((b (min pnt mrk)) (e (max pnt mrk)))
          (if region-ov
              (move-overlay region-ov b e)
            (setq region-ov (make-overlay b e nil nil t))
            (overlay-put region-ov 'face 'helixel-mc-fake-region)
            (overlay-put region-ov 'priority 50)
            (overlay-put region-ov 'helixel-mc-region t)
            (overlay-put cursor 'helixel-mc-region region-ov)))
      (when region-ov
        (delete-overlay region-ov)
        (overlay-put cursor 'helixel-mc-region nil)))))

;; ── Create / delete ──

(defun helixel-mc--snapshot-vars (ov)
  "Snapshot variables listed in `helixel-mc-cursor-vars' into OV."
  (dolist (v helixel-mc-cursor-vars)
    (when (boundp v)
      (overlay-put ov v (symbol-value v)))))

(defun helixel-mc--restore-vars (ov)
  "Restore variables listed in `helixel-mc-cursor-vars' from OV."
  (dolist (v helixel-mc-cursor-vars)
    (when (boundp v)
      (set v (overlay-get ov v)))))

(defun helixel-mc--cursor-key (ov-or-real)
  "Return a (POINT . EFFECTIVE-MARK) tuple identifying a cursor.
OV-OR-REAL is either a fake-cursor overlay or the keyword `:real'
\(meaning the real point/mark).  EFFECTIVE-MARK equals POINT when
the cursor has no active region, so cursors with the same point
but different inactive marks dedupe to the same key."
  (if (eq ov-or-real :real)
      (cons (point)
            (if (and mark-active (mark t)) (mark t) (point)))
    (let ((p (marker-position (overlay-get ov-or-real 'helixel-mc-point)))
          (m (marker-position (overlay-get ov-or-real 'helixel-mc-mark)))
          (a (overlay-get ov-or-real 'mark-active)))
      (cons p (if (and a m) m p)))))

(defun helixel-mc--cursor-region (ov-or-real)
  "Return (BEG . END) of OV-OR-REAL's active selection, or nil.
OV-OR-REAL is either a fake-cursor overlay or the keyword `:real'.
Returns nil when the cursor has no active region (point-only)."
  (if (eq ov-or-real :real)
      (and mark-active (mark t)
           (cons (min (point) (mark t))
                 (max (point) (mark t))))
    (let ((p (marker-position (overlay-get ov-or-real 'helixel-mc-point)))
          (m (marker-position (overlay-get ov-or-real 'helixel-mc-mark)))
          (a (overlay-get ov-or-real 'mark-active)))
      (and a m (/= p m) (cons (min p m) (max p m))))))

(defun helixel-mc-dedupe-cursors ()
  "Merge duplicate fake cursors, drop overlapping selections.
Two passes follow Helix's selection-set semantics:

  1. Drop fakes whose (point, effective-mark) tuple matches the
     real cursor or an earlier fake (see `helixel-mc--cursor-key').

  2. Drop fakes whose ACTIVE REGION overlaps an earlier kept
     selection (real or fake) when both walk in buffer order.
     This is Helix's \"merge overlapping selections\" rule:
     overlap collapses to the leftmost cursor.

Return the total number of fake cursors removed."
  (let ((removed 0))
    ;; ---- Pass 1: identical (point, mark) ----
    (let ((real-key (helixel-mc--cursor-key :real))
          (seen nil))
      (dolist (ov (helixel-mc-all-cursors :sort))
        (let ((k (helixel-mc--cursor-key ov)))
          (cond
           ((equal k real-key)
            (helixel-mc-delete-fake-cursor ov)
            (cl-incf removed))
           ((member k seen)
            (helixel-mc-delete-fake-cursor ov)
            (cl-incf removed))
           (t (push k seen))))))
    ;; ---- Pass 2: overlapping selections ----
    ;; Fast path: if no fake has an active region, skip the sort.
    ;; For point-spawn workflows (line / column / regex matches)
    ;; this elides O(N log N) work on every post-command tick.
    (when (or (and mark-active (mark t))
              (cl-some (lambda (ov) (overlay-get ov 'mark-active))
                       (helixel-mc-all-cursors)))
      (let* ((real-r (helixel-mc--cursor-region :real))
             (entries
              (sort
               (delq nil
                     (cons
                      (and real-r (list (car real-r) (cdr real-r) :real))
                      (mapcar (lambda (ov)
                                (when-let* ((r (helixel-mc--cursor-region ov)))
                                  (list (car r) (cdr r) ov)))
                              (helixel-mc-all-cursors))))
               (lambda (a b) (< (car a) (car b)))))
             (last-end -1))
        (dolist (e entries)
          (let ((beg (nth 0 e)) (end (nth 1 e)) (who (nth 2 e)))
            (cond
             ((eq who :real)
              (setq last-end (max last-end end)))
             ((< beg last-end)
              (helixel-mc-delete-fake-cursor who)
              (cl-incf removed))
             (t (setq last-end (max last-end end))))))))
    removed))

(defun helixel-mc-create-fake-cursor (point &optional mark)
  "Create a fake cursor at POINT, with optional active region to MARK.
Returns the new overlay, or nil if a fake at the same (point, mark)
already exists.  Signals `user-error' if `helixel-mc-max-cursors'
would be exceeded.
Snapshots variables listed in `helixel-mc-cursor-vars' into the
overlay (so each cursor has its own `kill-ring' etc.).
Auto-enables `helixel-multi-cursor-mode'."
  (when (and helixel-mc-max-cursors
             (>= (length helixel-mc--cursors) helixel-mc-max-cursors))
    (user-error "Refusing to create more than %d fake cursors"
                helixel-mc-max-cursors))
  ;; Dedup against existing fakes only.  We do NOT skip when this
  ;; position happens to match the real cursor, because legitimate
  ;; flows (e.g. `s a' / `helixel-mc-add-cursor-here') snapshot the
  ;; real cursor INTO a fake at the same spot, then move real to
  ;; the next line.  Post-command `helixel-mc-dedupe-cursors' will
  ;; collapse any real-vs-fake overlap that still exists after
  ;; the next command finishes.
  (let* ((eff-mark (or mark point))
         (new-key (cons point (if (and mark (/= mark point))
                                  eff-mark point)))
         (existing (cl-find new-key (helixel-mc-all-cursors)
                            :key #'helixel-mc--cursor-key
                            :test #'equal)))
    (cond
     (existing nil)                    ; duplicate fake → skip
     (t
      (let ((ov (make-overlay point point nil nil t)))
        (overlay-put ov 'helixel-mc-cursor t)
        (overlay-put ov 'priority 100)
        (overlay-put ov 'helixel-mc-point (copy-marker point t))
        (overlay-put ov 'helixel-mc-mark
                     (copy-marker eff-mark t))
        (overlay-put ov 'mark-active (and mark (/= mark point)))
        (helixel-mc--snapshot-vars ov)
        (helixel-mc--paint-cursor-overlay ov point)
        (helixel-mc--update-fake-region ov)
        ;; Exit `visual' state on first cursor creation.  Visual's
        ;; "extend" semantics are incompatible with multi-cursor
        ;; "each cursor has its own fresh selection" semantics.
        ;; Do this BEFORE pushing to helixel-mc--cursors so the
        ;; state-change hook (helixel-mc--sync-visual-state) won't
        ;; clear the new cursor's mark-active.
        (when (eq helixel--current-state 'visual)
          (helixel-enter-normal-state))
        (push ov helixel-mc--cursors)
        (unless helixel-multi-cursor-mode
          (helixel-multi-cursor-mode 1))
        ov)))))

(defun helixel-mc-delete-fake-cursor (cursor)
  "Delete fake CURSOR overlay and its associated region overlay."
  (when (helixel-mc-fake-cursor-p cursor)
    (when-let* ((m (overlay-get cursor 'helixel-mc-point)))
      (set-marker m nil))
    (when-let* ((m (overlay-get cursor 'helixel-mc-mark)))
      (set-marker m nil))
    (when-let* ((r (overlay-get cursor 'helixel-mc-region)))
      (delete-overlay r))
    (delete-overlay cursor)
    (setq helixel-mc--cursors (delq cursor helixel-mc--cursors))))

(defvar helixel-mc-before-clear-hook nil
  "Hook run BEFORE `helixel-mc-clear-all' destroys cursors.
Receives no arguments.  Use this for layout snapshotting,
undo recording, etc.")

(defun helixel-mc-clear-all ()
  "Remove every fake cursor in the current buffer.
Runs `helixel-mc-before-clear-hook' first."
  (interactive)
  (run-hooks 'helixel-mc-before-clear-hook)
  (dolist (ov (copy-sequence helixel-mc--cursors))
    (helixel-mc-delete-fake-cursor ov))
  (setq helixel-mc--cursors nil)
  (when helixel-multi-cursor-mode
    (helixel-multi-cursor-mode -1)))

;; ── Whitelist ──

(defun helixel-mc--should-run-for-all-p (command)
  "Return non-nil if COMMAND should run for every fake cursor.
Consults the `multiple-cursors' symbol property; falls back to
`helixel-mc-default-policy'."
  (cond
   ((not (symbolp command)) t)        ; lambdas — assume safe
   ((get command 'multiple-cursors-disabled) nil)
   (t
    (let ((prop (plist-member (symbol-plist command) 'multiple-cursors)))
      (if prop
          (cadr prop)
        (pcase helixel-mc-default-policy
          ('all t)
          ('once nil)
          ('prompt (helixel-mc--prompt-for command))
          (_ t)))))))

(defun helixel-mc--prompt-for (command)
  "Prompt once whether COMMAND should run for all cursors, remember choice."
  (let ((decision (ignore-error quit
                    (y-or-n-p (format "Run %S at every fake cursor? "
                                      command)))))
    (put command 'multiple-cursors decision)
    decision))

;;;###autoload
(defun helixel-mc-mark-all-for-multi-cursors (commands)
  "Mark each symbol in COMMANDS to run at every fake cursor."
  (dolist (c commands)
    (put c 'multiple-cursors t)))

;;;###autoload
(defun helixel-mc-mark-all-for-real-cursor-only (commands)
  "Mark each symbol in COMMANDS to run only at the real cursor."
  (dolist (c commands)
    (put c 'multiple-cursors nil)))

(cl-defmacro helixel-mc-defcmd (cmd &key (policy 'all) substitute prepos)
  "Declarative dispatch spec for CMD.
Keyword options:
  POLICY — `all' or `real' (default `all').  When `real', CMD
     runs only at the real cursor (sets `multiple-cursors'
     property to nil).  Any other value sets the property to t.
  SUBSTITUTE FN — when CMD runs at a fake cursor, dispatch FN
     instead.  Adds (CMD . FN) to
     `helixel-mc--fake-substitute-alist'.
     FN is also auto-marked with policy `all'.
  PREPOS FN — set CMD's `helixel-mc-prepos' symbol property to
     FN so insert-entry commands stage fakes before broadcast.

Replaces three separate calls (`put', `add-to-list', another
`put') at every dispatch site with one declarative form."
  (declare (indent 1))
  (let ((real-only (eq policy 'real)))
    `(progn
       (put ',cmd 'multiple-cursors ,(not real-only))
       ,@(when substitute
           `((add-to-list 'helixel-mc--fake-substitute-alist
                          (cons ',cmd ,substitute))
             (put ,substitute 'multiple-cursors t)))
       ,@(when prepos
           `((put ',cmd 'helixel-mc-prepos ,prepos)))
       ',cmd)))

;; ── Dispatch loop ──
;;
;; The legacy `helixel-mc-executing-command-for-fake-cursor' flag
;; was replaced by the `mc-fake' origin of the `helixel-replay'
;; context.  Check via `helixel-replay-in-fake-p'.

(defun helixel-mc--call-interactively (command)
  "Run COMMAND interactively (skipping `ignore').
Bound by the dispatch loop to recreate the simulated command loop
that fake-cursor execution needs."
  (unless (eq command 'ignore)
    (let ((this-command command))
      (call-interactively command))))

(defmacro helixel-mc--save-main-state (&rest body)
  "Save real point/mark/state, run BODY, then restore."
  (declare (indent 0) (debug t))
  (let ((real-pnt (gensym "pnt"))
        (real-mrk (gensym "mrk"))
        (vars     (gensym "vars")))
    `(let ((,real-pnt (copy-marker (point) t))
           (,real-mrk (copy-marker (mark-marker)))
           (,vars (mapcar (lambda (v)
                            (cons v (and (boundp v) (symbol-value v))))
                          helixel-mc-cursor-vars)))
       (save-excursion
         (unwind-protect
             (progn ,@body)
           (goto-char (marker-position ,real-pnt))
           (set-marker (mark-marker) (marker-position ,real-mrk))
           (set-marker ,real-pnt nil)
           (set-marker ,real-mrk nil)
           (dolist (cell ,vars)
             (when (boundp (car cell))
               (set (car cell) (cdr cell)))))))))

(defmacro helixel-mc-with-saved-state (&rest body)
  "Execute BODY, saving and restoring per-cursor state.
Saves all variables listed in `helixel-mc-cursor-vars' before
BODY, restores them after.  Does NOT restore point/mark — the
caller is responsible for cursor positioning.

Use this when walking the buffer to collect targets outside
of the standard with-each-cursor dispatch loop, so advance
functions don't clobber the real cursor's state."
  (declare (indent 0) (debug t))
  (let ((saved (gensym "saved")))
    `(let ((,saved (mapcar (lambda (v)
                             (cons v (and (boundp v) (symbol-value v))))
                           helixel-mc-cursor-vars)))
       (unwind-protect
           (progn ,@body)
         (dolist (cell ,saved)
           (when (boundp (car cell))
             (set (car cell) (cdr cell))))))))

(defmacro helixel-mc-with-each-cursor (&rest body)
  "Evaluate BODY once at each fake cursor.
Real cursor's state (point, mark, helixel vars) is preserved.
At each fake cursor BODY runs in an environment where point,
mark, and `helixel-mc-cursor-vars' have been restored from the
overlay.  After BODY, the overlay is updated to reflect the new
state."
  (declare (indent 0) (debug t))
  `(let ((inhibit-message t))            ; suppress per-fake echo spam
     (helixel-with-replay 'mc-fake
       (helixel-mc--save-main-state
         (dolist (cursor (helixel-mc-all-cursors :sort))
           (when (and (helixel-mc-fake-cursor-p cursor)
                      (helixel-mc--enter-cursor cursor))
             (unwind-protect (progn ,@body)
               (helixel-mc--leave-cursor cursor))))))))

(defun helixel-mc--enter-cursor (cursor)
  "Restore point/mark/state from CURSOR overlay into globals.
Does nothing (returns nil) if CURSOR has been detached or its
markers nulled — the caller can detect this via `eq' on the
overlay or by checking `helixel-mc-fake-cursor-p' afterwards."
  (let* ((pnt (overlay-get cursor 'helixel-mc-point))
         (mrk (overlay-get cursor 'helixel-mc-mark))
         (active (overlay-get cursor 'mark-active))
         (pnt-pos (and pnt (marker-position pnt)))
         (mrk-pos (and mrk (marker-position mrk))))
    (when (and pnt-pos mrk-pos (overlay-buffer cursor))
      (goto-char pnt-pos)
      (set-marker (mark-marker) mrk-pos)
      (setq mark-active active)
      (helixel-mc--restore-vars cursor)
      t)))

(defun helixel-mc--leave-cursor (cursor)
  "Snapshot current globals back into CURSOR overlay and repaint.
After the fake's body ran, the per-cursor variables registered
in `helixel-mc-cursor-vars' (including `helixel--live-action' and
`helixel--event-ring') hold this fake's state — snapshot them
back into the overlay.  Also re-snap the fake's point/mark and
repaint its visual overlay."
  (set-marker (overlay-get cursor 'helixel-mc-point) (point))
  (set-marker (overlay-get cursor 'helixel-mc-mark) (mark t))
  (overlay-put cursor 'mark-active mark-active)
  (helixel-mc--snapshot-vars cursor)
  (helixel-mc--paint-cursor-overlay
   cursor (marker-position (overlay-get cursor 'helixel-mc-point)))
  (helixel-mc--update-fake-region cursor))

(defun helixel-mc-execute-for-all-cursors (command)
  "Call COMMAND interactively for real cursor, then for every fake one.
This is the entry point intended for `post-command-hook' or for
external code that wants to manually trigger a batch operation
without going through the command loop."
  (helixel-mc--call-interactively command)
  (when (helixel-mc-any-p)
    (helixel-mc-with-each-cursor
      (helixel-mc--call-interactively command))))

;; ── Edit-replay dispatch ──
;;
;; If `this-command' produced a new `helixel-action' (stamped via the
;; edit's `by-command' slot at record time), dispatch at fakes by
;; replaying that edit's runner.  Runners already read their
;; decisions from the edit payload (char, register, delimiter,
;; pattern, ...), so fakes never re-prompt.  This eliminates the
;; need for per-command `advice-add' or substitute-alist hacks for
;; prompt commands like `helixel-replace-char', `helixel-surround-*'.

(defun helixel-mc--fresh-action-from-real ()
  "Return the helixel-action committed by `this-command' at real, or nil.
The check uses the edit's `by-command' stamp set at record time —
NO `pre-command-hook' snapshot needed (so this works correctly even
when tests bypass the command loop).

Returns nil when:
  - `helixel--last-action' is unset,
  - the edit was committed by a DIFFERENT command (leftover),
  - the edit carries no `op' (movement / search commit — not a real edit),
  - `this-command' has a `helixel-mc-prepos' property (those manage
    their own per-fake staging and should NOT replay the edit body)."
  (when (and (boundp 'helixel--last-action)
             (symbolp this-command)
             (not (get this-command 'helixel-mc-prepos)))
    (let ((cur helixel--last-action))
      (when (and cur
                 (helixel-action-op cur)
                 (eq (helixel-action-by-command cur) this-command))
        cur))))

;; ── post-command-hook integration ──
;;
;; The former `helixel-mc--inhibit' and
;; `helixel-mc-executing-command-for-fake-cursor' flags are gone:
;; their function is now expressed by the `mc-batch' / `mc-fake'
;; origin of the unified `helixel-replay' context.
;; `helixel-mc-dispatch-in-progress-p' covers both.

;; ── Fake-cursor command substitution (populated by mc-integrate) ──

(defvar helixel-mc--fake-substitute-alist nil
  "Alist of (REAL-CMD . FAKE-CMD) for fake-cursor dispatch.
When dispatching at fake cursors, REAL-CMD is replaced by FAKE-CMD
so the input prompt is not re-issued.  REAL-CMD must have already
run at the real cursor (so any shared state — e.g.
`helixel--active-search' — is populated).

Default value is nil; populated by `helixel-mc-integrate'
at load time.")

(defun helixel-mc--maybe-preposition ()
  "Run `this-command's prepositioner at each fake, if registered.
When `this-command' has a `helixel-mc-prepos' symbol property,
invoke that function once at every fake cursor.  Called from
the dispatcher so insert-entry commands stage fake cursors
before the next `self-insert-command' broadcast."
  (when (and helixel-multi-cursor-mode
             (not (helixel-mc-dispatch-in-progress-p))
             (helixel-mc-any-p)
             (symbolp this-command))
    (when-let* ((fn (get this-command 'helixel-mc-prepos)))
      (helixel-with-replay 'mc-batch
        (helixel-mc-with-each-cursor
          (condition-case err
              (funcall fn)
            (error
             (message "helixel-mc: prepos %s failed: %s"
                      this-command
                      (error-message-string err)))))))))

(defun helixel-mc--post-command ()
  "Post-command hook — dispatch `this-command' at every fake cursor.
Single-undo-step amalgamation.  Dispatch strategy:

  - If the real cursor committed a fresh `helixel-action' this command
    (detected via `helixel-action-by-command' stamp —
    see `helixel-mc--fresh-action-from-real'), replay that edit's
    runner at each fake.  Runner payload carries decisions so no
    prompt fires at fakes.
  - Otherwise, re-invoke `this-command' at each fake via the
    substitute-alist (if any), falling back to `call-interactively'
    for pure movements.

No-op when the mode is off, dispatch is already in progress,
we're in a keyboard-macro, or `this-command' is whitelisted off."
  (helixel-mc--maybe-preposition)
  (when (and helixel-multi-cursor-mode
             (not (helixel-mc-dispatch-in-progress-p))
             (not executing-kbd-macro)
             (not defining-kbd-macro)
             this-command
             (helixel-mc-any-p)
             (helixel-mc--should-run-for-all-p this-command))
    (helixel-with-replay 'mc-batch
     (let* ((fresh-edit (helixel-mc--fresh-action-from-real))
            (real-cmd this-command)
            (substituted (and (not fresh-edit)
                              (cdr (assq real-cmd
                                    helixel-mc--fake-substitute-alist))))
            (cmd (or substituted real-cmd)))
      (when (and substituted (not fresh-edit))
        ;; Substitute path: propagate freshly-set shared search state
        ;; so the substitute command sees the real cursor's match.
        (let ((shared (and (boundp 'helixel--active-search)
                           (symbol-value 'helixel--active-search))))
          (dolist (ov (helixel-mc-all-cursors))
            (when (helixel-mc-fake-cursor-p ov)
              (overlay-put ov 'helixel--active-search shared)))))
      (condition-case err
          (undo-amalgamate-change-group
            (let ((dead nil))
              (helixel-mc-with-each-cursor
                (condition-case e
                    (if fresh-edit
                        ;; Replay the just-committed edit at each
                        ;; fake via its runner.  Payload carries
                        ;; the prompted decisions so nothing prompts.
                        (helixel-with-replay-as 'dot
                          (helixel--execute-action fresh-edit))
                      ;; Pure movement / non-edit: re-call command.
                      (helixel-mc--call-interactively cmd))
                  (search-failed (push cursor dead))
                  (error (message "helixel-mc: %s at fake: %s"
                                  cmd (error-message-string e))
                         (push cursor dead))))
              (dolist (ov dead)
                (helixel-mc-delete-fake-cursor ov))))
        (error
         (message "helixel-mc: %s outer error: %s"
                  cmd (error-message-string err))))
      (helixel-mc-dedupe-cursors)))))

;; ── Minor mode ──

(defvar helixel-multi-cursor-mode-map (make-sparse-keymap)
  "Keymap active while `helixel-multi-cursor-mode' is on.
Populated by `helixel-keymap'.")

;;;###autoload
(define-minor-mode helixel-multi-cursor-mode
  "Helixel multi-cursor minor mode.
Activated automatically when at least one fake cursor exists,
deactivated when the last one is removed."
  :init-value nil
  :lighter (:eval (format helixel-mc-mode-line-indicator
                          (helixel-mc-num-cursors)))
  :keymap helixel-multi-cursor-mode-map
  (if helixel-multi-cursor-mode
      (add-hook 'post-command-hook #'helixel-mc--post-command 90 t)
    (remove-hook 'post-command-hook #'helixel-mc--post-command t)
    (helixel-mc-clear-all)))

;; ── Convenience: default whitelist for safe Emacs primitives ──

(helixel-mc-mark-all-for-multi-cursors
 '(self-insert-command
   newline newline-and-indent
   delete-backward-char delete-forward-char delete-char
   backward-delete-char-untabify
   kill-line kill-word backward-kill-word
   kill-region kill-ring-save yank yank-pop
   forward-char backward-char next-line previous-line
   forward-word backward-word
   move-beginning-of-line move-end-of-line
   beginning-of-line end-of-line
   back-to-indentation
   upcase-word downcase-word capitalize-word
   indent-for-tab-command
   transpose-chars transpose-words
   exchange-point-and-mark
   set-mark-command
   just-one-space delete-blank-lines
   comment-dwim
   open-line))

(helixel-mc-mark-all-for-real-cursor-only
 '(keyboard-quit
   save-buffer save-some-buffers
   find-file find-file-other-window
   other-window delete-other-windows delete-window
   split-window-below split-window-right
   switch-to-buffer kill-buffer
   undo undo-redo undo-only undo-tree-undo undo-tree-redo
   eval-expression eval-last-sexp eval-buffer eval-defun
   describe-function describe-variable describe-key describe-mode
   execute-extended-command
   minibuffer-complete-and-exit
   mouse-set-point mouse-drag-region
   scroll-up-command scroll-down-command
   ;; helixel-specific
   helixel-mc-toggle helixel-mc-clear-all
   helixel-mc-create-fake-cursor
   helixel-cursor-toggle helixel-cursor-hide
   helixel-repeat-chain-start helixel-repeat-chain-end
   helixel-repeat-chain-cancel
   helixel-repeat-edit helixel-repeat-selection
   helixel-repeat-edit-pick helixel-repeat-debug
   helixel-normal-escape
   helixel-enter-normal-state helixel-enter-insert-state
   helixel-enter-motion-state
   helixel-insert helixel-insert-after
   helixel-insert-beginning-line helixel-insert-after-end-line
   helixel-insert-newline helixel-insert-prevline
   helixel-insert-exit))

(provide 'helixel-mc-core)
;;; helixel-mc-core.el ends here
