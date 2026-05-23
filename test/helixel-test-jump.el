;;; helixel-test-jump.el --- Tests for Helixel: jump navigation  -*- lexical-binding: t; -*-

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

;;; Jump navigation tests

(ert-deftest helixel-test-jump-empty-list ()
  "C-o with empty jump list says no positions."
  (let ((helixel--jump-list nil)
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
  (let ((helixel--jump-list nil)
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
  (let ((helixel--jump-list nil)
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
  (let ((helixel--jump-list nil)
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
  (let ((helixel--jump-list nil)
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
  (let ((helixel--jump-list nil)
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

;; ============================================================================
;; P0.1: ring-head sync — verify pick replays full payload
;; ============================================================================

(ert-deftest helixel-test-repeat-pick-change-end-to-end ()
  "After ciwX<esc>, `helixel-repeat-edit-pick' replays the change correctly.
Verifies that `helixel-insert-exit' syncs `helixel--last-tx' payload
with the ring head so the picker sees the full transaction."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-change-thing-at-point)
    (helixel-change-thing-at-point)
    (insert "X")
    (helixel-insert-exit)
    ;; Verify action ring entry has the payload via :edit
    (should (plist-get (helixel-edit-payload
                        (plist-get (car helixel--action-ring) :edit))
                       :inserted-text))
    (should (string= (plist-get
                      (helixel-edit-payload
                       (plist-get (car helixel--action-ring) :edit))
                      :inserted-text)
                     "X"))
    ;; Action ring entry's :edit should be eq to last-tx
    (should (eq (plist-get (car helixel--action-ring) :edit)
                helixel--last-tx))
    ;; Picking the first entry replays correctly
    (goto-char 4)
    (setq helixel--last-tx
          (plist-get (car helixel--action-ring) :edit))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "X X foo"))))

(ert-deftest helixel-test-repeat-pick-insert-end-to-end ()
  "After iZ<esc>, ring head has :text payload; pick replays correctly."
  (let ((helixel--last-tx nil)
        (helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "abc"
      (set-match-data nil) ; clear stale match data from prior tests
      (goto-char 2)
        (setq last-command nil this-command 'helixel-insert)
        (helixel-insert)
        (insert "Z")
        (helixel-insert-exit)
        ;; Verify action ring entry has :text payload via :edit
        (should (plist-get (helixel-edit-payload
                            (plist-get (car helixel--action-ring) :edit))
                           :text))
        (should (string=
                 (plist-get (helixel-edit-payload
                             (plist-get (car helixel--action-ring) :edit))
                            :text)
                 "Z"))
        (should (eq (plist-get (car helixel--action-ring) :edit)
                    helixel--last-tx))
        (goto-char 4)
        (setq helixel--last-tx
              (plist-get (car helixel--action-ring) :edit))
        (helixel-repeat-edit)
        (should (string= (buffer-string) "aZbZc")))))

;; ============================================================================
;; P0.2: undo amalgamation — `.` produces a single undo step
;; ============================================================================

(ert-deftest helixel-test-repeat-undo-amalgamation ()
  "`.` (change replay) is a single undo step.
ciw X <esc> creates two buffer changes (kill + insert).  When `.`
replays them, undo should restore the pre-repeat state in one step."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 1)
    ;; Enable undo in this temp buffer
    (setq buffer-undo-list nil)
    ;; Record: ciw X <esc>
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-change-thing-at-point)
    (helixel-change-thing-at-point)
    (insert "X")
    (helixel-insert-exit)
    (should (string= (buffer-string) "X world foo"))
    ;; Repeat at "world"
    (goto-char 4)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "X X foo"))
    ;; Single undo should restore to "X world foo"
    (let ((last-command nil))
      (undo-only))
    (should (string= (buffer-string) "X world foo"))))

;; ============================================================================
;; P1.1: track-visual-move no-op during replay
;; ============================================================================

(ert-deftest helixel-test-repeat-track-visual-move-no-leak ()
  "`helixel--track-visual-move' does not leak state during dot-repeat replay.
Movement commands called during selection recreation should not
modify `helixel--repeat-sel-ctx'."
  (helixel-test-with-buffer "hello world foo bar"
    (goto-char 1)
    ;; Record a v w w d sequence
    (helixel--switch-state 'visual)
    (setq last-command nil this-command 'helixel-forward-word-start)
    (helixel-forward-word-start)
    (helixel-forward-word-start)
    (setq last-command 'helixel-forward-word-start
          this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (helixel--switch-state 'normal)
    ;; After kill, remaining is "foo bar"
    (should (string= (buffer-string) "foo bar"))
    ;; Save the stored sel-ctx
    (let ((stored-sel (copy-sequence (helixel-edit-sel helixel--last-tx))))
      ;; Replay
      (goto-char 1)
      (helixel-repeat-edit)
      ;; helixel--repeat-sel-ctx should be nil after consumption
      (should (null helixel--repeat-sel-ctx))
      ;; Should be "bar" after second kill (killed "foo ")
      (should (string= (buffer-string) "bar"))
      ;; The stored tx should be unchanged
      (should (equal (helixel-edit-sel helixel--last-tx) stored-sel)))))

;; ============================================================================
;; P1.2: rect change replay does not switch state
;; ============================================================================

(ert-deftest helixel-test-repeat-rect-change-no-state-switch ()
  "Rect change replay via `.` does not call `helixel-insert-exit'.
It should only run `helixel--rect-replay' without switching to insert
and back."
  (helixel-test-with-buffer "aaa\nbbb\nccc\n"
    (goto-char 1)
    ;; Select rect 2 lines, then change
    (helixel--switch-state 'visual)
    (setq helixel--current-state 'visual)
    (push-mark (point) t t)
    (goto-char 5)
    (rectangle-mark-mode 1)
    (setq helixel--selection-type 'rect)
    (setq last-command nil this-command 'helixel-change-thing-at-point)
    (helixel-change-thing-at-point)
    (insert "X")
    (helixel-insert-exit)
    (helixel--switch-state 'normal)
    (should (eq helixel--current-state 'normal))
    ;; Remember state before replay
    (let ((pre-state helixel--current-state))
      (helixel-repeat-edit)
      ;; State should be unchanged
      (should (eq helixel--current-state pre-state)))))

;; ============================================================================
;; End-to-end: search + insert with cursor movement + n .
;; ============================================================================

(ert-deftest helixel-test-repeat-search-insert-c-f-n-dot ()
  "Scenario: /hello<RET> i C-f foo<ESC> n . inserts foo at cursor offset.
Cursor-offset is set manually in sel ctx to simulate forward-char."
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (re-search-forward "hello")
    (let ((isearch-success t)
          (isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-other-end (match-beginning 0)))
      (helixel-search--handle-done nil))
    ;; Build tx with entry-kind=insert, cursor-offset=1 (C-f),
    ;; and text=foo.  sel ctx records the offset within the match.
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text
            (helixel-sel-create
             'search
             '(:pattern "hello" :dir forward
               :entry-kind insert :cursor-offset 1)
             #'helixel--recreate-search "/hello/")
            :text "foo"))
    ;; Apply first edit manually
    (goto-char (1+ (match-beginning 0)))
    (insert "foo")
    (should (string= (buffer-string) "hfooello world hello"))
    ;; . — repeat: searches for next "hello", inserts at offset 1
    (helixel-repeat-edit)
    (should (string= (buffer-string) "hfooello world hfooello"))))

(ert-deftest helixel-test-repeat-search-insert-no-region-n-dot ()
  "i after /hello: search sel with entry-kind and cursor-offset.
Cursor-offset is set manually; kmacro captures keys in real flow."
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (re-search-forward "hello")
    (let ((isearch-success t)
          (isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-other-end (match-beginning 0)))
      (helixel-search--handle-done nil))
    ;; Build tx: insert kind=search, entry-kind=insert, offset=1
    ;; simulates /hello + i + C-f + hi<ESC>
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text
            (helixel-sel-create
             'search
             '(:pattern "hello" :dir forward
               :entry-kind insert :cursor-offset 1)
             #'helixel--recreate-search "/hello/")
            :text "hi"))
    ;; Apply first edit manually
    (goto-char (1+ (match-beginning 0)))
    (insert "hi")
    (should (string= (buffer-string) "hhiello world hello"))
    ;; . — repeat on next match at offset 1
    (helixel-repeat-edit)
    (should (string= (buffer-string) "hhiello world hhiello"))))

;; ============================================================================
;; Reproduction: a + search + cursor-left + . (fixed marker-shift)
;; Scenario: /hello<RET> a <left><left> ww <esc> n .
;; Expected: "helwwlo" on both matches (was broken due to marker-shift bug).
;; ============================================================================

(ert-deftest helixel-test-repeat-search-insert-after-left-n-dot ()
  "Scenario: /hello<RET> a <left><left> ww <esc> n .
Insert-after with cursor-movement-left; offset set manually."
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (re-search-forward "hello")
    (should (= (match-beginning 0) 1))
    (should (= (match-end 0) 6))
    (let ((isearch-success t)
          (isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-other-end (match-beginning 0)))
      (helixel-search--handle-done nil))
    ;; Build tx: append kind, entry-kind=append, cursor-offset=-2
    ;; simulates /hello + a + <left><left> + ww<ESC>
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text
            (helixel-sel-create
             'search
             '(:pattern "hello" :dir forward
               :entry-kind append :cursor-offset -2)
             #'helixel--recreate-search "/hello/")
            :text "ww"))
    ;; Apply first edit manually
    (goto-char (- (match-end 0) 2))
    (insert "ww")
    (should (string= (buffer-string) "helwwlo world hello"))
    ;; . — repeat on next match at offset -2 from match-end
    (helixel-repeat-edit)
    (should (string= (buffer-string) "helwwlo world helwwlo"))))

;; ============================================================================
;; a (insert-after) + search + . — no cursor movement
;; ============================================================================

(ert-deftest helixel-test-repeat-search-insert-after-no-move-n-dot ()
  "Scenario: /hello<RET> a foo <esc> n . — appends at region-end.
Insert-after at region-end with no cursor movement.
Cursor-offset is 0 (first insertion at region-end)."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world hello"
      ;; Simulate /hello<RET>
      (goto-char 1)
      (re-search-forward "hello")
      (should (= (match-beginning 0) 1))
      (should (= (match-end 0) 6))
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      ;; Set up search sel context (done by helixel-search--set-sel-ctx in real flow)
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      ;; a — insert-after at match-end (unified search path)
      (setq last-command nil this-command 'helixel-insert-after)
      (helixel-insert-after)
      ;; foo — insert at point (no cursor movement)
      (insert "foo")
      (helixel-insert-exit)
      ;; Buffer after edit: "hellofoo world hello"
      (should (string= (buffer-string) "hellofoo world hello"))
      (should (string= (plist-get (helixel-edit-payload helixel--last-tx) :text)
                       "foo"))
      (let ((sel (helixel-edit-sel helixel--last-tx)))
        (should (eq (helixel-sel-get-kind sel) 'search))
        (should (eq (helixel-sel-search-entry-kind sel) 'append)))
      ;; . — repeat (searches for next "hello" and applies "foo" at end)
      (helixel-repeat-edit)
      (should (string= (buffer-string) "hellofoo world hellofoo")))))

;; ── a (insert-after) + backward search + . ──

(ert-deftest helixel-test-repeat-search-insert-after-backward-dot ()
  "Scenario: ?hello<RET> a foo <esc> . — backward search + append.
Backward search finds last match, a appends after it, . finds previous
match going backward and appends there too.  Regression: (looking-at)
only matched at match-start, missing the match-end case for append."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world hello"
      (goto-char (point-max))
      ;; Simulate ?hello<RET> — backward search from end
      (re-search-backward "hello")
      (should (= (match-beginning 0) 13))
      (should (= (match-end 0) 18))
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward nil)
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)
             #'helixel--recreate-search "?hello"))
      ;; a — insert-after at match-end
      (setq last-command nil this-command 'helixel-insert-after)
      (helixel-insert-after)
      (insert "foo")
      (helixel-insert-exit)
      ;; Buffer after edit: "hello world hellofoo"
      (should (string= (buffer-string) "hello world hellofoo"))
      (let ((sel (helixel-edit-sel helixel--last-tx)))
        (should (eq (helixel-sel-get-kind sel) 'search))
        (should (eq (helixel-sel-search-entry-kind sel) 'append)))
      ;; . — should find first "hello" (backward) and append "foo"
      (helixel-repeat-edit)
      (should (string= (buffer-string) "hellofoo world hellofoo")))))

;; ============================================================================
;; Regression: a after search goes to region-end, not buffer-beginning
;; ============================================================================

(ert-deftest helixel-test-search-insert-after-region-end ()
  "a after /hello<RET> goes to region-end (match-end), not buffer start.
Regression: using (match-end 0) instead of (region-end) caused
goto-char(nil) when match data was stale, jumping to buffer start."
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (re-search-forward "hello")
    (let ((isearch-success t)
          (isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-other-end (match-beginning 0)))
      (helixel-search--handle-done nil))
    ;; Simulate helixel-search--set-sel-ctx
    (setq helixel--repeat-sel-ctx
          (helixel-sel-create
           'search '(:pattern "hello" :dir forward)
           #'helixel--recreate-search "/hello/"))
    ;; a should go to region-end (6), not buffer-beginning (1)
    (setq last-command nil this-command 'helixel-insert-after)
    (helixel-insert-after)
    (should (= (point) 6))
    (should (= (region-beginning) 1))))

;; ============================================================================
;; . repeat — search-failed error message
;; ============================================================================

(ert-deftest helixel-test-repeat-search-no-more-matches ()
  ". after search-based edit: shows error when no more matches exist."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world"
      ;; /hello<RET> — search for "hello"
      (goto-char 1)
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      ;; i — insert at match-beginning
      (setq last-command nil this-command 'helixel-insert)
      (helixel-insert)
      (insert "X")
      (helixel-insert-exit)
      ;; Move past the only "hello" so . can't re-find it
      (goto-char (point-max))
      ;; Only one "hello" in buffer; . should fail
      (condition-case err
          (helixel-repeat-edit)
        ((error quit)
         (should (string-match-p "Search pattern not found"
                                  (error-message-string err)))))
      ;; Buffer should be unchanged (undo amalgamate cancelled)
      (should (string= (buffer-string) "Xhello world")))))

;; ============================================================================
;; Unified search-edit: additional end-to-end tests
;; ============================================================================

;; ── i (insert) no cursor movement + . ──

(ert-deftest helixel-test-repeat-search-insert-no-move-dot ()
  "Scenario: /hello<RET> i X <esc> . — insert X at match-beginning."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world hello"
      (goto-char 1)
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil this-command 'helixel-insert)
      (helixel-insert)
      (insert "X")
      (helixel-insert-exit)
      (should (string= (buffer-string) "Xhello world hello"))
      (let ((sel (helixel-edit-sel helixel--last-tx)))
        (should (eq (helixel-sel-get-kind sel) 'search))
        (should (eq (helixel-sel-search-entry-kind sel) 'insert)))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "Xhello world Xhello")))))

;; ── c (change) + search + . ──

(ert-deftest helixel-test-repeat-search-change-dot ()
  "Full-flow: /hello<RET> c X <esc> . — changes both matches to X."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world hello"
      (goto-char 1)
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "X")
      (helixel-insert-exit)
      (should (string= (buffer-string) "X world hello"))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "X world X")))))

;; ── . from arbitrary position ──

(ert-deftest helixel-test-repeat-search-dot-from-pos ()
  "`.` from middle of buffer finds next match."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world hello"
      (goto-char 1)
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil this-command 'helixel-insert)
      (helixel-insert)
      (insert "X")
      (helixel-insert-exit)
      (should (string= (buffer-string) "Xhello world hello"))
      (goto-char 8)
      (helixel-repeat-edit)
      (should (string= (buffer-string) "Xhello world Xhello")))))

;; ── Movement selection + . end-to-end ──

(ert-deftest helixel-test-repeat-movement-kill-at-start ()
  "vw d at position 1, then . at start selects the word at cursor."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world foo bar"
      (goto-char 1)
      (setq helixel--last-tx
            (helixel-edit-make 'kill
              (helixel-sel-create 'movement
                '(:moves ((helixel-forward-word-start . 1)))
                #'helixel--recreate-movement "v1")))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "world foo bar")))))

(ert-deftest helixel-test-repeat-movement-kill-at-word-start ()
  "vw d at position 1, then move to word start, . selects the word there."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world foo bar"
      (goto-char 1)
      (setq helixel--last-tx
            (helixel-edit-make 'kill
              (helixel-sel-create 'movement
                '(:moves ((helixel-forward-word-start . 1)))
                #'helixel--recreate-movement "v1")))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "world foo bar"))
      (goto-char 7)
      (helixel-repeat-edit)
      (should (string= (buffer-string) "world bar")))))

(ert-deftest helixel-test-repeat-movement-kill-count-two ()
  "v w w d selects 2 words forward, . at a new position selects 2 words."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world foo bar"
      (goto-char 1)
      (setq helixel--last-tx
            (helixel-edit-make 'kill
              (helixel-sel-create 'movement
                '(:moves ((helixel-forward-word-start . 2)))
                #'helixel--recreate-movement "v2")))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "foo bar")))))
;; ── , comma repeat-selection end-to-end ──

(ert-deftest helixel-test-repeat-selection-line-then-dot ()
  ", after x d previews the line, then . kills it."
  :tags '(repeat comma)
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "aaa\nbbb\nccc"
      (goto-char 1)
      (setq helixel--last-tx
            (helixel-edit-make
             'kill
             (helixel-sel-create 'line
               '(:dir forward :count 1)
               #'helixel--recreate-line "x")))
      (helixel-repeat-selection)
      (should (region-active-p))
      (should (= (region-beginning) 1))
      (should (= (region-end) 4))          ; "aaa\n" (point at 4)
      (helixel-repeat-edit)
      (should (string= (buffer-string) "bbb\nccc")))))

(ert-deftest helixel-test-repeat-selection-line-count-then-dot ()
  "3 , after x d kills 3 lines."
  :tags '(repeat comma)
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "aaa\nbbb\nccc\nddd"
      (goto-char 1)
      (setq helixel--last-tx
            (helixel-edit-make
             'kill
             (helixel-sel-create 'line
               '(:dir forward :count 1)
               #'helixel--recreate-line "x")))
      (helixel-repeat-selection 3)
      (should (region-active-p))
      (should (string= (buffer-string) "aaa\nbbb\nccc\nddd"))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "ddd")))))

(ert-deftest helixel-test-repeat-selection-movement-then-dot ()
  ", after vw d previews the word, then . kills it."
  :tags '(repeat comma)
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world"
      (goto-char 1)
      (setq helixel--last-tx
            (helixel-edit-make
             'kill
             (helixel-sel-create 'movement
               '(:moves ((helixel-forward-word-start . 1)))
               #'helixel--recreate-movement "v1")))
      (helixel-repeat-selection)
      (should (region-active-p))
      (should (= (region-beginning) 1))
      (should (= (region-end) 7))          ; 'hello '
      (helixel-repeat-edit)
      (should (string= (buffer-string) "world")))))

;; ── , comma repeat-selection with insert-text (advance) ──

(ert-deftest helixel-test-repeat-selection-insert-advance ()
  "`, after xi<text><ESC> advances to next line and shows cursor at bol."
  :tags '(repeat comma)
  (helixel-test-with-buffer "line one\nline two\nline three\n"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel-edit-make
           'insert-text
           (helixel-sel-create
            'line
            '(:dir forward :count 1 :entry-kind insert)
            #'helixel--recreate-line "x")
           :text "foo"))
    (helixel-repeat-selection)
    ;; Cursor at bol of line 2, region shows the target line.
    (should (region-active-p))
    (should (= (point) (line-beginning-position)))
    (should (string= (buffer-substring (line-beginning-position)
                                       (line-end-position))
                     "line two"))))

(ert-deftest helixel-test-repeat-selection-insert-double-comma ()
  "`, , ` advances twice then shows cursor at bol of line 3."
  :tags '(repeat comma)
  (helixel-test-with-buffer "line one\nline two\nline three\nline four\n"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel-edit-make
           'insert-text
           (helixel-sel-create
            'line
            '(:dir forward :count 1 :entry-kind insert)
            #'helixel--recreate-line "x")
           :text "foo"))
    (helixel-repeat-selection)
    (helixel-repeat-selection)
    (should (region-active-p))
    (should (= (point) (line-beginning-position)))
    (should (string= (buffer-substring (line-beginning-position)
                                       (line-end-position))
                     "line three"))))

(ert-deftest helixel-test-repeat-selection-insert-comma-then-dot ()
  "`, then . after xi<text><ESC> inserts at the advanced position."
  :tags '(repeat comma)
  (helixel-test-with-buffer "line one\nline two\nline three\n"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel-edit-make
           'insert-text
           (helixel-sel-create
            'line
            '(:dir forward :count 1 :entry-kind insert)
            #'helixel--recreate-line "x")
           :text "foo"))
    (helixel-repeat-selection)          ; advance to line 2
    (helixel-repeat-edit)               ; insert at bol of line 2
    (should (string= (buffer-string)
                     "line one\nfooline two\nline three\n"))))

(ert-deftest helixel-test-repeat-selection-insert-count-prefix ()
  "3 , after xi<text><ESC> advances 3 times, then . inserts once."
  :tags '(repeat comma)
  (helixel-test-with-buffer
      "line one\nline two\nline three\nline four\nline five\n"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel-edit-make
           'insert-text
           (helixel-sel-create
            'line
            '(:dir forward :count 1 :entry-kind insert)
            #'helixel--recreate-line "x")
           :text "foo"))
    (helixel-repeat-selection 3)        ; advance to line 4
    (should (region-active-p))
    (should (= (point) (line-beginning-position)))
    (should (string= (buffer-substring (line-beginning-position)
                                       (line-end-position))
                     "line four"))
    (helixel-repeat-edit)               ; insert at bol of line 4
    (should (string= (buffer-string)
                     (concat "line one\nline two\nline three\n"
                             "fooline four\nline five\n")))))

;; ── segment-based replay: cursor movement between insertions ──

(ert-deftest helixel-test-repeat-search-insert-move-forward-dot ()
  "Scenario: /hello<RET> i aa <M-f> bb <esc> .
Two insertions with cursor-movement gap between.
With kmacro recording, keys capture the full sequence."
  :tags '(repeat search)
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (re-search-forward "hello")
    (should (= (match-beginning 0) 1))
    (should (= (match-end 0) 6))
    (let ((isearch-success t)
          (isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-other-end (match-beginning 0)))
      (helixel-search--handle-done nil))
    ;; Build tx simulating i aa <M-f> bb <ESC>
    ;; Text records the concatenated text; sel tracks entry-kind.
    (let ((m-beg (match-beginning 0))
          (m-end (match-end 0)))
      (setq helixel--last-tx
            (helixel-edit-make 'insert-text
              (helixel-sel-create
               'search
               '(:pattern "hello" :dir forward :entry-kind insert)
               #'helixel--recreate-search "/hello/")
              :text "aabb"))
      ;; Apply first edit manually (aa before match, then bb after)
      ;; Save match positions before buffer modifications.
      (goto-char m-beg)
      (insert "aa")
      (goto-char (+ m-end (length "aa")))
      (insert "bb")
      (should (string= (buffer-string) "aahellobb world hello"))
      ;; . — repeat on next match: inserts "aabb" at match-beginning
      (helixel-repeat-edit)
      (should (string= (buffer-string)
                       "aahellobb world aabbhello")))))

;; ── $ (end-of-line) zero-length anchor + a (append) ──

(ert-deftest helixel-test-repeat-search-append-eol-zero-length-dot ()
  "Scenario: /$<RET> a foo <ESC> . — append at eol with $ anchor.
\=`$' is a zero-length regex anchor.  The skip logic in
`helixel--recreate-search' must advance one extra character
past the match-end to actually skip zero-length matches."
  :tags '(repeat search)
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "line one\nline two\nline three"
      ;; /$<RET> — search for end-of-line
      (goto-char 1)
      (re-search-forward "$")
      ;; Match should be at end of line 1
      (let ((isearch-success t)
            (isearch-string "$")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "$" :dir forward)
             #'helixel--recreate-search "/$/"))
      ;; a — insert-after at match-end
      (setq last-command nil this-command 'helixel-insert-after)
      (helixel-insert-after)
      (insert "foo")
      (helixel-insert-exit)
      ;; Buffer after edit: "line onefoo\nline two\nline three"
      (should (string= (buffer-string) "line onefoo\nline two\nline three"))
      ;; . — should append "foo" at end of line 2
      (helixel-repeat-edit)
      (should (string= (buffer-string) "line onefoo\nline twofoo\nline three"))
      ;; . again — should append "foo" at end of line 3
      (helixel-repeat-edit)
      (should (string= (buffer-string) "line onefoo\nline twofoo\nline threefoo")))))

;; ── $ (end-of-line) zero-length anchor + i (insert) ──

(ert-deftest helixel-test-repeat-search-insert-eol-zero-length-dot ()
  "Scenario: /$<RET> i foo <ESC> . — insert before eol with $ anchor."
  :tags '(repeat search)
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "line one\nline two\nline three"
      (goto-char 1)
      (re-search-forward "$")
      (let ((isearch-success t)
            (isearch-string "$")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "$" :dir forward)
             #'helixel--recreate-search "/$/"))
      ;; i — insert at match-beginning
      (setq last-command nil this-command 'helixel-insert)
      (helixel-insert)
      (insert "foo")
      (helixel-insert-exit)
      ;; Buffer after edit: "line onefoo\nline two\nline three"
      (should (string= (buffer-string) "line onefoo\nline two\nline three"))
      ;; . — should insert "foo" before eol of line 2
      (helixel-repeat-edit)
      (should (string= (buffer-string) "line onefoo\nline twofoo\nline three"))
      ;; . again — should insert "foo" before eol of line 3
      (helixel-repeat-edit)
      (should (string= (buffer-string) "line onefoo\nline twofoo\nline threefoo")))))

;; ── ^ (beginning-of-line) zero-length anchor + backward search ──

(ert-deftest helixel-test-repeat-search-insert-bol-zero-length-backward-dot ()
  "Scenario: ?^<RET> i foo <ESC> . — backward search for ^, insert at bol.
\=`^' is a zero-length anchor.  After inserting at bol, point moves past
the match so `looking-at' fails, and the backward-search proximity check
must detect we're still on the same line as the ^ match."
  :tags '(repeat search)
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "line one\nline two\nline three"
      ;; ?^<RET> — backward search for beginning-of-line
      (goto-char (point-max))
      (re-search-backward "^")
      ;; Match at bol of line 3
      (let ((isearch-success t)
            (isearch-string "^")
            (isearch-regexp t)
            (isearch-forward nil)
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "^" :dir backward)
             #'helixel--recreate-search "?^"))
      ;; i — insert at match-beginning (bol of line 3)
      (setq last-command nil this-command 'helixel-insert)
      (helixel-insert)
      (insert "foo")
      (helixel-insert-exit)
      ;; i at bol of "line three" inserts at beginning:
      ;; "line one\nline two\nfooline three"
      (should (string= (buffer-string) "line one\nline two\nfooline three"))
      ;; . — backward: should insert "foo" at bol of line 2
      (helixel-repeat-edit)
      (should (string= (buffer-string) "line one\nfooline two\nfooline three"))
      ;; . again — backward: should insert "foo" at bol of line 1
      (helixel-repeat-edit)
      (should (string= (buffer-string) "fooline one\nfooline two\nfooline three")))))

(ert-deftest helixel-test-repeat-search-append-bol-zero-length-backward-dot ()
  "Scenario: ?^<RET> a foo <ESC> . — backward search for ^, append at bol."
  :tags '(repeat search)
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "line one\nline two\nline three"
      (goto-char (point-max))
      (re-search-backward "^")
      (let ((isearch-success t)
            (isearch-string "^")
            (isearch-regexp t)
            (isearch-forward nil)
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "^" :dir backward)
             #'helixel--recreate-search "?^"))
      ;; a — append at match-end (also bol for ^, since it's zero-length)
      (setq last-command nil this-command 'helixel-insert-after)
      (helixel-insert-after)
      (insert "foo")
      (helixel-insert-exit)
      ;; a at bol of "line three" appends AFTER region-end = bol:
      ;; "line one\nline two\nfooline three" (same as insert for zero-length)
      (should (string= (buffer-string) "line one\nline two\nfooline three"))
      ;; . — backward: should insert "foo" at bol of line 2
      (helixel-repeat-edit)
      (should (string= (buffer-string) "line one\nfooline two\nfooline three"))
      ;; . again — backward: should insert "foo" at bol of line 1
      (helixel-repeat-edit)
      (should (string= (buffer-string) "fooline one\nfooline two\nfooline three")))))

;; ── 0. prefix: repeat-all in stored direction ──

(ert-deftest helixel-test-repeat-all-dir-forward-change ()
  "0. after /search cX<ESC> changes all remaining matches forward."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char 1)
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      (should (string= (buffer-string) "XXX A hello B hello C"))
      ;; 0. -> change all remaining "hello" forwards
      (helixel-repeat-edit 0)
      (should (string= (buffer-string) "XXX A XXX B XXX C")))))

(ert-deftest helixel-test-repeat-all-dir-forward-from-middle ()
  "0. after /search from middle only changes matches after cursor."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char 9)                        ; at "hello B"
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      ;; Only B and C changed, not A
      (should (string= (buffer-string) "hello A XXX B hello C"))
      (helixel-repeat-edit 0)
      (should (string= (buffer-string) "hello A XXX B XXX C")))))

