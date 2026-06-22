;;; helixel-test-common.el --- Shared test helpers  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

;; Author: jixiuf <https://github.com/jixiuf>
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Keywords: tests

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

;; Shared test helpers used across multiple test files.

;;; Code:

(require 'ert)

(defmacro helixel-test-with-buffer (content &rest body)
  "Execute BODY in a temp buffer with CONTENT and transient-mark-mode on.
Buffer starts at point 1 by default.  Internal hooks are activated
without enabling `helixel-mode' (avoids state-machine side-effects
in tests).

CONTENT can be:
  \"some text\"             — insert text, start at point 1
  \='(:text \"...\" :start N) — insert text, start at position N
  \='(:text \"...\")          — insert text, start at point 1"
  (declare (indent 1))
  (let ((text content)
        (start-pos 1))
    (when (and (consp content)
               (or (keywordp (car-safe content))
                   (and (eq (car-safe content) 'quote)
                        (consp (cdr content))
                        (keywordp (car-safe (cadr content))))))
      (let ((plist (if (eq (car-safe content) 'quote) (cadr content) content)))
        (setq text (plist-get plist :text)
              start-pos (or (plist-get plist :start) 1))))
    `(with-temp-buffer
       (transient-mark-mode 1)
       (insert ,text)
       (goto-char ,start-pos)
       (helixel--activate-all-hooks)
       (unwind-protect
           (progn ,@body)
         (helixel--deactivate-all-hooks)))))

(defmacro helixel-test-simulate (&rest commands)
  "Execute COMMANDS in sequence with correct \=`last-command' tracking.

Each element is a form like (COMMAND ARGS...).  The first command
runs with \=`last-command' nil; each subsequent command runs with
\=`last-command' set to the previous command's symbol.

Example:
  (helixel-test-simulate
    (helixel-mark-inner-word)
    (helixel-kill))
  ;; Equivalent to:
  ;;   (setq last-command nil this-command \='helixel-mark-inner-word)
  ;;   (helixel-mark-inner-word)
  ;;   (setq last-command \='helixel-mark-inner-word this-command \='helixel-kill)
  ;;   (helixel-kill)"
  (declare (indent 0))
  (let ((prev nil)
        (forms nil))
    (dolist (cmd-form commands)
      (let ((cmd-sym (car cmd-form)))
        (push `(setq last-command ,prev this-command ',cmd-sym)
              forms)
        (push `(,cmd-sym ,@(cdr cmd-form)) forms)
        (setq prev `(quote ,cmd-sym))))
    `(progn ,@(nreverse forms))))

(defmacro helixel-test-simulate-command (cmd &rest args)
  "Execute CMD as if interactively invoked as the first command.
Sets `last-command' nil and `this-command' to CMD before calling.

Use `helixel-test-simulate' for multi-command sequences."
  (declare (indent 1))
  `(progn
     (setq last-command nil this-command ',cmd)
     (,cmd ,@args)))

(provide 'helixel-test-common)
;;; helixel-test-common.el ends here
