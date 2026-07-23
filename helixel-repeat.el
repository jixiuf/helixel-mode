;;; helixel-repeat.el --- Repeat edit (`.`) system -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

;; Author: jixiuf <https://github.com/jixiuf>
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

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Dot-repeat (\\[helixel-repeat-edit]) infrastructure + insert-mode recording
;; for helixel-mode.
;;
;; Records every editing operation as a *transaction* (see helixel-core.el)
;; into a per-buffer ring; \\[helixel-repeat-edit] replays the head transaction,
;; optionally with
;; a numeric prefix.  `helixel-repeat-edit-pick' chooses an older entry from
;; the ring via completing-read.
;;
;; Architecture:
;;   Selection commands  → set helixel--pending-sel (selection descriptor)
;;   Editing commands    → helixel-record-action → last-action + ring
;;   \\[helixel-repeat-edit]                 → helixel-repeat-edit →
;; sel-recreate + op-runner
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
(require 'helixel-macros) ; helixel-with-action-tracking
(defsubst helixel--repeat-echo (count)
  "Echo COUNT of repeated iterations."
  (unless (zerop count)
    (message "Repeated %d time%s" count (if (> count 1) "s" "")))
  nil)

;; ----------------------------------------------------------------------
;; Shared key-sequence recording utilities
;; ----------------------------------------------------------------------
;;
;; Tiny utility shared by insert-mode recording
;; (`helixel-repeat.el').

(defsubst helixel--keyrec-capture ()
  "Return the current single-command key sequence for hook capture.

A semantic alias for `this-single-command-keys'.  The insert
recorder pushes the return value of this function onto its
accumulator inside `pre-command-hook'."
  (this-single-command-keys))


