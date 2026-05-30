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
;; Records every editing operation as a *transaction* (see helixel-core.el)
;; into a per-buffer ring; `.' replays the head transaction, optionally with
;; a numeric prefix.  `helixel-repeat-edit-pick' chooses an older entry from
;; the ring via completing-read.
;;
;; Architecture:
;;   Selection commands  → set helixel--pending-sel (selection descriptor)
;;   Editing commands    → helixel--record-edit → helixel--last-event + ring
;;   `.'                 → helixel-repeat-edit → sel-recreate + op-runner
;;
;; Both selection recreation and op execution use the `helixel-sel' struct
;; closures and the operator symbol-property registry in helixel-core.el.
;; This module knows nothing about specific kinds or operators.
;;
;; Depends on helixel-action and helixel-core.

;;; Code:

(require 'cl-lib)
(require 'helixel-action)
(require 'helixel-core)

;; ── State variables ──
(defvar helixel--inhibit-action-track)
(defvar helixel--current-state)

;; ---------------------------------------------------------------------------
;; Selection Context
;;
;; `helixel--pending-sel' and `helixel--sel-push'/`helixel--sel-pop'
;; are defined in `helixel-core.el'.  Selection commands push; editing
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

;; ── Insert recording (pre-command-hook based) ──
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

;; ── Record & replay entries ──
(defun helixel--record-edit (operator &rest extra)
  "Record edit OPERATOR with current selection context and EXTRA payload.
Pops `helixel--pending-sel' via `helixel--sel-pop' (consumes the
pending selection).  Looks up the runner and display from the operator
registry and stores them in the transaction so `helixel--execute-edit'
can dispatch without registry lookups.
Builds a transaction via `helixel--make-tx', pushes it onto
the action ring, and stores the most recent edit in `helixel--last-event'.
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
      (setq helixel--repeat-permanent-flip nil)
      (helixel--live-edit-set tx)
      ;; Always set last-event so callers that skip tracking-open
      ;; (tests, programmatic use) still have a valid edit to replay.
      ;; `helixel-event-commit' may be a no-op when live-event is nil.
      (setq helixel--last-event tx)
      (helixel-event-commit))))

(defun helixel--update-last-event (new-tx)
  "Update `helixel--last-event' payload to NEW-TX."
  (when (and helixel--last-event (helixel-event-p helixel--last-event))
    (setf (helixel-event-payload helixel--last-event)
          (helixel-event-payload new-tx))))

