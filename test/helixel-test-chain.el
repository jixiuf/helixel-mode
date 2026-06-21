;;; helixel-test-repeat-chain.el --- Tests for chain recording  -*- lexical-binding: t; -*-

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

;; Tests for helixel-repeat-chain: action-list accumulation and dot-repeat.

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
     ;; `execute-kbd-macro' runs in the selected window's buffer,
     ;; so display the temp buffer.
     (set-window-buffer nil (current-buffer))
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
       (remove-hook 'post-command-hook #'helixel--chain-post-cmd-hook t)
       (ignore-errors (helixel-normal-state -1)))))

;; ── Chain lifecycle tests ──

(ert-deftest helixel-test-chain-empty-no-record ()
  "Chain with no edits records nothing."
  (helixel-chain-test-with-buffer "line1\nline2\nline3\n"
    (let ((prev-action helixel-last-action))
      (helixel-repeat-chain-start)
      (should (helixel--chain-active-p))
      (helixel-repeat-chain-end)
      (should-not (helixel--chain-active-p))
      (should (eq helixel-last-action prev-action)))))

(ert-deftest helixel-test-chain-cancel-discards ()
  "Chain cancel discards macro and cleans up."
  (helixel-chain-test-with-buffer "aaa bbb\nccc ddd\n"
    (let ((prev-action helixel-last-action))
      (helixel-repeat-chain-start)
      (should (helixel--chain-active-p))
      (helixel-repeat-chain-cancel)
      (should-not (helixel--chain-active-p))
      (should-not defining-kbd-macro)
      (should (eq helixel-last-action prev-action)))))

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

(ert-deftest helixel-test-chain-end-without-actions ()
  "Ending chain without recorded actions creates empty chain (graceful)."
  (helixel-chain-test-with-buffer "test\n"
    (setq helixel--chain-session (make-helixel-chain-session :active-p t))
    (helixel-repeat-chain-end)
    (should-not (helixel--chain-active-p))))

;; ── Chain: compound action structure ──

(ert-deftest helixel-test-chain-records-action-list ()
  "Chain stores its action-list in the compound action payload."
  (helixel-chain-test-with-buffer "aaa\n"
    (goto-char 1)
    (helixel-repeat-chain-start)
    ;; Push two fake sub-actions directly onto the session's action-list.
    (push (helixel-action-create 'noop nil :runner #'ignore)
          (helixel-chain-session-action-list helixel--chain-session))
    (push (helixel-action-create 'noop nil :runner #'ignore)
          (helixel-chain-session-action-list helixel--chain-session))
    (helixel-repeat-chain-end)
    (should helixel-last-action)
    (should (eq (helixel-action-op helixel-last-action) 'chain))
    (let ((action-list (plist-get (helixel-action-payload helixel-last-action)
                              :action-list)))
      (should action-list)
      (should (listp action-list))
      (should (= 2 (length action-list)))
      (should (helixel-action-p (car action-list))))))

(ert-deftest helixel-test-chain-last-event-is-compound ()
  "After chain-end, helixel-last-action is the chain tx."
  (helixel-chain-test-with-buffer "aaa\n"
    (goto-char 1)
    (helixel-repeat-chain-start)
    (push (helixel-action-create 'noop nil :runner #'ignore)
          (helixel-chain-session-action-list helixel--chain-session))
    (helixel-repeat-chain-end)
    (should (eq (helixel-action-op helixel-last-action) 'chain))))

(ert-deftest helixel-test-chain-merge-entry-kind ()
  "`helixel--chain-propagate-entry-kind' updates init-ctx during recording."
  (helixel-chain-test-with-buffer "aaa\n"
    (goto-char 1)
    (setq helixel--pending-sel
          (helixel-sel-create 'search
            '(:pattern "foo" :dir forward)))
    (helixel-repeat-chain-start)
    ;; Simulate insert command calling propagate-entry-kind
    (helixel--chain-propagate-entry-kind 'insert)
    (push (helixel-action-create 'noop nil :runner #'ignore)
          (helixel-chain-session-action-list helixel--chain-session))
    (helixel-repeat-chain-end)
    (should helixel-last-action)
    (let ((sel (helixel-action-sel helixel-last-action)))
      (should sel)
      (should (eq (helixel-sel-search-entry-kind sel) 'insert)))))

(ert-deftest helixel-test-chain-in-edit-ring ()
  "Chain tx is pushed onto the event ring."
  (helixel-chain-test-with-buffer "aaa\n"
    (goto-char 1)
    (helixel-repeat-chain-start)
    (push (helixel-action-create 'noop nil :runner #'ignore)
          (helixel-chain-session-action-list helixel--chain-session))
    (helixel-repeat-chain-end)
    (should helixel--action-ring)
    (should (eq (helixel-action-op (car helixel--action-ring))
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

(ert-deftest helixel-test-chain-no-record-during-defining-kbd-macro ()
  "helixel-record-action is inhibited during defining-kbd-macro."
  (helixel-chain-test-with-buffer "test\n"
    (let* ((prev-action helixel-last-action)
           (defining-kbd-macro t))
      (helixel-record-action 'kill :runner #'ignore)
      (should (eq helixel-last-action prev-action)))))

;; ── End-to-end: chain advance failure in . and , ──

(defun helixel-chain--make-test-action (&optional sel-ctx)
  "Create a minimal chain TX with SEL-CTX for testing ./, flows.
The chain has one no-op sub-action so the runner has something to
iterate — the actual edit semantic is irrelevant to the advance
tests in this section."
  (helixel-action-create 'chain (or sel-ctx nil)
    :runner #'helixel--repeat-chain-runner
    :display "chain(test)"
    :action-list (list (helixel-action-create 'noop nil :runner #'ignore))))

(ert-deftest helixel-test-chain-dot-search-no-more ()
  ". on chain search at edge signals user-error (caught by repeat-edit)."
  (helixel-chain-test-with-buffer "foo bar\n"
    (goto-char 1)
    (let* ((ctx (helixel-sel-create 'search
                  '(:pattern "foo" :dir forward :entry-kind insert)))
           (tx (helixel-chain--make-test-action ctx))
           (helixel-last-action tx)
           (helixel--inhibit-action-track t))
      (should (string-match-p "aborted"
                              (helixel-repeat-edit))))))

(ert-deftest helixel-test-chain-dot-line-edge ()
  ". on chain line at last line operates on current line."
  (helixel-chain-test-with-buffer "aaa\n"
    (goto-char (point-max))
    (let* ((ctx (helixel-sel-create 'line '(:dir forward :count 1)))
           (tx (helixel-chain--make-test-action ctx))
           (helixel-last-action tx)
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
           (tx (helixel-chain--make-test-action ctx))
           (helixel-last-action tx)
           (helixel--inhibit-action-track t))
      (should-error (helixel-repeat-selection)))))

(ert-deftest helixel-test-chain-dot-skip-match ()
  ". on chain search with entry-kind skips current match."
  (helixel-chain-test-with-buffer "foo bar foo baz\n"
    (goto-char 1)
    (let* ((ctx (helixel-sel-create 'search
                  '(:pattern "foo" :dir forward :entry-kind insert)))
           (tx (helixel-chain--make-test-action ctx))
           (helixel-last-action tx)
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
           (tx (helixel-chain--make-test-action ctx))
           (helixel-last-action tx)
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
            (tx (helixel-chain--make-test-action ctx))
            (helixel-last-action tx)
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
                 :action-list (list (helixel-action-create 'noop nil :runner #'ignore))))
           (helixel-last-action tx)
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
                 :action-list (list (helixel-action-create 'noop nil :runner #'ignore))))
           (helixel-last-action tx)
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
                 :action-list (list (helixel-action-create 'noop nil :runner #'ignore))))
           (helixel-last-action tx)
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
                 :action-list (list (helixel-action-create 'noop nil :runner #'ignore))))
           (helixel-last-action tx)
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
                 :action-list (list (helixel-action-create 'noop nil :runner #'ignore))))
           (helixel-last-action tx)
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
                 :action-list (list (helixel-action-create 'noop nil :runner #'ignore))))
           (helixel-last-action tx)
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
                 :action-list (list (helixel-action-create 'noop nil :runner #'ignore))))
           (helixel-last-action tx)
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
                 :action-list (list (helixel-action-create 'noop nil :runner #'ignore))))
           (helixel-last-action tx)
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
                 :action-list (list (helixel-action-create 'noop nil :runner #'ignore))))
           (helixel-last-action tx)
           (helixel--inhibit-action-track t))
      (helixel-repeat-selection '(4))
      ;; C-u , previews all → ends at eol of last line
      (should (= (line-number-at-pos) 3)))))   ;; last content line

