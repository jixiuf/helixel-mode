;;; helixel-ring.el --- Event ring and jump log storage -*- lexical-binding: t; -*-

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

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Event storage layer + history navigation for helixel-mode.
;;
;; Two storage containers:
;;   1. buffer-local `helixel--action-ring' — serves
;;      \\[helixel-action-cycle\\] cycling,
;;      \\[helixel-repeat-edit\\]/\\[helixel-repeat-last-motion\\] repeat,
;;      and history selection.
;;   2. global `helixel--global-jump-log' — serves
;;      \\[helixel-jump-backward\\]/\\[helixel-jump-forward\\] jump
;;      navigation across buffers.
;;
;; Provides:
;;   - the unified tracking entry point `helixel--tracking-open' used by
;;     all command-definition macros and live-event management helpers;
;;   - the \\[helixel-action-cycle\\] action-cycle commands and the
;;     \\[helixel-jump-backward\\]/\\[helixel-jump-forward\\] jump commands
;;     (consumers of the two containers above).

;;; Code:

(require 'cl-lib)
(require 'helixel-core)

;; ----------------------------------------------------------------------
;; Custom groups
;; ----------------------------------------------------------------------

(defgroup helixel nil
  "Custom group for Helixel."
  :group 'helixel)

(defcustom helixel-action-cycle-categories
  '(movement textobj search find-char
             (edit . copy) (edit . paste-after) (edit . paste-before)
             (edit . replace) (edit . yank-pop))
  "Event categories that \\[helixel-action-cycle\\] navigates.
Each element is either a category symbol (matches all subcats)
or a cons (CATEGORY . SUBCAT) for precise matching.
Categories not listed here are invisible during cycling.

Examples:
  \='(movement textobj)              -> all movement + textobj
  \='(movement textobj (edit . paste-after) (edit . replace)
     (edit . kill))
                                     -> movement, textobj, and only
                                        paste/replace/kill edits
Set to nil to disable entirely."
  :type '(repeat (choice symbol (cons symbol symbol)))
  :group 'helixel)

(defcustom helixel-action-cycle-newest-for-mark
  '(edit (movement . pair) (movement . match))
  "Control which categories use the newest event's mark-region.
For the first \\[helixel-action-cycle\\] marking in these categories,
the newest event's bounds are selected.

For categories listed here, the first
\\[helixel-action-cycle\\] in a multi-event group selects the bounds
of the *newest* event (e.g. after pppp, the first
\\[helixel-action-cycle\\] selects the last paste, second
\\[helixel-action-cycle\\] selects all 4 pastes).
For other categories, the first \\[helixel-action-cycle\\] uses the
group-start event to mark the span from the start of the sequence
\(e.g. after www, the first \\[helixel-action-cycle\\] marks from the
first word to point).

Each element is a category symbol (matches all subcats) or a
cons (CATEGORY . SUBCAT) for precise matching.

Sensible defaults:
  \\='(edit)          — each paste/replace is independent
  nil              — always use group-start event
  \\='(edit movement) — independent edits + sequential movements

Set to nil to always use the group-start event."
  :type '(repeat (choice symbol (cons symbol symbol)))
  :group 'helixel)

(defcustom helixel-semicolon-mark-thing
  '(movement textobj search find-char edit)
  "Choose when \\[helixel-action-cycle\\] marks the full span first.
Each element is either a category symbol (matches all subcats) or a
cons (CATEGORY . SUBCAT) for precise matching.
The first \\[helixel-action-cycle\\] selects the full thing (word,
pair, etc.) instead of starting the action cycle.  The next
\\[helixel-action-cycle\\] does the normal cycle.

Examples:
  \='(movement textobj)              -> all movement + textobj subcats
  \='((movement . pair) textobj)     -> only pair movements + all textobj
Set to nil to disable entirely."
  :type '(repeat (choice symbol (cons symbol symbol)))
  :group 'helixel)

(defcustom helixel-action-ring-max 50
  "Maximum number of events stored in `helixel--action-ring'."
  :type 'integer
  :group 'helixel)

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

