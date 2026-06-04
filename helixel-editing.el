;;; helixel-editing.el --- Edit commands, selection recreate, op runners  -*- lexical-binding: t; -*-

;; Copyright (C) 2025-2026  jixiuf

;; Author: jixiuf
;; Keywords: convenience
;; URL: https://github.com/jixiuf/helixel-mode

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

;; Editing commands and dot-repeat replay for helixel-mode.
;;
;; Editing commands (kill, change, copy, replace, yank, indent) plus
;; the `helixel-register-op' dot-repeat runners that replay them.
;; Also houses selection recreation functions consumed by `.` and the
;; `helixel--selection-type' validator.
;;
;; Keymaps are NOT loaded here — `helixel-keymap' is loaded separately
;; by `helixel.el' after this file.

;;; Code:

(require 'cl-lib)
(require 'helixel-state)
(require 'helixel-move)
(require 'helixel-core)
(require 'helixel-macros)
(require 'helixel-search)

;; ── Shared kill core ──

(defun helixel--delete-selection ()
  "Delete current region or char at point, pushing to `kill-ring'.
Does NOT record an edit and does NOT clear selection data.
Used as the shared kill core by `helixel-kill-thing-at-point',
`helixel-change-thing-at-point', and `helixel--repeat-change-core'."
  (cond
   ((not (use-region-p))
    (helixel--kill-new (char-to-string (char-after)))
    (delete-char 1))
   ((eq (helixel--selection-type) 'rect)
    (let ((lines (extract-rectangle (region-beginning) (region-end))))
      (delete-rectangle (region-beginning) (region-end))
      (helixel--kill-new (helixel--rect-wise-text lines))))
   ((eq (helixel--selection-type) 'line)
    (if-let* ((bounds (helixel--line-bounds-of-region))
              (text (filter-buffer-substring (car bounds) (cdr bounds))))
        (progn
          (helixel--kill-new (helixel--linewise-text text))
          (delete-region (car bounds) (cdr bounds)))))
   (t
    (helixel--kill-new
     (filter-buffer-substring (region-beginning) (region-end)))
    (delete-region (region-beginning) (region-end)))))

(defun helixel--end-of-line-p ()
  "Return non-nil if current point is at the end of the current line."
  (save-excursion
    (let ((cur (point))
          eol)
      (end-of-line)
      (setq eol (point))
      (= cur eol))))

;; ── Selection recreation ──
;; These functions rebuild selections from ctx during `.` replay.
;; `helixel--recreate-line' and `helixel--recreate-rect' are defined
;; in helixel-move.el.

(defun helixel--recreate-insert-selection-start (ctx)
  "Replay insert-selection-start.  CTX holds :cursor-offset (int or nil)."
  (goto-char (region-beginning))
  (let ((off (helixel-sel-insert-cursor-offset ctx)))
    (when off (forward-char off))))

(defun helixel--recreate-insert-selection-end (ctx)
  "Replay insert-selection-end.  CTX holds :cursor-offset (int or nil)."
  (goto-char (region-end))
  (let ((off (helixel-sel-insert-cursor-offset ctx)))
    (when off (forward-char off))))

(defun helixel--recreate-insert-beginning-line (_ctx)
  "Replay insert-beginning-line.  CTX is ignored."
  (beginning-of-line))

(defun helixel--recreate-insert-end-line (_ctx)
  "Replay insert-end-line.  CTX is ignored."
  (end-of-line))

(defun helixel--recreate-insert-search-offset (ctx)
  "Replay insert-search-offset.  CTX holds :offset (integer)."
  (let ((offset (helixel-sel-insert-offset ctx)))
    (goto-char (+ (match-beginning 0) offset))))

;; ── Insert-entry tail helper ──
;;
;; Every insert variant command ends with the same three steps:
;;   1. Record 'insert-text as the operation
;;   2. Snap `helixel--change-track-marker' at point
;;   3. Enter insert mode
;;
;; `helixel--prepare-insert-entry' encapsulates this tail.
;; Commands that have already called `helixel--record-edit' earlier
;; (to interleave setup between record and marker snap) pass nil for
;; RECORD-P to skip the redundant record call.

(defun helixel--prepare-insert-entry (&optional record-p)
  "Prepare for insert-mode entry: record, snap marker, enter insert.
Calls `helixel--record-edit' (unless RECORD-P is nil).
After recording, snaps `helixel--change-track-marker' at point
and enters insert mode.

Pass nil for RECORD-P when the caller has already called
`helixel--record-edit' earlier (e.g. `helixel-insert-newline').
Otherwise RECORD-P defaults to t via the wrapper body."
  (setq record-p (or record-p t))
  (when record-p
    (helixel--record-edit 'insert-text))
  (setq helixel--change-track-marker (point-marker))
  (helixel--enter-insert))

;; ── Insert-* kind registrations ──
;; Recreate functions defined here; advance functions in helixel-repeat.el.

(helixel-register-kind insert-selection-start
  :ctx-schema '(:required () :optional (:cursor-offset :entry-kind))
  :recreate #'helixel--recreate-insert-selection-start
  :advance  #'helixel--repeat-advance-search
  :display  "i")

(helixel-register-kind insert-selection-end
  :ctx-schema '(:required () :optional (:cursor-offset :entry-kind))
  :recreate #'helixel--recreate-insert-selection-end
  :advance  #'helixel--repeat-advance-search
  :display  "a")

(helixel-register-kind insert-beginning-line
  :ctx-schema '(:required () :optional ())
  :recreate #'helixel--recreate-insert-beginning-line
  :advance  #'helixel--repeat-advance-line
  :display  "I")

(helixel-register-kind insert-end-line
  :ctx-schema '(:required () :optional ())
  :recreate #'helixel--recreate-insert-end-line
  :advance  #'helixel--repeat-advance-line
  :display  "A")

(helixel-register-kind insert-search-offset
  :ctx-schema '(:required (:offset) :optional ())
  :recreate #'helixel--recreate-insert-search-offset
  :advance  #'helixel--repeat-advance-search
  :display  "s")

(helixel-define-command helixel-insert
    (:category state :subcat insert)
  (cond
   ;; Search context: refine the search sel with entry-kind
   ((and helixel--pending-sel
         (eq (helixel-sel-kind helixel--pending-sel) 'search))
     (helixel--sel-push
          (helixel-sel-update-ctx helixel--pending-sel
                                  :entry-kind 'insert))
    (goto-char (region-beginning)))
   ;; Line selection: preserve sel for `.` auto-advance
   ((and helixel--pending-sel
         (eq (helixel-sel-kind helixel--pending-sel) 'line))
     (helixel--sel-push
          (helixel-sel-update-ctx helixel--pending-sel
                                  :entry-kind 'insert))
    (goto-char (region-beginning)))
   ;; Manual region
   ((use-region-p)
     (helixel--sel-push
          (helixel-sel-create
           'insert-selection-start nil
           #'helixel--recreate-insert-selection-start "is"))
    (goto-char (region-beginning)))
   ;; No context
   (t
    (setq helixel--pending-sel nil)))
  (helixel--prepare-insert-entry))

(helixel-define-command helixel-insert-exit
    (:category state :subcat exit)
  (let* ((keys (helixel--insert-finish))
         (text (when helixel--change-track-marker
                 (and (marker-position helixel--change-track-marker)
                      (buffer-substring
                       helixel--change-track-marker (point))))))
    (unless executing-kbd-macro
      (when helixel--last-edit
        (let ((tx helixel--last-edit))
          ;; Store keys as primary replay mechanism
          (when (and keys (> (length keys) 0))
            (setq tx (helixel-edit-with-payload tx :keys keys)))
          ;; Store text as replay fallback (tests, programmatic use)
          (when text
            (setq tx (helixel-edit-with-payload tx :text text))
            (when (eq (helixel-edit-op tx) 'change)
              (setq tx (helixel-edit-with-payload tx
                                                  :inserted-text text))))
          (helixel--update-last-event tx))))
    (when helixel--change-track-marker
      (set-marker helixel--change-track-marker nil)
      (setq helixel--change-track-marker nil))
    (when (helixel--rect-replay-get)
      (helixel--rect-replay))
    (let ((state (helixel--default-state-for-buffer)))
      (when (eq state 'insert)
        (setq state 'normal))
      (helixel--switch-state state))))

;; ── Insert variant commands ──

(helixel-define-command helixel-insert-after
    (:category state :subcat insert)
  (cond
   ;; Search context: refine the search sel with entry-kind
   ((and helixel--pending-sel
         (eq (helixel-sel-kind helixel--pending-sel) 'search))
     (helixel--sel-push
          (helixel-sel-update-ctx helixel--pending-sel
                                  :entry-kind 'append))
    (goto-char (region-end)))
   ;; Line selection: preserve sel for `.` auto-advance
   ((and helixel--pending-sel
         (eq (helixel-sel-kind helixel--pending-sel) 'line))
     (helixel--sel-push
          (helixel-sel-update-ctx helixel--pending-sel
                                  :entry-kind 'append))
    (goto-char (region-end)))
   ;; Manual region
   ((use-region-p)
     (helixel--sel-push
          (helixel-sel-create
           'insert-selection-end nil
           #'helixel--recreate-insert-selection-end "ie"))
    (goto-char (region-end)))
   ;; No context
   (t
    (unless (helixel--end-of-line-p)
      (forward-char))
    (setq helixel--pending-sel nil)))
  (helixel--prepare-insert-entry))

(helixel-define-command helixel-insert-beginning-line
    (:category state :subcat insert)
  (beginning-of-line)
   (helixel--sel-push
        (helixel-sel-create
         'insert-beginning-line nil
         #'helixel--recreate-insert-beginning-line "I"))
  (helixel--prepare-insert-entry))

(helixel-define-command helixel-insert-after-end-line
    (:category state :subcat insert)
  (end-of-line)
   (helixel--sel-push
        (helixel-sel-create
         'insert-end-line nil
         #'helixel--recreate-insert-end-line "A"))
  (helixel--prepare-insert-entry))

(helixel-define-command helixel-insert-newline
    (:category state :subcat insert)
  (helixel--record-edit 'insert-text)
  (helixel--clear-data)
  (end-of-line)
  (newline-and-indent)
  (helixel--prepare-insert-entry nil))

(helixel-define-command helixel-insert-prevline
    (:category state :subcat insert)
  (helixel--record-edit 'insert-text)
  (helixel--clear-data)
  (beginning-of-line)
  (let ((electric-indent-mode nil))
    (newline nil t)
    (call-interactively #'previous-line)
    (indent-according-to-mode))
  (helixel--prepare-insert-entry nil))


;; ── Edit-op change runner ──

(defun helixel--repeat-change-core (tx)
  "Repeat change TX: delete selection, replay keys or insert text.
TX is the complete edit transaction (see `helixel-edit-create').
Keys (primary) capture the full insert-mode keystrokes.
Text (fallback) is used when keys are unavailable (tests).

For rect selections the stored text is replayed on every subsequent
rectangle line via `helixel--rect-replay' — no state-switching side
-effect (avoids an unnecessary helixel-insert-exit during replay)."
  (let* ((keys (helixel--repeat-get-keys tx))
         (text (helixel-edit-payload-get tx :inserted-text)))
    (cond
     ((and (use-region-p) (eq (helixel--selection-type) 'rect))
      (helixel--rect-change)
      (if keys
          (helixel--execute-keys keys)
        (when text (insert text)))
      (helixel--rect-replay))
     (t
      ;; Save the region-beginning set by the advance function
      ;; so we can restore an active region afterward for
      ;; undo-in-region.
      (let ((sel-beg (region-beginning)))
        (helixel--delete-selection)
        ;; Deactivate the mark left by the deleted selection
        ;; so that key replay (e.g. delete-backward-char) does
        ;; not see an active region and delete the wrong span.
        (deactivate-mark)
        (if keys
            (helixel--execute-keys keys)
          (when text (insert text)))
        ;; Restore an active region covering the replayed edit
        ;; so undo-in-region limits undo to this replay only.
        (push-mark sel-beg t t))))))

;; ── Edit-op registry ──
;; Each operator registers a `:runner' (called by `.`) and a `:display'
;; label via `helixel-register-op' or `helixel-define-operator'.
;; Runners call the editing commands defined below.

;; Ops whose `.` runner IS the command → use `helixel-define-operator'
;; below (kill, copy, replace, paste-after, paste-before).

;; Ops with non-trivial runners (need tx payload) → register separately:
(helixel-register-op change :display "c" :repeat-advance nil
  :runner #'helixel--repeat-change-core)

(helixel-register-op replace-char :repeat-advance 'line
  :display (lambda (tx)
             (let ((c (helixel-edit-payload-get tx :char)))
               (if c (format "R[%c]" c) "R")))
  :runner (lambda (tx)
            (helixel-replace-char
             (helixel-edit-payload-get tx :char))))

(helixel-register-op insert-text :display "i" :repeat-advance 'line
  :runner (lambda (tx)
            (let ((keys (helixel-edit-payload-get tx :keys)))
              (if keys
                  (helixel--execute-keys keys)
                (insert (or (helixel-edit-payload-get tx :text)
                            ""))))))


;; ── Kill & Change ──

(helixel-define-operator helixel-kill-thing-at-point
    (:op kill :display "d" :repeat-advance nil)
  (helixel--record-edit 'kill)
  (helixel--delete-selection)
  (helixel--register-consume)
  (helixel--clear-data))

(helixel-define-command helixel-change-thing-at-point
    (:category edit :subcat change)
  (helixel--record-edit 'change)
  (if (and (use-region-p) (eq (helixel--selection-type) 'rect))
      (progn (helixel--rect-change)
             (helixel--register-consume))
    (helixel--delete-selection)
    (helixel--register-consume)
    (setq helixel--change-track-marker (point-marker))
    (helixel--enter-insert)))

;; ── Replace ──

(defvar helixel--replace-pop-bounds nil
  "Bounds (BEG . END) of text from `helixel-replace' or `helixel-replace-pop'.
Value is nil after a rectangle replace.
Used to support cycling through the kill ring after a replace.")

(helixel-define-operator helixel-replace
    (:op replace :display "r" :repeat-advance 'line)
  (helixel--record-edit 'replace)
  (if (and (not (helixel--register-active-p))
           (= 0 (length kill-ring)))
      (message "nothing to yank")
    (let* ((text (or (helixel--current-kill 0) (current-kill 0)))
           (linewise-p (helixel--linewise-kill-p text))
           (rectwise-p (helixel--rect-wise-kill-p text))
           (bare (string-trim-right (substring-no-properties text) "\n"))
           (pop-start nil)
           (_bare-rect (unless (or linewise-p rectwise-p) bare)))
      (cond
       ;; Rect selection — no pop tracking (rect bounds are multi-line)
       ((and (use-region-p) (eq (helixel--selection-type) 'rect))
        (let* ((beg (region-beginning))
               (end (region-end))
               (lines (nth 1 (get-text-property 0 'yank-handler text))))
          (delete-rectangle beg end)
          (goto-char beg)
          (if (and rectwise-p lines)
              (insert-rectangle lines)
            (insert bare)))
        (setq helixel--replace-pop-bounds nil))
       ;; Line-wise selection: expand to full line bounds
       ((and (use-region-p) (eq (helixel--selection-type) 'line))
        (when-let* ((bounds (helixel--line-bounds-of-region)))
          (delete-region (car bounds) (cdr bounds))
          (setq pop-start (point))
          (insert (if linewise-p text (concat bare "\n")))
          (setq helixel--replace-pop-bounds
                (cons pop-start (point)))))
       ;; Charwise region
       ((use-region-p)
        (delete-region (region-beginning) (region-end))
        (setq pop-start (point))
        (insert (if (or linewise-p rectwise-p)
                    bare
                  (substring-no-properties text)))
        (setq helixel--replace-pop-bounds
              (cons pop-start (point))))
       ;; No region — replace char at point
       (t
        (when helixel-replace-delete-char-p
          (delete-char 1))
        (setq pop-start (point))
        (helixel-with-replay-as 'dot
          (helixel-yank))
        (setq helixel--replace-pop-bounds
              (cons pop-start (point)))))
      (helixel--register-consume)
      (helixel--clear-data))))

;; `helixel-replace-pop' cycles through the `kill-ring' to replace
;; the text inserted by the previous `helixel-replace' or
;; `helixel-replace-pop', similar to `yank-pop'.
;;
;; When called after `yank' or `yank-pop', degrades to `yank-pop'
;; to replace the just-yanked text with the next `kill-ring' entry.
;;
;; When called after `helixel-replace' or `helixel-replace-pop',
;; ARG advances N kills forward (default 1).
;;
;; When called directly, prompts to select a `kill-ring' entry and
;; replaces the region/char-at-point with it, like `helixel-replace'
;; but letting you choose which kill to use.  Subsequent calls
;; then cycle through the `kill-ring' as usual.
(helixel-define-command helixel-replace-pop
    (:category edit :subcat replace-pop :params (&optional arg))
  (interactive "*p")
  (setq arg (or arg 1))
  (cond
   ((memq last-command '(yank yank-pop))
    ;; ── Degrade to `yank-pop' when previous command was a yank ──
    (yank-pop arg))
   ((memq last-command '(helixel-replace helixel-replace-pop))
    ;; ── Cycle: replace bounds text with next kill-ring entry ──
    (unless helixel--replace-pop-bounds
      (user-error "No replace text to cycle"))
    (setq this-command 'helixel-replace-pop)
    (let* ((beg (car helixel--replace-pop-bounds))
           (end (cdr helixel--replace-pop-bounds))
           (inhibit-read-only t)
           (text (helixel--current-kill arg))
           (ends-with-newline (char-equal (char-before end) ?\n)))
      (delete-region beg end)
      (goto-char beg)
      (if (and ends-with-newline
               (not (string-suffix-p "\n" text)))
          (insert (concat text "\n"))
        (insert-for-yank text))
      (setq helixel--replace-pop-bounds
            (cons beg (point)))))
   (t
    ;; ── Direct call: browse kill-ring and replace ──
    (let* ((candidates
              (mapcar #'substring-no-properties kill-ring))
             (collection
              (lambda (s p a)
                (if (eq a 'metadata)
                    '(metadata (category . helixel-replace-pop)
                               (cycle-sort-function . identity)
                               (display-sort-function . identity))
                  (complete-with-action a candidates s p))))
             (selected
              (completing-read "Replace with: " collection nil t))
             (idx (cl-position selected candidates :test #'string=))
             (text (nth idx kill-ring))
             (linewise-p (helixel--linewise-kill-p text))
             (rectwise-p (helixel--rect-wise-kill-p text))
             (bare (string-trim-right
                    (substring-no-properties text) "\n"))
             (pop-start nil))
        (unless text
          (user-error "No kill-ring entry selected"))
        (setq kill-ring-yank-pointer (nthcdr idx kill-ring))
        (setq this-command 'helixel-replace-pop)
        (cond
         ;; Rect selection — no pop tracking
         ((and (use-region-p)
               (eq (helixel--selection-type) 'rect))
          (let* ((beg (region-beginning))
                 (end (region-end))
                 (lines (nth 1 (get-text-property
                                0 'yank-handler text))))
            (delete-rectangle beg end)
            (goto-char beg)
            (if (and rectwise-p lines)
                (insert-rectangle lines)
              (insert bare)))
          (setq helixel--replace-pop-bounds nil))
         ;; Line-wise selection
         ((and (use-region-p)
               (eq (helixel--selection-type) 'line))
          (when-let* ((bounds (helixel--line-bounds-of-region)))
            (delete-region (car bounds) (cdr bounds))
            (setq pop-start (point))
            (insert (if linewise-p text (concat bare "\n")))
            (setq helixel--replace-pop-bounds
                  (cons pop-start (point)))))
         ;; Charwise region
         ((use-region-p)
          (delete-region (region-beginning) (region-end))
          (setq pop-start (point))
          (insert (if (or linewise-p rectwise-p)
                      bare
                    (substring-no-properties text)))
          (setq helixel--replace-pop-bounds
                (cons pop-start (point))))
         ;; No region — replace char at point
         (t
          (when helixel-replace-delete-char-p
            (delete-char 1))
          (setq pop-start (point))
          (insert-for-yank text)
          (setq helixel--replace-pop-bounds
                (cons pop-start (point)))))))))

;; ── Copy ──

(helixel-define-operator helixel-kill-ring-save
    (:op copy :display "y" :repeat-advance 'line)
  (helixel--record-edit 'copy)
  (when (use-region-p)
    (let ((swap-source
           (list :beg (copy-marker (region-beginning))
                 :end (copy-marker (region-end))
                 :buffer (current-buffer)
                 :type (helixel--swap-source-type))))
      (cond
       ((eq (helixel--selection-type) 'rect)
        (let ((lines (extract-rectangle (region-beginning) (region-end))))
          (helixel--kill-new
           (propertize (helixel--rect-wise-text lines)
                       'helixel-swap-source swap-source)
           :copy)))
       ((eq (helixel--selection-type) 'line)
        (when-let* ((bounds (helixel--line-bounds-of-region))
                    (text (filter-buffer-substring
                           (car bounds) (cdr bounds))))
          (helixel--kill-new
           (propertize (helixel--linewise-text text)
                       'helixel-swap-source swap-source)
           :copy)))
       (t
        (helixel--kill-new
         (propertize
          (filter-buffer-substring (region-beginning) (region-end))
          'helixel-swap-source swap-source)
         :copy)))))
  (helixel--register-consume)
  (helixel--clear-data))

;; ── Yank ──

(helixel-define-operator helixel-yank
    (:op paste-after :display "p" :repeat-advance 'line
     :params (&optional arg))
  (interactive "*P")
  (helixel--record-edit 'paste-after)
  (prog1
      (cond
       ((helixel--rect-wise-kill-p)
        (let* ((text (helixel--current-kill 0 t))
               (lines (when text
                        (nth 1 (get-text-property
                                0 'yank-handler text)))))
          (if lines
              (insert-rectangle lines)
            (when text (insert-for-yank text)))))
       ((helixel--linewise-kill-p)
        (let ((text (helixel--current-kill 0 t)))
          (when text (insert-for-yank text))))
       (t
        (helixel--yank arg)))
    (helixel--register-consume)))

(helixel-define-operator helixel-yank-before
    (:op paste-before :display "P" :repeat-advance 'line
     :params (&optional arg))
  (interactive "*P")
  (helixel--record-edit 'paste-before)
  (prog1
      (cond
       ((helixel--rect-wise-kill-p)
        (let* ((text (helixel--current-kill 0 t))
               (lines (when text
                        (nth 1 (get-text-property
                                0 'yank-handler text)))))
          (if lines
              (insert-rectangle lines)
            (when text (insert-for-yank text)))))
       ((helixel--linewise-kill-p)
        (let ((text (helixel--current-kill 0 t)))
          (when text (insert-for-yank text))))
       (t
        (helixel--yank arg)))
    (helixel--register-consume)))

;; ── Indent ──
;; helixel--replay-multiplier is bound by the op runner during `.`
;; replay so that the indent count is taken from the amalgamated
;; :multiplier payload instead of the interactive prefix.

(defvar helixel--replay-multiplier nil
  "When non-nil, overrides the indent count during `.` replay.
Set by the op runner from the transaction's :multiplier payload.")

(helixel-define-operator helixel-indent-left
    (:op indent-left :display "<" :repeat-advance 'line
     :params (&optional count))
  (interactive "p")
  (let* ((n (or helixel--replay-multiplier count 1))
         (consecutive-p nil))
    (unless (use-region-p)
      ;; Consecutive (same op): reuse selection, indent 1 level,
      ;; Consecutive (same op): reuse selection, indent 1 level,
      ;; amalgamate multiplier into the last event.
      (when-let* ((tx helixel--last-edit)
                  (sel (helixel-edit-sel tx)))
        (when (eq (helixel-edit-op tx) 'indent-left)
          (when-let* ((m (car (helixel-edit-mark-region tx)))
                      (pos (marker-position m)))
            (goto-char pos))
          (helixel-with-replay-as 'dot
            (helixel--recreate-selection sel))
          (indent-rigidly (region-beginning) (region-end) (- 1))
          (let* ((mult (or (helixel-edit-payload-get tx :multiplier) 1)))
            (helixel--update-last-event
             (helixel-edit-with-payload tx :multiplier (1+ mult))))
          (goto-char (region-beginning))
          (setq consecutive-p t))))
    (unless consecutive-p
      (if (use-region-p)
          (indent-rigidly (region-beginning) (region-end) (- n))
        (indent-rigidly (line-beginning-position) (line-end-position)
                        (- n)))
      (when (use-region-p)
        (goto-char (region-beginning)))
      (helixel--record-edit 'indent-left :multiplier n)))
  (helixel--clear-data))

(helixel-op-set-runner 'indent-left
     (lambda (tx)
       (let ((helixel--replay-multiplier
              (or (helixel-edit-payload-get tx :multiplier) 1)))
         (helixel-indent-left))))

(helixel-define-operator helixel-indent-right
    (:op indent-right :display ">" :repeat-advance 'line
     :params (&optional count))
  (interactive "p")
  (let* ((n (or helixel--replay-multiplier count 1))
         (consecutive-p nil))
    (unless (use-region-p)
      ;; Consecutive (same op): reuse selection, indent 1 level,
      ;; Consecutive (same op): reuse selection, indent 1 level,
      ;; amalgamate multiplier into the last event.
      (when-let* ((tx helixel--last-edit)
                  (sel (helixel-edit-sel tx)))
        (when (eq (helixel-edit-op tx) 'indent-right)
          (when-let* ((m (car (helixel-edit-mark-region tx)))
                      (pos (marker-position m)))
            (goto-char pos))
          (helixel-with-replay-as 'dot
            (helixel--recreate-selection sel))
          (indent-rigidly (region-beginning) (region-end) 1)
          (let* ((mult (or (helixel-edit-payload-get tx :multiplier) 1)))
            (helixel--update-last-event
             (helixel-edit-with-payload tx :multiplier (1+ mult))))
          (goto-char (region-beginning))
          (setq consecutive-p t))))
    (unless consecutive-p
      (if (use-region-p)
          (indent-rigidly (region-beginning) (region-end) n)
        (indent-rigidly (line-beginning-position) (line-end-position) n))
      (when (use-region-p)
        (goto-char (region-beginning)))
      (helixel--record-edit 'indent-right :multiplier n)))
  (helixel--clear-data))

(helixel-op-set-runner 'indent-right
     (lambda (tx)
       (let ((helixel--replay-multiplier
              (or (helixel-edit-payload-get tx :multiplier) 1)))
         (helixel-indent-right))))

;; ── Case operations ──

(helixel-define-operator helixel-toggle-case
    (:op toggle-case :display "~" :repeat-advance 'line
     :subcat case :params (&optional count))
  (interactive "p")
  (helixel--record-edit 'toggle-case :count (or count 1))
  (if (use-region-p)
      (let ((text (buffer-substring (region-beginning) (region-end))))
        (delete-region (region-beginning) (region-end))
        (insert (mapconcat (lambda (c)
                             (char-to-string
                              (if (eq c (upcase c)) (downcase c) (upcase c))))
                           text "")))
    (dotimes (_ (or count 1))
      (let ((c (following-char)))
        (delete-char 1)
        (insert (if (eq c (upcase c)) (downcase c) (upcase c))))))
  (helixel--clear-data))

(helixel-define-operator helixel-downcase
    (:op downcase :display "gu" :repeat-advance 'line
     :subcat case :params (&optional count))
  (interactive "p")
  (helixel--record-edit 'downcase :count (or count 1))
  (if (use-region-p)
      (downcase-region (region-beginning) (region-end))
    (downcase-word (or count 1)))
  (helixel--clear-data))

(helixel-define-operator helixel-upcase
    (:op upcase :display "gU" :repeat-advance 'line
     :subcat case :params (&optional count))
  (interactive "p")
  (helixel--record-edit 'upcase :count (or count 1))
  (if (use-region-p)
      (upcase-region (region-beginning) (region-end))
    (upcase-word (or count 1)))
  (helixel--clear-data))

;; ── Comment toggle ──

(helixel-define-operator helixel-comment-toggle
    (:op comment-toggle :display "gc" :repeat-advance 'line
     :subcat comment)
  (helixel--record-edit 'comment-toggle)
  (if (use-region-p)
      (comment-or-uncomment-region (region-beginning) (region-end))
    (comment-dwim nil))
  (helixel--clear-data))

;; ── Shell command filter ──

(helixel-define-operator helixel-shell-command
    (:op shell-command :display "!" :repeat-advance 'line
     :subcat shell)
  (helixel--record-edit 'shell-command)
  (let ((cmd (read-shell-command "!")))
    (if (use-region-p)
        (shell-command-on-region
         (region-beginning) (region-end) cmd nil nil
         (when current-prefix-arg
           (get-buffer-create "*Shell Command Output*")))
      (shell-command-on-region
       (line-beginning-position) (line-end-position) cmd nil nil
       (when current-prefix-arg
         (get-buffer-create "*Shell Command Output*")))))
  (helixel--clear-data))

;; ── Text formatting ──

(helixel-define-operator helixel-fill
    (:op fill :display "gq" :subcat fill)
  (helixel--record-edit 'fill)
  (if (use-region-p)
      (fill-region (region-beginning) (region-end))
    (fill-paragraph nil))
  (helixel--clear-data))

;; ── Join lines ──

(helixel-register-op join-lines :display "J" :repeat-advance nil
  :runner (lambda (tx)
            (let ((n (or (helixel-edit-payload-get tx :count) 2)))
              (dotimes (_ (1- n))
                (join-line 1)))))

(helixel-define-command helixel-join-lines
    (:category edit :subcat join-lines :params (&optional count))
  (interactive "p")
  (let ((n (max (or count 1) 2)))
    (helixel--record-edit 'join-lines :count n)
    (dotimes (_ (1- n))
      (join-line 1))
    (helixel--clear-data)))

;;; Line-wise helpers

(defun helixel--yank-handler-line-wise (text)
  "Insert TEXT as a complete line.
Dispatches on `this-command' to decide insertion position."
  (cond
   ((member this-command '(helixel-yank helixel-replace))
    (end-of-line)
    (newline)
    (insert (string-trim-right text "\n"))
    (beginning-of-line)
    (back-to-indentation))
   ((eq this-command 'helixel-yank-before)
    (beginning-of-line)
    (save-excursion
      (insert text)
      (unless (bolp) (newline)))
    (back-to-indentation))
   (t
    (insert text))))

(defun helixel--linewise-text (text)
  "Return a copy of TEXT propertized with line-wise yank-handler.
Ensures TEXT ends with a newline."
  (let ((s (if (and (> (length text) 0)
                    (/= (aref text (1- (length text))) ?\n))
               (concat text "\n")
             text)))
    (propertize s 'yank-handler '(helixel--yank-handler-line-wise nil t))))

(defun helixel--linewise-kill-p (&optional text)
  "Return non-nil if TEXT (default: top of kill ring) was killed line-wise."
  (when-let* ((s (or text
                     (and helixel--current-register
                          (helixel--current-kill 0 t))
                     (and kill-ring (helixel--current-kill 0 t)))))
    (eq (car-safe (get-text-property 0 'yank-handler s))
        'helixel--yank-handler-line-wise)))

(defun helixel--line-bounds-of-region ()
  "Return (BEG . END) expanded to full line boundaries.
BEG is at bol of `region-beginning', END includes the trailing newline."
  (when (use-region-p)
    (let ((beg (save-excursion (goto-char (region-beginning)) (pos-bol)))
          (end (save-excursion (goto-char (region-end))
                               (if (bolp) (point)
                                 (min (1+ (pos-eol)) (point-max))))))
      (cons beg end))))

;;; Rect-wise helpers

(defun helixel--yank-handler-rect-wise (lines)
  "Insert LINES as a rectangle at point."
  (insert-rectangle lines))

(defun helixel--rect-wise-text (strings)
  "Return a propertized string from STRINGS, a list of rect lines.
Tags the text with a rect-wise yank-handler for proper pasting."
  (let ((text (mapconcat #'identity strings "\n")))
    (propertize text 'yank-handler
                (list 'helixel--yank-handler-rect-wise strings t))))

(defun helixel--rect-wise-kill-p (&optional text)
  "Return non-nil if TEXT was killed as a rectangle."
  (when-let* ((s (or text
                     (and helixel--current-register
                          (helixel--current-kill 0 t))
                     (and kill-ring (helixel--current-kill 0 t)))))
    (eq (car-safe (get-text-property 0 'yank-handler s))
        'helixel--yank-handler-rect-wise)))

(defun helixel--rect-bounds-of-region ()
  "Return the rectangle bounds as a list of cons cells (BEG . END).
One per line of the rectangle."
  (when (and (use-region-p) rectangle-mark-mode)
    (extract-rectangle-bounds (region-beginning) (region-end))))

;;; Rect change with replay

(defun helixel--rect-change ()
  "Kill rectangle content, enter insert mode.
Replay typed text on all rectangle lines."
  (let* ((beg (region-beginning))
         (end (region-end))
         (line-count (count-lines beg end))
         (col (save-excursion (goto-char beg) (current-column)))
         (lines (extract-rectangle beg end)))
    (delete-rectangle beg end)
    (helixel--kill-new (helixel--rect-wise-text lines))
    (goto-char beg)
    (setq helixel--rect-replay-info
          `(:col ,col :line-count ,line-count :marker ,(point-marker)))
    (helixel--enter-insert)))

(defun helixel--rect-replay ()
  "Replay inserted text from rect change on remaining rectangle lines."
  (when-let* ((info (helixel--rect-replay-get))
              (col (plist-get info :col))
              (line-count (plist-get info :line-count))
              (marker (plist-get info :marker))
              ((marker-position marker)))
    (let ((text (buffer-substring marker (point))))
      (save-excursion
        (dotimes (_ (1- line-count))
          (forward-line 1)
          (move-to-column col t)
          (insert text))))
    (helixel--rect-replay-clear)))

;; ── Region replace / replace-char ──


(helixel-define-command helixel-replace-char
    (:category edit :subcat replace-char :params (char))
  (interactive "c")
  (helixel--record-edit 'replace-char :char char)
  (if (use-region-p)
      (helixel--replace-region
       (make-string (- (region-end) (region-beginning)) char)
       (region-beginning) (region-end))
    (helixel--replace-region
     (char-to-string char) (point) (1+ (point)))))


;; ── Region replacement utility ──

(defun helixel--replace-region (str beg end)
  "Replace region from BEG to END with STR.
Return the region replaced as (NEW-BEG . NEW-END)."
  (let* ((len (length str))
         (i-end 0)
         (i-beg 0)
         (i-end-ofs nil)
         (max-skip (min (- end beg) len)))
    ;; Skip common suffix.
    (while (and (< i-end max-skip)
                (eq (aref str (- len i-end 1))
                    (char-after (- end i-end 1))))
      (cl-incf i-end))
    (when (> i-end 0)
      (cl-decf len i-end)
      (cl-decf end i-end)
      (setq i-end-ofs i-end))
    ;; Skip common prefix.
    (setq max-skip (min (- end beg) len))
    (while (and (< i-beg max-skip)
                (eq (aref str i-beg)
                    (char-after (+ beg i-beg))))
      (cl-incf i-beg))
    (when (> i-beg 0)
      (cl-incf beg i-beg))
    ;; Trim common parts from str.
    (when (or (> i-beg 0) (> i-end 0))
      (setq str (substring-no-properties str i-beg len)))
    ;; Replace.
    (goto-char beg)
    (unless (eq beg end)
      (delete-region beg end))
    (unless (string-empty-p str)
      (insert str))
    (when i-end-ofs
      (goto-char (+ (point) i-end-ofs)))
    (cons beg (+ beg (length str)))))

(provide 'helixel-editing)
;;; helixel-editing.el ends here
