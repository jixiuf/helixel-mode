;;; helixel-test-move.el --- Tests for Helixel: movement  -*- lexical-binding: t; -*-

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


;;; Forward long word tests

(ert-deftest helixel-test-forward-WORD-start-basic-movement ()
  "Test basic forward movement between words.
On the last word at eob, w selects the word suffix."
  (helixel-test-with-buffer "hello world test"
    (helixel-forward-WORD-start)
    (should (= (point) 7))
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-forward-WORD-start)
    (should (= (point) 13))
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-forward-WORD-start)
    (should (= (point) 17))
    (should (= (- (region-end) (region-beginning)) 4))
))

(ert-deftest helixel-test-forward-WORD-start-hyphenated-words ()
  "Test forward movement with hyphenated words (long words)."
  (helixel-test-with-buffer "this test-string-example works"
    (helixel-forward-WORD-start)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-forward-WORD-start)
    (should (= (point) 26))
    (should (= (- (region-end) (region-beginning)) 20))
))

(ert-deftest helixel-test-forward-WORD-start-on-whitespace ()
  "Test that forward movement skips over whitespace."
  (helixel-test-with-buffer '(:text "word next" :start 5)
    (helixel-forward-WORD-start)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 1))
))

(ert-deftest helixel-test-forward-WORD-start-on-whitespaces ()
  "Test that forward movement skips over whitespace."
  (helixel-test-with-buffer '(:text "word   	  next" :start 5)
    (helixel-forward-WORD-start)
    (should (= (point) 11))
    (should (= (- (region-end) (region-beginning)) 6))
))

(ert-deftest helixel-test-forward-WORD-start-multiple-lines ()
  "Test forward movement across multiple lines.
When a WORD ends at end of line, stop at end of word (exclude newline)."
  (helixel-test-with-buffer "first line
second line
third"
    (helixel-forward-WORD-start)
    (should (= (point) 7))
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-forward-WORD-start)
    (should (= (point) 11))
    (should (= (- (region-end) (region-beginning)) 4))
    (helixel-forward-WORD-start)
    (should (= (point) 19))
    (should (= (- (region-end) (region-beginning)) 7))
    (helixel-forward-WORD-start)
    (should (= (point) 23))
    (should (= (- (region-end) (region-beginning)) 4))
))

(ert-deftest helixel-test-forward-WORD-start-empty-lines ()
  "Test forward movement with empty lines.
When a WORD ends at end of line, stop at end of word (exclude newline)."
  (helixel-test-with-buffer '(:text "first


second" :start 5)
    (helixel-forward-WORD-start)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 1))
))

(ert-deftest helixel-test-forward-WORD-start-at-end-of-buffer ()
  "Test that forward movement at end of buffer wraps back to last WORD."
  (helixel-test-with-buffer '(:text "test word" :start (point-max))
    (helixel-forward-WORD-start)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 4))
))

(ert-deftest helixel-test-forward-WORD-start-mixed-separators ()
  "Test forward movement with mixed word separators."
  (helixel-test-with-buffer "word1_part2-part3.part4 next"
    (helixel-forward-WORD-start)
    (should (= (point) 25))
    (should (= (- (region-end) (region-beginning)) 24))
))

(ert-deftest helixel-test-forward-WORD-start-punctuation ()
  "Test forward movement with punctuation."
  (helixel-test-with-buffer "Hello, world! How are you?"
    (helixel-forward-WORD-start)
    (should (= (point) 8))
    (should (= (- (region-end) (region-beginning)) 7))
    (helixel-forward-WORD-start)
    (should (= (point) 15))
    (should (= (- (region-end) (region-beginning)) 7))
))

;;; Forward long word end tests

(ert-deftest helixel-test-forward-WORD-end-basic-movement ()
  "Test basic forward movement to word ends."
  (helixel-test-with-buffer "hello world test"
    (helixel-forward-WORD-end)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-forward-WORD-end)
    (should (= (point) 12))
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-forward-WORD-end)
    (should (= (point) 17))
    (should (= (- (region-end) (region-beginning)) 5))
))

(ert-deftest helixel-test-forward-WORD-end-hyphenated-words ()
  "Test forward movement to ends of hyphenated words (long words)."
  (helixel-test-with-buffer "this test-string-example works"
    (helixel-forward-WORD-end)
    (should (= (point) 5))
    (should (= (- (region-end) (region-beginning)) 4))
    (helixel-forward-WORD-end)
    (should (= (point) 25))
    (should (= (- (region-end) (region-beginning)) 20))
    (helixel-forward-WORD-end)
    (should (= (point) 31))
    (should (= (- (region-end) (region-beginning)) 6))
))

(ert-deftest helixel-test-forward-WORD-end-on-whitespace ()
  "Test that forward movement to word ends skips over whitespace."
  (helixel-test-with-buffer '(:text "word next" :start 5)
    (helixel-forward-WORD-end)
    (should (= (point) 10))
    (should (= (- (region-end) (region-beginning)) 5))
))

(ert-deftest helixel-test-forward-WORD-end-on-whitespaces ()
  "Test that forward movement to word ends skips over multiple whitespaces."
  (helixel-test-with-buffer '(:text "word   	  next" :start 5)
    (helixel-forward-WORD-end)
    (should (= (point) 15))
    (should (= (- (region-end) (region-beginning)) 10))
))

(ert-deftest helixel-test-forward-WORD-end-multiple-lines ()
  "Test forward movement to word ends across multiple lines."
  (helixel-test-with-buffer "first line
second line
third"
    (helixel-forward-WORD-end)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-forward-WORD-end)
    (should (= (point) 11))
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-forward-WORD-end)
    (should (= (point) 18))
    (should (= (- (region-end) (region-beginning)) 6))
))

(ert-deftest helixel-test-forward-WORD-end-empty-lines ()
  "Test forward movement to word ends with empty lines."
  (helixel-test-with-buffer "first


second"
    (helixel-forward-WORD-end)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-forward-WORD-end)
    (should (= (point) 8))
    (should (= (- (region-end) (region-beginning)) 1))
))

(ert-deftest helixel-test-forward-WORD-end-at-end-of-buffer ()
  "Test that forward movement to word end at end of buffer doesn't move."
  (helixel-test-with-buffer '(:text "test word" :start (point-max))
    (let ((initial-point (point))) (helixel-forward-WORD-end) (should (= (point) initial-point)) (should (= (- (region-end) (region-beginning)) 0)))
))

(ert-deftest helixel-test-forward-WORD-end-mixed-separators ()
  "Test forward movement to word ends with mixed word separators."
  (helixel-test-with-buffer "word1_part2-part3.part4 next"
    (helixel-forward-WORD-end)
    (should (= (point) 24))
    (should (= (- (region-end) (region-beginning)) 23))
    (helixel-forward-WORD-end)
    (should (= (point) 29))
    (should (= (- (region-end) (region-beginning)) 5))
))

(ert-deftest helixel-test-forward-WORD-end-punctuation ()
  "Test forward movement to word ends with punctuation."
  (helixel-test-with-buffer "Hello, world! How are you?"
    (helixel-forward-WORD-end)
    (should (= (point) 7))
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-forward-WORD-end)
    (should (= (point) 14))
    (should (= (- (region-end) (region-beginning)) 7))
    (helixel-forward-WORD-end)
    (should (= (point) 18))
    (should (= (- (region-end) (region-beginning)) 4))
))

(ert-deftest helixel-test-forward-WORD-end-empty-buffer ()
  "Test forward movement to word end in empty buffer."
  (with-temp-buffer
    (transient-mark-mode 1)
    (let ((initial-point (point)))
      (helixel-forward-WORD-end)
      (should (= (point) initial-point))
      (should (= (- (region-end) (region-beginning)) 0)))))

;;; Backward long word tests

(ert-deftest helixel-test-backward-WORD-basic-movement ()
  "Test basic backward movement between words."
  (helixel-test-with-buffer '(:text "hello world test" :start (point-max))
    (helixel-backward-WORD)
    (should (= (point) 13))
    (should (= (- (region-end) (region-beginning)) 4))
    (helixel-backward-WORD)
    (should (= (point) 7))
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-backward-WORD)
    (should (= (point) 1))
    (should (= (- (region-end) (region-beginning)) 6))
))

(ert-deftest helixel-test-backward-WORD-hyphenated-words ()
  "Test backward movement with hyphenated words (long words)."
  (helixel-test-with-buffer '(:text "this test-string-example works" :start (point-max))
    (helixel-backward-WORD)
    (should (= (point) 26))
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-backward-WORD)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 20))
))

(ert-deftest helixel-test-backward-WORD-on-whitespace ()
  "Test that backward movement skips over whitespace."
  (helixel-test-with-buffer '(:text "word next" :start 5)
    (helixel-backward-WORD)
    (should (= (point) 1))
    (should (= (- (region-end) (region-beginning)) 4))
))

(ert-deftest helixel-test-backward-WORD-on-whitespaces ()
  "Test that backward movement skips over whitespace."
  (helixel-test-with-buffer '(:text "word   	  next" :start 10)
    (helixel-backward-WORD)
    (should (= (point) 1))
    (should (= (- (region-end) (region-beginning)) 9))
))

(ert-deftest helixel-test-backward-WORD-multiple-lines ()
  "Test backward movement across multiple lines."
  (helixel-test-with-buffer '(:text "first line
second line
third" :start (point-max))
    (helixel-backward-WORD)
    (should (= (point) 24))
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-backward-WORD)
    (should (= (point) 19))
    (should (= (- (region-end) (region-beginning)) 4))
    (helixel-backward-WORD)
    (should (= (point) 12))
)) ; start of "second"

(ert-deftest helixel-test-backward-WORD-empty-lines ()
  "Test backward movement with empty lines."
  (helixel-test-with-buffer '(:text "first


second" :start (point-max))
    (helixel-backward-WORD)
    (should (= (point) 9))
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-backward-WORD)
    (should (= (point) 7))
    (should (= (- (region-end) (region-beginning)) 1))
))

(ert-deftest helixel-test-backward-WORD-at-beginning-of-buffer ()
  "Test that backward movement at beginning of buffer doesn't move."
  (helixel-test-with-buffer "test word"
    (let ((initial-point (point))) (helixel-backward-WORD) (should (= (point) initial-point)) (should (= (- (region-end) (region-beginning)) 0)))
))

(ert-deftest helixel-test-backward-WORD-mixed-separators ()
  "Test backward movement with mixed word separators."
  (helixel-test-with-buffer '(:text "word1_part2-part3.part4 next" :start (point-max))
    (helixel-backward-WORD)
    (should (= (point) 25))
    (should (= (- (region-end) (region-beginning)) 4))
    (helixel-backward-WORD)
    (should (= (point) 1))
    (should (= (- (region-end) (region-beginning)) 24))
))

(ert-deftest helixel-test-backward-WORD-punctuation ()
  "Test backward movement with punctuation."
  (helixel-test-with-buffer '(:text "Hello, world! How are you?" :start (point-max))
    (helixel-backward-WORD)
    (should (= (point) 23))
    (should (= (- (region-end) (region-beginning)) 4))
    (helixel-backward-WORD)
    (should (= (point) 19))
    (should (= (- (region-end) (region-beginning)) 4))
))

;;; Edge case tests

(ert-deftest helixel-test-forward-WORD-empty-buffer ()
  "Test forward movement in empty buffer."
  (with-temp-buffer
    (transient-mark-mode 1)
    (let ((initial-point (point)))
      (helixel-forward-WORD-start)
      (should (= (point) initial-point))
      (should (= (- (region-end) (region-beginning)) 0)))))

(ert-deftest helixel-test-backward-WORD-empty-buffer ()
  "Test backward movement in empty buffer."
  (with-temp-buffer
    (transient-mark-mode 1)
    (let ((initial-point (point)))
      (helixel-backward-WORD)
      (should (= (point) initial-point))
      (should (= (- (region-end) (region-beginning)) 0)))))

(ert-deftest helixel-test-forward-WORD-start-only-whitespace ()
  "Test forward movement in buffer with only whitespace."
  (helixel-test-with-buffer "   	
  "
    (helixel-forward-WORD-start)
    (should (= (point) 8))
    (should (= (- (region-end) (region-beginning)) 7))
))

(ert-deftest helixel-test-forward-WORD-end-only-whitespace ()
  "Test forward movement to word end in buffer with only whitespace."
  (helixel-test-with-buffer "   	
  "
    (helixel-forward-WORD-end)
    (should (= (point) 8))
    (should (= (- (region-end) (region-beginning)) 7))
    (helixel-forward-WORD-end)
    (should (= (point) 8))
    (should (= (- (region-end) (region-beginning)) 0))
))

(ert-deftest helixel-test-backward-WORD-only-whitespace ()
  "Test backward movement in buffer with only whitespace."
  (helixel-test-with-buffer '(:text "   	
  " :start (point-max))
    (helixel-backward-WORD)
    (should (= (point) 1))
    (should (= (- (region-end) (region-beginning)) 7))
))

(ert-deftest helixel-test-forward-WORD-start-single-character ()
  "Test forward movement with single character words."
  (helixel-test-with-buffer "a b c d"
    (helixel-forward-WORD-start)
    (should (= (point) 3))
    (should (= (- (region-end) (region-beginning)) 2))
    (helixel-forward-WORD-start)
    (should (= (point) 5))
    (should (= (- (region-end) (region-beginning)) 2))
))

(ert-deftest helixel-test-forward-WORD-end-single-character ()
  "Test forward movement to word ends with single character words."
  (helixel-test-with-buffer "a b c d"
    (helixel-forward-WORD-end)
    (should (= (point) 2))
    (should (= (- (region-end) (region-beginning)) 1))
    (helixel-forward-WORD-end)
    (should (= (point) 4))
    (should (= (- (region-end) (region-beginning)) 2))
    (helixel-forward-WORD-end)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 2))
))

(ert-deftest helixel-test-backward-WORD-single-character ()
  "Test backward movement with single character words."
  (helixel-test-with-buffer '(:text "a b c d" :start (point-max))
    (helixel-backward-WORD)
    (should (= (point) 7))
    (should (= (- (region-end) (region-beginning)) 1))
    (helixel-backward-WORD)
    (should (= (point) 5))
    (should (= (- (region-end) (region-beginning)) 2))
))

;;; Backward word end tests (v key)

(ert-deftest helixel-test-backward-word-end-basic ()
  "Test backward-word-end moves to end of previous word."
  (helixel-test-with-buffer '(:text "hello world test" :start (point-max))
    (helixel-backward-word-end)
    (should (= (point) 12))
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-backward-word-end)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 6))
))

(ert-deftest helixel-test-backward-word-end-mid-word ()
  "Test backward-word-end from middle of a word."
  (helixel-test-with-buffer '(:text "hello world" :start 3)
    (helixel-backward-word-end)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 3))
))

(ert-deftest helixel-test-backward-word-end-at-bob ()
  "Test backward-word-end at beginning of buffer."
  (helixel-test-with-buffer "hello"
    (let ((initial-point (point))) (helixel-backward-word-end) (should (= (point) 6)) (should (= (- (region-end) (region-beginning)) 5)))
))

;;; Word/WORD/symbol newline-skip and line-crossing trim tests

(ert-deftest helixel-test-word-newline-not-included ()
  "Test that w from within a line stops at \n, excluding it."
  (helixel-test-with-buffer '(:text "foo bar 
baz" :start 5)
    (deactivate-mark)
    (setq last-command nil)
    (helixel-forward-word-start)
    (should (= (point) 9))
    (should (= (- (region-end) (region-beginning)) 4))
    (should (string= (buffer-substring (region-beginning) (region-end)) "bar "))
))