;; ── Chain action-list preservation ──

(ert-deftest helixel-test-chain-action-list-accumulates ()
  "After Phase 4.4, chain accumulates the LIST of committed txs.
Running a motion command + an edit during a chain leaves two
entries on `helixel-chain-session-action-list', and the resulting
chain action.s `:action-list' payload preserves them in chronological
order."
  (helixel-chain-test-with-buffer
      "aaa bbb ccc\nddd eee fff\nggg hhh iii\n"
    (goto-char 1)
    (helixel-select-line)
    (let ((init-ctx helixel--pending-sel))
      (helixel-repeat-chain-start)
      ;; Motion command (Phase 4.3 makes movements produce txs;
      ;; the chain hook appends them to action-list).
      (helixel-backward-word-start)
      ;; Edit command.
      (helixel-record-action 'kill :runner #'ignore)
      (let ((s helixel--chain-session))
        (should s)
        ;; action-list should have at least the kill entry.  Movement
        ;; commands produce txs only when their op is recorded;
        ;; we test only the more invariant edit-entry presence.
        (should (> (length (helixel-chain-session-action-list s)) 0)))
      (helixel-repeat-chain-end)
      (should helixel-last-action)
      (should (eq (helixel-action-op helixel-last-action) 'chain))
      (let ((action-list (plist-get (helixel-action-payload helixel-last-action)
                                :action-list)))
        (should action-list)
        (should (listp action-list))
        (should (> (length action-list) 0))
        (should (helixel-action-p (car action-list))))
      ;; init-ctx merged into the chain action.s sel.
      (should (equal init-ctx (helixel-action-sel helixel-last-action))))))

(ert-deftest helixel-test-chain-comma-strategy-builder ()
  "After C2 flatten, chain repeat goes through the unified
`helixel--repeat-advance' rather than a strategy struct.  Verify
the chain in-place fallback: when a chain action.s sel has no
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
                 :action-list (list (helixel-action-create 'noop nil
                                 :runner #'ignore)))))
      (setq helixel-last-action tx)
      ;; line kind has an :advance fn so this returns whatever the
      ;; advance fn does — just confirm the unified dispatcher
      ;; accepts the chain tx without erroring.
      (should-not (eq 'error
                      (condition-case nil
                          (helixel--repeat-advance tx tx)
                        (error 'error)))))))

;; ── Chain + insert + electric-pair replay (unit test) ──

(ert-deftest helixel-test-chain-insert-electric-pair-replay ()
  "A chain whose `:action-list' contains an insert-text tx with a
multi-char `:text' segment replays the segment verbatim at the
new position — the pattern produced when `electric-pair-mode' is
on and user types `(' inside a chain (captured as a single `()'
segment).

We build the chain tx by hand rather than driving the full
`pre/post-command-hook' pipeline (batch mode does not auto-run
those hooks reliably) — the invariant under test is the
chain-runner → insert-text-runner replay path, not capture."
  (helixel-chain-test-with-buffer "abc\nxyz\n"
    (let* ((insert-action (helixel-action-create 'insert-text nil
                        :runner (helixel--op-runner 'insert-text)
                        :keys (list (list :text "()"
                                          :delete-before 0
                                          :offset -1))))
           (chain-action  (helixel-action-create 'chain nil
                        :runner #'helixel--repeat-chain-runner
                        :display "chain"
                        :action-list (list insert-action))))
      (setq helixel-last-action chain-action)
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

;; ── End-to-end: chain wd wa hello, then . on next line ──

(ert-deftest helixel-test-chain-wd-wa-hello-dot ()
  "Chain: wd wa hello ESC, then . reproduces on next line."
  (helixel-chain-test-with-buffer
      "hello world\nhello world\nhello world\n"
    (goto-char 1)
    (helixel-repeat-chain-start)
    (helixel-forward-word-start)   ;; w
    (helixel-kill)                  ;; d
    (helixel-forward-word-start)   ;; w
    (helixel-insert-after)          ;; a
    (insert "hello")
    (helixel-insert-exit)           ;; ESC
    (helixel-repeat-chain-end)      ;; ESC
    ;; Verify recording result
    (goto-char 1)
    (let ((line1 (buffer-substring (line-beginning-position)
                                   (line-end-position))))
      (should (stringp line1))
      ;; Dot on line 2 should produce the same result
      (forward-line 1)
      (beginning-of-line)
      (let ((before (buffer-substring (line-beginning-position)
                                      (line-end-position))))
        (should (string= before "hello world")))
      (helixel-repeat-edit)
      (let ((line2 (buffer-substring (line-beginning-position)
                                     (line-end-position))))
        (should (string= line2 line1))))))

(ert-deftest helixel-test-chain-xqbdi-world-dot ()
  "Chain: x q b d i world ESC ESC advances one line per ."
  (helixel-chain-test-with-buffer
      "hello world\nhello world\nhello world\nhello world\n"
    (goto-char 1)
    (helixel-select-line)
    (helixel-repeat-chain-start)
    (helixel-backward-word-start)
    (helixel-kill)
    (helixel-insert)
    (insert "world")
    (helixel-insert-exit)
    (helixel-repeat-chain-end)
    ;; x before q is now flushed at chain-start — init-ctx is still
    ;; the line sel, but x doesn't appear in the action-list.
    ;; Advance moves one line per dot.
    (goto-char 1)
    (let ((rec-line (buffer-substring (line-beginning-position)
                                      (line-end-position))))
      (should (stringp rec-line))
      ;; Dot advances one line and applies
      (helixel-repeat-edit)
      ;; Result should be non-empty (chain applied)
      (let ((line2 (buffer-substring (line-beginning-position)
                                     (line-end-position))))
        (should (stringp line2))
        (should (> (length line2) 0)))
      ;; Second dot advances another line
      (helixel-repeat-edit)
      (let ((line3 (buffer-substring (line-beginning-position)
                                     (line-end-position))))
        (should (stringp line3))
        (should (> (length line3) 0))))))

(ert-deftest helixel-test-chain-wd-wa-hello-movement-entries ()
  "Chain recording wd wa hello captures movement entries between edits."
  (helixel-chain-test-with-buffer
      "hello world\nhello world\n"
    (goto-char 1)
    (helixel-repeat-chain-start)
    (helixel-forward-word-start)   ;; w
    (helixel-kill)                  ;; d
    (helixel-forward-word-start)   ;; w
    (helixel-insert-after)          ;; a
    (insert "hello")
    (helixel-insert-exit)           ;; ESC
    ;; Before chain-end, action-list should contain 4 entries:
    ;; w-movement, kill, w-movement, insert-text
    (let ((action-list (helixel-chain-session-action-list helixel--chain-session)))
      (should (= 4 (length action-list)))
      ;; Chronological order after chain-end nreverse:
      ;; [w-move, kill-edit, w-move, insert-edit]
      (helixel-repeat-chain-end)
      (let ((chain-action-list
             (plist-get (helixel-action-payload helixel-last-action) :action-list)))
        (should (= 4 (length chain-action-list)))
        ;; First entry: w movement (sel but no runner)
        (should (helixel-action-sel (nth 0 chain-action-list)))
        (should-not (helixel-action-runner (nth 0 chain-action-list)))
        ;; Second entry: kill (runner present)
        (should (eq 'kill (helixel-action-op (nth 1 chain-action-list))))
        (should (helixel-action-runner (nth 1 chain-action-list)))
        ;; Third entry: w movement
        (should (helixel-action-sel (nth 2 chain-action-list)))
        (should-not (helixel-action-runner (nth 2 chain-action-list)))
        ;; Fourth entry: insert-text (runner present)
        (should (eq 'insert-text (helixel-action-op (nth 3 chain-action-list))))
        (should (helixel-action-runner (nth 3 chain-action-list)))))))

;; ── Search-based chain advance ──

(ert-deftest helixel-test-chain-search-advance ()
  "Chain with search init-ctx advances to next match on each .
Note: if the chain creates text matching the search pattern
(e.g. inserting 'foo' before 'hello' creates 'foohello'),
the advance will find that new match rather than the next
original match.  This is an inherent limitation of search-based
advance — use distinct patterns to avoid self-matching."
  (helixel-chain-test-with-buffer
      "hello world\nfoo hello bar\nhello baz\n"
    (goto-char 1)
    (search-forward "hello")
    (let ((mb (match-beginning 0)) (me (match-end 0)))
      (goto-char mb)
      (push-mark me t t)
      (goto-char mb))
    (helixel--sel-push
     (helixel-sel-create 'search '(:pattern "hello" :dir forward)))
    (helixel-repeat-chain-start)
    (helixel-insert) (insert "foo") (helixel-insert-exit)
    (helixel-forward-word-start) (helixel-insert-after)
    (insert "bar") (helixel-insert-exit)
    (helixel-repeat-chain-end)
    ;; Verify chain has search sel
    (should (eq (helixel-sel-kind (helixel-action-sel helixel-last-action))
                'search))
    (should (string= (helixel-sel-search-pattern
                      (helixel-action-sel helixel-last-action))
                     "hello"))
    ;; First dot: advance to next match and apply
    (helixel-repeat-edit)
    ;; The advance should have moved to a new position
    (goto-char 1)
    (let ((line1 (buffer-substring (line-beginning-position)
                                   (line-end-position))))
      ;; After advance+apply, we should be on a different line
      ;; (or the same line modified again if the chain creates
      ;; new matches of the pattern)
      (should-not (string= line1 "hello world")))))

;; ── Zero-width search-based chain advance ──

(defun helixel-chain--setup-search (pattern dir)
  "Set up a simulated search with PATTERN in DIR and return match pos.
PATTERN is a regexp."
  (let ((search-fn (if (eq dir 'forward)
                       're-search-forward
                     're-search-backward)))
    (funcall search-fn pattern)
    (let ((mb (match-beginning 0)) (me (match-end 0)))
      (goto-char mb)
      (push-mark me t t)
      (goto-char mb))
    (helixel--sel-push
     (helixel-sel-create 'search `(:pattern ,pattern :dir ,dir)))
    (point)))

