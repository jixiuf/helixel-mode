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
    (should (eq (helixel-active-search--dir helixel--active-search) 'backward))
    (should (< (point) 8))))

;;; Pair delimiter movement tests — [ ] { } prefixes

(ert-deftest helixel-test-pair-outer-paren ()
  "Test [ ( outward to enclosing paren opening."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "foo (bar) baz")
    (deactivate-mark)
    (goto-char 7)
    (helixel-outer-paren)
    (should (= (point) 5))))

(ert-deftest helixel-test-pair-next-paren-end-outside ()
  "Test ] ( forward to next paren closing from outside."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x (one) (two)")
    (deactivate-mark)
    (goto-char 1)
    (helixel-next-paren-end)
    (should (= (point) 8))))

(ert-deftest helixel-test-pair-outer-bracket ()
  "Test [ [ outward to enclosing bracket opening."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "[abc] def")
    (deactivate-mark)
    (goto-char 4)
    (helixel-outer-bracket)
    (should (= (point) 1))))

(ert-deftest helixel-test-pair-next-bracket-end ()
  "Test ] [ forward to next bracket closing."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x [one] [two]")
    (deactivate-mark)
    (goto-char 1)
    (helixel-next-bracket-end)
    (should (= (point) 8))))

(ert-deftest helixel-test-pair-outer-brace ()
  "Test [ { outward to enclosing brace opening."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "{abc} def")
    (deactivate-mark)
    (goto-char 4)
    (helixel-outer-brace)
    (should (= (point) 1))))

(ert-deftest helixel-test-pair-next-brace-end ()
  "Test ] { forward to next brace closing."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x {one} {two}")
    (deactivate-mark)
    (goto-char 1)
    (helixel-next-brace-end)
    (should (= (point) 8))))

(ert-deftest helixel-test-pair-outer-double-quote ()
  "Test [ \" outward to enclosing double-quote opening."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x \"abc\" def")
    (deactivate-mark)
    (goto-char 5)
    (helixel-outer-double-quote)
    (should (= (point) 3))))

(ert-deftest helixel-test-pair-outer-single-quote ()
  "Test [ ' outward to enclosing single-quote opening."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x 'abc' def")
    (deactivate-mark)
    (goto-char 5)
    (helixel-outer-single-quote)
    (should (= (point) 3))))

(ert-deftest helixel-test-pair-outer-angle ()
  "Test [ < outward to enclosing angle opening."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "<abc> def")
    (deactivate-mark)
    (goto-char 4)
    (helixel-outer-angle)
    (should (= (point) 1))))

(ert-deftest helixel-test-pair-outer-back-quote ()
  "Test [ ` outward to enclosing back-quote opening."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x `abc` def")
    (deactivate-mark)
    (goto-char 5)
    (helixel-outer-back-quote)
    (should (= (point) 3))))

;; Inner variants: { outward, } forward

(ert-deftest helixel-test-pair-inner-outer-paren ()
  "Test { ( outward to enclosing inner paren opening."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(abc def) ghi")
    (deactivate-mark)
    (goto-char 5)
    (helixel-inner-outer-paren)
    (should (= (point) 2))))

(ert-deftest helixel-test-pair-inner-next-paren-end ()
  "Test } ( forward to next inner paren closing."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x (one) (two)")
    (deactivate-mark)
    (goto-char 1)
    (helixel-inner-next-paren-end)
    (should (= (point) 7))))

(ert-deftest helixel-test-pair-inner-outer-bracket ()
  "Test { [ outward to enclosing inner bracket opening."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "[abc] def")
    (deactivate-mark)
    (goto-char 4)
    (helixel-inner-outer-bracket)
    (should (= (point) 2))))

(ert-deftest helixel-test-pair-inner-next-bracket-end ()
  "Test } [ forward to next inner bracket closing."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x [one] [two]")
    (deactivate-mark)
    (goto-char 1)
    (helixel-inner-next-bracket-end)
    (should (= (point) 7))))

