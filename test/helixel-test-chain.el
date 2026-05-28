;;; helixel-test-repeat-chain.el --- Tests for chain recording  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

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

;; Tests for helixel-repeat-chain: kmacro recording and dot-repeat.

;;; Code:

(require 'ert)
(require 'helixel)
(require 'helixel-repeat)

(defmacro helixel-chain-test-with-buffer (content &rest body)
  "Execute BODY in a temp buffer with CONTENT, in normal state."
  (declare (indent 1))
  `(with-temp-buffer
     (transient-mark-mode 1)
     (insert ,content)
     (goto-char (point-min))
     (setq-local helixel--current-state 'motion)
     (helixel--switch-state 'normal)
     (setq helixel--repeat-chaining nil)
     (setq helixel--repeat-chain-init-ctx nil)
     (setq helixel--repeat-chain-init-bounds nil)
     (setq helixel--pending-sel nil)
     (setq helixel--inhibit-action-track nil)
     (setq helixel--repeat-permanent-flip nil)
     (setq helixel--chain-in-edit-phase nil)
     (setq helixel--chain-move-keys nil)
     (setq helixel--chain-edit-keys nil)
     (unwind-protect
         (progn ,@body)
       (setq helixel--repeat-chaining nil)
       (setq helixel--repeat-chain-init-ctx nil)
       (when helixel--repeat-chain-init-bounds
         (ignore-errors (set-marker (car helixel--repeat-chain-init-bounds) nil))
         (ignore-errors (set-marker (cdr helixel--repeat-chain-init-bounds) nil))
         (setq helixel--repeat-chain-init-bounds nil))
       (setq helixel--inhibit-action-track nil)
       (setq helixel--chain-in-edit-phase nil)
       (setq helixel--chain-move-keys nil)
       (setq helixel--chain-edit-keys nil)
       (ignore-errors (helixel-normal-state -1)))))

;; ── Chain lifecycle tests ──

(ert-deftest helixel-test-chain-empty-no-record ()
  "Chain with no edits records nothing."
  (helixel-chain-test-with-buffer "line1\nline2\nline3\n"
    (let ((prev-tx helixel--last-event))
      (helixel-repeat-chain-start)
      (should helixel--repeat-chaining)
      (helixel-repeat-chain-end)
      (should-not helixel--repeat-chaining)
      (should (eq helixel--last-event prev-tx)))))

(ert-deftest helixel-test-chain-cancel-discards ()
  "Chain cancel discards macro and cleans up."
  (helixel-chain-test-with-buffer "aaa bbb\nccc ddd\n"
    (let ((prev-tx helixel--last-event))
      (helixel-repeat-chain-start)
      (should helixel--repeat-chaining)
      (helixel-repeat-chain-cancel)
      (should-not helixel--repeat-chaining)
      (should-not defining-kbd-macro)
      (should (eq helixel--last-event prev-tx)))))

(ert-deftest helixel-test-chain-nested-error ()
  "Starting a chain while already chaining signals error."
  (helixel-chain-test-with-buffer "test\n"
    (helixel-repeat-chain-start)
    (should-error (helixel-repeat-chain-start))
    (helixel-repeat-chain-cancel)))

(ert-deftest helixel-test-chain-end-without-start ()
  "Ending a chain without starting signals error."
  (helixel-chain-test-with-buffer "test\n"
    (should-error (helixel-repeat-chain-end))))

(ert-deftest helixel-test-chain-end-without-kmacro ()
  "Ending chain without kmacro active creates empty chain (graceful)."
  (helixel-chain-test-with-buffer "test\n"
    (setq helixel--repeat-chaining t)
    (helixel-repeat-chain-end)
    (should-not helixel--repeat-chaining)))

;; ── Chain: kmacro tx structure ──

(ert-deftest helixel-test-chain-records-kmacro ()
  "Chain stores kmacro vector in tx payload."
  (helixel-chain-test-with-buffer "aaa\n"
    (goto-char 1)
    (helixel-repeat-chain-start)
    ;; Push keys directly to edit-keys accumulator (no move phase).
    (push (kbd "x") helixel--chain-edit-keys)
    (push (kbd "x") helixel--chain-edit-keys)
    (helixel-repeat-chain-end)
    (should helixel--last-event)
    (should (eq (helixel-event-op helixel--last-event) 'chain))
    (let ((kmacro (plist-get (helixel-event-payload helixel--last-event) :kmacro)))
      (should kmacro)
      (should (vectorp kmacro))
      (should (> (length kmacro) 0)))))

(ert-deftest helixel-test-chain-last-event-is-compound ()
  "After chain-end, helixel--last-event is the chain tx."
  (helixel-chain-test-with-buffer "aaa\n"
    (goto-char 1)
    (helixel-repeat-chain-start)
    (push (kbd "x") helixel--chain-edit-keys)
    (helixel-repeat-chain-end)
    (should (eq (helixel-event-op helixel--last-event) 'chain))))

(ert-deftest helixel-test-chain-merge-entry-kind ()
  "Chain-end merges :entry-kind from live ctx when snapshot lacks it."
  (helixel-chain-test-with-buffer "aaa\n"
    (goto-char 1)
    (setq helixel--pending-sel
          (helixel-sel-create 'search
            '(:pattern "foo" :dir forward)
            #'ignore "s"))
    (helixel-repeat-chain-start)
    ;; Simulate i updating live ctx after snapshot
    (setq helixel--pending-sel
          (helixel-sel-update-ctx helixel--pending-sel
                                  :entry-kind 'insert))
    (push (kbd "x") helixel--chain-edit-keys)
    (helixel-repeat-chain-end)
    (should helixel--last-event)
    (let ((sel (helixel-event-sel helixel--last-event)))
      (should sel)
      (should (eq (helixel-sel-search-entry-kind sel) 'insert)))))

(ert-deftest helixel-test-chain-in-edit-ring ()
  "Chain tx is pushed onto the event ring."
  (helixel-chain-test-with-buffer "aaa\n"
    (goto-char 1)
    (helixel-repeat-chain-start)
    (push (kbd "x") helixel--chain-edit-keys)
    (helixel-repeat-chain-end)
    (should helixel--event-ring)
    (should (eq (helixel-event-op (car helixel--event-ring))
                'chain))))

(ert-deftest helixel-test-chain-op-registered ()
  "Chain op is registered in helixel--op-runner."
  (should (helixel--op-runner 'chain)))

;; ── Chain advance: helper functions tested directly ──

(ert-deftest helixel-test-blank-line-p ()
  "Detect blank lines correctly."
  (helixel-chain-test-with-buffer "aaa\n   \nbbb\n"
    (goto-char (point-min))
    (should-not (helixel--blank-line-p))
    (forward-line 1)
    (should (helixel--blank-line-p))
    (forward-line 1)
    (should-not (helixel--blank-line-p))))

(ert-deftest helixel-test-chain-no-record-during-kmacro ()
  "helixel--record-edit is inhibited during defining-kbd-macro."
  (helixel-chain-test-with-buffer "test\n"
    (let* ((prev-tx helixel--last-event)
           (defining-kbd-macro t))
      (helixel--record-edit 'kill :runner #'ignore)
      (should (eq helixel--last-event prev-tx)))))

;; ── End-to-end: chain advance failure in . and , ──

(defun helixel-chain--make-test-tx (&optional sel-ctx)
  "Create a minimal chain TX with SEL-CTX for testing ./, flows."
  (helixel--make-tx 'chain (or sel-ctx nil)
    :runner #'helixel--repeat-chain-runner
    :display "chain(test)"
    :kmacro (vconcat (kbd "x"))
    :chain-move-keys nil
    :chain-init-ctx sel-ctx))

(ert-deftest helixel-test-chain-dot-search-no-more ()
  ". on chain search at edge signals user-error (caught by repeat-edit)."
  (helixel-chain-test-with-buffer "foo bar\n"
    (goto-char 1)
    (let* ((ctx (helixel-sel-create 'search
                  '(:pattern "foo" :dir forward :entry-kind insert)
                  #'ignore "s"))
           (tx (helixel-chain--make-test-tx ctx))
           (helixel--last-event tx)
           (helixel--inhibit-action-track t))
      (should (string-match-p "aborted"
                              (helixel-repeat-edit))))))

(ert-deftest helixel-test-chain-dot-line-edge ()
  ". on chain line at last line operates on current line."
  (helixel-chain-test-with-buffer "aaa\n"
    (goto-char (point-max))
    (let* ((ctx (helixel-sel-create 'line '(:dir forward :count 1)
                  #'ignore "l"))
           (tx (helixel-chain--make-test-tx ctx))
           (helixel--last-event tx)
           (helixel--inhibit-action-track t))
      ;; Should not error: the last line is a valid target
      (helixel-repeat-edit)
      (should t))))

(ert-deftest helixel-test-chain-comma-search-no-more ()
  ", on chain search at edge signals user-error."
  (helixel-chain-test-with-buffer "foo bar\n"
    (goto-char 1)
    (let* ((ctx (helixel-sel-create 'search
                  '(:pattern "foo" :dir forward :entry-kind insert)
                  #'ignore "s"))
           (tx (helixel-chain--make-test-tx ctx))
           (helixel--last-event tx)
           (helixel--inhibit-action-track t))
      (should-error (helixel-repeat-selection)))))

(ert-deftest helixel-test-chain-dot-skip-match ()
  ". on chain search with entry-kind skips current match."
  (helixel-chain-test-with-buffer "foo bar foo baz\n"
    (goto-char 1)
    (let* ((ctx (helixel-sel-create 'search
                  '(:pattern "foo" :dir forward :entry-kind insert)
                  #'ignore "s"))
           (tx (helixel-chain--make-test-tx ctx))
           (helixel--last-event tx)
           (helixel--inhibit-action-track t)
           (helixel--repeat-has-preview nil))
      (helixel-repeat-selection)
      ;; After ;, point should be at the second "foo" match-end
      (should (= (point) 12)))))

(ert-deftest helixel-test-chain-dot-skip-blank-line ()
  ", on chain line skips blank lines like dot does."
  (helixel-chain-test-with-buffer "aaa\n   \nbbb\n"
    (goto-char 1)
    (let* ((ctx (helixel-sel-create 'line '(:dir forward :count 1)
                  #'ignore "l"))
           (tx (helixel-chain--make-test-tx ctx))
           (helixel--last-event tx)
           (helixel--inhibit-action-track t)
           (helixel--repeat-has-preview nil))
      (helixel-repeat-selection)
      ;; Comma advances past blank line to next non-blank target
      (should (= (line-number-at-pos) 3)))))

(ert-deftest helixel-test-chain-dot-no-advance-data ()
  "Chain tx with no advance data does not error on ."
  (helixel-chain-test-with-buffer "test\n"
    (goto-char 1)
    (let* ((ctx (helixel-sel-create 'movement '(:moves ((forward-word . 1)))
                   #'ignore "m"))
            (tx (helixel-chain--make-test-tx ctx))
            (helixel--last-event tx)
            (helixel--inhibit-action-track t))
      ;; No advance data → should not error
      (helixel-repeat-edit))))

;; ── Chain prefix argument repeat ──

(defvar helixel-chain--test-ctr 0
  "Counter for chain repeat test runner.")

(defun helixel-chain--count-runner (_tx)
  "Test runner that increments `helixel-chain--test-ctr'."
  (setq helixel-chain--test-ctr (1+ (or helixel-chain--test-ctr 0))))

(ert-deftest helixel-test-chain-dot-all-remaining-search ()
  "0 . on chain search repeats for all remaining matches."
  (helixel-chain-test-with-buffer "foo x foo y foo z\n"
    (goto-char 1)
    (setq helixel-chain--test-ctr 0)
    (let* ((ctx (helixel-sel-create 'search
                  '(:pattern "foo" :dir forward)
                  #'ignore "s"))
           (tx (helixel--make-tx 'chain ctx
                 :runner #'helixel-chain--count-runner
                 :display "chain"
                 :kmacro (vconcat (kbd "x"))))
           (helixel--last-event tx)
           (helixel--inhibit-action-track t))
      (helixel-repeat-edit 0)
      (should (= 3 helixel-chain--test-ctr)))))

(ert-deftest helixel-test-chain-dot-all-buffer-search ()
  "C-u . on chain search repeats for all matches from point-min."
  (helixel-chain-test-with-buffer "foo a foo b foo c\n"
    (goto-char 8)
    (setq helixel-chain--test-ctr 0)
    (let* ((ctx (helixel-sel-create 'search
                  '(:pattern "foo" :dir forward)
                  #'ignore "s"))
           (tx (helixel--make-tx 'chain ctx
                 :runner #'helixel-chain--count-runner
                 :display "chain"
                 :kmacro (vconcat (kbd "x"))))
           (helixel--last-event tx)
           (helixel--inhibit-action-track t))
      (helixel-repeat-edit '(4))
      (should (= 3 helixel-chain--test-ctr)))))

(ert-deftest helixel-test-chain-dot-reverse-n-search ()
  "-3 . on chain search repeats 3 times in reverse."
  (helixel-chain-test-with-buffer "foo a foo b foo c foo d\n"
    (goto-char (point-max))
    (search-backward "foo d")
    (setq helixel-chain--test-ctr 0)
    (let* ((ctx (helixel-sel-create 'search
                  '(:pattern "foo" :dir forward)
                  #'ignore "s"))
           (tx (helixel--make-tx 'chain ctx
                 :runner #'helixel-chain--count-runner
                 :display "chain"
                 :kmacro (vconcat (kbd "x"))))
           (helixel--last-event tx)
           (helixel--inhibit-action-track t))
      (helixel-repeat-edit -3)
      (should (= 3 helixel-chain--test-ctr)))))

(ert-deftest helixel-test-chain-dot-all-remaining-line ()
  "0 . on chain line repeats for all remaining lines."
  (helixel-chain-test-with-buffer "aaa\nbbb\nccc\n"
    (goto-char 1)
    (setq helixel-chain--test-ctr 0)
    (let* ((ctx (helixel-sel-create 'line '(:dir forward :count 1)
                  #'ignore "l"))
           (tx (helixel--make-tx 'chain ctx
                 :runner #'helixel-chain--count-runner
                 :display "chain"
                 :kmacro (vconcat (kbd "x"))))
           (helixel--last-event tx)
           (helixel--inhibit-action-track t))
      (helixel-repeat-edit 0)
      ;; 3 lines, first already processed → 2 remaining
      (should (= 2 helixel-chain--test-ctr)))))

(ert-deftest helixel-test-chain-dot-all-buffer-line ()
  "C-u . on chain line repeats for all lines from point-min."
  (helixel-chain-test-with-buffer "aaa\nbbb\nccc\n"
    (goto-char 10)
    (setq helixel-chain--test-ctr 0)
    (let* ((ctx (helixel-sel-create 'line '(:dir forward :count 1)
                  #'ignore "l"))
           (tx (helixel--make-tx 'chain ctx
                 :runner #'helixel-chain--count-runner
                 :display "chain"
                 :kmacro (vconcat (kbd "x"))))
           (helixel--last-event tx)
           (helixel--inhibit-action-track t))
      (helixel-repeat-edit '(4))
      (should (= 3 helixel-chain--test-ctr)))))

(ert-deftest helixel-test-chain-dot-reverse-n-line ()
  "-2 . on chain line repeats 2 times in reverse."
  (helixel-chain-test-with-buffer "aaa\nbbb\nccc\nddd\n"
    (goto-char (point-max))
    (forward-line -1)
    (setq helixel-chain--test-ctr 0)
    (let* ((ctx (helixel-sel-create 'line '(:dir forward :count 1)
                  #'ignore "l"))
           (tx (helixel--make-tx 'chain ctx
                 :runner #'helixel-chain--count-runner
                 :display "chain"
                 :kmacro (vconcat (kbd "x"))))
           (helixel--last-event tx)
           (helixel--inhibit-action-track t))
      (helixel-repeat-edit -2)
      (should (= 2 helixel-chain--test-ctr)))))

;; ── Chain comma (,) prefix argument tests ──

(defun helixel-chain--noop-runner (_tx)
  "No-op runner for comma preview tests."
  nil)

(ert-deftest helixel-test-chain-comma-all-remaining-search ()
  "0 , on chain search previews by advancing past all remaining."
  (helixel-chain-test-with-buffer "foo x foo y foo z\n"
    (goto-char 1)
    (let* ((ctx (helixel-sel-create 'search
                  '(:pattern "foo" :dir forward)
                  #'ignore "s"))
           (tx (helixel--make-tx 'chain ctx
                 :runner #'helixel-chain--noop-runner
                 :display "chain"
                 :kmacro (vconcat (kbd "x"))))
           (helixel--last-event tx)
           (helixel--inhibit-action-track t))
      (helixel-repeat-selection 0)
      ;; After 0, : point should be at last match's match-end
      (should (>= (point) 16)))))   ;; end of "foo z\n"

(ert-deftest helixel-test-chain-comma-reverse-n-search ()
  "-3 , on chain search previews 3 times in reverse."
  (helixel-chain-test-with-buffer "foo a foo b foo c foo d\n"
    (goto-char (point-max))
    (search-backward "foo d")
    (let* ((ctx (helixel-sel-create 'search
                  '(:pattern "foo" :dir forward :entry-kind insert)
                  #'ignore "s"))
           (tx (helixel--make-tx 'chain ctx
                 :runner #'helixel-chain--noop-runner
                 :display "chain"
                 :kmacro (vconcat (kbd "x"))))
           (helixel--last-event tx)
           (helixel--inhibit-action-track t))
      (helixel-repeat-selection -3)
      ;; -3, reverse: each advance skips current and goes backward
      ;; "foo d" (19) → "foo c" (13) → "foo b" (7) → "foo a" (1)
      ;; Point ends at match-beginning of "foo a" = 1
      (should (= 1 (point))))))

(ert-deftest helixel-test-chain-comma-all-buffer-line ()
  "C-u , on chain line previews all lines from point-min."
  (helixel-chain-test-with-buffer "aaa\nbbb\nccc\n"
    (goto-char 10)
    (let* ((ctx (helixel-sel-create 'line '(:dir forward :count 1)
                  #'ignore "l"))
           (tx (helixel--make-tx 'chain ctx
                 :runner #'helixel-chain--noop-runner
                 :display "chain"
                 :kmacro (vconcat (kbd "x"))))
           (helixel--last-event tx)
           (helixel--inhibit-action-track t))
      (helixel-repeat-selection '(4))
      ;; C-u , previews all → ends at eol of last line
      (should (= (line-number-at-pos) 3)))))   ;; last content line

(provide 'helixel-test-repeat-chain)
;;; helixel-test-repeat-chain.el ends here