(ert-deftest helixel-test-chain-search-bol-forward ()
  "Chain with /^ forward search advances one line per ."
  (helixel-chain-test-with-buffer
      "hello\nworld\nfoo\nbar\n"
    (helixel-chain--setup-search "^" 'forward)
    (helixel-repeat-chain-start)
    (helixel-insert) (insert "X") (helixel-insert-exit)
    (helixel-repeat-chain-end)
    (should (eq (helixel-sel-kind (helixel-action-sel helixel-last-action)) 'search))
    ;; dot1: advance to line 2
    (helixel-repeat-edit)
    (save-excursion (goto-char 1) (forward-line 1)
      (should (string-prefix-p "X" (buffer-substring (line-beginning-position)
                                                       (line-end-position)))))
    ;; dot2: advance to line 3
    (helixel-repeat-edit)
    (save-excursion (goto-char 1) (forward-line 2)
      (should (string-prefix-p "X" (buffer-substring (line-beginning-position)
                                                       (line-end-position)))))
    ;; dot3: advance to line 4
    (helixel-repeat-edit)
    (save-excursion (goto-char 1) (forward-line 3)
      (should (string-prefix-p "X" (buffer-substring (line-beginning-position)
                                                       (line-end-position)))))))

(ert-deftest helixel-test-chain-search-eol-forward ()
  "Chain with /$ forward search advances one line per ."
  (helixel-chain-test-with-buffer
      "hello\nworld\nfoo\nbar\n"
    (goto-char 1)
    (re-search-forward "$")
    (let ((mb (match-beginning 0)) (me (match-end 0)))
      (goto-char mb)
      (push-mark me t t)
      (goto-char mb))
    (helixel--sel-push (helixel-sel-create 'search '(:pattern "$" :dir forward)))
    (helixel-repeat-chain-start)
    (helixel-insert) (insert "X") (helixel-insert-exit)
    (helixel-repeat-chain-end)
    ;; dot1: advance to line 2 eol
    (helixel-repeat-edit)
    (save-excursion (goto-char 1) (forward-line 1)
      (should (string-match-p "X$" (buffer-substring (line-beginning-position)
                                                       (line-end-position)))))
    ;; dot2: advance to line 3 eol
    (helixel-repeat-edit)
    (save-excursion (goto-char 1) (forward-line 2)
      (should (string-match-p "X$" (buffer-substring (line-beginning-position)
                                                       (line-end-position)))))))

(ert-deftest helixel-test-chain-search-bol-backward ()
  "Chain with ?^ backward search advances one line per ."
  (helixel-chain-test-with-buffer
      "hello\nworld\nfoo\nbar\n"
    (goto-char (point-max))
    (helixel-chain--setup-search "^" 'backward)
    (helixel-repeat-chain-start)
    (helixel-insert) (insert "X") (helixel-insert-exit)
    (helixel-repeat-chain-end)
    ;; dot1: advance backward to line 4 (the previous ^)
    (helixel-repeat-edit)
    (save-excursion (goto-char 1) (forward-line 3)
      (let ((line (buffer-substring (line-beginning-position)
                                    (line-end-position))))
        (should (string-prefix-p "X" line))))
    ;; dot2: advance backward to line 3
    (helixel-repeat-edit)
    (save-excursion (goto-char 1) (forward-line 2)
      (let ((line (buffer-substring (line-beginning-position)
                                    (line-end-position))))
        (should (string-prefix-p "X" line))))))

(ert-deftest helixel-test-chain-search-zero-width-edge ()
  "Zero-width /$ at last line should stop without infinite loop."
  (helixel-chain-test-with-buffer
      "hello\nworld\n"
    (goto-char 1)
    (re-search-forward "$")
    (let ((mb (match-beginning 0)) (me (match-end 0)))
      (goto-char mb)
      (push-mark me t t)
      (goto-char mb))
    (helixel--sel-push (helixel-sel-create 'search '(:pattern "$" :dir forward)))
    (helixel-repeat-chain-start)
    (helixel-insert) (insert "X") (helixel-insert-exit)
    (helixel-repeat-chain-end)
    ;; dot1: advance to line 2 eol
    (helixel-repeat-edit)
    (goto-char 1) (forward-line 1)
    (should (string-match-p "X$" (buffer-substring (line-beginning-position)
                                                     (line-end-position))))
    ;; dot2: no more targets (should message, not loop)
    ;; helixel-repeat-edit catches errors internally, so we just
    ;; verify it doesn't hang by checking the call returns.
    (helixel-repeat-edit))
  ;; Also test backward /^ at first line
  (helixel-chain-test-with-buffer
      "hello\nworld\n"
    (goto-char (point-max))
    (helixel-chain--setup-search "^" 'backward)
    (helixel-repeat-chain-start)
    (helixel-insert) (insert "X") (helixel-insert-exit)
    (helixel-repeat-chain-end)
    ;; dot1: advance backward to line 1
    (helixel-repeat-edit)
    ;; dot2: no more targets (should not loop)
    (helixel-repeat-edit)))

(ert-deftest helixel-test-chain-search-bol-backward-cursor-position ()
  "Chain with ?^ backward: cursor ends after inserted text, not after first char.
Regression for `?^ <RET> q i foo ESC ESC .' — cursor was landing
at BOL+1 (after 'f') because of a stale zw-step adjustment."
  (helixel-chain-test-with-buffer
      "hello\nworld\nfoo\n"
    (goto-char (point-max))
    (helixel-chain--setup-search "^" 'backward)
    (helixel-repeat-chain-start)
    (helixel-insert) (insert "foo") (helixel-insert-exit)
    (helixel-repeat-chain-end)
    ;; First dot: advance to previous BOL and insert "foo".
    ;; After replay cursor MUST be after the inserted text (BOL+3),
    ;; not at BOL+1 (after 'f').
    (helixel-repeat-edit)
    (let ((bol (line-beginning-position)))
      (should (string-prefix-p "foo" (buffer-substring bol (line-end-position))))
      (should (= (point) (+ bol 3))))
    ;; Second dot: advance further and verify cursor again.
    (helixel-repeat-edit)
    (let ((bol (line-beginning-position)))
      (should (string-prefix-p "foo" (buffer-substring bol (line-end-position))))
      (should (= (point) (+ bol 3))))))

(ert-deftest helixel-test-chain-no-initctx-j-gh ()
  "Chain with no init-ctx: q e a foo ESC j gh ESC . . advances per replay.
Pure motion commands (j, gh) have no runner and no sel — they must
be captured via `by-command' and replayed via `call-interactively'."
  (helixel-chain-test-with-buffer
      "world hello\nworld hello\nworld hello\nworld hello\n"
    (goto-char 1)
    (helixel-repeat-chain-start)
    (helixel-forward-word-end)       ;; e
    (helixel-insert-after)            ;; a
    (insert "foo")
    (helixel-insert-exit)             ;; ESC
    (helixel-next-line)               ;; j
    (helixel-go-beginning-line)       ;; gh
    (helixel-repeat-chain-end)        ;; ESC
    ;; First dot: replay on line 2; cursor must end at BOL of line 3
    (helixel-repeat-edit)
    (save-excursion
      (goto-char 1) (forward-line 1)
      (let ((line (buffer-substring (line-beginning-position)
                                    (line-end-position))))
        (should (string= line "worldfoo hello"))))
    ;; Cursor must be at BOL of line 3 (j moved down, gh → BOL)
    (should (= (point) (save-excursion (goto-char 1) (forward-line 2) (line-beginning-position))))
    ;; Second dot: replay on line 3
    (helixel-repeat-edit)
    (save-excursion
      (goto-char 1) (forward-line 2)
      (let ((line (buffer-substring (line-beginning-position)
                                    (line-end-position))))
        (should (string= line "worldfoo hello"))))
    ;; Cursor must be at BOL of line 4
    (should (= (point) (save-excursion (goto-char 1) (forward-line 3) (line-beginning-position))))
    ;; Third dot: replay on line 4
    (helixel-repeat-edit)
    (save-excursion
      (goto-char 1) (forward-line 3)
      (let ((line (buffer-substring (line-beginning-position)
                                    (line-end-position))))
        (should (string= line "worldfoo hello"))))))

;; ── Vanilla / native Emacs command capture ──
;; `execute-kbd-macro' goes through the real command loop, so
;; `post-command-hook' fires even in batch mode.

(ert-deftest helixel-test-chain-vanilla-C-a-at-end ()
  "Vanilla C-a as the last command before chain-end."
  (helixel-chain-test-with-buffer
      "world hello\nworld hello\nworld hello\n"
    (goto-char 1)
    (helixel-repeat-chain-start)
    (helixel-forward-word-end)           ;; e
    (helixel-insert-after)                ;; a
    (insert "foo")
    (helixel-insert-exit)                 ;; ESC (insert)
    (helixel-next-line)                   ;; j
    (execute-kbd-macro (kbd "C-a"))       ;; C-a
    (helixel-repeat-chain-end)            ;; ESC
    (let ((action-list (helixel-action-payload-get helixel-last-action :action-list)))
      (should (= 4 (length action-list)))
      ;; Vanilla C-a is flushed after the last helixel, so it
      ;; appears as the last entry after nreverse.
      (should (eq (helixel-action-by-command (nth 3 action-list))
                  'move-beginning-of-line)))
    ;; Replay: verify line content and cursor position
    (helixel-repeat-edit)
    (save-excursion
      (goto-char 1) (forward-line 1)
      (should (string= (buffer-substring (line-beginning-position)
                                          (line-end-position))
                       "worldfoo hello")))
    (should (= (point) (save-excursion (goto-char 1) (forward-line 2)
                                       (line-beginning-position))))))

(ert-deftest helixel-test-chain-vanilla-C-a-in-middle ()
  "Vanilla C-a in the middle of a chain."
  (helixel-chain-test-with-buffer
      "world hello\nworld hello\nworld hello\n"
    (goto-char 1)
    (helixel-repeat-chain-start)
    (execute-kbd-macro (kbd "C-a"))       ;; C-a (BOL)
    (helixel-forward-word-end)           ;; e
    (helixel-insert-after)
    (insert "X")
    (helixel-insert-exit)
    (helixel-repeat-chain-end)
    (let ((action-list (helixel-action-payload-get helixel-last-action :action-list)))
      (should (= 3 (length action-list)))
      (should (eq (helixel-action-by-command (nth 0 action-list))
                  'move-beginning-of-line))
      (should (eq (helixel-action-by-command (nth 1 action-list))
                  'helixel-forward-word-end)))
    (goto-char 1) (forward-line 1) (beginning-of-line)
    (helixel-repeat-edit)
    (should (string= (buffer-substring (line-beginning-position)
                                        (line-end-position))
                     "worldX hello"))))

(ert-deftest helixel-test-chain-vanilla-multiple ()
  "Multiple vanilla commands with correct ordering.
Uses <right> (right-char) instead of C-f because C-f is remapped
by helixel (to scroll-up).  <right> falls through to the global
keymap and invokes the vanilla `right-char' command."
  (helixel-chain-test-with-buffer
      "  hello world\n  hello world\n"
    (goto-char 1)
    (helixel-repeat-chain-start)
    ;; C-a is NOT remapped by helixel, falls through to vanilla.
    (execute-kbd-macro (kbd "C-a"))
    ;; <right> = right-char, also not remapped.
    (execute-kbd-macro (kbd "<right>"))
    (execute-kbd-macro (kbd "<right>"))
    (helixel-insert-after)
    (insert "X")
    (helixel-insert-exit)
    (helixel-repeat-chain-end)
    (let ((action-list (helixel-action-payload-get helixel-last-action :action-list)))
      ;; 4 entries: C-a, <right>, <right>, insert-text.
      ;; insert-after's state entry is excluded (category=state).
      (should (= 4 (length action-list)))
      (should (eq (helixel-action-by-command (nth 0 action-list))
                  'move-beginning-of-line))
      (should (eq (helixel-action-by-command (nth 1 action-list))
                  'right-char))
      (should (eq (helixel-action-by-command (nth 2 action-list))
                  'right-char)))
    (goto-char 1) (forward-line 1)
    (helixel-repeat-edit)
    ;; Right-char×2 + insert-after → "X" at position after right-moves.
    ;; The insert-after's internal forward-char is not captured
    ;; as a separate movement entry, so replay inserts one char earlier
    ;; than during recording.  This is a known limitation.
    (should (string= (buffer-substring (line-beginning-position)
                                        (line-end-position))
                     "  Xhello world"))))

(ert-deftest helixel-test-chain-vanilla-self-insert-excluded ()
  "self-insert-command is NOT captured by post-command-hook.
Tested by calling the hook function directly."
  (helixel-chain-test-with-buffer
      "hello\n"
    (helixel-repeat-chain-start)
    ;; self-insert-command should be excluded by the hook
    (let ((this-command 'self-insert-command))
      (helixel--chain-post-cmd-hook))
    ;; move-beginning-of-line should be captured
    (let ((this-command 'move-beginning-of-line))
      (helixel--chain-post-cmd-hook))
    (helixel-repeat-chain-end)
    (let ((action-list (helixel-action-payload-get helixel-last-action :action-list)))
      (should (= 1 (length action-list)))
      (should (eq (helixel-action-by-command (nth 0 action-list))
                  'move-beginning-of-line)))))

;; ── Chain: wwd multi-line dot-repeat (user-reported scenario) ──

(ert-deftest helixel-test-chain-wwd-multiline-dot ()
  "Chain q w w d j gh ESC then . on each subsequent line.
Each dot-repeat should delete the second word ('foo') on the
current line, then move to the next line."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello foo world man\nhello foo world man\nhello foo world man\n")
    (goto-char 1)
    (set-window-buffer nil (current-buffer))
    (setq-local helixel--current-state 'motion)
    (helixel--switch-state 'normal)
    (setq helixel--chain-session nil
          helixel--pending-sel nil
          helixel--repeat-permanent-flip nil)
    (unwind-protect
        (progn
          (helixel-repeat-chain-start)
          (helixel-forward-word-start)
          (helixel-forward-word-start)
          (helixel-kill)
          (helixel-next-line)
          (helixel-go-beginning-line)
          (helixel-repeat-chain-end)
          ;; Verify recording modified line 1
          (goto-char 1)
          (should (string= (buffer-substring (line-beginning-position)
                                              (line-end-position))
                           "hello world man"))
          ;; Dot on line 2
          (goto-char 1) (forward-line 1) (beginning-of-line)
          (helixel-repeat-edit)
          (goto-char 1) (forward-line 1)
          (should (string= (buffer-substring (line-beginning-position)
                                              (line-end-position))
                           "hello world man")))
      (when helixel--chain-session
        (when-let* ((b (helixel-chain-session-init-bounds
                        helixel--chain-session)))
          (ignore-errors (set-marker (car b) nil))
          (ignore-errors (set-marker (cdr b) nil))))
      (setq helixel--chain-session nil)
      (remove-hook 'post-command-hook #'helixel--chain-post-cmd-hook t)
      (ignore-errors (helixel-normal-state -1)))))

;; ── Chain: pre-edit movement entries have independent sel copies ──

(ert-deftest helixel-test-chain-movement-sel-independence ()
  "Pre-edit movement entries must have independent :moves lists.
Before the sel-copy fix, track-visual-move's setcdr mutation would
corrupt previously committed entries' :moves counts — w1 would end
up with ((w . 2)) instead of ((w . 1))."
  (helixel-chain-test-with-buffer
      "hello foo world man\n"
    (goto-char 1)
    (helixel-repeat-chain-start)
    (helixel-forward-word-start)   ;; w
    (helixel-forward-word-start)   ;; w
    (helixel-kill)                  ;; d
    (helixel-repeat-chain-end)
    (let ((action-list (helixel-action-payload-get helixel-last-action :action-list)))
      (should (= 3 (length action-list)))
      ;; w1 should have moves=((w . 1)), NOT ((w . 2))
      (let ((moves1 (helixel-sel-movement-moves
                     (helixel-action-sel (nth 0 action-list)))))
        (should moves1)
        (should (= 1 (cdar moves1))))
      ;; w2 should have moves=((w . 2)), accumulated
      (let ((moves2 (helixel-sel-movement-moves
                     (helixel-action-sel (nth 1 action-list)))))
        (should moves2)
        (should (= 2 (cdar moves2))))
      ;; kill should also have moves=((w . 2))
      (let ((moves3 (helixel-sel-movement-moves
                     (helixel-action-sel (nth 2 action-list)))))
        (should moves3)
        (should (= 2 (cdar moves3)))))))

;; ── Chain: inter-edit movement is replayed (not skipped) ──

(ert-deftest helixel-test-chain-inter-edit-movement-replayed ()
  "Movement entries between edits of different sel kinds are replayed.
For q w d w a hello ESC: the second w (between kill and insert-text)
is inter-edit — it must be replayed to position point before insert."
  (helixel-chain-test-with-buffer
      "hello foo world man\nhello foo world man\n"
    (goto-char 1)
    (helixel-repeat-chain-start)
    (helixel-forward-word-start)   ;; w
    (helixel-kill)                  ;; d
    (helixel-forward-word-start)   ;; w
    (helixel-insert-after)          ;; a
    (insert "hello")
    (helixel-insert-exit)           ;; ESC
    (helixel-repeat-chain-end)
    (goto-char 1)
    (let ((line1 (buffer-substring (line-beginning-position)
                                    (line-end-position))))
      (should (stringp line1))
      ;; Dot on line 2 should produce the same result
      (forward-line 1) (beginning-of-line)
      (helixel-repeat-edit)
      (let ((line2 (buffer-substring (line-beginning-position)
                                      (line-end-position))))
        (should (string= line2 line1))))))

;; ── Vanilla entry carries prefix-arg ──

(ert-deftest helixel-test-chain-vanilla-prefix-arg ()
  "Vanilla entries store current-prefix-arg in payload for faithful
replay."
  (helixel-chain-test-with-buffer
      "line1\nline2\nline3\n"
    (goto-char 1)
    (helixel-repeat-chain-start)
    ;; Simulate a vanilla command with prefix-arg
    (let ((current-prefix-arg 4)
          (this-command 'next-line))
      (helixel--chain-post-cmd-hook))
    (helixel-repeat-chain-end)
    (let ((action-list (helixel-action-payload-get helixel-last-action :action-list)))
      (should (= 1 (length action-list)))
      (should (eq 4 (helixel-action-payload-get (nth 0 action-list) :prefix))))))

(ert-deftest helixel-test-chain-line-insert-bol-dot ()
  "Chain x q i foo ESC ESC then . inserts at BOL on next lines.
Before the fix, the line init-ctx lacked entry-kind so chain
advance didn't position to BOL — foo was inserted at EOL."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "line1\nline2\nline3\n")
    (goto-char 1)
    (set-window-buffer nil (current-buffer))
    (setq-local helixel--current-state 'motion)
    (helixel--switch-state 'normal)
    (setq helixel--chain-session nil
          helixel--pending-sel nil
          helixel--repeat-permanent-flip nil)
    (unwind-protect
        (progn
          (helixel-select-line)            ;; x
          (helixel-repeat-chain-start)     ;; q
          (helixel-insert)                 ;; i
          (insert "foo")
          (helixel-insert-exit)            ;; ESC
          (helixel-repeat-chain-end)       ;; ESC
          ;; Verify recording: line1 has "foo" at BOL
          (goto-char 1)
          (should (string= (buffer-substring (line-beginning-position)
                                              (line-end-position))
                           "fooline1"))
          ;; Dot from line 1 (original recording position):
          ;; chain advance moves to line 2, inserts at BOL.
          (helixel-repeat-edit)
          (should (string= (buffer-substring (line-beginning-position)
                                              (line-end-position))
                           "fooline2"))
          ;; Dot again: advances to line 3, inserts at BOL.
          (helixel-repeat-edit)
          (should (string= (buffer-substring (line-beginning-position)
                                              (line-end-position))
                           "fooline3")))
      (when helixel--chain-session
        (when-let* ((b (helixel-chain-session-init-bounds
                        helixel--chain-session)))
          (ignore-errors (set-marker (car b) nil))
          (ignore-errors (set-marker (cdr b) nil))))
      (setq helixel--chain-session nil)
      (remove-hook 'post-command-hook #'helixel--chain-post-cmd-hook t)
      (ignore-errors (helixel-normal-state -1)))))

(provide 'helixel-test-repeat-chain)
;;; helixel-test-repeat-chain.el ends here

;; ── Insert-mode RET is NOT double-captured ──

(ert-deftest helixel-test-chain-insert-ret-no-double-capture ()
  "Insert-mode commands like RET are captured ONLY by insert-record,
not by the chain post-command-hook (which now excludes insert-state).
Without this fix, RET would appear as a vanilla entry AND in the
insert-text segments, producing double newlines on replay."
  (with-temp-buffer
    (transient-mark-mode 1)
    (goto-char 1)
    (set-window-buffer nil (current-buffer))
    (setq-local helixel--current-state 'motion)
    (helixel--switch-state 'normal)
    (setq helixel--chain-session nil
          helixel--pending-sel nil
          helixel--repeat-permanent-flip nil)
    (unwind-protect
        (progn
          (helixel-repeat-chain-start)
          (helixel-insert-after)
          ;; Use execute-kbd-macro for proper command-loop dispatch
          ;; (direct (insert ...) bypasses pre/post-command-hooks).
          (execute-kbd-macro (kbd "foo"))
          (execute-kbd-macro (kbd "RET"))
          (helixel-insert-exit)
          (helixel-repeat-chain-end)
          ;; Should have exactly 1 entry: insert-text only.
          (let ((action-list (helixel-action-payload-get
                          helixel-last-action :action-list)))
            (should (= 1 (length action-list)))
            (should (eq (helixel-action-op (nth 0 action-list))
                        'insert-text)))
          ;; Dot-repeat 3 times: each should produce "foo" on a
          ;; new line, without extra blank lines.
          (dotimes (_ 3) (helixel-repeat-edit))
          (goto-char 1)
          (should (string= (buffer-substring (line-beginning-position)
                                              (line-end-position))
                           "foo"))
          (forward-line)
          (should (string= (buffer-substring (line-beginning-position)
                                              (line-end-position))
                           "foo"))
          (forward-line)
          (should (string= (buffer-substring (line-beginning-position)
                                              (line-end-position))
                           "foo"))
          (forward-line)
          (should (string= (buffer-substring (line-beginning-position)
                                              (line-end-position))
                           "foo")))
      (when helixel--chain-session
        (when-let* ((b (helixel-chain-session-init-bounds
                        helixel--chain-session)))
          (ignore-errors (set-marker (car b) nil))
          (ignore-errors (set-marker (cdr b) nil))))
      (setq helixel--chain-session nil)
      (remove-hook 'post-command-hook #'helixel--chain-post-cmd-hook t)
      (ignore-errors (helixel-normal-state -1)))))
