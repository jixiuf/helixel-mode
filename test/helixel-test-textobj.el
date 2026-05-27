;;; helixel-test-textobj.el --- Tests for Helixel: text objects and blocks  -*- lexical-binding: t; -*-

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

;;; Word text object tests

(ert-deftest helixel-test-textobj-word-basic ()
  "Test basic word text object selection."
  (with-temp-buffer
    (insert ";; This buffer is for notes.")
    (goto-char 4) ; at "T" of "This"
    (call-interactively #'helixel-mark-inner-word)
    (should (eql (region-beginning) 4))
    (should (eql (region-end) 8)))
  (with-temp-buffer
    (insert ";; This buffer is for notes.")
    (goto-char 4)
    (call-interactively #'helixel-mark-a-word)
    (should (eql (region-beginning) 4))
    (should (eql (region-end) 9))))

(ert-deftest helixel-test-textobj-word-select-first ()
  "Test selecting first word in buffer."
  (with-temp-buffer
    (insert "(a)")
    (goto-char 2) ; inside the parens, on "a"
    (call-interactively #'helixel-mark-inner-word)
    (should (eql (region-beginning) 2))
    (should (eql (region-end) 3))))

(ert-deftest helixel-test-textobj-word-whitespace-line-bound ()
  "Test selecting word when surrounded by whitespace."
  (with-temp-buffer
    (insert "foo\n  bar")
    (goto-char 7)
    (call-interactively #'helixel-mark-inner-word)
    (should (= (region-beginning) 7))))

(ert-deftest helixel-test-textobj-WORD-basic ()
  "Test basic WORD text object selection."
  (with-temp-buffer
    (insert ";; This buffer is for notes.")
    (goto-char 4)
    (call-interactively #'helixel-mark-inner-WORD)
    (should (= (region-beginning) 4))
    (should (= (region-end) 8))))

(ert-deftest helixel-test-textobj-word-cjk ()
  "Test word text object with CJK characters."
  (with-temp-buffer
    (insert "abc漢字")
    (goto-char 1)
    (call-interactively #'helixel-mark-inner-word)
    (should (= (region-beginning) 1))
    (should (= (region-end) 4))))

;;; Symbol text object tests

(ert-deftest helixel-test-textobj-symbol-basic ()
  "Test basic symbol text object selection."
  (with-temp-buffer
    (insert ";; This buffer is for notes.")
    (goto-char 4) ; at "T" of "This"
    (call-interactively #'helixel-mark-inner-symbol)
    (should (= (region-beginning) 4))
    (should (= (region-end) 8))))

;;; Sentence text object tests

(ert-deftest helixel-test-textobj-sentence-basic ()
  "Test basic sentence text object selection."
  (with-temp-buffer
    (insert "This is sentence one. This is sentence two.")
    (goto-char 1)
    (call-interactively #'helixel-mark-inner-sentence)
    (should (= (region-beginning) 1))
    (should (= (region-end) 44))))

(ert-deftest helixel-test-textobj-sentence-select ()
  "Test selecting sentence from middle."
  (with-temp-buffer
    (insert "This is sentence one. This is sentence two.")
    (goto-char 10)
    (call-interactively #'helixel-mark-inner-sentence)
    (should (= (region-beginning) 1))
    (should (= (region-end) 44))))

;;; Paragraph text object tests

(ert-deftest helixel-test-textobj-paragraph-basic ()
  "Test basic paragraph text object selection."
  (with-temp-buffer
    (insert ";; This buffer is for notes,
;; and for Lisp evaluation.

;; Another paragraph here.")
    (goto-char 1)
    (call-interactively #'helixel-mark-inner-paragraph)
    (should (= (region-beginning) 1))
    (should (= (region-end) 58))))

(ert-deftest helixel-test-textobj-paragraph-select ()
  "Test selecting paragraph at different positions."
  (with-temp-buffer
    (insert "First paragraph.

Second paragraph.")
    (goto-char 1)
    (call-interactively #'helixel-mark-inner-paragraph)
    (should (= (region-beginning) 1))
    (should (= (region-end) 18))))

;;; Outer (a) text object tests

(ert-deftest helixel-test-textobj-a-word ()
  "Test a-word text object selection."
  (with-temp-buffer
    (insert ";; This buffer is for notes.")
    (goto-char 4)
    (call-interactively #'helixel-mark-a-word)
    (should (= (region-beginning) 4))
    (should (= (region-end) 9))))

(ert-deftest helixel-test-textobj-a-symbol ()
  "Test a-symbol text object selection."
  (with-temp-buffer
    (insert ";; This buffer is for notes.")
    (goto-char 4)
    (call-interactively #'helixel-mark-a-symbol)
    (should (= (region-beginning) 4))
    (should (= (region-end) 9))))

(ert-deftest helixel-test-textobj-a-sentence ()
  "Test a-sentence text object selection."
  (with-temp-buffer
    (insert "This is sentence one. This is sentence two.")
    (goto-char 1)
    (call-interactively #'helixel-mark-a-sentence)
    (should (= (region-beginning) 1))
    (should (= (region-end) 44))))

(ert-deftest helixel-test-textobj-a-paragraph ()
  "Test a-paragraph text object selection."
  (with-temp-buffer
    (insert ";; This buffer is for notes,
;; and for Lisp evaluation.

;; Another paragraph here.")
    (goto-char 1)
    (call-interactively #'helixel-mark-a-paragraph)
    (should (= (region-beginning) 1))
    (should (= (region-end) 58))))

;;; Paren text object tests

 (ert-deftest helixel-test-textobj-paren-inner ()
  "Test inner paren text object."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 2)
    (call-interactively #'helixel-mark-inner-paren)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))))

 (ert-deftest helixel-test-textobj-paren-outer ()
  "Test outer paren text object."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 2)
    (call-interactively #'helixel-mark-a-paren)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

;;; Bracket text object tests

 (ert-deftest helixel-test-textobj-bracket-inner ()
  "Test inner bracket text object."
  (with-temp-buffer
    (insert "[hello]")
    (goto-char 2)
    (call-interactively #'helixel-mark-inner-bracket)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))))

 (ert-deftest helixel-test-textobj-bracket-outer ()
  "Test outer bracket text object."
  (with-temp-buffer
    (insert "[hello]")
    (goto-char 2)
    (call-interactively #'helixel-mark-a-bracket)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

;;; Brace text object tests

 (ert-deftest helixel-test-textobj-brace-inner ()
  "Test inner brace text object."
  (with-temp-buffer
    (insert "{hello}")
    (goto-char 2)
    (call-interactively #'helixel-mark-inner-brace)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))))

 (ert-deftest helixel-test-textobj-brace-outer ()
  "Test outer brace text object."
  (with-temp-buffer
    (insert "{hello}")
    (goto-char 2)
    (call-interactively #'helixel-mark-a-brace)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

;;; Angle bracket text object tests

 (ert-deftest helixel-test-textobj-angle-inner ()
  "Test inner angle bracket text object."
  (with-temp-buffer
    (insert "<hello>")
    (goto-char 2)
    (call-interactively #'helixel-mark-inner-angle)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))))

 (ert-deftest helixel-test-textobj-angle-outer ()
  "Test outer angle bracket text object."
  (with-temp-buffer
    (insert "<hello>")
    (goto-char 2)
    (call-interactively #'helixel-mark-a-angle)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

;;; Paren core-correctness tests

(ert-deftest helixel-test-textobj-paren-nested-inner ()
  "mi( selects innermost paren pair in ((inner) outer)."
  (with-temp-buffer
    (insert "((inner) outer)")
    (goto-char 4)                  ; on 'n' of inner
    (call-interactively #'helixel-mark-inner-paren)
    (should (= (region-beginning) 3))
    (should (= (region-end) 8))))

(ert-deftest helixel-test-textobj-paren-nested-2count ()
  "2mi( selects the outer paren pair in ((inner) outer)."
  (with-temp-buffer
    (insert "((inner) outer)")
    (goto-char 4)                  ; on 'n' of inner
    (call-interactively (lambda () (interactive)
                           (helixel-mark-inner-paren 2)))
    ;; Outer exclusive range: (cdr op . car cl) = (2 . 15)
    ;; after outer ( at pos 1, includes inner ( at pos 2
    (should (= (region-beginning) 2))
    (should (= (region-end) 15))))

(ert-deftest helixel-test-textobj-paren-cursor-on-delimiter ()
  "mi( with cursor on '(' selects inner content."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 1)                  ; on '('
    (call-interactively #'helixel-mark-inner-paren)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))))

(ert-deftest helixel-test-textobj-paren-cursor-on-close-delimiter ()
  "mi( with cursor on ')' selects inner content."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 7)                  ; on ')'
    (call-interactively #'helixel-mark-inner-paren)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))))

(ert-deftest helixel-test-textobj-paren-multiline ()
  "mi( works across multiple lines."
  (with-temp-buffer
    (insert "(\nhello\nworld\n)")
    (goto-char 4)
    (call-interactively #'helixel-mark-inner-paren)
    ;; inner = content between ( and ), exclusive
    (should (= (region-beginning) 3))
    (should (= (region-end) 15))))

(ert-deftest helixel-test-textobj-paren-empty ()
  "mi( on empty parens () returns zero-width selection."
  (with-temp-buffer
    (insert "()")
    (goto-char 1)                  ; on '('
    (call-interactively #'helixel-mark-inner-paren)
    ;; inner selection is empty: region-beginning == region-end
    (should (= (region-beginning) (region-end)))
    (should (= (region-beginning) 2))))

;;; Quote edge-case tests

(ert-deftest helixel-test-textobj-quote-escaped ()
  "Quoted string with escaped inner quotes is selected correctly."
  (with-temp-buffer
    (insert "\"hello \\\"world\\\"!\"")
    (goto-char 4)
    (call-interactively #'helixel-mark-inner-double-quote)
    ;; inner content: hello \"world\"! (between outer quotes)
    (should (= (region-beginning) 2))
    ;; End should be at the position before the closing "
    (should (char-equal (char-before (region-end)) ?!))))

;;; Quote text object tests

(ert-deftest helixel-test-textobj-single-quote-inner ()
  "Test inner single-quote text object."
  (with-temp-buffer
    (insert "'hello'")
    (goto-char 2)
    (call-interactively #'helixel-mark-inner-single-quote)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))))

(ert-deftest helixel-test-textobj-single-quote-outer ()
  "Test outer single-quote text object."
  (with-temp-buffer
    (insert "'hello'")
    (goto-char 2)
    (call-interactively #'helixel-mark-a-single-quote)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

(ert-deftest helixel-test-textobj-double-quote-inner ()
  "Test inner double-quote text object."
  (with-temp-buffer
    (insert "\"hello\"")
    (goto-char 2)
    (call-interactively #'helixel-mark-inner-double-quote)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))))

(ert-deftest helixel-test-textobj-double-quote-outer ()
  "Test outer double-quote text object."
  (with-temp-buffer
    (insert "\"hello\"")
    (goto-char 2)
    (call-interactively #'helixel-mark-a-double-quote)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

(ert-deftest helixel-test-textobj-back-quote-inner ()
  "Test inner back-quote text object."
  (with-temp-buffer
    (insert "`hello`")
    (goto-char 2)
    (call-interactively #'helixel-mark-inner-back-quote)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))))

(ert-deftest helixel-test-textobj-back-quote-outer ()
  "Test outer back-quote text object."
  (with-temp-buffer
    (insert "`hello`")
    (goto-char 2)
    (call-interactively #'helixel-mark-a-back-quote)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

;;; Tag text object edge-case tests

(ert-deftest helixel-test-textobj-tag-with-attrs ()
  "Tag textobj works with attributes like <div class='x'>."
  (with-temp-buffer
    (insert "<div class=\"foo\">bar</div>")
    (goto-char 10)
    (call-interactively #'helixel-mark-inner-tag)
    ;; inner content = "bar" (between > and </)
    (should (= (region-beginning) 18))
    (should (= (region-end) 21))))

(ert-deftest helixel-test-textobj-tag-nested ()
  "mit inside <div><p>text</p></div> selects innermost <p>."
  (with-temp-buffer
    (insert "<div><p>text</p></div>")
    (goto-char 10)                 ; on 't' of text
    (call-interactively #'helixel-mark-inner-tag)
    ;; inner <p> content = "text"
    (should (= (region-beginning) 9))
    (should (= (region-end) 13))))

(ert-deftest helixel-test-textobj-tag-mismatched ()
  "mit on <div>text</span> should error (mismatched tags)."
  (with-temp-buffer
    (insert "<div>text</span>")
    (goto-char 3)
    (should-error (call-interactively #'helixel-mark-inner-tag))))

;;; Tag text object tests

(ert-deftest helixel-test-textobj-tag-inner ()
  "Test inner tag text object."
  (with-temp-buffer
    (insert "<foo>bar</foo>")
    (goto-char 2)
    (call-interactively #'helixel-mark-inner-tag)
    (should (= (region-beginning) 6))
    (should (= (region-end) 9))))

(ert-deftest helixel-test-textobj-tag-outer ()
  "Test outer tag text object."
  (with-temp-buffer
    (insert "<foo>bar</foo>")
    (goto-char 2)
    (call-interactively #'helixel-mark-a-tag)
    (should (= (region-beginning) 1))
    (should (= (region-end) 15))))

;;; Text object non-expansion tests

(ert-deftest helixel-test-textobj-no-expand-region-word ()
  "Test text-object replaces rather than expands active region."
  (helixel-test-with-buffer "hello world foo"
    (push-mark 6 nil t)
    (goto-char 1)
    (should (region-active-p))
    (goto-char 7)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (call-interactively #'helixel-mark-inner-word)
    (should (= (region-beginning) 7))
    (should (= (region-end) 12))))

(ert-deftest helixel-test-textobj-no-expand-region-paren ()
  "Test text-object replaces rather than expands active region (pairs)."
  (helixel-test-with-buffer "foo (hello) bar"
    (push-mark 4 nil t)
    (goto-char 1)
    (should (region-active-p))
    (goto-char 7)
    (setq last-command nil this-command 'helixel-mark-inner-paren)
    (call-interactively #'helixel-mark-inner-paren)
    (should (= (region-beginning) 6))
    (should (= (region-end) 11))))

(ert-deftest helixel-test-textobj-no-expand-region-quote ()
  "Test text-object replaces rather than expands active region (quotes)."
  (helixel-test-with-buffer "foo 'hello' bar"
    (push-mark 4 nil t)
    (goto-char 1)
    (should (region-active-p))
    (goto-char 7)
    (setq last-command nil this-command 'helixel-mark-inner-single-quote)
    (call-interactively #'helixel-mark-inner-single-quote)
     (should (= (region-beginning) 6))
     (should (= (region-end) 11))))

;;; Textobj: region-active prioritizes highlighted content

(ert-deftest helixel-test-textobj-region-active-prio-inner ()
  "When region is active with content, textobj selects the region content."
  (helixel-test-with-buffer "hello world"
    (push-mark 1 nil t)
    (goto-char 7)
    (call-interactively #'helixel-mark-inner-word)
    (should (= (region-beginning) 1))
    (should (= (region-end) 6))))

(ert-deftest helixel-test-textobj-followup-selects-next-inner ()
  "Second textobj press selects the next word, not expand."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 1)
    (call-interactively #'helixel-mark-inner-word)
    (should (= (region-beginning) 1))
    (should (= (region-end) 6))
    (call-interactively #'helixel-mark-inner-word)
    (should (= (region-beginning) 7))
    (should (= (region-end) 12))))

(ert-deftest helixel-test-textobj-whitespace-adjust ()
  "Cursor on whitespace finds the adjacent word."
  (helixel-test-with-buffer "hello world"
    (goto-char 6)
    (call-interactively #'helixel-mark-inner-word)
    (should (= (region-beginning) 1))
    (should (= (region-end) 6))))

(ert-deftest helixel-test-textobj-followup-selects-next-outer ()
  "Second a-word press selects the next a-word, not expand."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 1)
    (call-interactively #'helixel-mark-a-word)
    (should (= (region-beginning) 1))
    (should (= (region-end) 7))
    (call-interactively #'helixel-mark-a-word)
    (should (= (region-beginning) 7))
    (should (= (region-end) 13))))

;;; Text object action tests

(ert-deftest helixel-test-textobj-session-start ()
  "Test text-object command starts a live event."
  (helixel-test-with-buffer "hello world"
    (setq helixel--event-ring nil helixel--live-event nil helixel--action-pos nil
          last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (should helixel--live-event)
    (should (eq (helixel-event-category helixel--live-event) 'textobj))
    (should (= (marker-position (car (helixel-event-mark-region helixel--live-event))) 1))))

(ert-deftest helixel-test-textobj-session-same-family-continues ()
  "Test same-category text-object commands continue action."
  (helixel-test-with-buffer "(hello) (world)"
    (setq helixel--event-ring nil helixel--live-event nil helixel--action-pos nil
          last-command nil this-command 'helixel-mark-inner-paren)
    (goto-char 2)
    (helixel-mark-inner-paren)
    (should (eq (helixel-event-category helixel--live-event) 'textobj))
    (let ((mark-pos (marker-position (car (helixel-event-mark-region helixel--live-event)))))
      (setq last-command 'helixel-mark-inner-paren this-command 'helixel-mark-a-paren)
      (goto-char 10)
      (helixel-mark-a-paren)
      (should (eq (helixel-event-category helixel--live-event) 'textobj)))))

(ert-deftest helixel-test-textobj-session-different-family-breaks ()
  "Test different-family textobj commits old event to ring."
  (helixel-test-with-buffer "hello (world)"
    (setq helixel--event-ring nil helixel--live-event nil helixel--action-pos nil
          last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word this-command 'helixel-mark-inner-paren)
    (helixel-mark-inner-paren)
    (should (= (length helixel--event-ring) 1))
    (should (eq (helixel-event-subcat helixel--live-event) 'pair))))

(ert-deftest helixel-test-textobj-session-type-property ()
  "Test textobj actions have correct category and subcat."
  (let (helixel--event-ring helixel--live-event helixel--action-pos)
    (helixel-test-with-buffer "hello world"
      (setq last-command nil this-command 'helixel-mark-inner-word)
      (helixel-mark-inner-word)
      (should (eq (helixel-event-category helixel--live-event) 'textobj))
      (should (eq (helixel-event-subcat helixel--live-event) 'word)))))
;;; Regex block text object tests

;; --- helixel-up-regex-block: counter-based (markdown fences) ---

(ert-deftest helixel-test-up-regex-block-counter-same ()
  "Test counter-based up-regex-block with same begin/end (markdown fence)."
  (with-temp-buffer
    (insert "before\n```\ncode\n```\nafter\n```\nmore\n```\ndone")
    (goto-char 1)
    (let ((mb (save-excursion
                (should (= (helixel-up-regex-block "^```" "^```" 1 nil) 0))
                (match-beginning 0))))
      (should mb)
      (goto-char mb)
      (should (looking-at "```$")))))

(ert-deftest helixel-test-up-regex-block-counter-diff ()
  "Test counter-based up-regex-block with different begin/end."
  (with-temp-buffer
    (insert "before\n#+begin\na\n#+begin\nb\n#+end\nc\n#+end\nafter")
    (goto-char (point-min))
    (search-forward "a")
    (let ((mb (save-excursion
                (should (= (helixel-up-regex-block "^#\\+begin" "^#\\+end" 1 nil) 0))
                (match-beginning 0))))
      (should mb)
      (goto-char mb)
      (should (looking-at "^#\\+end$")))))

;; --- helixel-up-regex-block: name-based (org blocks) ---

(ert-deftest helixel-test-up-regex-block-named-forward ()
  "Test named up-regex-block forward (org block)."
  (with-temp-buffer
    (insert "#+begin_src emacs-lisp\ncode\n#+end_src\nafter")
    (goto-char (point-min))
    (let ((mb (save-excursion
                (should (= (helixel-up-regex-block "^#\\+begin_\\([^ \n\r]+\\)"
                                                   "^#\\+end_\\([^ \n\r]+\\)"
                                                   1 1) 0))
                (match-beginning 0))))
      (should mb)
      (goto-char mb)
      (should (looking-at "^#\\+end_src")))))

(ert-deftest helixel-test-up-regex-block-named-nested ()
  "Test named up-regex-block with nested org blocks."
  (with-temp-buffer
    (insert "#+begin_src emacs-lisp\nouter\n#+begin_example\ninner\n#+end_example\nmore\n#+end_src")
    (goto-char (point-min))
    (let ((mb (save-excursion
                (should (= (helixel-up-regex-block "^#\\+begin_\\([^ \n\r]+\\)"
                                                   "^#\\+end_\\([^ \n\r]+\\)"
                                                   1 1) 0))
                (match-beginning 0))))
      (should mb)
      (goto-char mb)
      (should (looking-at "^#\\+end_src")))))

;; --- helixel-select-regex-block integration ---

(ert-deftest helixel-test-select-regex-block-inner-fence ()
  "Test select inner markdown fence block."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "```python\nprint('hello')\n```")
    (goto-char 14)
    (let ((range (helixel-select-regex-block "^```.+$" "^```[ \t]*$"
                                              nil nil nil 1 nil)))
      (should range)
      (should (> (nth 0 range) 1))
      (should (< (nth 0 range) 14))
      (should (> (nth 1 range) (nth 0 range)))
      (should (< (nth 1 range) (point-max))))))

(ert-deftest helixel-test-select-regex-block-around-fence ()
  "Test select around markdown fence block."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "```python\nprint('hello')\n```")
    (goto-char 14)
    (let ((range (helixel-select-regex-block "^```.+$" "^```[ \t]*$"
                                              nil nil nil 1 t)))
      (should range)
      (should (= (nth 0 range) 1))
      (should (> (nth 1 range) 1)))))

(ert-deftest helixel-test-select-regex-block-inner-org ()
  "Test select inner org block."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "#+begin_src emacs-lisp\n(message \"hi\")\n#+end_src\n")
    (goto-char 32)
    (let ((range (helixel-select-regex-block
                  "^#\\+begin_\\([^ \n\r]+\\)[^\n]*" "^#\\+end_\\([^ \n\r]+\\)[^\n]*"
                  nil nil nil 1 nil 1)))
      (should range)
      (should (> (nth 0 range) 1))
      (should (< (nth 0 range) 32))
      (should (> (nth 1 range) (nth 0 range)))
      (should (< (nth 1 range) (point-max))))))

(ert-deftest helixel-test-select-regex-block-around-org ()
  "Test select around org block."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "#+begin_src emacs-lisp\n(message \"hi\")\n#+end_src\n")
    (goto-char 32)
    (let ((range (helixel-select-regex-block
                  "^#\\+begin_\\([^ \n\r]+\\)[^\n]*" "^#\\+end_\\([^ \n\r]+\\)[^\n]*"
                  nil nil nil 1 t 1)))
      (should range)
      (should (= (nth 0 range) 1))
      (should (> (nth 1 range) 1)))))

;; --- helixel-up-block-at-point dispatch ---

(ert-deftest helixel-test-up-block-at-point-org ()
  "Test `helixel-up-block-at-point' dispatches to org block in org-mode."
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert "#+begin_src emacs-lisp\ncode\n#+end_src")
    (goto-char (point-min))
    (let ((mb (save-excursion
                (should (= (helixel-up-block-at-point 1) 0))
                (match-beginning 0))))
      (should mb)
      (goto-char mb)
      (should (looking-at "^#\\+end_src")))))

(ert-deftest helixel-test-up-block-at-point-unsupported ()
  "Test `helixel-up-block-at-point' errors in unsupported mode."
  (with-temp-buffer
    (delay-mode-hooks (fundamental-mode))
    (insert "```\ncode\n```")
    (goto-char (point-min))
    (should-error (helixel-up-block-at-point 1))))

(ert-deftest helixel-test-block-inner-nested-fence-in-org ()
  "Inner block selects innermost fence inside an org block."
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert "#+begin_ai\nhello\n```sh\nsudo emerge\ndev-python\n```\nworld\n#+end_ai")
    (goto-char (point-min))
    (search-forward "sudo")
    (let* ((helixel-textobj-visual-state-p-function nil)
           (helixel-textobj-action-function nil))
      (setq helixel--block-chosen-spec nil)
      (call-interactively #'helixel-mark-inner-block)
      (message "region: %d-%d content: '%s'" 
               (region-beginning) (region-end)
               (buffer-substring (region-beginning) (region-end)))
      (should (> (region-beginning) 20))
      (should (< (region-end) 50)))))

(ert-deftest helixel-test-block-fallback-brackets ()
  "Fallback selects bracket pairs in fundamental-mode."
  (with-temp-buffer
    (delay-mode-hooks (fundamental-mode))
    (insert "before (inner) after")
    (goto-char (point-min))
    (search-forward "nne")
    (let* ((helixel-textobj-visual-state-p-function nil)
           (helixel-textobj-action-function nil))
      (setq helixel--block-chosen-spec nil)
      (call-interactively #'helixel-mark-inner-block)
      ;; inner = content between parens, excluding parens
      (should (= (region-beginning) 9))   ; after (
      (should (= (region-end) 14)))))     ; at )

;;; helixel-test-textobj.el ends here
