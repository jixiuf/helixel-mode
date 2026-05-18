;;; helixel-test-action.el --- Tests for Helixel: action tracking and command execution  -*- lexical-binding: t; -*-

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

;;; Action tracking tests

(ert-deftest helixel-test-action-start-movement ()
  "Test movement commands create and continue actions."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-next-line)
    (helixel-next-line)
    (should helixel--action)
    (should (eq (helixel--live-get :category) 'movement))
    (should (eq (helixel--live-get :subcat) 'line))
    (should (null helixel--action-pos))
    (let ((mark-pos (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-next-line this-command 'helixel-next-line)
      (helixel-next-line)
      (should (eq (helixel--live-get :category) 'movement))
      (should (eq (helixel--live-get :subcat) 'line)))))

(ert-deftest helixel-test-action-category-mismatch ()
  "Test different categories push old action to ring."
  (helixel-test-with-buffer "axb axb axb"
    (setq helixel--action nil helixel--action-ring nil
          last-command nil this-command 'helixel-find-next-char)
    (helixel-find-next-char ?b)
    (should (eq (helixel--live-get :category) 'find-char))
    (let ((mark1 (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-find-next-char this-command 'helixel-forward-char)
      (helixel-forward-char)
      (should (eq (helixel--live-get :category) 'movement))
      (should (eq (helixel--live-get :subcat) 'char))
      (should (not (eq (marker-position (helixel--live-get :marker)) mark1)))
      (should (= (length helixel--action-ring) 1))
      (should (eq (plist-get (car helixel--action-ring) :category) 'find-char)))))

(ert-deftest helixel-test-action-movement-different-subcat ()
  "Test different movement subcats push to ring."
  (helixel-test-with-buffer "hello\nworld\nagain"
    (setq helixel--action nil helixel--action-ring nil
          last-command nil this-command 'helixel-forward-char)
    (helixel-forward-char)
    (should (eq (helixel--live-get :subcat) 'char))
    (setq last-command 'helixel-forward-char this-command 'helixel-next-line)
    (helixel-next-line)
    (should (eq (helixel--live-get :subcat) 'line))
    (should (= (length helixel--action-ring) 1))))

(ert-deftest helixel-test-action-cycle-live ()
  "Test ; pushes live action to ring and shows ring[0]."
  (helixel-test-with-buffer "hello world again"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-forward-char)
    (goto-char 1)
    (helixel-forward-char)
    (setq last-command 'helixel-forward-char this-command 'helixel-forward-char)
    (helixel-forward-char)
    (helixel-action-cycle)
    (should (null helixel--action))
    (should (= (length helixel--action-ring) 2))
    (should (= helixel--action-pos 1))
    (should (= (region-beginning) 1))))

(ert-deftest helixel-test-action-cycle-ring ()
  "Test ; cycles through action ring."
  (helixel-test-with-buffer "hello\nworld\nagain"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-forward-char)
    (goto-char 1)
    (helixel-forward-char)
    (let ((mark1 (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-forward-char this-command 'helixel-next-line)
      (goto-char 5)
      (helixel-next-line)  ; line subcat differs → push old
      (should (= (length helixel--action-ring) 1))
      (helixel-action-cycle)
      (should (eq helixel--action-pos 0))
      (should (use-region-p)))))

(ert-deftest helixel-test-action-goto-continues ()
  "Test goto commands share the same action."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (setq helixel--action nil helixel--action-ring nil
          last-command nil this-command 'helixel-go-beginning-line)
    (helixel-go-beginning-line)
    (should (eq (helixel--live-get :category) 'movement))
    (should (eq (helixel--live-get :subcat) 'goto))))

(ert-deftest helixel-test-action-select-continues ()
  "Test select commands share the same action."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (setq helixel--action nil helixel--action-ring nil
          last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (should (eq (helixel--live-get :subcat) 'lineselect))))

(ert-deftest helixel-test-action-no-session-error ()
  "Test action-cycle with no sessions shows message."
  (let ((helixel--action nil) (helixel--action-ring nil) (helixel--action-pos nil))
    (helixel-action-cycle)
    t))  ; just verify no error

(ert-deftest helixel-test-action-cycle-forward ()
  "Test C-u ; cycles forward through saved actions."
  (helixel-test-with-buffer "hello\nworld\nagain"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-forward-char)
    (helixel-forward-char)
    (setq last-command 'helixel-forward-char this-command 'helixel-next-line)
    (goto-char 5)
    (helixel-next-line)
    (helixel-action-cycle)
    (should (eq helixel--action-pos 0))
    (should (= (region-beginning) 5))
    (helixel-action-cycle)
    (should (eq helixel--action-pos 1))
    (helixel-action-cycle t)
    (should (eq helixel--action-pos 0))))

(ert-deftest helixel-test-action-same-subcat-continues ()
  "Test same subcat movements continue action (word start→word end)."
  (helixel-test-with-buffer "hello world test"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-forward-word-start)
    (helixel-forward-word-start)
    (should (eq (helixel--live-get :subcat) 'word))
    (let ((mark-pos (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-forward-word-start this-command 'helixel-forward-word-end)
      (helixel-forward-word-end)
      (should (eq (helixel--live-get :subcat) 'word)))))

(ert-deftest helixel-test-action-different-subcat-breaks ()
  "Test different subcat pushes old action to ring."
  (helixel-test-with-buffer "hello world\ntest line"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-forward-word-start)
    (helixel-forward-word-start)
    (should (eq (helixel--live-get :subcat) 'word))
    (let ((word-mark (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-forward-word-start this-command 'helixel-next-line)
      (helixel-next-line)
      (should (eq (helixel--live-get :subcat) 'line))
      (should (= (length helixel--action-ring) 1)))))

(ert-deftest helixel-test-action-goto-marker ()
  "Test goto commands record correct marker position."
  (helixel-test-with-buffer "line1\nline2\nline3"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-go-beginning-buffer)
    (goto-char 10)
    (helixel-go-beginning-buffer)
    (should helixel--action)
    (should (eq (helixel--live-get :subcat) 'goto))
    (should (= (marker-position (helixel--live-get :marker)) 10))))

(ert-deftest helixel-test-action-wrapper-commands ()
  "Test goto-line starts action correctly."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\nline5"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-goto-line)
    (goto-char 1)
    (helixel-goto-line 3)
    (should helixel--action)
    (should (eq (helixel--live-get :subcat) 'goto))))

(ert-deftest helixel-test-goto-line-lisp-arg ()
  "Test helixel-goto-line called from Lisp uses the arg parameter, not current-prefix-arg.
Regression: the refactored macro version referenced current-prefix-arg
in the branch where arg was non-nil, which is nil in Lisp calls."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\nline5"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-goto-line
          current-prefix-arg nil)
    (helixel-goto-line 4)
    (should (= (line-number-at-pos) 4))
    (should (string= (buffer-substring (pos-bol) (pos-eol)) "line4"))))

(ert-deftest helixel-test-action-select-commands ()
  "Test select-line starts action correctly."
  (helixel-test-with-buffer "hello world"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (should helixel--action)
    (should (eq (helixel--live-get :subcat) 'lineselect))))

(ert-deftest helixel-test-define-movement-macro ()
  "Test helixel-define-movement creates a working action-tracked command."
  (helixel-define-movement helixel-test-movement2 forward-char char)
  (helixel-test-with-buffer "hello"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-test-movement2)
    (helixel-test-movement2)
    (should helixel--action)
    (should (eq (helixel--live-get :category) 'movement))
    (should (eq (helixel--live-get :subcat) 'char))))

;;; helixel-execute-command / helixel-define-ex-command tests

(ert-deftest helixel-test-execute-command-known ()
  "Test executing a known command via helixel-execute-command."
  (let ((helixel--command-alist
         `((("test-cmd") ,#'ignore))))
    (should (progn (helixel-execute-command "test-cmd") t))))

(ert-deftest helixel-test-execute-command-unknown ()
  "Test executing an unknown command shows message."
  (let ((helixel--command-alist nil))
    (should (progn (helixel-execute-command "no-such-cmd") t))))

(ert-deftest helixel-test-execute-command-call-interactively ()
  "Test commandp callbacks are called via call-interactively."
  (let ((helixel--command-alist nil)
        (called-interactively nil))
    (cl-letf (((symbol-function 'test-helixel-cmd)
               (lambda ()
                 (interactive)
                 (setq called-interactively (called-interactively-p)))))
      (helixel-define-ex-command "test-ia" #'test-helixel-cmd)
      (helixel-execute-command "test-ia")
      (should called-interactively))))

(ert-deftest helixel-test-execute-command-funcall ()
  "Test non-commandp callbacks are called via funcall."
  (let ((helixel--command-alist nil)
        (called nil))
    (helixel-define-ex-command "test-fn" (lambda () (setq called t)))
    (helixel-execute-command "test-fn")
    (should called)))

(ert-deftest helixel-test-execute-command-multi-callback ()
  "Test executing a command with multiple callbacks."
  (let ((helixel--command-alist nil)
        (counter 0))
    (helixel-define-ex-command "multi"
      (list (lambda () (setq counter (1+ counter)))
            (lambda () (setq counter (1+ counter)))
            #'ignore))
    (helixel-execute-command "multi")
    (should (= counter 2))))

(ert-deftest helixel-test-execute-command-multi-order ()
  "Test callbacks are executed in order."
  (let ((helixel--command-alist nil)
        (vals nil))
    (helixel-define-ex-command "ord"
      (list (lambda () (push 1 vals))
            (lambda () (push 2 vals))
            (lambda () (push 3 vals))))
    (helixel-execute-command "ord")
    (should (equal vals '(3 2 1)))))

(ert-deftest helixel-test-execute-command-with-aliases ()
  "Test command can be invoked via any of its aliases."
  (let ((helixel--command-alist nil)
        (called nil))
    (helixel-define-ex-command
     '("a" "alias" "alt") (lambda () (setq called t)))
    (helixel-execute-command "alias")
    (should called)))

(ert-deftest helixel-test-execute-command-second-alias ()
  "Test command can be invoked via second alias."
  (let ((helixel--command-alist nil)
        (called nil))
    (helixel-define-ex-command
     '("a" "alias" "alt") (lambda () (setq called t)))
    (setq called nil)
    (helixel-execute-command "alt")
    (should called)))

(ert-deftest helixel-test-define-typable-command-single-symbol ()
  "Test helixel-define-ex-command with a single symbol callback."
  (let ((helixel--command-alist nil)
        (called nil))
    (cl-letf (((symbol-function 'test-tc) (lambda () (setq called t))))
      (helixel-define-ex-command "tc-sym" #'test-tc)
      (helixel-execute-command "tc-sym")
      (should called))))

(ert-deftest helixel-test-define-typable-command-duplicate ()
  "Test defining the same command twice does not duplicate."
  (let ((helixel--command-alist nil))
    (helixel-define-ex-command "dup" #'ignore)
    (helixel-define-ex-command "dup" #'ignore)
    (should (= (length helixel--command-alist) 1))))

(ert-deftest helixel-test-repeat-ring-no-bare-entries ()
  "Test ring never contains bare (:dir ...) entries without :category."
  (let ((helixel--action nil)
        (helixel--action-ring '((:category movement :subcat line
                                :marker ,(point-marker) :dir forward)))
        (helixel--action-pos nil)
        (helixel--repeat-dir 'forward)
        (helixel--repeat-data nil))
    (helixel-test-with-buffer "hello"
      (helixel-search-repeat-next)
      ;; set-dir no longer exists — repeat-dir is separate from action dir.
      ;; Verify no bare entries were pushed.
      (when helixel--action-ring
        (dolist (a helixel--action-ring)
          (should (plist-get a :category))
          (should-not (and (null (plist-get a :category))
                           (plist-get a :dir))))))))

(ert-deftest helixel-test-history-search-creates-proper-action ()
  "Test from-history for search sets :subcat and :marker on live action."
  (let ((helixel--action-ring `((:category search :subcat search
                                 :search (:pattern "test" :dir forward) :display t
                                 :marker ,(point-marker))))
        (helixel--action nil)
        (helixel--repeat-dir 'forward)
        (helixel--repeat-data nil))
    (helixel-test-with-buffer "a test b"
      (goto-char 3)
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt _collection &rest _)
                   (helixel-action-display (car helixel--action-ring)))))
        (helixel-search--from-history t))
      (should (eq (helixel--live-get :category) 'search))
      (should (eq (helixel--live-get :subcat) 'search))
      (should (helixel--live-get :marker)))))

(ert-deftest helixel-test-repeat-dir-separate-from-action-dir ()
  "Test that N flips repeat-dir without mutating action :dir of ring entries."
  (let ((helixel--action nil)
        (helixel--action-ring nil)
        (helixel--repeat-dir 'forward)
        (helixel--repeat-data nil))
    (helixel-test-with-buffer "axb axb axb"
      (goto-char 5)
      (setq last-command 'helixel-find-next-char
            this-command 'helixel-find-next-char)
      (helixel-find-next-char ?b)
      (should (eql (point) 8))
      (helixel-search-repeat-reverse)
      ;; repeat-dir should be flipped
      (should (eq helixel--repeat-dir 'backward))
      ;; Ring front :dir was synced by N (for history display)
      (should (eq (helixel--action-cat-get (car helixel--action-ring) :dir) 'backward))
      ;; Live action :dir is 'backward (set by find-repeat's action-start)
      (should (eq (helixel--live-cat-get :dir) 'backward)))))

(ert-deftest helixel-test-repeat-find-session-continuity ()
  "Test f d then n are one session — no duplicate ring entries."
  (let ((helixel--action nil)
        (helixel--action-ring nil)
        (helixel--repeat-dir 'forward)
        (helixel--repeat-data nil))
    (helixel-test-with-buffer "axd axd axd"
      (goto-char 1)
      (setq last-command nil this-command 'helixel-find-next-char)
      (helixel-find-next-char ?d)
      (should (= (length helixel--action-ring) 1))
      (setq last-command 'helixel-find-next-char
            this-command 'helixel-search-repeat-next)
      (helixel-search-repeat-next)
      ;; Same session — no new ring entry pushed
      (should (= (length helixel--action-ring) 1))
      (helixel-search-repeat-next)
      (should (= (length helixel--action-ring) 1)))))

(ert-deftest helixel-test-repeat-find-across-movement ()
  "Test f d → j → n: movement pushed, find-repeat continues original session."
  (let ((helixel--action nil)
        (helixel--action-ring nil)
        (helixel--repeat-dir 'forward)
        (helixel--repeat-data nil))
    (helixel-test-with-buffer "axd\naxd\naxd"
      (goto-char 1)
      (setq last-command nil this-command 'helixel-find-next-char)
      (helixel-find-next-char ?d)
      (should (= (length helixel--action-ring) 1))
      ;; Intervening movement
      (setq last-command 'helixel-find-next-char
            this-command 'helixel-next-line)
      (helixel-next-line)
      ;; movement pushed old action? No — old was already committed.
      ;; Actually the movement just creates a new action.
      (setq last-command 'helixel-next-line
            this-command 'helixel-search-repeat-next)
      (helixel-search-repeat-next)
      ;; Ring has: [find-char/next, movement/line]
      (should (= (length helixel--action-ring) 2))
      ;; Live action is find-char/next (same subcat as original)
      (should (eq (helixel--live-get :category) 'find-char))
      (should (eq (helixel--live-get :subcat) 'next)))))

;;; C-g session cancel test

(ert-deftest helixel-test-c-g-cancels-session ()
  "Test C-g breaks session: next same-type command starts fresh.
The cancelled session is preserved in the ring for `;' to jump back to.
Cancel pushes a state/cancel sentinel so dedup works naturally."
  (helixel-test-with-buffer "hello world test extra"
    (setq helixel--action nil helixel--action-ring nil helixel--action-pos nil
          last-command nil this-command 'helixel-forward-word-start)
    ;; w w: two word movements, same session
    (helixel-forward-word-start)
    (let ((mark1 (marker-position (helixel--live-get :marker))))
      (setq last-command 'helixel-forward-word-start
            this-command 'helixel-forward-word-start)
      (helixel-forward-word-start)
      (should-not (= (marker-position (helixel--live-get :marker)) mark1))
      ;; C-g: cancel session → pushes live action + cancel sentinel
      (helixel--cancel-action)
      (should (null helixel--action))
      ;; ring: [state/cancel, movement/word(2nd w), movement/word(1st w)]
      (should (= (length helixel--action-ring) 3))
      (should (eq (plist-get (car helixel--action-ring) :category) 'state))
      ;; w: new session, new marker at current position
      (setq last-command nil this-command 'helixel-forward-word-start)
      (goto-char 7)
      (helixel-forward-word-start)
      (should helixel--action)
      (should (= (marker-position (helixel--live-get :marker)) 7))
      ;; ;: push new w to ring
      ;; ring: [movement/word(new), state/cancel, movement/word(2nd), movement/word(1st)]
      (helixel-action-cycle)
      (should (= (length helixel--action-ring) 4))
      ;; First visible entry is movement/word(new)
      (should (eq (plist-get (nth helixel--action-pos helixel--action-ring)
                             :category) 'movement))
      ;; ; again: skip cancel, jump to older session (original w-w)
      (helixel-action-cycle)
      (should (eq (plist-get (nth helixel--action-pos helixel--action-ring)
                             :category) 'movement))
      (should (= (region-beginning) 1)))))

;;; helixel-test-action.el ends here