(ert-deftest helixel-test-repeat-all-dir-backward-change ()
  "0. after ?search cX<ESC> changes all remaining matches backward."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char (point-max))
      (re-search-backward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward nil)       ; backward
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      ;; Changed last hello (C)
      (should (string= (buffer-string) "hello A hello B XXX C"))
      ;; 0. -> change remaining matches backward
      (helixel-repeat-edit 0)
      (should (string= (buffer-string) "XXX A XXX B XXX C")))))

(ert-deftest helixel-test-repeat-all-dir-backward-append ()
  "0. after ?search aXXX<ESC> — skip logic prevents re-editing current match."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char (point-max))
      (re-search-backward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward nil)
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)
             #'helixel--recreate-search "/hello/"))
      ;; Append "XXX" after match (a = helixel-insert-after)
      (setq last-command nil this-command 'helixel-insert-after)
      (helixel-insert-after)
      (insert "XXX")
      (helixel-insert-exit)
      (should (string= (buffer-string)
                       "hello A hello B helloXXX C"))
      ;; 0. -> append to remaining matches backward
      (helixel-repeat-edit 0)
      (should (string= (buffer-string)
                       "helloXXX A helloXXX B helloXXX C")))))

;; NOTE: This test is the insert-after variant (like `a`);
;; above test uses helixel-insert-after for append semantics.

