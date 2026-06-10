;;; helixel-test-swap.el --- Tests for Helixel: swap  -*- lexical-binding: t; -*-

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

;;; helixel-swap tests

(defun helixel-test--set-swap-source (buffer beg end &optional type)
  "Store swap-source plist in `helixel--yank-register'.
TYPE is the selection type: nil (char), `line', or `rect'."
  (set-register helixel--yank-register
                (list :beg (set-marker (make-marker) beg buffer)
                      :end (set-marker (make-marker) end buffer)
                      :buffer buffer
                      :type type)))

(defun helixel-test--get-swap-source ()
  "Return the swap-source plist from `helixel--yank-register', or nil."
  (get-register helixel--yank-register))

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

(ert-deftest helixel-test-swap-after-intermediate-kill ()
  "Swap still works after a delete operation.
`y' stores swap-source in the dedicated yank register, which is
independent of the kill-ring — so `d' does not invalidate it."
  (helixel-test-with-buffer "AAA BBB CCC"
    (let ((kill-ring nil))
      ;; Step 1: copy "AAA" with `y' (stores swap-source in register ?Y)
      (setq helixel--raw-selection-type nil)
      (push-mark 4 t t)
      (goto-char 1)
      (helixel-kill-ring-save)
      (should (helixel-test--get-swap-source)) ; swap source exists
      ;; Step 2: delete "BBB" with `d' (does NOT touch register ?Y)
      (push-mark 8 t t)
      (goto-char 5)
      (setq helixel--raw-selection-type nil)
      (helixel-kill)
      ;; Swap source still intact — register is independent.
      (should (helixel-test--get-swap-source))
      (should (helixel--swap-source-from-kill)))))

(ert-deftest helixel-test-y-sets-swap-source ()
  "`y' stores swap-source in `helixel--yank-register'."
  (helixel-test-with-buffer "hello world"
    (let ((kill-ring nil))
      (push-mark 1 t t)
      (goto-char 6)
      (setq helixel--raw-selection-type nil)
      (helixel-kill-ring-save)
      (let ((src (helixel-test--get-swap-source)))
        (should src)
        (should (= (marker-position (plist-get src :beg)) 1))
        (should (= (marker-position (plist-get src :end)) 6))))))

(ert-deftest helixel-test-y-sets-swap-source-line ()
  "`y' stores line-wise swap-source in `helixel--yank-register'."
  (helixel-test-with-buffer "first line\nsecond line"
    (let ((kill-ring nil))
      (push-mark 1 t t)
      (goto-char 11)
      (setq helixel--raw-selection-type 'line)
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
      (setq helixel--raw-selection-type nil)
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

;;; Zero-width swap tests

(ert-deftest helixel-test-swap-zero-width ()
  "Zero-width copy then swap with implied region."
  (helixel-test-with-buffer "AAA BBB CCC"
    (let ((kill-ring nil))
      ;; Zero-width copy at position 1 (beg = end = 1)
      (helixel-test--set-swap-source (current-buffer) 1 1)
      (goto-char 5)
      (let ((helixel-swap-imply-region t))
        (helixel-swap))
      ;; Zero-width source + zero-width implied region = no-op.
      (should (string= (buffer-string) "AAA BBB CCC")))))

(ert-deftest helixel-test-swap-zero-width-with-region ()
  "Zero-width copy then swap with active region (move text to insertion point)."
  (helixel-test-with-buffer "AAA BBB CCC"
    (let ((kill-ring nil))
      ;; Zero-width copy at position 5 (between AAA and BBB)
      (helixel-test--set-swap-source (current-buffer) 5 5)
      ;; Select "CCC" (positions 9-12)
      (push-mark 12 t t)
      (goto-char 9)
      (helixel-swap)
      ;; "CCC" should move to position 5 (the zero-width insertion point)
      (should (string= (buffer-string) "AAA CCCBBB ")))))

(ert-deftest helixel-test-swap-end-to-end-copy-swap ()
  "End-to-end: `y' copy then `S' swap."
  (helixel-test-with-buffer "AAA BBB CCC"
    (let ((kill-ring nil))
      (setq helixel--raw-selection-type nil)
      (push-mark 4 t t)
      (goto-char 1)
      (helixel-kill-ring-save)          ; y: copy "AAA"
      (push-mark 12 t t)
      (goto-char 9)
      (helixel-swap)                     ; S: swap "AAA" with "CCC"
      (should (string= (buffer-string) "CCC BBB AAA")))))

(ert-deftest helixel-test-swap-after-change ()
  "Swap still works after a change (`c') — change does not touch register ?Y."
  (helixel-test-with-buffer "AAA BBB CCC"
    (let ((kill-ring nil))
      ;; Copy "AAA"
      (setq helixel--raw-selection-type nil)
      (push-mark 4 t t)
      (goto-char 1)
      (helixel-kill-ring-save)
      ;; Change "BBB" (c replaces selection, pushes to kill-ring)
      (push-mark 8 t t)
      (goto-char 5)
      (setq helixel--raw-selection-type nil)
      (helixel-change)
      (insert "XXX")
      (helixel--record-action 'change)
      (helixel--clear-data)
      ;; Now buffer is "AAA XXX CCC", swap "AAA" with "CCC"
      (push-mark 12 t t)
      (goto-char 9)
      (helixel-swap)
      (should (string= (buffer-string) "CCC XXX AAA")))))

(ert-deftest helixel-test-swap-after-multiple-deletes ()
  "Swap still works after multiple deletes."
  (helixel-test-with-buffer "AAA BBB CCC DDD"
    (let ((kill-ring nil))
      ;; Copy "AAA"
      (setq helixel--raw-selection-type nil)
      (push-mark 4 t t)
      (goto-char 1)
      (helixel-kill-ring-save)
      ;; Delete "BBB"
      (push-mark 8 t t)
      (goto-char 5)
      (setq helixel--raw-selection-type nil)
      (helixel-kill)
      ;; Delete "DDD"
      (push-mark 14 t t)
      (goto-char 11)
      (setq helixel--raw-selection-type nil)
      (helixel-kill)
      ;; Buffer: "AAA  CCC ", swap with implied region at point 5
      (goto-char 5)
      (let ((helixel-swap-imply-region t))
        (helixel-swap))
      ;; Swap source ("AAA") should still be valid.
      (should (helixel--swap-source-from-kill)))))

(ert-deftest helixel-test-swap-named-register ()
  "Named register `\"ay' stores swap-source to register ?Y."
  (helixel-test-with-buffer "AAA BBB"
    (let ((kill-ring nil))
      ;; Copy to register a (swap-source goes to ?Y)
      (setq helixel--current-register ?a)
      (setq helixel--raw-selection-type nil)
      (push-mark 4 t t)
      (goto-char 1)
      (helixel-kill-ring-save)
      (helixel--register-consume)
      ;; Verify swap-source is in register ?Y
      (let ((src (helixel-test--get-swap-source)))
        (should src)
        (should (= (marker-position (plist-get src :beg)) 1))
        (should (= (marker-position (plist-get src :end)) 4)))
      ;; Swap with "BBB"
      (push-mark 8 t t)
      (goto-char 5)
      (helixel-swap)
      (should (string= (buffer-string) "BBB AAA")))))

;;; helixel-test-swap.el ends here
