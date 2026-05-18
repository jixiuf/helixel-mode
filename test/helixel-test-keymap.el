;;; helixel-test-keymap.el --- Tests for Helixel: keymap  -*- lexical-binding: t; -*-

;; Copyright (C) 2025  jixiuf

;; Author: jixiuf
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

(ert-deftest helixel-test-refresh-overriding-maps-clears-when-no-bindings ()
  "Test that refresh clears overriding alist when no bindings apply."
  (let ((helixel--mode-keybindings nil))
    (with-temp-buffer
      (setq-local helixel--current-state 'normal)
      ;; Pre-populate with a stale entry
      (setq minor-mode-overriding-map-alist
            (list (cons 'helixel-normal-state (make-sparse-keymap))))
      (helixel--refresh-overriding-maps)
      ;; Should have cleared the entry
      (should-not (assq 'helixel-normal-state minor-mode-overriding-map-alist)))))

(ert-deftest helixel-test-refresh-overriding-maps-no-cross-mode-leak ()
  "Test that bindings for one major mode don't leak into another."
  (let ((helixel--mode-keybindings nil))
    (with-temp-buffer
      ;; Register binding for dired-mode
      (helixel-define-key 'normal "j" #'next-line 'dired-mode)
      ;; But current buffer is a different major mode
      (setq major-mode 'fundamental-mode)
      (setq-local helixel--current-state 'normal)
      (helixel--refresh-overriding-maps)
      ;; Should have no overriding entry
      (should-not (assq 'helixel-normal-state minor-mode-overriding-map-alist)))))

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

;;; helixel-test-keymap.el ends here
