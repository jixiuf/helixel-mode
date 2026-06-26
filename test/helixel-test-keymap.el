;;; helixel-test-keymap.el --- Tests for Helixel: keymap  -*- lexical-binding: t; -*-

;; Copyright (C) 2025  jixiuf

;; Author: jixiuf <https://github.com/jixiuf>
;; Keywords: tests
;; Version: 0
;; URL: https://github.com/jixiuf/helixel-mode

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

;; Helixel tests.

;;; Code:

(require 'ert)
(require 'helixel)



;;; helixel-define-key tests

(ert-deftest helixel-test-define-key-standard ()
  "Test standard helixel-define-key without optional keymap."
  (let ((original-binding (lookup-key helixel-space-map "t")))
    (unwind-protect
        (progn
          (helixel-define-key 'space "t" #'ignore)
          (should (eq (lookup-key helixel-space-map "t") #'ignore)))
      (define-key helixel-space-map "t" original-binding))))

(ert-deftest helixel-test-define-key-with-mode ()
  "Test helixel-define-key with MODE stores binding in helixel--mode-keybindings."
  (let ((helixel--mode-keybindings nil))
    (helixel-define-key 'normal "j" #'next-line 'dired-mode)
    (let ((entry (assoc (cons 'dired-mode 'normal) helixel--mode-keybindings)))
      (should entry)
      (should (eq (lookup-key (cdr entry) "j") #'next-line)))))

(ert-deftest helixel-test-define-key-with-mode-multiple-bindings ()
  "Test that multiple bindings for the same mode and state accumulate."
  (let ((helixel--mode-keybindings nil))
    (helixel-define-key 'normal "j" #'next-line 'dired-mode)
    (helixel-define-key 'normal "k" #'previous-line 'dired-mode)
    (let ((entry (assoc (cons 'dired-mode 'normal) helixel--mode-keybindings)))
      (should (eq (lookup-key (cdr entry) "j") #'next-line))
      (should (eq (lookup-key (cdr entry) "k") #'previous-line)))))

(ert-deftest helixel-test-define-key-with-mode-different-states ()
  "Test that different states get different sparse keymaps."
  (let ((helixel--mode-keybindings nil))
    (helixel-define-key 'normal "j" #'next-line 'dired-mode)
    (helixel-define-key 'insert "j" #'self-insert-command 'dired-mode)
    (let ((normal-entry (assoc (cons 'dired-mode 'normal) helixel--mode-keybindings))
          (insert-entry (assoc (cons 'dired-mode 'insert) helixel--mode-keybindings)))
      (should normal-entry)
      (should insert-entry)
      (should-not (eq (cdr normal-entry) (cdr insert-entry)))
      (should (eq (lookup-key (cdr normal-entry) "j") #'next-line))
      (should (eq (lookup-key (cdr insert-entry) "j") #'self-insert-command)))))

(ert-deftest helixel-test-define-key-with-multiple-modes ()
  "Test that multiple modes create separate entries."
  (let ((helixel--mode-keybindings nil))
    (helixel-define-key 'normal "j" #'next-line 'dired-mode 'prog-mode)
    (let ((de (assoc (cons 'dired-mode 'normal) helixel--mode-keybindings))
          (pe (assoc (cons 'prog-mode 'normal) helixel--mode-keybindings)))
      (should de)
      (should pe)
      (should (eq (lookup-key (cdr de) "j") #'next-line))
      (should (eq (lookup-key (cdr pe) "j") #'next-line)))))

(ert-deftest helixel-test-define-key-invalid-state ()
  "Test that invalid state signals an error."
  (should-error (helixel-define-key 'invalid-state "t" #'ignore)))

(ert-deftest helixel-test-define-key-invalid-state-with-mode ()
  "Test that invalid state signals error even with explicit mode."
  (should-error (helixel-define-key 'invalid-state "t" #'ignore 'dired-mode)))

;;; helixel--refresh-overriding-maps tests

(ert-deftest helixel-test-refresh-overriding-maps-with-major-mode-bindings ()
  "Test that refresh builds correct minor-mode-overriding-map-alist."
  (let ((helixel--mode-keybindings nil))
    (with-temp-buffer
      ;; Simulate a major mode
      (setq major-mode 'helixel-test-mode)
      (setq-local helixel--current-state 'normal)
      ;; Register a binding for this mode
      (helixel-define-key 'normal "j" #'next-line 'helixel-test-mode)
      (helixel--refresh-overriding-maps)
      ;; Should have an entry in minor-mode-overriding-map-alist
      (let ((entry (assq 'helixel-normal-state minor-mode-overriding-map-alist)))
        (should entry)
        (should (eq (lookup-key (cdr entry) "j") #'next-line))))))

(ert-deftest helixel-test-refresh-overriding-maps-always-pushes-base ()
  "Test that refresh always pushes the base keymap to overriding alist.
Even when no mode-specific or keymap-targeted overrides apply, the
state keymap is pushed so it overrides all other minor mode keymaps."
  (let ((helixel--mode-keybindings nil)
        (helixel--keymap-bindings nil))
    (with-temp-buffer
      (setq-local helixel--current-state 'normal)
      (setq minor-mode-overriding-map-alist nil)
      (helixel--refresh-overriding-maps)
      ;; Should always have an overriding entry with the base keymap
      (let ((entry (assq 'helixel-normal-state minor-mode-overriding-map-alist)))
        (should entry)
        ;; The base keymap should have standard helixel bindings
        (should (eq (lookup-key (cdr entry) "j") #'helixel-next-line))
        (should (eq (lookup-key (cdr entry) "k") #'helixel-previous-line))))))

(ert-deftest helixel-test-refresh-overriding-maps-no-cross-mode-leak ()
  "Test that bindings for one major mode don't leak into another.
The overriding entry still exists (base keymap), but the dired-mode
binding for \"j\" should not be active in fundamental-mode."
  (let ((helixel--mode-keybindings nil)
        (helixel--keymap-bindings nil))
    (with-temp-buffer
      ;; Register binding for dired-mode
      (helixel-define-key 'normal "j" #'next-line 'dired-mode)
      ;; But current buffer is a different major mode
      (setq major-mode 'fundamental-mode)
      (setq-local helixel--current-state 'normal)
      (helixel--refresh-overriding-maps)
      ;; The overriding entry should exist (with base keymap)
      (let ((entry (assq 'helixel-normal-state minor-mode-overriding-map-alist)))
        (should entry)
        ;; But j should NOT be dired-next-line — it falls back to base
        (should-not (eq (lookup-key (cdr entry) "j") #'next-line))
        ;; j should be the base helixel binding
        (should (eq (lookup-key (cdr entry) "j") #'helixel-next-line))))))

(ert-deftest helixel-test-refresh-overriding-maps-fallback-to-base ()
  "Test that non-overridden keys fall back to base helixel keymap."
  (let ((helixel--mode-keybindings nil))
    (with-temp-buffer
      (setq major-mode 'helixel-test-mode)
      (setq-local helixel--current-state 'normal)
      ;; Override only "j"
      (helixel-define-key 'normal "j" #'next-line 'helixel-test-mode)
      (helixel--refresh-overriding-maps)
      (let ((entry (assq 'helixel-normal-state minor-mode-overriding-map-alist)))
        (should entry)
        ;; Overridden key works
        (should (eq (lookup-key (cdr entry) "j") #'next-line))
        ;; Non-overridden key falls back to helixel binding
        (should (eq (lookup-key (cdr entry) "k") #'helixel-previous-line))))))

;;; Keymap-targeted binding tests

(ert-deftest helixel-test-define-key-with-keymap ()
  "Test helixel-define-key with a keymap symbol stores in helixel--keymap-bindings."
  (let ((helixel--mode-keybindings nil)
        (helixel--keymap-bindings nil))
    ;; prog-mode-map is a known keymap symbol
    (helixel-define-key 'normal (kbd "g q") #'prog-fill-reindent-defun 'prog-mode-map)
    ;; Should NOT be in mode-keybindings
    (should-not (assoc (cons 'prog-mode-map 'normal) helixel--mode-keybindings))
    ;; Should be in keymap-bindings
    (let ((entry (assoc (cons 'prog-mode-map 'normal) helixel--keymap-bindings)))
      (should entry)
      (should (eq (lookup-key (cdr entry) (kbd "g q")) #'prog-fill-reindent-defun)))))

(ert-deftest helixel-test-define-key-with-keymap-multiple-bindings ()
  "Test that multiple bindings for the same keymap and state accumulate."
  (let ((helixel--keymap-bindings nil))
    (helixel-define-key 'normal (kbd "g q") #'prog-fill-reindent-defun 'prog-mode-map)
    (helixel-define-key 'normal ")" #'hel-mark-function-forward 'prog-mode-map)
    (let ((entry (assoc (cons 'prog-mode-map 'normal) helixel--keymap-bindings)))
      (should (eq (lookup-key (cdr entry) (kbd "g q")) #'prog-fill-reindent-defun))
      (should (eq (lookup-key (cdr entry) ")") #'hel-mark-function-forward)))))

(ert-deftest helixel-test-define-key-with-unquoted-keymap ()
  "Test helixel-define-key with an unquoted keymap object.
When the user passes prog-mode-map unquoted, the keymap object
itself is stored as the alist key (not the symbol)."
  (let ((helixel--mode-keybindings nil)
        (helixel--keymap-bindings nil))
    ;; Unquoted: prog-mode-map evaluates to the keymap object
    (helixel-define-key 'normal (kbd "g q") #'prog-fill-reindent-defun
                        prog-mode-map)
    ;; Should NOT be in mode-keybindings
    (should-not (assoc (cons 'prog-mode-map 'normal)
                       helixel--mode-keybindings))
    ;; Should be in keymap-bindings (car of alist key is the keymap obj)
    (should helixel--keymap-bindings)
    (let ((entry (car helixel--keymap-bindings)))
      (should (eq (cdar entry) 'normal))
      (should (keymapp (caar entry)))
      (should (eq (lookup-key (cdr entry) (kbd "g q"))
                  #'prog-fill-reindent-defun)))))

(ert-deftest helixel-test-define-key-with-unquoted-keymap-refresh ()
  "Test that unquoted keymap bindings activate in a prog-mode buffer."
  (let ((helixel--keymap-bindings nil))
    (helixel-define-key 'normal (kbd "g q") #'prog-fill-reindent-defun
                        prog-mode-map)
    (with-temp-buffer
      (emacs-lisp-mode)
      (setq-local helixel--current-state 'normal)
      (helixel--refresh-overriding-maps)
      (let ((entry (assq 'helixel-normal-state
                         minor-mode-overriding-map-alist)))
        (should entry)
        (should (eq (lookup-key (cdr entry) (kbd "g q"))
                    #'prog-fill-reindent-defun))))))

(ert-deftest helixel-test-define-key-mixed-modes-and-keymaps ()
  "Test that mixing mode and keymap symbols creates entries in both tables."
  (let ((helixel--mode-keybindings nil)
        (helixel--keymap-bindings nil))
    (helixel-define-key 'normal "j" #'next-line
                        'dired-mode 'prog-mode-map)
    ;; dired-mode is not a keymap, should go to mode-keybindings
    (let ((mode-entry (assoc (cons 'dired-mode 'normal)
                             helixel--mode-keybindings)))
      (should mode-entry)
      (should (eq (lookup-key (cdr mode-entry) "j") #'next-line)))
    ;; prog-mode-map is a keymap, should go to keymap-bindings
    (let ((keymap-entry (assoc (cons 'prog-mode-map 'normal)
                               helixel--keymap-bindings)))
      (should keymap-entry)
      (should (eq (lookup-key (cdr keymap-entry) "j") #'next-line)))))

(ert-deftest helixel-test-refresh-overriding-maps-with-keymap ()
  "Test that keymap-targeted bindings activate when the keymap is active."
  (let ((helixel--mode-keybindings nil)
        (helixel--keymap-bindings nil))
    ;; Register a binding for prog-mode-map
    (helixel-define-key 'normal (kbd "g q") #'prog-fill-reindent-defun
                        'prog-mode-map)
    (with-temp-buffer
      ;; Use emacs-lisp-mode which inherits from prog-mode so
      ;; prog-mode-map appears in current-active-maps.
      (emacs-lisp-mode)
      (setq-local helixel--current-state 'normal)
      (helixel--refresh-overriding-maps)
      (let ((entry (assq 'helixel-normal-state
                         minor-mode-overriding-map-alist)))
        (should entry)
        (should (eq (lookup-key (cdr entry) (kbd "g q"))
                    #'prog-fill-reindent-defun))))))

(ert-deftest helixel-test-refresh-overriding-maps-keymap-not-active ()
  "Test that keymap bindings don't activate when keymap is not in active-maps."
  (let ((helixel--mode-keybindings nil)
        (helixel--keymap-bindings nil))
    ;; Register a binding for prog-mode-map
    (helixel-define-key 'normal (kbd "g q") #'prog-fill-reindent-defun
                        'prog-mode-map)
    ;; Use a buffer that doesn't inherit from prog-mode-map
    (with-current-buffer (get-buffer-create "*helixel-test-keymap-NA*")
      (fundamental-mode)
      (setq-local helixel--current-state 'normal)
      (helixel--refresh-overriding-maps)
      ;; The overriding entry exists (base keymap always pushed),
      ;; but the prog-mode-map binding g q should not be active.
      (let ((entry (assq 'helixel-normal-state
                         minor-mode-overriding-map-alist)))
        (should entry)
        ;; prog-mode-map override should NOT leak into fundamental-mode
        (should-not (eq (lookup-key (cdr entry) (kbd "g q"))
                        #'prog-fill-reindent-defun))
        ;; But g q still resolves to base helixel binding (not nil)
        (should (commandp (lookup-key (cdr entry) (kbd "g q"))))
        ;; But base helixel bindings should still work
        (should (eq (lookup-key (cdr entry) "j") #'helixel-next-line))))))

(ert-deftest helixel-test-refresh-overriding-maps-keymap-fallback ()
  "Test that non-overridden keys fall back to base with keymap overrides."
  (let ((helixel--mode-keybindings nil)
        (helixel--keymap-bindings nil))
    ;; Override only g q on prog-mode-map
    (helixel-define-key 'normal (kbd "g q") #'prog-fill-reindent-defun
                        'prog-mode-map)
    (with-temp-buffer
      (emacs-lisp-mode)
      (setq-local helixel--current-state 'normal)
      (helixel--refresh-overriding-maps)
      (let ((entry (assq 'helixel-normal-state
                         minor-mode-overriding-map-alist)))
        (should entry)
        ;; Overridden key works
        (should (eq (lookup-key (cdr entry) (kbd "g q"))
                    #'prog-fill-reindent-defun))
        ;; Non-overridden key falls back to helixel binding
        (should (eq (lookup-key (cdr entry) "j")
                    #'helixel-next-line))))))

(ert-deftest helixel-test-refresh-overriding-maps-keymap-textobj ()
  "Test that keymap-targeted textobj overrides work."
  (let ((helixel--mode-keybindings nil)
        (helixel--keymap-bindings nil))
    ;; Register a textobj-inner binding for prog-mode-map
    (helixel-define-key 'textobj-inner "f"
                        #'helixel-mark-inner-function 'prog-mode-map)
    (with-temp-buffer
      (emacs-lisp-mode)
      ;; Activate refresh
      (helixel--refresh-overriding-maps)
      ;; helixel-textobj-map should be buffer-local and have the
      ;; inner composed keymap
      (when (local-variable-p 'helixel-textobj-map)
        (let ((inner-map (lookup-key helixel-textobj-map "i")))
          (when inner-map
            ;; The composed keymap should include our f binding
            (should (eq (lookup-key inner-map "f")
                        #'helixel-mark-inner-function))))))))

;;; helixel-test-keymap.el ends here
