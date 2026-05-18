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
  (let (helixel--action helixel--action-ring helixel--action-pos)
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
        (helixel-action-start 'search 'search)
        (helixel-search--done-hook))
      ;; Verify repeat state
      (should (eq (helixel-repeat-category) 'search))
      (should (string= (helixel--action-get helixel--repeat-data :pattern)
                       "hello"))
      (should (eq (helixel-repeat-dir) 'forward))
      ;; Verify selection context for . repeat
      (let ((sel helixel--repeat-sel-ctx))
        (should sel)
        (should (eq (helixel-sel-get-kind sel) 'search))
        (should (string= (helixel-sel-search-pattern sel) "hello"))
        (should (eq (helixel-sel-search-dir sel) 'forward)))
      ;; Verify region is active on the match
      (should (region-active-p))
      (should (= (region-beginning) 1))
      (should (= (region-end) 6)))))

(ert-deftest helixel-test-search-done-hook-case-sensitive ()
  "helixel-search--done-hook after ?Hello sets case-sensitive repeat."
  (let (helixel--action helixel--action-ring helixel--action-pos)
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
        (helixel-action-start 'search 'search)
        (helixel-search--done-hook))
      ;; Verify repeat preserves case-sensitive pattern
      (should (eq (helixel-repeat-category) 'search))
      (should (string= (helixel--action-get helixel--repeat-data :pattern)
                       "Hello"))
      (should (eq (helixel-repeat-dir) 'backward))
      ;; Verify selection context
      (let ((sel helixel--repeat-sel-ctx))
        (should sel)
        (should (eq (helixel-sel-get-kind sel) 'search))
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
      (should (eq (helixel-repeat-dir) 'backward))
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
      (setq helixel--action '(:dir backward))
      (goto-char 18)
      (helixel-search-repeat-next)
      (should (< (point) 18))
      (should (use-region-p)))))

(ert-deftest helixel-test-search-repeat-next-case-sensitive ()
  "n after case-sensitive search (?Hello) respects case."
  (helixel-test-with-buffer "hello Hello hello"
    (setq helixel--repeat-dir 'backward)
    (helixel-repeat-set 'search :pattern "Hello")
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
    (setq helixel--repeat-dir 'backward)
    (helixel-repeat-set 'search :pattern "hello")
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

;;; Combined search history tests

(ert-deftest helixel-test-history-push-and-cap ()
  "Test history push adds entries and respects max size."
  (let ((helixel--action-ring nil)
        (helixel-action-ring-max 3))
    (helixel-action-commit)  ; null action, does nothing
    (should (null helixel--action-ring))))

(ert-deftest helixel-test-history-display-format ()
  "Test history display formatting with action plists."
  (should (string= (helixel-action-display
                    '(:category search :search (:pattern "hello" :dir forward))) "/hello/"))
  (should (string= (helixel-action-display
                    '(:category search :search (:pattern "hello" :dir backward))) "?hello?"))
  (should (string= (helixel-action-display
                    '(:category find-char :find-char (:type next :char ?x :dir forward))) "f→x"))
  (should (string= (helixel-action-display
                    '(:category find-char :find-char (:type next :char ?x :dir backward))) "F→x"))
  (should (string= (helixel-action-display
                    '(:category find-char :find-char (:type till :char ?x :dir forward))) "t→x"))
  (should (string= (helixel-action-display
                    '(:category find-char :find-char (:type till :char ?x :dir backward))) "T→x")))

(ert-deftest helixel-test-history-find-pushes ()
  "Test that find-char operations push to the action ring."
  (let ((helixel--action-ring nil)
        (helixel--action nil)
        (helixel--action-pos nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (setq last-command nil this-command 'helixel-find-next-char)
      (helixel-find-next-char ?x)
      (should (eq (plist-get (car helixel--action-ring) :category) 'find-char))
      (should (eq (helixel--action-cat-get (car helixel--action-ring) :type) 'next))
      (should (eq (helixel--action-cat-get (car helixel--action-ring) :char) ?x)))))

(ert-deftest helixel-test-history-from-history-find-next ()
  "Test C-u n selecting a find-char next entry replays it correctly."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type next :char ?b :dir forward) :display t)))
        (helixel--action nil)
        
        (helixel--clear-highlights-called nil))
    (helixel-test-with-buffer "axb axb axb"
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring))))
                ((symbol-function 'helixel--clear-highlights)
                 (lambda () (setq helixel--clear-highlights-called t))))
        (helixel-search--from-history t))
      (should (eq (helixel--live-cat-get :dir) 'forward))
      (should (eql (point) 4))
      (should helixel--clear-highlights-called))))

(ert-deftest helixel-test-history-from-history-find-till ()
  "Test C-u n selecting a find-char till entry replays with till semantics."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type till :char ?b :dir forward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search--from-history t))
      (should (eql (point) 3))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search--from-history t))
      (should (eql (point) 7)))))

(ert-deftest helixel-test-history-from-history-direction-backward ()
  "Test selecting a backward find-char entry with forwardp=t (use stored dir)."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type next :char ?b :dir backward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 8)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search--from-history t))
      (should (eq (helixel--live-cat-get :dir) 'backward))
      (should (eql (point) 7)))))

(ert-deftest helixel-test-history-repeat-next-with-arg ()
  "Test helixel-search-repeat-next with prefix arg calls from-history."
  (let ((helixel--action-ring '((:category search :subcat search
                              :search (:pattern "test" :dir forward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "a test b"
      (goto-char 3)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search-repeat-next t))
      (should (>= (point) 4)))))

(ert-deftest helixel-test-history-repeat-prev-with-arg-find ()
  "Test C-u N toggles direction and picks a find-char entry from history."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type next :char ?b :dir forward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 8)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search-repeat-reverse t))
      (should (eq (helixel--live-cat-get :dir) 'backward))
      (should (eql (point) 7))
      (helixel-search-repeat-next)
      (should (eq (helixel--live-cat-get :dir) 'backward))
      (should (< (point) 7)))))

(ert-deftest helixel-test-history-repeat-prev-with-arg-search ()
  "Test C-u N with a regexp search entry: toggles direction, searches backward."
  (let ((helixel--action-ring '((:category search :subcat search
                              :search (:pattern "hello" :dir forward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "hello world hello world"
      (goto-char 20)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search-repeat-reverse t))
      (should (eq (helixel--live-cat-get :dir) 'backward))
      (should (<= (point) 13)))))

(ert-deftest helixel-test-history-sync-direction-c-u-N ()
  "Test C-u N flips the direction of the front history entry."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type next :char ?b :dir forward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 5)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search-repeat-reverse t))
      (should (eq (helixel--live-cat-get :dir) 'backward))
      (should (eq (helixel--action-cat-get (car helixel--action-ring) :dir) 'backward)))))

(ert-deftest helixel-test-history-sync-direction-N ()
  "Test N (no prefix) flips the direction of the front history entry."
  (let ((helixel--action nil)
        (helixel--action-ring nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 5)
      (setq last-command 'helixel-find-next-char this-command 'helixel-find-next-char)
      (helixel-find-next-char ?b)
      (setq last-command 'helixel-find-next-char this-command 'helixel-search-repeat-reverse)
      (helixel-search-repeat-reverse)
      (should (eq (helixel--live-cat-get :dir) 'backward))
      (should (eq (helixel--action-cat-get (car helixel--action-ring) :dir) 'backward)))))

(ert-deftest helixel-test-history-no-sync-c-u-n ()
  "Test C-u n does NOT flip the front entry direction."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type next :char ?b :dir forward) :display t)))
        (helixel--action nil)
        )
    (helixel-test-with-buffer "axb axb axb"
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search-repeat-next t))
      (should (eq (helixel--live-cat-get :dir) 'forward))
      (should (eq (helixel--action-cat-get (car helixel--action-ring) :dir) 'forward)))))

;;; Repeat recency tests

(ert-deftest helixel-test-repeat-find-after-movement ()
  "Test n repeats find-char after intervening movement."
  (helixel-test-with-buffer "axb axb axb"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-find-next-char)
    (helixel-find-next-char ?b)
    (should (eql (point) 4))
    ;; intervening movement pushes find-char to ring
    (setq last-command 'helixel-find-next-char this-command 'helixel-forward-char)
    (helixel-forward-char)
    (should (eq (plist-get (car helixel--action-ring) :category) 'find-char))
    ;; n should still repeat find-char (set :type on live action)
    (setq last-command 'helixel-forward-char this-command 'helixel-search-repeat-next)
    (helixel-search-repeat-next)
    (should (helixel--live-cat-get :type))))

(ert-deftest helixel-test-repeat-search-over-find ()
  "Test n picks search over older find-char in ring (detection only)."
  (let ((helixel--action-ring
         '((:category search :subcat search :search (:pattern "hello" :dir forward) :display t)
           (:category find-char :subcat find-char :find-char (:type next :char ?b :dir forward))))
        (helixel--action nil)
        (helixel--action-pos nil))
    (helixel-test-with-buffer "hello world"
      ;; call n — it should go to isearch-repeat (not find-char),
      ;; so helixel--action should NOT get :type from find-char-core
      (condition-case nil
          (helixel-search-repeat-next)
        (error nil))
      ;; verify no find-char data was set on live action
      (should (null (helixel--live-cat-get :type))))))

(ert-deftest helixel-test-repeat-no-search-repeat-wrap ()
  "Test n/N do not push search/repeat wrapper actions into ring."
  (let ((helixel--action nil) (helixel--action-ring nil) (helixel--action-pos nil))
    (helixel-test-with-buffer "axb axb axb"
      (setq last-command nil this-command 'helixel-find-next-char)
      (helixel-find-next-char ?b)
      (setq last-command 'helixel-find-next-char this-command 'helixel-search-repeat-next)
      (helixel-search-repeat-next)
      (helixel-search-repeat-next)
      ;; check: no search/repeat entries without :pattern in ring
      (let ((sr (cl-find-if (lambda (a)
                              (and (eq (helixel--action-get a :category) 'search)
                                   (null (helixel--action-cat-get a :pattern))))
                            helixel--action-ring)))
        (should (null sr))))))

(ert-deftest helixel-test-action-cycle-skip-meaningless ()
  "Test ; does not push meaningless live action into ring."
  (let ((helixel--action '(:category search :subcat repeat :dir forward))
        (helixel--action-ring `((:category movement :subcat char :marker ,(point-marker))))
        (helixel--action-pos nil))
    (let ((len-before (length helixel--action-ring)))
      (helixel-action-cycle)
      (should (= (length helixel--action-ring) len-before))
      (should (null helixel--action))
      (should (eq helixel--action-pos 0)))))

(ert-deftest helixel-test-history-from-history-sets-find-char-category ()
  "Test C-u N replaying find-char sets :category to find-char."
  (let ((helixel--action-ring '((:category find-char :subcat find-char
                              :find-char (:type next :char ?b :dir forward) :display t)))
        (helixel--action '(:category search :subcat repeat :dir forward))
        )
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 5)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search--from-history t))
      (should (eq (helixel--live-get :category) 'find-char))
      (should (eq (helixel--live-cat-get :type) 'next))
      (should (eq (helixel--live-cat-get :char) ?b)))))

;;; helixel-test-search.el ends here
