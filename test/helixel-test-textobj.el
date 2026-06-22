;;; helixel-test-textobj.el --- Tests for Helixel: text objects and blocks  -*- lexical-binding: t; -*-

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
(require 'helixel-test-common)


;;; Word text object tests

(ert-deftest helixel-test-textobj-word-basic ()
  "Test basic word text object selection."
  (helixel-test-with-buffer '(:text ";; This buffer is for notes." :start 4)
    (call-interactively #'helixel-mark-inner-word)
    (should (eql (region-beginning) 4))
    (should (eql (region-end) 8))
)
  (helixel-test-with-buffer '(:text ";; This buffer is for notes." :start 4)
    (call-interactively #'helixel-mark-a-word)
    (should (eql (region-beginning) 4))
    (should (eql (region-end) 9))
))

(ert-deftest helixel-test-textobj-word-select-first ()
  "Test selecting first word in buffer."
  (helixel-test-with-buffer '(:text "(a)" :start 2)
    (call-interactively #'helixel-mark-inner-word)
    (should (eql (region-beginning) 2))
    (should (eql (region-end) 3))
))

(ert-deftest helixel-test-textobj-word-whitespace-line-bound ()
  "Test selecting word when surrounded by whitespace."
  (helixel-test-with-buffer '(:text "foo
  bar" :start 7)
    (call-interactively #'helixel-mark-inner-word)
    (should (= (region-beginning) 7))
))

(ert-deftest helixel-test-textobj-WORD-basic ()
  "Test basic WORD text object selection."
  (helixel-test-with-buffer '(:text ";; This buffer is for notes." :start 4)
    (call-interactively #'helixel-mark-inner-WORD)
    (should (= (region-beginning) 4))
    (should (= (region-end) 8))
))

(ert-deftest helixel-test-textobj-word-cjk ()
  "Test word text object with CJK characters."
  (helixel-test-with-buffer "abc漢字"
    (call-interactively #'helixel-mark-inner-word)
    (should (= (region-beginning) 1))
    (should (= (region-end) 4))
))

;;; Symbol text object tests

(ert-deftest helixel-test-textobj-symbol-basic ()
  "Test basic symbol text object selection."
  (helixel-test-with-buffer '(:text ";; This buffer is for notes." :start 4)
    (call-interactively #'helixel-mark-inner-symbol)
    (should (= (region-beginning) 4))
    (should (= (region-end) 8))
))

(ert-deftest helixel-test-textobj-eob-symbol ()
  "Test inner symbol at end of buffer selects last symbol."
  (helixel-test-with-buffer '(:text "hello world" :start (point-max))
    (call-interactively #'helixel-mark-inner-symbol)
    (should (= (region-beginning) 7))
    (should (= (region-end) 12))
))     ; end of "world"

(ert-deftest helixel-test-textobj-eob-word ()
  "Test inner word at end of buffer selects last word."
  (helixel-test-with-buffer '(:text "hello world" :start (point-max))
    (call-interactively #'helixel-mark-inner-word)
    (should (= (region-beginning) 7))
    (should (= (region-end) 12))
))

(ert-deftest helixel-test-textobj-eob-a-symbol ()
  "Test a-symbol at end of buffer selects last symbol with leading ws."
  (helixel-test-with-buffer '(:text "hello world" :start (point-max))
    (call-interactively #'helixel-mark-a-symbol)
    (should (= (region-beginning) 6))
    (should (= (region-end) 12))
))

(ert-deftest helixel-test-textobj-eob-trailing-ws ()
  "Test inner symbol at EOB with trailing whitespace skips ws."
  (helixel-test-with-buffer '(:text "hello world   

" :start (point-max))
    (call-interactively #'helixel-mark-inner-symbol)
    (should (= (region-beginning) 7))
    (should (= (region-end) 12))
))

(ert-deftest helixel-test-textobj-eob-multiline ()
  "Test inner symbol at EOB in multiline buffer selects last symbol."
  (helixel-test-with-buffer '(:text "worldworld
hello hello
hello
hello
hello world" :start (point-max))
    (call-interactively #'helixel-mark-inner-symbol)
    (let ((last-line-start (save-excursion (goto-char (point-min)) (forward-line 4) (point)))) (should (= (region-beginning) (+ last-line-start 6))) (should (= (region-end) (point-max))))
))

;;; Sentence text object tests

(ert-deftest helixel-test-textobj-sentence-basic ()
  "Test basic sentence text object selection."
  (helixel-test-with-buffer "This is sentence one. This is sentence two."
    (call-interactively #'helixel-mark-inner-sentence)
    (should (= (region-beginning) 1))
    (should (= (region-end) 44))
))

(ert-deftest helixel-test-textobj-sentence-select ()
  "Test selecting sentence from middle."
  (helixel-test-with-buffer '(:text "This is sentence one. This is sentence two." :start 10)
    (call-interactively #'helixel-mark-inner-sentence)
    (should (= (region-beginning) 1))
    (should (= (region-end) 44))
))

;;; Paragraph text object tests

(ert-deftest helixel-test-textobj-paragraph-basic ()
  "Test basic paragraph text object selection."
  (helixel-test-with-buffer ";; This buffer is for notes,
;; and for Lisp evaluation.

;; Another paragraph here."
    (call-interactively #'helixel-mark-inner-paragraph)
    (should (= (region-beginning) 1))
    (should (= (region-end) 58))
))

(ert-deftest helixel-test-textobj-paragraph-select ()
  "Test selecting paragraph at different positions."
  (helixel-test-with-buffer "First paragraph.

Second paragraph."
    (call-interactively #'helixel-mark-inner-paragraph)
    (should (= (region-beginning) 1))
    (should (= (region-end) 18))
))

;;; Outer (a) text object tests

(ert-deftest helixel-test-textobj-a-word ()
  "Test a-word text object selection."
  (helixel-test-with-buffer '(:text ";; This buffer is for notes." :start 4)
    (call-interactively #'helixel-mark-a-word)
    (should (= (region-beginning) 4))
    (should (= (region-end) 9))
))

(ert-deftest helixel-test-textobj-a-symbol ()
  "Test a-symbol text object selection."
  (helixel-test-with-buffer '(:text ";; This buffer is for notes." :start 4)
    (call-interactively #'helixel-mark-a-symbol)
    (should (= (region-beginning) 4))
    (should (= (region-end) 9))
))

(ert-deftest helixel-test-textobj-a-sentence ()
  "Test a-sentence text object selection."
  (helixel-test-with-buffer "This is sentence one. This is sentence two."
    (call-interactively #'helixel-mark-a-sentence)
    (should (= (region-beginning) 1))
    (should (= (region-end) 44))
))

(ert-deftest helixel-test-textobj-a-paragraph ()
  "Test a-paragraph text object selection."
  (helixel-test-with-buffer ";; This buffer is for notes,
;; and for Lisp evaluation.

;; Another paragraph here."
    (call-interactively #'helixel-mark-a-paragraph)
    (should (= (region-beginning) 1))
    (should (= (region-end) 58))
))

;;; Paren text object tests

 (ert-deftest helixel-test-textobj-paren-inner ()
  "Test inner paren text object."
  (helixel-test-with-buffer '(:text "(hello)" :start 2)
    (call-interactively #'helixel-mark-inner-paren)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))
))

 (ert-deftest helixel-test-textobj-paren-outer ()
  "Test outer paren text object."
  (helixel-test-with-buffer '(:text "(hello)" :start 2)
    (call-interactively #'helixel-mark-a-paren)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))
))

;;; Bracket text object tests

 (ert-deftest helixel-test-textobj-bracket-inner ()
  "Test inner bracket text object."
  (helixel-test-with-buffer '(:text "[hello]" :start 2)
    (call-interactively #'helixel-mark-inner-bracket)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))
))

 (ert-deftest helixel-test-textobj-bracket-outer ()
  "Test outer bracket text object."
  (helixel-test-with-buffer '(:text "[hello]" :start 2)
    (call-interactively #'helixel-mark-a-bracket)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))
))

;;; Brace text object tests

 (ert-deftest helixel-test-textobj-brace-inner ()
  "Test inner brace text object."
  (helixel-test-with-buffer '(:text "{hello}" :start 2)
    (call-interactively #'helixel-mark-inner-brace)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))
))

 (ert-deftest helixel-test-textobj-brace-outer ()
  "Test outer brace text object."
  (helixel-test-with-buffer '(:text "{hello}" :start 2)
    (call-interactively #'helixel-mark-a-brace)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))
))

;;; Angle bracket text object tests

 (ert-deftest helixel-test-textobj-angle-inner ()
  "Test inner angle bracket text object."
  (helixel-test-with-buffer '(:text "<hello>" :start 2)
    (call-interactively #'helixel-mark-inner-angle)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))
))

 (ert-deftest helixel-test-textobj-angle-outer ()
  "Test outer angle bracket text object."
  (helixel-test-with-buffer '(:text "<hello>" :start 2)
    (call-interactively #'helixel-mark-a-angle)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))
))

;;; Paren core-correctness tests

(ert-deftest helixel-test-textobj-paren-nested-inner ()
  "mi( selects innermost paren pair in ((inner) outer)."
  (helixel-test-with-buffer '(:text "((inner) outer)" :start 4)
    (call-interactively #'helixel-mark-inner-paren)
    (should (= (region-beginning) 3))
    (should (= (region-end) 8))
))

(ert-deftest helixel-test-textobj-paren-nested-2count ()
  "2mi( selects the outer paren pair in ((inner) outer)."
  (helixel-test-with-buffer '(:text "((inner) outer)" :start 4)
    (call-interactively (lambda nil (interactive) (helixel-mark-inner-paren 2)))
    (should (= (region-beginning) 2))
    (should (= (region-end) 15))
))

(ert-deftest helixel-test-textobj-paren-cursor-on-delimiter ()
  "mi( with cursor on '(' selects inner content."
  (helixel-test-with-buffer "(hello)"
    (call-interactively #'helixel-mark-inner-paren)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))
))

(ert-deftest helixel-test-textobj-paren-cursor-on-close-delimiter ()
  "mi( with cursor on ')' selects inner content."
  (helixel-test-with-buffer '(:text "(hello)" :start 7)
    (call-interactively #'helixel-mark-inner-paren)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))
))

(ert-deftest helixel-test-textobj-paren-multiline ()
  "mi( works across multiple lines."
  (helixel-test-with-buffer '(:text "(
hello
world
)" :start 4)
    (call-interactively #'helixel-mark-inner-paren)
    (should (= (region-beginning) 3))
    (should (= (region-end) 15))
))

(ert-deftest helixel-test-textobj-paren-empty ()
  "mi( on empty parens () returns zero-width selection."
  (helixel-test-with-buffer "()"
    (call-interactively #'helixel-mark-inner-paren)
    (should (= (region-beginning) (region-end)))
    (should (= (region-beginning) 2))
))

;;; Quote edge-case tests

(ert-deftest helixel-test-textobj-quote-escaped ()
  "Quoted string with escaped inner quotes is selected correctly."
  (helixel-test-with-buffer '(:text "\"hello \\\"world\\\"!\"" :start 4)
    (call-interactively #'helixel-mark-inner-double-quote)
    (should (= (region-beginning) 2))
    (should (char-equal (char-before (region-end)) 33))
))

;;; Quote text object tests

(ert-deftest helixel-test-textobj-single-quote-inner ()
  "Test inner single-quote text object."
  (helixel-test-with-buffer '(:text "'hello'" :start 2)
    (call-interactively #'helixel-mark-inner-single-quote)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))
))

(ert-deftest helixel-test-textobj-single-quote-outer ()
  "Test outer single-quote text object."
  (helixel-test-with-buffer '(:text "'hello'" :start 2)
    (call-interactively #'helixel-mark-a-single-quote)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))
))

(ert-deftest helixel-test-textobj-double-quote-inner ()
  "Test inner double-quote text object."
  (helixel-test-with-buffer '(:text "\"hello\"" :start 2)
    (call-interactively #'helixel-mark-inner-double-quote)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))
))

(ert-deftest helixel-test-textobj-double-quote-outer ()
  "Test outer double-quote text object."
  (helixel-test-with-buffer '(:text "\"hello\"" :start 2)
    (call-interactively #'helixel-mark-a-double-quote)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))
))

(ert-deftest helixel-test-textobj-back-quote-inner ()
  "Test inner back-quote text object."
  (helixel-test-with-buffer '(:text "`hello`" :start 2)
    (call-interactively #'helixel-mark-inner-back-quote)
    (should (= (region-beginning) 2))
    (should (= (region-end) 7))
))

(ert-deftest helixel-test-textobj-back-quote-outer ()
  "Test outer back-quote text object."
  (helixel-test-with-buffer '(:text "`hello`" :start 2)
    (call-interactively #'helixel-mark-a-back-quote)
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))
))

;;; Tag text object edge-case tests

(ert-deftest helixel-test-textobj-tag-with-attrs ()
  "Tag textobj works with attributes like <div class='x'>."
  (helixel-test-with-buffer '(:text "<div class=\"foo\">bar</div>" :start 10)
    (call-interactively #'helixel-mark-inner-tag)
    (should (= (region-beginning) 18))
    (should (= (region-end) 21))
))

(ert-deftest helixel-test-textobj-tag-nested ()
  "mit inside <div><p>text</p></div> selects innermost <p>."
  (helixel-test-with-buffer '(:text "<div><p>text</p></div>" :start 10)
    (call-interactively #'helixel-mark-inner-tag)
    (should (= (region-beginning) 9))
    (should (= (region-end) 13))
))

(ert-deftest helixel-test-textobj-tag-mismatched ()
  "mit on <div>text</span> should error (mismatched tags)."
  (helixel-test-with-buffer '(:text "<div>text</span>" :start 3)
    (should-error (call-interactively #'helixel-mark-inner-tag))
))

;;; Tag text object tests

(ert-deftest helixel-test-textobj-tag-inner ()
  "Test inner tag text object."
  (helixel-test-with-buffer '(:text "<foo>bar</foo>" :start 2)
    (call-interactively #'helixel-mark-inner-tag)
    (should (= (region-beginning) 6))
    (should (= (region-end) 9))
))

(ert-deftest helixel-test-textobj-tag-outer ()
  "Test outer tag text object."
  (helixel-test-with-buffer '(:text "<foo>bar</foo>" :start 2)
    (call-interactively #'helixel-mark-a-tag)
    (should (= (region-beginning) 1))
    (should (= (region-end) 15))
))

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
    (setq helixel--action-ring nil helixel--live-action nil helixel--action-pos nil
          last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (should helixel--live-action)
    (should (eq (helixel-action-category helixel--live-action) 'textobj))
    (should (= (marker-position (car (helixel-action-mark-region helixel--live-action))) 1))))

(ert-deftest helixel-test-textobj-session-same-family-continues ()
  "Test same-category text-object commands continue action."
  (helixel-test-with-buffer "(hello) (world)"
    (setq helixel--action-ring nil helixel--live-action nil helixel--action-pos nil
          last-command nil this-command 'helixel-mark-inner-paren)
    (goto-char 2)
    (helixel-mark-inner-paren)
    (should (eq (helixel-action-category helixel--live-action) 'textobj))
    (let ((mark-pos (marker-position (car (helixel-action-mark-region helixel--live-action)))))
      (setq last-command 'helixel-mark-inner-paren this-command 'helixel-mark-a-paren)
      (goto-char 10)
      (helixel-mark-a-paren)
      (should (eq (helixel-action-category helixel--live-action) 'textobj)))))

(ert-deftest helixel-test-textobj-session-different-family-breaks ()
  "Test different-family textobj commits old event to ring."
  (helixel-test-with-buffer "hello (world)"
    (setq helixel--action-ring nil helixel--live-action nil helixel--action-pos nil
          last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word this-command 'helixel-mark-inner-paren)
    (helixel-mark-inner-paren)
    (should (= (length helixel--action-ring) 1))
    (should (eq (helixel-action-subcat helixel--live-action) 'pair))))

(ert-deftest helixel-test-textobj-session-type-property ()
  "Test textobj actions have correct category and subcat."
  (let (helixel--action-ring helixel--live-action helixel--action-pos)
    (helixel-test-with-buffer "hello world"
      (setq last-command nil this-command 'helixel-mark-inner-word)
      (helixel-mark-inner-word)
      (should (eq (helixel-action-category helixel--live-action) 'textobj))
      (should (eq (helixel-action-subcat helixel--live-action) 'word)))))
;;; Regex block text object tests

;; --- helixel-up-regex-block: counter-based (markdown fences) ---

(ert-deftest helixel-test-up-regex-block-counter-same ()
  "Test counter-based up-regex-block with same begin/end (markdown fence)."
  (helixel-test-with-buffer "before
```
code
```
after
```
more
```
done"
    (let ((mb (save-excursion (should (= (helixel-up-regex-block "^```" "^```" 1 nil) 0)) (match-beginning 0)))) (should mb) (goto-char mb) (should (looking-at "```$")))
))

(ert-deftest helixel-test-up-regex-block-counter-diff ()
  "Test counter-based up-regex-block with different begin/end."
  (helixel-test-with-buffer '(:text "before
#+begin
a
#+begin
b
#+end
c
#+end
after" :start (point-min))
    (search-forward "a")
    (let ((mb (save-excursion (should (= (helixel-up-regex-block "^#\\+begin" "^#\\+end" 1 nil) 0)) (match-beginning 0)))) (should mb) (goto-char mb) (should (looking-at "^#\\+end$")))
))

;; --- helixel-up-regex-block: name-based (org blocks) ---

(ert-deftest helixel-test-up-regex-block-named-forward ()
  "Test named up-regex-block forward (org block)."
  (helixel-test-with-buffer '(:text "#+begin_src emacs-lisp
code
#+end_src
after" :start (point-min))
    (let ((mb (save-excursion (should (= (helixel-up-regex-block "^#\\+begin_\\([^ 
]+\\)" "^#\\+end_\\([^ 
]+\\)" 1 1) 0)) (match-beginning 0)))) (should mb) (goto-char mb) (should (looking-at "^#\\+end_src")))
))

(ert-deftest helixel-test-up-regex-block-named-nested ()
  "Test named up-regex-block with nested org blocks."
  (helixel-test-with-buffer '(:text "#+begin_src emacs-lisp
outer
#+begin_example
inner
#+end_example
more
#+end_src" :start (point-min))
    (let ((mb (save-excursion (should (= (helixel-up-regex-block "^#\\+begin_\\([^ 
]+\\)" "^#\\+end_\\([^ 
]+\\)" 1 1) 0)) (match-beginning 0)))) (should mb) (goto-char mb) (should (looking-at "^#\\+end_src")))
))

;; --- helixel-select-regex-block integration ---

(ert-deftest helixel-test-select-regex-block-inner-fence ()
  "Test select inner markdown fence block."
  (helixel-test-with-buffer '(:text "```python
print('hello')
```" :start 14)
    (let ((range (helixel-select-regex-block "^```.+$" "^```[ 	]*$" nil nil nil 1 nil))) (should range) (should (> (nth 0 range) 1)) (should (< (nth 0 range) 14)) (should (> (nth 1 range) (nth 0 range))) (should (< (nth 1 range) (point-max))))
))

(ert-deftest helixel-test-select-regex-block-around-fence ()
  "Test select around markdown fence block."
  (helixel-test-with-buffer '(:text "```python
print('hello')
```" :start 14)
    (let ((range (helixel-select-regex-block "^```.+$" "^```[ 	]*$" nil nil nil 1 t))) (should range) (should (= (nth 0 range) 1)) (should (> (nth 1 range) 1)))
))

(ert-deftest helixel-test-select-regex-block-inner-org ()
  "Test select inner org block."
  (helixel-test-with-buffer '(:text "#+begin_src emacs-lisp
(message \"hi\")
#+end_src
" :start 32)
    (let ((range (helixel-select-regex-block "^#\\+begin_\\([^ 
]+\\)[^
]*" "^#\\+end_\\([^ 
]+\\)[^
]*" nil nil nil 1 nil 1))) (should range) (should (> (nth 0 range) 1)) (should (< (nth 0 range) 32)) (should (> (nth 1 range) (nth 0 range))) (should (< (nth 1 range) (point-max))))
))

(ert-deftest helixel-test-select-regex-block-around-org ()
  "Test select around org block."
  (helixel-test-with-buffer '(:text "#+begin_src emacs-lisp
(message \"hi\")
#+end_src
" :start 32)
    (let ((range (helixel-select-regex-block "^#\\+begin_\\([^ 
]+\\)[^
]*" "^#\\+end_\\([^ 
]+\\)[^
]*" nil nil nil 1 t 1))) (should range) (should (= (nth 0 range) 1)) (should (> (nth 1 range) 1)))
))

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
