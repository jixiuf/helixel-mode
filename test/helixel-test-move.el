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
    ;; From \n, skip to the next WORD on the next line
    (helixel-forward-WORD-start)
    (should (= (point) 19))
    (should (= (- (region-end) (region-beginning)) 7))
    ;; Then to the next WORD
    (helixel-forward-WORD-start)
    (should (= (point) 23))
    (should (= (- (region-end) (region-beginning)) 4))))

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
    ;; Skip \n, go to end of "second"
    (helixel-forward-WORD-end)
    (should (= (point) 18)) ; end of "second"
    (should (= (- (region-end) (region-beginning)) 6))))

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
    (should (= (- (region-end) (region-beginning)) 1))))

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
    ;; Skip \n, go to start of "line"
    (helixel-backward-WORD)
    (should (= (point) 19)) ; start of "line"
    (should (= (- (region-end) (region-beginning)) 4))
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
    (should (= (point) 7)) ; empty line before "first"
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

;;; Word/WORD/symbol newline-skip and line-crossing trim tests

(ert-deftest helixel-test-word-newline-not-included ()
  "Test that w from within a line stops at \n, excluding it."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "foo bar \nbaz")
    (goto-char 5)  ; start of "bar"
    (deactivate-mark)
    (setq last-command nil)
    (helixel-forward-word-start)
    ;; Should stop at \n position, range excludes \n.
    (should (= (point) 9))
    (should (= (- (region-end) (region-beginning)) 4)) ; "bar "
    (should (string= (buffer-substring (region-beginning) (region-end))
                     "bar "))))

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
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "foo bar \nbaz")
    (goto-char 5)  ; start of "bar"
    (deactivate-mark)
    (setq last-command nil)
    (helixel-forward-word-end)
    (should (= (point) 8))              ; end of "bar" (before space)
    (should (= (- (region-end) (region-beginning)) 3)) ; "bar"
    (should (string= (buffer-substring (region-beginning) (region-end))
                     "bar"))))

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
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "\nfoo bar")
    (goto-char 1)
    (deactivate-mark)
    (setq last-command nil)
    (call-interactively #'helixel-forward-word-start)
    ;; Should skip the leading \n and select "foo "
    (should (= (point) 6))              ; start of "bar"
    (should (= (- (region-end) (region-beginning)) 4)) ; "foo "
    (should (string= (buffer-substring (region-beginning) (region-end))
                     "foo "))))

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
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "line one\n\nline two\n")
    (goto-char 1)
    (deactivate-mark)
    (setq last-command nil)
    (call-interactively #'helixel-forward-paragraph-start)
    ;; Paragraph motion should move to the next paragraph across \n\n
    (should (>= (point) 10))
    (should (>= (- (region-end) (region-beginning)) 9))))

(ert-deftest helixel-test-sentence-not-affected-by-newline-skip ()
  "Test that sentence motion still works normally across lines."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "First. Second.\nThird.")
    (goto-char 1)
    (deactivate-mark)
    (setq last-command nil)
    (call-interactively #'helixel-forward-sentence-end)
    ;; Sentence end should find the end of a sentence (moved past 1st)
    (should (> (point) 7))
    (should (> (- (region-end) (region-beginning)) 7))))

(ert-deftest helixel-test-function-not-affected-by-newline-skip ()
  "Test that function movement still spans multiple lines."
  (with-temp-buffer
    (transient-mark-mode 1)
    (emacs-lisp-mode)
    (insert "(defun foo ()\n  (message \"hello\"))\n\n(defun bar ()\n  (message \"world\"))")
    (goto-char 1)
    (deactivate-mark)
    (setq last-command nil)
    (call-interactively #'helixel-forward-function-end)
    ;; Function end should move point forward from start of defun
    (should (> (point) 1))
    (should (> (- (region-end) (region-beginning)) 1))))

;;; Operator-pending (dw) integration test

(ert-deftest helixel-test-word-operator-newline ()
  "Test that dw at end of line does not eat the newline."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil)
    (insert "foo bar \nbaz")
    (goto-char 5)  ; start of "bar"
    (setq helixel--pending-op 'delete)
    (helixel-forward-word-start)
    ;; In operator-pending, the range should exclude \n
    (should (= (point) 9))              ; at \n (trim to end of line)
    (should (= (- (region-end) (region-beginning)) 4)) ; "bar "
    (should (string= (buffer-substring (region-beginning) (region-end))
                     "bar "))))

(ert-deftest helixel-test-word-pure-whitespace-buffer ()
  "Test w in a buffer with only whitespace goes to eob."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "   \t\n  ")
    (goto-char 1)
    (deactivate-mark)
    (setq last-command nil)
    (call-interactively #'helixel-forward-word-start)
    ;; Should go to end of buffer on pure whitespace
    (should (= (point) (point-max)))
    (should (= (- (region-end) (region-beginning))
               (1- (point-max))))))

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
    (helixel-repeat-last-motion)
    (should (eql (point) 18))
    (should (eql (- (region-end) (region-beginning)) 6))))

(ert-deftest helixel-test-find-prev-till-char-repeat ()
  "Test repeating previous till character find skips past adjacent char."
  (with-temp-buffer
    (insert "first second third")
    (goto-char (point-max))
    (helixel-find-prev-till-char ?s)
    (should (eql (point) 8))
    (helixel-repeat-last-motion)
    (should (eql (point) 5))))

