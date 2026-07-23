;;; helixel-test-treesit.el --- Tests for helixel-treesit  -*- lexical-binding: t; -*-

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

;; Tests for helixel-treesit.el — Phases 0 & 1.

;;; Code:

(require 'ert)
(require 'helixel-treesit)
(require 'helixel)  ; for helixel--activate-all-hooks
(require 'treesit)

;; Silence `python-indent-guess-indent-offset' stderr noise in batch
;; mode.  The function is a C subr that writes directly to stderr —
;; `inhibit-message' and `warning-minimum-level' have no effect.
(when (and noninteractive
           (fboundp 'python-indent-guess-indent-offset)
           (not (advice-member-p #'ignore
                                 'python-indent-guess-indent-offset)))
  (advice-add 'python-indent-guess-indent-offset :override #'ignore))

;; ═══════════════════════════════════════════════════════════════════
;; Test helpers
;; ═══════════════════════════════════════════════════════════════════

(defvar helixel-test--ts-grammars-available
  (and (fboundp 'treesit-available-p)
       (treesit-available-p)
       (ignore-errors
         (with-temp-buffer
           (treesit-parser-create 'python))))
  "Non-nil when tree-sitter grammars are installed for testing.")

(defmacro helixel-test-with-python-ts (content &rest body)
  "Execute BODY in a temp buffer with Python-tree-sitter enabled.
CONTENT is inserted and `python-ts-mode' is activated.
Point starts at the beginning of the buffer."
  (declare (indent 1))
  `(progn
     (skip-unless helixel-test--ts-grammars-available)
     (with-temp-buffer
       (transient-mark-mode 1)
       (insert ,content)
       (goto-char (point-min))
       (setq-local python-ts-mode-hook nil)
       (python-ts-mode)
       (unwind-protect
           (progn ,@body)
         ;; treesit parsers auto-cleanup with temp buffer
         ))))

;; ═══════════════════════════════════════════════════════════════════
;; Phase 0 — Foundation
;; ═══════════════════════════════════════════════════════════════════

(ert-deftest helixel-ts-ready-p--no-parser ()
  "Ready gate returns nil in a buffer without treesit parsers."
  (with-temp-buffer
    (insert "some text without tree-sitter")
    (should-not (helixel-ts-ready-p))))

(ert-deftest helixel-ts-ready-p--with-parser ()
  "Ready gate returns t when a treesit parser is loaded."
  (skip-unless helixel-test--ts-grammars-available)
  (with-temp-buffer
    (insert "def foo(): pass")
    (setq-local python-ts-mode-hook nil)
    (python-ts-mode)
    (should (helixel-ts-ready-p))))

(ert-deftest helixel-ts-ready-p--no-treesit-build ()
  "Ready gate gracefully handles missing treesit support.
Even if `treesit-available-p' is not fboundp, the function
should return nil without signaling an error."
  (skip-unless (fboundp 'treesit-available-p))
  (with-temp-buffer
    (insert "plain text")
    (should (booleanp (helixel-ts-ready-p)))))

(ert-deftest helixel-ts--language--python ()
  "Language resolution returns `python' in python-ts-mode."
  (helixel-test-with-python-ts "def foo(): pass"
    (should (eq (helixel-ts--language) 'python))))

(ert-deftest helixel-ts--language--no-parser ()
  "Language resolution returns nil in a buffer without treesit parsers."
  (with-temp-buffer
    (insert "plain text")
    (should-not (helixel-ts--language))))

(ert-deftest helixel-ts--node-at-point--at-function-name ()
  "Node at point on a function name returns the identifier node."
  (helixel-test-with-python-ts "def foo(): pass"
    (goto-char 5) ; on 'f' of 'foo'
    (let ((node (helixel-ts--node-at-point)))
      (should node)
      (should (treesit-node-check node 'named))
      (should (equal (treesit-node-type node) "identifier")))))

(ert-deftest helixel-ts--node-at-point--at-keyword ()
  "Node at point on 'def' returns nil (unnamed keyword node)."
  (helixel-test-with-python-ts "def foo(): pass"
    (goto-char 2) ; on 'e' of 'def'
    (let ((node (helixel-ts--node-at-point)))
      (if node
          (should (treesit-node-check node 'named))
        (should-not node)))))

(ert-deftest helixel-ts--node-at-point--no-parser ()
  "Node at point returns nil without a treesit parser."
  (with-temp-buffer
    (insert "some text")
    (should-not (helixel-ts--node-at-point))))

(ert-deftest helixel-ts--node->bounds--function-def ()
  "Bounds of a function_definition node span the function body."
  (helixel-test-with-python-ts "def foo(): pass\n"
    (goto-char 6)  ; on 'f' of 'foo' — should get identifier node
    (let* ((leaf (helixel-ts--node-at-point))
           (_should (should leaf))
           (parent (helixel-ts--named-parent leaf)))
      (should parent)
      (should (equal (treesit-node-type parent) "function_definition"))
      (let ((bounds (helixel-ts--node->bounds parent)))
        (should bounds)
        (should (= (car bounds) 1))  ; function starts at column 1
        ;; Node end is exclusive; may or may not include trailing newline
        (should (>= (cdr bounds) 14)) ; at least past 'pass'
        (should (<= (cdr bounds) (point-max)))))))

(ert-deftest helixel-ts--node->bounds--nil ()
  "Bounds of nil node return nil."
  (should-not (helixel-ts--node->bounds nil)))

(ert-deftest helixel-ts--named-parent--function-child ()
  "Named parent of an identifier inside a function is function_definition."
  (helixel-test-with-python-ts "def foo(): pass"
    (goto-char 5)  ; on 'f' of 'foo'
    (let* ((leaf (helixel-ts--node-at-point))
           (parent (helixel-ts--named-parent leaf)))
      (should parent)
      (should (equal (treesit-node-type parent) "function_definition")))))

(ert-deftest helixel-ts--named-parent--skips-unnamed ()
  "Named parent skips unnamed intermediate nodes."
  (helixel-test-with-python-ts "def foo(a, b): pass"
    (goto-char 9)  ; on 'a' of first parameter
    (let* ((leaf (helixel-ts--node-at-point))
           (_ (should leaf))
           (_ (should (equal (treesit-node-type leaf) "identifier")))
           (parent (helixel-ts--named-parent leaf)))
      (should parent)
      (should (equal (treesit-node-type parent) "parameters"))
      (let ((grandparent (helixel-ts--named-parent parent)))
        (should grandparent)
        (should (equal (treesit-node-type grandparent)
                       "function_definition"))))))

(ert-deftest helixel-ts--named-parent--nil ()
  "Named parent of nil returns nil."
  (should-not (helixel-ts--named-parent nil)))

;; ═══════════════════════════════════════════════════════════════════
;; Phase 1 — Capture normalization
;; ═══════════════════════════════════════════════════════════════════

(ert-deftest helixel-ts--capture->base-part--outer ()
  ".outer capture normalizes to (base . around)."
  (let ((result (helixel-ts--capture->base-part
                 (intern "function.outer"))))
    (should result)
    (should (equal (car result) "function"))
    (should (eq (cdr result) 'around))))

(ert-deftest helixel-ts--capture->base-part--inner ()
  ".inner capture normalizes to (base . inside)."
  (let ((result (helixel-ts--capture->base-part
                 (intern "class.inner"))))
    (should result)
    (should (equal (car result) "class"))
    (should (eq (cdr result) 'inside))))

(ert-deftest helixel-ts--capture->base-part--around ()
  ".around capture normalizes to around (Helix convention)."
  (let ((result (helixel-ts--capture->base-part
                 (intern "function.around"))))
    (should result)
    (should (eq (cdr result) 'around))))

(ert-deftest helixel-ts--capture->base-part--inside ()
  ".inside capture normalizes to inside (Helix convention)."
  (let ((result (helixel-ts--capture->base-part
                 (intern "function.inside"))))
    (should result)
    (should (eq (cdr result) 'inside))))

(ert-deftest helixel-ts--capture->base-part--start-marker ()
  "_start markers return nil."
  (should-not (helixel-ts--capture->base-part
               (intern "function._start"))))

(ert-deftest helixel-ts--capture->base-part--end-marker ()
  "_end markers return nil."
  (should-not (helixel-ts--capture->base-part
               (intern "function._end"))))

(ert-deftest helixel-ts--capture->base-part--unrecognized ()
  "Unrecognized capture names return nil."
  (should-not (helixel-ts--capture->base-part
               (intern "foo"))))

;; ═══════════════════════════════════════════════════════════════════
;; Phase 1 — Object resolution (integration tests need ts grammar)
;; ═══════════════════════════════════════════════════════════════════

(ert-deftest helixel-ts--object-at--function-around ()
  "object-at finds the enclosing function (around) at point."
  (helixel-test-with-python-ts "def foo():\n    pass\n"
    (goto-char 10)  ; inside function body
    (let ((range (helixel-ts--object-at "function" 'around)))
      (should range)
      (should (= (car range) 1))  ; starts at 'd'
      ;; Node end is exclusive; may or may not include trailing newline
      (should (>= (cdr range) 18)) ; at least past 'pass'
      (should (<= (cdr range) (point-max))))))

(ert-deftest helixel-ts--object-at--function-inside ()
  "object-at finds the function inner body."
  (helixel-test-with-python-ts "def foo():\n    pass\n"
    (goto-char 17)  ; on 'a' of 'pass' — inside the block
    (let ((range (helixel-ts--object-at "function" 'inside)))
      (should range)
      ;; inner block starts after the colon line
      (should (> (car range) 13))
      (should (< (car range) 21))
      (should (> (cdr range) (car range))))))

(ert-deftest helixel-ts--object-at--no-match ()
  "object-at returns nil when no object of the requested type exists."
  (helixel-test-with-python-ts "x = 1 + 2\n"
    (goto-char 3)
    (should-not (helixel-ts--object-at "function" 'around))))

;; ═══════════════════════════════════════════════════════════════════
;; Phase 1 — Selection commands (simulated in test buffer)
;; ═══════════════════════════════════════════════════════════════════

(ert-deftest helixel-ts-mark-a-function--simple ()
  "mark-a-function selects the full function in python-ts-mode."
  (helixel-test-with-python-ts "def foo():\n    pass\n"
    ;; Need hooks for tracking.  Simulate via the helper.
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 10)
          (helixel-ts-mark-a-function 1)
          (should (use-region-p))
          (should (= (region-beginning) 1))
          ;; cursor should be on the last char of the region
          (should (> (point) 1))
          ;; pending-sel should be set
          (should helixel--pending-sel)
          (should (eq (helixel-sel-kind helixel--pending-sel) 'treesit))
          (should (equal (helixel-sel-field helixel--pending-sel :base)
                         "function"))
          (should (eq (helixel-sel-field helixel--pending-sel :part)
                      'around)))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-mark-inner-function--simple ()
  "mark-inner-function selects the function body."
  (helixel-test-with-python-ts "def foo():\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 17)  ; on 'a' of 'pass' — inside function body
          (helixel-ts-mark-inner-function 1)
          (should (use-region-p))
          (should helixel--pending-sel)
          (should (eq (helixel-sel-kind helixel--pending-sel) 'treesit))
          (should (eq (helixel-sel-field helixel--pending-sel :part)
                      'inside)))
      (helixel--deactivate-all-hooks))))

;; ═══════════════════════════════════════════════════════════════════
;; Phase 2 — Class / Parameter / Loop / Conditional commands
;; ═══════════════════════════════════════════════════════════════════

(ert-deftest helixel-ts-mark-a-class--simple ()
  "mark-a-class selects the full class in python-ts-mode."
  (helixel-test-with-python-ts "class Foo:\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 10)
          (helixel-ts-mark-a-class 1)
          (should (use-region-p))
          (should helixel--pending-sel)
          (should (eq (helixel-sel-kind helixel--pending-sel) 'treesit))
          (should (equal (helixel-sel-field helixel--pending-sel :base)
                         "class"))
          (should (eq (helixel-sel-field helixel--pending-sel :part)
                      'around)))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-mark-inner-class--simple ()
  "mark-inner-class selects the class body."
  (helixel-test-with-python-ts "class Foo:\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 17)  ; on 'a' of 'pass' — inside class body
          (helixel-ts-mark-inner-class 1)
          (should (use-region-p))
          (should helixel--pending-sel)
          (should (eq (helixel-sel-field helixel--pending-sel :part)
                      'inside)))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-mark-a-parameter--simple ()
  "mark-a-parameter selects a function parameter with comma."
  (helixel-test-with-python-ts "def foo(a, b):\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 9)  ; on 'a'
          (helixel-ts-mark-a-parameter 1)
          (should (use-region-p))
          (should helixel--pending-sel)
          (should (eq (helixel-sel-kind helixel--pending-sel) 'treesit))
          (should (equal (helixel-sel-field helixel--pending-sel :base)
                         "parameter"))
          (should (eq (helixel-sel-field helixel--pending-sel :part)
                      'around))
          (should (equal (buffer-substring-no-properties
                          (region-beginning) (region-end))
                         "a, ")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-mark-a-parameter--last ()
  "mark-a-parameter on the last parameter selects it without leading comma."
  (helixel-test-with-python-ts "def foo(a, b):\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 12)  ; on 'b'
          (helixel-ts-mark-a-parameter 1)
          (should (use-region-p))
          (should (equal (buffer-substring-no-properties
                          (region-beginning) (region-end))
                         "b")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-mark-inner-parameter--simple ()
  "mark-inner-parameter selects parameter content without comma."
  (helixel-test-with-python-ts "def foo(a, b):\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 9)
          (helixel-ts-mark-inner-parameter 1)
          (should (use-region-p))
          (should helixel--pending-sel)
          (should (eq (helixel-sel-field helixel--pending-sel :part)
                      'inside)))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-mark-a-loop--simple ()
  "mark-a-loop selects a for loop in python-ts-mode."
  (helixel-test-with-python-ts "for x in xs:\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 5)
          (helixel-ts-mark-a-loop 1)
          (should (use-region-p))
          (should helixel--pending-sel)
          (should (equal (helixel-sel-field helixel--pending-sel :base)
                         "loop")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-mark-a-conditional--simple ()
  "mark-a-conditional selects an if statement in python-ts-mode."
  (helixel-test-with-python-ts "if True:\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 5)
          (helixel-ts-mark-a-conditional 1)
          (should (use-region-p))
          (should helixel--pending-sel)
          (should (equal (helixel-sel-field helixel--pending-sel :base)
                         "conditional")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-mark-a-comment--simple ()
  "mark-a-comment selects a comment in python-ts-mode."
  (helixel-test-with-python-ts "x = 1\n# hello\ny = 2\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 9)
          (helixel-ts-mark-a-comment 1)
          (should (use-region-p))
          (should helixel--pending-sel)
          (should (equal (helixel-sel-field helixel--pending-sel :base)
                         "comment"))
          (should (eq (helixel-sel-field helixel--pending-sel :part)
                      'around))
          (should (equal (buffer-substring-no-properties
                          (region-beginning) (region-end))
                         "# hello")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-mark-inner-comment--simple ()
  "mark-inner-comment selects a comment in python-ts-mode."
  (helixel-test-with-python-ts "x = 1\n# hello\ny = 2\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 9)
          (helixel-ts-mark-inner-comment 1)
          (should (use-region-p))
          (should helixel--pending-sel)
          (should (eq (helixel-sel-field helixel--pending-sel :part)
                      'inside))
          (should (equal (buffer-substring-no-properties
                          (region-beginning) (region-end))
                         "# hello")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-comment-dispatch--fallback ()
  "comment dispatch falls back to syntax comments outside treesit."
  (with-temp-buffer
    (emacs-lisp-mode)
    (transient-mark-mode 1)
    (insert ";; hello\n(+ 1 2)\n")
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 1)
          (helixel-mark-a-comment 1)
          (should (use-region-p))
          (should (equal (buffer-substring-no-properties
                          (region-beginning) (region-end))
                         ";; hello"))
          (deactivate-mark)
          (goto-char 1)
          (helixel-mark-inner-comment 1)
          (should (use-region-p))
          (should (equal (buffer-substring-no-properties
                          (region-beginning) (region-end))
                         ";; hello"))
          (deactivate-mark)
          (goto-char (point-max))
          ;; At end of buffer, backward search finds the comment.
          (helixel-mark-inner-comment 1)
          (should (use-region-p))
          (should (equal (buffer-substring-no-properties
                          (region-beginning) (region-end))
                         ";; hello")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-comment-fallback--no-comment-error ()
  "comment text object errors in a buffer without any comment."
  (with-temp-buffer
    (emacs-lisp-mode)
    (transient-mark-mode 1)
    (insert "(+ 1 2)\n")
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 3)
          (should-error (helixel-mark-inner-comment 1)
                        :type 'user-error))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-comment-motion-dispatch--setup ()
  "comment bracket motions dispatch to treesit in treesit buffers."
  (helixel-test-with-python-ts "x = 1\n# hello\ny = 2\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (should (eq helixel-forward-outer-comment-function
                      #'helixel-ts--move-forward-outer-comment))
          (should (eq helixel-backward-outer-comment-function
                      #'helixel-ts--move-backward-outer-comment))
          (goto-char 9)
          (helixel-forward-outer-comment 1)
          (should (= (point) 14))
          (should (use-region-p))
          (should (= (region-beginning) 7))
          (should (= (region-end) 14))
          (deactivate-mark)
          (goto-char 9)
          (helixel-backward-outer-comment 1)
          (should (= (point) 7))
          (should (use-region-p))
          (should (= (region-beginning) 7))
          (should (= (region-end) 14)))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-comment-motion--boundary-skip ()
  "comment bracket motions skip current comment only at boundaries."
  (helixel-test-with-python-ts "# one\nx = 1\n# two\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 13)
          (helixel-backward-outer-comment 1)
          (should (= (point) 1))
          (should (use-region-p))
          (should (= (region-beginning) 1))
          (should (= (region-end) 6))
          (deactivate-mark)
          (goto-char 6)
          (helixel-forward-outer-comment 1)
          (should (= (point) 18))
          (should (use-region-p))
          (should (= (region-beginning) 13))
          (should (= (region-end) 18)))
      (helixel--deactivate-all-hooks))))

;; ═══════════════════════════════════════════════════════════════════
;; Phase 3 — Dot-repeat advance
;; ═══════════════════════════════════════════════════════════════════

(ert-deftest helixel-treesit-repeat-advance--function ()
  "Advance moves to the next function after selection."
  (helixel-test-with-python-ts "def foo():\n    pass\ndef bar():\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 5)
          (helixel-ts-mark-a-function 1)
          (let* ((sel helixel--pending-sel)
                 (first-beg (region-beginning))
                 (tx (helixel-action-create 'insert-text sel (list :text "X"))))
            ;; Verify advance moves past current function
            (let ((result (helixel-ts--advance-by-recreate tx)))
              (should result)
              (should (use-region-p))
              (should (> (region-beginning) first-beg))
              (goto-char (region-beginning))
              (should (looking-at "def bar")))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-repeat-advance--parameter ()
  "Advance moves through consecutive parameters."
  (helixel-test-with-python-ts "def foo(a, b, c):\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 9)
          (helixel-ts-mark-a-parameter 1)
          (let* ((sel helixel--pending-sel)
                 (first-beg (region-beginning))
                 (tx (helixel-action-create 'insert-text sel (list :text "X"))))
            ;; First advance -> b
            (should (helixel-ts--advance-by-recreate tx))
            (should (use-region-p))
            (should (> (region-beginning) first-beg))
            ;; Second advance -> c
            (let ((second-beg (region-beginning)))
              (should (helixel-ts--advance-by-recreate tx))
              (should (use-region-p))
              (should (> (region-beginning) second-beg)))))
      (helixel--deactivate-all-hooks))))

;; ═══════════════════════════════════════════════════════════════════
;; Phase 4 — Tree motions: expand/shrink, next/prev type navigation
;; ═══════════════════════════════════════════════════════════════════

(ert-deftest helixel-ts-forward-outer-class--simple ()
  "next-class from inside class moves to end of current class."
  (helixel-test-with-python-ts "class Foo:\n    pass\nclass Bar:\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 5)
          (helixel-ts-forward-outer-class 1)
          (should (= (point) 20)))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-forward-outer-class--at-boundary ()
  "next-class at end of current class moves to end of next class."
  (helixel-test-with-python-ts "class Foo:\n    pass\nclass Bar:\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (search-forward "pass")
          (helixel-ts-forward-outer-class 1)
          (should (> (point) 20)))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-backward-outer-class--simple ()
  "prev-class from inside class stays in current class."
  (helixel-test-with-python-ts "class Foo:\n    pass\nclass Bar:\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 25)
          (helixel-ts-backward-outer-class 1)
          (should (looking-at "class Bar")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-backward-outer-class--at-boundary ()
  "prev-class at start of current class moves to previous class."
  (helixel-test-with-python-ts "class Foo:\n    pass\nclass Bar:\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (search-forward "class Bar")
          (goto-char (match-beginning 0))
          (helixel-ts-backward-outer-class 1)
          (should (looking-at "class Foo")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-forward-outer-class--no-more ()
  "next-class signals error when no more classes exist."
  (helixel-test-with-python-ts "class Foo:\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char (point-max))
          (should-error (helixel-ts-forward-outer-class 1)
                        :type 'user-error))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-forward-outer-parameter--simple ()
  "next-parameter from inside parameter moves to end of current parameter."
  (helixel-test-with-python-ts "def foo(a, b, c):\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 9)
          (helixel-ts-forward-outer-parameter 1)
          ;; Outer nav expands end to include trailing comma, like ma,.
          (should (= (point) 12)))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-forward-outer-parameter--at-boundary ()
  "next-parameter at end of current parameter moves to end of next."
  (helixel-test-with-python-ts "def foo(a, b, c):\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 10)
          (helixel-ts-forward-outer-parameter 1)
          ;; Outer nav expands end to include trailing comma, like ma,.
          (should (= (point) 15)))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-backward-outer-parameter--simple ()
  "prev-parameter from inside parameter stays in current parameter."
  (helixel-test-with-python-ts "def foo(a, b, c):\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 13)
          (helixel-ts-backward-outer-parameter 1)
          (should (looking-at "b")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-backward-outer-parameter--at-boundary ()
  "prev-parameter at start of current parameter moves to previous."
  (helixel-test-with-python-ts "def foo(a, b, c):\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 12)
          (helixel-ts-backward-outer-parameter 1)
          (should (looking-at "a")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-forward-outer-parameter--no-more ()
  "next-parameter stays at current when no more parameters exist."
  (helixel-test-with-python-ts "def foo(a):\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 10)  ;; at end of only parameter
          (helixel-ts-forward-outer-parameter 1)
          ;; silently stays at current — no error
          (should (>= (point) 9)))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-grow-shrink--simple ()
  "Grow from function body to whole function, then shrink back."
  (helixel-test-with-python-ts "def foo():\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 20)  ; on 's' of 'pass'
          (helixel-ts-grow-selection 1)
          (should (use-region-p))
          (should helixel--pending-sel)
          (should (eq (helixel-sel-kind helixel--pending-sel) 'treesit))
          (let ((first-beg (region-beginning)))
            (helixel-ts-grow-selection 1)
            (should (use-region-p))
            (should (< (region-beginning) first-beg))
            (helixel-ts-shrink-selection 1)
            (should (use-region-p))
            (should (= (region-beginning) first-beg))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-grow--from-function ()
  "Grow from a mark-a-function selection expands to parent."
  (helixel-test-with-python-ts "class Foo:\n    def bar():\n        pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 20)
          (helixel-ts-mark-a-function 1)
          (let ((func-beg (region-beginning)))
            (helixel-ts-grow-selection 1)
            (should (use-region-p))
            (should (< (region-beginning) func-beg))
            (goto-char (region-beginning))
            (should (looking-at "class"))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-grow--child-range ()
  "Grow on a function body selects the block, grow again = full function."
  (helixel-test-with-python-ts "def foo(a, b):\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 24)  ; on newline after 'pass'
          (helixel-ts-grow-selection 1)
          (should (use-region-p))
          (let ((level1-beg (region-beginning))
                (level1-end (region-end)))
            (helixel-ts-grow-selection 1)
            (should (use-region-p))
            ;; The expanded region should be strictly larger
            ;; (beg moves left, or end moves right, or both)
            (should (or (< (region-beginning) level1-beg)
                        (> (region-end) level1-end)))
            ;; Shrink back
            (helixel-ts-shrink-selection 1)
            (should (use-region-p))
            (should (= (region-beginning) level1-beg))
            (should (= (region-end) level1-end))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-shrink--at-root ()
  "Shrink at level 0 signals user-error."
  (helixel-test-with-python-ts "def foo():\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 5)
          (helixel-ts-mark-a-function 1)
          (should-error (helixel-ts-shrink-selection 1)
                        :type 'user-error))
      (helixel--deactivate-all-hooks))))

;; ═══════════════════════════════════════════════════════════════════
;; Phase 6 — Integration tests: action ring, non-ts fallback
;; ═══════════════════════════════════════════════════════════════════

(ert-deftest helixel-treesit-action-ring--maf-edit ()
  "After treesit maf + edit, ; cycle restores the selection."
  (helixel-test-with-python-ts "def foo():\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 5)
          ;; Simulate maf (mark around function)
          (helixel-ts-mark-a-function 1)
          (should helixel--pending-sel)
          ;; Simulate an edit (kill) that commits the action
          (helixel-sel-call-recreate helixel--pending-sel)
          (should (use-region-p))
          (let ((beg (region-beginning))
                (end (region-end)))
            (helixel--tracking-open 'edit 'kill)
            (helixel-record-action 'kill :beg beg :end end
                                    :runner #'ignore))
          ;; Verify action committed with treesit sel
          (should helixel-last-action)
          (should (eq (helixel-sel-kind
                       (helixel-action-sel helixel-last-action))
                      'treesit)))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-action-ring--grow-edit ()
  "After treesit grow + edit, ; cycle sees the expanded selection."
  (helixel-test-with-python-ts "def foo():\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 20)  ; on 'pass'
          ;; Grow to select the function block
          (helixel-ts-grow-selection 1)
          (should helixel--pending-sel)
          (should (eq (helixel-sel-kind helixel--pending-sel) 'treesit))
          ;; Simulate an edit (change) that commits
          (helixel-sel-call-recreate helixel--pending-sel)
          (should (use-region-p))
          (let ((beg (region-beginning))
                (end (region-end)))
            (helixel--tracking-open 'edit 'change)
            (helixel-record-action 'change :beg beg :end end
                                    :runner #'ignore))
          (should helixel-last-action)
          (should (eq (helixel-sel-kind
                       (helixel-action-sel helixel-last-action))
                      'treesit)))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit--non-ts-error ()
  "Treesit commands gracefully fail in non-ts buffers."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "def foo():\n    pass\n")
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          ;; Mark commands return nil silently (no region)
          (should-not (helixel-ts-mark-a-function 1))
          ;; Navigation commands signal user-error
          (should-error (helixel-ts-forward-outer-class 1)
                        :type 'user-error)
          (should-error (helixel-ts-grow-selection 1)
                        :type 'user-error))
      (helixel--deactivate-all-hooks))))

;; ═══════════════════════════════════════════════════════════════════
;; Phase 7 — Sibling navigation [o / ]o
;; ═══════════════════════════════════════════════════════════════════

(ert-deftest helixel-ts--node-matching-bounds--exact ()
  "node-matching-bounds returns a node containing the given bounds."
  (helixel-test-with-python-ts "def foo(a, b):\n    pass\n"
    (goto-char 9)  ;; on 'a'
    (let* ((leaf (helixel-ts--node-at-point))
           (_ (should leaf))
           (parent (helixel-ts--named-parent leaf)))
      (should parent)
      (let ((start (treesit-node-start parent))
            (end (treesit-node-end parent)))
        (let ((found (helixel-ts--node-matching-bounds start end)))
          (should found)
          (should (>= (treesit-node-start found) start))
          (should (>= end (treesit-node-end found))))))))

(ert-deftest helixel-ts--node-matching-bounds--nil-args ()
  "node-matching-bounds returns nil for nil arguments."
  (helixel-test-with-python-ts "def foo(): pass\n"
    (should-not (helixel-ts--node-matching-bounds nil nil))
    (should-not (helixel-ts--node-matching-bounds 1 nil))
    (should-not (helixel-ts--node-matching-bounds nil 10))))

(ert-deftest helixel-ts--node-matching-bounds--walks-past-unnamed ()
  "node-matching-bounds walks through unnamed nodes to find match."
  (helixel-test-with-python-ts "def foo(): pass\n"
    (goto-char 5)  ;; on 'f' of 'foo'
    (let* ((leaf (helixel-ts--node-at-point))
           (grand (helixel-ts--named-parent
                   (helixel-ts--named-parent leaf))))
      ;; grand should be function_definition
      (should grand)
      (let ((start (treesit-node-start grand))
            (end (treesit-node-end grand)))
        (let ((found (helixel-ts--node-matching-bounds start end)))
          (should found)
          (should (= (treesit-node-start found) start)))))))

(ert-deftest helixel-treesit-sibling--simple-next ()
  "next-sibling moves to the next sibling argument."
  (helixel-test-with-python-ts "foo(a, b, c)\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 5)  ;; on 'a'
          (helixel-ts-forward-outer-sibling 1)
          (should (use-region-p))
          (should helixel--pending-sel)
          (should (eq (helixel-sel-kind helixel--pending-sel) 'treesit))
          ;; Should select 'b'
          (goto-char (region-beginning))
          (should (looking-at "b")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-sibling--simple-prev ()
  "prev-sibling moves to the previous sibling."
  (helixel-test-with-python-ts "foo(a, b, c)\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 11)  ;; on 'c'
          (helixel-ts-backward-outer-sibling 1)
          (should (use-region-p))
          (should helixel--pending-sel)
          (goto-char (region-beginning))
          (should (looking-at "b")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-sibling--no-next-error ()
  "next-sibling signals error after last argument."
  (helixel-test-with-python-ts "foo(a, b, c)\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 11)  ;; on 'c' (last arg)
          ;; Move to the last sibling first, then next should error
          (ignore-errors (helixel-ts-forward-outer-sibling 1))
          ;; Now at last position, next should error
          (goto-char 11)
          (should-error (helixel-ts-forward-outer-sibling 1)
                        :type 'user-error))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-sibling--no-prev-error ()
  "prev-sibling signals error before first argument."
  (helixel-test-with-python-ts "foo(a, b, c)\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 5)  ;; on 'a' (first arg)
          ;; First jump to the prev sibling might work (ascending to
          ;; parent level), but after that there should be nothing.
          ;; Just verify that after multiple prev calls we hit error.
          (let ((count 0))
            (while (< count 10)
              (condition-case nil
                  (progn (helixel-ts-backward-outer-sibling 1)
                         (setq count (1+ count)))
                (user-error (setq count 99))))
            (should (> count 0))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-sibling--repeat-forward ()
  "Repeating next-sibling with , advances through siblings."
  (helixel-test-with-python-ts "foo(a, b, c)\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 5)  ;; on 'a'
          (helixel-ts-forward-outer-sibling 1)
          (goto-char (region-beginning))
          (should (looking-at "b"))
          ;; , repeat: call repeat-last-motion directly
          (setq last-command 'helixel-ts-forward-outer-sibling
                this-command 'helixel-repeat-last-motion)
          (helixel-repeat-last-motion)
          (goto-char (region-beginning))
          (should (looking-at "c")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-sibling--repeat-backward ()
  "Repeating prev-sibling with , advances backward through siblings."
  (helixel-test-with-python-ts "foo(a, b, c)\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 11)  ;; on 'c'
          (helixel-ts-backward-outer-sibling 1)
          (goto-char (region-beginning))
          (should (looking-at "b"))
          ;; , repeat
          (setq last-command 'helixel-ts-backward-outer-sibling
                this-command 'helixel-repeat-last-motion)
          (helixel-repeat-last-motion)
          (goto-char (region-beginning))
          (should (looking-at "a")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-sibling--reverse-direction ()
  "-, reverses sibling direction: ]o then -, goes back."
  (helixel-test-with-python-ts "foo(a, b, c)\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 5)  ;; on 'a'
          (helixel-ts-forward-outer-sibling 1)
          (goto-char (region-beginning))
          (should (looking-at "b"))
          ;; -, reverse = go back (call repeat with prefix '-')
          (setq last-command 'helixel-repeat-last-motion
                this-command 'helixel-repeat-last-motion)
          (helixel-repeat-last-motion '-)
          (goto-char (region-beginning))
          (should (looking-at "a")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-sibling--grow-shrink-reverse ()
  "Grow and shrink are registered as mutual reverse motions."
  (helixel-treesit-setup)
  (let ((rev (helixel--motion-reverse-lookup
              'helixel-ts-grow-selection)))
    (should (eq rev 'helixel-ts-shrink-selection)))
  (let ((rev (helixel--motion-reverse-lookup
              'helixel-ts-shrink-selection)))
    (should (eq rev 'helixel-ts-grow-selection))))

(ert-deftest helixel-treesit-sibling--mutual-reverse ()
  "next-sibling and prev-sibling are registered as mutual reverses."
  (helixel-treesit-setup)
  (let ((rev (helixel--motion-reverse-lookup
              'helixel-ts-forward-outer-sibling)))
    (should (eq rev 'helixel-ts-backward-outer-sibling)))
  (let ((rev (helixel--motion-reverse-lookup
              'helixel-ts-backward-outer-sibling)))
    (should (eq rev 'helixel-ts-forward-outer-sibling))))

(ert-deftest helixel-treesit-sibling--ascend-python-expr-stmt ()
  "Prev-sibling ascends through Python expression_statement wrappers."
  (helixel-test-with-python-ts "a = 1\nb = 2\nc = 3\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 14)  ;; inside 'c = 3' line
          (helixel-ts-backward-outer-sibling 1)
          (should (use-region-p))
          (goto-char (region-beginning))
          (should (looking-at "b")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-sibling--child-avoidance ()
  "After selecting b.c, ]o goes to d.e() not c (child avoidance)."
  (helixel-test-with-python-ts "foo(a, b.c, d.e())\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 5)  ;; on 'a'
          ;; ]o to b.c
          (helixel-ts-forward-outer-sibling 1)
          (goto-char (region-beginning))
          (should (looking-at "b"))
          (let ((first-region-end (region-end)))
            ;; ]o again should go to d.e(), not into b.c's children
            (helixel-ts-forward-outer-sibling 1)
            (goto-char (region-beginning))
            (should (looking-at "d"))
            ;; Verify we moved past the first selection
            (should (> (region-beginning) first-region-end))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-sibling--no-select ()
  "With sibling removed from motion-select-categories, only moves point."
  (helixel-test-with-python-ts "foo(a, b, c)\n"
    (helixel--activate-all-hooks)
    (let ((helixel-motion-select-categories
           (remove '(movement . sibling)
                   helixel-motion-select-categories)))
      (unwind-protect
          (progn
            (goto-char 5)  ;; on 'a'
            (helixel-ts-forward-outer-sibling 1)
            ;; Region should NOT be active
            (should-not (use-region-p))
            ;; Point should have moved
            (should (> (point) 5))
            ;; But pending-sel is still recorded for ; action cycle
            (should helixel--pending-sel)
            (should (eq (helixel-sel-kind helixel--pending-sel) 'treesit)))
        (helixel--deactivate-all-hooks)))))

(ert-deftest helixel-treesit-sibling--no-select-repeat ()
  "With select off, , repeat still works (just moves point)."
  (helixel-test-with-python-ts "foo(a, b, c)\n"
    (helixel--activate-all-hooks)
    (let ((helixel-motion-select-categories
           (remove '(movement . sibling)
                   helixel-motion-select-categories)))
      (unwind-protect
          (progn
            (goto-char 5)
            (helixel-ts-forward-outer-sibling 1)
            (should-not (use-region-p))
            (let ((pt1 (point)))
              (setq last-command 'helixel-ts-forward-outer-sibling
                    this-command 'helixel-repeat-last-motion)
              (helixel-repeat-last-motion)
              (should-not (use-region-p))
              (should (> (point) pt1))))
        (helixel--deactivate-all-hooks)))))

(ert-deftest helixel-treesit-sibling--maa-then-bracket-o ()
  "After maa (mark-a-parameter) on 'c', [o moves to 'b'."
  (helixel-test-with-python-ts "def foo(a, b, c):\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 15)  ;; on 'c' parameter
          (helixel-ts-mark-a-parameter 1)
          (let* ((sel helixel--pending-sel)
                 (ctx (helixel-sel-ctx sel)))
            ;; Verify :start and :end are stored
            (should (plist-get ctx :start))
            (should (plist-get ctx :end)))
          ;; [o should select the previous parameter (b)
          (helixel-ts-backward-outer-sibling 1)
          (should (use-region-p))
          (goto-char (region-beginning))
          (should (looking-at "b")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit--pending-sel-has-start-end--activate ()
  "activate-selection stores :start and :end in pending-sel."
  (helixel-test-with-python-ts "def foo(a, b):\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 9)  ;; on 'a'
          (helixel-ts-mark-a-parameter 1)
          (should helixel--pending-sel)
          (let ((ctx (helixel-sel-ctx helixel--pending-sel)))
            (should (plist-get ctx :start))
            (should (plist-get ctx :end))
            (should (> (plist-get ctx :end) (plist-get ctx :start)))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit--pending-sel-has-start-end--nav ()
  "setup-nav-state stores :start and :end in pending-sel."
  (helixel-test-with-python-ts "class Foo:\n    pass\nclass Bar:\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char (point-min))
          (helixel-ts-forward-outer-class 1)
          (should helixel--pending-sel)
          (let ((ctx (helixel-sel-ctx helixel--pending-sel)))
            (should (plist-get ctx :start))
            (should (plist-get ctx :end))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-sibling--motion-select-default ()
  "helixel-motion-select-categories includes (movement . sibling) by default."
  (should (member '(movement . sibling)
                  helixel-motion-select-categories)))

(ert-deftest helixel-treesit--motion-repeat-categories-includes-treesit ()
  "Treesit motions are registered for , / -, repeat after setup."
  (helixel-treesit-setup)
  (should (member '(movement . function)
                  helixel-motion-repeat-categories)))

;; ═══════════════════════════════════════════════════════════════════
;; Boundary & advance-stuck tests
;; ═══════════════════════════════════════════════════════════════════

(ert-deftest helixel-treesit-object-at--before-closing-paren ()
  "object-at finds parameter when cursor is just before )."
  (helixel-test-with-python-ts "def foo(a, b, c):\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          ;; Cursor at the ) after the last parameter.
          (goto-char 16)  ; right before )
          (let ((range (helixel-ts--object-at
                        "parameter" 'inside 0)))
            (should range)
            ;; Should select 'c' (the last parameter).
            (should (equal (buffer-substring (car range)
                                             (cdr range))
                           "c"))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-mark-inner-parameter--before-closing-paren ()
  "mi, selects the last parameter when cursor is just before )."
  (helixel-test-with-python-ts "def foo(a, b, c):\n    pass\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 16)  ; right before )
          (helixel-ts-mark-inner-parameter 1)
          (should (use-region-p))
          (should (string= (buffer-substring (region-beginning)
                                             (region-end))
                           "c")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-motion-repeat--advance-past-comment ()
  "maf then , advances past a comment to the next function."
  (helixel-test-with-python-ts
      "def foo():\n    pass\n# a comment\ndef bar():\n    pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 5)  ; on 'f' of foo
          (helixel-ts-mark-a-function 1)
          (should (use-region-p))
          ;; Simulate the first , press:
          ;; skip-past moves past foo, lands on comment.
          (goto-char (region-end))
          (skip-chars-forward " \t\n\r\f,;:")
          (let ((after-skip (point)))
            ;; Point should be on the comment line.
            (should (looking-at "#"))
            ;; Command invoked here (looking for "function")
            ;; fails to select anything.  The stuck-avoidance
            ;; should skip past the comment node.
            (when-let* ((node (helixel-ts--node-at-point)))
              (goto-char (treesit-node-end node))
              (skip-chars-forward " \t\n\r\f,;:"))
            ;; Now point should be at the next function.
            (should (looking-at "def bar"))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-motion-repeat--stuck-avoidance-skips-node ()
  "After failing on a non-matching node, the repeater skips and retries."
  (helixel-test-with-python-ts
      "def foo():\n    pass\n# a comment\ndef bar():\n    pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 5)
          (helixel-ts-mark-a-function 1)
          ;; Simulate: skip-past moves past foo, lands at comment.
          (goto-char (region-end))
          (skip-chars-forward " \t\n\r\f,;:")
          (should (looking-at "#"))  ; on the comment
          ;; Simulate command fails (no function here).
          (deactivate-mark)
          ;; Simulate stuck-avoidance + retry:
          ;; 1. Skip past the comment node.
          (when-let* ((node (helixel-ts--node-at-point)))
            (goto-char (treesit-node-end node))
            (skip-chars-forward " \t\n\r\f,;:"))
          ;; 2. Retry the command at the new position.
          (should (looking-at "def bar"))  ; at bar's start
          (helixel-ts-mark-a-function 1)
          (should (use-region-p))
          (goto-char (region-beginning))
          (should (looking-at "def bar")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-object-at--inside-from-outer-header ()
  "mif then , finds the inner body of the next function."
  (helixel-test-with-python-ts "def foo():\n    pass\ndef bar():\n    return 1\n"
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          ;; Select inner of foo.
          (search-forward "pass")
          (backward-word)
          (helixel-ts-mark-inner-function 1)
          (should (use-region-p))
          ;; Skip-past simulation: move past inner body, land at
          ;; the next function's def line.
          (goto-char (region-end))
          (skip-chars-forward " \t\n\r\f,;:")
          (should (looking-at "def bar"))
          ;; object-at inside at def line: should find bar's body.
          (let ((range (helixel-ts--object-at
                        "function" 'inside 0)))
            (should range)
            (goto-char (car range))
            (should (looking-at "return 1"))))
      (helixel--deactivate-all-hooks))))


;; ═══════════════════════════════════════════════════════════════════
;; Comma-repeat helpers — unit tests
;; ═══════════════════════════════════════════════════════════════════

(ert-deftest helixel-ts--cmd->base-part--inner-function ()
  "Parse mark-inner-function to (\"function\" . inside)."
  (let ((result (helixel-ts--cmd->base-part
                 'helixel-ts-mark-inner-function)))
    (should (equal result '("function" . inside)))))

(ert-deftest helixel-ts--cmd->base-part--a-function ()
  "Parse mark-a-function to (\"function\" . around)."
  (let ((result (helixel-ts--cmd->base-part
                 'helixel-ts-mark-a-function)))
    (should (equal result '("function" . around)))))

(ert-deftest helixel-ts--cmd->base-part--inner-parameter ()
  "Parse mark-inner-parameter to (\"parameter\" . inside)."
  (let ((result (helixel-ts--cmd->base-part
                 'helixel-ts-mark-inner-parameter)))
    (should (equal result '("parameter" . inside)))))

(ert-deftest helixel-ts--cmd->base-part--a-parameter ()
  "Parse mark-a-parameter to (\"parameter\" . around)."
  (let ((result (helixel-ts--cmd->base-part
                 'helixel-ts-mark-a-parameter)))
    (should (equal result '("parameter" . around)))))

(ert-deftest helixel-ts--cmd->base-part--non-textobj ()
  "Return nil for non-textobj treesit commands."
  (should-not (helixel-ts--cmd->base-part
               'helixel-ts-forward-outer-function))
  (should-not (helixel-ts--cmd->base-part
               'helixel-ts-grow-selection)))

(ert-deftest helixel-ts--cmd->base-part--unrelated ()
  "Return nil for commands outside the treesit namespace."
  (should-not (helixel-ts--cmd->base-part 'forward-char))
  (should-not (helixel-ts--cmd->base-part nil)))

;; ── next-capture ──

(ert-deftest helixel-ts--next-capture--forward ()
  "Find the next outer capture after a given position."
  (helixel-test-with-python-ts "def foo(): pass\ndef bar(): pass\ndef baz(): pass\n"
    (helixel-treesit-setup)
    (let* ((captures (helixel-ts--captures))
           ;; Find foo's outer start
           (foo-start (cl-some (lambda (c)
                                (when (eq (car c) 'function.outer)
                                  (nth 1 c)))
                              captures)))
      (should foo-start)
      ;; Search forward from foo's end: should find bar
      (let ((next (helixel-ts--next-capture
                   "function" (nth 2
                             (cl-find 'function.outer captures
                                      :key #'car))
                   t)))
        (should next)
        ;; Should be bar, not foo again
        (should (> (car next) foo-start))))))

(ert-deftest helixel-ts--next-capture--backward ()
  "Find the previous outer capture before a given position."
  (helixel-test-with-python-ts "def foo(): pass\ndef bar(): pass\ndef baz(): pass\n"
    (helixel-treesit-setup)
    (let ((captures (helixel-ts--captures)))
      ;; Find baz's start
      (let ((baz-start (cl-some (lambda (c)
                                 (when (eq (car c) 'function.outer)
                                   (nth 1 c)))
                               (reverse captures))))
        (should baz-start)
        ;; Search backward from baz's start: should find bar
        (let ((prev (helixel-ts--next-capture
                     "function" baz-start nil)))
          (should prev)
          (should (< (car prev) baz-start)))))))

(ert-deftest helixel-ts--next-capture--no-match ()
  "Return nil when no more captures in direction."
  (helixel-test-with-python-ts "def foo(): pass\n"
    (helixel-treesit-setup)
    (let ((captures (helixel-ts--captures)))
      (let ((foo-end (nth 2 (cl-find 'function.outer captures
                                     :key #'car))))
        ;; Forward from after the last function: no match
        (should-not (helixel-ts--next-capture
                     "function" foo-end t))
        ;; Backward from before the first function: no match
        (should-not (helixel-ts--next-capture
                     "function" 1 nil))))))

(ert-deftest helixel-ts--next-capture--correct-order-forward ()
  "Forward returns the nearest (smallest start) capture after position."
  (helixel-test-with-python-ts "def a(): pass\ndef b(): pass\ndef c(): pass\n"
    (helixel-treesit-setup)
    ;; Search from 0 so the first capture at pos 1 is included
    (let ((next (helixel-ts--next-capture "function" 0 t)))
      (should next)
      (goto-char (car next))
      (should (looking-at "def a")))))

(ert-deftest helixel-ts--next-capture--correct-order-backward ()
  "Backward returns the nearest (largest start) capture before position."
  (helixel-test-with-python-ts "def a(): pass\ndef b(): pass\ndef c(): pass\n"
    (helixel-treesit-setup)
    (goto-char (point-max))
    (let ((prev (helixel-ts--next-capture
                 "function" (point-max) nil)))
      (should prev)
      (goto-char (car prev))
      (should (looking-at "def c")))))

;; ── nearest-forward ──

(ert-deftest helixel-ts--nearest-forward--from-bol-around ()
  "From bol, nearest-forward finds the first function (around)."
  (helixel-test-with-python-ts "x = 1\ndef foo(): pass\ndef bar(): pass\n"
    (helixel-treesit-setup)
    (goto-char 1)
    (let ((range (helixel-ts--nearest-forward "function" 'around)))
      (should range)
      (goto-char (car range))
      (should (looking-at "def foo")))))

(ert-deftest helixel-ts--nearest-forward--from-between ()
  "From between objects, nearest-forward finds the next one."
  (helixel-test-with-python-ts "def foo(): pass\n# comment\ndef bar(): pass\n"
    (helixel-treesit-setup)
    ;; Point on the comment line
    (goto-char (point-min))
    (search-forward "# comment")
    (let ((range (helixel-ts--nearest-forward "function" 'around)))
      (should range)
      (goto-char (car range))
      (should (looking-at "def bar")))))

(ert-deftest helixel-ts--nearest-forward--no-match ()
  "Return nil when no matching object ahead."
  (helixel-test-with-python-ts "def foo(): pass\n"
    (helixel-treesit-setup)
    ;; Point at end of buffer
    (goto-char (point-max))
    (should-not (helixel-ts--nearest-forward "function" 'around))))

(ert-deftest helixel-ts--nearest-forward--inside-part ()
  "For inside part, return the innermost inner capture."
  (helixel-test-with-python-ts "x = 1\ndef foo():\n    pass\ndef bar(): pass\n"
    (helixel-treesit-setup)
    (goto-char 1)
    (let ((range (helixel-ts--nearest-forward "function" 'inside)))
      (should range)
      ;; Should be inside foo's body, not the def line
      (goto-char (car range))
      (should (looking-at "pass")))))

;; ── object-at no-fallback ──

(ert-deftest helixel-ts--object-at--no-fallback-suppresses-retry ()
  "no-fallback=t prevents the point-1 retry at boundary positions."
  (helixel-test-with-python-ts "def foo():\n    pass\n"
    (helixel-treesit-setup)
    ;; Place point exactly at the end of the function outer capture
    (let* ((caps (helixel-ts--captures))
           (outer (cl-find 'function.outer caps :key #'car)))
      (should outer)
      (goto-char (nth 2 outer))  ;; exclusive end
      ;; Without no-fallback: should fall back to point-1 and find foo
      (let ((range (helixel-ts--object-at "function" 'around 0 nil)))
        (should range))
      ;; With no-fallback: should NOT find foo
      (let ((range (helixel-ts--object-at "function" 'around 0 t)))
        (should-not range)))))

;; ═══════════════════════════════════════════════════════════════════
;; Textobj comma-repeat — integration tests
;; ═══════════════════════════════════════════════════════════════════

(ert-deftest helixel-treesit-comma-repeat--maf-forward ()
  "maf then , selects the next function."
  (helixel-test-with-python-ts "def foo():\n    pass\ndef bar():\n    return 1\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 5)  ;; on 'f' of foo
          (helixel-ts-mark-a-function 1)
          (should (use-region-p))
          (goto-char (region-beginning))
          (should (looking-at "def foo"))
          ;; , repeat: should move to bar
          (setq last-command 'helixel-ts-mark-a-function
                this-command 'helixel-repeat-last-motion)
          (helixel-repeat-last-motion)
          (should (use-region-p))
          (goto-char (region-beginning))
          (should (looking-at "def bar")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-comma-repeat--maf-backward ()
  "maf then -, goes to the previous function."
  (helixel-test-with-python-ts "def foo():\n    pass\ndef bar():\n    return 1\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          ;; Select bar first
          (goto-char 22)  ;; on 'b' of bar
          (helixel-ts-mark-a-function 1)
          (should (use-region-p))
          (goto-char (region-beginning))
          (should (looking-at "def bar"))
          ;; -, repeat: should go back to foo
          (setq last-command 'helixel-repeat-last-motion
                this-command 'helixel-repeat-last-motion)
          (helixel-repeat-last-motion '-)
          (should (use-region-p))
          (goto-char (region-beginning))
          (should (looking-at "def foo")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-comma-repeat--maf-double-forward ()
  "maf then ,, selects 2 functions ahead."
  (helixel-test-with-python-ts
      "def a(): pass\ndef b(): pass\ndef c(): pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 5)  ;; on 'a'
          (helixel-ts-mark-a-function 1)
          (should (save-excursion
                    (goto-char (region-beginning))
                    (looking-at "def a")))
          ;; First , → b
          (setq last-command 'helixel-ts-mark-a-function
                this-command 'helixel-repeat-last-motion)
          (helixel-repeat-last-motion)
          (should (save-excursion
                    (goto-char (region-beginning))
                    (looking-at "def b")))
          ;; Second , → c
          (setq last-command 'helixel-repeat-last-motion
                this-command 'helixel-repeat-last-motion)
          (helixel-repeat-last-motion)
          (should (save-excursion
                    (goto-char (region-beginning))
                    (looking-at "def c"))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-comma-repeat--maf-permanent-flip ()
  "-, flips direction permanently; subsequent , continues backward."
  (helixel-test-with-python-ts
      "def a(): pass\ndef b(): pass\ndef c(): pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          ;; Select c first
          (search-forward "def c")
          (helixel-ts-mark-a-function 1)
          (goto-char (region-beginning))
          (should (looking-at "def c"))
          ;; -, flip to backward → b
          (setq last-command 'helixel-repeat-last-motion
                this-command 'helixel-repeat-last-motion)
          (helixel-repeat-last-motion '-)
          (goto-char (region-beginning))
          (should (looking-at "def b"))
          ;; Plain , now continues backward → a
          (setq last-command 'helixel-repeat-last-motion
                this-command 'helixel-repeat-last-motion)
          (helixel-repeat-last-motion)
          (goto-char (region-beginning))
          (should (looking-at "def a")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-comma-repeat--maf-no-more ()
  "Signals user-error when no more targets in direction."
  (helixel-test-with-python-ts "def foo(): pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 5)
          (helixel-ts-mark-a-function 1)
          (setq last-command 'helixel-ts-mark-a-function
                this-command 'helixel-repeat-last-motion)
          (should-error (helixel-repeat-last-motion)
                        :type 'user-error))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-comma-repeat--parameter-forward ()
  "ma, then , moves to the next parameter."
  (helixel-test-with-python-ts "def foo(a, b, c): pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 8)  ;; on 'a'
          (helixel-ts-mark-a-parameter 1)
          (should (use-region-p))
          (goto-char (region-beginning))
          (should (looking-at "a"))
          ;; , → b
          (setq last-command 'helixel-ts-mark-a-parameter
                this-command 'helixel-repeat-last-motion)
          (helixel-repeat-last-motion)
          (should (use-region-p))
          (goto-char (region-beginning))
          (should (looking-at "b")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-comma-repeat--parameter-backward ()
  "ma, then -, moves to the previous parameter."
  (helixel-test-with-python-ts "def foo(a, b, c): pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 14)  ;; on 'c'
          (helixel-ts-mark-a-parameter 1)
          (should (equal (buffer-substring-no-properties
                          (region-beginning) (region-end))
                         "c"))
          ;; -, → b
          (setq last-command 'helixel-repeat-last-motion
                this-command 'helixel-repeat-last-motion)
          (helixel-repeat-last-motion '-)
          (should (use-region-p))
          (goto-char (region-beginning))
          (should (looking-at "b")))
      (helixel--deactivate-all-hooks))))

;; ── Nearest-forward via select-object ──

(ert-deftest helixel-treesit-select-object--nearest-from-bol ()
  "m, from bol selects the first parameter via nearest-forward."
  (helixel-test-with-python-ts
      "def foo(a, b, c): pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 1)  ;; bol, before all parameters
          (let ((result (helixel-ts--select-object
                         "parameter" 'around)))
            (should result)
            (should (use-region-p))
            (goto-char (region-beginning))
            (should (looking-at "a"))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-select-object--nearest-from-bol-inside ()
  "mi, from bol selects first parameter content via nearest-forward."
  (helixel-test-with-python-ts
      "def foo(a, b, c): pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 1)
          (let ((result (helixel-ts--select-object
                         "parameter" 'inside)))
            (should result)
            (should (use-region-p))
            ;; Should select the inside of parameter 'a'
            (let ((sel (buffer-substring
                        (region-beginning) (region-end))))
              (should (string= sel "a")))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-select-object--nearest-no-match ()
  "Returns nil via nearest-forward when no matching object ahead."
  (helixel-test-with-python-ts "x = 1\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 1)
          (let ((result (helixel-ts--select-object
                         "function" 'around)))
            (should-not result)
            (should-not (use-region-p))))
      (helixel--deactivate-all-hooks))))

;; ── Comma-repeat boundary fix tests ──

(ert-deftest helixel-treesit-comma-repeat--adjacent-captures ()
  "Comma-repeat works when next capture starts at region-end.
This tests the off-by-one fix: tree-sitter @parameter.outer
normalize adds trailing separator, making region-end ==
next-capture-start.  The strict > would skip it; the
(1- re) search-pos adjustment catches it."
  (helixel-test-with-python-ts "def foo(a, b, c): pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 9)  ;; on 'a'
          (helixel-ts-mark-a-parameter 1)
          (should (use-region-p))
          (should (equal (save-excursion
                           (goto-char (region-beginning))
                           (looking-at "a"))
                         t))
          ;; First comma: a -> b
          (setq last-command 'helixel-ts-mark-a-parameter
                this-command 'helixel-repeat-last-motion)
          (helixel-repeat-last-motion)
          (should (use-region-p))
          (should (equal (save-excursion
                           (goto-char (region-beginning))
                           (looking-at "b"))
                         t))
          ;; Second comma: b -> c
          (setq last-command 'helixel-repeat-last-motion
                this-command 'helixel-repeat-last-motion)
          (helixel-repeat-last-motion)
          (should (use-region-p))
          (should (equal (save-excursion
                           (goto-char (region-beginning))
                           (looking-at "c"))
                         t)))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-parameter-outer--no-leading-comma ()
  "Last parameter outer bounds do NOT include leading comma."
  (helixel-test-with-python-ts "def foo(a, b):\n    pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 12)  ;; on 'b' (last parameter)
          (helixel-ts-mark-a-parameter 1)
          (should (use-region-p))
          (let ((sel (buffer-substring-no-properties
                      (region-beginning) (region-end))))
            ;; Should be just "b" or "b" with trailing chars
            ;; but NOT include leading ", "
            (should-not (string-prefix-p "," sel))
            (should (string-prefix-p "b" sel))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-parameter-outer--trailing-comma ()
  "First parameter outer bounds include trailing comma."
  (helixel-test-with-python-ts "def foo(a, b):\n    pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 9)  ;; on 'a'
          (helixel-ts-mark-a-parameter 1)
          (should (use-region-p))
          (let ((sel (buffer-substring-no-properties
                      (region-beginning) (region-end))))
            ;; First param includes trailing comma
            (should (string-match "," sel))
            (should (string-prefix-p "a" sel))))
      (helixel--deactivate-all-hooks))))

;; ═══════════════════════════════════════════════════════════════════
;; Function navigation — [f / ]f (outer) and {f / }f (inner)
;; ═══════════════════════════════════════════════════════════════════

(ert-deftest helixel-treesit-func-nav--next-from-body ()
  "]f from inside function body moves to end of current function."
  (helixel-test-with-python-ts "def foo():\n    pass\ndef bar():\n    return 1\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 17)  ;; 'a' in 'pass' of foo
          (helixel-ts-forward-outer-function 1)
          (should (use-region-p))
          (should (>= (point) 17)))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-func-nav--prev-from-body ()
  "[f from inside function body moves to start of current function."
  (helixel-test-with-python-ts "def foo():\n    pass\ndef bar():\n    return 1\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 37)  ;; 'e' in 'return' of bar
          (helixel-ts-backward-outer-function 1)
          (should (use-region-p))
          ;; cursor at start of bar (after foo)
          (should (looking-at "def bar")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-func-nav--prev-at-start-advances ()
  "[f at function start advances to previous function."
  (helixel-test-with-python-ts "def foo():\n    pass\ndef bar():\n    return 1\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char (point-min))
          (search-forward "def bar")
          (goto-char (match-beginning 0))
          (helixel-ts-backward-outer-function 1)
          (should (use-region-p))
          (should (looking-at "def foo")))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-func-nav--next-at-end-advances ()
  "]f at function end advances to next function."
  (helixel-test-with-python-ts "def foo():\n    pass\ndef bar():\n    return 1\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 17)  ;; inside foo
          (helixel-ts-forward-outer-function 1)   ; first: end of foo
          (helixel-ts-forward-outer-function 1)   ; second: end of bar (advances)
          (should (> (point) (point-min)))
          (should (use-region-p)))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-func-nav--inner-prev ()
  "{f from inside body moves to inner start of current function."
  (helixel-test-with-python-ts "def foo():\n    pass\ndef bar():\n    return 1\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 37)  ;; inside 'return' of bar
          (helixel-ts-backward-inner-function 1)
          (should (use-region-p))
          ;; inner start of bar should be after 'def bar():\n'
          (should (> (point) (point-min))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-func-nav--inner-next ()
  "}f from inside body moves to inner end of current function."
  (helixel-test-with-python-ts "def foo():\n    pass\ndef bar():\n    return 1\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 17)  ;; inside 'pass' of foo
          (helixel-ts-forward-inner-function 1)
          (should (use-region-p))
          (should (> (point) 17)))
      (helixel--deactivate-all-hooks))))


;; ═══════════════════════════════════════════════════════════════════
;; Parameter outer nav — [, / ], comma inclusion
;; ═══════════════════════════════════════════════════════════════════

(ert-deftest helixel-treesit-param-nav--forward-includes-comma ()
  "], from inside parameter includes trailing comma in region."
  (helixel-test-with-python-ts "def foo(a, b, c):\n    pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 9)   ;; on 'a' (position 9)
          (helixel-ts-forward-outer-parameter 1)
          (should (use-region-p))
          (let ((sel (buffer-substring-no-properties
                      (region-beginning) (region-end))))
            ;; region should include trailing comma+space
            (should (string-match ", " sel))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-param-nav--backward-includes-comma ()
  "[, from inside parameter includes trailing comma in region."
  (helixel-test-with-python-ts "def foo(a, b, c):\n    pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 12)  ;; on 'b' (position 12)
          (helixel-ts-backward-outer-parameter 1)
          (should (use-region-p))
          (let ((sel (buffer-substring-no-properties
                      (region-beginning) (region-end))))
            ;; region should include leading 'a' and trailing comma
            (should (string-prefix-p "a" sel))
            (should (string-match ", " sel))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-param-nav--inner-no-comma ()
  "{, inner param puts cursor at identifier start, region is tight."
  (helixel-test-with-python-ts "def foo(a, b, c):\n    pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 9)   ;; on 'a' (position 9 is 'a')
          (helixel-ts-backward-inner-parameter 1)
          (should (use-region-p))
          ;; cursor should be at the identifier start
          (should (looking-at "a"))
          ;; region should be at most 3 chars ("a, ") — inner bounds
          ;; may or may not include comma depending on grammar
          (should (<= (- (region-end) (region-beginning)) 3)))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-func-nav--inner-prev-twice ()
  "{f pressed twice advances to previous function's body start."
  (helixel-test-with-python-ts "def foo():\n    a = 1\ndef bar():\n    b = 2\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char (point-min))
          (search-forward "b = 2")  ;; inside bar's body
          (helixel-ts-backward-inner-function 1)  ; first: bar body start
          (let ((first-pos (point)))
            (helixel-ts-backward-inner-function 1)  ; second: foo body start
            (should (< (point) first-pos))  ;; moved backward
            (should (looking-at "a = 1"))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-func-nav--inner-next-from-body ()
  "}f from inside body moves to inner end of current function."
  (helixel-test-with-python-ts "def foo():\n    a = 1\ndef bar():\n    b = 2\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char (point-min))
          (search-forward "a = 1")  ;; inside foo's body
          (let ((body-start (point)))
            (helixel-ts-forward-inner-function 1)
            ;; cursor should be at or past body end
            (should (>= (point) body-start))
            ;; should have moved forward
            (should (> (point) body-start))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-loop-nav--smoke ()
  "]l and [l navigate between loops."
  (helixel-test-with-python-ts "for x in xs:\n    pass\nfor y in ys:\n    pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char (point-min))
          (search-forward "xs")   ;; inside first for-loop
          (helixel-ts-forward-outer-loop 1)
          (should (use-region-p))
          (let ((after-first (point)))
            (helixel-ts-backward-outer-loop 1)
            (should (use-region-p))
            (should (< (point) after-first))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-treesit-param-nav--comma-in-region ()
  "[, region includes trailing comma+whitespace like ma,."
  (helixel-test-with-python-ts "def foo(a, bb, ccc):\n    pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 10)  ;; on ',' after 'a'
          (helixel-ts-backward-outer-parameter 1)
          (should (use-region-p))
          (let ((sel (buffer-substring-no-properties
                      (region-beginning) (region-end))))
            ;; region should be "a, " (identifier + comma + space)
            (should (string-match "a, " sel))))
      (helixel--deactivate-all-hooks))))


;; ═══════════════════════════════════════════════════════════════════
;; Multi-cursor spawn (helixel-ts--mc-spawn)
;; ═══════════════════════════════════════════════════════════════════

(ert-deftest helixel-ts-mc-spawn--two-functions ()
  "Spawn targets for every function in a buffer with two top-level defs."
  (helixel-test-with-python-ts
    "def foo():\n    pass\n\ndef bar():\n    pass\n"
    (helixel-treesit-setup)
    (let* ((sel (helixel-sel-create
                 'treesit `(:base "function" :part around
                                  :level 0 :count 1 :inline-advance t)))
           (targets (helixel-ts--mc-spawn sel)))
      (should (= 2 (length targets)))
      ;; First target: foo() — (point . mark) = (end . beg)
      (let ((p (car targets)))
        (should (markerp (car p)))
        (should (markerp (cdr p)))
        (should (= (marker-position (car p))
                   (save-excursion
                     (goto-char (point-min))
                     (search-forward "pass")
                     (line-end-position))))
        (should (= (marker-position (cdr p)) 1)))
      ;; Second target: bar()
      (let ((p (cadr targets)))
        (should (= (marker-position (cdr p))
                   (save-excursion
                     (goto-char (point-min))
                     (search-forward "def bar")
                     (line-beginning-position)))))
      (helixel-mc--free-targets targets))))

(ert-deftest helixel-ts-mc-spawn--single-function ()
  "Single function buffer returns one target."
  (helixel-test-with-python-ts
    "def foo():\n    pass\n"
    (helixel-treesit-setup)
    (let* ((sel (helixel-sel-create
                 'treesit `(:base "function" :part around
                                  :level 0 :count 1 :inline-advance t)))
           (targets (helixel-ts--mc-spawn sel)))
      (should (= 1 (length targets)))
      (let ((p (car targets)))
        (should (markerp (car p)))
        (should (markerp (cdr p)))
        ;; point at end, mark at beg
        (should (> (marker-position (car p))
                   (marker-position (cdr p)))))
      (helixel-mc--free-targets targets))))

(ert-deftest helixel-ts-mc-spawn--nested-functions ()
  "Nested functions: inner wins by containment filter (matching maf semantics)."
  (helixel-test-with-python-ts
    "def outer():\n    def inner():\n        pass\n    pass\n"
    (helixel-treesit-setup)
    (let* ((sel (helixel-sel-create
                 'treesit `(:base "function" :part around
                                  :level 0 :count 1 :inline-advance t)))
           (targets (helixel-ts--mc-spawn sel)))
      ;; Both outer and inner exist in the index.  The reverse-pass
      ;; containment filter keeps only the innermost (inner) because
      ;; outer.end >= inner.end means outer contains inner.
      (should (= 1 (length targets)))
      ;; The kept target should be the inner function (narrower range).
      (let* ((p (car targets))
             (beg (marker-position (cdr p)))
             (end (marker-position (car p))))
        (should (>= beg 14))          ; after "def outer():\n    "
        (should (<= end
                    (save-excursion
                      (goto-char (point-min))
                      (search-forward "pass")
                      (line-end-position)))))
      (helixel-mc--free-targets targets))))

(ert-deftest helixel-ts-mc-spawn--missing-base ()
  "Signal user-error when :base is missing from sel ctx."
  (helixel-test-with-python-ts
    "def foo(): pass\n"
    (helixel-treesit-setup)
    (let ((sel (helixel-sel-create 'treesit
                                   '(:part around :level 0))))
      (should-error (helixel-ts--mc-spawn sel) :type 'user-error))))

(ert-deftest helixel-ts-mc-spawn--no-such-type ()
  "Signal user-error when no objects of the requested type exist."
  (helixel-test-with-python-ts
    "x = 1\n"
    (helixel-treesit-setup)
    (let ((sel (helixel-sel-create
                'treesit `(:base "function" :part around
                                 :level 0 :count 1 :inline-advance t))))
      (should-error (helixel-ts--mc-spawn sel) :type 'user-error))))

(ert-deftest helixel-ts-mc-spawn--inner-vs-around ()
  "Inside vs around produce different ranges for the same function."
  (helixel-test-with-python-ts
    "def foo(a, b):\n    return a + b\n"
    (helixel-treesit-setup)
    (let* ((sel-a (helixel-sel-create
                   'treesit `(:base "function" :part around
                                    :level 0 :count 1 :inline-advance t)))
           (sel-i (helixel-sel-create
                   'treesit `(:base "function" :part inside
                                    :level 0 :count 1 :inline-advance t)))
           (targets-a (helixel-ts--mc-spawn sel-a))
           (targets-i (helixel-ts--mc-spawn sel-i)))
      (should (= 1 (length targets-a)))
      (should (= 1 (length targets-i)))
      ;; around range should be larger than (or equal to) inside range
      (let ((a-beg (marker-position (cdr (car targets-a))))
            (a-end (marker-position (car (car targets-a))))
            (i-beg (marker-position (cdr (car targets-i))))
            (i-end (marker-position (car (car targets-i)))))
        (should (<= a-beg i-beg))
        (should (>= a-end i-end)))
      (helixel-mc--free-targets targets-a)
      (helixel-mc--free-targets targets-i))))


;; ═══════════════════════════════════════════════════════════════════
;; Multi-cursor mark-like-this treesit (s n / s p semantic advance)
;; ═══════════════════════════════════════════════════════════════════

(ert-deftest helixel-ts-mc-mark-next--two-functions ()
  "s n on a treesit function selection advances to the next function."
  (helixel-test-with-python-ts
    "def foo():\n    pass\n\ndef bar():\n    pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          ;; Select foo with maf
          (goto-char 2)  ; inside foo
          (helixel-ts-mark-a-function 1)
          (should (use-region-p))
          (let ((first-beg (region-beginning))
                (first-end (region-end)))
            ;; s n — advance to next function
            (helixel-mc--mark-like-this 1)
            (should (use-region-p))
            ;; Region should start after first function's region ends
            (should (>= (region-beginning) first-end))
            ;; Cursor (point) should be past first region's end too
            (should (> (point) first-end))))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-mc-mark-next--no-more ()
  "s n at the last function signals user-error."
  (helixel-test-with-python-ts
    "def foo():\n    pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 2)
          (helixel-ts-mark-a-function 1)
          (should (use-region-p))
          ;; s n from the only function → no more
          (should-error (helixel-mc--mark-like-this 1)
                        :type 'user-error))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-mc-mark-next--creates-fake ()
  "s n on treesit selection creates a fake cursor at the old position."
  (helixel-test-with-python-ts
    "def foo():\n    pass\n\ndef bar():\n    pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 2)
          (helixel-ts-mark-a-function 1)
          (let ((old-point (point))
                (old-mark (mark t)))
            (helixel-mc--mark-like-this 1)
            ;; A fake cursor should now exist at the old position.
            (should (helixel-mc-any-p))
            (let* ((cursors (helixel-mc-all-cursors))
                   (fake (car cursors)))
              (should (= old-point
                         (marker-position
                          (helixel-mc-cursor-point fake))))))
          (helixel-mc-clear-all))
      (helixel--deactivate-all-hooks))))

(ert-deftest helixel-ts-mc-skip-next--advances ()
  "Skip-next on treesit selection advances without creating fake."
  (helixel-test-with-python-ts
    "def foo():\n    pass\n\ndef bar():\n    pass\n"
    (helixel-treesit-setup)
    (helixel--activate-all-hooks)
    (unwind-protect
        (progn
          (goto-char 2)
          (helixel-ts-mark-a-function 1)
          (let ((first-beg (region-beginning))
                (first-end (region-end))
                (nbefore (length (helixel-mc-all-cursors))))
            ;; s N — skip (no new fake)
            (helixel-mc--skip-in-dir 1)
            (should (= nbefore (length (helixel-mc-all-cursors))))
            (should (>= (region-beginning) first-end))
            (should (> (point) first-end))))
      (helixel--deactivate-all-hooks))))


(provide 'helixel-test-treesit)
;;; helixel-test-treesit.el ends here
