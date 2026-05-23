;;; helixel-test-move.el --- Tests for Helixel: movement  -*- lexical-binding: t; -*-

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

;;; Forward long word tests

(ert-deftest helixel-test-forward-WORD-start-basic-movement ()
  "Test basic forward movement between words.
On the last word at eob, w selects the word suffix."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello world test")
    (goto-char 1)
    (helixel-forward-WORD-start)
    (should (= (point) 7)) ; cursor at region-end (*-start)
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-forward-WORD-start)
    (should (= (point) 13)) ; before "test"
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-forward-WORD-start)
    ;; Last word at eob: selects "test" from point to end
    (should (= (point) 17))
    (should (= (- (region-end) (region-beginning)) 4))))

(ert-deftest helixel-test-forward-WORD-start-hyphenated-words ()
  "Test forward movement with hyphenated words (long words)."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "this test-string-example works")
    (goto-char 1)
    (helixel-forward-WORD-start)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-forward-WORD-start)
    (should (= (point) 26))
    (should (= (- (region-end) (region-beginning)) 20))))

(ert-deftest helixel-test-forward-WORD-start-on-whitespace ()
  "Test that forward movement skips over whitespace."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "word next")
    (goto-char 5) ; on the first whitespace
    (helixel-forward-WORD-start)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 1))))

(ert-deftest helixel-test-forward-WORD-start-on-whitespaces ()
  "Test that forward movement skips over whitespace."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "word   \t  next")
    (goto-char 5) ; on the first whitespace
    (helixel-forward-WORD-start)
    (should (= (point) 11))
    (should (= (- (region-end) (region-beginning)) 6))))

(ert-deftest helixel-test-forward-WORD-start-multiple-lines ()
  "Test forward movement across multiple lines.
When a WORD ends at end of line, stop at end of word (exclude newline)."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "first line\nsecond line\nthird")
    (goto-char 1) ; start of buffer
    (helixel-forward-WORD-start)
    (should (= (point) 7))
    (should (= (- (region-end) (region-beginning)) 6))
    ;; "line" ends at \n (position 11); region excludes the newline
    (helixel-forward-WORD-start)
    (should (= (point) 11))
    (should (= (- (region-end) (region-beginning)) 4))
    ;; From \n, jump to next WORD on next line
    (helixel-forward-WORD-start)
    (should (= (point) 12))
    (should (= (- (region-end) (region-beginning)) 1))
    ;; Then to the next WORD
    (helixel-forward-WORD-start)
    (should (= (point) 19))
    (should (= (- (region-end) (region-beginning)) 7))))

(ert-deftest helixel-test-forward-WORD-start-empty-lines ()
  "Test forward movement with empty lines.
When a WORD ends at end of line, stop at end of word (exclude newline)."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "first\n\n\nsecond")
    (goto-char 5) ; before end of first line ('t' of "first")
    (helixel-forward-WORD-start)
    ;; "first" ends at \n (pos 6); region is just "t" without \n
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 1))))

(ert-deftest helixel-test-forward-WORD-start-at-end-of-buffer ()
  "Test that forward movement at end of buffer wraps back to last WORD."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "test word")
    (goto-char (point-max))
    (helixel-forward-WORD-start)
    (should (= (point) 6)) ; jumps to start of last WORD
    (should (= (- (region-end) (region-beginning)) 4))))

(ert-deftest helixel-test-forward-WORD-start-mixed-separators ()
  "Test forward movement with mixed word separators."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "word1_part2-part3.part4 next")
    (goto-char 1)
    (helixel-forward-WORD-start)
    (should (= (point) 25))
    (should (= (- (region-end) (region-beginning)) 24))))

(ert-deftest helixel-test-forward-WORD-start-punctuation ()
  "Test forward movement with punctuation."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "Hello, world! How are you?")
    (goto-char 1)
    (helixel-forward-WORD-start)
    (should (= (point) 8))
    (should (= (- (region-end) (region-beginning)) 7))
    (helixel-forward-WORD-start)
    (should (= (point) 15))
    (should (= (- (region-end) (region-beginning)) 7))))

;;; Forward long word end tests

(ert-deftest helixel-test-forward-WORD-end-basic-movement ()
  "Test basic forward movement to word ends."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello world test")
    (goto-char 1)
    (helixel-forward-WORD-end)
    (should (= (point) 6)) ; end of "hello"
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-forward-WORD-end)
    (should (= (point) 12)) ; end of "world"
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-forward-WORD-end)
    (should (= (point) 17)) ; end of "test"
    (should (= (- (region-end) (region-beginning)) 5))))

