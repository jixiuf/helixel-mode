;;; helixel-mc-core.el --- Multi-cursor core for helixel-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

;; Author: jixiuf <https://github.com/jixiuf>
;; SPDX-License-Identifier: GPL-3.0-or-later
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
;;   helixel-mc-mode      buffer-local minor mode (auto)
;;   helixel-mc--create-fake-cursor  create one fake cursor
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
(require 'helixel-ring)            ; helixel--action-commit

;; Emacs 29 compatibility: `hash-table-values' is new in Emacs 30.
(defun helixel--hash-table-values (table)
  "Return a list of values in hash TABLE."
  (let (values)
    (maphash (lambda (_k v) (push v values)) table)
    (nreverse values)))

(defvar helixel-mc-mode)        ; forward decl — defined below
(defvar helixel--current-state)           ; from `helixel-state'
;; Per-cursor state variables that `helixel-mc--pcs-clone' /
;; `-restore' / `-update-from-globals' read and write.  Defined
;; in helixel-core / helixel-ring / helixel-state — declared here
;; so the byte compiler doesn't flag them when this file is built
;; before those modules are loaded.
(defvar helixel--pending-sel)             ; from `helixel-core'
(defvar helixel-last-action)             ; from `helixel-core'
(defvar helixel--yank-register-source)    ; from `helixel-core' (mc per-cursor)
(defvar helixel--current-register)        ; from `helixel-core'
(defvar helixel--active-search)           ; from `helixel-state'
(defvar helixel--action-ring)              ; from `helixel-ring'
(defvar helixel--live-action)             ; from `helixel-ring'
(defvar helixel--action-pos)              ; from `helixel-ring'
(defvar helixel--mark-cycle-pos)          ; from `helixel-ring'
(declare-function helixel-enter-normal-state "helixel-state" (&rest _))
(declare-function helixel-visual-exit "helixel-state")
(declare-function helixel-mc--repeat-edit-apply-only "helixel-mc-integrate"
                  (raw-prefix))

(defsubst helixel-mc--dispatch-in-progress-p ()
  "Return non-nil when an mc dispatch is in progress.
Covers both `mc-batch' (outer broadcast loop) and `mc-fake'
\(inside one fake cursor's body).  Used by guards that must not
re-enter the dispatcher."
  (and helixel--replay
       (memq (helixel-replay--origin helixel--replay)
             '(mc-batch mc-fake))))

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
  "Mode-line format string for `helixel-mc-mode'.
%d is replaced by the total cursor count (real + fake)."
  :type 'string
  :group 'helixel)

(defcustom helixel-mc-max-cursors 500
  "Maximum number of fake cursors before refusing to create more.
Nil disables the check."
  :type '(choice (const :tag "Unlimited" nil) integer)
  :group 'helixel)

;; ── Per-cursor state ──
;;
;; Each fake cursor owns a `helixel-pc-state' struct that captures
;; the full set of variables the dispatcher snapshots/restores around
;; the per-fake body.  The struct lives on the overlay under one
;; property (`helixel-pc-state').
;;
;; Real cursor uses the SAME struct via `helixel-mc--pcs-clone' /
;; `-restore' in `helixel-mc--save-main-state'.  One type, one place.

(cl-defstruct (helixel-pc-state
               (:conc-name helixel-pcs-)
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
  last-action            ; `helixel-action'      (helixel-last-action)
  yank-register-source   ; swap-source plist     (helixel--yank-register-source)
  registers-alist        ; list (copy of register-alist)
  active-search          ; `helixel--last-motion'  (helixel--active-search)
  event-ring             ; list of `helixel-action' (helixel--action-ring)
  live-action            ; `helixel-action'      (helixel--live-action)
  action-pos             ; integer | nil         (helixel--action-pos)
  jump-cycle-pos         ; integer | nil         (helixel--mark-cycle-pos)
  last-motion-cmd)       ; `helixel--last-motion' or nil

(defun helixel-mc--pcs-clone ()
  "Capture the current cursor state into a fresh `helixel-pc-state'.
Markers are FRESH copies (`copy-marker') so the snapshot is
independent of any later movement of point / mark.

Used by `helixel-mc--save-main-state' and
`helixel-mc-with-saved-state' — callers that need to snapshot the
REAL cursor's full state and restore it later.  For fake cursor
creation, use `helixel-mc--pcs-create-fresh' instead, which nil's
live-action and registers and deep-copies the event-ring."
  (make-helixel-pc-state
   :point          (copy-marker (point) t)
   :mark           (copy-marker (mark-marker))
   :mark-active    mark-active
   :kill-ring                 kill-ring
   :kill-ring-yank-pointer    kill-ring-yank-pointer
   :mark-ring                 mark-ring
   :pending-sel               helixel--pending-sel
   :last-action               helixel-last-action
   :yank-register-source      helixel--yank-register-source
   :registers-alist            (copy-tree register-alist)
   :active-search             helixel--active-search
   :event-ring                helixel--action-ring
   :live-action               helixel--live-action
   :action-pos                helixel--action-pos
   :jump-cycle-pos            helixel--mark-cycle-pos
   :last-motion-cmd           helixel--last-motion-cmd))

(defun helixel-mc--pcs-create-fresh ()
  "Create a fresh `helixel-pc-state' for a NEW fake cursor.
Like `helixel-mc--pcs-clone' but clears inherited state that
should NOT leak from the real cursor into a fake:
  - event-ring: deep-copied (independent list, not shared ref)
  - live-action: nil (real cursor's in-progress action belongs
    to the real cursor; its markers will be released)
  - registers-alist: nil (fresh fake starts with empty registers)
Callers override point, mark, and \=`mark-active' to match the
spawn site."
  (let ((cs (helixel-mc--pcs-clone)))
    (setf (helixel-pcs-event-ring cs)
          (copy-sequence helixel--action-ring))
    (setf (helixel-pcs-live-action cs) nil)
    (setf (helixel-pcs-registers-alist cs) nil)
    cs))

(defun helixel-mc--pcs-swap-in (cs)
  "Restore cursor state CS into the current globals.
Moves point and the `mark-marker' to CS's positions, sets
`mark-active', and copies every helixel per-cursor var."
  (goto-char (marker-position (helixel-pcs-point cs)))
  (set-marker (mark-marker) (marker-position (helixel-pcs-mark cs)))
  (setq mark-active            (helixel-pcs-mark-active cs)
        kill-ring              (helixel-pcs-kill-ring cs)
        kill-ring-yank-pointer (helixel-pcs-kill-ring-yank-pointer cs)
        mark-ring              (helixel-pcs-mark-ring cs)
        helixel--pending-sel   (helixel-pcs-pending-sel cs)
        helixel-last-action   (helixel-pcs-last-action cs)
        helixel--yank-register-source (helixel-pcs-yank-register-source cs)
        ;; Swap register-alist for per-cursor register isolation.
        ;; The real cursor's alist is preserved by the outer
        ;; `helixel-mc--save-main-state' — we just replace the
        ;; global with the fake's saved copy here.
        register-alist (helixel-pcs-registers-alist cs)
        helixel--active-search (helixel-pcs-active-search cs)
        helixel--action-ring    (helixel-pcs-event-ring cs)
        helixel--live-action   (helixel-pcs-live-action cs)
        helixel--action-pos    (helixel-pcs-action-pos cs)
        helixel--mark-cycle-pos (helixel-pcs-jump-cycle-pos cs)
        helixel--last-motion-cmd (helixel-pcs-last-motion-cmd cs)))

(defun helixel-mc--pcs-release (cs)
  "Null the markers held by CS.  Idempotent.
Called when the cursor a CS belongs to is destroyed, to release
any buffer text the markers might otherwise pin."
  (when cs
    (when-let* ((m (helixel-pcs-point cs))) (set-marker m nil))
    (when-let* ((m (helixel-pcs-mark cs))) (set-marker m nil))))

(defun helixel-mc--pcs-swap-out (cs)
  "Update CS in place with current cursor globals.
Mutates the existing point/mark markers (preserving identity for
any rendering code that holds them).  Sets the rest by `setf'."
  (set-marker (helixel-pcs-point cs) (point))
  (set-marker (helixel-pcs-mark cs) (mark t))
  (setf (helixel-pcs-mark-active cs)            mark-active
        (helixel-pcs-kill-ring cs)              kill-ring
        (helixel-pcs-kill-ring-yank-pointer cs) kill-ring-yank-pointer
        (helixel-pcs-mark-ring cs)              mark-ring
        (helixel-pcs-pending-sel cs)            helixel--pending-sel
        (helixel-pcs-last-action cs)            helixel-last-action
        (helixel-pcs-yank-register-source cs)   helixel--yank-register-source
        (helixel-pcs-registers-alist cs)         (copy-tree register-alist)
        (helixel-pcs-active-search cs)          helixel--active-search
        (helixel-pcs-event-ring cs)             helixel--action-ring
        (helixel-pcs-live-action cs)            helixel--live-action
        (helixel-pcs-action-pos cs)             helixel--action-pos
        (helixel-pcs-jump-cycle-pos cs)         helixel--mark-cycle-pos
        (helixel-pcs-last-motion-cmd cs)        helixel--last-motion-cmd))

;; ── Cursor accessors (read state via the struct on the overlay) ──

(defsubst helixel-mc-cursor-state (cursor)
  "Return the `helixel-pc-state' attached to CURSOR overlay."
  (overlay-get cursor 'helixel-pc-state))

(defsubst helixel-mc-cursor-point (cursor)
  "Return the point marker of fake CURSOR."
  (helixel-pcs-point (overlay-get cursor 'helixel-pc-state)))

(defsubst helixel-mc-cursor-mark (cursor)
  "Return the mark marker of fake CURSOR."
  (helixel-pcs-mark (overlay-get cursor 'helixel-pc-state)))

(defsubst helixel-mc-cursor-mark-active (cursor)
  "Return non-nil if fake CURSOR's mark is active."
  (helixel-pcs-mark-active (overlay-get cursor 'helixel-pc-state)))

;; ── Cursor IDs ──
;; Every fake cursor gets a monotonically increasing integer ID that
;; persists for the cursor's lifetime (including across undo/redo).
;; The hash table provides O(1) lookup; the ID counter is never reset.
;; ID 0 is reserved for the real cursor.

(defvar-local helixel-mc--next-cursor-id 0
  "Monotonically increasing counter for fake-cursor IDs.
Never reset during the buffer's lifetime — IDs are stable
across undo/redo cycles.")

(defvar-local helixel-mc--cursors-by-id nil
  "Hash table mapping integer cursor ID → fake-cursor overlay.
The single source of truth for all fake cursors in the buffer.
Populated on first cursor creation, cleared on mode deactivation.
Each overlay has properties:
  `helixel-mc-cursor'    t (type tag)
  `helixel-mc-id'        integer cursor ID
  `helixel-pc-state'     `helixel-pc-state' (per-cursor state)
  `helixel-mc-region'    fake-region overlay or nil")

(defun helixel-mc--ensure-cursor-table ()
  "Initialize `helixel-mc--cursors-by-id' if it doesn't exist.
Idempotent — safe to call from any context where cursors may be
created before the minor mode has fully activated."
  (unless helixel-mc--cursors-by-id
    (setq helixel-mc--cursors-by-id (make-hash-table :test 'eql))))

(defsubst helixel-mc-fake-cursor-p (ov)
  "Return non-nil if OV is a fake-cursor overlay."
  (and (overlayp ov) (overlay-get ov 'helixel-mc-cursor)))

(defun helixel-mc-all-cursors (&optional sort)
  "Return the list of fake-cursor overlays.
Filters out dead overlays (detached from buffer) and zombie
overlays whose marker has been nulled — either condition would
crash `helixel-mc--enter-cursor's `goto-char'.
When SORT is non-nil, return them sorted by buffer position.
Iterates the `helixel-mc--cursors-by-id' hash table values."
  (let ((cursors
         (when helixel-mc--cursors-by-id
           (cl-remove-if-not
            (lambda (ov)
              (and (overlay-buffer ov)
                   (let ((cs (overlay-get ov 'helixel-pc-state)))
                     (and cs (helixel-pcs-point cs)
                          (marker-position (helixel-pcs-point cs))))))
            (helixel--hash-table-values helixel-mc--cursors-by-id)))))
    (if sort
        (sort cursors
              (lambda (a b)
                (< (marker-position (helixel-pcs-point
                                     (overlay-get a 'helixel-pc-state)))
                   (marker-position (helixel-pcs-point
                                     (overlay-get b 'helixel-pc-state))))))
      cursors)))

(defun helixel-mc-num-cursors ()
  "Return the number of cursors (real + fake) in the buffer."
  (1+ (length (helixel-mc-all-cursors))))

(defun helixel-mc-any-p ()
  "Return non-nil if any fake cursors exist in the current buffer."
  (and helixel-mc--cursors-by-id
       (> (hash-table-count helixel-mc--cursors-by-id) 0)))

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
  (let* ((cs  (overlay-get cursor 'helixel-pc-state))
         (pnt (marker-position (helixel-pcs-point cs)))
         (mrk (marker-position (helixel-pcs-mark cs)))
         (active (helixel-pcs-mark-active cs))
         (region-ov (overlay-get cursor 'helixel-mc-region)))
    (if (and active mrk (/= pnt mrk))
        (let ((b (min pnt mrk)) (e (max pnt mrk)))
          (if region-ov
              (move-overlay region-ov b e)
            (setq region-ov (make-overlay b e nil nil t))
            (overlay-put region-ov 'face 'helixel-mc-fake-region)
            (overlay-put region-ov 'priority 100)
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
    (let* ((cs (overlay-get ov-or-real 'helixel-pc-state))
           (p (marker-position (helixel-pcs-point cs)))
           (m (marker-position (helixel-pcs-mark cs)))
           (a (helixel-pcs-mark-active cs)))
      (cons p (if (and a m) m p)))))

(defun helixel-mc--cursor-region (ov-or-real)
  "Return (BEG . END) of OV-OR-REAL's active selection, or nil.
OV-OR-REAL is either a fake-cursor overlay or the keyword `:real'.
Returns nil when the cursor has no active region (point-only)."
  (if (eq ov-or-real :real)
      (and mark-active (mark t)
           (cons (min (point) (mark t))
                 (max (point) (mark t))))
    (let* ((cs (overlay-get ov-or-real 'helixel-pc-state))
           (p (marker-position (helixel-pcs-point cs)))
           (m (marker-position (helixel-pcs-mark cs)))
           (a (helixel-pcs-mark-active cs)))
      (and a m (/= p m) (cons (min p m) (max p m))))))

(defun helixel-mc--dedupe-cursors ()
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
    ;; Sort not needed — key-comparison is position-order independent.
    (let ((real-key (helixel-mc--cursor-key :real))
          (seen nil))
      (dolist (ov (helixel-mc-all-cursors))
        (let ((k (helixel-mc--cursor-key ov)))
          (cond
           ((equal k real-key)
            (helixel-mc--delete-fake-cursor ov)
            (cl-incf removed))
           ((member k seen)
            (helixel-mc--delete-fake-cursor ov)
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
              (helixel-mc--delete-fake-cursor who)
              (cl-incf removed))
             (t (setq last-end (max last-end end))))))))
    removed))

(defun helixel-mc--create-fake-cursor (point &optional mark)
  "Create a fake cursor at POINT, with optional active region to MARK.
Returns the new overlay, or nil if a fake at the same (point, mark)
already exists.  Signals `user-error' if `helixel-mc-max-cursors'
would be exceeded.
Snapshots the cursor state into a `helixel-pc-state' struct
attached to the overlay (so each cursor has its own `kill-ring',
event-ring, etc.).  Auto-enables `helixel-mc-mode'."
  (when (and helixel-mc-max-cursors
             (and helixel-mc--cursors-by-id
                  (>= (hash-table-count helixel-mc--cursors-by-id)
                      helixel-mc-max-cursors)))
    (user-error "Refusing to create more than %d fake cursors"
                helixel-mc-max-cursors))
  ;; Dedup against existing fakes only.  We do NOT skip when this
  ;; position happens to match the real cursor, because legitimate
  ;; flows (e.g. `s a' / `helixel-mc-add-cursor-here') snapshot the
  ;; real cursor INTO a fake at the same spot, then move real to
  ;; the next line.  Post-command `helixel-mc--dedupe-cursors' will
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
             (id (cl-incf helixel-mc--next-cursor-id))
             ;; Snapshot the real cursor's state, then clear
             ;; inherited state that must not leak into a fake.
             ;; helixel-mc--pcs-create-fresh handles this.
             (cs (helixel-mc--pcs-create-fresh)))
        (set-marker (helixel-pcs-point cs) point)
        (set-marker (helixel-pcs-mark cs) eff-mark)
        (setf (helixel-pcs-mark-active cs) (and mark (/= mark point)))
        (overlay-put ov 'helixel-mc-cursor t)
        (overlay-put ov 'helixel-mc-id id)
        (overlay-put ov 'priority 100)
        (overlay-put ov 'helixel-pc-state cs)
        (helixel-mc--ensure-cursor-table)
        (puthash id ov helixel-mc--cursors-by-id)
        (helixel-mc--paint-cursor-overlay ov point)
        (helixel-mc--update-fake-region ov)
        ;; Exit `visual' state on first cursor creation.  Visual's
        ;; "extend" semantics are incompatible with multi-cursor
        ;; "each cursor has its own fresh selection" semantics.
        ;; Exit visual state BEFORE the cursor becomes visible to
        ;; the state-change hook (helixel-mc--sync-visual-state).
        (when (eq helixel--current-state 'visual)
          (helixel-enter-normal-state))
        (unless helixel-mc-mode
          (helixel-mc-mode 1))
        ov)))))

(defun helixel-mc--delete-fake-cursor (cursor)
  "Delete fake CURSOR overlay and its associated region overlay.
Releases the markers held by the cursor's `helixel-pc-state'.
Removes the cursor from the ID-lookup hash table."
  (when (helixel-mc-fake-cursor-p cursor)
    (when (and helixel-mc--cursors-by-id
               (overlay-get cursor 'helixel-mc-id))
      (remhash (overlay-get cursor 'helixel-mc-id)
               helixel-mc--cursors-by-id))
    (helixel-mc--pcs-release (overlay-get cursor 'helixel-pc-state))
    (when-let* ((r (overlay-get cursor 'helixel-mc-region)))
      (delete-overlay r))
    (delete-overlay cursor)))

(defvar helixel-mc-before-clear-hook nil
  "Hook run BEFORE `helixel-mc-clear-all' destroys cursors.
Receives no arguments.  Use this for layout snapshotting,
undo recording, etc.")

(defun helixel-mc-clear-all ()
  "Remove every fake cursor in the current buffer.
Runs `helixel-mc-before-clear-hook' first.
Clears the ID-lookup hash table."
  (interactive)
  (run-hooks 'helixel-mc-before-clear-hook)
  (when helixel-mc--cursors-by-id
    (dolist (ov (helixel--hash-table-values helixel-mc--cursors-by-id))
      (helixel-mc--delete-fake-cursor ov))
    (clrhash helixel-mc--cursors-by-id))
  (when helixel-mc-mode
    (helixel-mc-mode -1)))

;; ── Cursor-by-ID accessor ──

(defun helixel-mc--cursor-by-id (id)
  "Return the fake-cursor overlay with the given integer ID, or nil.
Lookup is O(1) via the `helixel-mc--cursors-by-id' hash table."
  (when helixel-mc--cursors-by-id
    (gethash id helixel-mc--cursors-by-id)))

;; ── Cursor-position capture / restore (for undo integration) ──
;;
;; `helixel-mc--capture-all-positions' produces an alist that
;; `helixel-mc--restore-all-positions' consumes.  The alist format
;; mirrors hel's `hel-cursors-positions':
;;
;;   ((0 . (POINT . MARK-OR-NIL))    ; real cursor (ID 0)
;;    (ID1 . (P1 . M1))
;;    (ID2 . (P2 . M2)) ...)
;;
;; During undo/redo, `primitive-undo' processes `apply' entries and
;; calls `helixel-mc--undo-step-end-cb', which calls
;; `helixel-mc--restore-all-positions' to move both real and fake
;; cursors to their correct positions.

(defun helixel-mc--capture-all-positions ()
  "Return an alist of all cursor positions for undo persistence.
Format: ((0 . (POINT . MARK-OR-NIL)) (ID . (P . M)) ...).
Real cursor has ID 0; MARK-OR-NIL is nil when mark is inactive.
Fake cursors are sorted by point position ascending."
  (let ((real-pos (cons 0
                        (cons (point)
                              (and mark-active (mark t)))))
        (fake-entries nil))
    (dolist (ov (helixel-mc-all-cursors :sort))
      (when-let* ((id (overlay-get ov 'helixel-mc-id))
                  (cs (overlay-get ov 'helixel-pc-state))
                  (p (helixel-pcs-point cs))
                  (m (helixel-pcs-mark cs))
                  (pp (marker-position p))
                  (mm (marker-position m)))
        (push (cons id
                    (cons pp
                          (and (helixel-pcs-mark-active cs) mm)))
              fake-entries)))
    ;; Real first, then fakes sorted ascending.
    (cons real-pos (nreverse fake-entries))))

(defun helixel-mc--restore-all-positions (positions)
  "Restore all cursors from the POSITIONS alist.
POSITIONS is in the format returned by `helixel-mc--capture-all-positions'.
Restores real cursor (ID 0) first, then creates/updates/deletes
fake cursors to match.  Auto-toggles `helixel-mc-mode'."
  (let ((existing-ids nil)
        (new-fakes nil))
    (dolist (entry positions)
      (let ((id (car entry))
            (pos (cdr entry)))
        (pcase id
          (0
           ;; Real cursor.
           (goto-char (car pos))
           (let ((mark-pos (cdr pos)))
             (if mark-pos
                 (progn
                   (set-marker (mark-marker) mark-pos)
                   (setq mark-active t))
               (deactivate-mark))))
          (_
           (push id existing-ids)
           (if-let* ((ov (helixel-mc--cursor-by-id id))
                     ((overlay-buffer ov)))
               ;; Existing fake — update position.
               (let ((cs (overlay-get ov 'helixel-pc-state))
                     (p (car pos))
                     (m (cdr pos)))
                 (set-marker (helixel-pcs-point cs) p)
                 (set-marker (helixel-pcs-mark cs) (or m p))
                 (setf (helixel-pcs-mark-active cs) m)
                 (helixel-mc--paint-cursor-overlay ov p)
                 (helixel-mc--update-fake-region ov))
             ;; New fake — create with the same ID.
             (push (cons id pos) new-fakes))))))
    ;; Create new fakes (reverse so insertion order is sensible).
    (helixel-mc--ensure-cursor-table)
    (dolist (entry (nreverse new-fakes))
      (let* ((id (car entry))
             (p (cadr entry))
             (m (cddr entry))
             (ov (make-overlay p p nil nil t))
             (cs (helixel-mc--pcs-create-fresh)))
        (set-marker (helixel-pcs-point cs) p)
        (set-marker (helixel-pcs-mark cs) (or m p))
        (setf (helixel-pcs-mark-active cs) m)
        (overlay-put ov 'helixel-mc-cursor t)
        (overlay-put ov 'helixel-mc-id id)
        (overlay-put ov 'priority 100)
        (overlay-put ov 'helixel-pc-state cs)
        (puthash id ov helixel-mc--cursors-by-id)
        (helixel-mc--paint-cursor-overlay ov p)
        (helixel-mc--update-fake-region ov)))
    ;; Delete fakes not present in POSITIONS.
    (dolist (ov (helixel-mc-all-cursors))
      (unless (memq (overlay-get ov 'helixel-mc-id) existing-ids)
        (helixel-mc--delete-fake-cursor ov)))
    ;; Ensure mc minor mode reflects reality.
    (if (helixel-mc-any-p)
        (unless helixel-mc-mode
          (helixel-mc-mode 1))
      (when helixel-mc-mode
        (helixel-mc-mode -1)))))

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

(cl-defmacro helixel-mc--with-undo-step (&body body)
  "Execute BODY wrapped in an mc undo step with guaranteed cleanup.
Calls `helixel-mc--undo-step-begin' before BODY and
`helixel-mc--undo-step-finish' via `unwind-protect' after.

Use for non-command-loop callers that need atomic undo grouping
without going through the pre/`post-command-hook' dispatch path
\(e.g. chain-end broadcast, completion-preview sync)."
  (declare (indent 0) (debug t))
  `(progn
     (helixel-mc--undo-step-begin)
     (unwind-protect (progn ,@body)
       (helixel-mc--undo-step-finish))))

(cl-defmacro helixel-mc-defcmd (cmd &key (policy 'all))
  "Declarative dispatch spec for CMD.
Keyword options:
  POLICY — `all' or `real' (default `all').  When `real', CMD
     runs only at the real cursor (sets `multiple-cursors'
     property to nil).  Any other value sets the property to t."
  (declare (indent 1))
  (let ((real-only (eq policy 'real)))
    `(progn
       (put ',cmd 'multiple-cursors ,(not real-only))
       ',cmd)))

;; ── Undo-step management ──
;;
;; When mc is active and fake cursors exist, every command that
;; dispatches to fakes is wrapped in an undo step via
;; `pre-command-hook' / `post-command-hook'.  Two `apply' entries
;; are injected into `buffer-undo-list':
;;
;;   pre-hook   → push (apply helixel-mc--undo-step-end-cb P0)
;;   post-hook  → push (apply helixel-mc--undo-step-start-cb P1)
;;                        then strip nil & number entries
;;
;; During undo, `primitive-undo' processes these entries LIFO:
;;   1. (apply mc--undo-step-start-cb P1) → pushes counterpart for redo
;;   2. Text changes undone
;;   3. (apply mc--undo-step-end-cb P0)   → restore cursors to P0
;;
;; Numbers (point adjustments) and nil (undo boundaries) are
;; stripped so `primitive-undo' doesn't move point between fakes.
;;
;; The `-cb' suffix on `start-cb' / `end-cb' distinguishes these
;; 1-argument `primitive-undo' callbacks from the 0-argument hook
;; functions `helixel-mc--undo-step-begin' / `-finish'.
;;
;; `helixel-mc--with-undo-step' wraps an explicit begin/finish
;; pair for non-command-loop callers (chain-end broadcast,
;; completion-preview sync).

(defvar-local helixel-mc--undo-step-active nil
  "Non-nil while inside an mc undo step.
Set by `helixel-mc--undo-step-begin', cleared by
`helixel-mc--undo-step-finish'.  Guards against nested wrapping.")
(defvar-local helixel-mc--undo-list-pointer nil
  "Cons cell at the head of `buffer-undo-list' when the step began.
Set by `helixel-mc--undo-step-begin' for later comparison in
`helixel-mc--undo-step-finish' to detect no-op steps.")
(defvar-local helixel-mc--undo-boundary-marker nil
  "The before-marker `apply' entry pushed at undo-step begin.
Used by `helixel-mc--undo-step-finish' to detect no-op steps:
if no text changes occurred, this entry is popped from
`buffer-undo-list'.")

(defvar helixel-mc--input-cache nil
  "See `helixel-mc--def-input-cache' in helixel-mc-integrate.el.
Declared here because `helixel-mc--pre-command' sets it.")

(defun helixel-mc--undo-command-p (command)
  "Return non-nil if COMMAND is an undo/redo command.
These commands should never be wrapped in an mc undo step
because they manipulate `buffer-undo-list' themselves."
  (memq command '(undo undo-redo undo-only
                  undo-tree-undo undo-tree-redo
                  undo-fu-only-undo undo-fu-only-redo)))

(defun helixel-mc--undo-step-begin ()
  "Begin an mc undo step.
Captures cursor positions and pushes a before-marker into
`buffer-undo-list'.  Guards against double-wrapping and
disabled undo lists."
  (unless (or helixel-mc--undo-step-active
              (eq buffer-undo-list t))
    (setq helixel-mc--undo-step-active t)
    (let ((pos (helixel-mc--capture-all-positions)))
      (setq helixel-mc--undo-boundary-marker
            `(apply helixel-mc--undo-step-end-cb ,pos))
      (push helixel-mc--undo-boundary-marker buffer-undo-list)
      (setq helixel-mc--undo-list-pointer buffer-undo-list))))

(defun helixel-mc--filter-undo-step (list pointer)
  "Destructively remove nil and number entries from LIST.
Operates on the segment between LIST's head and POINTER (exclusive).
Returns the (possibly new) head of LIST.

Nil entries are undo boundaries; number entries are point-movement
records that `primitive-undo' would otherwise use to move point
between fake cursors — we handle cursor positions ourselves."
  (let ((tail list) head)
    (while (and tail (not (eq tail pointer)))
      (if (or (numberp (car tail)) (null (car tail)))
          (progn
            (setq tail (cdr tail))
            (if head
                (setcdr head tail)
              (setq list tail)))
        (setq head tail
              tail (cdr tail))))
    list))

(defun helixel-mc--undo-skip-leading-nils (lst)
  "Return LST with any leading nil (undo boundary) entries skipped."
  (while (and (consp lst) (null (car lst)))
    (setq lst (cdr lst)))
  lst)

(defun helixel-mc--undo-step-finish ()
  "Finish an mc undo step (0-arg management, called from hooks).
If buffer text was modified during the step, pushes an after-marker,
strips nil and number entries from the step segment, and maintains
`undo-equiv-table' for proper undo/redo chaining.

If no changes occurred, pops the unused before-marker.
Distinct from the 1-arg `helixel-mc--undo-step-end-cb' callback
that `primitive-undo' calls during undo/redo."
  (when helixel-mc--undo-step-active
    (unwind-protect
        (if (eq buffer-undo-list helixel-mc--undo-list-pointer)
            ;; No changes — pop our unused marker.
            (when (eq (car buffer-undo-list)
                      helixel-mc--undo-boundary-marker)
              (pop buffer-undo-list))
          ;; Changes happened — finalize the step.
          (let ((pos (helixel-mc--capture-all-positions)))
            (push `(apply helixel-mc--undo-step-start-cb ,pos)
                  buffer-undo-list)
            (let* ((lst (helixel-mc--undo-skip-leading-nils
                         buffer-undo-list))
                   (prev-head (car lst)))
              (setq lst (helixel-mc--filter-undo-step
                         lst helixel-mc--undo-list-pointer))
              (when-let* (((car lst))
                          (equiv (gethash prev-head undo-equiv-table)))
                (puthash (car lst) equiv undo-equiv-table))
              (setq buffer-undo-list lst)
              (undo-boundary))))
      ;; Cleanup always runs, even if body errors.
      (setq helixel-mc--undo-step-active nil
            helixel-mc--undo-list-pointer nil
            helixel-mc--undo-boundary-marker nil))))

;; ── Undo-step callbacks — called by `primitive-undo' via `apply' ──
;;
;; These are the 1-argument functions whose names appear in the
;; `apply' entries pushed into `buffer-undo-list'.  They must NOT
;; The `-cb' suffix distinguishes these 1-arg callbacks from the
;; 0-arg hook functions `helixel-mc--undo-step-begin' / `-finish'.

(defun helixel-mc--undo-step-start-cb (positions)
  "1-arg callback — `primitive-undo' calls this at step START.
Pushes the counterpart end-cb marker for redo support.
POSITIONS is the alist from `helixel-mc--capture-all-positions'.

Distinct from the 0-arg hook function `helixel-mc--undo-step-begin'."
  (push `(apply helixel-mc--undo-step-end-cb ,positions)
        buffer-undo-list))

(defun helixel-mc--undo-step-end-cb (positions)
  "1-arg callback — `primitive-undo' calls this at step END.
Restores all cursor positions from POSITIONS and pushes the
counterpart start-cb marker for redo support.
POSITIONS is the alist from `helixel-mc--capture-all-positions'.

Clears the variable `deactivate-mark' so the command loop does
not clear `mark-active' after `undo' returns — `primitive-undo'
routinely sets the variable `deactivate-mark' during text restoration.

Distinct from the 0-arg hook function `helixel-mc--undo-step-finish'."
  (helixel-mc--restore-all-positions positions)
  (setq deactivate-mark nil)
  (push `(apply helixel-mc--undo-step-start-cb ,positions)
        buffer-undo-list))

;; ── Dispatch loop ──

(defun helixel-mc--call-interactively (command)
  "Run COMMAND interactively (skipping `ignore').
For `self-insert-command' at invisible position, inserts
directly after removing the invisible property — avoiding
org-fold hooks that would delete the inserted char."
  (unless (eq command 'ignore)
    (if (and (invisible-p (point))
             (or (eq command 'self-insert-command)
                 (eq command 'org-self-insert-command)))
        ;; Insert directly at invisible position: remove
        ;; invisibility then `insert' to bypass org-fold hooks
        ;; that corrupt the insertion.
        (progn
          (remove-text-properties (point) (1+ (point))
                                  '(invisible nil))
          (insert (char-to-string last-command-event)))
      (let ((this-command command))
        (call-interactively command)))))

(defmacro helixel-mc--save-main-state (&rest body)
  "Save real cursor state into a `helixel-pc-state', run BODY, restore.
Used by `helixel-mc-with-each-cursor' to keep the real cursor's
point/mark/helixel vars/kill-ring/event-ring untouched while each
fake cursor's body runs in turn."
  (declare (indent 0) (debug t))
  (let ((cs (gensym "cs")))
    `(let ((,cs (helixel-mc--pcs-clone)))
       (save-excursion
         (unwind-protect (progn ,@body)
           (helixel-mc--pcs-swap-in ,cs)
           (helixel-mc--pcs-release ,cs))))))

(defmacro helixel-mc-with-saved-state (&rest body)
  "Execute BODY, saving and restoring per-cursor state.
Snapshots the real cursor's state into a `helixel-pc-state'
before BODY and restores it after — EXCEPT for point and mark,
which are left as BODY leaves them (the caller is responsible
for cursor positioning).

Use this when walking the buffer to collect targets outside
of the standard with-each-cursor dispatch loop, so advance
functions don't clobber the real cursor's per-cursor helixel
state (kill-ring, event-ring, last-action, …)."
  (declare (indent 0) (debug t))
  (let ((cs (gensym "cs")))
    `(let ((,cs (helixel-mc--pcs-clone)))
       (unwind-protect (progn ,@body)
         ;; Restore everything except point/mark — callers rely on
         ;; BODY moving point freely.
         (setq mark-active            (helixel-pcs-mark-active ,cs)
               kill-ring              (helixel-pcs-kill-ring ,cs)
               kill-ring-yank-pointer (helixel-pcs-kill-ring-yank-pointer ,cs)
               mark-ring              (helixel-pcs-mark-ring ,cs)
               helixel--pending-sel   (helixel-pcs-pending-sel ,cs)
               helixel-last-action   (helixel-pcs-last-action ,cs)
               helixel--yank-register-source
                 (helixel-pcs-yank-register-source ,cs)
               register-alist
                 (helixel-pcs-registers-alist ,cs)
               helixel--active-search (helixel-pcs-active-search ,cs)
               helixel--action-ring    (helixel-pcs-event-ring ,cs)
               helixel--live-action   (helixel-pcs-live-action ,cs)
               helixel--action-pos    (helixel-pcs-action-pos ,cs)
               helixel--mark-cycle-pos (helixel-pcs-jump-cycle-pos ,cs))
         (helixel-mc--pcs-release ,cs)))))

(defvar helixel-mc--quit-p nil
  "Non-nil means `quit' has fired during the per-cursor body.
Bound by `helixel-mc-with-each-cursor'; prevents
`helixel-mc--leave-cursor' from saving corrupted state.")

(defmacro helixel-mc-with-each-cursor (&rest body)
  "Evaluate BODY once at each fake cursor.
Real cursor's state (point, mark, helixel vars) is preserved.
At each fake cursor BODY runs in an environment where point,
mark, and the per-cursor state struct have been restored from the
overlay.  After BODY, the overlay is updated to reflect the new
state — unless a `quit' fires during BODY, in which case the
fake's state is left untouched to avoid corruption from a
partially-executed command."
  (declare (indent 0) (debug t))
  `(let ((inhibit-message t)            ; suppress per-fake echo spam
         (helixel-mc--quit-p nil))
     (helixel-with-replay 'mc-fake
       (helixel-mc--save-main-state
         (dolist (cursor (helixel-mc-all-cursors :sort))
           (when (and (helixel-mc-fake-cursor-p cursor)
                      (helixel-mc--enter-cursor cursor))
             (setq helixel-mc--quit-p nil)
             (unwind-protect
                 (condition-case nil
                     (progn ,@body)
                   (quit (setq helixel-mc--quit-p t)))
               (unless helixel-mc--quit-p
                 (helixel-mc--leave-cursor cursor)))))))))

(defun helixel-collapse-selection ()
  "Collapse every cursor's selection to a bare cursor (Helix `;').
Each cursor (real and fake) with an active region has its mark
deactivated, leaving point unchanged.  When the real cursor has an
active region, visual state is also exited so subsequent movements
start fresh selections rather than extending the collapsed one.
Cursors without a region are left unchanged.  No cursors are removed."
  (interactive)
  ;; Collapse real cursor first.
  (when (use-region-p)
    (deactivate-mark)
    ;; Exit visual state so movements (w, e, b, etc.) start fresh
    ;; selections instead of extending in visual mode.
    (when (eq helixel--current-state 'visual)
      (helixel-visual-exit)))
  ;; Collapse each fake cursor.
  (when (helixel-mc-any-p)
    (helixel-mc-with-each-cursor
      (when (use-region-p)
        (deactivate-mark)))))

(defun helixel-mc--enter-cursor (cursor)
  "Restore point/mark/state from CURSOR overlay into globals.
Does nothing (returns nil) if CURSOR has been detached or its
state is missing — the caller can detect this via `eq' on the
overlay or by checking `helixel-mc-fake-cursor-p' afterwards."
  (let* ((cs (overlay-get cursor 'helixel-pc-state))
         (pnt (and cs (helixel-pcs-point cs)))
         (mrk (and cs (helixel-pcs-mark cs))))
    (when (and cs pnt mrk (marker-position pnt) (marker-position mrk)
               (overlay-buffer cursor))
      (helixel-mc--pcs-swap-in cs)
      t)))

(defun helixel-mc--leave-cursor (cursor)
  "Snapshot current globals back into CURSOR's state struct and repaint.
After the fake's body ran, the per-cursor variables (including
`helixel--live-action' and `helixel--action-ring') hold this fake's
state — push them back into the cursor's `helixel-pc-state'
struct, re-snap the fake's point/mark, and repaint its overlay."
  (let ((cs (overlay-get cursor 'helixel-pc-state)))
    (helixel-mc--pcs-swap-out cs)
    (helixel-mc--paint-cursor-overlay
     cursor (marker-position (helixel-pcs-point cs)))
    (helixel-mc--update-fake-region cursor)))

(defun helixel-mc--execute-for-all-cursors (command)
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

(defvar helixel-mc--saved-this-command nil
  "`this-command' snapshot taken by `helixel-mc--pre-command'.
Used as a fallback in `helixel-mc--fresh-action-from-real' when
`this-command' has been overwritten by a recursive edit (e.g.
isearch).  Set to nil after each dispatch to avoid stale reuse.")

(defun helixel-mc--fresh-action-from-real ()
  "Return the `helixel-action' committed by `this-command' at real, or nil.
Looks at the front of `helixel--action-ring' — the most recent committed
action.  Returns its `tx' if and only if:
  - the action carries a `tx',
  - the action carries a runner (replayable),
  - the action's `by-command' stamp matches `this-command' or
    `helixel-mc--saved-this-command' (fallback for `recursive-edit'
    commands like isearch that overwrite `this-command').

The action may have a nil op (movement commands) or a non-nil
`:preposition' (insert-entry commands' prepos).
`helixel-action-replay' handles both uniformly: preposition runs
first, then runner if any."
  ;; `helixel-mc--saved-this-command' takes priority — after a
  ;; recursive edit (isearch, query-replace) `this-command' is
  ;; stale (e.g. `isearch-exit' instead of `helixel-search-forward').
  (let ((cmd (or helixel-mc--saved-this-command
                 (and (symbolp this-command) this-command))))
    (when cmd
      (let ((entry (car helixel--action-ring)))
        (when (and entry
                   (eq (helixel-action-by-command entry) cmd))
          entry)))))

;; ── post-command-hook integration ──
;;
;; The former `helixel-mc--inhibit' and
;; `helixel-mc-executing-command-for-fake-cursor' flags are gone:
;; their function is now expressed by the `mc-batch' / `mc-fake'
;; origin of the unified `helixel-replay' context.
;; `helixel-mc--dispatch-in-progress-p' covers both.

;; ── Unified fake-cursor dispatch ──

(defun helixel-mc--replay-at-one-fake-1 (fresh-runnable cmd)
  "Dispatch CMD (or FRESH-RUNNABLE) at one fake cursor.
Return non-nil on success, nil on error (fake cursor deleted).

Design: a fake cursor should execute commands like the real cursor.
The only exception is operator commands (op non-nil), which may
prompt (surround-*, replace-char) or change global state
\(change → insert).  Those replay the pre-built runner.

Movement / search / textobj commands (op = nil) run the runner
AND record a per-fake ring entry so \=`;' cycling works.
Fallback commands (no fresh action) run via
\=`call-interactively' with no suppression — the fake's
\=`live-action' is nil at creation, so there is no stale state.
The \=`mc-fake' replay context does NOT inhibit
\=`helixel--tracking-open', so rings grow naturally."
  (condition-case e
      (progn
        (if fresh-runnable
            (if (helixel-action-op fresh-runnable)
                ;; Operator command: replay runner (no prompts).
                (helixel-action-replay fresh-runnable)
              ;; Non-operator: run the runner AND record a
              ;; per-fake ring entry via tracking-open + commit.
              (progn
                (helixel--tracking-open
                 (helixel-action-category fresh-runnable)
                 (helixel-action-subcat fresh-runnable))
                (helixel-action-replay fresh-runnable)
                (helixel--action-commit)))
          ;; No fresh-runnable: run via call-interactively.
          ;; mc-fake context → tracking-open works → ring grows.
          (helixel-mc--call-interactively cmd))
        t)
    (search-failed nil)
    (user-error t)
    (error
     (message "helixel-mc: %s at fake: %s"
              cmd (error-message-string e))
     nil)))

(defmacro helixel-mc--replay-at-one-fake (fresh-runnable cmd cursor dead)
  "Replay FRESH-RUNNABLE (or run CMD) at fake CURSOR.
Appends to DEAD list on `search-failed' or other errors.

Must be a macro (not a function) because `push' on DEAD must
mutate the caller's binding — a function would only modify its
own parameter."
  (declare (debug (form form form form)))
  `(unless (helixel-mc--replay-at-one-fake-1 ,fresh-runnable ,cmd)
     (push ,cursor ,dead)))

(defvar helixel-mc--post-command-depth 0
  "Nesting depth for mc `pre-command-hook' / `post-command-hook'.
Incremented in `helixel-mc--pre-command', decremented in
`helixel-mc--post-command'.  Dispatch only fires when depth
returns to 1 — the outermost command loop — so inner recursive
edits (isearch, `query-replace') don't trigger double-dispatch.")

(defun helixel-mc--post-command ()
  "Post-command hook — replay `this-command's tx at every fake cursor.
The tx attached to the freshly-committed action (front of
`helixel--action-ring' with matching `by-command' stamp) is replayed
at each fake cursor.  The undo-step wrapping (begin in pre-hook, end
here) amalgamates all changes — real cursor + fake dispatches — into
one atomic undo step with cursor-position persistence.

No-op when the mode is off, dispatch is already in progress, we're in
a keyboard-macro, isearch is active (global modal state), the command
is whitelisted off, or no fresh tx exists (e.g. for real-cursor-only
commands like `helixel-mc-toggle')."
  (when (and helixel-mc-mode
             (not (helixel-mc--dispatch-in-progress-p))
             (not executing-kbd-macro)
             (not defining-kbd-macro)
             (not isearch-mode)
             this-command)
    ;; Only dispatch when depth ≤ 1 — the outermost command loop.
    ;; Inner recursive-edit commands (isearch, etc.) are skipped
    ;; (depth > 1).  When no saved command exists (tests, first
    ;; command), dispatch falls back to `this-command'.
    (when (<= helixel-mc--post-command-depth 1)
      (when (and (helixel-mc-any-p)
                 (helixel-mc--should-run-for-all-p this-command))
        (helixel--action-commit)
        (let* ((fresh (helixel-mc--fresh-action-from-real))
               (fresh-runnable (and fresh (helixel-action-runner fresh) fresh))
               (cmd this-command))
          ;; The with-each-cursor quit guard (added in that macro)
          ;; makes all fallback call-interactively safe: any command
          ;; that signals quit gets caught, leave-cursor is skipped,
          ;; and fake state survives uncorrupted.
          (helixel-with-replay 'mc-batch
            (condition-case err
                (let ((dead nil))
                  (helixel-mc-with-each-cursor
                    (helixel-mc--replay-at-one-fake
                     fresh-runnable cmd cursor dead))
                  (dolist (ov dead)
                    (helixel-mc--delete-fake-cursor ov)))
              (quit nil)  ; belt-and-suspenders after C-g
              (error
               (message "helixel-mc: %s outer error: %s"
                        cmd (error-message-string err))))
            (helixel-mc--dedupe-cursors))
          (helixel-mc--undo-step-finish)))
      ;; Clear saved command so next outer command gets a fresh snapshot.
      (setq helixel-mc--saved-this-command nil))
    (unless (eq this-command 'helixel-select-register)
      (setq helixel--current-register nil)))
  ;; Always balance the depth — pre-command-hook always increments.
  ;; Don't go below 0 (tests call post-command without pre-command).
  (when (> helixel-mc--post-command-depth 0)
    (setq helixel-mc--post-command-depth
          (1- helixel-mc--post-command-depth)))
  ;; Keep real-region overlay above lazy-highlight during mc mode.
  (when helixel-mc-mode
    (helixel-mc--update-real-region)))

;; ── Pre-command hook ──

(defun helixel-mc--pre-command ()
  "Pre-command hook for mc undo-step wrapping.
Begins an undo step when mc is active, fake cursors exist,
this is the outermost command loop (depth = 1), the command is
eligible for mc dispatch, and it is not an undo/redo operation.

Also snapshots `this-command' into `helixel-mc--saved-this-command'
so the dispatcher can find the fresh action even after a recursive
edit (e.g. isearch) overwrites `this-command'.

Clears `helixel-mc--input-cache' so each command starts with a
fresh cache for third-party user-input functions (\=`read-char',
\=\`read-string\=, etc.)."
  ;; Clear the input cache at the start of each outer command.
  (setq helixel-mc--input-cache nil)
  ;; Snapshot `this-command' early — before any recursive edit
  ;; (isearch, query-replace, etc.) can overwrite it.  Used by
  ;; `helixel-mc--fresh-action-from-real' as a fallback.
  ;; Only save once per outer command — skip overwrites during
  ;; recursive edits (e.g. isearch inner commands like `isearch-exit').
  (setq helixel-mc--post-command-depth
        (1+ helixel-mc--post-command-depth))
  (when (and (= helixel-mc--post-command-depth 1)
             (not isearch-mode)
             (not helixel-mc--saved-this-command))
    (setq helixel-mc--saved-this-command this-command))
  ;; When mc mode is active and the real cursor has an active region,
  ;; force-deactivate the mark before undo/redo commands run.  Otherwise
  ;; Emacs' `undo' sees the active region and calls `undo-in-region'
  ;; instead of a full undo, which is never the user's intent in mc mode.
  (when (and helixel-mc-mode
             mark-active
             this-command
             (helixel-mc--undo-command-p this-command))
    (deactivate-mark t))
  (when (and helixel-mc-mode
             (helixel-mc-any-p)
             (not executing-kbd-macro)
             (not defining-kbd-macro)
             (= helixel-mc--post-command-depth 1)
             this-command
             (helixel-mc--should-run-for-all-p this-command)
             (not (helixel-mc--undo-command-p this-command))
             (not (helixel-mc--dispatch-in-progress-p)))
    (helixel-mc--undo-step-begin)))

;; ── Minor mode ──

(defvar helixel-mc-mode-map (make-sparse-keymap)
  "Keymap active while `helixel-mc-mode' is on.
Populated by `helixel-keymap'.")

(defvar-local helixel-mc--real-region-ov nil
  "Overlay showing the real cursor's region during mc mode.
Created so the real selection appears above isearch lazy-highlight
and other low-priority overlays.  Has the same priority as
fake-region overlays (100).")

(defun helixel-mc--update-real-region ()
  "Create or update the real-cursor region overlay.
Creates an overlay spanning the real cursor's active region with
high priority so it renders above lazy-highlight matches.
Clears the overlay when the region is inactive."
  (if (and mark-active (mark t) (/= (point) (mark t)))
      (let ((b (min (point) (mark t)))
            (e (max (point) (mark t))))
        (if helixel-mc--real-region-ov
            (move-overlay helixel-mc--real-region-ov b e)
          (setq helixel-mc--real-region-ov
                (make-overlay b e nil nil t))
          (overlay-put helixel-mc--real-region-ov
                       'face 'region)
          (overlay-put helixel-mc--real-region-ov 'priority 100)))
    (when helixel-mc--real-region-ov
      (delete-overlay helixel-mc--real-region-ov)
      (setq helixel-mc--real-region-ov nil))))

;;;###autoload
(define-minor-mode helixel-mc-mode
  "Helixel multi-cursor minor mode.
Activated automatically when at least one fake cursor exists,
deactivated when the last one is removed."
  :init-value nil
  :lighter (:eval (format helixel-mc-mode-line-indicator
                          (helixel-mc-num-cursors)))
  :keymap helixel-mc-mode-map
  (if helixel-mc-mode
      (progn
        (helixel-mc--ensure-cursor-table)
        (add-hook 'pre-command-hook #'helixel-mc--pre-command 90 t)
        (add-hook 'post-command-hook #'helixel-mc--post-command 90 t)
        (add-hook 'helixel-repeat-edit-override-functions
                  #'helixel-mc--repeat-edit-apply-only))
    (remove-hook 'pre-command-hook #'helixel-mc--pre-command t)
    (remove-hook 'post-command-hook #'helixel-mc--post-command t)
    (remove-hook 'helixel-repeat-edit-override-functions
                 #'helixel-mc--repeat-edit-apply-only)
    ;; Clean up lingering undo-step state.
    (setq helixel-mc--undo-step-active nil
          helixel-mc--undo-list-pointer nil
          helixel-mc--undo-boundary-marker nil)
    (when helixel-mc--cursors-by-id
      (clrhash helixel-mc--cursors-by-id))
    (helixel-mc-clear-all)
    ;; Clean up real-region overlay.
    (when helixel-mc--real-region-ov
      (delete-overlay helixel-mc--real-region-ov)
      (setq helixel-mc--real-region-ov nil))))

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
   helixel-select-register
   helixel-mc-toggle helixel-mc-clear-all
   helixel-mc--create-fake-cursor
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
   ;; insert-entry command declares a prepos via `:preposition' on its
   ;; `helixel-define-command' form; it lands as a `:preposition'
   ;; payload on the tx and runs at every fake during replay.  So
   ;; they MUST be whitelisted (multiple-cursors property = t).
   ;; `insert-exit' stays whitelisted too — fakes need to leave
   ;; insert state.
   ;; Nothing here.
   ))

(provide 'helixel-mc-core)
;;; helixel-mc-core.el ends here
