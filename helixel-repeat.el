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
it was recorded in.  Is `eq' to `(car helixel--edit-ring)' within
the recording buffer, but may differ after a buffer switch.
May be re-pointed by `helixel-repeat-edit-pick' to replay an older entry.")

(defcustom helixel-edit-ring-max 64
  "Maximum number of past edit transactions retained in the ring.
Older entries are discarded.  Set to 0 or nil to disable the ring
\(`helixel--last-tx' still works)."
  :type 'integer
  :group 'helixel)

(defvar-local helixel--edit-ring nil
  "List of recent edit transactions, newest first.
`helixel--last-tx' is always `eq' to `(car helixel--edit-ring)'
while both are non-nil.  Maintained by `helixel--edit-ring-push'.")

(defun helixel--edit-ring-push (tx)
  "Push TX onto the edit ring, deduplicating against the current head.
Trims to `helixel-edit-ring-max'."
  (when tx
    (unless (and helixel--edit-ring
                 (helixel-edit-equal-p tx (car helixel--edit-ring)))
      (push tx helixel--edit-ring)
      (when (and helixel-edit-ring-max
                 (> (length helixel--edit-ring) helixel-edit-ring-max))
        (setcdr (nthcdr (1- helixel-edit-ring-max) helixel--edit-ring)
                nil)))))


(defvar-local helixel--change-track-marker nil
  "Marker at position before entering insert during a change/insert operation.
Set by change and insert-entry commands.  Read in `helixel-insert-exit'
to extract :change-text.")

(defvar helixel--inhibit-repeat-record nil
  "When non-nil, `helixel--record-edit' is a no-op.
Bound during `helixel-repeat-edit' to prevent re-recording.
Also bound in compound commands (e.g. `helixel-replace' calling
`helixel-yank') to avoid double-recording.")

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
`helixel--edit-ring', and stores it as `helixel--last-tx'.
Also notifies the action ring so `;' jumping picks up the new edit.

NOTE: Caller is responsible for calling `helixel-action-start' first.
The `helixel-define-command' macro handles this automatically."
  (unless (or helixel--inhibit-repeat-record executing-kbd-macro)
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
      (helixel--edit-ring-push tx)
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
    (rect      . helixel--repeat-advance-line))
  "Alist mapping selection kind to auto-advance function.
Each function receives (TX ADVANCE-TAG) and should position
point at the next target.  Return nil to stop iteration.
Omitted kinds (search, textobj, movement, ...) get no advance —
their `helixel--recreate-*' functions already handle positioning.

Third-party selection kinds add entries here."
  :type '(alist :key-type symbol
                :value-type (choice (const nil) function))
  :group 'helixel)

