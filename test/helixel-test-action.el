;;; helixel-test-action.el --- Tests for action tracking (event-ring API)  -*- lexical-binding: t; -*-

;; Copyright (C) 2025-2026  jixiuf

;; Author: jixiuf
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

;; Tests for action tracking using helixel--action-ring (new API).

;;; Code:

(require 'ert)
(require 'helixel)

;;; Action tracking tests

(ert-deftest helixel-test-action-start-movement ()
  "Test movement commands create and continue actions."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil
          last-command nil this-command 'helixel-next-line)
    (helixel-next-line)
    (should helixel--live-action)
    (should (eq (helixel-action-category helixel--live-action) 'movement))
    (should (eq (helixel-action-subcat helixel--live-action) 'line))
    (should (null helixel--action-pos))
    (let ((mark-pos (marker-position
                     (car (helixel-action-mark-region helixel--live-action)))))
      (setq last-command 'helixel-next-line
            this-command 'helixel-next-line)
      (helixel-next-line)
      (should (eq (helixel-action-category helixel--live-action) 'movement))
      (should (eq (helixel-action-subcat helixel--live-action) 'line)))))

(ert-deftest helixel-test-action-category-mismatch ()
  "Test different categories push old event to ring."
  (helixel-test-with-buffer "axb axb axb"
    (setq helixel--action-ring nil helixel--live-action nil
          last-command nil this-command 'helixel-find-next-char)
    (helixel-find-next-char ?b)
    ;; find-char commits its event → ring has 1 entry
    (should (= (length helixel--action-ring) 1))
    (should (eq (helixel-action-category (car helixel--action-ring))
                'find-char))
    (let ((mark1 (marker-position
                  (car (helixel-action-mark-region (car helixel--action-ring))))))
      (setq last-command 'helixel-find-next-char
            this-command 'helixel-forward-char)
      (helixel-forward-char)
      (should (eq (helixel-action-category helixel--live-action) 'movement))
      (should (eq (helixel-action-subcat helixel--live-action) 'char))
      (should (not (eq (marker-position
                        (car (helixel-action-mark-region helixel--live-action)))
                       mark1)))
      (should (= (length helixel--action-ring) 1))
      (should (eq (helixel-action-category (nth 0 helixel--action-ring))
                  'find-char)))))

(ert-deftest helixel-test-action-movement-different-subcat ()
  "Test different movement subcats push to ring."
  (helixel-test-with-buffer "hello\nworld\nagain"
    (setq helixel--action-ring nil helixel--live-action nil
          last-command nil this-command 'helixel-forward-char)
    (helixel-forward-char)
    (should (eq (helixel-action-subcat helixel--live-action) 'char))
    (setq last-command 'helixel-forward-char
          this-command 'helixel-next-line)
    (helixel-next-line)
    (should (eq (helixel-action-subcat helixel--live-action) 'line))
    (should (= (length helixel--action-ring) 1))))

(ert-deftest helixel-test-action-cycle-live ()
  "Test ; pushes live event to ring and shows ring[0]."
  (helixel-test-with-buffer "hello world again"
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil
          last-command nil this-command 'helixel-forward-char)
    (goto-char 1)
    (helixel-forward-char)
    (setq last-command 'helixel-forward-char
          this-command 'helixel-forward-char)
    (helixel-forward-char)
    (helixel--action-cycle)
    (should (= (length helixel--action-ring) 2))
    (should (= helixel--action-pos 1))
    (should (= (region-beginning) 1))))

(ert-deftest helixel-test-action-cycle-ring ()
  "Test ; cycles through event ring."
  (helixel-test-with-buffer "hello\nworld\nagain"
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil
          last-command nil this-command 'helixel-forward-char)
    (goto-char 1)
    (helixel-forward-char)
    (let ((mark1 (marker-position
                  (car (helixel-action-mark-region helixel--live-action)))))
      (setq last-command 'helixel-forward-char
            this-command 'helixel-next-line)
      (goto-char 5)
      (helixel-next-line)
      (should (= (length helixel--action-ring) 1))
      (helixel--action-cycle)
      (should (eq helixel--action-pos 0))
      (should (use-region-p)))))

(ert-deftest helixel-test-action-goto-continues ()
  "Test goto commands share the same action."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (setq helixel--action-ring nil helixel--live-action nil
          last-command nil this-command 'helixel-go-beginning-line)
    (helixel-go-beginning-line)
    (should (eq (helixel-action-category helixel--live-action) 'movement))
    (should (eq (helixel-action-subcat helixel--live-action) 'goto))))

(ert-deftest helixel-test-action-select-continues ()
  "Test select commands share the same action."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (setq helixel--action-ring nil helixel--live-action nil
          last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (should (eq (helixel-action-subcat helixel--live-action) 'lineselect))))

(ert-deftest helixel-test-action-no-session-error ()
  "Test action-cycle with no sessions shows message."
  (let ((helixel--action-ring nil) (helixel--live-action nil)
        (helixel--action-pos nil))
    (helixel--action-cycle)
    t))

(ert-deftest helixel-test-action-cycle-forward ()
  "Test C-u ; cycles forward through saved events."
  (helixel-test-with-buffer "hello\nworld\nagain"
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil
          last-command nil this-command 'helixel-forward-char)
    (helixel-forward-char)
    (setq last-command 'helixel-forward-char
          this-command 'helixel-next-line)
    (goto-char 5)
    (helixel-next-line)
    (helixel--action-cycle)
    (should (eq helixel--action-pos 0))
    (should (= (region-beginning) 5))
    (helixel--action-cycle)
    (should (eq helixel--action-pos 1))
    (helixel--action-cycle t)
    (should (eq helixel--action-pos 0))))

(ert-deftest helixel-test-action-same-subcat-continues ()
  "Test same subcat movements continue event."
  (helixel-test-with-buffer "hello world test"
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil
          last-command nil this-command 'helixel-forward-word-start)
    (helixel-forward-word-start)
    (should (eq (helixel-action-subcat helixel--live-action) 'word))
    (let ((mark-pos (marker-position
                     (car (helixel-action-mark-region helixel--live-action)))))
      (setq last-command 'helixel-forward-word-start
            this-command 'helixel-forward-word-end)
      (helixel-forward-word-end)
      (should (eq (helixel-action-subcat helixel--live-action) 'word)))))

(ert-deftest helixel-test-action-different-subcat-breaks ()
  "Test different subcat pushes old event to ring."
  (helixel-test-with-buffer "hello world\ntest line"
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil
          last-command nil this-command 'helixel-forward-word-start)
    (helixel-forward-word-start)
    (should (eq (helixel-action-subcat helixel--live-action) 'word))
    (let ((word-mark (marker-position
                      (car (helixel-action-mark-region helixel--live-action)))))
      (setq last-command 'helixel-forward-word-start
            this-command 'helixel-next-line)
      (helixel-next-line)
      (should (eq (helixel-action-subcat helixel--live-action) 'line))
      (should (= (length helixel--action-ring) 1)))))

(ert-deftest helixel-test-action-goto-marker ()
  "Test goto commands record correct marker position."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil
          last-command nil this-command 'helixel-go-beginning-buffer)
    (goto-char 10)
    (helixel-go-beginning-buffer)
    (should helixel--live-action)
    (should (eq (helixel-action-subcat helixel--live-action) 'goto))
    (should (= (marker-position
                (car (helixel-action-mark-region helixel--live-action))) 10))))

(ert-deftest helixel-test-action-wrapper-commands ()
  "Test goto-line starts action correctly."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\nline5"
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil
          last-command nil this-command 'helixel-goto-line)
    (goto-char 1)
    (helixel-goto-line 3)
    (should helixel--live-action)
    (should (eq (helixel-action-subcat helixel--live-action) 'goto))))

(ert-deftest helixel-test-goto-line-lisp-arg ()
  "Test helixel-goto-line called from Lisp uses arg parameter."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\nline5"
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil
          last-command nil this-command 'helixel-goto-line
          current-prefix-arg nil)
    (helixel-goto-line 4)
    (should (= (line-number-at-pos) 4))
    (should (string= (buffer-substring (pos-bol) (pos-eol)) "line4"))))

(ert-deftest helixel-test-action-select-commands ()
  "Test select-line starts action correctly."
  (helixel-test-with-buffer "hello world"
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil
          last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (should helixel--live-action)
    (should (eq (helixel-action-subcat helixel--live-action) 'lineselect))))

(ert-deftest helixel-test-define-movement-macro ()
  "Test helixel-define-movement creates a working action-tracked command."
  (helixel-define-movement helixel-test-movement2 forward-char char)
  (helixel-test-with-buffer "hello"
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil
          last-command nil this-command 'helixel-test-movement2)
    (helixel-test-movement2)
    (should helixel--live-action)
    (should (eq (helixel-action-category helixel--live-action) 'movement))
    (should (eq (helixel-action-subcat helixel--live-action) 'char))))

;;; Execute command tests

(ert-deftest helixel-test-execute-command-known ()
  (let ((helixel--command-alist `((("test-cmd") ,#'ignore))))
    (should (progn (helixel-execute-command "test-cmd") t))))

(ert-deftest helixel-test-execute-command-unknown ()
  (let ((helixel--command-alist nil))
    (should (progn (helixel-execute-command "no-such-cmd") t))))

(ert-deftest helixel-test-execute-command-call-interactively ()
  (let ((helixel--command-alist nil)
        (called-interactively nil))
    (cl-letf (((symbol-function 'test-helixel-cmd)
               (lambda () (interactive)
                 (setq called-interactively (called-interactively-p)))))
      (helixel-define-ex-command "test-ia" #'test-helixel-cmd)
      (helixel-execute-command "test-ia")
      (should called-interactively))))

(ert-deftest helixel-test-execute-command-funcall ()
  (let ((helixel--command-alist nil) (called nil))
    (helixel-define-ex-command "test-fn" (lambda () (setq called t)))
    (helixel-execute-command "test-fn")
    (should called)))

(ert-deftest helixel-test-execute-command-multi-callback ()
  (let ((helixel--command-alist nil) (counter 0))
    (helixel-define-ex-command
     "multi"
     (list (lambda () (setq counter (1+ counter)))
           (lambda () (setq counter (1+ counter)))
           #'ignore))
    (helixel-execute-command "multi")
    (should (= counter 2))))

(ert-deftest helixel-test-execute-command-multi-order ()
  (let ((helixel--command-alist nil) (vals nil))
    (helixel-define-ex-command
     "ord"
     (list (lambda () (push 1 vals))
           (lambda () (push 2 vals))
           (lambda () (push 3 vals))))
    (helixel-execute-command "ord")
    (should (equal vals '(3 2 1)))))

(ert-deftest helixel-test-execute-command-with-aliases ()
  (let ((helixel--command-alist nil) (called nil))
    (helixel-define-ex-command
     '("a" "alias" "alt") (lambda () (setq called t)))
    (helixel-execute-command "alias")
    (should called)))

(ert-deftest helixel-test-execute-command-second-alias ()
  (let ((helixel--command-alist nil) (called nil))
    (helixel-define-ex-command
     '("a" "alias" "alt") (lambda () (setq called t)))
    (setq called nil)
    (helixel-execute-command "alt")
    (should called)))

(ert-deftest helixel-test-define-typable-command-single-symbol ()
  (let ((helixel--command-alist nil) (called nil))
    (cl-letf (((symbol-function 'test-tc) (lambda () (setq called t))))
      (helixel-define-ex-command "tc-sym" #'test-tc)
      (helixel-execute-command "tc-sym")
      (should called))))

(ert-deftest helixel-test-define-typable-command-duplicate ()
  (let ((helixel--command-alist nil))
    (helixel-define-ex-command "dup" #'ignore)
    (helixel-define-ex-command "dup" #'ignore)
    (should (= (length helixel--command-alist) 1))))

;;; Search-history tests

(ert-deftest helixel-test-history-search-creates-proper-action ()
  "Test from-history for search sets category, subcat, marker on live event."
  (let ((helixel--action-ring nil) (helixel--live-action nil)
        (helixel--active-search
         (make-helixel--last-motion :category 'search :pattern "test" :dir 'forward)))
    (helixel-test-with-buffer "a test b"
      (goto-char 3)
      ;; Push a search event to ring so history can find it
      (helixel--tracking-open 'search 'search)
      (setf (helixel-action-payload helixel--live-action)
            '(:pattern "test"))
      (helixel-action-commit)
      (should (= (length helixel--action-ring) 1))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display-format
                    (car helixel--action-ring)))))
        (helixel-search--from-history t))
      ;; from-history commits a new search event to the ring
      (should (= (length helixel--action-ring) 2))
      (should (eq (helixel-action-category (car helixel--action-ring)) 'search))
      (should (eq (helixel-action-subcat (car helixel--action-ring)) 'search))
      (should (car (helixel-action-mark-region (car helixel--action-ring)))))))

;;; C-g session cancel test

(ert-deftest helixel-test-c-g-cancels-session ()
  "Test C-g breaks session and pushes cancel sentinel."
  (helixel-test-with-buffer "hello world test extra"
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil
          last-command nil this-command 'helixel-forward-word-start)
    (helixel-forward-word-start)
    (let ((mark1 (marker-position
                  (car (helixel-action-mark-region helixel--live-action)))))
      (setq last-command 'helixel-forward-word-start
            this-command 'helixel-forward-word-start)
      (helixel-forward-word-start)
      (should-not (= (marker-position
                      (car (helixel-action-mark-region helixel--live-action)))
                     mark1))
      (helixel--cancel-action)
      (should (= (length helixel--action-ring) 3))
      (should (eq (helixel-action-category (car helixel--action-ring))
                  'state))
      (setq last-command nil this-command 'helixel-forward-word-start)
      (goto-char 7)
      (helixel-forward-word-start)
      (should helixel--live-action)
      (should (= (marker-position
                  (car (helixel-action-mark-region helixel--live-action))) 7))
      (helixel--action-cycle)
      (should (= (length helixel--action-ring) 4))
      (should (eq (helixel-action-category
                   (nth helixel--action-pos helixel--action-ring))
                  'movement))
      (helixel--action-cycle)
      (should (eq (helixel-action-category
                   (nth helixel--action-pos helixel--action-ring))
                  'movement))
      (should (= (region-beginning) 1)))))

(provide 'helixel-test-action)
;;; helixel-test-action.el ends here
