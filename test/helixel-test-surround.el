;;; helixel-test-surround.el --- Tests for Helixel: surround  -*- lexical-binding: t; -*-

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

;; Surround tests.  Regression coverage for issue #12: surround
;; operations must accept a pending textobj selection (the documented
;; md/mr-after-textobj flow) without a wrong-type-argument error.

;;; Code:

(require 'ert)
(require 'helixel)
(require 'helixel-test-common)

;;; Generic delimiter accessor

(ert-deftest helixel-test-surround-generic-delimiter-dispatch ()
  "Test `helixel-sel-delimiter' dispatch across sel kinds."
  (should (null (helixel-sel-delimiter nil)))
  ;; Non-delimited sel kinds return nil.
  (should (null (helixel-sel-delimiter (make-helixel-line-sel))))
  ;; Surround sel carries its delimiter.
  (let ((d (helixel-make-pair-delimiter ?\[ ?\])))
    (should (eq (helixel-sel-delimiter
                 (make-helixel-surround-sel :delimiter d))
                d))
    ;; Textobj sel carries the same slot for pair selections.
    (should (eq (helixel-sel-delimiter
                 (make-helixel-textobj-sel
                  :command 'helixel-mark-inner-bracket
                  :delimiter d))
                d)))
  ;; Non-pair textobjs (no delimiter) return nil.
  (should (null (helixel-sel-delimiter
                 (make-helixel-textobj-sel
                  :command 'helixel-mark-inner-word)))))

;;; md after textobj selection (issue #12)

(ert-deftest helixel-test-surround-delete-after-textobj ()
  "Test `helixel-surround-delete' after an inner-bracket selection."
  (helixel-test-with-buffer '(:text "[foo]" :start 3)
    (call-interactively #'helixel-mark-inner-bracket)
    (should (helixel-textobj-sel-p helixel--pending-sel))
    (call-interactively #'helixel-surround-delete)
    (should (string= (buffer-string) "foo"))))

(ert-deftest helixel-test-surround-delete-after-a-textobj ()
  "Test `helixel-surround-delete' after an a-bracket selection."
  (helixel-test-with-buffer '(:text "[foo] bar" :start 3)
    (call-interactively #'helixel-mark-a-bracket)
    (call-interactively #'helixel-surround-delete)
    (should (string= (buffer-string) "foo bar"))))

(ert-deftest helixel-test-surround-delete-replay-runner ()
  "Test replay of a surround-delete recorded from a textobj sel.
Directly invokes `helixel-action-replay' on the recorded tx (dot
repeat's advance targeting is covered separately).
Regression: the recorded sel is a textobj sel, so the runner must
read the delimiter via `helixel-sel-delimiter' (issue #12)."
  (helixel-test-with-buffer '(:text "[ab] [cd]" :start 2)
    (call-interactively #'helixel-mark-inner-bracket)
    (call-interactively #'helixel-surround-delete)
    (should (string= (buffer-string) "ab [cd]"))
    ;; Move into the second pair and replay the recorded tx.
    (goto-char 5)
    (call-interactively #'helixel-mark-inner-bracket)
    (deactivate-mark)
    (helixel-action-replay helixel-last-action)
    (should (string= (buffer-string) "ab cd"))))

(ert-deftest helixel-test-surround-execute-pending-textobj ()
  "Test the pending-op retry flow after a textobj selection (issue #12).
`md' with no surround info prompts for a target; the after-select
hook then re-invokes the op with the freshly selected textobj."
  (helixel-test-with-buffer '(:text "[foo]" :start 3)
    (let ((called 0))
      ;; `let*' (not `let'): the lambda must see `called'.  This
      ;; Emacs snapshot mis-captures lambdas placed in the same
      ;; `let' binding form that binds the variable they reference.
      (let* ((helixel--pending-surround-op
              (lambda ()
                (cl-incf called)
                (helixel-surround-delete))))
        (call-interactively #'helixel-mark-inner-bracket)
        (should (= called 1))
        (should (null helixel--pending-surround-op))
        (should (string= (buffer-string) "foo"))))))

(ert-deftest helixel-test-surround-execute-pending-no-delimiter ()
  "Test that the pending op is skipped for non-delimited textobjs."
  (helixel-test-with-buffer '(:text "foo" :start 2)
    (let ((called 0))
      (let* ((helixel--pending-surround-op (lambda () (cl-incf called))))
        (call-interactively #'helixel-mark-inner-word)
        (should (= called 0))
        (should (null helixel--pending-surround-op))))))

(ert-deftest helixel-test-surround-execute-pending-issue12-repro ()
  "Direct repro from issue #12: no wrong-type-argument, op runs once."
  (helixel-test-with-buffer '(:text "[foo]" :start 3)
    (let ((called 0))
      (let* ((helixel--pending-sel
              (make-helixel-textobj-sel
               :command 'helixel-mark-inner-bracket
               :delimiter (helixel-make-pair-delimiter ?\[ ?\])))
             (helixel--pending-surround-op
              (lambda ()
                (cl-incf called)
                (helixel-surround-delete))))
        (helixel--surround-execute-pending)
        (should (= called 1))
        (should (string= (buffer-string) "foo"))))))

;;; mr after textobj selection

(ert-deftest helixel-test-surround-replace-after-textobj ()
  "Test `helixel-surround-replace' after an inner-bracket selection."
  (helixel-test-with-buffer '(:text "[foo]" :start 3)
    (call-interactively #'helixel-mark-inner-bracket)
    (cl-letf (((symbol-function 'read-char)
               (lambda (&rest _) ?\{)))
      (call-interactively #'helixel-surround-replace))
    (should (string= (buffer-string) "{foo}"))))

(provide 'helixel-test-surround)
;;; helixel-test-surround.el ends here