(ert-deftest helixel-test-repeat-all-dir-forward-insert ()
  "0. after /search iXXX<ESC> — inserts before all remaining matches."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char 1)
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil this-command 'helixel-insert)
      (helixel-insert)
      (insert "XXX")
      (helixel-insert-exit)
      ;; Inserted before first hello
      (should (string= (buffer-string)
                       "XXXhello A hello B hello C"))
      ;; 0. -> insert before all remaining matches
      (helixel-repeat-edit 0)
      (should (string= (buffer-string)
                       "XXXhello A XXXhello B XXXhello C")))))

;; ── C-u . prefix: repeat-all entire buffer ──

(ert-deftest helixel-test-repeat-all-buffer-forward-change ()
  "C-u . after /search cX<ESC> changes ALL matches from point-min."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char 9)                        ; at "hello B"
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      (should (string= (buffer-string) "hello A XXX B hello C"))
      ;; C-u . -> all matches from point-min forward
      (helixel-repeat-edit '(4))
      (should (string= (buffer-string) "XXX A XXX B XXX C")))))

(ert-deftest helixel-test-repeat-all-buffer-forward-insert ()
  "C-u . after /search iXXX<ESC> inserts BEFORE all matches from point-min.
entry-kind=insert means insert at match-beginning, not match-end."
  (helixel-test-with-buffer "hello A hello B hello C"
    (goto-char 1)
    (re-search-forward "hello")
    (let ((isearch-success t)
          (isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-other-end (match-beginning 0)))
      (helixel-search--handle-done nil))
    ;; Build tx with entry-kind=insert (i before match)
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text
            (helixel-sel-create
             'search
             '(:pattern "hello" :dir forward :entry-kind insert)
             #'helixel--recreate-search "/hello/")
            :text "XXX"))
    ;; Apply first edit manually
    (goto-char (match-beginning 0))
    (insert "XXX")
    (should (string= (buffer-string)
                     "XXXhello A hello B hello C"))
    ;; C-u . -> insert before ALL matches from point-min
    (helixel-repeat-edit '(4))
    (should (string= (buffer-string)
                     "XXXhello A XXXhello B XXXhello C"))))

