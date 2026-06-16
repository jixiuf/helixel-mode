;;; helixel-test-operator.el --- Tests for Helixel: operators (case,comment,fill,join)  -*- lexical-binding: t; -*-

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
    (let ((tx helixel--last-action))
      (funcall (helixel--op-runner (helixel-action-op tx)) tx))
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

(ert-deftest helixel-test-join-lines-region-full-lines ()
  "J on a region joining 3 full lines."
  (helixel-test-with-buffer "one\ntwo\nthree"
    (set-mark 14)              ;; end of last line
    (helixel-join-lines)
    (should (string= (buffer-string) "one two three"))))

(ert-deftest helixel-test-join-lines-region-partial ()
  "J on a region that partially spans lines."
  (helixel-test-with-buffer "aa\nbb\ncc\ndd"
    (goto-char 2)              ;; mid first line
    (set-mark 8)               ;; mid third line (pos 8 is second 'c')
    (helixel-join-lines)
    (should (string= (buffer-string) "aa bb cc\ndd"))))

(ert-deftest helixel-test-join-lines-region-end-bolp ()
  "J on a region where end is at bol of the following line."
  (helixel-test-with-buffer "one\ntwo\nthree\nfour"
    (set-mark 14)              ;; bol of "four"
    (helixel-join-lines)
    (should (string= (buffer-string) "one two three\nfour"))))

(ert-deftest helixel-test-join-lines-region-dot-repeat ()
  "J on a region stores line count for dot-repeat."
  (helixel-test-with-buffer "a\nb\nc\nd\ne"
    (set-mark 6)               ;; select a,b,c (3 lines)
    (helixel-join-lines)
    (should (string= (buffer-string) "a b c\nd\ne"))
    (helixel-repeat-edit)      ;; joins next 3 lines (d,e + trailing)
    (should (string= (buffer-string) "a b c d e"))))

(ert-deftest helixel-test-join-lines-select-line-dot-repeat ()
  "xxxxJ j . joins from the new cursor position using stored count.
Regression: pending line selection from `x' (select-line) leaked
into the join-lines tx, causing dot-repeat to recreate a line
selection before joining, which interfered with the runner."
  (helixel-test-with-buffer
   "hello
hello
hello
hello
hello
hello
hello
hello
hello"
    (helixel-select-line)      ;; x
    (helixel-select-line)      ;; x
    (helixel-select-line)      ;; x
    (helixel-select-line)      ;; x — select 4 lines
    (helixel-join-lines)       ;; J
    (should (string= (buffer-string)
                     "hello hello hello hello\nhello\nhello\nhello\nhello\nhello"))
    (helixel-next-line)        ;; j — move one line down
    (helixel-repeat-edit)      ;; . — join 4 lines from new position
    (should (string= (buffer-string)
                     "hello hello hello hello\nhello hello hello hello\nhello"))))

(ert-deftest helixel-test-join-lines-c-u-region-no-space ()
  "C-u J on a region joins lines without adding spaces."
  (helixel-test-with-buffer "one\ntwo\nthree"
    (set-mark 14)              ;; end of last line
    (let ((current-prefix-arg '(4)))
      (call-interactively #'helixel-join-lines))
    (should (string= (buffer-string) "onetwothree"))))

(ert-deftest helixel-test-join-lines-c-u-region-whitespace ()
  "C-u J on a region strips leading whitespace but adds no space."
  (helixel-test-with-buffer "hello\n  world\n  !"
    (set-mark 17)              ;; end of last line
    (let ((current-prefix-arg '(4)))
      (call-interactively #'helixel-join-lines))
    (should (string= (buffer-string) "helloworld!"))))

(ert-deftest helixel-test-join-lines-c-u-region-dot-repeat ()
  "C-u J on a region, then . repeats without space."
  (helixel-test-with-buffer "a\nb\nc\nd\ne"
    (set-mark 6)               ;; select a,b,c (3 lines)
    (let ((current-prefix-arg '(4)))
      (call-interactively #'helixel-join-lines))
    (should (string= (buffer-string) "abc\nd\ne"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "abcde"))))

(ert-deftest helixel-test-join-lines-select-line-mc-spawn-J ()
  "xxx ss J joins at least 2 lines per cursor after mc spawn.
After `xxx' (select-line 3 times) and `ss' (mc-toggle), each cursor
gets a 1-line region.  The real cursor (nearest to point = last line)
joins its line with the next (n=2)."
  (helixel-test-with-buffer "hello\nhello\nhello\nhello"
    ;; xxx = select 3 lines
    (helixel-select-line)
    (helixel-select-line)
    (helixel-select-line)
    ;; ss = mc-toggle (spawn fake cursors on each line)
    (condition-case nil (helixel-mc-toggle) (error nil))
    ;; J — real cursor is on line 3 (closest to original point)
    ;; and joins lines 3+4.
    (helixel-join-lines)
    (helixel-mc-clear-all)
    (should (string= (buffer-string)
                     "hello\nhello\nhello hello"))))

