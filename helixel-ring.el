;;; helixel-ring.el --- Event ring and jump log storage -*- lexical-binding: t; -*-

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

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Event storage layer + history navigation for helixel-mode.
;;
;; Two storage containers:
;;   1. buffer-local `helixel--event-ring' — serves `;` cycling,
;;      `.`/`,` repeat, and history selection.
;;   2. global `helixel--global-jump-log' — serves C-o/C-i jump
;;      navigation across buffers.
;;
;; Provides:
;;   - the unified tracking entry point `helixel--tracking-open' used by
;;     all command-definition macros and live-event management helpers;
;;   - the `;' action-cycle commands and the C-o / C-i jump commands
;;     (consumers of the two containers above).

;;; Code:

(require 'cl-lib)
(require 'helixel-core)
(require 'helixel-replay)

;; ----------------------------------------------------------------------
;; State variables
;; ----------------------------------------------------------------------

(defvar-local helixel--action-pos nil
  "Ring position for `;' cycling.
nil = live event.  0 = newest ring entry.  N = older.")

;; ----------------------------------------------------------------------
;; Buffer-local event ring
;; ----------------------------------------------------------------------

(defcustom helixel-action-ring-max 50
  "Maximum number of events stored in `helixel--event-ring'."
  :type 'integer
  :group 'helixel)

(defvar-local helixel--event-ring nil
  "Event ring, most recent first.  Capped at `helixel-action-ring-max'.
Each entry is a `helixel-action' struct.
Shared by session jump (`;'), repeat (`.`/`,`), and history (`C-u n').")

(defvar-local helixel--live-action nil
  "The currently in-progress `helixel-action'.
Set at command start, committed to ring when complete.")

;; `helixel--last-tx' is defined in helixel-core.el.
;; It is available transitively through the require chain.

(defconst helixel--sel-categories '(movement search find-char textobj)
  "Event categories that carry a selection descriptor.
Used by `helixel-action-commit' to sync `helixel--pending-sel'
into the committed event's :sel slot when the event's own :sel
is nil.  Categories not listed here never carry a pending-sel.")

(defun helixel-action--ring-cap ()
  "Truncate `helixel--event-ring' to `helixel-action-ring-max' entries.
Releases markers of evicted entries to prevent leaks."
  (when (> (length helixel--event-ring) helixel-action-ring-max)
    (let ((tail (nthcdr helixel-action-ring-max helixel--event-ring)))
      (dolist (e tail)
        (when-let* ((mr (helixel-action-mark-region e))
                    ((consp mr)))
          (set-marker (car mr) nil)
          (set-marker (cdr mr) nil))))
    (setcdr (nthcdr (1- helixel-action-ring-max)
                    helixel--event-ring)
            nil)))

(defvar helixel-action-commit-hook nil
  "Abnormal hook run by `helixel-action-commit' after pushing to the ring.
Each function receives one argument: the just-committed
`helixel-action' (the deep-copied entry now sitting at the front
of `helixel--event-ring').

Used by chain recording (`helixel-chain.el') to accumulate the
list of txs run during the chain; the chain transaction simply
replays each tx in order.

Keep handlers fast — this fires on every command that commits an
action.")

(defun helixel-action-commit ()
  "Commit `helixel--live-action' to `helixel--event-ring'.
Deep-copies the event (marker + sel) so ring entries are independent.
Deduplicates against the ring front — same (op sel payload) skips push.
Also mirrors to `helixel--global-jump-log'.
Sets `helixel--last-tx' to the committed entry.
Returns the committed entry or nil."
  (when helixel--live-action
    ;; Sync pending-sel into the live-event so movement/search
    ;; events in the ring carry their selection descriptor.
    ;; Only for selection-creating categories; edits already set
    ;; sel via `helixel--live-action-set'.
    (when (and helixel--pending-sel
               (not (helixel-action-sel helixel--live-action))
               (memq (helixel-action-category helixel--live-action)
                     helixel--sel-categories))
      (setf (helixel-action-sel helixel--live-action)
            (helixel-sel--copy helixel--pending-sel)))
    (let ((entry (helixel-action--copy helixel--live-action)))
      ;; `by-command' is stamped at `tracking-open' time (eagerly) so
      ;; deferred commits keep the originating command symbol.  Only
      ;; fill it in here as a fallback when the live action was
      ;; constructed without one (rare — mainly tests).
      (unless (helixel-action-by-command entry)
        (let ((cmd (or (and (symbolp this-command) this-command)
                       helixel--current-command)))
          (when cmd
            (setf (helixel-action-by-command entry) cmd))))
      (unless (and (car helixel--event-ring)
                   (helixel-action--same-content-p
                    entry (car helixel--event-ring)))
        (push entry helixel--event-ring)
        (helixel-action--ring-cap))
      ;; `helixel--last-tx' tracks the most recent EDIT for `.' replay.
      ;; Movement txs (op = nil, runner-only) participate in mc dispatch
      ;; but must NOT advance last-tx — that would shadow the prior
      ;; edit and break dot-repeat semantics.  The op-presence check
      ;; distinguishes real edits (kill, change, insert-text, …) from
      ;; mc-replay movement shims.
      (when-let* ((tx (helixel-action-tx entry))
                  ((helixel-tx-op tx)))
        (setq helixel--last-tx tx))
      (helixel--global-jump-log-push entry)
      (setq helixel--live-action nil)
      (run-hook-with-args 'helixel-action-commit-hook entry)
      entry)))

;; ── Live-event helpers ──

(defun helixel--cancel-action ()
  "Cancel the current action via \\[keyboard-quit].
Commits meaningful events, pushes a state/cancel sentinel,
and clears the live state."
  (helixel-action-commit)
  ;; Push cancel sentinel for dedup boundary
  (setq helixel--live-action
        (make-helixel-action
         :category 'state
         :subcat 'cancel
         :mark-region (let ((pm (point-marker)))
                         (cons pm (copy-marker pm t)))
         :timestamp (float-time)
         :buffer (current-buffer)))
  (helixel-action-commit))

(defun helixel--live-action-set (tx)
  "Attach TX to `helixel--live-action' and lift its display, if any.
TX is a `helixel-tx' produced by `helixel-tx-create' (or equivalent).
No-op if no live action or TX isn't a tx."
  (when (and helixel--live-action (helixel-tx-p tx))
    (setf (helixel-action-tx helixel--live-action) tx)))

;; ── Unified entry point: open event (commit prev, create new) ──

(defun helixel--tracking-open (category subcat &optional op)
  "Commit previous `helixel--live-action' and create a new one.
CATEGORY and SUBCAT classify the event for \=`;\=` and jump-list.
OP is an optional operator symbol (nil for movement/search).

No-op when `(helixel-replaying-p)` is non-nil (dot-repeat).
Does NOT commit the new event — caller is responsible for eventual commit."
  (unless (helixel-replaying-p)
    ;; Clear textobj selection state on non-textobj actions
    (when (and (eq helixel--raw-selection-type 'textobj)
               (not (eq category 'textobj)))
      (setq helixel--raw-selection-type nil))
    (helixel-action-commit)
    (setq helixel--live-action
          (make-helixel-action
           :category category
           :subcat subcat
           ;; Stamp `by-command' EAGERLY at action open time, using the
           ;; current command symbol bound by `helixel-define-command'
           ;; (or fall back to `this-command' set by the command loop).
           ;; Doing it here — not at commit time — keeps the stamp
           ;; correct even when commit is deferred to the next
           ;; `tracking-open' (which then runs in a NEW command's scope).
           :by-command (or helixel--current-command
                           (and (symbolp this-command) this-command))
           :mark-region (let ((pm (point-marker)))
                           (cons pm (copy-marker pm t)))
           :timestamp (float-time)
           :buffer (current-buffer)
           :tx (when op (make-helixel-tx :op op)))
          helixel--action-pos nil)))

;; ----------------------------------------------------------------------
;; Global jump log (C-o / C-i)
;; ----------------------------------------------------------------------

(defcustom helixel-jump-log-max 100
  "Maximum number of entries in `helixel--global-jump-log'."
  :type 'integer
  :group 'helixel)

(defcustom helixel-jump-categories
  '(movement textobj search find-char edit goto user jump)
  "Event :category symbols recorded into `helixel--global-jump-log'.
Categories not listed here do not generate jump entries."
  :type '(repeat symbol)
  :group 'helixel)

(defcustom helixel-jump-cycle-categories
  '(movement textobj search find-char edit goto user jump)
  "Event :category symbols visible during jump cycling.
Only categories listed here are shown when pressing
`helixel-jump-backward' or `helixel-jump-forward'."
  :type '(repeat symbol)
  :group 'helixel)

(defvar helixel--global-jump-log nil
  "Global jump entries, most recent first.
Each entry: (:mark-region (START . END) :buffer BUF :category CAT
:subcat SUBCAT).  Lightweight — no full event payload, sel struct,
or closures.")

(defvar helixel--jump-pos nil
  "Current position in `helixel--global-jump-log' for jump cycling.
nil = not cycling.  0 = newest (list head).  N = older.")

(defun helixel--jump-same-content-p (a b)
  "Return non-nil if jump entries A and B have identical content.
Compares :buffer, :category, :subcat, and marker position."
  (and a b
       (eq (plist-get a :buffer) (plist-get b :buffer))
       (eq (plist-get a :category) (plist-get b :category))
       (equal (plist-get a :subcat) (plist-get b :subcat))
       (let ((mr-a (plist-get a :mark-region))
             (mr-b (plist-get b :mark-region)))
         (if (and (consp mr-a) (consp mr-b)
                  (markerp (car mr-a)) (markerp (car mr-b)))
             (= (marker-position (car mr-a))
                (marker-position (car mr-b)))
           t))))

(defun helixel--jump-log-cap ()
  "Truncate `helixel--global-jump-log' to `helixel-jump-log-max'."
  (when (> (length helixel--global-jump-log) helixel-jump-log-max)
    (let ((tail (nthcdr helixel-jump-log-max helixel--global-jump-log)))
      (dolist (e tail)
        (when-let* ((mr (plist-get e :mark-region))
                    ((consp mr)))
          (set-marker (car mr) nil)
          (set-marker (cdr mr) nil))))
    (setcdr (nthcdr (1- helixel-jump-log-max)
                    helixel--global-jump-log)
            nil)))

(defun helixel--global-jump-log-push (event)
  "Push jump info from EVENT to `helixel--global-jump-log'.
Only pushes if EVENT's :category is in `helixel-jump-categories'.
Creates independent marker copy; the jump-log entry is lightweight."
  (when (and event
             (memq (helixel-action-category event) helixel-jump-categories)
             ;; Don't pollute the global (cross-buffer) jump log
             ;; with events committed during fake-cursor dispatch.
             (not (helixel-replay-in-fake-p)))
    (let* ((src-mr (helixel-action-mark-region event))
           (buf (if (and (consp src-mr) (markerp (car src-mr)))
                    (marker-buffer (car src-mr))
                  (current-buffer)))
           (entry `(:mark-region ,(when (consp src-mr)
                                    (cons (copy-marker (car src-mr))
                                          (copy-marker (cdr src-mr) t)))
                    :buffer ,buf
                    :category ,(helixel-action-category event)
                    :subcat ,(helixel-action-subcat event))))
      (unless (helixel--jump-same-content-p
               entry (car helixel--global-jump-log))
        (push entry helixel--global-jump-log)
        (setq helixel--jump-pos nil)
        (helixel--jump-log-cap)))))


;; ----------------------------------------------------------------------
;; Shared cleanup
;;

(defvar rectangle-mark-mode)            ; defined in rect.el

(defun helixel--clear-data ()
  "Clear any intermediate data, e.g. selections/mark.
Used by state machine, surround, and jump navigation."
  (setq helixel--raw-selection-type nil)
  (setq helixel--action-pos nil)
  (setq helixel--pending-sel nil)
  (when rectangle-mark-mode
    (rectangle-mark-mode -1))
  (deactivate-mark))


;; ----------------------------------------------------------------------
;; Action cycle (`;') and global jump list (C-o / C-i)
;; ----------------------------------------------------------------------
;;
;; Thin consumers of `helixel--event-ring' and `helixel--global-jump-log'.
;; `helixel-action-cycle' (`;') navigates session start positions within
;; the current buffer; `helixel-jump-backward' / `helixel-jump-forward'
;; (C-o / C-i) navigate across buffers.  Both use the generic
;; grouped-ring helpers in `helixel-core' (Part 10).


;; ----------------------------------------------------------------------
;; Mark region helpers (used by movement commands + action cycle)
;; ----------------------------------------------------------------------

(defun helixel--compute-mark-bounds (thing &optional outer-p)
  "Compute mark bounds for THING at point.
THING is a thingatpt symbol (e.g. \='helixel-word, \='helixel-symbol).
If OUTER-P is non-nil, include trailing whitespace.
Returns (BEG . END) or nil if no bounds found."
  (when-let* ((b (bounds-of-thing-at-point thing)))
    (if outer-p
        (save-excursion
          (goto-char (cdr b))
          (skip-chars-forward " \t")
          (cons (car b) (point)))
      (cons (car b) (cdr b)))))

(defun helixel--set-mark-region (thing-or-bounds &optional outer-p)
  "Set the \=:mark-region slot of `helixel--live-action'.
If THING-OR-BOUNDS is a cons (BEG . END), use it as pre-computed bounds.
If it is a thingatpt symbol, compute bounds via
`helixel--compute-mark-bounds' at point.
OUTER-P only applies when THING-OR-BOUNDS is a symbol.
No-op if action tracking is inhibited, no live event exists,
or bounds are nil.

The mark-region is a cons of two markers (START . END).
These survive buffer edits and are used by the action cycle (`\;')
to mark the region without re-computing bounds.

Old markers are freed before replacement to prevent leaks."
  (when (and (not (helixel-replaying-p))
             helixel--live-action)
    (let* ((old (helixel-action-mark-region helixel--live-action))
           (bounds (if (consp thing-or-bounds)
                       thing-or-bounds
                     (save-excursion
                       (goto-char (car (helixel-action-mark-region
                                         helixel--live-action)))
                       (helixel--compute-mark-bounds
                        thing-or-bounds outer-p)))))
      (when bounds
        ;; Free old markers to prevent leaks.
        (when (consp old)
          (set-marker (car old) nil)
          (set-marker (cdr old) nil))
        (let ((beg-marker (copy-marker (car bounds)))
              (end-marker (copy-marker (cdr bounds) t)))
          (setf (helixel-action-mark-region helixel--live-action)
                (cons beg-marker end-marker)))))))

;; ----------------------------------------------------------------------
;; Custom groups
;; ----------------------------------------------------------------------

(defgroup helixel nil
  "Custom group for Helixel."
  :group 'helixel)

(defcustom helixel-action-cycle-categories
  '(movement textobj search find-char edit)
  "Event :category symbols that `;' (`helixel-action-cycle') navigates.
Categories not listed here are invisible during cycling."
  :type '(repeat symbol)
  :group 'helixel)

(defcustom helixel-semicolon-mark-thing
  '(movement textobj search find-char edit)
  "List controlling when the first `;' marks the full thing.
Each element is either a category symbol (matches all subcats)
or a cons (CATEGORY . SUBCAT) for precise matching.
The first `;' selects the full thing (word, pair, etc.) instead of
starting the action cycle.  The next `;' does the normal cycle.

Examples:
  \='(movement textobj)              -> all movement + textobj subcats
  \='((movement . pair) textobj)     -> only pair movements + all textobj
Set to nil to disable entirely."
  :type '(repeat (choice symbol (cons symbol symbol)))
  :group 'helixel)

(defun helixel--semicolon-mark-thing-p (event)
  "Return non-nil if mark-thing should fire for EVENT.
Consults `helixel-semicolon-mark-thing'."
  (cl-some
   (lambda (entry)
     (if (consp entry)
         (and (eq (helixel-action-category event) (car entry))
              (eq (helixel-action-subcat event) (cdr entry)))
       (eq (helixel-action-category event) entry)))
   helixel-semicolon-mark-thing))

;; ----------------------------------------------------------------------
;; State variables
;; ----------------------------------------------------------------------

(defvar helixel-jump-cleanup-function nil
  "Function called after a successful jump to clean up selection state.
Typically `helixel--clear-data'.")

;; ----------------------------------------------------------------------
;; Event display
;; ----------------------------------------------------------------------

(defun helixel-action-display-format (event)
  "Format `helixel-action' EVENT for display in cycling messages.
Uses `helixel-action-display' if set, otherwise builds from
category and subcat."
  (or (helixel-action-display event)
      (let ((cat (helixel-action-category event))
            (sub (helixel-action-subcat event)))
        (cond
         ((and (eq cat 'state) (eq sub 'cancel)) "C-g")
         (t (format "%s.%s" cat sub))))))

;; Generic grouped-ring helpers live in `helixel-core' (Part 10).

;; ----------------------------------------------------------------------
;; Marker jump helper
;; ----------------------------------------------------------------------

;; ----------------------------------------------------------------------
;; ; cycling — session jump within buffer
;; ----------------------------------------------------------------------

(defun helixel-action--cycle-visible-p (event)
  "Return non-nil if EVENT should be visible during `;' cycling."
  (memq (helixel-action-category event) helixel-action-cycle-categories))

(defun helixel-action--cycle-display (event pos ring)
  "Format cycling message for EVENT at POS in RING."
  (let* ((total (helixel-gr-visible-count
                 ring #'helixel-action--cycle-visible-p))
         (display-pos (1+ (cl-loop for i from 0 below pos
                                   count (helixel-action--cycle-visible-p
                                          (nth i ring))))))
    (format "[%d/%d] %s" display-pos total
            (helixel-action-display-format event))))

(defun helixel-action--push-sel-from-event (event)
  "Push a `helixel-sel' from EVENT for `.' repeat.
Preserves current \=`n\=' count by preferring
`helixel--pending-sel' \(which has up-to-date :n-count) over
the selection descriptor stored in EVENT.
Adds `:span t' so the strategy builder extends the region
to session-start, matching `;''s behaviour."
  (let ((pending helixel--pending-sel)
        (event-sel (helixel-action-sel event))
        sel)
    (cond
     ((and pending event-sel
           (eq (helixel-sel-kind pending)
               (helixel-sel-kind event-sel)))
      (setq sel (helixel-sel--copy pending)))
     (event-sel
      (setq sel (helixel-sel--copy event-sel))))
    (when sel
      ;; Add :span for all kinds so recreates extend the region.
      ;; Movement handles :normal-mode internally when :span is set.
      (setq sel (helixel-sel-update-ctx sel :span t))
      (helixel--sel-push sel))
    sel))

(defun helixel-action--cycle-mark-region (event first-call)
  "Mark the region for EVENT during `;' cycling.
If EVENT has a non-degenerate :mark-region and matches
`helixel-semicolon-mark-thing', and FIRST-CALL is non-nil,
activate a real region pointing at the far edge from point
and return t (did-mark).  Otherwise just push the mark to the
begin marker and return nil."
  (let* ((mr (helixel-action-mark-region event))
         (a (marker-position (car mr)))
         (b (marker-position (cdr mr)))
         (degenerate (= a b)))
    (if (and (helixel--semicolon-mark-thing-p event)
             first-call
             (not degenerate))
        (let ((p (point)))
          (push-mark (if (> (abs (- p a)) (abs (- p b))) a b) t t)
          (activate-mark)
          t)
      (push-mark a t t)
      nil)))

(defun helixel-action--cycle-show (pos ring)
  "Show the group-start entry for the group containing RING[POS].
If the event has a non-degenerate :mark-region and
`helixel-semicolon-mark-thing' matches the event, mark the region
using the pre-computed markers.

If the jump results in no useful region change and no marking
was performed, automatically advance to the next older event.

Thin orchestrator after step 15 — work split into
`helixel-action--cycle-mark-region',
`helixel-action--push-sel-from-event' and
`helixel-action--cycle-auto-advance'."
  (let* ((gpos (helixel-gr-group-start ring pos
                 #'helixel-action--same-group-p))
         (event (nth gpos ring))
         (newest-pos (helixel-gr-group-newest ring pos
                       #'helixel-action--same-group-p))
         (sel-event (if (= newest-pos gpos) event (nth newest-pos ring)))
         (first-call (null helixel--action-pos)))
    (setq helixel--action-pos gpos)
    (let ((did-mark (helixel-action--cycle-mark-region event first-call)))
      (helixel-action--push-sel-from-event sel-event)
      (message "%s" (helixel-action--cycle-display event gpos ring))
      ;; Auto-advance: skip events that produce no useful region change.
      (helixel-action--cycle-auto-advance did-mark first-call))))

(defun helixel-action--same-group-p (a b)
  "Return non-nil if `helixel-action' structs A and B share a group.
Two events are in the same group when they share both
category and subcat."
  (and a b
       (eq (helixel-action-category a) (helixel-action-category b))
       (eq (helixel-action-subcat a) (helixel-action-subcat b))))

(defun helixel-action--cycle-auto-advance (did-mark first-call)
  "Auto-advance the action cycle when `;' produced no useful change.
DID-MARK is non-nil when mark-thing selected a region.
FIRST-CALL is non-nil when this is the first `;' after a movement.

When the current event doesn't change point or the region, skip
forward to the next older event to avoid cycling through dead spots."
  (when (and (not (use-region-p))
             (not did-mark)
             (not first-call))
    (helixel--action-cycle)))

(defun helixel-action-cycle (&optional arg)
  "Cycle through `helixel--event-ring' entries with `;'.
If a pair-movement was the last command, the first `;' jumps to
the event and marks the full span (first-`;'-after-motion style).
Second `;' does the normal action cycle.

Optional prefix ARG is passed to the underlying commands."
  (interactive "P")
  (unless (eq last-command 'helixel-action-cycle)
    (setq helixel--action-pos nil))
  (helixel--action-cycle arg))

(defun helixel--action-cycle (&optional arg)
  "Internal: cycle logic without `last-command' guard.
Called by `helixel-action-cycle' and recursive auto-advance.
Optional prefix ARG is passed to the underlying commands."
  ;; Normal action cycle — marking is handled inline when showing
  ;; events that have a non-degenerate :mark-region.
  (if arg
      ;; C-u ; → go forward (newer)
      (cond
       ((and helixel--action-pos (> helixel--action-pos 0))
        (let* ((newest (helixel-gr-group-newest
                        helixel--event-ring helixel--action-pos
                        #'helixel-action--same-group-p))
               (prev (when (> newest 0)
                       (helixel-gr-visible-index
                        helixel--event-ring (1- newest)
                        #'helixel-action--cycle-visible-p))))
          (if prev
              (helixel-action--cycle-show prev helixel--event-ring)
            (message "At newest"))))
       ((eq helixel--action-pos 0)
        (if helixel--live-action
            (progn
              (setq helixel--action-pos nil)
              (push-mark (car (helixel-action-mark-region
                                  helixel--live-action)) t t)
              (message "[live] %s"
                       (helixel-action-display-format helixel--live-action)))
          (message "At newest")))
       (t (message "At newest")))
    ;; ; → go back (older)
    (cond
     (helixel--action-pos
      (let ((pos (helixel-gr-find
                  helixel--event-ring helixel--action-pos 1
                  #'helixel-action--cycle-visible-p)))
        (if pos
            (helixel-action--cycle-show pos helixel--event-ring)
          ;; No older group: jump to current group-start marker
          ;; to expand the visible region (first-`;' span wrap).
          (let ((gpos (helixel-gr-group-start
                       helixel--event-ring helixel--action-pos
                       #'helixel-action--same-group-p)))
            (push-mark (car (helixel-action-mark-region
                                (nth gpos helixel--event-ring))) t t)
            (message "%s"
                     (helixel-action--cycle-display
                      (nth gpos helixel--event-ring)
                      gpos helixel--event-ring))))))
     (helixel--live-action
      ;; Commit live event first, then show ring[0]
      (helixel-action-commit)
      (let ((pos (helixel-gr-visible-index
                  helixel--event-ring 0
                  #'helixel-action--cycle-visible-p)))
        (if pos
            (helixel-action--cycle-show pos helixel--event-ring)
          (message "No saved actions"))))
     (helixel--event-ring
      (let ((pos (helixel-gr-visible-index
                  helixel--event-ring 0
                  #'helixel-action--cycle-visible-p)))
        (if pos
            (helixel-action--cycle-show pos helixel--event-ring)
          (message "No saved actions"))))
     (t (message "No saved actions")))))

;; ----------------------------------------------------------------------
;; Global jump list (C-o / C-i)
;; ----------------------------------------------------------------------

(defun helixel-register-jump (&optional category subcat)
  "Register current point in `helixel--global-jump-log'.
CATEGORY defaults to `user', SUBCAT defaults to `jump'."
  (let ((cat (or category 'user))
        (sub (or subcat 'jump)))
    (helixel--global-jump-log-push
     (make-helixel-action
      :category cat
      :subcat sub
      :mark-region (let ((pm (point-marker))) (cons pm (copy-marker pm t)))
      :timestamp (float-time)
      :buffer (current-buffer)))))

(defun helixel-define-jump-command (symbol)
  "Mark SYMBOL as a jump command.
Adds :before advice to record position before SYMBOL runs."
  (advice-add symbol :before
              (lambda (&rest _)
                (deactivate-mark t)
                (helixel-register-jump 'goto 'jump))
              '((name . helixel-jump--before))))

;; ── Jump cycle predicates ──

(defun helixel--jump-visible-p (entry)
  "Return non-nil if jump log ENTRY is visible during cycling."
  (and (memq (plist-get entry :category) helixel-jump-cycle-categories)
       (let ((mr (plist-get entry :mark-region))
             (buf (plist-get entry :buffer)))
         (and (consp mr) (markerp (car mr))
              (marker-buffer (car mr)) (buffer-live-p buf)))))

(defun helixel--jump-same-group-p (a b)
  "Return non-nil if A and B belong to the same jump group."
  (and a b
       (eq (plist-get a :category) (plist-get b :category))
       (eq (plist-get a :subcat) (plist-get b :subcat))
       (eq (plist-get a :buffer) (plist-get b :buffer))))

(defun helixel--jump-goto (pos)
  "Go to the group-start of jump entry at POS, switching buffers as needed."
  (let* ((gpos (helixel-gr-group-start helixel--global-jump-log pos
                 #'helixel--jump-same-group-p))
         (entry (nth gpos helixel--global-jump-log)))
    (while (and (not (helixel--jump-visible-p entry))
                (> gpos 0)
                (helixel--jump-same-group-p
                 (nth (1- gpos) helixel--global-jump-log) entry))
      (cl-decf gpos)
      (setq entry (nth gpos helixel--global-jump-log)))
    (let ((buf (plist-get entry :buffer))
          (mr (plist-get entry :mark-region)))
      (when (and (consp mr) (markerp (car mr))
                 (marker-buffer (car mr)) (buffer-live-p buf))
        (let ((cross-buffer (not (eq buf (current-buffer)))))
          (setq helixel--jump-pos gpos)
          (when cross-buffer
            (switch-to-buffer buf))
          (goto-char (marker-position (car mr)))
          (when (consp mr)
            (push-mark (car mr) t t)
            (goto-char (cdr mr))
            (activate-mark))
          (when (functionp helixel-jump-cleanup-function)
            (funcall helixel-jump-cleanup-function))
          t)))))

(defun helixel-jump-backward ()
  "Jump to previous (older) position in `helixel--global-jump-log'."
  (interactive)
  (let* ((saved-pos helixel--jump-pos))
    (helixel-register-jump 'jump 'return)
    (setq helixel--jump-pos (if saved-pos (1+ saved-pos) nil))
    (let* ((start (if helixel--jump-pos helixel--jump-pos 0))
           (pos (helixel-gr-find
                 helixel--global-jump-log start 1
                 #'helixel--jump-visible-p))
           (found nil))
      (while pos
        (if (helixel--jump-goto pos)
            (setq found t pos nil)
          (setq helixel--jump-pos pos
                pos (helixel-gr-find
                     helixel--global-jump-log pos 1
                     #'helixel--jump-visible-p))))
      (unless found
        (message (if helixel--jump-pos "At oldest" "No jump positions"))))))

(defun helixel-jump-forward ()
  "Jump to next (newer) position in `helixel--global-jump-log'."
  (interactive)
  (if helixel--jump-pos
      (let ((newest (helixel-gr-group-newest
                     helixel--global-jump-log helixel--jump-pos
                     #'helixel--jump-same-group-p))
            (pos nil))
        (while (and (not pos) (> newest 0))
          (setq pos (helixel-gr-visible-index
                     helixel--global-jump-log (1- newest)
                     #'helixel--jump-visible-p))
          (when pos
            (let ((success (helixel--jump-goto pos)))
              (unless success
                (setq helixel--jump-pos pos
                      newest pos
                      pos nil)))))
        (unless pos
          (message "At newest")))
    (message "At newest")))


(provide 'helixel-ring)
;;; helixel-ring.el ends here