(ert-deftest helixel-test-repeat-all-buffer-backward-change ()
  "C-u . after ?search cX<ESC> changes ALL matches regardless of stored dir."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char (point-max))
      (re-search-backward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward nil)
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      (should (string= (buffer-string) "hello A hello B XXX C"))
      ;; C-u . -> all matches from point-min forward
      (helixel-repeat-edit '(4))
      (should (string= (buffer-string) "XXX A XXX B XXX C")))))

(ert-deftest helixel-test-repeat-all-buffer-backward-append ()
  "C-u . after ?search aXXX<ESC> inserts at ALL matches."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char (point-max))
      (re-search-backward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward nil)
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil this-command 'helixel-insert-after)
      (helixel-insert-after)
      (insert "XXX")
      (helixel-insert-exit)
      (should (string= (buffer-string)
                       "hello A hello B helloXXX C"))
      ;; C-u . -> append at ALL matches from point-min
      (helixel-repeat-edit '(4))
      (should (string= (buffer-string)
                       "helloXXX A helloXXX B helloXXX C")))))

;; ── 0. with zero-length anchors: must not hang ──

(ert-deftest helixel-test-repeat-all-dir-eol-forward-no-hang ()
  "0. after /$ aX<ESC> terminates at end-of-buffer without hanging."
  :tags '(repeat search)
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "line one\nline two\nline three"
      (goto-char 1)
      (re-search-forward "$")
      (let ((isearch-success t)
            (isearch-string "$")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "$" :dir forward)
             #'helixel--recreate-search "/$/"))
      (setq last-command nil this-command 'helixel-insert-after)
      (helixel-insert-after)
      (insert "X")
      (helixel-insert-exit)
      (should (string= (buffer-string) "line oneX\nline two\nline three"))
      ;; 0. -> append "X" at remaining eols, must terminate
      (helixel-repeat-edit 0)
      (should (string= (buffer-string) "line oneX\nline twoX\nline threeX")))))