(ert-deftest helixel-test-word-www-skips-newline ()
  "Test that www skips \n entirely, selecting three words."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil)
    (insert "foo bar \nbaz")
    (goto-char 1)
    (deactivate-mark)
    (setq last-command nil)
    ;; 1st w
    (call-interactively #'helixel-forward-word-start)
    (should (= (point) 5))              ; start of "bar"
    (should (= (- (region-end) (region-beginning)) 4)) ; "foo "
    ;; 2nd w
    (call-interactively #'helixel-forward-word-start)
    (should (= (point) 9))              ; \n position
    (should (= (- (region-end) (region-beginning)) 4)) ; "bar "
    ;; 3rd w — should skip \n and select "baz"
    (call-interactively #'helixel-forward-word-start)
    (should (= (point) 13))             ; past "baz"
    (should (= (- (region-end) (region-beginning)) 3)) ; "baz"
    (should (string= (buffer-substring (region-beginning) (region-end))
                     "baz"))))

(ert-deftest helixel-test-word-e-stops-at-end-no-newline ()
  "Test that e from within a line stops at end of word, excluding \n."
  (helixel-test-with-buffer '(:text "foo bar 
baz" :start 5)
    (deactivate-mark)
    (setq last-command nil)
    (helixel-forward-word-end)
    (should (= (point) 8))
    (should (= (- (region-end) (region-beginning)) 3))
    (should (string= (buffer-substring (region-beginning) (region-end)) "bar"))
))

(ert-deftest helixel-test-word-e-ee-skips-newline ()
  "Test that ee from end of line skips \n and goes to next word end."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil)
    (insert "foo bar \nbaz")
    (goto-char 5)  ; start of "bar"
    (deactivate-mark)
    (setq last-command nil)
    ;; 1st e: end of "bar"
    (call-interactively #'helixel-forward-word-end)
    (should (= (point) 8))              ; end of "bar"
    (should (= (- (region-end) (region-beginning)) 3)) ; "bar"
    ;; 2nd e: should skip \n and go to end of "baz"
    (call-interactively #'helixel-forward-word-end)
    (should (= (point) 13))             ; past "baz"
    (should (= (- (region-end) (region-beginning)) 3)) ; "baz"
    (should (string= (buffer-substring (region-beginning) (region-end))
                     "baz"))))

(ert-deftest helixel-test-word-b-skips-newline-backward ()
  "Test that b from start of word after \n skips back past \n."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil)
    (insert "foo bar \nbaz")
    (goto-char 10)  ; start of "baz" (after \n)
    (deactivate-mark)
    (setq last-command nil)
    (call-interactively #'helixel-backward-word-start)
    ;; Should skip \n backward and go to start of "bar"
    (should (= (point) 5))
    (should (= (- (region-end) (region-beginning)) 4)) ; "bar "
    (should (string= (buffer-substring (region-beginning) (region-end))
                     "bar "))))

