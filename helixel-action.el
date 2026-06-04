;;; helixel-action.el --- Session cycling & jump navigation  -*- lexical-binding: t; -*-

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
;; Thin consumers of the event ring and global jump log.
;;
;; `helixel-action-cycle' (`;') — navigates session start positions
;; within the current buffer using `helixel--event-ring'.
;;
;; `helixel-jump-backward' / `helixel-jump-forward' (C-o / C-i) —
;; navigate across buffers using `helixel--global-jump-log'.
;;
;; Both use generic grouped-ring helpers that work on any list.

;;; Code:

(require 'cl-lib)

(require 'helixel-core)
(require 'helixel-grouped-ring)
(require 'helixel-ring)

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
  "Set the \=:mark-region slot of `helixel--live-edit'.
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
             helixel--live-edit)
    (let* ((old (helixel-edit-mark-region helixel--live-edit))
           (bounds (if (consp thing-or-bounds)
                       thing-or-bounds
                     (save-excursion
                       (goto-char (car (helixel-edit-mark-region
                                         helixel--live-edit)))
                       (helixel--compute-mark-bounds
                        thing-or-bounds outer-p)))))
      (when bounds
        ;; Free old markers to prevent leaks.
        (when (consp old)
          (set-marker (car old) nil)
          (set-marker (cdr old) nil))
        (let ((beg-marker (copy-marker (car bounds)))
              (end-marker (copy-marker (cdr bounds) t)))
          (setf (helixel-edit-mark-region helixel--live-edit)
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
         (and (eq (helixel-edit-category event) (car entry))
              (eq (helixel-edit-subcat event) (cdr entry)))
       (eq (helixel-edit-category event) entry)))
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

(defun helixel-edit-display-format (event)
  "Format `helixel-edit' EVENT for display in cycling messages.
Uses `helixel-edit-display' if set, otherwise builds from
category and subcat."
  (or (helixel-edit-display event)
      (let ((cat (helixel-edit-category event))
            (sub (helixel-edit-subcat event)))
        (cond
         ((and (eq cat 'state) (eq sub 'cancel)) "C-g")
         (t (format "%s.%s" cat sub))))))

(defun helixel-action-display (event)
  "Format EVENT for display.  Delegates to `helixel-edit-display-format'."
  (helixel-edit-display-format event))

;; Generic grouped-ring helpers live in `helixel-grouped-ring'.

;; ----------------------------------------------------------------------
;; Marker jump helper
;; ----------------------------------------------------------------------

;; ----------------------------------------------------------------------
;; ; cycling — session jump within buffer
;; ----------------------------------------------------------------------

(defun helixel-action--cycle-visible-p (event)
  "Return non-nil if EVENT should be visible during `;' cycling."
  (memq (helixel-edit-category event) helixel-action-cycle-categories))

(defun helixel-action--cycle-display (event pos ring)
  "Format cycling message for EVENT at POS in RING."
  (let* ((total (helixel-gr-visible-count
                 ring #'helixel-action--cycle-visible-p))
         (display-pos (1+ (cl-loop for i from 0 below pos
                                   count (helixel-action--cycle-visible-p
                                          (nth i ring))))))
    (format "[%d/%d] %s" display-pos total
            (helixel-edit-display-format event))))

(defun helixel-action--push-sel-from-event (event)
  "Push a `helixel-sel' from EVENT for `.' repeat.
Preserves current \=`n\=' count by preferring
`helixel--pending-sel' \(which has up-to-date :n-count) over
the selection descriptor stored in EVENT.
Adds `:span t' so the strategy builder extends the region
to session-start, matching `;''s behaviour."
  (let ((pending helixel--pending-sel)
        (event-sel (helixel-edit-sel event))
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
  (let* ((mr (helixel-edit-mark-region event))
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
  (let* ((gpos (helixel-action--cycle-group-start pos ring))
         (event (nth gpos ring))
         (newest-pos (helixel-action--cycle-group-newest pos ring))
         (sel-event (if (= newest-pos gpos) event (nth newest-pos ring)))
         (first-call (null helixel--action-pos)))
    (setq helixel--action-pos gpos)
    (let ((did-mark (helixel-action--cycle-mark-region event first-call)))
      (helixel-action--push-sel-from-event sel-event)
      (message "%s" (helixel-action--cycle-display event gpos ring))
      ;; Auto-advance: skip events that produce no useful region change.
      (helixel-action--cycle-auto-advance did-mark first-call))))

(defun helixel-action--same-group-p (a b)
  "Return non-nil if `helixel-edit' structs A and B share a group.
Two events are in the same group when they share both
category and subcat."
  (and a b
       (eq (helixel-edit-category a) (helixel-edit-category b))
       (eq (helixel-edit-subcat a) (helixel-edit-subcat b))))

(defun helixel-action--cycle-group-start (pos ring)
  "Return the oldest index in RING of the group containing POS.
Uses `helixel-action--same-group-p' as the grouping predicate."
  (helixel-gr-group-start ring pos
    #'helixel-action--same-group-p))

(defun helixel-action--cycle-group-newest (pos ring)
  "Return the newest index in RING of the group containing POS.
Uses `helixel-action--same-group-p' as the grouping predicate."
  (helixel-gr-group-newest ring pos
    #'helixel-action--same-group-p))

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
        (let* ((newest (helixel-action--cycle-group-newest
                        helixel--action-pos helixel--event-ring))
               (prev (when (> newest 0)
                       (helixel-gr-visible-index
                        helixel--event-ring (1- newest)
                        #'helixel-action--cycle-visible-p))))
          (if prev
              (helixel-action--cycle-show prev helixel--event-ring)
            (message "At newest"))))
       ((eq helixel--action-pos 0)
        (if helixel--live-edit
            (progn
              (setq helixel--action-pos nil)
              (push-mark (car (helixel-edit-mark-region
                                  helixel--live-edit)) t t)
              (message "[live] %s"
                       (helixel-edit-display-format helixel--live-edit)))
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
          (let ((gpos (helixel-action--cycle-group-start
                       helixel--action-pos helixel--event-ring)))
            (push-mark (car (helixel-edit-mark-region
                                (nth gpos helixel--event-ring))) t t)
            (message "%s"
                     (helixel-action--cycle-display
                      (nth gpos helixel--event-ring)
                      gpos helixel--event-ring))))))
     (helixel--live-edit
      ;; Commit live event first, then show ring[0]
      (helixel-edit-commit)
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
     (make-helixel-edit
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

;; ── Jump display helpers ──

(defun helixel--jump-display (entry)
  "Format jump log ENTRY for display."
  (let ((cat (plist-get entry :category))
        (sub (plist-get entry :subcat))
        (buf (plist-get entry :buffer)))
    (format "%s.%s [%s]"
            (or cat ?\?)
            (or sub ?\?)
            (if (buffer-live-p buf)
                (buffer-name buf)
              "(dead)"))))

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

(defun helixel--jump-group-start (pos)
  "Return group-start index for jump entry at POS."
  (helixel-gr-group-start helixel--global-jump-log pos
    #'helixel--jump-same-group-p))

(defun helixel--jump-group-newest (pos)
  "Return newest index for jump group containing POS."
  (helixel-gr-group-newest helixel--global-jump-log pos
    #'helixel--jump-same-group-p))

(defun helixel--jump-message (pos)
  "Format and message the current jump position POS."
  (let* ((entry (nth pos helixel--global-jump-log))
         (total (helixel-gr-visible-count
                 helixel--global-jump-log #'helixel--jump-visible-p))
         (display-pos (1+ (cl-loop for i from 0 below pos
                                   count (helixel--jump-visible-p
                                          (nth i helixel--global-jump-log))))))
    (message "[%d/%d] %s" display-pos total
             (helixel--jump-display entry))))

(defun helixel--jump-goto (pos)
  "Go to the group-start of jump entry at POS, switching buffers as needed."
  (let* ((gpos (helixel--jump-group-start pos))
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
      (let ((newest (helixel--jump-group-newest helixel--jump-pos))
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

(provide 'helixel-action)
;;; helixel-action.el ends here