;; ----------------------------------------------------------------------
;; State variables
;; ----------------------------------------------------------------------

(defvar-local helixel--action-pos nil
  "Ring position for \\[helixel-action-cycle\\] cycling.
nil = live event.  0 = newest ring entry.  N = older.")

(defvar helixel--cycle-jump-p nil
  "Non-nil during \\[helixel-action-cycle-mark-start\\].
Disables the mark-thing path internally.
Internal dynvar — see `helixel-action-cycle-mark-start'.")

(defsubst helixel--cycle-mark-thing-p ()
  "Return non-nil if the current cycle mode should select the full span.
Returns t for \\[helixel-action-cycle\\] (mark-thing), nil for
\\[helixel-action-cycle-mark-start\\] (jump cycle).
Delegates to the inverse of `helixel--cycle-jump-p'."
  (not helixel--cycle-jump-p))

(defvar-local helixel--mark-cycle-pos nil
  "Ring position for \\[helixel-action-cycle-mark-start\\] cycling.
nil = not cycling.  0 = newest ring entry.  N = older.
\\[helixel-action-cycle\\] and \\[helixel-action-cycle-mark-start\\]
use separate positions so the two navigation modes are independent.")

;; ----------------------------------------------------------------------
;; Buffer-local event ring
;; ----------------------------------------------------------------------


(defvar-local helixel--action-ring nil
  "Event ring, most recent first.  Capped at `helixel-action-ring-max'.
Each entry is a `helixel-action' struct.
Shared by session jump (\\[helixel-action-cycle\\]), repeat
\(\\[helixel-repeat-edit\\]/\\[helixel-repeat-last-motion\\]), and history
\(\\[universal-argument\\] \\[helixel-search-repeat-next\\]).")

(defvar-local helixel--live-action nil
  "The currently in-progress `helixel-action'.
Set at command start, committed to ring when complete.")

;; `helixel-last-action' is defined in helixel-core.el.
;; It is available transitively through the require chain.

(defconst helixel--sel-categories '(movement search find-char textobj)
  "Event categories that carry a selection descriptor.
Used by `helixel--action-commit' to sync `helixel--pending-sel'
into the committed event's :sel slot when the event's own :sel
is nil.  Categories not listed here never carry a pending-sel.")

(defun helixel-action--ring-cap ()
  "Truncate `helixel--action-ring' to `helixel-action-ring-max' entries.
Releases markers of evicted entries to prevent leaks."
  (when (> (length helixel--action-ring) helixel-action-ring-max)
    (let ((tail (nthcdr helixel-action-ring-max helixel--action-ring)))
      (dolist (e tail)
        (helixel-action--release-markers e))
      (setcdr (nthcdr (1- helixel-action-ring-max)
                      helixel--action-ring)
              nil))))

(defvar helixel-action-commit-hook nil
  "Abnormal hook run by `helixel--action-commit' after pushing to the ring.
Each function receives one argument: the just-committed
`helixel-action' (the deep-copied entry now sitting at the front
of `helixel--action-ring').

Used by chain recording (`helixel-chain.el') to accumulate the
list of txs run during the chain; the chain transaction simply
replays each tx in order.

Keep handlers fast — this fires on every command that commits an
action.")

(defun helixel--action-commit ()
  "Commit `helixel--live-action' to `helixel--action-ring'.
Deep-copies the event (marker + sel) so ring entries are independent.
Deduplicates against the ring front — same (op sel payload) skips push.
Also mirrors to `helixel--global-jump-log'.
Sets `helixel-last-action' to the committed entry.
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
      (unless (and (car helixel--action-ring)
                   (helixel-action--same-content-p
                    entry (car helixel--action-ring)))
        (push entry helixel--action-ring)
        (helixel-action--ring-cap))
      ;; `helixel-last-action' tracks the most recent EDIT for
      ;; \\[helixel-repeat-edit] replay.
      ;; Movement txs (op = nil, runner-only) participate in mc dispatch
      ;; but must NOT advance last-action — that would shadow the prior
      ;; edit and break dot-repeat semantics.  The op-presence check
      ;; distinguishes real edits (kill, change, insert-text, …) from
      ;; mc-replay movement shims.
      (when-let* (((helixel-action-op entry)))
        (setq helixel-last-action entry))
      (helixel--global-jump-log-push entry)
      (helixel-action--release-markers helixel--live-action)
      (setq helixel--live-action nil)
      (run-hook-with-args 'helixel-action-commit-hook entry)
      entry)))

;; ── Group-span on-the-fly computation ──
;; Compute bounding box at query time by iterating all events in the
;; group.  Each event's mark-region markers already track buffer
;; changes, so min(cars) / max(cdrs) always give the correct extent.
;; No pre-computation, no hooks, no payload markers to clean up.

(defun helixel--compute-group-span (ring newest-pos gpos)
  "Return (MIN . MAX) bounding box of events in RING from NEWEST-POS to GPOS.
Both values are integer positions.  Scans every event's mark-region;
non-degenerate regions contribute car and cdr, degenerate ones
contribute just a point.  Returns nil if no usable mark-regions are
found."
  (let ((min-pos most-positive-fixnum)
        (max-pos most-negative-fixnum))
    (cl-loop for i from newest-pos to gpos
             for mr = (helixel-action-mark-region (nth i ring))
             when (and mr (consp mr)
                       (markerp (car mr)) (markerp (cdr mr)))
             do (setq min-pos (min min-pos (marker-position (car mr))))
             (setq max-pos (max max-pos (marker-position (cdr mr)))))
    (when (< min-pos most-positive-fixnum)
      (cons min-pos max-pos))))

;; ── Live-event helpers ──

(defun helixel--cancel-action ()
  "Cancel the current action via \\[keyboard-quit].
Commits meaningful events, pushes a state/cancel sentinel,
and clears the live state."
  (helixel--action-commit)
  ;; Push cancel sentinel for dedup boundary
  (setq helixel--live-action
        (make-helixel-action
         :category 'state
         :subcat 'cancel
         :mark-region (let ((pm (point-marker)))
                        (cons pm (copy-marker pm t)))
         :timestamp (float-time)
         :buffer (current-buffer)))
  (helixel--action-commit))

(defun helixel--live-action-set (tx)
  "Copy TX's replay slots onto `helixel--live-action'.
TX is a `helixel-action' carrying replay data (op/sel/payload/runner
/preposition/mark-region/display) produced by `helixel-action-create'
or equivalent.  No-op if no live action or TX isn't an action.

Preserves any existing `preposition' on the live action unless TX
provides its own (used by insert-entry commands whose `:preposition'
attaches a prepos function before `record-action' runs)."
  (when (and helixel--live-action (helixel-action-p tx))
    (let ((existing-pre (helixel-action-preposition helixel--live-action))
          (old-mr (helixel-action-mark-region helixel--live-action)))
      (setf (helixel-action-op           helixel--live-action)
            (helixel-action-op tx))
      (setf (helixel-action-sel          helixel--live-action)
            (helixel-action-sel tx))
      (setf (helixel-action-payload      helixel--live-action)
            (helixel-action-payload tx))
      (setf (helixel-action-runner       helixel--live-action)
            (helixel-action-runner tx))
      (setf (helixel-action-preposition helixel--live-action)
            (or (helixel-action-preposition tx) existing-pre))
      ;; Only overwrite mark-region with tx's if the existing one is
      ;; degenerate (default from tracking-open).  If a command has
      ;; deliberately set a meaningful mark-region (e.g., paste
      ;; bounds via `helixel--set-mark-region'), preserve it.
      (when-let* ((tx-mr (helixel-action-mark-region tx))
                  ((consp tx-mr))
                  ((or (null old-mr) (not (consp old-mr))
                       (and (markerp (car old-mr)) (markerp (cdr old-mr))
                            (= (marker-position (car old-mr))
                               (marker-position (cdr old-mr)))))))
        (when (consp old-mr)
          (when (markerp (car old-mr)) (set-marker (car old-mr) nil))
          (when (markerp (cdr old-mr)) (set-marker (cdr old-mr) nil)))
        (setf (helixel-action-mark-region helixel--live-action) tx-mr))
      (when-let* ((d (helixel-action-display tx)))
        (setf (helixel-action-display helixel--live-action) d)))))

;; ── Unified entry point: open event (commit prev, create new) ──

(defun helixel--tracking-open (category subcat &optional op)
  "Commit previous `helixel--live-action' and create a new one.
CATEGORY and SUBCAT classify the event for \\[helixel-action-cycle\\]
and jump-list.
OP is an optional operator symbol (nil for movement/search).

No-op when `(helixel-replaying-p)` is non-nil (dot-repeat).
Does NOT commit the new event — caller is responsible for eventual commit."
  (unless (helixel-replaying-p)
    (helixel--action-commit)
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
           :start-point (point-marker)
           :timestamp (float-time)
           :buffer (current-buffer)
           :op op)
          helixel--action-pos nil)))