(ert-deftest helixel-test-WORD-www-skips-newline ()
  "Test that WWW skips \n entirely, selecting three WORDs."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil)
    (insert "foo bar \nbaz")
    (goto-char 1)
    (deactivate-mark)
    (setq last-command nil)
    ;; 1st W
    (call-interactively #'helixel-forward-WORD-start)
    (should (= (point) 5))              ; start of "bar"
    (should (= (- (region-end) (region-beginning)) 4)) ; "foo "
    ;; 2nd W
    (call-interactively #'helixel-forward-WORD-start)
    (should (= (point) 9))              ; \n position
    (should (= (- (region-end) (region-beginning)) 4)) ; "bar "
    ;; 3rd W — should skip \n and select "baz"
    (call-interactively #'helixel-forward-WORD-start)
    (should (= (point) 13))             ; past "baz"
    (should (= (- (region-end) (region-beginning)) 3)) ; "baz"
    (should (string= (buffer-substring (region-beginning) (region-end))
                     "baz"))))

(ert-deftest helixel-test-symbol-skips-newline ()
  "Test that symbol motion (o) skips \n."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil)
    (insert "foo.bar \nbaz.qux")
    (goto-char 1)
    (deactivate-mark)
    (setq last-command nil)
    ;; 1st symbol: "foo"
    (call-interactively #'helixel-forward-symbol-start)
    (should (= (point) 4))              ; after "foo", before "."
    (should (= (- (region-end) (region-beginning)) 3)) ; "foo"
    ;; 2nd symbol: "." (punctuation is a separate symbol)
    (call-interactively #'helixel-forward-symbol-start)
    (should (= (point) 5))              ; after "."
    (should (= (- (region-end) (region-beginning)) 1)) ; "."
    ;; 3rd symbol: "bar " (stops before \n via line-crossing trim)
    (call-interactively #'helixel-forward-symbol-start)
    (should (= (point) 9))              ; \n position
    (should (= (- (region-end) (region-beginning)) 4)) ; "bar "
    ;; 4th symbol: should skip \n, select "baz"
    (call-interactively #'helixel-forward-symbol-start)
    (should (= (point) 13))             ; after "baz"
    (should (= (- (region-end) (region-beginning)) 3)) ; "baz"
    (should (string= (buffer-substring (region-beginning) (region-end))
                     "baz"))))

(ert-deftest helixel-test-word-newline-at-buffer-start ()
  "Test w when buffer starts with a newline."
  (helixel-test-with-buffer "
foo bar"
    (deactivate-mark)
    (setq last-command nil)
    (call-interactively #'helixel-forward-word-start)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 4))
    (should (string= (buffer-substring (region-beginning) (region-end)) "foo "))
))

(ert-deftest helixel-test-word-multiple-consecutive-newlines ()
  "Test w through multiple consecutive newlines."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil)
    (insert "foo\n\n\nbar")
    (goto-char 1)
    (deactivate-mark)
    (setq last-command nil)
    ;; 1st w: "foo"
    (call-interactively #'helixel-forward-word-start)
    (should (= (point) 4))              ; \n after "foo"
    (should (= (- (region-end) (region-beginning)) 3)) ; "foo"
    ;; 2nd w: one \n
    (call-interactively #'helixel-forward-word-start)
    (should (= (point) 6))              ; next \n
    (should (= (- (region-end) (region-beginning)) 1)) ; "\n"
    ;; 3rd w: should reach past "bar" on line 4
    (call-interactively #'helixel-forward-word-start)
    (should (= (point) 10))             ; past "bar" (point-max)
    (should (= (- (region-end) (region-beginning)) 3)) ; "bar"
    (should (string= (buffer-substring (region-beginning) (region-end))
                     "bar"))))

;;; Verify paragraph/sentence/function are NOT affected by newline skip

(ert-deftest helixel-test-paragraph-not-affected-by-newline-skip ()
  "Test that paragraph motion still spans multiple lines naturally."
  (helixel-test-with-buffer "line one

line two
"
    (deactivate-mark)
    (setq last-command nil)
    (call-interactively #'helixel-forward-paragraph-start)
    (should (>= (point) 10))
    (should (not (use-region-p)))
))

(ert-deftest helixel-test-sentence-not-affected-by-newline-skip ()
  "Test that sentence motion still works normally across lines."
  (helixel-test-with-buffer "First. Second.
Third."
    (deactivate-mark)
    (setq last-command nil)
    (call-interactively #'helixel-forward-sentence-end)
    (should (> (point) 7))
    (should (not (use-region-p)))
))

(ert-deftest helixel-test-function-not-affected-by-newline-skip ()
  "Test that function movement still spans multiple lines."
  (with-temp-buffer
    (transient-mark-mode 1)
    (emacs-lisp-mode)
    (insert "(defun foo ()\n  (message \"hello\"))\n\n(defun bar ()\n  (message \"world\"))")
    (goto-char 1)
    (deactivate-mark)
    (setq last-command nil)
    (call-interactively #'helixel-forward-outer-function)
    ;; Function end should move point forward from start of defun
    (should (> (point) 1))
    ;; Function IS in helixel-motion-select-categories by default
    ;; (unified subcat with treesit-function).
    (should (use-region-p))))

;;; Word in pure whitespace buffer

(ert-deftest helixel-test-word-pure-whitespace-buffer ()
  "Test w in a buffer with only whitespace goes to eob."
  (helixel-test-with-buffer "   	
  "
    (deactivate-mark)
    (setq last-command nil)
    (call-interactively #'helixel-forward-word-start)
    (should (= (point) (point-max)))
    (should (= (- (region-end) (region-beginning)) (1- (point-max))))
))

;;; Backward WORD end tests

(ert-deftest helixel-test-backward-WORD-end-basic ()
  "Test backward-WORD-end moves to end of previous WORD."
  (helixel-test-with-buffer '(:text "hello world test" :start (point-max))
    (helixel-backward-WORD-end)
    (should (= (point) 12))
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-backward-WORD-end)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 6))
))

(ert-deftest helixel-test-backward-WORD-end-hyphenated ()
  "Test backward-WORD-end with hyphenated words."
  (helixel-test-with-buffer '(:text "this test-string-example works" :start (point-max))
    (helixel-backward-WORD-end)
    (should (= (point) 25))
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-backward-WORD-end)
    (should (= (point) 5))
    (should (= (- (region-end) (region-beginning)) 20))
))

(ert-deftest helixel-test-backward-WORD-end-empty-buffer ()
  "Test backward-WORD-end in empty buffer."
  (with-temp-buffer
    (transient-mark-mode 1)
    (let ((initial-point (point)))
      (helixel-backward-WORD-end)
      (should (= (point) initial-point))
      (should (= (- (region-end) (region-beginning)) 0)))))

;;; Symbol movement tests

(ert-deftest helixel-test-forward-symbol-start-basic ()
  "Test forward-symbol-start movement.
On the last symbol at eob, w selects the symbol suffix."
  (helixel-test-with-buffer "foo_bar baz-qux hello"
    (helixel-forward-symbol-start)
    (should (= (point) 9))
    (should (= (- (region-end) (region-beginning)) 8))
    (helixel-forward-symbol-start)
    (should (= (point) 17))
    (should (= (- (region-end) (region-beginning)) 8))
    (helixel-forward-symbol-start)
    (should (= (point) 22))
    (should (= (- (region-end) (region-beginning)) 5))
))

(ert-deftest helixel-test-forward-symbol-start-single ()
  "Test forward-symbol-start with a single symbol char.
On a single-char symbol at eob, w selects it."
  (helixel-test-with-buffer "x"
    (helixel-forward-symbol-start)
    (should (= (point) 2))
    (should (= (- (region-end) (region-beginning)) 1))
))

(ert-deftest helixel-test-forward-symbol-start-empty-buffer ()
  "Test forward-symbol-start in empty buffer."
  (with-temp-buffer
    (transient-mark-mode 1)
    (let ((initial-point (point)))
      (helixel-forward-symbol-start)
      (should (= (point) initial-point))
      (should (= (- (region-end) (region-beginning)) 0)))))

(ert-deftest helixel-test-forward-symbol-end-basic ()
  "Test forward-symbol-end movement."
  (helixel-test-with-buffer "foo_bar baz-qux hello"
    (helixel-forward-symbol-end)
    (should (= (point) 8))
    (should (= (- (region-end) (region-beginning)) 7))
    (helixel-forward-symbol-end)
    (should (= (point) 16))
    (should (= (- (region-end) (region-beginning)) 8))
    (helixel-forward-symbol-end)
    (should (= (point) 22))
    (should (= (- (region-end) (region-beginning)) 6))
))

(ert-deftest helixel-test-backward-symbol-start-basic ()
  "Test backward-symbol-start movement."
  (helixel-test-with-buffer '(:text "foo_bar baz-qux hello" :start (point-max))
    (helixel-backward-symbol-start)
    (should (= (point) 17))
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-backward-symbol-start)
    (should (= (point) 9))
    (should (= (- (region-end) (region-beginning)) 8))
))

(ert-deftest helixel-test-backward-symbol-start-at-bob ()
  "Test backward-symbol-start at beginning of buffer."
  (helixel-test-with-buffer "hello world"
    (let ((initial-point (point))) (helixel-backward-symbol-start) (should (= (point) initial-point)) (should (= (- (region-end) (region-beginning)) 0)))
))

(ert-deftest helixel-test-backward-symbol-end-basic ()
  "Test backward-symbol-end movement."
  (helixel-test-with-buffer '(:text "foo_bar baz-qux hello" :start (point-max))
    (helixel-backward-symbol-end)
    (should (= (point) 16))
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-backward-symbol-end)
    (should (= (point) 8))
    (should (= (- (region-end) (region-beginning)) 8))
))

;; Find char

(ert-deftest helixel-test-find-next-char ()
  "Test finding next character and selecting from current position to it."
  (helixel-test-with-buffer "first second third"
    (helixel-find-next-char 100)
    (should (eql (point) 13))
    (should (eql (- (region-end) (region-beginning)) 12))
))

(ert-deftest helixel-test-find-next-char-two-line ()
  "Test finding next character across multiple lines and selecting to it."
  (helixel-test-with-buffer "first
second
third"
    (helixel-find-next-char 100)
    (should (eql (point) 13))
    (should (eql (- (region-end) (region-beginning)) 12))
))

(ert-deftest helixel-test-find-till-char ()
  "Test finding till character and selecting from current position to before it."
  (helixel-test-with-buffer "first second third"
    (helixel-find-till-char 100)
    (should (eql (point) 12))
    (should (eql (- (region-end) (region-beginning)) 11))
))

(ert-deftest helixel-test-find-till-char-two-line ()
  "Test finding till character across multiple lines and selecting to before it."
  (helixel-test-with-buffer "first
second
third"
    (helixel-find-till-char 100)
    (should (eql (point) 12))
    (should (eql (- (region-end) (region-beginning)) 11))
))

(ert-deftest helixel-test-find-till-char-repeat ()
  "Test repeating find till character skips past adjacent char."
  (helixel-test-with-buffer "first second third"
    (helixel-find-till-char 100)
    (should (eql (point) 12))
    (helixel-repeat-last-motion)
    (should (eql (point) 18))
    (should (eql (- (region-end) (region-beginning)) 6))
))

(ert-deftest helixel-test-find-prev-till-char-repeat ()
  "Test repeating previous till character find skips past adjacent char."
  (helixel-test-with-buffer '(:text "first second third" :start (point-max))
    (helixel-find-prev-till-char 115)
    (should (eql (point) 8))
    (helixel-repeat-last-motion)
    (should (eql (point) 5))
))

(ert-deftest helixel-test-empty-find-repeat ()
  "Test find repeat when nothing to repeat signals user-error."
  (helixel-test-with-buffer "first second third"
    (should-error (helixel-repeat-last-motion) :type 'user-error)
))

(ert-deftest helixel-test-find-direction-n ()
  "Test f + n repeats find forward."
  (helixel-test-with-buffer "axb axb axb"
    (helixel-find-next-char 98)
    (should (eql (point) 4))
    (helixel-search-repeat-next)
    (should (eql (point) 8))
))     ; next b

(ert-deftest helixel-test-find-direction-N ()
  "Test f + N toggles direction and repeats backward."
  (helixel-test-with-buffer '(:text "axb axb axb" :start 5)
    (helixel-find-next-char 98)
    (should (eql (point) 8))
    (helixel-search-repeat-reverse)
    (should (eq (helixel--last-motion-dir helixel--active-search) 'backward))
    (should (< (point) 8))
))

;;; Pair delimiter movement tests — [ ] { } prefixes

(ert-deftest helixel-test-pair-outer-paren ()
  "Test [ ( outward to enclosing paren opening."
  (helixel-test-with-buffer '(:text "foo (bar) baz" :start nil)
    (goto-char 7)
    (helixel-backward-outer-paren)
    (should (= (point) 5))
))

(ert-deftest helixel-test-pair-next-paren-end-outside ()
  "Test ] ( forward to next paren closing from outside."
  (helixel-test-with-buffer '(:text "x (one) (two)" :start nil)
    (goto-char 1)
    (helixel-forward-outer-paren)
    (should (= (point) 8))
))

(ert-deftest helixel-test-pair-outer-bracket ()
  "Test [ [ outward to enclosing bracket opening."
  (helixel-test-with-buffer '(:text "[abc] def" :start nil)
    (goto-char 4)
    (helixel-backward-outer-bracket)
    (should (= (point) 1))
))

(ert-deftest helixel-test-pair-next-bracket-end ()
  "Test ] [ forward to next bracket closing."
  (helixel-test-with-buffer '(:text "x [one] [two]" :start nil)
    (goto-char 1)
    (helixel-forward-outer-bracket)
    (should (= (point) 8))
))

(ert-deftest helixel-test-pair-outer-brace ()
  "Test [ { outward to enclosing brace opening."
  (helixel-test-with-buffer '(:text "{abc} def" :start nil)
    (goto-char 4)
    (helixel-backward-outer-brace)
    (should (= (point) 1))
))

(ert-deftest helixel-test-pair-next-brace-end ()
  "Test ] { forward to next brace closing."
  (helixel-test-with-buffer '(:text "x {one} {two}" :start nil)
    (goto-char 1)
    (helixel-forward-outer-brace)
    (should (= (point) 8))
))

(ert-deftest helixel-test-pair-outer-double-quote ()
  "Test [ \" outward to enclosing double-quote opening."
  (helixel-test-with-buffer '(:text "x \"abc\" def" :start nil)
    (goto-char 5)
    (helixel-backward-outer-double-quote)
    (should (= (point) 3))
))

(ert-deftest helixel-test-pair-outer-single-quote ()
  "Test [ ' outward to enclosing single-quote opening."
  (helixel-test-with-buffer '(:text "x 'abc' def" :start nil)
    (goto-char 5)
    (helixel-backward-outer-single-quote)
    (should (= (point) 3))
))

(ert-deftest helixel-test-pair-outer-angle ()
  "Test [ < outward to enclosing angle opening."
  (helixel-test-with-buffer '(:text "<abc> def" :start nil)
    (goto-char 4)
    (helixel-backward-outer-angle)
    (should (= (point) 1))
))

(ert-deftest helixel-test-pair-outer-back-quote ()
  "Test [ ` outward to enclosing back-quote opening."
  (helixel-test-with-buffer '(:text "x `abc` def" :start nil)
    (goto-char 5)
    (helixel-backward-outer-back-quote)
    (should (= (point) 3))
))

(ert-deftest helixel-test-comment-next-end ()
  "Test ] ; forward to current or next comment end."
  (helixel-test-with-buffer '(:text ";; a\nx\n;; b\n" :start nil)
    (emacs-lisp-mode)
    (goto-char 6)
    (helixel-forward-outer-comment)
    (should (= (point) 12))
))

(ert-deftest helixel-test-comment-outer ()
  "Test [ ; backward to current or previous comment start."
  (helixel-test-with-buffer '(:text ";; a\nx\n;; b\n" :start nil)
    (emacs-lisp-mode)
    (goto-char 12)
    (helixel-backward-outer-comment)
    (should (= (point) 8))
))

(ert-deftest helixel-test-comment-inner-next-end ()
  "Test } ; forward to current or next comment end."
  (helixel-test-with-buffer '(:text ";; a\nx\n;; b\n" :start nil)
    (emacs-lisp-mode)
    (goto-char 1)
    (helixel-forward-inner-comment)
    (should (= (point) 5))
))

(ert-deftest helixel-test-comment-inner-outer ()
  "Test { ; backward to current or previous comment start."
  (helixel-test-with-buffer '(:text ";; a\nx\n;; b\n" :start nil)
    (emacs-lisp-mode)
    (goto-char 11)
    (helixel-backward-inner-comment)
    (should (= (point) 8))
))
(ert-deftest helixel-test-comment-select-repeat-forward ()
  "Test ]; then , advances to next block with selection."
  (helixel-test-with-buffer '(:text ";; one\n;; two\ncode\n;; three\n" :start nil)
    (emacs-lisp-mode)
    (goto-char 1)
    (helixel-forward-outer-comment)
    (should (string= (buffer-substring (region-beginning) (region-end))
                     ";; one\n;; two"))
    (setq last-command 'helixel-forward-outer-comment)
    (helixel-repeat-last-motion nil)
    (should (use-region-p))
    (should (string= (buffer-substring (region-beginning) (region-end))
                     ";; three"))))


;; Select tests: [; / ]; with helixel-motion-select-categories

(ert-deftest helixel-test-comment-select-forward ()
  "Test ]; selects comment block when comment is in select-categories."
  (helixel-test-with-buffer '(:text ";; one\n;; two\ncode\n;; three\n" :start nil)
    (emacs-lisp-mode)
    (goto-char 1)
    (helixel-forward-outer-comment)
    (should (use-region-p))
    (should (string= (buffer-substring (region-beginning) (region-end))
                     ";; one\n;; two"))
    (should (= (point) (region-end)))))

(ert-deftest helixel-test-comment-select-backward ()
  "Test [; selects comment block when comment is in select-categories."
  (helixel-test-with-buffer '(:text ";; one\n;; two\ncode\n;; three\n" :start nil)
    (emacs-lisp-mode)
    (goto-char 23)  ;; inside ;; three
    (helixel-backward-outer-comment)
    (should (use-region-p))
    (should (string= (buffer-substring (region-beginning) (region-end))
                     ";; three"))
    (should (= (point) (region-beginning)))))

;; Inner variants: { outward, } forward

(ert-deftest helixel-test-pair-inner-outer-paren ()
  "Test { ( outward to enclosing inner paren opening."
  (helixel-test-with-buffer '(:text "(abc def) ghi" :start nil)
    (goto-char 5)
    (helixel-backward-inner-paren)
    (should (= (point) 2))
))

(ert-deftest helixel-test-pair-inner-next-paren-end ()
  "Test } ( forward to next inner paren closing."
  (helixel-test-with-buffer '(:text "x (one) (two)" :start nil)
    (goto-char 1)
    (helixel-forward-inner-paren)
    (should (= (point) 7))
))

(ert-deftest helixel-test-pair-inner-outer-bracket ()
  "Test { [ outward to enclosing inner bracket opening."
  (helixel-test-with-buffer '(:text "[abc] def" :start nil)
    (goto-char 4)
    (helixel-backward-inner-bracket)
    (should (= (point) 2))
))

(ert-deftest helixel-test-pair-inner-next-bracket-end ()
  "Test } [ forward to next inner bracket closing."
  (helixel-test-with-buffer '(:text "x [one] [two]" :start nil)
    (goto-char 1)
    (helixel-forward-inner-bracket)
    (should (= (point) 7))
))

(ert-deftest helixel-test-pair-inner-outer-brace ()
  "Test { { outward to enclosing inner brace opening."
  (helixel-test-with-buffer '(:text "{abc} def" :start nil)
    (goto-char 4)
    (helixel-backward-inner-brace)
    (should (= (point) 2))
))

(ert-deftest helixel-test-pair-inner-next-brace-end ()
  "Test } { forward to next inner brace closing."
  (helixel-test-with-buffer '(:text "x {one} {two}" :start nil)
    (goto-char 1)
    (helixel-forward-inner-brace)
    (should (= (point) 7))
))

(ert-deftest helixel-test-pair-inner-outer-double-quote ()
  "Test { \" outward to enclosing inner double-quote opening."
  (helixel-test-with-buffer '(:text "\"abc\" def" :start nil)
    (goto-char 4)
    (helixel-backward-inner-double-quote)
    (should (= (point) 2))
))

;; ; mark-thing after pair movement
(ert-deftest helixel-test-pair-semicolon-mark-paren ()
  "Test ; after [ ( marks the enclosing paren using stored bounds."
  (helixel-test-with-buffer '(:text "foo (the target) bar" :start nil)
    (goto-char 9)
    (helixel-backward-outer-paren)
    (should (helixel-action-mark-region helixel--live-action))
    (should (helixel-action-mark-region helixel--live-action))
    (let ((mr (helixel-action-mark-region helixel--live-action))) (push-mark (car mr) t t) (goto-char (cdr mr)) (activate-mark))
    (should (use-region-p))
    (should (= (region-beginning) 5))
    (should (= (region-end) 17))
))

;;; Paragraph / sentence / function move tests

(ert-deftest helixel-test-paragraph-move-forward-start ()
  "Test } moves to next paragraph start."
  (helixel-test-with-buffer "line one

line two
"
    (helixel-forward-paragraph-start)
    (should (>= (point) 10))
))

(ert-deftest helixel-test-paragraph-move-backward-start ()
  "Test g { moves to previous paragraph start."
  (helixel-test-with-buffer '(:text "line one

line two
" :start 18)
    (helixel-backward-paragraph-start)
    (should (>= (point) 10))
))

(ert-deftest helixel-test-paragraph-move-forward-end ()
  "Test ]p moves past current paragraph separator, not stuck at line end."
  (helixel-test-with-buffer "line one

line two
"
    (helixel-forward-paragraph-end)
    (should (> (point) 9))
    (should (< (point) (point-max)))
))

(ert-deftest helixel-test-paragraph-move-backward-end ()
  "Test [p moves backward past paragraph separator."
  (helixel-test-with-buffer '(:text "line one

line two
" :start (point-max))
    (helixel-backward-paragraph-end)
    (should (< (point) (point-max)))
    (should (> (point) 1))
))

(ert-deftest helixel-test-sentence-move-forward-end ()
  "Test ] s moves to next sentence end."
  (helixel-test-with-buffer "Hello.  World."
    (helixel-forward-sentence-end)
    (should (>= (point) 5))
))

;;; Jump to match — %
(ert-deftest helixel-test-jump-to-match-from-open ()
  "Test % from opening paren jumps after closing."
  (helixel-test-with-buffer '(:text "(abc def) ghi" :start nil)
    (goto-char 1)
    (helixel-jump-to-match)
    (should (= (point) 10))
))

(ert-deftest helixel-test-jump-to-match-from-close ()
  "Test % from closing paren jumps to opening."
  (helixel-test-with-buffer '(:text "(abc def) ghi" :start nil)
    (goto-char 9)
    (helixel-jump-to-match)
    (should (= (point) 1))
))

(ert-deftest helixel-test-jump-to-match-brace ()
  "Test % on { jumps to }."
  (helixel-test-with-buffer '(:text "{abc}" :start nil)
    (goto-char 1)
    (helixel-jump-to-match)
    (should (= (point) 6))
))

(ert-deftest helixel-test-jump-to-match-bracket ()
  "Test % on [ jumps to ]."
  (helixel-test-with-buffer '(:text "[abc]" :start nil)
    (goto-char 1)
    (helixel-jump-to-match)
    (should (= (point) 6))
))

(ert-deftest helixel-test-jump-to-match-between-close ()
  "Test % between ) and } jumps to matching (."
  (helixel-test-with-buffer '(:text "(x) {y}" :start nil)
    (goto-char 4)
    (helixel-jump-to-match)
    (should (= (point) 1))
))

(ert-deftest helixel-test-jump-to-match-nested ()
  "Test % from inner ( in nested parens jumps to inner )."
  (helixel-test-with-buffer '(:text "(a (b) c)" :start nil)
    (goto-char 4)
    (helixel-jump-to-match)
    (should (= (point) 7))
))

(ert-deftest helixel-test-jump-to-match-double-quote ()
  "Test % on \" does NOT jump to matching \" — quotes are excluded.
\=`%' only handles bracket-pair, tag, block, and syntax-table pairs."
  (helixel-test-with-buffer '(:text "x \"hi\" y" :start nil)
    (goto-char 3)
    (let ((pt-before (point))) (helixel-jump-to-match) (should (= (point) pt-before)))
))

(ert-deftest helixel-test-jump-to-match-no-match ()
  "Test % with no bracket does not crash."
  (helixel-test-with-buffer '(:text "no brackets here" :start nil)
    (goto-char 5)
    (condition-case nil (helixel-jump-to-match) (error nil))
    (should t)
))

(ert-deftest helixel-test-jump-to-match-tag ()
  "Test % inside tag moves backward to <; second % jumps to </div>."
  (helixel-test-with-buffer '(:text "<div>hi</div>" :start nil)
    (goto-char 2)
    (helixel-jump-to-match)
    (should (= (point) 1))
    (helixel-jump-to-match)
    (should (= (point) 14))
))

;;; Structure ; mark-thing
(ert-deftest helixel-test-structure-semicolon-mark-function ()
  (with-temp-buffer
    (transient-mark-mode 1)
    (emacs-lisp-mode)
    (insert "\n(defun foo () 1)\n")
    (deactivate-mark)
    (goto-char 2)
    (helixel-forward-outer-function)
    (should (helixel-action-mark-region helixel--live-action))
    ;; Mark using stored mark-region from event
    (let ((mr (helixel-action-mark-region helixel--live-action)))
      (push-mark (car mr) t t)
      (goto-char (cdr mr))
      (activate-mark))
    (should (use-region-p))))

;;; mark-thing ; after various movements

(defmacro helixel-test-mark-thing (name movement-cmd buffer-content
                                        init-pos expected-beg expected-end)
  `(ert-deftest ,(intern (format "helixel-test-mark-%s" name)) ()
     ,(format "Test ; after %s selects the thing." name)
     (with-temp-buffer
       (transient-mark-mode 1)
       (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil)
       (insert ,buffer-content)
       (deactivate-mark)
       (goto-char ,init-pos)
       (setq last-command nil)
       (call-interactively ,movement-cmd)
       (should (helixel-action-mark-region helixel--live-action))
       ;; Simulate ;
       (helixel--action-cycle)
       (should (use-region-p))
       (should (= (region-beginning) ,expected-beg))
       (should (= (region-end) ,expected-end)))))

(helixel-test-mark-thing "w-word" #'helixel-forward-word-start
  "hello world" 1 1 7)
(helixel-test-mark-thing "W-WORD" #'helixel-forward-WORD-start
  "hello world" 1 1 7)
(helixel-test-mark-thing "e-word-end" #'helixel-forward-word-end
  "hello world" 1 1 6)
(helixel-test-mark-thing "E-WORD-end" #'helixel-forward-WORD-end
  "hello world" 1 1 6)
(helixel-test-mark-thing "b-back-word" #'helixel-backward-word-start
  "hello world" 3 1 7)
(helixel-test-mark-thing "B-back-WORD" #'helixel-backward-WORD
  "hello world" 3 1 7)
(helixel-test-mark-thing "o-symbol" #'helixel-forward-symbol-start
  "foo.bar baz" 1 1 4)
(helixel-test-mark-thing "outer-paren" #'helixel-backward-outer-paren
  "foo (bar)" 7 5 10)
(helixel-test-mark-thing "next-paren" #'helixel-forward-outer-paren
  "a (one) (two)" 1 3 8)

(ert-deftest helixel-test-mark-thing-second-semicolon ()
  "Test second ; after mark-thing does action cycle."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil)
    (insert "hello world")
    (deactivate-mark)
    (goto-char 1)
    (helixel-forward-word-start)
    ;; First ; marks the thing
    (helixel--action-cycle)
    (should (use-region-p))
    ;; Second ; does action cycle (no error, no mark-thing)
    (deactivate-mark)
    (helixel--action-cycle)
    ;; Should have committed live event and be cycling
    (should helixel--action-pos)))

(ert-deftest helixel-test-c-semicolon-non-mark-thing ()
  "Test \\[helixel-action-cycle-mark-start] pushes mark to event start without selecting the full span."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil helixel--mark-cycle-pos nil)
    (insert "hello world")
    (deactivate-mark)
    (goto-char 1)
    (helixel-forward-word-start)
    (helixel-action-cycle-mark-start)
    ;; C-; does NOT select the full span (non-mark-thing path).
    ;; The region should be active (push-mark with activate=t) but
    ;; from current point to the thing-start, not the whole word.
    (should (region-active-p))
    (should helixel--mark-cycle-pos)))

;;; Tag pair movement [t and ; mark-thing

(ert-deftest helixel-test-pair-tag-semicolon-mark ()
  "Test [t; after pair movement marks the enclosing tag."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil)
    (insert "<p>\n<div>\nhe\n</div>\n</p>")
    (deactivate-mark)
    (goto-char 2)
    (search-forward "he")
    ;; [t from inside <div> content
    (helixel-backward-outer-tag)
    (should (helixel-action-mark-region helixel--live-action))
    ;; ; marks the stored bounds
    (helixel--action-cycle)
    (should (use-region-p))
    ;; Should mark <div>...</div> (positions 5-20)
    (should (= (region-beginning) 5))
    (should (= (region-end) 20))))

(ert-deftest helixel-test-pair-tag-double-semicolon-mark ()
  "Test [t from between inner close and outer close finds the outer tag."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil)
    (insert "<p>\n<div>\nhe\n</div>\n</p>")
    (deactivate-mark)
    ;; Go between </div> and </p> (position 20 is \n after </div>)
    (goto-char 20)
    ;; [t finds <p>...</p> (the outer enclosing tag)
    (helixel-backward-outer-tag)
    (should (helixel-action-mark-region helixel--live-action))
    ;; ; marks the stored bounds (outer <p>)
    (helixel--action-cycle)
    (should (use-region-p))
    ;; Should mark <p>...</p> (positions 1-25)
    (should (= (region-beginning) 1))
    (should (= (region-end) 25))))

(ert-deftest helixel-test-pair-tag-inner-semicolon-mark ()
  "Test {t; marks the inner content of the enclosing tag."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil)
    (insert "<p>\ninner\n</p>")
    (deactivate-mark)
    (goto-char 7)
    ;; {t from inside <p> content
    (helixel-backward-inner-tag)
    (should (helixel-action-mark-region helixel--live-action))
    ;; ; marks the stored inner bounds
    (helixel--action-cycle)
    (should (use-region-p))
    ;; Should mark inner content: \ninner\n (positions 4-11)
    (should (= (region-beginning) 4))
    (should (= (region-end) 11))))

(ert-deftest helixel-test-pair-tag-next-end-semicolon-mark ()
  "Test ]t; marks the current enclosing tag."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil)
    (insert "<a>x</a> <b>y</b>")
    (deactivate-mark)
    (goto-char 4)  ; inside <a> content (the "x")
    ;; ]t from inside <a>
    (helixel-forward-outer-tag)
    (should (helixel-action-mark-region helixel--live-action))
    ;; ; marks the current enclosing tag <a>
    (helixel--action-cycle)
    (should (use-region-p))
    ;; Should mark from <a> opening to point after ]t (positions 1-8)
    (should (= (region-beginning) 1))
    (should (= (region-end) 9))))

