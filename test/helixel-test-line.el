;;; helixel-test-line.el --- Tests for Helixel: line-wise editing  -*- lexical-binding: t; -*-

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



;;; Line-wise helper tests


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

;;; helixel--region-type tests

(ert-deftest helixel-test-selection-type-nil-without-region ()
  "Test `helixel--region-type' returns nil when no region."
  (helixel-test-with-buffer "hello"
    (should-not (helixel--region-type))))

(ert-deftest helixel-test-selection-type-line-validated ()
  "Test `helixel--region-type' validates line selection bounds."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (push-mark (point) t t)
    (end-of-line)
    (helixel-test--mock-sel-type 'line)
    (should (eq (helixel--region-type) 'line))))

(ert-deftest helixel-test-selection-type-line-invalidated ()
  "Test `helixel--region-type' rejects invalid line selection."
  (helixel-test-with-buffer "first line\nsecond line"
    ;; region doesn't start at bol
    (goto-char 3)
    (push-mark (point) t t)
    (end-of-line)
    (helixel-test--mock-sel-type 'line)
    (should-not (helixel--region-type))))

;;; helixel-select-line sets selection type

(ert-deftest helixel-test-select-line-sets-type ()
  "Test `helixel-select-line' sets `helixel--sel-type' to line."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (helixel-test--mock-sel-type nil)
    (helixel-select-line)
    (should (eq (helixel--sel-type) 'line))
    (should (region-active-p))))

;;; helixel-clear-data resets selection type

(ert-deftest helixel-test-clear-data-resets-type ()
  "Test `helixel-clear-data' resets `helixel--sel-type'."
  (helixel-test-with-buffer "hello"
    (helixel-test--mock-sel-type 'line)
    (helixel-clear-data)
    (should-not (helixel--sel-type))))

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
      (helixel-test--mock-sel-type nil)
      (helixel-kill-ring-save)
      (should-not (helixel--linewise-kill-p (car kill-ring)))
      (should (string= (car kill-ring) "hello")))))

;;; helixel-kill (d) line-wise tests

(ert-deftest helixel-test-kill-thing-linewise ()
  "Test `helixel-kill' kills whole line and tags line-wise."
  (helixel-test-with-buffer "first line\nsecond line\nthird line"
    (let ((kill-ring nil))
      (helixel-select-line)
      (helixel-kill)
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
      (helixel-kill)
      (should (helixel--linewise-kill-p (car kill-ring)))
      (should (string= (buffer-string) "first line\n")))))

(ert-deftest helixel-test-kill-thing-linewise-multi-line ()
  "Test killing multiple lines selected with helixel-select-line."
  (helixel-test-with-buffer "line one\nline two\nline three"
    (let ((kill-ring nil))
      (helixel-select-line)
      (helixel-select-line) ;; extend to second line
      (helixel-kill)
      (should (helixel--linewise-kill-p (car kill-ring)))
      (should (string= (car kill-ring) "line one\nline two\n"))
      (should (string= (buffer-string) "line three")))))

(ert-deftest helixel-test-kill-thing-charwise ()
  "Test `helixel-kill' without line-wise selection."
  (helixel-test-with-buffer "hello world"
    (let ((kill-ring nil))
      (push-mark (point) t t)
      (goto-char 6)
      (helixel-test--mock-sel-type nil)
      (helixel-kill)
      (should-not (helixel--linewise-kill-p (car kill-ring)))
      (should (string= (buffer-string) " world")))))

(ert-deftest helixel-test-kill-thing-no-region ()
  "Test `helixel-kill' deletes char when no region."
  (helixel-test-with-buffer "hello"
    (helixel-kill)
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
  "Test `helixel-yank' pastes charwise content after cursor (Vim-like p)."
  (helixel-test-with-buffer "hello world"
    (kill-new "XYZ")
    (goto-char 5)                    ; on 'o' of "hello"
    (helixel-yank)
    ;; p pastes after cursor: 'o' -> ' ' -> paste
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

(ert-deftest helixel-test-yank-after-selection ()
  "`p' with an active char selection pastes after it."
  (helixel-test-with-buffer "abcdef"
    (kill-new "XYZ")
    (goto-char 2)
    (push-mark (point) t t)
    (goto-char 5)                    ; select "bcd"
    (helixel-test--mock-sel-type nil)
    (helixel-yank)
    (should (string= (buffer-string) "abcdXYZef"))))

(ert-deftest helixel-test-yank-before-selection ()
  "`P' with an active char selection pastes before it."
  (helixel-test-with-buffer "abcdef"
    (kill-new "XYZ")
    (goto-char 2)
    (push-mark (point) t t)
    (goto-char 5)                    ; select "bcd"
    (helixel-test--mock-sel-type nil)
    (helixel-yank-before)
    (should (string= (buffer-string) "aXYZbcdef"))))

;;; Count (prefix arg) tests

(ert-deftest helixel-test-yank-count-charwise ()
  "`2p' pastes charwise text twice."
  (helixel-test-with-buffer "abcdef"
    (kill-new "XY")
    (goto-char 3)                    ; on 'c'
    (helixel-yank 2)
    ;; p moves past 'c' to 'd', then pastes "XY" twice
    (should (string= (buffer-string) "abcXYXYdef"))))

(ert-deftest helixel-test-yank-count-linewise ()
  "`3p' pastes line-wise text three times."
  (helixel-test-with-buffer "line1\nline2"
    (kill-new (helixel--linewise-text "NEW\n"))
    (goto-char 3)
    (let ((this-command 'helixel-yank))
      (helixel-yank 3))
    (should (string= (buffer-string) "line1\nNEW\nNEW\nNEW\nline2"))))

(ert-deftest helixel-test-yank-before-count-charwise ()
  "`2P' pastes charwise text twice before cursor."
  (helixel-test-with-buffer "abcdef"
    (kill-new "XY")
    (goto-char 3)                    ; on 'c'
    (helixel-yank-before 2)
    ;; P pastes at point (before 'c'), twice
    (should (string= (buffer-string) "abXYXYcdef"))))

(ert-deftest helixel-test-yank-count-with-selection ()
  "`2p' with selection pastes after selection twice."
  (helixel-test-with-buffer "abcdef"
    (kill-new "XY")
    (goto-char 2)
    (push-mark (point) t t)
    (goto-char 5)                    ; select "bcd"
    (helixel-test--mock-sel-type nil)
    (helixel-yank 2)
    ;; pastes after selection (region-end), twice
    (should (string= (buffer-string) "abcdXYXYef"))))

(ert-deftest helixel-test-yank-sets-mark-region ()
  "After p, the event has a mark-region covering the pasted text."
  (helixel-test-with-buffer "abcdef"
    (kill-new "XY")
    (goto-char 3)
    (helixel-yank)
    ;; pasted "XY", cursor at start
    (should (string= (buffer-string) "abcXYdef"))
    ;; No active region after p
    (should-not (region-active-p))
    ;; Event has mark-region covering the pasted text
    (should helixel--action-ring)
    (let ((mr (helixel-action-mark-region (car helixel--action-ring))))
      (should mr)
      (should (consp mr))
      (should (markerp (car mr)))
      (should (markerp (cdr mr)))
      (should (> (marker-position (cdr mr))
                 (marker-position (car mr)))) ; non-degenerate
      (should (string= (buffer-substring (marker-position (car mr))
                                          (marker-position (cdr mr)))
                       "XY")))))

(ert-deftest helixel-test-yank-linewise-sets-mark-region ()
  "After line-wise p, the event mark-region covers the pasted line."
  (helixel-test-with-buffer "line1\nline2"
    (kill-new (helixel--linewise-text "NEW\n"))
    (goto-char 3)
    (let ((this-command 'helixel-yank))
      (helixel-yank))
    (should (string= (buffer-string) "line1\nNEW\nline2"))
    (should-not (region-active-p))
    (should helixel--action-ring)
    (let ((mr (helixel-action-mark-region (car helixel--action-ring))))
      (should mr)
      (should (consp mr))
      (should (> (marker-position (cdr mr))
                 (marker-position (car mr))))
      (should (string= (buffer-substring (marker-position (car mr))
                                          (marker-position (cdr mr)))
                       "NEW")))))

(ert-deftest helixel-test-replace-sets-mark-region ()
  "After r, the event mark-region covers the replaced text."
  (helixel-test-with-buffer "hello"
    (let ((helixel-replace-delete-char-p t))
      (kill-new "XY")
      (helixel-replace)
      ;; 'h' deleted, "XY" inserted → "XYello"
      (should (string= (buffer-string) "XYello"))
      (should-not (region-active-p))
      (should helixel--action-ring)
      (let ((mr (helixel-action-mark-region (car helixel--action-ring))))
        (should mr)
        (should (consp mr))
        (should (> (marker-position (cdr mr))
                   (marker-position (car mr))))
        (should (string= (buffer-substring (marker-position (car mr))
                                            (marker-position (cdr mr)))
                         "XY"))))))

(ert-deftest helixel-test-yank-pop-sets-mark-region ()
  "After M-y (yank-pop), the event mark-region covers the cycled text."
  (helixel-test-with-buffer "hello"
    (let* ((kill-ring (list "X" "Y"))
           (kill-ring-yank-pointer kill-ring)
           (helixel-replace-delete-char-p t))
      (setq last-command nil)
      (helixel-replace)
      (should (string= (buffer-string) "Xello"))
      (setq last-command 'helixel-replace)
      (deactivate-mark)
      (helixel-yank-pop)
      (should (string= (buffer-string) "Yello"))
      (should-not (region-active-p))
      (should helixel--action-ring)
      (let ((mr (helixel-action-mark-region (car helixel--action-ring))))
        (should mr)
        (should (consp mr))
        (should (> (marker-position (cdr mr))
                   (marker-position (car mr))))
        (should (string= (buffer-substring (marker-position (car mr))
                                            (marker-position (cdr mr)))
                         "Y"))))))

(ert-deftest helixel-test-yank-after-linewise-selection ()
  "`p' with line selection pastes line-wise text after the line."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (kill-new (helixel--linewise-text "PASTED\n"))
    (goto-char 7)
    (helixel-select-line)             ; select "line2"
    (let ((this-command 'helixel-yank))
      (helixel-yank))
    (should (string= (buffer-string) "line1\nline2\nPASTED\nline3"))))

(ert-deftest helixel-test-yank-before-linewise-selection ()
  "`P' with line selection pastes line-wise text before the line."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (kill-new (helixel--linewise-text "PASTED\n"))
    (goto-char 7)
    (helixel-select-line)             ; select "line2"
    (let ((this-command 'helixel-yank-before))
      (helixel-yank-before))
    (should (string= (buffer-string) "line1\nPASTED\nline2\nline3"))))

(ert-deftest helixel-test-yank-handler-property-not-leaked ()
  "Past line-wise text, then copy buffer text with `y'.
The `yank-handler' property from the line-wise kill must NOT leak
into the buffer — otherwise a subsequent `y' (copy) on the pasted
text would capture the stale property and cause the next `p' to
paste line-wise instead of char-wise."
  (helixel-test-with-buffer "line one\nline two"
    (progn
    ;; 1. Create a line-wise kill and paste it (simulates x y p)
    (helixel-select-line)
    (helixel-kill-ring-save)
    (helixel-yank)
    ;; 2. Verify buffer text has NO yank-handler property
    (goto-char (point-min))
    (forward-line 1)                    ; move to pasted line
    (should-not (get-text-property (point) 'yank-handler))
    ;; 3. Select first word of the pasted line and copy
    (helixel-mark-inner-symbol)
    (helixel-kill-ring-save)
    ;; 4. Kill-ring top must be char-wise (no yank-handler)
    (should-not (helixel--linewise-kill-p))
    ;; 5. Paste at point — must paste inline, not on next line
    (goto-char 1)
    (helixel-yank-before)
    (should (string-prefix-p "lineline one" (buffer-string))))))

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
    (helixel-test--mock-sel-type nil)
    (helixel-replace)
    ;; Line-wise kill should be stripped of trailing newline for inline replace
    (should (string= (buffer-string) "REPLACED world"))))

(ert-deftest helixel-test-replace-yanked-no-region ()
  "Test replacing char at point with kill ring content."
  (helixel-test-with-buffer "hello"
    (let ((helixel-replace-delete-char-p t))
      (kill-new "X")
      (helixel-test--mock-sel-type nil)
      (helixel-replace)
      (should (string= (buffer-string) "Xello"))))

  (helixel-test-with-buffer "hello"
    (let ((helixel-replace-delete-char-p nil))
      (kill-new "X")
      (helixel-test--mock-sel-type nil)
      (helixel-replace)
      (should (string= (buffer-string) "Xhello")))))

(ert-deftest helixel-test-replace-yanked-empty-kill-ring ()
  "Test replace with empty kill ring shows message."
  (helixel-test-with-buffer "hello"
    (let ((kill-ring nil))
      (helixel-replace)
      ;; Buffer unchanged
      (should (string= (buffer-string) "hello")))))

;;; helixel-yank-pop tests

(ert-deftest helixel-test-yank-pop-no-region ()
  "Test yank-pop cycles kill ring after no-region replace."
  (helixel-test-with-buffer "hello world"
    (let* ((kill-ring (list "BBB" "AAA"))
           (kill-ring-yank-pointer kill-ring)
           (helixel-replace-delete-char-p t))
      (setq last-command nil)
      (helixel-replace)
      (should (string= (buffer-string) "BBBello world"))
      (setq last-command 'helixel-replace)
      (helixel-yank-pop)
      (should (string= (buffer-string) "AAAello world"))
      (helixel-yank-pop)
      (should (string= (buffer-string) "BBBello world")))))

(ert-deftest helixel-test-yank-pop-no-delete-char ()
  "Test yank-pop with `helixel-replace-delete-char-p' nil."
  (helixel-test-with-buffer "hello"
    (let* ((kill-ring (list "BBB" "AAA"))
           (kill-ring-yank-pointer kill-ring)
           (helixel-replace-delete-char-p nil))
      (setq last-command nil)
      (helixel-replace)
      (should (string= (buffer-string) "BBBhello"))
      (setq last-command 'helixel-replace)
      (helixel-yank-pop)
      (should (string= (buffer-string) "AAAhello")))))

(ert-deftest helixel-test-yank-pop-charwise-region ()
  "Test yank-pop after charwise region replace."
  (helixel-test-with-buffer "hello brave world"
    (let* ((kill-ring (list "cruel" "nice"))
           (kill-ring-yank-pointer kill-ring))
      ;; Select "brave"
      (push-mark 7 t t)
      (goto-char 12)
      (helixel-test--mock-sel-type nil)
      (setq last-command nil)
      (helixel-replace)
      (should (string= (buffer-string) "hello cruel world"))
      (setq last-command 'helixel-replace)
      (helixel-yank-pop)
      (should (string= (buffer-string) "hello nice world")))))

(ert-deftest helixel-test-yank-pop-linewise-selection ()
  "Test yank-pop after line-wise selection replace."
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
      (helixel-yank-pop)
      (should (string= (buffer-string) "first line\nBBB\nthird line")))))

(ert-deftest helixel-test-yank-pop-wrong-last-command ()
  "Test yank-pop browses kill-ring when previous command was not a replace."
  (helixel-test-with-buffer "hello"
    (let* ((kill-ring (list "BBB" "AAA"))
           (kill-ring-yank-pointer kill-ring)
           (helixel-replace-delete-char-p t))
      (setq last-command 'self-insert-command)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt collection &rest _)
                   (car (all-completions "" collection)))))
        (helixel-yank-pop)
        (should (string= (buffer-string) "BBBello"))
        ;; Subsequent calls should cycle
        (setq last-command 'helixel-yank-pop)
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (_prompt _collection &rest _)
                     (error "should not be called"))))
          (helixel-yank-pop)
          (should (string= (buffer-string) "AAAello")))))))

(ert-deftest helixel-test-yank-pop-no-bounds ()
  "Test yank-pop errors with no yank-pop-bounds (rect case)."
  (helixel-test-with-buffer "hello"
    (let* ((kill-ring (list "AAA"))
           (kill-ring-yank-pointer kill-ring)
           (helixel--yank-pop-bounds nil))
      (setq last-command 'helixel-replace)
      ;; `yank-pop' behavior differs across Emacs versions:
      ;; Emacs <30 signals user-error when last-command is not
      ;; `yank'; Emacs 30+ prompts via `yank-from-kill-ring'.
      ;; Mock it so the test is version-independent.
      (cl-letf (((symbol-function 'yank-pop)
                 (lambda (&optional _)
                   (user-error "Previous command was not a yank"))))
        (should-error (helixel-yank-pop))))))

(ert-deftest helixel-test-yank-pop-with-arg ()
  "Test yank-pop with numeric argument skips kills."
  (helixel-test-with-buffer "hello"
    (let* ((kill-ring (list "CCC" "BBB" "AAA"))
           (kill-ring-yank-pointer kill-ring)
           (helixel-replace-delete-char-p t))
      (setq last-command nil)
      (helixel-replace)
      (should (string= (buffer-string) "CCCello"))
      (setq last-command 'helixel-replace)
      ;; Pop with arg 1 advances one kill forward (CCC→BBB)
      (helixel-yank-pop 1)
      (should (string= (buffer-string) "BBBello")))))

;;; yank-pop cycling: C-y / p / r followed by M-y M-y

(ert-deftest helixel-test-yank-pop-after-cy-mark ()
  "After C-y, M-y cycles using mark bounds (region may be inactive)."
  (helixel-test-with-buffer "hello"
    (let* ((kill-ring (list "X" "Y" "Z"))
           (kill-ring-yank-pointer kill-ring))
      ;; C-y: Emacs yank pastes "X"
      (setq last-command 'yank)
      (push-mark (point) t t)  ; simulate C-y mark activation
      (insert "X")
      ;; M-y → "Y"
      (setq last-command 'yank)
      (helixel-yank-pop)
      (should (string= (buffer-string) "Yhello"))
      ;; M-y → "Z"
      (setq last-command 'helixel-yank-pop)
      (helixel-yank-pop)
      (should (string= (buffer-string) "Zhello")))))

(ert-deftest helixel-test-yank-pop-after-real-yank ()
  "After real Emacs `yank' (C-y), M-y M-y cycles through kill ring.
Emacs 32 no longer activates mark in yank, so the test covers the
mark-position-based bounds detection (not use-region-p)."
  (helixel-test-with-buffer "hello world"
    (let* ((kill-ring (list "AAA" "BBB" "CCC"))
           (kill-ring-yank-pointer kill-ring))
      (goto-char 6)                    ; before "world"
      ;; Real Emacs C-y
      (setq last-command nil)
      (yank)
      (should (string= (buffer-string) "helloAAA world"))
      ;; M-y → "BBB"
      (setq last-command 'yank)
      (helixel-yank-pop)
      (should (string= (buffer-string) "helloBBB world"))
      ;; M-y → "CCC"
      (setq last-command 'helixel-yank-pop)
      (helixel-yank-pop)
      (should (string= (buffer-string) "helloCCC world"))
      ;; pop-bounds should be set for further cycling
      (should helixel--yank-pop-bounds))))

(ert-deftest helixel-test-yank-pop-after-p ()
  "After p, M-y M-y cycles through kill ring."
  (helixel-test-with-buffer "abcdef"
    (let* ((kill-ring (list "X" "Y" "Z"))
           (kill-ring-yank-pointer kill-ring))
      ;; p pastes "X"
      (goto-char 3)
      (setq last-command 'helixel-yank)
      (helixel-yank)
      (should (string= (buffer-string) "abcXdef"))
      ;; M-y → "Y"
      (setq last-command 'helixel-yank)
      (helixel-yank-pop)
      (should (string= (buffer-string) "abcYdef"))
      ;; M-y → "Z"
      (setq last-command 'helixel-yank-pop)
      (helixel-yank-pop)
      (should (string= (buffer-string) "abcZdef")))))

(ert-deftest helixel-test-yank-pop-after-r ()
  "After r, M-y M-y cycles through kill ring."
  (helixel-test-with-buffer "hello"
    (let* ((kill-ring (list "X" "Y" "Z"))
           (kill-ring-yank-pointer kill-ring)
           (helixel-replace-delete-char-p t))
      ;; r replaces 'h' with "X"
      (setq last-command nil)
      (helixel-replace)
      (should (string= (buffer-string) "Xello"))
      ;; M-y → "Y"
      (setq last-command 'helixel-replace)
      (helixel-yank-pop)
      (should (string= (buffer-string) "Yello"))
      ;; M-y → "Z"
      (setq last-command 'helixel-yank-pop)
      (helixel-yank-pop)
      (should (string= (buffer-string) "Zello")))))

(ert-deftest helixel-test-yank-pop-no-stale-bounds ()
  "M-y after p uses p's position, not stale bounds from previous r."
  (helixel-test-with-buffer "hello world"
    (deactivate-mark)
    (let* ((kill-ring (list "R" "S" "T"))
           (kill-ring-yank-pointer kill-ring)
           (helixel-replace-delete-char-p t))
      ;; r replaces 'h' with "R", sets yank-pop-bounds
      (setq last-command nil)
      (helixel-replace)
      (should helixel--yank-pop-bounds)
      (should (eq (car helixel--yank-pop-bounds) 1))
      ;; p at position 7 should use its own bounds, not stale ones from r
      (goto-char 7)
      (setq last-command 'helixel-yank)
      (helixel-yank)
      ;; After p, bounds are from p (position 8 after forward-char), not r (position 1)
      (should helixel--yank-pop-bounds)
      (should (eq (car helixel--yank-pop-bounds) 8)))))

;;; Integration: select-line -> kill -> yank round-trip

(ert-deftest helixel-test-linewise-round-trip ()
  "Test full round-trip: select line, kill, then yank elsewhere."
  (helixel-test-with-buffer "line A\nline B\nline C"
    (let ((kill-ring nil))
      ;; Select and kill line B
      (goto-char 8)
      (helixel-select-line)
      (helixel-kill)
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
      (helixel-test--mock-sel-type nil)
      (helixel-kill)
      (should (string= (car kill-ring) "hello"))
      (should-not (helixel--linewise-kill-p (car kill-ring)))
      (goto-char 1)
      (helixel-yank-before)
      (should (string= (buffer-string) "hello world")))))

;;; helixel-begin-selection clears line type

(ert-deftest helixel-test-begin-selection-preserves-line-type ()
  "`helixel-begin-selection' with `preserve-selection' keeps line type."
  (helixel-test-with-buffer "hello"
    (helixel-test--mock-sel-type 'line)
    (helixel-begin-selection)
    (should (eq (helixel--sel-type) 'line))))

;;; Direction flip / shrink tests

(ert-deftest helixel-test-line-select-enters-visual ()
  "`x' creates a line selection without entering visual state.
Line/rect selections stay in normal state; operators (d/y/c) read
pending-sel kind, not visual state."
  (helixel-test-with-buffer "aaa\nbbb\nccc\n"
    (helixel-enter-normal-state)
    (helixel-select-line)
    (should (eq helixel--current-state 'normal))
    (should (eq (helixel--sel-type) 'line))
    (should (use-region-p))))

(ert-deftest helixel-test-line-select-up-enters-visual ()
  "`X' creates a line selection without entering visual state.
Line/rect selections stay in normal state (operators d/y/c read
pending-sel kind, not visual state)."
  (helixel-test-with-buffer "aaa\nbbb\nccc\n"
    (helixel-enter-normal-state)
    (goto-char 5)
    (helixel-select-line-up)
    (should (eq helixel--current-state 'normal))
    (should (eq (helixel--sel-type) 'line))
    (should (use-region-p))))

(ert-deftest helixel-test-line-v-preserves-selection ()
  "`v' after `x' preserves the existing line selection.
Entering visual from normal with an active region keeps the
region and enables extending (Helix-like)."
  (helixel-test-with-buffer "line one\nline two\n"
    (helixel-enter-normal-state)
    ;; x selects the first line in normal state.
    (helixel-select-line)
    (should (eq helixel--current-state 'normal))
    (should (use-region-p))
    (let ((beg (region-beginning))
          (end (region-end)))
      ;; v enters visual but preserves the region.
      (helixel-begin-selection)
      (should (eq helixel--current-state 'visual))
      (should (use-region-p))
      (should (= beg (region-beginning)))
      (should (= end (region-end)))
      ;; Movements now extend (visual state).
      (helixel-forward-word-start)
      (should (> (region-end) end)))))

(ert-deftest helixel-test-line-dir-stored-in-ctx ()
  "`:dir' is stored in pending-sel ctx for line selections."
  (helixel-test-with-buffer "aaa\nbbb\nccc\n"
    (helixel-enter-normal-state)
    (helixel-select-line)
    (should (eq 'forward
                (helixel-sel-line-dir helixel--pending-sel)))
    (helixel-enter-normal-state)
    (helixel-clear-data)
    (goto-char 5)
    (helixel-select-line-up)
    (should (eq 'backward
                (helixel-sel-line-dir helixel--pending-sel)))))

(ert-deftest helixel-test-line-neg-prefix-flips-dir ()
  "`-x' flips `:dir' permanently like `N' for search."
  (helixel-test-with-buffer "aaa\nbbb\nccc\nddd\n"
    (helixel-enter-normal-state)
    (helixel-select-line 2)          ; 2 lines, forward
    (should (eq 'forward
                (helixel-sel-line-dir helixel--pending-sel)))
    (should (= 2 (helixel-sel-count helixel--pending-sel)))
    ;; -x: flip backward + shrink 1
    (setq current-prefix-arg nil)
    (call-interactively (lambda () (interactive) (helixel-select-line -1)))
    (should (eq 'backward
                (helixel-sel-line-dir helixel--pending-sel)))
    (should (= 1 (helixel-sel-count helixel--pending-sel)))))

(ert-deftest helixel-test-line-neg-flips-then-extend ()
  "`-x' flips dir and extends in new direction; second `-x' flips back."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\n"
    (helixel-enter-normal-state)
    (helixel-select-line 3)          ; 3 lines, forward
    ;; -x: flip backward, shrink 1 → 2 lines
    (setq current-prefix-arg nil)
    (call-interactively (lambda () (interactive) (helixel-select-line -1)))
    (should (= 2 (helixel-sel-count helixel--pending-sel)))
    (should (eq 'backward
                (helixel-sel-line-dir helixel--pending-sel)))
    ;; -x again: flip forward, extend 1 → 3 lines
    (call-interactively (lambda () (interactive) (helixel-select-line -1)))
    (should (= 3 (helixel-sel-count helixel--pending-sel)))
    (should (eq 'forward
                (helixel-sel-line-dir helixel--pending-sel)))))

(ert-deftest helixel-test-line-shrink-boundary ()
  "At 1-line boundary, plain `x' crosses over; next `x' extends from top."
  (helixel-test-with-buffer "aaa\nbbb\nccc\nddd\n"
    (helixel-enter-normal-state)
    (goto-char 5)                    ; bol of line 2
    (helixel-select-line 2)          ; 2 lines forward (lines 2-3)
    ;; -x: flip backward, shrink → 1 line (line 2)
    (setq current-prefix-arg nil)
    (call-interactively (lambda () (interactive) (helixel-select-line -1)))
    (should (eq 'backward
                (helixel-sel-line-dir helixel--pending-sel)))
    (should (= 1 (helixel-sel-count helixel--pending-sel)))
    ;; x at boundary: cross over, still 1 line (point moves to eol)
    (helixel-select-line 1)
    (should (= 1 (helixel-sel-count helixel--pending-sel)))
    ;; x again: now extend from top → 2 lines
    (helixel-select-line 1)
    (should (= 2 (helixel-sel-count helixel--pending-sel)))
    ;; x again: extend from top but at buffer top → no-op → 2 lines
    (helixel-select-line 1)
    (should (= 2 (helixel-sel-count helixel--pending-sel)))))

(ert-deftest helixel-test-line-extend-after-flip ()
  "After flip, `x' extends in current direction (shrink if backward)."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\n"
    (helixel-enter-normal-state)
    (helixel-select-line 3)          ; 3 lines, forward
    ;; -x: flip backward, shrink from bottom → 2 lines
    (setq current-prefix-arg nil)
    (call-interactively (lambda () (interactive) (helixel-select-line -1)))
    (should (eq 'backward
                (helixel-sel-line-dir helixel--pending-sel)))
    (should (= 2 (helixel-sel-count helixel--pending-sel)))
    ;; x: backward+eolp → continue shrink → 1 line
    (helixel-select-line 1)
    (should (= 1 (helixel-sel-count helixel--pending-sel)))))

(ert-deftest helixel-test-line-up-neg-shrink-from-top ()
  "`-X' shrinks selection from top."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\n"
    (helixel-enter-normal-state)
    (goto-char (point-max))
    (forward-line -1)                ; on line4
    (helixel-select-line-up 3)       ; select 3 lines up (line2..line4)
    (should (eq 'backward
                (helixel-sel-line-dir helixel--pending-sel)))
    (should (= 3 (helixel-sel-count helixel--pending-sel)))
    ;; -X: flip forward + shrink from top → 2 lines
    (setq current-prefix-arg nil)
    (call-interactively (lambda () (interactive) (helixel-select-line-up -1)))
    (should (eq 'forward
                (helixel-sel-line-dir helixel--pending-sel)))
    (should (= 2 (helixel-sel-count helixel--pending-sel)))))

(ert-deftest helixel-test-line-movement-does-not-extend ()
  "Movement keys (h/l/j/k) do NOT extend a line selection in visual state."
  (helixel-test-with-buffer "line1\nline2\nline3\n"
    (helixel-enter-normal-state)
    (helixel-select-line)
    (let ((region-beg (region-beginning))
          (region-end (region-end)))
      ;; Moving char should deactivate mark, not extend line selection.
      (helixel-forward-char)
      (should-not (use-region-p))
      ;; Region should be gone — movement moved point without extending.
      (should (not (= region-end (region-end)))))))

(ert-deftest helixel-test-line-o-flips-dir ()
  "`o' swaps point/mark AND flips :dir for line selections."
  (helixel-test-with-buffer "aaa\nbbb\nccc\n"
    (helixel-enter-normal-state)
    (helixel-select-line 2)
    (should (eq 'forward (helixel-sel-line-dir helixel--pending-sel)))
    (let ((pt (point)) (mk (mark)))
      (helixel-visual-exchange-point-and-mark)
      (should (= pt (mark)))          ; point → mark
      (should (= mk (point)))         ; mark → point
      (should (eq 'backward
                  (helixel-sel-line-dir helixel--pending-sel))))
    ;; o again flips back
    (helixel-visual-exchange-point-and-mark)
    (should (eq 'forward
                (helixel-sel-line-dir helixel--pending-sel)))))

(ert-deftest helixel-test-line-o-rect-no-flip ()
  "`o' for rect selection does NOT touch :dir (nonexistent)."
  (helixel-test-with-buffer "aaa\nbbb\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-begin-selection)
    (helixel-select-rectangle)
    (should rectangle-mark-mode)
    (let ((pt (point)) (mk (mark)))
      (helixel-visual-exchange-point-and-mark)
      (should (= pt (mark)))
      (should (= mk (point)))
      ;; rect has no :dir — just verify no error
      (should-not (eq (helixel--sel-type) 'line)))))

(ert-deftest helixel-test-line-auto-reverse-at-boundary ()
  "At boundary, plain `x' crosses over; `-x' just shrinks (no switch)."
  (helixel-test-with-buffer "aaa\nbbb\nccc\nddd\n"
    (helixel-enter-normal-state)
    (goto-char 5)                    ; bol of line 2
    (helixel-select-line 2)          ; 2 lines forward
    ;; -x: flip backward, shrink → 1 line, no boundary switch
    (setq current-prefix-arg nil)
    (call-interactively (lambda () (interactive) (helixel-select-line -1)))
    (should (eq 'backward
                (helixel-sel-line-dir helixel--pending-sel)))
    (should (= 1 (helixel-sel-count helixel--pending-sel)))
    ;; x at boundary: cross over, still 1 line
    (helixel-select-line 1)
    (should (= 1 (helixel-sel-count helixel--pending-sel)))
    ;; x again: extend from top → 2 lines
    (helixel-select-line 1)
    (should (= 2 (helixel-sel-count helixel--pending-sel)))))

(ert-deftest helixel-test-line-up-auto-reverse-at-top ()
  "At top boundary, `X' crosses over; `-X' just shrinks."
  (helixel-test-with-buffer "aaa\nbbb\nccc\nddd\n"
    (helixel-enter-normal-state)
    (goto-char 6)                    ; eol of line 2
    (helixel-select-line-up 2)       ; 2 lines backward (lines 1-2)
    ;; -X: flip forward, shrink → 1 line, no switch
    (setq current-prefix-arg nil)
    (call-interactively (lambda () (interactive) (helixel-select-line-up -1)))
    (should (eq 'forward
                (helixel-sel-line-dir helixel--pending-sel)))
    (should (= 1 (helixel-sel-count helixel--pending-sel)))
    ;; X at boundary: cross over, still 1 line
    (helixel-select-line-up 1)
    (should (= 1 (helixel-sel-count helixel--pending-sel)))
    ;; X again: extend → 2
    (helixel-select-line-up 1)
    (should (= 2 (helixel-sel-count helixel--pending-sel)))
    ;; X again: continue → 3
    (helixel-select-line-up 1)
    (should (= 3 (helixel-sel-count helixel--pending-sel)))))

(ert-deftest helixel-test-line-shrink-then-cross-over ()
  "Full scenario: -x flips dir, x shrinks, cross-over at 1 line, then extend.
Start with backward selection (point<mark, point at bol).
-x: flip dir to forward, shrink from top, point stays at bol.
x x: continue shrinking until 1 line.
x: cross over (exchange), point moves to eol.
x x x: continue extending forward."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\nline5\n"
    (helixel-enter-normal-state)
    ;; Create 3-line backward selection (lines 2-4).
    ;; Point at bol of line 2, mark at eol of line 4.
    (goto-char (point-min))
    (forward-line 3)                ; go to line 4
    (end-of-line)
    (helixel-select-line-up 3)
    (should (eq 'backward
                (helixel-sel-line-dir helixel--pending-sel)))
    (should (= 3 (helixel-sel-count helixel--pending-sel)))
    ;; -x: flip dir to forward, shrink from top → 2 lines (lines 2-3).
    (setq current-prefix-arg nil)
    (call-interactively (lambda () (interactive) (helixel-select-line -1)))
    (should (eq 'forward
                (helixel-sel-line-dir helixel--pending-sel)))
    (should (= 2 (helixel-sel-count helixel--pending-sel)))
    ;; x: continue shrink → 1 line (line 3).
    (helixel-select-line 1)
    (should (= 1 (helixel-sel-count helixel--pending-sel)))
    ;; x: at boundary, cross over → still 1 line, point>mark.
    (helixel-select-line 1)
    (should (= 1 (helixel-sel-count helixel--pending-sel)))
    ;; x: extend forward → 2 lines (lines 3-4).
    (helixel-select-line 1)
    (should (= 2 (helixel-sel-count helixel--pending-sel)))
    ;; x: continue extend → 3 lines (lines 3-5).
    (helixel-select-line 1)
    (should (= 3 (helixel-sel-count helixel--pending-sel)))
    ;; x: continue extend → 3 lines (lines 3-5).
    (helixel-select-line 1)
    (should (= 3 (helixel-sel-count helixel--pending-sel)))
    ;; x: at buffer end, forward-line no-op → still 3 lines.
    (helixel-select-line 1)
    (should (= 3 (helixel-sel-count helixel--pending-sel)))))

(ert-deftest helixel-test-line-fresh-extend-no-cross-over ()
  "Fresh 1-line selection extends directly, no spurious cross-over.
-x on a fresh selection with no existing line sel is a no-op
(since there is no pending-sel to flip)."
  (helixel-test-with-buffer "aaa\nbbb\nccc\n"
    (helixel-enter-normal-state)
    ;; x: fresh forward 1-line selection.
    (helixel-select-line)
    (should (= 1 (helixel-sel-count helixel--pending-sel)))
    (should (eq 'forward
                (helixel-sel-line-dir helixel--pending-sel)))
    ;; x: extend to 2 lines (not cross-over).
    (helixel-select-line 1)
    (should (= 2 (helixel-sel-count helixel--pending-sel)))
    ;; x: extend to 3 lines.
    (helixel-select-line 1)
    (should (= 3 (helixel-sel-count helixel--pending-sel)))))

(ert-deftest helixel-test-line-fresh-X-extend-no-cross-over ()
  "Fresh 1-line backward selection (X) extends directly, no cross-over."
  (helixel-test-with-buffer "aaa\nbbb\nccc\n"
    (helixel-enter-normal-state)
    (goto-char (point-max))
    ;; X: fresh backward 1-line selection.
    (helixel-select-line-up)
    (should (= 1 (helixel-sel-count helixel--pending-sel)))
    (should (eq 'backward
                (helixel-sel-line-dir helixel--pending-sel)))
    ;; X: extend to 2 lines (not cross-over).
    (helixel-select-line-up 1)
    (should (= 2 (helixel-sel-count helixel--pending-sel)))
    ;; X: extend to 3 lines.
    (helixel-select-line-up 1)
    (should (= 3 (helixel-sel-count helixel--pending-sel)))))

;;; line selection with invisible text

(ert-deftest helixel-test-line-visible-only-nil ()
  "x selects only visible line when helixel-invisible is nil."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\nline5"
    (setq-local helixel-invisible nil)
    (let ((start (save-excursion (forward-line 1) (point)))
          (end (save-excursion (forward-line 3) (point))))
      (put-text-property start end (quote invisible) (quote outline)))
    (goto-char 1)
    (helixel-select-line)
    (should (= (region-beginning) 1))
    (should (= (region-end) 6))
    (should (eq (helixel--sel-type) 'line))))

(ert-deftest helixel-test-line-expand-t ()
  "x expands through invisible text-property when helixel-invisible is t."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\nline5"
    (setq-local helixel-invisible t)
    (let ((start (save-excursion (forward-line 1) (point)))
          (end (save-excursion (forward-line 3) (point))))
      (put-text-property start end (quote invisible) (quote outline)))
    (goto-char 1)
    (helixel-select-line)
    (should (= (region-beginning) 1))
    (should (= (region-end) 18))
    (should (eq (helixel--sel-type) 'line))))

(ert-deftest helixel-test-line-toggle ()
  "helixel-toggle-invisible cycles \='auto → nil → t → \='open → \='auto."
  (with-temp-buffer
    (setq-local helixel-invisible 'auto)
    (helixel-toggle-invisible)
    (should-not helixel-invisible)   ; auto → nil
    (helixel-toggle-invisible)
    (should (eq helixel-invisible t)) ; nil → t
    (helixel-toggle-invisible)
    (should (eq helixel-invisible 'open)) ; t → open
    (helixel-toggle-invisible)
    (should (eq helixel-invisible 'auto)) ; open → auto
    ;; Full cycle back to nil.
    (helixel-toggle-invisible)
    (should-not helixel-invisible)))


;;; helixel--line-end-or-invisible unit tests

(ert-deftest helixel-test-line-end-or-invisible-no-invis ()
  "line-end-or-invisible at EOL with visible next line stays at EOL."
  (helixel-test-with-buffer "line1\nline2\n"
    (setq-local helixel-invisible t)
    (goto-char 1)
    (helixel--line-end-or-invisible)
    (should (= (point) 6))  ; EOL of line1
    (should (eolp))))

(ert-deftest helixel-test-line-end-or-invisible-next-line-fully-invis ()
  "line-end-or-invisible expands through next line when it is entirely invisible."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\n"
    (setq-local helixel-invisible t)
    ;; Make lines 2-3 entirely invisible (including newlines).
    (let ((start (save-excursion (forward-line 1) (point)))
          (end (save-excursion (forward-line 3) (point))))
      (put-text-property start end 'invisible 'outline))
    (goto-char 1)
    (helixel--line-end-or-invisible)
    ;; Should expand through lines 2-3 and stop at EOL of line 3.
    (should (= (point) 18))
    (should (eolp))))

(ert-deftest helixel-test-line-end-or-invisible-next-line-prefix-only ()
  "line-end-or-invisible stops when next line has invisible prefix only.
Simulates vc-annotate: each line has an invisible annotation prefix
followed by visible code.  Must NOT expand into the next line."
  (helixel-test-with-buffer
      "AAAAAline1\nBBBBBline2\nCCCCCline3\n"
    (setq-local helixel-invisible t)
    ;; Invisible prefixes on each line (positions 1-5, 12-16, 23-27).
    (put-text-property 1 6 'invisible 'outline)
    (put-text-property 12 17 'invisible 'outline)
    (put-text-property 23 28 'invisible 'outline)
    (goto-char 1)
    (helixel--line-end-or-invisible)
    ;; Must stay at EOL of line 1, not expand into line 2.
    (should (= (point) 11))
    (should (eolp))))

(ert-deftest helixel-test-line-end-or-invisible-mid-line-invis ()
  "line-end-or-invisible when mid-line (not eolp) always expands.
Invisible text on the same line after point should be traversed."
  (helixel-test-with-buffer "visibleXXXXX\n"
    (setq-local helixel-invisible t)
    ;; Make "XXXXX" (positions 8-12) invisible.
    (put-text-property 8 13 'invisible 'outline)
    (goto-char 1)
    ;; Simulate mid-line: point after "visible" but before "XXXXX".
    (goto-char 8)
    (helixel--line-end-or-invisible)
    (should (= (point) 13))  ; newline after XXXXX
    (should (eolp))))

(ert-deftest helixel-test-line-end-or-invisible-invis-nil ()
  "line-end-or-invisible with helixel-invisible nil just calls end-of-line."
  (helixel-test-with-buffer "line1\nline2\n"
    ;; Make next line fully invisible.
    (let ((start (save-excursion (forward-line 1) (point)))
          (end (save-excursion (forward-line 2) (point))))
      (put-text-property start end 'invisible 'outline))
    ;; BUT helixel-invisible is nil → no expansion.
    (setq-local helixel-invisible nil)
    (goto-char 1)
    (helixel--line-end-or-invisible)
    (should (= (point) 6))  ; EOL of line1 only
    (should (eolp))))

(ert-deftest helixel-test-line-end-or-invisible-invis-auto ()
  "line-end-or-invisible with helixel-invisible=auto follows search-invisible."
  (helixel-test-with-buffer "line1\nline2\n"
    (setq-local helixel-invisible 'auto)
    ;; When search-invisible is nil, no expansion.
    (let ((search-invisible nil))
      (let ((start (save-excursion (forward-line 1) (point)))
            (end (save-excursion (forward-line 2) (point))))
        (put-text-property start end 'invisible 'outline))
      (goto-char 1)
      (helixel--line-end-or-invisible)
      (should (= (point) 6))  ; no expansion
      (should (eolp)))
    ;; When search-invisible is t, expansion happens.
    (let ((search-invisible t))
      (goto-char 1)
      (helixel--line-end-or-invisible)
      (should (= (point) 12))  ; expanded through invisible line2
      (should (eolp)))))


;;; helixel-select-line with invisible prefixes (vc-annotate style)

(ert-deftest helixel-test-line-select-prefix-no-expand ()
  "x selects one line when invisible text is a per-line prefix.
Simulates vc-annotate buffers where each line starts with invisible
annotation text followed by visible source code.  x must not expand
through subsequent invisible prefixes."
  (helixel-test-with-buffer
      "AAAAAline1\nBBBBBline2\nCCCCCline3\n"
    (setq-local helixel-invisible t)
    (put-text-property 1 6 'invisible 'outline)
    (put-text-property 12 17 'invisible 'outline)
    (put-text-property 23 28 'invisible 'outline)
    (goto-char 1)
    (helixel-select-line)
    (should (= (region-beginning) 1))
    (should (= (region-end) 11))
    (should (eq (helixel--sel-type) 'line))))

(ert-deftest helixel-test-line-select-prefix-extend ()
  "xx extends by one line when lines have invisible prefixes."
  (helixel-test-with-buffer
      "AAAAAline1\nBBBBBline2\nCCCCCline3\nDDDDDline4\n"
    (setq-local helixel-invisible t)
    (put-text-property 1 6 'invisible 'outline)
    (put-text-property 12 17 'invisible 'outline)
    (put-text-property 23 28 'invisible 'outline)
    (put-text-property 34 39 'invisible 'outline)
    (goto-char 1)
    (helixel-select-line)   ; x     → line 1
    (helixel-select-line)   ; x     → lines 1-2
    (should (= (region-beginning) 1))
    (should (= (region-end) 22))
    (helixel-select-line)   ; x     → lines 1-3
    (should (= (region-beginning) 1))
    (should (= (region-end) 33))
    (should (eq (helixel--sel-type) 'line))))

(ert-deftest helixel-test-line-select-prefix-count-3 ()
  "3x selects three lines with invisible prefixes."
  (helixel-test-with-buffer
      "AAAAAline1\nBBBBBline2\nCCCCCline3\nDDDDDline4\n"
    (setq-local helixel-invisible t)
    (put-text-property 1 6 'invisible 'outline)
    (put-text-property 12 17 'invisible 'outline)
    (put-text-property 23 28 'invisible 'outline)
    (put-text-property 34 39 'invisible 'outline)
    (goto-char 1)
    (helixel-select-line 3)
    (should (= (region-beginning) 1))
    (should (= (region-end) 33))
    (should (eq (helixel--sel-type) 'line))))

(ert-deftest helixel-test-line-select-prefix-standalone ()
  "x on a middle line selects only that line with invisible prefix.
Start on line 2, not line 1 — avoids any BOB edge-cases."
  (helixel-test-with-buffer
      "AAAAAline1\nBBBBBline2\nCCCCCline3\n"
    (setq-local helixel-invisible t)
    (put-text-property 1 6 'invisible 'outline)
    (put-text-property 12 17 'invisible 'outline)
    (put-text-property 23 28 'invisible 'outline)
    (goto-char 12)
    (helixel-select-line)
    (should (= (region-beginning) 12))
    (should (= (region-end) 22))
    (should (eq (helixel--sel-type) 'line))))

(ert-deftest helixel-test-line-select-prefix-extend-from-middle ()
  "xx from a middle line extends downward with invisible prefixes."
  (helixel-test-with-buffer
      "AAAAAline1\nBBBBBline2\nCCCCCline3\nDDDDDline4\n"
    (setq-local helixel-invisible t)
    (put-text-property 1 6 'invisible 'outline)
    (put-text-property 12 17 'invisible 'outline)
    (put-text-property 23 28 'invisible 'outline)
    (put-text-property 34 39 'invisible 'outline)
    (goto-char 12)
    (helixel-select-line)   ; x     → line 2
    (helixel-select-line)   ; x     → lines 2-3
    (should (= (region-beginning) 12))
    (should (= (region-end) 33))
    (should (eq (helixel--sel-type) 'line))))

(ert-deftest helixel-test-line-select-prefix-shrink ()
  "Negative count shrinks line selection with invisible prefixes."
  (helixel-test-with-buffer
      "AAAAAline1\nBBBBBline2\nCCCCCline3\nDDDDDline4\n"
    (setq-local helixel-invisible t)
    (put-text-property 1 6 'invisible 'outline)
    (put-text-property 12 17 'invisible 'outline)
    (put-text-property 23 28 'invisible 'outline)
    (put-text-property 34 39 'invisible 'outline)
    ;; Select lines 1-3 first.
    (goto-char 1)
    (helixel-select-line 3)
    (should (= (region-beginning) 1))
    (should (= (region-end) 33))
    ;; Shrink by 1 (negative count).
    (helixel-select-line -1)
    (should (= (region-beginning) 1))
    (should (= (region-end) 22))
    (should (eq (helixel--sel-type) 'line))))

(ert-deftest helixel-test-line-select-prefix-variable-lengths ()
  "x works with invisible prefixes of different lengths per line."
  (helixel-test-with-buffer
      "AAline1\nBBBBBline2\nCCCline3\n"
    (setq-local helixel-invisible t)
    ;; Line 1: 2-char invisible prefix (positions 1-2)
    ;; Line 2: 5-char invisible prefix (positions 9-13)
    ;; Line 3: 3-char invisible prefix (positions 20-22)
    (put-text-property 1 3 'invisible 'outline)
    (put-text-property 9 14 'invisible 'outline)
    (put-text-property 20 23 'invisible 'outline)
    (goto-char 1)
    (helixel-select-line)
    ;; Line 1: AAline1\n = positions 1-8
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))
    (helixel-select-line)   ; extend to line 2
    ;; Lines 1-2: positions 1-19
    (should (= (region-beginning) 1))
    (should (= (region-end) 19))
    (should (eq (helixel--sel-type) 'line))))


;;; helixel-select-line with invisible block (org-fold style)

(ert-deftest helixel-test-line-select-block-extend ()
  "x on fully-invisible next lines expands and extends correctly."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\nline5\n"
    (setq-local helixel-invisible t)
    ;; Make lines 2-4 entirely invisible.
    (let ((start (save-excursion (forward-line 1) (point)))
          (end (save-excursion (forward-line 4) (point))))
      (put-text-property start end 'invisible 'outline))
    (goto-char 1)
    (helixel-select-line)
    ;; Should expand through lines 2-4.
    (should (= (region-beginning) 1))
    (should (= (region-end) 24))
    (helixel-select-line)   ; extend by 1 more visible line
    (should (= (region-beginning) 1))
    (should (= (region-end) 30))
    (should (eq (helixel--sel-type) 'line))))


;;; helixel-select-line with mid-line invisible (org-body same line)

(ert-deftest helixel-test-line-select-mid-line-invis ()
  "x expands through invisible text on the same line.
Simulates an org-mode heading with body text folded on the same line."
  (helixel-test-with-buffer "headXXXXX\n"
    (setq-local helixel-invisible t)
    ;; "XXXXX" (positions 5-9) is invisible body on same line.
    (put-text-property 5 10 'invisible 'outline)
    (goto-char 1)
    (helixel-select-line)
    (should (= (region-beginning) 1))
    (should (= (region-end) 10))  ; includes XXXXX
    (should (eq (helixel--sel-type) 'line))))

(ert-deftest helixel-test-line-select-mid-line-invis-extend ()
  "x extends from a line with invisible tail."
  (helixel-test-with-buffer "headXXXXX\nline2\n"
    (setq-local helixel-invisible t)
    (put-text-property 5 10 'invisible 'outline)
    (goto-char 1)
    (helixel-select-line)
    (should (= (region-beginning) 1))
    (should (= (region-end) 10))
    (helixel-select-line)   ; extend to line 2
    (should (= (region-beginning) 1))
    (should (= (region-end) 16))  ; through line 2 EOL
    (should (eq (helixel--sel-type) 'line))))

(ert-deftest helixel-test-line-end-or-invisible-no-trailing-newline ()
  "line-end-or-invisible works when invisible line has no trailing newline.
When the buffer ends without a final newline after invisible text,
line-end-position returns point-max; must still expand correctly."
  (helixel-test-with-buffer "headXXXXX"
    (setq-local helixel-invisible t)
    (put-text-property 5 10 'invisible 'outline)
    (goto-char 1)
    (goto-char 5)  ; mid-line, before invisible text
    (helixel--line-end-or-invisible)
    (should (= (point) 10))  ; includes invisible XXXXX
    (should (eobp))))


;;; Integration: select → kill → paste on folded content

(ert-deftest helixel-test-line-select-kill-folded ()
  "x d on folded content kills the entire section including hidden text."
  (helixel-test-with-buffer
      "* Heading\nline 1\nline 2\n* Next\n"
    (setq-local helixel-invisible t)
    ;; Make the body (lines 2-3) entirely invisible.
    (let ((start (save-excursion (forward-line 1) (point)))
          (end (save-excursion (forward-line 3) (point))))
      (put-text-property start end 'invisible 'outline))
    (goto-char 1)
    (helixel-select-line)
    ;; Verify full section is selected.
    (should (= (region-beginning) 1))
    (should (= (region-end) 24))  ; through line 3
    ;; Kill (d).
    (helixel-kill)
    (should (string= (buffer-string) "* Next\n"))
    (should (string= (car kill-ring)
                     "* Heading\nline 1\nline 2\n"))))

(ert-deftest helixel-test-line-select-copy-folded ()
  "x y on folded content copies the entire section."
  (helixel-test-with-buffer
      "* Heading\nline 1\nline 2\n* Next\n"
    (setq-local helixel-invisible t)
    (let ((start (save-excursion (forward-line 1) (point)))
          (end (save-excursion (forward-line 3) (point))))
      (put-text-property start end 'invisible 'outline))
    (goto-char 1)
    (helixel-select-line)
    ;; Copy (y).
    (helixel-kill-ring-save)
    (should (string= (car kill-ring)
                     "* Heading\nline 1\nline 2\n"))
    ;; Buffer should still be intact.
    (should (string= (buffer-string)
                     "* Heading\nline 1\nline 2\n* Next\n"))))


(provide 'helixel-test-line)
;;; helixel-test-line.el ends here
