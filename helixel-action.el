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
(require 'helixel-ring)

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

;; ----------------------------------------------------------------------
;; State variables
;; ----------------------------------------------------------------------

(defvar helixel--inhibit-action-track nil
  "When non-nil, event recording is inhibited.
Bound during dot-repeat replay to prevent re-recording.")


(defvar-local helixel--action-pos nil
  "Ring position for `;' cycling.
nil = live event.  0 = newest ring entry.  N = older.")

(defvar helixel-jump-cleanup-function nil
  "Function called after a successful jump to clean up selection state.
Typically `helixel--clear-data'.")

;; ----------------------------------------------------------------------
;; Event display
;; ----------------------------------------------------------------------

(defun helixel-event-display-format (event)
  "Format `helixel-event' EVENT for display in cycling messages.
Uses `helixel-event-display' if set, otherwise builds from
category and subcat."
  (or (helixel-event-display event)
      (let ((cat (helixel-event-category event))
            (sub (helixel-event-subcat event)))
        (cond
         ((and (eq cat 'state) (eq sub 'cancel)) "C-g")
         (t (format "%s.%s" cat sub))))))

(defun helixel-action-display (event)
  "Format EVENT for display.  Delegates to `helixel-event-display-format'."
  (helixel-event-display-format event))

;; ----------------------------------------------------------------------
;; Generic grouped-ring helpers
;; ----------------------------------------------------------------------
;;
;; Both `;' cycling (event ring) and C-o/C-i (jump list) share the
;; same core algorithm.  These helpers are parameterized by visibility
;; and same-group predicates.

(defun helixel--grouped-ring-group-start (list pos same-group-pred)
  "Return the oldest index in LIST of the group containing POS.
SAME-GROUP-PRED is a function of two elements returning non-nil
when they belong to the same group."
  (let ((len (length list)))
    (while (and (< (1+ pos) len)
                (funcall same-group-pred
                         (nth pos list) (nth (1+ pos) list)))
      (cl-incf pos))
    pos))

(defun helixel--grouped-ring-group-newest (list pos same-group-pred)
  "Return the newest index in LIST of the group containing POS.
SAME-GROUP-PRED is a function of two elements returning non-nil
when they belong to the same group."
  (let ((i pos))
    (while (and (> i 0)
                (funcall same-group-pred
                         (nth i list) (nth (1- i) list)))
      (cl-decf i))
    i))

(defun helixel--grouped-ring-visible-index (list pos visible-pred)
  "Return index of first visible entry starting at POS in LIST, or nil.
VISIBLE-PRED is a function of one element returning non-nil when the
entry should be counted as visible."
  (cl-loop for i from pos below (length list)
           when (funcall visible-pred (nth i list))
           return i))

(defun helixel--grouped-ring-visible-count (list visible-pred)
  "Count visible entries in LIST.
VISIBLE-PRED is a function of one element returning non-nil when the
entry should be counted as visible."
  (cl-loop for a in list
           when (funcall visible-pred a)
           count 1))

(defun helixel--grouped-ring-find (list pos direction visible-pred)
  "Find index of next visible entry from POS in DIRECTION (+1/-1).
LIST is the ring to search.  VISIBLE-PRED is a function of one
element returning non-nil when the entry is visible."
  (let ((len (length list)))
    (cl-loop for i from (+ pos direction) by direction
             while (if (> direction 0) (< i len) (>= i 0))
             when (funcall visible-pred (nth i list))
             return i)))

;; ----------------------------------------------------------------------
;; Marker jump helper
;; ----------------------------------------------------------------------

(defun helixel--jump-to-marker (marker)
  "Set mark at MARKER, keeping point unchanged."
  (when (and (markerp marker) (marker-buffer marker))
    (push-mark marker t t)))

;; ----------------------------------------------------------------------
;; ; cycling — session jump within buffer
;; ----------------------------------------------------------------------

(defun helixel-action--cycle-visible-p (event)
  "Return non-nil if EVENT should be visible during `;' cycling."
  (memq (helixel-event-category event) helixel-action-cycle-categories))

(defun helixel-action--cycle-display (event pos ring)
  "Format cycling message for EVENT at POS in RING."
  (let* ((total (helixel--grouped-ring-visible-count
                 ring #'helixel-action--cycle-visible-p))
         (display-pos (1+ (cl-loop for i from 0 below pos
                                   count (helixel-action--cycle-visible-p
                                          (nth i ring))))))
    (format "[%d/%d] %s" display-pos total
            (helixel-event-display-format event))))

(defun helixel-action--cycle-show (pos ring)
  "Show the group-start entry for the group containing RING[POS]."
  (let* ((gpos (helixel-action--cycle-group-start pos ring))
         (event (nth gpos ring)))
    (setq helixel--action-pos gpos)
    (helixel--jump-to-marker (helixel-event-marker event))
    (message "%s" (helixel-action--cycle-display event gpos ring))))

(defun helixel-action--same-group-p (a b)
  "Return non-nil if `helixel-event' structs A and B share a group.
Two events are in the same group when they share both
category and subcat."
  (and a b
       (eq (helixel-event-category a) (helixel-event-category b))
       (eq (helixel-event-subcat a) (helixel-event-subcat b))))

(defun helixel-action--cycle-group-start (pos ring)
  "Return the oldest index in RING of the group containing POS.
Uses `helixel-action--same-group-p' as the grouping predicate."
  (helixel--grouped-ring-group-start ring pos
    #'helixel-action--same-group-p))

(defun helixel-action--cycle-group-newest (pos ring)
  "Return the newest index in RING of the group containing POS.
Uses `helixel-action--same-group-p' as the grouping predicate."
  (helixel--grouped-ring-group-newest ring pos
    #'helixel-action--same-group-p))

(defun helixel-action-cycle (&optional arg)
  "Cycle through `helixel--event-ring' entries with `;'.
Without prefix ARG: go to older action.
With prefix ARG (`C-u'): go to newer action or restore live event."
  (interactive "P")
  (if arg
      ;; C-u ; → go forward (newer)
      (cond
       ((and helixel--action-pos (> helixel--action-pos 0))
        (let* ((newest (helixel-action--cycle-group-newest
                        helixel--action-pos helixel--event-ring))
               (prev (when (> newest 0)
                       (helixel--grouped-ring-visible-index
                        helixel--event-ring (1- newest)
                        #'helixel-action--cycle-visible-p))))
          (if prev
              (helixel-action--cycle-show prev helixel--event-ring)
            (message "At newest"))))
       ((eq helixel--action-pos 0)
        (if helixel--live-event
            (progn
              (setq helixel--action-pos nil)
              (helixel--jump-to-marker
               (helixel-event-marker helixel--live-event))
              (message "[live] %s"
                       (helixel-event-display-format helixel--live-event)))
          (message "At newest")))
       (t (message "At newest")))
    ;; ; → go back (older)
    (cond
     (helixel--action-pos
      (let ((pos (helixel--grouped-ring-find
                  helixel--event-ring helixel--action-pos 1
                  #'helixel-action--cycle-visible-p)))
        (if pos
            (helixel-action--cycle-show pos helixel--event-ring)
          (message "No more"))))
     (helixel--live-event
      ;; Commit live event first, then show ring[0]
      (helixel-event-commit)
      (let ((pos (helixel--grouped-ring-visible-index
                  helixel--event-ring 0
                  #'helixel-action--cycle-visible-p)))
        (if pos
            (helixel-action--cycle-show pos helixel--event-ring)
          (message "No saved actions"))))
     (helixel--event-ring
      (let ((pos (helixel--grouped-ring-visible-index
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
     (make-helixel-event
      :category cat
      :subcat sub
      :marker (point-marker)
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
       (let ((m (plist-get entry :marker))
             (buf (plist-get entry :buffer)))
         (and (markerp m) (marker-buffer m) (buffer-live-p buf)))))

(defun helixel--jump-same-group-p (a b)
  "Return non-nil if A and B belong to the same jump group."
  (and a b
       (eq (plist-get a :category) (plist-get b :category))
       (eq (plist-get a :subcat) (plist-get b :subcat))
       (eq (plist-get a :buffer) (plist-get b :buffer))))

(defun helixel--jump-group-start (pos)
  "Return group-start index for jump entry at POS."
  (helixel--grouped-ring-group-start helixel--global-jump-log pos
    #'helixel--jump-same-group-p))

(defun helixel--jump-group-newest (pos)
  "Return newest index for jump group containing POS."
  (helixel--grouped-ring-group-newest helixel--global-jump-log pos
    #'helixel--jump-same-group-p))

(defun helixel--jump-message (pos)
  "Format and message the current jump position POS."
  (let* ((entry (nth pos helixel--global-jump-log))
         (total (helixel--grouped-ring-visible-count
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
          (m (plist-get entry :marker)))
      (when (and (markerp m) (marker-buffer m) (buffer-live-p buf))
        (let ((cross-buffer (not (eq buf (current-buffer)))))
          (setq helixel--jump-pos gpos)
          (when cross-buffer
            (switch-to-buffer buf))
          (goto-char (marker-position m))
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
           (pos (helixel--grouped-ring-find
                 helixel--global-jump-log start 1
                 #'helixel--jump-visible-p))
           (found nil))
      (while pos
        (if (helixel--jump-goto pos)
            (setq found t pos nil)
          (setq helixel--jump-pos pos
                pos (helixel--grouped-ring-find
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
          (setq pos (helixel--grouped-ring-visible-index
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
