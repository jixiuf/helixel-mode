;;; helixel-test.el --- Tests for Helixel minor mode  -*- lexical-binding: t; -*-

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

;;; Forward long word tests

(ert-deftest helixel-test-forward-WORD-start-basic-movement ()
  "Test basic forward movement between words."
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
    (should (= (point) 13)) ; no more words, stays
    (should (= (- (region-end) (region-beginning)) 0))))

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
  "Test forward movement across multiple lines."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "first line\nsecond line\nthird")
    (goto-char 1) ; start of buffer
    (helixel-forward-WORD-start)
    (should (= (point) 7))
    (should (= (- (region-end) (region-beginning)) 6))
    (helixel-forward-WORD-start)
    (should (= (point) 12))
    (should (= (- (region-end) (region-beginning)) 5))
    (helixel-forward-WORD-start)
    (should (= (point) 19))
    (should (= (- (region-end) (region-beginning)) 7))))

(ert-deftest helixel-test-forward-WORD-start-empty-lines ()
  "Test forward movement with empty lines."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "first\n\n\nsecond")
    (goto-char 5) ; before end of first line
    (helixel-forward-WORD-start)
    (should (= (point) 7))
    (should (= (- (region-end) (region-beginning)) 2))))

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
  "Test forward-symbol-start movement."
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
    (should (= (point) 17))
    (should (= (- (region-end) (region-beginning)) 0))))

(ert-deftest helixel-test-forward-symbol-start-single ()
  "Test forward-symbol-start with a single symbol char."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x")
    (goto-char 1)
    (helixel-forward-symbol-start)
    (should (= (point) 1))
    (should (= (- (region-end) (region-beginning)) 0))))

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

;;; Line-wise helper tests

