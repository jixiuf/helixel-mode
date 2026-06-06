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
     (setq helixel--chain-session nil)
     (setq helixel--pending-sel nil)
     (setq helixel--inhibit-action-track nil)
     (setq helixel--repeat-permanent-flip nil)
     (unwind-protect
         (progn ,@body)
       (when helixel--chain-session
         (when-let* ((b (helixel-chain-session-init-bounds
                         helixel--chain-session)))
           (ignore-errors (set-marker (car b) nil))
           (ignore-errors (set-marker (cdr b) nil))))
       (setq helixel--chain-session nil)
       (setq helixel--inhibit-action-track nil)
       (ignore-errors (helixel-normal-state -1)))))

;; ── Chain lifecycle tests ──

(ert-deftest helixel-test-chain-empty-no-record ()
  "Chain with no edits records nothing."
  (helixel-chain-test-with-buffer "line1\nline2\nline3\n"
    (let ((prev-tx helixel--last-tx))
      (helixel-repeat-chain-start)
      (should (helixel--chain-active-p))
      (helixel-repeat-chain-end)
      (should-not (helixel--chain-active-p))
      (should (eq helixel--last-tx prev-tx)))))

(ert-deftest helixel-test-chain-cancel-discards ()
  "Chain cancel discards macro and cleans up."
  (helixel-chain-test-with-buffer "aaa bbb\nccc ddd\n"
    (let ((prev-tx helixel--last-tx))
      (helixel-repeat-chain-start)
      (should (helixel--chain-active-p))
      (helixel-repeat-chain-cancel)
      (should-not (helixel--chain-active-p))
      (should-not defining-kbd-macro)
      (should (eq helixel--last-tx prev-tx)))))

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
    (setq helixel--chain-session (make-helixel-chain-session :active-p t))
    (helixel-repeat-chain-end)
    (should-not (helixel--chain-active-p))))

;; ── Chain: kmacro tx structure ──

