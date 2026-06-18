;;; helixel-test-rect.el --- Tests for Helixel: rectangle selection and editing  -*- lexical-binding: t; -*-

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


(require 'ert)
(require 'helixel)

;;; Rect selection tests

(ert-deftest helixel-test-select-rectangle-starts-rect ()
  "Test `helixel-select-rectangle' starts rectangle-mark-mode."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (call-interactively #'helixel-select-rectangle)
    (should rectangle-mark-mode)
    (should (eq (helixel--sel-type) 'rect))
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

;;; helixel--region-type rect tests

(ert-deftest helixel-test-selection-type-rect ()
  "Test `helixel--region-type' returns `rect' for rectangle selection."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (setq helixel--sel-type-override 'rect)
    (push-mark (point) t t)
    (goto-char 8)
    (rectangle-mark-mode 1)
    (should (eq (helixel--region-type) 'rect))
    (rectangle-mark-mode -1)))

(ert-deftest helixel-test-selection-type-rect-without-mode ()
  "Test `helixel--region-type' returns nil when rect type but mode off."
  (helixel-test-with-buffer "first line\nsecond line"
    (setq helixel--sel-type-override 'rect)
    (push-mark (point) t t)
    (goto-char 8)
    ;; rectangle-mark-mode not active
    (should-not (helixel--region-type))))

;;; helixel-clear-data clears rect mode

(ert-deftest helixel-test-clear-data-clears-rect ()
  "Test `helixel-clear-data' disables rectangle-mark-mode."
  (helixel-test-with-buffer "first line\nsecond line"
    (helixel-select-rectangle)
    (helixel-clear-data)
    (should-not rectangle-mark-mode)
    (should-not (helixel--sel-type))))

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

;;; helixel-kill (d) rect tests

(ert-deftest helixel-test-kill-thing-rect ()
  "Test killing a rectangle selection."
  (helixel-test-with-buffer "ABC line1\nDEF line2\nGHI line3"
    (let ((kill-ring nil))
      (goto-char 1)
      (push-mark (point) t t)
      (goto-char 14) ;; col 3 on line 2 (space after "DEF")
      (rectangle-mark-mode 1)
      (setq helixel--sel-type-override 'rect)
      (helixel-kill)
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
      (setq helixel--sel-type-override 'rect)
      (helixel-kill)
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
      (setq helixel--sel-type-override 'rect)
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
    (setq helixel--sel-type-override 'rect)
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
    (setq helixel--sel-type-override 'rect)
    (helixel-replace)
    ;; "!!" inserted at top-left of rectangle area
    (should (string= (buffer-string) "!! line1\n line2\nGHI line3"))))
;;; helixel-yank (p) rect tests

(ert-deftest helixel-test-yank-rect ()
  "`p' pastes a rect kill after cursor (Vim-like).
At bol, moves past first char so rect starts at column 1."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (kill-new (helixel--rect-wise-text '("<<<" ">>>")))
    (goto-char 1)                    ; on 'l', moves to col 1
    (helixel-yank)
    (should (string= (buffer-string) "l<<<ine1\nl>>>ine2\nline3"))))

(ert-deftest helixel-test-yank-rect-after-cursor ()
  "`p' pastes rect after current char at mid-line cursor."
  (helixel-test-with-buffer "AAline1\nBBline2\nCCline3"
    (kill-new (helixel--rect-wise-text '("--" "++")))
    (goto-char 2)                    ; on second 'A' (col1)
    (helixel-yank)
    ;; forward-char to pos3(col2,'l'), rect at col2
    (should (string= (buffer-string) "AA--line1\nBB++line2\nCCline3"))))

(ert-deftest helixel-test-yank-rect-after ()
  "`p' pastes rect after cursor (was at pos 3 on 'l')."
  (helixel-test-with-buffer "AAline1\nBBline2\nCCline3"
    (kill-new (helixel--rect-wise-text '("--" "++")))
    (goto-char 3) ;; on 'l' (col2)
    (helixel-yank)
    ;; forward-char to pos4(col3,'i'), rect at col3 pushes 'i' right
    (should (string= (buffer-string) "AAl--ine1\nBBl++ine2\nCCline3"))))

;;; helixel-yank-before (P) rect tests

(ert-deftest helixel-test-yank-before-rect ()
  "Test pasting a rect kill before point."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (kill-new (helixel--rect-wise-text '("<<<" ">>>")))
    (goto-char 1)
    (helixel-yank-before)
    (should (string= (buffer-string) "<<<line1\n>>>line2\nline3"))))

(ert-deftest helixel-test-yank-rect-count ()
  "`2p' pastes rect twice at the same column."
  (helixel-test-with-buffer "AAline1\nBBline2\nCCline3"
    (kill-new (helixel--rect-wise-text '("--" "++")))
    (goto-char 1)                    ; on first 'A' (col0)
    (helixel-yank 2)
    ;; forward-char to pos2(col1), then rect twice at col1
    (should (string= (buffer-string) "A----Aline1\nB++++Bline2\nCCline3"))))

(ert-deftest helixel-test-yank-rect-sets-mark-region ()
  "After rect p, the event mark-region covers the pasted rectangle."
  (helixel-test-with-buffer "AAline1\nBBline2\nCCline3"
    (kill-new (helixel--rect-wise-text '("--" "++")))
    (goto-char 1)
    (helixel-yank)
    ;; No active region after p
    (should-not (region-active-p))
    ;; But mark-region is stored on the event (first in ring)
    (should helixel--action-ring)
    (let ((mr (helixel-action-mark-region (car helixel--action-ring))))
      (should mr)
      (should (consp mr))
      (should (marker-position (car mr)))
      (should (marker-position (cdr mr)))
      ;; Markers point to the pasted rect bounds
      (should (= (marker-position (car mr)) 2))   ; after 'A' at col1
      (should (= (marker-position (cdr mr)) 14))))) ; end of "++" on line 2

(ert-deftest helixel-test-rect-p-stays-on-row ()
  "Rect selection + p: point stays on same row, only column moves."
  (helixel-test-with-buffer "AAAA\nBBBB\nCCCC"
    (kill-new (helixel--rect-wise-text '("X")))
    ;; Create a rect selection: 3 lines, 1 column at col1
    (goto-char 2)                        ; col1 on line1
    (helixel-select-rectangle)           ; line1 col1
    (helixel-select-rectangle)           ; +line2
    (helixel-select-rectangle)           ; +line3: point on line3
    (let ((row-before (line-number-at-pos)))
      (helixel-yank)
      ;; Same row: pasted on line3, not jumped to line1
      (should (= (line-number-at-pos) row-before)))))

;;; helixel-begin-selection exits rect

(ert-deftest helixel-test-begin-selection-clears-rect ()
  "Test that `helixel-begin-selection' disables rectangle-mark-mode."
  (helixel-test-with-buffer "hello\nworld"
    (helixel-select-rectangle)
    (should rectangle-mark-mode)
    (helixel-begin-selection)
    (should-not rectangle-mark-mode)
    (should-not (helixel--sel-type))))

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
      (setq helixel--sel-type-override 'rect)
      (helixel-kill)
      (should (string= (buffer-string) " line1\n line2\nCCC line3"))
      ;; Now yank at beginning (P to paste before first char)
      (goto-char 1)
      (helixel-yank-before)
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
    (setq helixel--sel-type-override 'rect)
    (helixel-change)
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
    (setq helixel--sel-type-override 'rect)
    (helixel-change)
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
    (setq helixel--sel-type-override 'rect)
    (helixel-change)
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
    (setq helixel--sel-type-override 'rect)
    (helixel-change)
    (insert "XXX")
    (helixel-insert-exit)
    (should-not (helixel--rect-replay-get)))
)
;;; Rect after movement extension: d/y/c dispatch

(ert-deftest helixel-test-rect-j-d-uses-rect-delete ()
  "After C-v C-v d, rect is deleted via delete-rectangle (not delete-region).
Rect is extended by pressing C-v again."
  (helixel-test-with-buffer "ABC line1\nDEF line2\nGHI line3"
    (let ((kill-ring nil))
      (helixel-enter-normal-state)
      (goto-char 4)  ;; col 3 on line 1 (on space after ABC)
      (call-interactively #'helixel-select-rectangle)
      (should rectangle-mark-mode)
      (should (eq (helixel--sel-type) 'rect))
      ;; Extend rect with C-v (second press)
      (setq last-command 'helixel-select-rectangle
            this-command 'helixel-select-rectangle)
      (call-interactively #'helixel-select-rectangle)
      (should rectangle-mark-mode)
      (should (eq (helixel--sel-type) 'rect))
      ;; Kill should delete rect: first 3 cols of first 2 lines
      (helixel-kill)
      (should (helixel--rect-wise-kill-p (car kill-ring)))
      (should (string= (buffer-string) " line1\n line2\nGHI line3"))
      (should-not rectangle-mark-mode))))

(ert-deftest helixel-test-rect-j-y-uses-rect-copy ()
  "After C-v C-v y, rect is copied as rect (not char)."
  (helixel-test-with-buffer "ABC line1\nDEF line2\nGHI line3"
    (let ((kill-ring nil))
      (helixel-enter-normal-state)
      (goto-char 4)  ;; col 3 on line 1
      (call-interactively #'helixel-select-rectangle)
      ;; Extend rect with C-v (second press)
      (setq last-command 'helixel-select-rectangle
            this-command 'helixel-select-rectangle)
      (call-interactively #'helixel-select-rectangle)
      (should (eq (helixel--sel-type) 'rect))
      (helixel-kill-ring-save)
      (should (helixel--rect-wise-kill-p (car kill-ring)))
      (should (string= (buffer-string) "ABC line1\nDEF line2\nGHI line3"))
      (should-not rectangle-mark-mode))))

(ert-deftest helixel-test-rect-j-c-uses-rect-change ()
  "After C-v C-v c, rect is deleted and change replays correctly."
  (helixel-test-with-buffer "ABC line1\nDEF line2\nGHI line3"
    (helixel-enter-normal-state)
    (goto-char 4)  ;; col 3 on line 1
    (call-interactively #'helixel-select-rectangle)
    ;; Extend rect with C-v (second press)
    (setq last-command 'helixel-select-rectangle
          this-command 'helixel-select-rectangle)
    (call-interactively #'helixel-select-rectangle)
    (should (eq (helixel--sel-type) 'rect))
    (helixel-change)
    (insert "XXX")
    (helixel-insert-exit)
    (should (string= (buffer-string) "XXX line1\nXXX line2\nGHI line3"))))

(ert-deftest helixel-test-rect-j-k-extend-preserves-sel-type ()
  "After C-v, j/k do NOT clear sel-type in visual rect mode.
Basic motion commands preserve the selection type so operators
can dispatch correctly.  (General motions deactivate the mark
for line selections but preserve rect via rectangle-mark-mode.)"
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\nline5"
    (helixel-enter-normal-state)
    (call-interactively #'helixel-select-rectangle)
    (should (eq (helixel--sel-type) 'rect))
    (setq last-command 'helixel-select-rectangle)
    (call-interactively #'helixel-next-line)
    (should (eq (helixel--sel-type) 'rect))
    (setq last-command 'helixel-next-line)
    (call-interactively #'helixel-next-line)
    (should (eq (helixel--sel-type) 'rect))
    (setq last-command 'helixel-next-line)
    (call-interactively #'helixel-previous-line)
    (should (eq (helixel--sel-type) 'rect))))

(ert-deftest helixel-test-rect-w-converts-to-char ()
  "After C-v w, sel-type becomes nil (char) not rect.
Word movements in visual rect mode convert to char selection."
  (helixel-test-with-buffer "hello world\nfoo bar"
    (helixel-enter-normal-state)
    (goto-char 1)
    (call-interactively #'helixel-select-rectangle)
    (should (eq (helixel--sel-type) 'rect))
    (setq last-command 'helixel-select-rectangle)
    (call-interactively #'helixel-forward-word-start)
    (should (null (helixel--sel-type)))))

;;; helixel-test-rect.el ends here
