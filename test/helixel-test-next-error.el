;;; helixel-test-next-error.el --- Tests for helixel-next-error.el  -*- lexical-binding: t -*-

;; Copyright (C) 2024  Free Software Foundation, Inc.

;; Author: jixiuf <jixiuf@qq.com>
;; Keywords: tests

;; This file is part of helixel.

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

;; Tests for `helixel-next-error.el'.

;;; Code:

(require 'ert)
(require 'helixel-test-common)
(require 'helixel-next-error)
(require 'compile)
(require 'grep)

;; ── Face-run extraction ──
;; Test lines use the realistic grep entry format "FILE:LINE:CONTENT".
;; Face-run columns are buffer-column offsets; collect-grep-runs must
;; subtract the printed "FILE:LINE:" prefix to produce source columns.

(ert-deftest helixel-ne-grep-face-runs-single-match ()
  "Collect-grep-runs extracts a run and subtracts the entry prefix."
  (let ((buf (generate-new-buffer " *ne-test*")))
    (unwind-protect
        (with-current-buffer buf
          (fundamental-mode)
          (insert "/tmp/f:1:foo hello world\n")
          ;; "hello": buffer cols 13-18 (content col 4-9).
          (put-text-property 14 19 'font-lock-face 'match)
          (goto-char 1)
          (let ((result (helixel-ne--collect-grep-runs
                         "/tmp/f" 1 1 'match nil "/tmp/f")))
            (should (equal (length result) 1))
            (let ((tgt (car result)))
              (should (string-equal (helixel-ne--target-file tgt) "/tmp/f"))
              (should (equal (helixel-ne--target-line tgt) 1))
              (should (equal (helixel-ne--target-col-beg tgt) 4))
              (should (equal (helixel-ne--target-col-end tgt) 9)))))
      (kill-buffer buf))))

(ert-deftest helixel-ne-grep-face-runs-multi-match ()
  "Collect-grep-runs extracts multiple runs in order, prefix removed."
  (let ((buf (generate-new-buffer " *ne-test*")))
    (unwind-protect
        (with-current-buffer buf
          (fundamental-mode)
          (insert "/tmp/f:1:ab ab ab\n")
          ;; "ab" runs: buffer cols 9-11, 12-14, 15-17.
          (put-text-property 10 12 'font-lock-face 'match)
          (put-text-property 13 15 'font-lock-face 'match)
          (put-text-property 16 18 'font-lock-face 'match)
          (goto-char 1)
          (let ((result (helixel-ne--collect-grep-runs
                         "/tmp/f" 1 1 'match nil "/tmp/f")))
            (should (equal (length result) 3))
            (let ((t1 (nth 0 result))
                  (t2 (nth 1 result))
                  (t3 (nth 2 result)))
              (should (equal (helixel-ne--target-col-beg t1) 0))
              (should (equal (helixel-ne--target-col-end t1) 2))
              (should (equal (helixel-ne--target-col-beg t2) 3))
              (should (equal (helixel-ne--target-col-end t2) 5))
              (should (equal (helixel-ne--target-col-beg t3) 6))
              (should (equal (helixel-ne--target-col-end t3) 8)))))
      (kill-buffer buf))))

(ert-deftest helixel-ne-grep-face-runs-col-anchor ()
  "When the message column is available, it anchors the first run."
  (let ((buf (generate-new-buffer " *ne-test*")))
    (unwind-protect
        (with-current-buffer buf
          (fundamental-mode)
          (insert "/tmp/f:1:5:foo hello world\n")
          ;; "hello": buffer cols 15-20; "world": buffer cols 21-26.
          (put-text-property 16 21 'font-lock-face 'match)
          (put-text-property 22 27 'font-lock-face 'match)
          (goto-char 1)
          ;; loc-col = 4 anchors the first run: base = 15 - 4 = 11.
          (let ((result (helixel-ne--collect-grep-runs
                         "/tmp/f" 1 1 'match 4 "/tmp/f")))
            (should (equal (length result) 2))
            (let ((t1 (nth 0 result))
                  (t2 (nth 1 result)))
              (should (equal (helixel-ne--target-col-beg t1) 4))
              (should (equal (helixel-ne--target-col-end t1) 9))
              (should (equal (helixel-ne--target-col-beg t2) 10))
              (should (equal (helixel-ne--target-col-end t2) 15)))))
      (kill-buffer buf))))

(ert-deftest helixel-ne-grep-face-runs-no-match ()
  "Collect-grep-runs returns empty when no face runs exist."
  (let ((buf (generate-new-buffer " *ne-test*")))
    (unwind-protect
        (with-current-buffer buf
          (fundamental-mode)
          (insert "/tmp/f:1:no matches here\n")
          (goto-char 1)
          (let ((result (helixel-ne--collect-grep-runs
                         "/tmp/f" 1 1 'match nil "/tmp/f")))
            (should (equal (length result) 0))))
      (kill-buffer buf))))

(ert-deftest helixel-ne-grep-face-runs-ignores-other-face ()
  "Collect-grep-runs skips text with a different font-lock-face."
  (let ((buf (generate-new-buffer " *ne-test*")))
    (unwind-protect
        (with-current-buffer buf
          (fundamental-mode)
          (insert "/tmp/f:1:aXbYc\n")
          ;; X: buffer col 10 (content col 1); Y: buffer col 12.
          (put-text-property 11 12 'font-lock-face 'match)    ; X
          (put-text-property 13 14 'font-lock-face 'warning)  ; Y — skipped
          (goto-char 1)
          (let ((result (helixel-ne--collect-grep-runs
                         "/tmp/f" 1 1 'match nil "/tmp/f")))
            (should (equal (length result) 1))
            (should (equal (helixel-ne--target-col-beg (car result)) 1))
            (should (equal (helixel-ne--target-col-end (car result)) 2))))
      (kill-buffer buf))))

;; ── targets-for-file filtering ──

(ert-deftest helixel-ne-targets-for-file-filter ()
  "targets-for-file returns only targets matching the given filename."
  (let ((targets (vector
                  (helixel-ne--target--create
                   :file "/a/b.txt" :line 1 :col-beg 0 :col-end nil
                   :entry-pos 1)
                  (helixel-ne--target--create
                   :file "/a/c.txt" :line 2 :col-beg 5 :col-end 8
                   :entry-pos 2)
                  (helixel-ne--target--create
                   :file "/a/b.txt" :line 3 :col-beg 0 :col-end nil
                   :entry-pos 3))))
    (let ((result (helixel-ne--targets-for-file "/a/b.txt" targets)))
      (should (equal (length result) 2))
      (should (equal (helixel-ne--target-line (nth 0 result)) 1))
      (should (equal (helixel-ne--target-line (nth 1 result)) 3)))))

;; ── targets build + cache ──

(ert-deftest helixel-ne-targets-builds-from-compilation ()
  "Collect-targets builds snapshot from a compilation-mode buffer.
Uses `compilation-fake-loc' and manually set text properties
to simulate a grep-style entry."
  (let ((src-buf (generate-new-buffer "ne-src"))
        (comp-buf (generate-new-buffer "*ne-comp*"))
        (tmp-file (make-temp-file "helixel-ne-test-")))
    (unwind-protect
        (progn
          ;; Use a real temp file so compilation-fake-loc gets a
          ;; proper absolute filename.
          (with-current-buffer src-buf
            (set-visited-file-name tmp-file)
            (insert "hello world\n")
            (goto-char (point-min))
            (setq-local next-error-last-buffer comp-buf))
          ;; Set up compilation buffer.
          (with-current-buffer comp-buf
            (let ((delay-mode-hooks t))
              (compilation-mode))
            (setq next-error-function #'compilation-next-error-function)
            ;; Insert a grep-style line and set compilation-message.
            (let ((inhibit-read-only t))
              (erase-buffer)
              (insert (format "%s:1:hello world\n" tmp-file)))
            (goto-char (point-min))
            ;; Build targets — compilation-mode will parse the line.
            (setq next-error-last-buffer comp-buf)
            (let ((targets (helixel-ne--collect-targets)))
              (should targets)
              (should (>= (length targets) 1))
              (let ((tgt (aref targets 0)))
                (should (equal (helixel-ne--target-line tgt) 1))
                (should (equal (helixel-ne--target-col-beg tgt) 0))))))
      ;; Cleanup.
      (ignore-errors (kill-buffer comp-buf))
      (ignore-errors (kill-buffer src-buf))
      (ignore-errors (delete-file tmp-file)))))