;; ---------------------------------------------------------------------------
;; Insert-keys accessor (consumed by helixel-editing.el's op runners)

(defsubst helixel--repeat-get-keys (tx)
  "Return the :keys key-sequence vector from TX payload, or nil."
  (plist-get (helixel-event-payload tx) :keys))

(defun helixel--execute-keys (keys)
  "Execute recorded KEYS (a key vector).
For printable characters, uses `insert-char' directly then runs
`post-self-insert-hook' (for `electric-pair-mode' etc.) with
`last-command-event' bound to the character.
For non-printable keys, uses `execute-kbd-macro'."
  (let ((helixel--inhibit-repeat-record t)
        (helixel--inhibit-action-track t))
    (when (and keys (> (length keys) 0))
      (dolist (key (append keys nil))
        (if (and (characterp key) (>= key 32) (/= key 127))
            ;; Printable char: direct insertion + post-self-insert-hook.
            ;; Using `insert-char' preserves the region (unlike
            ;; `self-insert-command') while binding `last-command-event'
            ;; lets `electric-pair-mode' and other hook functions work.
            ;; Deactivate mark first so hooks see the same region
            ;; state as during manual insertion (no accidental wrapping).
            (let ((last-command-event key))
              (insert-char key 1 t)
              (deactivate-mark)
              (run-hooks 'post-self-insert-hook))
          ;; Non-printable key: use execute-kbd-macro.
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

;; ── Flip-dir, all-buffer, line-pass ──

(defun helixel--repeat-line-pass (tx sel advance start-pos dir cnt
                                     &optional preview-p)
  "Process one line per step from START-POS in direction DIR.
TX is the edit transaction, SEL the selection descriptor.
ADVANCE is the operator advance tag, CNT the starting count.
If PREVIEW-P is non-nil, only recreate selections without executing edits.

ADVANCE controls two things:
  1. Whether to auto-advance at all (nil = recreate at point only).
  2. The stepping algorithm when doing all-buffer/all-dir line passes:
     \=`line' → simple `forward-line' (op doesn't move point, e.g. insert,
              surround, indent).
     nil     → bol/eol check before `forward-line' (op may have moved
              point, e.g. kill, change)."
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

(defun helixel--repeat-line-preview (tx sel reverse-p)
  "Preview all-buffer line repeat for `helixel-repeat-selection'.
Uses TX, SEL, REVERSE-P and `helixel--repeat-line-pass'
for correct per-line stepping with the operator's advance tag.
Derives the op advance tag from TX internally."
  (let* ((dir (if reverse-p -1 1))
         (start (if (> dir 0) (point-min) (point-max)))
         (op (helixel-event-op tx))
         (cnt 0))
    (save-excursion
      (goto-char start)
      (setq cnt (helixel--repeat-line-pass
                 tx sel (or (helixel--op-advance op) 'line)
                 start dir cnt t)))
    (helixel--repeat-echo cnt)))

;; ── All-buffer / all-dir line handlers ──
;; Registered via the kind registry in helixel-move.el.

(defun helixel--all-buffer-line (edit prefix)
  "All-buffer repeat handler for line selections, for EDIT and PREFIX.
Forward pass then backward pass from the marker position.
For chain ops, does a single pass from the buffer edge."
  (let* ((sel (helixel-event-sel edit))
         (op (helixel-event-op edit))
         (reverse-p (helixel-repeat-prefix-reverse-p prefix))
         (marker (car (helixel-event-mark-region edit)))
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

;; ── Search advance state (reset per repeat-edit/repeat-selection) ──

(defvar helixel--search-advance-done nil
  "Bound to t when `helixel--repeat-advance-search' has positioned point.
Read by `helixel--recreate-search' to skip its internal search.")

(defvar helixel--advance-search-last-pos nil
  "Last `match-beginning' processed by `helixel--repeat-advance-search'.
Used to detect zero-width matches that would cause infinite loops.
Bound per all-dir/all-buffer repeat session.")

(defvar helixel--advance-search-edge-seen nil
  "Non-nil when a zero-width buffer-edge match was already processed.
Used to prevent infinite loops with patterns like `$' at
end-of-buffer or `^' at beginning-of-buffer.")

(defvar-local helixel--repeat-has-preview nil
  "Set to t by `helixel-repeat-selection', consumed by `helixel-repeat-edit'.
When t, `helixel-repeat-edit' uses the active region directly
instead of recreating the selection, so the preview is honoured.")



(defun helixel--repeat-flip-tx-dir ()
  "Toggle `helixel--repeat-permanent-flip' for line/search selections.
Like \=`N\=` for search, \=`-.\=` permanently reverses dot-repeat direction.
No-op for movement, textobj, or nil selections.
Returns t on success, nil otherwise."
  (when-let* ((tx helixel--last-event)
              (sel (helixel-event-sel tx))
              (kind (helixel-sel-get-kind sel)))
    (when (memq kind '(line search))
      (setq helixel--repeat-permanent-flip
            (not helixel--repeat-permanent-flip))
      t)))

;; ── Common repeat setup ──

(defun helixel--repeat-setup (raw-prefix)
  "Common setup for `helixel-repeat-edit' and `helixel-repeat-selection'.
Takes RAW-PREFIX (the raw prefix argument from `interactive').
Gets the last edit transaction (falling back to the event ring if
`helixel--last-event' is not an edit), parses the prefix argument,
handles permanent direction flip, and resets search-advance state.

Returns (TX PREFIX SAVED-STATE) where:
  TX           — resolved edit `helixel-event'
  PREFIX       — `helixel-repeat-prefix' struct
  SAVED-STATE  — previous `helixel--current-state'

Signals `user-error' when no edit is available."
  (let ((tx helixel--last-event))
    (unless tx
      (user-error "No previous edit"))
    ;; Fall back to most recent edit in ring if last-event is
    ;; not an edit (e.g. movement event from event-commit).
    (unless (helixel-event-op tx)
      (setq tx (cl-loop for e in helixel--event-ring
                        when (helixel-event-op e)
                        return e))
      (unless tx
        (user-error "No previous edit")))

    (let* ((saved-state helixel--current-state)
           (flip-dir-p (or (eq raw-prefix '-)
                           (and (integerp raw-prefix)
                                (< raw-prefix 0))))
           (prefix (helixel--decode-repeat-prefix raw-prefix)))
      (when flip-dir-p (helixel--repeat-flip-tx-dir))
      ;; Reset search-advance state for fresh repeat session.
      (setq helixel--search-advance-done nil
            helixel--advance-search-last-pos nil
            helixel--advance-search-edge-seen nil)
      (list tx prefix saved-state))))

;; ── Interactive entry points ──
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
  (when (and executing-kbd-macro (not helixel--last-event))
    (user-error "No previous edit to repeat (kmacro playback)"))
  (cl-destructuring-bind (tx prefix saved-state)
      (helixel--repeat-setup raw-prefix)
    (let* ((helixel--inhibit-repeat-record t)
           (helixel--inhibit-action-track t)
           (use-preview helixel--repeat-has-preview)
           (mode (helixel-repeat-prefix-mode prefix))
           (sel (helixel-event-sel tx)))
      (setq helixel--repeat-has-preview nil)
      (unwind-protect
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
                      (error-message-string err))))
        (setq helixel--current-state saved-state)))))

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
  (cl-destructuring-bind (tx prefix saved-state)
      (helixel--repeat-setup raw-prefix)
    (let* ((helixel--inhibit-repeat-record t)
           (helixel--inhibit-action-track t))
      (unless (helixel-event-sel tx)
        (user-error (concat "Previous edit has no selection to repeat."
                            "  Use a textobj (e.g. ciw)"
                            " or line/rect selection first")))
      (unwind-protect
          (let* ((reverse-p (helixel-repeat-prefix-reverse-p prefix))
                 (mode (helixel-repeat-prefix-mode prefix))
                 (n (helixel-repeat-prefix-n prefix))
                 (sel (helixel-event-sel tx)))
            (if (and (eq mode :all-buffer)
                     (eq (helixel-sel-get-kind sel) 'line))
                ;; Line needs per-line stepping via
                ;; `helixel--repeat-line-pass' (different from generic
                ;; advance loop due to operator advance tag handling).
                (helixel--repeat-line-preview tx sel reverse-p)
              ;; Generic: strategy-driven preview
              (let ((strategy (helixel--build-strategy tx reverse-p)))
                (helixel--repeat-preview strategy tx mode n
                                         reverse-p))))
        (setq helixel--current-state saved-state))
      (setq helixel--repeat-has-preview t))))

;; ── Interactive entry points ──
(defun helixel-repeat-edit-pick ()
  "Choose a past edit from the event ring and replay it.
Scans `helixel--event-ring' for entries with an :op.
The chosen event's edit data becomes the new `helixel--last-event'."
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
        ;; Reconstruct tx from event.  Payload keys are spread via apply.
        ;; helixel--make-tx signature: (op sel-ctx &rest payload-kv)
        ;; so sel-ctx is the second positional arg, then
        ;; remaining payload plist keys are spread via apply.
        (helixel--update-last-event
         (apply #'helixel--make-tx
                (helixel-event-op event)
                (helixel-event-sel event)
                :display (helixel-event-display-format event)
                :runner (helixel-event-runner event)
                (helixel-event-payload event)))
        (helixel-repeat-edit)))))

(defun helixel-repeat-debug ()
  "Pretty-print `helixel--last-event' and edit events in the event ring."
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
        (insert ";; helixel--last-event (display: "
                (or (and helixel--last-event
                         (helixel--tx-display helixel--last-event))
                    "<none>")
                ")\n")
        (pp helixel--last-event (current-buffer))
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



;; ----------------------------------------------------------------------
;; Prefix parsing
;; ----------------------------------------------------------------------

(cl-defstruct helixel-repeat-prefix
  "Decoded dot-repeat prefix argument."
  mode      ;; :all-buffer | :all-dir | :n-times
  n         ;; integer count (>= 1)
  reverse-p ;; boolean
  raw)      ;; original raw-prefix

(defun helixel--decode-repeat-prefix (raw-prefix)
  "Parse RAW-PREFIX into a `helixel-repeat-prefix' struct.

Semantics:
  \\[universal-argument] .    → :all-buffer, forward
  \\[universal-argument] - .  → :all-buffer, reverse
  0 .           → :all-dir, forward
  - .           → :n-times 1 (caller flips direction permanently)
  -3 .          → :n-times 3 (caller flips direction permanently)
  3 .           → :n-times 3, forward
  \\[universal-argument] -3 . → :n-times 3, reverse (one-time)
  \\[universal-argument] 3 .  → :all-buffer (n=3 ignored)

Bare '-' (raw-prefix = symbol \\='-) is detected by the caller
to permanently flip the stored direction (like N for search)."
  (let* ((all-buffer-p (consp raw-prefix))
         (all-dir-p (and (integerp raw-prefix) (eql raw-prefix 0)))
         (n (cond ((not raw-prefix) 1)
                  ((consp raw-prefix)
                   (abs (prefix-numeric-value raw-prefix)))
                  ((integerp raw-prefix) (abs raw-prefix))
                  (t 1)))
         (reverse-p (and (consp raw-prefix)
                        (< (prefix-numeric-value raw-prefix) 0)))
         (mode (cond (all-buffer-p :all-buffer)
                     (all-dir-p    :all-dir)
                     (t            :n-times))))
    (make-helixel-repeat-prefix
     :mode mode :n n :reverse-p reverse-p :raw raw-prefix)))


;; ----------------------------------------------------------------------
;; Repeat strategy struct
;; ----------------------------------------------------------------------

(cl-defstruct helixel-repeat-strategy
  "Self-contained repeat strategy.
ADVANCE:      fn(edit) → t|nil — move to next target, create region.
APPLY:        fn(edit) → nil   — execute edit at current position.
RESET:        fn(edit) → nil   — return to start position (all-buffer).
ALL-BUFFER-FN: fn(edit prefix) → nil — custom all-buffer scan.
ALL-DIR-FN:    fn(edit) → nil — custom all-dir scan, or nil.
  When non-nil, `helixel--repeat-all-dir' delegates to this
  instead of the generic advance/apply loop."
  (advance nil :read-only t)
  (apply   nil :read-only t)
  (reset   nil :read-only t)
  (all-buffer-fn nil :read-only t)
  (all-dir-fn nil :read-only t))


;; ----------------------------------------------------------------------
;; Shared direction-flip helper (used by all strategy builders)
;; ----------------------------------------------------------------------

(defun helixel--maybe-flip-dir-edit (edit reverse-p)
  "Return EDIT with :dir flipped for line/search selections, or EDIT unchanged.
When REVERSE-P or `helixel--repeat-permanent-flip' is non-nil and the
selection kind is `line' or `search', creates a copy of EDIT with
:dir flipped.  Otherwise returns EDIT unchanged."
  (let* ((sel (helixel-event-sel edit))
         (kind (and sel (helixel-sel-get-kind sel)))
         (effective-reverse (or reverse-p helixel--repeat-permanent-flip)))
    (if (and effective-reverse sel (memq kind '(line search)))
        (let* ((current-dir (if (eq kind 'search)
                                (helixel-sel-search-dir sel)
                              (helixel-sel-line-dir sel)))
               (reversed-sel (helixel-sel-update-ctx
                              sel :dir (helixel--flip-dir current-dir)))
               (new-edit (helixel--copy-tx edit)))
          (setf (helixel-event-sel new-edit) reversed-sel)
          new-edit)
      edit)))

;; ----------------------------------------------------------------------
;; Strategy builder — dispatches on op
;; ----------------------------------------------------------------------

(defun helixel--build-strategy (edit &optional reverse-p)
  "Return a `helixel-repeat-strategy' for EDIT.
If the operator has a :strategy-builder in the op registry, use it.
Otherwise fall back to `helixel--default-strategy-builder'.
If REVERSE-P is non-nil, flip :dir in the selection ctx
for line/search kinds."
  (let* ((op (helixel-event-op edit))
         (custom-builder (helixel--op-strategy-builder op)))
    (if custom-builder
        (funcall custom-builder edit reverse-p)
      (helixel--default-strategy-builder edit reverse-p))))


;; ----------------------------------------------------------------------
;; Default strategy builder — selection-kind driven
;; ----------------------------------------------------------------------

(defun helixel--default-strategy-builder (edit &optional reverse-p)
  "Build a default repeat strategy for EDIT.
If REVERSE-P is non-nil, flip :dir for line/search kinds.
Looks up the advance function from the kind registry.
When the operator has no :repeat-advance tag, the advance
just recreates the selection at the current position
\(no actual advancing — e.g. kill auto-moves point)."
  (let* ((sel (helixel-event-sel edit))
         (kind (and sel (helixel-sel-get-kind sel)))
         (op (helixel-event-op edit))
         (adv-tag (helixel--op-advance op))
         (effective-edit (helixel--maybe-flip-dir-edit edit reverse-p))
         (advance-fn
          (cond
           ;; Advance tag present: use the kind's advance function
           ((and adv-tag (helixel--kind-advance kind))
            (helixel--kind-advance kind))
           ;; No advance tag (e.g. kill): just recreate at point
           ;; Catches errors = no more targets at buffer edge
           (t
            (lambda (ed)
              (condition-case nil
                  (progn
                    (helixel-sel-call-recreate
                     (helixel-event-sel ed))
                    t)
                (error nil)))))))
    (make-helixel-repeat-strategy
     :advance (lambda (_ed) (funcall advance-fn effective-edit))
     :apply   (lambda (_ed) (helixel--execute-edit effective-edit))
     :reset   (lambda (_ed)
                (when-let* ((m (car (helixel-event-mark-region
                                       effective-edit))))
                  (goto-char (marker-position m))))
     :all-buffer-fn (helixel--kind-all-buffer-fn kind)
     :all-dir-fn (helixel--kind-all-dir-fn kind))))


;; ----------------------------------------------------------------------
;; Generic repeat loops
;; ----------------------------------------------------------------------

(defun helixel--repeat-all-buffer (strategy edit prefix)
  "Use STRATEGY over the entire buffer from EDIT.
If STRATEGY has a custom `all-buffer-fn', delegate to it.
Otherwise: reset to start, then advance+apply from point-min
\(or point-max if PREFIX is reverse)."
  (if-let* ((custom-fn (helixel-repeat-strategy-all-buffer-fn strategy)))
      (funcall custom-fn edit prefix)
    (funcall (helixel-repeat-strategy-reset strategy) edit)
    (save-excursion
      (goto-char (if (helixel-repeat-prefix-reverse-p prefix)
                     (point-max)
                   (point-min)))
      (let ((cnt 0))
        (while (funcall (helixel-repeat-strategy-advance strategy) edit)
          (cl-incf cnt)
          (funcall (helixel-repeat-strategy-apply strategy) edit))
        (helixel--repeat-echo cnt)))))

(defun helixel--repeat-all-dir (strategy edit)
  "Use STRATEGY on EDIT over all remaining targets from current position.
If STRATEGY has a custom `all-dir-fn', delegate to it."
  (if-let* ((custom-fn (helixel-repeat-strategy-all-dir-fn strategy)))
      (funcall custom-fn edit)
    (let ((cnt 0))
      (while (funcall (helixel-repeat-strategy-advance strategy) edit)
        (cl-incf cnt)
        (funcall (helixel-repeat-strategy-apply strategy) edit))
      (helixel--repeat-echo cnt))))

(defun helixel--repeat-n (strategy edit n)
  "Use STRATEGY on EDIT N times from current position."
  (dotimes (_ n)
    (unless (funcall (helixel-repeat-strategy-advance strategy) edit)
      (user-error "No more targets for dot-repeat"))
    (funcall (helixel-repeat-strategy-apply strategy) edit))
  (helixel--repeat-echo n))

(defun helixel--repeat-preview (strategy edit mode n &optional reverse-p)
  "Preview STRATEGY over EDIT — advance only, no apply.
MODE is :all-buffer, :all-dir, or :n-times.
N is the repeat count for :n-times mode.
When REVERSE-P is non-nil, for :all-buffer start from `point-max'
instead of `point-min' so backward scans work correctly.
For :all-dir and :n-times, the direction is already flipped in
the strategy via `helixel--build-strategy'."
  (pcase mode
    (:all-buffer
     (funcall (helixel-repeat-strategy-reset strategy) edit)
     (goto-char (if reverse-p (point-max) (point-min)))
     (let ((cnt 0))
       (while (funcall (helixel-repeat-strategy-advance strategy) edit)
         (cl-incf cnt))
       (helixel--repeat-echo cnt)))
    (:all-dir
     (let ((cnt 0))
       (while (funcall (helixel-repeat-strategy-advance strategy) edit)
         (cl-incf cnt))
       (helixel--repeat-echo cnt)))
    (:n-times
     (dotimes (_ n)
       (unless (funcall (helixel-repeat-strategy-advance strategy) edit)
         (user-error "No more targets for dot-repeat")))
     (helixel--repeat-echo n))))


(provide 'helixel-repeat)
;;; helixel-repeat.el ends here
