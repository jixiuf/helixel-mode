;;; helixel-test-repeat.el --- Tests for Helixel: line selection repeat auto-advance  -*- lexical-binding: t; -*-

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

;;; Line selection auto-advance for `.` repeat

(ert-deftest helixel-test-repeat-line-advance-insert ()
  "`. ` after xi<text><ESC> auto-advances to next line."
  (helixel-test-with-buffer "line1\nline2\nline3\n"
    (goto-char 3)
    ;; Simulate xihello<ESC>: insert-text op on line sel.
    ;; insert-text inserts at point (which helixel-select-line
    ;; leaves at eol after recreating).  The key test: `.`
    ;; should advance point to line 2 before executing.
    (setq helixel-last-action
          (helixel-action-create 'insert-text
            (helixel-sel-create 'line '(:dir forward :count 1))
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
          this-command 'helixel-kill)
    (helixel-kill)
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
    (setq helixel-last-action
          (helixel-action-create 'insert-text
            (helixel-sel-create 'line '(:dir backward :count 1))
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
    (let ((helixel--pending-sel
           (helixel-sel-create 'line
               '(:dir forward :count 1 :entry-kind insert))))
      (helixel-record-action 'insert-text))
    (setq helixel-last-action
          (helixel-action-with-payload helixel-last-action :text "hello"))
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
    (let ((helixel--pending-sel
           (helixel-sel-create 'line
               '(:dir forward :count 2 :entry-kind insert))))
      (helixel-record-action 'insert-text))
    (setq helixel-last-action
          (helixel-action-with-payload helixel-last-action :text "hello"))
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
    (let ((helixel--pending-sel
           (helixel-sel-create 'line
               '(:dir forward :count 2 :entry-kind insert))))
      (helixel-record-action 'insert-text))
    (setq helixel-last-action
          (helixel-action-with-payload helixel-last-action :text "hello"))
    (helixel-repeat-edit)               ; insert on lines 3-4 target
    (should (string= (buffer-string)
                     "line1\nline2\nhelloline3\nline4\nline5\nline6\nline7\n"))
    (helixel-repeat-edit)               ; advance 2 more → lines 5-6 target
    (should (string= (buffer-string)
                     (concat "line1\nline2\nhelloline3\n"
                             "line4\nhelloline5\nline6\nline7\n")))))

(ert-deftest helixel-test-repeat-line-advance-append-count2 ()
  "`. ` after xxafoo<ESC> (2-line sel, append) advances exactly 2 lines.
Cursor at region-end (append) should advance 1 line past selection,
not count lines — bug where advancing by count from last selected
line's EOL overshoots and selects lines 4-5 instead of 3-4."
  (helixel-test-with-buffer
      "line1\nline2\nline3\nline4\nline5\n"
    (goto-char (point-min))
    ;; Simulate xx: select 2 lines forward, point ends at EOL of line 2
    ;; Simulate afoo<ESC>: entry-kind append, point stays at EOL of line 2
    (end-of-line)                       ; line 1
    (forward-line 1)                    ; line 2
    (end-of-line)                       ; EOL of line 2 (where a leaves point)
    (let ((helixel--pending-sel
           (helixel-sel-create 'line
               '(:dir forward :count 2 :entry-kind append))))
      (helixel-record-action 'insert-text))
    (setq helixel-last-action
          (helixel-action-with-payload helixel-last-action :text "foo"))
    ;; Point at EOL of line 2 before dot-repeat (where a leaves it).
    (should (= (line-number-at-pos) 2))
    (helixel-repeat-edit)
    ;; Should append "foo" at EOL of line 4 (the 2nd line of the
    ;; 2-line target starting at line 3), NOT line 5.
    (should (string= (buffer-string)
                     "line1\nline2\nline3\nline4foo\nline5\n")))
  ;; Second dot-repeat: advance by 2 more → lines 5-6 target
  (helixel-test-with-buffer
      "line1\nline2\nline3\nline4\nline5\nline6\nline7\n"
    (goto-char (point-min))
    (end-of-line)                       ; line 1
    (forward-line 1)                    ; line 2
    (end-of-line)                       ; EOL of line 2
    (let ((helixel--pending-sel
           (helixel-sel-create 'line
               '(:dir forward :count 2 :entry-kind append))))
      (helixel-record-action 'insert-text))
    (setq helixel-last-action
          (helixel-action-with-payload helixel-last-action :text "foo"))
    (helixel-repeat-edit)               ; append on line 4 (lines 3-4 target)
    (should (string= (buffer-string)
                     "line1\nline2\nline3\nline4foo\nline5\nline6\nline7\n"))
    (helixel-repeat-edit)               ; advance 1 more → lines 5-6 target
    (should (string= (buffer-string)
                     (concat "line1\nline2\nline3\nline4foo\n"
                             "line5\nline6foo\nline7\n")))))

(ert-deftest helixel-test-repeat-line-insert-move-forward-dot ()
  "`. ` after xi<M-f>foo<ESC> replays cursor-movement via recorded keys.
M-f (meta key) is a non-character integer — must go through
key-binding dispatch, not insert-char, in `helixel--execute-keys'."
  (helixel-test-with-buffer "line1\nline2\n"
    (goto-char 3)
    ;; Build tx simulating xi + <M-f> + foo + <ESC>
    ;; :keys captures the full key sequence (M-f + f + o + o).
    (setq helixel-last-action
          (helixel-action-create 'insert-text
            (helixel-sel-create
             'line
             '(:dir forward :count 1 :entry-kind insert))
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
    (setq helixel-last-action
          (helixel-action-create 'insert-text
            (helixel-sel-create
             'line
             '(:dir forward :count 1 :entry-kind append))
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
    (setq helixel-last-action
          (helixel-action-create 'insert-text
            (helixel-sel-create
             'line
             '(:dir forward :count 1 :entry-kind insert))
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
    (setq helixel-last-action
          (helixel-action-create 'insert-text
            (helixel-sel-create
             'line
             '(:dir backward :count 1 :entry-kind append))
            :text "YYXX"))
    (helixel-repeat-edit)
    ;; Text appended at eol of line 1 (earlier line).
     (should (string= (buffer-string)
                      "hello worldYYXX\nline2\n"))))

(ert-deftest helixel-test-repeat-line-advance-skip-blank ()
  "`. ` after x on a non-blank line skips blank lines on advance."
  (helixel-test-with-buffer "line1\n   \nline3\n"
    (goto-char 1)
    (setq helixel-last-action
          (helixel-action-create 'insert-text
            (helixel-sel-create 'line '(:dir forward :count 1))
            :text "X"))
    (let ((old-line (line-number-at-pos)))
      (should (= old-line 1))
      (helixel-repeat-edit)
      (should (= (line-number-at-pos) 3))))
  ;; Backward
  (helixel-test-with-buffer "line1\n   \nline3\n"
    (goto-char (point-min))
    (forward-line 2)              ;; go to line 3
    (setq helixel-last-action
          (helixel-action-create 'insert-text
            (helixel-sel-create 'line '(:dir backward :count 1))
            :text "Y"))
    (let ((old-line (line-number-at-pos)))
      (should (= old-line 3))
      (helixel-repeat-edit)
      ;; Should skip blank line and go to line 1
      (should (= (line-number-at-pos) 1)))))

;; ── `-.' permanent direction flip (like N for search) ──

(ert-deftest helixel-test-repeat-flip-dir-forward-to-backward ()
  "`-.' flips line direction forward→backward permanently.
After `-.' a plain `.` continues backward.  `-.' again flips back."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\nline5\n"
    (goto-char (point-min))
    (forward-line 1)                    ; line 2
    (end-of-line)                       ; EOL of line 2
    (let ((helixel--pending-sel
           (helixel-sel-create 'line
               '(:dir forward :count 1 :entry-kind append))))
      (helixel-record-action 'insert-text))
    (setq helixel-last-action
          (helixel-action-with-payload helixel-last-action :text "X"))
    ;; Verify sel direction is forward
    (should (not helixel--repeat-permanent-flip))
    ;; `-.' — flip direction forward→backward, then 1 repeat
    (helixel-repeat-edit '-)
    ;; Should have gone backward from line 2 → appended X at EOL of line 1
    (should (string= (buffer-string)
                     "line1X\nline2\nline3\nline4\nline5\n"))
    ;; Direction is now permanently backward
    (should helixel--repeat-permanent-flip)
    ;; Plain `.` continues backward
    (goto-char (point-min))
    (forward-line 2)                    ; line 3
    (end-of-line)
    (helixel-repeat-edit)
    (should (string= (buffer-string)
                     "line1X\nline2X\nline3\nline4\nline5\n"))
    ;; `-.' again flips back to forward
    (goto-char (point-min))
    (forward-line 1)                    ; line 2
    (end-of-line)
    (helixel-repeat-edit '-)
    ;; Now forward from line 2 → append at EOL of line 3
    (should (string= (buffer-string)
                     "line1X\nline2X\nline3X\nline4\nline5\n"))
    (should (not helixel--repeat-permanent-flip))))

(ert-deftest helixel-test-repeat-flip-dir-movement-works ()
  "`-.' on a movement selection flips direction via reverse-motion lookup."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (setq helixel-last-action
          (helixel-action-create 'insert-text
            (helixel-sel-create
             'movement
             '(:moves ((forward-word . 1))))
            :text "X"))
    (insert "X")
    ;; `-.' — flips direction permanently, does 1 repeat backward.
    ;; forward-word is reversed to backward-word via motion-reverse registry.
    (helixel-repeat-edit '-)
    (should helixel--repeat-permanent-flip)
    (setq helixel--repeat-permanent-flip nil)
    (should (>= (how-many "X" (point-min) (point-max)) 2))))

(ert-deftest helixel-test-repeat-flip-dir-neg3 ()
  "`-3.' permanently flips direction and does 3 repeats.
Like 3N for search — negative count also permanently flips."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\nline5\nline6\n"
    (goto-char (point-min))
    (forward-line 1)                    ; line 2
    (end-of-line)
    (let ((helixel--pending-sel
           (helixel-sel-create 'line
               '(:dir forward :count 1 :entry-kind append))))
      (helixel-record-action 'insert-text))
    (setq helixel-last-action
          (helixel-action-with-payload helixel-last-action :text "X"))
    (should (not helixel--repeat-permanent-flip))
    ;; -3. flips to backward + 3 repeats
    ;; From EOL of line 2: backward appends at EOL of lines 1 (skip: at edge)
    ;; Actually from line 2 backward: line 1, then no more lines.
    ;; Let me reposition to line 5 for 3 backward repeats.
    (goto-char (point-min))
    (forward-line 4)                    ; line 5
    (end-of-line)
    (helixel-repeat-edit -3)
    ;; 3 backward appends from line 5: lines 4, 3, 2
    (should (string= (buffer-string)
                     "line1\nline2X\nline3X\nline4X\nline5\nline6\n"))
    ;; Direction is now permanently backward
    (should helixel--repeat-permanent-flip)
    ;; Plain `.` continues backward
    (goto-char (point-min))
    (forward-line 4)                    ; line 5
    (end-of-line)
    (helixel-repeat-edit)
    (should (string= (buffer-string)
                     "line1\nline2X\nline3X\nline4XX\nline5\nline6\n"))
    ;; Clean up: reset permanent flip so later tests aren't affected.
    (setq helixel--repeat-permanent-flip nil)))

(ert-deftest helixel-test-repeat-flip-dir-comma ()
  "`-,' flips direction permanently and previews.
After `-,' a plain `.` uses the preview position (helixel--repeat-preview-pos)."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\n"
    (goto-char (point-min))
    (forward-line 1)                    ; line 2
    (end-of-line)
    (let ((helixel--pending-sel
           (helixel-sel-create 'line
               '(:dir forward :count 1 :entry-kind append))))
      (helixel-record-action 'insert-text))
    (setq helixel-last-action
          (helixel-action-with-payload helixel-last-action :text "X"))
    ;; `-,' flips dir and previews
    (helixel-repeat-selection '-)
    ;; Should now be on line 1 (previewed backward from line 2)
    (should (= (line-number-at-pos) 1))
    ;; Direction permanently flipped
    (should helixel--repeat-permanent-flip)
    ;; Plain `.` at the preview position: appends at preview EOL.
    ;; helixel--repeat-preview-pos was set by `,` so `.` uses
    ;; the current position directly (no advance).
    (helixel-repeat-edit)
    (should (string= (buffer-string)
                     "line1X\nline2\nline3\nline4\n"))
    ;; Clean up: reset permanent flip so later tests aren't affected.
    (setq helixel--repeat-permanent-flip nil)))

(ert-deftest helixel-test-repeat-keys-mode-remap ()
  "`. ` replays insert keys when self-insert-command is remapped.
In org-mode self-insert-command is remapped to org-self-insert-command.
Key replay must detect remapped commands and use insert-char rather
than call-interactively (which triggers mode-specific side effects)."
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (delay-mode-hooks (org-mode))
    ;; Simulate keys recorded in org-mode (self-insert is remapped)
    ;; :commands layer removed — keys-only replay is the primary path
    (setq helixel-last-action
          (helixel-action-create 'insert-text nil
            :keys (kbd "foo")
            :text "foo"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "foohello world hello"))))

;;; helixel-test-repeat.el ends here
;;; helixel-test-repeat-new.el --- Tests for new dot-repeat features  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf
;; Author: jixiuf <https://github.com/jixiuf>
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
;;
;; Tests for the unified dot-repeat features:
;; - movement (w/e/b) repeat
;; - textobj (iw/aw) repeat
;; - find-char (f/t) repeat
;; - chain with movement/textobj selections
;; - zero-length search dot-repeat

;;; Code:

(require 'helixel-search)


;; ── Movement dot-repeat (w/e/b) ──

(ert-deftest helixel-test-repeat-movement-wd-dot ()
  "wd then . deletes the next word."
  (helixel-test-with-buffer "hello world foo bar"
    (setq helixel--current-state 'normal)
    (helixel-forward-word-start)
    (setq last-command nil this-command 'helixel-kill)
    (helixel-kill)
    (should (string= (buffer-string) "world foo bar"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "foo bar"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "bar"))))

(ert-deftest helixel-test-repeat-movement-wd-3dot ()
  "3. after wd repeats the delete-word 3 times."
  (helixel-test-with-buffer "a b c d e f"
    (setq helixel--current-state 'normal)
    (helixel-forward-word-start)
    (setq last-command nil this-command 'helixel-kill)
    (helixel-kill)
    (should (string= (buffer-string) "b c d e f"))
    (helixel-repeat-edit 3)
    (should (string= (buffer-string) "e f"))))

(ert-deftest helixel-test-movement-wd-single-word-line ()
  "wd on a single-word line should NOT delete the trailing newline."
  (helixel-test-with-buffer "hello\nworld"
    (setq helixel--current-state 'normal)
    (goto-char 2) ; on 'e' of "hello"
    (helixel-forward-word-start)
    (should (string= (buffer-substring (region-beginning) (region-end))
                     "ello"))
    (setq last-command nil this-command 'helixel-kill)
    (helixel-kill)
    ;; Should keep the newline: "h\nworld" not "hworld"
    (should (string= (buffer-string) "h\nworld"))))

(ert-deftest helixel-test-movement-wc-single-word-line ()
  "wc on a single-word line should NOT delete the trailing newline."
  (helixel-test-with-buffer "hello\nworld"
    (setq helixel--current-state 'normal)
    (goto-char 2) ; on 'e' of "hello"
    (helixel-forward-word-start)
    (should (string= (buffer-substring (region-beginning) (region-end))
                     "ello"))
    (setq last-command nil this-command 'helixel-change)
    (helixel-change)
    (insert "XXX")
    (helixel-insert-exit)
    ;; Should keep the newline: "hXXX\nworld" not "hXXXworld"
    (should (string= (buffer-string) "hXXX\nworld"))))

(ert-deftest helixel-test-movement-wd-single-word-line-dot ()
  "wd then . on single-word lines should not delete newlines."
  (helixel-test-with-buffer "aaa\nbbb\nccc"
    (setq helixel--current-state 'normal)
    (goto-char 2) ; on 'a' of "aaa"
    (helixel-forward-word-start)
    (setq last-command nil this-command 'helixel-kill)
    (helixel-kill)
    ;; First wd: delete "aa" (suffix of "aaa"), keep newline
    (should (string= (buffer-string) "a\nbbb\nccc"))
    ;; Manually advance past the newline into the next word
    (forward-char) ; skip \n to 'b' of "bbb"
    (helixel-repeat-edit)
    ;; Dot-repeat: w from 'b' in "bbb" selects "bbb" (suffix),
    ;; d deletes it; newlines are preserved
    (should (string= (buffer-string) "a\n\nccc"))))


;; ── Textobj dot-repeat ──

(ert-deftest helixel-test-repeat-textobj-diw-dot ()
  "diw then . deletes inner word each time."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 3)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-kill)
    (helixel-kill)
    (should (string= (buffer-string) " world foo"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "  foo"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "  "))))

(ert-deftest helixel-test-repeat-textobj-ciw-dot ()
  "ciwXXX then . changes the next word to XXX."
  (helixel-test-with-buffer "hello world bar"
    (goto-char 3)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-change)
    (helixel-change)
    (insert "XXX")
    (helixel-insert-exit)
    (should (string= (buffer-string) "XXX world bar"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "XXX XXX bar"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "XXX XXX XXX"))))

(ert-deftest helixel-test-repeat-textobj-diw-dot-backward ()
  "miw d then -. flips direction and deletes previous word."
  (helixel-test-with-buffer "aaa bbb ccc ddd"
    (goto-char 5)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-kill)
    (helixel-kill)
    (should (string= (buffer-string) "aaa  ccc ddd"))
    ;; -. permanently flips direction + 1 repeat backward
    (helixel-repeat-edit '-)
    ;; aaa deleted (the word before point)
    (should (string= (buffer-string) "  ccc ddd"))
    (should helixel--repeat-permanent-flip)
    ;; . continues backward — at bob with leading spaces, selects
    ;; the non-word region (spaces) and deletes it.
    (helixel-repeat-edit)
    (should (string= (buffer-string) "ccc ddd"))
    (setq helixel--repeat-permanent-flip nil)))

(ert-deftest helixel-test-repeat-textobj-miw-d-backward-flip ()
  "-. flips direction permanently; -. again flips back to forward."
  (helixel-test-with-buffer "aaa bbb ccc"
    (goto-char 5)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-kill)
    (helixel-kill)
    (should (string= (buffer-string) "aaa  ccc"))
    ;; -. backward: deletes "aaa"
    (helixel-repeat-edit '-)
    (should helixel--repeat-permanent-flip)
    (should (string= (buffer-string) "  ccc"))
    ;; -. again: flips back to forward
    (helixel-repeat-edit '-)
    (should (not helixel--repeat-permanent-flip))
    (setq helixel--repeat-permanent-flip nil)))

;; ── Find-char dot-repeat ──

(ert-deftest helixel-test-repeat-findchar-fxd-dot ()
  "f x d then . deletes up to next x."
  (helixel-test-with-buffer "hello x world x foo"
    (helixel-find-next-char ?x)
    (setq last-command nil this-command 'helixel-kill)
    (helixel-kill)
    (should (string= (buffer-string) " world x foo"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) " foo"))
    ;; . with no more 'x' prints message, doesn't error
    (helixel-repeat-edit)
    (should (string= (buffer-string) " foo"))))

(ert-deftest helixel-test-repeat-findchar-txd-dot ()
  "t x d then . deletes up to (not including) next x."
  (helixel-test-with-buffer "hello x world x foo"
    (helixel-find-till-char ?x)
    (setq last-command nil this-command 'helixel-kill)
    (helixel-kill)
    (should (string= (buffer-string) "x world x foo"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "x foo"))))


;; ── Normal-mode movement dot-repeat: only final word selected ──

(ert-deftest helixel-test-repeat-movement-normal-mode-single-word ()
  "w w w d in normal mode then . deletes only the 3rd word."
  (helixel-test-with-buffer "word1 word2 word3 word4 word5 word6 word7 word8"
    (setq helixel--current-state 'normal)
    (helixel-forward-word-start)
    (helixel-forward-word-start)
    (helixel-forward-word-start)
    (setq last-command nil this-command 'helixel-kill)
    (helixel-kill)
    ;; d deletes the word at point (word3)
    (should (string= (buffer-string)
                     "word1 word2 word4 word5 word6 word7 word8"))
    ;; . deletes word6 (the 3rd word from current position)
    (helixel-repeat-edit)
    (should (string= (buffer-string)
                     "word1 word2 word4 word5 word7 word8"))))
(ert-deftest helixel-test-repeat-pick-change-end-to-end ()
  "After ciwX<esc>, `helixel-repeat-edit-pick' replays the change correctly.
Verifies that event ring head carries the inserted text in its payload."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-change)
    (helixel-change)
    (insert "X")
    (helixel-insert-exit)
    ;; Verify event ring head has the inserted-text payload
    (let ((front-event (car helixel--action-ring)))
      (should front-event)
      (should (plist-get (helixel-action-payload front-event)
                         :inserted-text))
      (should (string= (plist-get (helixel-action-payload front-event)
                                  :inserted-text)
                       "X")))
    ;; Replay from event ring (simulating pick)
    (goto-char 4)
    (let ((front-event (car helixel--action-ring)))
      (setq helixel-last-action front-event))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "X X foo"))))

(ert-deftest helixel-test-repeat-pick-reconstruction-invariant ()
  "Picked event: reconstructed tx preserves op, sel, runner, not just payload.
Tests the reconstruction path inside `helixel-repeat-edit-pick'
\(apply #\='helixel-action-create op sel :display :runner payload).
This ensures that `helixel-action-shallow-copy'+`setq' replaces the
entire `helixel-last-action', not just the payload."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 1)
    ;; Record: ciw X <esc>
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-change)
    (helixel-change)
    (insert "X")
    (helixel-insert-exit)
    ;; Get the front event from the ring
    (let* ((event (car helixel--action-ring))
           ;; Reconstruct tx exactly as repeat-edit-pick does
           (reconstructed
            (apply #'helixel-action-create
                   (helixel-action-op event)
                   (helixel-action-sel event)
                   :display (helixel--action-display-format event)
                   :runner (helixel-action-runner event)
                   (helixel-action-payload event))))
      (should event)
      (should reconstructed)
      ;; Verify all replay-relevant slots match
      (should (eq (helixel-action-op reconstructed)
                  (helixel-action-op event)))
      (should (eq (helixel-action-sel reconstructed)
                  (helixel-action-sel event)))
      (should (eq (helixel-action-runner reconstructed)
                  (helixel-action-runner event)))
      ;; Payload: inserted-text must be preserved
      (should (string=
               (plist-get (helixel-action-payload reconstructed)
                          :inserted-text)
               (plist-get (helixel-action-payload event)
                          :inserted-text)))
      ;; Set as last-tx and replay
      (goto-char 4)
      (setq helixel-last-action (helixel-action-shallow-copy reconstructed))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "X X foo")))))

(ert-deftest helixel-test-repeat-pick-insert-end-to-end ()
  "After iZ<esc>, ring head has :text payload; pick replays correctly."
  (let ((helixel-last-action nil)
        (helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "abc"
      (set-match-data nil) ; clear stale match data from prior tests
      (goto-char 2)
        (setq last-command nil this-command 'helixel-insert)
        (helixel-insert)
        (insert "Z")
        (helixel-insert-exit)
        ;; Verify event ring head has :text payload
        (let ((front-event (car helixel--action-ring)))
          (should front-event)
          (should (plist-get (helixel-action-payload front-event) :text))
          (should (string= (plist-get (helixel-action-payload front-event)
                                      :text)
                           "Z")))
        ;; Replay from event ring (simulating pick)
        (goto-char 4)
        (let ((front-event (car helixel--action-ring)))
          (setq helixel-last-action front-event))
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
          this-command 'helixel-change)
    (helixel-change)
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
modify `helixel--pending-sel'."
  (helixel-test-with-buffer "hello world foo bar"
    (goto-char 1)
    ;; Record a v w w d sequence
    (helixel--switch-state 'visual)
    (setq last-command nil this-command 'helixel-forward-word-start)
    (helixel-forward-word-start)
    (helixel-forward-word-start)
    (setq last-command 'helixel-forward-word-start
          this-command 'helixel-kill)
    (helixel-kill)
    (helixel--switch-state 'normal)
    ;; After kill, remaining is "foo bar"
    (should (string= (buffer-string) "foo bar"))
    ;; Save the stored sel-ctx
    (let ((stored-sel (copy-sequence (helixel-action-sel helixel-last-action))))
      ;; Replay
      (goto-char 1)
      (helixel-repeat-edit)
      ;; helixel--pending-sel should be nil after consumption
      (should (null helixel--pending-sel))
      ;; Should be "bar" after second kill (killed "foo ")
      (should (string= (buffer-string) "bar"))
      ;; The stored tx should be unchanged
      (should (equal (helixel-action-sel helixel-last-action) stored-sel)))))

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
    (helixel-test--mock-sel-type 'rect)
    (setq last-command nil this-command 'helixel-change)
    (helixel-change)
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
    (setq helixel-last-action
          (helixel-action-create 'insert-text
            (helixel-sel-create
             'search
             '(:pattern "hello" :dir forward
               :entry-kind insert :cursor-offset 1))
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
Cursor-offset is set manually; insert-mode recording captures keys in real flow."
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
    (setq helixel-last-action
          (helixel-action-create 'insert-text
            (helixel-sel-create
             'search
             '(:pattern "hello" :dir forward
               :entry-kind insert :cursor-offset 1))
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
    (setq helixel-last-action
          (helixel-action-create 'insert-text
            (helixel-sel-create
             'search
             '(:pattern "hello" :dir forward
               :entry-kind append :cursor-offset -2))
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)))
      ;; a — insert-after at match-end (unified search path)
      (setq last-command nil this-command 'helixel-insert-after)
      (helixel-insert-after)
      ;; foo — insert at point (no cursor movement)
      (insert "foo")
      (helixel-insert-exit)
      ;; Buffer after edit: "hellofoo world hello"
      (should (string= (buffer-string) "hellofoo world hello"))
      (should (string= (plist-get (helixel-action-payload helixel-last-action) :text)
                       "foo"))
      (let ((sel (helixel-action-sel helixel-last-action)))
        (should (eq (helixel-sel-kind sel) 'search))
        (should (eq (helixel-sel-entry-kind sel) 'append)))
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)))
      ;; a — insert-after at match-end
      (setq last-command nil this-command 'helixel-insert-after)
      (helixel-insert-after)
      (insert "foo")
      (helixel-insert-exit)
      ;; Buffer after edit: "hello world hellofoo"
      (should (string= (buffer-string) "hello world hellofoo"))
      (let ((sel (helixel-action-sel helixel-last-action)))
        (should (eq (helixel-sel-kind sel) 'search))
        (should (eq (helixel-sel-entry-kind sel) 'append)))
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
    (setq helixel--pending-sel
          (helixel-sel-create
           'search '(:pattern "hello" :dir forward)))
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)))
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)))
      (setq last-command nil this-command 'helixel-insert)
      (helixel-insert)
      (insert "X")
      (helixel-insert-exit)
      (should (string= (buffer-string) "Xhello world hello"))
      (let ((sel (helixel-action-sel helixel-last-action)))
        (should (eq (helixel-sel-kind sel) 'search))
        (should (eq (helixel-sel-entry-kind sel) 'insert)))
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)))
      (setq last-command nil this-command 'helixel-change)
      (helixel-change)
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)))
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
      (setq helixel-last-action
            (helixel-action-create 'kill
              (helixel-sel-create 'movement
                '(:moves ((helixel-forward-word-start . 1))))))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "world foo bar")))))

(ert-deftest helixel-test-repeat-movement-kill-at-word-start ()
  "vw d at position 1, then move to word start, . selects the word there."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world foo bar"
      (goto-char 1)
      (setq helixel-last-action
            (helixel-action-create 'kill
              (helixel-sel-create 'movement
                '(:moves ((helixel-forward-word-start . 1))))))
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
      (setq helixel-last-action
            (helixel-action-create 'kill
              (helixel-sel-create 'movement
                '(:moves ((helixel-forward-word-start . 2))))))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "foo bar")))))
;; ── , comma repeat-selection end-to-end ──

(ert-deftest helixel-test-repeat-selection-line-then-dot ()
  ", after x d previews the line, then . kills it."
  :tags '(repeat comma)
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "aaa\nbbb\nccc"
      (goto-char 1)
      (setq helixel-last-action
            (helixel-action-create
             'kill
             (helixel-sel-create 'line
               '(:dir forward :count 1))))
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
      (setq helixel-last-action
            (helixel-action-create
             'kill
             (helixel-sel-create 'line
               '(:dir forward :count 1))))
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
      (setq helixel-last-action
            (helixel-action-create
             'kill
             (helixel-sel-create 'movement
               '(:moves ((helixel-forward-word-start . 1))))))
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
    (setq helixel-last-action
          (helixel-action-create
           'insert-text
           (helixel-sel-create
            'line
            '(:dir forward :count 1 :entry-kind insert))
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
    (setq helixel-last-action
          (helixel-action-create
           'insert-text
           (helixel-sel-create
            'line
            '(:dir forward :count 1 :entry-kind insert))
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
    (setq helixel-last-action
          (helixel-action-create
           'insert-text
           (helixel-sel-create
            'line
            '(:dir forward :count 1 :entry-kind insert))
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
    (setq helixel-last-action
          (helixel-action-create
           'insert-text
           (helixel-sel-create
            'line
            '(:dir forward :count 1 :entry-kind insert))
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
With insert-mode key recording, keys capture the full sequence."
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
      (setq helixel-last-action
            (helixel-action-create 'insert-text
              (helixel-sel-create
               'search
               '(:pattern "hello" :dir forward :entry-kind insert))
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "$" :dir forward)))
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "$" :dir forward)))
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

;; ── ^ (beginning-of-line) zero-length anchor + backward search ──

(ert-deftest helixel-test-repeat-search-insert-bol-zero-length-backward-dot ()
  "Scenario: ?^<RET> i foo <ESC> . — backward search for ^, insert at bol.
\=`^' is a zero-length anchor.  After inserting at bol, point moves past
the match so `looking-at' fails, and the backward-search proximity check
must detect we're still on the same line as the ^ match."
  :tags '(repeat search)
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "line one\nline two\nline three"
      ;; ?^<RET> — backward search for beginning-of-line
      (goto-char (point-max))
      (re-search-backward "^")
      ;; Match at bol of line 3
      (let ((isearch-success t)
            (isearch-string "^")
            (isearch-regexp t)
            (isearch-forward nil)
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "^" :dir backward)))
      ;; i — insert at match-beginning (bol of line 3)
      (setq last-command nil this-command 'helixel-insert)
      (helixel-insert)
      (insert "foo")
      (helixel-insert-exit)
      ;; i at bol of "line three" inserts at beginning:
      ;; "line one\nline two\nfooline three"
      (should (string= (buffer-string) "line one\nline two\nfooline three"))
      ;; . — backward: should insert "foo" at bol of line 2
      (helixel-repeat-edit)
      (should (string= (buffer-string) "line one\nfooline two\nfooline three"))
      ;; . again — backward: should insert "foo" at bol of line 1
      (helixel-repeat-edit)
      (should (string= (buffer-string) "fooline one\nfooline two\nfooline three")))))

(ert-deftest helixel-test-repeat-search-append-bol-zero-length-backward-dot ()
  "Scenario: ?^<RET> a foo <ESC> . — backward search for ^, append at bol."
  :tags '(repeat search)
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "line one\nline two\nline three"
      (goto-char (point-max))
      (re-search-backward "^")
      (let ((isearch-success t)
            (isearch-string "^")
            (isearch-regexp t)
            (isearch-forward nil)
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "^" :dir backward)))
      ;; a — append at match-end (also bol for ^, since it's zero-length)
      (setq last-command nil this-command 'helixel-insert-after)
      (helixel-insert-after)
      (insert "foo")
      (helixel-insert-exit)
      ;; a at bol of "line three" appends AFTER region-end = bol:
      ;; "line one\nline two\nfooline three" (same as insert for zero-length)
      (should (string= (buffer-string) "line one\nline two\nfooline three"))
      ;; . — backward: should insert "foo" at bol of line 2
      (helixel-repeat-edit)
      (should (string= (buffer-string) "line one\nfooline two\nfooline three"))
      ;; . again — backward: should insert "foo" at bol of line 1
      (helixel-repeat-edit)
      (should (string= (buffer-string) "fooline one\nfooline two\nfooline three")))))

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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)))
      (setq last-command nil
            this-command 'helixel-change)
      (helixel-change)
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)))
      (setq last-command nil
            this-command 'helixel-change)
      (helixel-change)
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)))
      (setq last-command nil
            this-command 'helixel-change)
      (helixel-change)
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)))
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)))
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)))
      (setq last-command nil
            this-command 'helixel-change)
      (helixel-change)
      (insert "XXX")
      (helixel-insert-exit)
      (should (string= (buffer-string) "hello A XXX B hello C"))
      ;; C-u . -> all matches from point-min forward
      (helixel-repeat-edit '(4))
      (should (string= (buffer-string) "XXX A XXX B XXX C")))))

(ert-deftest helixel-test-repeat-all-buffer-search-pattern-in-replacement ()
  "C-u . after /hello c helloworld <ESC> changes all 'hello' to 'helloworld'.
When the replacement text contains the search pattern (e.g. hello → helloworld),
the all-buffer scan must skip the already-edited match so it does not re-edit
the replacement's prefix."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello\nhello\nhello"
      (goto-char 1)
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)))
      (setq last-command nil
            this-command 'helixel-change)
      (helixel-change)
      (insert "helloworld")
      (helixel-insert-exit)
      ;; C-u . -> all matches from point-min forward
      (helixel-repeat-edit '(4))
      ;; Every "hello" should become "helloworld" exactly once.
      ;; If the scan re-edits the already-modified first line,
      ;; we'd get "helloworldworld".
      (should (string= (buffer-string)
                       "helloworld\nhelloworld\nhelloworld")))))

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
    (setq helixel-last-action
          (helixel-action-create 'insert-text
            (helixel-sel-create
             'search
             '(:pattern "hello" :dir forward :entry-kind insert))
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)))
      (setq last-command nil
            this-command 'helixel-change)
      (helixel-change)
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)))
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

;; ── 0. with zero-length anchors: must not hang ──

(ert-deftest helixel-test-repeat-all-dir-eol-forward-no-hang ()
  "0. after /$ aX<ESC> terminates at end-of-buffer without hanging."
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "$" :dir forward)))
      (setq last-command nil this-command 'helixel-insert-after)
      (helixel-insert-after)
      (insert "X")
      (helixel-insert-exit)
      (should (string= (buffer-string) "line oneX\nline two\nline three"))
      ;; 0. -> append "X" at remaining eols, must terminate
      (helixel-repeat-edit 0)
      (should (string= (buffer-string) "line oneX\nline twoX\nline threeX")))))

(ert-deftest helixel-test-repeat-all-dir-bol-backward-no-hang ()
  "0. after ?^ iX<ESC> terminates at beginning-of-buffer without hanging."
  :tags '(repeat search)
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "line one\nline two\nline three"
      (goto-char (point-max))
      (re-search-backward "^")
      (let ((isearch-success t)
            (isearch-string "^")
            (isearch-regexp t)
            (isearch-forward nil)
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "^" :dir backward)))
      (setq last-command nil this-command 'helixel-insert)
      (helixel-insert)
      (insert "X")
      (helixel-insert-exit)
      (should (string= (buffer-string) "line one\nline two\nXline three"))
      ;; 0. -> insert "X" at remaining bols backward, must terminate
      (helixel-repeat-edit 0)
      (should (string= (buffer-string) "Xline one\nXline two\nXline three")))))

;; ── C-u . with zero-length anchors: must not hang ──

(ert-deftest helixel-test-repeat-all-buffer-eol-forward-no-hang ()
  "C-u . after /$ aX<ESC> terminates at end-of-buffer without hanging."
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "$" :dir forward)))
      (setq last-command nil this-command 'helixel-insert-after)
      (helixel-insert-after)
      (insert "X")
      (helixel-insert-exit)
      (should (string= (buffer-string) "line oneX\nline two\nline three"))
      ;; C-u . -> append "X" at ALL eols, must terminate
      (helixel-repeat-edit '(4))
      (should (string= (buffer-string) "line oneX\nline twoX\nline threeX")))))

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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)))
      (setq last-command nil
            this-command 'helixel-change)
      (helixel-change)
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)))
      (setq last-command nil
            this-command 'helixel-change)
      (helixel-change)
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)))
      (setq last-command nil
            this-command 'helixel-change)
      (helixel-change)
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)))
      (setq last-command nil
            this-command 'helixel-change)
      (helixel-change)
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
      (setq helixel-last-action
            (helixel-action-create 'kill
              (helixel-sel-create 'line
                '(:dir forward :count 2))))
      ;; First . kills line1+line2, leaving line3
      (helixel-repeat-edit)
      (should (string= (buffer-string) "line3\n"))
      ;; 0. on non-search sel -> advance fails (can't select
      ;; 2 lines from 1 remaining), no-ops silently.
      (helixel-repeat-edit 0)
      (should (string= (buffer-string) "line3\n")))))

(ert-deftest helixel-test-repeat-reverse-keeps-stored-dir ()
  "`-1 .' permanently flips the stored direction (like N for search).
After `-1 .' a plain `.` continues in the flipped direction."
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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)))
      (setq last-command nil
            this-command 'helixel-change)
      (helixel-change)
      (insert "XXX")
      (helixel-insert-exit)
      (should (string= (buffer-string) "hello A XXX B hello C"))
      ;; Direction is forward (no permanent flip)
      (should (not helixel--repeat-permanent-flip))
      ;; -1 . — permanently flips to backward, changes A
      (helixel-repeat-edit -1)
      (should (string= (buffer-string) "XXX A XXX B hello C"))
      ;; Direction is now permanently backward
      (should helixel--repeat-permanent-flip)
      ;; Plain `.` continues backward — nothing left to change
      ;; (A was already changed), so it should error silently.
      (let ((helixel--inhibit-repeat-record t))
        (condition-case nil
            (helixel-repeat-edit)
          (error nil)))
      ;; Buffer unchanged
      (should (string= (buffer-string) "XXX A XXX B hello C")))))

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
      (setq helixel--pending-sel
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)))
      (setq last-command nil
            this-command 'helixel-change)
      (helixel-change)
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
    (setq helixel-last-action
          (helixel-action-create 'insert-text
            (helixel-sel-create
             'search
             '(:pattern "hello" :dir forward :entry-kind insert))
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
    (setq helixel-last-action
          (helixel-action-create 'change
            (helixel-sel-create 'line '(:dir forward :count 1))
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
    (setq helixel-last-action
          (helixel-action-create 'kill
            (helixel-sel-create 'line '(:dir forward :count 1))))
    ;; First . kills line 1; cursor at BOL of line 2
    (helixel-repeat-edit)
    (should (string= (buffer-string) "line2\nline3\nline4\n"))
    ;; C-u . from recorded position: forward skips line 2
    ;; (marker now pointing there), kills lines 3 and 4;
    ;; backward from marker: skip-current hits bobp, exits.
    ;; Line 2 survives.
    (helixel-repeat-edit '(4))
    (should (string= (buffer-string) "line2\n"))))

;;; helixel-test-jump.el ends here

;;; helixel-test-repeat-new.el ends here


;;; ── ; + . repeat: span extension across movement/search/find-char/textobj ──

(ert-deftest helixel-test-repeat-semicolon-movement-ww-dot ()
  "ww ; d . deletes the full 2-word span on each line."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--current-state 'normal
          helixel--action-ring nil
          helixel--live-action nil
          helixel--pending-sel nil
          helixel--action-pos nil
          helixel--inhibit-repeat-record nil
          helixel--inhibit-action-track nil
          helixel--repeat-preview-pos nil
          helixel--repeat-permanent-flip nil)
    (insert "hello world foo bar baz qux")
    (goto-char 1)
    (deactivate-mark)
    ;; w w — two word movements
    (setq last-command nil this-command 'helixel-forward-word-start)
    (helixel-forward-word-start)
    (setq last-command 'helixel-forward-word-start
          this-command 'helixel-forward-word-start)
    (helixel-forward-word-start)
    ;; ; — session mark (marks start of session, extends region)
    (helixel--action-cycle)
    ;; d — delete the full span (hello world)
    (setq last-command nil this-command 'helixel-kill)
    (helixel-kill)
    (should (string= (buffer-string) "foo bar baz qux"))
    ;; . — repeat: advance 2 words + full span → deletes "foo bar"
    (helixel-repeat-edit)
    (should (string= (buffer-string) "baz qux"))
    ;; . — again: advance 2 words → deletes "baz "
    (helixel-repeat-edit)
    (should (string= (buffer-string) "qux"))))

(ert-deftest helixel-test-repeat-semicolon-search-n-dot ()
  "/hello RET n ; d . deletes from match1 to match2, then repeat."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil
          helixel--live-action nil
          helixel--pending-sel nil
          helixel--action-pos nil
          helixel--inhibit-repeat-record nil
          helixel--inhibit-action-track nil
          helixel--repeat-preview-pos nil
          helixel--repeat-permanent-flip nil)
    (insert "x hello y hello z hello w")
    (goto-char 1)
    (deactivate-mark)
    ;; Simulate /hello RET — find first match
    (re-search-forward "hello")
    (let ((isearch-success t)
          (isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-other-end (match-beginning 0)))
      ;; Create a live-event so the hook can set mark-region and commit
      (setq helixel--live-action
            (make-helixel-action
             :category 'search :subcat 'search
             :mark-region (let ((pm (point-marker)))
                             (cons pm (copy-marker pm t)))
             :timestamp (float-time)
             :buffer (current-buffer)))
      (helixel-search--done-hook))
    ;; n — next match (second hello)
    (goto-char (point-min))
    (re-search-forward "hello")
    (re-search-forward "hello")
    (let ((isearch-success t)
          (isearch-string "hello")
          (isearch-other-end (match-beginning 0)))
      (helixel-search--handle-done nil)
      (helixel-search--set-sel-ctx))
    ;; ; — session mark
    (helixel--action-cycle)
    ;; d — delete from session-start to current (first to second hello)
    (setq last-command nil this-command 'helixel-kill)
    (helixel-kill)
    ;; After deletion: "x  z hello w" (first two hellos gone)
    (should (string= (buffer-string) "x  z hello w"))
    ;; . — advance search, n-count=1 extra, span → deletes " z hello"
    (helixel-repeat-edit)
    (should (string= (buffer-string) "x  w"))))

(ert-deftest helixel-test-repeat-semicolon-findchar-nn-dot ()
  "f x n n ; d . deletes from first x to third x, then repeat."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--pending-sel nil helixel--action-pos nil
          helixel--inhibit-repeat-record nil
          helixel--inhibit-action-track nil
          helixel--repeat-preview-pos nil
          helixel--repeat-permanent-flip nil
          helixel--active-search nil)
    (insert "a x b x c x d x e")
    (goto-char 1)
    (deactivate-mark)
    ;; f x — find first x
    (setq last-command nil this-command 'helixel-find-next-char)
    (helixel-find-next-char ?x)
    ;; n — second x
    (setq last-command 'helixel-repeat-last-motion
          this-command 'helixel-repeat-last-motion)
    (helixel-repeat-last-motion)
    ;; n — third x
    (helixel-repeat-last-motion)
    ;; ; — session mark
    (helixel--action-cycle)
    ;; d — delete from session-start to current (first to third x)
    (setq last-command nil this-command 'helixel-kill)
    (helixel-kill)
    ;; After: "a  d x e" (first three x's and text between gone)
    (should (string= (buffer-string) " d x e"))
    ;; . — advance find-char + 2 extra n + span → deletes " d x"
    (helixel-repeat-edit)
    (should (string= (buffer-string) " e"))))

(ert-deftest helixel-test-repeat-semicolon-textobj-iw-iw-iw-dot ()
  "miw miw miw ; d . deletes from 1st to 3rd word, then repeat."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--pending-sel nil helixel--action-pos nil
          helixel--inhibit-repeat-record nil
          helixel--inhibit-action-track nil
          helixel--repeat-preview-pos nil
          helixel--repeat-permanent-flip nil)
    (insert "hello world foo bar baz qux")
    (goto-char 1)
    (deactivate-mark)
    ;; miw — select first inner word (hello)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    ;; miw — second word (world)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    ;; miw — third word (foo)
    (helixel-mark-inner-word)
    ;; ; — session mark
    (helixel--action-cycle)
    ;; d — delete from session-start to current
    (setq last-command nil this-command 'helixel-kill)
    (helixel-kill)
    ;; After: " bar baz qux" (hello world foo deleted)
    (should (string= (buffer-string) " bar baz qux"))
    ;; . — textobj count=3 + span → deletes "bar baz qux"
    (helixel-repeat-edit)
    (should (string= (buffer-string) " qux"))))

;; ── , all-buffer reverse preview (C-u - ,) ──

(ert-deftest helixel-test-repeat-selection-all-buffer-reverse-search ()
  "C-u - , after /search d previews all matches from bottom.
Tests the generic `helixel--repeat-preview' reverse path."
  :tags '(repeat comma)
  (helixel-test-with-buffer "hello A hello B hello C"
    (goto-char 1)
    (setq helixel-last-action
          (helixel-action-create 'kill
            (helixel-sel-create 'search
              '(:pattern "hello" :dir forward))))
    ;; C-u - , → scan from point-max backward, end at first (top) match
    (helixel-repeat-selection '(-4))
    (should (region-active-p))
    ;; Last advance lands on first match ("hello A" at pos 1–6)
    (should (= (region-beginning) 1))
    (should (= (match-beginning 0) 1))))

(ert-deftest helixel-test-repeat-selection-all-buffer-reverse-line ()
  "C-u - , after x d previews all lines from bottom.
Tests the line-specific `helixel--repeat-line-pass' reverse branch."
  :tags '(repeat comma)
  (helixel-test-with-buffer "aaa\nbbb\nccc\n"
    (goto-char 1)
    (setq helixel-last-action
          (helixel-action-create 'kill
            (helixel-sel-create 'line
              '(:dir forward :count 1))))
    ;; C-u - , → scan from point-max backward, end at top line
    (helixel-repeat-selection '(-4))
    (should (region-active-p))
    (should (= (line-number-at-pos) 1))
    (should (= (region-beginning) 1))))

(ert-deftest helixel-test-repeat-selection-all-buffer-reverse-search-insert ()
  "C-u - , after /search c<ESC> previews all matches from bottom with entry-kind."
  :tags '(repeat comma)
  (helixel-test-with-buffer "hello A hello B hello C"
    (goto-char 1)
    (setq helixel-last-action
          (helixel-action-create 'insert-text
            (helixel-sel-create 'search
              '(:pattern "hello" :dir forward :entry-kind insert))
            :text "X"))
    ;; C-u - , → scan from point-max backward, end at first (top) match
    (helixel-repeat-selection '(-4))
    (should (region-active-p))
    (should (= (region-beginning) 1))
    (should (= (match-beginning 0) 1))))

;; ── Forward , all-buffer preview ──

(ert-deftest helixel-test-repeat-selection-all-buffer-forward-search ()
  "C-u , after /search d previews all matches from top.
Tests the forward `helixel--repeat-preview' path."
  :tags '(repeat comma)
  (helixel-test-with-buffer "hello A hello B hello C"
    (goto-char 1)
    (setq helixel-last-action
          (helixel-action-create 'kill
            (helixel-sel-create 'search
              '(:pattern "hello" :dir forward))))
    ;; C-u , → scan from point-min forward, end at last match
    (helixel-repeat-selection '(4))
    (should (region-active-p))
    ;; Last advance lands on third match ("hello C")
    (should (>= (region-beginning) 14))
    (should (string= (match-string 0) "hello"))))

(ert-deftest helixel-test-repeat-selection-all-buffer-forward-line ()
  "C-u , after x d previews all lines from top.
Tests the line-specific `helixel--repeat-line-pass' forward branch.
After preview, `save-excursion' restores point to original position."
  :tags '(repeat comma)
  (helixel-test-with-buffer "aaa\nbbb\nccc\n"
    (goto-char 1)
    (setq helixel-last-action
          (helixel-action-create 'kill
            (helixel-sel-create 'line
              '(:dir forward :count 1))))
    ;; C-u , → scan from point-min forward.
    ;; line-pass starts at line 2 (after initial forward-line),
    ;; finding 2 remaining non-blank lines.
    (helixel-repeat-selection '(4))
    ;; After preview, last advance creates an active region.
    (should (region-active-p))))

;; ── normal-mode + :span interaction ──

(ert-deftest helixel-test-repeat-semicolon-movement-normalmode-span ()
  "ww ; d . with normal-mode movements: span forces visual accumulation.
When :span is set, `helixel--recreate-movement' ignores :normal-mode
so `; d .' replays the full two-word span rather than resetting
the selection on each word."
  :tags '(repeat semicolon span)
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--current-state 'normal
          helixel--action-ring nil
          helixel--live-action nil
          helixel--pending-sel nil
          helixel--action-pos nil
          helixel--inhibit-repeat-record nil
          helixel--inhibit-action-track nil
          helixel--repeat-preview-pos nil
          helixel--repeat-permanent-flip nil)
    (insert "hello world foo bar baz qux")
    (goto-char 1)
    (deactivate-mark)
    ;; w w — two normal-mode word movements
    (setq last-command nil this-command 'helixel-forward-word-start)
    (helixel-forward-word-start)
    (setq last-command 'helixel-forward-word-start
          this-command 'helixel-forward-word-start)
    (helixel-forward-word-start)
    ;; ; — pushes sel with :span t, :normal-mode from the original sel
    (helixel--action-cycle)
    ;; d — delete full span from session-start (hello world)
    (setq last-command nil this-command 'helixel-kill)
    (helixel-kill)
    (should (string= (buffer-string) "foo bar baz qux"))
    ;; . — normal-mode + span → should still use visual accumulation
    (helixel-repeat-edit)
    (should (string= (buffer-string) "baz qux"))))

;; ── , n-times preview ──

(ert-deftest helixel-test-repeat-selection-n-times-search ()
  "3, after /search d previews 3 matches forward.
Tests the n-times branch of `helixel--repeat-preview'."
  :tags '(repeat comma)
  (helixel-test-with-buffer "hello A hello B hello C hello D"
    (goto-char 1)
    (setq helixel-last-action
          (helixel-action-create 'kill
            (helixel-sel-create 'search
              '(:pattern "hello" :dir forward))))
    ;; 3, → advance 3 times, land on third match
    (helixel-repeat-selection 3)
    (should (region-active-p))
    ;; Should be on third match ("hello C")
    (should (>= (region-beginning) 14))
    (should (string= (match-string 0) "hello"))))

;; ── , all-dir preview ──

(ert-deftest helixel-test-repeat-selection-all-dir-search ()
  "0, after /search d previews all remaining matches.
Tests the all-dir branch of `helixel--repeat-preview'."
  :tags '(repeat comma)
  (helixel-test-with-buffer "hello A hello B hello C"
    (goto-char 1)
    (setq helixel-last-action
          (helixel-action-create 'kill
            (helixel-sel-create 'search
              '(:pattern "hello" :dir forward))))
    ;; 0, → scan all remaining matches from current position
    (helixel-repeat-selection 0)
    (should (region-active-p))
    ;; Last advance lands on last match ("hello C")
    (should (>= (region-beginning) 14))
    (should (string= (match-string 0) "hello"))))

;; ── Step 14: positional preview handoff regression ──

(ert-deftest helixel-test-repeat-preview-cleared-by-other-command ()
  "After \\[helixel-repeat-last-motion], moving point invalidates the preview handoff.
Replaces the old `helixel--repeat-preview-pos' flag +
`post-command-hook' stale-clear design: a marker at the preview
position auto-invalidates the moment point moves."
  :tags '(repeat comma preview-stale)
  (helixel-test-with-buffer "hello A hello B hello C"
    (goto-char 1)
    (setq helixel-last-action
          (helixel-action-create 'kill
            (helixel-sel-create 'search
              '(:pattern "hello" :dir forward))))
    ;; , -> sets the preview marker at the previewed position
    (helixel-repeat-selection nil)
    (should (markerp helixel--repeat-preview-pos))
    (should (= (point) (marker-position helixel--repeat-preview-pos)))
    ;; Move point: marker still exists but no longer matches point —
    ;; the next \\[helixel-repeat-edit] would NOT treat this as a preview replay.
    (forward-char 1)
    (should (markerp helixel--repeat-preview-pos))
    (should-not (= (point)
                   (marker-position helixel--repeat-preview-pos)))))

