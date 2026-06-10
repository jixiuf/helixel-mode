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

;; ── Insert-entry prepositioner helpers ──
;;
;; Each insert-entry command (`helixel-insert' / `-after' / `-bol' /
;; `-eol' / `-newline' / `-prevline') declares a `:tx-runner' that
;; just calls one of these helpers.  The multi-cursor dispatcher
;; invokes the runner at every fake cursor through the unified
;; `helixel-action-replay' path — each helper runs in the fake's
;; restored context (point, mark, mark-active per `helixel-cs').
;;
;; They live here (NOT in `helixel-mc-integrate.el') so the
;; insert-entry commands have a direct same-file reference and no
;; forward `declare-function' is needed.  Tests still find them by
;; name.

(defun helixel-mc--prepos-region-begin ()
  "Move to `region-beginning' if `mark-active', else stay.
For `i' / `helixel-insert' semantics: enter insert with point at
the START of any active selection."
  (when (and mark-active (mark t))
    (goto-char (min (point) (mark t))))
  (setq mark-active nil))

(defun helixel-mc--prepos-region-end ()
  "Move to `region-end' if `mark-active', else `forward-char'.
For `a' / `helixel-insert-after' semantics: enter insert with
point AFTER the selection (or one char past point if no region)."
  (if (and mark-active (mark t))
      (goto-char (max (point) (mark t)))
    (unless (eolp) (forward-char)))
  (setq mark-active nil))

(defun helixel-mc--prepos-bol ()
  "Move to beginning of line at this fake cursor (`I' semantics)."
  (beginning-of-line))

(defun helixel-mc--prepos-eol ()
  "Move to end of line at this fake cursor (`A' semantics)."
  (end-of-line))

(defun helixel-mc--prepos-newline-after ()
  "Open a new line below this fake cursor (`o' semantics)."
  (end-of-line)
  (newline-and-indent))

(defun helixel-mc--prepos-newline-before ()
  "Open a new line above this fake cursor (`O' semantics)."
  (beginning-of-line)
  (let ((electric-indent-mode nil))
    (newline nil t)
    (forward-line -1)
    (indent-according-to-mode)))

;; ── Shared kill core ──

