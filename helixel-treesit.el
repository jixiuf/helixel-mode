;;; helixel-treesit.el --- Tree-sitter integration for helixel-mode (facade) -*- lexical-binding: t; -*-

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
;; OPT-IN tree-sitter layer for helixel-mode — facade module.
;;
;; Requires helixel-treesit-core (foundation) and
;; helixel-treesit-commands (all commands).  Provides
;; `helixel-treesit-setup' as the single entry point.
;;
;; Usage:
;;   ;; Automatic — registered on `helixel-mode-on-hook'.
;;   ;; Call manually only if treesit is installed after
;;   ;; helixel-mode is already active (idempotent):
;;   ;; (helixel-treesit-setup)

;;; Code:

(require 'helixel-treesit-core)
(require 'helixel-treesit-commands)

;; Cross-module declarations
(declare-function helixel-define-key "helixel-keymap" t t)
(declare-function helixel-register-motion-reverse "helixel-core" t t)
(declare-function helixel-register-motion-repeater "helixel-core" t t)
(declare-function helixel--motion-eff-cmd "helixel-move" t t)
(declare-function helixel--motion-invoke "helixel-move" t t)
(declare-function helixel--motion-reverse-lookup "helixel-move" t t)
(declare-function helixel--track-visual-move "helixel-move" t t)
(declare-function helixel--clear-highlights "helixel-state" t t)

;; Dispatch vars used by move.el — declared here for setup.
(defvar helixel-forward-outer-function-function)
(defvar helixel-backward-outer-function-function)
(defvar helixel-mark-inner-function-function)
(defvar helixel-mark-a-function-function)
(defvar helixel-mark-inner-comment-function)
(defvar helixel-mark-a-comment-function)
(defvar helixel-backward-outer-comment-function)
(defvar helixel-forward-outer-comment-function)
(defvar helixel-backward-inner-comment-function)
(defvar helixel-forward-inner-comment-function)

;; ----------------------------------------------------------------------
;; Type dispatch variable table
;; ----------------------------------------------------------------------

;; Plain sibling impls for dispatch — referenced by dispatch table.
(declare-function helixel-ts--sibling-move
                  "helixel-treesit-commands")

(defun helixel-ts--sibling-move-t (count)
  "Move to next sibling (plain impl, for dispatch vars).
With COUNT, repeat that many times."
  (helixel-ts--sibling-move t count))
(defun helixel-ts--sibling-move-nil (count)
  "Move to previous sibling (plain impl, for dispatch vars).
With COUNT, repeat that many times."
  (helixel-ts--sibling-move nil count))

(defconst helixel-ts--type-dispatch-table
  ;; Each entry: (TYPE . ((MOVE-VAR . PLAIN-IMPL) ...))
  ;; TYPE is a string like "class", "parameter", etc.
  ;; MOVE-VAR is the buffer-local dispatch variable (symbol).
  ;; PLAIN-IMPL is the plain function (no tracking).
  `(("function"
     (helixel-forward-outer-function-function
      . helixel-ts--move-forward-outer-function)
     (helixel-backward-outer-function-function
      . helixel-ts--move-backward-outer-function)
     (helixel-mark-inner-function-function
      . helixel-ts-mark-inner-function)
     (helixel-mark-a-function-function
      . helixel-ts-mark-a-function))
    ("class"
     (helixel-forward-outer-class-function
      . helixel-ts--move-forward-outer-class)
     (helixel-backward-outer-class-function
      . helixel-ts--move-backward-outer-class)
     (helixel-forward-inner-class-function
      . helixel-ts--move-forward-inner-class)
     (helixel-backward-inner-class-function
      . helixel-ts--move-backward-inner-class))
    ("parameter"
     (helixel-forward-outer-parameter-function
      . helixel-ts--move-forward-outer-parameter)
     (helixel-backward-outer-parameter-function
      . helixel-ts--move-backward-outer-parameter)
     (helixel-forward-inner-parameter-function
      . helixel-ts--move-forward-inner-parameter)
     (helixel-backward-inner-parameter-function
      . helixel-ts--move-backward-inner-parameter))
    ("loop"
     (helixel-forward-outer-loop-function
      . helixel-ts--move-forward-outer-loop)
     (helixel-backward-outer-loop-function
      . helixel-ts--move-backward-outer-loop)
     (helixel-forward-inner-loop-function
      . helixel-ts--move-forward-inner-loop)
     (helixel-backward-inner-loop-function
      . helixel-ts--move-backward-inner-loop))
    ("conditional"
     (helixel-forward-outer-conditional-function
      . helixel-ts--move-forward-outer-conditional)
     (helixel-backward-outer-conditional-function
      . helixel-ts--move-backward-outer-conditional)
     (helixel-forward-inner-conditional-function
      . helixel-ts--move-forward-inner-conditional)
     (helixel-backward-inner-conditional-function
      . helixel-ts--move-backward-inner-conditional))
    ("comment"
     (helixel-mark-inner-comment-function
      . helixel-ts-mark-inner-comment)
     (helixel-mark-a-comment-function
      . helixel-ts-mark-a-comment)
     (helixel-backward-outer-comment-function
      . helixel-ts--move-backward-outer-comment)
     (helixel-forward-outer-comment-function
      . helixel-ts--move-forward-outer-comment)
     (helixel-backward-inner-comment-function
      . helixel-ts--move-backward-inner-comment)
     (helixel-forward-inner-comment-function
      . helixel-ts--move-forward-inner-comment))
    ("sibling"
     (helixel-forward-outer-sibling-function
      . helixel-ts--sibling-move-t)
     (helixel-backward-outer-sibling-function
      . helixel-ts--sibling-move-nil)))
  "Dispatch table mapping types to (VAR . PLAIN-IMPL) pairs.
Each entry's VAR is set buffer-locally by `helixel-ts--install-nav-vars'.")

;; ----------------------------------------------------------------------
;; Dispatch var generation macros
;; ----------------------------------------------------------------------

(defmacro helixel-ts--define-nav-dispatch (name)
  "Define forward/backward nav dispatch commands for NAME.
Generates buffer-local dispatch vars and `helixel-define-command' wrappers.
The command wrappers record motion for comma-repeat; the dispatch vars
point to plain treesit impls so there is no double-tracking."
  (declare (indent 1))
  (let* ((next-cmd  (intern (format "helixel-forward-outer-%s" name)))
         (prev-cmd  (intern (format "helixel-backward-outer-%s" name)))
         (next-var  (intern (format "helixel-forward-outer-%s-function" name)))
         (prev-var  (intern (format "helixel-backward-outer-%s-function" name)))
         (subcat (intern name)))
    `(progn
       (defvar-local ,next-var nil
         ,(format "Buffer-local override for `%s'." next-cmd))
       (defvar-local ,prev-var nil
         ,(format "Buffer-local override for `%s'." prev-cmd))
       (helixel-define-command ,next-cmd
           (:category movement :subcat ,subcat
                      :params (&optional count)
                      :motion-extra (list :reverse-command ',prev-cmd))
         ,(format "Move to next %s." name)
         (if ,next-var
             (funcall ,next-var (or count 1))
           (user-error "No tree-sitter parser in this buffer")))
       (helixel-define-command ,prev-cmd
           (:category movement :subcat ,subcat
                      :params (&optional count)
                      :motion-extra (list :reverse-command ',next-cmd))
         ,(format "Move to previous %s." name)
         (if ,prev-var
             (funcall ,prev-var (or count 1))
           (user-error "No tree-sitter parser in this buffer"))))))

(defmacro helixel-ts--define-inner-dispatch (name)
  "Define inner move dispatch commands for NAME.
Generates buffer-local dispatch vars and `helixel-define-command' wrappers."
  (declare (indent 1))
  (let* ((left-cmd  (intern (format "helixel-backward-inner-%s" name)))
         (right-cmd (intern (format "helixel-forward-inner-%s" name)))
         (left-var  (intern (format "helixel-backward-inner-%s-function" name)))
         (right-var (intern (format "helixel-forward-inner-%s-function" name)))
         (subcat (intern name)))
    `(progn
       (defvar-local ,left-var nil
         ,(format "Buffer-local override for `%s'." left-cmd))
       (defvar-local ,right-var nil
         ,(format "Buffer-local override for `%s'." right-cmd))
       (helixel-define-command ,left-cmd
           (:category movement :subcat ,subcat
                      :params (&optional count)
                      :motion-extra (list :reverse-command ',right-cmd))
         ,(format "Move to inner start of current/previous %s." name)
         (if ,left-var
             (funcall ,left-var (or count 1))
           (user-error "No tree-sitter parser in this buffer")))
       (helixel-define-command ,right-cmd
           (:category movement :subcat ,subcat
                      :params (&optional count)
                      :motion-extra (list :reverse-command ',left-cmd))
         ,(format "Move to inner end of current/next %s." name)
         (if ,right-var
             (funcall ,right-var (or count 1))
           (user-error "No tree-sitter parser in this buffer"))))))

;; ── Generate dispatch commands ──

(helixel-ts--define-nav-dispatch "class")
(helixel-ts--define-nav-dispatch "parameter")
(helixel-ts--define-nav-dispatch "conditional")
(helixel-ts--define-nav-dispatch "loop")
(helixel-ts--define-nav-dispatch "sibling")

(helixel-ts--define-inner-dispatch "function")
(helixel-ts--define-inner-dispatch "class")
(helixel-ts--define-inner-dispatch "parameter")
(helixel-ts--define-inner-dispatch "loop")
(helixel-ts--define-inner-dispatch "conditional")

;; ----------------------------------------------------------------------
;; Install dispatch vars in treesit buffers
;; ----------------------------------------------------------------------

(defvar helixel-ts--known-ts-modes-cache nil
  "Cached result of `helixel-ts--known-ts-modes'.")

(defun helixel-ts--known-ts-modes ()
  "Return list of known tree-sitter major mode symbols.
Result is memoized since atom scan is expensive."
  (or helixel-ts--known-ts-modes-cache
      (let ((modes nil))
        (mapatoms (lambda (s)
                    (and (string-suffix-p "-ts-mode" (symbol-name s))
                         (commandp s)
                         (push s modes))))
        (setq helixel-ts--known-ts-modes-cache (nreverse modes)))))

(defun helixel-ts--install-nav-vars ()
  "Set buffer-local dispatch variables to treesit implementations.
Only activates when captures are available for this buffer.
All dispatch vars are set via `helixel-ts--type-dispatch-table'."
  (when (helixel-ts--captures-available-p)
    (dolist (entry helixel-ts--type-dispatch-table)
      (dolist (pair (cdr entry))
        (set (make-local-variable (car pair)) (cdr pair))))))

(defun helixel-ts--maybe-install-nav-vars ()
  "Run `helixel-ts--install-nav-vars' when treesit is ready."
  (helixel-ts--install-nav-vars))

(defvar helixel-ts--nav-vars-installed nil
  "Non-nil when `helixel-ts--maybe-install-nav-vars' is in hooks.")

;; ----------------------------------------------------------------------
;; Setup
;; ----------------------------------------------------------------------

;;;###autoload
(defun helixel-treesit-setup ()
  "Enable helixel treesit text objects and motions.
Binds mode-specific keys in treesit-enabled buffers.
Idempotent; safe to call multiple times.

This function is registered on `helixel-mode-on-hook', so it
runs automatically when `helixel-mode' activates.  Call it
manually only if you install tree-sitter support after
`helixel-mode' is already active."
  (interactive)
  (unless (fboundp 'helixel-define-key)
    (require 'helixel-keymap))
  ;; ── Reverse-motion pairs ──
  (let ((pairs
         `((helixel-ts-forward-outer-parameter
            . helixel-ts-backward-outer-parameter)
           (helixel-ts-forward-outer-class
            . helixel-ts-backward-outer-class)
           (helixel-ts-forward-outer-function
            . helixel-ts-backward-outer-function)
           (helixel-ts-forward-outer-conditional
            . helixel-ts-backward-outer-conditional)
           (helixel-ts-forward-outer-loop
            . helixel-ts-backward-outer-loop)
           (helixel-ts-grow-selection
            . helixel-ts-shrink-selection)
           (helixel-ts-forward-outer-sibling
            . helixel-ts-backward-outer-sibling)
           (helixel-ts-forward-inner-function
            . helixel-ts-backward-inner-function)
           (helixel-ts-forward-inner-class
            . helixel-ts-backward-inner-class)
           (helixel-ts-forward-inner-parameter
            . helixel-ts-backward-inner-parameter)
           (helixel-ts-forward-inner-loop
            . helixel-ts-backward-inner-loop)
           (helixel-ts-forward-inner-conditional
            . helixel-ts-backward-inner-conditional)
           ,@(mapcar (lambda (name)
                       `(,(intern (format "helixel-forward-outer-%s" name))
                         .
                         ,(intern (format "helixel-backward-outer-%s" name))))
                     '("class" "parameter" "conditional" "loop" "sibling"))
           ,@(mapcar (lambda (name)
                       `(,(intern (format "helixel-forward-inner-%s" name))
                         .
                         ,(intern (format "helixel-backward-inner-%s" name))))
                     '("function" "class" "parameter" "loop" "conditional")))))
    (dolist (pair pairs)
      (helixel-register-motion-reverse (car pair) (cdr pair))
      (helixel-register-motion-reverse (cdr pair) (car pair))))
  ;; ── Motion repeater: treesit-specific ──
  (dolist (subcat '(function class parameter comment
                             loop conditional sibling grow-shrink))
    (helixel-register-motion-repeater 'movement subcat
                                      #'helixel-ts--repeat-treesit-motion))
  ;; ── Text objects key bindings ──
  (helixel-define-key 'textobj-inner "y" #'helixel-ts-mark-inner-class)
  (helixel-define-key 'textobj-outer "y" #'helixel-ts-mark-a-class)
  (helixel-define-key 'textobj-inner "," #'helixel-ts-mark-inner-parameter)
  (helixel-define-key 'textobj-outer "," #'helixel-ts-mark-a-parameter)
  (helixel-define-key 'textobj-inner "l" #'helixel-ts-mark-inner-loop)
  (helixel-define-key 'textobj-outer "l" #'helixel-ts-mark-a-loop)
  (helixel-define-key 'textobj-inner "e" #'helixel-ts-mark-inner-conditional)
  (helixel-define-key 'textobj-outer "e" #'helixel-ts-mark-a-conditional)
  ;; ── Tree motions (mode-specific) ──
  (dolist (m (helixel-ts--known-ts-modes))
    (helixel-define-key 'normal (kbd "M-o")
                        #'helixel-ts-grow-selection m)
    (helixel-define-key 'normal (kbd "M-i")
                        #'helixel-ts-shrink-selection m))
  ;; ── Nav dispatch vars — auto-set in TS buffers ──
  (unless helixel-ts--nav-vars-installed
    (add-hook 'after-change-major-mode-hook
              #'helixel-ts--maybe-install-nav-vars)
    (setq helixel-ts--nav-vars-installed t))
  ;; ── Navigation key bindings ──
  (when (and (boundp 'helixel-right-map) (keymapp helixel-right-map)
             (boundp 'helixel-left-map) (keymapp helixel-left-map))
    (define-key helixel-right-map "y" #'helixel-forward-outer-class)
    (define-key helixel-left-map "y" #'helixel-backward-outer-class)
    (define-key helixel-right-map "," #'helixel-forward-outer-parameter)
    (define-key helixel-left-map "," #'helixel-backward-outer-parameter)
    (define-key helixel-right-map "e" #'helixel-forward-outer-conditional)
    (define-key helixel-left-map "e" #'helixel-backward-outer-conditional)
    (define-key helixel-right-map "l" #'helixel-forward-outer-loop)
    (define-key helixel-left-map "l" #'helixel-backward-outer-loop)
    (define-key helixel-right-map "o" #'helixel-forward-outer-sibling)
    (define-key helixel-left-map "o" #'helixel-backward-outer-sibling))
  ;; ── Inner prefix maps ──
  (when (and (boundp 'helixel-inner-right-map) (keymapp helixel-inner-right-map)
             (boundp 'helixel-inner-left-map) (keymapp helixel-inner-left-map))
    (define-key helixel-inner-left-map "f" #'helixel-backward-inner-function)
    (define-key helixel-inner-right-map "f" #'helixel-forward-inner-function)
    (define-key helixel-inner-left-map "y" #'helixel-backward-inner-class)
    (define-key helixel-inner-right-map "y" #'helixel-forward-inner-class)
    (define-key helixel-inner-left-map "," #'helixel-backward-inner-parameter)
    (define-key helixel-inner-right-map "," #'helixel-forward-inner-parameter)
    (define-key helixel-inner-left-map "l" #'helixel-backward-inner-loop)
    (define-key helixel-inner-right-map "l" #'helixel-forward-inner-loop)
    (define-key helixel-inner-left-map "e" #'helixel-backward-inner-conditional)
    (define-key helixel-inner-right-map "e" #'helixel-forward-inner-conditional))
  ;; Install vars in current buffer
  (helixel-ts--install-nav-vars))

(provide 'helixel-treesit)
;;; helixel-treesit.el ends here