(ert-deftest helixel-test-forward-WORD-end-hyphenated-words ()
  "Test forward movement to ends of hyphenated words (long words)."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "this test-string-example works")
    (goto-char 1)
    (helixel-forward-WORD-end)
    (should (= (point) 5)) ; end of "this"
    (should (= (- (region-end) (region-beginning)) 4))
    (helixel-forward-WORD-end)
    (should (= (point) 25)) ; end of "test-string-example"
    (should (= (- (region-end) (region-beginning)) 20))
    (helixel-forward-WORD-end)
    (should (= (point) 31)) ; end of "works"
    (should (= (- (region-end) (region-beginning)) 6))))

(ert-deftest helixel-test-forward-WORD-end-on-whitespace ()
  "Test that forward movement to word ends skips over whitespace."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "word next")
    (goto-char 5) ; on the first whitespace
    (helixel-forward-WORD-end)
    (should (= (point) 10)) ; end of "next"
    (should (= (- (region-end) (region-beginning)) 5))))

(ert-deftest helixel-test-forward-WORD-end-on-whitespaces ()
  "Test that forward movement to word ends skips over multiple whitespaces."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "word   \t  next")
    (goto-char 5) ; on the first whitespace
    (helixel-forward-WORD-end)
    (should (= (point) 15)) ; end of "next"
    (should (= (- (region-end) (region-beginning)) 10))))

(ert-deftest helixel-test-forward-WORD-end-multiple-lines ()
  "Test forward movement to word ends across multiple lines."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "first line\nsecond line\nthird")
    (goto-char 1) ; start of buffer
    (helixel-forward-WORD-end)
    (should (= (point) 6)) ; end of "first"
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-forward-WORD-end)
    (should (= (point) 11)) ; end of "line"
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-forward-WORD-end)
    (should (= (point) 18)) ; end of "second"
    (should (= (- (region-end) (region-beginning)) 7))))

(ert-deftest helixel-test-forward-WORD-end-empty-lines ()
  "Test forward movement to word ends with empty lines."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "first\n\n\nsecond")
    (goto-char 1)
    (helixel-forward-WORD-end)
    (should (= (point) 6)) ; end of "first"
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-forward-WORD-end)
    (should (= (point) 8)) ; newline after empty lines
    (should (= (- (region-end) (region-beginning)) 2))))

(ert-deftest helixel-test-forward-WORD-end-at-end-of-buffer ()
  "Test that forward movement to word end at end of buffer doesn't move."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "test word")
    (goto-char (point-max))
    (let ((initial-point (point)))
      (helixel-forward-WORD-end)
      (should (= (point) initial-point))
      (should (= (- (region-end) (region-beginning)) 0)))))

(ert-deftest helixel-test-forward-WORD-end-mixed-separators ()
  "Test forward movement to word ends with mixed word separators."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "word1_part2-part3.part4 next")
    (goto-char 1)
    (helixel-forward-WORD-end)
    (should (= (point) 24)) ; end of "word1_part2-part3.part4"
    (should (= (- (region-end) (region-beginning)) 23))
    (helixel-forward-WORD-end)
    (should (= (point) 29)) ; end of "next"
    (should (= (- (region-end) (region-beginning)) 5))))

(ert-deftest helixel-test-forward-WORD-end-punctuation ()
  "Test forward movement to word ends with punctuation."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "Hello, world! How are you?")
    (goto-char 1)
    (helixel-forward-WORD-end)
    (should (= (point) 7)) ; end of "Hello,"
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-forward-WORD-end)
    (should (= (point) 14)) ; end of "world!"
    (should (= (- (region-end) (region-beginning)) 7))
    (helixel-forward-WORD-end)
    (should (= (point) 18)) ; end of "How"
    (should (= (- (region-end) (region-beginning)) 4))))

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
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello world test")
    (goto-char (point-max))
    (helixel-backward-WORD)
    (should (= (point) 13)) ; start of "test"
    (should (= (- (region-end) (region-beginning)) 4))
    (helixel-backward-WORD)
    (should (= (point) 7)) ; start of "world"
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-backward-WORD)
    (should (= (point) 1)) ; start of "hello"
    (should (= (- (region-end) (region-beginning)) 6))))