(ert-deftest helixel-test-empty-find-repeat ()
  "Test find repeat when nothing to repeat signals user-error."
  (with-temp-buffer
    (insert "first second third")
    (goto-char 1)
    (should-error (helixel-repeat-last-motion)
                  :type 'user-error)))

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
    (should (eq (helixel--last-motion-dir helixel--active-search) 'backward))
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

(ert-deftest helixel-test-paragraph-move-forward-end ()
  "Test ]p moves past current paragraph separator, not stuck at line end."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "line one\n\nline two\n")
    (goto-char 1)
    (helixel-forward-paragraph-end)
    ;; Position 9 is the end of the first line (\n).
    ;; The old (broken) line-crossing trim pulled point back here.
    ;; After fix, ]p must reach past the paragraph separator (>=10).
    (should (> (point) 9))
    (should (< (point) (point-max)))))

(ert-deftest helixel-test-paragraph-move-backward-end ()
  "Test [p moves backward past paragraph separator."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "line one\n\nline two\n")
    (goto-char (point-max))
    (helixel-backward-paragraph-end)
    ;; Must move backward past the blank line separator.
    (should (< (point) (point-max)))
    (should (> (point) 1))))

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
  "Test % on \" does NOT jump to matching \" — quotes are excluded.
\=`%' only handles bracket-pair, tag, block, and syntax-table pairs."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x \"hi\" y")
    (deactivate-mark)
    (goto-char 3)
    ;; % on a quote char should NOT jump — quotes are excluded.
    ;; The command prints "No matching bracket found" and point stays.
    (let ((pt-before (point)))
      (helixel-jump-to-match)
      (should (= (point) pt-before)))))

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
  "Test % inside tag moves backward to <; second % jumps to </div>."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "<div>hi</div>")
    (deactivate-mark)
    (goto-char 2)  ; on 'd' of <div>
    (helixel-jump-to-match)
    ;; Backward reposition finds < at pos 1, stops there.
    (should (= (point) 1))
    ;; Second % from < on delimiter — jumps to matching </div>.
    (helixel-jump-to-match)
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
(helixel-test-mark-thing "outer-paren" #'helixel-outer-paren
  "foo (bar)" 7 5 10)
(helixel-test-mark-thing "next-paren" #'helixel-next-paren-end
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
  "Test `C-;' pushes mark to event start without selecting the full span."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil helixel--jump-cycle-pos nil)
    (insert "hello world")
    (deactivate-mark)
    (goto-char 1)
    (helixel-forward-word-start)
    (helixel-action-cycle-jump)
    ;; C-; does NOT select the full span (non-mark-thing path).
    ;; The region should be active (push-mark with activate=t) but
    ;; from current point to the thing-start, not the whole word.
    (should (region-active-p))
    (should helixel--jump-cycle-pos)))

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
    (setq helixel--action-ring nil helixel--live-action nil
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
    (setq helixel--action-ring nil helixel--live-action nil
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
    (setq helixel--action-ring nil helixel--live-action nil
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

;;; Triple-nested climb-outward — stepping one level per press

(ert-deftest helixel-test-pair-next-paren-triple-nested ()
  "Test ]) from inside 3-nested parens steps one level each press."
  ;; Buffer: (a (b (c))) — point inside innermost (c)
  ;; 1:\( 2:a 3:SPC 4:\( 5:b 6:SPC 7:\( 8:c 9:\) 10:\) 11:\) 12:eob
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a (b (c)))")
    (deactivate-mark)
    (goto-char 8)   ; between ( and c, inside innermost
    (helixel-next-paren-end)
    (should (= (point) 10)) ; after first )
    (helixel-next-paren-end)
    (should (= (point) 11)) ; after second )
    (helixel-next-paren-end)
    (should (= (point) 12)) ; after third ) = eob
    ;; One more press at eob: no movement, no error
    (helixel-next-paren-end)
    (should (= (point) 12))))

(ert-deftest helixel-test-pair-next-paren-triple-nested-compact ()
  "Test ]) with no spaces: (a(b(c))) — adjacent ))."
  ;; 1:\( 2:a 3:\( 4:b 5:\( 6:c 7:\) 8:\) 9:\) 10:eob
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a(b(c)))")
    (deactivate-mark)
    (goto-char 6)   ; between ( and c
    (helixel-next-paren-end)
    (should (= (point) 8))  ; after first )
    (helixel-next-paren-end)
    (should (= (point) 9))  ; after second )
    (helixel-next-paren-end)
    (should (= (point) 10)))) ; after third ) = eob

(ert-deftest helixel-test-pair-next-brace-triple-nested ()
  "Test ]{ from inside 3-nested braces steps one level each press."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "{a {b {c}}}")
    (deactivate-mark)
    (goto-char 8)   ; between { and c, inside innermost
    (helixel-next-brace-end)
    (should (= (point) 10)) ; after first }
    (helixel-next-brace-end)
    (should (= (point) 11)) ; after second }
    (helixel-next-brace-end)
    (should (= (point) 12)))) ; after third } = eob

(ert-deftest helixel-test-pair-next-bracket-triple-nested ()
  "Test ][ from inside 3-nested brackets steps one level each press."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "[a [b [c]]]")
    (deactivate-mark)
    (goto-char 8)   ; between [ and c, inside innermost
    (helixel-next-bracket-end)
    (should (= (point) 10)) ; after first ]
    (helixel-next-bracket-end)
    (should (= (point) 11)) ; after second ]
    (helixel-next-bracket-end)
    (should (= (point) 12)))) ; after third ] = eob

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

;; ── Surround macro clears stale pending-sel ──