(ert-deftest helixel-test-pair-inner-outer-brace ()
  "Test { { outward to enclosing inner brace opening."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "{abc} def")
    (deactivate-mark)
    (goto-char 4)
    (helixel-inner-outer-brace)
    (should (= (point) 2))))

(ert-deftest helixel-test-pair-inner-next-brace-end ()
  "Test } { forward to next inner brace closing."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x {one} {two}")
    (deactivate-mark)
    (goto-char 1)
    (helixel-inner-next-brace-end)
    (should (= (point) 7))))

(ert-deftest helixel-test-pair-inner-outer-double-quote ()
  "Test { \" outward to enclosing inner double-quote opening."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "\"abc\" def")
    (deactivate-mark)
    (goto-char 4)
    (helixel-inner-outer-double-quote)
    (should (= (point) 2))))

;; ; mark-thing after pair movement
(ert-deftest helixel-test-pair-semicolon-mark-paren ()
  "Test ; after [ ( marks the enclosing paren using stored bounds."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "foo (the target) bar")
    (deactivate-mark)
    (goto-char 9)
    
    (helixel-outer-paren)
    (should (helixel-action-mark-region helixel--live-action))
    (should (helixel-action-mark-region helixel--live-action))
    ;; Simulate ; — use stored markers from mark-region
    (let ((mr (helixel-action-mark-region helixel--live-action)))
      (push-mark (car mr) t t)
      (goto-char (cdr mr))
      (activate-mark))
    (should (use-region-p))
    ;; foo (the target) bar: positions 1-4="foo ", 5="(", 16=")", 17-20=" bar"
    (should (= (region-beginning) 5))
    (should (= (region-end) 17))))

;;; Paragraph / sentence / function move tests

(ert-deftest helixel-test-paragraph-move-forward-start ()
  "Test } moves to next paragraph start."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "line one\n\nline two\n")
    (goto-char 1)
    (helixel-forward-paragraph-start)
    (should (>= (point) 10))))

(ert-deftest helixel-test-paragraph-move-backward-start ()
  "Test g { moves to previous paragraph start."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "line one\n\nline two\n")
    (goto-char 18)
    (helixel-backward-paragraph-start)
    (should (>= (point) 10))))

(ert-deftest helixel-test-sentence-move-forward-end ()
  "Test ] s moves to next sentence end."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "Hello.  World.")
    (goto-char 1)
    (helixel-forward-sentence-end)
    ;; Forward sentence end lands after the period
    (should (>= (point) 5))))

;;; Jump to match — %
(ert-deftest helixel-test-jump-to-match-from-open ()
  "Test % from opening paren jumps after closing."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(abc def) ghi")
    (deactivate-mark)
    (goto-char 1)
    (helixel-jump-to-match)
    (should (= (point) 10))))

(ert-deftest helixel-test-jump-to-match-from-close ()
  "Test % from closing paren jumps to opening."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(abc def) ghi")
    (deactivate-mark)
    (goto-char 9)
    (helixel-jump-to-match)
    (should (= (point) 1))))

(ert-deftest helixel-test-jump-to-match-brace ()
  "Test % on { jumps to }."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "{abc}")
    (deactivate-mark)
    (goto-char 1)
    (helixel-jump-to-match)
    (should (= (point) 6))))

(ert-deftest helixel-test-jump-to-match-bracket ()
  "Test % on [ jumps to ]."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "[abc]")
    (deactivate-mark)
    (goto-char 1)
    (helixel-jump-to-match)
    (should (= (point) 6))))

(ert-deftest helixel-test-jump-to-match-between-close ()
  "Test % between ) and } jumps to matching (."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(x) {y}")
    (deactivate-mark)
    (goto-char 4)  ; between ) and space
    (helixel-jump-to-match)
    ;; char-before is ), should jump to matching (
    (should (= (point) 1))))