(ert-deftest helixel-test-repeat-all-dir-bol-backward-no-hang ()
  "0. after ?^ iX<ESC> terminates at beginning-of-buffer without hanging."
  :tags '(repeat search)
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "line one\nline two\nline three"
      (goto-char (point-max))
      (re-search-backward "^")
      (let ((isearch-success t)
            (isearch-string "^")
            (isearch-regexp t)
            (isearch-forward nil)
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "^" :dir backward)
             #'helixel--recreate-search "?^"))
      (setq last-command nil this-command 'helixel-insert)
      (helixel-insert)
      (insert "X")
      (helixel-insert-exit)
      (should (string= (buffer-string) "line one\nline two\nXline three"))
      ;; 0. -> insert "X" at remaining bols backward, must terminate
      (helixel-repeat-edit 0)
      (should (string= (buffer-string) "Xline one\nXline two\nXline three")))))

;; ── C-u . with zero-length anchors: must not hang ──

(ert-deftest helixel-test-repeat-all-buffer-eol-forward-no-hang ()
  "C-u . after /$ aX<ESC> terminates at end-of-buffer without hanging."
  :tags '(repeat search)
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "line one\nline two\nline three"
      (goto-char 1)
      (re-search-forward "$")
      (let ((isearch-success t)
            (isearch-string "$")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "$" :dir forward)
             #'helixel--recreate-search "/$/"))
      (setq last-command nil this-command 'helixel-insert-after)
      (helixel-insert-after)
      (insert "X")
      (helixel-insert-exit)
      (should (string= (buffer-string) "line oneX\nline two\nline three"))
      ;; C-u . -> append "X" at ALL eols, must terminate
      (helixel-repeat-edit '(4))
      (should (string= (buffer-string) "line oneX\nline twoX\nline threeX")))))

;; ── C-u -N . prefix: reverse direction ──

(ert-deftest helixel-test-repeat-reverse-forward-to-backward ()
  "C-u -2 . after /search reverses direction: forward -> backward."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char 9)                        ; at "hello B"
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      ;; Changed B
      (should (string= (buffer-string) "hello A XXX B hello C"))
      ;; C-u -2 . -> reverse (backward): change A + search-failed
      (helixel-repeat-edit -2)
      (should (string= (buffer-string) "XXX A XXX B hello C")))))

