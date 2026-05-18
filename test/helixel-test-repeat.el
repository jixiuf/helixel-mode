;;; helixel-test-repeat.el --- Tests for Helixel: line selection repeat auto-advance  -*- lexical-binding: t; -*-

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

;;; helixel-test-repeat.el ends here