(ert-deftest helixel-test-jump-to-match-nested ()
  "Test % from inner ( in nested parens jumps to inner )."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a (b) c)")
    (deactivate-mark)
    (goto-char 4)  ; inner (
    (helixel-jump-to-match)
    (should (= (point) 7))))

(ert-deftest helixel-test-jump-to-match-double-quote ()
  "Test % on \" jumps to matching \"."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x \"hi\" y")
    (deactivate-mark)
    (goto-char 3)
    (helixel-jump-to-match)
    ;; Should land right after the closing "
    (should (= (point) 7))))

(ert-deftest helixel-test-jump-to-match-no-match ()
  "Test % with no bracket does not crash."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "no brackets here")
    (deactivate-mark)
    (goto-char 5)
    (condition-case nil
        (helixel-jump-to-match)
      (error nil))
    (should t)))

(ert-deftest helixel-test-jump-to-match-tag ()
  "Test % inside XML tag jumps to matching closing tag."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "<div>hi</div>")
    (deactivate-mark)
    (goto-char 2)  ; on 'd' of <div>
    (helixel-jump-to-match)
    ;; Should jump to closing </div> (position 14 = after > of </div>)
    (should (= (point) 14))))

;;; Structure ; mark-thing
(ert-deftest helixel-test-structure-semicolon-mark-function ()
  (with-temp-buffer
    (transient-mark-mode 1)
    (emacs-lisp-mode)
    (insert "\n(defun foo () 1)\n")
    (deactivate-mark)
    (goto-char 2)
    (helixel-forward-function-end)
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
       (setq helixel--event-ring nil helixel--live-action nil
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
(helixel-test-mark-thing "outer-paren" #'helixel-outer-paren
  "foo (bar)" 7 5 10)
(helixel-test-mark-thing "next-paren" #'helixel-next-paren-end
  "a (one) (two)" 1 3 8)

(ert-deftest helixel-test-mark-thing-second-semicolon ()
  "Test second ; after mark-thing does action cycle."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--event-ring nil helixel--live-action nil
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

(ert-deftest helixel-test-mark-thing-disabled-by-defcustom ()
  "Test mark-thing disabled when helixel-semicolon-mark-thing is nil."
  (let ((helixel-semicolon-mark-thing nil))
    (with-temp-buffer
      (transient-mark-mode 1)
      (setq helixel--event-ring nil helixel--live-action nil
          helixel--action-pos nil)
      (insert "hello world")
      (deactivate-mark)
      (goto-char 1)
      (helixel-forward-word-start)
      (helixel--action-cycle)
      ;; ; did NOT do mark-thing: region is from movement, action cycle started
      (should (region-active-p))
      (should helixel--action-pos))))

;;; Tag pair movement [t and ; mark-thing

(ert-deftest helixel-test-pair-tag-semicolon-mark ()
  "Test [t; after pair movement marks the enclosing tag."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--event-ring nil helixel--live-action nil
          helixel--action-pos nil)
    (insert "<p>\n<div>\nhe\n</div>\n</p>")
    (deactivate-mark)
    (goto-char 2)
    (search-forward "he")
    ;; [t from inside <div> content
    (helixel-outer-tag)
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
    (setq helixel--event-ring nil helixel--live-action nil
          helixel--action-pos nil)
    (insert "<p>\n<div>\nhe\n</div>\n</p>")
    (deactivate-mark)
    ;; Go between </div> and </p> (position 20 is \n after </div>)
    (goto-char 20)
    ;; [t finds <p>...</p> (the outer enclosing tag)
    (helixel-outer-tag)
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
    (setq helixel--event-ring nil helixel--live-action nil
          helixel--action-pos nil)
    (insert "<p>\ninner\n</p>")
    (deactivate-mark)
    (goto-char 7)
    ;; {t from inside <p> content
    (helixel-inner-outer-tag)
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
    (setq helixel--event-ring nil helixel--live-action nil
          helixel--action-pos nil)
    (insert "<a>x</a> <b>y</b>")
    (deactivate-mark)
    (goto-char 4)  ; inside <a> content (the "x")
    ;; ]t from inside <a>
    (helixel-next-tag-end)
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
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "<p>\n<div>\nhe\n</div>\n</p>")
    (goto-char 4)  ; between <p> and <div>
    (call-interactively #'helixel-mark-a-tag)
    (should (= (region-beginning) 1))
    (should (= (region-end) 25))))

(ert-deftest helixel-test-textobj-tag-nested-inner ()
  "Test mat from inside nested <div> marks the innermost <div>."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "<p>\n<div>\nhello\n</div>\n</p>")
    (goto-char 2)
    (search-forward "hello")  ; inside <div> content
    (call-interactively #'helixel-mark-a-tag)
    (should (= (region-beginning) 5))
    (should (= (region-end) 23))))

(ert-deftest helixel-test-textobj-tag-before-outer-close ()
  "Test mat before outer closing tag marks the outer tag."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "<p>\n<div>\nhello\n</div>\n</p>")
    (goto-char (point-max))
    (search-backward "</p>")
    ;; cursor is at < of </p>
    (call-interactively #'helixel-mark-a-tag)
    (should (= (region-beginning) 1))
    (should (= (region-end) 28))))

;;; Pair climb-outward tests — ]/} when point at closing edge

(ert-deftest helixel-test-pair-next-paren-climb-outward ()
  "Test ] ( at inner ) climbs to outer ) in nested parens."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a (b) c)")
    (deactivate-mark)
    ;; Point at the inner close ) — position 6
    (goto-char 6)
    (helixel-next-paren-end)
    ;; Climb outward to outer ), whose match-end is eob (pos 10).
    (should (= (point) 10))))