(ert-deftest helixel-test-backward-WORD-hyphenated-words ()
  "Test backward movement with hyphenated words (long words)."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "this test-string-example works")
    (goto-char (point-max))
    (helixel-backward-WORD)
    (should (= (point) 26)) ; start of "works"
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-backward-WORD)
    (should (= (point) 6)) ; start of "test-string-example"
    (should (= (- (region-end) (region-beginning)) 20))))

(ert-deftest helixel-test-backward-WORD-on-whitespace ()
  "Test that backward movement skips over whitespace."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "word next")
    (goto-char 5) ; on whitespace
    (helixel-backward-WORD)
    (should (= (point) 1)) ; start of "word"
    (should (= (- (region-end) (region-beginning)) 4))))

(ert-deftest helixel-test-backward-WORD-on-whitespaces ()
  "Test that backward movement skips over whitespace."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "word   \t  next")
    (goto-char 10) ; on the last whitespace
    (helixel-backward-WORD)
    (should (= (point) 1)) ; start of "word"
    (should (= (- (region-end) (region-beginning)) 9))))

(ert-deftest helixel-test-backward-WORD-multiple-lines ()
  "Test backward movement across multiple lines."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "first line\nsecond line\nthird")
    (goto-char (point-max))
    (helixel-backward-WORD)
    (should (= (point) 24)) ; start of "third"
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-backward-WORD)
    (should (= (point) 19)) ; start of "line"
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-backward-WORD)
    (should (= (point) 12)))) ; start of "second"

(ert-deftest helixel-test-backward-WORD-empty-lines ()
  "Test backward movement with empty lines."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "first\n\n\nsecond")
    (goto-char (point-max))
    (helixel-backward-WORD)
    (should (= (point) 9)) ; start of "second"
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-backward-WORD)
    (should (= (point) 8)) ; empty line before "first"
    (should (= (- (region-end) (region-beginning)) 1))))

(ert-deftest helixel-test-backward-WORD-at-beginning-of-buffer ()
  "Test that backward movement at beginning of buffer doesn't move."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "test word")
    (goto-char 1)
    (let ((initial-point (point)))
      (helixel-backward-WORD)
      (should (= (point) initial-point))
      (should (= (- (region-end) (region-beginning)) 0)))))

(ert-deftest helixel-test-backward-WORD-mixed-separators ()
  "Test backward movement with mixed word separators."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "word1_part2-part3.part4 next")
    (goto-char (point-max))
    (helixel-backward-WORD)
    (should (= (point) 25)) ; start of "next"
    (should (= (- (region-end) (region-beginning)) 4))
    (helixel-backward-WORD)
    (should (= (point) 1)) ; start of "word1_part2-part3.part4"
    (should (= (- (region-end) (region-beginning)) 24))))

(ert-deftest helixel-test-backward-WORD-punctuation ()
  "Test backward movement with punctuation."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "Hello, world! How are you?")
    (goto-char (point-max))
    (helixel-backward-WORD)
    (should (= (point) 23)) ; start of "you?"
    (should (= (- (region-end) (region-beginning)) 4))
    (helixel-backward-WORD)
    (should (= (point) 19)) ; start of "are"
    (should (= (- (region-end) (region-beginning)) 4))))

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
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "   \t\n  ")
    (goto-char 1)
    (helixel-forward-WORD-start)
    (should (= (point) 8))
    (should (= (- (region-end) (region-beginning)) 7))))

(ert-deftest helixel-test-forward-WORD-end-only-whitespace ()
  "Test forward movement to word end in buffer with only whitespace."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "   \t\n  ")
    (goto-char 1)
    (helixel-forward-WORD-end)
    (should (= (point) 8)) ; end of buffer
    (should (= (- (region-end) (region-beginning)) 7))
    (helixel-forward-WORD-end)
    (should (= (point) 8)) ; stays at eob
    (should (= (- (region-end) (region-beginning)) 0))))

(ert-deftest helixel-test-backward-WORD-only-whitespace ()
  "Test backward movement in buffer with only whitespace."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "   \t\n  ")
    (goto-char (point-max))
    (helixel-backward-WORD)
    (should (= (point) 1))
    (should (= (- (region-end) (region-beginning)) 7))))

(ert-deftest helixel-test-forward-WORD-start-single-character ()
  "Test forward movement with single character words."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "a b c d")
    (goto-char 1)
    (helixel-forward-WORD-start)
    (should (= (point) 3))
    (should (= (- (region-end) (region-beginning)) 2))
    (helixel-forward-WORD-start)
    (should (= (point) 5))
    (should (= (- (region-end) (region-beginning)) 2))))

