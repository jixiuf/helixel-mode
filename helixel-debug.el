;;; helixel-debug.el --- Error capture for helixel-mode -*- lexical-binding: t; -*-

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
;; Centralized error-capture system for helixel-mode.
;;
;; This module has ZERO dependencies on other helixel modules
;; (cl-lib only); `helixel-core' requires it so every module gets
;; `helixel--with-debug-log' transitively.
;;
;; When `helixel-debug' is non-nil, errors that are normally silently
;; swallowed (via `condition-case nil' or `ignore-errors') are captured
;; with full backtraces into a per-buffer ring buffer.  Use
;; `helixel-debug-show-log' to inspect them.

;;; Code:

(require 'cl-lib)

;; ── Debug infrastructure ──
;; Centralized error-capture system.  When `helixel-debug' is non-nil,
;; errors that are normally silently swallowed (via `condition-case nil'
;; or `ignore-errors') are captured with full backtraces into a per-buffer
;; ring buffer.  Use `helixel-debug-show-log' to inspect them.

(defcustom helixel-debug nil
  "When non-nil, capture silently-swallowed errors into `helixel--debug-log'.
When nil, error-handling is identical to the undebugged version — zero
overhead.  Enabling this preserves error messages and backtraces for
pattern-matched `condition-case' sites throughout `helixel-mode'.
\<helixel-debug-log-mode-map>
Use \\[helixel-debug-show-log] to open the debug-log buffer."
  :type 'boolean
  :group 'helixel)

(defvar-local helixel--debug-log nil
  "Circular buffer of captured error entries.
Each entry is a plist:
  (:context STR :error ERR :backtrace STR :timestamp FLOAT :buffer BUFFER).
Max `helixel-debug-log-max' entries, newest first.")

(defcustom helixel-debug-log-max 200
  "Maximum number of error entries in `helixel--debug-log'."
  :type 'natnum
  :group 'helixel)

(defun helixel--debug-log-error (context err)
  "Record ERR with CONTEXT string into `helixel--debug-log'.
Captures the full backtrace for inspection.  No-op when `helixel-debug'
is nil or when called from within the debug-log buffer itself.
ERR must be a condition object (the second argument to `condition-case')."
  (when (and helixel-debug
             (not (derived-mode-p 'helixel-debug-log-mode))
             ;; Don't fill up the log with its own errors.
             (not (eq context 'helixel-debug-log)))
    (unless helixel--debug-log
      (setq helixel--debug-log nil))
    (push (list :context context
                :error err
                :backtrace (helixel--debug--capture-backtrace)
                :timestamp (float-time)
                :buffer (current-buffer))
          helixel--debug-log)
    ;; Cap the ring.
    (when (> (length helixel--debug-log) helixel-debug-log-max)
      (setq helixel--debug-log
            (cl-subseq helixel--debug-log 0 helixel-debug-log-max)))))

(defun helixel--debug--capture-backtrace ()
  "Return a string with the full backtrace at point of call."
  (let ((standard-output (generate-new-buffer " *helixel-debug-bt*")))
    (unwind-protect
        (progn
          (backtrace)
          (with-current-buffer standard-output
            (buffer-string)))
      (kill-buffer standard-output))))

(defmacro helixel--with-debug-log (context &rest condition-case-clauses)
  "Like `condition-case' but captures errors into `helixel--debug-log'.

CONTEXT is a short string label identifying the error site (e.g.
\"delimiter-bounds\", \"mc-replay\").

CONDITION-CASE-CLAUSES are one or more `condition-case' clauses:
  BODY
  (CONDITION HANDLER...)
  ...

The first element is the body form; subsequent elements are condition
handlers.  When `helixel-debug' is nil, this expands to a standard
`condition-case' — zero overhead.

When `helixel-debug' is non-nil, any non-`user-error' signal that is
caught also logs the error with full backtrace to
`helixel--debug-log'.

Example:
  ;; Before (silent swallow):
  (condition-case nil
      (risky-operation)
    (error nil))
  ;; After (debuggable):
  (helixel--with-debug-log \"risky-op\"
    (risky-operation)
    (error nil))"
  (declare (indent 1) (debug (sexp &rest (sexp body))))
  (let* ((body (car condition-case-clauses))
         (handlers (cdr condition-case-clauses))
         (ctx context))
    (if (and (not (eq ctx 'helixel-debug-log))
             (symbolp ctx))
        `(condition-case helixel--debug-err
             ,body
           ,@handlers
           (user-error nil)
           (error
            (helixel--debug-log-error ,(symbol-name ctx)
                                      helixel--debug-err)
            nil))
      `(condition-case nil ,body ,@handlers))))

;;;###autoload
(defun helixel-debug-show-log ()
  "Display the helixel debug-log buffer.
Shows captured errors with context labels, error messages,
and full backtraces.  Each entry includes a timestamp and
source buffer.  Press \\[helixel-debug-clear-log] to clear.

When `helixel-debug' is nil, the log is always empty — enable
`helixel-debug' first to capture errors."
  (interactive)
  (let ((buf (get-buffer-create "*helixel-debug-log*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (helixel-debug-log-mode)
        (if (not helixel--debug-log)
            (insert (propertize
                     (if helixel-debug
                         (concat "No errors captured yet."
                                 "  Errors appear here as they happen.\n")
                       (concat "helixel-debug is nil —"
                               " enable it to capture errors.\n"))
                     'face 'font-lock-comment-face))
          (dolist (entry (reverse helixel--debug-log))
            (let ((ctx (plist-get entry :context))
                  (err (plist-get entry :error))
                  (bt  (plist-get entry :backtrace))
                  (ts  (plist-get entry :timestamp))
                  (buf-name (buffer-name (plist-get entry :buffer))))
              (insert (propertize
                       (format "[%s] %s  —  %s\n"
                               (format-time-string "%T" ts)
                               ctx
                               (error-message-string err))
                       'face 'font-lock-warning-face))
              (insert (propertize
                       (format "  buffer: %s\n" buf-name)
                       'face 'font-lock-comment-face))
              (when bt
                (insert (propertize bt 'face 'font-lock-doc-face)))
              (insert "\n")))))
      (goto-char (point-min))
      (pop-to-buffer buf))))

(defun helixel-debug-clear-log ()
  "Clear the helixel debug-log."
  (interactive)
  (setq helixel--debug-log nil)
  (when-let* ((buf (get-buffer "*helixel-debug-log*")))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (let ((inhibit-read-only t))
          (erase-buffer)
          (insert (propertize "Log cleared.\n"
                              'face 'font-lock-comment-face))
          (goto-char (point-min))))))
  (message "helixel debug-log cleared"))

(defvar helixel-debug-log-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "q") #'quit-window)
    (define-key map (kbd "g") #'helixel-debug-show-log)
    (define-key map (kbd "C") #'helixel-debug-clear-log)
    map)
  "Keymap for `helixel-debug-log-mode'.")

(define-derived-mode helixel-debug-log-mode special-mode "Helixel-Debug-Log"
  "Major mode for viewing helixel debug-log entries.
\\<helixel-debug-log-mode-map>
\\[helixel-debug-clear-log] — clear the log.
\\[helixel-debug-show-log] — refresh the display.
\\[quit-window] — quit."
  (setq-local buffer-read-only t)
  (setq-local truncate-lines t))

(provide 'helixel-debug)
;;; helixel-debug.el ends here