;; ----------------------------------------------------------------------
;; Global jump log (\\[helixel-jump-backward\\] / \\[helixel-jump-forward\\])
;; ----------------------------------------------------------------------

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
             (not (helixel--replay-in-fake-p)))
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

(defvar helixel-clear-data-hook nil
  "Hook run at the start of `helixel-clear-data'.
Modules can add functions here to perform cleanup before
selection data is cleared.  For example, `helixel-state.el'
adds a function to exit visual state.")

(defun helixel-clear-data-internal ()
  "Clear selection data without running `helixel-clear-data-hook'.
Called directly by `helixel--switch-state' to avoid triggering
hook functions (like visual exit) that would re-enter state switching.
All other callers should use `helixel-clear-data'."
  (setq helixel--sel-type-override nil)
  (setq helixel--action-pos nil)
  (setq helixel--pending-sel nil)
  (when rectangle-mark-mode
    (rectangle-mark-mode -1))
  (deactivate-mark))

(defun helixel-clear-data ()
  "Clear any intermediate data, e.g. selections/mark.
Used by state machine, surround, and jump navigation."
  (run-hooks 'helixel-clear-data-hook)
  (helixel-clear-data-internal))


;; ----------------------------------------------------------------------
;; Action cycle (\\[helixel-action-cycle\\]) and global jump list
;; (\\[helixel-jump-backward\\] / \\[helixel-jump-forward\\])
;; ----------------------------------------------------------------------
;;
;; Thin consumers of `helixel--action-ring' and `helixel--global-jump-log'.
;; \\[helixel-action-cycle\\] navigates session start positions within
;; the current buffer; \\[helixel-jump-backward\\] /
;; \\[helixel-jump-forward\\] navigate across buffers.  Both use the generic
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

(defun helixel-action--cycle-mark-group-span (ring pos)
  "Mark the full group span for the group containing RING[POS].
Computes the bounding box of all events in the group on-the-fly
via `helixel--compute-group-span', pushes mark to the start, and
moves point to the end.  Returns the group-start position."
  (let* ((gpos (helixel--gr-group-start ring pos
                                        #'helixel-action--same-group-p))
         (grp-event (nth gpos ring))
         (newest-pos (helixel--gr-group-newest ring pos
                                               #'helixel-action--same-group-p))
         (span (helixel--compute-group-span ring newest-pos gpos)))
    (when span
      (push-mark (car span) t t)
      (goto-char (cdr span))
      (activate-mark))
    (message "%s" (helixel-action--cycle-display grp-event gpos ring))
    gpos))

(defun helixel-action--newest-for-mark-p (event)
  "Return non-nil if EVENT should use the newest event for ; marking.
Consults `helixel-action-cycle-newest-for-mark'."
  (helixel--category-match-p
   (helixel-action-category event)
   (helixel-action-subcat event)
   helixel-action-cycle-newest-for-mark))

(defun helixel--semicolon-mark-thing-p (event)
  "Return non-nil if mark-thing should fire for EVENT.
Consults `helixel-semicolon-mark-thing'."
  (helixel--category-match-p
   (helixel-action-category event)
   (helixel-action-subcat event)
   helixel-semicolon-mark-thing))

;; ----------------------------------------------------------------------
;; State variables
;; ----------------------------------------------------------------------

(defvar helixel-jump-cleanup-function nil
  "Function called after a successful jump to clean up selection state.
Typically `helixel-clear-data'.")

;; ----------------------------------------------------------------------
;; Event display
;; ----------------------------------------------------------------------

(defun helixel--action-display-format (event)
  "Format `helixel-action' EVENT for display in cycling messages.
Uses `helixel-action-display' if set, otherwise tries the
selection descriptor's display, and finally falls back to
category and subcat."
  (or (helixel-action-display event)
      (when-let* ((sel (helixel-action-sel event))
                  (d (helixel-sel-call-display sel)))
        d)
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
  "Return non-nil if EVENT is visible during cycle.
Checks \\[helixel-action-cycle\\] cycling visibility.
Consults `helixel-action-cycle-categories', which supports both
category symbols (match all subcats) and (CATEGORY . SUBCAT) pairs."
  (helixel--category-match-p
   (helixel-action-category event)
   (helixel-action-subcat event)
   helixel-action-cycle-categories))

(defun helixel-action--cycle-display (event pos ring)
  "Format cycling message for EVENT at POS in RING."
  (let* ((total (helixel--gr-visible-count
                 ring #'helixel-action--cycle-visible-p))
         (display-pos (1+ (cl-loop for i from 0 below pos
                                   count (helixel-action--cycle-visible-p
                                          (nth i ring))))))
    (format "[%d/%d] %s" display-pos total
            (helixel--action-display-format event))))

(defun helixel-action--push-sel-from-event (event)
  "Push a `helixel-sel' from EVENT for \\[helixel-repeat-edit] repeat.
Preserves current \=`n\=' count by preferring
`helixel--pending-sel' \(which has up-to-date :n-count) over
the selection descriptor stored in EVENT.
Adds `:span t' so the strategy builder extends the region
to session-start, matching \\[helixel-action-cycle\\]'s behaviour."
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

(defun helixel-action--cycle-mark-region (event mr first-call)
  "Mark the region during \\[helixel-action-cycle\\] cycling.
Uses mark-region MR from EVENT.
MR is a cons (START . END) of two markers or two integers.
If FIRST-CALL is non-nil, MR is non-degenerate,
`helixel--cycle-mark-thing-p' returns non-nil, and EVENT matches
`helixel-semicolon-mark-thing', activate a real region pointing at
the far edge from point (mark-thing) and return t (did-mark).
Otherwise just push the mark to the begin marker and return nil.

When `helixel--cycle-mark-thing-p' returns nil (from
\\[helixel-action-cycle-mark-start\\]), the
mark-thing path is skipped entirely — every call is non-mark-thing."
  (let* ((a (if (markerp (car mr))
                (marker-position (car mr))
              (car mr)))
         (b (if (markerp (cdr mr))
                (marker-position (cdr mr))
              (cdr mr)))
         (degenerate (= a b)))
    (if (and (helixel--cycle-mark-thing-p)
             (helixel--semicolon-mark-thing-p event)
             first-call
             (not degenerate))
        (let ((p (point)))
          (push-mark (if (> (abs (- p a)) (abs (- p b))) a b) t t)
          (activate-mark)
          ;; When the mark-region extends one char past point and
          ;; that char is a close delimiter (e.g. \=`\=' after
          ;; \=`%\='), extend the highlighted region so the close
          ;; char is visible in the selection.
          (when (and (= (1+ p) b)
                     (memq (char-after p)
                           (helixel--active-delim-chars :close-only t)))
            (goto-char b)
            (activate-mark))
          t)
      (push-mark a t t)
      nil)))

(defun helixel-action--cycle-compute-mark-region
    (ring gpos newest-pos event mark-event multi-event-p use-newest)
  "Compute the mark-region for cycle-show at RING[GPOS].
RING is the action ring, GPOS the group-start index, NEWEST-POS
the newest index in the group, EVENT the group-start action,
MARK-EVENT the event whose mark-region to use, MULTI-EVENT-P
non-nil when the group has multiple events, USE-NEWEST non-nil
when the category prefers the newest event's bounds.

Returns a cons (START . END) of markers or integers.

For the first \\=`\\;\\=' press on a `newest-for-mark' category,
uses the newest event's own mark-region (select just the last
paste).  For other cases, computes the full group span on-the-fly
via `helixel--compute-group-span'.

When `helixel--cycle-mark-thing-p' returns nil (jump-cycle mode),
replaces the START with the group-start event's `start-point'
marker — pushing mark to the original pre-motion cursor position
instead of the movement span start."
  (let* ((own-mr (helixel-action-mark-region mark-event))
         (own-mr (and own-mr
                      (not (= (marker-position (car own-mr))
                              (marker-position (cdr own-mr))))
                      own-mr))
         (group-mr (when multi-event-p
                     (helixel--compute-group-span
                      ring newest-pos gpos)))
         (raw-mr
          (if multi-event-p
              (if use-newest
                  (or own-mr group-mr
                      (let ((fallback (helixel-action-mark-region
                                       event)))
                        (and fallback
                             (not (= (marker-position (car fallback))
                                     (marker-position (cdr fallback))))
                             fallback)))
                (or group-mr
                    (helixel-action-mark-region mark-event)))
            (helixel-action-mark-region mark-event))))
    (if (helixel--cycle-mark-thing-p)
        raw-mr
      (cons (or (when-let* ((sp (helixel-action-start-point
                                 (nth gpos ring)))
                            ((markerp sp)))
                  (marker-position sp))
                (helixel--cycle-mark-start event))
            (cdr raw-mr)))))

(defun helixel-action--cycle-show (pos ring)
  "Show the group-start entry for the group containing RING[POS].
If the event has a non-degenerate :mark-region, mark the region
using the pre-computed markers (mark-thing on first call).

If the jump results in no useful region change and no marking
was performed, automatically advance to the next older event."
  (let* ((gpos (helixel--gr-group-start ring pos
                                        #'helixel-action--same-group-p))
         (event (nth gpos ring))
         (newest-pos (helixel--gr-group-newest ring pos
                                               #'helixel-action--same-group-p))
         (multi-event-p (not (= newest-pos gpos)))
         (sel-event (if multi-event-p (nth newest-pos ring) event))
         (first-call (null helixel--action-pos))
         (use-newest (and multi-event-p
                          (helixel-action--newest-for-mark-p event)))
         (mark-event (if use-newest sel-event event))
         (mr (helixel-action--cycle-compute-mark-region
              ring gpos newest-pos event mark-event
              multi-event-p use-newest)))
    ;; For newest-for-mark categories with multiple events, set
    ;; action-pos to newest-pos so the next ; walks within the
    ;; same group (marking the full span) before going older.
    (setq helixel--action-pos
          (if use-newest newest-pos gpos))
    (let ((did-mark (helixel-action--cycle-mark-region
                     mark-event mr first-call)))
      (helixel-action--push-sel-from-event sel-event)
      (message "%s" (helixel-action--cycle-display event gpos ring))
      (helixel-action--cycle-auto-advance did-mark first-call))))

(defun helixel--cycle-mark-start (event)
  "Return the start marker/position for EVENT based on cycle mode.
When `helixel--cycle-mark-thing-p' returns nil
\\(\\[helixel-action-cycle-mark-start\\] mode), returns
EVENT's start-point (the original pre-motion cursor position).
Otherwise returns the car of EVENT's mark-region.
Falls back to mark-region car when start-point is nil."
  (if (helixel--cycle-mark-thing-p)
      (car-safe (helixel-action-mark-region event))
    (let ((sp (helixel-action-start-point event)))
      (if (and sp (markerp sp) (marker-buffer sp))
          sp
        (car-safe (helixel-action-mark-region event))))))

(defun helixel-action--same-group-p (a b)
  "Return non-nil if `helixel-action' structs A and B share a group.
Two events are in the same group when they share both
category and subcat."
  (and a b
       (eq (helixel-action-category a) (helixel-action-category b))
       (eq (helixel-action-subcat a) (helixel-action-subcat b))))

(defun helixel-action--cycle-auto-advance (did-mark first-call)
  "Auto-advance the action cycle to skip dead spots.
Called when \\[helixel-action-cycle\\] produced no useful change.
DID-MARK is non-nil when mark-thing selected a region.
FIRST-CALL is non-nil when this is the first
\\[helixel-action-cycle\\] after a movement.

When the current event doesn't change point or the region, skip
forward to the next older event to avoid cycling through dead spots."
  (when (and (not (use-region-p))
             (not did-mark)
             (not first-call))
    (helixel--action-cycle-backward)))

(defun helixel-action-cycle (&optional arg)
  "Cycle through `helixel--action-ring' entries.
Uses \\[helixel-action-cycle\\] at each step.
The first \\[helixel-action-cycle\\] after a movement selects the full
span (mark-thing).
Subsequent presses cycle to older events.

Optional prefix ARG is passed to the underlying commands."
  (interactive "P")
  (unless (eq last-command 'helixel-action-cycle)
    (setq helixel--action-pos nil))
  (helixel--action-cycle arg))

(defun helixel--action-cycle (&optional arg)
  "Internal: cycle logic without `last-command' guard.
Called by `helixel-action-cycle' and recursive auto-advance.
Optional prefix ARG is passed to the underlying commands."
  (if arg
      (helixel--action-cycle-forward)
    (helixel--action-cycle-backward)))

(defun helixel--action-cycle-forward ()
  "Step forward (newer) in `helixel--action-ring'.
Used by \\[universal-argument] \\[helixel-action-cycle\]."
  (cond
   ((and helixel--action-pos (> helixel--action-pos 0))
    (let* ((newest (helixel--gr-group-newest
                    helixel--action-ring helixel--action-pos
                    #'helixel-action--same-group-p))
           (prev (when (> newest 0)
                   (helixel--gr-visible-index
                    helixel--action-ring (1- newest)
                    #'helixel-action--cycle-visible-p))))
      (if prev
          (helixel-action--cycle-show prev helixel--action-ring)
        (message "At newest"))))
   ((eq helixel--action-pos 0)
    (if helixel--live-action
        (progn
          (setq helixel--action-pos nil)
          (push-mark (helixel--cycle-mark-start
                      helixel--live-action)
                     t t)
          (message "[live] %s"
                   (helixel--action-display-format helixel--live-action)))
      (message "At newest")))
   (t (message "At newest"))))

(defun helixel--action-cycle-backward ()
  "Step backward (older) in `helixel--action-ring'.
Used by \\[helixel-action-cycle\] and auto-advance."
  (cond
   (helixel--action-pos
    (let ((pos (helixel--gr-find
                helixel--action-ring helixel--action-pos 1
                #'helixel-action--cycle-visible-p)))
      (if pos
          (if (and (helixel--cycle-mark-thing-p)
                   (helixel-action--newest-for-mark-p
                    (nth helixel--action-pos helixel--action-ring))
                   (funcall #'helixel-action--same-group-p
                            (nth helixel--action-pos helixel--action-ring)
                            (nth pos helixel--action-ring)))
              (setq helixel--action-pos
                    (helixel-action--cycle-mark-group-span
                     helixel--action-ring pos))
            (helixel-action--cycle-show pos helixel--action-ring))
        ;; No older visible group: jump to current group-start marker.
        (let* ((gpos (helixel--gr-group-start
                      helixel--action-ring helixel--action-pos
                      #'helixel-action--same-group-p))
               (grp-event (nth gpos helixel--action-ring)))
          (if (and (helixel--cycle-mark-thing-p)
                   (helixel-action--newest-for-mark-p grp-event))
              (setq helixel--action-pos
                    (helixel-action--cycle-mark-group-span
                     helixel--action-ring helixel--action-pos))
            (let ((mr (helixel-action-mark-region grp-event)))
              (push-mark (if (helixel--cycle-mark-thing-p)
                             (car mr)
                           (helixel--cycle-mark-start grp-event))
                         t t)
              (message "%s" (helixel-action--cycle-display
                             grp-event gpos helixel--action-ring))))))))
   (helixel--live-action
    (helixel--action-commit)
    (let ((pos (helixel--gr-visible-index
                helixel--action-ring 0
                #'helixel-action--cycle-visible-p)))
      (if pos
          (helixel-action--cycle-show pos helixel--action-ring)
        (message "No saved actions"))))
   (helixel--action-ring
    (let ((pos (helixel--gr-visible-index
                helixel--action-ring 0
                #'helixel-action--cycle-visible-p)))
      (if pos
          (helixel-action--cycle-show pos helixel--action-ring)
        (message "No saved actions"))))
   (t (message "No saved actions"))))

;; ── Jump cycle (\\[helixel-action-cycle-mark-start\\]) ──
;;
;; \\[helixel-action-cycle-mark-start\\] shares the full
;; \\[helixel-action-cycle\\] cycle infrastructure (group navigation,
;; newest-for-mark, group-span computation, auto-advance) via
;; `helixel--action-cycle'.
;; It uses the same ring, visibility, and grouping as
;; \\[helixel-action-cycle\\].  The two
;; differences are:
;;   1. Marking: `helixel--cycle-mark-thing-p' returns nil, disabling
;;      the mark-thing path.  Every press pushes mark to the
;;      thing-start (non-mark-thing).
;;   2. Position: `helixel--action-pos' is let-bound from
;;      `helixel--mark-cycle-pos' so the two commands track their
;;      cycle positions independently.

(defun helixel-action-cycle-mark-start (&optional arg)
  "Cycle through event history, pushing mark to each event's start position.
Bound to \\[helixel-action-cycle-mark-start\\].  Unlike
\\[helixel-action-cycle\\] which selects the full movement span,
this command always pushes mark to the original pre-motion cursor
position (the start-position of each tracked action).

Shares the full \\[helixel-action-cycle\\] cycle infrastructure
\(group navigation,
newest-for-mark, group-span) but never selects the full span.

Optional prefix ARG reverses direction (go newer)."
  (interactive "P")
  (unless (eq last-command 'helixel-action-cycle-mark-start)
    (setq helixel--mark-cycle-pos nil))
  (let ((helixel--cycle-jump-p t)
        (helixel--action-pos helixel--mark-cycle-pos))
    ;; helixel--action-pos is let-bound from helixel--mark-cycle-pos
    ;; so the shared cycle logic reads/writes
    ;; \\[helixel-action-cycle-mark-start\\]'s own position.
    (unwind-protect
        (helixel--action-cycle arg)
      (setq helixel--mark-cycle-pos helixel--action-pos))))

;; ----------------------------------------------------------------------
;; Global jump list (\\[helixel-jump-backward\\] / \\[helixel-jump-forward\\])
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
  (let* ((gpos (helixel--gr-group-start helixel--global-jump-log pos
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
           (pos (helixel--gr-find
                 helixel--global-jump-log start 1
                 #'helixel--jump-visible-p))
           (found nil))
      (while pos
        (if (helixel--jump-goto pos)
            (setq found t pos nil)
          (setq helixel--jump-pos pos
                pos (helixel--gr-find
                     helixel--global-jump-log pos 1
                     #'helixel--jump-visible-p))))
      (unless found
        (message (if helixel--jump-pos "At oldest" "No jump positions"))))))

(defun helixel-jump-forward ()
  "Jump to next (newer) position in `helixel--global-jump-log'."
  (interactive)
  (if helixel--jump-pos
      (let ((newest (helixel--gr-group-newest
                     helixel--global-jump-log helixel--jump-pos
                     #'helixel--jump-same-group-p))
            (pos nil))
        (while (and (not pos) (> newest 0))
          (setq pos (helixel--gr-visible-index
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