(ert-deftest helixel-test-repeat-reverse-backward-to-forward ()
  "C-u -2 . after ?search reverses direction: backward -> forward."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char (point-max))
      (re-search-backward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward nil)
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      ;; Changed C
      (should (string= (buffer-string) "hello A hello B XXX C"))
      ;; C-u -2 . -> reverse (forward): from C there's nothing forward
      ;; -> 0 changes, but original direction unchanged
      (helixel-repeat-edit -2)
      (should (string= (buffer-string) "hello A hello B XXX C")))))

(ert-deftest helixel-test-repeat-reverse-mid-buffer ()
  "C-u -3 . after ?search from middle changes backward matches in reverse."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char 15)                       ; after "hello B", before C
      (re-search-backward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward nil)
            (isearch-other-end (match-end 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      ;; Changed B (backward from middle)
      (should (string= (buffer-string) "hello A XXX B hello C"))
      ;; C-u -3 . -> reverse (forward): change C
      (helixel-repeat-edit -3)
      (should (string= (buffer-string) "hello A XXX B XXX C")))))

;; ── Edge cases ──

(ert-deftest helixel-test-repeat-all-single-match ()
  "0. with only one match: executes once then stops silently."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello world"
      (goto-char 1)
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      (should (string= (buffer-string) "XXX world"))
      ;; 0. -> no more matches, silently stops
      (helixel-repeat-edit 0)
      (should (string= (buffer-string) "XXX world")))))

