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
;; Records every editing operation as a *transaction* (see helixel-data.el)
;; into a per-buffer ring; `.' replays the head transaction, optionally with
;; a numeric prefix.  `helixel-repeat-edit-pick' chooses an older entry from
;; the ring via completing-read.
;;
;; Architecture:
;;   Selection commands  → set helixel--pending-sel (selection descriptor)
;;   Editing commands    → helixel--record-edit → helixel--last-tx + ring
;;   `.'                 → helixel-repeat-edit → sel-recreate + op-runner
;;
;; Both selection recreation and op execution use the `helixel-sel' struct
;; closures and the operator symbol-property registry in helixel-data.el.
;; This module knows nothing about specific kinds or operators.
;;
;; Depends on helixel-action and helixel-data.

;;; Code:

(require 'cl-lib)
(require 'helixel-action)
(require 'helixel-data)
(defvar helixel--inhibit-action-track)
(defvar helixel--selection-type)
(declare-function helixel-search--search "helixel-search"
                  (pattern dir &optional bound noerror))
(declare-function helixel--decode-repeat-prefix "helixel-repeat-strategy")
(declare-function helixel-repeat-prefix-mode "helixel-repeat-strategy")
(declare-function helixel-repeat-prefix-n "helixel-repeat-strategy")
(declare-function helixel-repeat-prefix-reverse-p "helixel-repeat-strategy")
(declare-function helixel--build-strategy "helixel-repeat-strategy")
(declare-function helixel--repeat-all-buffer "helixel-repeat-strategy")
(declare-function helixel--repeat-all-dir "helixel-repeat-strategy")
(declare-function helixel--repeat-n "helixel-repeat-strategy")
(declare-function helixel--repeat-preview "helixel-repeat-strategy")

(declare-function helixel-repeat-strategy-advance
              "helixel-repeat-strategy")
(declare-function helixel-repeat-strategy-apply "helixel-repeat-strategy")
(declare-function helixel-repeat-strategy-reset "helixel-repeat-strategy")
(declare-function helixel--recreate-line "helixel-move")
(declare-function helixel--recreate-rect "helixel-move")
(declare-function helixel--recreate-search "helixel-search")
(declare-function helixel--chain-preview-strategy "helixel-chain")

;; ---------------------------------------------------------------------------
;; Selection Context
;;
;; `helixel--pending-sel' and `helixel--sel-push'/`helixel--sel-pop'
;; are defined in `helixel-data.el'.  Selection commands push; editing
;; commands pop.

(defvar helixel--repeat-permanent-flip nil
  "When non-nil, dot-repeat permanently uses reversed direction.
Toggled by `-.' — resets on each new `helixel--record-edit'.")

;; Edit transactions are stored in the unified action ring
;; (`helixel--event-ring') as `:edit' entries.  No separate edit ring.
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

(defvar-local helixel--repeat-chain-preview nil
  "Non-nil when , was used to preview movement; . should skip it.
Set by `helixel-repeat-selection' for chain txs, cleared by the runner.")


;; ---------------------------------------------------------------------------
;; Insert-mode recording
;;
;; Records key sequences via `pre-command-hook' during insert mode.
;; Uses `this-single-command-keys' (not kmacro) to avoid breaking
;; `sit-for' which eglot's LSP completion depends on.
;;
;; Two-layer fallback: keys (primary) → text (last resort for tests).
;; The `:commands' layer was removed — never proven necessary in practice.

(defvar-local helixel--insert-keys nil
  "List of key vectors collected during insert-mode recording.
Each element is the return value of `this-single-command-keys'
from one command execution.
Collected by `helixel--on-insert-command' via `pre-command-hook'.
Cleared and vconcat'd by `helixel--insert-finish'.")

(defun helixel--on-insert-command ()
  "Pre-command-hook: record key sequence via `this-single-command-keys'.
Skips `helixel-insert-exit' (the exit command itself)."
  (unless (eq this-command 'helixel-insert-exit)
    (push (this-single-command-keys) helixel--insert-keys)))

(defun helixel--insert-begin ()
  "Start insert-mode recording.
Records key sequences via `pre-command-hook'.
Does NOT call `helixel--switch-state' -- that stays in helixel-editing.el."
  (setq helixel--insert-keys nil)
  (add-hook 'pre-command-hook #'helixel--on-insert-command nil t))

(defun helixel--insert-finish ()
  "End insert-mode recording.  Returns the key vector or nil."
  (remove-hook 'pre-command-hook #'helixel--on-insert-command t)
  (let ((keys (when helixel--insert-keys
                (apply #'vconcat (nreverse helixel--insert-keys)))))
    (setq helixel--insert-keys nil)
    keys))

;; ---------------------------------------------------------------------------
;; Recording (called by editing commands in helixel-editing)

(defun helixel--record-edit (operator &rest extra)
  "Record edit OPERATOR with current selection context and EXTRA payload.
Pops `helixel--pending-sel' via `helixel--sel-pop' (consumes the
pending selection).  Looks up the runner and display from the operator
registry and stores them in the transaction so `helixel--execute-edit'
can dispatch without registry lookups.
Builds a transaction via `helixel--make-tx', pushes it onto
the action ring, and stores it as `helixel--last-tx'.
Also notifies the action ring so `;' jumping picks up the new edit.

NOTE: Caller is responsible for calling `helixel--tracking-open' first.
The `helixel-define-command' macro handles this automatically."
  (unless (or helixel--inhibit-repeat-record executing-kbd-macro
              defining-kbd-macro)
    (let* ((pop-sel (helixel--sel-pop))
           (runner (helixel--op-runner operator))
           (tx (apply #'helixel--make-tx operator
                      pop-sel
                      :runner runner
                      extra)))
      (let ((new-tx (helixel--copy-tx tx)))
        (setf (helixel-event-display new-tx)
              (helixel--op-display operator tx))
        (setq tx new-tx))
      (setq helixel--last-tx tx)
      (setq helixel--repeat-permanent-flip nil)
      (helixel--live-edit-set tx)
      (helixel-event-commit))))

(defun helixel--update-last-tx (new-tx)
  "Sync last-tx, last-event, and event ring front to NEW-TX."
  (setq helixel--last-tx new-tx)
  (when-let* ((front (car helixel--event-ring)))
    (helixel--live-edit-set new-tx))
  ;; Keep last-event payload in sync so repeat-edit sees inserted text.
  (when (and helixel--last-event (helixel-event-p helixel--last-event))
    (setf (helixel-event-payload helixel--last-event)
          (helixel-event-payload new-tx))))

;; ---------------------------------------------------------------------------
;; Selection Replay

(defun helixel--recreate-selection (sel-ctx)
  "Recreate a selection from SEL-CTX at the current point.
Thin wrapper around `helixel-sel-call-recreate' —
dispatches on struct closures."
  (when sel-ctx
    (helixel-sel-call-recreate sel-ctx)))

;; ---------------------------------------------------------------------------
;; Insert-keys accessor (consumed by helixel-editing.el's op runners)

(defsubst helixel--repeat-get-keys (tx)
  "Return the :keys key-sequence vector from TX payload, or nil."
  (plist-get (helixel-event-payload tx) :keys))

(defun helixel--execute-keys (keys)
  "Execute recorded KEYS (a key vector).
For printable characters, uses `insert-char' directly.
For non-printable keys, uses `execute-kbd-macro'."
  (let ((helixel--inhibit-repeat-record t)
        (helixel--inhibit-action-track t))
    (when (and keys (> (length keys) 0))
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
;; Auto-advance — per-selection-kind advance for `.` replay.
;; Registered in the kind registry via `helixel-register-kind'.
;; Each advance fn receives (TX) → boolean.

(defvar helixel--search-advance-done nil
  "Bound to t when `helixel--repeat-advance-search' has positioned point.
Read by `helixel--recreate-search' to skip its internal search.")

(defvar helixel--advance-search-last-pos nil
  "Last `match-beginning' processed by `helixel--repeat-advance-search'.
Used to detect zero-width matches that would cause infinite loops.
Bound per all-dir/all-buffer repeat session.")

(defvar helixel--advance-search-edge-seen nil
  "Non-nil when a zero-width buffer-edge match was already processed.
Used to prevent infinite loops with patterns like \=`$\=' at
end-of-buffer or \=`^\=' at beginning-of-buffer.")

(defun helixel--repeat-advance-search (tx)
  "Find next search match for TX, skip current match for insert ops.
Positions point and sets `match-data' so `helixel--recreate-search'
can reuse it without re-searching.  Returns nil if no more matches.
Guards against zero-width patterns (\=`$\=', \=`^\=') that would
otherwise cause infinite loops at buffer edges."
  (let* ((sel (helixel-event-sel tx))
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
          ;; Guard against zero-width matches that don't advance:
          ;; if the same match position was already processed,
          ;; we're stuck in a loop (e.g. \=`$\=' at EOB, \=`^\=' at BOB).
          (let ((m-beg (match-beginning 0))
                (m-end (match-end 0)))
            ;; Guard against zero-width patterns at buffer edges
            ;; that re-match after insertions (e.g. \=`$\=' at growing
            ;; EOB).  Allow the first edge match; bail on subsequent.
            (when (and (= m-beg m-end)
                       (or (= m-beg (point-min))
                           (= m-beg (point-max))))
              (if helixel--advance-search-edge-seen
                  (signal 'search-failed nil)
                (setq helixel--advance-search-edge-seen t)))
            ;; Guard against repeated matches at same position
            (when (equal m-beg helixel--advance-search-last-pos)
              (signal 'search-failed nil)))
          (setq helixel--search-advance-done t)
          (setq helixel--advance-search-last-pos (match-beginning 0))
          (helixel--recreate-selection sel)
          t)
      (search-failed nil))))

(defun helixel--blank-line-p ()
  "Return non-nil if the current line is blank (empty or whitespace only)."
  (save-excursion
    (goto-char (line-beginning-position))
    (looking-at-p "[ \t]*$")))

(defun helixel--repeat-advance-line (tx)
  "Advance TX past the current line target in selection's direction.
For append entry-kind (cursor at `region-end' after op), advance 1 line.
Otherwise advance by the selection count.
After advancing, recreates the line selection to position point
correctly (bol for insert, eol for append).  Returns nil at buffer edge.
Deactivates any prior region so `helixel-select-line-up' starts
fresh rather than extending a stale mark."
  (let* ((sel (helixel-event-sel tx))
         (dir (if (eq (helixel-sel-line-dir sel) 'backward) -1 1))
         (entry-kind (plist-get (helixel-sel-get-ctx sel) :entry-kind))
         (count (if (eq entry-kind 'append) 1
                  (helixel-sel-line-count sel)))
         (lines-left count))
    (while (and (> lines-left 0) (= (forward-line dir) 0))
      (unless (helixel--blank-line-p)
        (setq lines-left (1- lines-left))))
    (when (= lines-left 0)
      (deactivate-mark)
      (helixel--recreate-selection sel)
      t)))

(defun helixel--repeat-advance-movement (tx)
  "Advance to next target for TX's movement selection.
Calls the selection's recreate function from the current cursor
position.  The recreate IS the advance (inline — movement commands
inherently create the region).  Returns t on success, nil when
point does not move.
The strategy skips the separate `recreate-selection' call for inline
advance functions to avoid double-moving."
  (let ((sel (helixel-event-sel tx)))
    (when sel
      (condition-case nil
          (progn (helixel--recreate-selection sel) t)
        (error nil)))))

(defun helixel--repeat-advance-textobj (tx)
  "Advance to next target for TX's textobj selection.
Calls the selection's recreate function from the current cursor
position.  The recreate IS the advance (inline — textobj commands
inherently create the region).  Returns t on success, nil when
recreate fails.
The strategy skips the separate `recreate-selection' call for inline
advance functions to avoid double-moving."
  (let ((sel (helixel-event-sel tx)))
    (when sel
      (condition-case nil
          (progn (helixel--recreate-selection sel) t)
        (error nil)))))

;; ---------------------------------------------------------------------------
;; Execution dispatcher — single entry point for replay
;;
;; All op runners live in their owning modules and self-register via
;; `helixel-register-op'.  This module knows nothing about specific ops.

(defun helixel--execute-edit (tx)
  "Execute transaction TX on the current buffer.
Does NOT record, does NOT switch state.
Calls the :runner stored in TX (set at record time by
`helixel--op-runner').  If :runner is missing,
falls back to the operator registry."
  (when-let* ((runner (or (helixel-event-runner tx)
                         (helixel--op-runner (helixel-event-op tx)))))
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
           (txt (or (plist-get (helixel-event-payload tx) :inserted-text)
                    (plist-get (helixel-event-payload tx) :text)
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

(defun helixel--repeat-line-pass (tx sel advance start-pos dir cnt
                                     &optional preview-p)
  "Process one line per step from START-POS in direction DIR.
TX is the edit transaction, SEL the selection descriptor.
ADVANCE is the operator advance tag, CNT the starting count.
If PREVIEW-P is non-nil, only recreate selections without executing edits."
  (save-excursion
    (goto-char start-pos)
    (forward-line dir)
    (condition-case nil
        (while t
          (when (if (eq dir -1) (bobp) (eobp))
            (signal 'user-error nil))
          (setq cnt (1+ cnt))
          (helixel--recreate-selection sel)
          (unless preview-p
            (helixel--execute-edit tx))
          (if (eq advance 'line)
              (progn
                (when (/= (forward-line dir) 0)
                  (signal 'user-error nil))
                (when (if (eq dir -1) (bobp) (eobp))
                  (signal 'user-error nil)))
            (if (if (eq dir -1) (bobp) (eobp))
                (signal 'user-error nil)
              (unless (if (eq dir -1) (eolp) (bolp))
                (forward-line dir))
              (when (if (eq dir -1) (bobp) (eobp))
                (signal 'user-error nil)))))
      (user-error nil)))
  cnt)

(defun helixel--repeat-flip-tx-dir ()
  "Toggle `helixel--repeat-permanent-flip' for line/search selections.
Like \=`N\=` for search, \=`-.\=` permanently reverses dot-repeat direction.
No-op for movement, textobj, or nil selections.
Returns t on success, nil otherwise."
  (when-let* ((tx helixel--last-tx)
              (sel (helixel-event-sel tx))
              (kind (helixel-sel-get-kind sel)))
    (when (memq kind '(line search))
      (setq helixel--repeat-permanent-flip
            (not helixel--repeat-permanent-flip))
      t)))

(defun helixel-repeat-edit (&optional raw-prefix)
  "Repeat the last editing operation at point (bound to `.`).

Prefix RAW-PREFIX semantics:
  3.     -> 3 times in stored direction
  -.     -> flip direction permanently (like N for search), 1 repeat
  0.     -> all remaining targets in stored direction
  \\[universal-argument] .    -> all targets in entire buffer
  \\[universal-argument] - .  -> all targets in entire buffer, reverse

After `-.' the direction is permanently changed — subsequent `.`
repeats in the new direction.  `-.' again flips back.

All iterations are amalgamated into a single undo step."
  (interactive "P")
  (let ((event helixel--last-event)
        (tx helixel--last-tx))
    (when (and executing-kbd-macro (not tx))
      (user-error "No previous edit to repeat (kmacro playback)"))
    (unless tx
      (when (and event (helixel-event-p event))
        ;; Fallback: reconstruct tx from event if tx lost
        (setq tx event))
      (unless tx
        (user-error "No previous edit to repeat")))
    (let* ((helixel--inhibit-repeat-record t)
           (helixel--inhibit-action-track t)
           (flip-dir-p (or (eq raw-prefix '-)
                           (and (integerp raw-prefix)
                                (< raw-prefix 0))))
           (prefix (helixel--decode-repeat-prefix raw-prefix))
           (mode (helixel-repeat-prefix-mode prefix))
           (use-preview helixel--repeat-has-preview)
           (sel (helixel-event-sel tx)))
    (when flip-dir-p (helixel--repeat-flip-tx-dir))
    (setq helixel--repeat-has-preview nil)
    (setq helixel--search-advance-done nil)
    (setq helixel--advance-search-last-pos nil)
    (setq helixel--advance-search-edge-seen nil)
    (condition-case err
        (undo-amalgamate-change-group
          (let ((strategy
                 (helixel--build-strategy
                  tx (helixel-repeat-prefix-reverse-p prefix))))
            (pcase mode
              (:all-buffer
               (if sel
                   (helixel--repeat-all-buffer strategy tx prefix)
                 (helixel--execute-edit tx)))
              (:all-dir
               (if sel
                   (helixel--repeat-all-dir strategy tx)
                 (helixel--execute-edit tx)))
              (:n-times
               (if use-preview
                   (dotimes (_ (helixel-repeat-prefix-n prefix))
                     (helixel--execute-edit tx))
                 (helixel--repeat-n strategy tx
                                    (helixel-repeat-prefix-n prefix))))
              (:preview
               (helixel--execute-edit tx)))))
      ((error quit)
       (message "helixel-repeat-edit aborted: %s"
                (error-message-string err)))))))

;; ---------------------------------------------------------------------------
;; Repeat Selection (bound to `,`)

(defun helixel-repeat-selection (&optional raw-prefix)
  "Repeat the last selection without applying any edit (bound to `,`).
Mirrors the advance behaviour of `.` without executing the operator.

Prefix RAW-PREFIX semantics (same as `.`):
  3,     -> 3 times in stored direction
  -,     -> flip direction permanently (like N for search), preview 1
  0,     -> all remaining targets in stored direction
  \\[universal-argument] - 3 , -> 3 times in opposite direction
  \\[universal-argument] ,    -> all targets in entire buffer

Sets `helixel--repeat-has-preview' so a subsequent `.` uses the
preview position."
  (interactive "P")
  (let ((event helixel--last-event)
        (tx helixel--last-tx))
    (unless tx
      (when (and event (helixel-event-p event))
        ;; Fallback: reconstruct tx from event if tx lost
        (setq tx event))
      (unless tx
        (user-error "No previous edit")))
    (let* ((helixel--inhibit-repeat-record t)
           (helixel--inhibit-action-track t)
           (helixel--search-advance-done nil)
           (helixel--advance-search-last-pos nil)
           (helixel--advance-search-edge-seen nil)
           (flip-dir-p (or (eq raw-prefix '-)
                           (and (integerp raw-prefix)
                                (< raw-prefix 0))))
           (prefix (helixel--decode-repeat-prefix raw-prefix))
           (chain-p (eq (helixel-event-op tx) 'chain)))
    (when flip-dir-p (helixel--repeat-flip-tx-dir))
    (unless (or (helixel-event-sel tx) chain-p)
      (user-error (concat "Previous edit has no selection to repeat."
                          "  Use a textobj (e.g. ciw)"
                          " or line/rect selection first")))
    (let* ((reverse-p (helixel-repeat-prefix-reverse-p prefix))
           (mode (helixel-repeat-prefix-mode prefix))
           (n (helixel-repeat-prefix-n prefix))
           (sel (helixel-event-sel tx)))
      (cond
       ;; All-buffer line preview: scan forward from point-min
       ((and (eq mode :all-buffer) sel
             (eq (helixel-sel-get-kind sel) 'line))
        (let* ((op (helixel-event-op tx))
               (dir (if reverse-p -1 1))
               (start (if (> dir 0) (point-min) (point-max)))
               (cnt 0))
          (save-excursion
            (goto-char start)
            (setq cnt (helixel--repeat-line-pass
                       tx sel (or (helixel--op-advance op) 'line)
                       start dir cnt t)))
          (helixel--repeat-echo cnt)))
       ;; Generic: strategy-driven preview
       (t
        (let ((strategy (if chain-p
                            (helixel--chain-preview-strategy tx reverse-p)
                          (helixel--build-strategy tx reverse-p))))
          (helixel--repeat-preview strategy tx mode n)))))
    (when chain-p (setq helixel--repeat-chain-preview t))
    (setq helixel--repeat-has-preview t))))

(defun helixel-repeat-edit-pick ()
  "Choose a past edit from the event ring and replay it.
Scans `helixel--event-ring' for entries with an :op.
The chosen event's edit data becomes the new `helixel--last-tx'."
  (interactive)
  (let* ((edit-entries
          (cl-loop for event in helixel--event-ring
                   when (helixel-event-op event)
                   collect event)))
    (unless edit-entries
      (user-error "No past edits to repeat"))
    (let* ((items (cl-loop for e in edit-entries
                           for i from 0
                           collect (cons (format "%3d  %s" i
                                                 (helixel-event-display-format
                                                  e))
                                         e)))
           (collection
            (lambda (s p a)
              (if (eq a 'metadata)
                  '(metadata
                    (category . helixel-repeat-edit)
                    (cycle-sort-function . identity)
                    (display-sort-function . identity))
                (complete-with-action a items s p))))
           (choice (completing-read "Repeat edit: " collection nil t))
           (event (cdr (assoc choice items))))
      (when event
        ;; Reconstruct old-style tx from event for helixel--last-tx
        (helixel--update-last-tx
         (helixel--make-tx
          (helixel-event-op event)
          :display (helixel-event-display-format event)
          :sel (helixel-event-sel event)
          :payload (helixel-event-payload event)
          :runner (helixel-event-runner event)))
        (helixel-repeat-edit)))))

(defun helixel-repeat-debug ()
  "Pretty-print `helixel--last-tx' and edit events in the event ring."
  (interactive)
  (require 'pp)
  (let* ((events (cl-loop for e in helixel--event-ring
                          when (helixel-event-op e)
                          collect e))
         (buf (get-buffer-create "*helixel-repeat-debug*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (emacs-lisp-mode)
        (insert ";; helixel--last-tx (display: "
                (or (and helixel--last-tx
                         (helixel--tx-display helixel--last-tx))
                    "<none>")
                ")\n")
        (pp helixel--last-tx (current-buffer))
        (insert "\n;; Edit events in event ring ("
                (number-to-string (length events))
                " entries):\n")
        (dolist (ev events)
          (insert (format ";;   %s\n"
                          (helixel-event-display-format ev))))
        (goto-char (point-min))))
    (display-buffer buf)))


;; ── Kind-specific all-buffer handlers ──
;; These are invoked via the :all-buffer-fn slot in the kind registry.

(declare-function helixel-repeat-prefix-reverse-p "helixel-repeat-strategy")

(defun helixel--all-buffer-line (edit prefix)
  "All-buffer repeat handler for line selections, for EDIT and PREFIX.
Forward pass then backward pass from the marker position.
For chain ops, does a single pass from the buffer edge."
  (let* ((sel (helixel-event-sel edit))
         (op (helixel-event-op edit))
         (reverse-p (helixel-repeat-prefix-reverse-p prefix))
         (marker (helixel-event-marker edit))
         (chain-p (eq op 'chain)))
    (if chain-p
        (let* ((dir (if reverse-p -1
                     (if (eq (helixel-sel-line-dir sel) 'backward) -1 1)))
               (start (if (> dir 0) (point-min) (point-max)))
               (cnt 0))
          (save-excursion
            (goto-char start)
            (unless (helixel--blank-line-p)
              (helixel--execute-edit edit)))
          (setq cnt (helixel--repeat-line-pass
                     edit sel (or (helixel--op-advance op) 'line)
                     start dir cnt))
          (helixel--repeat-echo cnt))
      (let* ((first-dir (if reverse-p -1
                          (if (eq (helixel-sel-line-dir sel) 'backward) -1 1)))
             (cnt 0)
             (start-pos (and marker (marker-position marker))))
        (when start-pos
          (goto-char start-pos)
          (beginning-of-line)
          (setq start-pos (point)))
        (setq cnt (helixel--repeat-line-pass
                   edit sel (helixel--op-advance op)
                   start-pos first-dir cnt))
        (setq cnt (helixel--repeat-line-pass
                   edit sel (helixel--op-advance op)
                   start-pos (- first-dir) cnt))
        (helixel--repeat-echo cnt)))))

(defun helixel--all-dir-line (edit)
  "All-dir repeat handler for line selections, for EDIT.
Uses `helixel--repeat-line-pass' for proper cursor advance."
  (let* ((sel (helixel-event-sel edit))
         (op (helixel-event-op edit))
         (dir (if (eq (helixel-sel-line-dir sel) 'backward) -1 1))
         (adv (or (helixel--op-advance op) 'line))
         (cnt 0))
    (setq cnt (helixel--repeat-line-pass edit sel adv (point) dir cnt))
    (helixel--repeat-echo cnt)))

(defun helixel--all-buffer-search (edit prefix)
  "All-buffer repeat handler for search selections, for EDIT and PREFIX.
For entry-kind searches, inserts text at every match from
buffer edge.  For non-entry-kind, scans from point-min
using advance+apply without recursion."
  (let* ((sel (helixel-event-sel edit))
         (entry-kind (helixel-sel-search-entry-kind sel)))
    (if entry-kind
        (let ((start-pos (if (helixel-repeat-prefix-reverse-p prefix)
                             (point-max) (point-min)))
              (dir (if (helixel-repeat-prefix-reverse-p prefix)
                       'backward 'forward)))
          (helixel--allbuffer-search-insert edit sel start-pos dir))
      ;; Non-entry-kind: force forward direction, scan via advance+apply
      ;; directly (don't go through helixel--repeat-all-buffer to avoid
      ;; recursion since the kind's :all-buffer-fn is this function).
      (let* ((reverse-p (helixel-repeat-prefix-reverse-p prefix))
             (forced-dir (if reverse-p 'backward 'forward))
             (forced-sel (helixel-sel-update-ctx sel :dir forced-dir))
             (forced-tx (helixel--copy-tx edit))
             (strategy (helixel--build-strategy forced-tx)))
        (setf (helixel-event-sel forced-tx) forced-sel)
        (funcall (helixel-repeat-strategy-reset strategy) forced-tx)
        (save-excursion
          (goto-char (if reverse-p (point-max) (point-min)))
          (let ((cnt 0))
            (while (funcall (helixel-repeat-strategy-advance strategy)
                            forced-tx)
              (cl-incf cnt)
              (funcall (helixel-repeat-strategy-apply strategy)
                       forced-tx))
            (helixel--repeat-echo cnt)))))))


;; ── Kind registrations ──
;; Register advance/recreate/disp for kinds whose impls live here.

(helixel-register-kind line
  :recreate #'helixel--recreate-line
  :advance  #'helixel--repeat-advance-line
  :all-buffer-fn #'helixel--all-buffer-line
  :all-dir-fn #'helixel--all-dir-line
  :display  (lambda (ctx)
              (format "%dL" (or (helixel-sel-count ctx) 1)))
  :make-sel nil)

(helixel-register-kind rect
  :recreate #'helixel--recreate-rect
  :advance  nil
  :display  "R"
  :make-sel nil)

(helixel-register-kind search
  :recreate #'helixel--recreate-search
  :advance  #'helixel--repeat-advance-search
  :all-buffer-fn #'helixel--all-buffer-search
  :display  (lambda (ctx)
              (format "/%s/" (or (helixel-sel-search-pattern ctx) "?")))
  :make-sel nil)

(helixel-register-kind movement
  :recreate nil
  :advance  #'helixel--repeat-advance-movement
  :display  "m"
  :make-sel nil)

(helixel-register-kind textobj
  :recreate nil
  :advance  #'helixel--repeat-advance-textobj
  :display  (lambda (ctx) (symbol-name (helixel-sel-textobj-command ctx)))
  :make-sel nil)

(provide 'helixel-repeat)
;;; helixel-repeat.el ends here