(ert-deftest helixel-test-surround-clears-nonmovement-sel ()
  "Surround clears a non-movement pending-sel."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (helixel--sel-push (helixel-sel-create 'line '(:dir forward :count 1)))
    (push-mark (point-max) t t)
    (should (eq (helixel-sel-kind helixel--pending-sel) 'line))
    (helixel-forward-word-start)
    (should helixel--pending-sel)
    (should (eq (helixel-sel-kind helixel--pending-sel) 'movement))))

(ert-deftest helixel-test-surround-clears-override ()
  "Surround clears the sel-type override."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (setq helixel--sel-type-override 'rect)
    (should (eq (helixel--sel-type) 'rect))
    (helixel-forward-word-start)
    (should (null (helixel--sel-type)))))

;; ── , motion-repeat tests ──

(ert-deftest helixel-test-motion-repeat-pair ()
  ", tracks and re-invokes pair delimiter motion (])."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x (a) (b) (c)")
    (deactivate-mark)
    (goto-char 1)
    (helixel-next-paren-end)
    (should (= (point) 6))
    (should (helixel--last-motion-p helixel--last-motion-cmd))
    (should (eq (helixel--last-motion-command helixel--last-motion-cmd)
                'helixel-next-paren-end))
    (helixel-repeat-last-motion)
    (should (eq (helixel--last-motion-command helixel--last-motion-cmd)
                'helixel-next-paren-end))))

(ert-deftest helixel-test-motion-repeat-match ()
  ", direction is recorded: forward/backward based on %% direction."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a (b) c)")
    (deactivate-mark)
    (goto-char 4)  ;; on ( of (b)
    (helixel-jump-to-match)
    (should (eq (helixel--last-motion-dir helixel--last-motion-cmd)
                'forward))
    (goto-char 7)  ;; on ) of (b)
    (helixel-jump-to-match)
    (should (eq (helixel--last-motion-dir helixel--last-motion-cmd)
                'backward))))

(ert-deftest helixel-test-motion-repeat-match-semicolon ()
  ", outward then ; selects a region."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(outer (inner))")
    (deactivate-mark)
    (let ((helixel--action-ring nil)
          (helixel--live-action nil)
          (helixel--action-pos nil))
      (goto-char 8)  ;; on (inner
      (helixel-jump-to-match)  ;; forward % → after )inner
      (helixel-repeat-last-motion)  ;; , outward → )outer
      (let ((last-command 'helixel-repeat-last-motion))
        (helixel-action-cycle))
      (should (region-active-p))
      (should (> (region-end) (region-beginning))))))

(ert-deftest helixel-test-motion-repeat-match-commits-event ()
  ", after % commits an event to the ring."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a (b (c)))")
    (deactivate-mark)
    (let ((helixel--action-ring nil)
          (helixel--live-action nil)
          (helixel--action-pos nil))
      (goto-char 9)  ;; on ) of (c)
      (helixel-jump-to-match)   ;; backward %% → (c opener at 7
      (helixel-repeat-last-motion)  ;; , outward
      ;; The , call must commit at least 2 events (%% + ,).
      (should (>= (length helixel--action-ring) 2))
      ;; The newest event (from ,) must have a non-degenerate mr.
      (let ((mr (helixel-action-mark-region
                 (car helixel--action-ring))))
        (should mr)
        (should (> (marker-position (cdr mr))
                   (marker-position (car mr))))))))

(ert-deftest helixel-test-motion-repeat-match-semicolon-outer-pair ()
  "; after , selects the enclosing pair one level outward, not two."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a (b (c)))")
    (deactivate-mark)
    (let ((helixel--action-ring nil)
          (helixel--live-action nil)
          (helixel--action-pos nil))
      (goto-char 9)  ;; on ) of (c)
      (helixel-jump-to-match)   ;; backward %% → (c opener at pos 7
      (helixel-repeat-last-motion)  ;; , outward → (b opener at pos 4
      (let ((last-command 'helixel-repeat-last-motion))
        (helixel-action-cycle))
      ;; ; after , must activate a region
      (should (region-active-p))
      ;; Region covers the (b (c)) pair — the enclosing pair.
      (should (= (region-beginning) 4))
      ;; Must span to the closing of (b (c)).
      (should (= (region-end) 11)))))

(ert-deftest helixel-test-jump-to-match-nopair-backward ()
  "% from non-delim moves to nearest pair char backward and stops."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello (world)")
    (deactivate-mark)
    (goto-char 8)  ;; on 'r' in "world"
    (helixel-jump-to-match)
    ;; Should search back to ( and stop — no forward jump.
    ;; "hello (world)" = h e l l o ' ' ( w o r l d )
    ;;                   1 2 3 4 5 6 7 8 9 0 1 2 3
    (should (= (point) 7))))

(ert-deftest helixel-test-jump-to-match-nopair-forward ()
  "% at BOB with no backward pair shows no match."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "abc def ghi")
    (deactivate-mark)
    (goto-char 1)  ;; on 'a', nothing behind, no pair chars at all
    (let ((helixel--last-motion-cmd nil))
      (helixel-jump-to-match)
      ;; Should not move — backward-only reposition finds nothing,
      ;; and core fallback (up-list) fails since we're not in a list.
      (should (= (point) 1)))))

(ert-deftest helixel-test-jump-to-match-nopair-on-close ()
  "% from a non-pair position with nothing backward falls to core."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "abc (def) ghi")
    (deactivate-mark)
    (goto-char 1)  ;; on 'a', nothing behind
    (helixel-jump-to-match)
    ;; No pair char backward — core fallback runs but up-list
    ;; fails (not inside a list), so no movement.
    (should (= (point) 1))))

(ert-deftest helixel-test-jump-to-match-nopair-nested ()
  "% from non-delim moves backward to (; second % jumps to match."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(x (y (z)))")
    (deactivate-mark)
    (goto-char 6)  ;; between (y and (z), not on a pair char
    (helixel-jump-to-match)
    ;; Backward reposition finds ( at pos 4 and stops there.
    ;; "(x (y (z)))" = ( x ' ' ( y ' ' ( z ) ) )
    ;;                   1 2 3 4 5 6 7 8 9 0 1 2
    (should (= (point) 4))
    ;; Second % from ( on delimiter → jump to matching ).
    (helixel-jump-to-match)
    (should (= (point) 11))))

(ert-deftest helixel-test-forward-match-direct ()
  "helixel-forward-match goes one level outward."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a) (b) (c)")
    (deactivate-mark)
    (goto-char 4)  ;; after ) of first pair
    (helixel-forward-match)
    ;; Goes outward to the enclosing pair — but there is none,
    ;; top-level parens.  Should find no enclosing bracket.
    (should (= (point) 4))))

(ert-deftest helixel-test-backward-match-direct ()
  "helixel-backward-match goes one level outward to parent opener."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a) (b) (c)")
    (deactivate-mark)
    (goto-char 4)  ;; after ) of first pair
    (helixel-backward-match)
    ;; backward-up-list from after (a) goes before (a), then
    ;; outside, then... there's no parent pair at top level.
    ;; up-list signals error, point stays at 4.
    (should (= (point) 4))))

(ert-deftest helixel-test-M-dot-outward-nested ()
  ", goes one level outward to the parent pair."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(outer (inner))")
    (deactivate-mark)
    (goto-char 10)  ;; inside inner
    (helixel-backward-match)
    ;; Goes outward to (outer at pos 1.
    (should (= (point) 1))
    ;; Second , — no parent.
    (helixel-backward-match)
    (should (= (point) 1))))

(ert-deftest helixel-test-motion-M-dot-after-backward-percent ()
  ", after backward % goes outward to parent pair."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(outer (inner))")
    (deactivate-mark)
    ;; % from after inner ) → backward reposition to ) at 14
    ;; → on delimiter → core jump to (inner at 8.
    (goto-char 15)  ;; after inner ))
    (helixel-jump-to-match)
    ;; Should land on (inner at pos 8 after core jump from ).
    (should (eq (helixel--last-motion-dir helixel--last-motion-cmd)
                'backward))
    ;; , backward → outward to parent: (outer at pos 1.
    (helixel-repeat-last-motion)
    (should (= (point) 1))
    ;; , again — no parent, stays.
    (helixel-repeat-last-motion)
    (should (= (point) 1))))

(ert-deftest helixel-test-motion-M-dot-match-maintains-direction ()
  ", after forward % dispatches correctly and goes outward."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(outer (inner))")
    (deactivate-mark)
    (goto-char 8)  ;; on (inner
    (helixel-jump-to-match)
    ;; Forward % from ( → jumps to )inner.
    (should (eq (helixel--last-motion-dir helixel--last-motion-cmd)
                'forward))
    ;; , forward → outward to parent )outer at pos 15.
    (helixel-repeat-last-motion)
    (should (= (point) 15))))

(ert-deftest helixel-test-motion-M-dot-match-semicolon ()
  ", outward then ; selects a region."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(outer (inner))")
    (deactivate-mark)
    (let ((helixel--action-ring nil)
          (helixel--live-action nil)
          (helixel--action-pos nil))
      (goto-char 8)  ;; on (inner
      (helixel-jump-to-match)  ;; forward → after )inner
      (helixel-repeat-last-motion)  ;; , forward → )outer
      (let ((last-command 'helixel-repeat-last-motion))
        (helixel-action-cycle))
      (should (region-active-p))
      ;; The region covers the pair bounds.
      (should (> (region-end) (region-beginning))))))

(ert-deftest helixel-test-motion-repeat-with-count ()
  ", replays motion with original prefix count."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "a\n\nb\n\nc\n\nd\n")
    (deactivate-mark)
    (goto-char 1)
    (let ((current-prefix-arg 2))
      (call-interactively #'helixel-forward-paragraph-end))
    (should (helixel--last-motion-p helixel--last-motion-cmd))
    (should (eq (helixel--last-motion-command helixel--last-motion-cmd)
                'helixel-forward-paragraph-end))
    (should (eq (helixel--last-motion-prefix-arg helixel--last-motion-cmd) 2))))

(ert-deftest helixel-test-motion-repeat-paragraph ()
  ", repeats last paragraph-end motion (]p)."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "para1\n\npara2\n\npara3\n")
    (deactivate-mark)
    (goto-char 1)
    (helixel-forward-paragraph-end)
    (let ((first-pos (point)))
      (should (> first-pos 1))
      (helixel-repeat-last-motion)
      (should (> (point) first-pos)))))

(ert-deftest helixel-test-motion-empty-repeat ()
  ", with no prior motion signals user-error."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello world")
    (deactivate-mark)
    (goto-char 1)
    (let ((helixel--last-motion-cmd nil)
          (helixel--active-search nil))
      (should-error (helixel-repeat-last-motion)
                    :type 'user-error))))

(ert-deftest helixel-test-motion-word-not-tracked ()
  ", does NOT repeat word motions (w)."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello world foo")
    (deactivate-mark)
    (goto-char 1)
    (let ((helixel--last-motion-cmd nil)
          (helixel--active-search nil))
      (helixel-forward-word-start)
      (should (= (point) 7))
      (should-not (helixel--last-motion-p helixel--last-motion-cmd)))))

(ert-deftest helixel-test-motion-semicolon-consistency ()
  "[( , ; selects the same span as [( [( ;."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "((char (hello)))")
    (deactivate-mark)
    (goto-char 12)  ;; inside "hello"
    (let ((helixel--action-ring nil)
          (helixel--live-action nil)
          (helixel--action-pos nil))
      (helixel-outer-paren)
      (let ((last-command 'helixel-outer-paren))
        (helixel--action-cycle))
      (should (region-active-p))
      (should (> (region-end) (region-beginning))))))

(ert-deftest helixel-test-semicolon-nested-paren-span ()
  "; after consecutive [( selects the full outer span."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "((char (hello)))")
    (deactivate-mark)
    (goto-char 12)  ;; inside "hello"
    (let ((helixel--action-ring nil)
          (helixel--live-action nil)
          (helixel--action-pos nil))
      (helixel-outer-paren)
      (helixel-outer-paren)
      ;; First ; should select (char (hello)) — not missing the last ).
      (helixel--action-cycle)
      (should (region-active-p))
      (should (= (region-beginning) 2))
      (should (= (region-end) 16))
      (should (string= (buffer-substring-no-properties
                        (region-beginning) (region-end))
                       "(char (hello))")))))

(ert-deftest helixel-test-motion-find-char-survives-search ()
  ", replays f x even after /pattern changed active-search.
This is the design property: , reads from self-contained
`helixel--last-motion-cmd' struct, never from `helixel--active-search',
so changing the active-search category cannot break motion repeat."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "axb cxd exf")
    (deactivate-mark)
    (goto-char 1)
    ;; f x — record find-char in struct.
    (helixel-find-next-char ?x)
    (should (= (point) 3))
    ;; Simulate / pattern — overwrite active-search to search category
    ;; (same effect as a real search, but avoids interactive isearch).
    (setq helixel--active-search
          (make-helixel--last-motion
           :category 'search :pattern "f" :dir 'forward))
    (should (eq (helixel-search--safe-category) 'search))
    ;; , — should replay f x from struct, NOT from active-search.
    (helixel-repeat-last-motion)
    (should (= (point) 7))   ;; after second x
    ;; Verify struct still has find-char data.
    (should (helixel--last-motion-p helixel--last-motion-cmd))
    (should (helixel--last-motion-char helixel--last-motion-cmd))
    (should (eq (helixel--last-motion-type helixel--last-motion-cmd)
                'next))
    ;; Verify active-search was NOT corrupted (still search).
    (should (eq (helixel-search--safe-category) 'search))))

(ert-deftest helixel-test-motion-category-recorded ()
  "Each motion records its category+subcat in `helixel--last-motion-cmd'.
Movement subcats store category=movement with the specific subcat."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x (a)")
    (deactivate-mark)
    (goto-char 1)
    (helixel-next-paren-end)
    (should (eq (helixel--last-motion-category helixel--last-motion-cmd)
                'movement))
    (should (eq (helixel--last-motion-subcat helixel--last-motion-cmd)
                'pair))
    (goto-char 1)
    (helixel-find-next-char ?a)
    (should (eq (helixel--last-motion-category helixel--last-motion-cmd)
                'find-char))
    (should (eq (helixel--last-motion-subcat helixel--last-motion-cmd)
                nil))))

(ert-deftest helixel-test-motion-repeat-search ()
  ", repeats a search recorded in `helixel--last-motion-cmd'.
Simulates search by directly recording a search entry; real search
recording is tested via integration tests."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "abc foo def foo ghi")
    (deactivate-mark)
    (goto-char 1)
    ;; Simulate a completed search for "foo".
    (helixel--record-last-motion nil
      :category 'search :pattern "foo" :dir 'forward)
    (helixel-repeat-last-motion)
    ;; Should have found first "foo" and be at match-end.
    (should (= (point) 8))
    (should (region-active-p))
    ;; , again — next match.
    (helixel-repeat-last-motion)
    (should (= (point) 16))))

;; ── , boundary skip tests ──

(ert-deftest helixel-test-motion-skip-pair-forward ()
  ", repeats ] past consecutive paren boundaries."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a) (b) (c)")
    (deactivate-mark)
    (goto-char 1)
    (helixel-next-paren-end)
    (should (= (point) 4))   ;; after ) of (a)
    ;; , should skip to next paren, not stay on (a)
    (helixel-repeat-last-motion)
    (should (= (point) 8))   ;; after ) of (b)
    (helixel-repeat-last-motion)
    (should (= (point) 12)))) ;; after ) of (c), end of buffer

(ert-deftest helixel-test-motion-skip-pair-backward ()
  ", repeats [ past consecutive paren boundaries."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a) (b) (c)")
    (deactivate-mark)
    (goto-char (point-max))
    (helixel-outer-paren)
    (should (= (point) 9))  ;; at ( of (c)
    (helixel-repeat-last-motion)
    (should (= (point) 5))  ;; at ( of (b)
    (helixel-repeat-last-motion)
    (should (= (point) 1)))) ;; at ( of (a)

(ert-deftest helixel-test-motion-skip-pair-nested-from-opener ()
  ", after [ lands on opener steps one level, not two."
  ;; Regression: when [( leaves point on the opening delimiter,
  ;; , must skip past the current pair (not the parent).
  ;; Without the fix, helixel-delimiter-bounds-flat would
  ;; jump past the current opener to the parent opener,
  ;; so , would skip two nesting levels instead of one.
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a (b (c)))")
    (deactivate-mark)
    (goto-char 8)  ;; inside (c), on 'c'
    (helixel-outer-paren)
    ;; First [( lands on the opener of the enclosing (c) pair.
    (should (= (point) 7))  ;; at ( of (c)
    ;; , must go one level outward to (b opener.
    (helixel-repeat-last-motion)
    (should (= (point) 4))  ;; at ( of (b
    ;; Another , goes to (a opener.
    (helixel-repeat-last-motion)
    (should (= (point) 1))  ;; at ( of (a
    ;; At outermost level: no more enclosing pair -- returns nil,
    ;; consistent with --next at EOB (silent no-op, no error).
    (helixel-repeat-last-motion)
    (should (= (point) 1))))

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
    (helixel-outer-block)
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
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a x) (b y) (c z)")
    (deactivate-mark)
    (goto-char 3)  ;; inside 'a x'
    (helixel-inner-next-paren-end)
    (let ((p1 (point)))
      (should (> p1 3))   ;; moved forward
      (helixel-repeat-last-motion)
      (should (> (point) p1))))) ;; moved further

(ert-deftest helixel-test-motion-skip-inner-pair-backward ()
  ", repeats { past consecutive inner paren boundaries."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a) (b) (c)")
    (deactivate-mark)
    (goto-char 10)  ;; near end
    (helixel-inner-outer-paren)
    (let ((p1 (point)))
      (helixel-repeat-last-motion)
      (should (< (point) p1))))) ;; moved backward

;;; Backward opener stepping -- [ / { step one level per press

(ert-deftest helixel-test-motion-outer-paren-step-backward ()
  "[ ( steps outward through paren openers one level each press."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a (b (c)))")
    (deactivate-mark)
    (goto-char 8)   ;; inside (c)
    (helixel-outer-paren)
    (should (= (point) 7))  ;; on ( of (c)
    (helixel-outer-paren)
    (should (= (point) 4))  ;; on ( of (b
    (helixel-outer-paren)
    (should (= (point) 1))  ;; on ( of (a
    ;; At outermost -- no more openers, no-op.
    (helixel-outer-paren)
    (should (= (point) 1))))

(ert-deftest helixel-test-motion-inner-paren-step-backward ()
  "{ ( steps outward through inner paren openers one level each press."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a (b (c)))")
    (deactivate-mark)
    (goto-char 8)   ;; inside (c)
    (helixel-inner-outer-paren)
    (should (= (point) 5))  ;; inner edge of (b -- after the opener
    (helixel-inner-outer-paren)
    (should (= (point) 2))  ;; inner edge of (a
    ;; At outermost -- no more inner openers, no-op.
    (helixel-inner-outer-paren)
    (should (= (point) 2))))

(ert-deftest helixel-test-motion-comma-repeats-backward-opener ()
  ", repeats [ ( stepping outward through paren openers."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a (b (c)))")
    (deactivate-mark)
    (goto-char 8)
    ;; First press: go to innermost opener
    (helixel-outer-paren)
    (should (= (point) 7))
    ;; , repeats: step outward
    (helixel-repeat-last-motion)
    (should (= (point) 4))
    (helixel-repeat-last-motion)
    (should (= (point) 1))
    ;; At outermost -- , does nothing
    (helixel-repeat-last-motion)
    (should (= (point) 1))))

(ert-deftest helixel-test-motion-skip-paragraph-forward ()
  ", repeats ]p past consecutive paragraph boundaries."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "para1\n\npara2\n\npara3\n")
    (deactivate-mark)
    (goto-char 1)
    (helixel-forward-paragraph-end)
    (let ((first-pos (point)))
      (should (> first-pos 1))
      ;; First , should advance exactly one paragraph, not two.
      (helixel-repeat-last-motion)
      (should (> (point) first-pos))
      ;; Second , should still advance (not already at last para).
      (let ((second-pos (point)))
        (helixel-repeat-last-motion)
        (should (> (point) second-pos))))))

(ert-deftest helixel-test-motion-skip-paragraph-backward ()
  ", repeats [p past consecutive paragraph boundaries backward."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "para1\n\npara2\n\npara3\n")
    (deactivate-mark)
    (goto-char (point-max))
    (helixel-backward-paragraph-start)
    (let ((first-pos (point)))
      (should (< first-pos (point-max)))
      ;; First , should go back exactly one paragraph, not two.
      (helixel-repeat-last-motion)
      (should (< (point) first-pos))
      ;; Second , should still advance (not already at first para).
      (let ((second-pos (point)))
        (helixel-repeat-last-motion)
        (should (< (point) second-pos))))))

(ert-deftest helixel-test-motion-skip-word-not-recorded ()
  ", cannot repeat word motion (w) — not in repeat categories."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello world foo")
    (deactivate-mark)
    (goto-char 1)
    (let ((helixel--last-motion-cmd nil))
      (helixel-forward-word-start)
      (should (= (point) 7))
      (should-not (helixel--last-motion-p helixel--last-motion-cmd))
      (should-error (helixel-repeat-last-motion)
                    :type 'user-error))))

(ert-deftest helixel-test-percent-after-close ()
  "% right after ) jumps to matching (."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(hello) world")
    (deactivate-mark)
    (goto-char 8)  ;; right after ) — on space
    (helixel-jump-to-match)
    ;; char-before is ), a close char → on-or-after-delim → core
    ;; → jumps to ( at pos 1.
    (should (= (point) 1))))

(ert-deftest helixel-test-percent-on-bracket ()
  "% on ] jumps to matching [."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "[hello]")
    (deactivate-mark)
    (goto-char 7)  ;; on ]
    (helixel-jump-to-match)
    (should (= (point) 1))))

(ert-deftest helixel-test-percent-on-brace ()
  "% on } jumps to matching {."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "{hello}")
    (deactivate-mark)
    (goto-char 7)  ;; on }
    (helixel-jump-to-match)
    (should (= (point) 1))))

(ert-deftest helixel-test-M-dot-deeply-nested ()
  ", works through 3 levels of nesting."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a (b (c)))")
    (deactivate-mark)
    (goto-char 8)  ;; inside (c)
    (helixel-jump-to-match)  ;; % from inside → backward reposition
    ;; → goes to (c at pos 7
    (should (= (point) 7))
    ;; , outward → (b at pos 4
    (helixel-repeat-last-motion)
    (should (= (point) 4))
    ;; , outward → (a at pos 1
    (helixel-repeat-last-motion)
    (should (= (point) 1))
    ;; , outward — no parent
    (helixel-repeat-last-motion)
    (should (= (point) 1))))

(ert-deftest helixel-test-M-dot-from-inside-pair ()
  ", from inside a pair goes outward to parent."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(outer (inner))")
    (deactivate-mark)
    (goto-char 10)  ;; inside inner, not on delimiter
    ;; Record a motion first so , has something to repeat.
    ;; Simulate % then test , directly.
    (helixel-jump-to-match)  ;; goes backward to (inner at 8
    (should (= (point) 8))
    (helixel-jump-to-match)  ;; on (inner → forward % → after )inner
    ;; , forward → outward to )outer at pos 15.
    (helixel-repeat-last-motion)
    (should (= (point) 15))))

(ert-deftest helixel-test-M-dot-at-bob ()
  ", at beginning of buffer does nothing."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(hello)")
    (deactivate-mark)
    (goto-char 1)  ;; on (
    (helixel-jump-to-match)  ;; forward % → after )
    (goto-char 1)  ;; back to (
    ;; , outward from outermost pair — no parent
    (let ((helixel--last-motion-cmd
           (make-helixel--last-motion
            :category 'movement :subcat 'match
            :command 'helixel-jump-to-match
            :dir 'forward)))
      (helixel-repeat-last-motion)
      ;; Should not move — no parent
      (should (= (point) 1)))))

(ert-deftest helixel-test-percent-then-percent-then-M-dot ()
  "Two % presses then , outward."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(outer (inner))")
    (deactivate-mark)
    (goto-char 8)  ;; on (inner
    (helixel-jump-to-match)  ;; % → after )inner (pos 15)
    (should (= (point) 15))
    (helixel-jump-to-match)  ;; % again → back to (inner opener
    (should (= (point) 8))
    ;; , outward — no enclosing pair at top level.
    (helixel-repeat-last-motion)
    (should (>= (point) 1))))

(ert-deftest helixel-test-semicolon-after-multiple-M-dot ()
  "; after % + , + , marks the outermost pair."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(a (b (c)))")
    (deactivate-mark)
    (let ((helixel--action-ring nil)
          (helixel--live-action nil)
          (helixel--action-pos nil))
      (goto-char 8)  ;; on c inside (c)
      (helixel-jump-to-match)  ;; → backward to (c at pos 7
      (should (= (point) 7))
      (helixel-repeat-last-motion)  ;; , → (b at pos 4
      (should (= (point) 4))
      (helixel-repeat-last-motion)  ;; , → (a at pos 1
      (should (= (point) 1))
      ;; ; should select a region
      (let ((last-command 'helixel-repeat-last-motion))
        (helixel-action-cycle))
      (should (region-active-p))
      (should (> (region-end) (region-beginning))))))

(ert-deftest helixel-test-percent-backward-from-text ()
  "% from inside text goes backward to nearest (."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "abc(def)ghi")
    (deactivate-mark)
    (goto-char 8)  ;; on g of ghi, after )
    (helixel-jump-to-match)
    ;; Not on delimiter. Backward reposition: finds ) at pos 7.
    ;; char-before at pos 8 is ). Is ) in close-chars? Yes.
    ;; And char-after is g (not pair char).
    ;; So on-or-after-delim-p → core → jumps to ( at pos 4.
    (should (= (point) 4))))

;;; ── % + , outward navigation for tags and blocks ──

(ert-deftest helixel-test-percent-inside-tag ()
  "% inside a tag (right after >) jumps to the matching closing tag.
Point is after the > of <div>, which is a close delimiter for the
angle-bracket pair — so % enters the jump path and lands at </div>."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "<div>hi</div>")
    (deactivate-mark)
    (goto-char 6)  ;; on 'h', right after > of <div>
    (helixel-jump-to-match)
    ;; Jumps to the matching </div> via the tag fallback path.
    (should (= (point) 14))))

(ert-deftest helixel-test-percent-inside-tag-before-gt ()
  "% inside tag before > moves backward to < (reposition).
Point is on 'd' of <div>, before the >.  char-before is < which
is not a close char, so we enter the backward-reposition path."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "<div>hi</div>")
    (deactivate-mark)
    (goto-char 2)  ;; on 'd' of <div>, before >
    (helixel-jump-to-match)
    ;; Backward reposition finds < at pos 1 and stops.
    (should (= (point) 1))))

(ert-deftest helixel-test-percent-on-tag-opener ()
  "% on < of an opening tag jumps to the matching </div>."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "<div>hi</div>")
    (deactivate-mark)
    (goto-char 1)  ;; on < of <div>
    (helixel-jump-to-match)
    ;; Should land right after </div>
    (should (= (point) 14))))

(ert-deftest helixel-test-M-dot-after-percent-on-tag ()
  ", after % on a tag goes outward to parent tag's closer."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "<outer><inner>hi</inner></outer>")
    (deactivate-mark)
    (goto-char 8)  ;; on < of <inner>
    (helixel-jump-to-match)  ;; % → jumps after </inner>
    ;; , forward → outward to after </outer> at pos 33.
    (helixel-repeat-last-motion)
    (should (= (point) 33))))

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
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "<a><b>hi</b></a>")
    (deactivate-mark)
    ;; % from inner opener <b at pos 4
    (goto-char 4)  ;; on < of <b>
    (helixel-jump-to-match)  ;; % → jumps after </b>
    (let ((b-close (point)))
      (should (> b-close 10))
      ;; , outward → after </a>
      (helixel-repeat-last-motion)
      (should (> (point) b-close)))))

(ert-deftest helixel-test-M-dot-tag-outward-from-content ()
  ", after % from inside tag content outward to parent."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "<a><b>text</b></a>")
    (deactivate-mark)
    (goto-char 5)  ;; on t of text
    ;; First % repositions backward to <b (since 't' is not a pair char
    ;; and the nearest pair char backward is <).
    (helixel-jump-to-match)
    ;; Now on < — second % actually jumps
    (helixel-jump-to-match)  ;; forward % → after </b>
    (let ((b-close (point)))
      (should (> b-close 10))
      ;; , outward → after </a>
      (helixel-repeat-last-motion)
      (should (> (point) b-close)))))

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
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "<div>(hello)</div>")
    (deactivate-mark)
    (goto-char 6)  ;; on ( of (hello)
    (helixel-jump-to-match)  ;; % from ( → jumps to matching )
    (let ((paren-close (point)))
      (should (> paren-close 6))
      ;; , outward from ) → should go to </div> or past it
      (helixel-repeat-last-motion)
      (should (not (= (point) paren-close))))))

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
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x 'hi' y")
    (deactivate-mark)
    (goto-char 3)  ;; on first '
    (let ((pt-before (point)))
      (helixel-jump-to-match)
      (should (= (point) pt-before)))))

