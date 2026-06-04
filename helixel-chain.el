;;; helixel-chain.el --- chain recording & compound dot-repeat  -*- lexical-binding: t; -*-

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

;; Chain extends the `.`/`,` repeat system with compound kmacro recording.
;; See `helixel-repeat.el' for the repeat strategy engine.

;;; Code:

(require 'helixel-core)                  ; for helixel--make-tx, keyrec helpers
(require 'helixel-macros)                ; for helixel-with-edit-tracking
(require 'helixel-repeat)                ; for helixel--last-event, etc.

;; ── State variables ──

(defvar-local helixel--repeat-chaining nil
  "Non-nil when kmacro is being recorded for a compound chain.
Set by `helixel-repeat-chain-start', cleared by `helixel-repeat-chain-end'
or `helixel-repeat-chain-cancel'.")

(defvar-local helixel--repeat-chain-init-ctx nil
  "The `helixel-sel' at chain-start time.
Snapshotted by `helixel-repeat-chain-start', used by chain-end
to determine advance behavior.")

(defvar-local helixel--repeat-chain-init-bounds nil
  "Initial region bounds at chain-start, as (BEG . END) markers, or nil.")

(defvar-local helixel--chain-move-keys nil
  "Key vectors for cursor-movement commands before the first edit.
Collected by `helixel--chain-pre-cmd' in move phase.
Cleared and vconcat'd by `helixel-repeat-chain-end'.")