(ert-deftest helixel-test-repeat-all-non-search-line ()
  "0. on line (non-search) selection falls back to single execution."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "line1\nline2\nline3\n"
      (goto-char 1)
      (setq helixel--last-tx
            (helixel-edit-make 'kill
              (helixel-sel-create 'line
                '(:dir forward :count 2)
                (lambda (ctx)
                  (let ((cnt (helixel-sel-line-count ctx)))
                    (push-mark (line-beginning-position) t t)
                    (goto-char
                     (line-beginning-position (1+ cnt)))
                    (setq mark-active t))
                  (setq helixel--selection-type 'line))
                "2lines")))
      ;; First . kills line1+line2, leaving line3
      (helixel-repeat-edit)
      (should (string= (buffer-string) "line3\n"))
      ;; 0. on non-search sel -> fallback to single execution
      ;; kills the remaining line3
      (helixel-repeat-edit 0)
      (should (string= (buffer-string) "")))))

(ert-deftest helixel-test-repeat-reverse-keeps-stored-dir ()
  "`-1 .' permanently flips the stored direction (like N for search).
After `-1 .' a plain `.` continues in the flipped direction."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char 9)
      (re-search-forward "hello")
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward t)
            (isearch-other-end (match-beginning 0)))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir forward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      (should (string= (buffer-string) "hello A XXX B hello C"))
      ;; Direction is forward
      (should (eq (helixel-sel-search-dir
                   (helixel-edit-sel helixel--last-tx))
                  'forward))
      ;; -1 . — permanently flips to backward, changes A
      (helixel-repeat-edit -1)
      (should (string= (buffer-string) "XXX A XXX B hello C"))
      ;; Direction is now permanently backward
      (should (eq (helixel-sel-search-dir
                   (helixel-edit-sel helixel--last-tx))
                  'backward))
      ;; Plain `.` continues backward — nothing left to change
      ;; (A was already changed), so it should error silently.
      (let ((helixel--inhibit-repeat-record t))
        (condition-case nil
            (helixel-repeat-edit)
          (error nil)))
      ;; Buffer unchanged
      (should (string= (buffer-string) "XXX A XXX B hello C")))))

(ert-deftest helixel-test-repeat-all-dir-backward-from-start ()
  "0. after ?search from buffer start: no matches backward, silent stop."
  (let ((helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "hello A hello B hello C"
      (goto-char 1)
      (re-search-forward "hello")        ; find first hello
      ;; Backward search puts point at match-beginning
      (goto-char (match-beginning 0))
      (let ((isearch-success t)
            (isearch-string "hello")
            (isearch-regexp t)
            (isearch-forward nil)        ; backward
            (isearch-other-end (copy-marker (match-end 0))))
        (helixel-search--handle-done nil))
      (setq helixel--repeat-sel-ctx
            (helixel-sel-create
             'search '(:pattern "hello" :dir backward)
             #'helixel--recreate-search "/hello/"))
      (setq last-command nil
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "XXX")
      (helixel-insert-exit)
      (should (string= (buffer-string) "XXX A hello B hello C"))
      ;; 0. backward from start -> no more matches
      (helixel-repeat-edit 0)
      (should (string= (buffer-string) "XXX A hello B hello C")))))

;; === All-buffer reverse (C-u - .) ===

(ert-deftest helixel-test-repeat-all-buffer-reverse-search-insert ()
  "C-u - . after /search iXXX<ESC> inserts BEFORE all matches backward."
  (helixel-test-with-buffer "hello A hello B hello C"
    (goto-char 1)
    (re-search-forward "hello")
    (let ((isearch-success t)
          (isearch-string "hello")
          (isearch-regexp t)
          (isearch-forward t)
          (isearch-other-end (match-beginning 0)))
      (helixel-search--handle-done nil))
    (setq helixel--last-tx
          (helixel-edit-make 'insert-text
            (helixel-sel-create
             'search
             '(:pattern "hello" :dir forward :entry-kind insert)
             #'helixel--recreate-search "/hello/")
            :text "XXX"))
    (goto-char (match-beginning 0))
    (insert "XXX")
    (should (string= (buffer-string) "XXXhello A hello B hello C"))
    ;; C-u - . -> insert before ALL matches from point-max backward
    (helixel-repeat-edit '(-4))
    (should (string= (buffer-string)
                     "XXXhello A XXXhello B XXXhello C"))))

(ert-deftest helixel-test-repeat-all-buffer-reverse-line ()
  "C-u - . after x> indents ALL lines from bottom up."
  (helixel-test-with-buffer "a\nb\nc\nd\n"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (setq last-command 'helixel-select-line
          this-command 'helixel-indent-right)
    (helixel-indent-right)
    (should (string= (buffer-string) " a\nb\nc\nd\n"))
    ;; C-u - . from recorded marker: backward skip-current (nothing
    ;; above), then forward skip-current (lines b,c,d get indented).
    ;; The recorded line (a) is skipped → stays with 1 indent.
    (helixel-repeat-edit '(-4))
    (should (string= (buffer-string) " a\n b\n c\n d\n"))))

(ert-deftest helixel-test-repeat-reverse-line-n-times ()
  "C-u -2 . after x> (from line 2) indents the 2 lines above."
  (helixel-test-with-buffer "a\nb\nc\nd\n"
    (goto-char 4) ; line 2
    (setq last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (setq last-command 'helixel-select-line
          this-command 'helixel-indent-right)
    (helixel-indent-right)
    (should (string= (buffer-string) "a\n b\nc\nd\n"))
    ;; Reverse 2: skip line 2, indent line 1
    (helixel-repeat-edit -2)
    (should (string= (buffer-string) " a\n b\nc\nd\n"))))

(ert-deftest helixel-test-repeat-all-buffer-line-change ()
  "C-u . after xc<text><ESC> changes ALL lines from point-min.
Verifies nil-advance ops (change,kill) don't loop forever."
  (helixel-test-with-buffer "hello\nhello\nhello\nxibar\n"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel-edit-make 'change
            (helixel-sel-create 'line '(:dir forward :count 1)
                                #'helixel--recreate-line "L")
            ;; The change replaces the whole line (incl. \n) so the
            ;; replacement text must include the trailing newline.
            :inserted-text "bar\n"))
    ;; First . changes line 1
    (helixel-repeat-edit)
    (should (string= (buffer-string) "bar\nhello\nhello\nxibar\n"))
    ;; C-u . -> change ALL lines from point-min
    (helixel-repeat-edit '(4))
    (should (string= (buffer-string) "bar\nbar\nbar\nbar\n"))))

(ert-deftest helixel-test-repeat-all-buffer-line-kill ()
  "C-u . after xd kills remaining lines from recorded position.
After kill, the marker points to the next surviving line;
C-u . processes forward + backward, skipping the recorded line.
Note: C-u . AFTER a kill skips the new current line because
kill naturally moved point — use a single xd prefix for bulk kill."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\n"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel-edit-make 'kill
            (helixel-sel-create 'line '(:dir forward :count 1)
                                #'helixel--recreate-line "L")))
    ;; First . kills line 1; cursor at BOL of line 2
    (helixel-repeat-edit)
    (should (string= (buffer-string) "line2\nline3\nline4\n"))
    ;; C-u . from recorded position: forward skips line 2
    ;; (marker now pointing there), kills lines 3 and 4;
    ;; backward from marker: skip-current hits bobp, exits.
    ;; Line 2 survives.
    (helixel-repeat-edit '(4))
    (should (string= (buffer-string) "line2\n"))))

;;; helixel-test-jump.el ends here