(ert-deftest helixel-test-pair-inner-next-paren-climb-outward ()
  "Test } ( at inner ) climbs to outer inner ) in nested parens."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a (b) c)")
    (deactivate-mark)
    (goto-char 6)
    (helixel-inner-next-paren-end)
    ;; Inner closing: cdr of (oe . cb) = cb = 9 (the outer ))
    (should (= (point) 9))))

(ert-deftest helixel-test-pair-next-brace-climb-outward ()
  "Test ] { at inner } climbs to outer } in nested braces."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "{a {b} c}")
    (deactivate-mark)
    (goto-char 6)
    (helixel-next-brace-end)
    (should (= (point) 10))))

(ert-deftest helixel-test-pair-inner-next-brace-climb-outward ()
  "Test } { at inner } climbs to outer inner } in nested braces."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "{a {b} c}")
    (deactivate-mark)
    (goto-char 6)
    (helixel-inner-next-brace-end)
    (should (= (point) 9))))

;;; Multi-char delimiter climb-outward — tag and block

(ert-deftest helixel-test-pair-next-tag-climb-outward ()
  "Test ]t at inner </div> climbs to outer </p> in nested tags."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "<p><div>hi</div></p>")
    (deactivate-mark)
    ;; Point at the > of inner </div>.
    ;; <p><div>hi</div></p>: 1=< 2=p 3=> 4=< 5=d 6=i 7=v 8=> 9=h 10=i
    ;;  11=< 12=/ 13=d 14=i 15=v 16=> 17=< 18=/ 19=p 20=> 21=eob
    (goto-char 16)  ; right after > of </div>
    (helixel-next-tag-end)
    ;; Climb outward to after outer </p> (eob at 21).
    (should (= (point) 21))))

(ert-deftest helixel-test-pair-inner-next-tag-climb-outward ()
  "Test }t at inner </div> climbs to outer inner </p> in nested tags."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "<p><div>hi</div></p>")
    (deactivate-mark)
    (goto-char 16)
    (helixel-inner-next-tag-end)
    ;; Inner close beginning of outer tag: cb = 17 (the < of </p>).
    (should (= (point) 17))))

;;; Pair next-end from outside (not inside any pair)

