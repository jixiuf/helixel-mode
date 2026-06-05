;;; helixel-insert-record.el --- Insert-mode key recording -*- lexical-binding: t; -*-

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

;;; Commentary:
;;
;; Records key sequences via `pre-command-hook' during insert mode.
;; Uses `this-single-command-keys' (not kmacro) to avoid breaking
;; `sit-for' which eglot's LSP completion depends on.
;;
;; Public API (consumed by helixel-state, helixel-editing,
;; helixel-repeat):
;;   helixel--insert-begin
;;   helixel--insert-finish
;;   helixel--execute-keys
;;   helixel--repeat-get-keys
;;

;;; Code:

(require 'helixel-core)
(require 'helixel-replay)

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
    (push (helixel-keyrec-capture) helixel--insert-keys)))

(defun helixel--insert-begin ()
  "Start insert-mode recording.
Records key sequences via `pre-command-hook'.
Does NOT call `helixel--switch-state' -- that stays in helixel-editing.el."
  (setq helixel--insert-keys nil)
  (add-hook 'pre-command-hook #'helixel--on-insert-command nil t))

(defun helixel--insert-finish ()
  "End insert-mode recording.  Returns the key vector or nil."
  (remove-hook 'pre-command-hook #'helixel--on-insert-command t)
  (let ((keys (helixel-keyrec-finalize-list helixel--insert-keys)))
    (setq helixel--insert-keys nil)
    keys))

;; ── Replay ──

(defsubst helixel--repeat-get-keys (tx)
  "Return the :keys key-sequence vector from TX payload, or nil."
  (helixel-action-payload-get tx :keys))

(defun helixel--execute-keys (keys)
  "Execute recorded KEYS (a key vector).
For printable characters, uses `insert-char' directly then runs
`post-self-insert-hook' (for `electric-pair-mode' etc.) with
`last-command-event' bound to the character.
For non-printable keys, uses `execute-kbd-macro'."
  (helixel-with-replay-as 'dot
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

(provide 'helixel-insert-record)
;;; helixel-insert-record.el ends here
