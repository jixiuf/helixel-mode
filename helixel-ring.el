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
;; Event storage layer for helixel-mode.
;;
;; Two storage containers:
;;   1. buffer-local `helixel--event-ring' — serves `;` cycling,
;;      `.`/`,` repeat, and history selection.
;;   2. global `helixel--global-jump-log' — serves C-o/C-i jump
;;      navigation across buffers.
;;
;; Also provides the unified tracking entry point
;; `helixel--tracking-open' used by all command-definition macros,
;; and the live-event management helpers.

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

(defcustom helixel-edit-ring-max 50
  "Maximum number of events stored in `helixel--event-ring'."
  :type 'integer
  :group 'helixel)

(defvar-local helixel--event-ring nil
  "Event ring, most recent first.  Capped at `helixel-edit-ring-max'.
Each entry is a `helixel-edit' struct.
Shared by session jump (`;'), repeat (`.`/`,`), and history (`C-u n').")

(defvar-local helixel--live-edit nil
  "The currently in-progress `helixel-edit'.
Set at command start, committed to ring when complete.")

;; `helixel--last-edit' is defined in helixel-core.el.
;; It is available transitively through the require chain.

(defconst helixel--sel-categories '(movement search find-char textobj)
  "Event categories that carry a selection descriptor.
Used by `helixel-edit-commit' to sync `helixel--pending-sel'
into the committed event's :sel slot when the event's own :sel
is nil.  Categories not listed here never carry a pending-sel.")

(defun helixel-edit--ring-cap ()
  "Truncate `helixel--event-ring' to `helixel-edit-ring-max' entries.
Releases markers of evicted entries to prevent leaks."
  (when (> (length helixel--event-ring) helixel-edit-ring-max)
    (let ((tail (nthcdr helixel-edit-ring-max helixel--event-ring)))
      (dolist (e tail)
        (when-let* ((mr (helixel-edit-mark-region e))
                    ((consp mr)))
          (set-marker (car mr) nil)
          (set-marker (cdr mr) nil))))
    (setcdr (nthcdr (1- helixel-edit-ring-max)
                    helixel--event-ring)
            nil)))

(defun helixel-edit-commit ()
  "Commit `helixel--live-edit' to `helixel--event-ring'.
Deep-copies the event (marker + sel) so ring entries are independent.
Deduplicates against the ring front — same (op sel payload) skips push.
Also mirrors to `helixel--global-jump-log'.
Sets `helixel--last-edit' to the committed entry.
Returns the committed entry or nil."
  (when helixel--live-edit
    ;; Sync pending-sel into the live-event so movement/search
    ;; events in the ring carry their selection descriptor.
    ;; Only for selection-creating categories; edits already set
    ;; sel via `helixel--live-edit-set'.
    (when (and helixel--pending-sel
               (not (helixel-edit-sel helixel--live-edit))
               (memq (helixel-edit-category helixel--live-edit)
                     helixel--sel-categories))
      (setf (helixel-edit-sel helixel--live-edit)
            (helixel-sel--copy helixel--pending-sel)))
    (let ((entry (helixel-edit--copy helixel--live-edit)))
      (unless (and (car helixel--event-ring)
                   (helixel-edit--same-content-p
                    entry (car helixel--event-ring)))
        (push entry helixel--event-ring)
        (helixel-edit--ring-cap))
      (setq helixel--last-edit entry)
      (helixel--global-jump-log-push entry)
      (setq helixel--live-edit nil)
      entry)))

;; ── Live-event helpers ──

(defun helixel--cancel-action ()
  "Cancel the current action via \\[keyboard-quit].
Commits meaningful events, pushes a state/cancel sentinel,
and clears the live state."
  (helixel-edit-commit)
  ;; Push cancel sentinel for dedup boundary
  (setq helixel--live-edit
        (make-helixel-edit
         :category 'state
         :subcat 'cancel
         :mark-region (let ((pm (point-marker)))
                         (cons pm (copy-marker pm t)))
         :timestamp (float-time)
         :buffer (current-buffer)))
  (helixel-edit-commit))

(defun helixel--live-edit-set (tx)
  "Set edit details from TX on `helixel--live-edit'."
  (when (and helixel--live-edit (helixel-edit-p tx))
    (setf (helixel-edit-op helixel--live-edit) (helixel-edit-op tx))
    (setf (helixel-edit-sel helixel--live-edit) (helixel-edit-sel tx))
    (setf (helixel-edit-payload helixel--live-edit)
          (helixel-edit-payload tx))
    (setf (helixel-edit-runner helixel--live-edit)
          (helixel-edit-runner tx))
    (when-let* ((disp (helixel-edit-display tx)))
      (setf (helixel-edit-display helixel--live-edit) disp))))

;; ── Unified entry point: open event (commit prev, create new) ──

(defun helixel--tracking-open (category subcat &optional op)
  "Commit previous `helixel--live-edit' and create a new one.
CATEGORY and SUBCAT classify the event for \=`;\=` and jump-list.
OP is an optional operator symbol (nil for movement/search).

No-op when `(helixel-replaying-p)` is non-nil (dot-repeat).
Does NOT commit the new event — caller is responsible for eventual commit."
  (unless (helixel-replaying-p)
    ;; Clear textobj selection state on non-textobj actions
    (when (and (eq helixel--raw-selection-type 'textobj)
               (not (eq category 'textobj)))
      (setq helixel--raw-selection-type nil))
    (helixel-edit-commit)
    (setq helixel--live-edit
          (make-helixel-edit
           :op op
           :category category
           :subcat subcat
           :mark-region (let ((pm (point-marker)))
                           (cons pm (copy-marker pm t)))
           :timestamp (float-time)
           :buffer (current-buffer))
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
             (memq (helixel-edit-category event) helixel-jump-categories)
             ;; Don't pollute the global (cross-buffer) jump log
             ;; with events committed during fake-cursor dispatch.
             (not (helixel-replay-in-fake-p)))
    (let* ((src-mr (helixel-edit-mark-region event))
           (buf (if (and (consp src-mr) (markerp (car src-mr)))
                    (marker-buffer (car src-mr))
                  (current-buffer)))
           (entry `(:mark-region ,(when (consp src-mr)
                                    (cons (copy-marker (car src-mr))
                                          (copy-marker (cdr src-mr) t)))
                    :buffer ,buf
                    :category ,(helixel-edit-category event)
                    :subcat ,(helixel-edit-subcat event))))
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

(provide 'helixel-ring)
;;; helixel-ring.el ends here