(defun helixel--delete-selection (&optional noyank)
  "Delete current region or char at point.
When NOYANK is non-nil, do NOT push to `kill-ring' or registers
(Vim `\"_d' / Helix black-hole semantics).  Otherwise pushes to
`kill-ring' and populates rotate / small-delete registers.
Does NOT record an edit and does NOT clear selection data.
Used by `helixel-kill' (NOYANK nil), `helixel-delete' (NOYANK t),
`helixel-change', and `helixel--repeat-change-core'."
  (cond
   ((not (use-region-p))
    (unless noyank
      (helixel--kill-new (char-to-string (char-after))))
    (delete-char 1))
   ((eq (helixel--selection-type) 'rect)
    (unless noyank
      (let ((lines (extract-rectangle (region-beginning) (region-end))))
        (helixel--kill-new (helixel--rect-wise-text lines))))
    (delete-rectangle (region-beginning) (region-end)))
   ((eq (helixel--selection-type) 'line)
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
;; Commands that have already called `helixel--record-action' earlier
;; (to interleave setup between record and marker snap) pass nil for
;; RECORD-P to skip the redundant record call.

(defun helixel--prepare-insert-entry (&optional record-p)
  "Prepare for insert-mode entry: record, snap marker, enter insert.
Calls `helixel--record-action' (unless RECORD-P is nil).
After recording, snaps `helixel--change-track-marker' at point
and enters insert mode.

Pass nil for RECORD-P when the caller has already called
`helixel--record-action' earlier (e.g. `helixel-insert-newline').
Otherwise RECORD-P defaults to t via the wrapper body."
  (setq record-p (or record-p t))
  (when record-p
    (helixel--record-action 'insert-text))
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
    (:category state :subcat insert
     :tx-runner (lambda (_tx) (helixel-mc--prepos-region-begin)))
  (let ((kind (and helixel--pending-sel
                   (helixel-sel-kind helixel--pending-sel))))
    (cond
     ;; Search or line context: preserve sel (just tag entry-kind)
     ;; for `.` auto-advance.
     ((memq kind '(search line))
      (helixel--sel-push
       (helixel-sel-update-ctx helixel--pending-sel
                               :entry-kind 'insert))
      (goto-char (region-beginning)))
     ;; Manual region
     ((use-region-p)
      (helixel--sel-push
       (helixel-sel-create 'insert-selection-start nil))
      (goto-char (region-beginning)))
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
      (when helixel--last-tx
        (let ((tx helixel--last-tx))
          ;; Store keys as primary replay mechanism
          (when (and keys (> (length keys) 0))
            (setq tx (helixel-action-with-payload tx :keys keys)))
          ;; Store text as replay fallback (tests, programmatic use)
          (when text
            (setq tx (helixel-action-with-payload tx :text text))
            (when (memq (helixel-action-op tx) '(change change-noyank))
              (setq tx (helixel-action-with-payload tx
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
    (:category state :subcat insert
     :tx-runner (lambda (_tx) (helixel-mc--prepos-region-end)))
  (let ((kind (and helixel--pending-sel
                   (helixel-sel-kind helixel--pending-sel))))
    (cond
     ;; Search or line context: preserve sel (just tag entry-kind)
     ;; for `.` auto-advance.
     ((memq kind '(search line))
      (helixel--sel-push
       (helixel-sel-update-ctx helixel--pending-sel
                               :entry-kind 'append))
      (goto-char (region-end)))
     ;; Manual region
     ((use-region-p)
      (helixel--sel-push
       (helixel-sel-create 'insert-selection-end nil))
      (goto-char (region-end)))
     ;; No context
     (t
      (unless (helixel--end-of-line-p)
        (forward-char))
      (setq helixel--pending-sel nil))))
  (helixel--prepare-insert-entry))

(helixel-define-command helixel-insert-beginning-line
    (:category state :subcat insert
     :tx-runner (lambda (_tx) (helixel-mc--prepos-bol)))
  (beginning-of-line)
   (helixel--sel-push
        (helixel-sel-create 'insert-beginning-line nil))
  (helixel--prepare-insert-entry))

(helixel-define-command helixel-insert-after-end-line
    (:category state :subcat insert
     :tx-runner (lambda (_tx) (helixel-mc--prepos-eol)))
  (end-of-line)
   (helixel--sel-push
        (helixel-sel-create 'insert-end-line nil))
  (helixel--prepare-insert-entry))

(helixel-define-command helixel-insert-newline
    (:category state :subcat insert
     :tx-runner (lambda (_tx) (helixel-mc--prepos-newline-after)))
  (helixel--record-action 'insert-text)
  (helixel--clear-data)
  (end-of-line)
  (newline-and-indent)
  (helixel--prepare-insert-entry nil))

(helixel-define-command helixel-insert-prevline
    (:category state :subcat insert
     :tx-runner (lambda (_tx) (helixel-mc--prepos-newline-before)))
  (helixel--record-action 'insert-text)
  (helixel--clear-data)
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
-effect (avoids an unnecessary helixel-insert-exit during replay)."
  (let* ((keys (helixel--repeat-get-keys tx))
         (text (helixel-action-payload-get tx :inserted-text)))
    (cond
     ((and (use-region-p) (eq (helixel--selection-type) 'rect))
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
        (helixel--delete-selection noyank)
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
        (unless (helixel-replay-in-fake-p)
          (push-mark sel-beg t t)))))))

;; ── Edit-op registry ──
;; Each operator registers a `:runner' (called by `.`) and a `:display'
;; label via `helixel-register-op' or `helixel-define-operator'.
;; Runners call the editing commands defined below.

;; Ops whose `.` runner IS the command → use `helixel-define-operator'
;; below (kill, copy, replace, paste-after, paste-before).

;; Ops with non-trivial runners (need tx payload) → register separately:
(helixel-register-op change :display "c" :moves-point-p t
  :runner #'helixel--repeat-change-core)

(helixel-register-op change-noyank :display "C" :moves-point-p t
  :runner (lambda (tx) (helixel--repeat-change-core tx t)))

(helixel-register-op replace-char :moves-point-p nil
  :display (lambda (tx)
             (let ((c (helixel-action-char tx)))
               (if c (format "R[%c]" c) "R")))
  :runner (lambda (tx)
            (helixel-replace-char (helixel-action-char tx))))

(helixel-register-op insert-text :display "i" :moves-point-p nil
  :runner (lambda (tx)
            (let ((keys (helixel-action-payload-get tx :keys)))
              (if keys
                  (helixel--execute-keys keys)
                (insert (or (helixel-action-payload-get tx :text)
                            ""))))))


;; ── Kill & Change ──

(helixel-define-operator helixel-kill
    (:op kill :display "d" :moves-point-p t)
  (helixel--record-action 'kill)
  (helixel--delete-selection)
  (helixel--register-consume)
  (helixel--clear-data))

(helixel-define-operator helixel-delete
    (:op delete :display "D" :moves-point-p t)
  (helixel--record-action 'delete)
  (helixel--delete-selection t)
  (helixel--clear-data))

(helixel-define-command helixel-change
    (:category edit :subcat change)
  (helixel--record-action 'change)
  (if (and (use-region-p) (eq (helixel--selection-type) 'rect))
      (progn (helixel--rect-change)
             (helixel--register-consume))
    (helixel--delete-selection)
    (helixel--register-consume)
    (setq helixel--change-track-marker (point-marker))
    (helixel--enter-insert)))

(helixel-define-command helixel-change-noyank
    (:category edit :subcat change-noyank)
  (helixel--record-action 'change-noyank)
  (if (and (use-region-p) (eq (helixel--selection-type) 'rect))
      (helixel--rect-change t)
    (progn
      (helixel--delete-selection t)
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
     ((and (use-region-p) (eq (helixel--selection-type) 'rect))
      (let* ((beg (region-beginning))
             (end (region-end))
             (lines (nth 1 (get-text-property 0 'yank-handler text))))
        (delete-rectangle beg end)
        (goto-char beg)
        (if (and rectwise-p lines)
            (insert-rectangle (mapcar #'substring-no-properties lines))
          (insert bare)))
      (setq helixel--yank-pop-bounds nil))
     ;; Line-wise selection: expand to full line bounds
     ((and (use-region-p) (eq (helixel--selection-type) 'line))
      (when-let* ((bounds (helixel--line-bounds-of-region)))
        (delete-region (car bounds) (cdr bounds))
        (setq pop-start (point))
        ;; Strip properties to prevent yank-handler leaking into buffer
        (insert (if linewise-p (substring-no-properties text)
                  (concat bare "\n")))
        (setq helixel--yank-pop-bounds
              (cons pop-start (point)))))
     ;; Charwise region
     ((use-region-p)
      (delete-region (region-beginning) (region-end))
      (setq pop-start (point))
      (insert (if (or linewise-p rectwise-p)
                  bare
                (substring-no-properties text)))
      (setq helixel--yank-pop-bounds
            (cons pop-start (point))))
     ;; No region — replace char at point
     (t
      (when helixel-replace-delete-char-p
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
              (cons pop-start (point))))))))

(helixel-define-operator helixel-replace
    (:op replace :display "r" :moves-point-p nil)
  (if (and (not (helixel--register-active-p))
           (= 0 (length kill-ring)))
      (message "nothing to yank")
    (let ((text (or (helixel--current-kill 0) (current-kill 0))))
      (helixel--replace-do
       text
       (lambda () (helixel-with-replay-as 'dot (helixel--yank-body nil))))
      (helixel--register-consume)
      ;; Store paste bounds as mark-region for `;' re-select.
      (when helixel--yank-pop-bounds
        (helixel--set-mark-region helixel--yank-pop-bounds))
      (helixel--record-action 'replace)
      (helixel--clear-data))))

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
                (memq last-command '(helixel-replace helixel-yank-pop
                                     helixel-yank helixel-yank-before)))
           helixel--yank-pop-bounds)
          ;; After yank or replace: use mark position to find
          ;; the yanked/replaced text even when mark is inactive
          ;; (Emacs 32 yank no longer activates mark).
          ((and (memq last-command '(helixel-yank helixel-yank-before
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
              (insert (concat text "\n"))
            (insert-for-yank text))
          (setq helixel--yank-pop-bounds (cons beg (point)))
          ;; Store bounds as mark-region for `;' re-select.
          (helixel--set-mark-region (cons beg (point))))
      ;; No bounds available — fall back or browse.
      (if (memq last-command '(helixel-yank helixel-yank-before
                               helixel-replace yank yank-pop
                               helixel-yank-pop))
          ;; After a yank/replace with no region, delegate to yank-pop.
          ;; Capture bounds afterward so subsequent M-y cycles via the
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
    (:op copy :display "y" :moves-point-p nil)
  (when (and transient-mark-mode mark-active (mark))
    (let ((swap-source
           (list :beg (copy-marker (region-beginning))
                 :end (copy-marker (region-end))
                 :buffer (current-buffer)
                 :type (helixel--swap-source-type))))
      ;; Store swap-source.  In mc mode each fake cursor stores to
      ;; its own per-cursor variable; the real cursor stores to the
      ;; global register (for non-mc fallback and cross-buffer use).
      (if (helixel-replay-in-fake-p)
          (setq helixel--yank-register-source swap-source)
        (set-register helixel--yank-register swap-source))
      (when (use-region-p) ;; non-zero-width: store text on kill-ring
        (cond
         ((eq (helixel--selection-type) 'rect)
          (let ((lines (extract-rectangle (region-beginning) (region-end))))
            (helixel--kill-new
             (helixel--rect-wise-text lines)
             :copy)))
         ((eq (helixel--selection-type) 'line)
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
  (helixel--record-action 'copy)
  (helixel--clear-data))

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
              (let ((text (helixel-register-get helixel--current-register)))
                (dotimes (_ count)
                  (if text
                      (insert-for-yank text)
                    (message "Register \"%c is empty"
                             helixel--current-register))))
            (dotimes (_ count)
              (yank 1)))))
      (helixel--register-consume)
      (helixel--register-consume)
      ;; Store pasted bounds as mark-region for `;' re-select,
      ;; and as yank-pop-bounds for M-y cycling.
      (let ((bounds nil))
        (cond
         ;; Line-wise: handler already positioned cursor.
         ((helixel--linewise-kill-p)
          (if (or paste-after-p
                  ;; Replace handler positions point at bol of the
                  ;; inserted text (same as p), so use current line.
                  (eq (or this-command helixel--current-command)
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
          ;; Also set pop-bounds so M-y can find the pasted text.
          (setq helixel--yank-pop-bounds bounds)))
      ;; Restore cursor to start for char/rect (line handler does its own).
      (when start
        (unless (helixel--linewise-kill-p)
          (when (marker-position start) (goto-char start)))
        (set-marker start nil)))))

(helixel-define-operator helixel-yank
    (:op paste-after :display "p" :moves-point-p nil
     :params (&optional arg))
  (interactive "*P")
  ;; Paste after: if selection active, go to end of selection.
  ;; For rect selection, stay on same row — only move column
  ;; to region-end, so insert-rectangle starts on the correct line.
  (when (use-region-p)
    (if (and rectangle-mark-mode
             (eq helixel--raw-selection-type 'rect))
        (move-to-column (save-excursion
                          (goto-char (region-end))
                          (current-column)) t)
      (goto-char (region-end))))
  ;; Clear stale pop bounds from previous replace.
  (setq helixel--yank-pop-bounds nil)
  (helixel--yank-body arg t)
  (helixel--record-action 'paste-after))

(helixel-define-operator helixel-yank-before
    (:op paste-before :display "P" :moves-point-p nil
     :params (&optional arg))
  (interactive "*P")
  ;; Paste before: if selection active, go to beg of selection.
  (when (use-region-p)
    (goto-char (region-beginning)))
  ;; Clear stale pop bounds from previous replace.
  (setq helixel--yank-pop-bounds nil)
  (helixel--yank-body arg nil)
  (helixel--record-action 'paste-before))

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
      ;; Consecutive (same op): reuse selection, indent 1 level,
      ;; amalgamate multiplier into the last event.
      (when-let* ((tx helixel--last-tx)
                  (sel (helixel-action-sel tx))
                  ((eq (helixel-action-op tx) op)))
        (when-let* ((m (car (helixel-action-mark-region tx)))
                    (pos (marker-position m)))
          (goto-char pos))
        (helixel-with-replay-as 'dot
          (helixel--recreate-selection sel))
        (indent-rigidly (region-beginning) (region-end) indent-sign)
        (let ((mult (or (helixel-action-payload-get tx :multiplier) 1)))
          (helixel--update-last-event
           (helixel-action-with-payload tx :multiplier (1+ mult))))
        (goto-char (region-beginning))
        (setq consecutive-p t)))
    (unless consecutive-p
      (let ((delta (* n indent-sign)))
        (if (use-region-p)
            (indent-rigidly (region-beginning) (region-end) delta)
          (indent-rigidly (line-beginning-position)
                          (line-end-position) delta)))
      (when (use-region-p)
        (goto-char (region-beginning)))
      (helixel--record-action op :multiplier n)))
  (helixel--clear-data))

(helixel-define-operator helixel-indent-left
    (:op indent-left :display "<" :moves-point-p nil
     :params (&optional count))
  (interactive "p")
  (helixel--indent-body 'indent-left count -1))

(helixel-op-set-runner 'indent-left
     (lambda (tx)
       (let ((helixel--replay-multiplier
              (or (helixel-action-payload-get tx :multiplier) 1)))
         (helixel-indent-left))))

(helixel-define-operator helixel-indent-right
    (:op indent-right :display ">" :moves-point-p nil
     :params (&optional count))
  (interactive "p")
  (helixel--indent-body 'indent-right count 1))

(helixel-op-set-runner 'indent-right
     (lambda (tx)
       (let ((helixel--replay-multiplier
              (or (helixel-action-payload-get tx :multiplier) 1)))
         (helixel-indent-right))))

;; ── Case operations ──

(helixel-define-operator helixel-toggle-case
    (:op toggle-case :display "~" :moves-point-p nil
     :subcat case :params (&optional count))
  (interactive "p")
  (helixel--record-action 'toggle-case :count (or count 1))
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
  (helixel--clear-data))

(defmacro helixel--def-case-op (name op display subcat region-fn word-fn)
  "Define a case-changing operator NAME.
OP, DISPLAY, SUBCAT match `helixel-define-operator's keys.
REGION-FN takes (beg end), WORD-FN takes COUNT."
  `(helixel-define-operator ,name
       (:op ,op :display ,display :moves-point-p nil
        :subcat ,subcat :params (&optional count))
     (interactive "p")
     (helixel--record-action ',op :count (or count 1))
     (if (use-region-p)
         (,region-fn (region-beginning) (region-end))
       (,word-fn (or count 1)))
     (helixel--clear-data)))

(helixel--def-case-op helixel-downcase downcase "gu" case
                      downcase-region downcase-word)
(helixel--def-case-op helixel-upcase   upcase   "gU" case
                      upcase-region   upcase-word)

;; ── Comment toggle ──

(helixel-define-operator helixel-comment-toggle
    (:op comment-toggle :display "gc" :moves-point-p nil
     :subcat comment)
  (helixel--record-action 'comment-toggle)
  (if (use-region-p)
      (comment-or-uncomment-region (region-beginning) (region-end))
    (comment-dwim nil))
  (helixel--clear-data))

;; ── Shell command filter ──

(helixel-define-operator helixel-shell-command
    (:op shell-command :display "!" :moves-point-p nil
     :subcat shell)
  (helixel--record-action 'shell-command)
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
  (helixel--record-action 'fill)
  (if (use-region-p)
      (fill-region (region-beginning) (region-end))
    (fill-paragraph nil))
  (helixel--clear-data))

;; ── Join lines ──

(defun helixel--join-line-no-space ()
  "Join current line with the next, stripping whitespace but adding NO space.
Like `join-line' but replaces `fixup-whitespace' with
`delete-horizontal-space' so no space is inserted at the join point."
  (end-of-line)
  (unless (eobp)
    (delete-char 1)            ;; delete the newline
    (delete-horizontal-space))) ;; delete spaces/tabs, don't add space

(helixel-register-op join-lines :display "J" :moves-point-p t
  :runner (lambda (tx)
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
                (deactivate-mark)))))

(helixel-define-command helixel-join-lines
    (:category edit :subcat join-lines :params (&optional count))
  (interactive "p")
  ;; Pop pending selection early — join-lines only needs the count,
  ;; never the selection recreation.  Pre-popping ensures
  ;; `helixel--record-action' gets nil so the tx carries no sel, and
  ;; dot-repeat advance doesn't recreate a spurious line selection.
  (let* ((popped (helixel--sel-pop))
         (pending-count (and popped
                             (eq (helixel-sel-kind popped) 'line)
                             (helixel-sel-line-count popped)))
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
    (helixel--record-action 'join-lines :count n :no-space no-space)
    (when (use-region-p)
      (goto-char (region-beginning)))
    (dotimes (_ (1- n))
      (if no-space
          (helixel--join-line-no-space)
        (join-line 1)))
    (helixel--clear-data)))

;;; Line-wise helpers

(defun helixel--yank-handler-line-wise (text)
  "Insert TEXT as a complete line.
Dispatches on `this-command' (with `helixel--current-command' fallback
for ERT/batch where `this-command' is nil) to decide insertion position."
  (let ((cmd (or this-command helixel--current-command))
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
  (insert-rectangle (mapcar #'substring-no-properties lines)))

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
  (helixel--record-action 'replace-char :char char)
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
