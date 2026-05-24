;;; helixel-ring.el --- Unified event ring for helixel-mode -*- lexical-binding: t; -*-

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
;; Unified event ring for helixel-mode.
;;
;; Two storage containers:
;;   1. buffer-local `helixel--event-ring' — serves `;` cycling,
;;      `.`/`,` repeat, and history selection.
;;   2. global `helixel--global-jump-log' — serves C-o/C-i jump
;;      navigation across buffers.
;;
;; Both are populated by `helixel-event-commit', eliminating the
;; old `helixel-action-push-functions' hook bridge.
;;
;; Dependencies: helixel-data (helixel-event struct).

;;; Code:

(require 'cl-lib)
(require 'helixel-data)

;; ═══════════════════════════════════════════════════════════════════════
;; Buffer-local event ring
;; ═══════════════════════════════════════════════════════════════════════

(defcustom helixel-event-ring-max 50
  "Maximum number of events stored in `helixel--event-ring'."
  :type 'integer
  :group 'helixel)

(defvar-local helixel--event-ring nil
  "Event ring, most recent first.  Capped at `helixel-event-ring-max'.
Each entry is a `helixel-event' struct.
Shared by session jump (`;'), repeat (`.`/`,`), and history (`C-u n').")

(defvar-local helixel--live-event nil
  "The currently in-progress `helixel-event'.
Set at command start, committed to ring when complete.")

(defvar-local helixel--last-event nil
  "Pointer to the most recent committed event in the ring.
Consumed by `.` and `,` for repeat.")

(defun helixel-event--ring-cap ()
  "Truncate `helixel--event-ring' to `helixel-event-ring-max' entries.
Releases markers of evicted entries to prevent leaks."
  (when (> (length helixel--event-ring) helixel-event-ring-max)
    (let ((tail (nthcdr helixel-event-ring-max helixel--event-ring)))
      (dolist (e tail)
        (when-let* ((m (helixel-event-marker e))
                    ((markerp m)))
          (set-marker m nil))))
    (setcdr (nthcdr (1- helixel-event-ring-max)
                    helixel--event-ring)
            nil)))

(defun helixel-event-commit ()
  "Commit `helixel--live-event' to `helixel--event-ring'.
Deep-copies the event (marker + sel) so ring entries are independent.
Deduplicates against the ring front — same (op sel payload) skips push.
Also mirrors to `helixel--global-jump-log'.
Sets `helixel--last-event' to the committed entry.
Returns the committed entry or nil."
  (when helixel--live-event
    (let ((entry (helixel-event--copy helixel--live-event)))
      (unless (and (car helixel--event-ring)
                   (helixel-event--same-content-p
                    entry (car helixel--event-ring)))
        (push entry helixel--event-ring)
        (helixel-event--ring-cap))
      (setq helixel--last-event entry)
      (helixel--global-jump-log-push entry)
      (setq helixel--live-event nil)
      entry)))


;; ═══════════════════════════════════════════════════════════════════════
;; Global jump log (C-o / C-i)
;; ═══════════════════════════════════════════════════════════════════════

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
Each entry: (:marker M :buffer BUF :category CAT :subcat SUBCAT).
Lightweight — no full event payload, sel struct, or closures.")

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
       (let ((m1 (plist-get a :marker))
             (m2 (plist-get b :marker)))
         (if (and (markerp m1) (markerp m2))
             (= (marker-position m1) (marker-position m2))
           t))))

(defun helixel--jump-log-cap ()
  "Truncate `helixel--global-jump-log' to `helixel-jump-log-max'."
  (when (> (length helixel--global-jump-log) helixel-jump-log-max)
    (let ((tail (nthcdr helixel-jump-log-max helixel--global-jump-log)))
      (dolist (e tail)
        (when-let* ((m (plist-get e :marker))
                    ((markerp m)))
          (set-marker m nil))))
    (setcdr (nthcdr (1- helixel-jump-log-max)
                    helixel--global-jump-log)
            nil)))

(defun helixel--global-jump-log-push (event)
  "Push jump info from EVENT to `helixel--global-jump-log'.
Only pushes if EVENT's :category is in `helixel-jump-categories'.
Creates independent marker copy; the jump-log entry is lightweight."
  (when (and event
             (memq (helixel-event-category event) helixel-jump-categories))
    (let* ((src-m (helixel-event-marker event))
           (buf (or (when (markerp src-m) (marker-buffer src-m))
                    (current-buffer)))
           (entry `(:marker ,(if (markerp src-m)
                                 (copy-marker src-m
                                              (marker-insertion-type src-m))
                               src-m)
                    :buffer ,buf
                    :category ,(helixel-event-category event)
                    :subcat ,(helixel-event-subcat event))))
      (unless (helixel--jump-same-content-p
               entry (car helixel--global-jump-log))
        (push entry helixel--global-jump-log)
        (setq helixel--jump-pos nil)
        (helixel--jump-log-cap)))))

(provide 'helixel-ring)
;;; helixel-ring.el ends here