;; ----------------------------------------------------------------------
;; Insert-mode key + text recording
;; ----------------------------------------------------------------------
;;
;; Records insert-mode user activity for dot-repeat (\\[helixel-repeat-edit])
;; and
;; multi-cursor broadcast.  Each command run during insert mode is
;; captured as ONE of two segment kinds:
;;
;;   (:keys VEC)
;;     The command did NOT modify the buffer (pure motion, no-op, ...).
;;     Replay via `execute-kbd-macro' / `insert-char'.
;;
;;   (:changes ((REL-BEG INS NDEL) ...) :rel-point R)
;;     The command DID modify the buffer.  Each (REL-BEG INS NDEL)
;;     triplet is one after-change event, recorded independently
;;     (Evil-style):
;;       REL-BEG — position relative to pre-command point
;;       INS     — text inserted (from final buffer state)
;;       NDEL    — exact deleted char count (len from
;;                 `after-change-functions')
;;       R       — final point relative to pre-command base.
;;     Replay iterates the triplets: goto base+REL-BEG, delete
;;     NDEL chars, insert INS, then goto base+R.
;;     `post-self-insert-hook' is NOT re-fired — INS already
;;     contains whatever the hook produced live.
;;
;; Public API (consumed by helixel-state, helixel-editing,
;; helixel-repeat):
;;   helixel--insert-begin
;;   helixel--insert-finish    → list of segments (canonical :keys form)
;;   helixel--repeat-get-keys  → normalizes raw vectors into segments
;;   helixel--execute-keys     → accepts segment lists only

(defvar-local helixel--insert-segments nil
  "List of insert-mode segments captured during the current insert session.
Each element is one of:
  (:keys VEC)
  (:changes ((REL-BEG INS NDEL) ...) :rel-point R)
Each (REL-BEG INS NDEL) triplet records one after-change event:
  REL-BEG — position relative to pre-command point
  INS     — inserted text (buffer-substring from final state)
  NDEL    — exact deleted char count (len from `after-change-functions')
  :rel-point R — final point relative to pre-command base.
Pushed in reverse order; finalized (nreverse) by
`helixel--insert-finish'.")

(cl-defstruct (helixel--insert-cmd (:type vector))
  "Per-command insert-mode recording state.
Captured at `pre-command-hook', consumed at `post-command-hook'."
  keys       ; Key vector captured for the current command.
  start-point ; Point (integer) at command start.
  events)     ; List of (BEG END LEN) triples from `after-change-functions'.

(defvar-local helixel--insert-cmd nil
  "`helixel--insert-cmd' struct for the current command.
Nil between commands; bound during `helixel--on-insert-command'.")

;; ── after-change-functions ──

(defun helixel--insert-after-change (beg end len)
  "Push (BEG END LEN) onto the current command's events.
No-op when `helixel--insert-cmd' is nil (e.g. outside insert mode)."
  (when helixel--insert-cmd
    (push (list beg end len) (helixel--insert-cmd-events helixel--insert-cmd))))

;; ── pre / post-command hooks ──

(defun helixel--on-insert-command ()
  "Pre-command-hook: create a fresh `helixel--insert-cmd' struct.
Skips `helixel-insert-exit'."
  (unless (eq this-command 'helixel-insert-exit)
    (setq helixel--insert-cmd
          (make-helixel--insert-cmd
           :keys (helixel--keyrec-capture)
           :start-point (point)
           :events nil))))

(defun helixel--insert-classify-segment ()
  "Return the segment plist for the just-finished command.
Reads events and start-point from `helixel--insert-cmd'.
Returns one of:
  (:keys VEC)
  (:changes ((REL-BEG INS NDEL) ...) :rel-point R)
or nil for an effectively empty change.

Each after-change event is recorded as an independent
\(REL-BEG INS NDEL) triplet (Evil-style, precise):
  REL-BEG = beg - pre-cmd-start  (relative position)
  INS     = buffer-substring(beg, end) at post-command time
  NDEL    = len (exact deleted count from `after-change-functions')
Disjoint changes DON'T corrupt each other — each triplet is
replayed at its own relative position.

Falls back to :keys if any event's span is invalid in the final
buffer (e.g. fully reverted change)."
  (let ((events (helixel--insert-cmd-events helixel--insert-cmd))
        (start (helixel--insert-cmd-start-point helixel--insert-cmd))
        (keys (helixel--insert-cmd-keys helixel--insert-cmd)))
    (if (null events)
        (list :keys keys)
      (let* ((chrono-events (nreverse events))
             (changes
              (cl-loop for (beg end len) in chrono-events
                       for rel = (- beg start)
                       ;; Guard: if the span doesn't exist in the final
                       ;; buffer (fully reverted), fall back to keys.
                       for valid = (and (>= beg (point-min))
                                        (<= end (point-max)))
                       if (not valid) return :invalid
                       collect (list rel
                                     (buffer-substring-no-properties beg end)
                                     len)))
             (rel-point (- (point) start)))
        (if (eq changes :invalid)
            (list :keys keys)
          (let ((net-delta 0))
            ;; Filter out no-op changes (empty insert, zero delete)
            (dolist (ch changes)
              (cl-incf net-delta (- (length (nth 1 ch)) (nth 2 ch))))
            (if (and (zerop net-delta)
                     (cl-every (lambda (c) (string-empty-p (nth 1 c)))
                               changes))
                ;; Pure no-op: replay keys
                (list :keys keys)
              (list :changes changes :rel-point rel-point))))))))

(defun helixel--insert-post-command ()
  "Post-command-hook: build a segment for the just-finished command."
  (when (and helixel--insert-cmd
             (not (eq this-command 'helixel-insert-exit)))
    (let ((seg (helixel--insert-classify-segment)))
      (when seg
        (push seg helixel--insert-segments)))
    (setq helixel--insert-cmd nil)))

;; ── Public lifecycle ──

(defun helixel--insert-begin ()
  "Start insert-mode recording.
Installs pre/post-command hooks + an after-change hook."
  (setq helixel--insert-segments nil
        helixel--insert-cmd       nil)
  (add-hook 'pre-command-hook       #'helixel--on-insert-command nil t)
  (add-hook 'post-command-hook      #'helixel--insert-post-command nil t)
  (add-hook 'after-change-functions #'helixel--insert-after-change nil t))

(defun helixel--insert-finish ()
  "End insert-mode recording.  Returns the finalized segment list."
  (remove-hook 'pre-command-hook       #'helixel--on-insert-command t)
  (remove-hook 'post-command-hook      #'helixel--insert-post-command t)
  (remove-hook 'after-change-functions #'helixel--insert-after-change t)
  (let ((segs (nreverse helixel--insert-segments)))
    (setq helixel--insert-segments nil
          helixel--insert-cmd      nil)
    segs))

;; ── Replay ──

(defsubst helixel--repeat-get-keys (tx)
  "Return the :keys payload from TX as a canonical segment list.
A raw key vector/string (programmatic callers, tests) is normalized
into ((:keys VEC)) here — the single place that tolerates the
degenerate form, so `helixel--execute-keys' only handles segments."
  (let ((keys (helixel-action-payload-get tx :keys)))
    (if (or (vectorp keys) (stringp keys))
        (list (list :keys (if (stringp keys) (vconcat keys) keys)))
      keys)))

(defun helixel--execute-keys (segments)
  "Execute insert-mode replay payload SEGMENTS.

SEGMENTS is the canonical segment list produced by
`helixel--insert-finish' (via `helixel--repeat-get-keys', which
normalizes raw key vectors into this form).  Each element is
\=(:keys VEC) or \=(:changes ((REL-BEG INS NDEL) ...) :rel-point R).

`:changes' replay: for each (REL-BEG INS NDEL), goto base+REL-BEG,
delete NDEL chars, insert INS.  Then goto base+:rel-point.
`post-self-insert-hook' is NOT re-fired.

`:keys' segments replay char-by-char with `post-self-insert-hook'
firing (for `electric-pair-mode')."
  (helixel-with-replay-as 'dot
    (dolist (seg segments)
      (cond
       ((plist-member seg :changes)
        (let* ((changes (plist-get seg :changes))
               (rel-point (or (plist-get seg :rel-point) 0))
               (base (point)))
          (dolist (ch changes)
            (let ((rel-beg (nth 0 ch))
                  (ins     (nth 1 ch))
                  (ndel    (nth 2 ch)))
              (goto-char (+ base rel-beg))
              (when (> ndel 0)
                (delete-char (min ndel (- (point-max) (point)))))
              (when (and (stringp ins) (not (string-empty-p ins)))
                (insert ins))))
          (goto-char (+ base rel-point))))
       ((plist-member seg :keys)
        (helixel--execute-keys-vector (plist-get seg :keys)))))))

(defun helixel--execute-keys-vector (keys)
  "Replay raw key vector KEYS char-by-char.
Printable chars use `insert-char' + `post-self-insert-hook' so
`electric-pair-mode' fires.  Non-printable keys use
`execute-kbd-macro'."
  (when (and keys (> (length keys) 0))
    (dolist (key (append keys nil))
      (if (and (characterp key) (>= key 32) (/= key 127))
          (let ((last-command-event key))
            (insert-char key 1 t)
            (deactivate-mark)
            (run-hooks 'post-self-insert-hook))
        (let ((win (selected-window)))
          (if (and win (not (eq (window-buffer win)
                                (current-buffer))))
              (let ((prev-buf (window-buffer win)))
                (unwind-protect
                    (progn
                      (set-window-buffer win (current-buffer))
                      (execute-kbd-macro (vector key) 1))
                  (set-window-buffer win prev-buf)))
            (execute-kbd-macro (vector key) 1)))))))


;; ----------------------------------------------------------------------
;; Repeat strategy engine
;; ----------------------------------------------------------------------
;;
;; The `helixel-repeat-strategy' struct, the default strategy builder,
;; the dispatcher (`helixel--build-strategy') that delegates to
;; op-registered builders, and the generic advance / apply / preview
;; loops invoked by \\[helixel-repeat-edit] and \\[helixel-repeat-last-motion].
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

;; ── Direction flip ──

(defvar helixel--repeat-permanent-flip nil
  "When non-nil, dot-repeat permanently uses reversed direction.
Toggled by `-.' — resets on each new `helixel-record-action'.")

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
               (new-edit (helixel-action-shallow-copy edit)))
          (setf (helixel-action-sel new-edit) reversed-sel)
          new-edit)
      edit)))

;; ── Unified advance ──
;;
;; Replaces the previous `helixel-repeat-strategy' struct + two
;; strategy-builder functions (default and chain).  The 5-closure
;; struct existed only to bundle three per-edit closures (which all
;; closed over EFFECTIVE-EDIT and ignored their argument) with two
;; raw kind-registry lookups.  Both lookups now happen inline at the
;; loop level, and the per-edit advance is a single function.

(defun helixel--repeat-advance (edit effective)
  "Advance point to next replay target for EDIT.  Return non-nil on success.
EDIT is the original `helixel-action' (used for op classification);
EFFECTIVE is the direction-flipped tx whose sel drives the actual
recreate.

Dispatch:
  - chain op with no kind-advance → in-place repeat (always t).
  - op moves point itself (kill, change …) or kind has no advance
    → just recreate selection at point; nil if recreate errors.
  - otherwise → delegate to the kind's :advance fn."
  (let* ((op (helixel-action-op edit))
         (sel (helixel-action-sel edit))
         (kind (and sel (helixel-sel-kind sel)))
         (advance-fn (and kind (helixel--kind-advance kind))))
    (cond
     ;; Chain edits may have no kind advance (e.g. after J / join-lines
     ;; with no selection); allow in-place repeat.
     ((and (eq op 'chain) (null advance-fn)) t)
     ;; Treesit advance handles its own positioning even for
     ;; self-advancing ops (e.g. kill, change); skipping it
     ;; would cause dot-repeat to re-select the same node
     ;; instead of advancing to the next one.
     ((and advance-fn (eq kind 'treesit))
      (funcall advance-fn effective))
     ;; Op handles its own positioning, or kind has no advance: just recreate.
     ((or (not advance-fn) (helixel--op-self-advancing-p op))
      (helixel--with-debug-log repeat-advance-recreate
        (progn (helixel-sel-call-recreate (helixel-action-sel effective))
               t)
        (error nil)))
     (t (funcall advance-fn effective)))))

;; ── Generic repeat loops ──

(defun helixel--repeat-all-buffer (edit prefix reverse-p)
  "Repeat EDIT across the entire buffer with REVERSE-P direction.
If the kind has a custom `:all-buffer-fn', delegate to it.
Otherwise reset to recorded start and advance+apply from point-min
\(or point-max if PREFIX is reverse)."
  (let* ((sel (helixel-action-sel edit))
         (kind (and sel (helixel-sel-kind sel))))
    (if-let* ((custom-fn (helixel--kind-all-buffer-fn kind)))
        (funcall custom-fn edit prefix)
      (let ((effective (helixel--maybe-flip-dir-action edit reverse-p)))
        (when-let* ((m (car (helixel-action-mark-region effective))))
          (goto-char (marker-position m)))
        (save-excursion
          (goto-char (if (helixel-repeat-prefix-reverse-p prefix)
                         (point-max)
                       (point-min)))
          (let ((cnt 0))
            (while (helixel--repeat-advance edit effective)
              (cl-incf cnt)
              (helixel-action-replay effective))
            (helixel--repeat-echo cnt)))))))

(defun helixel--repeat-all-dir (edit reverse-p)
  "Repeat EDIT over all remaining targets from current position.
When REVERSE-P is non-nil, flip the stored direction.
If the kind has a custom `:all-dir-fn', delegate to it."
  (let* ((sel (helixel-action-sel edit))
         (kind (and sel (helixel-sel-kind sel))))
    (if-let* ((custom-fn (helixel--kind-all-dir-fn kind)))
        (funcall custom-fn edit)
      (let ((effective (helixel--maybe-flip-dir-action edit reverse-p))
            (cnt 0))
        (while (helixel--repeat-advance edit effective)
          (cl-incf cnt)
          (helixel-action-replay effective))
        (helixel--repeat-echo cnt)))))

(defun helixel--repeat-n (edit n reverse-p)
  "Repeat EDIT N times from current position with REVERSE-P direction.
When N=1 and `helixel--pending-sel' holds a selection of a DIFFERENT
kind than the action's stored sel (e.g. user searched with / after a
word-change), apply the edit directly without advancing — the user's
explicit positioning takes priority.

When the pending-sel has the SAME kind as the action's sel (typical
of an advance leftover from a previous \\[helixel-repeat-edit]),
advance normally.  `helixel--pending-sel' is NOT modified — the
advance function relies on it internally for follow-up detection."
  (let ((effective (helixel--maybe-flip-dir-action edit reverse-p)))
    (if (and (= n 1)
             helixel--pending-sel
             (let ((action-kind (when-let* ((s (helixel-action-sel edit)))
                                  (helixel-sel-kind s))))
               (or (not action-kind)
                   (not (eq (helixel-sel-kind helixel--pending-sel)
                            action-kind)))))
        ;; Direct apply: user explicitly selected a different kind
        ;; (e.g. / search after a word-change).
        (helixel-action-replay effective)
      ;; Normal: advance then apply.
      (dotimes (_ n)
        (unless (helixel--repeat-advance edit effective)
          (user-error "No more targets for dot-repeat"))
        (helixel-action-replay effective)))
    (helixel--repeat-echo n)))

(defun helixel--repeat-preview (edit mode n reverse-p)
  "Preview EDIT — advance only, no apply.
MODE is :all-buffer, :all-dir, or :n-times.  N is the repeat count
for :n-times mode.  When REVERSE-P is non-nil for :all-buffer, start
from `point-max' instead of `point-min'."
  (let ((effective (helixel--maybe-flip-dir-action edit reverse-p)))
    (pcase mode
      (:all-buffer
       (when-let* ((m (car (helixel-action-mark-region effective))))
         (goto-char (marker-position m)))
       (goto-char (if reverse-p (point-max) (point-min)))
       (let ((cnt 0))
         (while (helixel--repeat-advance edit effective)
           (cl-incf cnt))
         (helixel--repeat-echo cnt)))
      (:all-dir
       (let ((cnt 0))
         (while (helixel--repeat-advance edit effective)
           (cl-incf cnt))
         (helixel--repeat-echo cnt)))
      (:n-times
       (dotimes (_ n)
         (unless (helixel--repeat-advance edit effective)
           (user-error "No more targets for dot-repeat")))
       (helixel--repeat-echo n)))))


;; ── State variables ──
(defvar helixel--current-state)

;; ---------------------------------------------------------------------------
;; Selection Context
;;
;; `helixel--pending-sel' and `helixel--sel-push'/`helixel--sel-pop'
;; are defined in `helixel-core.el'.  Selection commands push; editing
;; commands pop.

;; Edit transactions are stored in the unified event ring
;; (`helixel--action-ring') as `:edit' entries.  No separate edit ring.
;; `helixel-repeat-edit-pick' filters the event ring for entries
;; that carry `:edit' data.


(defvar-local helixel--change-track-marker nil
  "Marker at position before entering insert during a change/insert operation.
Set by change and insert-entry commands.  Read in `helixel-insert-exit'
to extract :change-text.")



;; ---------------------------------------------------------------------------
;; Recording (called by editing commands in helixel-editing)

;; ── Record & replay entries ──
(defun helixel-record-action (operator &rest extra)
  "Record edit OPERATOR with current selection context and EXTRA payload.
Pops `helixel--pending-sel' via `helixel--sel-pop' (consumes the
pending selection).  Looks up the runner and display from the operator
registry and stores them in the transaction so `helixel-action-replay'
can dispatch without registry lookups.
Builds a transaction via `helixel-action-create', pushes it onto
the event ring, and stores the most recent edit in `helixel-last-action'.
Also notifies the event ring so \\[helixel-action-cycle]
jumping picks up the new edit.

NOTE: Caller is responsible for calling `helixel--tracking-open' first.
The `helixel-define-command' macro handles this automatically."
  (unless (or (helixel-replaying-p) executing-kbd-macro
              defining-kbd-macro)
    (let* ((pop-sel helixel--pending-sel) ; read but don't pop: clear-data does
           (runner (helixel--op-runner operator))
           ;; helixel--live-action-set already preserves the existing
           ;; preposition from a prior `:preposition' clause (mc prepos).
           ;; No explicit inheritence needed.
           (tx (helixel-action-create operator pop-sel extra
                                      :runner runner)))
      (let ((new-action (helixel-action-shallow-copy tx)))
        ;; Pre-compute and stash display on the live action (tx-replay
        ;; itself doesn't need display, but the action ring formatter does).
        (when helixel--live-action
          (setf (helixel-action-display helixel--live-action)
                (helixel--op-display operator tx)))
        (setq tx new-action))
      (setq helixel--repeat-permanent-flip nil)
      (helixel--live-action-set tx)
      ;; Always set last-action so callers that skip `tracking-open'
      ;; (tests, programmatic use) still have a valid edit to replay.
      (setq helixel-last-action tx)
      (helixel--action-commit))))


;; ---------------------------------------------------------------------------
;; Auto-advance — per-selection-kind advance for `.` replay.
;; Registered in the kind registry via `helixel-register-kind'.
;; Each advance fn receives (TX) → boolean.

;; ── Flip-dir, all-buffer, line-pass ──

(defun helixel--repeat-line-pass (tx sel self-advancing start-pos dir cnt
                                     &optional preview-p)
  "Process one line per step from START-POS in direction DIR.
TX is the edit transaction, SEL the selection descriptor.
SELF-ADVANCING is the operator's `:self-advancing' property
\(nil when the op leaves point alone, t when it handles its
own positioning).  CNT is the starting count.
If PREVIEW-P is non-nil, only recreate selections without executing edits.

SELF-ADVANCING chooses the stepping algorithm:
  nil → simple `forward-line' (op left point alone, e.g. insert,
        surround, indent).
  t   → bol/eol check before `forward-line' (op may have eaten
        the line, e.g. kill, change)."
  (save-excursion
    (goto-char start-pos)
    (forward-line dir)
    (let ((at-edge (lambda () (if (eq dir -1) (bobp) (eobp))))
          (done nil))
      (while (not (or done (funcall at-edge)))
        (setq cnt (1+ cnt))
        (deactivate-mark)
        (helixel--recreate-selection sel)
        (unless preview-p
          (helixel-action-replay tx))
        ;; Step to next line.  Two algorithms:
        ;;   self-advancing nil → simple `forward-line'
        ;;   self-advancing t   → skip the step if the op already
        ;;                        left point at line edge (it ate
        ;;                        the current line)
        (cond
         ((not self-advancing)
          (when (/= (forward-line dir) 0)
            (setq done t)))
         (t
          (unless (if (eq dir -1) (eolp) (bolp))
            (forward-line dir)))))))
  cnt)

(defun helixel--repeat-line-preview (tx sel reverse-p)
  "Preview all-buffer line repeat for `helixel-repeat-selection'.
Uses TX, SEL, REVERSE-P and `helixel--repeat-line-pass'
for correct per-line stepping.  Preview always uses the
\"op left point alone\" stepping algorithm (the operator does not
run in preview mode, so its `:self-advancing' is moot)."
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
         (self-advancing (helixel--op-self-advancing-p op))
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
              (helixel-action-replay edit)))
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
                   edit sel self-advancing
                   start-pos first-dir cnt))
        (setq cnt (helixel--repeat-line-pass
                   edit sel self-advancing
                   start-pos (- first-dir) cnt))
        (helixel--repeat-echo cnt)))))

(defun helixel--all-dir-line (edit)
  "All-dir repeat handler for line selections, for EDIT.
Uses `helixel--repeat-line-pass' for proper cursor advance."
  (let* ((sel (helixel-action-sel edit))
         (op (helixel-action-op edit))
         (dir (if (eq (helixel-sel-line-dir sel) 'backward) -1 1))
         ;; In all-dir line replay, even ops that ordinarily handle
         ;; their own positioning (kill, change) want the simple
         ;; line-stepping algorithm here, because the kill/change
         ;; already happened once before we entered the loop.
         (self-advancing (helixel--op-self-advancing-p op))
         (cnt 0))
    (setq cnt (helixel--repeat-line-pass
               edit sel self-advancing (point) dir cnt))
    (helixel--repeat-echo cnt)))

;; ── Search advance scratch ──
;;
;; The 3 former globals (`--search-advance-done', `--advance-search-last-pos',
;; `--advance-search-edge-seen') now live as fields on the
;; `helixel-replay' context, so they reset automatically per
;; \\[helixel-repeat-edit] /
;; \\[helixel-repeat-last-motion] session.  See `helixel-search-advance-*' in
;; `helixel-replay.el'.

(defvar-local helixel--repeat-preview-pos nil
  "Marker for the \\[helixel-repeat-selection] preview position.
Consumed by \\[helixel-repeat-edit].
Set by \\[helixel-repeat-selection] at the preview position;
consumed by \\[helixel-repeat-edit] when point is still there.
A marker auto-invalidates the moment the user moves point
\(the equality check in \\[helixel-repeat-edit] fails),
so no global hook is needed.")


(defun helixel--repeat-flip-action-dir ()
  "Toggle `helixel--repeat-permanent-flip' for the last edit.
Like \\=`N\\=` for search,
\\[negative-argument] \\[helixel-repeat-edit]
permanently reverses dot-repeat direction.
Works for any kind that has a `:flip-dir-fn' registered
\(line, search, etc.).
No-op for kinds without directional state
\(movement, textobj, rect).
Returns t on success, nil otherwise."
  (when-let* ((tx helixel-last-action)
              (sel (helixel-action-sel tx))
              (kind (helixel-sel-kind sel))
              ((helixel--kind-flip-dir-fn kind)))
    (setq helixel--repeat-permanent-flip
          (not helixel--repeat-permanent-flip))
    t))

;; ── Common repeat setup ──

(defun helixel--repeat-setup (raw-prefix)
  "Common setup for `helixel-repeat-edit' and `helixel-repeat-selection'.
Takes RAW-PREFIX \(the raw prefix argument from `interactive').
Gets the last edit transaction (falling back to the event ring
if `helixel-last-action' is not an edit), parses the prefix
argument, handles permanent direction flip, and resets
search-advance state.

Returns (TX PREFIX SAVED-STATE) where:
  TX           — resolved edit `helixel-action'
  PREFIX       — `helixel-repeat-prefix' struct
  SAVED-STATE  — previous `helixel--current-state'

Signals `user-error' when no edit is available."
  (let ((tx helixel-last-action))
    (unless tx
      (user-error "No previous edit"))
    ;; Fall back to most recent edit in ring if last-event is
    ;; not an edit (e.g. movement event from event-commit).
    (unless (helixel-action-op tx)
      (setq tx (cl-loop for e in helixel--action-ring
                        when (helixel-action-op e)
                        return e))
      (unless tx
        (user-error "No previous edit")))

    (let* ((saved-state helixel--current-state)
           (flip-dir-p (or (eq raw-prefix '-)
                           (and (integerp raw-prefix)
                                (< raw-prefix 0))))
           (prefix (helixel--decode-repeat-prefix raw-prefix)))
      (when flip-dir-p (helixel--repeat-flip-action-dir))
      ;; Search-advance scratch lives on the replay ctx, no reset needed
      ;; — each \\[helixel-repeat-edit] / \\[helixel-repeat-last-motion]
      ;; creates a fresh `helixel-replay' binding.
      (list tx prefix saved-state))))

;; ── Interactive entry points ──

(defvar helixel-repeat-edit-override-functions nil
  "Abnormal hook run before `helixel-repeat-edit''s default logic.
Each function receives RAW-PREFIX and should return non-nil if it
handled the dot-repeat; nil delegates to the default implementation.
Uses `run-hook-with-args-until-success'.

Set by mc-integrate to override \\[helixel-repeat-edit]
when fake cursors exist, so \\[helixel-repeat-edit]
applies the last edit once at each cursor's current position without
advancing.")

(defun helixel-repeat-edit (&optional raw-prefix)
  "Repeat the last editing operation at point (bound to `.`).

RAW-PREFIX is the raw prefix argument.  Delegates to
`helixel-repeat-edit-override-functions' first; falls back to
`helixel--repeat-edit-default' if that hook is unset or returns nil."
  (interactive "P")
  (unless (run-hook-with-args-until-success
           'helixel-repeat-edit-override-functions raw-prefix)
    (helixel--repeat-edit-default raw-prefix)))

(defun helixel--repeat-edit-default (&optional raw-prefix)
  "Default implementation of \\[helixel-repeat-edit] (`helixel-repeat-edit').

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
  (when (and executing-kbd-macro (not helixel-last-action))
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
                 (let ((reverse-p (helixel-repeat-prefix-reverse-p prefix)))
                   (pcase mode
                     (:all-buffer
                      (if sel
                          (helixel--repeat-all-buffer tx prefix reverse-p)
                        (helixel-action-replay tx)))
                     (:all-dir
                      (if sel
                          (helixel--repeat-all-dir tx reverse-p)
                        (helixel-action-replay tx)))
                     (:n-times
                      (if use-preview
                          (dotimes (_ (helixel-repeat-prefix-n prefix))
                            (helixel-action-replay tx))
                        (helixel--repeat-n tx
                                           (helixel-repeat-prefix-n prefix)
                                           reverse-p)))
                     (:preview
                      (helixel-action-replay tx)))))
              ((error quit)
               (message "helixel-repeat-edit aborted: %s"
                        (error-message-string err))))
          (setq helixel--current-state saved-state))))))

;; ---------------------------------------------------------------------------
;; Repeat Selection (bound to `M-.`)

(defun helixel-repeat-selection (&optional raw-prefix)
  "Repeat the last selection without applying any edit (bound to `M-.`).
Mirrors the advance behaviour of `.` without executing the operator.

Prefix RAW-PREFIX semantics (same as `.`):
  3,     -> 3 times in stored direction
  -,     -> flip direction permanently (like N for search), preview 1
  0,     -> all remaining targets in stored direction
  \\[universal-argument] - 3 , -> 3 times in opposite direction
  \\[universal-argument] ,    -> all targets in entire buffer

Leaves a marker at the preview position in
`helixel--repeat-preview-pos' so a subsequent \\[helixel-repeat-edit] that fires
without the user moving point in between will replay at that
position.  Any other command moves point off the marker and
automatically invalidates the preview."
  (interactive "P")
  (cl-destructuring-bind (tx prefix saved-state)
      (helixel--repeat-setup raw-prefix)
    (helixel-with-replay-as 'dot
      (unless (or (helixel-action-sel tx)
                  (eq (helixel-action-op tx) 'chain))
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
              ;; Generic: unified advance/preview
              (helixel--repeat-preview tx mode n reverse-p)))
        (setq helixel--current-state saved-state))
      ;; Stash preview position for the next \\[helixel-repeat-edit] (positional
      ;; handoff).
      (when helixel--repeat-preview-pos
        (set-marker helixel--repeat-preview-pos nil))
      (setq helixel--repeat-preview-pos (point-marker)))))

;; ── Interactive entry points ──
(defun helixel-repeat-edit-pick ()
  "Choose a past edit from the event ring and replay it.
Scans `helixel--action-ring' for entries with an :op.
The chosen event's edit data becomes the new `helixel-last-action'."
  (interactive)
  (let* ((edit-entries
          (cl-loop for event in helixel--action-ring
                   when (helixel-action-op event)
                   collect event)))
    (unless edit-entries
      (user-error "No past edits to repeat"))
    (let* ((items (cl-loop for e in edit-entries
                           for i from 0
                           collect (cons (format "%3d  %s" i
                                                 (helixel--action-display-format
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
        ;; Reconstruct tx from event and set it as `helixel-last-action'.
        ;; Must use `helixel-action-shallow-copy'
        ;; (not `helixel--update-last-action'
        ;; which only copies the payload, leaving op/sel/runner stale).
        (setq helixel-last-action
              (helixel-action-shallow-copy
               (helixel-action-create
                (helixel-action-op event)
                (helixel-action-sel event)
                (helixel-action-payload event)
                :display (helixel--action-display-format event)
                :runner (helixel-action-runner event))))
        (helixel-repeat-edit)))))

(defun helixel-repeat-debug ()
  "Pretty-print `helixel-last-action' and edit events in the event ring."
  (interactive)
  (require 'pp)
  (let* ((events (cl-loop for e in helixel--action-ring
                          when (helixel-action-op e)
                          collect e))
         (buf (get-buffer-create "*helixel-repeat-debug*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (emacs-lisp-mode)
        (insert ";; helixel-last-action (display: "
                (or (and helixel-last-action
                         (helixel-action-format helixel-last-action))
                    "<none>")
                ")\n")
        (pp helixel-last-action (current-buffer))
        (insert "\n;; Edit events in event ring ("
                (number-to-string (length events))
                " entries):\n")
        (dolist (ev events)
          (insert (format ";;   %s\n"
                          (helixel--action-display-format ev))))
        (goto-char (point-min))))
    (display-buffer buf)))


;; ── Kind-specific all-buffer handlers ──
;; These are invoked via the :all-buffer-fn slot in the kind registry.



;; ----------------------------------------------------------------------


;; ----------------------------------------------------------------------
;; Chain recording & compound dot-repeat
;; ----------------------------------------------------------------------
;;
;; Compound dot-repeat: \[helixel-repeat-chain-start] starts a chain,
;; \[helixel-normal-escape] ends it, \[keyboard-quit] cancels.
;; Chain recording captures the LIST of helixel-action values
;; produced by the commands run during the chain (via
;; `helixel-action-commit-hook').  Replay iterates the list and
;; `helixel-action-replay's each entry in chronological order.

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
Excludes self-insert, insert-mode commands, helixel commands
\(identified by the `helixel-command' symbol property), and
chain-control commands."
  (or (eq cmd 'self-insert-command)
      (eq helixel--current-state 'insert)
      (get cmd 'helixel-command)
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
                   (helixel-sel-entry-kind edit-sel)))
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
                       :keys (helixel--with-debug-log chain-vanilla-keys
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

Flushes any deferred live action (e.g. from `x' before
\\[helixel-repeat-chain-start]) so that pre-chain commands
don't leak into the action-list."
  (interactive)
  (when (or (helixel--chain-active-p) executing-kbd-macro)
    (user-error "Already chaining or macro replay in progress"))
  ;; Flush any deferred live action (e.g. from `x' before
  ;; \\[helixel-repeat-chain-start])
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
      (let ((tx (helixel-action-create
                 'chain init-ctx
                 (list :action-list action-list)
                 :runner #'helixel--repeat-chain-runner
                 :display (format "chain(%d)" (length action-list)))))
        (setq helixel-last-action (helixel-action-shallow-copy tx))
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

(provide 'helixel-repeat)
;;; helixel-repeat.el ends here
