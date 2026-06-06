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
(require 'helixel-ring)            ; helixel-action-commit

(defvar helixel-multi-cursor-mode)        ; forward decl — defined below
(defvar helixel--current-state)           ; from `helixel-state'
;; Per-cursor state variables that `helixel-cs-snapshot' /
;; `-restore' / `-update-from-globals' read and write.  Defined
;; in helixel-core / helixel-ring / helixel-state — declared here
;; so the byte compiler doesn't flag them when this file is built
;; before those modules are loaded.
(defvar helixel--pending-sel)             ; from `helixel-core'
(defvar helixel--last-tx)             ; from `helixel-core'
(defvar helixel--active-search)           ; from `helixel-state'
(defvar helixel--event-ring)              ; from `helixel-ring'
(defvar helixel--live-action)             ; from `helixel-ring'
(defvar helixel--action-pos)              ; from `helixel-ring'
(declare-function helixel-enter-normal-state "helixel-state" (&rest _))
(declare-function helixel-mc--repeat-edit-apply-only "helixel-mc-integrate"
                  (raw-prefix))

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

;; ── Per-cursor state ──
;;
;; Each fake cursor owns a `helixel-cursor-state' struct that captures
;; the full set of variables the dispatcher snapshots/restores around
;; the per-fake body.  The struct lives on the overlay under one
;; property (`helixel-cs') — replacing what used to be 11 separate
;; `overlay-put' calls per snapshot.
;;
;; Real cursor uses the SAME struct via `helixel-cs-snapshot' /
;; `-restore' in `helixel-mc--save-main-state'.  One type, one place.

(cl-defstruct (helixel-cursor-state
               (:conc-name helixel-cs-)
               (:copier nil))
  "Snapshot of one cursor's state — used for both real and fake cursors.
The mc dispatcher restores this struct into globals at fake-cursor
enter time and snapshots back at leave time.  Real cursor uses the
same struct in `helixel-mc--save-main-state'.

Position slots (POINT, MARK) are markers — the same markers live
for the cursor's lifetime; `set-marker' mutates them in place so
rendering code that holds the overlay's marker stays valid.
MARK-ACTIVE is the cursor's region-active flag (per-cursor copy of
the global `mark-active').

The remaining slots mirror buffer-local Emacs and helixel state so
each cursor has an independent kill-ring, search, event-ring and
so on — broadcasts at one cursor never leak into another."
  point                  ; marker
  mark                   ; marker
  mark-active            ; boolean
  kill-ring              ; list
  kill-ring-yank-pointer ; sublist of kill-ring
  mark-ring              ; list of markers
  pending-sel            ; `helixel-sel' or nil  (helixel--pending-sel)
  last-action            ; `helixel-action'      (helixel--last-tx)
  active-search          ; `helixel-active-search' (helixel--active-search)
  event-ring             ; list of `helixel-action' (helixel--event-ring)
  live-action            ; `helixel-action'      (helixel--live-action)
  action-pos)            ; integer | nil         (helixel--action-pos)

(defun helixel-cs-snapshot ()
  "Capture the current cursor state into a fresh `helixel-cursor-state'.
Markers are FRESH copies (`copy-marker') so the snapshot is
independent of any later movement of point / mark."
  (make-helixel-cursor-state
   :point          (copy-marker (point) t)
   :mark           (copy-marker (mark-marker))
   :mark-active    mark-active
   :kill-ring                 kill-ring
   :kill-ring-yank-pointer    kill-ring-yank-pointer
   :mark-ring                 mark-ring
   :pending-sel               helixel--pending-sel
   :last-action               helixel--last-tx
   :active-search             helixel--active-search
   :event-ring                helixel--event-ring
   :live-action               helixel--live-action
   :action-pos                helixel--action-pos))

(defun helixel-cs-restore (cs)
  "Restore cursor state CS into the current globals.
Moves point and the `mark-marker' to CS's positions, sets
`mark-active', and copies every helixel per-cursor var."
  (goto-char (marker-position (helixel-cs-point cs)))
  (set-marker (mark-marker) (marker-position (helixel-cs-mark cs)))
  (setq mark-active            (helixel-cs-mark-active cs)
        kill-ring              (helixel-cs-kill-ring cs)
        kill-ring-yank-pointer (helixel-cs-kill-ring-yank-pointer cs)
        mark-ring              (helixel-cs-mark-ring cs)
        helixel--pending-sel   (helixel-cs-pending-sel cs)
        helixel--last-tx   (helixel-cs-last-action cs)
        helixel--active-search (helixel-cs-active-search cs)
        helixel--event-ring    (helixel-cs-event-ring cs)
        helixel--live-action   (helixel-cs-live-action cs)
        helixel--action-pos    (helixel-cs-action-pos cs)))

(defun helixel-cs-release (cs)
  "Null the markers held by CS.  Idempotent.
Called when the cursor a CS belongs to is destroyed, to release
any buffer text the markers might otherwise pin."
  (when cs
    (when-let* ((m (helixel-cs-point cs))) (set-marker m nil))
    (when-let* ((m (helixel-cs-mark cs))) (set-marker m nil))))

(defun helixel-cs-update-from-globals (cs)
  "Update CS in place with current cursor globals.
Mutates the existing point/mark markers (preserving identity for
any rendering code that holds them).  Sets the rest by `setf'."
  (set-marker (helixel-cs-point cs) (point))
  (set-marker (helixel-cs-mark cs) (mark t))
  (setf (helixel-cs-mark-active cs)            mark-active
        (helixel-cs-kill-ring cs)              kill-ring
        (helixel-cs-kill-ring-yank-pointer cs) kill-ring-yank-pointer
        (helixel-cs-mark-ring cs)              mark-ring
        (helixel-cs-pending-sel cs)            helixel--pending-sel
        (helixel-cs-last-action cs)            helixel--last-tx
        (helixel-cs-active-search cs)          helixel--active-search
        (helixel-cs-event-ring cs)             helixel--event-ring
        (helixel-cs-live-action cs)            helixel--live-action
        (helixel-cs-action-pos cs)             helixel--action-pos))

;; ── Cursor accessors (read state via the struct on the overlay) ──

(defsubst helixel-mc-cursor-state (cursor)
  "Return the `helixel-cursor-state' attached to CURSOR overlay."
  (overlay-get cursor 'helixel-cs))

(defsubst helixel-mc-cursor-point (cursor)
  "Return the point marker of fake CURSOR."
  (helixel-cs-point (overlay-get cursor 'helixel-cs)))

(defsubst helixel-mc-cursor-mark (cursor)
  "Return the mark marker of fake CURSOR."
  (helixel-cs-mark (overlay-get cursor 'helixel-cs)))

(defsubst helixel-mc-cursor-mark-active (cursor)
  "Return non-nil if fake CURSOR's mark is active."
  (helixel-cs-mark-active (overlay-get cursor 'helixel-cs)))

;; ── Cursors table (per buffer) ──

(defvar-local helixel-mc--cursors nil
  "List of fake-cursor overlays in the current buffer.
Each overlay has properties:
  `helixel-mc-cursor'    t (type tag)
  `helixel-cs'           `helixel-cursor-state' (per-cursor state)
  `helixel-mc-region'    fake-region overlay or nil")

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
                 (let ((cs (overlay-get ov 'helixel-cs)))
                   (and cs (helixel-cs-point cs)
                        (marker-position (helixel-cs-point cs))))))
          (copy-sequence helixel-mc--cursors))))
    (if sort
        (sort cursors
              (lambda (a b)
                (< (marker-position (helixel-cs-point
                                     (overlay-get a 'helixel-cs)))
                   (marker-position (helixel-cs-point
                                     (overlay-get b 'helixel-cs))))))
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
  (let* ((cs  (overlay-get cursor 'helixel-cs))
         (pnt (marker-position (helixel-cs-point cs)))
         (mrk (marker-position (helixel-cs-mark cs)))
         (active (helixel-cs-mark-active cs))
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

(defun helixel-mc--cursor-key (ov-or-real)
  "Return a (POINT . EFFECTIVE-MARK) tuple identifying a cursor.
OV-OR-REAL is either a fake-cursor overlay or the keyword `:real'
\(meaning the real point/mark).  EFFECTIVE-MARK equals POINT when
the cursor has no active region, so cursors with the same point
but different inactive marks dedupe to the same key."
  (if (eq ov-or-real :real)
      (cons (point)
            (if (and mark-active (mark t)) (mark t) (point)))
    (let* ((cs (overlay-get ov-or-real 'helixel-cs))
           (p (marker-position (helixel-cs-point cs)))
           (m (marker-position (helixel-cs-mark cs)))
           (a (helixel-cs-mark-active cs)))
      (cons p (if (and a m) m p)))))

(defun helixel-mc--cursor-region (ov-or-real)
  "Return (BEG . END) of OV-OR-REAL's active selection, or nil.
OV-OR-REAL is either a fake-cursor overlay or the keyword `:real'.
Returns nil when the cursor has no active region (point-only)."
  (if (eq ov-or-real :real)
      (and mark-active (mark t)
           (cons (min (point) (mark t))
                 (max (point) (mark t))))
    (let* ((cs (overlay-get ov-or-real 'helixel-cs))
           (p (marker-position (helixel-cs-point cs)))
           (m (marker-position (helixel-cs-mark cs)))
           (a (helixel-cs-mark-active cs)))
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
              (cl-some #'helixel-mc-cursor-mark-active
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
Snapshots the cursor state into a `helixel-cursor-state' struct
attached to the overlay (so each cursor has its own `kill-ring',
event-ring, etc.).  Auto-enables `helixel-multi-cursor-mode'."
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
      (let* ((ov (make-overlay point point nil nil t))
             ;; Snapshot the real cursor's current state into the
             ;; struct, then override the position fields to match
             ;; the requested POINT/MARK so the new fake reflects
             ;; the spawn site, not the real cursor's location.
             (cs (helixel-cs-snapshot)))
        (set-marker (helixel-cs-point cs) point)
        (set-marker (helixel-cs-mark cs) eff-mark)
        (setf (helixel-cs-mark-active cs) (and mark (/= mark point)))
        (overlay-put ov 'helixel-mc-cursor t)
        (overlay-put ov 'priority 100)
        (overlay-put ov 'helixel-cs cs)
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
  "Delete fake CURSOR overlay and its associated region overlay.
Releases the markers held by the cursor's `helixel-cursor-state'."
  (when (helixel-mc-fake-cursor-p cursor)
    (helixel-cs-release (overlay-get cursor 'helixel-cs))
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

(cl-defmacro helixel-mc-defcmd (cmd &key (policy 'all))
  "Declarative dispatch spec for CMD.
Keyword options:
  POLICY — `all' or `real' (default `all').  When `real', CMD
     runs only at the real cursor (sets `multiple-cursors'
     property to nil).  Any other value sets the property to t.

The legacy `:substitute' and `:prepos' arms (Phase 4.3 cleanup) are
gone — commands now produce a `helixel-tx' (or store a
`:pre-replay-fn' on it via `helixel-define-command's `:tx-runner'
clause) which the unified dispatcher replays at every fake cursor."
  (declare (indent 1))
  (let ((real-only (eq policy 'real)))
    `(progn
       (put ',cmd 'multiple-cursors ,(not real-only))
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
  "Save real cursor state into a `helixel-cursor-state', run BODY, restore.
Used by `helixel-mc-with-each-cursor' to keep the real cursor's
point/mark/helixel vars/kill-ring/event-ring untouched while each
fake cursor's body runs in turn."
  (declare (indent 0) (debug t))
  (let ((cs (gensym "cs")))
    `(let ((,cs (helixel-cs-snapshot)))
       (save-excursion
         (unwind-protect (progn ,@body)
           (helixel-cs-restore ,cs)
           (helixel-cs-release ,cs))))))

(defmacro helixel-mc-with-saved-state (&rest body)
  "Execute BODY, saving and restoring per-cursor state.
Snapshots the real cursor's state into a `helixel-cursor-state'
before BODY and restores it after — EXCEPT for point and mark,
which are left as BODY leaves them (the caller is responsible
for cursor positioning).

Use this when walking the buffer to collect targets outside
of the standard with-each-cursor dispatch loop, so advance
functions don't clobber the real cursor's per-cursor helixel
state (kill-ring, event-ring, last-action, …)."
  (declare (indent 0) (debug t))
  (let ((cs (gensym "cs")))
    `(let ((,cs (helixel-cs-snapshot)))
       (unwind-protect (progn ,@body)
         ;; Restore everything except point/mark — callers rely on
         ;; BODY moving point freely.
         (setq mark-active            (helixel-cs-mark-active ,cs)
               kill-ring              (helixel-cs-kill-ring ,cs)
               kill-ring-yank-pointer (helixel-cs-kill-ring-yank-pointer ,cs)
               mark-ring              (helixel-cs-mark-ring ,cs)
               helixel--pending-sel   (helixel-cs-pending-sel ,cs)
               helixel--last-tx   (helixel-cs-last-action ,cs)
               helixel--active-search (helixel-cs-active-search ,cs)
               helixel--event-ring    (helixel-cs-event-ring ,cs)
               helixel--live-action   (helixel-cs-live-action ,cs)
               helixel--action-pos    (helixel-cs-action-pos ,cs))
         (helixel-cs-release ,cs)))))

(defmacro helixel-mc-with-each-cursor (&rest body)
  "Evaluate BODY once at each fake cursor.
Real cursor's state (point, mark, helixel vars) is preserved.
At each fake cursor BODY runs in an environment where point,
mark, and the per-cursor state struct have been restored from the
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
state is missing — the caller can detect this via `eq' on the
overlay or by checking `helixel-mc-fake-cursor-p' afterwards."
  (let* ((cs (overlay-get cursor 'helixel-cs))
         (pnt (and cs (helixel-cs-point cs)))
         (mrk (and cs (helixel-cs-mark cs))))
    (when (and cs pnt mrk (marker-position pnt) (marker-position mrk)
               (overlay-buffer cursor))
      (helixel-cs-restore cs)
      t)))

(defun helixel-mc--leave-cursor (cursor)
  "Snapshot current globals back into CURSOR's state struct and repaint.
After the fake's body ran, the per-cursor variables (including
`helixel--live-action' and `helixel--event-ring') hold this fake's
state — push them back into the cursor's `helixel-cursor-state'
struct, re-snap the fake's point/mark, and repaint its overlay."
  (let ((cs (overlay-get cursor 'helixel-cs)))
    (helixel-cs-update-from-globals cs)
    (helixel-mc--paint-cursor-overlay
     cursor (marker-position (helixel-cs-point cs)))
    (helixel-mc--update-fake-region cursor)))

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
  "Return the `helixel-tx' committed by `this-command' at real, or nil.
Looks at the front of `helixel--event-ring' — the most recent committed
action.  Returns its `tx' if and only if:
  - the action carries a `tx',
  - the action carries a runner (replayable),
  - the action's `by-command' stamp matches `this-command'.

The action may have a nil op (movement commands) or a non-nil
`:pre-replay-fn' (insert-entry commands' prepos).
`helixel-tx-replay' handles both uniformly: pre-replay-fn runs
first, then runner if any."
  (when (symbolp this-command)
    (let ((entry (car helixel--event-ring)))
      (when (and entry
                 (eq (helixel-action-by-command entry) this-command))
        entry))))

;; ── post-command-hook integration ──
;;
;; The former `helixel-mc--inhibit' and
;; `helixel-mc-executing-command-for-fake-cursor' flags are gone:
;; their function is now expressed by the `mc-batch' / `mc-fake'
;; origin of the unified `helixel-replay' context.
;; `helixel-mc-dispatch-in-progress-p' covers both.

;; ── Unified fake-cursor dispatch ──
;;
;; Phase 4.3 collapsed four dispatch strategies (fresh-edit replay,
;; substitute-alist, call-interactively fallback, prepos pre-broadcast)
;; into one.  Every helixel command produces a `helixel-tx' (either
;; via `:tx-runner' on the `helixel-define-command' macro, or via the
;; op-registry `:runner' attached by `helixel--record-action').  The
;; dispatcher now does ONE thing: replay the freshly-committed tx at
;; every fake.  No substitute-alist, no prepos symbol property, no
;; call-interactively fallback.

(defun helixel-mc--post-command ()
  "Post-command hook — replay `this-command's tx at every fake cursor.
The tx attached to the freshly-committed action (front of
`helixel--event-ring' with matching `by-command' stamp) is replayed
at each fake inside one `undo-amalgamate-change-group'.  Insert-entry
commands install a per-fake prepositioner as a `:pre-replay-fn'
payload on the action's tx — `helixel-tx-replay' calls it before
the main runner.

No-op when the mode is off, dispatch is already in progress, we're in
a keyboard-macro, the command is whitelisted off, or no fresh tx
exists (e.g. for real-cursor-only commands like
`helixel-mc-toggle')."
  (when (and helixel-multi-cursor-mode
             (not (helixel-mc-dispatch-in-progress-p))
             (not executing-kbd-macro)
             (not defining-kbd-macro)
             this-command
             (helixel-mc-any-p)
             (helixel-mc--should-run-for-all-p this-command))
    ;; Ensure the action just produced by `this-command' is on the ring
    ;; before we look for a fresh tx.  Movement / textobj commands do
    ;; not eagerly commit (only `record-action' does), so without this
    ;; the dispatcher would see the PRIOR action's tx.
    (helixel-action-commit)
    (let* ((fresh (helixel-mc--fresh-action-from-real))
           ;; A fresh tx is only useful for replay when it carries a
           ;; runner.  Auto-allocated txs (e.g. textobj sel-only,
           ;; pure jump entries) have a sel but no runner — they fall
           ;; back to the call-interactively path below.
           (fresh-tx (and fresh (helixel-tx-runner fresh) fresh))
           (cmd this-command))
      (helixel-with-replay 'mc-batch
        (condition-case err
            (undo-amalgamate-change-group
              (let ((dead nil))
                (helixel-mc-with-each-cursor
                  (condition-case e
                      (if fresh-tx
                          ;; Unified path: replay the fresh tx.  Payload
                          ;; carries prompted decisions so nothing
                          ;; re-prompts at fakes.
                          (helixel-with-replay-as 'dot
                            (helixel-tx-replay fresh-tx))
                        ;; Fallback: whitelisted Emacs built-ins
                        ;; (forward-char, next-line, self-insert-command,
                        ;; ...) have no tx — just re-call interactively.
                        (helixel-mc--call-interactively cmd))
                    (search-failed (push cursor dead))
                    (user-error
                     ;; Recoverable: command isn't applicable at this
                     ;; fake (e.g. `completion-preview-insert' with no
                     ;; preview active at the fake's position, or a
                     ;; movement command at bobp).  Keep the cursor
                     ;; alive — only operational failures kill cursors.
                     (ignore e))
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
      (progn
        (add-hook 'post-command-hook #'helixel-mc--post-command 90 t)
        (add-hook 'helixel-repeat-edit-override-functions
                  #'helixel-mc--repeat-edit-apply-only))
    (remove-hook 'post-command-hook #'helixel-mc--post-command t)
    (remove-hook 'helixel-repeat-edit-override-functions
                 #'helixel-mc--repeat-edit-apply-only)
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
   ;; Insert-entry commands themselves remain real-only — except
   ;; they're now broadcast via the unified dispatcher.  Each
   ;; insert-entry command declares a prepos via `:tx-runner' on its
   ;; `helixel-define-command' form; it lands as a `:pre-replay-fn'
   ;; payload on the tx and runs at every fake during replay.  So
   ;; they MUST be whitelisted (multiple-cursors property = t).
   ;; `insert-exit' stays whitelisted too — fakes need to leave
   ;; insert state.
   ;; Nothing here.
   ))

(provide 'helixel-mc-core)
;;; helixel-mc-core.el ends here