(ert-deftest helixel-ne-targets-cache-invalidation ()
  "Cache is invalidated when the compilation buffer is modified."
  (let ((comp-buf (generate-new-buffer "*ne-cache*")))
    (unwind-protect
        (with-current-buffer comp-buf
          (let ((delay-mode-hooks t))
            (compilation-mode))
          (setq next-error-function #'compilation-next-error-function)
          (setq next-error-last-buffer comp-buf)
          (let* ((first (or (helixel-ne--targets) []))
                 (tick1 helixel-ne--all-targets-tick))
            (should (vectorp first))
            ;; Modify the buffer behind read-only — cache should be stale.
            (let ((inhibit-read-only t))
              (insert "x"))
            (let ((second (helixel-ne--targets)))
              (should (or (not helixel-ne--all-targets-tick)
                          (not (eq helixel-ne--all-targets-tick tick1)))))))
      (ignore-errors (kill-buffer comp-buf)))))

;; ── end-loc precise ranges (non-grep) ──

(defun helixel-ne-test--collect-with-message (loc end-loc)
  "Run `helixel-ne--collect-entry' on a fabricated compilation message.
LOC and END-LOC are (COL LINE) pairs in upstream storage form
\(1-based per `compilation-first-column', END-LOC column already
made exclusive by the parser); END-LOC may be nil.
Returns the collected target list."
  (let ((buf (generate-new-buffer " *ne-msg*")))
    (unwind-protect
        (with-current-buffer buf
          (insert "x.c:10:5-8: some error text\n")
          (let* ((fs (compilation--make-file-struct
                      (list "/tmp/x.c" nil) nil))
                 (loc-obj (list (car loc) (cadr loc) fs nil nil))
                 (end-loc-obj (and end-loc
                                   (list (car end-loc) (cadr end-loc)
                                         fs nil nil)))
                 (msg (compilation--make-message
                       loc-obj 2 end-loc-obj nil)))
            (put-text-property 1 2 'compilation-message msg)
            (goto-char 1)
            (helixel-ne--collect-entry nil nil)))
      (kill-buffer buf))))

(ert-deftest helixel-ne-end-loc-same-line-range ()
  "Non-grep entries with a same-line END-LOC get precise columns.
Message columns are 1-based: col 5, stored end-col 9 (already
exclusive upstream) normalize to col-beg 4, col-end 8."
  (let ((targets (helixel-ne-test--collect-with-message '(5 10) '(9 10))))
    (should (= (length targets) 1))
    (let ((tgt (car targets)))
      (should (= (helixel-ne--target-col-beg tgt) 4))
      (should (= (helixel-ne--target-col-end tgt) 8)))))

(ert-deftest helixel-ne-end-loc-multiline-is-whole-line ()
  "An END-LOC on a different line falls back to whole-line selection."
  (let ((targets (helixel-ne-test--collect-with-message '(5 10) '(3 12))))
    (should (= (length targets) 1))
    (should (null (helixel-ne--target-col-end (car targets))))))

(ert-deftest helixel-ne-end-loc-eol-marker-is-whole-line ()
  "END-COL -1 (upstream end-of-line marker) selects the whole line."
  (let ((targets (helixel-ne-test--collect-with-message '(5 10) '(-1 10))))
    (should (= (length targets) 1))
    (should (null (helixel-ne--target-col-end (car targets))))))

(ert-deftest helixel-ne-no-end-loc-is-whole-line ()
  "Entries without END-LOC keep whole-line selection, with the
column normalized from the 1-based message convention."
  (let ((targets (helixel-ne-test--collect-with-message '(5 10) nil)))
    (should (= (length targets) 1))
    (should (= (helixel-ne--target-col-beg (car targets)) 4))
    (should (null (helixel-ne--target-col-end (car targets))))))

(ert-deftest helixel-ne-col-respects-first-column ()
  "Column normalization follows `compilation-first-column' (0 in
grep buffers): stored columns are used as-is."
  (let ((compilation-first-column 0))
    (let ((targets (helixel-ne-test--collect-with-message '(5 10) '(9 10))))
      (should (= (helixel-ne--target-col-beg (car targets)) 5))
      (should (= (helixel-ne--target-col-end (car targets)) 9)))))

;; ── Navigation: step / step-in-file / after-jump ──
;; Fixture: F1 has matches on lines 2 and 4, F2 on line 1; the
;; compilation buffer lists entries in order F1:2, F2:1, F1:4.

(defmacro helixel-ne-test--with-fixture (&rest body)
  "Set up two temp files and a compilation buffer with 3 entries.
Binds COMP-BUF, F1 and F2 lexically around BODY."
  (declare (indent 0))
  `(let* ((tmp-dir (make-temp-file "helixel-ne-test-" t))
          (f1 (expand-file-name "a.txt" tmp-dir))
          (f2 (expand-file-name "b.txt" tmp-dir))
          (comp-buf (generate-new-buffer " *ne-fixture*")))
     (unwind-protect
         (progn
           (with-temp-file f1 (insert "l1\nfoo one\nl3\nfoo two\n"))
           (with-temp-file f2 (insert "foo three\nl2\n"))
           (with-current-buffer comp-buf
             (let ((delay-mode-hooks t))
               (compilation-mode))
             (setq next-error-function
                   #'compilation-next-error-function)
             (let ((inhibit-read-only t))
               (erase-buffer)
               (insert (format "%s:2:foo one\n" f1))
               (insert (format "%s:1:foo three\n" f2))
               (insert (format "%s:4:foo two\n" f1)))
             (setq next-error-last-buffer comp-buf)
             (goto-char (point-min)))
           (save-window-excursion ,@body))
      (ignore-errors (kill-buffer comp-buf))
      (dolist (f (list f1 f2))
        (ignore-errors (kill-buffer (find-buffer-visiting f)))
        (ignore-errors (delete-file f)))
      (ignore-errors (delete-directory tmp-dir)))))

(defsubst helixel-ne-test--at (file line)
  "Return non-nil when visiting FILE with point on LINE."
  (and (string-equal (buffer-file-name) file)
       (= (line-number-at-pos) line)))

(ert-deftest helixel-ne-step-forward-backward-across-files ()
  "Step walks the snapshot by index, across file boundaries.
Both ends signal `user-error' without moving."
  (helixel-ne-test--with-fixture
    (helixel-ne--step 'forward)
    (should (helixel-ne-test--at f1 2))
    (should (use-region-p))
    (helixel-ne--step 'forward)
    (should (helixel-ne-test--at f2 1))
    (helixel-ne--step 'forward)
    (should (helixel-ne-test--at f1 4))
    (should-error (helixel-ne--step 'forward) :type 'user-error)
    (helixel-ne--step 'backward)
    (should (helixel-ne-test--at f2 1))
    (helixel-ne--step 'backward)
    (should (helixel-ne-test--at f1 2))
    (should-error (helixel-ne--step 'backward) :type 'user-error)))

(ert-deftest helixel-ne-step-in-file-skips-other-files ()
  "Step-in-file visits only targets in the current file and
syncs the shared index."
  (helixel-ne-test--with-fixture
    (helixel-ne--step 'forward)              ; f1:2 (idx 0)
    (should (helixel-ne--step-in-file 'forward)) ; f1:4 (idx 2)
    (should (helixel-ne-test--at f1 4))
    ;; Index synced: global forward step is now at the boundary.
    (should-error (helixel-ne--step 'forward) :type 'user-error)))

(ert-deftest helixel-ne-step-in-file-nil-at-file-edge ()
  "Step-in-file returns nil (no move, no index change) when no
target remains in the current file."
  (helixel-ne-test--with-fixture
    (helixel-ne--step 'forward)
    (helixel-ne--step 'forward)              ; f2:1 (idx 1)
    (should (helixel-ne-test--at f2 1))
    (should-not (helixel-ne--step-in-file 'forward))
    (should-not (helixel-ne--step-in-file 'backward))
    (should (helixel-ne-test--at f2 1))
    ;; Index untouched: global backward step still reaches f1:2.
    (helixel-ne--step 'backward)
    (should (helixel-ne-test--at f1 2))))

(ert-deftest helixel-ne-after-jump-syncs-state ()
  "After-jump syncs the index from `compilation-current-error',
selects the match region, and seeds repeat state."
  (helixel-ne-test--with-fixture
    (with-current-buffer comp-buf
      (goto-char (point-min))    ; entry 1 starts at point-min
      (setq compilation-current-error (point-marker)))
    (find-file f1)
    (setq-local next-error-last-buffer comp-buf)
    (helixel-ne--after-jump)
    (should (eq (helixel-search--safe-category) 'next-error))
    (should (= (buffer-local-value 'helixel-ne--target-idx comp-buf)
               0))
    (should (use-region-p))
    (should (helixel-ne-test--at f1 2))))

(ert-deftest helixel-ne-repeat-cross-buffer ()
  "n/N keep working after a step lands in another file buffer.
`helixel--active-search' is buffer-local, so each visit seeds
it (with the direction in effect at step time)."
  (helixel-ne-test--with-fixture
    (with-current-buffer comp-buf
      (goto-char (point-min))
      (setq compilation-current-error (point-marker)))
    (find-file f1)
    (setq-local next-error-last-buffer comp-buf)
    (helixel-ne--after-jump)               ; in f1, idx 0
    (helixel-search-repeat-next)           ; n  -> f2:1
    (should (helixel-ne-test--at f2 1))
    (helixel-search-repeat-next)           ; n (pressed in f2) -> f1:4
    (should (helixel-ne-test--at f1 4))
    (helixel-search-repeat-reverse)        ; N: flip -> bwd, f2:1
    (should (helixel-ne-test--at f2 1))
    (helixel-search-repeat-next)           ; n: dir now bwd -> f1:2
    (should (helixel-ne-test--at f1 2))))

(provide 'helixel-test-next-error)
;;; helixel-test-next-error.el ends here
