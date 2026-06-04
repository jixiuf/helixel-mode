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
;;   Editing commands    → helixel--record-edit → helixel--last-edit + ring
;;   `.'                 → helixel-repeat-edit → sel-recreate + op-runner
;;
;; Both selection recreation and op execution use the `helixel-sel' struct
;; registry lookups in helixel-core.el.
;; This module knows nothing about specific kinds or operators.
;;
;; Depends on helixel-action and helixel-core.

;;; Code:

(require 'cl-lib)
(require 'helixel-action)
(require 'helixel-core)
(require 'helixel-insert-record)
(require 'helixel-repeat-strategy)

;; ── State variables ──
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

;; Edit transactions are stored in the unified event ring
;; (`helixel--event-ring') as `:edit' entries.  No separate edit ring.
;; `helixel-repeat-edit-pick' filters the event ring for entries
;; that carry `:edit' data.


(defvar-local helixel--change-track-marker nil
  "Marker at position before entering insert during a change/insert operation.
Set by change and insert-entry commands.  Read in `helixel-insert-exit'
to extract :change-text.")



;; ---------------------------------------------------------------------------
;; Recording (called by editing commands in helixel-editing)

;; ── Record & replay entries ──
(defun helixel--record-edit (operator &rest extra)
  "Record edit OPERATOR with current selection context and EXTRA payload.
Pops `helixel--pending-sel' via `helixel--sel-pop' (consumes the
pending selection).  Looks up the runner and display from the operator
registry and stores them in the transaction so `helixel--execute-edit'
can dispatch without registry lookups.
Builds a transaction via `helixel-edit-create', pushes it onto
the event ring, and stores the most recent edit in `helixel--last-edit'.
Also notifies the event ring so `;' jumping picks up the new edit.

NOTE: Caller is responsible for calling `helixel--tracking-open' first.
The `helixel-define-command' macro handles this automatically."
  (unless (or (helixel-replaying-p) executing-kbd-macro
              defining-kbd-macro)
    (let* ((pop-sel (helixel--sel-pop))
           (runner (helixel--op-runner operator))
           (tx (apply #'helixel-edit-create operator
                      pop-sel
                      :runner runner
                      extra)))
      (let ((new-tx (helixel-edit-copy tx)))
        (setf (helixel-edit-display new-tx)
              (helixel--op-display operator tx))
        (setq tx new-tx))
      (setq helixel--repeat-permanent-flip nil)
      (helixel--live-edit-set tx)
      ;; Always set last-event so callers that skip tracking-open
      ;; (tests, programmatic use) still have a valid edit to replay.
      ;; `helixel-edit-commit' may be a no-op when live-event is nil.
      (setq helixel--last-edit tx)
      (helixel-edit-commit))))


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
          (deactivate-mark)
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
         (op (helixel-edit-op tx))
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
  (let* ((sel (helixel-edit-sel edit))
         (op (helixel-edit-op edit))
         (reverse-p (helixel-repeat-prefix-reverse-p prefix))
         (marker (car (helixel-edit-mark-region edit)))
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
  (let* ((sel (helixel-edit-sel edit))
         (op (helixel-edit-op edit))
         (dir (if (eq (helixel-sel-line-dir sel) 'backward) -1 1))
         (adv (or (helixel--op-advance op) 'line))
         (cnt 0))
    (setq cnt (helixel--repeat-line-pass edit sel adv (point) dir cnt))
    (helixel--repeat-echo cnt)))

;; ── Search advance scratch ──
;;
;; The 3 former globals (`--search-advance-done', `--advance-search-last-pos',
;; `--advance-search-edge-seen') now live as fields on the
;; `helixel-replay' context, so they reset automatically per `.' /
;; `,' session.  See `helixel-search-advance-*' in `helixel-replay.el'.

(defvar-local helixel--repeat-has-preview nil
  "Set to t by `helixel-repeat-selection', consumed by `helixel-repeat-edit'.
When t, `helixel-repeat-edit' uses the active region directly
instead of recreating the selection, so the preview is honoured.

Cleared automatically by `helixel--repeat-preview-stale-clear' on the
next command boundary that is not itself `helixel-repeat-selection'
or `helixel-repeat-edit', so a stale preview never leaks past one
command pair.")

(defun helixel--repeat-preview-stale-clear ()
  "Clear stale `helixel--repeat-has-preview' after non-repeat commands.
Runs in `post-command-hook'.  The flag is set by `,'
\(`helixel-repeat-selection') and is meant to survive ONLY until the
immediately-following `.' (`helixel-repeat-edit') consumes it.  If any
other command runs in between, the cached preview position is no
longer meaningful — clear the flag so the next `.' does a normal
recreate."
  (when (and helixel--repeat-has-preview
             (not (memq this-command
                        '(helixel-repeat-selection
                          helixel-repeat-edit))))
    (setq helixel--repeat-has-preview nil)))

(add-hook 'post-command-hook #'helixel--repeat-preview-stale-clear)



(defun helixel--repeat-flip-tx-dir ()
  "Toggle `helixel--repeat-permanent-flip' for line/search selections.
Like \=`N\=` for search, \=`-.\=` permanently reverses dot-repeat direction.
No-op for movement, textobj, or nil selections.
Returns t on success, nil otherwise."
  (when-let* ((tx helixel--last-edit)
              (sel (helixel-edit-sel tx))
              (kind (helixel-sel-kind sel)))
    (when (memq kind '(line search))
      (setq helixel--repeat-permanent-flip
            (not helixel--repeat-permanent-flip))
      t)))

;; ── Common repeat setup ──

(defun helixel--repeat-setup (raw-prefix)
  "Common setup for `helixel-repeat-edit' and `helixel-repeat-selection'.
Takes RAW-PREFIX (the raw prefix argument from `interactive').
Gets the last edit transaction (falling back to the event ring if
`helixel--last-edit' is not an edit), parses the prefix argument,
handles permanent direction flip, and resets search-advance state.

Returns (TX PREFIX SAVED-STATE) where:
  TX           — resolved edit `helixel-edit'
  PREFIX       — `helixel-repeat-prefix' struct
  SAVED-STATE  — previous `helixel--current-state'

Signals `user-error' when no edit is available."
  (let ((tx helixel--last-edit))
    (unless tx
      (user-error "No previous edit"))
    ;; Fall back to most recent edit in ring if last-event is
    ;; not an edit (e.g. movement event from event-commit).
    (unless (helixel-edit-op tx)
      (setq tx (cl-loop for e in helixel--event-ring
                        when (helixel-edit-op e)
                        return e))
      (unless tx
        (user-error "No previous edit")))

    (let* ((saved-state helixel--current-state)
           (flip-dir-p (or (eq raw-prefix '-)
                           (and (integerp raw-prefix)
                                (< raw-prefix 0))))
           (prefix (helixel--decode-repeat-prefix raw-prefix)))
      (when flip-dir-p (helixel--repeat-flip-tx-dir))
      ;; Search-advance scratch lives on the replay ctx, no reset needed
      ;; — each `.' / `,' creates a fresh `helixel-replay' binding.
      (list tx prefix saved-state))))

;; ── Interactive entry points ──

(defvar helixel-repeat-edit-function nil
  "Override hook for `helixel-repeat-edit'.
When non-nil, called with RAW-PREFIX before the default implementation.
A non-nil return value means the override handled the call and the
default implementation is skipped; a nil return value means fall through
to the default.

Used by `helixel-mc-integrate' to collapse `.' to apply-once-at-point
under multi-cursor mode without `advice-add'.  See
`helixel-mc-integrate.el' for details.")

(defun helixel-repeat-edit (&optional raw-prefix)
  "Repeat the last editing operation at point (bound to `.`).

RAW-PREFIX is the raw prefix argument.  Delegates to
`helixel-repeat-edit-function' first; falls back to
`helixel--repeat-edit-default' if that hook is unset or returns nil."
  (interactive "P")
  (unless (and helixel-repeat-edit-function
               (funcall helixel-repeat-edit-function raw-prefix))
    (helixel--repeat-edit-default raw-prefix)))

(defun helixel--repeat-edit-default (&optional raw-prefix)
  "Default implementation of `.' (`helixel-repeat-edit').

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
  (when (and executing-kbd-macro (not helixel--last-edit))
    (user-error "No previous edit to repeat (kmacro playback)"))
  (cl-destructuring-bind (tx prefix saved-state)
      (helixel--repeat-setup raw-prefix)
    (let* ((use-preview helixel--repeat-has-preview)
           (mode (helixel-repeat-prefix-mode prefix))
           (sel (helixel-edit-sel tx)))
      (setq helixel--repeat-has-preview nil)
      (helixel-with-replay-context
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
        (setq helixel--current-state saved-state))))))

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
    (helixel-with-replay-context
      (unless (helixel-edit-sel tx)
        (user-error (concat "Previous edit has no selection to repeat."
                            "  Use a textobj (e.g. ciw)"
                            " or line/rect selection first")))
      (unwind-protect
          (let* ((reverse-p (helixel-repeat-prefix-reverse-p prefix))
                 (mode (helixel-repeat-prefix-mode prefix))
                 (n (helixel-repeat-prefix-n prefix))
                 (sel (helixel-edit-sel tx)))
            (if (and (eq mode :all-buffer)
                     (eq (helixel-sel-kind sel) 'line))
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
The chosen event's edit data becomes the new `helixel--last-edit'."
  (interactive)
  (let* ((edit-entries
          (cl-loop for event in helixel--event-ring
                   when (helixel-edit-op event)
                   collect event)))
    (unless edit-entries
      (user-error "No past edits to repeat"))
    (let* ((items (cl-loop for e in edit-entries
                           for i from 0
                           collect (cons (format "%3d  %s" i
                                                 (helixel-edit-display-format
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
        ;; helixel-edit-create signature: (op sel-ctx &rest payload-kv)
        ;; so sel-ctx is the second positional arg, then
        ;; remaining payload plist keys are spread via apply.
        (helixel--update-last-event
         (apply #'helixel-edit-create
                (helixel-edit-op event)
                (helixel-edit-sel event)
                :display (helixel-edit-display-format event)
                :runner (helixel-edit-runner event)
                (helixel-edit-payload event)))
        (helixel-repeat-edit)))))

(defun helixel-repeat-debug ()
  "Pretty-print `helixel--last-edit' and edit events in the event ring."
  (interactive)
  (require 'pp)
  (let* ((events (cl-loop for e in helixel--event-ring
                          when (helixel-edit-op e)
                          collect e))
         (buf (get-buffer-create "*helixel-repeat-debug*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (emacs-lisp-mode)
        (insert ";; helixel--last-edit (display: "
                (or (and helixel--last-edit
                         (helixel-edit-format helixel--last-edit))
                    "<none>")
                ")\n")
        (pp helixel--last-edit (current-buffer))
        (insert "\n;; Edit events in event ring ("
                (number-to-string (length events))
                " entries):\n")
        (dolist (ev events)
          (insert (format ";;   %s\n"
                          (helixel-edit-display-format ev))))
        (goto-char (point-min))))
    (display-buffer buf)))


;; ── Kind-specific all-buffer handlers ──
;; These are invoked via the :all-buffer-fn slot in the kind registry.



;; ----------------------------------------------------------------------


(provide 'helixel-repeat)
;;; helixel-repeat.el ends here



