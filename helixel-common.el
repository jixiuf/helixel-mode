;;; helixel-common.el --- Editing and dot-repeat  -*- lexical-binding: t; -*-

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

(declare-function helixel-search--search "helixel-search"
                  (pattern dir &optional bound noerror))

;; ── Selection recreation ──
;; These functions rebuild selections from ctx during `.` replay.
;; Referenced by `helixel-sel-create' in helixel-state and helixel-move
;; as stored closures; called at runtime by `helixel--execute-edit'.

(defun helixel--recreate-line (ctx)
  "Replay a linewise selection from CTX.
When :entry-kind is present (insert ops), position cursor
at the appropriate offset on the selected line:
  :entry-kind insert \=`region-beginning' + cursor-offset
  :entry-kind append \=`region-end' + cursor-offset"
  (let ((n (helixel-sel-line-count ctx))
        (entry-kind (plist-get ctx :entry-kind)))
    (if (eq (helixel-sel-line-dir ctx) 'backward)
        (helixel-select-line-up n)
      (helixel-select-line n))
    ;; Signal error when buffer is empty (nothing to select).
    ;; The strategy catches this to stop iteration.
    (when (and (bobp) (eobp))
      (user-error "No more targets"))
    (when entry-kind
      ;; Position cursor for key/text insertion.
      ;; Use region-beginning/region-end because helixel-select-line
      ;; leaves point on the LAST selected line, so
      ;; line-beginning-position/line-end-position would target
      ;; the wrong line for multi-line selections.
      (if (eq entry-kind 'append)
          (goto-char (region-end))
        (let ((rend (region-end)))
          (goto-char (region-beginning))
          ;; If point landed on the mark (zero-length region),
          ;; restore the visible region so the selection highlight
          ;; shows the full target range.
          (when (= (point) (mark))
            (set-mark rend))))
      (let ((off (helixel-sel-insert-cursor-offset ctx)))
        (when off (forward-char off))))))

(defun helixel--recreate-rect (ctx)
  "Replay a rectangular selection from CTX."
  (let ((n (helixel-sel-rect-count ctx)))
    (unless rectangle-mark-mode
      (helixel--switch-state 'visual)
      (push-mark (point) t t)
      (rectangle-mark-mode 1))
    (dotimes (_ (1- n))
      (forward-line 1)
      (rectangle--reset-point-crutches))
    (setq helixel--selection-type 'rect)))

(defun helixel--recreate-movement (ctx)
  "Replay movement selection from CTX.
Signals `user-error' when point does not move (no more targets)."
  (let ((helixel--current-state 'visual)
        (saved-pos (point)))
    (dolist (m (reverse (helixel-sel-movement-moves ctx)))
      (dotimes (_ (cdr m))
        (funcall (car m))))
    ;; Signal error when movement commands produced no displacement.
    (when (= (point) saved-pos)
      (user-error "No more targets"))))

(defun helixel--recreate-search (ctx)
  "Replay search selection from CTX.
Finds the next match, activates the region on it.
If `helixel--search-advance-done' is t, skips the internal search
\(the advance function already positioned point and set `match-data').
If CTX has :entry-kind (insert or append), positions the cursor
at the appropriate offset within the match for insert-text ops."
  (let* ((pat (helixel-sel-search-pattern ctx))
         (dir (helixel-sel-search-dir ctx))
         (pre-skip-pos (point)))
    (unless pat
      (user-error "No search pattern to repeat"))
    (if helixel--search-advance-done
        (setq helixel--search-advance-done nil)
      ;; Internal search — only run when advance wasn't already done
      (when (and (helixel-sel-search-entry-kind ctx)
                 (let ((orig (point)))
                   (or (looking-at pat)
                       (save-excursion
                         (condition-case nil
                             (progn
                               (helixel-search--search
                                pat 'backward)
                               (let ((m-end (match-end 0))
                                     (m-beg (match-beginning 0)))
                                 (if (= m-beg m-end)
                                     (= (line-number-at-pos orig)
                                        (line-number-at-pos m-end))
                                   (<= (- orig m-end) (length pat)))))
                           (search-failed nil))))))
        (if (eq dir 'backward)
              (goto-char (max (point-min)
                              (1- (match-beginning 0))))
            (goto-char (if (= (match-beginning 0) (match-end 0))
                            (min (point-max) (1+ (match-end 0)))
                          (match-end 0))))
          (when (or (= (point) pre-skip-pos)
                    (and (eq dir 'forward) (= (point) (point-max)))
                    (and (eq dir 'backward) (= (point) (point-min))))
            (user-error "No more matches for %s" pat)))
      (condition-case nil
          (helixel-search--search pat dir)
        (search-failed
         (user-error "Search pattern not found: %s" pat))))
    (push-mark (match-beginning 0) t t)
    (goto-char (match-end 0))
    (setq helixel--selection-type 'char)
    (when-let* ((entry-kind (helixel-sel-search-entry-kind ctx)))
      (let* ((base (if (eq entry-kind 'append)
                       (match-end 0)
                     (match-beginning 0)))
             (cursor-offset (or (helixel-sel-search-cursor-offset ctx) 0)))
        (goto-char (+ base cursor-offset))))))

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


(require 'helixel-swap)

;; ── Edit-op change runner ──

(defun helixel--repeat-change-core (tx)
  "Repeat change TX: delete selection, replay kmacro keys or insert text.
TX is the complete edit transaction (see `helixel-edit-make').
Kmacro keys/commands (primary) capture the full insert-mode keystrokes.
Text (fallback) is used when keys/commands are unavailable (tests).

For rect selections the stored text is replayed on every subsequent
rectangle line via `helixel--rect-replay' — no state-switching side
-effect (avoids an unnecessary helixel-insert-exit during replay)."
  (let* ((keys (helixel--repeat-get-keys tx))
         (cmds (plist-get (helixel-edit-payload tx) :commands))
         (text (plist-get (helixel-edit-payload tx) :inserted-text)))
    (cond
     ((and (use-region-p) (eq (helixel--selection-type) 'rect))
      (helixel--rect-change)
      (if (or keys cmds)
          (helixel--execute-keys keys cmds)
        (when text (insert text)))
      (helixel--rect-replay))
     (t
      (helixel--delete-selection)
      (if (or keys cmds)
          (helixel--execute-keys keys cmds)
        (when text (insert text)))))))

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
             (let ((c (plist-get (helixel-edit-payload tx) :char)))
               (if c (format "R[%c]" c) "R")))
  :runner (lambda (tx)
            (helixel-replace-char
             (plist-get (helixel-edit-payload tx) :char))))

(helixel-register-op insert-text :display "i" :repeat-advance 'line
  :runner (lambda (tx)
            (let ((keys (plist-get (helixel-edit-payload tx) :keys))
                  (cmds (plist-get (helixel-edit-payload tx) :commands)))
              (if (or keys cmds)
                  (progn (helixel--execute-keys keys cmds))
                (insert (or (plist-get (helixel-edit-payload tx) :text)
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
        (let ((helixel--inhibit-repeat-record t))
          (helixel-yank))
        (setq helixel--replace-pop-bounds
              (cons pop-start (point)))))
      (helixel--register-consume)
      (helixel--clear-data))))

;; `helixel-replace-pop' cycles through the `kill-ring' to replace
;; the text inserted by the previous `helixel-replace' or
;; `helixel-replace-pop', similar to `yank-pop'.
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
  (if (memq last-command '(helixel-replace helixel-replace-pop))
      ;; ── Cycle: replace bounds text with next kill-ring entry ──
      (progn
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
              (cons pop-start (point))))))))

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
      ;; amalgamate multiplier into the last tx.
      (when-let* ((tx helixel--last-tx)
                  (sel (helixel-edit-sel tx)))
        (when (eq (helixel-edit-op tx) 'indent-left)
          (when-let* ((m (helixel-edit-marker tx))
                      (pos (marker-position m)))
            (goto-char pos))
          (let ((helixel--inhibit-action-track t))
            (helixel--recreate-selection sel))
          (indent-rigidly (region-beginning) (region-end) (- 1))
          (let* ((payload (helixel-edit-payload tx))
                 (mult (or (plist-get payload :multiplier) 1)))
            (helixel--update-last-tx
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
              (or (plist-get (helixel-edit-payload tx) :multiplier) 1)))
         (helixel-indent-left))))

(helixel-define-operator helixel-indent-right
    (:op indent-right :display ">" :repeat-advance 'line
     :params (&optional count))
  (interactive "p")
  (let* ((n (or helixel--replay-multiplier count 1))
         (consecutive-p nil))
    (unless (use-region-p)
      ;; Consecutive (same op): reuse selection, indent 1 level,
      ;; amalgamate multiplier into the last tx.
      (when-let* ((tx helixel--last-tx)
                  (sel (helixel-edit-sel tx)))
        (when (eq (helixel-edit-op tx) 'indent-right)
          (when-let* ((m (helixel-edit-marker tx))
                      (pos (marker-position m)))
            (goto-char pos))
          (let ((helixel--inhibit-action-track t))
            (helixel--recreate-selection sel))
          (indent-rigidly (region-beginning) (region-end) 1)
          (let* ((payload (helixel-edit-payload tx))
                 (mult (or (plist-get payload :multiplier) 1)))
            (helixel--update-last-tx
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
              (or (plist-get (helixel-edit-payload tx) :multiplier) 1)))
         (helixel-indent-right))))

;; ── Case operations ──

(helixel-define-operator helixel-toggle-case
    (:op toggle-case :display "~" :subcat case
     :params (&optional count))
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
    (:op comment-toggle :display "gc" :subcat comment)
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
            (let ((n (or (plist-get (helixel-edit-payload tx) :count) 2)))
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

(provide 'helixel-common)
;;; helixel-common.el ends here
