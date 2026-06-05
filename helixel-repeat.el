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
;;   Editing commands    → helixel--record-action → helixel--last-action + ring
;;   `.'                 → helixel-repeat-edit → sel-recreate + op-runner
;;
;; Both selection recreation and op execution use the `helixel-sel' struct
;; registry lookups in helixel-core.el.
;; This module knows nothing about specific kinds or operators.
;;
;; Depends on helixel-action and helixel-core.

;;; Code:

(require 'cl-lib)
(require 'helixel-core)
(require 'helixel-ring)
(require 'helixel-insert-record)

;; ----------------------------------------------------------------------
;; Repeat strategy engine
;; ----------------------------------------------------------------------
;;
;; The `helixel-repeat-strategy' struct, the default strategy builder,
;; the dispatcher (`helixel--build-strategy') that delegates to
;; op-registered builders, and the generic advance / apply / preview
;; loops invoked by `.' and `,'.
;;
;; Knows nothing about specific kinds beyond what the kind registry
;; exposes.  Per-kind line / search / textobj behaviour lives in the
;; kind registry slots `:all-buffer-fn', `:all-dir-fn'.

;; ── Repeat prefix decoder ──

(cl-defstruct helixel-repeat-prefix
  "Decoded dot-repeat prefix argument."
  mode      ;; :all-buffer | :all-dir | :n-times
  n         ;; integer count (>= 1)
  reverse-p ;; boolean
  raw)      ;; original raw-prefix

(defun helixel--decode-repeat-prefix (raw-prefix)
  "Parse RAW-PREFIX into a `helixel-repeat-prefix' struct.

Semantics:
  \\[universal-argument] .    \\=→ :all-buffer, forward
  \\[universal-argument] - .  \\=→ :all-buffer, reverse
  0 .           \\=→ :all-dir, forward
  - .           \\=→ :n-times 1 (flips direction)
  -3 .          \\=→ :n-times 3 (flips direction)
  3 .           \\=→ :n-times 3, forward
  \\[universal-argument] -3 . \\=→ :n-times 3, reverse (one-time)
  \\[universal-argument] 3 .  \\=→ :all-buffer (n=3 ignored)

Bare \\='-\\=' (raw-prefix = symbol \\='-) is detected by the caller
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

;; ── Strategy struct ──

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

(defvar helixel--repeat-permanent-flip nil
  "When non-nil, dot-repeat permanently uses reversed direction.
Toggled by `-.' — resets on each new `helixel--record-action'.")

;; ── Direction flip ──

(defun helixel--maybe-flip-dir-action (edit reverse-p)
  "Return EDIT with :dir flipped per the sel kind's :flip-dir-fn.
When REVERSE-P or `helixel--repeat-permanent-flip' is non-nil and
the selection kind has a `:flip-dir-fn' registered, build a copy
of EDIT whose sel has been flipped by that function.  Otherwise
return EDIT unchanged."
  (let* ((sel (helixel-action-sel edit))
         (kind (and sel (helixel-sel-kind sel)))
         (flip-fn (and kind (helixel--kind-flip-dir-fn kind)))
         (effective-reverse (or reverse-p helixel--repeat-permanent-flip)))
    (if (and effective-reverse sel flip-fn)
        (let* ((reversed-sel (funcall flip-fn sel))
               (new-edit (helixel-action-copy edit)))
          (setf (helixel-action-sel new-edit) reversed-sel)
          new-edit)
      edit)))

;; ── Strategy builder dispatcher ──

(defun helixel--build-strategy (edit &optional reverse-p)
  "Return a `helixel-repeat-strategy' for EDIT.
If the operator has a :strategy-builder in the op registry, use it.
Otherwise fall back to `helixel--default-strategy-builder'.
If REVERSE-P is non-nil, flip :dir in the selection ctx
for line/search kinds."
  (let* ((op (helixel-action-op edit))
         (custom-builder (helixel--op-strategy-builder op)))
    (if custom-builder
        (funcall custom-builder edit reverse-p)
      (helixel--default-strategy-builder edit reverse-p))))

;; ── Default builder ──

(defun helixel--default-strategy-builder (edit &optional reverse-p)
  "Build a default repeat strategy for EDIT.
If REVERSE-P is non-nil, flip :dir for line/search kinds.
Looks up the advance function from the kind registry.
When the operator has `:moves-point-p' set (kill, change …),
the advance just recreates the selection at the current position
\(no actual advancing — the op already moved point)."
  (let* ((sel (helixel-action-sel edit))
         (kind (and sel (helixel-sel-kind sel)))
         (op (helixel-action-op edit))
         (op-moves-point (helixel--op-moves-point-p op))
         (effective-edit (helixel--maybe-flip-dir-action edit reverse-p))
         (advance-fn
          (cond
           ;; Op does NOT move point: drive stepping via the kind's
           ;; advance fn.
           ((and (not op-moves-point) (helixel--kind-advance kind))
            (helixel--kind-advance kind))
           ;; Op moves point itself (kill, change): just recreate at
           ;; the new point.  Catches errors = no more targets.
           (t
            (lambda (ed)
              (condition-case nil
                  (progn
                    (helixel-sel-call-recreate
                     (helixel-action-sel ed))
                    t)
                (error nil)))))))
    (make-helixel-repeat-strategy
     :advance (lambda (_ed) (funcall advance-fn effective-edit))
     :apply   (lambda (_ed) (helixel--execute-action effective-edit))
     :reset   (lambda (_ed)
                (when-let* ((m (car (helixel-action-mark-region
                                       effective-edit))))
                  (goto-char (marker-position m))))
     :all-buffer-fn (helixel--kind-all-buffer-fn kind)
     :all-dir-fn (helixel--kind-all-dir-fn kind))))

;; ── Generic repeat loops ──

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


;; ── State variables ──
(defvar helixel--current-state)

;; ---------------------------------------------------------------------------
;; Selection Context
;;
;; `helixel--pending-sel' and `helixel--sel-push'/`helixel--sel-pop'
;; are defined in `helixel-core.el'.  Selection commands push; editing
;; commands pop.

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
(defun helixel--record-action (operator &rest extra)
  "Record edit OPERATOR with current selection context and EXTRA payload.
Pops `helixel--pending-sel' via `helixel--sel-pop' (consumes the
pending selection).  Looks up the runner and display from the operator
registry and stores them in the transaction so `helixel--execute-action'
can dispatch without registry lookups.
Builds a transaction via `helixel-action-create', pushes it onto
the event ring, and stores the most recent edit in `helixel--last-action'.
Also notifies the event ring so `;' jumping picks up the new edit.

NOTE: Caller is responsible for calling `helixel--tracking-open' first.
The `helixel-define-command' macro handles this automatically."
  (unless (or (helixel-replaying-p) executing-kbd-macro
              defining-kbd-macro)
    (let* ((pop-sel (helixel--sel-pop))
           (runner (helixel--op-runner operator))
           (tx (apply #'helixel-action-create operator
                      pop-sel
                      :runner runner
                      extra)))
      (let ((new-tx (helixel-action-copy tx)))
        (setf (helixel-action-display new-tx)
              (helixel--op-display operator tx))
        (setq tx new-tx))
      (setq helixel--repeat-permanent-flip nil)
      (helixel--live-action-set tx)
      ;; Always set last-event so callers that skip tracking-open
      ;; (tests, programmatic use) still have a valid edit to replay.
      ;; `helixel-action-commit' may be a no-op when live-event is nil.
      (setq helixel--last-action tx)
      (helixel-action-commit))))


;; ---------------------------------------------------------------------------
;; Auto-advance — per-selection-kind advance for `.` replay.
;; Registered in the kind registry via `helixel-register-kind'.
;; Each advance fn receives (TX) → boolean.

;; ── Flip-dir, all-buffer, line-pass ──

(defun helixel--repeat-line-pass (tx sel op-moves-point start-pos dir cnt
                                     &optional preview-p)
  "Process one line per step from START-POS in direction DIR.
TX is the edit transaction, SEL the selection descriptor.
OP-MOVES-POINT is the operator's `:moves-point-p' property
\(nil when the op keeps point in place, t when it advances on
its own).  CNT is the starting count.
If PREVIEW-P is non-nil, only recreate selections without executing edits.

OP-MOVES-POINT chooses the stepping algorithm:
  nil → simple `forward-line' (op left point alone, e.g. insert,
        surround, indent).
  t   → bol/eol check before `forward-line' (op may have eaten
        the line, e.g. kill, change)."
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
            (helixel--execute-action tx))
          (if (not op-moves-point)
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
for correct per-line stepping.  Preview always uses the
\"op left point alone\" stepping algorithm (the operator does not
run in preview mode, so its `:moves-point-p' is moot)."
  (let* ((dir (if reverse-p -1 1))
         (start (if (> dir 0) (point-min) (point-max)))
         (cnt 0))
    (save-excursion
      (goto-char start)
      (setq cnt (helixel--repeat-line-pass
                 tx sel nil start dir cnt t)))
    (helixel--repeat-echo cnt)))

;; ── All-buffer / all-dir line handlers ──
;; Registered via the kind registry in helixel-move.el.

(defun helixel--all-buffer-line (edit prefix)
  "All-buffer repeat handler for line selections, for EDIT and PREFIX.
Forward pass then backward pass from the marker position.
For chain ops, does a single pass from the buffer edge."
  (let* ((sel (helixel-action-sel edit))
         (op (helixel-action-op edit))
         (op-moves-point (helixel--op-moves-point-p op))
         (reverse-p (helixel-repeat-prefix-reverse-p prefix))
         (marker (car (helixel-action-mark-region edit)))
         (chain-p (eq op 'chain)))
    (if chain-p
        (let* ((dir (if reverse-p -1
                     (if (eq (helixel-sel-line-dir sel) 'backward) -1 1)))
               (start (if (> dir 0) (point-min) (point-max)))
               (cnt 0))
          (save-excursion
            (goto-char start)
            (unless (helixel--blank-line-p)
              (helixel--execute-action edit)))
          ;; Chain ops use line-stepping algorithm regardless.
          (setq cnt (helixel--repeat-line-pass
                     edit sel nil
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
                   edit sel op-moves-point
                   start-pos first-dir cnt))
        (setq cnt (helixel--repeat-line-pass
                   edit sel op-moves-point
                   start-pos (- first-dir) cnt))
        (helixel--repeat-echo cnt)))))

(defun helixel--all-dir-line (edit)
  "All-dir repeat handler for line selections, for EDIT.
Uses `helixel--repeat-line-pass' for proper cursor advance."
  (let* ((sel (helixel-action-sel edit))
         (op (helixel-action-op edit))
         (dir (if (eq (helixel-sel-line-dir sel) 'backward) -1 1))
         ;; In all-dir line replay, even ops that ordinarily move
         ;; point on their own (kill, change) want the simple
         ;; line-stepping algorithm here, because the kill/change
         ;; already happened once before we entered the loop.
         (op-moves-point (helixel--op-moves-point-p op))
         (cnt 0))
    (setq cnt (helixel--repeat-line-pass
               edit sel op-moves-point (point) dir cnt))
    (helixel--repeat-echo cnt)))

;; ── Search advance scratch ──
;;
;; The 3 former globals (`--search-advance-done', `--advance-search-last-pos',
;; `--advance-search-edge-seen') now live as fields on the
;; `helixel-replay' context, so they reset automatically per `.' /
;; `,' session.  See `helixel-search-advance-*' in `helixel-replay.el'.

(defvar-local helixel--repeat-preview-pos nil
  "Marker set by `,' (`helixel-repeat-selection') at the preview
position, consumed by `.' (`helixel-repeat-edit') when point is
still there.

Positional handoff replaces the old boolean flag +
`post-command-hook' stale-clear: a marker auto-invalidates the
moment the user moves point (the equality check in
`.' fails), so no global hook is needed.")



(defun helixel--repeat-flip-tx-dir ()
  "Toggle `helixel--repeat-permanent-flip' for line/search selections.
Like \=`N\=` for search, \=`-.\=` permanently reverses dot-repeat direction.
No-op for movement, textobj, or nil selections.
Returns t on success, nil otherwise."
  (when-let* ((tx helixel--last-action)
              (sel (helixel-action-sel tx))
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
`helixel--last-action' is not an edit), parses the prefix argument,
handles permanent direction flip, and resets search-advance state.

Returns (TX PREFIX SAVED-STATE) where:
  TX           — resolved edit `helixel-action'
  PREFIX       — `helixel-repeat-prefix' struct
  SAVED-STATE  — previous `helixel--current-state'

Signals `user-error' when no edit is available."
  (let ((tx helixel--last-action))
    (unless tx
      (user-error "No previous edit"))
    ;; Fall back to most recent edit in ring if last-event is
    ;; not an edit (e.g. movement event from event-commit).
    (unless (helixel-action-op tx)
      (setq tx (cl-loop for e in helixel--event-ring
                        when (helixel-action-op e)
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
  (when (and executing-kbd-macro (not helixel--last-action))
    (user-error "No previous edit to repeat (kmacro playback)"))
  (cl-destructuring-bind (tx prefix saved-state)
      (helixel--repeat-setup raw-prefix)
    (let* ((use-preview
            (and helixel--repeat-preview-pos
                 (= (point)
                    (marker-position helixel--repeat-preview-pos))))
           (mode (helixel-repeat-prefix-mode prefix))
           (sel (helixel-action-sel tx)))
      (when helixel--repeat-preview-pos
        (set-marker helixel--repeat-preview-pos nil)
        (setq helixel--repeat-preview-pos nil))
      (helixel-with-replay-as 'dot
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
                       (helixel--execute-action tx)))
                    (:all-dir
                     (if sel
                         (helixel--repeat-all-dir strategy tx)
                       (helixel--execute-action tx)))
                    (:n-times
                     (if use-preview
                         (dotimes (_ (helixel-repeat-prefix-n prefix))
                           (helixel--execute-action tx))
                       (helixel--repeat-n strategy tx
                                          (helixel-repeat-prefix-n prefix))))
                    (:preview
                     (helixel--execute-action tx)))))
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

Leaves a marker at the preview position in
`helixel--repeat-preview-pos' so a subsequent `.' that fires
without the user moving point in between will replay at that
position.  Any other command moves point off the marker and
automatically invalidates the preview."
  (interactive "P")
  (cl-destructuring-bind (tx prefix saved-state)
      (helixel--repeat-setup raw-prefix)
    (helixel-with-replay-as 'dot
      (unless (helixel-action-sel tx)
        (user-error (concat "Previous edit has no selection to repeat."
                            "  Use a textobj (e.g. ciw)"
                            " or line/rect selection first")))
      (unwind-protect
          (let* ((reverse-p (helixel-repeat-prefix-reverse-p prefix))
                 (mode (helixel-repeat-prefix-mode prefix))
                 (n (helixel-repeat-prefix-n prefix))
                 (sel (helixel-action-sel tx)))
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
      ;; Stash preview position for the next `.' (positional handoff).
      (when helixel--repeat-preview-pos
        (set-marker helixel--repeat-preview-pos nil))
      (setq helixel--repeat-preview-pos (point-marker)))))

;; ── Interactive entry points ──
(defun helixel-repeat-edit-pick ()
  "Choose a past edit from the event ring and replay it.
Scans `helixel--event-ring' for entries with an :op.
The chosen event's edit data becomes the new `helixel--last-action'."
  (interactive)
  (let* ((edit-entries
          (cl-loop for event in helixel--event-ring
                   when (helixel-action-op event)
                   collect event)))
    (unless edit-entries
      (user-error "No past edits to repeat"))
    (let* ((items (cl-loop for e in edit-entries
                           for i from 0
                           collect (cons (format "%3d  %s" i
                                                 (helixel-action-display-format
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
        ;; helixel-action-create signature: (op sel-ctx &rest payload-kv)
        ;; so sel-ctx is the second positional arg, then
        ;; remaining payload plist keys are spread via apply.
        (helixel--update-last-event
         (apply #'helixel-action-create
                (helixel-action-op event)
                (helixel-action-sel event)
                :display (helixel-action-display-format event)
                :runner (helixel-action-runner event)
                (helixel-action-payload event)))
        (helixel-repeat-edit)))))

(defun helixel-repeat-debug ()
  "Pretty-print `helixel--last-action' and edit events in the event ring."
  (interactive)
  (require 'pp)
  (let* ((events (cl-loop for e in helixel--event-ring
                          when (helixel-action-op e)
                          collect e))
         (buf (get-buffer-create "*helixel-repeat-debug*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (emacs-lisp-mode)
        (insert ";; helixel--last-action (display: "
                (or (and helixel--last-action
                         (helixel-action-format helixel--last-action))
                    "<none>")
                ")\n")
        (pp helixel--last-action (current-buffer))
        (insert "\n;; Edit events in event ring ("
                (number-to-string (length events))
                " entries):\n")
        (dolist (ev events)
          (insert (format ";;   %s\n"
                          (helixel-action-display-format ev))))
        (goto-char (point-min))))
    (display-buffer buf)))


;; ── Kind-specific all-buffer handlers ──
;; These are invoked via the :all-buffer-fn slot in the kind registry.



;; ----------------------------------------------------------------------


(provide 'helixel-repeat)
;;; helixel-repeat.el ends here



