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

(require 'helixel-core)                  ; for helixel--make-tx
(require 'helixel-macros)                ; for helixel-with-edit-tracking
(require 'helixel-repeat)                ; for helixel--last-tx, etc.

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

(defvar-local helixel--chain-last-tx-snapshot nil
  "Snapshot of `helixel--last-tx' at chain-start.
Used by `helixel--chain-post-cmd' to detect the first edit
command by checking whether `helixel--last-tx' changed.
More reliable than checking `:category' on `helixel--action'.")


;; ── Key recording (pre-command-hook, no kmacro) ──

(defun helixel--chain-pre-cmd ()
  "Pre-command-hook: route keys to move-keys or edit-keys.
Before first edit: push to `helixel--chain-move-keys'.
After first edit: push to `helixel--chain-edit-keys'.
Skips chain start/end/cancel commands."
  (unless (memq this-command
                '(helixel-repeat-chain-start
                  helixel-repeat-chain-end
                  helixel-repeat-chain-cancel))
    (if helixel--chain-in-edit-phase
        (push (this-single-command-keys) helixel--chain-edit-keys)
      (push (this-single-command-keys) helixel--chain-move-keys))))

;; ── Runner ──

(defun helixel--chain-post-cmd ()
  "Post-command-hook: detect first edit, switch from move to edit phase.
Once `helixel--last-tx' changes (meaning `helixel--record-edit' was
called), all subsequent keys go to edit-keys."
  (when (and helixel--repeat-chaining
             (not helixel--chain-in-edit-phase)
             helixel--last-tx
             (not (eq helixel--last-tx helixel--chain-last-tx-snapshot)))
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
  (let* ((payload (helixel-event-payload tx))
         (sel (helixel-event-sel tx))
         (edit-keys (plist-get payload :kmacro))
         (helixel--inhibit-repeat-record t)
         (helixel--inhibit-action-track t))
    (when edit-keys
      ;; Reposition cursor at match-beginning for search sel chains.
      ;; The advance fn leaves point at match-end, but the original
      ;; recording started at match-beginning (via region-beginning).
      (when (and sel (eq (helixel-sel-get-kind sel) 'search)
                 (match-beginning 0))
        (goto-char (match-beginning 0)))
      (execute-kbd-macro edit-keys))))

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
         (kind (and sel (helixel-sel-get-kind sel)))
         (advance-fn (helixel--kind-advance kind))
         (payload (helixel-event-payload edit))
         (move-keys (plist-get payload :chain-move-keys))
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
              (when-let* ((m (helixel-event-marker effective-edit)))
                (goto-char (marker-position m))))
     :all-buffer-fn (helixel--kind-all-buffer-fn kind))))

