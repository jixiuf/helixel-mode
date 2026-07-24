;;; helixel-editing.el --- Edit commands, selection recreate, op runners  -*- lexical-binding: t; -*-

;; Copyright (C) 2025-2026  jixiuf

;; Author: jixiuf <https://github.com/jixiuf>
;; Keywords: convenience
;; URL: https://github.com/jixiuf/helixel-mode
;; SPDX-License-Identifier: GPL-3.0-or-later

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
;; `helixel--region-type' validator.
;;
;; Keymaps are NOT loaded here — `helixel-keymap' is loaded separately
;; by `helixel.el' after this file.

;;; Code:

(require 'cl-lib)
(require 'rect)
(require 'helixel-state)
(require 'helixel-move)
(require 'helixel-core)
(require 'helixel-macros)
(defvar helixel-chain-insert-entry-functions)
(require 'helixel-search)
(require 'helixel-register)

(defsubst helixel--swap-source-type ()
  "Return the swap-source type for the current selection.
Returns nil (char), \=`line', or \=`rect'.
More permissive than `helixel--region-type' — detects
`rectangle-mark-mode' directly."
  (cond
   ((eq (helixel--sel-type) 'rect) 'rect)
   ((eq (helixel--sel-type) 'line) 'line)
   ((bound-and-true-p rectangle-mark-mode) 'rect)
   (t nil)))

;; ── Insert-entry prepositioner helpers ──
;;
;; Each insert-entry command (`helixel-insert' / `-after' / `-bol' /
;; `-eol' / `-newline' / `-prevline') declares a `:preposition' that
;; just calls one of these helpers.  The multi-cursor dispatcher
;; invokes the runner at every fake cursor through the unified
;; `helixel-action-replay' path — each helper runs in the fake's
;; restored context (point, mark, mark-active per `helixel-cs').
;;
;; They live here (NOT in `helixel-mc-integrate.el') so the
;; insert-entry commands have a direct same-file reference and no
;; forward `declare-function' is needed.  Tests still find them by
;; name.

(defun helixel-mc--prepos-region-begin (_tx)
  "Move to `region-beginning' if `mark-active', else stay.
_TX is the replayed action, ignored (kept for the preposition calling
convention `(funcall PRE TX)').
For `i' / `helixel-insert' semantics: enter insert with point at
the START of any active selection."
  (when (and mark-active (mark t))
    (goto-char (min (point) (mark t))))
  (setq mark-active nil))

(defun helixel-mc--prepos-region-end (_tx)
  "Move to `region-end' if `mark-active', else `forward-char'.
For `a' / `helixel-insert-after' semantics: enter insert with
point AFTER the selection (or one char past point if no region)."
  (if (and mark-active (mark t))
      (goto-char (max (point) (mark t)))
    (unless (eolp) (forward-char)))
  (setq mark-active nil))

(defun helixel-mc--prepos-bol (_tx)
  "Move to beginning of line at this fake cursor (I semantics)."
  (beginning-of-line))

(defun helixel-mc--prepos-eol (_tx)
  "Move to end of line at this fake cursor (A semantics)."
  (end-of-line))

(defun helixel-mc--prepos-newline-after (_tx)
  "Open a new line below this fake cursor (`o' semantics)."
  (end-of-line)
  (newline-and-indent))

(defun helixel-mc--prepos-newline-before (_tx)
  "Open a new line above this fake cursor (O semantics)."
  (beginning-of-line)
  (let ((electric-indent-mode nil))
    (newline nil t)
    (forward-line -1)
    (indent-according-to-mode)))

;; ── Shared kill core ──

(defun helixel-delete-selection (&optional noyank)
  "Delete current region or char at point.
When NOYANK is non-nil, do NOT push to `kill-ring' or registers
\(Vim `\"_d' / Helix black-hole semantics).  Otherwise pushes to
`kill-ring' and populates rotate / small-delete registers.
Does NOT record an edit and does NOT clear selection data.
Used by `helixel-kill' (NOYANK nil), `helixel-delete' (NOYANK t),
`helixel-change', and `helixel--repeat-change-core'."
  (cond
   ((not (use-region-p))
    (unless noyank
      (helixel--kill-new (char-to-string (char-after))))
    (delete-char 1))
   ((eq (helixel--region-type) 'rect)
    (unless noyank
      (let ((lines (extract-rectangle (region-beginning) (region-end))))
        (helixel--kill-new (helixel--rect-wise-text lines))))
    (delete-rectangle (region-beginning) (region-end)))
   ((eq (helixel--region-type) 'line)
    (if-let* ((bounds (helixel--line-bounds-of-region)))
        (let ((text (unless noyank
                      (filter-buffer-substring (car bounds) (cdr bounds)))))
          (when text (helixel--kill-new (helixel--linewise-text text)))
          (delete-region (car bounds) (cdr bounds)))))
   (t
    (unless noyank
      (helixel--kill-new
       (filter-buffer-substring (region-beginning) (region-end))))
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
  (let ((offset (helixel-insert-search-offset-sel-offset ctx)))
    (goto-char (+ (match-beginning 0) offset))))

;; ── Insert-entry tail helper ──
;;
;; Every insert variant command ends with the same three steps:
;;   1. Record 'insert-text as the operation
;;   2. Snap `helixel--change-track-marker' at point
;;   3. Enter insert mode
;;
;; `helixel--prepare-insert-entry' encapsulates this tail.
;; Commands that have already called `helixel-record-action' earlier
;; (to interleave setup between record and marker snap) pass nil for
;; RECORD-P to skip the redundant record call.

(defun helixel--prepare-insert-entry (&optional record-p)
  "Prepare for insert-mode entry: record, snap marker, enter insert.
Calls `helixel-record-action' (unless RECORD-P is nil).
After recording, snaps `helixel--change-track-marker' at point
and enters insert mode.

Pass nil for RECORD-P when the caller has already called
`helixel-record-action' earlier (e.g. `helixel-insert-newline').
Otherwise RECORD-P defaults to t via the wrapper body."
  (setq record-p (or record-p t))
  (when record-p
    (helixel-record-action 'insert-text))
  (setq helixel--change-track-marker (point-marker))
  (helixel--enter-insert))

;; ── Insert-* kind registrations ──
;; Recreate functions defined here; advance functions in helixel-repeat.el.

(cl-defstruct (helixel-insert-selection-start-sel (:include helixel-sel)
                                                  (:copier nil))
  "Insert-at-selection-start selection.  Slots: CURSOR-OFFSET, ENTRY-KIND."
  cursor-offset
  entry-kind)


(cl-defstruct (helixel-insert-selection-end-sel (:include helixel-sel)
                                                (:copier nil))
  "Insert-at-selection-end selection.  Slots: CURSOR-OFFSET, ENTRY-KIND."
  cursor-offset
  entry-kind)


(cl-defstruct (helixel-insert-beginning-line-sel (:include helixel-sel)
                                                 (:copier nil))
  "Insert-at-beginning-of-line selection.  No kind-specific slots.")


(cl-defstruct (helixel-insert-end-line-sel (:include helixel-sel)
                                           (:copier nil))
  "Insert-at-end-of-line selection.  No kind-specific slots.")


(cl-defstruct (helixel-insert-search-offset-sel (:include helixel-sel)
                                                (:copier nil))
  "Insert-with-search-offset selection.  Slots: OFFSET."
  offset)


(cl-defmethod helixel-sel-entry-kind ((sel helixel-insert-selection-start-sel))
  "Return the entry-kind of SEL."
  (helixel-insert-selection-start-sel-entry-kind sel))

(cl-defmethod helixel-sel-entry-kind ((sel helixel-insert-selection-end-sel))
  "Return the entry-kind of SEL."
  (helixel-insert-selection-end-sel-entry-kind sel))

(cl-defmethod helixel-sel-insert-cursor-offset ((sel helixel-insert-selection-start-sel))
  "Return the cursor offset of SEL."
  (helixel-insert-selection-start-sel-cursor-offset sel))

(cl-defmethod helixel-sel-insert-cursor-offset ((sel helixel-insert-selection-end-sel))
  "Return the cursor offset of SEL."
  (helixel-insert-selection-end-sel-cursor-offset sel))

(defmacro helixel--def-insert-sel-methods (struct display recreate advance)
  "Define insert-kind methods for STRUCT: DISPLAY string, RECREATE fn, ADVANCE fn."
  `(progn
     (cl-defmethod helixel-sel-recreate ((sel ,struct))
       "Sel recreate method for SEL."
       ,(if recreate `(,recreate sel) '(ignore)))
     (cl-defmethod helixel-sel-advance-fn ((_sel ,struct))
       "Sel advance fn method for SEL."
       ,advance)
     (cl-defmethod helixel-sel-display ((_sel ,struct)) ,display)))

(helixel--def-insert-sel-methods
 helixel-insert-selection-start-sel "i"
 helixel--recreate-insert-selection-start #'helixel--repeat-advance-search)
(helixel--def-insert-sel-methods
 helixel-insert-selection-end-sel "a"
 helixel--recreate-insert-selection-end #'helixel--repeat-advance-search)
(helixel--def-insert-sel-methods
 helixel-insert-beginning-line-sel "I"
 helixel--recreate-insert-beginning-line #'helixel--repeat-advance-line)
(helixel--def-insert-sel-methods
 helixel-insert-end-line-sel "A"
 helixel--recreate-insert-end-line #'helixel--repeat-advance-line)
(helixel--def-insert-sel-methods
 helixel-insert-search-offset-sel "s"
 helixel--recreate-insert-search-offset #'helixel--repeat-advance-search)

(helixel-define-command helixel-insert
    (:category state :subcat insert
               :preposition #'helixel-mc--prepos-region-begin)
  (let ((kind (and helixel--pending-sel
                   (helixel-sel-kind helixel--pending-sel))))
    (cond
     ;; Search or line context: preserve sel (just tag entry-kind)
     ;; for `.` auto-advance.
     ((memq kind '(helixel-search-sel helixel-line-sel))
      (helixel--sel-push
       (helixel-sel-update-ctx helixel--pending-sel
                               :entry-kind 'insert))
      (run-hook-with-args
       'helixel-chain-insert-entry-functions 'insert)
      (when mark-active
        (goto-char (region-beginning))))
     ;; Manual region
     ((use-region-p)
      (helixel--sel-push
       (make-helixel-insert-selection-start-sel))
      (when mark-active
        (goto-char (region-beginning))))
     ;; No context
     (t
      (setq helixel--pending-sel nil))))
  (helixel--prepare-insert-entry))

(helixel-define-command helixel-insert-exit
    (:category state :subcat exit)
  (let* ((keys (helixel--insert-finish))
         (text (when helixel--change-track-marker
                 (and (marker-position helixel--change-track-marker)
                      (buffer-substring
                       helixel--change-track-marker (point))))))
    (unless executing-kbd-macro
      (when helixel-last-action
        (let ((tx helixel-last-action))
          ;; Store keys as primary replay mechanism
          (when (and keys (> (length keys) 0))
            (setq tx (helixel-action-with-payload tx :keys keys)))
          ;; Store text as replay fallback (tests, programmatic use)
          (when text
            (setq tx (helixel-action-with-payload tx :text text))
            (when (memq (helixel-action-op tx) '(change change-noyank))
              (setq tx (helixel-action-with-payload tx
                                                    :inserted-text text))))
          (helixel--update-last-action tx))))
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
    (:category state :subcat insert
               :preposition #'helixel-mc--prepos-region-end)
  (let ((kind (and helixel--pending-sel
                   (helixel-sel-kind helixel--pending-sel))))
    (cond
     ;; Search or line context: preserve sel (just tag entry-kind)
     ;; for `.` auto-advance.
     ((memq kind '(helixel-search-sel helixel-line-sel))
      (helixel--sel-push
       (helixel-sel-update-ctx helixel--pending-sel
                               :entry-kind 'append))
      (run-hook-with-args
       'helixel-chain-insert-entry-functions 'append)
      (when mark-active
        (goto-char (region-end))))
     ;; Manual region
     ((use-region-p)
      (helixel--sel-push
       (make-helixel-insert-selection-end-sel))
      (when mark-active
        (goto-char (region-end))))
     ;; No context
     (t
      (unless (helixel--end-of-line-p)
        (forward-char))
      (setq helixel--pending-sel nil))))
  (helixel--prepare-insert-entry))

(helixel-define-command helixel-insert-beginning-line
    (:category state :subcat insert
               :preposition #'helixel-mc--prepos-bol)
  (beginning-of-line)
  (helixel--sel-push
   (make-helixel-insert-beginning-line-sel))
  (helixel--prepare-insert-entry))

(helixel-define-command helixel-insert-after-end-line
    (:category state :subcat insert
               :preposition #'helixel-mc--prepos-eol)
  (end-of-line)
  (helixel--sel-push
   (make-helixel-insert-end-line-sel))
  (helixel--prepare-insert-entry))

(helixel-define-command helixel-insert-newline
    (:category state :subcat insert
               :preposition #'helixel-mc--prepos-newline-after)
  (helixel-record-action 'insert-text)
  (helixel-clear-data)
  (end-of-line)
  (newline-and-indent)
  (helixel--prepare-insert-entry nil))

(helixel-define-command helixel-insert-prevline
    (:category state :subcat insert
               :preposition #'helixel-mc--prepos-newline-before)
  (helixel-record-action 'insert-text)
  (helixel-clear-data)
  (beginning-of-line)
  (let ((electric-indent-mode nil))
    (newline nil t)
    (call-interactively #'previous-line)
    (indent-according-to-mode))
  (helixel--prepare-insert-entry nil))


;; ── Edit-op change runner ──

(defun helixel--repeat-change-core (tx &optional noyank)
  "Repeat change TX: delete selection, replay keys or insert text.
TX is the complete edit transaction (see `helixel-action-create').
Keys (primary) capture the full insert-mode keystrokes.
Text (fallback) is used when keys are unavailable (tests).
When NOYANK is non-nil, skip pushing deleted text to `kill-ring'.

For rect selections the stored text is replayed on every subsequent
rectangle line via `helixel--rect-replay' — no state-switching side
-effect (avoids an unnecessary `helixel-insert-exit' during replay)."
  (let* ((keys (helixel--repeat-get-keys tx))
         (text (helixel-action-payload-get tx :inserted-text)))
    (cond
     ((and (use-region-p) (eq (helixel--region-type) 'rect))
      (helixel--rect-change noyank)
      (if keys
          (helixel--execute-keys keys)
        (when text (insert text)))
      (helixel--rect-replay))
     (t
      ;; Save the region-beginning set by the advance function
      ;; so we can restore an active region afterward for
      ;; undo-in-region.
      (let ((sel-beg (region-beginning)))
        (helixel-delete-selection noyank)
        ;; Deactivate the mark left by the deleted selection
        ;; so that key replay (e.g. delete-backward-char) does
        ;; not see an active region and delete the wrong span.
        (deactivate-mark)
        (if keys
            (helixel--execute-keys keys)
          (when text (insert text)))
        ;; Restore an active region covering the replayed edit
        ;; so undo-in-region limits undo to this replay only.
        ;; Skip in mc-fake context — the undo amalgamation already
        ;; isolates each fake, and a stale active mark would leak
        ;; as a fake-cursor region overlay after dispatch.
        (unless (helixel--replay-in-fake-p)
          (push-mark sel-beg t t)))))))

;; ── Edit-op registry ──
;; Each operator registers a `:runner' (called by `.`) and a `:display'
;; label via `helixel-register-op' or `helixel-define-operator'.
;; Runners call the editing commands defined below.

;; Ops whose `.` runner IS the command → use `helixel-define-operator'
;; below (kill, copy, replace, paste-after, paste-before).

;; Ops with non-trivial runners (need tx payload) → register separately:
(helixel-register-op change :display "c" :self-advancing t
                     :runner #'helixel--repeat-change-core)

(defun helixel--repeat-change-noyank (tx)
  "Replay `change-noyank' from TX (named runner, pure-data op entry)."
  (helixel--repeat-change-core tx t))

(helixel-register-op change-noyank :display "C" :self-advancing t
                     :runner #'helixel--repeat-change-noyank)

(defun helixel--display-replace-char (tx)
  "Return the display label for a `replace-char' TX (named display fn)."
  (let ((c (helixel-action-char tx)))
    (if c (format "R[%c]" c) "R")))

(defun helixel--repeat-replace-char (tx)
  "Replay `replace-char' from TX (named runner, pure-data op entry)."
  (helixel-replace-char (helixel-action-char tx)))

(helixel-register-op replace-char :self-advancing nil
                     :display #'helixel--display-replace-char
                     :runner #'helixel--repeat-replace-char)

(defun helixel--repeat-insert-text (tx)
  "Replay an `insert-text' TX: re-execute recorded keys, or insert :text."
  (let ((keys (helixel--repeat-get-keys tx)))
    (if keys
        (helixel--execute-keys keys)
      (insert (or (helixel-action-payload-get tx :text) "")))))

(helixel-register-op insert-text :display "i" :self-advancing nil
                     :runner #'helixel--repeat-insert-text)


;; ── Kill & Change ──

(helixel-define-operator helixel-kill
    (:op kill :display "d" :self-advancing t)
  (helixel-record-action 'kill)
  (helixel-delete-selection)
  (helixel--register-consume)
  (helixel-clear-data))

(helixel-define-operator helixel-delete
    (:op delete :display "D" :self-advancing t)
  (helixel-record-action 'delete)
  (helixel-delete-selection t)
  (helixel-clear-data))

(helixel-define-operator helixel-delete-backward-char
    (:op delete-backward-char :display "BS" :self-advancing t)
  (helixel-record-action 'delete-backward-char)
  (cond
   ((and (use-region-p) delete-active-region)
    (helixel-delete-selection t))
   ((bobp)) ; no-op at beginning of buffer
   (t
    (backward-delete-char-untabify 1 nil)))
  (helixel-clear-data))

(helixel-define-operator helixel-delete-backward-word
    (:op delete-backward-word :display "C-BS" :self-advancing t)
  (helixel-record-action 'delete-backward-word)
  (if (and (use-region-p) delete-active-region)
      (helixel-delete-selection t)
    (unless (bobp)
      (let ((end (point)))
        (forward-word -1)
        (delete-region (point) end))))
  (helixel-clear-data))

(helixel-define-command helixel-change
    (:category edit :subcat change)
  (helixel-record-action 'change)
  (if (and (use-region-p) (eq (helixel--region-type) 'rect))
      (progn (helixel--rect-change)
             (helixel--register-consume))
    (helixel-delete-selection)
    (helixel--register-consume)
    (setq helixel--change-track-marker (point-marker))
    (helixel--enter-insert)))

(helixel-define-command helixel-change-noyank
    (:category edit :subcat change-noyank)
  (helixel-record-action 'change-noyank)
  (if (and (use-region-p) (eq (helixel--region-type) 'rect))
      (helixel--rect-change t)
    (progn
      (helixel-delete-selection t)
      (setq helixel--change-track-marker (point-marker))
      (helixel--enter-insert))))

;; ── Replace ──

(defvar helixel--yank-pop-bounds nil
  "Bounds (BEG . END) of text from `helixel-replace' or `helixel-yank-pop'.
Value is nil after a rectangle replace.
Used to support cycling through the kill ring after a replace.")

(defun helixel--replace-do (text &optional yank-fallback-fn)
  "Delete current region (or char) and insert TEXT respecting selection type.
Updates `helixel--yank-pop-bounds' with the inserted range, or
nils it for rectangle replaces.  Returns the inserted bounds.

TEXT is the `kill-ring' entry to insert.  YANK-FALLBACK-FN, when
non-nil, is called in the no-region case (replace char at point)
instead of `insert-for-yank' — `helixel-replace' passes
`helixel-yank' so its dot-replay path runs."
  (let* ((linewise-p (helixel--linewise-kill-p text))
         (rectwise-p (helixel--rect-wise-kill-p text))
         (bare (string-trim-right (substring-no-properties text) "\n"))
         (pop-start nil))
    (cond
     ;; Rect selection — no pop tracking (rect bounds are multi-line)
     ((and (use-region-p) (eq (helixel--region-type) 'rect))
      (let* ((beg (region-beginning))
             (end (region-end))
             (lines (nth 1 (get-text-property 0 'yank-handler text)))
             (deleted-lines (extract-rectangle beg end)))
        (helixel--register-store-delete
         (helixel--rect-wise-text deleted-lines))
        (delete-rectangle beg end)
        (goto-char beg)
        (if (and rectwise-p lines)
            (insert-rectangle (mapcar #'substring-no-properties lines))
          (insert bare)))
      (setq helixel--yank-pop-bounds nil))
     ;; Line-wise selection: expand to full line bounds
     ((and (use-region-p) (eq (helixel--region-type) 'line))
      (when-let* ((bounds (helixel--line-bounds-of-region)))
        (let ((deleted-text (filter-buffer-substring
                             (car bounds) (cdr bounds))))
          (helixel--register-store-delete
           (helixel--linewise-text deleted-text)))
        (delete-region (car bounds) (cdr bounds))
        (setq pop-start (point))
        ;; Strip properties to prevent yank-handler leaking into buffer
        (insert (if linewise-p (substring-no-properties text)
                  (concat bare "\n")))
        (setq helixel--yank-pop-bounds
              (cons pop-start (point)))))
     ;; Charwise region
     ((use-region-p)
      (helixel--register-store-delete
       (filter-buffer-substring (region-beginning) (region-end)))
      (delete-region (region-beginning) (region-end))
      (setq pop-start (point))
      (insert (if (or linewise-p rectwise-p)
                  bare
                (substring-no-properties text)))
      (setq helixel--yank-pop-bounds
            (cons pop-start (point))))
     ;; No region — replace char at point
     (t
      (let ((deleted-char nil))
        (when helixel-replace-delete-char-p
          (setq deleted-char (char-to-string (char-after)))
          (delete-char 1))
        (setq pop-start (point))
        (if yank-fallback-fn
            (let ((end-marker (copy-marker (point) t)))
              (funcall yank-fallback-fn)
              (setq helixel--yank-pop-bounds
                    (cons pop-start (marker-position end-marker)))
              (set-marker end-marker nil))
          (insert-for-yank text)
          (setq helixel--yank-pop-bounds
                (cons pop-start (point))))
        ;; Store deleted char to registers AFTER insertion so
        ;; yank-fallback-fn can still read the original register.
        (when deleted-char
          (helixel--register-store-delete deleted-char)))))))

(helixel-define-operator helixel-replace
    (:op replace :display "r" :self-advancing nil)
  (if (and (not (helixel--register-active-p))
           (= 0 (length kill-ring)))
      (message "nothing to yank")
    (let ((text (or (helixel--current-kill 0) (current-kill 0))))
      (helixel--replace-do
       text
       (lambda () (helixel-with-replay-as 'dot (helixel--yank-body nil))))
      (helixel--register-consume)
      ;; Store paste bounds as mark-region for \\[helixel-action-cycle]
      ;; re-select.
      (when helixel--yank-pop-bounds
        (helixel--set-mark-region helixel--yank-pop-bounds))
      (helixel-record-action 'replace)
      (helixel-clear-data))))

;; `helixel-yank-pop' cycles through the `kill-ring' to replace
;; the text inserted by the previous `helixel-replace' or
;; `helixel-yank-pop', similar to `yank-pop'.
;;
;; When called after `yank' or `yank-pop', degrades to `yank-pop'
;; to replace the just-yanked text with the next `kill-ring' entry.
;;
;; When called after `helixel-replace' or `helixel-yank-pop',
;; ARG advances N kills forward (default 1).
;;
;; When called directly, prompts to select a `kill-ring' entry and
;; replaces the region/char-at-point with it, like `helixel-replace'
;; but letting you choose which kill to use.  Subsequent calls
;; then cycle through the `kill-ring' as usual.
(helixel-define-command helixel-yank-pop
    (:category edit :subcat yank-pop :params (&optional arg))
  (interactive "*p")
  (setq arg (or arg 1))
  (let ((bounds
         (cond
          ((and helixel--yank-pop-bounds
                (memq last-command
                      '(helixel-replace helixel-yank-pop
                                        helixel-yank helixel-yank-before)))
           helixel--yank-pop-bounds)
          ;; After yank or replace: use mark position to find
          ;; the yanked/replaced text even when mark is inactive
          ;; (Emacs 32 yank no longer activates mark).
          ((and (memq last-command
                      '(helixel-yank helixel-yank-before
                                     helixel-replace yank yank-pop))
                (mark t))
           (let ((m (mark t)) (p (point)))
             (if (/= m p)
                 (cons (min m p) (max m p))
               nil))))))
    (if bounds
        ;; ── Cycle: replace bounds text with next kill-ring entry ──
        (let* ((b (car bounds))
               (e (cdr bounds))
               ;; Normalize: beg <= end
               (beg (min b e))
               (end (max b e))
               (inhibit-read-only t)
               (text (helixel--current-kill arg))
               (ends-with-newline (and (> end (point-min))
                                       (char-equal (char-before end) ?\n))))
          (setq this-command 'helixel-yank-pop)
          (delete-region beg end)
          (goto-char beg)
          (if (and ends-with-newline
                   (not (string-suffix-p "\n" text)))
              (insert text "\n")
            (insert-for-yank text))
          (setq helixel--yank-pop-bounds (cons beg (point)))
          ;; Store bounds as mark-region for \\[helixel-action-cycle] re-select.
          (helixel--set-mark-region (cons beg (point))))
      ;; No bounds available — fall back or browse.
      (if (memq last-command '(helixel-yank helixel-yank-before
                                            helixel-replace yank yank-pop
                                            helixel-yank-pop))
          ;; After a yank/replace with no region, delegate to yank-pop.
          ;; Capture bounds afterward so subsequent
          ;; \\[helixel-yank-pop\\] cycles via the
          ;; helixel--yank-pop-bounds path (yank-pop may not set them).
          (progn
            (yank-pop arg)
            (when-let* ((m (mark t))
                        ((/= m (point))))
              (setq helixel--yank-pop-bounds
                    (cons (min m (point)) (max m (point)))))
            (setq this-command 'helixel-yank-pop))
        ;; ── Direct call: browse kill-ring and replace ──
        (let* ((candidates (mapcar #'substring-no-properties kill-ring))
               (collection
                (lambda (s p a)
                  (if (eq a 'metadata)
                      '(metadata (category . helixel-yank-pop)
                                 (cycle-sort-function . identity)
                                 (display-sort-function . identity))
                    (complete-with-action a candidates s p))))
               (selected (completing-read "Replace with: " collection nil t))
               (idx (cl-position selected candidates :test #'string=))
               (text (nth idx kill-ring)))
          (unless text (user-error "No kill-ring entry selected"))
          (setq kill-ring-yank-pointer (nthcdr idx kill-ring))
          (setq this-command 'helixel-yank-pop)
          (helixel--replace-do text))))))

;; ── Copy ──

(helixel-define-operator helixel-kill-ring-save
    (:op copy :display "y" :self-advancing nil)
  (when (and transient-mark-mode mark-active (mark))
    (let ((swap-source
           (list :beg (copy-marker (region-beginning))
                 :end (copy-marker (region-end))
                 :buffer (current-buffer)
                 :type (helixel--swap-source-type))))
      ;; Store swap-source.  In mc mode each fake cursor stores to
      ;; its own per-cursor variable; the real cursor stores to the
      ;; global register (for non-mc fallback and cross-buffer use).
      (if (helixel--replay-in-fake-p)
          (setq helixel--yank-register-source swap-source)
        (set-register helixel--yank-register swap-source))
      (when (use-region-p) ;; non-zero-width: store text on kill-ring
        (cond
         ((eq (helixel--region-type) 'rect)
          (let ((lines (extract-rectangle (region-beginning) (region-end))))
            (helixel--kill-new
             (helixel--rect-wise-text lines)
             :copy)))
         ((eq (helixel--region-type) 'line)
          (when-let* ((bounds (helixel--line-bounds-of-region))
                      (text (filter-buffer-substring
                             (car bounds) (cdr bounds))))
            (helixel--kill-new
             (helixel--linewise-text text)
             :copy)))
         (t
          (helixel--kill-new
           (filter-buffer-substring (region-beginning) (region-end))
           :copy))))
      ;; Store the copied region as mark-region for ; re-select.
      (helixel--set-mark-region (cons (region-beginning) (region-end)))))
  (helixel--register-consume)
  (helixel-record-action 'copy)
  (helixel-clear-data))

;; ── Yank ──

(defun helixel--yank-body (arg &optional paste-after-p)
  "Shared body for `helixel-yank' / `helixel-yank-before'.
Dispatches rect, linewise, or plain yank with ARG, then consumes
the register.
When PASTE-AFTER-P is non-nil (direct `p' without selection or
replay), moves past the current character first (Vim-like p),
unless at eol.
ARG is the raw prefix argument; when > 1, the yank repeats
that many times (Vim-like 2p, 3P)."
  ;; For direct p without selection, move past current char.
  ;; Applies to all kill types: line handler overrides position
  ;; (end-of-line), rect shifts one column right as Vim does.
  (when (and paste-after-p
             (not (helixel-replaying-p))
             (not (use-region-p))
             (not (helixel--end-of-line-p)))
    (forward-char))
  ;; Marker set before paste stays before inserted text.
  ;; After pasting we jump back so cursor lands at the
  ;; start of the pasted content (Helix convention).
  ;; Line-wise handler positions cursor itself.
  (let ((count (prefix-numeric-value arg))
        (start (point-marker)))
    (prog1
        (cond
         ((helixel--rect-wise-kill-p)
          (let* ((text (helixel--current-kill 0 t))
                 (lines (when text
                          (nth 1 (get-text-property
                                  0 'yank-handler text))))
                 ;; Save position so repeated rect pastes don't drift.
                 (col (current-column))
                 (ln (line-number-at-pos)))
            (dotimes (_ count)
              (goto-char (point-min))
              (forward-line (1- ln))
              (move-to-column col t)
              (if lines
                  (insert-rectangle (mapcar #'substring-no-properties lines))
                (when text (insert-for-yank text))))))
         ((helixel--linewise-kill-p)
          (dotimes (_ count)
            (let ((text (helixel--current-kill 0 t)))
              (when text (insert-for-yank text)))))
         (t
          ;; For charwise with named register, insert the register
          ;; text count times without consuming the register each time.
          (if (helixel--register-active-p)
              (let ((text (helixel--register-get helixel--current-register)))
                (dotimes (_ count)
                  (if text
                      (insert-for-yank text)
                    (message "Register \"%c is empty"
                             helixel--current-register))))
            (dotimes (_ count)
              (yank 1)))))
      (helixel--register-consume)
      (helixel--register-consume)
      ;; Store pasted bounds as mark-region for \\[helixel-action-cycle]
      ;; re-select,
      ;; and as yank-pop-bounds for \\[helixel-yank-pop\\] cycling.
      (let ((bounds nil))
        (cond
         ;; Line-wise: handler already positioned cursor.
         ((helixel--linewise-kill-p)
          (if (or paste-after-p
                  ;; Replace handler positions point at bol of the
                  ;; inserted text (same as p), so use current line.
                  (eq (or helixel--current-command this-command)
                      'helixel-replace))
              ;; p / replace: pasted at-or-below current line.
              (setq bounds (cons (pos-bol) (pos-eol)))
            ;; P: pasted above, select previous line.
            (save-excursion
              (forward-line -1)
              (setq bounds (cons (pos-bol) (pos-eol))))))
         ;; Charwise / rect: use start marker.
         (start
          (let ((end (point-marker)))
            (setq bounds (cons (marker-position start)
                               (marker-position end)))
            (set-marker end nil))))
        (when bounds
          (helixel--set-mark-region bounds)
          ;; Also set pop-bounds so \\[helixel-yank-pop\\] can find the
          ;; pasted text.
          (setq helixel--yank-pop-bounds bounds)))
      ;; Restore cursor to start for char/rect (line handler does its own).
      (when start
        (unless (helixel--linewise-kill-p)
          (when (marker-position start) (goto-char start)))
        (set-marker start nil)))))

(helixel-define-operator helixel-yank
    (:op paste-after :display "p" :self-advancing nil
         :params (&optional arg))
  (interactive "*P")
  ;; Paste after: if selection active, go to end of selection.
  ;; For rect selection, stay on same row — only move column
  ;; to region-end, so insert-rectangle starts on the correct line.
  (when (use-region-p)
    (if rectangle-mark-mode
        (move-to-column (save-excursion
                          (goto-char (region-end))
                          (current-column)) t)
      (goto-char (region-end))))
  ;; Clear stale pop bounds from previous replace.
  (setq helixel--yank-pop-bounds nil)
  (helixel--yank-body arg t)
  (helixel-record-action 'paste-after))

(helixel-define-operator helixel-yank-before
    (:op paste-before :display "P" :self-advancing nil
         :params (&optional arg))
  (interactive "*P")
  ;; Paste before: if selection active, go to beg of selection.
  (when (use-region-p)
    (goto-char (region-beginning)))
  ;; Clear stale pop bounds from previous replace.
  (setq helixel--yank-pop-bounds nil)
  (helixel--yank-body arg nil)
  (helixel-record-action 'paste-before))

;; ── Indent ──
;; helixel--replay-multiplier is bound by the op runner during `.`
;; replay so that the indent count is taken from the amalgamated
;; :multiplier payload instead of the interactive prefix.

(defvar helixel--replay-multiplier nil
  "When non-nil, overrides the indent count during `.` replay.
Set by the op runner from the transaction's :multiplier payload.")

(defun helixel--indent-body (op count indent-sign)
  "Shared body for `helixel-indent-left' / `helixel-indent-right'.
OP is the recorded op symbol; COUNT the interactive count;
INDENT-SIGN is +1 (right) or -1 (left)."
  (let* ((n (or helixel--replay-multiplier count 1))
         (consecutive-p nil))
    (unless (use-region-p)
      ;; Consecutive (same op or opposite indent): reuse selection,
      ;; indent 1 level, amalgamate multiplier into the last event.
      ;; Only fires when point is still at the last indent position;
      ;; moving the cursor elsewhere starts a fresh indent on the
      ;; current line.
      (when-let* ((tx helixel-last-action)
                  (tx-op (helixel-action-op tx))
                  ((or (eq tx-op op)
                       (and (eq op 'indent-left)
                            (eq tx-op 'indent-right))
                       (and (eq op 'indent-right)
                            (eq tx-op 'indent-left))))
                  ((let ((mr (helixel-action-mark-region tx)))
                     (and (consp mr) (markerp (car mr))
                          (= (point) (marker-position (car mr)))))))
        (let* ((sel (helixel-action-sel tx))
               (mr (helixel-action-mark-region tx))
               (mr-beg (when (and (consp mr) (markerp (car mr)))
                         (marker-position (car mr))))
               (mr-end (when (and (consp mr) (markerp (cdr mr)))
                         (marker-position (cdr mr)))))
          (cond
           ;; Stored region bounds from the first indent — restore
           ;; region directly.  Avoids `helixel--recreate-textobj'
           ;; which advances to the next target (correct for `.`
           ;; repeat, wrong for consecutive indent).
           ((and mr-beg mr-end (/= mr-beg mr-end))
            (goto-char mr-beg)
            (push-mark mr-end t t))
           ;; Go to mark-region car and recreate selection (original
           ;; behaviour for line/movement/find-char kinds).
           (sel
            (when mr-beg (goto-char mr-beg))
            (helixel-with-replay-as 'dot
              (helixel--recreate-selection sel)))
           ;; No sel, no stored bounds (e.g. single-line indent
           ;; without prior selection) — position at mark-region
           ;; car; indent-rigidly on empty region is a no-op.
           (t
            (when mr-beg (goto-char mr-beg)))))
        (indent-rigidly (region-beginning) (region-end) indent-sign)
        (let* ((mult (or (helixel-action-payload-get tx :multiplier) 1))
               (new-mult (if (eq tx-op op) (1+ mult) (1- mult))))
          (helixel--update-last-action
           (helixel-action-with-payload tx :multiplier new-mult)))
        (goto-char (region-beginning))
        (setq consecutive-p t)))
    (unless consecutive-p
      (let* ((delta (* n indent-sign))
             (has-region (use-region-p))
             (region-beg (when has-region (region-beginning)))
             (region-end-pos (when has-region (region-end))))
        ;; Store region bounds BEFORE indent so markers track text
        ;; shifts (indent-rigidly inserts spaces, moving all positions).
        (when (and has-region region-beg region-end-pos)
          (helixel--set-mark-region
           (cons region-beg region-end-pos)))
        (if has-region
            (indent-rigidly region-beg region-end-pos delta)
          (indent-rigidly (line-beginning-position)
                          (line-end-position) delta))
        (when has-region
          (goto-char region-beg))
        (helixel-record-action op :multiplier n)))
    (helixel-clear-data)))

(helixel-define-operator helixel-indent-left
    (:op indent-left :display "<" :self-advancing nil
         :params (&optional count))
  (interactive "p")
  (helixel--indent-body 'indent-left count -1))

(defun helixel--repeat-indent-left (tx)
  "Replay `indent-left' from TX, restoring the recorded multiplier."
  (let ((helixel--replay-multiplier
         (or (helixel-action-payload-get tx :multiplier) 1)))
    (helixel-indent-left)))

(helixel--op-set-runner 'indent-left #'helixel--repeat-indent-left)

(helixel-define-operator helixel-indent-right
    (:op indent-right :display ">" :self-advancing nil
         :params (&optional count))
  (interactive "p")
  (helixel--indent-body 'indent-right count 1))

(defun helixel--repeat-indent-right (tx)
  "Replay `indent-right' from TX, restoring the recorded multiplier."
  (let ((helixel--replay-multiplier
         (or (helixel-action-payload-get tx :multiplier) 1)))
    (helixel-indent-right)))

(helixel--op-set-runner 'indent-right #'helixel--repeat-indent-right)

;; ── Case operations ──

(helixel-define-operator helixel-toggle-case
    (:op toggle-case :display "~" :self-advancing nil
         :subcat case :params (&optional count))
  (interactive "p")
  (helixel-record-action 'toggle-case :count (or count 1))
  (if (use-region-p)
      (let ((saved-point (point))
            (text (buffer-substring (region-beginning) (region-end))))
        (delete-region (region-beginning) (region-end))
        (insert (mapconcat (lambda (c)
                             (char-to-string
                              (if (eq c (upcase c)) (downcase c) (upcase c))))
                           text ""))
        (goto-char saved-point))
    (dotimes (_ (or count 1))
      (let ((c (following-char)))
        (delete-char 1)
        (insert (if (eq c (upcase c)) (downcase c) (upcase c))))))
  (helixel-clear-data))

(defmacro helixel--def-case-op (name op display subcat region-fn word-fn)
  "Define a case-changing operator NAME.
OP, DISPLAY, SUBCAT match `helixel-define-operator's keys.
REGION-FN takes (beg end), WORD-FN takes COUNT."
  `(helixel-define-operator ,name
       (:op ,op :display ,display :self-advancing nil
            :subcat ,subcat :params (&optional count))
     (interactive "p")
     (helixel-record-action ',op :count (or count 1))
     (if (use-region-p)
         (,region-fn (region-beginning) (region-end))
       (,word-fn (or count 1)))
     (helixel-clear-data)))

(helixel--def-case-op helixel-downcase downcase "gu" case
                      downcase-region downcase-word)
(helixel--def-case-op helixel-upcase   upcase   "gU" case
                      upcase-region   upcase-word)

;; ── Comment toggle ──

(helixel-define-operator helixel-comment-toggle
    (:op comment-toggle :display "gc" :self-advancing nil
         :subcat comment)
  (helixel-record-action 'comment-toggle)
  (if (use-region-p)
      (comment-or-uncomment-region (region-beginning) (region-end))
    (comment-dwim nil))
  (helixel-clear-data))

;; ── Shell command filter ──

(helixel-define-operator helixel-shell-command
    (:op shell-command :display "!" :self-advancing nil
         :subcat shell)
  (helixel-record-action 'shell-command)
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
  (helixel-clear-data))

;; ── Text formatting ──

(helixel-define-operator helixel-fill
    (:op fill :display "gq" :subcat fill)
  (helixel-record-action 'fill)
  (if (use-region-p)
      (fill-region (region-beginning) (region-end))
    (fill-paragraph nil))
  (helixel-clear-data))

;; ── Join lines ──

(defun helixel--join-line-no-space ()
  "Join current line with the next, stripping whitespace but adding NO space.
Like `join-line' but replaces `fixup-whitespace' with
`delete-horizontal-space' so no space is inserted at the join point."
  (end-of-line)
  (unless (eobp)
    (delete-char 1)            ;; delete the newline
    (delete-horizontal-space))) ;; delete spaces/tabs, don't add space

(defun helixel--repeat-join-lines (tx)
  "Replay a `join-lines' TX (named runner, pure-data op entry)."
  (let ((n (or (helixel-action-payload-get tx :count) 2))
        (no-space (helixel-action-payload-get tx :no-space)))
    (unwind-protect
        (dotimes (_ (1- n))
          (if no-space
              (helixel--join-line-no-space)
            (join-line 1)))
      ;; Deactivate mark so fake cursor regions are
      ;; cleaned up after mc dispatch (`update-fake-region'
      ;; checks mark-active).  Harmless during dot-repeat.
      (deactivate-mark))))

(helixel-register-op join-lines
  :display "J" :self-advancing t
  :runner #'helixel--repeat-join-lines)

(helixel-define-command helixel-join-lines
    (:category edit :subcat join-lines :params (&optional count))
  (interactive "p")
  ;; Pop pending selection early — join-lines only needs the count,
  ;; never the selection recreation.  Pre-popping ensures
  ;; `helixel-record-action' gets nil so the tx carries no sel, and
  ;; dot-repeat advance doesn't recreate a spurious line selection.
  (let* ((popped (helixel--sel-pop))
         (pending-count (and popped
                             (eq (helixel-sel-kind popped) 'helixel-line-sel)
                             (helixel-line-sel-count popped)))
         (no-space (and (use-region-p) (consp current-prefix-arg)))
         (n (if (use-region-p)
                ;; Region active: join all lines spanned by selection.
                ;; A single-line region (region-n=1) is degenerate —
                ;; join at least the current line with the next.
                ;; Matters after mc spawn where each cursor gets a
                ;; 1-line region.
                (max (save-excursion
                       (let ((beg (region-beginning))
                             (end (region-end)))
                         (goto-char end)
                         (1+ (- (line-number-at-pos
                                 (if (bolp) (1- end) end))
                                (line-number-at-pos beg)))))
                     2)
              (or pending-count
                  (max (or count 1) 2)))))
    (helixel-record-action 'join-lines :count n :no-space no-space)
    (when (use-region-p)
      (goto-char (region-beginning)))
    (dotimes (_ (1- n))
      (if no-space
          (helixel--join-line-no-space)
        (join-line 1)))
    (helixel-clear-data)))

;;; Line-wise helpers

(defun helixel--yank-handler-line-wise (text)
  "Insert TEXT as a complete line.
Dispatches on `this-command' (with `helixel--current-command' fallback
for ERT/batch where `this-command' is nil) to decide insertion position."
  (let ((cmd (or helixel--current-command this-command))
        ;; Strip kill-ring properties (yank-handler)
        ;; so they don't leak into the buffer and infect subsequent copies.
        (clean-text (substring-no-properties text)))
    (pcase cmd
      ((or 'helixel-yank 'helixel-replace)
       (helixel--line-end-or-invisible)
       (newline)
       (insert (string-trim-right clean-text "\n"))
       (beginning-of-line)
       (back-to-indentation))
      ('helixel-yank-before
       (beginning-of-line)
       (save-excursion
         (insert clean-text)
         (unless (bolp) (newline)))
       (back-to-indentation))
      (_
       (insert clean-text)))))

(defun helixel--linewise-text (text)
  "Return a copy of TEXT propertized with line-wise yank-handler.
Ensures TEXT ends with a newline."
  (let ((s (if (and (> (length text) 0)
                    (/= (aref text (1- (length text))) ?\n))
               (concat text "\n")
             text)))
    (propertize s 'yank-handler '(helixel--yank-handler-line-wise nil t))))

(defun helixel--kill-type-p (handler &optional text)
  "Return non-nil if TEXT (default: top of `kill-ring')
uses yank-handler HANDLER.
HANDLER is a symbol; TEXT looks up the current `kill-ring' entry."
  (when-let* ((s (or text
                     (and helixel--current-register
                          (helixel--current-kill 0 t))
                     (and kill-ring (helixel--current-kill 0 t)))))
    (eq (car-safe (get-text-property 0 'yank-handler s))
        handler)))

(defun helixel--linewise-kill-p (&optional text)
  "Return non-nil if TEXT (default: top of kill ring) was killed line-wise."
  (helixel--kill-type-p 'helixel--yank-handler-line-wise text))

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
  (insert-rectangle (mapcar #'substring-no-properties lines)))

(defun helixel--rect-wise-text (strings)
  "Return a propertized string from STRINGS, a list of rect lines.
Tags the text with a rect-wise yank-handler for proper pasting."
  (let ((text (mapconcat #'identity strings "\n")))
    (propertize text 'yank-handler
                (list 'helixel--yank-handler-rect-wise strings t))))

(defun helixel--rect-wise-kill-p (&optional text)
  "Return non-nil if TEXT was killed as a rectangle."
  (helixel--kill-type-p 'helixel--yank-handler-rect-wise text))

;;; Rect change with replay

(defun helixel--rect-change (&optional noyank)
  "Kill rectangle content, enter insert mode.
When NOYANK is non-nil, skip pushing to `kill-ring'.
Replay typed text on all rectangle lines."
  (let* ((beg (region-beginning))
         (end (region-end))
         (line-count (count-lines beg end))
         (col (save-excursion (goto-char beg) (current-column)))
         (lines (extract-rectangle beg end)))
    (delete-rectangle beg end)
    (unless noyank
      (helixel--kill-new (helixel--rect-wise-text lines)))
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
  (helixel-record-action 'replace-char :char char)
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
    (when (and (stringp str) (not (string-empty-p str)))
      (insert str))
    (when i-end-ofs
      (goto-char (+ (point) i-end-ofs)))
    (cons beg (+ beg (length str)))))

;; ----------------------------------------------------------------------
;; Swap commands
;; ----------------------------------------------------------------------
;;
;; Region swap (same-buffer and cross-buffer): exchange the current
;; selection with the stored swap source.

;; ── Region swap utilities ──

(defun helixel--rect-ranges (beg end)
  "Return a list of (BEG . END) ranges for each line in rectangle BEG..END."
  (let ((result (list)))
    (apply-on-rectangle
     (lambda (col-beg col-end)
       (let ((pos-beg nil)
             (pos-end nil))
         (save-excursion
           (move-to-column col-beg)
           (setq pos-beg (point))
           (move-to-column col-end)
           (setq pos-end (point))
           (push (cons pos-beg pos-end) result))))
     beg end)
    (nreverse result)))

(defun helixel--ranges-overlap (list-a list-b)
  "Return t if any range in LIST-A overlaps any range in LIST-B.
Each range is a cons (BEG . END)."
  (let ((found nil))
    (while (and list-a (null found))
      (let* ((range-a (car list-a))
             (a-beg (car range-a))
             (a-end (cdr range-a))
             (b-list list-b))
        (while (and b-list (null found))
          (let* ((range-b (car b-list))
                 (b-beg (car range-b))
                 (b-end (cdr range-b)))
            (when (and (< a-beg b-end) (< b-beg a-end))
              (setq found t)))
          (setq b-list (cdr b-list))))
      (setq list-a (cdr list-a)))
    found))

(defun helixel--ranges->markers (ranges)
  "Convert RANGES (list of (BEG . END) integers) to marker pairs."
  (mapcar
   (lambda (item)
     (let ((mark-beg (set-marker (make-marker) (car item)))
           (mark-end (set-marker (make-marker) (cdr item))))
       (set-marker-insertion-type mark-beg nil)
       (set-marker-insertion-type mark-end t)
       (cons mark-beg mark-end)))
   ranges))

(defun helixel--columns-from-point (beg end)
  "Return the column offset between points BEG and END."
  (save-excursion
    (let ((col-beg
           (progn
             (goto-char beg)
             (current-column)))
          (col-end
           (progn
             (goto-char end)
             (current-column))))
      (- col-end col-beg))))

;; ── Region swap defcustom ──

(defcustom helixel-swap-imply-region t
  "When non-nil, `helixel-swap' implies a region when none is active.
The implied region extends from point with the same dimensions
as the swap source (stored by y or Y)."
  :type 'boolean
  :group 'helixel)

;; ── Region swap helpers ──

(defun helixel--swap-source-line-count (beg end)
  "Return number of full lines spanned by region BEG..END.
Normalizes BEG to bol and END to include trailing newline."
  (let ((beg-bol (save-excursion (goto-char beg) (pos-bol)))
        (end-eol (save-excursion
                   (goto-char end)
                   (if (bolp) (point)
                     (min (1+ (pos-eol)) (point-max))))))
    (count-lines beg-bol end-eol)))

(defun helixel--swap-imply-range (beg-a end-a is-line-wise)
  "Compute implied region range from source bounds BEG-A..END-A.
When IS-LINE-WISE is non-nil, the implied range starts at bol
and spans the same number of full lines as the source.
Returns (BEG-B . END-B) for the implied region."
  (if is-line-wise
      (let* ((nlines (helixel--swap-source-line-count beg-a end-a))
             (beg-b (pos-bol)))
        (save-excursion
          (goto-char beg-b)
          (forward-line (1- nlines))
          (cons beg-b (pos-eol))))
    (let* ((beg-a-eol (save-excursion (goto-char beg-a) (pos-eol)))
           (beg-b (point)))
      (cons beg-b
            (if (<= end-a beg-a-eol)
                (helixel--swap-single-line-end beg-a end-a)
              (helixel--swap-multi-line-end beg-a end-a beg-b))))))

(defun helixel--swap-single-line-end (beg-a end-a)
  "Return end-b for implied char-wise region on a single line.
BEG-A and END-A bound the source single-line region."
  (save-excursion
    (move-to-column (+ (current-column)
                       (helixel--columns-from-point beg-a end-a)))
    (point)))

(defun helixel--swap-multi-line-end (beg-a end-a beg-b)
  "Return end-b for implied char-wise region spanning multiple lines.
BEG-A and END-A bound the source region; BEG-B is point."
  (save-excursion
    (goto-char end-a)
    (if (bolp)
        (helixel--swap-multi-line-bolp beg-a end-a beg-b)
      (helixel--swap-multi-line-nonbolp beg-a end-a beg-b))))

(defun helixel--swap-multi-line-bolp (beg-a end-a beg-b)
  "Return end-b when END-A is at bol for multi-line implied range.
BEG-A bounds the start of the region; END-A is at bol.
BEG-B is the original point."
  (cl-decf end-a)
  (unless (<= beg-a end-a)
    (error "Assertion failed"))
  (goto-char beg-b)
  (beginning-of-line)
  (let ((range-a-lines (1- (count-lines beg-a end-a))))
    (unless (zerop (forward-line range-a-lines))
      (user-error "Region swap failed, expected %d line(s) after the point"
                  range-a-lines)))
  (pos-eol))

(defun helixel--swap-multi-line-nonbolp (beg-a end-a beg-b)
  "Return end-b when END-A is NOT at bol for multi-line implied range.
BEG-A and END-A bound the source region; BEG-B is point."
  (let ((col-end-a (current-column)))
    (goto-char beg-b)
    (beginning-of-line)
    (let ((range-a-lines (1- (count-lines beg-a end-a))))
      (unless (zerop (forward-line range-a-lines))
        (user-error "Region swap failed, expected %d line(s) after the point"
                    range-a-lines)))
    (move-to-column col-end-a)
    (point)))

(defun helixel--swap-rect-imply-region (source-beg source-end len-b)
  "Compute implied rectangle region from source bounds.
SOURCE-BEG, SOURCE-END are positions in current buffer.
LEN-B is the number of lines in source rectangle.
Returns (REGION-BEG . REGION-END)."
  (save-excursion
    (let* ((pos-init (point))
           (col-beg (progn (goto-char source-beg) (current-column)))
           (col-end (progn (goto-char source-end) (current-column)))
           (col-init (progn (goto-char pos-init) (current-column))))
      (when (> col-beg col-end)
        (cl-rotatef col-beg col-end))
      (goto-char (pos-bol))
      (when (> len-b 1)
        (let ((remaining (forward-line (1- len-b))))
          (unless (zerop remaining)
            (user-error
             (concat "Rectangle line count mismatch"
                     " for implied region (%d and %d)")
             (- len-b remaining) len-b))))
      (move-to-column (+ col-init (- col-end col-beg)))
      (when (< (current-column) col-init)
        (user-error
         (concat "Rectangle can't compute implied region"
                 " (last line doesn't meet current column)")))
      (cons pos-init (point)))))

;; ── Region swap implementation ──

(defun helixel--swap-from-source (beg-mark end-mark is-line-wise)
  "Swap current region with the source region at BEG-MARK..END-MARK.
When IS-LINE-WISE is non-nil, treat the source as whole lines.
Returns the source boundaries after swap for updating the swap-source."
  (let* ((beg-a (marker-position beg-mark))
         (end-a (marker-position end-mark))
         (range-a (cons beg-a end-a))
         (is-forward nil)
         (range-b
          (cond
           ((region-active-p)
            (when (eq (point) (region-end))
              (setq is-forward t))
            (cons (region-beginning) (region-end)))
           (helixel-swap-imply-region
            (helixel--swap-imply-range beg-a end-a is-line-wise))
           (t
            (cons (point) (point)))))
         (range-region range-b))
    (when (> (car range-a) (car range-b))
      (cl-rotatef range-a range-b))
    (when (> (cdr range-a) (car range-b))
      (user-error "Region swap unsupported for overlapping regions"))
    (let ((str-a (buffer-substring-no-properties
                  (car range-a) (cdr range-a)))
          (str-b (buffer-substring-no-properties
                  (car range-b) (cdr range-b))))
      (helixel--replace-region str-a (car range-b) (cdr range-b))
      (setcdr range-b (+ (cdr range-b)
                         (- (length str-a)
                            (- (cdr range-b) (car range-b)))))
      (helixel--replace-region str-b (car range-a) (cdr range-a))
      (let ((delta (- (length str-b)
                      (- (cdr range-a) (car range-a)))))
        (cl-incf (car range-b) delta)
        (cl-incf (cdr range-b) delta)
        (cl-incf (cdr range-a) delta)))
    (if is-forward
        (progn
          (set-marker (mark-marker) (car range-region))
          (goto-char (cdr range-region)))
      (set-marker (mark-marker) (cdr range-region))
      (goto-char (car range-region)))
    (cons (car range-a) (cdr range-a))))

(defun helixel--extend-rect-ranges (ranges n)
  "Extend RANGES to N lines by adding lines downward.
Each added line uses the same column span as the original last range.
RANGES is a list of (BEG . END) cons cells."
  (let* ((last (car (last ranges)))
         (col-beg (save-excursion
                    (goto-char (car last)) (current-column)))
         (col-end (save-excursion
                    (goto-char (cdr last)) (current-column)))
         (extra (- n (length ranges))))
    (if (<= extra 0)
        ranges
      (append ranges
              (save-excursion
                (goto-char (cdr last))
                (cl-loop repeat extra
                         do (forward-line 1)
                         collect (progn
                                   (move-to-column col-beg)
                                   (let ((b (point)))
                                     (move-to-column col-end)
                                     (cons b (point))))))))))

(defun helixel--swap-from-source-rect (beg-mark end-mark &optional truncate)
  "Swap current region with the source rect at BEG-MARK..END-MARK.
By default extends the shorter rectangle to match the longer one.
When TRUNCATE is non-nil, swap only min(N,M) line pairs instead.
Returns the new source end position for updating the swap-source."
  (let* ((source-beg (marker-position beg-mark))
         (source-end (marker-position end-mark))
         (line-ranges-b (helixel--rect-ranges source-beg source-end))
         (len-b (length line-ranges-b))
         (is-forward nil)
         (is-swap nil)
         region-beg region-end region-end-next source-end-next)
    (if (region-active-p)
        (progn
          (setq region-beg (region-beginning))
          (setq region-end (region-end))
          (when (eq (point) (region-end))
            (setq is-forward t)))
      (let ((implied (helixel--swap-rect-imply-region
                      source-beg source-end len-b)))
        (setq region-beg (car implied))
        (setq region-end (cdr implied))))
    (let* ((line-ranges-a (helixel--rect-ranges region-beg region-end))
           (len-a (length line-ranges-a)))
      (cond
       (truncate
        (when (> len-a len-b)
          (setq line-ranges-a (cl-subseq line-ranges-a 0 len-b)))
        (when (> len-b len-a)
          (setq line-ranges-b (cl-subseq line-ranges-b 0 len-a))))
       (t
        (let ((nswap (max len-a len-b)))
          (setq line-ranges-a (helixel--extend-rect-ranges
                               line-ranges-a nswap)
                line-ranges-b (helixel--extend-rect-ranges
                               line-ranges-b nswap)))))
      (when (helixel--ranges-overlap line-ranges-a line-ranges-b)
        (user-error
         "Region swap unsupported for overlapping (rectangle) regions"))
      (when (> (car (car line-ranges-a))
               (car (car line-ranges-b)))
        (cl-rotatef line-ranges-a line-ranges-b)
        (setq is-swap t))
      (let ((markers-a (helixel--ranges->markers line-ranges-a))
            (markers-b (helixel--ranges->markers line-ranges-b)))
        (save-excursion
          (while markers-a
            (let* ((range-a (pop markers-a))
                   (range-b (pop markers-b))
                   (text-a (buffer-substring-no-properties
                            (car range-a) (cdr range-a)))
                   (text-b (buffer-substring-no-properties
                            (car range-b) (cdr range-b))))
              (unless (string-equal text-a text-b)
                (let ((ra-beg (marker-position (car range-a)))
                      (ra-end (marker-position (cdr range-a)))
                      (rb-beg (marker-position (car range-b)))
                      (rb-end (marker-position (cdr range-b))))
                  (helixel--replace-region text-a rb-beg rb-end)
                  (helixel--replace-region text-b ra-beg ra-end)))
              (unless markers-a
                (if is-swap
                    (setq source-end-next
                          (marker-position (cdr range-a))
                          region-end-next
                          (marker-position (cdr range-b)))
                  (setq source-end-next
                        (marker-position (cdr range-b))
                        region-end-next
                        (marker-position (cdr range-a)))))
              (set-marker (car range-a) nil)
              (set-marker (cdr range-a) nil)
              (set-marker (car range-b) nil)
              (set-marker (cdr range-b) nil))))))
    (if is-forward
        (goto-char region-end-next)
      (set-marker (mark-marker) region-end-next))
    source-end-next))

;; ── Swap source helpers ──

(defun helixel--swap-source-from-kill ()
  "Return the swap-source plist.
In multi-cursor mode reads from the per-cursor variable
`helixel--yank-register-source'; otherwise reads from the
global `helixel--yank-register'.
Returns nil if no valid swap-source is found."
  (helixel--swap-source--validate
   (if (and (bound-and-true-p helixel-mc-mode)
            helixel--yank-register-source)
       helixel--yank-register-source
     (get-register helixel--yank-register))))

(defun helixel--swap-source--validate (src)
  "Validate swap-source plist SRC.
Returns (:beg BEG :end END :buffer BUF :type TYPE) if markers are
live in their native buffer, or nil otherwise."
  (let ((beg (plist-get src :beg))
        (end (plist-get src :end))
        (buf (plist-get src :buffer))
        (type (plist-get src :type)))
    (when (and (markerp beg) (markerp end)
               (eq (marker-buffer beg) buf)
               (marker-position beg)
               (marker-position end))
      (list :beg beg :end end :buffer buf :type type))))

;; ── Region swap command ──

(helixel-define-command helixel-swap
    (:category edit :subcat swap :params (&optional arg))
  (interactive "*P")
  (let* ((truncate arg)
         (source (helixel--swap-source-from-kill)))
    (unless source
      (user-error "No swap source — use `y' to copy first"))
    (let* ((beg (plist-get source :beg))
           (end (plist-get source :end))
           (source-buf (plist-get source :buffer))
           (swaptype (plist-get source :type))
           (same-buf (eq source-buf (current-buffer))))
      (if same-buf
          (let ((is-line-wise (eq swaptype 'line))
                (is-rect-wise (eq swaptype 'rect)))
            (when (and (region-active-p)
                       (bound-and-true-p rectangle-mark-mode))
              (setq is-rect-wise t)
              (setq is-line-wise nil))
            (cond
             (is-rect-wise
              (helixel--swap-from-source-rect beg end truncate))
             (t
              (helixel--swap-from-source beg end is-line-wise))))
        (let* ((source-text (with-current-buffer source-buf
                              (buffer-substring-no-properties
                               (marker-position beg)
                               (marker-position end))))
               (has-region (region-active-p))
               (target-beg (if has-region
                               (region-beginning)
                             (point)))
               (target-end (if has-region (region-end) (point)))
               (target-text
                (cond
                 (has-region
                  (buffer-substring-no-properties
                   target-beg target-end))
                 ((eq swaptype 'line)
                  (let ((nlines
                         (with-current-buffer source-buf
                           (helixel--swap-source-line-count
                            (marker-position beg)
                            (marker-position end)))))
                    (setq target-beg (pos-bol))
                    (save-excursion
                      (goto-char target-beg)
                      (forward-line (1- nlines))
                      (setq target-end (pos-eol)))
                    (buffer-substring-no-properties
                     target-beg target-end)))
                 (t
                  (setq target-end target-beg)
                  ""))))
          (with-current-buffer source-buf
            (helixel--replace-region target-text
                                     (marker-position beg)
                                     (marker-position end)))
          (helixel--replace-region source-text target-beg target-end)
          (message "Swapped with buffer `%s'" (buffer-name source-buf))
          (let* ((new-end (+ target-beg (length source-text)))
                 (stored-text (if (string-empty-p target-text)
                                  source-text
                                target-text))
                 (new-source (list :beg (copy-marker target-beg)
                                   :end (copy-marker new-end)
                                   :buffer (current-buffer)
                                   :type nil)))
            (set-register helixel--yank-register new-source)
            (helixel--kill-new stored-text :replace)
            (if has-region
                (progn
                  (set-marker (mark-marker) target-beg)
                  (goto-char new-end))
              (goto-char new-end))))))))

(provide 'helixel-editing)
;;; helixel-editing.el ends here
