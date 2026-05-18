;;; helixel-test-line.el --- Tests for Helixel: line-wise editing  -*- lexical-binding: t; -*-

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

;;; helixel-test-line.el ends here
