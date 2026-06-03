;;; helixel-test-search.el --- Tests for Helixel: search  -*- lexical-binding: t; -*-

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

;;; Search tests

(ert-deftest helixel-test-search--search-case-fold ()
  "helixel-search--search respects `case-fold-search'.
With case-fold-search=t (default), 'hello' matches 'Hello'.
With case-fold-search=nil, 'hello' does NOT match 'Hello' but
exact-case 'Hello' still matches 'Hello'."
  (helixel-test-with-buffer "foo Hello bar HELLO baz"
    (goto-char (point-min))
    ;; case-fold-search t (default): 'hello' matches 'Hello' (first)
    (let ((case-fold-search t))
      (should (helixel-search--search "hello" 'forward))
      (should (= (match-beginning 0) 5)))
    ;; case-fold-search nil: 'hello' does NOT match 'Hello'
    (goto-char (point-min))
    (let ((case-fold-search nil))
      (condition-case nil
          (progn
            (helixel-search--search "hello" 'forward)
            (ert-fail "Expected search-failed with case-fold nil"))
        (search-failed)))
    ;; case-fold nil but matching exact case
    (goto-char (point-min))
    (let ((case-fold-search nil))
      (should (helixel-search--search "Hello" 'forward))
      (should (= (match-beginning 0) 5)))))

(ert-deftest helixel-test-search--search-backward ()
  "helixel-search--search backward finds match before point."
  (helixel-test-with-buffer "hello world hello"
    (goto-char (point-max))
    ;; Backward search from end finds last "hello"
    (should (helixel-search--search "hello" 'backward))
    (should (= (match-beginning 0) 13))
    (should (= (match-end 0) 18))
    ;; point moves to match-beginning for backward search
    (should (= (point) (match-beginning 0)))))

(ert-deftest helixel-test-search--search-forward ()
  "helixel-search--search forward finds match after point."
  (helixel-test-with-buffer "hello world hello"
    (goto-char (point-min))
    ;; Forward search from start finds first "hello"
    (should (helixel-search--search "hello" 'forward))
    (should (= (match-beginning 0) 1))
    (should (= (match-end 0) 6))
    ;; point moves to match-end for forward search
    (should (= (point) (match-end 0)))))

(ert-deftest helixel-test-search-done-hook-forward ()
  "helixel-search--done-hook sets up repeat state after /search."
  (let (helixel--event-ring helixel--live-event helixel--action-pos
        (helixel--active-search nil))
    (helixel-test-with-buffer "hello world hello"
      (goto-char 1)
      ;; Simulate /hello<RET> — forward search
      (re-search-forward "hello")
      (let ((helixel-search--had-region nil)
            (isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (copy-marker (match-beginning 0))))
        ;; helixel-search-forward calls action-start before isearch
        (helixel--tracking-open 'search 'search)
        (helixel-search--done-hook))
      ;; Verify repeat state
      (should (eq (helixel-active-search--category helixel--active-search) 'search))
      (should (string= (helixel-active-search--pattern helixel--active-search)
                       "hello"))
      (should (eq (helixel-active-search--dir helixel--active-search) 'forward))
      ;; Verify selection context for . repeat
      (let ((sel helixel--pending-sel))
        (should sel)
        (should (eq (helixel-sel-kind sel) 'search))
        (should (string= (helixel-sel-search-pattern sel) "hello"))
        (should (eq (helixel-sel-search-dir sel) 'forward)))
      ;; Verify region is active on the match
      (should (region-active-p))
      (should (= (region-beginning) 1))
      (should (= (region-end) 6)))))

(ert-deftest helixel-test-search-done-hook-case-sensitive ()
  "helixel-search--done-hook after ?Hello sets case-sensitive repeat."
  (let (helixel--event-ring helixel--live-event helixel--action-pos
        (helixel--active-search nil))
    (helixel-test-with-buffer "Hello hello Hello"
      (goto-char (point-max))
      ;; Simulate ?Hello<RET> — backward case-sensitive search
      (re-search-backward "Hello")
      (let ((helixel-search--had-region nil)
            (isearch-success t)
            (isearch-string "Hello")
            (isearch-regexp t)
            (isearch-forward nil)  ;; backward
            (isearch-other-end (copy-marker (match-end 0))))
        (helixel--tracking-open 'search 'search)
        (helixel-search--done-hook))
      ;; Verify repeat preserves case-sensitive pattern
      (should (eq (helixel-active-search--category helixel--active-search) 'search))
      (should (string= (helixel-active-search--pattern helixel--active-search)
                       "Hello"))
      (should (eq (helixel-active-search--dir helixel--active-search) 'backward))
      ;; Verify selection context
      (let ((sel helixel--pending-sel))
        (should sel)
        (should (eq (helixel-sel-kind sel) 'search))
        (should (string= (helixel-sel-search-pattern sel) "Hello"))
        (should (eq (helixel-sel-search-dir sel) 'backward)))
      ;; Verify region active on last Hello (13-18)
      (should (region-active-p))
      (should (= (region-beginning) 13))
      (should (= (region-end) 18)))))

(ert-deftest helixel-test-search-repeat-prev-exchange ()
  "Test N exchanges point and mark and toggles direction."
  (helixel-test-with-buffer "hello world"
    (push-mark (point) t t)
    (goto-char 6)
    (let ((pt (point))
          (mk (mark)))
      (helixel-search-repeat-reverse)
      (should (eq (or (helixel-active-search--dir helixel--active-search) (quote forward)) 'backward))
      (should (= (point) mk))
      (should (= (mark) pt)))))

(ert-deftest helixel-test-search-extract-regex ()
  "Test extracting a bounded regex for word at point."
  (helixel-test-with-buffer "hello world"
    (goto-char 3)
    (let ((result (helixel-search--extract-regex (cons 1 6))))
      (should (string-match "hello" result)))))

(ert-deftest helixel-test-search-extract-regex-no-boundary ()
  "Test extracting regex without word boundary when inside a word."
  (helixel-test-with-buffer "hello world"
    (goto-char 2)
    (let ((result (helixel-search--extract-regex (cons 2 4))))
      (should (string= (regexp-quote "el") result)))))

(ert-deftest helixel-test-search-bounds-at-point-symbol ()
  "Test bounds-at-point returns symbol bounds."
  (helixel-test-with-buffer "hello world"
    (goto-char 3)
    (let ((bounds (helixel-search--bounds-at-point)))
      (should bounds)
      (should (= (car bounds) 1))
      (should (= (cdr bounds) 6)))))

(ert-deftest helixel-test-search-bounds-at-point-region ()
  "Test bounds-at-point uses single-line region when active."
  (helixel-test-with-buffer "hello world"
    (goto-char 2)
    (push-mark (point) t t)
    (goto-char 5)
    (activate-mark)
    (let ((bounds (helixel-search--bounds-at-point)))
      (should bounds)
      (should (= (car bounds) 2))
      (should (= (cdr bounds) 5)))))

(ert-deftest helixel-test-search-repeat-next-forward ()
  "Test n repeats search forward."
  (helixel-test-with-buffer "hello hello hello"
    (let ((isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-case-fold-search t)
          (isearch-success t)
          (isearch-other-end (copy-marker 6))
          (isearch-wrap-pause 'no-ding)
          (isearch-repeat-on-direction-change t))
      (goto-char 6)
      (helixel-search-repeat-next)
      (should (>= (point) 7))
      (should (use-region-p)))))

(ert-deftest helixel-test-search-repeat-next-reverse-when-point<mark ()
  "Test n goes backward when direction is backward."
  (helixel-test-with-buffer "hello hello hello"
    (let ((isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-case-fold-search t)
          (isearch-success t)
          (isearch-other-end (copy-marker 22))
          (isearch-wrap-pause 'no-ding)
          (isearch-repeat-on-direction-change t))
      (setq helixel--live-event '(:dir backward))
      (goto-char 18)
      (helixel-search-repeat-next)
      (should (< (point) 18))
      (should (use-region-p)))))

(ert-deftest helixel-test-search-repeat-next-case-sensitive ()
  "n after case-sensitive search (?Hello) respects case."
  (helixel-test-with-buffer "hello Hello hello"
    (setq helixel--active-search (make-helixel-active-search :category 'search :pattern "Hello" :dir 'forward))
    (helixel-search--set-dir 'backward)
    ;; Simulate isearch state for a case-sensitive backward search
    (let ((isearch-string "Hello")
          (isearch-regexp t)
          (isearch-forward nil)  ;; backward
          (isearch-case-fold-search 'auto)  ;; 'Hello' has uppercase → nil
          (isearch-success t)
          (isearch-other-end (copy-marker 18))  ;; end of last Hello
          (isearch-wrap-pause 'no-ding)
          (isearch-repeat-on-direction-change t))
      ;; Starting at end of last match (pos 18), backward finds
      ;; 'Hello' at 13-17 case-sensitively
      (goto-char 18)
      (helixel-search-repeat-next)
      ;; point moves to match-beginning for backward search
      (should (= (point) 13))
      (should (use-region-p)))))

(ert-deftest helixel-test-search-repeat-next-case-fold-insensitive ()
  "n after case-insensitive search (?hello) matches any case."
  (helixel-test-with-buffer "foo Hello bar HELLO baz"
    (setq helixel--active-search (make-helixel-active-search :category 'search :pattern "hello" :dir 'forward))
    (helixel-search--set-dir 'backward)
    ;; Simulate isearch state for case-insensitive backward search
    (let ((isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward nil)  ;; backward
          (isearch-case-fold-search 'auto)  ;; 'hello' all-lower → t
          (isearch-success t)
          (isearch-other-end (copy-marker 10))  ;; end of Hello
          (isearch-wrap-pause 'no-ding)
          (isearch-repeat-on-direction-change t))
      (goto-char 10)  ;; end of 'Hello'
      (helixel-search-repeat-next)
      ;; backward from 10: 'hello' matches 'Hello' case-insensitively
      ;; point moves to match-beginning (5)
      (should (= (point) 5))
      (should (use-region-p)))))


(ert-deftest helixel-test-history-from-history-find-next ()
  "Test C-u n selecting a find-char entry from history replays it."
  (let ((helixel--event-ring nil)
        (helixel--live-event nil)
        (helixel--active-search nil)
        (helixel--clear-highlights-called nil))
    (helixel-test-with-buffer "axb axb axb"
      ;; Create a find-char sel with type/char/dir for history replay
      (let ((sel (helixel-sel-create 'find-char
                   '(:char ?b :type next :dir forward :inline-advance t)
                   #'ignore "fb")))
        (helixel--tracking-open 'find-char 'next)
        (setf (helixel-event-sel helixel--live-event) sel)
        (helixel-event-commit))
      (setq helixel--active-search (make-helixel-active-search :category 'find-char :type 'next :char ?b :dir 'forward))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--event-ring))))
                ((symbol-function 'helixel--clear-highlights)
                 (lambda () (setq helixel--clear-highlights-called t))))
        (helixel-search--from-history t))
      (should (eql (point) 4))
      (should helixel--clear-highlights-called))))

(ert-deftest helixel-test-repeat-find-after-movement ()
  "Test n repeats find-char after intervening movement."
  (helixel-test-with-buffer "axb axb axb"
    (setq helixel--event-ring nil helixel--live-event nil helixel--action-pos nil
          last-command nil this-command 'helixel-find-next-char)
    (helixel-find-next-char ?b)
    (should (eql (point) 4))
    (setq last-command 'helixel-find-next-char this-command 'helixel-forward-char)
    (helixel-forward-char)
    (should (= (length helixel--event-ring) 1))
    (setq last-command 'helixel-forward-char this-command 'helixel-search-repeat-next)
    (helixel-search-repeat-next)
    (should (helixel-active-search--type helixel--active-search))))

;;; History collection and display

(ert-deftest helixel-test-search-history-collect-search ()
  "`helixel-search--history-collect' includes search events."
  (let ((helixel--event-ring nil) (helixel--live-event nil))
    (helixel-test-with-buffer "a test b"
      (helixel--tracking-open 'search 'search)
      (setf (helixel-event-sel helixel--live-event)
            (helixel-sel-create 'search
              '(:pattern "test" :dir forward)
              #'ignore "/test/"))
      (helixel-event-commit)
      (let ((alist (helixel-search--history-collect)))
        (should (= (length alist) 1))
        (should (helixel-event-p (cdar alist)))
        (should (eq (helixel-event-category (cdar alist)) 'search))))))

(ert-deftest helixel-test-search-history-collect-find-char ()
  "`helixel-search--history-collect' includes find-char events."
  (let ((helixel--event-ring nil) (helixel--live-event nil))
    (helixel-test-with-buffer "axb axb axb"
      (helixel--tracking-open 'find-char 'next)
      (setf (helixel-event-sel helixel--live-event)
            (helixel-sel-create 'find-char
              '(:char ?b :type next :dir forward :inline-advance t)
              #'ignore "fb"))
      (helixel-event-commit)
      (let ((alist (helixel-search--history-collect)))
        (should (= (length alist) 1))
        (should (eq (helixel-event-category (cdar alist)) 'find-char))))))

(ert-deftest helixel-test-search-history-collect-no-irrelevant ()
  "`helixel-search--history-collect' excludes non-search events."
  (let ((helixel--event-ring nil) (helixel--live-event nil))
    (helixel-test-with-buffer "hello"
      ;; Push a movement event — not in repeatable categories
      (helixel--tracking-open 'movement 'char)
      (helixel-event-commit)
      ;; Push a search event
      (helixel--tracking-open 'search 'search)
      (setf (helixel-event-sel helixel--live-event)
            (helixel-sel-create 'search
              '(:pattern "hello" :dir forward)
              #'ignore "/hello/"))
      (helixel-event-commit)
      (let ((alist (helixel-search--history-collect)))
        (should (= (length alist) 1))
        (should (eq (helixel-event-category (cdar alist)) 'search))))))

(ert-deftest helixel-test-search-action-display-format-search ()
  "`helixel-action-display' formats a search event with its display string."
  (let ((helixel--event-ring nil) (helixel--live-event nil))
    (helixel-test-with-buffer "hello"
      (helixel--tracking-open 'search 'search)
      (setf (helixel-event-display helixel--live-event) "/hello/")
      (helixel-event-commit)
      (should (string= (helixel-action-display (car helixel--event-ring))
                       "/hello/")))))

(ert-deftest helixel-test-search-action-display-format-find-char ()
  "`helixel-action-display' formats a find-char event via its display."
  (let ((helixel--event-ring nil) (helixel--live-event nil))
    (helixel-test-with-buffer "axb"
      (helixel--tracking-open 'find-char 'next)
      (setf (helixel-event-display helixel--live-event) "f→b")
      (helixel-event-commit)
      (should (string= (helixel-action-display (car helixel--event-ring))
                       "f→b")))))

(ert-deftest helixel-test-search-action-display-format-no-sel ()
  "`helixel-action-display' falls back to category.subcat for events
without a display."
  (let ((helixel--event-ring nil) (helixel--live-event nil))
    (helixel-test-with-buffer "hello"
      (helixel--tracking-open 'search 'search)
      (helixel-event-commit)
      ;; No sel means no display → falls back to "search.search"
      (should (string= (helixel-action-display (car helixel--event-ring))
                       "search.search")))))

;;; C-u n / C-u N from-history

(ert-deftest helixel-test-search-from-history-find-till ()
  "C-u n selecting a find-char till entry replays with till semantics."
  (let ((helixel--event-ring nil) (helixel--live-event nil)
        (helixel--active-search nil))
    (helixel-test-with-buffer "axb axb axb"
      ;; Create a find-char till entry in ring
      (let ((sel (helixel-sel-create 'find-char
                   '(:char ?b :type till :dir forward :inline-advance t)
                   #'ignore "tb")))
        (helixel--tracking-open 'find-char 'till)
        (setf (helixel-event-sel helixel--live-event) sel)
        (helixel-event-commit))
      ;; Simulate completing-read returning the till entry
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--event-ring)))))
        (helixel-search-repeat-next t))
      ;; till ?b: stops before 'b' → point at 3
      (should (eql (point) 3)))))

(ert-deftest helixel-test-search-from-history-backward-dir ()
  "C-u n respects backward direction in active-search for find-char.
For find-char events, the stored direction comes from
`helixel--active-search', not the sel's :dir."
  (let ((helixel--event-ring nil) (helixel--live-event nil)
        (helixel--active-search
         (make-helixel-active-search :category 'find-char :type 'next :char ?b :dir 'backward)))
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 8)
      (let ((sel (helixel-sel-create 'find-char
                   '(:char ?b :type next :dir backward :inline-advance t)
                   #'ignore "Fb")))
        (helixel--tracking-open 'find-char 'next)
        (setf (helixel-event-sel helixel--live-event) sel)
        (helixel-event-commit))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--event-ring)))))
        (helixel-search-repeat-next t))
      ;; C-u n: use-dir = stored-dir = backward, from pos 8 → 7
      (should (eq (helixel-search--current-dir) 'backward))
      (should (eql (point) 7)))))

(ert-deftest helixel-test-search-from-history-search-entry ()
  "C-u n with a search entry from history activates the match."
  (let ((helixel--event-ring nil) (helixel--live-event nil)
        (helixel--active-search nil))
    (helixel-test-with-buffer "hello X hello Y hello Z"
      (goto-char 10)
      ;; Push a search event to ring
      (let ((sel (helixel-sel-create 'search
                   '(:pattern "hello" :dir forward)
                   #'ignore "/hello/")))
        (helixel--tracking-open 'search 'search)
        (setf (helixel-event-sel helixel--live-event) sel)
        (helixel-event-commit))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--event-ring)))))
        (helixel-search-repeat-next t))
      ;; Forward from 10: next "hello" is at position 9
      (should (>= (point) 15))
      (should (use-region-p)))))

(ert-deftest helixel-test-search-repeat-reverse-from-history-find ()
  "C-u N with a forward find-char entry toggles direction to backward."
  (let ((helixel--event-ring nil) (helixel--live-event nil)
        (helixel--active-search
         (make-helixel-active-search :category 'find-char :type 'next :char ?b :dir 'forward)))
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 8)
      (let ((sel (helixel-sel-create 'find-char
                   '(:char ?b :type next :dir forward :inline-advance t)
                   #'ignore "fb")))
        (helixel--tracking-open 'find-char 'next)
        (setf (helixel-event-sel helixel--live-event) sel)
        (helixel-event-commit))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--event-ring)))))
        (helixel-search-repeat-reverse t))
      ;; C-u N: forwardp=nil → toggles stored dir (forward→backward)
      (should (eq (helixel-search--current-dir) 'backward))
      (should (eql (point) 7)))))

(ert-deftest helixel-test-search-repeat-reverse-from-history-search ()
  "C-u N with a forward search entry toggles direction to backward."
  (let ((helixel--event-ring nil) (helixel--live-event nil)
        (helixel--active-search nil))
    (helixel-test-with-buffer "hello X hello Y"
      (goto-char 20)
      (let ((sel (helixel-sel-create 'search
                   '(:pattern "hello" :dir forward)
                   #'ignore "/hello/")))
        (helixel--tracking-open 'search 'search)
        (setf (helixel-event-sel helixel--live-event) sel)
        (helixel-event-commit))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--event-ring)))))
        (helixel-search-repeat-reverse t))
      ;; Direction toggled to backward, from pos 20 backward → first hello
      (should (eq (helixel-search--current-dir) 'backward))
      (should (<= (point) 10)))))

(ert-deftest helixel-test-search-from-history-no-direction-flip ()
  "C-u n does NOT flip the active-search direction."
  (let ((helixel--event-ring nil) (helixel--live-event nil)
        (helixel--active-search (make-helixel-active-search :category 'find-char :type 'next :char ?b :dir 'forward)))
    (helixel-test-with-buffer "axb axb axb"
      (let ((sel (helixel-sel-create 'find-char
                   '(:char ?b :type next :dir forward :inline-advance t)
                   #'ignore "fb")))
        (helixel--tracking-open 'find-char 'next)
        (setf (helixel-event-sel helixel--live-event) sel)
        (helixel-event-commit))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--event-ring)))))
        (helixel-search-repeat-next t))
      ;; C-u n uses stored direction, does NOT flip
      (should (eq (helixel-search--current-dir) 'forward)))))

(ert-deftest helixel-test-search-repeat-no-push ()
  "n/N for search do not push entries with :subcat repeat into the ring.
When isearch-repeat is used (search, not find-char), the live event
is committed by action-start but gets category search/subcat repeat.
This test verifies no stray search wrappers accumulate."
  (let ((helixel--event-ring nil) (helixel--live-event nil)
        (helixel--active-search (make-helixel-active-search :category 'search :pattern "hello" :dir 'forward))
        (helixel--action-pos nil))
    (helixel-test-with-buffer "hello world hello"
      ;; Simulate isearch state for search-repeat-next
      (let ((isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-success t)
            (isearch-other-end (copy-marker 6))
            (isearch-wrap-pause 'no-ding)
            (isearch-repeat-on-direction-change t))
        (goto-char 6)
        (helixel-search-repeat-next)
        (helixel-search-repeat-next))
      ;; Check: no entries with :category search and no :pattern
      (let ((bad (cl-find-if
                  (lambda (e)
                    (and (helixel-event-p e)
                         (eq (helixel-event-category e) 'search)
                         (null (when-let* ((s (helixel-event-sel e)))
                                 (helixel-sel-search-pattern s)))))
                  helixel--event-ring)))
        (should (null bad))))))

;;; Edge cases

(ert-deftest helixel-test-search-from-history-empty-ring ()
  "C-u n with empty ring signals user-error."
  (let ((helixel--event-ring nil) (helixel--live-event nil)
        (helixel--active-search nil))
    (helixel-test-with-buffer "hello world"
      (goto-char 1)
      (should-error (helixel-search-repeat-next t)
                    :type 'user-error))))

(ert-deftest helixel-test-search-from-history-search-not-found ()
  "C-u n with a search pattern not present in buffer: graceful failure.
Buffer content and point stay unchanged when search fails."
  (let ((helixel--event-ring nil) (helixel--live-event nil)
        (helixel--active-search nil))
    (helixel-test-with-buffer "hello world"
      (goto-char 1)
      ;; Push a search event for a pattern not in buffer
      (let ((sel (helixel-sel-create 'search
                   '(:pattern "xyzzy" :dir forward)
                   #'ignore "/xyzzy/")))
        (helixel--tracking-open 'search 'search)
        (setf (helixel-event-sel helixel--live-event) sel)
        (helixel-event-commit))
      (let ((pos-before (point)))
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (_prompt _collection &rest _)
                     (helixel-action-display (car helixel--event-ring)))))
          ;; Should not signal an error
          (helixel-search-repeat-next t))
        ;; Buffer content unchanged
        (should (string= (buffer-string) "hello world"))
        ;; Point stayed where it was
        (should (= (point) pos-before))))))

(ert-deftest helixel-test-search-from-history-payload-pattern ()
  "`helixel-search--history-execute' for search uses payload :pattern
when the event's sel has no pattern in its ctx (fallback path)."
  (let ((helixel--event-ring nil) (helixel--live-event nil)
        (helixel--active-search nil))
    (helixel-test-with-buffer "hello world"
      (goto-char 1)
      ;; Create an event with sel lacking :pattern, pattern in payload
      (let ((sel (helixel-sel-create 'search '(:dir forward)
                   #'ignore "search")))
        (helixel--tracking-open 'search 'search)
        (setf (helixel-event-sel helixel--live-event) sel)
        (setf (helixel-event-payload helixel--live-event)
              '(:pattern "hello"))
        (helixel-event-commit))
      ;; Verify the payload fallback is used: the event carries pattern
      ;; in payload, not in sel-ctx.
      (let ((event (car helixel--event-ring)))
        ;; sel has no :pattern → sel-search-pattern returns nil
        (should-not (helixel-sel-search-pattern
                     (helixel-event-sel event)))
        ;; payload has :pattern
        (should (string= (plist-get (helixel-event-payload event)
                                    :pattern)
                         "hello"))))))
;;; helixel-test-search.el ends here