(ert-deftest helixel-test-forward-WORD-end-single-character ()
  "Test forward movement to word ends with single character words."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "a b c d")
    (goto-char 1)
    (helixel-forward-WORD-end)
    (should (= (point) 2)) ; end of "a"
    (should (= (- (region-end) (region-beginning)) 1))
    (helixel-forward-WORD-end)
    (should (= (point) 4)) ; end of "b"
    (should (= (- (region-end) (region-beginning)) 2))
    (helixel-forward-WORD-end)
    (should (= (point) 6)) ; end of "c"
    (should (= (- (region-end) (region-beginning)) 2))))

(ert-deftest helixel-test-backward-WORD-single-character ()
  "Test backward movement with single character words."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "a b c d")
    (goto-char (point-max))
    (helixel-backward-WORD)
    (should (= (point) 7)) ; start of "d"
    (should (= (- (region-end) (region-beginning)) 1))
    (helixel-backward-WORD)
    (should (= (point) 5)) ; start of "c"
    (should (= (- (region-end) (region-beginning)) 2))))

;;; Backward word end tests (v key)

(ert-deftest helixel-test-backward-word-end-basic ()
  "Test backward-word-end moves to end of previous word."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello world test")
    (goto-char (point-max))
    (helixel-backward-word-end)
    (should (= (point) 12)) ; cursor at region-beginning (*-end)
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-backward-word-end)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 6))))

(ert-deftest helixel-test-backward-word-end-mid-word ()
  "Test backward-word-end from middle of a word."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello world")
    (goto-char 3) ; on "l" of "hello"
    (helixel-backward-word-end)
    (should (= (point) 6)) ; cursor at previous word end (*-end)
    (should (= (- (region-end) (region-beginning)) 3))))

(ert-deftest helixel-test-backward-word-end-at-bob ()
  "Test backward-word-end at beginning of buffer."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1)
    (let ((initial-point (point)))
      (helixel-backward-word-end)
      (should (= (point) 6)) ; cursor at word end
      (should (= (- (region-end) (region-beginning)) 5)))))

;;; Backward WORD end tests

(ert-deftest helixel-test-backward-WORD-end-basic ()
  "Test backward-WORD-end moves to end of previous WORD."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello world test")
    (goto-char (point-max))
    (helixel-backward-WORD-end)
    (should (= (point) 12)) ; cursor at region-beginning (*-end)
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-backward-WORD-end)
    (should (= (point) 6))
    (should (= (- (region-end) (region-beginning)) 6))))

(ert-deftest helixel-test-backward-WORD-end-hyphenated ()
  "Test backward-WORD-end with hyphenated words."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "this test-string-example works")
    (goto-char (point-max))
    (helixel-backward-WORD-end)
    (should (= (point) 25))
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-backward-WORD-end)
    (should (= (point) 5))
    (should (= (- (region-end) (region-beginning)) 20))))

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
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "foo_bar baz-qux hello")
    (goto-char 1)
    (helixel-forward-symbol-start)
    (should (= (point) 9)) ; cursor at region-end (*-start)
    (should (= (- (region-end) (region-beginning)) 8))
    (helixel-forward-symbol-start)
    (should (= (point) 17))
    (should (= (- (region-end) (region-beginning)) 8))
    (helixel-forward-symbol-start)
    ;; Last symbol at eob: selects "hello" from point to end
    (should (= (point) 22))
    (should (= (- (region-end) (region-beginning)) 5))))

(ert-deftest helixel-test-forward-symbol-start-single ()
  "Test forward-symbol-start with a single symbol char.
On a single-char symbol at eob, w selects it."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x")
    (goto-char 1)
    (helixel-forward-symbol-start)
    (should (= (point) 2))
    (should (= (- (region-end) (region-beginning)) 1))))

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
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "foo_bar baz-qux hello")
    (goto-char 1)
    (helixel-forward-symbol-end)
    (should (= (point) 8)) ; cursor at region-end (*-end)
    (should (= (- (region-end) (region-beginning)) 7))
    (helixel-forward-symbol-end)
    (should (= (point) 16))
    (should (= (- (region-end) (region-beginning)) 8))
    (helixel-forward-symbol-end)
    (should (= (point) 22))
    (should (= (- (region-end) (region-beginning)) 6))))