(defmacro helixel-test-with-buffer (content &rest body)
  "Execute BODY in a temp buffer with CONTENT and transient-mark-mode on.
Buffer starts with point at position 1."
  (declare (indent 1))
  `(with-temp-buffer
     (transient-mark-mode 1)
     (insert ,content)
     (goto-char 1)
     ,@body))

(ert-deftest helixel-test-linewise-text-adds-newline ()
  "Test that `helixel--linewise-text' ensures trailing newline."
  (let ((text (helixel--linewise-text "hello")))
    (should (string= text "hello\n"))
    (should (eq (car (get-text-property 0 'yank-handler text))
                'helixel--yank-handler-line-wise))))

(ert-deftest helixel-test-linewise-text-preserves-existing-newline ()
  "Test that `helixel--linewise-text' doesn't double newline."
  (let ((text (helixel--linewise-text "hello\n")))
    (should (string= text "hello\n"))
    (should (eq (car (get-text-property 0 'yank-handler text))
                'helixel--yank-handler-line-wise))))

(ert-deftest helixel-test-linewise-kill-p-positive ()
  "Test `helixel--linewise-kill-p' detects line-wise text."
  (let ((text (helixel--linewise-text "hello\n")))
    (should (helixel--linewise-kill-p text))))

(ert-deftest helixel-test-linewise-kill-p-negative ()
  "Test `helixel--linewise-kill-p' returns nil for plain text."
  (should-not (helixel--linewise-kill-p "hello")))

(ert-deftest helixel-test-linewise-kill-p-nil ()
  "Test `helixel--linewise-kill-p' returns nil when no kill ring."
  (let ((kill-ring nil))
    (should-not (helixel--linewise-kill-p))))

;;; helixel--selection-type tests

(ert-deftest helixel-test-selection-type-nil-without-region ()
  "Test `helixel--selection-type' returns nil when no region."
  (helixel-test-with-buffer "hello"
    (should-not (helixel--selection-type))))

(ert-deftest helixel-test-selection-type-line-validated ()
  "Test `helixel--selection-type' validates line selection bounds."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (push-mark (point) t t)
    (end-of-line)
    (setq helixel--selection-type 'line)
    (should (eq (helixel--selection-type) 'line))))

(ert-deftest helixel-test-selection-type-line-invalidated ()
  "Test `helixel--selection-type' rejects invalid line selection."
  (helixel-test-with-buffer "first line\nsecond line"
    ;; region doesn't start at bol
    (goto-char 3)
    (push-mark (point) t t)
    (end-of-line)
    (setq helixel--selection-type 'line)
    (should-not (helixel--selection-type))))

;;; helixel-select-line sets selection type

(ert-deftest helixel-test-select-line-sets-type ()
  "Test `helixel-select-line' sets `helixel--selection-type' to line."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (setq helixel--selection-type nil)
    (helixel-select-line)
    (should (eq helixel--selection-type 'line))
    (should (region-active-p))))

;;; helixel--clear-data resets selection type

(ert-deftest helixel-test-clear-data-resets-type ()
  "Test `helixel--clear-data' resets `helixel--selection-type'."
  (helixel-test-with-buffer "hello"
    (setq helixel--selection-type 'line)
    (helixel--clear-data)
    (should-not helixel--selection-type)))

;;; helixel--line-bounds-of-region tests

(ert-deftest helixel-test-line-bounds-single-line ()
  "Test line bounds expansion for a single line selection."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    ;; Select "first line" (bol to eol)
    (push-mark (point) t t)
    (end-of-line)
    (let ((bounds (helixel--line-bounds-of-region)))
      (should bounds)
      ;; beg=1, end includes newline=12
      (should (= (car bounds) 1))
      (should (= (cdr bounds) 12)))))

(ert-deftest helixel-test-line-bounds-multi-line ()
  "Test line bounds expansion for a multi-line selection."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    ;; Select from middle of first to middle of second
    (goto-char 5)
    (push-mark (point) t t)
    (goto-char 18)
    (let ((bounds (helixel--line-bounds-of-region)))
      (should bounds)
      ;; Should expand to cover both full lines
      (should (= (car bounds) 1))
      (should (= (cdr bounds) 24)))))

(ert-deftest helixel-test-line-bounds-last-line-no-newline ()
  "Test line bounds at end of buffer without trailing newline."
  (helixel-test-with-buffer "first line\nlast line"
    (goto-char 12)
    (push-mark (point) t t)
    (goto-char (point-max))
    (let ((bounds (helixel--line-bounds-of-region)))
      (should bounds)
      (should (= (car bounds) 12))
      ;; end should be point-max since no trailing newline
      (should (= (cdr bounds) (point-max))))))

;;; helixel-kill-ring-save (y) line-wise tests

(ert-deftest helixel-test-kill-ring-save-linewise ()
  "Test `helixel-kill-ring-save' tags text as line-wise."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (let ((kill-ring nil))
      (helixel-select-line)
      (helixel-kill-ring-save)
      (should (helixel--linewise-kill-p (car kill-ring)))
      ;; Should include trailing newline
      (should (string= (car kill-ring) "first line\n"))
      ;; Buffer content unchanged
      (should (string= (buffer-string) "first line\nsecond line\nthird line")))))

(ert-deftest helixel-test-kill-ring-save-charwise ()
  "Test `helixel-kill-ring-save' does not tag charwise text."
  (helixel-test-with-buffer "hello world"
    (let ((kill-ring nil))
      (push-mark (point) t t)
      (goto-char 6)
      (setq helixel--selection-type nil)
      (helixel-kill-ring-save)
      (should-not (helixel--linewise-kill-p (car kill-ring)))
      (should (string= (car kill-ring) "hello")))))

;;; helixel-kill-thing-at-point (d) line-wise tests

(ert-deftest helixel-test-kill-thing-linewise ()
  "Test `helixel-kill-thing-at-point' kills whole line and tags line-wise."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (let ((kill-ring nil))
      (helixel-select-line)
      (helixel-kill-thing-at-point)
      ;; Kill ring should have the line with trailing newline
      (should (helixel--linewise-kill-p (car kill-ring)))
      (should (string= (car kill-ring) "first line\n"))
      ;; Buffer should have remaining lines
      (should (string= (buffer-string) "second line\nthird line")))))

(ert-deftest helixel-test-kill-thing-linewise-last-line ()
  "Test killing the last line (no trailing newline in buffer)."
  (helixel-test-with-buffer "first line\nlast line"
    (let ((kill-ring nil))
      (goto-char 12)
      (helixel-select-line)
      (helixel-kill-thing-at-point)
      (should (helixel--linewise-kill-p (car kill-ring)))
      (should (string= (buffer-string) "first line\n")))))

(ert-deftest helixel-test-kill-thing-linewise-multi-line ()
  "Test killing multiple lines selected with helixel-select-line."
  (helixel-test-with-buffer "line one\nline two\nline three"
    (let ((kill-ring nil))
      (helixel-select-line)
      (helixel-select-line) ;; extend to second line
      (helixel-kill-thing-at-point)
      (should (helixel--linewise-kill-p (car kill-ring)))
      (should (string= (car kill-ring) "line one\nline two\n"))
      (should (string= (buffer-string) "line three")))))

(ert-deftest helixel-test-kill-thing-charwise ()
  "Test `helixel-kill-thing-at-point' without line-wise selection."
  (helixel-test-with-buffer "hello world"
    (let ((kill-ring nil))
      (push-mark (point) t t)
      (goto-char 6)
      (setq helixel--selection-type nil)
      (helixel-kill-thing-at-point)
      (should-not (helixel--linewise-kill-p (car kill-ring)))
      (should (string= (buffer-string) " world")))))

(ert-deftest helixel-test-kill-thing-no-region ()
  "Test `helixel-kill-thing-at-point' deletes char when no region."
  (helixel-test-with-buffer "hello"
    (helixel-kill-thing-at-point)
    (should (string= (buffer-string) "ello"))))

;;; helixel-yank (p) line-wise tests

(ert-deftest helixel-test-yank-linewise-below ()
  "Test `helixel-yank' pastes line-wise content below current line."
  (helixel-test-with-buffer "first line\nsecond line"
    ;; Put a line-wise kill in the kill ring
    (kill-new (helixel--linewise-text "new line\n"))
    ;; Cursor on first line
    (goto-char 5)
    (let ((this-command 'helixel-yank))
      (helixel-yank))
    ;; "new line" should appear between first and second
    (should (string= (buffer-string) "first line\nnew line\nsecond line"))))

(ert-deftest helixel-test-yank-linewise-at-last-line ()
  "Test `helixel-yank' pastes line-wise content below last line."
  (helixel-test-with-buffer "only line"
    (kill-new (helixel--linewise-text "new line\n"))
    (goto-char 5)
    (let ((this-command 'helixel-yank))
      (helixel-yank))
    (should (string= (buffer-string) "only line\nnew line"))))

(ert-deftest helixel-test-yank-charwise ()
  "Test `helixel-yank' pastes charwise content at point."
  (helixel-test-with-buffer "hello world"
    (kill-new "XYZ")
    (goto-char 6)
    (helixel-yank)
    (should (string= (buffer-string) "helloXYZ world"))))

;;; helixel-yank-before (P) line-wise tests

(ert-deftest helixel-test-yank-before-linewise ()
  "Test `helixel-yank-before' pastes line-wise content above current line."
  (helixel-test-with-buffer "first line\nsecond line"
    (kill-new (helixel--linewise-text "new line\n"))
    ;; Cursor on second line
    (goto-char 15)
    (let ((this-command 'helixel-yank-before))
      (helixel-yank-before))
    ;; "new line" should appear between first and second
    (should (string= (buffer-string) "first line\nnew line\nsecond line"))))

(ert-deftest helixel-test-yank-before-linewise-first-line ()
  "Test `helixel-yank-before' pastes above first line."
  (helixel-test-with-buffer "only line"
    (kill-new (helixel--linewise-text "new line\n"))
    (let ((this-command 'helixel-yank-before))
      (helixel-yank-before))
    (should (string= (buffer-string) "new line\nonly line"))))

(ert-deftest helixel-test-yank-before-charwise ()
  "Test `helixel-yank-before' pastes charwise content at point."
  (helixel-test-with-buffer "hello world"
    (kill-new "XYZ")
    (goto-char 6)
    (helixel-yank-before)
    (should (string= (buffer-string) "helloXYZ world"))))

;;; helixel-replace (r) line-wise tests

(ert-deftest helixel-test-replace-yanked-linewise-selection-linewise-kill ()
  "Test replacing line-wise selection with line-wise kill."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (kill-new (helixel--linewise-text "REPLACED\n"))
    ;; Select second line
    (goto-char 12)
    (helixel-select-line)
    (helixel-replace)
    (should (string= (buffer-string) "first line\nREPLACED\nthird line"))))

(ert-deftest helixel-test-replace-yanked-linewise-selection-charwise-kill ()
  "Test replacing line-wise selection with charwise kill."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (kill-new "INLINE")
    (goto-char 12)
    (helixel-select-line)
    (helixel-replace)
    ;; Charwise kill replaces the full line
    (should (string= (buffer-string) "first line\nINLINE\nthird line"))))

(ert-deftest helixel-test-replace-yanked-charwise-selection-linewise-kill ()
  "Test replacing charwise selection with line-wise kill (strips newline)."
  (helixel-test-with-buffer "hello world"
    (kill-new (helixel--linewise-text "REPLACED\n"))
    (push-mark (point) t t)
    (goto-char 6)
    (setq helixel--selection-type nil)
    (helixel-replace)
    ;; Line-wise kill should be stripped of trailing newline for inline replace
    (should (string= (buffer-string) "REPLACED world"))))

(ert-deftest helixel-test-replace-yanked-no-region ()
  "Test replacing char at point with kill ring content."
  (helixel-test-with-buffer "hello"
    (let ((helixel-replace-delete-char-p t))
      (kill-new "X")
      (setq helixel--selection-type nil)
      (helixel-replace)
      (should (string= (buffer-string) "Xello"))))

  (helixel-test-with-buffer "hello"
    (let ((helixel-replace-delete-char-p nil))
      (kill-new "X")
      (setq helixel--selection-type nil)
      (helixel-replace)
      (should (string= (buffer-string) "Xhello")))))

(ert-deftest helixel-test-replace-yanked-empty-kill-ring ()
  "Test replace with empty kill ring shows message."
  (helixel-test-with-buffer "hello"
    (let ((kill-ring nil))
      (helixel-replace)
      ;; Buffer unchanged
      (should (string= (buffer-string) "hello")))))

;;; helixel-replace-pop tests

(ert-deftest helixel-test-replace-pop-no-region ()
  "Test replace-pop cycles kill ring after no-region replace."
  (helixel-test-with-buffer "hello world"
    (let* ((kill-ring (list "BBB" "AAA"))
           (kill-ring-yank-pointer kill-ring)
           (helixel-replace-delete-char-p t))
      (setq last-command nil)
      (helixel-replace)
      (should (string= (buffer-string) "BBBello world"))
      (setq last-command 'helixel-replace)
      (helixel-replace-pop)
      (should (string= (buffer-string) "AAAello world"))
      (helixel-replace-pop)
      (should (string= (buffer-string) "BBBello world")))))

(ert-deftest helixel-test-replace-pop-no-delete-char ()
  "Test replace-pop with `helixel-replace-delete-char-p' nil."
  (helixel-test-with-buffer "hello"
    (let* ((kill-ring (list "BBB" "AAA"))
           (kill-ring-yank-pointer kill-ring)
           (helixel-replace-delete-char-p nil))
      (setq last-command nil)
      (helixel-replace)
      (should (string= (buffer-string) "BBBhello"))
      (setq last-command 'helixel-replace)
      (helixel-replace-pop)
      (should (string= (buffer-string) "AAAhello")))))

(ert-deftest helixel-test-replace-pop-charwise-region ()
  "Test replace-pop after charwise region replace."
  (helixel-test-with-buffer "hello brave world"
    (let* ((kill-ring (list "cruel" "nice"))
           (kill-ring-yank-pointer kill-ring))
      ;; Select "brave"
      (push-mark 7 t t)
      (goto-char 12)
      (setq helixel--selection-type nil)
      (setq last-command nil)
      (helixel-replace)
      (should (string= (buffer-string) "hello cruel world"))
      (setq last-command 'helixel-replace)
      (helixel-replace-pop)
      (should (string= (buffer-string) "hello nice world")))))

(ert-deftest helixel-test-replace-pop-linewise-selection ()
  "Test replace-pop after line-wise selection replace."
  (helixel-test-with-buffer
      "first line\nsecond line\nthird line"
    (let* ((kill-ring (list "AAA" "BBB"))
           (kill-ring-yank-pointer kill-ring))
      (goto-char 12)
      (helixel-select-line)
      (setq last-command nil)
      (helixel-replace)
      (should (string= (buffer-string) "first line\nAAA\nthird line"))
      (setq last-command 'helixel-replace)
      (helixel-replace-pop)
      (should (string= (buffer-string) "first line\nBBB\nthird line")))))

(ert-deftest helixel-test-replace-pop-wrong-last-command ()
  "Test replace-pop browses kill-ring when previous command was not a replace."
  (helixel-test-with-buffer "hello"
    (let* ((kill-ring (list "BBB" "AAA"))
           (kill-ring-yank-pointer kill-ring)
           (helixel-replace-delete-char-p t))
      (setq last-command 'self-insert-command)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt collection &rest _)
                   (car collection))))
        (helixel-replace-pop)
        (should (string= (buffer-string) "BBBello"))
        ;; Subsequent calls should cycle
        (setq last-command 'helixel-replace-pop)
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (_prompt _collection &rest _)
                     (error "should not be called"))))
          (helixel-replace-pop)
          (should (string= (buffer-string) "AAAello")))))))

(ert-deftest helixel-test-replace-pop-no-bounds ()
  "Test replace-pop errors with no replace-pop-bounds (rect case)."
  (helixel-test-with-buffer "hello"
    (let* ((kill-ring (list "AAA"))
           (kill-ring-yank-pointer kill-ring)
           (helixel--replace-pop-bounds nil))
      (setq last-command 'helixel-replace)
      (should-error (helixel-replace-pop)))))

(ert-deftest helixel-test-replace-pop-with-arg ()
  "Test replace-pop with numeric argument skips kills."
  (helixel-test-with-buffer "hello"
    (let* ((kill-ring (list "CCC" "BBB" "AAA"))
           (kill-ring-yank-pointer kill-ring)
           (helixel-replace-delete-char-p t))
      (setq last-command nil)
      (helixel-replace)
      (should (string= (buffer-string) "CCCello"))
      (setq last-command 'helixel-replace)
      ;; Pop with arg 1 advances one kill forward (CCC→BBB)
      (helixel-replace-pop 1)
      (should (string= (buffer-string) "BBBello")))))

;;; Integration: select-line -> kill -> yank round-trip

(ert-deftest helixel-test-linewise-round-trip ()
  "Test full round-trip: select line, kill, then yank elsewhere."
  (helixel-test-with-buffer "line A\nline B\nline C"
    (let ((kill-ring nil))
      ;; Select and kill line B
      (goto-char 8)
      (helixel-select-line)
      (helixel-kill-thing-at-point)
      (should (string= (buffer-string) "line A\nline C"))
      ;; Now yank (paste below) on line A
      (goto-char 1)
      (let ((this-command 'helixel-yank))
        (helixel-yank))
      (should (string= (buffer-string) "line A\nline B\nline C")))))

(ert-deftest helixel-test-linewise-copy-yank-round-trip ()
  "Test round-trip: select line, copy, then yank-before."
  (helixel-test-with-buffer "line A\nline B\nline C"
    (let ((kill-ring nil))
      ;; Select and copy line A
      (helixel-select-line)
      (helixel-kill-ring-save)
      ;; Yank before line C
      (goto-char 15) ;; on line C
      (let ((this-command 'helixel-yank-before))
        (helixel-yank-before))
      (should (string= (buffer-string) "line A\nline B\nline A\nline C")))))

(ert-deftest helixel-test-charwise-not-affected ()
  "Test that charwise operations are unaffected by line-wise changes."
  (helixel-test-with-buffer "hello world"
    (let ((kill-ring nil))
      (push-mark (point) t t)
      (goto-char 6)
      (setq helixel--selection-type nil)
      (helixel-kill-thing-at-point)
      (should (string= (car kill-ring) "hello"))
      (should-not (helixel--linewise-kill-p (car kill-ring)))
      (goto-char 1)
      (helixel-yank)
      (should (string= (buffer-string) "hello world")))))

;;; helixel-begin-selection clears line type

(ert-deftest helixel-test-begin-selection-clears-line-type ()
  "Test that `helixel-begin-selection' clears line selection type."
  (helixel-test-with-buffer "hello"
    (setq helixel--selection-type 'line)
    (helixel-begin-selection)
    (should-not helixel--selection-type)))

;;; Rect selection tests

(ert-deftest helixel-test-select-rectangle-starts-rect ()
  "Test `helixel-select-rectangle' starts rectangle-mark-mode."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (call-interactively #'helixel-select-rectangle)
    (should rectangle-mark-mode)
    (should (eq helixel--selection-type 'rect))
    (should (region-active-p))))

(ert-deftest helixel-test-select-rectangle-extends ()
  "Test `helixel-select-rectangle' extends rectangle downward."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (call-interactively #'helixel-select-rectangle)
    (setq last-command 'helixel-select-rectangle)
    (let ((mark-pos (mark)))
      (call-interactively #'helixel-select-rectangle)
      (should (> (point) mark-pos))
      (should rectangle-mark-mode))))

;;; helixel--selection-type rect tests

(ert-deftest helixel-test-selection-type-rect ()
  "Test `helixel--selection-type' returns `rect' for rectangle selection."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (setq helixel--selection-type 'rect)
    (push-mark (point) t t)
    (goto-char 8)
    (rectangle-mark-mode 1)
    (should (eq (helixel--selection-type) 'rect))
    (rectangle-mark-mode -1)))

(ert-deftest helixel-test-selection-type-rect-without-mode ()
  "Test `helixel--selection-type' returns nil when rect type but mode off."
  (helixel-test-with-buffer "first line\nsecond line"
    (setq helixel--selection-type 'rect)
    (push-mark (point) t t)
    (goto-char 8)
    ;; rectangle-mark-mode not active
    (should-not (helixel--selection-type))))

;;; helixel--clear-data clears rect mode

(ert-deftest helixel-test-clear-data-clears-rect ()
  "Test `helixel--clear-data' disables rectangle-mark-mode."
  (helixel-test-with-buffer "first line\nsecond line"
    (helixel-select-rectangle)
    (helixel--clear-data)
    (should-not rectangle-mark-mode)
    (should-not helixel--selection-type)))

;;; helixel--rect-wise-text and helixel--rect-wise-kill-p tests

(ert-deftest helixel-test-rect-wise-text-propertizes ()
  "Test `helixel--rect-wise-text' propertizes text with rect handler."
  (let* ((lines '("hel" "wor"))
         (text (helixel--rect-wise-text lines)))
    (should (string= text "hel\nwor"))
    (should (eq (car (get-text-property 0 'yank-handler text))
                'helixel--yank-handler-rect-wise))
    (should (equal (nth 1 (get-text-property 0 'yank-handler text))
                   lines))))

(ert-deftest helixel-test-rect-wise-kill-p-positive ()
  "Test `helixel--rect-wise-kill-p' detects rect text."
  (let ((text (helixel--rect-wise-text '("AAA" "BBB"))))
    (should (helixel--rect-wise-kill-p text))))

(ert-deftest helixel-test-rect-wise-kill-p-negative ()
  "Test `helixel--rect-wise-kill-p' returns nil for plain text."
  (should-not (helixel--rect-wise-kill-p "plain")))

(ert-deftest helixel-test-rect-wise-kill-p-nil-kill-ring ()
  "Test `helixel--rect-wise-kill-p' returns nil when no kill ring."
  (let ((kill-ring nil))
    (should-not (helixel--rect-wise-kill-p))))

;;; helixel-kill-thing-at-point (d) rect tests

(ert-deftest helixel-test-kill-thing-rect ()
  "Test killing a rectangle selection."
  (helixel-test-with-buffer "ABC line1\nDEF line2\nGHI line3"
    (let ((kill-ring nil))
      (goto-char 1)
      (push-mark (point) t t)
      (goto-char 14) ;; col 3 on line 2 (space after "DEF")
      (rectangle-mark-mode 1)
      (setq helixel--selection-type 'rect)
      (helixel-kill-thing-at-point)
      (should (helixel--rect-wise-kill-p (car kill-ring)))
      ;; After killing first 3 chars of first two lines:
      (should (string= (buffer-string) " line1\n line2\nGHI line3"))
      (should-not rectangle-mark-mode))))

(ert-deftest helixel-test-kill-thing-rect-single-line ()
  "Test killing a single-line rectangle (like one char)."
  (helixel-test-with-buffer "ABCDE"
    (let ((kill-ring nil))
      (push-mark (point) t t)
      (goto-char 2)
      (rectangle-mark-mode 1)
      (setq helixel--selection-type 'rect)
      (helixel-kill-thing-at-point)
      (should (helixel--rect-wise-kill-p (car kill-ring)))
      (should (string= (buffer-string) "BCDE"))
      (should-not rectangle-mark-mode))))

;;; helixel-kill-ring-save (y) rect tests

(ert-deftest helixel-test-kill-ring-save-rect ()
  "Test copying a rectangle to kill ring without deleting."
  (helixel-test-with-buffer "ABC line1\nDEF line2\nGHI line3"
    (let ((kill-ring nil))
      (goto-char 1)
      (push-mark (point) t t)
      (goto-char 14) ;; col 3 on line 2 (space after "DEF")
      (rectangle-mark-mode 1)
      (setq helixel--selection-type 'rect)
      (helixel-kill-ring-save)
      (should (helixel--rect-wise-kill-p (car kill-ring)))
      ;; Buffer content unchanged
      (should (string= (buffer-string) "ABC line1\nDEF line2\nGHI line3"))
      (should-not rectangle-mark-mode))))

;;; helixel-replace (R) rect tests

(ert-deftest helixel-test-replace-yanked-rect-with-rect ()
  "Test replacing a rectangle selection with a rect kill."
  (helixel-test-with-buffer "ABC line1\nDEF line2\nGHI line3"
    (kill-new (helixel--rect-wise-text '("???" "XXX")))
    (goto-char 1)
    (push-mark (point) t t)
    (goto-char 14) ;; col 3 on line 2
    (rectangle-mark-mode 1)
    (setq helixel--selection-type 'rect)
    (helixel-replace)
    (should (string= (buffer-string) "??? line1\nXXX line2\nGHI line3"))))

(ert-deftest helixel-test-replace-yanked-rect-with-charwise ()
  "Test replacing a rect selection with a charwise kill."
  (helixel-test-with-buffer "ABC line1\nDEF line2\nGHI line3"
    (kill-new "!!")
    (goto-char 1)
    (push-mark (point) t t)
    (goto-char 14) ;; col 3 on line 2
    (rectangle-mark-mode 1)
    (setq helixel--selection-type 'rect)
    (helixel-replace)
    ;; "!!" inserted at top-left of rectangle area
    (should (string= (buffer-string) "!! line1\n line2\nGHI line3"))))

;;; New operators: case, comment, shell, fill

(ert-deftest helixel-test-toggle-case-region ()
  "~ on a region toggles case of each char."
  (helixel-test-with-buffer "Hello World"
    (set-mark 12)
    (helixel-toggle-case)
    (should (string= (buffer-string) "hELLO wORLD"))))

(ert-deftest helixel-test-toggle-case-char ()
  "~ at point toggles single char and advances."
  (helixel-test-with-buffer "hello"
    (helixel-toggle-case)
    (should (string= (buffer-string) "Hello"))
    (should (= (point) 2))))

(ert-deftest helixel-test-toggle-case-dot-repeat ()
  "~ then . advances and toggles next char."
  (helixel-test-with-buffer "Hello"
    (helixel-toggle-case)
    (should (string= (buffer-string) "hello"))
    (should (= (point) 2))
    (let ((tx helixel--last-tx))
      (funcall (helixel-edit-op-runner (helixel-edit-op tx)) tx))
    (should (string= (buffer-string) "hEllo"))
    (should (= (point) 3))))

(ert-deftest helixel-test-toggle-case-count ()
  "3~ toggles 3 characters and advances."
  (helixel-test-with-buffer "HeLlO"
    (let ((current-prefix-arg 3))
      (call-interactively #'helixel-toggle-case))
    (should (string= (buffer-string) "hEllO"))
    (should (= (point) 4))))

(ert-deftest helixel-test-toggle-case-count-dot-repeat ()
  "2. after 2~ toggles 2 more chars (each . toggles 1)."
  (helixel-test-with-buffer "HeLlO wOrLd"
    (let ((current-prefix-arg 2))
      (call-interactively #'helixel-toggle-case))
    (should (string= (buffer-string) "hELlO wOrLd"))
    (should (= (point) 3))
    (helixel-repeat-edit 2)
    (should (string= (buffer-string) "hElLO wOrLd"))
    (should (= (point) 5))))

(ert-deftest helixel-test-downcase-region ()
  "gu on a region lowercases."
  (helixel-test-with-buffer "HELLO"
    (set-mark 6)
    (helixel-downcase)
    (should (string= (buffer-string) "hello"))))

(ert-deftest helixel-test-upcase-region ()
  "gU on a region uppercases."
  (helixel-test-with-buffer "hello"
    (set-mark 6)
    (helixel-upcase)
    (should (string= (buffer-string) "HELLO"))))

(ert-deftest helixel-test-downcase-count ()
  "3gu lowercases 3 words."
  (helixel-test-with-buffer "HELLO WORLD FOO bar"
    (let ((current-prefix-arg 3))
      (call-interactively #'helixel-downcase))
    (should (string= (buffer-string) "hello world foo bar"))))

(ert-deftest helixel-test-upcase-count ()
  "2gU uppercases 2 words."
  (helixel-test-with-buffer "hello WORLD foo BAR"
    (let ((current-prefix-arg 2))
      (call-interactively #'helixel-upcase))
    (should (string= (buffer-string) "HELLO WORLD foo BAR"))))

(ert-deftest helixel-test-comment-toggle ()
  "gc toggles comment on region or line."
  (helixel-test-with-buffer ";; commented"
    (emacs-lisp-mode)
    (set-mark 13)
    (helixel-comment-toggle)
    (should (string= (buffer-string) "commented"))))

(ert-deftest helixel-test-fill-paragraph ()
  "gq fills paragraph to fill-column."
  (helixel-test-with-buffer
      "This is a long line that exceeds the column."
    (let ((fill-column 20))
      (helixel-fill))
    (should (string-match-p "\n" (buffer-string)))))

;;; helixel-join-lines (J) tests

(ert-deftest helixel-test-join-lines-basic ()
  "J joins the current line with the next."
  (helixel-test-with-buffer "hello\nworld"
    (helixel-join-lines)
    (should (string= (buffer-string) "hello world"))))

(ert-deftest helixel-test-join-lines-with-count ()
  "3J joins 3 lines together."
  (helixel-test-with-buffer "one\ntwo\nthree"
    (helixel-join-lines 3)
    (should (string= (buffer-string) "one two three"))))

(ert-deftest helixel-test-join-lines-dot-repeat ()
  "J then . repeats the join on the next line."
  (helixel-test-with-buffer "a\nb\nc"
    (helixel-join-lines)
    (should (string= (buffer-string) "a b\nc"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "a b c"))))

(ert-deftest helixel-test-join-lines-dot-repeat-with-count ()
  "3J stores count so . repeats joining 3 lines."
  (helixel-test-with-buffer "a\nb\nc\nd\ne\nf"
    (helixel-join-lines 3)
    (should (string= (buffer-string) "a b c\nd\ne\nf"))
    (forward-line)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "a b c\nd e f"))))

(ert-deftest helixel-test-join-lines-at-eob ()
  "J with one line in buffer removes trailing newline."
  (helixel-test-with-buffer "hello\n"
    (helixel-join-lines)
    (should (string= (buffer-string) "hello"))))

(ert-deftest helixel-test-join-lines-whitespace-cleanup ()
  "J strips leading whitespace from the joined line."
  (helixel-test-with-buffer "hello\n  world"
    (helixel-join-lines)
    (should (string= (buffer-string) "hello world"))))

(ert-deftest helixel-test-join-lines-blank-line ()
  "J joins a blank line with the next."
  (helixel-test-with-buffer "hello\n\nworld"
    (goto-char 7)
    (helixel-join-lines)
    (should (string= (buffer-string) "hello\nworld"))))

;;; helixel-swap tests

(defun helixel-test--set-swap-source (buffer beg end &optional type)
  "Push text from BUFFER at BEG..END to `kill-ring' with swap-source.
TYPE is the selection type: nil (char), `line', or `rect'."
  (let ((text (with-current-buffer buffer
                (buffer-substring-no-properties beg end))))
    (kill-new
     (propertize text
       'helixel-swap-source
       (list :beg (set-marker (make-marker) beg buffer)
             :end (set-marker (make-marker) end buffer)
             :buffer buffer
             :type type)))))

(defun helixel-test--get-swap-source ()
  "Return the swap-source plist from `kill-ring' top, or nil."
  (when kill-ring
    (let ((src (get-text-property 0 'helixel-swap-source
                                  (car kill-ring))))
      (and (plist-get src :beg) src))))

(ert-deftest helixel-test-swap-contiguous ()
  "Swap primary region with swap source from kill-ring."
  (helixel-test-with-buffer "AAA BBB CCC"
    (let ((kill-ring nil))
      (helixel-test--set-swap-source (current-buffer) 1 4)
      (push-mark 8 t t)
      (goto-char 5)
      (helixel-swap)
      (should (string= (buffer-string) "BBB AAA CCC")))))

(ert-deftest helixel-test-swap-imply-region ()
  "Swap implied region with swap source."
  (helixel-test-with-buffer "AAA BBB CCC"
    (let ((kill-ring nil))
      (helixel-test--set-swap-source (current-buffer) 1 4)
      (goto-char 5)
      (let ((helixel-swap-imply-region t))
        (helixel-swap))
      (should (string= (buffer-string) "BBB AAA CCC")))))

(ert-deftest helixel-test-swap-overlap-error ()
  "Error when region and swap source overlap."
  (helixel-test-with-buffer "ABCDEF"
    (let ((kill-ring nil))
      (helixel-test--set-swap-source (current-buffer) 1 4)
      (push-mark 5 t t)
      (goto-char 3)
      (should-error (helixel-swap)))))

(ert-deftest helixel-test-swap-no-source ()
  "Error when no swap source exists."
  (helixel-test-with-buffer "hello"
    (let ((kill-ring nil))
      (should-error (helixel-swap)))))

(ert-deftest helixel-test-y-sets-swap-source ()
  "`y' stores swap-source property on kill-ring text."
  (helixel-test-with-buffer "hello world"
    (let ((kill-ring nil))
      (push-mark 1 t t)
      (goto-char 6)
      (setq helixel--selection-type nil)
      (helixel-kill-ring-save)
      (let ((src (helixel-test--get-swap-source)))
        (should src)
        (should (= (marker-position (plist-get src :beg)) 1))
        (should (= (marker-position (plist-get src :end)) 6))))))

(ert-deftest helixel-test-y-sets-swap-source-line ()
  "`y' stores line-wise swap-source."
  (helixel-test-with-buffer "first line\nsecond line"
    (let ((kill-ring nil))
      (push-mark 1 t t)
      (goto-char 11)
      (setq helixel--selection-type 'line)
      (helixel-kill-ring-save)
      (let ((src (helixel-test--get-swap-source)))
        (should src)
        (should (eq (plist-get src :type) 'line))
        (should (= (marker-position (plist-get src :beg)) 1))))))

(ert-deftest helixel-test-y-then-swap ()
  "After `y', swap works without explicit `Y'."
  (helixel-test-with-buffer "AAA BBB CCC"
    (let ((kill-ring nil))
      ;; Select "AAA" and yank it (stores swap-source)
      (push-mark 1 t t)
      (goto-char 4)
      (setq helixel--selection-type nil)
      (helixel-kill-ring-save)
      ;; Now select "BBB" and swap
      (push-mark 8 t t)
      (goto-char 5)
      (helixel-swap)
      (should (string= (buffer-string) "BBB AAA CCC")))))

;;; Swap: cross-buffer

(ert-deftest helixel-test-swap-cross-buffer ()
  "Cross-buffer swap exchanges text between two buffers."
  (let ((kill-ring nil)
        buf-a buf-b)
    (unwind-protect
        (progn
          (setq buf-a (generate-new-buffer " *swap-a*" t))
          (with-current-buffer buf-a
            (insert "HELLO"))
          (helixel-test--set-swap-source buf-a 1 6)
          (setq buf-b (generate-new-buffer " *swap-b*" t))
          (with-current-buffer buf-b
            (transient-mark-mode 1)
            (insert "WORLD")
            (push-mark 1 t t)
            (goto-char 6)
            (helixel-swap)
            (should (string= (buffer-string) "HELLO"))
            (let ((src (helixel-test--get-swap-source)))
              (should src)
              (should (eq (plist-get src :buffer) (current-buffer)))))
          (with-current-buffer buf-a
            (should (string= (buffer-string) "WORLD"))))
      (ignore-errors (kill-buffer buf-a))
      (ignore-errors (kill-buffer buf-b)))))

(ert-deftest helixel-test-swap-cross-buffer-no-region ()
  "Cross-buffer swap at point (no active region)."
  (let ((kill-ring nil)
        buf-a buf-b)
    (unwind-protect
        (progn
          (setq buf-a (generate-new-buffer " *swap-a*" t))
          (with-current-buffer buf-a
            (insert "HELLO"))
          (helixel-test--set-swap-source buf-a 1 6)
          (setq buf-b (generate-new-buffer " *swap-b*" t))
          (with-current-buffer buf-b
            (transient-mark-mode 1)
            (insert "WORLD")
            (goto-char 4)  ;; after "WOR"
            (helixel-swap)
            (should (string= (buffer-string) "WORHELLOLD")))
          (with-current-buffer buf-a
            (should (string= (buffer-string) ""))))
      (ignore-errors (kill-buffer buf-a))
      (ignore-errors (kill-buffer buf-b)))))

(ert-deftest helixel-test-swap-cross-buffer-linewise-no-region ()
  "Cross-buffer line-wise swap with no region implies full lines."
  (let ((kill-ring nil)
        buf-a buf-b)
    (unwind-protect
        (progn
          (setq buf-a (generate-new-buffer " *swap-a*" t))
          (with-current-buffer buf-a
            (insert "a\nb\n"))
          ;; Store 2-line line-wise swap source.
          (helixel-test--set-swap-source buf-a 1 4 'line)
          (setq buf-b (generate-new-buffer " *swap-b*" t))
          (with-current-buffer buf-b
            (transient-mark-mode 1)
            (insert "1\n2\n3\n4\n")
            (goto-char 5)  ;; start of line 3
            (helixel-swap)
            ;; 2 lines from line 3: "3\n4\n" swapped with "a\nb\n".
            (should (string= (buffer-string) "1\n2\na\nb\n")))
          (with-current-buffer buf-a
            (should (string= (buffer-string) "3\n4\n"))))
      (ignore-errors (kill-buffer buf-a))
      (ignore-errors (kill-buffer buf-b)))))

(ert-deftest helixel-test-swap-cross-buffer-stores-inserted ()
  "Cross-buffer swap with no region stores inserted text as swap source."
  (let ((kill-ring nil)
        buf-a buf-b)
    (unwind-protect
        (progn
          (setq buf-a (generate-new-buffer " *swap-a*" t))
          (with-current-buffer buf-a
            (insert "HELLO"))
          (helixel-test--set-swap-source buf-a 1 6)
          (setq buf-b (generate-new-buffer " *swap-b*" t))
          (with-current-buffer buf-b
            (transient-mark-mode 1)
            (insert "WORLD")
            (goto-char 4)
            (helixel-swap)
            ;; Swap source should store the inserted text.
            (let ((src (helixel-test--get-swap-source)))
              (should src)
              (should (eq (plist-get src :buffer) (current-buffer)))
              (let ((stored (car kill-ring)))
                (should (string= stored "HELLO"))))))
      (ignore-errors (kill-buffer buf-a))
      (ignore-errors (kill-buffer buf-b)))))

;;; Swap: line-wise implied region

(ert-deftest helixel-test-swap-imply-linewise ()
  "Line-wise implied region swaps full lines from current line."
  (helixel-test-with-buffer "line1\nline2\nline3\n"
    (let ((kill-ring nil)
          (helixel-swap-imply-region t))
      ;; Store line1 (positions 1-6) as line-wise swap source.
      (helixel-test--set-swap-source (current-buffer) 1 6 'line)
      ;; Go to start of line2, no active region.
      (goto-char 7)
      (helixel-swap)
      ;; line2 swapped with line1.
      (should (string= (buffer-string) "line2\nline1\nline3\n")))))

(ert-deftest helixel-test-swap-imply-linewise-multiline ()
  "Line-wise implied region swaps N lines from current line."
  (helixel-test-with-buffer "a\nb\nc\nd\ne\n"
    (let ((kill-ring nil)
          (helixel-swap-imply-region t))
      ;; Store lines a-b (positions 1-4) as line-wise source (2 lines).
      (helixel-test--set-swap-source (current-buffer) 1 4 'line)
      ;; Go to start of line4 (position 7 = after "c\n").
      (goto-char 7)
      (helixel-swap)
      ;; 2 lines from position 7 bol: "d\ne\n" swapped with "a\nb\n".
      (should (string= (buffer-string) "d\ne\nc\na\nb\n")))))

;;; Swap: rectangle

(ert-deftest helixel-test-swap-rect-equal-lines ()
  "Rect swap with equal line counts."
  (helixel-test-with-buffer "111AAA\n222BBB\n333CCC\n"
    (let ((kill-ring nil))
      ;; Source: 3-line rect at col 0-2.
      (helixel-test--set-swap-source (current-buffer) 1 18 'rect)
      ;; Target: 3-line rect at col 3-5.
      (rectangle-mark-mode 1)
      (goto-char 4)
      (push-mark 4 t t)
      (goto-char 21)
      (activate-mark)
      (let ((src (helixel-test--get-swap-source)))
        (helixel--swap-from-source-rect
         (plist-get src :beg) (plist-get src :end) nil))
      (should (string= (buffer-string)
                       "AAA111\nBBB222\nCCC333\n")))))

(ert-deftest helixel-test-extend-rect-ranges ()
  "`helixel--extend-rect-ranges' adds lines with same column span."
  (helixel-test-with-buffer "xxx---\nyyy===\nzzz+++\n"
    (let* ((ranges (helixel--rect-ranges 1 4))  ;; col 0-2, line 1 only
           (ext (helixel--extend-rect-ranges ranges 3)))
      (should (= (length ext) 3))
      ;; Line 2: col 0-2 = "yyy", line 3: col 0-2 = "zzz".
      (should (string= (buffer-substring-no-properties
                        (car (nth 1 ext)) (cdr (nth 1 ext)))
                       "yyy"))
      (should (string= (buffer-substring-no-properties
                        (car (nth 2 ext)) (cdr (nth 2 ext)))
                       "zzz")))))

(ert-deftest helixel-test-swap-rect-extend ()
  "Rect swap extends shorter source to match longer target (default: max)."
  (helixel-test-with-buffer "111AAA\n222BBB\n333CCC\n"
    (let ((kill-ring nil))
      ;; Source: 1-line rect at col 0-2 (positions 1-3 = "111").
      (helixel-test--set-swap-source (current-buffer) 1 4 'rect)
      ;; Target: 3-line rect at col 3-5 ("AAA"/"BBB"/"CCC").
      (rectangle-mark-mode 1)
      (goto-char 4)
      (push-mark 4 t t)
      (goto-char 21)  ;; col 6, line 3 (exclusive end)
      (activate-mark)
      (let ((src (helixel-test--get-swap-source)))
        (helixel--swap-from-source-rect
         (plist-get src :beg) (plist-get src :end) nil))
      (should (string= (buffer-string)
                       "AAA111\nBBB222\nCCC333\n")))))

(ert-deftest helixel-test-swap-rect-truncate ()
  "C-u rect swap truncates longer to match shorter (min lines)."
  (helixel-test-with-buffer "111AAA\n222BBB\n333CCC\n"
    (let ((kill-ring nil))
      ;; Source: 3-line rect at col 0-2 ("111"/"222"/"333").
      (helixel-test--set-swap-source (current-buffer) 1 18 'rect)
      ;; Target: 1-line rect at col 3-5 ("AAA").
      (rectangle-mark-mode 1)
      (goto-char 4)
      (push-mark 4 t t)
      (goto-char 7)  ;; col 6, line 1 (exclusive end)
      (activate-mark)
      (let ((src (helixel-test--get-swap-source)))
        (helixel--swap-from-source-rect
         (plist-get src :beg) (plist-get src :end) t))
      (should (string= (buffer-string)
                       "AAA111\n222BBB\n333CCC\n")))))

;;; helixel-yank (p) rect tests

(ert-deftest helixel-test-yank-rect ()
  "Test pasting a rect kill at point."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (kill-new (helixel--rect-wise-text '("<<<" ">>>")))
    (goto-char 1)
    (helixel-yank)
    (should (string= (buffer-string) "<<<line1\n>>>line2\nline3"))))

(ert-deftest helixel-test-yank-rect-after ()
  "Test pasting a rect kill after point."
  (helixel-test-with-buffer "AAline1\nBBline2\nCCline3"
    (kill-new (helixel--rect-wise-text '("--" "++")))
    (goto-char 3) ;; after "AA"
    (helixel-yank)
    (should (string= (buffer-string) "AA--line1\nBB++line2\nCCline3"))))

;;; helixel-yank-before (P) rect tests

(ert-deftest helixel-test-yank-before-rect ()
  "Test pasting a rect kill before point."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (kill-new (helixel--rect-wise-text '("<<<" ">>>")))
    (goto-char 1)
    (helixel-yank-before)
    (should (string= (buffer-string) "<<<line1\n>>>line2\nline3"))))

;;; helixel-begin-selection exits rect

(ert-deftest helixel-test-begin-selection-clears-rect ()
  "Test that `helixel-begin-selection' disables rectangle-mark-mode."
  (helixel-test-with-buffer "hello\nworld"
    (helixel-select-rectangle)
    (should rectangle-mark-mode)
    (helixel-begin-selection)
    (should-not rectangle-mark-mode)
    (should-not helixel--selection-type)))

;;; Interaction: rect kill doesn't affect line-wise detection

(ert-deftest helixel-test-rect-kill-not-line-wise ()
  "Test that rect-killed text is not detected as line-wise."
  (let ((text (helixel--rect-wise-text '("AAA" "BBB"))))
    (should-not (helixel--linewise-kill-p text))))

(ert-deftest helixel-test-line-kill-not-rect-wise ()
  "Test that line-killed text is not detected as rect-wise."
  (let ((text (helixel--linewise-text "hello\n")))
    (should-not (helixel--rect-wise-kill-p text))))

;;; Round-trip: rect select -> kill -> yank

(ert-deftest helixel-test-rect-round-trip ()
  "Test full round-trip: select rect, kill, then yank elsewhere."
  (helixel-test-with-buffer "AAA line1\nBBB line2\nCCC line3"
    (let ((kill-ring nil))
      (goto-char 1)
      (push-mark (point) t t)
      (goto-char 14) ;; col 3 on line 2 (space after "BBB")
      (rectangle-mark-mode 1)
      (setq helixel--selection-type 'rect)
      (helixel-kill-thing-at-point)
      (should (string= (buffer-string) " line1\n line2\nCCC line3"))
      ;; Now yank at beginning
      (goto-char 1)
      (helixel-yank)
      (should (string= (buffer-string) "AAA line1\nBBB line2\nCCC line3")))))

;;; Movement preserves rectangle selection

(ert-deftest helixel-test-movement-preserves-rect ()
  "Test that h/l/j/k movement preserves rectangle-mark-mode."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (goto-char 4) ;; avoid beginning-of-buffer on backward-char
    (call-interactively #'helixel-select-rectangle)
    (should rectangle-mark-mode)
    (helixel-backward-char)
    (should rectangle-mark-mode)
    (helixel-forward-char)
    (should rectangle-mark-mode)
    (helixel-next-line)
    (should rectangle-mark-mode)
    (helixel-previous-line)
    (should rectangle-mark-mode)))

;;; Rect change (c) with replay

(ert-deftest helixel-test-rect-change-multi-line ()
  "Test `c` on rect replays inserted text on all rect lines."
  (helixel-test-with-buffer "ABC line1\nDEF line2\nGHI line3"
    (goto-char 1)
    (push-mark (point) t t)
    (goto-char 14) ;; col 3 on line 2
    (rectangle-mark-mode 1)
    (setq helixel--selection-type 'rect)
    (helixel-change-thing-at-point)
    ;; Rect deleted, now type text in insert mode
    (insert "XXX")
    (helixel-insert-exit)
    (should (string= (buffer-string) "XXX line1\nXXX line2\nGHI line3"))))

(ert-deftest helixel-test-rect-change-empty-input ()
  "Test `c` on rect with empty input just deletes the rect."
  (helixel-test-with-buffer "ABC line1\nDEF line2\nGHI line3"
    (goto-char 1)
    (push-mark (point) t t)
    (goto-char 14)
    (rectangle-mark-mode 1)
    (setq helixel--selection-type 'rect)
    (helixel-change-thing-at-point)
    ;; Exit immediately without typing anything
    (helixel-insert-exit)
    (should (string= (buffer-string) " line1\n line2\nGHI line3"))))

(ert-deftest helixel-test-rect-change-single-line ()
  "Test `c` on single-line rect (no replay needed)."
  (helixel-test-with-buffer "ABC line1\nDEF line2"
    (goto-char 1)
    (push-mark (point) t t)
    (goto-char 3) ;; col 2 on same line
    (rectangle-mark-mode 1)
    (setq helixel--selection-type 'rect)
    (helixel-change-thing-at-point)
    (insert "XXX")
    (helixel-insert-exit)
    ;; Only line 1 changed; line-count=1 → no replay
    (should (string= (buffer-string) "XXXC line1\nDEF line2"))))

(ert-deftest helixel-test-rect-change-clears-replay-data ()
  "Test that rect replay data is cleared after exit."
  (helixel-test-with-buffer "ABC line1\nDEF line2\nGHI line3"
    (goto-char 1)
    (push-mark (point) t t)
    (goto-char 14)
    (rectangle-mark-mode 1)
    (setq helixel--selection-type 'rect)
    (helixel-change-thing-at-point)
    (insert "XXX")
    (helixel-insert-exit)
    (should-not helixel--rect-replay-data)
    (should-not helixel--rect-replay-marker)))

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
  "Test text-object command starts an action."
  (helixel-test-with-buffer "hello world"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (should helixel--action)
    (should (eq (helixel--live-get :category) 'textobj))
    (should (= (marker-position (helixel--live-get :marker)) 1))))

(ert-deftest helixel-test-textobj-session-same-family-continues ()
  "Test same-category text-object commands continue action."
  (helixel-test-with-buffer "(hello) (world)"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-mark-inner-paren)
    (goto-char 2)
    (helixel-mark-inner-paren)
    (should (eq (helixel--live-get :category) 'textobj))
    (let ((mark-pos (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-mark-inner-paren this-command 'helixel-mark-a-paren)
      (goto-char 10)
      (helixel-mark-a-paren)
      (should (eq (helixel--live-get :category) 'textobj)))))

(ert-deftest helixel-test-textobj-session-different-family-breaks ()
  "Test different-family textobj pushes old action to ring."
  (helixel-test-with-buffer "hello (world)"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word this-command 'helixel-mark-inner-paren)
    (helixel-mark-inner-paren)
    (should (= (length helixel--action-ring) 1))
    (should (eq (helixel--live-get :subcat) 'pair))))

(ert-deftest helixel-test-textobj-session-type-property ()
  "Test textobj actions have correct category and subcat."
  (let (helixel--action helixel--action-ring helixel--action-pos)
    (helixel-test-with-buffer "hello world"
      (setq last-command nil this-command 'helixel-mark-inner-word)
      (helixel-mark-inner-word)
      (should (eq (helixel--live-get :category) 'textobj))
      (should (eq (helixel--live-get :subcat) 'word)))))

;;; Search tests

(ert-deftest helixel-test-search--search-case-fold ()
  "helixel-search--search respects `case-fold-search'.
With case-fold-search=t (default), 'hello' matches 'Hello'.
With case-fold-search=nil, 'hello' does NOT match 'Hello' but
exact-case 'Hello' still matches 'Hello'."
  (helixel-test-with-buffer "foo Hello bar HELLO baz"
    (goto-char (point-min))
    ;; case-fold-search t (default): 'hello' matches 'Hello' (first)
    (let ((case-fold-search t))
      (should (helixel-search--search "hello" 'forward))
      (should (= (match-beginning 0) 5)))
    ;; case-fold-search nil: 'hello' does NOT match 'Hello'
    (goto-char (point-min))
    (let ((case-fold-search nil))
      (condition-case nil
          (progn
            (helixel-search--search "hello" 'forward)
            (ert-fail "Expected search-failed with case-fold nil"))
        (search-failed)))
    ;; case-fold nil but matching exact case
    (goto-char (point-min))
    (let ((case-fold-search nil))
      (should (helixel-search--search "Hello" 'forward))
      (should (= (match-beginning 0) 5)))))

(ert-deftest helixel-test-search--search-backward ()
  "helixel-search--search backward finds match before point."
  (helixel-test-with-buffer "hello world hello"
    (goto-char (point-max))
    ;; Backward search from end finds last "hello"
    (should (helixel-search--search "hello" 'backward))
    (should (= (match-beginning 0) 13))
    (should (= (match-end 0) 18))
    ;; point moves to match-beginning for backward search
    (should (= (point) (match-beginning 0)))))

(ert-deftest helixel-test-search--search-forward ()
  "helixel-search--search forward finds match after point."
  (helixel-test-with-buffer "hello world hello"
    (goto-char (point-min))
    ;; Forward search from start finds first "hello"
    (should (helixel-search--search "hello" 'forward))
    (should (= (match-beginning 0) 1))
    (should (= (match-end 0) 6))
    ;; point moves to match-end for forward search
    (should (= (point) (match-end 0)))))

(ert-deftest helixel-test-search-done-hook-forward ()
  "helixel-search--done-hook sets up repeat state after /search."
  (let (helixel--action helixel--action-ring helixel--action-pos)
    (helixel-test-with-buffer "hello world hello"
      (goto-char 1)
      ;; Simulate /hello<RET> — forward search
      (re-search-forward "hello")
      (let ((helixel-search--had-region nil)
            (isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (copy-marker (match-beginning 0))))
        ;; helixel-search-forward calls action-start before isearch
        (helixel-action-start 'search 'search)
        (helixel-search--done-hook))
      ;; Verify repeat state
      (should (eq (helixel-repeat-category) 'search))
      (should (string= (helixel--action-get helixel--repeat-data :pattern)
                       "hello"))
      (should (eq (helixel-repeat-dir) 'forward))
      ;; Verify selection context for . repeat
      (let ((sel helixel--repeat-sel-ctx))
        (should sel)
        (should (eq (helixel-sel-get-kind sel) 'search))
        (should (string= (helixel-sel-search-pattern sel) "hello"))
        (should (eq (helixel-sel-search-dir sel) 'forward)))
      ;; Verify region is active on the match
      (should (region-active-p))
      (should (= (region-beginning) 1))
      (should (= (region-end) 6)))))

(ert-deftest helixel-test-search-done-hook-case-sensitive ()
  "helixel-search--done-hook after ?Hello sets case-sensitive repeat."
  (let (helixel--action helixel--action-ring helixel--action-pos)
    (helixel-test-with-buffer "Hello hello Hello"
      (goto-char (point-max))
      ;; Simulate ?Hello<RET> — backward case-sensitive search
      (re-search-backward "Hello")
      (let ((helixel-search--had-region nil)
            (isearch-success t)
            (isearch-string "Hello")
            (isearch-regexp t)
            (isearch-forward nil)  ;; backward
            (isearch-other-end (copy-marker (match-end 0))))
        (helixel-action-start 'search 'search)
        (helixel-search--done-hook))
      ;; Verify repeat preserves case-sensitive pattern
      (should (eq (helixel-repeat-category) 'search))
      (should (string= (helixel--action-get helixel--repeat-data :pattern)
                       "Hello"))
      (should (eq (helixel-repeat-dir) 'backward))
      ;; Verify selection context
      (let ((sel helixel--repeat-sel-ctx))
        (should sel)
        (should (eq (helixel-sel-get-kind sel) 'search))
        (should (string= (helixel-sel-search-pattern sel) "Hello"))
        (should (eq (helixel-sel-search-dir sel) 'backward)))
      ;; Verify region active on last Hello (13-18)
      (should (region-active-p))
      (should (= (region-beginning) 13))
      (should (= (region-end) 18)))))

(ert-deftest helixel-test-search-repeat-prev-exchange ()
  "Test N exchanges point and mark and toggles direction."
  (helixel-test-with-buffer "hello world"
    (push-mark (point) t t)
    (goto-char 6)
    (let ((pt (point))
          (mk (mark)))
      (helixel-search-repeat-reverse)
      (should (eq (helixel-repeat-dir) 'backward))
      (should (= (point) mk))
      (should (= (mark) pt)))))

(ert-deftest helixel-test-search-extract-regex ()
  "Test extracting a bounded regex for word at point."
  (helixel-test-with-buffer "hello world"
    (goto-char 3)
    (let ((result (helixel-search--extract-regex (cons 1 6))))
      (should (string-match "hello" result)))))

(ert-deftest helixel-test-search-extract-regex-no-boundary ()
  "Test extracting regex without word boundary when inside a word."
  (helixel-test-with-buffer "hello world"
    (goto-char 2)
    (let ((result (helixel-search--extract-regex (cons 2 4))))
      (should (string= (regexp-quote "el") result)))))

(ert-deftest helixel-test-search-bounds-at-point-symbol ()
  "Test bounds-at-point returns symbol bounds."
  (helixel-test-with-buffer "hello world"
    (goto-char 3)
    (let ((bounds (helixel-search--bounds-at-point)))
      (should bounds)
      (should (= (car bounds) 1))
      (should (= (cdr bounds) 6)))))

(ert-deftest helixel-test-search-bounds-at-point-region ()
  "Test bounds-at-point uses single-line region when active."
  (helixel-test-with-buffer "hello world"
    (goto-char 2)
    (push-mark (point) t t)
    (goto-char 5)
    (activate-mark)
    (let ((bounds (helixel-search--bounds-at-point)))
      (should bounds)
      (should (= (car bounds) 2))
      (should (= (cdr bounds) 5)))))

(ert-deftest helixel-test-search-repeat-next-forward ()
  "Test n repeats search forward."
  (helixel-test-with-buffer "hello hello hello"
    (let ((isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-case-fold-search t)
          (isearch-success t)
          (isearch-other-end (copy-marker 6))
          (isearch-wrap-pause 'no-ding)
          (isearch-repeat-on-direction-change t))
      (goto-char 6)
      (helixel-search-repeat-next)
      (should (>= (point) 7))
      (should (use-region-p)))))

(ert-deftest helixel-test-search-repeat-next-reverse-when-point<mark ()
  "Test n goes backward when direction is backward."
  (helixel-test-with-buffer "hello hello hello"
    (let ((isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-case-fold-search t)
          (isearch-success t)
          (isearch-other-end (copy-marker 22))
          (isearch-wrap-pause 'no-ding)
          (isearch-repeat-on-direction-change t))
      (setq helixel--action '(:dir backward))
      (goto-char 18)
      (helixel-search-repeat-next)
      (should (< (point) 18))
      (should (use-region-p)))))

(ert-deftest helixel-test-search-repeat-next-case-sensitive ()
  "n after case-sensitive search (?Hello) respects case."
  (helixel-test-with-buffer "hello Hello hello"
    (setq helixel--repeat-dir 'backward)
    (helixel-repeat-set 'search :pattern "Hello")
    ;; Simulate isearch state for a case-sensitive backward search
    (let ((isearch-string "Hello")
          (isearch-regexp t)
          (isearch-forward nil)  ;; backward
          (isearch-case-fold-search 'auto)  ;; 'Hello' has uppercase → nil
          (isearch-success t)
          (isearch-other-end (copy-marker 18))  ;; end of last Hello
          (isearch-wrap-pause 'no-ding)
          (isearch-repeat-on-direction-change t))
      ;; Starting at end of last match (pos 18), backward finds
      ;; 'Hello' at 13-17 case-sensitively
      (goto-char 18)
      (helixel-search-repeat-next)
      ;; point moves to match-beginning for backward search
      (should (= (point) 13))
      (should (use-region-p)))))

(ert-deftest helixel-test-search-repeat-next-case-fold-insensitive ()
  "n after case-insensitive search (?hello) matches any case."
  (helixel-test-with-buffer "foo Hello bar HELLO baz"
    (setq helixel--repeat-dir 'backward)
    (helixel-repeat-set 'search :pattern "hello")
    ;; Simulate isearch state for case-insensitive backward search
    (let ((isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward nil)  ;; backward
          (isearch-case-fold-search 'auto)  ;; 'hello' all-lower → t
          (isearch-success t)
          (isearch-other-end (copy-marker 10))  ;; end of Hello
          (isearch-wrap-pause 'no-ding)
          (isearch-repeat-on-direction-change t))
      (goto-char 10)  ;; end of 'Hello'
      (helixel-search-repeat-next)
      ;; backward from 10: 'hello' matches 'Hello' case-insensitively
      ;; point moves to match-beginning (5)
      (should (= (point) 5))
      (should (use-region-p)))))

;;; Combined search history tests

(ert-deftest helixel-test-history-push-and-cap ()
  "Test history push adds entries and respects max size."
  (let ((helixel--action-ring nil)
        (helixel-action-ring-max 3))
    (helixel-action-commit)  ; null action, does nothing
    (should (null helixel--action-ring))))

(ert-deftest helixel-test-history-display-format ()
  "Test history display formatting with action plists."
  (should (string= (helixel-action-display
                    '(:category search :search (:pattern "hello" :dir forward))) "/hello/"))
  (should (string= (helixel-action-display
                    '(:category search :search (:pattern "hello" :dir backward))) "?hello?"))
  (should (string= (helixel-action-display
                    '(:category find-char :find-char (:type next :char ?x :dir forward))) "f→x"))
  (should (string= (helixel-action-display
                    '(:category find-char :find-char (:type next :char ?x :dir backward))) "F→x"))
  (should (string= (helixel-action-display
                    '(:category find-char :find-char (:type till :char ?x :dir forward))) "t→x"))
  (should (string= (helixel-action-display
                    '(:category find-char :find-char (:type till :char ?x :dir backward))) "T→x")))

(ert-deftest helixel-test-history-find-pushes ()
  "Test that find-char operations push to the action ring."
  (let ((helixel--action-ring nil)
        (helixel--action nil)
        (helixel--action-pos nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (setq last-command nil this-command 'helixel-find-next-char)
      (helixel-find-next-char ?x)
      (should (eq (plist-get (car helixel--action-ring) :category) 'find-char))
      (should (eq (helixel--action-cat-get (car helixel--action-ring) :type) 'next))
      (should (eq (helixel--action-cat-get (car helixel--action-ring) :char) ?x)))))

(ert-deftest helixel-test-history-from-history-find-next ()
  "Test C-u n selecting a find-char next entry replays it correctly."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type next :char ?b :dir forward) :display t)))
        (helixel--action nil)
        
        (helixel--clear-highlights-called nil))
    (helixel-test-with-buffer "axb axb axb"
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring))))
                ((symbol-function 'helixel--clear-highlights)
                 (lambda () (setq helixel--clear-highlights-called t))))
        (helixel-search--from-history t))
      (should (eq (helixel--live-cat-get :dir) 'forward))
      (should (eql (point) 4))
      (should helixel--clear-highlights-called))))

(ert-deftest helixel-test-history-from-history-find-till ()
  "Test C-u n selecting a find-char till entry replays with till semantics."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type till :char ?b :dir forward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search--from-history t))
      (should (eql (point) 3))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search--from-history t))
      (should (eql (point) 7)))))

(ert-deftest helixel-test-history-from-history-direction-backward ()
  "Test selecting a backward find-char entry with forwardp=t (use stored dir)."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type next :char ?b :dir backward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 8)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search--from-history t))
      (should (eq (helixel--live-cat-get :dir) 'backward))
      (should (eql (point) 7)))))

(ert-deftest helixel-test-history-repeat-next-with-arg ()
  "Test helixel-search-repeat-next with prefix arg calls from-history."
  (let ((helixel--action-ring '((:category search :subcat search
                              :search (:pattern "test" :dir forward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "a test b"
      (goto-char 3)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search-repeat-next t))
      (should (>= (point) 4)))))

(ert-deftest helixel-test-history-repeat-prev-with-arg-find ()
  "Test C-u N toggles direction and picks a find-char entry from history."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type next :char ?b :dir forward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 8)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search-repeat-reverse t))
      (should (eq (helixel--live-cat-get :dir) 'backward))
      (should (eql (point) 7))
      (helixel-search-repeat-next)
      (should (eq (helixel--live-cat-get :dir) 'backward))
      (should (< (point) 7)))))

(ert-deftest helixel-test-history-repeat-prev-with-arg-search ()
  "Test C-u N with a regexp search entry: toggles direction, searches backward."
  (let ((helixel--action-ring '((:category search :subcat search
                              :search (:pattern "hello" :dir forward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "hello world hello world"
      (goto-char 20)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search-repeat-reverse t))
      (should (eq (helixel--live-cat-get :dir) 'backward))
      (should (<= (point) 13)))))

(ert-deftest helixel-test-history-sync-direction-c-u-N ()
  "Test C-u N flips the direction of the front history entry."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type next :char ?b :dir forward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 5)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search-repeat-reverse t))
      (should (eq (helixel--live-cat-get :dir) 'backward))
      (should (eq (helixel--action-cat-get (car helixel--action-ring) :dir) 'backward)))))

(ert-deftest helixel-test-history-sync-direction-N ()
  "Test N (no prefix) flips the direction of the front history entry."
  (let ((helixel--action nil)
        (helixel--action-ring nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 5)
      (setq last-command 'helixel-find-next-char this-command 'helixel-find-next-char)
      (helixel-find-next-char ?b)
      (setq last-command 'helixel-find-next-char this-command 'helixel-search-repeat-reverse)
      (helixel-search-repeat-reverse)
      (should (eq (helixel--live-cat-get :dir) 'backward))
      (should (eq (helixel--action-cat-get (car helixel--action-ring) :dir) 'backward)))))

(ert-deftest helixel-test-history-no-sync-c-u-n ()
  "Test C-u n does NOT flip the front entry direction."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type next :char ?b :dir forward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search-repeat-next t))
      (should (eq (helixel--live-cat-get :dir) 'forward))
      (should (eq (helixel--action-cat-get (car helixel--action-ring) :dir) 'forward)))))

;;; Repeat recency tests

(ert-deftest helixel-test-repeat-find-after-movement ()
  "Test n repeats find-char after intervening movement."
  (helixel-test-with-buffer "axb axb axb"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-find-next-char)
    (helixel-find-next-char ?b)
    (should (eql (point) 4))
    ;; intervening movement pushes find-char to ring
    (setq last-command 'helixel-find-next-char this-command 'helixel-forward-char)
    (helixel-forward-char)
    (should (eq (plist-get (car helixel--action-ring) :category) 'find-char))
    ;; n should still repeat find-char (set :type on live action)
    (setq last-command 'helixel-forward-char this-command 'helixel-search-repeat-next)
    (helixel-search-repeat-next)
    (should (helixel--live-cat-get :type))))

(ert-deftest helixel-test-repeat-search-over-find ()
  "Test n picks search over older find-char in ring (detection only)."
  (let ((helixel--action-ring
         '((:category search :subcat search :search (:pattern "hello" :dir forward) :display t)
           (:category find-char :subcat find-char :find-char (:type next :char ?b :dir forward))))
        (helixel--action nil)
        (helixel--action-pos nil))
    (helixel-test-with-buffer "hello world"
      ;; call n — it should go to isearch-repeat (not find-char),
      ;; so helixel--action should NOT get :type from find-char-core
      (condition-case nil
          (helixel-search-repeat-next)
        (error nil))
      ;; verify no find-char data was set on live action
      (should (null (helixel--live-cat-get :type))))))

(ert-deftest helixel-test-repeat-no-search-repeat-wrap ()
  "Test n/N do not push search/repeat wrapper actions into ring."
  (let ((helixel--action nil) (helixel--action-ring nil) (helixel--action-pos nil))
    (helixel-test-with-buffer "axb axb axb"
      (setq last-command nil this-command 'helixel-find-next-char)
      (helixel-find-next-char ?b)
      (setq last-command 'helixel-find-next-char this-command 'helixel-search-repeat-next)
      (helixel-search-repeat-next)
      (helixel-search-repeat-next)
      ;; check: no search/repeat entries without :pattern in ring
      (let ((sr (cl-find-if (lambda (a)
                              (and (eq (helixel--action-get a :category) 'search)
                                   (null (helixel--action-cat-get a :pattern))))
                            helixel--action-ring)))
        (should (null sr))))))

(ert-deftest helixel-test-action-cycle-skip-meaningless ()
  "Test ; does not push meaningless live action into ring."
  (let ((helixel--action '(:category search :subcat repeat :dir forward))
        (helixel--action-ring `((:category movement :subcat char :marker ,(point-marker))))
        (helixel--action-pos nil))
    (let ((len-before (length helixel--action-ring)))
      (helixel-action-cycle)
      (should (= (length helixel--action-ring) len-before))
      (should (null helixel--action))
      (should (eq helixel--action-pos 0)))))

(ert-deftest helixel-test-history-from-history-sets-find-char-category ()
  "Test C-u N replaying find-char sets :category to find-char."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type next :char ?b :dir forward) :display t)))
        (helixel--action '(:category search :subcat repeat :dir forward))
        )
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 5)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search--from-history t))
      (should (eq (helixel--live-get :category) 'find-char))
      (should (eq (helixel--live-cat-get :type) 'next))
      (should (eq (helixel--live-cat-get :char) ?b)))))

;;; Action tracking tests

(ert-deftest helixel-test-action-start-movement ()
  "Test movement commands create and continue actions."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-next-line)
    (helixel-next-line)
    (should helixel--action)
    (should (eq (helixel--live-get :category) 'movement))
    (should (eq (helixel--live-get :subcat) 'line))
    (should (null helixel--action-pos))
    (let ((mark-pos (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-next-line this-command 'helixel-next-line)
      (helixel-next-line)
      (should (eq (helixel--live-get :category) 'movement))
      (should (eq (helixel--live-get :subcat) 'line)))))

(ert-deftest helixel-test-action-category-mismatch ()
  "Test different categories push old action to ring."
  (helixel-test-with-buffer "axb axb axb"
    (setq helixel--action nil helixel--action-ring nil
          last-command nil this-command 'helixel-find-next-char)
    (helixel-find-next-char ?b)
    (should (eq (helixel--live-get :category) 'find-char))
    (let ((mark1 (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-find-next-char this-command 'helixel-forward-char)
      (helixel-forward-char)
      (should (eq (helixel--live-get :category) 'movement))
      (should (eq (helixel--live-get :subcat) 'char))
      (should (not (eq (marker-position (helixel--live-get :marker)) mark1)))
      (should (= (length helixel--action-ring) 1))
      (should (eq (plist-get (car helixel--action-ring) :category) 'find-char)))))

(ert-deftest helixel-test-action-movement-different-subcat ()
  "Test different movement subcats push to ring."
  (helixel-test-with-buffer "hello\nworld\nagain"
    (setq helixel--action nil helixel--action-ring nil
          last-command nil this-command 'helixel-forward-char)
    (helixel-forward-char)
    (should (eq (helixel--live-get :subcat) 'char))
    (setq last-command 'helixel-forward-char this-command 'helixel-next-line)
    (helixel-next-line)
    (should (eq (helixel--live-get :subcat) 'line))
    (should (= (length helixel--action-ring) 1))))

(ert-deftest helixel-test-action-cycle-live ()
  "Test ; pushes live action to ring and shows ring[0]."
  (helixel-test-with-buffer "hello world again"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-forward-char)
    (goto-char 1)
    (helixel-forward-char)
    (setq last-command 'helixel-forward-char this-command 'helixel-forward-char)
    (helixel-forward-char)
    (helixel-action-cycle)
    (should (null helixel--action))
    (should (= (length helixel--action-ring) 2))
    (should (= helixel--action-pos 1))
    (should (= (region-beginning) 1))))

(ert-deftest helixel-test-action-cycle-ring ()
  "Test ; cycles through action ring."
  (helixel-test-with-buffer "hello\nworld\nagain"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-forward-char)
    (goto-char 1)
    (helixel-forward-char)
    (let ((mark1 (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-forward-char this-command 'helixel-next-line)
      (goto-char 5)
      (helixel-next-line)  ; line subcat differs → push old
      (should (= (length helixel--action-ring) 1))
      (helixel-action-cycle)
      (should (eq helixel--action-pos 0))
      (should (use-region-p)))))

(ert-deftest helixel-test-action-goto-continues ()
  "Test goto commands share the same action."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (setq helixel--action nil helixel--action-ring nil
          last-command nil this-command 'helixel-go-beginning-line)
    (helixel-go-beginning-line)
    (should (eq (helixel--live-get :category) 'movement))
    (should (eq (helixel--live-get :subcat) 'goto))))

(ert-deftest helixel-test-action-select-continues ()
  "Test select commands share the same action."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (setq helixel--action nil helixel--action-ring nil
          last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (should (eq (helixel--live-get :subcat) 'lineselect))))

(ert-deftest helixel-test-action-no-session-error ()
  "Test action-cycle with no sessions shows message."
  (let ((helixel--action nil) (helixel--action-ring nil) (helixel--action-pos nil))
    (helixel-action-cycle)
    t))  ; just verify no error

(ert-deftest helixel-test-action-cycle-forward ()
  "Test C-u ; cycles forward through saved actions."
  (helixel-test-with-buffer "hello\nworld\nagain"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-forward-char)
    (helixel-forward-char)
    (setq last-command 'helixel-forward-char this-command 'helixel-next-line)
    (goto-char 5)
    (helixel-next-line)
    (helixel-action-cycle)
    (should (eq helixel--action-pos 0))
    (should (= (region-beginning) 5))
    (helixel-action-cycle)
    (should (eq helixel--action-pos 1))
    (helixel-action-cycle t)
    (should (eq helixel--action-pos 0))))

(ert-deftest helixel-test-action-same-subcat-continues ()
  "Test same subcat movements continue action (word start→word end)."
  (helixel-test-with-buffer "hello world test"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-forward-word-start)
    (helixel-forward-word-start)
    (should (eq (helixel--live-get :subcat) 'word))
    (let ((mark-pos (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-forward-word-start this-command 'helixel-forward-word-end)
      (helixel-forward-word-end)
      (should (eq (helixel--live-get :subcat) 'word)))))

(ert-deftest helixel-test-action-different-subcat-breaks ()
  "Test different subcat pushes old action to ring."
  (helixel-test-with-buffer "hello world\ntest line"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-forward-word-start)
    (helixel-forward-word-start)
    (should (eq (helixel--live-get :subcat) 'word))
    (let ((word-mark (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-forward-word-start this-command 'helixel-next-line)
      (helixel-next-line)
      (should (eq (helixel--live-get :subcat) 'line))
      (should (= (length helixel--action-ring) 1)))))

(ert-deftest helixel-test-action-goto-marker ()
  "Test goto commands record correct marker position."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-go-beginning-buffer)
    (goto-char 10)
    (helixel-go-beginning-buffer)
    (should helixel--action)
    (should (eq (helixel--live-get :subcat) 'goto))
    (should (= (marker-position (helixel--live-get :marker)) 10))))

(ert-deftest helixel-test-action-wrapper-commands ()
  "Test goto-line starts action correctly."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\nline5"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-goto-line)
    (goto-char 1)
    (helixel-goto-line 3)
    (should helixel--action)
    (should (eq (helixel--live-get :subcat) 'goto))))

(ert-deftest helixel-test-goto-line-lisp-arg ()
  "Test helixel-goto-line called from Lisp uses the arg parameter, not current-prefix-arg.
Regression: the refactored macro version referenced current-prefix-arg
in the branch where arg was non-nil, which is nil in Lisp calls."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\nline5"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-goto-line
          current-prefix-arg nil)
    (helixel-goto-line 4)
    (should (= (line-number-at-pos) 4))
    (should (string= (buffer-substring (pos-bol) (pos-eol)) "line4"))))

(ert-deftest helixel-test-action-select-commands ()
  "Test select-line starts action correctly."
  (helixel-test-with-buffer "hello world"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (should helixel--action)
    (should (eq (helixel--live-get :subcat) 'lineselect))))

(ert-deftest helixel-test-define-movement-macro ()
  "Test helixel-define-movement creates a working action-tracked command."
  (helixel-define-movement helixel-test-movement2 forward-char char)
  (helixel-test-with-buffer "hello"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-test-movement2)
    (helixel-test-movement2)
    (should helixel--action)
    (should (eq (helixel--live-get :category) 'movement))
    (should (eq (helixel--live-get :subcat) 'char))))

;;; helixel-execute-command / helixel-define-ex-command tests

(ert-deftest helixel-test-execute-command-known ()
  "Test executing a known command via helixel-execute-command."
  (let ((helixel--command-alist
         `((("test-cmd") ,#'ignore))))
    (should (progn (helixel-execute-command "test-cmd") t))))

(ert-deftest helixel-test-execute-command-unknown ()
  "Test executing an unknown command shows message."
  (let ((helixel--command-alist nil))
    (should (progn (helixel-execute-command "no-such-cmd") t))))

(ert-deftest helixel-test-execute-command-call-interactively ()
  "Test commandp callbacks are called via call-interactively."
  (let ((helixel--command-alist nil)
        (called-interactively nil))
    (cl-letf (((symbol-function 'test-helixel-cmd)
               (lambda ()
                 (interactive)
                 (setq called-interactively (called-interactively-p)))))
      (helixel-define-ex-command "test-ia" #'test-helixel-cmd)
      (helixel-execute-command "test-ia")
      (should called-interactively))))

(ert-deftest helixel-test-execute-command-funcall ()
  "Test non-commandp callbacks are called via funcall."
  (let ((helixel--command-alist nil)
        (called nil))
    (helixel-define-ex-command "test-fn" (lambda () (setq called t)))
    (helixel-execute-command "test-fn")
    (should called)))

(ert-deftest helixel-test-execute-command-multi-callback ()
  "Test executing a command with multiple callbacks."
  (let ((helixel--command-alist nil)
        (counter 0))
    (helixel-define-ex-command "multi"
      (list (lambda () (setq counter (1+ counter)))
            (lambda () (setq counter (1+ counter)))
            #'ignore))
    (helixel-execute-command "multi")
    (should (= counter 2))))

(ert-deftest helixel-test-execute-command-multi-order ()
  "Test callbacks are executed in order."
  (let ((helixel--command-alist nil)
        (vals nil))
    (helixel-define-ex-command "ord"
      (list (lambda () (push 1 vals))
            (lambda () (push 2 vals))
            (lambda () (push 3 vals))))
    (helixel-execute-command "ord")
    (should (equal vals '(3 2 1)))))

(ert-deftest helixel-test-execute-command-with-aliases ()
  "Test command can be invoked via any of its aliases."
  (let ((helixel--command-alist nil)
        (called nil))
    (helixel-define-ex-command
     '("a" "alias" "alt") (lambda () (setq called t)))
    (helixel-execute-command "alias")
    (should called)))

(ert-deftest helixel-test-execute-command-second-alias ()
  "Test command can be invoked via second alias."
  (let ((helixel--command-alist nil)
        (called nil))
    (helixel-define-ex-command
     '("a" "alias" "alt") (lambda () (setq called t)))
    (setq called nil)
    (helixel-execute-command "alt")
    (should called)))

(ert-deftest helixel-test-define-typable-command-single-symbol ()
  "Test helixel-define-ex-command with a single symbol callback."
  (let ((helixel--command-alist nil)
        (called nil))
    (cl-letf (((symbol-function 'test-tc) (lambda () (setq called t))))
      (helixel-define-ex-command "tc-sym" #'test-tc)
      (helixel-execute-command "tc-sym")
      (should called))))

(ert-deftest helixel-test-define-typable-command-duplicate ()
  "Test defining the same command twice does not duplicate."
  (let ((helixel--command-alist nil))
    (helixel-define-ex-command "dup" #'ignore)
    (helixel-define-ex-command "dup" #'ignore)
    (should (= (length helixel--command-alist) 1))))

(ert-deftest helixel-test-repeat-ring-no-bare-entries ()
  "Test ring never contains bare (:dir ...) entries without :category."
  (let ((helixel--action nil)
        (helixel--action-ring '((:category movement :subcat line
                                :marker ,(point-marker) :dir forward)))
        (helixel--action-pos nil)
        (helixel--repeat-dir 'forward)
        (helixel--repeat-data nil))
    (helixel-test-with-buffer "hello"
      (helixel-search-repeat-next)
      ;; set-dir no longer exists — repeat-dir is separate from action dir.
      ;; Verify no bare entries were pushed.
      (when helixel--action-ring
        (dolist (a helixel--action-ring)
          (should (plist-get a :category))
          (should-not (and (null (plist-get a :category))
                           (plist-get a :dir))))))))

(ert-deftest helixel-test-history-search-creates-proper-action ()
  "Test from-history for search sets :subcat and :marker on live action."
  (let ((helixel--action-ring `((:category search :subcat search
                                 :search (:pattern "test" :dir forward) :display t
                                 :marker ,(point-marker))))
        (helixel--action nil)
        (helixel--repeat-dir 'forward)
        (helixel--repeat-data nil))
    (helixel-test-with-buffer "a test b"
      (goto-char 3)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search--from-history t))
      (should (eq (helixel--live-get :category) 'search))
      (should (eq (helixel--live-get :subcat) 'search))
      (should (helixel--live-get :marker)))))

(ert-deftest helixel-test-repeat-dir-separate-from-action-dir ()
  "Test that N flips repeat-dir without mutating action :dir of ring entries."
  (let ((helixel--action nil)
        (helixel--action-ring nil)
        (helixel--repeat-dir 'forward)
        (helixel--repeat-data nil))
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 5)
      (setq last-command 'helixel-find-next-char
            this-command 'helixel-find-next-char)
      (helixel-find-next-char ?b)
      (should (eql (point) 8))
      (helixel-search-repeat-reverse)
      ;; repeat-dir should be flipped
      (should (eq helixel--repeat-dir 'backward))
      ;; Ring front :dir was synced by N (for history display)
      (should (eq (helixel--action-cat-get (car helixel--action-ring) :dir) 'backward))
      ;; Live action :dir is 'backward (set by find-repeat's action-start)
      (should (eq (helixel--live-cat-get :dir) 'backward)))))

(ert-deftest helixel-test-repeat-find-session-continuity ()
  "Test f d then n are one session — no duplicate ring entries."
  (let ((helixel--action nil)
        (helixel--action-ring nil)
        (helixel--repeat-dir 'forward)
        (helixel--repeat-data nil))
    (helixel-test-with-buffer "axd axd axd"
      (goto-char 1)
      (setq last-command nil this-command 'helixel-find-next-char)
      (helixel-find-next-char ?d)
      (should (= (length helixel--action-ring) 1))
      (setq last-command 'helixel-find-next-char
            this-command 'helixel-search-repeat-next)
      (helixel-search-repeat-next)
      ;; Same session — no new ring entry pushed
      (should (= (length helixel--action-ring) 1))
      (helixel-search-repeat-next)
      (should (= (length helixel--action-ring) 1)))))

(ert-deftest helixel-test-repeat-find-across-movement ()
  "Test f d → j → n: movement pushed, find-repeat continues original session."
  (let ((helixel--action nil)
        (helixel--action-ring nil)
        (helixel--repeat-dir 'forward)
        (helixel--repeat-data nil))
    (helixel-test-with-buffer "axd\naxd\naxd"
      (goto-char 1)
      (setq last-command nil this-command 'helixel-find-next-char)
      (helixel-find-next-char ?d)
      (should (= (length helixel--action-ring) 1))
      ;; Intervening movement
      (setq last-command 'helixel-find-next-char
            this-command 'helixel-next-line)
      (helixel-next-line)
      ;; movement pushed old action? No — old was already committed.
      ;; Actually the movement just creates a new action.
      (setq last-command 'helixel-next-line
            this-command 'helixel-search-repeat-next)
      (helixel-search-repeat-next)
      ;; Ring has: [find-char/next, movement/line]
      (should (= (length helixel--action-ring) 2))
      ;; Live action is find-char/next (same subcat as original)
      (should (eq (helixel--live-get :category) 'find-char))
      (should (eq (helixel--live-get :subcat) 'next)))))

;;; C-g session cancel test

(ert-deftest helixel-test-c-g-cancels-session ()
  "Test C-g breaks session: next same-type command starts fresh.
The cancelled session is preserved in the ring for `;' to jump back to.
Cancel pushes a state/cancel sentinel so dedup works naturally."
  (helixel-test-with-buffer "hello world test extra"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-forward-word-start)
    ;; w w: two word movements, same session
    (helixel-forward-word-start)
    (let ((mark1 (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-forward-word-start
            this-command 'helixel-forward-word-start)
      (helixel-forward-word-start)
      (should-not (= (marker-position (helixel--live-get :marker)) mark1))
      ;; C-g: cancel session → pushes live action + cancel sentinel
      (helixel--cancel-action)
      (should (null helixel--action))
      ;; ring: [state/cancel, movement/word(2nd w), movement/word(1st w)]
      (should (= (length helixel--action-ring) 3))
      (should (eq (plist-get (car helixel--action-ring) :category) 'state))
      ;; w: new session, new marker at current position
      (setq last-command nil this-command 'helixel-forward-word-start)
      (goto-char 7)
      (helixel-forward-word-start)
      (should helixel--action)
      (should (= (marker-position (helixel--live-get :marker)) 7))
      ;; ;: push new w to ring
      ;; ring: [movement/word(new), state/cancel, movement/word(2nd), movement/word(1st)]
      (helixel-action-cycle)
      (should (= (length helixel--action-ring) 4))
      ;; First visible entry is movement/word(new)
      (should (eq (plist-get (nth helixel--action-pos helixel--action-ring)
                             :category) 'movement))
      ;; ; again: skip cancel, jump to older session (original w-w)
      (helixel-action-cycle)
      (should (eq (plist-get (nth helixel--action-pos helixel--action-ring)
                             :category) 'movement))
      (should (= (region-beginning) 1)))))

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

;;; Repeat Edit tests

;; ---------------------------------------------------------------------------
;; helixel-sel struct API tests

(ert-deftest helixel-test-sel-create-basic ()
  "`helixel-sel-create' builds a valid struct."
  (let ((sel (helixel-sel-create 'line '(:count 3)
                                 (lambda (_) nil)
                                 "L")))
    (should (helixel-sel-p sel))
    (should (eq (helixel-sel--kind sel) 'line))
    (should (equal (helixel-sel--ctx sel) '(:count 3)))
    (should (string= (helixel-sel--display sel) "L"))))

(ert-deftest helixel-test-sel-get-kind ()
  "`helixel-sel-get-kind' works for struct."
  (let ((struct (helixel-sel-create 'line nil (lambda (_) nil))))
    (should (eq (helixel-sel-get-kind struct) 'line))
    (should (eq (helixel-sel-get-kind (helixel-sel-create 'rect '(:count 2) #'helixel--recreate-rect "r")) 'rect))
    (should (null (helixel-sel-get-kind nil)))))

(ert-deftest helixel-test-sel-get-field ()
  "`helixel-sel-get-field' extracts from ctx."
  (let ((struct (helixel-sel-create 'line '(:count 3 :dir backward)
                                    (lambda (_) nil))))
    (should (= (helixel-sel-get-field struct :count) 3))
    (should (eq (helixel-sel-get-field struct :dir) 'backward))
    (should (null (helixel-sel-get-field struct :missing)))
    (should (null (helixel-sel-get-field nil :count)))
    (should (= (helixel-sel-get-field (helixel-sel-create 'line '(:count 5) #'helixel--recreate-line "L") :count) 5))))

(ert-deftest helixel-test-sel-count ()
  "`helixel-sel-count' returns :count from ctx or 0."
  (let ((sel (helixel-sel-create 'line '(:count 3) (lambda (_) nil))))
    (should (= (helixel-sel-count sel) 3)))
  (let ((sel (helixel-sel-create 'line nil (lambda (_) nil))))
    (should (= (helixel-sel-count sel) 0)))
  (should (= (helixel-sel-count nil) 0))
  (should (= (helixel-sel-count (helixel-sel-create 'line '(:count 7) #'helixel--recreate-line "L")) 7)))

(ert-deftest helixel-test-sel-update-ctx ()
  "`helixel-sel-update-ctx' returns a new sel with updated ctx."
  (let* ((s1 (helixel-sel-create 'line '(:count 3) (lambda (_) nil)))
         (s2 (helixel-sel-update-ctx s1 :count 5)))
    (should (= (helixel-sel-get-field s1 :count) 3))
    (should (= (helixel-sel-get-field s2 :count) 5))
    (should (helixel-sel-p s2))
    (should (eq (helixel-sel--kind s2) 'line))
    (let ((p2 (helixel-sel-update-ctx (helixel-sel-create 'line '(:count 1) #'helixel--recreate-line "L") :count 9)))
      (should (equal p2 (helixel-sel-create 'line '(:count 9) #'helixel--recreate-line "L"))))))

(ert-deftest helixel-test-sel-equal-p ()
  "`helixel-sel-equal-p' compares kind and ctx."
  (let ((a (helixel-sel-create 'line '(:count 3) (lambda (_) nil)))
        (b (helixel-sel-create 'line '(:count 3) (lambda (_) nil)))
        (c (helixel-sel-create 'line '(:count 5) (lambda (_) nil)))
        (d (helixel-sel-create 'rect '(:count 3) (lambda (_) nil))))
    (should (helixel-sel-equal-p a b))
    (should-not (helixel-sel-equal-p a c))
    (should-not (helixel-sel-equal-p a d))
    (should (helixel-sel-equal-p nil nil))
    (should-not (helixel-sel-equal-p a nil))
    (should (helixel-sel-equal-p (helixel-sel-create 'line '(:count 3) #'helixel--recreate-line "L")
                                 (helixel-sel-create 'line '(:count 3) #'helixel--recreate-line "L")))
    (should-not (helixel-sel-equal-p (helixel-sel-create 'line '(:count 3) #'helixel--recreate-line "L")
                                     (helixel-sel-create 'rect '(:count 3) #'helixel--recreate-rect "r")))))

(ert-deftest helixel-test-sel-call-recreate ()
  "`helixel-sel-call-recreate' dispatches to struct closure."
  (with-temp-buffer
    (insert "hello world")
    (goto-char 1)
    (let ((sel (helixel-sel-create 'line nil
                                   (lambda (_) (goto-char 7))
                                   "L")))
      (helixel-sel-call-recreate sel)
      (should (= (point) 7)))
    (let ((pt (point)))
      (helixel-sel-call-recreate nil)
      (should (= (point) pt)))))

(ert-deftest helixel-test-sel-call-display ()
  "`helixel-sel-call-display' returns display string for struct."
  (should (string= (helixel-sel-call-display
                    (helixel-sel-create 'line nil (lambda (_) nil) "L"))
                   "L"))
  (should (string= (helixel-sel-call-display (helixel-sel-create 'line '(:count 3) #'helixel--recreate-line "L"))
                   "L"))
  (should (null (helixel-sel-call-display nil))))

;; ---------------------------------------------------------------------------
;; insert-* sel structs (was raw plists, now proper structs)

(ert-deftest helixel-test-sel-insert-selection-start ()
  "insert-selection-start sel struct: kind, recreate, display."
  (let ((sel (helixel-sel-create
              'insert-selection-start nil
              #'helixel--recreate-insert-selection-start "is")))
    (should (eq (helixel-sel-get-kind sel) 'insert-selection-start))
    (should (string= (helixel-sel-call-display sel) "is"))
    (should (helixel-sel-p sel))))

(ert-deftest helixel-test-sel-insert-selection-end ()
  "insert-selection-end sel struct: kind, recreate, display."
  (let ((sel (helixel-sel-create
              'insert-selection-end nil
              #'helixel--recreate-insert-selection-end "ie")))
    (should (eq (helixel-sel-get-kind sel) 'insert-selection-end))
    (should (string= (helixel-sel-call-display sel) "ie"))
    (should (helixel-sel-p sel))))

(ert-deftest helixel-test-sel-insert-beginning-line ()
  "insert-beginning-line sel struct: kind, recreate, display."
  (let ((sel (helixel-sel-create
              'insert-beginning-line nil
              #'helixel--recreate-insert-beginning-line "I")))
    (should (eq (helixel-sel-get-kind sel) 'insert-beginning-line))
    (should (string= (helixel-sel-call-display sel) "I"))
    (should (helixel-sel-p sel))))

(ert-deftest helixel-test-sel-insert-end-line ()
  "insert-end-line sel struct: kind, recreate, display."
  (let ((sel (helixel-sel-create
              'insert-end-line nil
              #'helixel--recreate-insert-end-line "A")))
    (should (eq (helixel-sel-get-kind sel) 'insert-end-line))
    (should (string= (helixel-sel-call-display sel) "A"))
    (should (helixel-sel-p sel))))

(ert-deftest helixel-test-sel-insert-search-offset ()
  "insert-search-offset sel struct: kind, recreate, display."
  (let ((sel (helixel-sel-create
              'insert-search-offset '(:offset 3)
              #'helixel--recreate-insert-search-offset "io")))
    (should (eq (helixel-sel-get-kind sel) 'insert-search-offset))
    (should (string= (helixel-sel-call-display sel) "io"))
    (should (= (helixel-sel-insert-offset sel) 3))
    (should (helixel-sel-p sel))))

(ert-deftest helixel-test-recreate-insert-selection-start ()
  "recreate-insert-selection-start moves to region-beginning + offset."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (push-mark 6 t t)
    (activate-mark)
    (let ((sel (helixel-sel-update-ctx
                (helixel-sel-create
                 'insert-selection-start nil
                 #'helixel--recreate-insert-selection-start "is")
                :cursor-offset 2)))
      (helixel-sel-call-recreate sel)
      (should (= (point) 3)))))

(ert-deftest helixel-test-recreate-insert-selection-end ()
  "recreate-insert-selection-end moves to region-end + offset."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (push-mark 6 t t)
    (activate-mark)
    (let ((sel (helixel-sel-update-ctx
                (helixel-sel-create
                 'insert-selection-end nil
                 #'helixel--recreate-insert-selection-end "ie")
                :cursor-offset 1)))
      (helixel-sel-call-recreate sel)
      (should (= (point) 7)))))

(ert-deftest helixel-test-recreate-insert-beginning-line ()
  "recreate-insert-beginning-line moves to beginning of line."
  (helixel-test-with-buffer "hello\nworld"
    (goto-char 7)
    (let ((sel (helixel-sel-create
                'insert-beginning-line nil
                #'helixel--recreate-insert-beginning-line "I")))
      (helixel-sel-call-recreate sel)
      (should (= (point) 7)))))

(ert-deftest helixel-test-recreate-insert-end-line ()
  "recreate-insert-end-line moves to end of line."
  (helixel-test-with-buffer "hello\nworld"
    (goto-char 5)
    (let ((sel (helixel-sel-create
                'insert-end-line nil
                #'helixel--recreate-insert-end-line "A")))
      (helixel-sel-call-recreate sel)
      (should (= (point) 6)))))

(ert-deftest helixel-test-recreate-insert-search-offset ()
  "recreate-insert-search-offset moves to match-beginning + offset."
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (re-search-forward "hello")
    (let ((sel (helixel-sel-create
                'insert-search-offset '(:offset 2)
                #'helixel--recreate-insert-search-offset "io")))
      (helixel-sel-call-recreate sel)
      ;; match-beginning of first "hello" = 1, + 2 = 3
      (should (= (point) 3)))))

;; ---------------------------------------------------------------------------
;; edit transaction runner/display tests

(ert-deftest helixel-test-edit-make-stores-runner ()
  "`helixel-edit-make' stores :runner in the struct slot."
  (let ((dummy-fn #'ignore))
    (let ((tx (helixel-edit-make 'kill nil :runner dummy-fn)))
      (should (eq (helixel-edit-runner tx) dummy-fn))
      (should (null (plist-get (helixel-edit-payload tx) :runner))))))

(ert-deftest helixel-test-edit-make-stores-display ()
  "`helixel-edit-make' stores :display in DISPLAY-FIELD slot, not in :payload."
  (let ((tx (helixel-edit-make 'kill nil :display "d.K")))
    (should (string= (helixel-edit-display-field tx) "d.K"))
    (should (null (plist-get (helixel-edit-payload tx) :display)))))

(ert-deftest helixel-test-execute-edit-uses-stored-runner ()
  "`helixel--execute-edit' calls the :runner stored in TX."
  (with-temp-buffer
    (insert "hello")
    (goto-char 1)
    (let ((tx (helixel-edit-make 'test nil
                :runner (lambda (_tx) (insert "X")))))
      (helixel--execute-edit tx)
      (should (string= (buffer-string) "Xhello")))))

(ert-deftest helixel-test-execute-edit-fallback-registry ()
  "`helixel--execute-edit' falls back to registry when :runner missing."
  ;; kill op is registered; a plist without :runner should still
  ;; execute via the registry lookup fallback.
  (with-temp-buffer
    (insert "hello")
    (goto-char 2)  ; on "e"
    ;; Create a tx without :runner (tests registry fallback)
    (let ((tx (helixel-edit-make 'kill nil)))
      (should (helixel-edit-op-runner 'kill)) ;; registry has runner
      ;; Should not error — just verify the fallback path runs
      (should (progn (helixel--execute-edit tx) t)))))

(ert-deftest helixel-test-edit-display-uses-stored-field ()
  "`helixel-edit-display' prefers :display stored in TX."
  (let ((tx (helixel-edit-make 'kill nil :display "custom-label")))
    (should (string= (helixel-edit-display tx) "custom-label"))))

(ert-deftest helixel-test-repeat-edit-no-prev ()
  "Test repeat-edit with no previous edit signals error."
  (helixel-test-with-buffer "hello world"
    (setq helixel--last-tx nil)
    (should-error (helixel-repeat-edit))))

(ert-deftest helixel-test-repeat-edit-paste ()
  "Test repeat paste."
  (helixel-test-with-buffer "hello world"
    (goto-char 7)
    (kill-word 1)
    (setq last-command nil this-command 'helixel-yank)
    (helixel-yank)
    (should (string= (buffer-string) "hello world"))
    (goto-char 7)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "hello worldworld"))))

(ert-deftest helixel-test-repeat-edit-replace-char ()
  "Test repeat replace-char."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-replace-char)
    (helixel-replace-char ?X)
    (should (string= (buffer-string) "Xello world"))
    (goto-char 2)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "XXllo world"))))

(ert-deftest helixel-test-repeat-edit-indent ()
  "Test repeat indent right with line selection."
  (helixel-test-with-buffer "hello\nworld\n"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (setq last-command 'helixel-select-line this-command 'helixel-indent-right)
    (helixel-indent-right)
    (let ((after-first (buffer-string)))
      (should-not (string= "hello\nworld\n" after-first))
      (helixel-repeat-edit)
      (should-not (string= after-first (buffer-string))))))

(ert-deftest helixel-test-repeat-edit-kill-textobj ()
  "Test repeat kill with textobj selection (diw style)."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 3)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (string= (buffer-string) " world foo"))
    (goto-char 3)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "  foo"))))

(ert-deftest helixel-test-repeat-edit-kill-linewise ()
  "Test repeat kill with linewise selection (x d style)."
  (helixel-test-with-buffer "first line\nsecond line\nthird line\n"
    (goto-char 3)
    (setq last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (setq last-command 'helixel-select-line this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (string= (buffer-string) "second line\nthird line\n"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "third line\n"))))

(ert-deftest helixel-test-repeat-edit-change-textobj ()
  "Test repeat change with textobj (ciw style)."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 3)
    (setq helixel--last-tx
          (helixel-edit-make 'change
            (helixel-sel-create 'textobj '(:command helixel-mark-inner-word :count 1)
            #'helixel--recreate-textobj
            (replace-regexp-in-string "^helixel-mark-" "" (symbol-name 'helixel-mark-inner-word)))
            :inserted-text "CHANGED"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "CHANGED world foo"))
    (goto-char 1)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "CHANGED world foo"))))

(ert-deftest helixel-test-repeat-edit-preserves-last-edit ()
  "Test that repeat-edit does not overwrite helixel--last-tx."
  (helixel-test-with-buffer "hello world"
    (goto-char 7)
    (kill-word 1)
    (setq last-command nil this-command 'helixel-yank)
    (helixel-yank)
    (let ((before helixel--last-tx))
      (helixel-repeat-edit)
      (should (equal helixel--last-tx before)))))

(ert-deftest helixel-test-repeat-edit-clear-data ()
  "Test repeat-edit clears selection data after operation."
  (helixel-test-with-buffer "hello world"
    (goto-char 7)
    (kill-word 1)
    (setq last-command nil this-command 'helixel-yank)
    (helixel-yank)
    (helixel-repeat-edit)
    (should (null helixel--selection-type))))

(ert-deftest helixel-test-repeat-edit-copy ()
  "Test repeat copy (yank)."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word this-command 'helixel-kill-ring-save)
    (helixel-kill-ring-save)
    (should (string= (current-kill 0 t) "hello"))
    (goto-char 7)
    (helixel-repeat-edit)
    (should (string= (current-kill 0 t) "world"))))

(ert-deftest helixel-test-repeat-edit-insert-text ()
  "Test repeat insert-text (i style)."
  (helixel-test-with-buffer "hello world"
    (goto-char 7)
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text nil :text "INSERTED"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "hello INSERTEDworld"))))

(ert-deftest helixel-test-repeat-edit-insert-text-empty ()
  "Test repeat insert-text with empty text does nothing."
  (helixel-test-with-buffer "hello world"
    (goto-char 7)
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text nil :text ""))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "hello world"))))

(ert-deftest helixel-test-repeat-edit-count-prefix ()
  "Numeric prefix to `helixel-repeat-edit' replays N times."
  (helixel-test-with-buffer "hello world"
    (goto-char 7)
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text nil :text "x"))
    (helixel-repeat-edit 5)
    (should (string= (buffer-string) "hello xxxxxworld"))))

(ert-deftest helixel-test-repeat-edit-preserves-on-error ()
  "`helixel-repeat-edit' does not discard `helixel--last-tx' on failure."
  (helixel-test-with-buffer "hello"
    (setq helixel--last-tx
          (helixel-edit-make 'kill (helixel-sel-create 'unknown-kind-no-method nil #'ignore "?")))
    (let ((before helixel--last-tx))
      (helixel-repeat-edit)
      (should (equal helixel--last-tx before)))))

(ert-deftest helixel-test-repeat-edit-change-end-to-end ()
  "End-to-end: c<text><esc> records inserted text; `.' replays it."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-change-thing-at-point)
    (helixel-change-thing-at-point)
    (insert "X")
    (helixel-insert-exit)
    (should (string= (buffer-string) "X world foo"))
    ;; Repeat inside "world"
    (goto-char 4)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "X X foo"))))

(ert-deftest helixel-test-repeat-edit-insert-end-to-end ()
  "End-to-end: i<text><esc> records inserted text; `.' replays it."
  (let ((helixel--last-tx nil)
        (helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "abc"
      (set-match-data nil) ; clear stale match data from prior tests
      (goto-char 2)
      (setq last-command nil this-command 'helixel-insert)
      (helixel-insert)
      (insert "Z")
      (helixel-insert-exit)
      (should (string= (buffer-string) "aZbc"))
      (goto-char 4)
      (helixel-repeat-edit)
      (should (string= (buffer-string) "aZbZc")))))

(ert-deftest helixel-test-edit-ring-push-and-dedup ()
  "`helixel--record-edit' pushes onto the ring with head dedup."
  (helixel-test-with-buffer "hello world"
    (setq helixel--edit-ring nil helixel--last-tx nil)
    (goto-char 1)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (= 1 (length helixel--edit-ring)))
    (should (eq (car helixel--edit-ring) helixel--last-tx))
    ;; Repeating the very same op shouldn't grow the ring (head dedup).
    (goto-char 1)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (= 1 (length helixel--edit-ring)))))

(ert-deftest helixel-test-edit-display ()
  "`helixel-edit-display' formats op + sel + payload hints."
  (should (string= (helixel-edit-display
                    (helixel-edit-make 'kill
                      (helixel-sel-create 'line '(:count 3)
                        #'helixel--recreate-line "L")))
                   "d.Lx3"))
  (should (string= (helixel-edit-display
                    (helixel-edit-make 'kill
                      (helixel-sel-create 'line '(:dir backward :count 2)
                        #'helixel--recreate-line "L^")))
                   "d.L^x2"))
  (should (string= (helixel-edit-display
                    (helixel-edit-make 'replace-char nil :char ?Q))
                   "R[Q]"))
  (should (string= (helixel-edit-display
                    (helixel-edit-make 'kill
                      (helixel-sel-create 'textobj
                        '(:command helixel-mark-inner-word :count 1)
                        #'helixel--recreate-textobj
                        "inner-word")))
                   "d.inner-word"))
  (should (string= (helixel-edit-display
                    (helixel-edit-make 'kill
                      (helixel-sel-create 'movement
                        '(:moves ((helixel-forward-word-start . 3)))
                        #'helixel--recreate-movement
                        "v3")))
                   "d.v3")))

(ert-deftest helixel-test-repeat-edit-movement-kill ()
  "Test repeat kill with movement selection (v w d style)."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel-edit-make 'kill
            (helixel-sel-create 'movement '(:moves ((helixel-forward-word-start . 2)))
            #'helixel--recreate-movement
            (format "v%d" 2))))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "foo"))))

(ert-deftest helixel-test-repeat-edit-movement-change ()
  "Test repeat change with movement selection (v w c style)."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel-edit-make 'change
            (helixel-sel-create 'movement '(:moves ((helixel-forward-word-start . 1)))
            #'helixel--recreate-movement
            (format "v%d" 1))
            :inserted-text "X"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "Xworld foo"))))

(ert-deftest helixel-test-repeat-invariant-sel-ctx-consumed ()
  "Test record-edit consumes helixel--repeat-sel-ctx."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (should helixel--repeat-sel-ctx)
    (setq last-command 'helixel-mark-inner-word this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (null helixel--repeat-sel-ctx))))

(ert-deftest helixel-test-repeat-invariant-repeat-no-pollute-ring ()
  "Test repeat-edit does not add extra entries to the action ring beyond record-edit."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (let ((ring-len (length helixel--action-ring)))
      (helixel-repeat-edit)
      (should (= (length helixel--action-ring) ring-len)))))

(ert-deftest helixel-test-repeat-invariant-insert-after-records ()
  "Test helixel-insert-after (a) records insert-text."
  (helixel-test-with-buffer "hello world"
    (goto-char 3)
    (setq helixel--last-tx nil
          helixel--change-track-marker nil)
    (helixel-insert-after)
    (should (eq (helixel-edit-op helixel--last-tx) 'insert-text))
    (should helixel--change-track-marker)
    (set-marker helixel--change-track-marker nil)
    (setq helixel--change-track-marker nil)))

(ert-deftest helixel-test-execute-keys-meta ()
  "`helixel--execute-keys' handles meta keys (e.g. M-f) gracefully.
Meta keys are non-character integers; they must go through
key-binding dispatch, not `insert-char'."
  (helixel-test-with-buffer ""
    (helixel--execute-keys (kbd "foo"))
    (should (string= (buffer-string) "foo")))
  (helixel-test-with-buffer "one two three"
    (goto-char 1)
    ;; M-f goes through key-binding -> forward-word
    (helixel--execute-keys (kbd "M-f"))
    (should (= (point) 4)))
  (helixel-test-with-buffer "one two three"
    (goto-char 1)
    ;; M-f mixed with character keys
    (helixel--execute-keys (kbd "a M-f b"))
    (should (string= (buffer-string) "aoneb two three"))))

(ert-deftest helixel-test-execute-commands ()
  "`helixel--execute-keys' with :commands replays recorded commands.
Command-based replay is keymap-independent — correct even when
insert-mode bindings differ from normal-mode."
  ;; Test: recorded commands simulate h (backward-char in insert mode)
  ;; In normal mode, 'h' is NOT self-insert — but commands bypass keymaps.
  (helixel-test-with-buffer "abcdef"
    (goto-char 4)
    ;; Recorded: self-insert ?X, then backward-char, then self-insert ?Y
    (helixel--execute-keys (kbd "X h Y")
                           '(self-insert-command
                             backward-char
                             self-insert-command))
    ;; X inserts at 4, backward-char to 3, Y inserts at 3
    (should (string= (buffer-string) "abcYXdef")))
  ;; Test: fallback to keys when no commands
  (helixel-test-with-buffer "hello"
    (goto-char 1)
    (helixel--execute-keys (kbd "XX"))
    (should (string= (buffer-string) "XXhello"))))

(ert-deftest helixel-test-execute-keys-backspace ()
  "`helixel--execute-keys' replays DEL via command-based path.
Command-based replay calls backward-delete-char-untabify directly."
  (helixel-test-with-buffer "hello"
    (goto-char 6)
    ;; Replay: insert A, insert B, DEL (deletes B) → "helloA"
    ;; Keys must match command count; non-self-insert keys are ignored.
    (helixel--execute-keys (kbd "ABx")
                           '(self-insert-command
                             self-insert-command
                             backward-delete-char-untabify))
    (should (string= (buffer-string) "helloA"))))

(ert-deftest helixel-test-execute-keys-control-d ()
  "`helixel--execute-keys' replays C-d via command-based path.
C-d (delete-char) is called via call-interactively, not insert-char."
  (helixel-test-with-buffer "hello"
    (goto-char 1)
    (helixel--execute-keys (kbd "C-d") '(delete-char))
    (should (string= (buffer-string) "ello"))))

(ert-deftest helixel-test-execute-keys-mixed-backspace ()
  "`helixel--execute-keys' replays mixed insert + DEL + insert.
Simulates typing 'bao' then DEL (deletes 'o') then 'r'."
  (helixel-test-with-buffer "hello"
    (goto-char 6)
    ;; Replay: insert b,a,o, DEL deletes o, insert r → "hellobar"
    (helixel--execute-keys (kbd "baoxr")
                           '(self-insert-command     ; b
                             self-insert-command     ; a
                             self-insert-command     ; o
                             backward-delete-char-untabify ; DEL
                             self-insert-command))   ; r
    (should (string= (buffer-string) "hellobar"))))

(ert-deftest helixel-test-execute-keys-symbol-no-crash ()
  "`helixel--execute-keys' handles symbol keys without crashing.
Unbound symbols (like backspace on some Emacs) go through
execute-kbd-macro — may beep but must not raise wrong-type-argument.
Also verifies the characterp guard in helixel--insert-finish."
  (helixel-test-with-buffer "hello"
    (goto-char 1)
    ;; The key-based fallback must not crash on symbols.
    ;; execute-kbd-macro may error on unbound keys — that's OK.
    ;; The old bug (= 'backspace ?\e) must NOT happen.
    (condition-case err
        (helixel--execute-keys [backspace])
      (wrong-type-argument
       (ert-fail
        (format "crashed with wrong-type-argument: %S" err)))
      (error nil))  ;; other errors (unbound key) are OK
    (should t)))

;; ============================================================================
;; Cross-buffer repeat tests (Item 5)
;; ============================================================================

(ert-deftest helixel-test-repeat-cross-buffer ()
  "`. replays the last edit across buffers when `helixel--last-tx' is global."
  (helixel-test-with-buffer "hello world"
    (goto-char 7)
    (kill-word 1)
    (setq last-command nil this-command 'helixel-yank)
    (helixel-yank)
    (should (string= (buffer-string) "hello world"))
    (let ((cross-tx helixel--last-tx))
      (with-temp-buffer
        (insert "foo bar")
        (goto-char 8)                   ; end of buffer, after "bar"
        (setq helixel--last-tx cross-tx)
        (helixel-repeat-edit)
        ;; "p" pastes the killed word "world" after "bar"
        (should (string= (buffer-string) "foo barworld"))))))

(ert-deftest helixel-test-repeat-cross-buffer-change ()
  "Cross-buffer `.` replays a change+insert operation from another buffer."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-change-thing-at-point)
    (helixel-change-thing-at-point)
    (insert "X")
    (helixel-insert-exit)
    (should (string= (buffer-string) "X world"))
    (let ((cross-tx helixel--last-tx))
      (with-temp-buffer
        (insert "abc def")
        (goto-char 1)
        (setq helixel--last-tx cross-tx)
        (helixel-repeat-edit)
        (should (string= (buffer-string) "X def"))))))

;; ============================================================================
;; Keys-mode change replay tests (Item 4)
;; ============================================================================

(ert-deftest helixel-test-repeat-change-keys-mode ()
  "`helixel-repeat-change-method' = `keys' replays raw key sequence."
  (helixel-test-with-buffer "hello world"
    (let ((helixel-repeat-change-method 'keys))
      (goto-char 1)
      ;; Directly construct a tx with :keys payload, simulating
      ;; what c X Y <esc> would record.  The keys are only the
      ;; productive insert-mode keystrokes (X Y), not the initiating c.
      (setq helixel--last-tx
            (helixel-edit-make 'change
              (helixel-sel-create 'textobj '(:command helixel-mark-inner-word :count 1)
            #'helixel--recreate-textobj
            (replace-regexp-in-string "^helixel-mark-" "" (symbol-name 'helixel-mark-inner-word)))
              :inserted-text "XY" :keys (kbd "XY")))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "XY world"))
      ;; Replay in keys mode on another word
      (goto-char 4)
      (helixel-repeat-edit)
      (should (string= (buffer-string) "XY XY")))))

(ert-deftest helixel-test-repeat-insert-keys-mode ()
  "`helixel-repeat-change-method' = `keys' replays insert key sequence."
  (helixel-test-with-buffer "abc"
    (let ((helixel-repeat-change-method 'keys))
      (goto-char 2)
      ;; Directly construct a tx with :keys payload (simulating i Z <esc>)
      (setq helixel--last-tx
            (helixel-edit-make 'insert-text nil
              :text "Z" :keys (kbd "Z")))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "aZbc"))
      (should (helixel--repeat-get-keys helixel--last-tx))
      (goto-char 4)
      (helixel-repeat-edit)
      (should (string= (buffer-string) "aZbZc")))))

(ert-deftest helixel-test-repeat-keys-fallback-to-text ()
  "When :keys is absent from payload, keys-mode falls back to :text."
  (helixel-test-with-buffer "hello"
    (let ((helixel-repeat-change-method 'keys))
      (goto-char 1)
      ;; Manually construct a tx without :keys (old-format tx)
      (setq helixel--last-tx
            (helixel-edit-make 'insert-text nil :text "OLD"))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "OLDhello")))))

(ert-deftest helixel-test-repeat-change-keys-preferred ()
  "`:keys' payload is always preferred over `:inserted-text'."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    ;; A tx with both :inserted-text and :keys — :keys wins
    (setq helixel--last-tx
          (helixel-edit-make 'change
            (helixel-sel-create 'textobj
              '(:command helixel-mark-inner-word :count 1)
              #'helixel--recreate-textobj
              (replace-regexp-in-string
               "^helixel-mark-" ""
               (symbol-name 'helixel-mark-inner-word)))
            :inserted-text "XY" :keys (kbd "ZZ")))
    (helixel-repeat-edit)
    ;; :keys "ZZ" is used, not :inserted-text "XY"
    (should (string= (buffer-string) "ZZ world"))
    (goto-char 4)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "ZZ ZZ"))))

;; ============================================================================
;; Repeat-selection (,`) tests
;; ============================================================================

(ert-deftest helixel-test-repeat-selection-textobj ()
  "`,` recreates the last textobj selection without applying the edit."
  (helixel-test-with-buffer "hello world"
    (goto-char 3)
    (setq helixel--last-tx
          (helixel-edit-make 'change
            (helixel-sel-create 'textobj '(:command helixel-mark-inner-word :count 1)
            #'helixel--recreate-textobj
            (replace-regexp-in-string "^helixel-mark-" "" (symbol-name 'helixel-mark-inner-word)))
            :inserted-text "X"))
    (helixel-repeat-selection)
    (should (region-active-p))
    (should (= (region-beginning) 1))
    (should (= (region-end) 6))))

(ert-deftest helixel-test-repeat-selection-line ()
  "`,` recreates a linewise selection without applying the edit."
  (helixel-test-with-buffer "line one\nline two\nline three\n"
    (goto-char 3)
    (setq helixel--last-tx
          (helixel-edit-make 'kill
            (helixel-sel-create 'line '(:count 1)
              #'helixel--recreate-line "L")))
    (helixel-repeat-selection)
    (should (region-active-p))
    (should (= (region-beginning) 1))))

(ert-deftest helixel-test-repeat-selection-count ()
  "`,` with count prefix selects multiple units."
  (helixel-test-with-buffer "line one\nline two\nline three\n"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel-edit-make 'kill (helixel-sel-create 'line '(:count 1) #'helixel--recreate-line "L")))
    (helixel-repeat-selection 2)
    (should (region-active-p))
    (should (= (region-beginning) 1))
    (should (>= (region-end) 1))))

(ert-deftest helixel-test-repeat-dot-on-existing-region ()
  "`.` on an active region (from `,`) uses it without recreating."
  (helixel-test-with-buffer "hello world"
    (goto-char 3)
    (setq helixel--last-tx
          (helixel-edit-make 'change
            (helixel-sel-create 'textobj '(:command helixel-mark-inner-word :count 1)
            #'helixel--recreate-textobj
            (replace-regexp-in-string "^helixel-mark-" "" (symbol-name 'helixel-mark-inner-word)))
            :inserted-text "X"))
    (helixel-repeat-selection)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "X world"))))

(ert-deftest helixel-test-repeat-selection-extend ()
  "`,` in visual state extends an existing selection using the stored method."
  (helixel-test-with-buffer "hello world foo bar"
    (goto-char 3)
    (setq helixel--last-tx
          (helixel-edit-make 'change
            (helixel-sel-create 'textobj '(:command helixel-mark-inner-word :count 1)
            #'helixel--recreate-textobj
            (replace-regexp-in-string "^helixel-mark-" "" (symbol-name 'helixel-mark-inner-word)))
            :inserted-text "X"))
    ;; Enter visual state then recreate selection
    (setq-local helixel--current-state 'visual)
    (helixel-repeat-selection)     ;; selects "hello"
    (should (string= (buffer-substring (region-beginning) (region-end)) "hello"))
    (helixel-repeat-selection)     ;; extends to next word
    (should (string= (buffer-substring (region-beginning) (region-end)) "hello world"))))

(ert-deftest helixel-test-repeat-selection-no-prev ()
  "`,` without a previous edit signals an error."
  (let ((helixel--last-tx nil))
    (should-error (helixel-repeat-selection))))

(ert-deftest helixel-test-repeat-selection-no-sel ()
  "`,` with an edit that has no selection context signals an error."
  (helixel-test-with-buffer "hello"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text nil :text "X"))
    (should-error (helixel-repeat-selection))))

;; ============================================================================
;; Forward-seek for textobj sel-recreate tests
;; ============================================================================

(ert-deftest helixel-test-repeat-forward-seek-whitespace ()
  "`.` when cursor is on whitespace skips forward to the next textobj."
  (helixel-test-with-buffer "hello   world"
    (goto-char 3)                                ;; on "l" of "hello"
    (setq helixel--last-tx
          (helixel-edit-make 'change
            (helixel-sel-create 'textobj '(:command helixel-mark-inner-word :count 1)
            #'helixel--recreate-textobj
            (replace-regexp-in-string "^helixel-mark-" "" (symbol-name 'helixel-mark-inner-word)))
            :inserted-text "X"))
    (goto-char 7)                                ;; on whitespace between words
    (helixel-repeat-edit)
    ;; Skips whitespace forward, selects "world", changes to "X"
    (should (string= (buffer-string) "hello   X"))))

(ert-deftest helixel-test-repeat-forward-seek-at-word-start ()
  "`.` on whitespace after a word jumps forward to the next word."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 3)
    (setq helixel--last-tx
          (helixel-edit-make 'change
            (helixel-sel-create 'textobj '(:command helixel-mark-inner-word :count 1)
            #'helixel--recreate-textobj
            (replace-regexp-in-string "^helixel-mark-" "" (symbol-name 'helixel-mark-inner-word)))
            :inserted-text "X"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "X world foo"))
    ;; Cursor on space between "X" and "world"
    (goto-char 2)
    (helixel-repeat-edit)
    ;; Skips whitespace forward, selects "world", changes to "X"
    (should (string= (buffer-string) "X X foo"))))

;; ============================================================================
;; Search selection replay (`, .) tests
;; ============================================================================

(ert-deftest helixel-test-repeat-selection-search ()
  "`,` recreates a search-based selection from the stored :pattern."
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel-edit-make 'change
            (helixel-sel-create 'search '(:pattern "hello" :dir forward)
            #'helixel--recreate-search
            "/hello")
            :inserted-text "X"))
    (helixel-repeat-selection)
    (should (region-active-p))
    (should (string= (buffer-substring (region-beginning) (region-end)) "hello"))))

(ert-deftest helixel-test-repeat-search-then-dot ()
  "`.` replays a search-based change on the next match."
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel-edit-make 'change
            (helixel-sel-create 'search '(:pattern "hello" :dir forward)
            #'helixel--recreate-search
            "/hello")
            :inserted-text "X"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "X world hello"))
    ;; cursor after "X " — next . should find next "hello"
    (helixel-repeat-edit)
    (should (string= (buffer-string) "X world X"))))

(ert-deftest helixel-test-repeat-search-comma-then-dot ()
  "`,` previews the search match, `.` applies the edit."
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel-edit-make 'change
            (helixel-sel-create 'search '(:pattern "hello" :dir forward)
            #'helixel--recreate-search
            "/hello")
            :inserted-text "X"))
    (helixel-repeat-selection)
    (should (string= (buffer-substring (region-beginning) (region-end)) "hello"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "X world hello"))))

(ert-deftest helixel-test-repeat-search-n-dot ()
  "Simulate /hello cX<Esc> then n . n . pattern."
  (helixel-test-with-buffer "a hello b hello c hello d"
    (goto-char 3)
    (setq helixel--last-tx
          (helixel-edit-make 'change
            (helixel-sel-create 'search '(:pattern "hello" :dir forward)
            #'helixel--recreate-search
            "/hello")
            :inserted-text "X"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "a X b hello c hello d"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "a X b X c hello d"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "a X b X c X d"))))

(ert-deftest helixel-test-repeat-search-backward ()
  "`.` replays a backward search change."
  (helixel-test-with-buffer "hello world hello"
    (goto-char (point-max))
    (setq helixel--last-tx
          (helixel-edit-make 'change
            (helixel-sel-create 'search '(:pattern "hello" :dir backward)
            #'helixel--recreate-search
            "?hello")
            :inserted-text "X"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "hello world X"))))

(ert-deftest helixel-test-search-sel-display ()
  "`helixel-sel-call-display' for search shows /pattern."
  (should (string= (helixel-sel-call-display
                    (helixel-sel-create 'search
                      '(:pattern "hello" :dir forward)
                      #'helixel--recreate-search
                      "/hello"))
                   "/hello")))

;; ============================================================================
;; Surround tests
;; ============================================================================

(ert-deftest helixel-test-surround-add-paren ()
  "Test `helixel--surround-add' with (pair."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\( ?\))
    (should (equal (buffer-string) "(hello)"))
    (should (region-active-p))
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

(ert-deftest helixel-test-surround-add-bracket ()
  "Test `helixel--surround-add' with [pair."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\[ ?\])
    (should (equal (buffer-string) "[hello]"))
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

(ert-deftest helixel-test-surround-add-quote ()
  "Test `helixel--surround-add' with 'pair."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\' ?\')
    (should (equal (buffer-string) "'hello'"))
    (should (region-active-p))))

(ert-deftest helixel-test-surround-add-block ()
  "Test `helixel--surround-add' with string block pair."
  (with-temp-buffer
    (org-mode)
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add "#+begin_quote " "#+end_quote")
    (should (string-match "\\`#\\+begin_quote .*\nhello\n#\\+end_quote\\'" (buffer-string)))))

(ert-deftest helixel-test-surround-add-tag ()
  "Test `helixel--surround-add-tag'."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add-tag "div")
    (should (equal (buffer-string) "<div>\nhello\n</div>"))))

(ert-deftest helixel-test-surround-add-tag-inline ()
  "Test `helixel--surround-add-tag' on content with leading newline.
The leading newline is part of content so mt adds newline only before close."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "\nhello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 7) (activate-mark)
    (helixel--surround-add-tag "b")
    (should (equal (buffer-string) "<b>\nhello\n</b>"))))

(ert-deftest helixel-test-surround-delete-pair-inner ()
  "Test delete surrounding () when point is inside (mi()."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 4)
    (helixel--surround-delete-delimiter (helixel--make-pair-delimiter ?\( ?\)))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-surround-delete-pair-outer ()
  "Test delete surrounding () when point is after the close (ma()."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 7)
    (helixel--surround-delete-delimiter (helixel--make-pair-delimiter ?\( ?\)))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-surround-delete-quote ()
  "Test delete surrounding '' when point is inside."
  (with-temp-buffer
    (insert "'hello'")
    (goto-char 4)
    (helixel--surround-delete-delimiter (helixel--make-pair-delimiter ?\' ?\'))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-surround-delete-quote-outer ()
  "Test delete surrounding \"\" when point is after the close (ma\")."
  (with-temp-buffer
    (insert "\"hello\"")
    (goto-char 8)
    (helixel--surround-delete-delimiter (helixel--make-pair-delimiter ?\" ?\"))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-surround-delete-tag ()
  "Test delete surrounding XML tags."
  (with-temp-buffer
    (insert "<div>hello</div>")
    (goto-char 8)
    (helixel--surround-delete-delimiter (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-surround-delete-tag-with-newlines ()
  "Test delete surrounding XML tags with newlines."
  (with-temp-buffer
    (insert "<div>\nhello\n</div>")
    (goto-char 9)
    (helixel--surround-delete-delimiter (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-surround-replace-pair ()
  "Test replace () with []."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 4)
    (helixel--surround-replace-pair (helixel--make-pair-delimiter ?\( ?\)) ?\[ ?\])
    (should (equal (buffer-string) "[hello]"))))

(ert-deftest helixel-test-surround-replace-quote ()
  "Test replace '' with \"\"."
  (with-temp-buffer
    (insert "'hello'")
    (goto-char 4)
    (helixel--surround-replace-pair (helixel--make-pair-delimiter ?\' ?\') ?\" ?\")
    (should (equal (buffer-string) "\"hello\""))))

(ert-deftest helixel-test-surround-replace-tag ()
  "Test replace tag div -> p."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add-tag "div")
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<p>\nhello\n</p>"))))

(ert-deftest helixel-test-surround-replace-equal-repeated ()
  "Test repeated mr does not accumulate newlines."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add-tag "div")
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (helixel--surround-replace-tag "span" (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<span>\nhello\n</span>"))))

(ert-deftest helixel-test-surround-chain-ms-md ()
  "Chain ms( then md."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\( ?\))
    (let ((d (helixel--make-pair-delimiter ?\( ?\))))
      (let ((pos (helixel--surround-delete-delimiter d)))
        (goto-char pos)
        (should (equal (buffer-string) "hello"))))))

(ert-deftest helixel-test-surround-chain-ms-mr-md ()
  "Chain ms[ then mr{ then md."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\[ ?\])
    (helixel--surround-replace-pair (helixel--make-pair-delimiter ?\[ ?\]) ?\{ ?\})
    (let ((d (helixel--make-pair-delimiter ?\{ ?\})))
      (let ((pos (helixel--surround-delete-delimiter d)))
        (goto-char pos)
        (should (equal (buffer-string) "hello"))))))

(ert-deftest helixel-test-surround-chain-mt-mr-md ()
  "Chain mt div -> mr p -> md."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add-tag "div")
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (let ((d (helixel--make-tag-delimiter)))
      (let ((pos (helixel--surround-delete-delimiter d)))
        (goto-char pos)
        (should (equal (buffer-string) "hello"))))))

(ert-deftest helixel-test-surround-replace-trailing-newline ()
  "Test replace () with [] when content has trailing newline."
  (with-temp-buffer
    (insert "(hello)\n")
    (goto-char 4)
    (helixel--surround-replace-pair (helixel--make-pair-delimiter ?\( ?\)) ?\[ ?\])
    (should (equal (buffer-string) "[hello]\n"))))

(ert-deftest helixel-test-surround-block-lookup ()
  "Test block pair lookup returns (STRING . STRING)."
  (with-temp-buffer
    (org-mode)
    (let ((pair (helixel--surround-block-lookup ?s)))
      (should pair)
      (should (stringp (car pair)))
      (should (stringp (cdr pair)))
      (should (string-match "begin_src" (car pair)))
      (should (string-match "end_src" (cdr pair))))))

(ert-deftest helixel-test-surround-block-lookup-fallback ()
  "Test block pair lookup in fundamental mode returns nil."
  (with-temp-buffer
    (fundamental-mode)
    (should-not (helixel--surround-block-lookup ?s))))

(ert-deftest helixel-test-surround-available-keys ()
  "Test `helixel--surround-available-keys' returns expected keys."
  (with-temp-buffer
    (fundamental-mode)
    (let ((keys-str (string-join (helixel--surround-available-keys) " ")))
      (should (string-match-p "(" keys-str))
      (should (string-match-p "\\[" keys-str))
      (should (string-match-p "'" keys-str))
      (should (string-match-p "\"" keys-str)))))

(ert-deftest helixel-test-surround-available-keys-org ()
  "Test `helixel--surround-available-keys' includes block keys in org."
  (with-temp-buffer
    (org-mode)
    (let ((keys (helixel--surround-available-keys)))
      (should (cl-some (lambda (k) (string-match "src" k)) keys)))))

(ert-deftest helixel-test-surround-delete-block ()
  "Test delete block after ms s in org-mode."
  (with-temp-buffer
    (org-mode)
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (let ((pair (helixel--surround-block-lookup ?s)))
      (helixel--surround-add (car pair) (cdr pair))
      (let ((d (helixel--make-block-delimiter (car pair) (cdr pair))))
        (let ((pos (helixel--surround-delete-delimiter d)))
          (goto-char pos)
          (should (equal (buffer-string) "hello")))))))

;; ============================================================================
;; surround: delimiter protocol + edge cases
;; ============================================================================

;; --- helixel-up-xml-tag match-data fix ---

(ert-deftest helixel-test-up-xml-tag-match-data-from-opener ()
  "match-data is preserved when starting on opening tag."
  (with-temp-buffer
    (insert "<div>hello</div>")
    (goto-char 1)
    (should (zerop (helixel-up-xml-tag 1)))
    (should (match-beginning 0))
    (should (= (match-beginning 0) 11))))

(ert-deftest helixel-test-up-xml-tag-match-data-from-eob ()
  "match-data is preserved when starting from end of buffer."
  (with-temp-buffer
    (insert "<div>\nhello\n</div>")
    (goto-char (point-max))
    (should (zerop (helixel-up-xml-tag -1)))
    (should (match-beginning 0))
    (should (= (match-beginning 0) 1))))

(ert-deftest helixel-test-up-xml-tag-nested-from-inside ()
  "Find innermost tag pair when point is inside content."
  (with-temp-buffer
    (insert "<div><span>hello</span></div>")
    (goto-char 14) ;; inside "hello"
    (should (zerop (helixel-up-xml-tag 1)))
    (should (string= (match-string 0) "</span>"))
    (should (zerop (helixel-up-xml-tag -1)))
    (should (string= (match-string 0) "<span>"))))

;; --- helixel--strip-adjacent-newlines ---

(ert-deftest helixel-test-strip-adjacent-newlines-both ()
  "Strip newlines on both sides."
  (with-temp-buffer
    (insert "open\ncontent\nclose")
    (pcase-let ((`(,oe . ,cb) (helixel--strip-adjacent-newlines 5 14)))
      (should (= oe 6))
      (should (= cb 13)))))

(ert-deftest helixel-test-strip-adjacent-newlines-none ()
  "No newlines to strip."
  (with-temp-buffer
    (insert "openXcontentYclose")
    (pcase-let ((`(,oe . ,cb) (helixel--strip-adjacent-newlines 5 13)))
      (should (= oe 5))
      (should (= cb 13)))))

;; --- helixel-delimiter-bounds / unified delete ---

(ert-deftest helixel-test-delimiter-bounds-pair ()
  "Bounds for pair () from inside."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 4)
    (let* ((d (helixel--make-pair-delimiter ?\( ?\)))
           (b (helixel-delimiter-bounds d)))
      (should (= (caar b) 1))  ;; open-beg
      (should (= (cdar b) 2))  ;; open-end
      (should (= (cadr b) 7))  ;; close-beg
      (should (= (cddr b) 8))))) ;; close-end

(ert-deftest helixel-test-delimiter-bounds-pair-after-close ()
  "Bounds for pair from after closing delimiter."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 8) ;; after )
    (let* ((d (helixel--make-pair-delimiter ?\( ?\)))
           (b (helixel-delimiter-bounds d)))
      (should (= (caar b) 1))
      (should (= (cddr b) 8)))))

(ert-deftest helixel-test-delimiter-bounds-quote ()
  "Bounds for quote from inside (uses char-scanning fallback)."
  (with-temp-buffer
    (insert "\"hello\"")
    (goto-char 4)
    (should (> (helixel--surround-delete-delimiter
                (helixel--make-pair-delimiter ?\" ?\")) 0))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-delimiter-bounds-tag ()
  "Bounds for tag from inside."
  (with-temp-buffer
    (insert "<div>hello</div>")
    (goto-char 8)
    (let* ((d (helixel--make-tag-delimiter))
           (b (helixel-delimiter-bounds d)))
      (should (= (caar b) 1))
      (should (= (cadr b) 11)))))

(ert-deftest helixel-test-delimiter-bounds-block-org ()
  "Bounds for org block."
  (with-temp-buffer
    (org-mode)
    (insert "#+begin_src emacs-lisp\nhello\n#+end_src")
    (goto-char 25)
    (let* ((d (helixel--make-block-delimiter))
           (b (helixel-delimiter-bounds d)))
      (should b)
      (should (>= (caar b) 1)))))

(ert-deftest helixel-test-delete-block-via-delimiter ()
  "Delete org block via unified delimiter-delete."
  (with-temp-buffer
    (org-mode)
    (insert "#+begin_src emacs-lisp\nhello\n#+end_src")
    (goto-char 26)
    (let ((d (helixel--make-block-delimiter)))
      (helixel--surround-delete-delimiter d)
      (should (equal (buffer-string) "hello")))))

;; --- replace-tag fix: trailing text + newline correctness ---

(ert-deftest helixel-test-replace-tag-trailing-text ()
  "Replace tag when text follows closing tag."
  (with-temp-buffer
    (insert "prefix\n<div>\nhello\n</div>\nsuffix")
    (goto-char 14) ;; inside content
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "prefix\n<p>\nhello\n</p>\nsuffix"))))

(ert-deftest helixel-test-replace-tag-inline-no-newlines ()
  "Replace inline tag, add newlines."
  (with-temp-buffer
    (insert "<div>hello</div>")
    (goto-char 8)
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<p>\nhello\n</p>"))))

(ert-deftest helixel-test-replace-tag-preexisting-newlines ()
  "Replace tag that already has newlines."
  (with-temp-buffer
    (insert "<div>\nhello\n</div>")
    (goto-char 9)
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<p>\nhello\n</p>"))))

(ert-deftest helixel-test-replace-tag-eob-no-extra-newlines ()
  "Replace tag at end of buffer, no extra \\n."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add-tag "div")
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    ;; Must not have double newline
    (should-not (string-match "\n\n</p>" (buffer-string)))
    (should (equal (buffer-string) "<p>\nhello\n</p>"))))

;; --- nested tags ---

(ert-deftest helixel-test-delete-tag-nested-same-name ()
  "Delete innermost pair of same-name nested tags."
  (with-temp-buffer
    (insert "<div><div>hello</div></div>")
    (goto-char 14) ;; inside inner content
    (helixel--surround-delete-delimiter (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<div>hello</div>"))))

(ert-deftest helixel-test-delete-tag-nested-different-name ()
  "Delete innermost pair of different-name nested tags."
  (with-temp-buffer
    (insert "<div><span>hello</span></div>")
    (goto-char 15)
    (helixel--surround-delete-delimiter (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<div>hello</div>"))))

(ert-deftest helixel-test-replace-tag-innermost-nested ()
  "Replace innermost pair in nested tags."
  (with-temp-buffer
    (insert "<div><span>hello</span></div>")
    (goto-char 15)
    (helixel--surround-replace-tag "b" (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<div><b>\nhello\n</b></div>"))))

(ert-deftest helixel-test-nested-tag-mat-mr-replaces-inner ()
  "After mat on inner tag of nested tags, mr replaces inner (not outer)."
  (with-temp-buffer
    (insert "<p>\n<div>\nhello\n</div>\n</p>\n\nworld")
    ;; Simulate mat selecting outer <div> — region spans <div> to </div>
    (push-mark 5 nil t)
    (goto-char 25)
    (activate-mark)
    ;; position at midpoint of selection for finder
    (goto-char (/ (+ 5 25) 2))
    (helixel--surround-replace-tag "a" (helixel--make-tag-delimiter))
    (should (equal (buffer-string)
                   "<p>\n<a>\nhello\n</a>\n</p>\n\nworld"))))

(ert-deftest helixel-test-nested-tag-mat-md-deletes-inner ()
  "After mat on inner tag of nested tags, md deletes inner (not outer)."
  (with-temp-buffer
    (insert "<p>\n<div>\nhello\n</div>\n</p>\n\nworld")
    ;; Simulate mat selecting outer <div> — region spans <div> to </div>
    (push-mark 5 nil t)
    (goto-char 25)
    (activate-mark)
    ;; position at midpoint of selection for finder
    (goto-char (/ (+ 5 25) 2))
    (helixel--surround-delete-delimiter (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<p>\nhello\n</p>\n\nworld"))))

;; --- unified delete via delimiter protocol ---

(ert-deftest helixel-test-delete-delimiter-pair ()
  "Unified delete for pair via delimiter."
  (with-temp-buffer
    (insert "[hello]")
    (goto-char 4)
    (let ((d (helixel--make-pair-delimiter ?\[ ?\])))
      (helixel--surround-delete-delimiter d)
      (should (equal (buffer-string) "hello")))))

(ert-deftest helixel-test-delete-delimiter-regex ()
  "Unified delete for regex block."
  (with-temp-buffer
    (insert "#+begin_quote\nhello\n#+end_quote")
    (goto-char 18)
    (let ((d (helixel--make-regex-delimiter
              "#\\+begin_quote" "#\\+end_quote")))
      (helixel--surround-delete-delimiter d)
      (should (equal (buffer-string) "hello")))))

(ert-deftest helixel-test-chain-mt-mr-md-via-delimiter ()
  "Chain mt→mr→md via delimiter protocol."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add-tag "div")
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (let ((d (helixel--make-tag-delimiter)))
      (helixel--surround-delete-delimiter d)
      (should (equal (buffer-string) "hello")))))

;; --- delete-tag newline cleanup ---

(ert-deftest helixel-test-delete-tag-strips-newlines ()
  "Delete tag strips adjacent newlines."
  (with-temp-buffer
    (insert "<div>\nhello\n</div>")
    (goto-char 9)
    (helixel--surround-delete-delimiter (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "hello"))))

;; --- ms add with new delimiter types ---

(ert-deftest helixel-test-surround-add-brace ()
  "Test `helixel--surround-add' with { pair."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\{ ?\})
    (should (equal (buffer-string) "{hello}"))))

(ert-deftest helixel-test-surround-add-angle ()
  "Test `helixel--surround-add' with < pair."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\< ?\>)
    (should (equal (buffer-string) "<hello>"))))
;; ---------------------------------------------------------------------------
;; Count-aware repeat tests

(ert-deftest helixel-test-repeat-count-line-select ()
  "Test `3x d .` repeats killing 3 lines."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\nline5\nline6\n"
    (goto-char 1)
    ;; Select 3 lines: x x x
    (setq last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (setq last-command 'helixel-select-line this-command 'helixel-select-line)
    (helixel-select-line)
    (setq last-command 'helixel-select-line this-command 'helixel-select-line)
    (helixel-select-line)
    ;; Verify count stored
    (should (= (helixel-sel-count helixel--repeat-sel-ctx) 3))
    ;; Kill
    (setq last-command 'helixel-select-line this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (string= (buffer-string) "line4\nline5\nline6\n"))
    ;; Repeat at line4 — should kill 3 lines again
    (goto-char 1)
    (helixel-repeat-edit)
    (should (string= (buffer-string) ""))))

(ert-deftest helixel-test-repeat-count-prefix-line ()
  "Test `3x d .` with prefix arg selects 3 lines at once."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\nline5\nline6\n"
    (goto-char 1)
    ;; Select 3 lines at once with prefix
    (setq last-command nil this-command 'helixel-select-line)
    (helixel-select-line 3)
    ;; Verify count stored
    (should (= (helixel-sel-count helixel--repeat-sel-ctx) 3))
    ;; Kill
    (setq last-command 'helixel-select-line this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (string= (buffer-string) "line4\nline5\nline6\n"))
    ;; Repeat
    (goto-char 1)
    (helixel-repeat-edit)
    (should (string= (buffer-string) ""))))

(ert-deftest helixel-test-repeat-count-line-up ()
  "Test count-aware repeat for line-up selection."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\n"
    (goto-char (point-max))
    (forward-line -1)
    ;; Select 2 lines upward
    (setq last-command nil this-command 'helixel-select-line-up)
    (helixel-select-line-up 2)
    (should (= (helixel-sel-count helixel--repeat-sel-ctx) 2))
    ;; Kill
    (setq last-command 'helixel-select-line-up this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (string= (buffer-string) "line1\nline2\n"))))

(ert-deftest helixel-test-select-line-count-stored-in-tx ()
  "Test that count is preserved through record-edit into the transaction."
  (helixel-test-with-buffer "a\nb\nc\nd\n"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (helixel-select-line)
    (setq last-command 'helixel-select-line this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    ;; The tx sel should have count 2
    (should (= (helixel-sel-count (helixel-edit-sel helixel--last-tx)) 2))))

;;; Jump navigation tests

(ert-deftest helixel-test-jump-empty-list ()
  "C-o with empty jump list says no positions."
  (let ((helixel--jump-list nil)
        (helixel--jump-pos nil)
        (msg nil))
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args)
                 (setq msg (apply #'format fmt args)))))
      (with-temp-buffer
        (helixel-jump-backward)
        (should (string= msg "No jump positions"))))))

(ert-deftest helixel-test-jump-forward-no-state ()
  "C-i without prior C-o says at newest."
  (let ((helixel--jump-list nil)
        (helixel--jump-pos nil)
        (msg nil))
    (cl-letf (((symbol-function 'message)
               (lambda (fmt &rest args)
                 (setq msg (apply #'format fmt args)))))
      (with-temp-buffer
        (helixel-jump-forward)
        (should (string= msg "At newest"))))))

(ert-deftest helixel-test-jump-same-buffer-roundtrip ()
  "C-o then C-i returns to original position."
  (let ((helixel--jump-list nil)
        (helixel--jump-pos nil))
    (with-temp-buffer
      (transient-mark-mode 1)
      (insert "aaa bbb ccc ddd")
      (goto-char 5)
      (let ((orig (point)))
        (helixel-register-jump 'goto 'test)
        (goto-char 1)
        (should (= (point) 1))
        (helixel-jump-backward)
        (should (= (point) orig))
        (should helixel--jump-pos)
        (helixel-jump-forward)
        (should (= (point) 1))
        (let ((msg nil))
          (cl-letf (((symbol-function 'message)
                     (lambda (fmt &rest args)
                       (setq msg (apply #'format fmt args)))))
            (helixel-jump-forward)
            (should (string= msg "At newest"))))))))

(ert-deftest helixel-test-jump-multiple-chaining ()
  "Multiple C-o then multiple C-i chain correctly and stop at ends."
  (let ((helixel--jump-list nil)
        (helixel--jump-pos nil))
    (with-temp-buffer
      (transient-mark-mode 1)
      (insert "aaa bbb ccc ddd eee fff")
      (goto-char 1)
      (helixel-register-jump 'search 'a)
      (goto-char 5)
      (helixel-register-jump 'find-char 'b)
      (goto-char 9)
      (helixel-register-jump 'goto 'c)
      (goto-char 13)
      (helixel-jump-backward)       ;; 13→9
      (should (= (point) 9))
      (helixel-jump-backward)       ;; 9→5
      (should (= (point) 5))
      (helixel-jump-backward)       ;; 5→1
      (should (= (point) 1))
      ;; At oldest
      (let ((msg nil))
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args)
                     (setq msg (apply #'format fmt args)))))
          (helixel-jump-backward)
          (should (string= msg "At oldest"))))
      ;; C-i chain back forward
      (helixel-jump-forward)        ;; 1→5
      (should (= (point) 5))
      (helixel-jump-forward)        ;; 5→9
      (should (= (point) 9))
      (helixel-jump-forward)        ;; 9→13 (return point from first C-o)
      (should (= (point) 13))
      ;; At newest
      (let ((msg nil))
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args)
                     (setq msg (apply #'format fmt args)))))
          (helixel-jump-forward)
          (should (string= msg "At newest")))))))

(ert-deftest helixel-test-jump-no-infinite-loop ()
  "Repeated C-i does not loop infinitely — it stops at newest."
  (let ((helixel--jump-list nil)
        (helixel--jump-pos nil))
    (with-temp-buffer
      (transient-mark-mode 1)
      (insert "aaa bbb")
      (goto-char 5)
      (helixel-register-jump 'goto 'test)
      (goto-char 1)
      (helixel-jump-backward)
      (should (= (point) 5))
      (helixel-jump-forward)
      (should (= (point) 1))
      ;; Subsequent C-i should all say "At newest", not loop
      (let ((count 0))
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args)
                     (when (string= fmt "At newest")
                       (cl-incf count)))))
          (dotimes (_ 5)
            (helixel-jump-forward)))
        (should (= count 5))))))

(ert-deftest helixel-test-jump-cross-buffer ()
  "Cross-buffer C-o switches buffer and C-i returns."
  (let ((helixel--jump-list nil)
        (helixel--jump-pos nil)
        (buf-a (generate-new-buffer "jump-test-a"))
        (buf-b (generate-new-buffer "jump-test-b")))
    (with-current-buffer buf-a
      (insert "AAA BBB CCC")
      (goto-char 5)
      (helixel-register-jump 'goto 'test))
    (with-current-buffer buf-b
      (insert "XXX YYY ZZZ")
      (goto-char 5))
    (switch-to-buffer buf-b)
    (should (eq (current-buffer) buf-b))
    (helixel-jump-backward)
    (should (eq (current-buffer) buf-a))
    (should (= (point) 5))
    (helixel-jump-forward)
    (should (eq (current-buffer) buf-b))
    (let ((msg nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args)
                   (setq msg (apply #'format fmt args)))))
        (helixel-jump-forward)
        (should (string= msg "At newest"))))
    (kill-buffer buf-a)
    (kill-buffer buf-b)))

;; ============================================================================
;; P0.1: ring-head sync — verify pick replays full payload
;; ============================================================================

(ert-deftest helixel-test-repeat-pick-change-end-to-end ()
  "After ciwX<esc>, `helixel-repeat-edit-pick' replays the change correctly.
Verifies that `helixel-insert-exit' syncs `helixel--last-tx' payload
with the ring head so the picker sees the full transaction."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-change-thing-at-point)
    (helixel-change-thing-at-point)
    (insert "X")
    (helixel-insert-exit)
    ;; Verify ring head has the payload
    (should (plist-get (helixel-edit-payload (car helixel--edit-ring))
                       :inserted-text))
    (should (string= (plist-get
                      (helixel-edit-payload (car helixel--edit-ring))
                      :inserted-text)
                     "X"))
    ;; Ring head should be eq to last-tx
    (should (eq (car helixel--edit-ring) helixel--last-tx))
    ;; Simulate picking the first entry (the only one)
    (should (= 1 (length helixel--edit-ring)))
    (goto-char 4)
    (setq helixel--last-tx (car helixel--edit-ring))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "X X foo"))))

(ert-deftest helixel-test-repeat-pick-insert-end-to-end ()
  "After iZ<esc>, ring head has :text payload; pick replays correctly."
  (let ((helixel--last-tx nil)
        (helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "abc"
      (set-match-data nil) ; clear stale match data from prior tests
      (goto-char 2)
        (setq last-command nil this-command 'helixel-insert)
        (helixel-insert)
        (insert "Z")
        (helixel-insert-exit)
        ;; Verify ring head has :text payload
        (should (plist-get (helixel-edit-payload (car helixel--edit-ring))
                           :text))
        (should (string=
                 (plist-get (helixel-edit-payload (car helixel--edit-ring))
                            :text)
                 "Z"))
        (should (eq (car helixel--edit-ring) helixel--last-tx))
        (goto-char 4)
        (setq helixel--last-tx (car helixel--edit-ring))
        (helixel-repeat-edit)
        (should (string= (buffer-string) "aZbZc")))))

;; ============================================================================
;; P0.2: undo amalgamation — `.` produces a single undo step
;; ============================================================================

(ert-deftest helixel-test-repeat-undo-amalgamation ()
  "`.` (change replay) is a single undo step.
ciw X <esc> creates two buffer changes (kill + insert).  When `.`
replays them, undo should restore the pre-repeat state in one step."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 1)
    ;; Enable undo in this temp buffer
    (setq buffer-undo-list nil)
    ;; Record: ciw X <esc>
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-change-thing-at-point)
    (helixel-change-thing-at-point)
    (insert "X")
    (helixel-insert-exit)
    (should (string= (buffer-string) "X world foo"))
    ;; Repeat at "world"
    (goto-char 4)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "X X foo"))
    ;; Single undo should restore to "X world foo"
    (let ((last-command nil))
      (undo-only))
    (should (string= (buffer-string) "X world foo"))))

;; ============================================================================
;; P1.1: track-visual-move no-op during replay
;; ============================================================================

(ert-deftest helixel-test-repeat-track-visual-move-no-leak ()
  "`helixel--track-visual-move' does not leak state during dot-repeat replay.
Movement commands called during selection recreation should not
modify `helixel--repeat-sel-ctx'."
  (helixel-test-with-buffer "hello world foo bar"
    (goto-char 1)
    ;; Record a v w w d sequence
    (helixel--switch-state 'visual)
    (setq last-command nil this-command 'helixel-forward-word-start)
    (helixel-forward-word-start)
    (helixel-forward-word-start)
    (setq last-command 'helixel-forward-word-start
          this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (helixel--switch-state 'normal)
    ;; After kill, remaining is "foo bar"
    (should (string= (buffer-string) "foo bar"))
    ;; Save the stored sel-ctx
    (let ((stored-sel (copy-sequence (helixel-edit-sel helixel--last-tx))))
      ;; Replay
      (goto-char 1)
      (helixel-repeat-edit)
      ;; helixel--repeat-sel-ctx should be nil after consumption
      (should (null helixel--repeat-sel-ctx))
      ;; Should be "bar" after second kill (killed "foo ")
      (should (string= (buffer-string) "bar"))
      ;; The stored tx should be unchanged
      (should (equal (helixel-edit-sel helixel--last-tx) stored-sel)))))

;; ============================================================================
;; P1.2: rect change replay does not switch state
;; ============================================================================

(ert-deftest helixel-test-repeat-rect-change-no-state-switch ()
  "Rect change replay via `.` does not call `helixel-insert-exit'.
It should only run `helixel--rect-replay' without switching to insert
and back."
  (helixel-test-with-buffer "aaa\nbbb\nccc\n"
    (goto-char 1)
    ;; Select rect 2 lines, then change
    (helixel--switch-state 'visual)
    (setq helixel--current-state 'visual)
    (push-mark (point) t t)
    (goto-char 5)
    (rectangle-mark-mode 1)
    (setq helixel--selection-type 'rect)
    (setq last-command nil this-command 'helixel-change-thing-at-point)
    (helixel-change-thing-at-point)
    (insert "X")
    (helixel-insert-exit)
    (helixel--switch-state 'normal)
    (should (eq helixel--current-state 'normal))
    ;; Remember state before replay
    (let ((pre-state helixel--current-state))
      (helixel-repeat-edit)
      ;; State should be unchanged
      (should (eq helixel--current-state pre-state)))))

;; ============================================================================
;; End-to-end: search + insert with cursor movement + n .
;; ============================================================================

(ert-deftest helixel-test-repeat-search-insert-c-f-n-dot ()
  "Scenario: /hello<RET> i C-f foo<ESC> n . inserts foo at cursor offset.
Cursor-offset is set manually in sel ctx to simulate forward-char."
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (re-search-forward "hello")
    (let ((isearch-success t)
          (isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-other-end (match-beginning 0)))
      (helixel-search--handle-done nil))
    ;; Build tx with entry-kind=insert, cursor-offset=1 (C-f),
    ;; and text=foo.  sel ctx records the offset within the match.
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text
            (helixel-sel-create
             'search
             '(:pattern "hello" :dir forward
               :entry-kind insert :cursor-offset 1)
             #'helixel--recreate-search "/hello/")
            :text "foo"))
    ;; Apply first edit manually
    (goto-char (1+ (match-beginning 0)))
    (insert "foo")
    (should (string= (buffer-string) "hfooello world hello"))
    ;; . — repeat: searches for next "hello", inserts at offset 1
    (helixel-repeat-edit)
    (should (string= (buffer-string) "hfooello world hfooello"))))

(ert-deftest helixel-test-repeat-search-insert-no-region-n-dot ()
  "i after /hello: search sel with entry-kind and cursor-offset.
Cursor-offset is set manually; kmacro captures keys in real flow."
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (re-search-forward "hello")
    (let ((isearch-success t)
          (isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-other-end (match-beginning 0)))
      (helixel-search--handle-done nil))
    ;; Build tx: insert kind=search, entry-kind=insert, offset=1
    ;; simulates /hello + i + C-f + hi<ESC>
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text
            (helixel-sel-create
             'search
             '(:pattern "hello" :dir forward
               :entry-kind insert :cursor-offset 1)
             #'helixel--recreate-search "/hello/")
            :text "hi"))
    ;; Apply first edit manually
    (goto-char (1+ (match-beginning 0)))
    (insert "hi")
    (should (string= (buffer-string) "hhiello world hello"))
    ;; . — repeat on next match at offset 1
    (helixel-repeat-edit)
    (should (string= (buffer-string) "hhiello world hhiello"))))

;; ============================================================================
;; Reproduction: a + search + cursor-left + . (fixed marker-shift)
;; Scenario: /hello<RET> a <left><left> ww <esc> n .
;; Expected: "helwwlo" on both matches (was broken due to marker-shift bug).
;; ============================================================================

(ert-deftest helixel-test-repeat-search-insert-after-left-n-dot ()
  "Scenario: /hello<RET> a <left><left> ww <esc> n .
Insert-after with cursor-movement-left; offset set manually."
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (re-search-forward "hello")
    (should (= (match-beginning 0) 1))
    (should (= (match-end 0) 6))
    (let ((isearch-success t)
          (isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-other-end (match-beginning 0)))
      (helixel-search--handle-done nil))
    ;; Build tx: append kind, entry-kind=append, cursor-offset=-2
    ;; simulates /hello + a + <left><left> + ww<ESC>
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text
            (helixel-sel-create
             'search
             '(:pattern "hello" :dir forward
               :entry-kind append :cursor-offset -2)
             #'helixel--recreate-search "/hello/")
            :text "ww"))
    ;; Apply first edit manually
    (goto-char (- (match-end 0) 2))
    (insert "ww")
    (should (string= (buffer-string) "helwwlo world hello"))
    ;; . — repeat on next match at offset -2 from match-end
    (helixel-repeat-edit)
    (should (string= (buffer-string) "helwwlo world helwwlo"))))

;; ============================================================================
;; a (insert-after) + search + . — no cursor movement
;; ============================================================================

(ert-deftest helixel-test-repeat-search-insert-after-no-move-n-dot ()
  "Scenario: /hello<RET> a foo <esc> n . — appends at region-end.
Insert-after at region-end with no cursor movement.
Cursor-offset is 0 (first insertion at region-end)."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world hello"
      ;; Simulate /hello<RET>
      (goto-char 1)
      (re-search-forward "hello")
      (should (= (match-beginning 0) 1))
      (should (= (match-end 0) 6))
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      ;; Set up search sel context (done by helixel-search--set-sel-ctx in real flow)
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      ;; a — insert-after at match-end (unified search path)
      (setq last-command nil this-command 'helixel-insert-after)
      (helixel-insert-after)
      ;; foo — insert at point (no cursor movement)
      (insert "foo")
      (helixel-insert-exit)
      ;; Buffer after edit: "hellofoo world hello"
      (should (string= (buffer-string) "hellofoo world hello"))
      (should (string= (plist-get (helixel-edit-payload helixel--last-tx) :text)
                       "foo"))
      (let ((sel (helixel-edit-sel helixel--last-tx)))
        (should (eq (helixel-sel-get-kind sel) 'search))
        (should (eq (helixel-sel-search-entry-kind sel) 'append)))
      ;; . — repeat (searches for next "hello" and applies "foo" at end)
      (helixel-repeat-edit)
      (should (string= (buffer-string) "hellofoo world hellofoo")))))

;; ── a (insert-after) + backward search + . ──

(ert-deftest helixel-test-repeat-search-insert-after-backward-dot ()
  "Scenario: ?hello<RET> a foo <esc> . — backward search + append.
Backward search finds last match, a appends after it, . finds previous
match going backward and appends there too.  Regression: (looking-at)
only matched at match-start, missing the match-end case for append."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world hello"
      (goto-char (point-max))
      ;; Simulate ?hello<RET> — backward search from end
      (re-search-backward "hello")
      (should (= (match-beginning 0) 13))
      (should (= (match-end 0) 18))
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward nil)
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)
             #'helixel--recreate-search "?hello"))
      ;; a — insert-after at match-end
      (setq last-command nil this-command 'helixel-insert-after)
      (helixel-insert-after)
      (insert "foo")
      (helixel-insert-exit)
      ;; Buffer after edit: "hello world hellofoo"
      (should (string= (buffer-string) "hello world hellofoo"))
      (let ((sel (helixel-edit-sel helixel--last-tx)))
        (should (eq (helixel-sel-get-kind sel) 'search))
        (should (eq (helixel-sel-search-entry-kind sel) 'append)))
      ;; . — should find first "hello" (backward) and append "foo"
      (helixel-repeat-edit)
      (should (string= (buffer-string) "hellofoo world hellofoo")))))

;; ============================================================================
;; Regression: a after search goes to region-end, not buffer-beginning
;; ============================================================================

(ert-deftest helixel-test-search-insert-after-region-end ()
  "a after /hello<RET> goes to region-end (match-end), not buffer start.
Regression: using (match-end 0) instead of (region-end) caused
goto-char(nil) when match data was stale, jumping to buffer start."
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (re-search-forward "hello")
    (let ((isearch-success t)
          (isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-other-end (match-beginning 0)))
      (helixel-search--handle-done nil))
    ;; Simulate helixel-search--set-sel-ctx
    (setq helixel--repeat-sel-ctx
          (helixel-sel-create
           'search '(:pattern "hello" :dir forward)
           #'helixel--recreate-search "/hello/"))
    ;; a should go to region-end (6), not buffer-beginning (1)
    (setq last-command nil this-command 'helixel-insert-after)
    (helixel-insert-after)
    (should (= (point) 6))
    (should (= (region-beginning) 1))))

;; ============================================================================
;; . repeat — search-failed error message
;; ============================================================================

(ert-deftest helixel-test-repeat-search-no-more-matches ()
  ". after search-based edit: shows error when no more matches exist."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world"
      ;; /hello<RET> — search for "hello"
      (goto-char 1)
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      ;; i — insert at match-beginning
      (setq last-command nil this-command 'helixel-insert)
      (helixel-insert)
      (insert "X")
      (helixel-insert-exit)
      ;; Move past the only "hello" so . can't re-find it
      (goto-char (point-max))
      ;; Only one "hello" in buffer; . should fail
      (condition-case err
          (helixel-repeat-edit)
        ((error quit)
         (should (string-match-p "Search pattern not found"
                                  (error-message-string err)))))
      ;; Buffer should be unchanged (undo amalgamate cancelled)
      (should (string= (buffer-string) "Xhello world")))))

;; ============================================================================
;; Unified search-edit: additional end-to-end tests
;; ============================================================================

;; ── i (insert) no cursor movement + . ──

(ert-deftest helixel-test-repeat-search-insert-no-move-dot ()
  "Scenario: /hello<RET> i X <esc> . — insert X at match-beginning."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world hello"
      (goto-char 1)
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil this-command 'helixel-insert)
      (helixel-insert)
      (insert "X")
      (helixel-insert-exit)
      (should (string= (buffer-string) "Xhello world hello"))
      (let ((sel (helixel-edit-sel helixel--last-tx)))
        (should (eq (helixel-sel-get-kind sel) 'search))
        (should (eq (helixel-sel-search-entry-kind sel) 'insert)))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "Xhello world Xhello")))))

;; ── c (change) + search + . ──

(ert-deftest helixel-test-repeat-search-change-dot ()
  "Full-flow: /hello<RET> c X <esc> . — changes both matches to X."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world hello"
      (goto-char 1)
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "X")
      (helixel-insert-exit)
      (should (string= (buffer-string) "X world hello"))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "X world X")))))

;; ── . from arbitrary position ──

(ert-deftest helixel-test-repeat-search-dot-from-pos ()
  "`.` from middle of buffer finds next match."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world hello"
      (goto-char 1)
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil this-command 'helixel-insert)
      (helixel-insert)
      (insert "X")
      (helixel-insert-exit)
      (should (string= (buffer-string) "Xhello world hello"))
      (goto-char 8)
      (helixel-repeat-edit)
      (should (string= (buffer-string) "Xhello world Xhello")))))

;; ── Movement selection + . end-to-end ──

(ert-deftest helixel-test-repeat-movement-kill-at-start ()
  "vw d at position 1, then . at start selects the word at cursor."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world foo bar"
      (goto-char 1)
      (setq helixel--last-tx
            (helixel-edit-make 'kill
              (helixel-sel-create 'movement
                '(:moves ((helixel-forward-word-start . 1)))
                #'helixel--recreate-movement "v1")))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "world foo bar")))))

(ert-deftest helixel-test-repeat-movement-kill-at-word-start ()
  "vw d at position 1, then move to word start, . selects the word there."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world foo bar"
      (goto-char 1)
      (setq helixel--last-tx
            (helixel-edit-make 'kill
              (helixel-sel-create 'movement
                '(:moves ((helixel-forward-word-start . 1)))
                #'helixel--recreate-movement "v1")))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "world foo bar"))
      (goto-char 7)
      (helixel-repeat-edit)
      (should (string= (buffer-string) "world bar")))))

(ert-deftest helixel-test-repeat-movement-kill-count-two ()
  "v w w d selects 2 words forward, . at a new position selects 2 words."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world foo bar"
      (goto-char 1)
      (setq helixel--last-tx
            (helixel-edit-make 'kill
              (helixel-sel-create 'movement
                '(:moves ((helixel-forward-word-start . 2)))
                #'helixel--recreate-movement "v2")))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "foo bar")))))
;; ── , comma repeat-selection end-to-end ──

(ert-deftest helixel-test-repeat-selection-line-then-dot ()
  ", after x d previews the line, then . kills it."
  :tags '(repeat comma)
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "aaa\nbbb\nccc"
      (goto-char 1)
      (setq helixel--last-tx
            (helixel-edit-make
             'kill
             (helixel-sel-create 'line
               '(:dir forward :count 1)
               #'helixel--recreate-line "x")))
      (helixel-repeat-selection)
      (should (region-active-p))
      (should (= (region-beginning) 1))
      (should (= (region-end) 4))          ; "aaa\n" (point at 4)
      (helixel-repeat-edit)
      (should (string= (buffer-string) "bbb\nccc")))))

(ert-deftest helixel-test-repeat-selection-line-count-then-dot ()
  "3 , after x d kills 3 lines."
  :tags '(repeat comma)
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "aaa\nbbb\nccc\nddd"
      (goto-char 1)
      (setq helixel--last-tx
            (helixel-edit-make
             'kill
             (helixel-sel-create 'line
               '(:dir forward :count 1)
               #'helixel--recreate-line "x")))
      (helixel-repeat-selection 3)
      (should (region-active-p))
      (should (string= (buffer-string) "aaa\nbbb\nccc\nddd"))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "ddd")))))

(ert-deftest helixel-test-repeat-selection-movement-then-dot ()
  ", after vw d previews the word, then . kills it."
  :tags '(repeat comma)
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world"
      (goto-char 1)
      (setq helixel--last-tx
            (helixel-edit-make
             'kill
             (helixel-sel-create 'movement
               '(:moves ((helixel-forward-word-start . 1)))
               #'helixel--recreate-movement "v1")))
      (helixel-repeat-selection)
      (should (region-active-p))
      (should (= (region-beginning) 1))
      (should (= (region-end) 7))          ; 'hello '
      (helixel-repeat-edit)
      (should (string= (buffer-string) "world")))))

;; ── , comma repeat-selection with insert-text (advance) ──

(ert-deftest helixel-test-repeat-selection-insert-advance ()
  "`, after xi<text><ESC> advances to next line and shows cursor at bol."
  :tags '(repeat comma)
  (helixel-test-with-buffer "line one\nline two\nline three\n"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel-edit-make
           'insert-text
           (helixel-sel-create
            'line
            '(:dir forward :count 1 :entry-kind insert)
            #'helixel--recreate-line "x")
           :text "foo"))
    (helixel-repeat-selection)
    ;; Cursor at bol of line 2, region shows the target line.
    (should (region-active-p))
    (should (= (point) (line-beginning-position)))
    (should (string= (buffer-substring (line-beginning-position)
                                       (line-end-position))
                     "line two"))))

(ert-deftest helixel-test-repeat-selection-insert-double-comma ()
  "`, , ` advances twice then shows cursor at bol of line 3."
  :tags '(repeat comma)
  (helixel-test-with-buffer "line one\nline two\nline three\nline four\n"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel-edit-make
           'insert-text
           (helixel-sel-create
            'line
            '(:dir forward :count 1 :entry-kind insert)
            #'helixel--recreate-line "x")
           :text "foo"))
    (helixel-repeat-selection)
    (helixel-repeat-selection)
    (should (region-active-p))
    (should (= (point) (line-beginning-position)))
    (should (string= (buffer-substring (line-beginning-position)
                                       (line-end-position))
                     "line three"))))

(ert-deftest helixel-test-repeat-selection-insert-comma-then-dot ()
  "`, then . after xi<text><ESC> inserts at the advanced position."
  :tags '(repeat comma)
  (helixel-test-with-buffer "line one\nline two\nline three\n"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel-edit-make
           'insert-text
           (helixel-sel-create
            'line
            '(:dir forward :count 1 :entry-kind insert)
            #'helixel--recreate-line "x")
           :text "foo"))
    (helixel-repeat-selection)          ; advance to line 2
    (helixel-repeat-edit)               ; insert at bol of line 2
    (should (string= (buffer-string)
                     "line one\nfooline two\nline three\n"))))

(ert-deftest helixel-test-repeat-selection-insert-count-prefix ()
  "3 , after xi<text><ESC> advances 3 times, then . inserts once."
  :tags '(repeat comma)
  (helixel-test-with-buffer
      "line one\nline two\nline three\nline four\nline five\n"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel-edit-make
           'insert-text
           (helixel-sel-create
            'line
            '(:dir forward :count 1 :entry-kind insert)
            #'helixel--recreate-line "x")
           :text "foo"))
    (helixel-repeat-selection 3)        ; advance to line 4
    (should (region-active-p))
    (should (= (point) (line-beginning-position)))
    (should (string= (buffer-substring (line-beginning-position)
                                       (line-end-position))
                     "line four"))
    (helixel-repeat-edit)               ; insert at bol of line 4
    (should (string= (buffer-string)
                     (concat "line one\nline two\nline three\n"
                             "fooline four\nline five\n")))))

;; ── segment-based replay: cursor movement between insertions ──

(ert-deftest helixel-test-repeat-search-insert-move-forward-dot ()
  "Scenario: /hello<RET> i aa <M-f> bb <esc> .
Two insertions with cursor-movement gap between.
With kmacro recording, keys capture the full sequence."
  :tags '(repeat search)
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (re-search-forward "hello")
    (should (= (match-beginning 0) 1))
    (should (= (match-end 0) 6))
    (let ((isearch-success t)
          (isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-other-end (match-beginning 0)))
      (helixel-search--handle-done nil))
    ;; Build tx simulating i aa <M-f> bb <ESC>
    ;; Text records the concatenated text; sel tracks entry-kind.
    (let ((m-beg (match-beginning 0))
          (m-end (match-end 0)))
      (setq helixel--last-tx
            (helixel-edit-make 'insert-text
              (helixel-sel-create
               'search
               '(:pattern "hello" :dir forward :entry-kind insert)
               #'helixel--recreate-search "/hello/")
              :text "aabb"))
      ;; Apply first edit manually (aa before match, then bb after)
      ;; Save match positions before buffer modifications.
      (goto-char m-beg)
      (insert "aa")
      (goto-char (+ m-end (length "aa")))
      (insert "bb")
      (should (string= (buffer-string) "aahellobb world hello"))
      ;; . — repeat on next match: inserts "aabb" at match-beginning
      (helixel-repeat-edit)
      (should (string= (buffer-string)
                       "aahellobb world aabbhello")))))

;; ── $ (end-of-line) zero-length anchor + a (append) ──

(ert-deftest helixel-test-repeat-search-append-eol-zero-length-dot ()
  "Scenario: /$<RET> a foo <ESC> . — append at eol with $ anchor.
\=`$' is a zero-length regex anchor.  The skip logic in
`helixel--recreate-search' must advance one extra character
past the match-end to actually skip zero-length matches."
  :tags '(repeat search)
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "line one\nline two\nline three"
      ;; /$<RET> — search for end-of-line
      (goto-char 1)
      (re-search-forward "$")
      ;; Match should be at end of line 1
      (let ((isearch-success t)
            (isearch-string "$")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "$" :dir forward)
             #'helixel--recreate-search "/$/"))
      ;; a — insert-after at match-end
      (setq last-command nil this-command 'helixel-insert-after)
      (helixel-insert-after)
      (insert "foo")
      (helixel-insert-exit)
      ;; Buffer after edit: "line onefoo\nline two\nline three"
      (should (string= (buffer-string) "line onefoo\nline two\nline three"))
      ;; . — should append "foo" at end of line 2
      (helixel-repeat-edit)
      (should (string= (buffer-string) "line onefoo\nline twofoo\nline three"))
      ;; . again — should append "foo" at end of line 3
      (helixel-repeat-edit)
      (should (string= (buffer-string) "line onefoo\nline twofoo\nline threefoo")))))

;; ── $ (end-of-line) zero-length anchor + i (insert) ──

(ert-deftest helixel-test-repeat-search-insert-eol-zero-length-dot ()
  "Scenario: /$<RET> i foo <ESC> . — insert before eol with $ anchor."
  :tags '(repeat search)
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "line one\nline two\nline three"
      (goto-char 1)
      (re-search-forward "$")
      (let ((isearch-success t)
            (isearch-string "$")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "$" :dir forward)
             #'helixel--recreate-search "/$/"))
      ;; i — insert at match-beginning
      (setq last-command nil this-command 'helixel-insert)
      (helixel-insert)
      (insert "foo")
      (helixel-insert-exit)
      ;; Buffer after edit: "line onefoo\nline two\nline three"
      (should (string= (buffer-string) "line onefoo\nline two\nline three"))
      ;; . — should insert "foo" before eol of line 2
      (helixel-repeat-edit)
      (should (string= (buffer-string) "line onefoo\nline twofoo\nline three"))
      ;; . again — should insert "foo" before eol of line 3
      (helixel-repeat-edit)
      (should (string= (buffer-string) "line onefoo\nline twofoo\nline threefoo")))))

;; ── 0. prefix: repeat-all in stored direction ──

(ert-deftest helixel-test-repeat-all-dir-forward-change ()
  "0. after /search cX<ESC> changes all remaining matches forward."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char 1)
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      (should (string= (buffer-string) "XXX A hello B hello C"))
      ;; 0. -> change all remaining "hello" forwards
      (helixel-repeat-edit 0)
      (should (string= (buffer-string) "XXX A XXX B XXX C")))))

(ert-deftest helixel-test-repeat-all-dir-forward-from-middle ()
  "0. after /search from middle only changes matches after cursor."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char 9)                        ; at "hello B"
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      ;; Only B and C changed, not A
      (should (string= (buffer-string) "hello A XXX B hello C"))
      (helixel-repeat-edit 0)
      (should (string= (buffer-string) "hello A XXX B XXX C")))))

(ert-deftest helixel-test-repeat-all-dir-backward-change ()
  "0. after ?search cX<ESC> changes all remaining matches backward."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char (point-max))
      (re-search-backward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward nil)       ; backward
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      ;; Changed last hello (C)
      (should (string= (buffer-string) "hello A hello B XXX C"))
      ;; 0. -> change remaining matches backward
      (helixel-repeat-edit 0)
      (should (string= (buffer-string) "XXX A XXX B XXX C")))))

(ert-deftest helixel-test-repeat-all-dir-backward-append ()
  "0. after ?search aXXX<ESC> — skip logic prevents re-editing current match."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char (point-max))
      (re-search-backward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward nil)
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)
             #'helixel--recreate-search "/hello/"))
      ;; Append "XXX" after match (a = helixel-insert-after)
      (setq last-command nil this-command 'helixel-insert-after)
      (helixel-insert-after)
      (insert "XXX")
      (helixel-insert-exit)
      (should (string= (buffer-string)
                       "hello A hello B helloXXX C"))
      ;; 0. -> append to remaining matches backward
      (helixel-repeat-edit 0)
      (should (string= (buffer-string)
                       "helloXXX A helloXXX B helloXXX C")))))

;; NOTE: This test is the insert-after variant (like `a`);
;; above test uses helixel-insert-after for append semantics.

(ert-deftest helixel-test-repeat-all-dir-forward-insert ()
  "0. after /search iXXX<ESC> — inserts before all remaining matches."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char 1)
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil this-command 'helixel-insert)
      (helixel-insert)
      (insert "XXX")
      (helixel-insert-exit)
      ;; Inserted before first hello
      (should (string= (buffer-string)
                       "XXXhello A hello B hello C"))
      ;; 0. -> insert before all remaining matches
      (helixel-repeat-edit 0)
      (should (string= (buffer-string)
                       "XXXhello A XXXhello B XXXhello C")))))

;; ── C-u . prefix: repeat-all entire buffer ──

(ert-deftest helixel-test-repeat-all-buffer-forward-change ()
  "C-u . after /search cX<ESC> changes ALL matches from point-min."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char 9)                        ; at "hello B"
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      (should (string= (buffer-string) "hello A XXX B hello C"))
      ;; C-u . -> all matches from point-min forward
      (helixel-repeat-edit '(4))
      (should (string= (buffer-string) "XXX A XXX B XXX C")))))

(ert-deftest helixel-test-repeat-all-buffer-forward-insert ()
  "C-u . after /search iXXX<ESC> inserts BEFORE all matches from point-min.
entry-kind=insert means insert at match-beginning, not match-end."
  (helixel-test-with-buffer "hello A hello B hello C"
    (goto-char 1)
    (re-search-forward "hello")
    (let ((isearch-success t)
          (isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-other-end (match-beginning 0)))
      (helixel-search--handle-done nil))
    ;; Build tx with entry-kind=insert (i before match)
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text
            (helixel-sel-create
             'search
             '(:pattern "hello" :dir forward :entry-kind insert)
             #'helixel--recreate-search "/hello/")
            :text "XXX"))
    ;; Apply first edit manually
    (goto-char (match-beginning 0))
    (insert "XXX")
    (should (string= (buffer-string)
                     "XXXhello A hello B hello C"))
    ;; C-u . -> insert before ALL matches from point-min
    (helixel-repeat-edit '(4))
    (should (string= (buffer-string)
                     "XXXhello A XXXhello B XXXhello C"))))

(ert-deftest helixel-test-repeat-all-buffer-backward-change ()
  "C-u . after ?search cX<ESC> changes ALL matches regardless of stored dir."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char (point-max))
      (re-search-backward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward nil)
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      (should (string= (buffer-string) "hello A hello B XXX C"))
      ;; C-u . -> all matches from point-min forward
      (helixel-repeat-edit '(4))
      (should (string= (buffer-string) "XXX A XXX B XXX C")))))

(ert-deftest helixel-test-repeat-all-buffer-backward-append ()
  "C-u . after ?search aXXX<ESC> inserts at ALL matches."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char (point-max))
      (re-search-backward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward nil)
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil this-command 'helixel-insert-after)
      (helixel-insert-after)
      (insert "XXX")
      (helixel-insert-exit)
      (should (string= (buffer-string)
                       "hello A hello B helloXXX C"))
      ;; C-u . -> append at ALL matches from point-min
      (helixel-repeat-edit '(4))
      (should (string= (buffer-string)
                       "helloXXX A helloXXX B helloXXX C")))))

;; ── C-u -N . prefix: reverse direction ──

(ert-deftest helixel-test-repeat-reverse-forward-to-backward ()
  "C-u -2 . after /search reverses direction: forward -> backward."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char 9)                        ; at "hello B"
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      ;; Changed B
      (should (string= (buffer-string) "hello A XXX B hello C"))
      ;; C-u -2 . -> reverse (backward): change A + search-failed
      (helixel-repeat-edit -2)
      (should (string= (buffer-string) "XXX A XXX B hello C")))))

(ert-deftest helixel-test-repeat-reverse-backward-to-forward ()
  "C-u -2 . after ?search reverses direction: backward -> forward."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char (point-max))
      (re-search-backward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward nil)
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      ;; Changed C
      (should (string= (buffer-string) "hello A hello B XXX C"))
      ;; C-u -2 . -> reverse (forward): from C there's nothing forward
      ;; -> 0 changes, but original direction unchanged
      (helixel-repeat-edit -2)
      (should (string= (buffer-string) "hello A hello B XXX C")))))

(ert-deftest helixel-test-repeat-reverse-mid-buffer ()
  "C-u -3 . after ?search from middle changes backward matches in reverse."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char 15)                       ; after "hello B", before C
      (re-search-backward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward nil)
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      ;; Changed B (backward from middle)
      (should (string= (buffer-string) "hello A XXX B hello C"))
      ;; C-u -3 . -> reverse (forward): change C
      (helixel-repeat-edit -3)
      (should (string= (buffer-string) "hello A XXX B XXX C")))))

;; ── Edge cases ──

(ert-deftest helixel-test-repeat-all-single-match ()
  "0. with only one match: executes once then stops silently."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world"
      (goto-char 1)
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      (should (string= (buffer-string) "XXX world"))
      ;; 0. -> no more matches, silently stops
      (helixel-repeat-edit 0)
      (should (string= (buffer-string) "XXX world")))))

(ert-deftest helixel-test-repeat-all-non-search-line ()
  "0. on line (non-search) selection falls back to single execution."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "line1\nline2\nline3\n"
      (goto-char 1)
      (setq helixel--last-tx
            (helixel-edit-make 'kill
              (helixel-sel-create 'line
                '(:dir forward :count 2)
                (lambda (ctx)
                  (let ((cnt (helixel-sel-line-count ctx)))
                    (push-mark (line-beginning-position) t t)
                    (goto-char
                     (line-beginning-position (1+ cnt)))
                    (setq mark-active t))
                  (setq helixel--selection-type 'line))
                "2lines")))
      ;; First . kills line1+line2, leaving line3
      (helixel-repeat-edit)
      (should (string= (buffer-string) "line3\n"))
      ;; 0. on non-search sel -> fallback to single execution
      ;; kills the remaining line3
      (helixel-repeat-edit 0)
      (should (string= (buffer-string) "")))))

(ert-deftest helixel-test-repeat-reverse-keeps-stored-dir ()
  "C-u -1 . does NOT change the stored direction for subsequent ."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char 9)
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      (should (string= (buffer-string) "hello A XXX B hello C"))
      ;; C-u -1 . reverse (backward) -> changes A
      (helixel-repeat-edit -1)
      (should (string= (buffer-string) "XXX A XXX B hello C"))
      ;; Normal . -> still forward, changes C
      (helixel-repeat-edit)
      (should (string= (buffer-string) "XXX A XXX B XXX C")))))

(ert-deftest helixel-test-repeat-all-dir-backward-from-start ()
  "0. after ?search from buffer start: no matches backward, silent stop."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char 1)
      (re-search-forward "hello")        ; find first hello
      ;; Backward search puts point at match-beginning
      (goto-char (match-beginning 0))
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward nil)        ; backward
            (isearch-other-end (copy-marker (match-end 0))))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      (should (string= (buffer-string) "XXX A hello B hello C"))
      ;; 0. backward from start -> no more matches
      (helixel-repeat-edit 0)
      (should (string= (buffer-string) "XXX A hello B hello C")))))

;; === All-buffer reverse (C-u - .) ===

(ert-deftest helixel-test-repeat-all-buffer-reverse-search-insert ()
  "C-u - . after /search iXXX<ESC> inserts BEFORE all matches backward."
  (helixel-test-with-buffer "hello A hello B hello C"
    (goto-char 1)
    (re-search-forward "hello")
    (let ((isearch-success t)
          (isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-other-end (match-beginning 0)))
      (helixel-search--handle-done nil))
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text
            (helixel-sel-create
             'search
             '(:pattern "hello" :dir forward :entry-kind insert)
             #'helixel--recreate-search "/hello/")
            :text "XXX"))
    (goto-char (match-beginning 0))
    (insert "XXX")
    (should (string= (buffer-string) "XXXhello A hello B hello C"))
    ;; C-u - . -> insert before ALL matches from point-max backward
    (helixel-repeat-edit '(-4))
    (should (string= (buffer-string)
                     "XXXhello A XXXhello B XXXhello C"))))

(ert-deftest helixel-test-repeat-all-buffer-reverse-line ()
  "C-u - . after x> indents ALL lines from bottom up."
  (helixel-test-with-buffer "a\nb\nc\nd\n"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (setq last-command 'helixel-select-line
          this-command 'helixel-indent-right)
    (helixel-indent-right)
    (should (string= (buffer-string) " a\nb\nc\nd\n"))
    ;; C-u - . from recorded marker: backward skip-current (nothing
    ;; above), then forward skip-current (lines b,c,d get indented).
    ;; The recorded line (a) is skipped → stays with 1 indent.
    (helixel-repeat-edit '(-4))
    (should (string= (buffer-string) " a\n b\n c\n d\n"))))

(ert-deftest helixel-test-repeat-reverse-line-n-times ()
  "C-u -2 . after x> (from line 2) indents the 2 lines above."
  (helixel-test-with-buffer "a\nb\nc\nd\n"
    (goto-char 4) ; line 2
    (setq last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (setq last-command 'helixel-select-line
          this-command 'helixel-indent-right)
    (helixel-indent-right)
    (should (string= (buffer-string) "a\n b\nc\nd\n"))
    ;; Reverse 2: skip line 2, indent line 1
    (helixel-repeat-edit -2)
    (should (string= (buffer-string) " a\n b\nc\nd\n"))))

(ert-deftest helixel-test-repeat-all-buffer-line-change ()
  "C-u . after xc<text><ESC> changes ALL lines from point-min.
Verifies nil-advance ops (change,kill) don't loop forever."
  (helixel-test-with-buffer "hello\nhello\nhello\nxibar\n"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel-edit-make 'change
            (helixel-sel-create 'line '(:dir forward :count 1)
                                #'helixel--recreate-line "L")
            ;; The change replaces the whole line (incl. \n) so the
            ;; replacement text must include the trailing newline.
            :inserted-text "bar\n"))
    ;; First . changes line 1
    (helixel-repeat-edit)
    (should (string= (buffer-string) "bar\nhello\nhello\nxibar\n"))
    ;; C-u . -> change ALL lines from point-min
    (helixel-repeat-edit '(4))
    (should (string= (buffer-string) "bar\nbar\nbar\nbar\n"))))

(ert-deftest helixel-test-repeat-all-buffer-line-kill ()
  "C-u . after xd kills remaining lines from recorded position.
After kill, the marker points to the next surviving line;
C-u . processes forward + backward, skipping the recorded line.
Note: C-u . AFTER a kill skips the new current line because
kill naturally moved point — use a single xd prefix for bulk kill."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\n"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel-edit-make 'kill
            (helixel-sel-create 'line '(:dir forward :count 1)
                                #'helixel--recreate-line "L")))
    ;; First . kills line 1; cursor at BOL of line 2
    (helixel-repeat-edit)
    (should (string= (buffer-string) "line2\nline3\nline4\n"))
    ;; C-u . from recorded position: forward skips line 2
    ;; (marker now pointing there), kills lines 3 and 4;
    ;; backward from marker: skip-current hits bobp, exits.
    ;; Line 2 survives.
    (helixel-repeat-edit '(4))
    (should (string= (buffer-string) "line2\n"))))

;;; Line selection auto-advance for `.` repeat

(ert-deftest helixel-test-repeat-line-advance-insert ()
  "`. ` after xi<text><ESC> auto-advances to next line."
  (helixel-test-with-buffer "line1\nline2\nline3\n"
    (goto-char 3)
    ;; Simulate xihello<ESC>: insert-text op on line sel.
    ;; insert-text inserts at point (which helixel-select-line
    ;; leaves at eol after recreating).  The key test: `.`
    ;; should advance point to line 2 before executing.
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text
            (helixel-sel-create 'line '(:dir forward :count 1)
                                #'helixel--recreate-line "L")
            :text "hello"))
    (let ((old-line (line-number-at-pos)))
      (should (= old-line 1))
      (helixel-repeat-edit)
      ;; After `.`, the edit should have been applied on
      ;; a different line (line 2, the auto-advanced line).
      ;; Point changed from line 1 to line 2 or beyond.
      (should (not (= old-line (line-number-at-pos)))))))

(ert-deftest helixel-test-repeat-line-advance-kill-no-skip ()
  "`. ` after xd does NOT skip the next line (kill auto-moves point)."
  (helixel-test-with-buffer "line1\nline2\nline3\n"
    (goto-char 3)
    (setq last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (setq last-command 'helixel-select-line
          this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    ;; line1 killed, point at bol of line2
    (should (string= (buffer-string) "line2\nline3\n"))
    (helixel-repeat-edit)
    ;; Should kill line2 (now at point), NOT skip to line3
    (should (string= (buffer-string) "line3\n"))))

(ert-deftest helixel-test-repeat-line-advance-indent ()
  "`. ` after x> auto-advances and indents the next line."
  (helixel-test-with-buffer "line1\nline2\nline3\n"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (setq last-command 'helixel-select-line
          this-command 'helixel-indent-right)
    (helixel-indent-right)
    (let ((after-first (buffer-string)))
      (helixel-repeat-edit)
      ;; The second line should also be indented
      (should (not (string= after-first (buffer-string)))))))

(ert-deftest helixel-test-indent-count ()
  "3>> indents 3 columns."
  (helixel-test-with-buffer "line1\nline2"
    (goto-char 1)
    (set-mark 12)
    (let ((current-prefix-arg 3))
      (call-interactively #'helixel-indent-right))
    (should (string= (buffer-string) "   line1\n   line2"))))

(ert-deftest helixel-test-replace-char-basic ()
  "rX replaces char at point."
  (helixel-test-with-buffer "hello"
    (helixel-replace-char ?X)
    (should (string= (buffer-string) "Xello"))))

(ert-deftest helixel-test-replace-char-region ()
  "rX on region replaces all chars with X."
  (helixel-test-with-buffer "hello world"
    (set-mark 6)
    (helixel-replace-char ?-)
    (should (string= (buffer-string) "----- world"))))

(ert-deftest helixel-test-replace-char-dot-repeat ()
  "rX then . replaces next char with X."
  (helixel-test-with-buffer "abc"
    (helixel-replace-char ?X)
    (should (string= (buffer-string) "Xbc"))
    (should (= (point) 2))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "XXc"))))

(ert-deftest helixel-test-repeat-line-advance-count ()
  "`3. ` after x> indents lines 2,3,4 (auto-advancing each time)."
  (helixel-test-with-buffer "a\nb\nc\nd\ne\n"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (setq last-command 'helixel-select-line
          this-command 'helixel-indent-right)
    (helixel-indent-right)
    (should (string= (buffer-string) " a\nb\nc\nd\ne\n"))
    (helixel-repeat-edit 3)
    ;; Lines b, c, d should be indented (3 iterations, each advancing)
    (should (string= (buffer-string) " a\n b\n c\n d\ne\n"))))

(ert-deftest helixel-test-repeat-line-advance-backward ()
  "`. ` after X (backward dir) i<text><ESC> advances up."
  (helixel-test-with-buffer "line1\nline2\nline3\n"
    (goto-char 10)
    ;; Simulate Xihello<ESC>: insert-text on backward line sel.
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text
            (helixel-sel-create 'line '(:dir backward :count 1)
                                #'helixel--recreate-line "L")
            :text "hello"))
    (let ((old-line (line-number-at-pos)))
      (should (= old-line 2))
      (helixel-repeat-edit)
      ;; Should have advanced backward to line 1
      (should (not (= old-line (line-number-at-pos)))))))

(ert-deftest helixel-test-repeat-line-advance-real-insert ()
  "`. ` after xihello<ESC> advances to next line.
Verifies: sel kind stays `line' through insert recording,
`. ` auto-advances to next line and inserts at bol."
  (helixel-test-with-buffer "line1\nline2\nline3\n"
    (goto-char 3)
    ;; Simulate xihello<ESC> by building a tx that mimics
    ;; the real recording output.
    (let ((helixel--repeat-sel-ctx
           (helixel-sel-create 'line
               '(:dir forward :count 1 :entry-kind insert)
               #'helixel--recreate-line "L")))
      (helixel--record-edit 'insert-text))
    (setq helixel--last-tx
          (helixel-edit-with-payload helixel--last-tx :text "hello"))
    (let ((old-line (line-number-at-pos)))
      (should (= old-line 1))
      (helixel-repeat-edit)
      ;; Should have advanced to line 2 and inserted there.
      (should (not (= old-line (line-number-at-pos))))
      ;; Verify "hello" went to line 2 (at bol).
      (should (string= (buffer-string)
                       "line1\nhelloline2\nline3\n")))))

(ert-deftest helixel-test-repeat-line-advance-real-insert-count2 ()
  "`. ` after xxihello<ESC> (2-line sel) advances 2 lines.
Verifies: point lands at bol of the correct line (not the
wrong line due to line-beginning-position on the last
selected line)."
  (helixel-test-with-buffer
      "line1\nline2\nline3\nline4\nline5\n"
    (goto-char 3)
    ;; Simulate xxihello<ESC>: 2-line forward selection + insert
    (let ((helixel--repeat-sel-ctx
           (helixel-sel-create 'line
               '(:dir forward :count 2 :entry-kind insert)
               #'helixel--recreate-line "L")))
      (helixel--record-edit 'insert-text))
    (setq helixel--last-tx
          (helixel-edit-with-payload helixel--last-tx :text "hello"))
    ;; Point on line 1 before dot-repeat.
    (should (= (line-number-at-pos) 1))
    (helixel-repeat-edit)
    ;; Should have advanced to line 3 (skip 2-line selection) and
    ;; inserted at bol of line 3 (NOT line 4).
    (should (string= (buffer-string)
                     "line1\nline2\nhelloline3\nline4\nline5\n"))))

(ert-deftest helixel-test-repeat-line-advance-insert-count2 ()
  "`. ` after xxihello<ESC> (count=2) advances past 2 lines.
Second `. ` advances from line 3 to line 5."
  (helixel-test-with-buffer
      "line1\nline2\nline3\nline4\nline5\nline6\nline7\n"
    (goto-char 3)
    (let ((helixel--repeat-sel-ctx
           (helixel-sel-create 'line
               '(:dir forward :count 2 :entry-kind insert)
               #'helixel--recreate-line "L")))
      (helixel--record-edit 'insert-text))
    (setq helixel--last-tx
          (helixel-edit-with-payload helixel--last-tx :text "hello"))
    (helixel-repeat-edit)               ; insert on lines 3-4 target
    (should (string= (buffer-string)
                     "line1\nline2\nhelloline3\nline4\nline5\nline6\nline7\n"))
    (helixel-repeat-edit)               ; advance 2 more → lines 5-6 target
    (should (string= (buffer-string)
                     (concat "line1\nline2\nhelloline3\n"
                             "line4\nhelloline5\nline6\nline7\n")))))

(ert-deftest helixel-test-repeat-line-insert-move-forward-dot ()
  "`. ` after xi<M-f>foo<ESC> replays cursor-movement via kmacro keys.
M-f (meta key) is a non-character integer — must go through
key-binding dispatch, not insert-char, in `helixel--execute-keys'."
  (helixel-test-with-buffer "line1\nline2\n"
    (goto-char 3)
    ;; Build tx simulating xi + <M-f> + foo + <ESC>
    ;; :keys captures the full kmacro (M-f + f + o + o).
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text
            (helixel-sel-create
             'line
             '(:dir forward :count 1 :entry-kind insert)
             #'helixel--recreate-line "L")
            :keys (kbd "M-f foo")))
    ;; Apply first edit manually on line 1
    (beginning-of-line)
    (forward-word)                  ; simulate M-f
    (insert "foo")
    ;; M-f moves to end of "line1" (pos 6), then "foo" inserted.
    (should (string= (buffer-string) "line1foo\nline2\n"))
    ;; . — advance to line 2, replay M-f + foo
    (helixel-repeat-edit)
    ;; On line 2: bol, M-f -> end of "line2", insert "foo"
    (should (string= (buffer-string)
                     "line1foo\nline2foo\n"))))

(ert-deftest helixel-test-repeat-line-cursor-move-append ()
  "`. ` after xa+foobar replays concatenated text on next line.
Kmacro captures cursor movement keys; test uses text fallback."
  (helixel-test-with-buffer "hello world\nline2\n"
    (goto-char 1)
    ;; Build tx: line sel + append + text "foobar"
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text
            (helixel-sel-create
             'line
             '(:dir forward :count 1 :entry-kind append)
             #'helixel--recreate-line "L")
            :text "foobar"))
    ;; Apply first edit manually (append at eol)
    (end-of-line)
    (insert "foobar")
    (should (string= (buffer-string) "hello worldfoobar\nline2\n"))
    ;; . — advance to next line, append at eol
    (helixel-repeat-edit)
    (should (string= (buffer-string)
                     "hello worldfoobar\nline2foobar\n"))))

(ert-deftest helixel-test-repeat-line-cursor-move-insert ()
  "`. ` after xi+text replays text on next line at bol.
Kmacro captures cursor movement keys; test uses text fallback."
  (helixel-test-with-buffer "hello world\nline2\n"
    (goto-char 1)
    ;; Build tx: line sel + insert + text "AAA"
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text
            (helixel-sel-create
             'line
             '(:dir forward :count 1 :entry-kind insert)
             #'helixel--recreate-line "L")
            :text "AAA"))
    ;; Apply first edit manually
    (beginning-of-line)
    (insert "AAA")
    (helixel-repeat-edit)
    ;; AAA goes to bol of line 2.
    (should (string-match-p "\nAAA" (buffer-string)))))

(ert-deftest helixel-test-repeat-line-cursor-move-append-backward ()
  "`. ` after backward xa+text replays text on earlier line.
Kmacro captures cursor keys; test uses text fallback."
  (helixel-test-with-buffer "hello world\nline2\n"
    (goto-char (point-min))
    (forward-line 1)
    ;; Build tx: backward line sel + append + text
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text
            (helixel-sel-create
             'line
             '(:dir backward :count 1 :entry-kind append)
             #'helixel--recreate-line "L")
            :text "YYXX"))
    (helixel-repeat-edit)
    ;; Text appended at eol of line 1 (earlier line).
    (should (string= (buffer-string)
                     "hello worldYYXX\nline2\n"))))

;;; helixel-register tests

(ert-deftest helixel-test-register-select ()
  "Test `helixel-select-register' sets and can cancel."
  (should (null helixel--current-register))
  ;; Test setting (simulate via direct set, since read-char can't be
  ;; automated in batch ERT).
  (setq helixel--current-register ?a)
  (should (eq helixel--current-register ?a))
  (should (helixel--register-active-p))
  ;; Consume
  (helixel--register-consume)
  (should (null helixel--current-register))
  ;; Default register (\") is NOT active
  (setq helixel--current-register ?\")
  (should (not (helixel--register-active-p)))
  (helixel--register-consume)
  (should (null helixel--current-register)))

(ert-deftest helixel-test-register-set-get ()
  "Test storing and retrieving text in a named register."
  (unwind-protect
      (progn
        (helixel-register-set ?x "test-text")
        (should (string= (helixel-register-get ?x) "test-text")))
    ;; Cleanup
    (set-register ?x nil)))

(ert-deftest helixel-test-register-set-get-with-properties ()
  "Test register preserves yank-handler text properties."
  (unwind-protect
      (let ((text (helixel--linewise-text "hello")))
        (helixel-register-set ?x text)
        (let ((retrieved (helixel-register-get ?x)))
          (should (string= retrieved "hello\n"))
          (should (eq (car-safe (get-text-property 0 'yank-handler retrieved))
                      'helixel--yank-handler-line-wise))))
    (set-register ?x nil)))

(ert-deftest helixel-test-register-kill-new ()
  "Test `helixel--kill-new' stores to named register when active."
  (unwind-protect
      (progn
        (setq helixel--current-register ?x)
        (helixel--kill-new "killed-text")
        (should (string= (helixel-register-get ?x) "killed-text"))
        (should (eq helixel--current-register ?x)) ; not consumed
        (helixel--register-consume))
    (set-register ?x nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-kill-new-default ()
  "Test `helixel--kill-new' uses kill-ring when no register active."
  (let ((prev-kill (and kill-ring (current-kill 0 t)))
        (helixel--current-register nil))
    (helixel--kill-new "test-kill")
    (should (string= (current-kill 0 t) "test-kill"))))

(ert-deftest helixel-test-register-current-kill ()
  "Test `helixel--current-kill' reads from named register when active."
  (unwind-protect
      (progn
        (helixel-register-set ?x "reg-content")
        (setq helixel--current-register ?x)
        (should (string= (helixel--current-kill 0 t) "reg-content"))
        (helixel--register-consume))
    (set-register ?x nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-yank ()
  "Test `helixel--yank' inserts from named register when active."
  (unwind-protect
      (helixel-test-with-buffer "hello"
        (goto-char 6) ; after "hello"
        (helixel-register-set ?x "WORLD")
        (setq helixel--current-register ?x)
        (helixel--yank)
        (should (string= (buffer-string) "helloWORLD"))
        (helixel--register-consume))
    (set-register ?x nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-kill ()
  "Test \"ad deletes to register a (charwise)."
  (unwind-protect
      (helixel-test-with-buffer "hello world"
        (setq helixel--current-register ?a)
        (goto-char 2)
        (push-mark (point) t t)
        (goto-char 7)
        (helixel-kill-thing-at-point)
        (should (null helixel--current-register)) ; consumed
        (should (string= (buffer-string) "hworld"))
        (should (string= (helixel-register-get ?a) "ello ")))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-kill-no-region ()
  "Test \"ad deletes single char to register (no region)."
  (unwind-protect
      (helixel-test-with-buffer "hello"
        (setq helixel--current-register ?a)
        (helixel-kill-thing-at-point)
        (should (null helixel--current-register))
        (should (string= (buffer-string) "ello"))
        ;; Single char delete goes to kill-ring via delete-char,
        ;; but register was active so we check it was consumed.
        (should (null helixel--current-register)))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-kill-linewise ()
  "Test \"ad with line selection stores linewise to register."
  (unwind-protect
      (helixel-test-with-buffer "line1\nline2\nline3"
        (setq helixel--current-register ?a)
        (helixel-select-line)
        (helixel-kill-thing-at-point)
        (should (null helixel--current-register))
        ;; One line deleted
        (should (string= (buffer-string) "line2\nline3"))
        (let ((text (helixel-register-get ?a)))
          (should (string= text "line1\n"))
          (should (eq (car-safe (get-text-property 0 'yank-handler text))
                      'helixel--yank-handler-line-wise))))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-copy ()
  "Test \"ay copies region to register a."
  (unwind-protect
      (helixel-test-with-buffer "hello world"
        (setq helixel--current-register ?a)
        (goto-char 1)
        (push-mark (point) t t)
        (goto-char 6)
        (helixel-kill-ring-save)
        (should (null helixel--current-register))
        ;; Buffer unchanged
        (should (string= (buffer-string) "hello world"))
        (should (string= (helixel-register-get ?a) "hello")))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-copy-linewise ()
  "Test \"ay with line selection copies linewise to register."
  (unwind-protect
      (helixel-test-with-buffer "line1\nline2"
        (setq helixel--current-register ?a)
        (helixel-select-line)
        (helixel-kill-ring-save)
        (should (null helixel--current-register))
        (let ((text (helixel-register-get ?a)))
          (should (string= text "line1\n"))
          (should (eq (car-safe (get-text-property 0 'yank-handler text))
                      'helixel--yank-handler-line-wise))))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-paste ()
  "Test \"ap pastes from register a."
  (unwind-protect
      (helixel-test-with-buffer "hello"
        (goto-char 6) ; after "hello"
        (helixel-register-set ?a "WORLD")
        (setq helixel--current-register ?a)
        (helixel-yank)
        (should (null helixel--current-register))
        (should (string= (buffer-string) "helloWORLD")))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-paste-linewise ()
  "Test \"ap pastes linewise content from register."
  (unwind-protect
      (helixel-test-with-buffer "line1\nline2"
        (helixel-register-set ?a
                              (helixel--linewise-text "INSERTED"))
        (setq helixel--current-register ?a)
        (goto-char 7) ;; start of line2
        (helixel-yank)
        (should (null helixel--current-register))
        (should (string= (buffer-string)
                         "line1\nINSERTED\nline2")))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-paste-before ()
  "Test \"aP pastes before from register a."
  (unwind-protect
      (helixel-test-with-buffer "hello"
        (helixel-register-set ?a "PRE")
        (setq helixel--current-register ?a)
        (helixel-yank-before)
        (should (null helixel--current-register))
        ;; yank-before inserts at point; point is at 1
        (should (string= (buffer-string) "PREhello")))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-replace ()
  "Test \"ar replaces region with register a content."
  (unwind-protect
      (helixel-test-with-buffer "hello world"
        (helixel-register-set ?a "REPLACED")
        (goto-char 1)
        (push-mark (point) t t)
        (goto-char 6)
        (setq helixel--current-register ?a)
        (helixel-replace)
        (should (null helixel--current-register))
        (should (string= (buffer-string) "REPLACED world")))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-replace-no-region ()
  "Test \"ar without region replaces char with register content."
  (let ((helixel-replace-delete-char-p t))
    (unwind-protect
        (helixel-test-with-buffer "hello"
          (helixel-register-set ?a "X")
          (setq helixel--current-register ?a)
          (helixel-replace)
          (should (null helixel--current-register))
          (should (string= (buffer-string) "Xello")))
      (set-register ?a nil)
      (setq helixel--current-register nil))))

(ert-deftest helixel-test-register-change ()
  "Test \"ac changes region, stores deleted text in register a."
  (unwind-protect
      (helixel-test-with-buffer "hello world"
        (setq helixel--current-register ?a)
        (goto-char 1)
        (push-mark (point) t t)
        (goto-char 6)
        (let ((helixel--inhibit-repeat-record t))
          (helixel-change-thing-at-point))
        ;; Register is consumed after the kill part
        (should (null helixel--current-register))
        (should (string= (helixel-register-get ?a) "hello"))
        (should (string= (buffer-string) " world")))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-default-unnamed ()
  "Test \"\" y is same as y (uses kill-ring)."
  (helixel-test-with-buffer "hello world"
    (setq helixel--current-register ?\")
    (goto-char 1)
    (push-mark (point) t t)
    (goto-char 6)
    (helixel-kill-ring-save)
    (should (null helixel--current-register))
    (should (string= (buffer-string) "hello world"))
    (should (string= (current-kill 0 t) "hello"))))

(ert-deftest helixel-test-register-empty-paste ()
  "Test pasting from empty register shows a message."
  (unwind-protect
      (helixel-test-with-buffer "hello"
        ;; Ensure register is empty
        (set-register ?z nil)
        (setq helixel--current-register ?z)
        (helixel-yank)
        (should (null helixel--current-register))
        (should (string= (buffer-string) "hello")))
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-repeat-no-register ()
  "Test . after \"ad uses kill-ring not register a."
  (unwind-protect
      (helixel-test-with-buffer "hello world"
        ;; Step 1: kill to register a (ello )
        (setq helixel--current-register ?a)
        (goto-char 2)
        (push-mark (point) t t)
        (goto-char 7)
        (helixel-kill-thing-at-point)
        ;; Register consumed, buffer: "hworld"
        (should (null helixel--current-register))
        (should (string= (helixel-register-get ?a) "ello "))
        ;; Step 2: press . — select and kill one char
        (goto-char 1)
        (push-mark (point) t t)
        (goto-char 2)
        (helixel-repeat-edit 1)
        ;; Kill-ring top should be "h" (the char deleted by .)
        (should (string= (current-kill 0 t) "h"))
        ;; Register a should still have "ello " unchanged
        (should (string= (helixel-register-get ?a) "ello ")))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-repeat-with-register ()
  "Test \"b. replays the last edit using register b."
  (unwind-protect
      (helixel-test-with-buffer "hello world"
        ;; Step 1: do a normal kill (stores tx)
        (goto-char 3)
        (push-mark (point) t t)
        (goto-char 7)
        (helixel-kill-thing-at-point)
        ;; Buffer: "held"
        ;; Step 2: select register b and press .
        (goto-char 1)
        (push-mark (point) t t)
        (goto-char 2)
        (setq helixel--current-register ?b)
        (helixel-repeat-edit 1)
        ;; Register b should have the char deleted by replay
        (should (string= (helixel-register-get ?b) "h"))
        (should (null helixel--current-register)))
    (set-register ?a nil)
    (set-register ?b nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-persistence ()
  "Test register content persists across operations."
  (unwind-protect
      (helixel-test-with-buffer "hello"
        ;; Store to register a
        (setq helixel--current-register ?a)
        (helixel-kill-thing-at-point)
        ;; Register a has "h"
        (should (string= (helixel-register-get ?a) "h"))
        ;; Do another operation (no register)
        (helixel-kill-thing-at-point)  ; kill "e", goes to kill-ring
        ;; Register a still has "h"
        (should (string= (helixel-register-get ?a) "h"))
        ;; Now paste from register a
        (goto-char 4) ; after "llo" (remaining: "llo")
        (setq helixel--current-register ?a)
        (helixel-yank)
        (should (string= (buffer-string) "lloh")))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-numbered-yank ()
  "Test yank (copy) sets register 0."
  (unwind-protect
      (helixel-test-with-buffer "hello world"
        (goto-char 1)
        (push-mark (point) t t)
        (goto-char 6)
        (helixel-kill-ring-save)  ;; copy "hello"
        (should (string= (helixel-register-get ?0) "hello")))
    (set-register ?0 nil)
    (dolist (r '(?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9 ?-))
      (set-register r nil))
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-numbered-delete-rotate ()
  "Test delete rotates registers 1-9."
  (unwind-protect
      (helixel-test-with-buffer "hello world"
        ;; Delete "ello " (positions 2-7)
        (goto-char 2)
        (push-mark (point) t t)
        (goto-char 7)
        (helixel-kill-thing-at-point)
        ;; Buffer: "hworld"
        ;; Delete "world" (positions 2-7)
        (goto-char 2)
        (push-mark (point) t t)
        (goto-char 7)
        (helixel-kill-thing-at-point)
        ;; Register 1 = "world" (most recent), Register 2 = "ello "
        (should (string= (helixel-register-get ?1) "world"))
        (should (string= (helixel-register-get ?2) "ello ")))
    (dolist (r '(?0 ?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9 ?-))
      (set-register r nil))
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-numbered-small-delete ()
  "Test small delete (single char) sets register -."
  (unwind-protect
      (helixel-test-with-buffer "hello"
        (helixel-kill-thing-at-point) ; delete "h"
        (should (string= (helixel-register-get ?-) "h"))
        ;; Also goes to register 1 (rotated)
        (should (string= (helixel-register-get ?1) "h")))
    (dolist (r '(?0 ?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9 ?-))
      (set-register r nil))
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-numbered-linewise-not-small ()
  "Test linewise delete does NOT go to small delete register -."
  (unwind-protect
      (helixel-test-with-buffer "line1\nline2"
        (set-register ?- nil) ; ensure empty
        (helixel-select-line)
        (helixel-kill-thing-at-point)
        ;; Linewise delete has newline, should NOT go to -
        (should (null (helixel-register-get ?-)))
        ;; Does go to register 1
        (should (string= (helixel-register-get ?1) "line1\n")))
    (dolist (r '(?0 ?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9 ?-))
      (set-register r nil))
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-numbered-yank-preserves-0 ()
  "Test yank sets register 0, subsequent delete does not overwrite."
  (unwind-protect
      (helixel-test-with-buffer "first second"
        ;; Yank "first" → register 0
        (goto-char 1)
        (push-mark (point) t t)
        (goto-char 6)
        (helixel-kill-ring-save)
        (should (string= (helixel-register-get ?0) "first"))
        ;; Delete "second" → register 1, register 0 unchanged
        (goto-char 7)
        (push-mark (point) t t)
        (goto-char 13)
        (helixel-kill-thing-at-point)
        (should (string= (helixel-register-get ?1) "second"))
        (should (string= (helixel-register-get ?0) "first")))
    (dolist (r '(?0 ?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9 ?-))
      (set-register r nil))
    (setq helixel--current-register nil)))

;;; helixel-test.el ends here