(defun helixel--chain-preview-strategy (edit &optional reverse-p)
  "Build a preview-only repeat strategy for chain EDIT and REVERSE-P.
Same as chain strategy but uses `ignore' for apply (no edit execution)."
  (let* ((sel (helixel-event-sel edit))
         (kind (and sel (helixel-sel-get-kind sel)))
         (advance-fn (helixel--kind-advance kind))
         (payload (helixel-event-payload edit))
         (move-keys (plist-get payload :chain-move-keys))
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
              (when-let* ((m (helixel-event-marker effective-edit)))
                (goto-char (marker-position m)))))))


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
  (setq helixel--chain-last-tx-snapshot helixel--last-tx)
  (setq helixel--chain-move-keys nil)
  (setq helixel--chain-edit-keys nil)
  (setq helixel--repeat-chain-init-ctx helixel--pending-sel)
  (setq helixel--repeat-chain-init-bounds
        (when (use-region-p)
          (cons (copy-marker (region-beginning))
                (copy-marker (region-end)))))
  (deactivate-mark)
  (add-hook 'pre-command-hook #'helixel--chain-pre-cmd nil t)
  (add-hook 'post-command-hook #'helixel--chain-post-cmd nil t)
  (message "Chain rec • Q to finish"))

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
  (setq helixel--repeat-chaining nil)
  (remove-hook 'pre-command-hook #'helixel--chain-pre-cmd t)
  (remove-hook 'post-command-hook #'helixel--chain-post-cmd t)
  ;; Build move/edit macros from separate accumulators.
  ;; No substring splitting — keys were routed during recording.
  (let* ((move-keys (when helixel--chain-move-keys
                      (apply #'vconcat (nreverse helixel--chain-move-keys))))
         (edit-keys (when helixel--chain-edit-keys
                      (apply #'vconcat (nreverse helixel--chain-edit-keys))))
         (macro (if (and move-keys edit-keys)
                    (vconcat move-keys edit-keys)
                  (or move-keys edit-keys)))
         (init-ctx helixel--repeat-chain-init-ctx)
         ;; Merge entry-kind from live ctx (i/a updates it after snapshot)
         (live-ctx helixel--pending-sel)
         (init-ctx (if (and init-ctx live-ctx
                            (eq (helixel-sel-get-kind init-ctx)
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
         (init-bounds helixel--repeat-chain-init-bounds))
    (if (and macro (> (length macro) 0))
        (let* ((tx (helixel--make-tx 'chain init-ctx
                     :runner #'helixel--repeat-chain-runner
                     :display (format "chain(%d)" (length edit-keys))
                     :kmacro edit-keys
                     :chain-move-keys move-keys
                     :chain-init-ctx init-ctx)))
          (when init-bounds
            (let ((mb (car init-bounds))
                  (me (cdr init-bounds)))
              (when (marker-position mb) (set-marker mb nil))
              (when (marker-position me) (set-marker me nil))))
          (setq helixel--repeat-chain-init-ctx nil)
          (setq helixel--repeat-chain-init-bounds nil)
          (setq helixel--chain-in-edit-phase nil)
          (setq helixel--chain-move-keys nil)
          (setq helixel--chain-edit-keys nil)
          (helixel--update-last-tx tx)
          (helixel-with-edit-tracking
              (:op 'chain :category 'edit :subcat 'chain)
            (helixel--live-edit-set tx))
          (message "Chain recorded (%d keys, move=%d)"
                   (length edit-keys)
                   (if move-keys (length move-keys) 0)))
      ;; Empty macro — clean up and discard
      (when helixel--repeat-chain-init-bounds
        (let ((mb (car helixel--repeat-chain-init-bounds))
              (me (cdr helixel--repeat-chain-init-bounds)))
          (when (marker-position mb) (set-marker mb nil))
          (when (marker-position me) (set-marker me nil))))
      (setq helixel--repeat-chain-init-ctx nil)
      (setq helixel--repeat-chain-init-bounds nil)
      (setq helixel--chain-in-edit-phase nil)
      (setq helixel--chain-move-keys nil)
      (setq helixel--chain-edit-keys nil)
      (message "Chain empty — nothing recorded"))))

;;;###autoload
(defun helixel-repeat-chain-cancel ()
  "Discard the current chain without recording."
  (interactive)
  (when helixel--repeat-chain-init-bounds
    (let ((mb (car helixel--repeat-chain-init-bounds))
          (me (cdr helixel--repeat-chain-init-bounds)))
      (when (marker-position mb) (set-marker mb nil))
      (when (marker-position me) (set-marker me nil))))
  (setq helixel--repeat-chaining nil)
  (setq helixel--repeat-chain-init-ctx nil)
  (setq helixel--repeat-chain-init-bounds nil)
  (setq helixel--chain-in-edit-phase nil)
  (setq helixel--chain-move-keys nil)
  (setq helixel--chain-edit-keys nil)
  (remove-hook 'pre-command-hook #'helixel--chain-pre-cmd t)
  (remove-hook 'post-command-hook #'helixel--chain-post-cmd t)
  (message "Chain cancelled"))

(provide 'helixel-chain)
;;; helixel-chain.el ends here
