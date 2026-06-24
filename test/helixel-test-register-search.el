;;; helixel-test-register-search.el --- Tests: register-search  -*- lexical-binding: t; -*-

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

;; Tests for register-prefix search (\"d/ \"d* \"d? \"d#).

;;; Code:

(require 'ert)
(require 'helixel)


;; ── `helixel-search--from-register' unit tests ──

(ert-deftest helixel-test-register-search--empty-register ()
  "`helixel-search--from-register' signals user-error for empty register."
  (let ((helixel--current-register ?z)
        (helixel--action-ring nil)
        (helixel--live-action nil)
        (helixel--action-pos nil))
    (should (null (helixel--register-get ?z)))
    (should-error
     (helixel-search--from-register 'forward)
     :type 'user-error)))

(ert-deftest helixel-test-register-search--from-register-forward ()
  "Register-search forward: done-hook sets up active-search and sel-ctx."
  (let ((helixel--current-register nil)
        helixel--action-ring helixel--live-action helixel--action-pos
        (helixel--active-search nil)
        (helixel--pending-sel nil))
    (unwind-protect
        (progn
          (helixel--register-set ?a "hello")
          (setq helixel--current-register ?a)
          (should (helixel--register-active-p))
          (helixel-test-with-buffer "hello world hello"
            (goto-char 1)
            (helixel--tracking-open 'search 'search)
            ;; Simulate from-register: consume → isearch-literal → done-hook
            (helixel--register-consume)
            (let ((helixel-search--had-region nil)
                  (pat "hello"))
              (re-search-forward pat)
              (let ((isearch-success t)
                    (isearch-string pat)
                    (isearch-regexp t)
                    (isearch-forward t)
                    (isearch-other-end (copy-marker (match-beginning 0))))
                (helixel-search--done-hook)))
            ;; Register consumed
            (should (null helixel--current-register))
            ;; Point at match-end (forward search)
            (should (= (point) 6))
            ;; Region active on match
            (should (region-active-p))
            (should (= (region-beginning) 1))
            (should (= (region-end) 6))
            ;; Active search set up for n/N repeat
            (should (eq (helixel--last-motion-category
                         helixel--active-search)
                        'search))
            (should (eq (helixel--last-motion-dir
                         helixel--active-search)
                        'forward))
            ;; Pending-sel for . repeat
            (should helixel--pending-sel)
            (should (eq (helixel-sel-kind helixel--pending-sel)
                        'search))))
      (set-register ?a nil))))

(ert-deftest helixel-test-register-search--from-register-backward ()
  "Register-search backward: done-hook sets up backward dir and sel-ctx."
  (let ((helixel--current-register nil)
        helixel--action-ring helixel--live-action helixel--action-pos
        (helixel--active-search nil)
        (helixel--pending-sel nil))
    (unwind-protect
        (progn
          (helixel--register-set ?a "hello")
          (setq helixel--current-register ?a)
          (helixel-test-with-buffer "hello world hello"
            (goto-char (point-max))
            (helixel--tracking-open 'search 'search)
            (helixel--register-consume)
            (let ((helixel-search--had-region nil)
                  (pat "hello"))
              (re-search-backward pat)
              (let ((isearch-success t)
                    (isearch-string pat)
                    (isearch-regexp t)
                    (isearch-forward nil)  ;; backward
                    (isearch-other-end (copy-marker (match-end 0))))
                (helixel-search--done-hook)))
            (should (null helixel--current-register))
            ;; Point at match-beginning (backward search)
            (should (= (point) 13))
            (should (region-active-p))
            ;; Direction
            (should (eq (helixel--last-motion-dir
                         helixel--active-search)
                        'backward))
            (should helixel--pending-sel)))
      (set-register ?a nil))))

(ert-deftest helixel-test-register-search--from-register-word-bound ()
  "Symbol-bound pattern \\_<...\\_> matches via done-hook."
  (let ((helixel--current-register ?a)
        helixel--action-ring helixel--live-action helixel--action-pos
        (helixel--active-search nil)
        (helixel--pending-sel nil))
    (unwind-protect
        (progn
          (helixel--register-set ?a "hello")
          (helixel-test-with-buffer "hello world hello"
            (goto-char 1)
            (helixel--tracking-open 'search 'search)
            (helixel--register-consume)
            (let ((helixel-search--had-region nil)
                  (pat "\\_<hello\\_>"))
              (re-search-forward pat)
              (let ((isearch-success t)
                    (isearch-string pat)
                    (isearch-regexp t)
                    (isearch-forward t)
                    (isearch-other-end
                     (copy-marker (match-beginning 0))))
                (helixel-search--done-hook)))
            (should (= (point) 6))
            (should (region-active-p))
            (should (= (region-beginning) 1))))
      (set-register ?a nil))))

(ert-deftest helixel-test-register-search--register-consume ()
  "Register is consumed after search via done-hook path."
  (let ((helixel--current-register ?a)
        helixel--action-ring helixel--live-action helixel--action-pos
        (helixel--active-search nil)
        (helixel--pending-sel nil))
    (unwind-protect
        (progn
          (helixel--register-set ?a "world")
          (should (helixel--register-active-p))
          (should (eq helixel--current-register ?a))
          (helixel-test-with-buffer "hello world hello"
            (goto-char 1)
            (helixel--tracking-open 'search 'search)
            (helixel--register-consume)
            (let ((helixel-search--had-region nil)
                  (pat "world"))
              (re-search-forward pat)
              (let ((isearch-success t)
                    (isearch-string pat)
                    (isearch-regexp t)
                    (isearch-forward t)
                    (isearch-other-end
                     (copy-marker (match-beginning 0))))
                (helixel-search--done-hook)))
            (should (null helixel--current-register))
            (should (not (helixel--register-active-p)))))
      (set-register ?a nil))))

(ert-deftest helixel-test-register-search--n-repeat-after-register ()
  "n/N repeat works after register-search (helixel-search--search finds next)."
  (let ((helixel--current-register nil)
        helixel--action-ring helixel--live-action helixel--action-pos
        (helixel--active-search nil)
        (helixel--pending-sel nil))
    (unwind-protect
        (progn
          (helixel--register-set ?a "hello")
          (setq helixel--current-register ?a)
          (helixel-test-with-buffer "hello world hello"
            (goto-char 1)
            (helixel--tracking-open 'search 'search)
            (helixel--register-consume)
            (let ((helixel-search--had-region nil)
                  (pat "hello"))
              (re-search-forward pat)
              (let ((isearch-success t)
                    (isearch-string pat)
                    (isearch-regexp t)
                    (isearch-forward t)
                    (isearch-other-end
                     (copy-marker (match-beginning 0))))
                (helixel-search--done-hook)))
            ;; Active search set
            (should helixel--active-search)
            (should (string= (helixel--last-motion-pattern
                              helixel--active-search)
                             "hello"))
            ;; n finds next match (forward)
            (should (helixel-search--search "hello" 'forward nil nil t))
            (should (= (match-beginning 0) 13))))
      (set-register ?a nil))))

(ert-deftest helixel-test-register-search--action-committed-to-ring ()
  "Done-hook after search commits action to ring with search category."
  (let (helixel--action-ring helixel--live-action helixel--action-pos
        (helixel--active-search nil)
        (helixel--pending-sel nil))
    (helixel-test-with-buffer "hello world hello"
      (goto-char 1)
      (helixel--tracking-open 'search 'search)
      (let ((helixel-search--had-region nil))
        (let ((pat "hello"))
          (re-search-forward pat)
          (let ((isearch-success t)
                (isearch-string pat)
                (isearch-regexp t)
                (isearch-forward t)
                (isearch-other-end (copy-marker (match-beginning 0))))
            (helixel-search--done-hook))))
      ;; After done-hook: action committed to ring
      (should helixel--action-ring)
      (should (helixel-action-p (car helixel--action-ring)))
      (should (eq (helixel-action-category (car helixel--action-ring))
                  'search))
      ;; Region active on match
      (should (region-active-p))
      ;; Domain state set
      (should helixel--active-search)
      (should (eq (helixel--last-motion-category helixel--active-search)
                  'search)))))

(provide 'helixel-test-register-search)
;;; helixel-test-register-search.el ends here