(ert-deftest helixel-test-join-lines-single-line-region-joins-2 ()
  "J with a single-line region joins 2 lines (selected + next).
A region confined to one line (e.g. after mc spawn) should still
join at least the current line with the next, rather than doing
nothing (region-n=1)."
  (helixel-test-with-buffer "one\ntwo\nthree"
    ;; Create a single-line region (like after mc spawn)
    (goto-char 1)
    (push-mark (line-end-position) t t)
    (helixel-join-lines)
    (should (string= (buffer-string) "one two\nthree"))))

(ert-deftest helixel-test-join-lines-tx-sel-cleared ()
  "Join-lines tx has nil sel so dot-repeat advance doesn't recreate it.
Regression: pending line selection from `x' leaked into the tx's sel,
causing dot-repeat advance to recreate a line selection before the
runner, moving cursor to wrong position."
  (helixel-test-with-buffer "hello\nhello\nhello\nhello"
    (helixel-select-line)
    (helixel-select-line)
    (helixel-select-line)
    (helixel-select-line)
    (helixel-join-lines)
    ;; The tx must NOT carry a selection — dot-repeat relies on
    ;; :count alone, advance is a no-op for ops that move point.
    (should-not (helixel-action-sel helixel--last-action))
    (should (eql 4 (helixel-action-payload-get helixel--last-action :count)))))

(ert-deftest helixel-test-toggle-case-bword-dot-repeat ()
  "b~ at eob, then . repeatedly — must advance backward each time.

Regression: `helixel-toggle-case' on a region used `delete-region'
+ `insert', which left point at region-end.  This broke the `.`
advance because `b' (backward-word-start) from region-end
re-selected the same word instead of the previous one."
  (helixel-test-with-buffer "hello\nworld\nFOO\nBAR"
    (goto-char (point-max))              ; eob
    ;; b → backward word
    (call-interactively #'helixel-backward-word-start)
    ;; ~ → toggle case on region (should stay at region-beginning)
    (call-interactively #'helixel-toggle-case)
    (should (= (point) 17))              ; stayed at region-beginning
    (should (string= (buffer-string) "hello\nworld\nFOO\nbar"))
    ;; . → advance backward one word, toggle region
    (call-interactively #'helixel-repeat-edit)
    (should (= (point) 13))              ; moved to previous word
    (should (string= (buffer-string) "hello\nworld\nfoo\nbar"))
    ;; . → advance backward again
    (call-interactively #'helixel-repeat-edit)
    (should (= (point) 7))               ; moved to second word
    (should (string-match-p "WORLD" (buffer-string)))
    ;; . → advance backward once more
    (call-interactively #'helixel-repeat-edit)
    (should (= (point) 1))
    (should (string-match-p "HELLO" (buffer-string)))))

(ert-deftest helixel-test-toggle-case-fword-dot-repeat ()
  "w~ then . repeatedly — must advance forward each time.

Same root cause as `helixel-test-toggle-case-bword-dot-repeat',
but for forward motion: after `w~' point must stay at region-end
so `.` advance continues forward."
  (helixel-test-with-buffer "hello world foo bar"
    (goto-char 1)
    ;; w → forward word
    (call-interactively #'helixel-forward-word-start)
    ;; ~ → toggle case on region (should stay at region-end)
    (call-interactively #'helixel-toggle-case)
    (should (= (point) 7))               ; stayed at region-end
    (should (string= (buffer-string) "HELLO world foo bar"))
    ;; . → advance forward one word, toggle region
    (call-interactively #'helixel-repeat-edit)
    (should (= (point) 13))              ; moved to next word
    (should (string= (buffer-string) "HELLO WORLD foo bar"))
    ;; . → advance forward again
    (call-interactively #'helixel-repeat-edit)
    (should (= (point) 17))              ; moved to third word
    (should (string= (buffer-string) "HELLO WORLD FOO bar"))
    ;; . → advance forward once more
    (call-interactively #'helixel-repeat-edit)
    (should (= (point) 20))              ; moved to last word (eob)
    (should (string= (buffer-string) "HELLO WORLD FOO BAR"))))

(ert-deftest helixel-test-toggle-case-dot-repeat-point-preserved ()
  "~ at eob followed by . errors cleanly but action is still recorded.

After the error, `helixel--last-action' should still be valid for
replay at a non-eob position."
  (helixel-test-with-buffer "hello\nworld"
    (goto-char (point-max))              ; eob
    (condition-case nil
        (call-interactively #'helixel-toggle-case)
      (error nil))
    ;; Even though ~ errored, a tx was recorded (record-action runs
    ;; before the following-char check).  Move off eob and replay.
    (should helixel--last-action)
    (goto-char 1)
    ;; Replay the toggle-case tx at position 1
    (let ((tx helixel--last-action))
      (funcall (helixel--op-runner (helixel-action-op tx)) tx))
    (should (string= (buffer-string) "Hello\nworld"))))

;;; helixel-test-operator.el ends here