(ert-deftest helixel-test-backward-symbol-start-basic ()
  "Test backward-symbol-start movement."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "foo_bar baz-qux hello")
    (goto-char (point-max))
    (helixel-backward-symbol-start)
    (should (= (point) 17)) ; cursor at region-beginning (*-start)
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-backward-symbol-start)
    (should (= (point) 9))
    (should (= (- (region-end) (region-beginning)) 8))))

(ert-deftest helixel-test-backward-symbol-start-at-bob ()
  "Test backward-symbol-start at beginning of buffer."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello world")
    (goto-char 1)
    (let ((initial-point (point)))
      (helixel-backward-symbol-start)
      (should (= (point) initial-point))
      (should (= (- (region-end) (region-beginning)) 0)))))

(ert-deftest helixel-test-backward-symbol-end-basic ()
  "Test backward-symbol-end movement."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "foo_bar baz-qux hello")
    (goto-char (point-max))
    (helixel-backward-symbol-end)
    (should (= (point) 16)) ; cursor at region-beginning (*-end)
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-backward-symbol-end)
    (should (= (point) 8))
    (should (= (- (region-end) (region-beginning)) 8))))

;; Find char

(ert-deftest helixel-test-find-next-char ()
  "Test finding next character and selecting from current position to it."
  (with-temp-buffer
    (insert "first second third")
    (goto-char 1)
    (helixel-find-next-char ?d)
    (should (eql (point) 13))
    (should (eql (- (region-end) (region-beginning)) 12))))

(ert-deftest helixel-test-find-next-char-two-line ()
  "Test finding next character across multiple lines and selecting to it."
  (with-temp-buffer
    (insert "first\nsecond\nthird")
    (goto-char 1)
    (helixel-find-next-char ?d)
    (should (eql (point) 13))
    (should (eql (- (region-end) (region-beginning)) 12))))

(ert-deftest helixel-test-find-till-char ()
  "Test finding till character and selecting from current position to before it."
  (with-temp-buffer
    (insert "first second third")
    (goto-char 1)
    (helixel-find-till-char ?d)
    (should (eql (point) 12))
    (should (eql (- (region-end) (region-beginning)) 11))))

(ert-deftest helixel-test-find-till-char-two-line ()
  "Test finding till character across multiple lines and selecting to before it."
  (with-temp-buffer
    (insert "first\nsecond\nthird")
    (goto-char 1)
    (helixel-find-till-char ?d)
    (should (eql (point) 12))
    (should (eql (- (region-end) (region-beginning)) 11))))

(ert-deftest helixel-test-find-till-char-repeat ()
  "Test repeating find till character skips past adjacent char."
  (with-temp-buffer
    (insert "first second third")
    (goto-char 1)
    (helixel-find-till-char ?d)
    (should (eql (point) 12))
    (helixel-find-repeat)
    (should (eql (point) 18))
    (should (eql (- (region-end) (region-beginning)) 6))))

(ert-deftest helixel-test-find-prev-till-char-repeat ()
  "Test repeating previous till character find skips past adjacent char."
  (with-temp-buffer
    (insert "first second third")
    (goto-char (point-max))
    (helixel-find-prev-till-char ?s)
    (should (eql (point) 8))
    (helixel-find-repeat)
    (should (eql (point) 5))))

(ert-deftest helixel-test-empty-find-repeat ()
  "Test find repeat when nothing to repeat."
  (with-temp-buffer
    (insert "first second third")
    (goto-char 1)
    (helixel-find-repeat)
    (should (eql (point) 1))))

(ert-deftest helixel-test-find-direction-n ()
  "Test f + n repeats find forward."
  (with-temp-buffer
    (insert "axb axb axb")
    (goto-char 1)
    (helixel-find-next-char ?b)
    (should (eql (point) 4))       ; search-forward lands after match
    (helixel-search-repeat-next)
    (should (eql (point) 8))))     ; next b

(ert-deftest helixel-test-find-direction-N ()
  "Test f + N toggles direction and repeats backward."
  (with-temp-buffer
    (insert "axb axb axb")
    (goto-char 5)
    (helixel-find-next-char ?b)
    (should (eql (point) 8))       ; after second b
    (helixel-search-repeat-reverse)
    (should (eq (helixel--live-cat-get :dir) 'backward))
    (should (< (point) 8))))

;;; helixel-test-move.el ends here