;;; Tag textobj mat from between tags

(ert-deftest helixel-test-textobj-tag-between-tags ()
  "Test mat from between <p> and <div> marks the enclosing <p>."
  (helixel-test-with-buffer '(:text "<p>
<div>
he
</div>
</p>" :start 4)
    (call-interactively #'helixel-mark-a-tag)
    (should (= (region-beginning) 1))
    (should (= (region-end) 25))
))

(ert-deftest helixel-test-textobj-tag-nested-inner ()
  "Test mat from inside nested <div> marks the innermost <div>."
  (helixel-test-with-buffer '(:text "<p>
<div>
hello
</div>
</p>" :start 2)
    (search-forward "hello")
    (call-interactively #'helixel-mark-a-tag)
    (should (= (region-beginning) 5))
    (should (= (region-end) 23))
))

(ert-deftest helixel-test-textobj-tag-before-outer-close ()
  "Test mat before outer closing tag marks the outer tag."
  (helixel-test-with-buffer '(:text "<p>
<div>
hello
</div>
</p>" :start (point-max))
    (search-backward "</p>")
    (call-interactively #'helixel-mark-a-tag)
    (should (= (region-beginning) 1))
    (should (= (region-end) 28))
))

;;; Pair climb-outward tests — ]/} when point at closing edge

(ert-deftest helixel-test-pair-next-paren-climb-outward ()
  "Test ] ( at inner ) climbs to outer ) in nested parens."
  (helixel-test-with-buffer '(:text "(a (b) c)" :start nil)
    (goto-char 6)
    (helixel-forward-outer-paren)
    (should (= (point) 10))
))

(ert-deftest helixel-test-pair-inner-next-paren-climb-outward ()
  "Test } ( at inner ) climbs to outer inner ) in nested parens."
  (helixel-test-with-buffer '(:text "(a (b) c)" :start nil)
    (goto-char 6)
    (helixel-forward-inner-paren)
    (should (= (point) 9))
))

(ert-deftest helixel-test-pair-next-brace-climb-outward ()
  "Test ] { at inner } climbs to outer } in nested braces."
  (helixel-test-with-buffer '(:text "{a {b} c}" :start nil)
    (goto-char 6)
    (helixel-forward-outer-brace)
    (should (= (point) 10))
))

(ert-deftest helixel-test-pair-inner-next-brace-climb-outward ()
  "Test } { at inner } climbs to outer inner } in nested braces."
  (helixel-test-with-buffer '(:text "{a {b} c}" :start nil)
    (goto-char 6)
    (helixel-forward-inner-brace)
    (should (= (point) 9))
))

;;; Multi-char delimiter climb-outward — tag and block

(ert-deftest helixel-test-pair-next-tag-climb-outward ()
  "Test ]t at inner </div> climbs to outer </p> in nested tags."
  (helixel-test-with-buffer '(:text "<p><div>hi</div></p>" :start nil)
    (goto-char 16)
    (helixel-forward-outer-tag)
    (should (= (point) 21))
))

(ert-deftest helixel-test-pair-inner-next-tag-climb-outward ()
  "Test }t at inner </div> climbs to outer inner </p> in nested tags."
  (helixel-test-with-buffer '(:text "<p><div>hi</div></p>" :start nil)
    (goto-char 16)
    (helixel-forward-inner-tag)
    (should (= (point) 17))
))

;;; Triple-nested climb-outward — stepping one level per press

(ert-deftest helixel-test-pair-next-paren-triple-nested ()
  "Test ]) from inside 3-nested parens steps one level each press."
  ;; Buffer: (a (b (c))) — point inside innermost (c)
  ;; 1:\( 2:a 3:SPC 4:\( 5:b 6:SPC 7:\( 8:c 9:\) 10:\) 11:\) 12:eob
  (helixel-test-with-buffer '(:text "(a (b (c)))" :start nil)
    (goto-char 8)
    (helixel-forward-outer-paren)
    (should (= (point) 10))
    (helixel-forward-outer-paren)
    (should (= (point) 11))
    (helixel-forward-outer-paren)
    (should (= (point) 12))
    (helixel-forward-outer-paren)
    (should (= (point) 12))
))

(ert-deftest helixel-test-pair-next-paren-triple-nested-compact ()
  "Test ]) with no spaces: (a(b(c))) — adjacent ))."
  ;; 1:\( 2:a 3:\( 4:b 5:\( 6:c 7:\) 8:\) 9:\) 10:eob
  (helixel-test-with-buffer '(:text "(a(b(c)))" :start nil)
    (goto-char 6)
    (helixel-forward-outer-paren)
    (should (= (point) 8))
    (helixel-forward-outer-paren)
    (should (= (point) 9))
    (helixel-forward-outer-paren)
    (should (= (point) 10))
)) ; after third ) = eob

(ert-deftest helixel-test-pair-next-brace-triple-nested ()
  "Test ]{ from inside 3-nested braces steps one level each press."
  (helixel-test-with-buffer '(:text "{a {b {c}}}" :start nil)
    (goto-char 8)
    (helixel-forward-outer-brace)
    (should (= (point) 10))
    (helixel-forward-outer-brace)
    (should (= (point) 11))
    (helixel-forward-outer-brace)
    (should (= (point) 12))
)) ; after third } = eob

(ert-deftest helixel-test-pair-next-bracket-triple-nested ()
  "Test ][ from inside 3-nested brackets steps one level each press."
  (helixel-test-with-buffer '(:text "[a [b [c]]]" :start nil)
    (goto-char 8)
    (helixel-forward-outer-bracket)
    (should (= (point) 10))
    (helixel-forward-outer-bracket)
    (should (= (point) 11))
    (helixel-forward-outer-bracket)
    (should (= (point) 12))
)) ; after third ] = eob

(ert-deftest helixel-test-pair-next-paren-double-nested-eob ()
  "]) steps one level per press through ((a)) at eob.
When inner )) are adjacent AND the outer ) is at eob,
the just-exited check must not suppress climbing —
cur-bounds IS the same as the inner pair, so we
need the normal AT-closing climb to advance."
  ;; Buffer: ((a)) — 1:( 2:( 3:a 4:) 5:) 6:eob
  (helixel-test-with-buffer '(:text "((a))" :start nil)
    (goto-char 3)
    (helixel-forward-outer-paren)
    (should (= (point) 5))
    (helixel-forward-outer-paren)
    (should (= (point) 6))
    (helixel-forward-outer-paren)
    (should (= (point) 6))
))

;;; Pair next-end from outside (not inside any pair)

(ert-deftest helixel-test-pair-next-paren-end-from-outside ()
  "Test ] ( from before a paren pair jumps into it."
  (helixel-test-with-buffer '(:text "before (target) after" :start nil)
    (goto-char 1)
    (helixel-forward-outer-paren)
    (should (= (point) 16))
))

(ert-deftest helixel-test-pair-next-brace-end-from-outside ()
  "Test ] { from before a brace pair jumps into it."
  (helixel-test-with-buffer '(:text "before {target} after" :start nil)
    (goto-char 1)
    (helixel-forward-outer-brace)
    (should (= (point) 16))
))

(ert-deftest helixel-test-pair-next-double-quote-end-from-outside ()
  "Test ] \" from before a quoted string finds its closing."
  (helixel-test-with-buffer '(:text "x \"one\" y" :start nil)
    (goto-char 1)
    (helixel-forward-outer-double-quote)
    (should (= (point) 8))
))

(ert-deftest helixel-test-pair-next-single-quote-end-from-outside ()
  "Test ] ' from before a quoted string finds its closing."
  (helixel-test-with-buffer '(:text "x 'one' y" :start nil)
    (goto-char 1)
    (helixel-forward-outer-single-quote)
    (should (= (point) 8))
))

(ert-deftest helixel-test-pair-next-angle-end ()
  "Test ] < moves to closing angle bracket."
  (helixel-test-with-buffer '(:text "<foo> bar" :start nil)
    (goto-char 2)
    (helixel-forward-outer-angle)
    (should (= (point) 6))
))

;;; No pair found — graceful handling

(ert-deftest helixel-test-pair-next-paren-no-pair ()
  "Test ] ( with no paren in buffer does not crash."
  (helixel-test-with-buffer '(:text "no parens here at all" :start nil)
    (goto-char 5)
    (condition-case nil (helixel-forward-outer-paren) (error nil))
    (let ((mr (helixel-action-mark-region helixel--live-action))) (should (= (marker-position (car mr)) (marker-position (cdr mr)))))
))

(ert-deftest helixel-test-pair-outer-paren-no-pair ()
  "Test [ ( with no paren in buffer does not crash."
  (helixel-test-with-buffer '(:text "no parens here" :start nil)
    (condition-case nil (helixel-backward-outer-paren) (error nil))
    (let ((mr (helixel-action-mark-region helixel--live-action))) (should (= (marker-position (car mr)) (marker-position (cdr mr)))))
))

;;; Block movement (org-mode)

(ert-deftest helixel-test-pair-outer-block-org ()
  "Test [ c outward to enclosing org block opening."
  (with-temp-buffer
    (transient-mark-mode 1)
    (delay-mode-hooks (org-mode))
    (insert "#+begin_src emacs-lisp\ncode\n#+end_src\n")
    (deactivate-mark)
    (goto-char 10)
    (condition-case nil
        (helixel-backward-outer-block)
      (error nil))
    (when-let* ((mr (helixel-action-mark-region helixel--live-action)))
      (should (<= (marker-position (car mr)) 10)))))

(ert-deftest helixel-test-pair-next-block-end-org ()
  "Test ] c forward to enclosing org block closing."
  (with-temp-buffer
    (transient-mark-mode 1)
    (delay-mode-hooks (org-mode))
    (insert "#+begin_src emacs-lisp\ncode\n#+end_src\n")
    (deactivate-mark)
    (goto-char 10)
    (condition-case nil
        (helixel-forward-outer-block)
      (error nil))
    (when-let* ((mr (helixel-action-mark-region helixel--live-action)))
      (should (>= (marker-position (cdr mr)) 10)))))

;;; ; mark-thing for paragraph/sentence/function movements

(ert-deftest helixel-test-mark-thing-paragraph-forward ()
  "Test ; after } (paragraph forward) marks the paragraph."
  (helixel-test-with-buffer '(:text "First paragraph.

Second paragraph." :start nil)
    (goto-char 1)
    (setq helixel--action-pos nil)
    (helixel-forward-paragraph-start)
    (should (helixel-action-mark-region helixel--live-action))
    (helixel--action-cycle)
    (should (use-region-p))
))

(ert-deftest helixel-test-mark-thing-sentence-forward ()
  "Test ; after ]s (sentence forward end) marks the sentence."
  (helixel-test-with-buffer '(:text "One. Two. Three." :start nil)
    (goto-char 1)
    (setq helixel--action-pos nil)
    (helixel-forward-sentence-end)
    (should (helixel-action-mark-region helixel--live-action))
    (helixel--action-cycle)
    (should (use-region-p))
))

(ert-deftest helixel-test-mark-thing-function-forward ()
  "Test ; after ]f (function forward end) marks the function."
  (with-temp-buffer
    (transient-mark-mode 1)
    (emacs-lisp-mode)
    (insert "(defun foo () (message \"hi\"))\n\n(defun bar () nil)")
    (deactivate-mark)
    (goto-char 1)
    (setq helixel--action-pos nil)
    (helixel-forward-outer-function)
    (should (helixel-action-mark-region helixel--live-action))
    (helixel--action-cycle)
    (should (use-region-p))))

;; ── Function movement: double-tracking eliminated ──
;; The outer helixel-*-outer-function commands call plain helpers
;; (no tracking), so each keypress produces exactly one ring entry.

