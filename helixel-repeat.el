;;; helixel-repeat.el --- Repeat edit (`.`) system -*- lexical-binding: t; -*-

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
;; Dot-repeat (`.') infrastructure for helixel-mode.
;;
;; Records every editing operation as a *transaction* (see helixel-edit.el)
;; into a per-buffer ring; `.' replays the head transaction, optionally with
;; a numeric prefix.  `helixel-repeat-edit-pick' chooses an older entry from
;; the ring via completing-read.
;;
;; Architecture:
;;   Selection commands  → set helixel--repeat-sel-ctx (selection descriptor)
;;   Editing commands    → helixel--record-edit → helixel--last-tx + ring
;;   `.'                 → helixel-repeat-edit → sel-recreate + op-runner
;;
;; Both selection recreation and op execution use the `helixel-sel' struct
;; closures and the operator symbol-property registry in helixel-edit.el.
;; This module knows nothing about specific kinds or operators.
;;
;; Dependencies: helixel-action (action ring) and helixel-edit (kernel).

;;; Code:

(require 'cl-lib)
(require 'helixel-action)
(require 'helixel-edit)
(require 'helixel-delimiter)

(defvar helixel--inhibit-action-track)
(defvar helixel--selection-type)
(declare-function helixel-search--search "helixel-search"
                  (pattern dir &optional bound noerror))
(declare-function helixel--decode-repeat-prefix "helixel-repeat-strategy")
(declare-function helixel-repeat-prefix-mode "helixel-repeat-strategy")
(declare-function helixel-repeat-prefix-n "helixel-repeat-strategy")
(declare-function helixel-repeat-prefix-reverse-p "helixel-repeat-strategy")
(declare-function helixel--repeat-strategy "helixel-repeat-strategy")
(declare-function helixel--repeat-all-remaining "helixel-repeat-strategy")
(declare-function helixel--repeat-all-buffer "helixel-repeat-strategy")
(declare-function helixel--repeat-n "helixel-repeat-strategy")
(declare-function helixel--repeat-all-remaining-action "helixel-repeat-strategy")
(declare-function helixel--repeat-all-buffer-action "helixel-repeat-strategy")
(declare-function helixel--repeat-n-action "helixel-repeat-strategy")
(declare-function helixel--repeat-preview "helixel-repeat-strategy")
(declare-function helixel--repeat-all-remaining-preview "helixel-repeat-strategy")
(declare-function helixel--repeat-all-buffer-preview "helixel-repeat-strategy")
(declare-function helixel--repeat-n-preview "helixel-repeat-strategy")
(declare-function helixel-repeat-action-position-fn "helixel-repeat-strategy")
(declare-function helixel-repeat-action-execute-fn "helixel-repeat-strategy")
(declare-function make-helixel-repeat-action "helixel-repeat-strategy")

;; ---------------------------------------------------------------------------
;; Selection Context (helixel--repeat-sel-ctx)
;;
;; Set by textobj/line/rect/movement selection commands; consumed by
;; helixel--record-edit when the next edit fires.  Its shape is the
;; *selection descriptor* understood by `helixel-sel-call-recreate' — see
;; helixel-edit.el for the `helixel-sel' struct schema.

(defvar-local helixel--repeat-sel-ctx nil
  "Selection descriptor for dot-repeat.
Written by selection commands (textobj / line / rect / movement),
consumed by `helixel--record-edit'.  See `helixel-sel' struct in
helixel-edit.el for the set of recognised :kind values.")

(defsubst helixel--repeat-sel-set (sel)
  "Set `helixel--repeat-sel-ctx' to SEL."
  (setq helixel--repeat-sel-ctx sel))

(defsubst helixel--repeat-sel-get ()
  "Return `helixel--repeat-sel-ctx'."
  helixel--repeat-sel-ctx)

(defsubst helixel--repeat-sel-clear ()
  "Clear `helixel--repeat-sel-ctx'."
  (setq helixel--repeat-sel-ctx nil))

;; ---------------------------------------------------------------------------
;; Last Edit Transaction (stored as helixel--last-tx)

(defvar helixel--last-tx nil
  "The most recent edit transaction (see `helixel-edit-make').
Cross-buffer: `.` replays the last edit regardless of which buffer
it was recorded in.  May be re-pointed by `helixel-repeat-edit-pick'
to replay an older entry.

The unified action ring (`helixel--action-ring') stores all actions;
edit transactions are accessible as `:edit' plist entries.
`helixel-repeat-edit-pick' scans the action ring for entries with
`:edit' data.")

;; Edit transactions are stored in the unified action ring
;; (`helixel--action-ring') as `:edit' entries.  No separate edit ring.
;; `helixel-repeat-edit-pick' filters the action ring for entries
;; that carry `:edit' data.


(defvar-local helixel--change-track-marker nil
  "Marker at position before entering insert during a change/insert operation.
Set by change and insert-entry commands.  Read in `helixel-insert-exit'
to extract :change-text.")

(defvar helixel--inhibit-repeat-record nil
  "When non-nil, `helixel--record-edit' is a no-op.
Bound during `helixel-repeat-edit' to prevent re-recording.
Also bound in compound commands (e.g. `helixel-replace' calling
`helixel-yank') to avoid double-recording.")

(defvar-local helixel--repeat-chaining nil
  "Non-nil when kmacro is being recorded for a compound chain.
Set by `helixel-repeat-chain-start', cleared by `helixel-repeat-chain-end'
or `helixel-repeat-chain-cancel'.")

(defvar-local helixel--repeat-chain-init-ctx nil
  "The `helixel-sel' at chain-start time.
Snapshotted by `helixel-repeat-chain-start', used by chain-end
to determine advance behavior.")

(defvar-local helixel--repeat-chain-init-bounds nil
  "Initial region bounds at chain-start, as (BEG . END) markers, or nil.
Checked at chain-end to decide whether cursor still touches the
original target range.")

(defvar-local helixel--chain-move-len nil
  "Number of movement keys before the first edit in the chain.
Counted by `helixel--chain-post-cmd' via `post-command-hook'.
Nil until the first edit command is detected.")

(defvar-local helixel--repeat-chain-preview nil
  "Non-nil when , was used to preview movement; . should skip it.
Set by `helixel-repeat-selection' for chain txs, cleared by the runner.")


;; ---------------------------------------------------------------------------
;; Kmacro-based insert recorder
;;
;; Insert-mode recorder (no kmacro — avoids `defining-kbd-macro')
;;
;; Records both the executed command and its key sequence via
;; `pre-command-hook', so replay can call either the exact same
;; commands (keymap-independent) or the raw key sequence.
;;
;; Uses `pre-command-hook' (not `post-command-hook') because the
;; hook is added *during* the insert-entry command (e.g. helixel-insert),
;; so `pre-command-hook' won't fire for that first command — it only
;; captures subsequent user keystrokes.  `post-command-hook' would
;; fire for the insert-entry command itself, causing `.` to re-enter
;; insert mode and triggering infinite recursion.
;;
;; Does NOT use `start-kbd-macro' / `end-kbd-macro': setting
;; `defining-kbd-macro' to t breaks Emacs' `sit-for' (subr.el line
;; ~3877 skips the read-event wait), which in turn breaks eglot's LSP
;; completion pipeline and any other code that relies on `sit-for'.

(defvar-local helixel--insert-commands nil
  "List of commands executed during insert-mode recording.
Recorded by `helixel--on-insert-command' via `pre-command-hook'.
Cleared and returned by `helixel--insert-finish'.")

(defvar-local helixel--insert-keys nil
  "List of key vectors collected during insert-mode recording.
Each element is the return value of `this-single-command-keys'
from one command execution.  Collected by
`helixel--on-insert-command' via `pre-command-hook'.
Cleared and vconcat'd by `helixel--insert-finish'.")

(defun helixel--on-insert-command ()
  "Pre-command-hook: record command and key sequence.
Captures `this-command' for command-based replay and
`this-single-command-keys' for key-based fallback replay.
Skips `helixel-insert-exit' (the exit command itself)."
  (unless (eq this-command 'helixel-insert-exit)
    (push this-command helixel--insert-commands)
    (push (this-single-command-keys) helixel--insert-keys)))

(defun helixel--insert-begin ()
  "Start insert-mode recording (no kmacro).
Records commands and key sequences via a single `pre-command-hook'.

Does NOT call `helixel--switch-state' — that stays in helixel-common.el
because helixel-repeat.el does not depend on helixel-common.el."
  (setq helixel--insert-commands nil)
  (setq helixel--insert-keys nil)
  (add-hook 'pre-command-hook #'helixel--on-insert-command nil t))

(defun helixel--insert-finish ()
  "End insert-mode recording.
Returns (KEYS . COMMANDS).  KEYS is the apply'd-vconcat of key vectors
or nil.  COMMANDS is the list of executed commands (oldest first),
or nil."
  (remove-hook 'pre-command-hook #'helixel--on-insert-command t)
  (let ((keys (when helixel--insert-keys
                (apply #'vconcat (nreverse helixel--insert-keys))))
        (cmds (nreverse helixel--insert-commands)))
    (setq helixel--insert-commands nil)
    (setq helixel--insert-keys nil)
    (cons keys cmds)))

;; ---------------------------------------------------------------------------
;; Recording (called by editing commands in helixel-common)

(defun helixel--record-edit (operator &rest extra)
  "Record edit OPERATOR with current selection context and EXTRA payload.
Consumes `helixel--repeat-sel-ctx'.  Looks up the runner and display
from the operator registry and stores them in the transaction so
`helixel--execute-edit' can dispatch without registry lookups.
Builds a transaction via `helixel-edit-make', pushes it onto
the action ring, and stores it as `helixel--last-tx'.
Also notifies the action ring so `;' jumping picks up the new edit.

NOTE: Caller is responsible for calling `helixel-action-start' first.
The `helixel-define-command' macro handles this automatically."
  (unless (or helixel--inhibit-repeat-record executing-kbd-macro
              defining-kbd-macro)
    (let* ((runner (helixel-edit-op-runner operator))
           (tx (apply #'helixel-edit-make operator
                      helixel--repeat-sel-ctx
                      :runner runner
                      extra)))
      (let ((new-tx (copy-helixel-edit tx)))
        (setf (helixel-edit-display-field new-tx)
              (helixel-edit-op-display operator tx))
        (setq tx new-tx))
      (helixel--repeat-sel-clear)
      (setq helixel--last-tx tx)
      (helixel--live-edit-set tx)
      (helixel-action-commit))))

;; ---------------------------------------------------------------------------
;; Selection Replay

(defun helixel--recreate-selection (sel-ctx)
  "Recreate a selection from SEL-CTX at the current point.
Thin wrapper around `helixel-sel-call-recreate' —
dispatches on struct closures."
  (when sel-ctx
    (helixel-sel-call-recreate sel-ctx)))

;; ---------------------------------------------------------------------------
;; Insert-keys accessor (consumed by helixel-common.el's op runners)

(defsubst helixel--repeat-get-keys (tx)
  "Return the :keys key-sequence vector from TX payload, or nil."
  (plist-get (helixel-edit-payload tx) :keys))

(defun helixel--execute-keys (keys &optional commands)
  "Execute recorded KEYS with optional COMMANDS.
When COMMANDS are available (from `pre-command-hook' recording),
call each recorded command directly — keymap-independent.
`self-insert-command' is handled specially via `insert-char' with
the corresponding key (avoids `last-command-event' dependency).
When COMMANDS are nil, fall back to key-based replay."
  (let ((helixel--inhibit-repeat-record t)
        (helixel--inhibit-action-track t))
    (if commands
        ;; Command-based replay: call recorded commands directly
        (cl-loop for cmd in commands
                 for key in (append keys nil)
                 do (if (eq cmd 'self-insert-command)
                        (insert-char key 1 t)
                      (call-interactively cmd)))
      ;; Key-based fallback: insert-char for printable
      ;; characters, execute-kbd-macro for control/special
      ;; keys (e.g. C-d, backspace, C-a).
      (dolist (key (append keys nil))
        (if (and (characterp key) (>= key 32) (/= key 127))
            (insert-char key 1 t)
          (let ((win (selected-window)))
            (if (and win (not (eq (window-buffer win)
                                  (current-buffer))))
                (let ((prev-buf (window-buffer win)))
                  (unwind-protect
                      (progn
                        (set-window-buffer win (current-buffer))
                        (execute-kbd-macro (vector key) 1))
                    (set-window-buffer win prev-buf)))
              (execute-kbd-macro (vector key) 1))))))))

;; ---------------------------------------------------------------------------
;; Auto-advance — per-selection-kind advance for `.` replay

(defcustom helixel-repeat-advance-alist
  '((line      . helixel--repeat-advance-line)
    (rect      . helixel--repeat-advance-line)
    (search    . helixel--repeat-advance-search))
  "Alist mapping selection kind to auto-advance function.
Each function receives (TX ADVANCE-TAG) and should position
point at the next target.  Return nil to stop iteration.
Third-party selection kinds add entries here."
  :type '(alist :key-type symbol
                :value-type (choice (const nil) function))
  :group 'helixel)

(defvar helixel--search-advance-done nil
  "Bound to t when `helixel--repeat-advance-search' has positioned point.
Read by `helixel--recreate-search' to skip its internal search.")

(defun helixel--repeat-advance-search (tx _advance-tag)
  "Find next search match for TX, skipping current match for insert ops.
Positions point and sets `match-data' so `helixel--recreate-search' can
reuse it without re-searching.  Returns nil if no more matches."
  (let* ((sel (helixel-edit-sel tx))
         (pat (helixel-sel-search-pattern sel))
         (dir (helixel-sel-search-dir sel))
         (entry-kind (helixel-sel-search-entry-kind sel)))
    ;; Skip past current match (same logic as `helixel--recreate-search')
    (when entry-kind
      (when (or (looking-at pat)
                  (save-excursion
                    (condition-case nil
                        (progn
                          (helixel-search--search pat 'backward)
                          (let ((m-end (match-end 0))
                                (m-beg (match-beginning 0)))
                            (if (= m-beg m-end)
                                (= (line-number-at-pos)
                                   (line-number-at-pos m-end))
                              (<= (- (point) m-end) (length pat)))))
                      (search-failed nil))))
          (if (eq dir 'backward)
              (goto-char (max (point-min)
                              (1- (match-beginning 0))))
            (goto-char (if (= (match-beginning 0) (match-end 0))
                           (min (point-max) (1+ (match-end 0)))
                         (match-end 0))))))
    ;; Find next match; set flag so recreate-search reuses match-data
    (condition-case nil
        (progn
          (helixel-search--search pat dir)
          (setq helixel--search-advance-done t)
          t)
      (search-failed nil))))

(defun helixel--blank-line-p ()
  "Return non-nil if the current line is blank (empty or whitespace only)."
  (save-excursion
    (goto-char (line-beginning-position))
    (looking-at-p "[ \t]*$")))

(defun helixel--repeat-advance-line (tx _advance-tag)
  "Advance TX past `count' non-blank lines in selection's direction.
Returns nil at buffer edge."
  (let* ((sel (helixel-edit-sel tx))
         (dir (if (eq (helixel-sel-line-dir sel) 'backward) -1 1))
         (count (helixel-sel-line-count sel))
         (lines-left count))
    (while (and (> lines-left 0) (= (forward-line dir) 0))
      (unless (helixel--blank-line-p)
        (setq lines-left (1- lines-left))))
    (= lines-left 0)))

;; ---------------------------------------------------------------------------
;; Execution dispatcher — single entry point for replay
;;
;; All op runners live in their owning modules and self-register via
;; `helixel-register-op'.  This module knows nothing about specific ops.

(defun helixel--force-direction (tx dir)
  "Return a copy of TX with advance direction forced to DIR.
Works for both chain and non-chain: modifies sel :dir."
  (let* ((sel (helixel-edit-sel tx))
         (new-tx (copy-helixel-edit tx)))
    (when sel
      (setf (helixel-edit-sel new-tx)
            (helixel-sel-update-ctx sel :dir dir)))
    new-tx))

(defun helixel--execute-edit (tx)
  "Execute transaction TX on the current buffer.
Does NOT record, does NOT switch state.
Calls the :runner stored in TX (set at record time by
`helixel-edit-op-runner').  If :runner is missing,
falls back to the operator registry."
  (when-let* ((runner (or (helixel-edit-runner tx)
                         (helixel-edit-op-runner (helixel-edit-op tx)))))
    (funcall runner tx)))

;; ---------------------------------------------------------------------------
;; Replay (bound to `.`)

(defvar-local helixel--repeat-has-preview nil
  "Set to t by `helixel-repeat-selection', consumed by `helixel-repeat-edit'.
When t, `helixel-repeat-edit' uses the active region directly
instead of recreating the selection, so the preview is honoured.")

(defsubst helixel--repeat-echo (count)
  "Echo COUNT of repeated iterations."
  (unless (zerop count)
    (message "Repeated %d time%s" count (if (> count 1) "s" "")))
  nil)

(defun helixel--flip-dir (dir)
  "Return the opposite direction of DIR.  `forward' <-> `backward'."
  (if (eq dir 'forward) 'backward 'forward))

(defun helixel--allbuffer-search-insert (tx sel start-pos dir)
  "Insert TX payload text at every SEL match from START-POS in DIR.
For `insert-search-offset' and `insert-selection-*' entry-kinds."
  (save-excursion
    (goto-char start-pos)
    (let* ((pat (helixel-sel-search-pattern sel))
           (entry-kind (helixel-sel-search-entry-kind sel))
           (txt (or (plist-get (helixel-edit-payload tx) :inserted-text)
                    (plist-get (helixel-edit-payload tx) :text)
                    ""))
           (last-pos nil)
           (cnt 0))
      (catch 'done
        (while (helixel-search--search pat dir nil 'noerror)
          (let ((mpos (match-beginning 0)))
            (when (equal mpos last-pos)
              (setq cnt (1- cnt))
              (throw 'done nil))
            (setq last-pos mpos))
          (setq cnt (1+ cnt))
          (let* ((is-insert (eq entry-kind 'insert))
                 (pos (if is-insert (match-beginning 0)
                        (match-end 0)))
                 (zlen (= (match-beginning 0) (match-end 0)))
                 (guard-pos (if zlen (- pos (length txt))
                              (if is-insert (- pos (length txt)) pos))))
            (unless (save-excursion
                      (goto-char guard-pos)
                      (looking-at (regexp-quote txt)))
              (goto-char pos)
              (insert txt)
              (when is-insert (goto-char (match-end 0))))
            (when zlen (unless (eobp) (forward-char 1))))))
      (helixel--repeat-echo cnt))))

(defun helixel-repeat-edit (&optional raw-prefix)
  "Repeat the last editing operation at point (bound to `.`).

Prefix RAW-PREFIX semantics with search-based selections:
  3.          -> 3 times in stored direction
  0.          -> all remaining matches in stored direction
  \\[universal-argument] - 3 . -> 3 times, opposite direction
  \\[universal-argument] .    -> all matches in entire buffer

For line selections, 0. and \\[universal-argument] . replay on all
remaining / entire buffer lines respectively.

All iterations are amalgamated into a single undo step.
During keyboard macro recording `executing-kbd-macro' is non-nil
this command replays the current `helixel--last-tx' but does not
record a new edit (edit recording is inhibited during kmacro).
Failure during replay is reported but does not discard the stored edit."
  (interactive "P")
  ;; During keyboard macro playback, silently ignore . if there
  ;; is no stored edit to replay (the macro was likely recorded
  ;; in a different context).
  (when (and executing-kbd-macro (not helixel--last-tx))
    (user-error "No previous edit to repeat (kmacro playback)"))
  (unless helixel--last-tx
    (user-error "No previous edit to repeat"))
  (let* ((tx helixel--last-tx)
         (helixel--inhibit-repeat-record t)
         (helixel--inhibit-action-track t)
         (prefix (helixel--decode-repeat-prefix raw-prefix))
         (all-buffer-p (eq (helixel-repeat-prefix-mode prefix) :all-buffer))
         (all-dir-p    (eq (helixel-repeat-prefix-mode prefix) :all-dir))
         (n            (helixel-repeat-prefix-n prefix))
         (reverse-p    (helixel-repeat-prefix-reverse-p prefix))
         (use-preview helixel--repeat-has-preview)
         (sel (helixel-edit-sel tx))
         (search-sel-p (and sel
                            (eq (helixel-sel-get-kind sel) 'search)))
         (line-sel-p   (and sel
                            (eq (helixel-sel-get-kind sel) 'line))))
    (setq helixel--repeat-has-preview nil)
    (setq helixel--search-advance-done nil)
    (condition-case err
        (undo-amalgamate-change-group
          (cond
            ;; --- Entire buffer: point-min -> forward, all matches ---
            ((and all-buffer-p search-sel-p (not (eq (helixel-edit-op tx) 'chain)))
             (if (helixel-sel-search-entry-kind sel)
                 (helixel--allbuffer-search-insert tx sel
                   (point-min) 'forward)
               ;; Force forward direction: C-u . always scans buffer forward
               (let* ((fwd-sel (helixel-sel-update-ctx sel :dir 'forward))
                      (fwd-tx (copy-helixel-edit tx)))
                 (setf (helixel-edit-sel fwd-tx) fwd-sel)
                 (helixel--repeat-all-buffer-action
                  (helixel--repeat-strategy fwd-tx)
                  prefix))))
           ;; --- Entire buffer: all lines from recorded position ---
           ;; C-u . = 0. (forward) + -. (backward) from the recorded
           ;; marker, so every line is processed exactly once and the
           ;; recorded line is skipped.
           ((and all-buffer-p line-sel-p (not (eq (helixel-edit-op tx) 'chain)))
            (let* ((marker (helixel-edit-marker tx))
                   (advance (helixel-edit-op-advance
                             (helixel-edit-op tx)))
                   (line-dir (if (eq (helixel-sel-line-dir sel)
                                    'backward)
                                 -1 1))
                   (cnt 0)
                   (start-pos (and marker
                                   (marker-position marker))))
              (when start-pos
                (goto-char start-pos)
                (beginning-of-line)
                (setq start-pos (point)))
              ;; Forward pass — like 0.
              (save-excursion
                (when start-pos (goto-char start-pos))
                (forward-line line-dir)
                (condition-case nil
                    (while t
                      (when (if (= line-dir -1) (bobp) (eobp))
                        (signal 'user-error nil))
                      (setq cnt (1+ cnt))
                      (helixel--recreate-selection sel)
                      (helixel--execute-edit tx)
                      (if (eq advance 'line)
                          (progn
                            (when (/= (forward-line line-dir) 0)
                              (signal 'user-error nil))
                            (when (if (= line-dir -1)
                                      (bobp) (eobp))
                              (signal 'user-error nil)))
                        (if (if (= line-dir -1) (bobp) (eobp))
                            (signal 'user-error nil)
                          (unless (if (= line-dir -1)
                                      (eolp) (bolp))
                            (forward-line line-dir))
                          (when (if (= line-dir -1)
                                    (bobp) (eobp))
                            (signal 'user-error nil)))))
                  (user-error nil)))
              ;; Backward pass — like -.
              (save-excursion
                (when start-pos (goto-char start-pos))
                (let ((rev-dir (- line-dir)))
                  (forward-line rev-dir)
                  (unless (= (point) start-pos)
                    (condition-case nil
                      (while t
                        (setq cnt (1+ cnt))
                        (helixel--recreate-selection sel)
                        (helixel--execute-edit tx)
                        (if (eq advance 'line)
                            (when (/= (forward-line rev-dir) 0)
                              (signal 'user-error nil))
                          (if (if (= rev-dir -1) (bobp) (eobp))
                              (signal 'user-error nil)
                            (unless (if (= rev-dir -1)
                                        (eolp) (bolp))
                              (forward-line rev-dir))
                            (when (if (= rev-dir -1)
                                      (bobp) (eobp))
                              (signal 'user-error nil)))))
                    (user-error nil)))))
              (helixel--repeat-echo cnt)))
            ;; --- All remaining in reverse direction (- .) ---
            ((and all-dir-p reverse-p (or search-sel-p line-sel-p))
             (helixel--repeat-all-remaining-action
              (helixel--repeat-strategy tx t)))
            ;; --- All remaining in stored direction ---
            ((and all-dir-p (or search-sel-p line-sel-p))
             (helixel--repeat-all-remaining-action
              (helixel--repeat-strategy tx)))
            ;; --- Reverse direction |N| times ---
            ((and reverse-p (not all-buffer-p) (not all-dir-p)
                  (or search-sel-p line-sel-p))
             (helixel--repeat-n-action
              (helixel--repeat-strategy tx t) n))
            ;; --- Entire buffer + reverse: point-max -> backward ---
            ((and all-buffer-p reverse-p search-sel-p)
             (if (helixel-sel-search-entry-kind sel)
                 (helixel--allbuffer-search-insert tx sel
                   (point-max) 'backward)
               ;; Force backward direction
               (let* ((bwd-sel (helixel-sel-update-ctx sel :dir 'backward))
                      (bwd-tx (copy-helixel-edit tx)))
                 (setf (helixel-edit-sel bwd-tx) bwd-sel)
                 (helixel--repeat-all-buffer-action
                  (helixel--repeat-strategy bwd-tx)
                  prefix))))
           ((and all-buffer-p reverse-p line-sel-p)
            ;; C-u - . = -. (backward) + 0. (forward) from recorded
            ;; marker, so every line is processed exactly once.
            (let* ((marker (helixel-edit-marker tx))
                   (advance (helixel-edit-op-advance
                             (helixel-edit-op tx)))
                   (line-dir -1)  ; start backward
                   (cnt 0)
                   (start-pos (and marker
                                   (marker-position marker))))
              (when start-pos
                (goto-char start-pos)
                (beginning-of-line)
                (setq start-pos (point)))
              ;; Backward pass — like -.
              (save-excursion
                (when start-pos (goto-char start-pos))
                (forward-line line-dir)
                (condition-case nil
                    (while t
                      (when (if (= line-dir -1) (bobp) (eobp))
                        (signal 'user-error nil))
                      (setq cnt (1+ cnt))
                      (helixel--recreate-selection sel)
                      (helixel--execute-edit tx)
                      (if (eq advance 'line)
                          (progn
                            (when (/= (forward-line line-dir) 0)
                              (signal 'user-error nil))
                            (when (if (= line-dir -1)
                                      (bobp) (eobp))
                              (signal 'user-error nil)))
                        (if (if (= line-dir -1) (bobp) (eobp))
                            (signal 'user-error nil)
                          (unless (if (= line-dir -1)
                                      (eolp) (bolp))
                            (forward-line line-dir))
                          (when (if (= line-dir -1)
                                    (bobp) (eobp))
                            (signal 'user-error nil)))))
                  (user-error nil)))
              ;; Forward pass — like 0.
              (save-excursion
                (when start-pos (goto-char start-pos))
                (let ((fwd-dir 1))
                  (forward-line fwd-dir)
                  (condition-case nil
                      (while t
                        (when (eobp)
                          (signal 'user-error nil))
                        (setq cnt (1+ cnt))
                        (helixel--recreate-selection sel)
                        (helixel--execute-edit tx)
                        (if (eq advance 'line)
                            (progn
                              (when (/= (forward-line fwd-dir) 0)
                                (signal 'user-error nil))
                              (when (eobp)
                                (signal 'user-error nil)))
                          (if (eobp)
                              (signal 'user-error nil)
                            (unless (bolp)
                              (forward-line fwd-dir))
                            (when (eobp)
                              (signal 'user-error nil)))))
                    (user-error nil))))
              (helixel--repeat-echo cnt)))
            ;; --- Chain all-buffer: use strategy
            ((and all-buffer-p (eq (helixel-edit-op tx) 'chain)
                  (eq (helixel-sel-get-kind (helixel-edit-sel tx)) 'search))
             (helixel--repeat-all-buffer-action
              (if reverse-p
                  (helixel--repeat-strategy tx t)
                (helixel--repeat-strategy tx))
              prefix))
            ;; --- Chain line: entire buffer (C-u ./C-u - .) — use strategy
            ((and all-buffer-p
                  (eq (helixel-edit-op tx) 'chain)
                  (eq (helixel-sel-get-kind (helixel-edit-sel tx)) 'line))
             (let* ((dir (if reverse-p 'backward 'forward))
                    (forced-tx (helixel--force-direction tx dir)))
               ;; Execute once at start (position-fn skips to next line).
               (helixel--execute-edit forced-tx)
               (helixel--repeat-all-buffer-action
                (helixel--repeat-strategy forced-tx)
                prefix)))
            ;; --- Chain all-dir / reverse-n: use strategy
            ((and (or all-dir-p (and reverse-p (not all-buffer-p)))
                  (eq (helixel-edit-op tx) 'chain))
             (if all-dir-p
                 (helixel--repeat-all-remaining-action
                  (if reverse-p (helixel--repeat-strategy tx t)
                    (helixel--repeat-strategy tx)))
               (helixel--repeat-n-action
                (if reverse-p (helixel--repeat-strategy tx t)
                  (helixel--repeat-strategy tx))
                n)))
            ;; --- Non-search sel, 0 or C-u: fall back to once ---
           ((and (or all-dir-p all-buffer-p) sel
                 (not line-sel-p))
            (helixel--recreate-selection sel)
            (helixel--execute-edit tx))
           ;; --- Normal N times (preview path) ---
           (use-preview
            (dotimes (_ n)
              (helixel--execute-edit tx)))
           ;; --- Normal N times: use strategy + repeat-n ---
            (t
             (when (and sel (eq (helixel-sel-get-kind sel) 'textobj))
               (deactivate-mark))
             (helixel--repeat-n-action
              (helixel--repeat-strategy tx) n))))
      ((error quit)
       (message "helixel-repeat-edit aborted: %s"
                (error-message-string err))))))

;; ---------------------------------------------------------------------------
;; Repeat Selection (bound to `,`)

(defun helixel-repeat-selection (&optional raw-prefix)
  "Repeat the last selection without applying any edit (bound to `,`).
Mirrors the advance-and-recreate behaviour of `.`
\(\[helixel-repeat-edit]) without executing the operator.

Prefix RAW-PREFIX semantics (same as `.`):
  3,          -> 3 times in stored direction
  0,          -> all remaining targets in stored direction
  - ,         -> all remaining targets in reverse direction
  \\[universal-argument] - 3 , -> 3 times in opposite direction
  \\[universal-argument] ,    -> all targets in entire buffer

For chain txs with movement keys, replays those keys to position the
cursor for preview.  Sets `helixel--repeat-has-preview' so a
subsequent `.` uses this position directly."
  (interactive "P")
  (unless helixel--last-tx
    (user-error "No previous edit"))
  (let* ((tx helixel--last-tx)
         (sel-ctx (helixel-edit-sel tx))
         (helixel--inhibit-repeat-record t)
         (helixel--inhibit-action-track t)
         (prefix (helixel--decode-repeat-prefix raw-prefix))
         (chain-p (eq (helixel-edit-op tx) 'chain))
         (chain-move (and chain-p
                          (plist-get (helixel-edit-payload tx)
                                     :chain-move-keys))))
    (unless (or sel-ctx chain-p)
      (user-error (concat "Previous edit has no selection to repeat."
                          "  Use a textobj (e.g. ciw)"
                          " or line/rect selection first")))
    (if chain-p
        (helixel--repeat-selection-chain tx prefix nil chain-move)
      ;; Non-chain: use strategy + preview loops.
      (helixel--repeat-selection-nonchain tx prefix)))
  (setq helixel--repeat-has-preview t))

(defun helixel--repeat-selection-nonchain (tx prefix)
  "Non-chain `,` preview.
All modes use strategy + preview loops."
  (let ((mode (helixel-repeat-prefix-mode prefix)))
    (if (eq mode :n-times)
        ;; N-times: advance + recreate (matches old code exactly).
        (helixel--repeat-n-preview
         (helixel--repeat-strategy
          tx (helixel-repeat-prefix-reverse-p prefix))
         (helixel-repeat-prefix-n prefix))
      ;; All-buffer / all-dir: use strategy + preview loops.
      ;; Non-search non-line ops fall through to one-shot recreate
      ;; (matches old behavior: all-dir for movement/textobj
      ;; executes once, not in a loop).
      (let ((sel (helixel-edit-sel tx)))
        (if (and sel
                 (not (memq (helixel-sel-get-kind sel) '(search line))))
            (helixel--recreate-selection sel)
        (let* ((reverse-p (helixel-repeat-prefix-reverse-p prefix))
               (action (helixel--repeat-strategy tx reverse-p)))
          (helixel--repeat-preview action prefix)))))))

(defun helixel--repeat-selection-chain (tx prefix _chain-adv chain-move)
  "Chain `,` preview: advance + movement-key replay."
  (setq helixel--repeat-has-preview nil)
  (let* ((reverse-p (helixel-repeat-prefix-reverse-p prefix))
         (mode (helixel-repeat-prefix-mode prefix))
         (sel (helixel-edit-sel tx))
         (kind (helixel-sel-get-kind sel)))
    ;; Line all-buffer: first target at start needs movement
    ;; replay before the loop advances.
    (if (and (eq mode :all-buffer) (eq kind 'line))
        (let* ((use-dir (if reverse-p 'backward 'forward))
               (start (if (eq use-dir 'forward) (point-min) (point-max))))
          (goto-char start)
          (when chain-move (execute-kbd-macro chain-move))
          (let ((chain-action
                 (make-helixel-repeat-action
                  :position-fn
                  (lambda ()
                    (when (helixel--chain-do-advance
                           `(:kind line :dir ,use-dir :count ,(or (helixel-sel-line-count sel) 1)))
                      (when chain-move (execute-kbd-macro chain-move))
                      t))
                  :execute-fn (lambda () nil))))
            (helixel--repeat-all-remaining-preview chain-action)))
      ;; All other chain cases: wrap strategy with movement replay.
      (let* ((action (helixel--repeat-strategy tx reverse-p))
             (wrapped-action
              (make-helixel-repeat-action
               :position-fn
               (lambda ()
                 (when (funcall
                        (helixel-repeat-action-position-fn action))
                   (when chain-move (execute-kbd-macro chain-move))
                   t))
               :execute-fn (lambda () nil))))
        (helixel--repeat-preview wrapped-action prefix))))
  (setq helixel--repeat-chain-preview t)
  (setq helixel--repeat-has-preview t))

(defun helixel-repeat-edit-pick ()
  "Choose a past edit from the action ring and replay it.
Scans `helixel--action-ring' for entries with `:edit' data.
The chosen entry's :edit becomes the new `helixel--last-tx'."
  (interactive)
  (let* ((edit-entries
          (cl-loop for action in helixel--action-ring
                   for edit = (plist-get action :edit)
                   when edit
                   collect (cons action edit))))
    (unless edit-entries
      (user-error "No past edits to repeat"))
    (let* ((items (cl-loop for (_ . tx) in edit-entries
                           for i from 0
                           collect (cons (format "%3d  %s" i
                                                 (helixel-edit-display tx))
                                         tx)))
           (choice (completing-read "Repeat edit: " items nil t))
           (tx (cdr (assoc choice items))))
      (when tx
        (setq helixel--last-tx tx)
        (helixel-repeat-edit)))))

(defun helixel-repeat-debug ()
  "Pretty-print `helixel--last-tx' and edit entries in the action ring.
Intended for development — inspect what dot-repeat would replay next."
  (interactive)
  (require 'pp)
  (let* ((edits (cl-loop for a in helixel--action-ring
                         for tx = (plist-get a :edit)
                         when tx collect tx))
         (buf (get-buffer-create "*helixel-repeat-debug*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (emacs-lisp-mode)
        (insert ";; helixel--last-tx (display: "
                (or (and helixel--last-tx
                         (helixel-edit-display helixel--last-tx))
                    "<none>")
                ")\n")
        (pp helixel--last-tx (current-buffer))
        (insert "\n;; Edits in action ring ("
                (number-to-string (length edits))
                " entries):\n")
        (dolist (tx edits)
          (insert (format ";;   %s\n" (helixel-edit-display tx))))
        (goto-char (point-min))))
    (display-buffer buf)))

;; ── Chain runner + op registration ──

(defvar-local helixel--chain-cmd-count 0
  "Counter for commands executed during chain recording.
Incremented by `helixel--chain-post-cmd'.")

(defun helixel--chain-post-cmd ()
  "Post-command-hook: track movement key count during chain recording.
Sets `helixel--chain-move-len' when the first edit command is detected."
  (when helixel--repeat-chaining
    ;; Don't count Q (chain-end) itself
    (unless (memq this-command
                  '(helixel-repeat-chain-start helixel-repeat-chain-end))
      (setq helixel--chain-cmd-count (1+ helixel--chain-cmd-count)))
    (unless helixel--chain-move-len
      ;; Check if this command is a known edit op
      (when (and helixel--action
                 (eq (plist-get helixel--action :category) (quote edit)))
        ;; First edit detected: move-len = commands BEFORE this one
        (setq helixel--chain-move-len
              (max 0 (1- helixel--chain-cmd-count)))))))

(defun helixel--repeat-chain-runner (tx)
  "Execute the stored kmacro in chain TX.
When `helixel--repeat-chain-preview' is set (from ,), replays only
the edit part (movement keys were already executed by ,)."
  (let* ((payload (helixel-edit-payload tx))
         (edit-keys (plist-get payload :kmacro))
         (helixel--inhibit-repeat-record t)
         (helixel--inhibit-action-track t))
    (setq helixel--repeat-chain-preview nil)
    (when edit-keys
      (execute-kbd-macro edit-keys))))

(helixel-register-op chain
  :display "chain"
  :repeat-advance nil    ; chain uses its own :chain-advance in payload
  :runner #'helixel--repeat-chain-runner)

;; ── Chain advance helpers ──

(defun helixel--chain-cursor-touches-p (bounds)
  "Return non-nil if cursor is within marker BOUNDS (BEG . END).
When BOUNDS is nil (no initial selection) always returns t."
  (if bounds
      (let ((mb (car bounds)) (me (cdr bounds)))
        (and (marker-position mb) (marker-position me)
             (let ((sl (line-number-at-pos mb))
                   (el (line-number-at-pos me))
                   (cl (line-number-at-pos)))
               (and (>= cl sl) (<= cl el)))))
    t))

(defun helixel--chain-advance-data (ctx)
  "Return advance plist from init CTX, or nil if CTX is nil.
Only produces advance data for `search' and `line' selection kinds;
other kinds (movement, textobj, etc.) return nil for no auto-advance."
  (when ctx
    (let ((kind (helixel-sel-get-kind ctx)))
      (cond ((eq kind 'search)
             `(:kind search
               :pattern ,(helixel-sel-search-pattern ctx)
               :dir ,(helixel-sel-search-dir ctx)
               :entry-kind ,(helixel-sel-search-entry-kind ctx)))
            ((eq kind 'line)
             `(:kind line
               :dir ,(or (plist-get (helixel-sel--ctx-ensure ctx)
                                    :dir)
                         'forward)
               :count ,(or (plist-get (helixel-sel--ctx-ensure ctx)
                                      :count)
                           1)))))))

(defun helixel--chain-do-advance (adv-data)
  "Execute advance using ADV-DATA plist, skipping blank lines for line kind.
Return t on success, nil on edge or when search finds no more matches.
For search with :entry-kind, skips the current match so `.` advances
to the next match instead of re-finding the same one."
  (let ((kind (plist-get adv-data :kind))
        (dir (plist-get adv-data :dir))
        (count (or (plist-get adv-data :count) 1))
        (pat (plist-get adv-data :pattern))
        (entry-kind (plist-get adv-data :entry-kind)))
    (if (eq kind 'search)
        (progn
          (when entry-kind
            (when (or (looking-at pat)
                      (save-excursion
                        (condition-case nil
                            (progn
                              (helixel-search--search pat 'backward)
                              (let ((m-end (match-end 0))
                                    (m-beg (match-beginning 0)))
                                (if (= m-beg m-end)
                                    (= (line-number-at-pos)
                                       (line-number-at-pos m-end))
                                  (<= (- (point) m-end) (length pat)))))
                          (search-failed nil))))
              (if (eq dir 'backward)
                  (goto-char (max (point-min)
                                  (1- (match-beginning 0))))
                (goto-char (if (= (match-beginning 0) (match-end 0))
                               (min (point-max)
                                    (1+ (match-end 0)))
                             (match-end 0))))))
          (condition-case nil
              (progn (helixel-search--search pat dir)
                     (push-mark (match-beginning 0) t t)
                     (goto-char (match-end 0))
                     t)
            (search-failed nil)))
      (let ((inc (if (eq dir 'backward) -1 1))
            (lines-left count))
        (while (and (> lines-left 0) (= (forward-line inc) 0))
          (unless (helixel--blank-line-p)
            (setq lines-left (1- lines-left))))
        (when (= lines-left 0)
          (end-of-line)
          t)))))

;; ── Chain lifecycle commands ──

(defun helixel-repeat-chain-start ()
  "Start recording a kmacro for compound dot-repeat.
Snapshots the current selection context for advance decisions.
While recording, all keystrokes are captured by kmacro.
Call `helixel-repeat-chain-end' to finish and create a repeatable
transaction, or `helixel-repeat-chain-cancel' to discard."
  (interactive)
  (when (or helixel--repeat-chaining executing-kbd-macro)
    (user-error "Already chaining or macro replay in progress"))
  (setq helixel--repeat-chaining t)
  (setq helixel--chain-move-len nil)
  (setq helixel--chain-cmd-count 0)
  ;; Snapshot init context BEFORE deactivate-mark
  (setq helixel--repeat-chain-init-ctx helixel--repeat-sel-ctx)
  (setq helixel--repeat-chain-init-bounds
        (when (use-region-p)
          (cons (copy-marker (region-beginning))
                (copy-marker (region-end)))))
  (deactivate-mark)
  ;; Add hook to count movement keys before first edit
  (add-hook 'post-command-hook #'helixel--chain-post-cmd nil t)
  ;; Start kmacro recording
  (start-kbd-macro nil)
  (message "Chain rec • Q to finish"))

(defun helixel-repeat-chain-end ()
  "Stop kmacro recording and create a compound chain transaction.
Determines advance behavior from the initial selection context
\(snapshotted at chain-start) and whether the cursor still touches
the original target range."
  (interactive)
  (unless helixel--repeat-chaining
    (user-error "Not chaining"))
  (when defining-kbd-macro
    (end-kbd-macro))
  (setq helixel--repeat-chaining nil)
  (remove-hook 'post-command-hook #'helixel--chain-post-cmd t)
  (let ((macro (copy-sequence last-kbd-macro)))
    ;; NOTE: Do NOT clean up init-bounds markers yet —
    ;; helixel--chain-cursor-touches-p reads them below.
    (if (and macro (> (length macro) 0))
        (let* ((init-ctx helixel--repeat-chain-init-ctx)
               ;; The snapshot was taken before the first edit; i/a
               ;; commands update :entry-kind in the live ctx after
               ;; the snapshot.  Merge it so search advance can
               ;; skip the current match correctly.
               (live-ctx helixel--repeat-sel-ctx)
               (init-ctx (if (and init-ctx live-ctx
                                  (eq (helixel-sel-get-kind init-ctx)
                                      'search)
                                  (not (helixel-sel-search-entry-kind
                                        init-ctx))
                                  (helixel-sel-search-entry-kind
                                   live-ctx))
                             (helixel-sel-update-ctx
                              init-ctx
                              :entry-kind
                              (helixel-sel-search-entry-kind live-ctx))
                           init-ctx))
               (init-bounds helixel--repeat-chain-init-bounds)
               (move-len (and helixel--chain-move-len
                              (> helixel--chain-move-len 0)
                              (<= helixel--chain-move-len (length macro))
                              helixel--chain-move-len))
               (move-keys (when move-len
                            (substring macro 0 move-len)))
               (edit-keys (if move-len
                              (substring macro move-len)
                            macro))
               (touching-p (helixel--chain-cursor-touches-p init-bounds))
               (advance-data (when touching-p
                               (helixel--chain-advance-data init-ctx)))
               (tx (helixel-edit-make 'chain init-ctx
                     :runner #'helixel--repeat-chain-runner
                     :display (format "chain(%d)" (length edit-keys))
                     :kmacro edit-keys
                     :chain-move-keys move-keys
                     :chain-advance advance-data
                     :chain-init-ctx init-ctx)))
          ;; Now clean up markers
          (when init-bounds
            (let ((mb (car init-bounds))
                  (me (cdr init-bounds)))
              (when (marker-position mb) (set-marker mb nil))
              (when (marker-position me) (set-marker me nil))))
          (setq helixel--repeat-chain-init-ctx nil)
          (setq helixel--repeat-chain-init-bounds nil)
          (setq helixel--chain-move-len nil)
          (setq helixel--last-tx tx)
          ;; Create action so live-edit-set + action-commit have a target
          (helixel-action-start 'edit 'chain)
          (helixel--live-edit-set tx)
          (helixel-action-commit)
          (message "Chain recorded (%d keys, move=%d) %s"
                   (length edit-keys)
                   (if move-keys (length move-keys) 0)
                   (if advance-data "• . to advance" "• . to repeat")))
      ;; Clean up markers even when recording empty
      (when helixel--repeat-chain-init-bounds
        (let ((mb (car helixel--repeat-chain-init-bounds))
              (me (cdr helixel--repeat-chain-init-bounds)))
          (when (marker-position mb) (set-marker mb nil))
          (when (marker-position me) (set-marker me nil))))
      (setq helixel--repeat-chain-init-ctx nil)
      (setq helixel--repeat-chain-init-bounds nil)
      (message "Chain empty — nothing recorded"))))

(defun helixel-repeat-chain-cancel ()
  "Discard the current chain without recording."
  (interactive)
  (when defining-kbd-macro (end-kbd-macro))
  ;; Clean up markers
  (when helixel--repeat-chain-init-bounds
    (let ((mb (car helixel--repeat-chain-init-bounds))
          (me (cdr helixel--repeat-chain-init-bounds)))
      (when (marker-position mb) (set-marker mb nil))
      (when (marker-position me) (set-marker me nil))))
  (setq helixel--repeat-chaining nil)
  (setq helixel--repeat-chain-init-ctx nil)
  (setq helixel--repeat-chain-init-bounds nil)
  (setq helixel--chain-move-len nil)
  (remove-hook 'post-command-hook #'helixel--chain-post-cmd t)
  (message "Chain cancelled"))

(provide 'helixel-repeat)
;;; helixel-repeat.el ends here