(defvar-local helixel--chain-edit-keys nil
  "Key vectors for editing commands (after first edit detected).
Collected by `helixel--chain-pre-cmd' in edit phase.
Cleared and vconcat'd by `helixel-repeat-chain-end'.")

(defvar-local helixel--chain-in-edit-phase nil
  "Non-nil once the first edit command has been detected.
Set by `helixel--chain-post-cmd'.  Before this, keys go into
`helixel--chain-move-keys'; after, into `helixel--chain-edit-keys'.")

(defvar-local helixel--chain-last-event-snapshot nil
  "Snapshot of `helixel--last-event' at chain-start.
Used by `helixel--chain-post-cmd' to detect the first edit
command by checking whether `helixel--last-event' changed.
More reliable than checking `:category' on `helixel-event'.")


;; ── Key recording (pre-command-hook, no kmacro) ──

(defun helixel--chain-pre-cmd ()
  "Pre-command-hook: route keys to move-keys or edit-keys.
Before first edit: push to `helixel--chain-move-keys'.
After first edit: push to `helixel--chain-edit-keys'.
Skips chain start/end/cancel commands."
  (unless (memq this-command
                '(helixel-repeat-chain-start
                  helixel-repeat-chain-end
                  helixel-repeat-chain-cancel
                  helixel-normal-escape))
    (if helixel--chain-in-edit-phase
        (push (helixel-keyrec-capture) helixel--chain-edit-keys)
      (push (helixel-keyrec-capture) helixel--chain-move-keys))))

;; ── Runner ──

(defun helixel--chain-post-cmd ()
  "Post-command-hook: detect first edit, switch from move to edit phase.
Once `helixel--last-event' changes AND carries an :op (meaning
`helixel--record-edit' was called, not a mere movement commit),
all subsequent keys go to edit-keys."
  (when (and helixel--repeat-chaining
             (not helixel--chain-in-edit-phase)
             helixel--last-event
             (helixel-event-op helixel--last-event)
             (not (eq helixel--last-event helixel--chain-last-event-snapshot)))
    ;; Move the edit command's own key from move-keys to edit-keys.
    (when helixel--chain-move-keys
      (push (car helixel--chain-move-keys) helixel--chain-edit-keys)
      (pop helixel--chain-move-keys))
    (setq helixel--chain-in-edit-phase t)))

(defun helixel--repeat-chain-runner (tx)
  "Execute the stored kmacro in chain TX.

For search-initiated chains, positions cursor at `match-beginning'
before replay, matching the behaviour of the original recording
where `helixel-insert' calls `(goto-char (region-beginning))'."
  (let* ((sel (helixel-event-sel tx))
         (edit-keys (helixel-event-payload-get tx :kmacro)))
    (helixel-with-replay-context
    (when edit-keys
      ;; Reposition cursor at match-beginning for search sel chains.
      ;; The advance fn leaves point at match-end, but the original
      ;; recording started at match-beginning (via region-beginning).
      (when (and sel (eq (helixel-sel-kind sel) 'search)
                 (match-beginning 0))
        (goto-char (match-beginning 0)))
      (execute-kbd-macro edit-keys)))))

(helixel-register-op chain
  :display "chain"
  :runner #'helixel--repeat-chain-runner
  :strategy-builder #'helixel--chain-strategy-builder)

(defun helixel--chain-strategy-builder (edit &optional reverse-p)
  "Build a repeat strategy for chain EDIT with optional REVERSE-P.
Direction flip is delegated to `helixel--maybe-flip-dir-edit'.
Advance: sel advance + move-keys + edit-keys.
Apply: edit-keys only.
Reset: goto marker."
  (let* ((sel (helixel-event-sel edit))
         (kind (and sel (helixel-sel-kind sel)))
         (advance-fn (helixel--kind-advance kind))
         (move-keys (helixel-event-payload-get edit :chain-move-keys))
         (effective-edit (helixel--maybe-flip-dir-edit edit reverse-p)))
    (make-helixel-repeat-strategy
     :advance (lambda (_edit)
                (and (or (null advance-fn)
                         (funcall advance-fn effective-edit))
                     (progn
                       (when move-keys
                         (execute-kbd-macro move-keys))
                       t)))
     :apply (lambda (_edit)
              (helixel--execute-edit effective-edit))
     :reset (lambda (_edit)
              (when-let* ((m (car (helixel-event-mark-region effective-edit))))
                (goto-char (marker-position m))))
     :all-buffer-fn (helixel--kind-all-buffer-fn kind))))

(defun helixel--chain-preview-strategy (edit &optional reverse-p)
  "Build a preview-only repeat strategy for chain EDIT and REVERSE-P.
Same as chain strategy but uses `ignore' for apply (no edit execution)."
  (let* ((sel (helixel-event-sel edit))
         (kind (and sel (helixel-sel-kind sel)))
         (advance-fn (helixel--kind-advance kind))
         (move-keys (helixel-event-payload-get edit :chain-move-keys))
         (effective-edit (helixel--maybe-flip-dir-edit edit reverse-p)))
    (make-helixel-repeat-strategy
     :advance (lambda (_edit)
                (and (or (null advance-fn)
                         (funcall advance-fn effective-edit))
                     (progn
                       (when move-keys
                         (execute-kbd-macro move-keys))
                       t)))
     :apply #'ignore
     :reset (lambda (_edit)
              (when-let* ((m (car (helixel-event-mark-region effective-edit))))
                (goto-char (marker-position m)))))))


;; ── Cleanup helper ──

(defun helixel--chain-reset-state ()
  "Reset all chain bookkeeping state.
Clears recording flags, key accumulators, snapshotted ctx, and
any initial-region markers (releasing them so they don't pin
buffer text).  Idempotent.  Used by chain-end and chain-cancel."
  (when helixel--repeat-chain-init-bounds
    (let ((mb (car helixel--repeat-chain-init-bounds))
          (me (cdr helixel--repeat-chain-init-bounds)))
      (when (marker-position mb) (set-marker mb nil))
      (when (marker-position me) (set-marker me nil))))
  (setq helixel--repeat-chaining nil
        helixel--repeat-chain-init-ctx nil
        helixel--repeat-chain-init-bounds nil
        helixel--chain-in-edit-phase nil
        helixel--chain-move-keys nil
        helixel--chain-edit-keys nil)
  (remove-hook 'pre-command-hook #'helixel--chain-pre-cmd t)
  (remove-hook 'post-command-hook #'helixel--chain-post-cmd t))


;; ── Lifecycle commands ──

;;;###autoload
(defun helixel-repeat-chain-start ()
  "Start recording keystrokes for compound dot-repeat.
Snapshots the current selection context for advance decisions.
Keystrokes are collected via `pre-command-hook' (no kmacro).
Call `helixel-repeat-chain-end' to finish and create a repeatable
transaction, or `helixel-repeat-chain-cancel' to discard."
  (interactive)
  (when (or helixel--repeat-chaining executing-kbd-macro)
    (user-error "Already chaining or macro replay in progress"))
  (setq helixel--repeat-chaining t)
  (setq helixel--chain-in-edit-phase nil)
  (setq helixel--chain-last-event-snapshot helixel--last-event)
  (setq helixel--chain-move-keys nil)
  (setq helixel--chain-edit-keys nil)
  (setq helixel--repeat-chain-init-ctx helixel--pending-sel)
  (setq helixel--repeat-chain-init-bounds
        (when (use-region-p)
          (cons (copy-marker (region-beginning))
                (copy-marker (region-end)))))
  (deactivate-mark)
  (add-hook 'pre-command-hook #'helixel--chain-pre-cmd t)
  (add-hook 'post-command-hook #'helixel--chain-post-cmd nil t)
  (message "Chain rec • esc to finish"))

;;;###autoload
(defun helixel-repeat-chain-end ()
  "Stop keystroke recording and create a compound chain transaction.
Collects move-keys and edit-keys from separate accumulators
\(routed during recording by `helixel--chain-pre-cmd').
Determines advance behavior from the initial selection context
\(snapshotted at chain-start)."
  (interactive)
  (unless helixel--repeat-chaining
    (user-error "Not chaining"))
  ;; Stop recording first; finalize-list reads the accumulators.
  (setq helixel--repeat-chaining nil)
  (remove-hook 'pre-command-hook #'helixel--chain-pre-cmd t)
  (remove-hook 'post-command-hook #'helixel--chain-post-cmd t)
  (let* ((move-keys (helixel-keyrec-finalize-list
                     helixel--chain-move-keys))
         (edit-keys (helixel-keyrec-finalize-list
                     helixel--chain-edit-keys))
         (macro (if (and move-keys edit-keys)
                    (vconcat move-keys edit-keys)
                  (or move-keys edit-keys)))
         (init-ctx helixel--repeat-chain-init-ctx)
         ;; Merge entry-kind from live ctx (i/a updates it after snapshot)
         (live-ctx helixel--pending-sel)
         (init-ctx (if (and init-ctx live-ctx
                            (eq (helixel-sel-kind init-ctx)
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
         (had-content (and macro (> (length macro) 0))))
    (when had-content
      (let ((tx (helixel--make-tx 'chain init-ctx
                   :runner #'helixel--repeat-chain-runner
                   :display (format "chain(%d)" (length edit-keys))
                   :kmacro edit-keys
                   :chain-move-keys move-keys
                   :chain-init-ctx init-ctx)))
        (setq helixel--last-event (helixel--copy-tx tx))
        (helixel-with-edit-tracking
            (:op 'chain :category 'edit :subcat 'chain)
          (helixel--live-edit-set tx))))
    ;; Single point of teardown for both success and empty paths.
    (let ((edit-len (length (or edit-keys [])))
          (move-len (length (or move-keys []))))
      (helixel--chain-reset-state)
      (if had-content
          (message "Chain recorded (%d keys, move=%d)" edit-len move-len)
        (message "Chain empty — nothing recorded")))))

;;;###autoload
(defun helixel-repeat-chain-cancel ()
  "Discard the current chain without recording."
  (interactive)
  (helixel--chain-reset-state)
  (message "Chain cancelled"))

(provide 'helixel-chain)
;;; helixel-chain.el ends here
