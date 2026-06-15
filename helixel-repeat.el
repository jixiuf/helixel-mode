;;; helixel-repeat.el --- Repeat edit (`.`) system -*- lexical-binding: t; -*-

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

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Dot-repeat (`.') infrastructure + insert-mode recording for helixel-mode.
;;
;; Records every editing operation as a *transaction* (see helixel-core.el)
;; into a per-buffer ring; `.' replays the head transaction, optionally with
;; a numeric prefix.  `helixel-repeat-edit-pick' chooses an older entry from
;; the ring via completing-read.
;;
;; Architecture:
;;   Selection commands  → set helixel--pending-sel (selection descriptor)
;;   Editing commands    → helixel--record-action → helixel--last-tx + ring
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

;; ----------------------------------------------------------------------
;; Insert-mode key + text recording
;; ----------------------------------------------------------------------
;;
;; Records insert-mode user activity for dot-repeat (`.') and
;; multi-cursor broadcast.  Each command run during insert mode is
;; captured as ONE of two segment kinds:
;;
;;   (:keys VEC)
;;     The command did NOT modify the buffer (pure motion, no-op, ...).
;;     Replay via `execute-kbd-macro' / `insert-char'.
;;
;;   (:text STR :delete-before N :offset O)
;;     The command DID modify the buffer (self-insert, electric-pair
;;     pair insertion, completion-preview accept, snippet expand, ...).
;;     STR is the net inserted substring (the post-state buffer text
;;     within the command's change span).  N is the number of characters
;;     to delete BEFORE the insertion site at replay time.  O is the
;;     offset of point from the END of the insertion at recording time.
;;     Replay = `(delete-char -N)' then `(insert STR)' then
;;     `(goto-char (+ (point) O))'.  `post-self-insert-hook' is NOT
;;     re-fired, because STR already reflects whatever the hook
;;     produced live — re-firing would double-insert pairs.
;;
;; Public API (consumed by helixel-state, helixel-editing,
;; helixel-repeat):
;;   helixel--insert-begin
;;   helixel--insert-finish    → list of segments (replaces key-vec)
;;   helixel--execute-keys     → accepts segment list OR raw key vec
;;   helixel--repeat-get-keys

(defvar-local helixel--insert-segments nil
  "List of insert-mode segments captured during the current insert session.
Each element is one of:
  (:keys VEC)
  (:text STR :delete-before N :offset O)
Pushed in reverse order; finalized (nreverse) by
`helixel--insert-finish'.")

(defvar-local helixel--insert-cmd-keys nil
  "Key vector captured at `pre-command-hook' for the current command.")

(defvar-local helixel--insert-cmd-start-point nil
  "Point (integer) at `pre-command-hook' time of the current command.")

(defvar-local helixel--insert-cmd-events nil
  "List of (BEG END LEN) triples from `after-change-functions'.
Accumulated during the current command; consumed by
`helixel--insert-classify-segment'.")

;; ── after-change-functions ──

(defun helixel--insert-after-change (beg end len)
  "Push (BEG END LEN) onto `helixel--insert-cmd-events'."
  (push (list beg end len) helixel--insert-cmd-events))

;; ── pre / post-command hooks ──

(defun helixel--on-insert-command ()
  "Pre-command-hook: snapshot key + reset per-command change tracking.
Skips `helixel-insert-exit'."
  (unless (eq this-command 'helixel-insert-exit)
    (setq helixel--insert-cmd-keys        (helixel-keyrec-capture)
          helixel--insert-cmd-start-point (point)
          helixel--insert-cmd-events      nil)))

(defun helixel--insert-classify-segment ()
  "Return the segment plist for the just-finished command.
Reads `helixel--insert-cmd-events' along with the pre-command
snapshot of point.  Returns one of:
  (:keys VEC)
  (:text STR :delete-before N :offset O)
or nil for an effectively empty change."
  (let ((events helixel--insert-cmd-events))
    (if (null events)
        ;; No buffer modification: replay the keystroke verbatim.
        (list :keys helixel--insert-cmd-keys)
      (let* ((mn (apply #'min (mapcar #'car  events)))
             (mx (apply #'max (mapcar #'cadr events)))
             (span (- mx mn)))
        (cond
         ;; Span collapsed to empty range — pure deletion or fully
         ;; reverted change.  Safest replay is the keystroke.
         ((<= span 0)
          (list :keys helixel--insert-cmd-keys))
         (t
          (let* ((str   (buffer-substring-no-properties mn mx))
                 (offset (- (point) mx))
                 ;; `delete-before' — chars to remove just-before the
                 ;; insertion site at replay time.  Approximation:
                 ;; how many chars BEFORE the post-state insertion
                 ;; site existed pre-command and were eaten by the
                 ;; replace-style change.
                 (start helixel--insert-cmd-start-point)
                 (delete-before (max 0 (- start mn))))
            (list :text str
                  :delete-before delete-before
                  :offset offset))))))))

(defun helixel--insert-post-command ()
  "Post-command-hook: build a segment for the just-finished command."
  (when (and helixel--insert-cmd-keys
             (not (eq this-command 'helixel-insert-exit)))
    (let ((seg (helixel--insert-classify-segment)))
      (when seg
        (push seg helixel--insert-segments)))
    (setq helixel--insert-cmd-keys        nil
          helixel--insert-cmd-events      nil
          helixel--insert-cmd-start-point nil)))

;; ── Public lifecycle ──

(defun helixel--insert-begin ()
  "Start insert-mode recording.
Installs pre/post-command hooks + an after-change hook."
  (setq helixel--insert-segments         nil
        helixel--insert-cmd-keys         nil
        helixel--insert-cmd-events       nil
        helixel--insert-cmd-start-point  nil)
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
          helixel--insert-cmd-keys nil)
    segs))

;; ── Replay ──

(defsubst helixel--repeat-get-keys (tx)
  "Return the :keys payload from TX (segment list OR legacy key vector)."
  (helixel-action-payload-get tx :keys))

(defun helixel--execute-keys (keys-or-segments)
  "Execute insert-mode replay payload KEYS-OR-SEGMENTS.

Accepted shapes:
  * Segment list: each element is (:keys VEC) or
    (:text STR :delete-before N :offset O).  Produced by
    `helixel--insert-finish'.
  * Raw key vector / string: legacy / hand-built payloads.  Replayed
    char-by-char with `post-self-insert-hook' firing so
    `electric-pair-mode' works.

A `:text' segment is replayed by deleting N chars before point
\(if N > 0\), inserting STR, and moving point by O.  The
`post-self-insert-hook' is NOT re-fired — STR already contains
whatever the hook produced live."
  (helixel-with-replay-as 'dot
    (cond
     ;; Empty payload.
     ((or (null keys-or-segments)
          (and (or (vectorp keys-or-segments)
                   (stringp keys-or-segments))
               (= 0 (length keys-or-segments))))
      nil)
     ;; Segment list (plist with keyword cars).
     ((and (listp keys-or-segments)
           (consp (car keys-or-segments))
           (keywordp (caar keys-or-segments)))
      (dolist (seg keys-or-segments)
        (cond
         ((plist-member seg :text)
          (let* ((str    (plist-get seg :text))
                 (del    (or (plist-get seg :delete-before) 0))
                 (offset (or (plist-get seg :offset) 0))) ; ctx-lint-ok
            (when (> del 0)
              (delete-char (- (min del (- (point) (point-min))))))
            (when (stringp str)
              (insert str))
            (unless (zerop offset)
              (goto-char (+ (point) offset)))))
         ((plist-member seg :keys)
          (helixel--execute-keys-vector (plist-get seg :keys))))))
     ;; Legacy raw key vector OR key string (`kbd' returns a string).
     ((or (vectorp keys-or-segments) (stringp keys-or-segments))
      (helixel--execute-keys-vector
       (if (stringp keys-or-segments)
           (vconcat keys-or-segments)
         keys-or-segments))))))

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

;; ── Direction flip ──

(defvar helixel--repeat-permanent-flip nil
  "When non-nil, dot-repeat permanently uses reversed direction.
Toggled by `-.' — resets on each new `helixel--record-action'.")

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
EDIT is the original `helixel-tx' (used for op classification);
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
     ;; Op moves point itself, or kind has no advance: just recreate.
     ((or (not advance-fn) (helixel--op-moves-point-p op))
      (condition-case nil
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
  "Repeat EDIT N times from current position with REVERSE-P direction."
  (let ((effective (helixel--maybe-flip-dir-action edit reverse-p)))
    (dotimes (_ n)
      (unless (helixel--repeat-advance edit effective)
        (user-error "No more targets for dot-repeat"))
      (helixel-action-replay effective))
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
(defun helixel--record-action (operator &rest extra)
  "Record edit OPERATOR with current selection context and EXTRA payload.
Pops `helixel--pending-sel' via `helixel--sel-pop' (consumes the
pending selection).  Looks up the runner and display from the operator
registry and stores them in the transaction so `helixel-action-replay'
can dispatch without registry lookups.
Builds a transaction via `helixel-action-create', pushes it onto
the event ring, and stores the most recent edit in `helixel--last-tx'.
Also notifies the event ring so `;' jumping picks up the new edit.

NOTE: Caller is responsible for calling `helixel--tracking-open' first.
The `helixel-define-command' macro handles this automatically."
  (unless (or (helixel-replaying-p) executing-kbd-macro
              defining-kbd-macro)
    (let* ((pop-sel helixel--pending-sel) ; read but don't pop: clear-data does
           (runner (helixel--op-runner operator))
           ;; helixel--live-action-set already preserves the existing
           ;; preposition from a prior `:tx-runner' clause (mc prepos).
           ;; No explicit inheritence needed.
           (tx (apply #'helixel-action-create operator
                      pop-sel
                      :runner runner
                      extra)))
      (let ((new-tx (helixel-action-copy tx)))
        ;; Pre-compute and stash display on the live action (tx-replay
        ;; itself doesn't need display, but the action ring formatter does).
        (when helixel--live-action
          (setf (helixel-action-display helixel--live-action)
                (helixel--op-display operator tx)))
        (setq tx new-tx))
      (setq helixel--repeat-permanent-flip nil)
      (helixel--live-action-set tx)
      ;; Always set last-tx so callers that skip `tracking-open'
      ;; (tests, programmatic use) still have a valid edit to replay.
      (setq helixel--last-tx tx)
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
    (let ((at-edge (lambda () (if (eq dir -1) (bobp) (eobp))))
          (done nil))
      (while (not (or done (funcall at-edge)))
        (setq cnt (1+ cnt))
        (deactivate-mark)
        (helixel--recreate-selection sel)
        (unless preview-p
          (helixel-action-replay tx))
        ;; Step to next line.  Two algorithms:
        ;;   op-moves-point=nil → simple `forward-line'
        ;;   op-moves-point=t   → skip the step if the op already
        ;;                        left point at line edge (it ate
        ;;                        the current line)
        (cond
         ((not op-moves-point)
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
  "Marker for the `M-.' preview position, consumed by `.'.
Set by `M-.' (`helixel-repeat-selection') at the preview position;
consumed by `.' (`helixel-repeat-edit') when point is still there.

Positional handoff replaces the old boolean flag +
`post-command-hook' stale-clear: a marker auto-invalidates the
moment the user moves point (the equality check in
`.' fails), so no global hook is needed.")



(defun helixel--repeat-flip-tx-dir ()
  "Toggle `helixel--repeat-permanent-flip' for line/search selections.
Like \=`N\=` for search, \=`-.\=` permanently reverses dot-repeat direction.
No-op for movement, textobj, or nil selections.
Returns t on success, nil otherwise."
  (when-let* ((tx helixel--last-tx)
              (sel (helixel-action-sel tx))
              (kind (helixel-sel-kind sel))
              ((memq kind '(line search))))
    (setq helixel--repeat-permanent-flip
          (not helixel--repeat-permanent-flip))
    t))

;; ── Common repeat setup ──

(defun helixel--repeat-setup (raw-prefix)
  "Common setup for `helixel-repeat-edit' and `helixel-repeat-selection'.
Takes RAW-PREFIX (the raw prefix argument from `interactive').
Gets the last edit transaction (falling back to the event ring if
`helixel--last-tx' is not an edit), parses the prefix argument,
handles permanent direction flip, and resets search-advance state.

Returns (TX PREFIX SAVED-STATE) where:
  TX           — resolved edit `helixel-action'
  PREFIX       — `helixel-repeat-prefix' struct
  SAVED-STATE  — previous `helixel--current-state'

Signals `user-error' when no edit is available."
  (let ((tx helixel--last-tx))
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
      (when flip-dir-p (helixel--repeat-flip-tx-dir))
      ;; Search-advance scratch lives on the replay ctx, no reset needed
      ;; — each `.' / `,' creates a fresh `helixel-replay' binding.
      (list tx prefix saved-state))))

;; ── Interactive entry points ──

(defvar helixel-repeat-edit-override-functions nil
  "Abnormal hook run before `helixel-repeat-edit''s default logic.
Each function receives RAW-PREFIX and should return non-nil if it
handled the dot-repeat; nil delegates to the default implementation.
Uses `run-hook-with-args-until-success'.

Set by mc-integrate to override `.' when fake cursors exist, so `.'
applies the last edit once at each cursor's current position without
advancing.")
(make-obsolete-variable 'helixel-repeat-edit-function
                        'helixel-repeat-edit-override-functions
                        "helixel 5.0")

(defun helixel-repeat-edit (&optional raw-prefix)
  "Repeat the last editing operation at point (bound to `.`).

RAW-PREFIX is the raw prefix argument.  Delegates to
`helixel-repeat-edit-function' first; falls back to
`helixel--repeat-edit-default' if that hook is unset or returns nil."
  (interactive "P")
  (unless (run-hook-with-args-until-success
           'helixel-repeat-edit-override-functions raw-prefix)
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
  (when (and executing-kbd-macro (not helixel--last-tx))
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
`helixel--repeat-preview-pos' so a subsequent `.' that fires
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
      ;; Stash preview position for the next `.' (positional handoff).
      (when helixel--repeat-preview-pos
        (set-marker helixel--repeat-preview-pos nil))
      (setq helixel--repeat-preview-pos (point-marker)))))

;; ── Interactive entry points ──
(defun helixel-repeat-edit-pick ()
  "Choose a past edit from the event ring and replay it.
Scans `helixel--action-ring' for entries with an :op.
The chosen event's edit data becomes the new `helixel--last-tx'."
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
        ;; Reconstruct tx from event and set it as `helixel--last-tx'.
        ;; Must use `helixel-action-copy' (not `helixel--update-last-event'
        ;; which only copies the payload, leaving op/sel/runner stale).
        (setq helixel--last-tx
              (helixel-action-copy
               (apply #'helixel-action-create
                      (helixel-action-op event)
                      (helixel-action-sel event)
                      :display (helixel-action-display-format event)
                      :runner (helixel-action-runner event)
                      (helixel-action-payload event))))
        (helixel-repeat-edit)))))

(defun helixel-repeat-debug ()
  "Pretty-print `helixel--last-tx' and edit events in the event ring."
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
        (insert ";; helixel--last-tx (display: "
                (or (and helixel--last-tx
                         (helixel-action-format helixel--last-tx))
                    "<none>")
                ")\n")
        (pp helixel--last-tx (current-buffer))
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



