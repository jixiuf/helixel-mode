;;; helixel-test-repeat-new.el --- Tests for new dot-repeat features  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf
;; Author: jixiuf
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
;;
;; Tests for the unified dot-repeat features:
;; - movement (w/e/b) repeat
;; - textobj (iw/aw) repeat
;; - find-char (f/t) repeat
;; - chain with movement/textobj selections
;; - zero-length search dot-repeat

;;; Code:

(require 'ert)
(require 'helixel)
(require 'helixel-search)

(defmacro helixel-test-with-buffer (content &rest body)
  "Execute BODY in a temp buffer with CONTENT and transient-mark-mode on."
  (declare (indent 1))
  `(with-temp-buffer
     (transient-mark-mode 1)
     (insert ,content)
     (goto-char 1)
     ,@body))

;; ── Movement dot-repeat (w/e/b) ──

(ert-deftest helixel-test-repeat-movement-wd-dot ()
  "wd then . deletes the next word."
  (helixel-test-with-buffer "hello world foo bar"
    (setq helixel--current-state 'normal)
    (helixel-forward-word-start)
    (setq last-command nil this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (string= (buffer-string) "world foo bar"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "foo bar"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "bar"))))

(ert-deftest helixel-test-repeat-movement-wd-3dot ()
  "3. after wd repeats the delete-word 3 times."
  (helixel-test-with-buffer "a b c d e f"
    (setq helixel--current-state 'normal)
    (helixel-forward-word-start)
    (setq last-command nil this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (string= (buffer-string) "b c d e f"))
    (helixel-repeat-edit 3)
    (should (string= (buffer-string) "e f"))))


;; ── Textobj dot-repeat ──

(ert-deftest helixel-test-repeat-textobj-diw-dot ()
  "diw then . deletes inner word each time."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 3)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (string= (buffer-string) " world foo"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "  foo"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "  "))))

(ert-deftest helixel-test-repeat-textobj-ciw-dot ()
  "ciwXXX then . changes the next word to XXX."
  (helixel-test-with-buffer "hello world bar"
    (goto-char 3)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-change-thing-at-point)
    (helixel-change-thing-at-point)
    (insert "XXX")
    (helixel-insert-exit)
    (should (string= (buffer-string) "XXX world bar"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "XXX XXX bar"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "XXX XXX XXX"))))

;; ── Find-char dot-repeat ──

(ert-deftest helixel-test-repeat-findchar-fxd-dot ()
  "f x d then . deletes up to next x."
  (helixel-test-with-buffer "hello x world x foo"
    (helixel-find-next-char ?x)
    (setq last-command nil this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (string= (buffer-string) " world x foo"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) " foo"))
    ;; . with no more 'x' prints message, doesn't error
    (helixel-repeat-edit)
    (should (string= (buffer-string) " foo"))))

(ert-deftest helixel-test-repeat-findchar-txd-dot ()
  "t x d then . deletes up to (not including) next x."
  (helixel-test-with-buffer "hello x world x foo"
    (helixel-find-till-char ?x)
    (setq last-command nil this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (string= (buffer-string) "x world x foo"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "x foo"))))

;;; helixel-test-repeat-new.el ends here
