;;; helixel-test-jump.el --- Tests for Helixel: jump navigation  -*- lexical-binding: t; -*-

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



;;; Jump navigation tests

(ert-deftest helixel-test-jump-empty-list ()
  "C-o with empty jump list says no positions."
  (let ((helixel--global-jump-log nil)
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
  (let ((helixel--global-jump-log nil)
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
  (let ((helixel--global-jump-log nil)
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
  (let ((helixel--global-jump-log nil)
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
  (let ((helixel--global-jump-log nil)
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
  (let ((helixel--global-jump-log nil)
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

(ert-deftest helixel-test-jump-dead-buffer ()
  "C-o skips entries whose buffer has been killed."
  (let ((helixel--global-jump-log nil)
        (helixel--jump-pos nil)
        (buf (generate-new-buffer "jump-dead")))
    (with-current-buffer buf
      (insert "line1\nline2")
      (goto-char 2)
      (helixel-register-jump 'goto 'test)
      (goto-char 7)
      (helixel-register-jump 'search 'foo))
    (kill-buffer buf)
    (with-temp-buffer
      (insert "fresh")
      (let ((msg nil))
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args)
                     (setq msg (apply #'format fmt args)))))
          (helixel-jump-backward)
          (should (string= msg "No jump positions")))))))

(ert-deftest helixel-test-jump-capacity-cap ()
  "Jump log truncates at helixel-jump-log-max; navigation survives."
  (let ((helixel--global-jump-log nil)
        (helixel--jump-pos nil)
        (helixel-jump-log-max 5))
    (with-temp-buffer
      (transient-mark-mode 1)
      (insert (make-string 100 ?x))
      (dotimes (i 10)
        (goto-char (1+ i))
        (helixel-register-jump 'goto 'test))
      ;; Log should be capped at 5
      (should (<= (length helixel--global-jump-log) 5))
      ;; The oldest entry should be position 7 (the return jump eats one cap slot)
      (goto-char 10)
      (helixel-jump-backward)
      (should (= (point) 7))
      (helixel-jump-forward)  ;; back to original position
      (should (= (point) 10))
      (let ((msg nil))
        (cl-letf (((symbol-function 'message)
                   (lambda (fmt &rest args)
                     (setq msg (apply #'format fmt args)))))
          (helixel-jump-forward)  ;; now at newest
          (should (string= msg "At newest")))))))

;; ============================================================================
;; P0.1: ring-head sync — verify pick replays full payload
;; ============================================================================


(provide 'helixel-test-jump)
;;; helixel-test-jump.el ends here
