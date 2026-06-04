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

(require 'helixel-core) ; helixel-edit-create, keyrec helpers
(require 'helixel-macros)                ; for helixel-with-edit-tracking
(require 'helixel-repeat)                ; for helixel--last-edit, etc.

;; ── Session state ──
;;
;; All chain bookkeeping lives in a single `helixel-chain-session'
;; struct stored in one buffer-local, replacing what used to be 7
;; separate `defvar-local's.  Predicate `helixel--chain-active-p'
;; replaces direct reads of the old `helixel--repeat-chaining' flag.

(cl-defstruct (helixel-chain-session
               (:conc-name helixel-chain-session-)
               (:copier nil))
  "Per-buffer chain recording session, owned by `helixel--chain-session'.
Slots:
  ACTIVE-P    — non-nil while recording is in progress.
  EDIT-PHASE-P — non-nil once the first editing command has been seen;
                 before this, captured keys go to MOVE-KEYS, after to
                 EDIT-KEYS.
  MOVE-KEYS   — list of key-vectors captured before the first edit
                 (reversed; finalize via `nreverse'+vconcat).
  EDIT-KEYS   — list of key-vectors captured after first edit.
  INIT-CTX    — `helixel-sel' snapshotted at chain-start; drives
                 advance behaviour at replay time.
  INIT-BOUNDS — (BEG . END) markers of the initial region at start,
                 or nil; released on teardown.
  LAST-EDIT-SNAPSHOT — `helixel--last-edit' at chain-start; used to
                       detect the first edit (a different value of
                       `helixel--last-edit' carrying an :op)."
  active-p edit-phase-p
  move-keys edit-keys
  init-ctx init-bounds
  last-edit-snapshot)

(defvar-local helixel--chain-session nil
  "Per-buffer `helixel-chain-session' for the in-progress chain, or nil.
Replaces what used to be 7 separate buffer-local variables
\(`helixel--repeat-chaining', `helixel--chain-move-keys',
`helixel--chain-edit-keys', `helixel--chain-in-edit-phase',
`helixel--chain-last-event-snapshot', `helixel--repeat-chain-init-ctx',
`helixel--repeat-chain-init-bounds').")

(defsubst helixel--chain-active-p ()
  "Return non-nil while a chain is being recorded in this buffer."
  (and helixel--chain-session
       (helixel-chain-session-active-p helixel--chain-session)))


;; ── Key recording (pre-command-hook, no kmacro) ──

(defun helixel--chain-pre-cmd ()
  "Pre-command-hook: route keys to move-keys or edit-keys.
Before first edit: push to MOVE-KEYS slot of `helixel--chain-session'.
After first edit: push to EDIT-KEYS slot.
Skips chain start/end/cancel commands."
  (unless (memq this-command
                '(helixel-repeat-chain-start
                  helixel-repeat-chain-end
                  helixel-repeat-chain-cancel
                  helixel-normal-escape))
    (let ((s helixel--chain-session))
      (when s
        (let ((k (helixel-keyrec-capture)))
          (if (helixel-chain-session-edit-phase-p s)
              (push k (helixel-chain-session-edit-keys s))
            (push k (helixel-chain-session-move-keys s))))))))

;; ── Runner ──

(defun helixel--chain-post-cmd ()
  "Post-command-hook: detect first edit, switch from move to edit phase.
Once `helixel--last-edit' changes AND carries an :op (meaning
`helixel--record-edit' was called, not a mere movement commit),
all subsequent keys go to EDIT-KEYS."
  (let ((s helixel--chain-session))
    (when (and s
               (helixel-chain-session-active-p s)
               (not (helixel-chain-session-edit-phase-p s))
               helixel--last-edit
               (helixel-edit-op helixel--last-edit)
               (not (eq helixel--last-edit
                        (helixel-chain-session-last-edit-snapshot s))))
      ;; Move the edit command's own key from move-keys to edit-keys.
      (when (helixel-chain-session-move-keys s)
        (push (car (helixel-chain-session-move-keys s))
              (helixel-chain-session-edit-keys s))
        (pop (helixel-chain-session-move-keys s)))
      (setf (helixel-chain-session-edit-phase-p s) t))))

(defun helixel--repeat-chain-runner (tx)
  "Execute the stored kmacro in chain TX.

For search-initiated chains, positions cursor at `match-beginning'
before replay, matching the behaviour of the original recording
where `helixel-insert' calls `(goto-char (region-beginning))'."
  (let* ((sel (helixel-edit-sel tx))
         (edit-keys (helixel-edit-payload-get tx :kmacro)))
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
  (let* ((sel (helixel-edit-sel edit))
         (kind (and sel (helixel-sel-kind sel)))
         (advance-fn (helixel--kind-advance kind))
         (move-keys (helixel-edit-payload-get edit :chain-move-keys))
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
              (when-let* ((m (car (helixel-edit-mark-region effective-edit))))
                (goto-char (marker-position m))))
     :all-buffer-fn (helixel--kind-all-buffer-fn kind))))


;; ── Cleanup helper ──

(defun helixel--chain-reset-state ()
  "Reset all chain bookkeeping state.
Releases any initial-region markers (so they don't pin buffer text),
then clears `helixel--chain-session' and removes the recording hooks.
Idempotent.  Used by chain-end and chain-cancel."
  (when-let* ((s helixel--chain-session)
              (bounds (helixel-chain-session-init-bounds s)))
    (let ((mb (car bounds)) (me (cdr bounds)))
      (when (marker-position mb) (set-marker mb nil))
      (when (marker-position me) (set-marker me nil))))
  (setq helixel--chain-session nil)
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
  (when (or (helixel--chain-active-p) executing-kbd-macro)
    (user-error "Already chaining or macro replay in progress"))
  (setq helixel--chain-session
        (make-helixel-chain-session
         :active-p t
         :edit-phase-p nil
         :move-keys nil
         :edit-keys nil
         :init-ctx helixel--pending-sel
         :init-bounds (when (use-region-p)
                        (cons (copy-marker (region-beginning))
                              (copy-marker (region-end))))
         :last-edit-snapshot helixel--last-edit))
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
  (unless (helixel--chain-active-p)
    (user-error "Not chaining"))
  ;; Stop recording first; finalize-list reads the accumulators.
  (let* ((s helixel--chain-session)
         (_ (setf (helixel-chain-session-active-p s) nil))
         (_ (remove-hook 'pre-command-hook #'helixel--chain-pre-cmd t))
         (_ (remove-hook 'post-command-hook #'helixel--chain-post-cmd t))
         (move-keys (helixel-keyrec-finalize-list
                     (helixel-chain-session-move-keys s)))
         (edit-keys (helixel-keyrec-finalize-list
                     (helixel-chain-session-edit-keys s)))
         (macro (if (and move-keys edit-keys)
                    (vconcat move-keys edit-keys)
                  (or move-keys edit-keys)))
         (init-ctx (helixel-chain-session-init-ctx s))
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
         (had-content (and macro (> (length macro) 0)))
         (chain-tx nil))
    (when had-content
      (let ((tx (helixel-edit-create 'chain init-ctx
                   :runner #'helixel--repeat-chain-runner
                   :display (format "chain(%d)" (length edit-keys))
                   :kmacro edit-keys
                   :chain-move-keys move-keys)))
        (setq chain-tx tx)
        (setq helixel--last-edit (helixel-edit-copy tx))
        (helixel-with-edit-tracking
            (:op 'chain :category 'edit :subcat 'chain)
          (helixel--live-edit-set tx))))
    ;; Single point of teardown for both success and empty paths.
    (let ((edit-len (length (or edit-keys [])))
          (move-len (length (or move-keys []))))
      (helixel--chain-reset-state)
      (if had-content
          (message "Chain recorded (%d keys, move=%d)" edit-len move-len)
        (message "Chain empty — nothing recorded")))
    ;; Fire integration hook AFTER teardown so any handler (mc, etc.)
    ;; sees a fully-consistent state.
    (when chain-tx
      (run-hook-with-args 'helixel-chain-recorded-functions chain-tx))))

(defvar helixel-chain-recorded-functions nil
  "Abnormal hook run after a chain is successfully recorded.
Each function is called with one argument, the new chain
`helixel-edit'.  Runs synchronously inside
`helixel-repeat-chain-end' AFTER `helixel--last-edit' has been
updated to point at the new chain.

Use this hook from integration layers (e.g. `helixel-mc-integrate')
instead of `advice-add' on `helixel-repeat-chain-end' —
helixel-mode modules MUST NOT advise each other.")

;;;###autoload
(defun helixel-repeat-chain-cancel ()
  "Discard the current chain without recording."
  (interactive)
  (helixel--chain-reset-state)
  (message "Chain cancelled"))

(provide 'helixel-chain)
;;; helixel-chain.el ends here