(defun helixel--repeat-advance-search (tx _advance-tag)
  "Find next search match for TX.  Returns nil if no more matches."
  (let* ((sel (helixel-edit-sel tx))
         (pat (helixel-sel-search-pattern sel))
         (dir (helixel-sel-search-dir sel)))
    (condition-case nil
        (progn (helixel-search--search pat dir nil 'noerror) t)
      (search-failed nil))))

(defun helixel--repeat-advance-line (tx _advance-tag)
  "Advance TX past the selection's line count.
Returns nil at buffer edge."
  (let* ((sel (helixel-edit-sel tx))
         (dir (if (eq (helixel-sel-line-dir sel) 'backward) -1 1))
         (count (helixel-sel-line-count sel)))
    (= (forward-line (* dir count)) 0)))

(defun helixel--repeat-advance-none (_tx _advance-tag)
  "No auto-advance — target stays at point.  Always returns t."
  t)

(defun helixel--repeat-do-advance (tx)
  "Execute auto-advance for TX before recreating selection.
Looks up advance function from `helixel-repeat-advance-alist'
by selection kind.  If the operator's `:repeat-advance' tag
is nil, no advance happens."
  (let* ((sel (helixel-edit-sel tx))
         (kind (and sel (helixel-sel-get-kind sel)))
         (fn (cdr (assq kind helixel-repeat-advance-alist)))
         (tag (helixel-edit-op-advance (helixel-edit-op tx))))
    (when (and fn tag)
      (funcall fn tx tag))))

;; ---------------------------------------------------------------------------
;; Execution dispatcher — single entry point for replay
;;
;; All op runners live in their owning modules and self-register via
;; `helixel-register-op'.  This module knows nothing about specific ops.

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
         (all-buffer-p (consp raw-prefix))        ; C-u . -> (4)
         (all-dir-p    (or (and (integerp raw-prefix)
                            (eql raw-prefix 0))  ; 0. -> 0
                           (eq raw-prefix '-)))  ; - . -> reverse all
         (n            (cond ((not raw-prefix) 1)
                             ((consp raw-prefix)
                              (abs (prefix-numeric-value raw-prefix)))
                             ((integerp raw-prefix)
                             (abs raw-prefix))
                             (t 1)))
         (use-preview helixel--repeat-has-preview)
         (sel (helixel-edit-sel tx))
         (search-sel-p (and sel
                            (eq (helixel-sel-get-kind sel) 'search)))
         (line-sel-p   (and sel
                            (eq (helixel-sel-get-kind sel) 'line)))
         ;; Detect reverse: C-u -3 . or C-u - .
         (reverse-p    (or (and (integerp raw-prefix)
                                (< raw-prefix 0))
                           (and (consp raw-prefix)
                                (< (prefix-numeric-value raw-prefix)
                                   0))
                           (eq raw-prefix '-))))
    (setq helixel--repeat-has-preview nil)
    (condition-case err
        (undo-amalgamate-change-group
          (cond
           ;; --- Entire buffer: point-min -> forward, all matches ---
           ((and all-buffer-p search-sel-p)
            (save-excursion
              (goto-char (point-min))
              (let ((pat (helixel-sel-search-pattern sel))
                    (entry-kind (helixel-sel-search-entry-kind sel))
                    (cnt 0))
                (if entry-kind
                    (let ((txt (or (plist-get
                                    (helixel-edit-payload tx)
                                    :inserted-text)
                                   (plist-get
                                    (helixel-edit-payload tx)
                                    :text)
                                   ""))
                          (last-pos nil))
                      (catch 'done
                        (while (helixel-search--search
                                pat 'forward nil 'noerror)
                          (let ((mpos (match-beginning 0)))
                            (when (equal mpos last-pos)
                              (setq cnt (1- cnt))
                              (throw 'done nil))
                            (setq last-pos mpos))
                          (setq cnt (1+ cnt))
                          (let* ((is-insert (eq entry-kind 'insert))
                                 (pos (if is-insert
                                          (match-beginning 0)
                                        (match-end 0)))
                                 (zlen (= (match-beginning 0)
                                          (match-end 0)))
                                 (guard-pos (if zlen
                                                (- pos (length txt))
                                              (if is-insert
                                                  (- pos (length txt))
                                                pos))))
                            (unless (save-excursion
                                      (goto-char guard-pos)
                                      (looking-at
                                       (regexp-quote txt)))
                              (goto-char pos)
                              (insert txt)
                              (when is-insert
                                (goto-char (match-end 0))))
                            (when zlen
                              (unless (eobp)
                                (forward-char 1)))))))
                  (let ((last-pos nil))
                    (catch 'done
                      (while (helixel-search--search
                              pat 'forward nil 'noerror)
                        (let ((mpos (match-beginning 0)))
                          (when (equal mpos last-pos)
                            (setq cnt (1- cnt))
                            (throw 'done nil))
                          (setq last-pos mpos))
                        (setq cnt (1+ cnt))
                        (push-mark (match-beginning 0) t t)
                        (goto-char (match-end 0))
                        (setq helixel--selection-type 'char)
                        (helixel--execute-edit tx)))))
                (helixel--repeat-echo cnt))))
           ;; --- Entire buffer: all lines from recorded position ---
           ;; C-u . = 0. (forward) + -. (backward) from the recorded
           ;; marker, so every line is processed exactly once and the
           ;; recorded line is skipped.
           ((and all-buffer-p line-sel-p)
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
           ((and all-dir-p reverse-p search-sel-p)
            (save-excursion
              (let* ((orig-dir (helixel-sel-search-dir sel))
                     (flipped (helixel-sel-update-ctx sel
                                :dir (if (eq orig-dir 'forward)
                                         'backward 'forward)))
                     (cnt 0))
                (condition-case nil
                    (while t
                      (setq cnt (1+ cnt))
                      (helixel--recreate-selection flipped)
                      (helixel--execute-edit tx))
                  (user-error nil)
                  (search-failed nil))
                (helixel--repeat-echo cnt))))
           ((and all-dir-p reverse-p line-sel-p)
            (save-excursion
              (let ((line-dir (if (eq (helixel-sel-line-dir sel)
                                      'forward)
                                  -1 1))
                    (cnt 0))
                ;; Skip the first (already-edited) line.
                (forward-line line-dir)
                (condition-case nil
                    (while t
                      (setq cnt (1+ cnt))
                      (helixel--recreate-selection sel)
                      (helixel--execute-edit tx)
                      ;; Advance: stop at buffer edge.
                      (when (/= (forward-line line-dir) 0)
                        (signal 'user-error nil)))
                  (user-error nil))
                (helixel--repeat-echo cnt))))
           ;; --- All remaining matches in stored direction ---
           ((and all-dir-p search-sel-p)
            (save-excursion
              (let ((cnt 0))
                (condition-case nil
                    (while t
                      (setq cnt (1+ cnt))
                      (helixel--recreate-selection sel)
                      (helixel--execute-edit tx))
                  (user-error nil)
                  (search-failed nil))
                (helixel--repeat-echo cnt))))
           ;; --- All remaining lines in stored direction ---
           ((and all-dir-p line-sel-p)
            (save-excursion
              (let* ((line-dir (if (eq (helixel-sel-line-dir sel)
                                       'backward)
                                   -1 1))
                     (advance (helixel-edit-op-advance
                               (helixel-edit-op tx)))
                     (cnt 0))
                (when (eq advance 'line)
                  (forward-line line-dir))
                (condition-case nil
                    (while t
                      (when (if (eq line-dir -1) (bobp) (eobp))
                        (signal 'user-error nil))
                      (setq cnt (1+ cnt))
                      (helixel--recreate-selection sel)
                      (helixel--execute-edit tx)
                      (if (eq advance 'line)
                          (when (or (/= (forward-line line-dir) 0)
                                    (if (eq line-dir -1) (bobp) (eobp)))
                            (signal 'user-error nil))
                        ;; nil advance: explicit line advance
                        ;; with bolp/eolp guard to avoid
                        ;; double-advancing (kill vs change).
                        (if (if (eq line-dir -1) (bobp) (eobp))
                            (signal (quote user-error) nil)
                          (unless (if (eq line-dir -1)
                                      (eolp) (bolp))
                            (forward-line line-dir))
                          (when (if (eq line-dir -1)
                                    (bobp) (eobp))
                            (signal (quote user-error)
                                    nil)))))
                  (user-error nil))
                (helixel--repeat-echo cnt))))
           ;; --- Reverse direction |N| times ---
           ((and reverse-p (not all-buffer-p) (not all-dir-p)
                 search-sel-p)
            (let* ((orig-dir (helixel-sel-search-dir sel))
                   (flipped-dir (if (eq orig-dir 'forward)
                                    'backward 'forward))
                   (flipped (helixel-sel-update-ctx sel
                              :dir flipped-dir)))
              (condition-case nil
                  (dotimes (_ n)
                    (helixel--recreate-selection flipped)
                    (helixel--execute-edit tx))
                (user-error nil)
                (search-failed nil))
              (helixel--repeat-echo n)))
           ((and reverse-p (not all-buffer-p) (not all-dir-p)
                 line-sel-p)
            (let ((line-dir (if (eq (helixel-sel-line-dir sel)
                                    'forward)
                                -1 1)))
              (condition-case nil
                  (dotimes (_ n)
                    (when (/= (forward-line line-dir) 0)
                      (signal 'user-error nil))
                    (helixel--recreate-selection sel)
                    (helixel--execute-edit tx))
                (user-error nil))
              (helixel--repeat-echo n)))
           ;; --- Entire buffer + reverse: point-max -> backward ---
           ((and all-buffer-p reverse-p search-sel-p)
            (save-excursion
              (goto-char (point-max))
              (let ((pat (helixel-sel-search-pattern sel))
                    (entry-kind (helixel-sel-search-entry-kind sel))
                    (cnt 0))
                (if entry-kind
                    (let ((txt (or (plist-get (helixel-edit-payload tx)
                                              :inserted-text)
                                   (plist-get (helixel-edit-payload tx) :text)
                                   ""))
                          (last-pos nil))
                      (catch 'done
                        (while (helixel-search--search pat 'backward nil
                                                       'noerror)
                          (let ((mpos (match-beginning 0)))
                            (when (equal mpos last-pos)
                              (setq cnt (1- cnt))
                              (throw 'done nil))
                            (setq last-pos mpos))
                          (setq cnt (1+ cnt))
                          (let ((pos (if (eq entry-kind 'insert)
                                         (match-beginning 0)
                                       (match-end 0))))
                            (unless (save-excursion
                                      (goto-char pos)
                                      (looking-at (regexp-quote txt)))
                              (goto-char pos)
                              (insert txt)
                              (when (eq entry-kind 'insert)
                                (goto-char (match-beginning 0))))))))
                  (let ((last-pos nil))
                    (catch 'done
                      (while (helixel-search--search pat 'backward nil
                                                     'noerror)
                        (let ((mpos (match-beginning 0)))
                          (when (equal mpos last-pos)
                            (setq cnt (1- cnt))
                            (throw 'done nil))
                          (setq last-pos mpos))
                        (setq cnt (1+ cnt))
                        (push-mark (match-beginning 0) t t)
                        (goto-char (match-end 0))
                        (setq helixel--selection-type 'char)
                        (helixel--execute-edit tx)))))
                (helixel--repeat-echo cnt))))
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
           ;; --- Non-search sel (not line), 0 or C-u: fall back to once ---
           ((and (or all-dir-p all-buffer-p) sel
                 (not line-sel-p))
            (helixel--recreate-selection sel)
            (helixel--execute-edit tx))
           ;; --- Normal N times (preview path) ---
           (use-preview
            (dotimes (_ n)
              (helixel--execute-edit tx)))
           ;; --- Normal N times (recreate + execute) ---
            (t
             (when (and sel (eq (helixel-sel-get-kind sel) 'textobj))
               (deactivate-mark))
             (dotimes (_ n)
               (helixel--repeat-do-advance tx)
               (helixel--recreate-selection sel)
               (helixel--execute-edit tx)))))
      ((error quit)
       (message "helixel-repeat-edit aborted: %s"
                (error-message-string err))))))

;; ---------------------------------------------------------------------------
;; Repeat Selection (bound to `,`)

(defun helixel-repeat-selection (&optional count)
  "Repeat the last selection without applying any edit (bound to `,`).
Mirrors the advance-and-recreate behaviour of `.` (\[helixel-repeat-edit])
without executing the operator.
For operators with :repeat-advance (e.g. insert-text, replace-char)
this advances to the next target before showing the selection;
for operators without advance (e.g. kill, change) it recreates
the selection in place.

The full region is shown so you can preview what will be affected
by a subsequent `.`.

In visual state extends the current selection; in normal state
recreates it from scratch.  With COUNT, repeats the step that many
times.

Sets `helixel--repeat-has-preview' so a subsequent `.` uses this
region/position directly instead of advancing again."
  (interactive "p")
  (unless helixel--last-tx
    (user-error "No previous edit"))
  (let* ((tx helixel--last-tx)
         (sel-ctx (helixel-edit-sel tx)))
    (unless sel-ctx
      (user-error (concat "Previous edit has no selection to repeat."
                          "  Use a textobj (e.g. ciw)"
                          " or line/rect selection first")))
    (let ((n (or count 1)))
      (dotimes (_ n)
        (helixel--repeat-do-advance tx)
        (helixel--recreate-selection sel-ctx))

      (setq helixel--repeat-has-preview t))))

(defun helixel-repeat-edit-pick ()
  "Choose a past edit from `helixel--edit-ring' and replay it.
The chosen entry becomes the new `helixel--last-tx'."
  (interactive)
  (unless helixel--edit-ring
    (user-error "Edit ring is empty"))
  (let* ((items (cl-loop for tx in helixel--edit-ring
                         for i from 0
                         collect (cons (format "%3d  %s" i
                                               (helixel-edit-display tx))
                                       tx)))
         (choice (completing-read "Repeat edit: " items nil t))
         (tx (cdr (assoc choice items))))
    (when tx
      (setq helixel--last-tx tx)
      (helixel-repeat-edit))))

(defun helixel-repeat-debug ()
  "Pretty-print `helixel--last-tx' and the head of `helixel--edit-ring'.
Intended for development — inspect what dot-repeat would replay next."
  (interactive)
  (require 'pp)
  (let ((buf (get-buffer-create "*helixel-repeat-debug*")))
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
        (insert "\n;; helixel--edit-ring ("
                (number-to-string (length helixel--edit-ring))
                " entries):\n")
        (dolist (tx helixel--edit-ring)
          (insert (format ";;   %s\n" (helixel-edit-display tx))))
        (goto-char (point-min))))
    (display-buffer buf)))

(provide 'helixel-repeat)
;;; helixel-repeat.el ends here