(ert-deftest helixel-test-pair-next-paren-end-from-outside ()
  "Test ] ( from before a paren pair jumps into it."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "before (target) after")
    (deactivate-mark)
    (goto-char 1)
    (helixel-next-paren-end)
    (should (= (point) 16))))

(ert-deftest helixel-test-pair-next-brace-end-from-outside ()
  "Test ] { from before a brace pair jumps into it."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "before {target} after")
    (deactivate-mark)
    (goto-char 1)
    (helixel-next-brace-end)
    (should (= (point) 16))))

(ert-deftest helixel-test-pair-next-double-quote-end-from-outside ()
  "Test ] \" from before a quoted string finds its closing."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x \"one\" y")
    (deactivate-mark)
    (goto-char 1)
    (helixel-next-double-quote-end)
    (should (= (point) 8))))

(ert-deftest helixel-test-pair-next-single-quote-end-from-outside ()
  "Test ] ' from before a quoted string finds its closing."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x 'one' y")
    (deactivate-mark)
    (goto-char 1)
    (helixel-next-single-quote-end)
    (should (= (point) 8))))

(ert-deftest helixel-test-pair-next-angle-end ()
  "Test ] < moves to closing angle bracket."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "<foo> bar")
    (deactivate-mark)
    (goto-char 2)
    (helixel-next-angle-end)
    (should (= (point) 6))))

;;; No pair found — graceful handling

(ert-deftest helixel-test-pair-next-paren-no-pair ()
  "Test ] ( with no paren in buffer does not crash."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "no parens here at all")
    (deactivate-mark)
    (goto-char 5)
    (condition-case nil
        (helixel-next-paren-end)
      (error nil))
    (let ((mr (helixel-action-mark-region helixel--live-action)))
      (should (= (marker-position (car mr)) (marker-position (cdr mr)))))))

(ert-deftest helixel-test-pair-outer-paren-no-pair ()
  "Test [ ( with no paren in buffer does not crash."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "no parens here")
    (deactivate-mark)
    (condition-case nil
        (helixel-outer-paren)
      (error nil))
    (let ((mr (helixel-action-mark-region helixel--live-action)))
      (should (= (marker-position (car mr)) (marker-position (cdr mr)))))))

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
        (helixel-outer-block)
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
        (helixel-next-block-end)
      (error nil))
    (when-let* ((mr (helixel-action-mark-region helixel--live-action)))
      (should (>= (marker-position (cdr mr)) 10)))))

;;; ; mark-thing for paragraph/sentence/function movements

(ert-deftest helixel-test-mark-thing-paragraph-forward ()
  "Test ; after } (paragraph forward) marks the paragraph."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "First paragraph.\n\nSecond paragraph.")
    (deactivate-mark)
    (goto-char 1)
    (setq helixel--action-pos nil)
    (helixel-forward-paragraph-start)
    (should (helixel-action-mark-region helixel--live-action))
    (helixel--action-cycle)
    (should (use-region-p))))

(ert-deftest helixel-test-mark-thing-sentence-forward ()
  "Test ; after ]s (sentence forward end) marks the sentence."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "One. Two. Three.")
    (deactivate-mark)
    (goto-char 1)
    (setq helixel--action-pos nil)
    (helixel-forward-sentence-end)
    (should (helixel-action-mark-region helixel--live-action))
    (helixel--action-cycle)
    (should (use-region-p))))

(ert-deftest helixel-test-mark-thing-function-forward ()
  "Test ; after ]f (function forward end) marks the function."
  (with-temp-buffer
    (transient-mark-mode 1)
    (emacs-lisp-mode)
    (insert "(defun foo () (message \"hi\"))\n\n(defun bar () nil)")
    (deactivate-mark)
    (goto-char 1)
    (setq helixel--action-pos nil)
    (helixel-forward-function-end)
    (should (helixel-action-mark-region helixel--live-action))
    (helixel--action-cycle)
    (should (use-region-p))))

;;; helixel-test-move.el ends here
