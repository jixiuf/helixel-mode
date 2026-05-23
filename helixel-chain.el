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

(require 'helixel-data)                  ; for helixel-edit-make
(require 'helixel-repeat)                ; for helixel--last-tx, etc.

(defvar helixel--repeat-chain-preview)    ; defined in helixel-repeat.el

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

(defvar-local helixel--chain-move-len nil
  "Number of movement keys before the first edit in the chain.
Counted by `helixel--chain-post-cmd' via `post-command-hook'.
Nil until the first edit command is detected.")

(defvar-local helixel--chain-cmd-count 0
  "Counter for commands executed during chain recording.
Incremented by `helixel--chain-post-cmd'.")

(defvar-local helixel--chain-keys nil
  "List of key vectors collected during chain recording via pre-command-hook.
Each element is the return value of `this-single-command-keys'
from one command execution.  Collected by `helixel--chain-pre-cmd'.
Vconcat'd by `helixel-repeat-chain-end' into the full kmacro.

Does NOT use `start-kbd-macro'/`end-kbd-macro' because
`start-kbd-macro' prepends `this-command-keys' (the chain-start
key) into `last-kbd-macro', shifting all move-len indices.
Manual collection avoids this offset entirely.")


;; ── Key recording (pre-command-hook, no kmacro) ──

(defun helixel--chain-pre-cmd ()
  "Pre-command-hook: record each command's key sequence.
Captures `this-single-command-keys' for key-based replay.
Skips `helixel-repeat-chain-start' and `helixel-repeat-chain-end'
so the start/end keys are never recorded."
  (unless (memq this-command
                '(helixel-repeat-chain-start
                  helixel-repeat-chain-end
                  helixel-repeat-chain-cancel))
    (push (this-single-command-keys) helixel--chain-keys)))

;; ── Runner ──

(defun helixel--chain-post-cmd ()
  "Post-command-hook: track movement key count during chain recording.
Sets `helixel--chain-move-len' when the first edit command is detected."
  (when helixel--repeat-chaining
    (unless (memq this-command
                  '(helixel-repeat-chain-start helixel-repeat-chain-end))
      (setq helixel--chain-cmd-count (1+ helixel--chain-cmd-count)))
    (unless helixel--chain-move-len
      (when (and helixel--action
                 (eq (plist-get helixel--action :category) 'edit))
        (setq helixel--chain-move-len
              (max 0 (1- helixel--chain-cmd-count)))))))

(defun helixel--repeat-chain-runner (tx)
  "Execute the stored kmacro in chain TX.
When `helixel--repeat-chain-preview' is set (from `,'), replays only
the edit part (movement keys were already executed by `,')."
  (let* ((payload (helixel-edit-payload tx))
         (edit-keys (plist-get payload :kmacro))
         (helixel--inhibit-repeat-record t)
         (helixel--inhibit-action-track t))
    (setq helixel--repeat-chain-preview nil)
    (when edit-keys
      (execute-kbd-macro edit-keys))))

(helixel-register-op chain
  :display "chain"
  :repeat-advance nil    ; chain uses sel-driven advance via unified strategy
  :runner #'helixel--repeat-chain-runner)


;; ── Lifecycle commands ──

;;;###autoload
(defun helixel-repeat-chain-start ()
  "Start recording keystrokes for compound dot-repeat.
Snapshots the current selection context for advance decisions.
Keystrokes are collected via pre-command-hook (no kmacro).
Call `helixel-repeat-chain-end' to finish and create a repeatable
transaction, or `helixel-repeat-chain-cancel' to discard."
  (interactive)
  (when (or helixel--repeat-chaining executing-kbd-macro)
    (user-error "Already chaining or macro replay in progress"))
  (setq helixel--repeat-chaining t)
  (setq helixel--chain-move-len nil)
  (setq helixel--chain-cmd-count 0)
  (setq helixel--chain-keys nil)
  (setq helixel--repeat-chain-init-ctx helixel--repeat-sel-ctx)
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
Collects the recorded keys from `helixel--chain-keys', splits them
into move-keys (before first edit) and edit-keys (including edit),
and stores a chain transaction in `helixel--last-tx'.

Determines advance behavior from the initial selection context
\(snapshotted at chain-start)."
  (interactive)
  (unless helixel--repeat-chaining
    (user-error "Not chaining"))
  (setq helixel--repeat-chaining nil)
  (remove-hook 'pre-command-hook #'helixel--chain-pre-cmd t)
  (remove-hook 'post-command-hook #'helixel--chain-post-cmd t)
  ;; Build the macro from collected key vectors (no kmacro — no
  ;; start-kbd-macro prepend).
  (let* ((keys (nreverse helixel--chain-keys))
         (macro (when keys (apply #'vconcat keys)))
         (init-ctx helixel--repeat-chain-init-ctx)
         ;; Merge entry-kind from live ctx (i/a updates it after snapshot)
         (live-ctx helixel--repeat-sel-ctx)
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
         (init-bounds helixel--repeat-chain-init-bounds)
         (move-len (and helixel--chain-move-len
                        (> helixel--chain-move-len 0)
                        (<= helixel--chain-move-len
                            (length macro))
                        helixel--chain-move-len))
         (move-keys (when move-len
                      (substring macro 0 move-len)))
         (edit-keys (if move-len
                        (substring macro move-len)
                      macro)))
    (if (and macro (> (length macro) 0))
        (let* ((tx (helixel-edit-make 'chain init-ctx
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
          (setq helixel--chain-move-len nil)
          (setq helixel--last-tx tx)
          (helixel-action-start 'edit 'chain)
          (helixel--live-edit-set tx)
          (helixel-action-commit)
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
  (setq helixel--chain-move-len nil)
  (setq helixel--chain-keys nil)
  (remove-hook 'pre-command-hook #'helixel--chain-pre-cmd t)
  (remove-hook 'post-command-hook #'helixel--chain-post-cmd t)
  (message "Chain cancelled"))

(provide 'helixel-chain)
;;; helixel-chain.el ends here