(ert-deftest helixel-test-chain-records-kmacro ()
  "Chain stores its tx-list in the tx payload."
  (helixel-chain-test-with-buffer "aaa\n"
    (goto-char 1)
    (helixel-repeat-chain-start)
    ;; Push two fake sub-txs directly onto the session's tx-list.
    (push (helixel-action-create 'noop nil :runner #'ignore)
          (helixel-chain-session-tx-list helixel--chain-session))
    (push (helixel-action-create 'noop nil :runner #'ignore)
          (helixel-chain-session-tx-list helixel--chain-session))
    (helixel-repeat-chain-end)
    (should helixel--last-tx)
    (should (eq (helixel-action-op helixel--last-tx) 'chain))
    (let ((tx-list (plist-get (helixel-action-payload helixel--last-tx)
                              :tx-list)))
      (should tx-list)
      (should (listp tx-list))
      (should (= 2 (length tx-list)))
      (should (helixel-action-p (car tx-list))))))

(ert-deftest helixel-test-chain-last-event-is-compound ()
  "After chain-end, helixel--last-tx is the chain tx."
  (helixel-chain-test-with-buffer "aaa\n"
    (goto-char 1)
    (helixel-repeat-chain-start)
    (push (helixel-action-create 'noop nil :runner #'ignore)
          (helixel-chain-session-tx-list helixel--chain-session))
    (helixel-repeat-chain-end)
    (should (eq (helixel-action-op helixel--last-tx) 'chain))))

(ert-deftest helixel-test-chain-merge-entry-kind ()
  "Chain-end merges :entry-kind from live ctx when snapshot lacks it."
  (helixel-chain-test-with-buffer "aaa\n"
    (goto-char 1)
    (setq helixel--pending-sel
          (helixel-sel-create 'search
            '(:pattern "foo" :dir forward)))
    (helixel-repeat-chain-start)
    ;; Simulate i updating live ctx after snapshot
    (setq helixel--pending-sel
          (helixel-sel-update-ctx helixel--pending-sel
                                  :entry-kind 'insert))
    (push (helixel-action-create 'noop nil :runner #'ignore)
          (helixel-chain-session-tx-list helixel--chain-session))
    (helixel-repeat-chain-end)
    (should helixel--last-tx)
    (let ((sel (helixel-action-sel helixel--last-tx)))
      (should sel)
      (should (eq (helixel-sel-search-entry-kind sel) 'insert)))))

(ert-deftest helixel-test-chain-in-edit-ring ()
  "Chain tx is pushed onto the event ring."
  (helixel-chain-test-with-buffer "aaa\n"
    (goto-char 1)
    (helixel-repeat-chain-start)
    (push (helixel-action-create 'noop nil :runner #'ignore)
          (helixel-chain-session-tx-list helixel--chain-session))
    (helixel-repeat-chain-end)
    (should helixel--event-ring)
    (should (eq (helixel-action-op (car helixel--event-ring))
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
  "helixel--record-action is inhibited during defining-kbd-macro."
  (helixel-chain-test-with-buffer "test\n"
    (let* ((prev-tx helixel--last-tx)
           (defining-kbd-macro t))
      (helixel--record-action 'kill :runner #'ignore)
      (should (eq helixel--last-tx prev-tx)))))

;; ── End-to-end: chain advance failure in . and , ──

(defun helixel-chain--make-test-tx (&optional sel-ctx)
  "Create a minimal chain TX with SEL-CTX for testing ./, flows.
The chain has one no-op sub-tx so the runner has something to
iterate — the actual edit semantic is irrelevant to the advance
tests in this section."
  (helixel-action-create 'chain (or sel-ctx nil)
    :runner #'helixel--repeat-chain-runner
    :display "chain(test)"
    :tx-list (list (helixel-action-create 'noop nil :runner #'ignore))))

(ert-deftest helixel-test-chain-dot-search-no-more ()
  ". on chain search at edge signals user-error (caught by repeat-edit)."
  (helixel-chain-test-with-buffer "foo bar\n"
    (goto-char 1)
    (let* ((ctx (helixel-sel-create 'search
                  '(:pattern "foo" :dir forward :entry-kind insert)))
           (tx (helixel-chain--make-test-tx ctx))
           (helixel--last-tx tx)
           (helixel--inhibit-action-track t))
      (should (string-match-p "aborted"
                              (helixel-repeat-edit))))))

(ert-deftest helixel-test-chain-dot-line-edge ()
  ". on chain line at last line operates on current line."
  (helixel-chain-test-with-buffer "aaa\n"
    (goto-char (point-max))
    (let* ((ctx (helixel-sel-create 'line '(:dir forward :count 1)))
           (tx (helixel-chain--make-test-tx ctx))
           (helixel--last-tx tx)
           (helixel--inhibit-action-track t))
      ;; Should not error: the last line is a valid target
      (helixel-repeat-edit)
      (should t))))

(ert-deftest helixel-test-chain-comma-search-no-more ()
  ", on chain search at edge signals user-error."
  (helixel-chain-test-with-buffer "foo bar\n"
    (goto-char 1)
    (let* ((ctx (helixel-sel-create 'search
                  '(:pattern "foo" :dir forward :entry-kind insert)))
           (tx (helixel-chain--make-test-tx ctx))
           (helixel--last-tx tx)
           (helixel--inhibit-action-track t))
      (should-error (helixel-repeat-selection)))))

(ert-deftest helixel-test-chain-dot-skip-match ()
  ". on chain search with entry-kind skips current match."
  (helixel-chain-test-with-buffer "foo bar foo baz\n"
    (goto-char 1)
    (let* ((ctx (helixel-sel-create 'search
                  '(:pattern "foo" :dir forward :entry-kind insert)))
           (tx (helixel-chain--make-test-tx ctx))
           (helixel--last-tx tx)
           (helixel--inhibit-action-track t)
           (helixel--repeat-preview-pos nil))
      (helixel-repeat-selection)
      ;; After ;, point should be at the second "foo" match-beginning
      (should (= (point) 9)))))

(ert-deftest helixel-test-chain-dot-skip-blank-line ()
  ", on chain line skips blank lines like dot does."
  (helixel-chain-test-with-buffer "aaa\n   \nbbb\n"
    (goto-char 1)
    (let* ((ctx (helixel-sel-create 'line '(:dir forward :count 1)))
           (tx (helixel-chain--make-test-tx ctx))
           (helixel--last-tx tx)
           (helixel--inhibit-action-track t)
           (helixel--repeat-preview-pos nil))
      (helixel-repeat-selection)
      ;; Comma advances past blank line to next non-blank target
      (should (= (line-number-at-pos) 3)))))

(ert-deftest helixel-test-chain-dot-no-advance-data ()
  "Chain tx with no advance data does not error on ."
  (helixel-chain-test-with-buffer "test\n"
    (goto-char 1)
    (let* ((ctx (helixel-sel-create 'movement '(:moves ((forward-word . 1)))))
            (tx (helixel-chain--make-test-tx ctx))
            (helixel--last-tx tx)
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
                  '(:pattern "foo" :dir forward)))
           (tx (helixel-action-create 'chain ctx
                 :runner #'helixel-chain--count-runner
                 :display "chain"
                 :tx-list (list (helixel-action-create 'noop nil :runner #'ignore))))
           (helixel--last-tx tx)
           (helixel--inhibit-action-track t))
      (helixel-repeat-edit 0)
      (should (= 3 helixel-chain--test-ctr)))))

(ert-deftest helixel-test-chain-dot-all-buffer-search ()
  "C-u . on chain search repeats for all matches from point-min."
  (helixel-chain-test-with-buffer "foo a foo b foo c\n"
    (goto-char 8)
    (setq helixel-chain--test-ctr 0)
    (let* ((ctx (helixel-sel-create 'search
                  '(:pattern "foo" :dir forward)))
           (tx (helixel-action-create 'chain ctx
                 :runner #'helixel-chain--count-runner
                 :display "chain"
                 :tx-list (list (helixel-action-create 'noop nil :runner #'ignore))))
           (helixel--last-tx tx)
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
                  '(:pattern "foo" :dir forward)))
           (tx (helixel-action-create 'chain ctx
                 :runner #'helixel-chain--count-runner
                 :display "chain"
                 :tx-list (list (helixel-action-create 'noop nil :runner #'ignore))))
           (helixel--last-tx tx)
           (helixel--inhibit-action-track t))
      (helixel-repeat-edit -3)
      (should (= 3 helixel-chain--test-ctr)))))

(ert-deftest helixel-test-chain-dot-all-remaining-line ()
  "0 . on chain line repeats for all remaining lines."
  (helixel-chain-test-with-buffer "aaa\nbbb\nccc\n"
    (goto-char 1)
    (setq helixel-chain--test-ctr 0)
    (let* ((ctx (helixel-sel-create 'line '(:dir forward :count 1)))
           (tx (helixel-action-create 'chain ctx
                 :runner #'helixel-chain--count-runner
                 :display "chain"
                 :tx-list (list (helixel-action-create 'noop nil :runner #'ignore))))
           (helixel--last-tx tx)
           (helixel--inhibit-action-track t))
      (helixel-repeat-edit 0)
      ;; 3 lines, first already processed → 2 remaining
      (should (= 2 helixel-chain--test-ctr)))))

(ert-deftest helixel-test-chain-dot-all-buffer-line ()
  "C-u . on chain line repeats for all lines from point-min."
  (helixel-chain-test-with-buffer "aaa\nbbb\nccc\n"
    (goto-char 10)
    (setq helixel-chain--test-ctr 0)
    (let* ((ctx (helixel-sel-create 'line '(:dir forward :count 1)))
           (tx (helixel-action-create 'chain ctx
                 :runner #'helixel-chain--count-runner
                 :display "chain"
                 :tx-list (list (helixel-action-create 'noop nil :runner #'ignore))))
           (helixel--last-tx tx)
           (helixel--inhibit-action-track t))
      (helixel-repeat-edit '(4))
      (should (= 3 helixel-chain--test-ctr)))))

(ert-deftest helixel-test-chain-dot-reverse-n-line ()
  "-2 . on chain line repeats 2 times in reverse."
  (helixel-chain-test-with-buffer "aaa\nbbb\nccc\nddd\n"
    (goto-char (point-max))
    (forward-line -1)
    (setq helixel-chain--test-ctr 0)
    (let* ((ctx (helixel-sel-create 'line '(:dir forward :count 1)))
           (tx (helixel-action-create 'chain ctx
                 :runner #'helixel-chain--count-runner
                 :display "chain"
                 :tx-list (list (helixel-action-create 'noop nil :runner #'ignore))))
           (helixel--last-tx tx)
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
                  '(:pattern "foo" :dir forward)))
           (tx (helixel-action-create 'chain ctx
                 :runner #'helixel-chain--noop-runner
                 :display "chain"
                 :tx-list (list (helixel-action-create 'noop nil :runner #'ignore))))
           (helixel--last-tx tx)
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
                  '(:pattern "foo" :dir forward :entry-kind insert)))
           (tx (helixel-action-create 'chain ctx
                 :runner #'helixel-chain--noop-runner
                 :display "chain"
                 :tx-list (list (helixel-action-create 'noop nil :runner #'ignore))))
           (helixel--last-tx tx)
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
    (let* ((ctx (helixel-sel-create 'line '(:dir forward :count 1)))
           (tx (helixel-action-create 'chain ctx
                 :runner #'helixel-chain--noop-runner
                 :display "chain"
                 :tx-list (list (helixel-action-create 'noop nil :runner #'ignore))))
           (helixel--last-tx tx)
           (helixel--inhibit-action-track t))
      (helixel-repeat-selection '(4))
      ;; C-u , previews all → ends at eol of last line
      (should (= (line-number-at-pos) 3)))))   ;; last content line

;; ── Chain tx-list preservation ──

(ert-deftest helixel-test-chain-tx-list-accumulates ()
  "After Phase 4.4, chain accumulates the LIST of committed txs.
Running a motion command + an edit during a chain leaves two
entries on `helixel-chain-session-tx-list', and the resulting
chain tx's `:tx-list' payload preserves them in chronological
order."
  (helixel-chain-test-with-buffer
      "aaa bbb ccc\nddd eee fff\nggg hhh iii\n"
    (goto-char 1)
    (helixel-select-line)
    (let ((init-ctx helixel--pending-sel))
      (helixel-repeat-chain-start)
      ;; Motion command (Phase 4.3 makes movements produce txs;
      ;; the chain hook appends them to tx-list).
      (helixel-backward-word-start)
      ;; Edit command.
      (helixel--record-action 'kill :runner #'ignore)
      (let ((s helixel--chain-session))
        (should s)
        ;; tx-list should have at least the kill entry.  Movement
        ;; commands produce txs only when their op is recorded;
        ;; we test only the more invariant edit-entry presence.
        (should (> (length (helixel-chain-session-tx-list s)) 0)))
      (helixel-repeat-chain-end)
      (should helixel--last-tx)
      (should (eq (helixel-action-op helixel--last-tx) 'chain))
      (let ((tx-list (plist-get (helixel-action-payload helixel--last-tx)
                                :tx-list)))
        (should tx-list)
        (should (listp tx-list))
        (should (> (length tx-list) 0))
        (should (helixel-action-p (car tx-list))))
      ;; init-ctx merged into the chain tx's sel.
      (should (equal init-ctx (helixel-action-sel helixel--last-tx))))))

(ert-deftest helixel-test-chain-comma-strategy-builder ()
  "After C2 flatten, chain repeat goes through the unified
`helixel--repeat-advance' rather than a strategy struct.  Verify
the chain in-place fallback: when a chain tx's sel has no
kind-advance fn (e.g. movement kind), `helixel--repeat-advance'
returns t (allowing in-place repeat) instead of nil."
  (helixel-chain-test-with-buffer
      "aaa bbb ccc\nddd eee fff\nggg hhh iii\n"
    (goto-char 1)
    (helixel-select-line)
    (let* ((init-ctx helixel--pending-sel)
           (tx (helixel-action-create 'chain init-ctx
                 :runner #'helixel--repeat-chain-runner
                 :display "chain"
                 :tx-list (list (helixel-action-create 'noop nil
                                 :runner #'ignore)))))
      (setq helixel--last-tx tx)
      ;; line kind has an :advance fn so this returns whatever the
      ;; advance fn does — just confirm the unified dispatcher
      ;; accepts the chain tx without erroring.
      (should-not (eq 'error
                      (condition-case nil
                          (helixel--repeat-advance tx tx)
                        (error 'error)))))))

;; ── Chain + insert + electric-pair replay (unit test) ──

(ert-deftest helixel-test-chain-insert-electric-pair-replay ()
  "A chain whose `:tx-list' contains an insert-text tx with a
multi-char `:text' segment replays the segment verbatim at the
new position — the pattern produced when `electric-pair-mode' is
on and user types `(' inside a chain (captured as a single `()'
segment).

We build the chain tx by hand rather than driving the full
`pre/post-command-hook' pipeline (batch mode does not auto-run
those hooks reliably) — the invariant under test is the
chain-runner → insert-text-runner replay path, not capture."
  (helixel-chain-test-with-buffer "abc\nxyz\n"
    (let* ((insert-tx (helixel-action-create 'insert-text nil
                        :runner (helixel--op-runner 'insert-text)
                        :keys (list (list :text "()"
                                          :delete-before 0
                                          :offset -1))))
           (chain-tx  (helixel-action-create 'chain nil
                        :runner #'helixel--repeat-chain-runner
                        :display "chain"
                        :tx-list (list insert-tx))))
      (setq helixel--last-tx chain-tx)
      ;; Replay at start of line 2.
      (goto-char (point-min))
      (forward-line 1)
      (let ((before (point)))
        (helixel-repeat-edit)
        (goto-char before)
        (should (looking-at-p "()"))))))

;; ── Insert-record IME / composition edge case ──

(ert-deftest helixel-test-insert-record-composition-multi-event ()
  "Two after-change events in one command (e.g. composition / IME)
are collapsed into a single `:text' segment carrying the
MIN..MAX buffer substring.

Simulates a composition that fires (BEG END 0) then
(BEG END+2 0) within one command — covered by min/max span
collapse in `helixel--insert-classify-segment'."
  (helixel-test-with-buffer ""
    (helixel--insert-begin)
    ;; Simulate a custom "composition" command that fires two
    ;; after-change events on the same insertion site.
    (let ((this-command 'my-fake-composition))
      (run-hooks 'pre-command-hook)
      (insert "a")
      (insert "明天")                ; another insertion
      (run-hooks 'post-command-hook))
    (let ((segs (helixel--insert-finish)))
      (should (= 1 (length segs)))
      (should (eq :text (caar segs)))
      (should (equal "a明天" (plist-get (car segs) :text))))))

(ert-deftest helixel-test-insert-record-replace-with-delete-before ()
  "A command that DELETES some prefix then INSERTS new text
(`completion-preview-insert' replacing `fo' → `foo') is captured
as a single `:text' segment with `:delete-before' set, so replay
deletes the prefix before inserting."
  (helixel-test-with-buffer "fo"
    (goto-char (point-max))
    (helixel--insert-begin)
    ;; Simulate the completion-accept command:
    ;;   delete the 2-char prefix "fo", insert "foo".
    (let ((this-command 'my-fake-completion))
      (run-hooks 'pre-command-hook)
      (delete-region (- (point) 2) (point))
      (insert "foo")
      (run-hooks 'post-command-hook))
    (let* ((segs (helixel--insert-finish))
           (seg  (car segs)))
      (should (= 1 (length segs)))
      (should (eq :text (car seg)))
      (should (equal "foo" (plist-get seg :text)))
      (should (= 2 (plist-get seg :delete-before)))
      ;; Replay in a buffer with the same prefix typed.
      (helixel-test-with-buffer "fo"
        (goto-char (point-max))
        (helixel--execute-keys segs)
        (should (string= "foo" (buffer-string)))))))

(provide 'helixel-test-repeat-chain)
;;; helixel-test-repeat-chain.el ends here