(ert-deftest helixel-test-function-no-double-tracking ()
  "Single [f press produces exactly one non-degenerate ring entry."
  (let ((helixel--action-ring nil)
        (helixel--live-action nil)
        (helixel--action-pos nil)
        (helixel--last-motion-cmd nil))
    (with-temp-buffer
      (emacs-lisp-mode)
      (transient-mark-mode 1)
      (insert "(defun foo () 1)\n\n(defun bar () 2)\n")
      ;; Start at bar (the second defun).
      (goto-char 19)
      (setq last-command nil
            this-command 'helixel-backward-outer-function)
      (call-interactively #'helixel-backward-outer-function)
      ;; Live action was set.
      (should helixel--live-action)
      (let ((mr (helixel-action-mark-region helixel--live-action)))
        (should mr)
        (should (consp mr))
        ;; Non-degenerate: arrived-at function bounds.
        (should (not (= (marker-position (car mr))
                        (marker-position (cdr mr))))))
      (helixel--action-cycle)
      ;; Exactly one entry (not two from double-tracking).
      (should (= (length helixel--action-ring) 1))
      (should-not helixel--live-action))))

(ert-deftest helixel-test-function-comma-no-double-tracking ()
  "Each comma-repeat produces exactly one ring entry per press."
  (let ((helixel--action-ring nil)
        (helixel--live-action nil)
        (helixel--action-pos nil)
        (helixel--last-motion-cmd nil))
    (with-temp-buffer
      (emacs-lisp-mode)
      (transient-mark-mode 1)
      (insert "(defun foo () 1)\n\n(defun bar () 2)\n\n(defun baz () 3)\n")
      ;; Start at baz (third defun).
      (goto-char 37)
      ;; [f — backward to bar.
      (setq last-command nil
            this-command 'helixel-backward-outer-function)
      (call-interactively #'helixel-backward-outer-function)
      ;; , — backward to foo.
      (setq last-command 'helixel-backward-outer-function)
      (helixel-repeat-last-motion nil)
      ;; ; commits pending live + starts cycle.
      (helixel--action-cycle)
      ;; 2 entries: initial + 1 comma.  No degenerate doubles.
      (should (= (length helixel--action-ring) 2)))))

;; ── Function movement: newest-for-mark (;) ──
;; (movement . function) is in helixel-action-cycle-newest-for-mark.
;; First ; selects just the last function; second ; selects all.

(ert-deftest helixel-test-function-newest-for-mark-first ()
  "After [f , , first ; selects only the last function (newest)."
  (let ((helixel--action-ring nil)
        (helixel--live-action nil)
        (helixel--action-pos nil)
        (helixel--last-motion-cmd nil)
        (helixel-action-cycle-newest-for-mark
         '((movement . function))))
    (with-temp-buffer
      (emacs-lisp-mode)
      (transient-mark-mode 1)
      (insert "(defun foo () 1)\n\n(defun bar () 2)\n\n(defun baz () 3)\n")
      ;; Start at baz (pos 37).
      (goto-char 37)
      (deactivate-mark)
      ;; [f — backward to bar.
      (setq last-command nil
            this-command 'helixel-backward-outer-function)
      (call-interactively #'helixel-backward-outer-function)
      ;; , — backward to foo.
      (setq last-command 'helixel-backward-outer-function)
      (helixel-repeat-last-motion nil)
      ;; First ; : newest-for-mark → selects just foo (last function).
      (helixel--action-cycle)
      (should (region-active-p))
      ;; Region starts at foo, is short (one function, not all three).
      (should (= (region-beginning) 1))
      (should (< (- (region-end) (region-beginning)) 20)))))

(ert-deftest helixel-test-function-newest-for-mark-second ()
  "After [f , , second ; selects the full span (all functions)."
  (let ((helixel--action-ring nil)
        (helixel--live-action nil)
        (helixel--action-pos nil)
        (helixel--last-motion-cmd nil)
        (helixel-action-cycle-newest-for-mark
         '((movement . function))))
    (with-temp-buffer
      (emacs-lisp-mode)
      (transient-mark-mode 1)
      (insert "(defun foo () 1)\n\n(defun bar () 2)\n\n(defun baz () 3)\n")
      (goto-char 37)
      (deactivate-mark)
      (setq last-command nil
            this-command 'helixel-backward-outer-function)
      (call-interactively #'helixel-backward-outer-function)
      (setq last-command 'helixel-backward-outer-function)
      (helixel-repeat-last-motion nil)
      ;; First ; — newest function only.
      (helixel--action-cycle)
      (let ((len1 (- (region-end) (region-beginning))))
        ;; Second ; — group-span → selects all three functions.
        (let ((last-command 'helixel-action-cycle)
              (helixel--action-pos helixel--action-pos))
          (helixel--action-cycle))
        (should (region-active-p))
        ;; Now region is larger: spans all functions from foo to baz.
        (should (= (region-beginning) 1))
        (should (> (- (region-end) (region-beginning)) len1))
        (should (> (- (region-end) (region-beginning)) 30))))))

;; ── Function movement: motion-select region covers full function ──
;; When helixel-motion-select-categories includes (movement . function),
;; [f / ]f select the full destination function (matching TS behaviour),
;; not just the movement span from origin to destination.

(ert-deftest helixel-test-function-select-full-backward ()
  "[f with motion-select selects the entire destination function."
  (let ((helixel-motion-select-categories '((movement . function)))
        (helixel--last-motion-cmd nil)
        (helixel--action-ring nil)
        (helixel--live-action nil)
        (helixel--action-pos nil))
    (with-temp-buffer
      (emacs-lisp-mode)
      (transient-mark-mode 1)
      (insert "(defun foo () (message \"hi\"))\n\n(defun bar () nil)\n")
      ;; Start at bar (pos 32).
      (goto-char 32)
      (deactivate-mark)
      (setq last-command nil
            this-command 'helixel-backward-outer-function)
      (call-interactively #'helixel-backward-outer-function)
      (should (region-active-p))
      ;; Region starts at foo, not at the cursor origin.
      (should (= (region-beginning) 1))
      ;; Region covers the full foo function.
      (should (>= (region-end) 29)))))

(ert-deftest helixel-test-function-select-full-forward ()
  "]f with motion-select selects the entire destination function."
  (let ((helixel-motion-select-categories '((movement . function)))
        (helixel--last-motion-cmd nil)
        (helixel--action-ring nil)
        (helixel--live-action nil)
        (helixel--action-pos nil))
    (with-temp-buffer
      (emacs-lisp-mode)
      (transient-mark-mode 1)
      (insert "(defun foo () (message \"hi\"))\n\n(defun bar () nil)\n")
      ;; Start inside foo (pos 15, inside the message call).
      (goto-char 15)
      (deactivate-mark)
      (setq last-command nil
            this-command 'helixel-forward-outer-function)
      (call-interactively #'helixel-forward-outer-function)
      (should (region-active-p))
      ;; Region starts at foo (current function end reached first).
      (should (= (region-beginning) 1)))))

;; ── Surround macro clears stale pending-sel ──

(ert-deftest helixel-test-surround-clears-nonmovement-sel ()
  "Surround clears a non-movement pending-sel."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (helixel--sel-push (make-helixel-line-sel :dir 'forward :count 1))
    (push-mark (point-max) t t)
    (should (eq (helixel-sel-kind helixel--pending-sel) 'helixel-line-sel))
    (helixel-forward-word-start)
    (should helixel--pending-sel)
    (should (eq (helixel-sel-kind helixel--pending-sel) 'helixel-movement-sel))))

(ert-deftest helixel-test-movement-clears-stale-sel-type ()
  "Movement clears a stale non-movement pending-sel."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (helixel-test--mock-sel-type 'rect)
    (should (eq (helixel--sel-type) 'rect))
    (helixel-forward-word-start)
    (should (null (helixel--sel-type)))))

;; ── , motion-repeat tests ──

(ert-deftest helixel-test-motion-repeat-pair ()
  ", tracks and re-invokes pair delimiter motion (])."
  (helixel-test-with-buffer '(:text "x (a) (b) (c)" :start nil)
    (goto-char 1)
    (helixel-forward-outer-paren)
    (should (= (point) 6))
    (should (helixel--last-motion-p helixel--last-motion-cmd))
    (should (eq (helixel--last-motion-command helixel--last-motion-cmd) 'helixel-forward-outer-paren))
    (helixel-repeat-last-motion)
    (should (eq (helixel--last-motion-command helixel--last-motion-cmd) 'helixel-forward-outer-paren))
))

(ert-deftest helixel-test-motion-repeat-match ()
  ", direction is recorded: forward/backward based on %% direction."
  (helixel-test-with-buffer '(:text "(a (b) c)" :start nil)
    (goto-char 4)
    (helixel-jump-to-match)
    (should (eq (helixel--last-motion-dir helixel--last-motion-cmd) 'forward))
    (goto-char 7)
    (helixel-jump-to-match)
    (should (eq (helixel--last-motion-dir helixel--last-motion-cmd) 'backward))
))

(ert-deftest helixel-test-motion-repeat-match-semicolon ()
  ", outward then ; selects a region."
  (helixel-test-with-buffer '(:text "(outer (inner))" :start nil)
    (let ((helixel--action-ring nil) (helixel--live-action nil) (helixel--action-pos nil)) (goto-char 8) (helixel-jump-to-match) (helixel-repeat-last-motion) (let ((last-command 'helixel-repeat-last-motion)) (helixel-action-cycle)) (should (region-active-p)) (should (> (region-end) (region-beginning))))
))

(ert-deftest helixel-test-motion-repeat-match-commits-event ()
  ", after % commits an event to the ring."
  (helixel-test-with-buffer '(:text "(a (b (c)))" :start nil)
    (let ((helixel--action-ring nil) (helixel--live-action nil) (helixel--action-pos nil)) (goto-char 9) (helixel-jump-to-match) (helixel-repeat-last-motion) (should (>= (length helixel--action-ring) 2)) (let ((mr (helixel-action-mark-region (car helixel--action-ring)))) (should mr) (should (> (marker-position (cdr mr)) (marker-position (car mr))))))
))

(ert-deftest helixel-test-motion-repeat-match-semicolon-outer-pair ()
  "; after , selects the enclosing pair one level outward, not two."
  (helixel-test-with-buffer '(:text "(a (b (c)))" :start nil)
    (let ((helixel--action-ring nil) (helixel--live-action nil) (helixel--action-pos nil)) (goto-char 9) (helixel-jump-to-match) (helixel-repeat-last-motion) (let ((last-command 'helixel-repeat-last-motion)) (helixel-action-cycle)) (should (region-active-p)) (should (= (region-beginning) 4)) (should (= (region-end) 11)))
))

(ert-deftest helixel-test-jump-to-match-nopair-backward ()
  "% from non-delim moves to nearest pair char backward and stops."
  (helixel-test-with-buffer '(:text "hello (world)" :start nil)
    (goto-char 8)
    (helixel-jump-to-match)
    (should (= (point) 7))
))

(ert-deftest helixel-test-jump-to-match-nopair-forward ()
  "% at BOB with no backward pair shows no match."
  (helixel-test-with-buffer '(:text "abc def ghi" :start nil)
    (goto-char 1)
    (let ((helixel--last-motion-cmd nil)) (helixel-jump-to-match) (should (= (point) 1)))
))

(ert-deftest helixel-test-jump-to-match-nopair-on-close ()
  "% from a non-pair position with nothing backward falls to core."
  (helixel-test-with-buffer '(:text "abc (def) ghi" :start nil)
    (goto-char 1)
    (helixel-jump-to-match)
    (should (= (point) 1))
))

(ert-deftest helixel-test-jump-to-match-nopair-nested ()
  "% from non-delim moves backward to (; second % jumps to match."
  (helixel-test-with-buffer '(:text "(x (y (z)))" :start nil)
    (goto-char 6)
    (helixel-jump-to-match)
    (should (= (point) 4))
    (helixel-jump-to-match)
    (should (= (point) 11))
))

(ert-deftest helixel-test-forward-match-direct ()
  "helixel-forward-match goes one level outward."
  (helixel-test-with-buffer '(:text "(a) (b) (c)" :start nil)
    (goto-char 4)
    (helixel-forward-match)
    (should (= (point) 4))
))

(ert-deftest helixel-test-backward-match-direct ()
  "helixel-backward-match goes one level outward to parent opener."
  (helixel-test-with-buffer '(:text "(a) (b) (c)" :start nil)
    (goto-char 4)
    (helixel-backward-match)
    (should (= (point) 4))
))

(ert-deftest helixel-test-M-dot-outward-nested ()
  ", goes one level outward to the parent pair."
  (helixel-test-with-buffer '(:text "(outer (inner))" :start nil)
    (goto-char 10)
    (helixel-backward-match)
    (should (= (point) 1))
    (helixel-backward-match)
    (should (= (point) 1))
))

(ert-deftest helixel-test-motion-M-dot-after-backward-percent ()
  ", after backward % goes outward to parent pair."
  (helixel-test-with-buffer '(:text "(outer (inner))" :start nil)
    (goto-char 15)
    (helixel-jump-to-match)
    (should (eq (helixel--last-motion-dir helixel--last-motion-cmd) 'backward))
    (helixel-repeat-last-motion)
    (should (= (point) 1))
    (helixel-repeat-last-motion)
    (should (= (point) 1))
))

(ert-deftest helixel-test-motion-M-dot-match-maintains-direction ()
  ", after forward % dispatches correctly and goes outward."
  (helixel-test-with-buffer '(:text "(outer (inner))" :start nil)
    (goto-char 8)
    (helixel-jump-to-match)
    (should (eq (helixel--last-motion-dir helixel--last-motion-cmd) 'forward))
    (helixel-repeat-last-motion)
    (should (= (point) 15))
))

(ert-deftest helixel-test-motion-M-dot-match-semicolon ()
  ", outward then ; selects a region."
  (helixel-test-with-buffer '(:text "(outer (inner))" :start nil)
    (let ((helixel--action-ring nil) (helixel--live-action nil) (helixel--action-pos nil)) (goto-char 8) (helixel-jump-to-match) (helixel-repeat-last-motion) (let ((last-command 'helixel-repeat-last-motion)) (helixel-action-cycle)) (should (region-active-p)) (should (> (region-end) (region-beginning))))
))

(ert-deftest helixel-test-motion-repeat-with-count ()
  ", replays motion with original prefix count."
  (helixel-test-with-buffer '(:text "a

b

c

d
" :start nil)
    (goto-char 1)
    (let ((current-prefix-arg 2)) (call-interactively #'helixel-forward-paragraph-end))
    (should (helixel--last-motion-p helixel--last-motion-cmd))
    (should (eq (helixel--last-motion-command helixel--last-motion-cmd) 'helixel-forward-paragraph-end))
    (should (eq (helixel--last-motion-prefix-arg helixel--last-motion-cmd) 2))
))

(ert-deftest helixel-test-motion-repeat-paragraph ()
  ", repeats last paragraph-end motion (]p)."
  (helixel-test-with-buffer '(:text "para1

para2

para3
" :start nil)
    (goto-char 1)
    (helixel-forward-paragraph-end)
    (let ((first-pos (point))) (should (> first-pos 1)) (helixel-repeat-last-motion) (should (> (point) first-pos)))
))

(ert-deftest helixel-test-motion-empty-repeat ()
  ", with no prior motion signals user-error."
  (helixel-test-with-buffer '(:text "hello world" :start nil)
    (goto-char 1)
    (let ((helixel--last-motion-cmd nil) (helixel--active-search nil)) (should-error (helixel-repeat-last-motion) :type 'user-error))
))

(ert-deftest helixel-test-motion-word-not-tracked ()
  ", does NOT repeat word motions (w)."
  (helixel-test-with-buffer '(:text "hello world foo" :start nil)
    (goto-char 1)
    (let ((helixel--last-motion-cmd nil) (helixel--active-search nil)) (helixel-forward-word-start) (should (= (point) 7)) (should-not (helixel--last-motion-p helixel--last-motion-cmd)))
))

(ert-deftest helixel-test-motion-semicolon-consistency ()
  "[( , ; selects the same span as [( [( ;."
  (helixel-test-with-buffer '(:text "((char (hello)))" :start nil)
    (goto-char 12)
    (let ((helixel--action-ring nil) (helixel--live-action nil) (helixel--action-pos nil)) (helixel-backward-outer-paren) (let ((last-command 'helixel-backward-outer-paren)) (helixel--action-cycle)) (should (region-active-p)) (should (> (region-end) (region-beginning))))
))

(ert-deftest helixel-test-semicolon-nested-paren-span ()
  "; after consecutive [( selects the full outer span."
  (helixel-test-with-buffer '(:text "((char (hello)))" :start nil)
    (goto-char 12)
    (let ((helixel--action-ring nil) (helixel--live-action nil) (helixel--action-pos nil)) (helixel-backward-outer-paren) (helixel-backward-outer-paren) (helixel--action-cycle) (should (region-active-p)) (should (= (region-beginning) 2)) (should (= (region-end) 16)) (should (string= (buffer-substring-no-properties (region-beginning) (region-end)) "(char (hello))")))
))

(ert-deftest helixel-test-motion-find-char-survives-search ()
  ", replays f x even after /pattern changed active-search.
This is the design property: , reads from self-contained
`helixel--last-motion-cmd' struct, never from `helixel--active-search',
so changing the active-search category cannot break motion repeat."
  (helixel-test-with-buffer '(:text "axb cxd exf" :start nil)
    (goto-char 1)
    (helixel-find-next-char 120)
    (should (= (point) 3))
    (setq helixel--active-search (make-helixel--last-motion :category 'search :pattern "f" :dir 'forward))
    (should (eq (helixel-search--safe-category) 'search))
    (helixel-repeat-last-motion)
    (should (= (point) 7))
    (should (helixel--last-motion-p helixel--last-motion-cmd))
    (should (helixel--last-motion-char helixel--last-motion-cmd))
    (should (eq (helixel--last-motion-type helixel--last-motion-cmd) 'next))
    (should (eq (helixel-search--safe-category) 'search))
))

(ert-deftest helixel-test-motion-category-recorded ()
  "Each motion records its category+subcat in `helixel--last-motion-cmd'.
Movement subcats store category=movement with the specific subcat."
  (helixel-test-with-buffer '(:text "x (a)" :start nil)
    (goto-char 1)
    (helixel-forward-outer-paren)
    (should (eq (helixel--last-motion-category helixel--last-motion-cmd) 'movement))
    (should (eq (helixel--last-motion-subcat helixel--last-motion-cmd) 'pair))
    (goto-char 1)
    (helixel-find-next-char 97)
    (should (eq (helixel--last-motion-category helixel--last-motion-cmd) 'find-char))
    (should (eq (helixel--last-motion-subcat helixel--last-motion-cmd) nil))
))

(ert-deftest helixel-test-motion-repeat-search ()
  ", repeats a search recorded in `helixel--last-motion-cmd'.
Simulates search by directly recording a search entry; real search
recording is tested via integration tests."
  (helixel-test-with-buffer '(:text "abc foo def foo ghi" :start nil)
    (goto-char 1)
    (helixel-record-motion nil :category 'search :pattern "foo" :dir 'forward)
    (helixel-repeat-last-motion)
    (should (= (point) 8))
    (should (region-active-p))
    (helixel-repeat-last-motion)
    (should (= (point) 16))
))

;; ── , boundary skip tests ──

(ert-deftest helixel-test-motion-skip-pair-forward ()
  ", repeats ] past consecutive paren boundaries."
  (helixel-test-with-buffer '(:text "(a) (b) (c)" :start nil)
    (goto-char 1)
    (helixel-forward-outer-paren)
    (should (= (point) 4))
    (helixel-repeat-last-motion)
    (should (= (point) 8))
    (helixel-repeat-last-motion)
    (should (= (point) 12))
)) ;; after ) of (c), end of buffer

(ert-deftest helixel-test-motion-skip-pair-backward ()
  ", repeats [ past consecutive paren boundaries."
  (helixel-test-with-buffer '(:text "(a) (b) (c)" :start nil)
    (goto-char (point-max))
    (helixel-backward-outer-paren)
    (should (= (point) 9))
    (helixel-repeat-last-motion)
    (should (= (point) 5))
    (helixel-repeat-last-motion)
    (should (= (point) 1))
)) ;; at ( of (a)

(ert-deftest helixel-test-motion-skip-pair-nested-from-opener ()
  ", after [ lands on opener steps one level, not two."
  ;; Regression: when [( leaves point on the opening delimiter,
  ;; , must skip past the current pair (not the parent).
  ;; Without the fix, helixel-delimiter-bounds-flat would
  ;; jump past the current opener to the parent opener,
  ;; so , would skip two nesting levels instead of one.
  (helixel-test-with-buffer '(:text "(a (b (c)))" :start nil)
    (goto-char 8)
    (helixel-backward-outer-paren)
    (should (= (point) 7))
    (helixel-repeat-last-motion)
    (should (= (point) 4))
    (helixel-repeat-last-motion)
    (should (= (point) 1))
    (helixel-repeat-last-motion)
    (should (= (point) 1))
))

(ert-deftest helixel-test-motion-skip-block-nested-from-opener ()
  ", after [c lands on block opener steps one level, not two."
  ;; Regression: when [c leaves point on the block opener line,
  ;; , must skip past the current block (not the parent).
  ;; Covers all three opener types:
  ;;   - string openers (blocks in org-mode)
  ;;   - character openers (paren fallback in plain buffer)
  ;;   - nil openers (block fallback to parens)
  (with-temp-buffer
    (transient-mark-mode 1)
    (delay-mode-hooks (org-mode))
    (insert "#+begin_quote\nouter\n#+begin_src elisp\ninner\n#+end_src\nmore\n#+end_quote\n")
    (deactivate-mark)
    (goto-char 35)  ;; inside inner src block
    (helixel-backward-outer-block)
    ;; First [c lands on the inner block opener.
    (should (= (point) 21))  ;; at #+begin_src
    ;; , must go one level outward to outer block opener.
    (helixel-repeat-last-motion)
    (should (= (point) 1))   ;; at #+begin_quote
    ;; At outermost level: no more enclosing block -- returns nil.
    (helixel-repeat-last-motion)
    (should (= (point) 1))))

(ert-deftest helixel-test-motion-skip-inner-pair-forward ()
  ", repeats } past consecutive inner paren boundaries."
  (helixel-test-with-buffer '(:text "(a x) (b y) (c z)" :start nil)
    (goto-char 3)
    (helixel-forward-inner-paren)
    (let ((p1 (point))) (should (> p1 3)) (helixel-repeat-last-motion) (should (> (point) p1)))
)) ;; moved further

(ert-deftest helixel-test-motion-skip-inner-pair-forward-nested ()
  ", repeats } past nested inner paren boundaries one level each."
  ;; } takes cursor to inner ), then , steps to parent ) (not
  ;; grandparent).  Regression: skip-past for inner-forward
  ;; went to CE which equals CB of the parent pair (adjacent ))),
  ;; causing , to double-jump to the grandparent.
  (helixel-test-with-buffer '(:text "(a (b (c)))" :start nil)
    (goto-char 8)
    (helixel-forward-inner-paren)
    (should (= (point) 9))
    (helixel-repeat-last-motion)
    (should (= (point) 10))
    (helixel-repeat-last-motion)
    (should (= (point) 11))
    (helixel-repeat-last-motion)
    (should (= (point) 11))
))

(ert-deftest helixel-test-motion-skip-inner-pair-backward ()
  ", repeats { past consecutive inner paren boundaries."
  (helixel-test-with-buffer '(:text "(a) (b) (c)" :start nil)
    (goto-char 10)
    (helixel-backward-inner-paren)
    (let ((p1 (point))) (helixel-repeat-last-motion) (should (< (point) p1)))
)) ;; moved backward

;;; Backward opener stepping -- [ / { step one level per press

(ert-deftest helixel-test-motion-outer-paren-step-backward ()
  "[ ( steps outward through paren openers one level each press."
  (helixel-test-with-buffer '(:text "(a (b (c)))" :start nil)
    (goto-char 8)
    (helixel-backward-outer-paren)
    (should (= (point) 7))
    (helixel-backward-outer-paren)
    (should (= (point) 4))
    (helixel-backward-outer-paren)
    (should (= (point) 1))
    (helixel-backward-outer-paren)
    (should (= (point) 1))
))

(ert-deftest helixel-test-motion-inner-paren-step-backward ()
  "{ ( steps outward through inner paren openers one level each press."
  (helixel-test-with-buffer '(:text "(a (b (c)))" :start nil)
    (goto-char 8)
    (helixel-backward-inner-paren)
    (should (= (point) 5))
    (helixel-backward-inner-paren)
    (should (= (point) 2))
    (helixel-backward-inner-paren)
    (should (= (point) 2))
))

(ert-deftest helixel-test-motion-comma-repeats-backward-opener ()
  ", repeats [ ( stepping outward through paren openers."
  (helixel-test-with-buffer '(:text "(a (b (c)))" :start nil)
    (goto-char 8)
    (helixel-backward-outer-paren)
    (should (= (point) 7))
    (helixel-repeat-last-motion)
    (should (= (point) 4))
    (helixel-repeat-last-motion)
    (should (= (point) 1))
    (helixel-repeat-last-motion)
    (should (= (point) 1))
))

(ert-deftest helixel-test-motion-outer-paren-backward-adjacent ()
  "[ ( steps one level per press through ((a)) at bob.
Backward opener stepping with adjacent (( — verifies no
`just-entered' check is needed because ob(parent) < ob(child)
always."
  ;; Buffer: ((a)) — 1:( 2:( 3:a 4:) 5:) 6:eob
  (helixel-test-with-buffer '(:text "((a))" :start nil)
    (goto-char 3)
    (helixel-backward-outer-paren)
    (should (= (point) 2))
    (helixel-backward-outer-paren)
    (should (= (point) 1))
    (helixel-backward-outer-paren)
    (should (= (point) 1))
))

(ert-deftest helixel-test-motion-skip-paragraph-forward ()
  ", repeats ]p past consecutive paragraph boundaries."
  (helixel-test-with-buffer '(:text "para1

para2

para3
" :start nil)
    (goto-char 1)
    (helixel-forward-paragraph-end)
    (let ((first-pos (point))) (should (> first-pos 1)) (helixel-repeat-last-motion) (should (> (point) first-pos)) (let ((second-pos (point))) (helixel-repeat-last-motion) (should (> (point) second-pos))))
))

(ert-deftest helixel-test-motion-skip-paragraph-backward ()
  ", repeats [p past consecutive paragraph boundaries backward."
  (helixel-test-with-buffer '(:text "para1

para2

para3
" :start nil)
    (goto-char (point-max))
    (helixel-backward-paragraph-start)
    (let ((first-pos (point))) (should (< first-pos (point-max))) (helixel-repeat-last-motion) (should (< (point) first-pos)) (let ((second-pos (point))) (helixel-repeat-last-motion) (should (< (point) second-pos))))
))

(ert-deftest helixel-test-motion-skip-word-not-recorded ()
  ", cannot repeat word motion (w) — not in repeat categories."
  (helixel-test-with-buffer '(:text "hello world foo" :start nil)
    (goto-char 1)
    (let ((helixel--last-motion-cmd nil)) (helixel-forward-word-start) (should (= (point) 7)) (should-not (helixel--last-motion-p helixel--last-motion-cmd)) (should-error (helixel-repeat-last-motion) :type 'user-error))
))

(ert-deftest helixel-test-percent-after-close ()
  "% right after ) jumps to matching (."
  (helixel-test-with-buffer '(:text "(hello) world" :start nil)
    (goto-char 8)
    (helixel-jump-to-match)
    (should (= (point) 1))
))

(ert-deftest helixel-test-percent-on-bracket ()
  "% on ] jumps to matching [."
  (helixel-test-with-buffer '(:text "[hello]" :start nil)
    (goto-char 7)
    (helixel-jump-to-match)
    (should (= (point) 1))
))

(ert-deftest helixel-test-percent-on-brace ()
  "% on } jumps to matching {."
  (helixel-test-with-buffer '(:text "{hello}" :start nil)
    (goto-char 7)
    (helixel-jump-to-match)
    (should (= (point) 1))
))

(ert-deftest helixel-test-M-dot-deeply-nested ()
  ", works through 3 levels of nesting."
  (helixel-test-with-buffer '(:text "(a (b (c)))" :start nil)
    (goto-char 8)
    (helixel-jump-to-match)
    (should (= (point) 7))
    (helixel-repeat-last-motion)
    (should (= (point) 4))
    (helixel-repeat-last-motion)
    (should (= (point) 1))
    (helixel-repeat-last-motion)
    (should (= (point) 1))
))

(ert-deftest helixel-test-M-dot-from-inside-pair ()
  ", from inside a pair goes outward to parent."
  (helixel-test-with-buffer '(:text "(outer (inner))" :start nil)
    (goto-char 10)
    (helixel-jump-to-match)
    (should (= (point) 8))
    (helixel-jump-to-match)
    (helixel-repeat-last-motion)
    (should (= (point) 15))
))

(ert-deftest helixel-test-M-dot-at-bob ()
  ", at beginning of buffer does nothing."
  (helixel-test-with-buffer '(:text "(hello)" :start nil)
    (goto-char 1)
    (helixel-jump-to-match)
    (goto-char 1)
    (let ((helixel--last-motion-cmd (make-helixel--last-motion :category 'movement :subcat 'match :command 'helixel-jump-to-match :dir 'forward))) (helixel-repeat-last-motion) (should (= (point) 1)))
))

(ert-deftest helixel-test-percent-then-percent-then-M-dot ()
  "Two % presses then , outward."
  (helixel-test-with-buffer '(:text "(outer (inner))" :start nil)
    (goto-char 8)
    (helixel-jump-to-match)
    (should (= (point) 15))
    (helixel-jump-to-match)
    (should (= (point) 8))
    (helixel-repeat-last-motion)
    (should (>= (point) 1))
))

(ert-deftest helixel-test-semicolon-after-multiple-M-dot ()
  "; after % + , + , marks the outermost pair."
  (helixel-test-with-buffer '(:text "(a (b (c)))" :start nil)
    (let ((helixel--action-ring nil) (helixel--live-action nil) (helixel--action-pos nil)) (goto-char 8) (helixel-jump-to-match) (should (= (point) 7)) (helixel-repeat-last-motion) (should (= (point) 4)) (helixel-repeat-last-motion) (should (= (point) 1)) (let ((last-command 'helixel-repeat-last-motion)) (helixel-action-cycle)) (should (region-active-p)) (should (> (region-end) (region-beginning))))
))

(ert-deftest helixel-test-percent-backward-from-text ()
  "% from inside text goes backward to nearest (."
  (helixel-test-with-buffer '(:text "abc(def)ghi" :start nil)
    (goto-char 8)
    (helixel-jump-to-match)
    (should (= (point) 4))
))

;;; ── % + , outward navigation for tags and blocks ──

(ert-deftest helixel-test-percent-inside-tag ()
  "% inside a tag (right after >) jumps to the matching closing tag.
Point is after the > of <div>, which is a close delimiter for the
angle-bracket pair — so % enters the jump path and lands at </div>."
  (helixel-test-with-buffer '(:text "<div>hi</div>" :start nil)
    (goto-char 6)
    (helixel-jump-to-match)
    (should (= (point) 14))
))

(ert-deftest helixel-test-percent-inside-tag-before-gt ()
  "% inside tag before > moves backward to < (reposition).
Point is on 'd' of <div>, before the >.  char-before is < which
is not a close char, so we enter the backward-reposition path."
  (helixel-test-with-buffer '(:text "<div>hi</div>" :start nil)
    (goto-char 2)
    (helixel-jump-to-match)
    (should (= (point) 1))
))

(ert-deftest helixel-test-percent-on-tag-opener ()
  "% on < of an opening tag jumps to the matching </div>."
  (helixel-test-with-buffer '(:text "<div>hi</div>" :start nil)
    (goto-char 1)
    (helixel-jump-to-match)
    (should (= (point) 14))
))

(ert-deftest helixel-test-M-dot-after-percent-on-tag ()
  ", after % on a tag goes outward to parent tag's closer."
  (helixel-test-with-buffer '(:text "<outer><inner>hi</inner></outer>" :start nil)
    (goto-char 8)
    (helixel-jump-to-match)
    (helixel-repeat-last-motion)
    (should (= (point) 33))
))

;;; ── , + % comprehensive coverage: tag, block, regex, cross-type ──

;; ── Counter-based block (different begin/end) ──

(ert-deftest helixel-test-M-dot-after-percent-on-block ()
  ", after % on a block delimiter outward to parent block.
Uses counter-based (different begin/end) fence patterns
registered via `helixel-block-textobj-alist'."
  (with-temp-buffer
    (fundamental-mode)
    (transient-mark-mode 1)
    (let ((helixel-block-textobj-alist
           '((fundamental-mode . ("^<|" "^|>" nil))))
          (helixel-block-textobj-fallback-alist nil)
          (helixel--block-no-bracket-fallback t))
      ;; Outer fence, inner fence, content, inner close, outer close
      (insert "<|outer\n<|inner\nhello\n|>inner\n|>outer\n")
      (deactivate-mark)
      ;; Point on < of <|inner so % jumps to matching |>
      (goto-char (point-min))
      (forward-line 1)
      (let ((start-pos (point)))
        (helixel-jump-to-match)  ;; % → jumps to matching close
        (should (> (point) start-pos))
        (let ((pos-after-pct (point)))
          ;; , → outward to parent block's close
          (helixel-repeat-last-motion)
          (should (> (point) pos-after-pct)))))))

;; ── Tag outward navigation ──

(ert-deftest helixel-test-M-dot-tag-outward ()
  ", after % on a tag goes outward to parent tag."
  (helixel-test-with-buffer '(:text "<a><b>hi</b></a>" :start nil)
    (goto-char 4)
    (helixel-jump-to-match)
    (let ((b-close (point))) (should (> b-close 10)) (helixel-repeat-last-motion) (should (> (point) b-close)))
))

(ert-deftest helixel-test-M-dot-tag-outward-from-content ()
  ", after % from inside tag content outward to parent."
  (helixel-test-with-buffer '(:text "<a><b>text</b></a>" :start nil)
    (goto-char 5)
    (helixel-jump-to-match)
    (helixel-jump-to-match)
    (let ((b-close (point))) (should (> b-close 10)) (helixel-repeat-last-motion) (should (> (point) b-close)))
))

;; ── Named block (org-mode #+begin/#+end) ──

(ert-deftest helixel-test-percent-on-named-block-close ()
  "% on #+end_src jumps to matching #+begin_src in org-mode."
  (with-temp-buffer
    (org-mode)
    (transient-mark-mode 1)
    (insert "#+begin_src elisp\n(message \"hi\")\n#+end_src\n")
    (deactivate-mark)
    ;; On #+end_src line
    (goto-char (point-max))
    (forward-line -1)
    (let ((end-pos (point)))
      (helixel-jump-to-match)
      ;; Should jump to #+begin_src (pos 1), not to a nearby pair char
      (should (= (point) 1)))))

(ert-deftest helixel-test-percent-on-named-block-open ()
  "% on #+begin_src jumps to matching #+end_src in org-mode."
  (with-temp-buffer
    (org-mode)
    (transient-mark-mode 1)
    (insert "#+begin_src elisp\n(message \"hi\")\n#+end_src\n")
    (deactivate-mark)
    (goto-char 1)  ;; on # of #+begin_src
    (helixel-jump-to-match)
    ;; Should jump somewhere after the content, near #+end_src
    (should (> (point) 20))))

(ert-deftest helixel-test-M-dot-named-block-outward ()
  ", after % inside an org block outward using cross-type fallback.
Tests that cross-type outward fallback finds the enclosing named block."
  (with-temp-buffer
    (org-mode)
    (transient-mark-mode 1)
    (insert "#+begin_src elisp\n(helixel-mode)\n#+end_src\n")
    (deactivate-mark)
    ;; % from ( of (helixel-mode)
    (goto-char (point-min))
    (forward-line 1)  ;; on (helixel-mode) line
    (let ((paren-pos (point)))
      (helixel-jump-to-match)  ;; % from ( → matching )
      (let ((paren-close (point)))
        (should (> paren-close paren-pos))
        ;; , outward → cross-type fallback to #+begin_src
        (helixel-repeat-last-motion)
        (should (not (= (point) paren-close)))))))

;; ── Toggle-based block (same begin/end) ──

(ert-deftest helixel-test-percent-on-toggle-block ()
  "% on a toggle-based fence (same begin/end) jumps to match."
  (with-temp-buffer
    (fundamental-mode)
    (transient-mark-mode 1)
    (let ((helixel-block-textobj-alist
           '((fundamental-mode . ("^xxx$" "^xxx$" nil))))
          (helixel-block-textobj-fallback-alist nil)
          (helixel--block-no-bracket-fallback t))
      ;; Toggle fence: each xxx toggles the counter
      (insert "xxx\nhello\nxxx\n")
      (deactivate-mark)
      (goto-char 1)  ;; on first xxx
      (helixel-jump-to-match)
      ;; Should jump somewhere past "hello"
      (should (> (point) 6)))))

;; ── Regex textobj ──

(ert-deftest helixel-test-M-dot-regex-textobj-outward ()
  ", after % on a regex-defined text object outward to parent."
  (with-temp-buffer
    (fundamental-mode)
    (transient-mark-mode 1)
    (let ((helixel-block-textobj-alist
           '((fundamental-mode . ("^<<<" "^>>>" nil))))
          (helixel-block-textobj-fallback-alist nil)
          (helixel--block-no-bracket-fallback t))
      (insert "<<<\n<<<\nhello\n>>>\n>>>\n")
      (deactivate-mark)
      (goto-char (point-min))
      (forward-line 1)  ;; on inner opener <<<
      (helixel-jump-to-match)  ;; % → inner close >>>
      (let ((inner-close (point)))
        (should (> inner-close 1))
        (helixel-repeat-last-motion)  ;; , → outward to outer >>>
        (should (> (point) inner-close))))))

;; ── Cross-type outward: pair → block ──

(ert-deftest helixel-test-M-dot-cross-type-pair-to-block ()
  ", after % on a pair inside a block outward to the block."
  (with-temp-buffer
    (org-mode)
    (transient-mark-mode 1)
    (insert "#+begin_src elisp\n(use-package helixel)\n#+end_src\n")
    (deactivate-mark)
    (goto-char (point-min))
    (forward-line 1)
    (forward-char 5)  ;; on 'package' inside (use-package ...)
    ;; %: reposition backward to (, then actually jump
    (helixel-jump-to-match)  ;; reposition to (
    (let ((paren-open (point)))
      (helixel-jump-to-match)  ;; % from ( → jumps to matching )
      (let ((paren-close (point)))
        (should (> paren-close paren-open))
        ;; , outward from ) → should go to #+begin_src
        (helixel-repeat-last-motion)
        ;; moved outward past the enclosing pair
        (should (not (= (point) paren-close)))))))

(ert-deftest helixel-test-M-dot-cross-type-pair-to-tag ()
  ", after % on a pair inside a tag outward to the tag."
  (helixel-test-with-buffer '(:text "<div>(hello)</div>" :start nil)
    (goto-char 6)
    (helixel-jump-to-match)
    (let ((paren-close (point))) (should (> paren-close 6)) (helixel-repeat-last-motion) (should (not (= (point) paren-close))))
))

;; ── Repeated , across 3 levels ──

(ert-deftest helixel-test-M-dot-repeated-outward ()
  "Repeated , presses navigate through multiple nesting levels."
  (with-temp-buffer
    (fundamental-mode)
    (transient-mark-mode 1)
    (let ((helixel-block-textobj-alist
           '((fundamental-mode . ("^<|" "^|>" nil))))
          (helixel-block-textobj-fallback-alist nil)
          (helixel--block-no-bracket-fallback t))
      (insert "<|a\n<|b\n<|c\nhello\n|>c\n|>b\n|>a\n")
      (deactivate-mark)
      ;; On < of <|c
      (goto-char (point-min))
      (forward-line 2)
      (let ((start (point)))
        (helixel-jump-to-match)  ;; % → matching close
        (should (> (point) start))
        (let ((p1 (point)))
          (helixel-repeat-last-motion)  ;; , → parent close
          (should (> (point) p1))
          (let ((p2 (point)))
            (helixel-repeat-last-motion)  ;; , → grandparent close
            (should (> (point) p2))))))))

;; ── Outermost-noop ──

(ert-deftest helixel-test-M-dot-outermost-noop ()
  ", at the outermost level does not move or errors gracefully."
  (with-temp-buffer
    (fundamental-mode)
    (transient-mark-mode 1)
    (let ((helixel-block-textobj-alist
           '((fundamental-mode . ("^<|" "^|>" nil))))
          (helixel-block-textobj-fallback-alist nil)
          (helixel--block-no-bracket-fallback t))
      (insert "<|outer\nhello\n|>outer\n")
      (deactivate-mark)
      (goto-char 1)  ;; on <|
      (helixel-jump-to-match)  ;; % → matching |>
      (let ((p (point)))
        (should (> p 1))
        ;; , outward — outermost, no parent
        (condition-case nil
            (helixel-repeat-last-motion)
          (user-error nil))
        ;; Should not move (or show error and stay)
        (should (= (point) p))))))

;;; ── ; selects region after % on block / regex / tag ──

(ert-deftest helixel-test-semicolon-after-percent-on-block ()
  "; after % on a counter-based block selects the block region."
  (with-temp-buffer
    (fundamental-mode)
    (transient-mark-mode 1)
    (let ((helixel-block-textobj-alist
           '((fundamental-mode . ("^<|" "^|>" nil))))
          (helixel-block-textobj-fallback-alist nil)
          (helixel--block-no-bracket-fallback t))
      (insert "<|outer\n<|inner\nhello\n|>inner\n|>outer\n")
      (deactivate-mark)
      (goto-char (point-min))
      (forward-line 1)  ;; on <|inner line
      (let ((block-open (point)))
        (helixel-jump-to-match)  ;; % → jumps to matching close
        (let ((last-command 'helixel-jump-to-match))
          (helixel-action-cycle))  ;; ; → select the block
        (should (region-active-p))
        ;; Region should start at the block opener
        (should (= (region-beginning) block-open))))))

(ert-deftest helixel-test-semicolon-after-percent-on-regex-block ()
  "; after % on a regex-defined textobj selects the region."
  (with-temp-buffer
    (fundamental-mode)
    (transient-mark-mode 1)
    (let ((helixel-block-textobj-alist
           '((fundamental-mode . ("^<<<" "^>>>" nil))))
          (helixel-block-textobj-fallback-alist nil)
          (helixel--block-no-bracket-fallback t))
      (insert "<<<\nhello\n>>>\n")
      (deactivate-mark)
      (goto-char 1)  ;; on <<< opener
      (let ((block-open (point)))
        (helixel-jump-to-match)  ;; % → jumps to matching >>>
        (let ((last-command 'helixel-jump-to-match))
          (helixel-action-cycle))  ;; ; → select the block
        (should (region-active-p))
        (should (= (region-beginning) block-open))))))

(ert-deftest helixel-test-semicolon-after-percent-on-named-block ()
  "; after % on an org-mode named block selects the block region."
  (with-temp-buffer
    (org-mode)
    (transient-mark-mode 1)
    (insert "#+begin_src elisp\n(message \"hi\")\n#+end_src\n")
    (deactivate-mark)
    (goto-char 1)  ;; on #+begin_src
    (let ((block-open (point)))
      (helixel-jump-to-match)  ;; % → jumps to #+end_src
      (let ((last-command 'helixel-jump-to-match))
        (helixel-action-cycle))  ;; ; → select the block
      (should (region-active-p))
      (should (= (region-beginning) block-open)))))

(ert-deftest helixel-test-semicolon-after-percent-on-toggle-block ()
  "; after % on a toggle-based fence selects the block region."
  (with-temp-buffer
    (fundamental-mode)
    (transient-mark-mode 1)
    (let ((helixel-block-textobj-alist
           '((fundamental-mode . ("^xxx$" "^xxx$" nil))))
          (helixel-block-textobj-fallback-alist nil)
          (helixel--block-no-bracket-fallback t))
      (insert "xxx\nhello\nxxx\n")
      (deactivate-mark)
      (goto-char 1)  ;; on first xxx
      (let ((block-open (point)))
        (helixel-jump-to-match)  ;; % → jumps to matching xxx
        (let ((last-command 'helixel-jump-to-match))
          (helixel-action-cycle))  ;; ; → select the block
        (should (region-active-p))
        (should (= (region-beginning) block-open))))))

;;; ── Mode-aware surround-pairs filtering ──

(ert-deftest helixel-test-surround-pairs-active-no-org-markers ()
  "In fundamental-mode, org emphasis markers are excluded."
  (with-temp-buffer
    (fundamental-mode)
    (let ((active (helixel--surround-pairs-active)))
      (should-not (cl-some (lambda (e)
                             (eq (helixel--surround-entry-open e) ?*))
                           active))
      (should-not (cl-some (lambda (e)
                             (eq (helixel--surround-entry-open e) ?~))
                           active)))))

(ert-deftest helixel-test-surround-pairs-active-has-org-markers ()
  "In org-mode, org emphasis markers are included."
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (let ((active (helixel--surround-pairs-active)))
      (should (cl-some (lambda (e)
                         (eq (helixel--surround-entry-open e) ?*))
                       active))
      (should (cl-some (lambda (e)
                         (eq (helixel--surround-entry-open e) ?~))
                       active)))))

(ert-deftest helixel-test-surround-pairs-active-universal ()
  "Universal pairs () [] {} are available in all modes."
  (with-temp-buffer
    (fundamental-mode)
    (let ((active (helixel--surround-pairs-active)))
      (should (cl-some (lambda (e)
                         (eq (helixel--surround-entry-open e) ?\())
                       active))
      (should (cl-some (lambda (e)
                         (eq (helixel--surround-entry-open e) ?\[))
                       active))
      (should (cl-some (lambda (e)
                         (eq (helixel--surround-entry-open e) ?\{))
                       active)))))

;;; ── pair-chars type filter ──

(ert-deftest helixel-test-pair-chars-type-filter ()
  "helixel--pair-chars with :pair filter excludes quotes."
  (with-temp-buffer
    (fundamental-mode)
    (let ((all (helixel--pair-chars nil))
          (pairs-only (helixel--pair-chars :pair)))
      ;; Quotes are in all-chars but not in pairs-only
      (should (memq ?\" all))
      (should-not (memq ?\" pairs-only))
      ;; Brackets are in both
      (should (memq ?\( pairs-only))
      (should (memq ?\) pairs-only)))))

;;; ── close-chars correctness ──

(ert-deftest helixel-test-close-chars ()
  "helixel--close-chars returns close delimiters only."
  (with-temp-buffer
    (fundamental-mode)
    (let ((close (helixel--close-chars)))
      ;; Close delimiters
      (should (memq ?\) close))
      (should (memq ?\] close))
      (should (memq ?\} close))
      ;; Open delimiters are NOT close chars
      (should-not (memq ?\( close))
      (should-not (memq ?\[ close))
      (should-not (memq ?\{ close)))))

;;; ── % excludes quotes ──

(ert-deftest helixel-test-percent-on-single-quote-noop ()
  "% on single quote does not jump — quotes are excluded."
  (helixel-test-with-buffer '(:text "x 'hi' y" :start nil)
    (goto-char 3)
    (let ((pt-before (point))) (helixel-jump-to-match) (should (= (point) pt-before)))
))

(ert-deftest helixel-test-percent-on-backtick-noop ()
  "% on backtick does not jump — quotes are excluded."
  (helixel-test-with-buffer '(:text "x `hi` y" :start nil)
    (goto-char 3)
    (let ((pt-before (point))) (helixel-jump-to-match) (should (= (point) pt-before)))
))

;;; ── , edge cases ──

(ert-deftest helixel-test-M-dot-no-delimiter-fallback ()
  ", works after syntax-table-only % (no stored delimiter)."
  (helixel-test-with-buffer '(:text "(outer (inner))" :start nil)
    (goto-char 8)
    (helixel-jump-to-match)
    (helixel-repeat-last-motion)
    (should (= (point) 15))
))

(ert-deftest helixel-test-M-dot-multiple-levels-mixed ()
  ", works through bracket + brace nesting."
  (helixel-test-with-buffer '(:text "{a (b [c])}" :start nil)
    (goto-char 8)
    (helixel-jump-to-match)
    (should (= (point) 7))
    (helixel-repeat-last-motion)
    (should (= (point) 4))
    (helixel-repeat-last-motion)
    (should (= (point) 1))
    (helixel-repeat-last-motion)
    (should (= (point) 1))
))

;;; ── % inside string skips quotes, finds enclosing bracket ──

(ert-deftest helixel-test-percent-inside-string ()
  "% inside a string moves backward past the quote to the nearest bracket."
  (helixel-test-with-buffer '(:text "(message \"hello world\")" :start nil)
    (goto-char 14)
    (helixel-jump-to-match)
    (should (= (point) 1))
    (save-excursion (helixel--jump-to-match-core))
    (should (helixel-action-mark-region helixel--live-action))
))

(ert-deftest helixel-test-percent-inside-nested-string ()
  "% inside nested string skips both quotes, finds outer bracket."
  (helixel-test-with-buffer '(:text "[x \"hi\" y]" :start nil)
    (goto-char 5)
    (helixel-jump-to-match)
    (should (= (point) 1))
))

;;; helixel-test-move.el ends here

;;; ── Layer-by-layer outward: , closest-enclosing-wins ──

(ert-deftest helixel-test-M-dot-layer-pair-then-block ()
  ", from inside pair expands pair->parent->block."
  (with-temp-buffer
    (org-mode)
    (transient-mark-mode 1)
    (insert "#+begin_src elisp\n(defun hello()\n  (message x)\n  )\n#+end_src\n")
    (deactivate-mark)
    (goto-char (point-min))
    (search-forward "x")
    (goto-char (match-beginning 0))
    (helixel-jump-to-match)
    (should (= (char-after) ?\())
    (helixel-repeat-last-motion)
    (should (looking-at "(defun"))
    (helixel-repeat-last-motion)
    (should (= (point) 1))
    (helixel-repeat-last-motion)
    (should (= (point) 1))))

(ert-deftest helixel-test-M-dot-block-not-stolen-by-orphan-brace ()
  ", inside block with orphaned { finds the block."
  (with-temp-buffer
    (org-mode)
    (transient-mark-mode 1)
    (insert "Or manually:(  {\n#+begin_src elisp\n  (add-to-list x)\n#+end_src\n")
    (deactivate-mark)
    (goto-char (point-min))
    (search-forward "add-to-list")
    (goto-char (match-beginning 0))
    (helixel-jump-to-match)
    (should (= (char-after) ?\())
    (helixel-repeat-last-motion)
    (should (looking-at "#\\+begin_src"))))

(ert-deftest helixel-test-M-dot-syntax-propertize-org-gt ()
  ", from pair with >=29.1 finds block not >."
  (with-temp-buffer
    (org-mode)
    (transient-mark-mode 1)
    (insert "#+begin_src elisp\n  (use-package helixel)\n#+end_src\n\nRequires Emacs >= 29.1.\n")
    (deactivate-mark)
    (goto-char (point-min))
    (search-forward "use-package")
    (goto-char (match-beginning 0))
    (helixel-jump-to-match)
    (should (= (char-after) ?\())
    (helixel-repeat-last-motion)
    (should (= (point) 1))))

(ert-deftest helixel-test-M-dot-stored-delimiter-wins-over-closer-block ()
  "Stored block delimiter from % beats same block from pass 3."
  (with-temp-buffer
    (fundamental-mode)
    (transient-mark-mode 1)
    (let ((helixel-block-textobj-alist
           '((fundamental-mode . ("^<|" "^|>" nil))))
          (helixel-block-textobj-fallback-alist nil)
          (helixel--block-no-bracket-fallback t))
      (insert "<|outer\n<|inner\nhello\n|>inner\n|>outer\n")
      (deactivate-mark)
      (goto-char 9)
      (helixel-jump-to-match)
      (let ((inner-close (point)))
        (should (> inner-close 9))
        (helixel-repeat-last-motion)
        (should (> (point) inner-close))
        (should (not (= (point) inner-close)))))))

(ert-deftest helixel-test-M-dot-mixed-bracket-block-priority ()
  ", from pair inside block: outward one level at a time."
  (with-temp-buffer
    (org-mode)
    (transient-mark-mode 1)
    (insert "#+begin_src elisp\n(let ((x 1))\n  x)\n#+end_src\n")
    (deactivate-mark)
    (goto-char (point-min))
    (search-forward "x 1")
    (goto-char (match-beginning 0))
    (helixel-jump-to-match)
    (should (= (char-after) ?\())
    ;; First , goes one level out — from (x 1) to the bindings list opener
    (helixel-repeat-last-motion)
    (should (= (char-after) ?\())  ;; now at first ( of ((x 1))
    ;; Second , goes to (let ...)
    (helixel-repeat-last-motion)
    (should (looking-at "(let"))
    ;; Third , goes to begin_src (point=1)
    (helixel-repeat-last-motion)
    (should (= (point) 1))))

(ert-deftest helixel-test-M-dot-tag-priority-over-pair ()
  ", from pair inside tag moves outward past the pair."
  (with-temp-buffer
    (fundamental-mode)
    (transient-mark-mode 1)
    (insert "<div>(hello)</div>")
    (deactivate-mark)
    (goto-char 6)
    (helixel-jump-to-match)
    (let ((paren-close (point)))
      (should (> paren-close 6))
      (helixel-repeat-last-motion)
      (should (not (= (point) paren-close))))))

(ert-deftest helixel-test-M-dot-raw-up-list-then-block ()
  ", uses raw up-list for consecutive parens, fallback to block."
  (with-temp-buffer
    (org-mode)
    (transient-mark-mode 1)
    (insert "#+begin_src elisp\n(a (b (c)))\n#+end_src\n")
    (deactivate-mark)
    (goto-char (point-min))
    (search-forward "c)")
    (backward-char 2)
    (helixel-jump-to-match)
    (should (= (char-after) ?\())
    (helixel-repeat-last-motion)
    (should (looking-at "(b"))
    (helixel-repeat-last-motion)
    (should (looking-at "(a"))
    (helixel-repeat-last-motion)
    (should (= (point) 1))))

(ert-deftest helixel-test-M-dot-no-block-in-plain-mode ()
  ", in fundamental-mode with only bracket pairs still works."
  (with-temp-buffer
    (fundamental-mode)
    (transient-mark-mode 1)
    (insert "(outer (inner))")
    (deactivate-mark)
    (goto-char 10)
    (helixel-backward-match)
    (should (= (point) 1))
    (helixel-backward-match)
    (should (= (point) 1))))

;; ============================================================================
;; % blank-line boundary (regression: don't cross paragraphs)
;; ============================================================================

(ert-deftest helixel-test-percent-blank-line-boundary ()
  "% from inside a paragraph does not find delimiters across blank lines."
  (helixel-test-with-buffer '(:text "(far-away)

inside text" :start nil)
    (goto-char (point-max))
    (forward-char -3)
    (let ((helixel--last-motion-cmd nil)) (helixel-jump-to-match) (should (= (point) (- (point-max) 3))))
))

(ert-deftest helixel-test-percent-same-paragraph-works ()
  "% from inside a paragraph still finds delimiters on the same line."
  (helixel-test-with-buffer '(:text "hello (world)" :start nil)
    (goto-char 8)
    (helixel-jump-to-match)
    (should (= (point) 7))
))

(ert-deftest helixel-test-percent-no-blank-line-multiline ()
  "% finds delimiter across newlines when no blank line separates them."
  (helixel-test-with-buffer '(:text "(foo
 bar
 baz)
quux" :start nil)
    (goto-char (point-max))
    (forward-char -2)
    (helixel-jump-to-match)
    (should (= (char-after) 41))
))

;; ============================================================================
;; ; mark-region after each jump strategy
;; ============================================================================

(ert-deftest helixel-test-semicolon-after-jump-via-pair ()
  "; after % on pair delimiter selects the matched region."
  (helixel-test-with-buffer '(:text "before (inner content) after" :start nil)
    (let ((helixel--action-ring nil) (helixel--live-action nil) (helixel--action-pos nil)) (goto-char 8) (helixel-jump-to-match) (let ((last-command 'helixel-jump-to-match)) (helixel-action-cycle)) (should (region-active-p)) (should (string= (buffer-substring (region-beginning) (region-end)) "(inner content)")))
))

(ert-deftest helixel-test-semicolon-after-jump-via-syntax ()
  "; after % via syntax-table selects the matched region."
  (helixel-test-with-buffer '(:text "before (inner) after" :start nil)
    (let ((helixel--action-ring nil) (helixel--live-action nil) (helixel--action-pos nil)) (goto-char 12) (helixel-jump-to-match) (let ((last-command 'helixel-jump-to-match)) (helixel-action-cycle)) (should (region-active-p)) (should (string= (buffer-substring (region-beginning) (region-end)) "(inner)")))
))

;; ============================================================================
;; surround struct accessor round-trip
;; ============================================================================

(ert-deftest helixel-test-surround-entry-struct-roundtrip ()
  "Surround-entry struct accessors return correct values."
  (let ((e (helixel--make-surround-entry
            :open ?\( :close ?\) :type :pair
            :meta '(:modes (emacs-lisp-mode)))))
    (should (helixel--surround-entry-p e))
    (should (eq (helixel--surround-entry-open e) ?\())
    (should (eq (helixel--surround-entry-close e) ?\)))
    (should (eq (helixel--surround-entry-type e) :pair))
    (should (equal (helixel--surround-entry-meta e)
                   '(:modes (emacs-lisp-mode))))))

(ert-deftest helixel-test-surround-entry-struct-no-meta ()
  "Surround-entry without :meta has nil meta slot."
  (let ((e (helixel--make-surround-entry
            :open ?\[ :close ?\] :type :pair)))
    (should (helixel--surround-entry-p e))
    (should-not (helixel--surround-entry-meta e))))

(ert-deftest helixel-test-surround-entry-applicable-mode-filter ()
  "helixel--surround-entry-applicable-p respects :modes."
  (let ((org-only (helixel--make-surround-entry
                   :open ?* :close ?* :type :quote
                   :meta '(:modes (org-mode))))
        (universal (helixel--make-surround-entry
                    :open ?\( :close ?\) :type :pair)))
    (with-temp-buffer
      (fundamental-mode)
      (should-not (helixel--surround-entry-applicable-p org-only))
      (should (helixel--surround-entry-applicable-p universal)))
    (with-temp-buffer
      (delay-mode-hooks (org-mode))
      (should (helixel--surround-entry-applicable-p org-only))
      (should (helixel--surround-entry-applicable-p universal)))))

(ert-deftest helixel-test-surround-lookup-returns-struct ()
  "helixel--surround-lookup returns a struct for pair entries."
  (with-temp-buffer
    (fundamental-mode)
    (let ((entry (helixel--surround-lookup ?\()))
      (should (helixel--surround-entry-p entry))
      (should (eq (helixel--surround-entry-open entry) ?\())
      (should (eq (helixel--surround-entry-close entry) ?\))))))

(ert-deftest helixel-test-surround-block-lookup-returns-struct ()
  "helixel--surround-block-lookup returns a struct (no more cons fallback)."
  ;; This test only works when a block alist entry exists for the current mode.
  ;; In fundamental-mode, block lookup returns nil.
  (with-temp-buffer
    (fundamental-mode)
    (should-not (helixel--surround-block-lookup ?b))))

;; ============================================================================
;; helixel--jump-to-match-core decomposed sub-functions
;; ============================================================================

(ert-deftest helixel-test-jump-via-pair-adjacent ()
  "%% on adjacent pair () jumps to the matching delimiter."
  (helixel-test-with-buffer '(:text "()" :start nil)
    (goto-char 1)
    (helixel-jump-to-match)
    (should (> (point) 2))
))

(ert-deftest helixel-test-jump-via-syntax-from-inside ()
  "%% from inside parens jumps to nearer end via syntax-table."
  (helixel-test-with-buffer '(:text "(inner)" :start nil)
    (goto-char 3)
    (helixel-jump-to-match)
    (should (memq (point) '(1 7)))
))

(ert-deftest helixel-test-jump-to-match-core-no-delimiter ()
  "jump-to-match-core returns nil when point is not near any delimiter."
  (helixel-test-with-buffer '(:text "just some random text without any brackets" :start nil)
    (goto-char 10)
    (should-not (helixel--jump-to-match-core))
    (should (= (point) 10))
))

;; --- helixel--skip-newline ---

(ert-deftest helixel-test-skip-newline-forward ()
  "skip-newline forward jumps past \n."
  (helixel-test-with-buffer '(:text "foo\nbar" :start nil :mode text-mode)
    (goto-char 4)                 ; at \n
    (helixel--skip-newline 1)
    (should (eql (char-after) ?b))))

(ert-deftest helixel-test-skip-newline-backward ()
  "skip-newline backward jumps onto \n from position after it."
  (helixel-test-with-buffer '(:text "foo\nbar" :start nil :mode text-mode)
    (goto-char 5)                 ; at b after \n
    (helixel--skip-newline -1)
    (should (eql (char-after) ?\n))))

(ert-deftest helixel-test-skip-newline-noop-eob ()
  "skip-newline forward at eob is a no-op."
  (helixel-test-with-buffer '(:text "x" :start nil :mode text-mode)
    (goto-char (point-max))
    (let ((pos (point)))
      (helixel--skip-newline 1)
      (should (eql (point) pos)))))

;; --- helixel--clear-non-movement-pending-sel ---

(ert-deftest helixel-test-clear-non-movement-pending-sel-clears-line ()
  "Clears a line pending-sel."
  (let ((helixel--pending-sel (make-helixel-line-sel :dir 'forward :count 1)))
    (helixel--clear-non-movement-pending-sel)
    (should-not helixel--pending-sel)))

(ert-deftest helixel-test-clear-non-movement-pending-sel-keeps-movement ()
  "Keeps a movement pending-sel."
  (let ((helixel--pending-sel (make-helixel-movement-sel :moves '((forward-word . 1)))))
    (helixel--clear-non-movement-pending-sel)
    (should (eq (helixel-sel-kind helixel--pending-sel) 'helixel-movement-sel))))