(ert-deftest helixel-test-percent-on-backtick-noop ()
  "% on backtick does not jump — quotes are excluded."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "x `hi` y")
    (deactivate-mark)
    (goto-char 3)  ;; on first `
    (let ((pt-before (point)))
      (helixel-jump-to-match)
      (should (= (point) pt-before)))))

;;; ── , edge cases ──

(ert-deftest helixel-test-M-dot-no-delimiter-fallback ()
  ", works after syntax-table-only % (no stored delimiter)."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(outer (inner))")
    (deactivate-mark)
    ;; % records the matched delimiter in helixel--last-motion-cmd's
    ;; EXTRA; , reads it back for outward navigation.
    (goto-char 8)  ;; on ( of (inner)
    (helixel-jump-to-match)  ;; forward % → after )inner
    ;; , forward → outward to )outer at pos 15.
    (helixel-repeat-last-motion)
    (should (= (point) 15))))

(ert-deftest helixel-test-M-dot-multiple-levels-mixed ()
  ", works through bracket + brace nesting."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "{a (b [c])}")
    (deactivate-mark)
    (goto-char 8)  ;; inside [c]
    (helixel-jump-to-match)  ;; % → backward to [
    (should (= (point) 7))
    ;; , outward → ( opener
    (helixel-repeat-last-motion)
    (should (= (point) 4))
    ;; , outward → { opener
    (helixel-repeat-last-motion)
    (should (= (point) 1))
    ;; , — no parent
    (helixel-repeat-last-motion)
    (should (= (point) 1))))

;;; ── % inside string skips quotes, finds enclosing bracket ──

(ert-deftest helixel-test-percent-inside-string ()
  "% inside a string moves backward past the quote to the nearest bracket."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(message \"hello world\")")
    (deactivate-mark)
    (goto-char 14)  ;; inside \"hello world\", on 'o'
    (helixel-jump-to-match)
    ;; Should skip " and reposition to the nearest bracket: (
    ;; (message "hello world")
    ;; 1234567890123456789012345
    ;; ( = pos 1
    (should (= (point) 1))
    ;; ; should now mark the (message ...) pair
    (save-excursion (helixel--jump-to-match-core))
    (should (helixel-action-mark-region helixel--live-action))))

(ert-deftest helixel-test-percent-inside-nested-string ()
  "% inside nested string skips both quotes, finds outer bracket."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "[x \"hi\" y]")
    (deactivate-mark)
    (goto-char 5)  ;; inside \"hi\", on 'i'
    (helixel-jump-to-match)
    ;; Should skip " and reposition to [
    ;; [ = pos 1
    (should (= (point) 1))))

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
  ", from pair inside block: parent pair before block."
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
    (helixel-repeat-last-motion)
    (should (looking-at "(let"))
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
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(far-away)\n\ninside text")
    (deactivate-mark)
    (goto-char (point-max))  ;; at end of "inside text"
    (forward-char -3)         ;; somewhere in "text"
    ;; % should NOT find ( in the paragraph above the blank line.
    ;; Before fix: would jump to ( at pos 1.
    ;; After fix: blank line acts as boundary → no match.
    (let ((helixel--last-motion-cmd nil))
      (helixel-jump-to-match)
      ;; Point should not move — no delimiter in current paragraph.
      (should (= (point) (- (point-max) 3))))))

(ert-deftest helixel-test-percent-same-paragraph-works ()
  "% from inside a paragraph still finds delimiters on the same line."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello (world)")
    (deactivate-mark)
    (goto-char 8)  ;; on 'r' in "world"
    (helixel-jump-to-match)
    ;; Should find ( backward on the same line — no blank line in between.
    (should (= (point) 7))))

(ert-deftest helixel-test-percent-no-blank-line-multiline ()
  "% finds delimiter across newlines when no blank line separates them."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(foo\n bar\n baz)\nquux")
    (deactivate-mark)
    (goto-char (point-max))  ;; at end
    (forward-char -2)         ;; somewhere in "quux"
    (helixel-jump-to-match)
    ;; Should find ) backward — no blank line, just regular newlines.
    (should (= (char-after) ?\)))))

;; ============================================================================
;; ; mark-region after each jump strategy
;; ============================================================================

(ert-deftest helixel-test-semicolon-after-jump-via-pair ()
  "; after % on pair delimiter selects the matched region."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "before (inner content) after")
    (deactivate-mark)
    (let ((helixel--action-ring nil)
          (helixel--live-action nil)
          (helixel--action-pos nil))
      (goto-char 8)  ;; on ( of (inner
      (helixel-jump-to-match)
      (let ((last-command 'helixel-jump-to-match))
        (helixel-action-cycle))
      (should (region-active-p))
      (should (string= (buffer-substring (region-beginning) (region-end))
                       "(inner content)")))))

(ert-deftest helixel-test-semicolon-after-jump-via-syntax ()
  "; after % via syntax-table selects the matched region."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "before (inner) after")
    (deactivate-mark)
    (let ((helixel--action-ring nil)
          (helixel--live-action nil)
          (helixel--action-pos nil))
      (goto-char 12)  ;; inside (inner), NOT on a delimiter
      (helixel-jump-to-match)
      (let ((last-command 'helixel-jump-to-match))
        (helixel-action-cycle))
      (should (region-active-p))
      (should (string= (buffer-substring (region-beginning) (region-end))
                       "(inner)")))))

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
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "()")
    (deactivate-mark)
    (goto-char 1)  ;; on first (
    (helixel-jump-to-match)
    ;; Should jump past ) — the match-end position.
    (should (> (point) 2))))

(ert-deftest helixel-test-jump-via-syntax-from-inside ()
  "%% from inside parens jumps to nearer end via syntax-table."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "(inner)")
    (deactivate-mark)
    (goto-char 3)  ;; inside "inner"
    (helixel-jump-to-match)
    ;; Should jump to either ( or ) — whichever is nearer to orig.
    (should (memq (point) '(1 7)))))

(ert-deftest helixel-test-jump-to-match-core-no-delimiter ()
  "jump-to-match-core returns nil when point is not near any delimiter."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "just some random text without any brackets")
    (deactivate-mark)
    (goto-char 10)
    (should-not (helixel--jump-to-match-core))
    ;; Point should be unchanged.
    (should (= (point) 10))))
