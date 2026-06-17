;;; helixel-chain.el --- chain recording & compound dot-repeat  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

;; Author: jixiuf
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Keywords: convenience

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;;; Commentary:
;;
;; Compound dot-repeat: `@' starts a chain, ESC ends it, `C-g'
;; cancels.  Chain recording captures the LIST of helixel-action
;; values produced by the commands run during the chain.  Replay
;; iterates the list and replays each entry in chronological order.
;;
;; Architecture (v2 — eager commit, single capture point):
;;
;;   Capture: a single `post-command-hook' handles EVERY command:
;;     1. Eager commit — commit any pending `helixel--live-action'
;;        at the END of its command (not deferred to next command).
;;        This fires `action-commit-hook' → `helixel--chain-push-entry' pushes
;;        helixel entries to action-list.
;;     2. Vanilla capture — for non-helixel commands, create a
;;        vanilla entry with `this-command', `current-prefix-arg',
;;        and key sequence, then push DIRECTLY to action-list.
;;     No vanilla queue, no flush hacks, no ordering flags.
;;
;;   Replay: the chain runner iterates the action-list and dispatches:
;;     - Edit entries (runner present)       → funcall runner
;;     - Movement entries (sel, no runner)   → recreate selection
;;     - Vanilla entries (by-command only)   → call-interactively
;;       with saved prefix-arg; key-sequence fallback on error.
;;
;;   Entry-kind propagation: insert-entry commands propagate their
;;   entry-kind to the chain session's init-ctx during recording
;;   (via `helixel--chain-propagate-entry-kind'), so search-based
;;   chains correctly skip the current match on dot-repeat.

;;; Code:

(require 'cl-lib)
(require 'helixel-core)         ; helixel-action-create
(require 'helixel-ring)         ; helixel-action-commit-hook
(require 'helixel-macros)       ; helixel-with-action-tracking
(require 'helixel-repeat)       ; helixel--maybe-flip-dir-action

(defvar helixel--current-state)  ; from `helixel-state'

;; ── Session struct (single buffer-local) ──

(cl-defstruct (helixel-chain-session
               (:conc-name helixel-chain-session-)
               (:copier nil))
  "Per-buffer chain recording session.
Slots:
  ACTIVE-P    — non-nil while recording.
  ACTION-LIST — list of `helixel-action' values committed during the
                chain (chronological after `nreverse').
  INIT-CTX    — `helixel-sel' snapshotted at chain-start; drives
                advance behaviour at replay time.
  INIT-BOUNDS — (BEG . END) markers of the initial region, or nil."
  active-p
  action-list
  init-ctx
  init-bounds)

(defvar-local helixel--chain-session nil
  "Per-buffer `helixel-chain-session' for the in-progress chain, or nil.")

(defsubst helixel--chain-active-p ()
  "Return non-nil while a chain is being recorded in this buffer."
  (and helixel--chain-session
       (helixel-chain-session-active-p helixel--chain-session)))

;; ── Extension points for third-party integration ──

(defcustom helixel-chain-vanilla-exclude-predicates
  '(helixel--chain-vanilla-exclude-default-p)
  "List of predicate functions for excluding vanilla commands.
Each function receives the command symbol and should return
non-nil to EXCLUDE the command from vanilla capture during
chain recording.

Built-in default excludes:
  - `self-insert-command' (captured by insert-record)
  - Commands running during insert state (captured by insert-record)
  - Commands whose name starts with \"helixel-\" (captured by
    `helixel--chain-push-entry')
  - Chain-control commands (chain-start/end/cancel, normal-escape)

Add functions here to exclude additional commands (e.g. commands
from third-party packages that have their own recording mechanism)."
  :type '(repeat function)
  :group 'helixel)

(defcustom helixel-chain-vanilla-replay-function nil
  "Optional function to replay vanilla entries instead of `call-interactively'.
If non-nil, called with two arguments:
  CMD    — the command symbol to replay
  ENTRY  — the vanilla `helixel-action' entry (contains :prefix, :keys).
Should execute the command's effect at point.
When nil (default), vanilla entries are replayed via
`call-interactively' with the saved prefix argument.

Set this to provide custom replay for commands that need special
handling (e.g. commands that read from the minibuffer or depend on
state not captured in the entry)."
  :type '(choice (const nil) function)
  :group 'helixel)

(defvar helixel-chain-start-hook nil
  "Hook run after a chain recording session starts.
Called with no arguments.  The chain session is available via
`helixel--chain-session'.")

(defvar helixel-chain-end-hook nil
  "Hook run before a chain recording session is committed.
Called with the action-list (chronological order) as argument.
The chain session is still active; use this to add final entries
or modify the action-list before it is sealed into the chain action.")

(defvar helixel-chain-cancel-hook nil
  "Hook run when a chain recording session is cancelled.
Called with no arguments before the session is destroyed.")

(defconst helixel--chain-control-commands
  '(helixel-repeat-chain-start
    helixel-repeat-chain-end
    helixel-repeat-chain-cancel
    helixel-normal-escape)
  "Commands that control chain lifecycle; excluded from action-list.")

(defun helixel--chain-vanilla-exclude-default-p (cmd)
  "Default vanilla-command exclusion predicate.
Returns non-nil if CMD should NOT be captured as a vanilla entry.
Excludes self-insert, insert-mode commands, helixel commands, and
chain-control commands."
  (or (eq cmd 'self-insert-command)
      (eq helixel--current-state 'insert)
      (string-prefix-p "helixel-" (symbol-name cmd))
      (memq cmd helixel--chain-control-commands)))

;; ── action-list push helper (unified path for helixel + vanilla) ──

(defun helixel--chain-push-entry (entry)
  "Push ENTRY into the active chain session's action-list.
Filters out chain-control commands and non-replayable entries.
Called from `helixel-action-commit-hook' (helixel entries) and
`helixel--chain-post-cmd-hook' (vanilla entries), giving a single
code path for action-list accumulation."
  (when (helixel--chain-active-p)
    (unless (memq (helixel-action-by-command entry)
                  helixel--chain-control-commands)
      (when (or (helixel-action-runner entry)
                (helixel-action-sel entry)
                (and (helixel-action-by-command entry)
                     (not (eq (helixel-action-category entry)
                              'state))))
        (push entry (helixel-chain-session-action-list
                     helixel--chain-session))))))

;; ── Entry-kind propagation hook ──

(defvar helixel-chain-insert-entry-functions nil
  "Abnormal hook run when entering insert mode during a chain.
Called with one argument ENTRY-KIND, either `insert' (from `i')
or `append' (from `a').  The default handler propagates the
entry-kind to the chain session's init-ctx so search-initiated
chains can skip the current match on dot-repeat.

Third-party packages can add functions here to react to insert-mode
entry during chain recording.")

(defun helixel--chain-propagate-entry-kind (entry-kind)
  "Propagate ENTRY-KIND to the active chain session's init-ctx.
Ensures `helixel-search--skip-current-match' can skip the current
match during dot-repeat advance for search-initiated chains, and
the chain advance positions point at BOL/EOL for line-initiated
insert/append chains.
No-op when no chain is active or the init-ctx is not a search/line sel."
  (when (and (helixel--chain-active-p)
             (helixel-chain-session-init-ctx helixel--chain-session)
             (memq (helixel-sel-kind helixel--pending-sel)
                   '(search line)))
    (setf (helixel-chain-session-init-ctx helixel--chain-session)
          (helixel-sel-update-ctx
           (helixel-chain-session-init-ctx helixel--chain-session)
           :entry-kind entry-kind))))

;; ── Runner helpers ──

(defun helixel--chain-replay-edit (sub-action)
  "Replay an edit entry SUB-ACTION.
For movement-kind sels (built from pre-edit w/e/b moves),
recreates the accumulated selection before running the runner.
For line-kind sels with :entry-kind (insert/append from `i'/`a'),
also recreates to reposition point to BOL/EOL — the chain
advance may not have applied entry-kind positioning.
For other sel kinds (search, rect, etc.) the chain advance
already positioned point and the runner handles the rest."
  (when-let* ((edit-sel (helixel-action-sel sub-action))
              (kind (helixel-sel-kind edit-sel)))
    (when (or (eq kind 'movement)
              (and (eq kind 'line)
                   (plist-get (helixel-sel-ctx edit-sel) :entry-kind)))
      (deactivate-mark)
      (condition-case nil
          (helixel-sel-call-recreate edit-sel)
        (user-error nil))))
  (funcall (helixel-action-runner sub-action) sub-action))

(defun helixel--chain-replay-movement (sub-action)
  "Replay a movement-only entry SUB-ACTION via selection recreation.
Used for inter-edit positioning (e.g. j, gh between edits of
different sel kinds) and post-chain navigation."
  (deactivate-mark)
  (condition-case nil
      (helixel-sel-call-recreate (helixel-action-sel sub-action))
    (user-error nil)))

(defun helixel--chain-replay-vanilla (sub-action)
  "Replay a vanilla (non-helixel) entry SUB-ACTION.
Primary: replay saved key sequence via `execute-kbd-macro'
\(triggers full command loop, works in batch mode).  Wrapped in
`helixel-with-replay-as' to prevent hooks from re-recording the
replayed commands as new chain entries.
Fallback: `call-interactively' with saved `prefix-arg'.
Third-party override: `helixel-chain-vanilla-replay-function'."
  (when-let* ((cmd (helixel-action-by-command sub-action))
              ((commandp cmd)))
    (if helixel-chain-vanilla-replay-function
        (funcall helixel-chain-vanilla-replay-function cmd sub-action)
      (let ((keys (helixel-action-payload-get sub-action :keys)))
        (if (and keys (vectorp keys) (> (length keys) 0))
            (condition-case err
                (helixel-with-replay-as 'dot
                  (execute-kbd-macro keys))
              (error
               (message "helixel-chain: key replay error %s: %s"
                        cmd (error-message-string err))))
          (let ((current-prefix-arg
                 (helixel-action-payload-get sub-action :prefix))
                (real-this-command cmd))
            (condition-case err
                (call-interactively cmd)
              (error
               (message "helixel-chain: error replaying %s: %s"
                        cmd (error-message-string err))))))))))

(defun helixel--chain-build-skip-vector (action-list chain-sel)
  "Return a `bool-vector' marking entries in ACTION-LIST to skip during replay.
A movement-only entry (sel but no runner) is skipped when:
  (a) its sel kind matches the next edit's sel kind (pre-edit), or
  (b) its sel kind matches CHAIN-SEL's kind (advance handles positioning).
Uses a single backward pass — O(N) instead of O(N*M) per-entry scans."
  (let* ((len (length action-list))
         (skips (make-bool-vector len nil))
         (next-edit-kind nil))
    (cl-loop for i from (1- len) downto 0
             for sub-action = (nth i action-list)
             do
             (if (helixel-action-runner sub-action)
                 (setq next-edit-kind
                       (when-let* ((s (helixel-action-sel sub-action)))
                         (helixel-sel-kind s)))
               (when (and (helixel-action-sel sub-action)
                          (not (helixel-action-runner sub-action)))
                 (let ((kind (helixel-sel-kind
                              (helixel-action-sel sub-action))))
                   (when (or (eq kind next-edit-kind)
                             (and chain-sel
                                  (eq kind (helixel-sel-kind chain-sel))))
                     (aset skips i t))))))
    skips))

;; ── Chain runner ──

(defun helixel--repeat-chain-runner (tx)
  "Replay each tx in chain TX's `:action-list' payload, in order.
For search-initiated chains, reposition to `match-beginning' before
replay so insert-position semantics match the original recording.

Dispatch per entry:
  - Skip (pre-computed)      → pre-edit movement, advance covers it.
  - Edit (runner present)    → recreate sel then funcall runner.
  - Movement (sel, no runner) → recreate selection for positioning.
  - Vanilla (by-command only) → `execute-kbd-macro' / `call-interactively'."
  (let* ((chain-sel (helixel-action-sel tx))
         (action-list (helixel-action-payload-get tx :action-list)))
    (helixel-with-replay-as 'dot
      (when action-list
        (when (and chain-sel (eq (helixel-sel-kind chain-sel) 'search)
                   (match-beginning 0))
          (goto-char (match-beginning 0)))
        (let ((skips (helixel--chain-build-skip-vector action-list chain-sel)))
          (cl-loop for i from 0 for sub-action in action-list
                   do
                   (cond
                    ((aref skips i) nil)
                    ((helixel-action-runner sub-action)
                     (helixel--chain-replay-edit sub-action))
                    ((helixel-action-sel sub-action)
                     (helixel--chain-replay-movement sub-action))
                    (t
                     (helixel--chain-replay-vanilla sub-action)))))))))

(helixel-register-op chain
  :display "chain"
  :runner #'helixel--repeat-chain-runner)


;; ── Cleanup helper ──

(defun helixel--chain-reset-state ()
  "Reset all chain bookkeeping state.
Releases any initial-region markers (so they don't pin buffer text),
clears `helixel--chain-session'.  Idempotent."
  (when-let* ((s helixel--chain-session)
              (bounds (helixel-chain-session-init-bounds s)))
    (let ((mb (car bounds)) (me (cdr bounds)))
      (when (marker-position mb) (set-marker mb nil))
      (when (marker-position me) (set-marker me nil))))
  (setq helixel--chain-session nil))


;; ── post-command-hook: unified capture (eager commit + vanilla) ──

(defun helixel--chain-post-cmd-hook ()
  "Capture every command during chain recording in correct order.
Runs in `post-command-hook'.

Step 1 — Eager commit:
  Commit any pending `helixel--live-action' at command-end rather
  than deferring to the next command's `tracking-open'.  This
  fires `action-commit-hook' → `helixel--chain-push-entry' pushes the
  helixel entry to action-list at the CORRECT chronological position.

Step 2 — Vanilla capture:
  For non-helixel, non-self-insert, non-chain-control commands,
  push a vanilla entry directly to action-list.  Each entry carries
  the command symbol, prefix argument, and key sequence for
  faithful replay."
  (when (helixel--chain-active-p)
    ;; Step 1: Eager commit — flush pending helixel action NOW.
    (when helixel--live-action
      (helixel--action-commit))
    ;; Step 2: Capture vanilla commands via unified push path.
    (when (and this-command
               (symbolp this-command)
               (commandp this-command)
               (not (run-hook-with-args-until-success
                     'helixel-chain-vanilla-exclude-predicates
                     this-command)))
      (helixel--chain-push-entry
       (make-helixel-action
        :category 'movement
        :subcat 'vanilla
        :by-command this-command
        :op nil :runner nil :sel nil
        :payload (list :prefix current-prefix-arg
                       :keys (ignore-errors
                               (copy-sequence
                                (this-single-command-keys))))
        :mark-region (let ((pm (point-marker)))
                       (cons pm pm))
        :timestamp (float-time)
        :buffer (current-buffer))))))

;; ── Lifecycle commands ──

;;;###autoload
(defun helixel-repeat-chain-start ()
  "Start recording a compound dot-repeat chain.
Snapshots the current selection context for advance decisions.
Commands run from now on are accumulated (their replay entries are
appended to the session via `helixel-action-commit-hook' for
helixel commands, and directly in `post-command-hook' for vanilla
commands).  Call `helixel-repeat-chain-end' to finish or
`helixel-repeat-chain-cancel' to discard.

Flushes any deferred live action (e.g. from `x' before `@') so
that pre-chain commands don't leak into the action-list."
  (interactive)
  (when (or (helixel--chain-active-p) executing-kbd-macro)
    (user-error "Already chaining or macro replay in progress"))
  ;; Flush any deferred live action (e.g. from `x' before `@')
  ;; so it commits to the ring BEFORE the chain hook is active,
  ;; preventing pre-chain selections from leaking into the action-list.
  (helixel--action-commit)
  (add-hook 'post-command-hook #'helixel--chain-post-cmd-hook nil t)
  (setq helixel--chain-session
        (make-helixel-chain-session
         :active-p t
         :action-list nil
         :init-ctx helixel--pending-sel
         :init-bounds (when (use-region-p)
                        (cons (copy-marker (region-beginning))
                              (copy-marker (region-end))))))
  (run-hooks 'helixel-chain-start-hook)
  (message "Chain rec \u2022 esc to finish"))

;;;###autoload
(defun helixel-repeat-chain-end ()
  "Stop chain recording and create a compound chain transaction.
Builds a chain action whose `:action-list' payload is the accumulated
list of sub-txs from this chain.  Advance behaviour is determined
by the initial selection context snapshotted at chain-start."
  (interactive)
  (unless (helixel--chain-active-p)
    (user-error "Not chaining"))
  ;; Eager commit in post-command-hook already handled the last
  ;; command's pending action.  Defensive commit for edge cases
  ;; (e.g. called programmatically without command loop).
  (when helixel--live-action
    (helixel--action-commit))
  (let* ((s helixel--chain-session)
         (_ (setf (helixel-chain-session-active-p s) nil))
         (action-list (nreverse (helixel-chain-session-action-list s)))
         (init-bounds (helixel-chain-session-init-bounds s))
         (init-ctx (helixel-chain-session-init-ctx s))
         (had-content (and action-list (consp action-list))))
    ;; If the cursor has left the original target range
    ;; (e.g. moved to a different line), disable advance so
    ;; `.` replays in-place instead of advancing to a
    ;; mismatched target.  Only applies to line/rect selections
    ;; — search advance moves to the next match regardless
    ;; of cursor position.
    (when (and init-ctx init-bounds
               (memq (helixel-sel-kind init-ctx) '(line rect))
               (not (and (marker-position (car init-bounds))
                         (marker-position (cdr init-bounds))
                         (>= (point) (car init-bounds))
                         (<= (point) (cdr init-bounds)))))
      (setq init-ctx nil))
    ;; Entry-kind (search chains) is propagated to init-ctx during
    ;; recording by `helixel--chain-propagate-entry-kind'.  At this
    ;; point the chain action is built with the fully-populated init-ctx.
    (run-hook-with-args 'helixel-chain-end-hook action-list)
    (when had-content
      (let ((tx (helixel-action-create 'chain init-ctx
                   :runner #'helixel--repeat-chain-runner
                   :display (format "chain(%d)" (length action-list))
                   :action-list action-list)))
        (setq helixel--last-action (helixel-action-copy tx))
        (helixel-with-action-tracking
            (:op 'chain :category 'edit :subcat 'chain)
          (helixel--live-action-set tx))))
    (let ((n (length (or action-list '()))))
      (remove-hook 'post-command-hook #'helixel--chain-post-cmd-hook t)
      (helixel--chain-reset-state)
      (if had-content
          (message "Chain recorded (%d txs)" n)
        (message "Chain empty \u2014 nothing recorded")))))

;;;###autoload
(defun helixel-repeat-chain-cancel ()
  "Discard the current chain without recording."
  (interactive)
  (remove-hook 'post-command-hook #'helixel--chain-post-cmd-hook t)
  (run-hooks 'helixel-chain-cancel-hook)
  (helixel--chain-reset-state)
  (message "Chain cancelled"))

(provide 'helixel-chain)
;;; helixel-chain.el ends here
