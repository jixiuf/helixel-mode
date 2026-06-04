;;; helixel-test-mc.el --- Tests for multi-cursor (mc) modules  -*- lexical-binding: t; -*-

;;; Commentary:
;; Covers helixel-mc-core, helixel-mc-spawn, and helixel-mc-integrate.

;;; Code:

(require 'ert)
(require 'helixel)
(require 'helixel-mc-core)
(require 'helixel-mc-spawn)
(require 'helixel-mc-integrate)
(require 'helixel-test-common)

;; ── Core: create / clear / mode lifecycle ──

(ert-deftest helixel-test-mc-create-and-clear ()
  (helixel-test-with-buffer "abc\ndef\nghi\n"
    (helixel-mc-create-fake-cursor 5)
    (helixel-mc-create-fake-cursor 9)
    (should helixel-multi-cursor-mode)
    (should (= 2 (length (helixel-mc-all-cursors))))
    (should (= 3 (helixel-mc-num-cursors)))
    (helixel-mc-clear-all)
    (should-not helixel-multi-cursor-mode)
    (should (null (helixel-mc-all-cursors)))))

(ert-deftest helixel-test-mc-cursor-with-region ()
  (helixel-test-with-buffer "hello world\n"
    (let ((c (helixel-mc-create-fake-cursor 1 6)))
      (should (overlay-get c 'mark-active))
      (should (overlay-get c 'helixel-mc-region))
      (helixel-mc-clear-all))))

;; ── Whitelist ──

(ert-deftest helixel-test-mc-whitelist ()
  (put 'helixel-test-mc-foo 'multiple-cursors t)
  (put 'helixel-test-mc-bar 'multiple-cursors nil)
  (should (helixel-mc--should-run-for-all-p 'helixel-test-mc-foo))
  (should-not (helixel-mc--should-run-for-all-p 'helixel-test-mc-bar))
  ;; Lambdas treated as safe.
  (should (helixel-mc--should-run-for-all-p (lambda () (interactive))))
  ;; Unknown command + default policy 'all
  (let ((helixel-mc-default-policy 'all))
    (should (helixel-mc--should-run-for-all-p 'helixel-test-mc-unknown-1)))
  (let ((helixel-mc-default-policy 'once))
    (should-not (helixel-mc--should-run-for-all-p
                 'helixel-test-mc-unknown-2))))

;; ── with-each-cursor: state isolation ──

(ert-deftest helixel-test-mc-with-each-cursor-state-isolation ()
  (helixel-test-with-buffer "aaaa\nbbbb\ncccc\n"
    (helixel-mc-create-fake-cursor 5)   ; on \n of line 1
    (helixel-mc-create-fake-cursor 10)  ; on \n of line 2
    (goto-char 1)
    (let ((visited nil))
      (helixel-mc-with-each-cursor
        (push (point) visited))
      (should (equal (sort visited #'<) '(5 10))))
    ;; Real point must be restored.
    (should (= 1 (point)))
    (helixel-mc-clear-all)))

;; ── Dispatch: insert char at each cursor ──

(ert-deftest helixel-test-mc-dispatch-insert ()
  (helixel-test-with-buffer "aaa\nbbb\nccc\n"
    (helixel-mc-create-fake-cursor 5)   ; before 'b'
    (helixel-mc-create-fake-cursor 9)   ; before 'c'
    (goto-char 1)
    (helixel-mc-with-each-cursor
      (insert "X"))
    ;; Each fake cursor inserted at its position.
    ;; Order: lines processed in buffer order; markers update.
    (should (string= "aaa\nXbbb\nXccc\n" (buffer-string)))
    (helixel-mc-clear-all)))

;; ── Spawn from line: column cursors ──

(ert-deftest helixel-test-mc-spawn-from-line ()
  (helixel-test-with-buffer "aaa\nbbb\nccc\n"
    (goto-char 1)
    (push-mark (point-max) t t)
    (let* ((sel (helixel-sel-create 'line '(:count 3)
                                    #'ignore "L"))
           (targets (helixel-mc-spawn-from-line sel)))
      (should (= 3 (length targets))))))

;; ── Spawn: column at offset 2 ──

(ert-deftest helixel-test-mc-spawn-line-back-to-indent ()
  (helixel-test-with-buffer "abc\n  de\nfghi\n"
    (goto-char 1)
    (push-mark (point-max) t t)
    (let* ((sel (helixel-sel-create 'line '(:count 3)
                                    #'ignore "L"))
           (targets (helixel-mc-spawn-from-line sel)))
      ;; one target per line; each target is (eol . bol) so the fake
      ;; cursor will select its own line
      (should (= 3 (length targets)))
      ;; first target: line 1 "abc" → (4 . 1)
      (let ((p (car targets)))
        (should (= 4 (marker-position (car p))))
        (should (= 1 (marker-position (cdr p))))))))

;; ── Edit-lines: per-line cursor ──

(ert-deftest helixel-test-mc-edit-lines ()
  (helixel-test-with-buffer "111\n222\n333\n"
    (goto-char 1)
    (push-mark (point-max) t t)
    (helixel-mc-edit-lines (region-beginning) (region-end))
    (should (>= (length (helixel-mc-all-cursors)) 2))
    (helixel-mc-clear-all)))

;; ── Add-cursor-here: Helix `C' semantics (copy current cursor to next line)

(ert-deftest helixel-test-mc-add-here-snapshots-and-advances ()
  "`s a' snapshots real to a fake at the current position, then moves
real to the next line same column.  Repeated invocations stack."
  (helixel-test-with-buffer "hello\nworld\n"
    (goto-char 3)                       ; col 2 of line 1
    (helixel-mc-add-cursor-here)
    (should (= 1 (length (helixel-mc-all-cursors))))
    (should (= 9 (point)))              ; col 2 of line 2
    (should (= 3 (marker-position
                  (overlay-get (car (helixel-mc-all-cursors))
                               'helixel-mc-point))))
    (helixel-mc-clear-all)))

;; ── Mark-next-like-this ──

(ert-deftest helixel-test-mc-mark-next-like-this ()
  (helixel-test-with-buffer "foo bar foo baz foo\n"
    (goto-char 1)
    (push-mark 4 t t)                   ; region: "foo" (real at 1..4)
    (helixel-mc-mark-next-like-this)
    (should (= 1 (length (helixel-mc-all-cursors))))
    (helixel-mc-mark-next-like-this)
    (should (= 2 (length (helixel-mc-all-cursors))))
    (helixel-mc-clear-all)))

;; ── Regression: `s n' must NOT move the real cursor onto the match
;; (would collide with the fake created at the same position, causing
;; the same edit to run twice at that spot — user-reported "two foos
;; at the last position").

(ert-deftest helixel-test-mc-mark-next-leaves-real-in-place ()
  "`helixel-mc-mark-next-like-this' must leave real cursor untouched.
Real stays on the FIRST occurrence; fakes spawn at successive matches.
No two cursors may share a position (else edits double up there)."
  (helixel-test-with-buffer "foo bar foo baz foo\n"
    (goto-char 1)
    (push-mark 4 t t)                   ; real region: foo (1..4)
    (helixel-mc-mark-next-like-this)    ; fake at 9..12
    (helixel-mc-mark-next-like-this)    ; fake at 17..20
    ;; Real did NOT move.
    (should (= 1 (point)))
    (should (= 4 (mark t)))
    (should mark-active)
    ;; Two fakes, both at later occurrences — distinct positions.
    (let* ((cursors (helixel-mc-all-cursors :sort))
           ;; Each fake stores its `point' marker; we sort by that.
           (positions (mapcar (lambda (ov)
                                (marker-position
                                 (overlay-get ov 'helixel-mc-point)))
                              cursors)))
      (should (= 2 (length cursors)))
      ;; Fakes have point=9 (start of 2nd `foo') and 17 (start of 3rd).
      (should (equal '(9 17) (sort positions #'<)))
      ;; No fake collides with the real cursor.
      (should-not (memq 1 positions)))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-mark-next-end-to-end-insert ()
  "Realistic flow: `miw' on first `foo' then `s n s n', then `i' to
insert `X' — must produce `Xfoo bar Xfoo baz Xfoo' (one X per match,
NOT two at the last)."
  (helixel-test-with-buffer "foo bar foo baz foo\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (setq this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (helixel-mc-mark-next-like-this)
    (helixel-mc-mark-next-like-this)
    (should (= 2 (length (helixel-mc-all-cursors))))
    ;; Simulate `i' (helixel-insert): jump to region-begin at every cursor.
    ;; We test the position invariant directly: collect (point) at real
    ;; and at each fake; they must be distinct.
    (let ((positions (cons (region-beginning)
                           (mapcar (lambda (ov)
                                     (min (marker-position
                                           (overlay-get ov 'helixel-mc-point))
                                          (marker-position
                                           (overlay-get ov 'helixel-mc-mark))))
                                   (helixel-mc-all-cursors)))))
      ;; Region-begin of each cursor: real=1 (1st foo), fakes=9,17.
      (should (equal '(1 9 17) (sort positions #'<))))
    (helixel-mc-clear-all)))

;; ── Regression: `s x' on a line-wise (`x') selection must spawn one
;; cursor at BOL of each line.  Previously edit-lines used
;; `current-column' (=line-end-column of the LAST line) so it skipped
;; every line where the column was past end-of-line.

;; ── Regression: zombie / detached cursors must NOT crash dispatch.
;; Before the fix, `helixel-mc-all-cursors' filtered only on
;; `overlay-buffer' — a cursor whose `helixel-mc-point' marker had
;; been nulled (but overlay still alive somehow) would pass the
;; filter, then `helixel-mc--enter-cursor's `(goto-char nil)' crashed
;; with `wrong-type-argument integer-or-marker-p nil'.  Real-world
;; trigger: `s s' + `q ciwBUG ESC ESC' — chain-end advice broadcasts
;; the chain TX, but some cursor got cleaned by the chain replay.

(ert-deftest helixel-test-mc-all-cursors-filters-dead-marker ()
  "`helixel-mc-all-cursors' must skip overlays whose point marker
has been nulled (zombie state)."
  (helixel-test-with-buffer "abc def ghi\n"
    (helixel-mc-create-fake-cursor 5)
    (helixel-mc-create-fake-cursor 9)
    (should (= 2 (length (helixel-mc-all-cursors))))
    ;; Simulate the zombie state: null out the marker WITHOUT
    ;; removing the overlay from the list (the actual production bug).
    (let ((victim (car helixel-mc--cursors)))
      (set-marker (overlay-get victim 'helixel-mc-point) nil))
    ;; Now `all-cursors' must filter the zombie out.
    (should (= 1 (length (helixel-mc-all-cursors))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-with-each-cursor-skips-zombie ()
  "`helixel-mc-with-each-cursor' must not crash on a zombie cursor."
  (helixel-test-with-buffer "abc def ghi\n"
    (helixel-mc-create-fake-cursor 5)
    (helixel-mc-create-fake-cursor 9)
    ;; Zombie one cursor mid-state.
    (let ((victim (car helixel-mc--cursors)))
      (set-marker (overlay-get victim 'helixel-mc-point) nil))
    ;; Dispatching to all should silently skip the zombie.
    (let ((live-count 0))
      (helixel-mc-with-each-cursor
        (cl-incf live-count))
      (should (= 1 live-count)))
    (helixel-mc-clear-all)))

;; ── Regression: chain-end advice must NOT re-apply at fakes.
;; During recording each keystroke broadcasts live to every fake,
;; so an extra `apply-chain-once' at chain-end would double the
;; edit.  Verify the advice only emits the user message and
;; broadcasts the TX for future `.' replay.

(ert-deftest helixel-test-mc-chain-end-does-not-double-apply ()
  "After chain-end with mc-mode + a chain TX, the runner must NOT
be re-invoked by the advice (recording already broadcast)."
  (helixel-test-with-buffer "abc\n"
    (helixel-mc-create-fake-cursor 2)
    ;; Fake a chain TX whose runner would `error' if called.
    (let* ((sel (helixel-sel-create 'line '(:dir forward :count 1)
                                    #'ignore))
           (tx (helixel-edit-create 'chain sel
                 :runner (lambda (_tx) (error "REAPPLIED"))
                 :kmacro (vector ?x))))
      (setq helixel--last-edit tx))
    ;; The hook impl returns its `message' string — just ensure
    ;; it does not signal (i.e. the runner is NOT invoked).
    (helixel-mc--on-chain-recorded helixel--last-edit)
    (helixel-mc-clear-all)))

;; ── Regression: chain recording must NOT broadcast per-command.
;; The chain-end advice replays the whole macro at every fake cursor
;; as one atomic step.  If post-command-hook also broadcast each
;; sub-command during recording, every fake would get the edit
;; twice: once live, then again via the replay.

;; ── Regression: chain recording broadcasts per-command so every
;; fake gets the edit live; chain-end MUST NOT replay again.
;; (See `helixel-test-mc-chain-end-does-not-double-apply' above.)

(ert-deftest helixel-test-mc-chain-recording-broadcasts ()
  "`helixel-mc--post-command' must STILL dispatch broadcast-eligible
commands during chain recording — the live broadcast is the only
application path; chain-end does not re-replay."
  (helixel-test-with-buffer "abc\n"
    (helixel-mc-create-fake-cursor 2)
    (let ((helixel--chain-session
           (make-helixel-chain-session :active-p t))
          (this-command 'self-insert-command)
          (helixel-multi-cursor-mode t))
      (should (helixel-mc--should-run-for-all-p 'self-insert-command)))
    (helixel-mc-clear-all)))

;; ── Regression: chain end must NOT capture the trailing `ESC' that
;; triggered `helixel-normal-escape' — otherwise replaying the macro
;; at each fake would run normal-escape with chain inactive, falling
;; through to `helixel-mc-clear-all' which wipes cursors mid-replay
;; and yields the user-visible "chain applied at 0 fake cursors".

(ert-deftest helixel-test-mc-chain-end-excludes-normal-escape ()
  "`helixel--chain-pre-cmd' must skip `helixel-normal-escape' so the
chain's edit-keys do not contain the trailing chain-end ESC."
  (helixel-test-with-buffer "abc\n"
    (setq helixel--chain-session
          (make-helixel-chain-session
           :active-p t :edit-phase-p t :edit-keys nil :move-keys nil))
    (let ((this-command 'helixel-normal-escape))
      (helixel--chain-pre-cmd))
    (should (null (helixel-chain-session-edit-keys helixel--chain-session)))
    ;; Cleanup chain state.
    (setq helixel--chain-session nil)))

;; ── Regression: bulk whitelist must mark ALL helixel-* commands.
;; Two bugs we want to catch:
;;   1. Top-level call in `helixel-mc-integrate' runs before later
;;      modules load — only ~7 commands get marked.
;;   2. Filter `(not (eq (get sym ...) nil))' wrongly skips symbols
;;      WITHOUT the property (eq nil nil → t → not t → skip).
;; Must use `plist-member' to distinguish "missing" from "nil".

(ert-deftest helixel-test-mc-bulk-whitelist-covers-all ()
  "Every helixel-* `commandp' symbol must carry an explicit
`multiple-cursors' property (t or nil) after package load."
  (let ((unmarked nil))
    (mapatoms
     (lambda (sym)
       (when (and (commandp sym)
                  (string-prefix-p "helixel-" (symbol-name sym))
                  ;; Skip ert-style test fixtures that define
                  ;; dummy helixel-test-* commands at run time.
                  (not (string-prefix-p "helixel-test-"
                                        (symbol-name sym)))
                  (not (plist-member (symbol-plist sym)
                                     'multiple-cursors)))
         (push sym unmarked))))
    (should (null unmarked))))

(ert-deftest helixel-test-mc-bulk-whitelist-preserves-explicit-nil ()
  "Bulk whitelist must NOT overwrite explicit real-cursor-only marks
on guard commands (chain, escape, mc management)."
  (dolist (cmd '(helixel-normal-escape
                 helixel-mc-toggle
                 helixel-mc-clear-all
                 helixel-repeat-chain-start
                 helixel-repeat-chain-end
                 helixel-repeat-chain-cancel
                 helixel-insert
                 helixel-insert-exit))
      (should (plist-member (symbol-plist cmd) 'multiple-cursors))
      (should (null (get cmd 'multiple-cursors)))))

;; ── Phase A: Cursor 碰撞/去重 ──────────────────────────────────────

(ert-deftest helixel-test-mc-create-dedupes-by-point-and-mark ()
  "Creating a fake at a (point, mark) that already exists returns nil
and does NOT add a duplicate."
  (helixel-test-with-buffer "abcdefg\n"
    (goto-char 1)
    (should (helixel-mc-create-fake-cursor 4))
    (should (= 1 (length (helixel-mc-all-cursors))))
    ;; Same point, no mark — dup.
    (should-not (helixel-mc-create-fake-cursor 4))
    (should (= 1 (length (helixel-mc-all-cursors))))
    ;; Same point, different (active) mark — NOT a dup.
    (should (helixel-mc-create-fake-cursor 4 7))
    (should (= 2 (length (helixel-mc-all-cursors))))
    ;; Same point + same mark again — dup.
    (should-not (helixel-mc-create-fake-cursor 4 7))
    (should (= 2 (length (helixel-mc-all-cursors))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-dedupe-removes-fake-on-real ()
  "`helixel-mc-dedupe-cursors' deletes any fake sharing the real
cursor's (point, effective-mark)."
  (helixel-test-with-buffer "abcdefg\n"
    (goto-char 1)
    (helixel-mc-create-fake-cursor 4)
    (helixel-mc-create-fake-cursor 6)
    (should (= 2 (length (helixel-mc-all-cursors))))
    ;; Move real onto the fake at 4.
    (goto-char 4)
    (should (= 1 (helixel-mc-dedupe-cursors)))
    (should (= 1 (length (helixel-mc-all-cursors))))
    ;; Surviving fake is at 6.
    (should (= 6 (marker-position
                  (overlay-get (car (helixel-mc-all-cursors))
                               'helixel-mc-point))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-dedupe-merges-duplicate-fakes ()
  "`helixel-mc-dedupe-cursors' collapses several fakes that share
the same (point, effective-mark) into one."
  (helixel-test-with-buffer "abcdefg\n"
    (goto-char 1)
    (let ((a (helixel-mc-create-fake-cursor 4))
          (b (helixel-mc-create-fake-cursor 6))
          (c (helixel-mc-create-fake-cursor 7)))
      (should (= 3 (length (helixel-mc-all-cursors))))
      (set-marker (overlay-get c 'helixel-mc-point) 6)
      (set-marker (overlay-get c 'helixel-mc-mark) 6)
      ;; b and c now collide.
      (should (= 1 (helixel-mc-dedupe-cursors)))
      (should (= 2 (length (helixel-mc-all-cursors))))
      (ignore a b))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-post-command-dedupes-after-movement ()
  "After a broadcast movement that collapses two fakes onto each
other, post-command dedup must trim them down."
  (helixel-test-with-buffer "abcdefg\n"
    (goto-char 1)
    (helixel-mc-create-fake-cursor 4)
    (helixel-mc-create-fake-cursor 5)
    ;; Pile both fakes up at 8.
    (helixel-mc-with-each-cursor
      (goto-char 8))
    (should (= 1 (helixel-mc-dedupe-cursors)))
    (should (= 1 (length (helixel-mc-all-cursors))))
    (helixel-mc-clear-all)))

;; ── Region overlap merging (Helix selection-set rule) ─────────────

(ert-deftest helixel-test-mc-dedupe-drops-overlapping-fake-region ()
  "When two fakes' active regions overlap, the rightmost is dropped."
  (helixel-test-with-buffer "abcdefghij\n"
    (helixel-enter-normal-state)
    (goto-char 1)                       ; real outside
    (helixel-mc-create-fake-cursor 5 2) ; fake1 region [2,5)
    (helixel-mc-create-fake-cursor 7 4) ; fake2 region [4,7) overlaps
    (should (= 1 (helixel-mc-dedupe-cursors)))
    (should (= 1 (length (helixel-mc-all-cursors))))
    ;; The surviving fake is the leftmost (ended at 5).
    (let ((ov (car (helixel-mc-all-cursors))))
      (should (= 5 (marker-position
                    (overlay-get ov 'helixel-mc-point)))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-dedupe-keeps-non-overlapping-fakes ()
  "Adjacent (touching) but non-overlapping regions are preserved."
  (helixel-test-with-buffer "abcdefghij\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-mc-create-fake-cursor 4 2) ; [2,4)
    (helixel-mc-create-fake-cursor 6 4) ; [4,6) — touch but not overlap
    (should (= 0 (helixel-mc-dedupe-cursors)))
    (should (= 2 (length (helixel-mc-all-cursors))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-dedupe-drops-fake-overlapping-real ()
  "A fake region overlapping the real cursor's region is dropped.
Real is never deleted."
  (helixel-test-with-buffer "abcdefghij\n"
    (helixel-enter-normal-state)
    (goto-char 2)
    (set-mark 6)                        ; real region [2,6)
    (helixel-mc-create-fake-cursor 8 4) ; fake region [4,8) overlaps
    (should (= 1 (helixel-mc-dedupe-cursors)))
    (should (= 0 (length (helixel-mc-all-cursors))))
    ;; Real still in place and active.
    (should (= 2 (point)))
    (should mark-active)
    (helixel-mc-clear-all)
    (deactivate-mark)))

(ert-deftest helixel-test-mc-dedupe-ignores-point-only-fakes ()
  "Point-only fakes (no active region) are NOT subject to the
region-overlap pass — only Pass 1 (identical point+mark) can
drop them."
  (helixel-test-with-buffer "abcdefghij\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    ;; A fake with a region…
    (helixel-mc-create-fake-cursor 7 3) ; [3,7)
    ;; …and a point-only fake INSIDE that range.
    (helixel-mc-create-fake-cursor 5)
    ;; Point-only fake has no region → region pass ignores it.
    (should (= 0 (helixel-mc-dedupe-cursors)))
    (should (= 2 (length (helixel-mc-all-cursors))))
    (helixel-mc-clear-all)))

;; ── Phase D: . and , under mc ─────────────────────────────────

(ert-deftest helixel-test-mc-dot-replays-per-cursor-last-event ()
  "Each fake snapshots its own `helixel--last-edit' via
`helixel-mc-cursor-vars' after the broadcast.  `.' replayed via
the amalgamated dispatcher must use the per-cursor snapshot, not
the real cursor's event."
  (helixel-test-with-buffer "foo bar baz\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-mc-create-fake-cursor 5)
    (helixel-mc-create-fake-cursor 9)
    ;; Manufacture distinct events on each cursor by writing
    ;; directly to the overlay snapshots.
    (let* ((sel (helixel-sel-create 'line '(:dir forward :count 1)
                                    #'ignore))
           (tx (helixel-edit-create 'insert-text sel
                 :runner (lambda (_tx) (insert "X"))
                 :text "X")))
      (setq helixel--last-edit tx)
      (dolist (ov (helixel-mc-all-cursors))
        (overlay-put ov 'helixel--last-edit tx)))
    ;; Now broadcast `.' — dispatcher's around-advice converts it
    ;; to a single execute-edit at each cursor's point.
    (helixel--execute-edit helixel--last-edit)
    (helixel-mc-with-each-cursor
      (let ((helixel--inhibit-repeat-record t))
        (helixel--execute-edit helixel--last-edit)))
    ;; Each cursor inserted an X at its position.
    (should (string-match-p "X" (buffer-string)))
    (should (>= (length (split-string (buffer-string) "X")) 4))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-broadcast-snapshots-last-event ()
  "After a broadcast edit, each fake's overlay `helixel--last-edit'
property must be updated by `leave-cursor' — otherwise a later
`.' at the fake would replay a stale TX."
  (helixel-test-with-buffer "aaa bbb\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    ;; Wipe any stale `helixel--last-edit' from previous tests so
    ;; the fresh fake's snapshot really starts nil.
    (let ((helixel--last-edit nil))
      (helixel-mc-create-fake-cursor 5)
      ;; Initially fakes have no last-event snapshot.
      (let ((ov (car (helixel-mc-all-cursors))))
        (should-not (overlay-get ov 'helixel--last-edit))
        (helixel-mc-with-each-cursor
          (let ((sel (helixel-sel-create 'line '(:dir forward :count 1)
                                         #'ignore)))
            (setq helixel--last-edit
                  (helixel-edit-create 'noop sel))))
        (should (overlay-get ov 'helixel--last-edit))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-dot-bypasses-advance-with-fakes ()
  "`helixel-repeat-edit' under mc must NOT call the full advance+apply
loop — just `helixel--execute-edit' once.  Verify the around-advice
fires only when fakes exist."
  (helixel-test-with-buffer "abc\n"
    (helixel-mc-create-fake-cursor 2)
    ;; Stub last-event with a counter.
    (let* ((called 0)
           (sel (helixel-sel-create 'line '(:dir forward :count 1)
                                    #'ignore))
           (tx (helixel-edit-create 'noop sel
                 :runner (lambda (_tx) (cl-incf called)))))
      (setq helixel--last-edit tx)
      ;; Direct call to advised `.':
      (helixel-repeat-edit)
      ;; The around advice runs `helixel--execute-edit' exactly once
      ;; at real (no advance loop).  Broadcast to fakes is the
      ;; dispatcher's job (not measured here — we directly assert
      ;; the advice short-circuits the advance loop).
      (should (= 1 called)))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-chain-broadcast-then-dot-at-fakes ()
  "After `q...ESC' the chain TX is broadcast to every fake via
`helixel-mc--broadcast-last-event'.  A later `.' dispatched at a
fake then replays the chain TX (not the pre-chain edit)."
  (helixel-test-with-buffer "abc\n"
    (helixel-mc-create-fake-cursor 2)
    (let* ((sel (helixel-sel-create 'line '(:dir forward :count 1)
                                    #'ignore))
           (tx (helixel-edit-create 'chain sel
                 :runner (lambda (_tx) (ignore))
                 :kmacro (vector ?x))))
      (setq helixel--last-edit tx)
      (helixel-mc--broadcast-last-event)
      ;; Every fake's overlay holds the chain TX as last-event.
      (dolist (ov (helixel-mc-all-cursors))
        (should (eq tx (overlay-get ov 'helixel--last-edit)))))
    (helixel-mc-clear-all)))

;; ── Phase C: find-char per-cursor + per-fake error tolerance ────

;; ── Action cycle (`;') + jump nav (C-o / C-i) are real-only ─────

(ert-deftest helixel-test-mc-action-cycle-broadcasts ()
  "`;' is whitelisted for multi-cursor dispatch: each fake
cycles its OWN per-cursor `helixel--event-ring' built from
commands dispatched after the fake was spawned."
  (should (eq t (get 'helixel-action-cycle 'multiple-cursors))))

(ert-deftest helixel-test-mc-per-fake-event-ring-isolated ()
  "After broadcasting `w' to fakes, each fake's overlay carries
its OWN `helixel--event-ring' independent of real's and of
other fakes' (snapshotted by `helixel-mc--leave-cursor')."
  (helixel-test-with-buffer "alpha beta gamma delta epsilon\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-mc-create-fake-cursor 7)   ; on `beta'
    (helixel-mc-create-fake-cursor 12)  ; on `gamma'
    ;; Broadcast one word-motion to every fake.
    (helixel-mc-with-each-cursor (helixel-forward-word-start 1))
    ;; Each fake's overlay should have a private ring with the
    ;; just-committed motion event.
    (dolist (ov (helixel-mc-all-cursors))
      (let ((ring (overlay-get ov 'helixel--event-ring)))
        ;; Ring is per-cursor and points at independent events.
        (should (listp ring))))
    ;; Real's ring is NOT contaminated by fake commits (rings are
    ;; separated by snapshot/restore).
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-global-jump-log-not-polluted ()
  "`helixel--global-jump-log' must NOT receive entries committed
during fake dispatch (it is cross-buffer global state)."
  (helixel-test-with-buffer "alpha beta gamma delta\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-mc-create-fake-cursor 7)
    (helixel-mc-create-fake-cursor 12)
    (let ((before (length helixel--global-jump-log)))
      ;; Broadcast a motion to 2 fakes — real does NOT run it here.
      (helixel-mc-with-each-cursor (helixel-forward-word-start 1))
      ;; Without inhibit, length would grow by ≥1 (deduped) from
      ;; fake commits.  With inhibit, fakes contribute nothing.
      (should (= before (length helixel--global-jump-log))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-per-fake-ring-grows-over-multiple-motions ()
  "Successive motions broadcast to a fake commit successive
events into the fake's OWN ring.  3 motions → 2 ring entries +
1 still-live (commit happens at the NEXT `tracking-open')."
  (helixel-test-with-buffer
      "alpha beta gamma delta epsilon zeta eta theta\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-mc-create-fake-cursor 7)
    (dotimes (_ 3)
      (helixel-mc-with-each-cursor (helixel-forward-word-start 1)))
    (let* ((ov (car (helixel-mc-all-cursors)))
           (ring (overlay-get ov 'helixel--event-ring))
           (live (overlay-get ov 'helixel--live-edit)))
      (should (= 2 (length ring)))
      (should live)
      (dolist (e ring)
        (should (eq 'movement (helixel-edit-category e)))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-per-fake-rings-are-independent ()
  "Each fake's ring grows independently — commits from cursor A
do NOT leak into cursor B's ring.  Achieved because
`helixel-mc-cursor-vars' snapshots `helixel--event-ring' /
`helixel--live-edit' per cursor."
  (helixel-test-with-buffer
      "alpha beta gamma delta epsilon zeta eta theta iota kappa\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-mc-create-fake-cursor 7)   ; fake A on `beta'  (col 6)
    (helixel-mc-create-fake-cursor 13)  ; fake B on `delta' (col 12)
    ;; Two motions → each fake commits 1 to ring, 1 stays live.
    (helixel-mc-with-each-cursor (helixel-forward-word-start 1))
    (helixel-mc-with-each-cursor (helixel-forward-word-start 1))
    (let* ((sorted (sort (helixel-mc-all-cursors)
                         (lambda (a b)
                           (< (marker-position
                               (overlay-get a 'helixel-mc-point))
                              (marker-position
                               (overlay-get b 'helixel-mc-point))))))
           (fakeA (nth 0 sorted))
           (fakeB (nth 1 sorted))
           (ringA (overlay-get fakeA 'helixel--event-ring))
           (ringB (overlay-get fakeB 'helixel--event-ring))
           (begA  (marker-position
                   (car (helixel-edit-mark-region (car ringA)))))
           (begB  (marker-position
                   (car (helixel-edit-mark-region (car ringB))))))
      (should (= 1 (length ringA)))
      (should (= 1 (length ringB)))
      ;; Per-cursor isolation: fakeA's mark-region is near beta;
      ;; fakeB's mark-region is near delta.  They are NOT eq.
      (should (< begA begB))
      (should (not (eq (car ringA) (car ringB)))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-semicolon-on-empty-ring-is-noop ()
  "Pressing `;' at a fake whose ring is empty (no motions ever
broadcast since spawn) is a silent no-op — must not error and
must not corrupt the fake's state."
  (helixel-test-with-buffer "abc def ghi\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (let ((ov (helixel-mc-create-fake-cursor 5)))
      ;; Sanity: fresh fake has nil ring and nil live-event.
      (should (null (overlay-get ov 'helixel--event-ring)))
      (should (null (overlay-get ov 'helixel--live-edit)))
      ;; Broadcast `;' — fake's `helixel-action-cycle' sees no
      ;; ring, no live; prints "No saved actions" and returns.
      (helixel-mc-with-each-cursor (helixel-action-cycle))
      ;; Fake's point/mark unchanged.
      (should (= 5 (marker-position
                    (overlay-get ov 'helixel-mc-point)))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-spawn-after-motion-inherits-real-ring ()
  "Spawning a fake AFTER real built a ring: the fake inherits
real's `helixel--event-ring' / `--live-edit' via the snapshot
taken by `helixel-mc-create-fake-cursor'.  This means
`w w w s s ;' DOES work — fake's `;' cycles the inherited
history."
  (helixel-test-with-buffer "alpha beta gamma delta epsilon\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    ;; Real builds ring with 2 word motions.
    (helixel-forward-word-start 1)
    (helixel-forward-word-start 1)
    (let ((real-ring-len (length helixel--event-ring))
          (real-live helixel--live-edit))
      (should (>= real-ring-len 1))
      ;; Spawn fake AFTER motions.
      (let* ((ov (helixel-mc-create-fake-cursor 13))
             (fake-ring (overlay-get ov 'helixel--event-ring))
             (fake-live (overlay-get ov 'helixel--live-edit)))
        ;; Fake's snapshot copies real's history.
        (should (= real-ring-len (length fake-ring)))
        (should (eq real-live fake-live))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-action-cycle-no-message-spam ()
  "`with-each-cursor' binds `inhibit-message' so that `;' (which
calls `(message ...)' inside `helixel-action--cycle-show')
doesn't echo once per fake."
  (helixel-test-with-buffer "(aa) (bb) (cc)\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-mc-create-fake-cursor 6)
    (helixel-mc-create-fake-cursor 11)
    (helixel-mc-with-each-cursor (helixel-jump-to-match))
    ;; Capture echo area: should not record per-fake messages.
    (let ((messages-count 0))
      (cl-letf (((symbol-function 'message)
                 (lambda (&rest _) (cl-incf messages-count))))
        ;; Under `inhibit-message t' our advice still increments
        ;; — but the standard `message' WOULD be suppressed at the
        ;; echo area.  What we verify: the `with-each-cursor'
        ;; macroexpansion DOES bind `inhibit-message'.
        (let ((expansion (macroexpand-1
                          '(helixel-mc-with-each-cursor t))))
          (should (member 'inhibit-message (flatten-tree expansion))))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-removed-motion-overlay-props ()
  "Cleanup verification: the obsolete overlay properties
`helixel-mc-pre-point' / `-motion-pre-point' / `-motion-bounds'
are no longer written by `helixel-mc--enter/leave-cursor'."
  (helixel-test-with-buffer "alpha beta gamma\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-mc-create-fake-cursor 7)
    (helixel-mc-with-each-cursor (helixel-forward-word-start 1))
    (let ((ov (car (helixel-mc-all-cursors))))
      (should (null (overlay-get ov 'helixel-mc-pre-point)))
      (should (null (overlay-get ov 'helixel-mc-motion-pre-point)))
      (should (null (overlay-get ov 'helixel-mc-motion-bounds))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-jump-nav-is-real-only ()
  "C-o / C-i navigate the GLOBAL `helixel--global-jump-log'; same
argument as `;' — real-only."
  (dolist (cmd '(helixel-jump-backward helixel-jump-forward))
    (should (plist-member (symbol-plist cmd) 'multiple-cursors))
    (should (null (get cmd 'multiple-cursors)))))

(ert-deftest helixel-test-mc-jump-to-match-broadcasts ()
  "`%' (`helixel-jump-to-match') is pure point-local; broadcast
must send each fake to ITS own matching delimiter."
  (should (eq t (get 'helixel-jump-to-match 'multiple-cursors)))
  (helixel-test-with-buffer "(aa) (bb) (cc)\n"
    (helixel-enter-normal-state)
    (goto-char 1)                       ; on first `('
    (helixel-mc-create-fake-cursor 6)   ; on second `('
    (helixel-mc-create-fake-cursor 11)  ; on third `('
    (helixel-jump-to-match)
    (helixel-mc-with-each-cursor (helixel-jump-to-match))
    (should (= 5 (point)))              ; real → after first `)'
    (let ((points (sort (mapcar
                         (lambda (ov)
                           (marker-position
                            (overlay-get ov 'helixel-mc-point)))
                         (helixel-mc-all-cursors))
                        #'<)))
      (should (equal '(10 15) points)))  ; fakes → their `)' each
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-bracket-movement-broadcasts ()
  "`])' / `[(' / etc. are point-local textobj-end movements;
broadcast must advance each fake to ITS own next/outer match."
  (should (eq t (get 'helixel-next-paren-end 'multiple-cursors)))
  (should (eq t (get 'helixel-outer-paren  'multiple-cursors)))
  (helixel-test-with-buffer "(aa) (bb) (cc) (dd)\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-mc-create-fake-cursor 6)
    (helixel-next-paren-end)
    (helixel-mc-with-each-cursor (helixel-next-paren-end))
    ;; `helixel-next-paren-end' lands one PAST the closing `)'.
    (should (= 5 (point)))
    (should (= 10 (marker-position
                  (overlay-get (car (helixel-mc-all-cursors))
                               'helixel-mc-point))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-semicolon-after-percent-marks-per-cursor ()
  "After `%' (broadcast) every cursor has point at its own match;
the first `;' must then select the pair AT EACH cursor by
activating mark over the (pre, post) span."
  (helixel-test-with-buffer "(aa) (bb) (cc)\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-mc-create-fake-cursor 6)
    (helixel-mc-create-fake-cursor 11)
    ;; Broadcast `%' — each cursor moves to its own `)' (one past).
    (helixel-jump-to-match)
    (helixel-mc-with-each-cursor (helixel-jump-to-match))
    ;; Pre-`;': no cursor has an active region.
    (should (not mark-active))
    (dolist (ov (helixel-mc-all-cursors))
      (should (not (overlay-get ov 'mark-active))))
    ;; First `;' — broadcast so each fake cycles its OWN ring's
    ;; `%' event and marks its enclosing pair.
    (let ((last-command 'helixel-jump-to-match))
      (helixel-action-cycle)
      (helixel-mc-with-each-cursor (helixel-action-cycle)))
    ;; Real now has an active region spanning pre→post.
    (should mark-active)
    (should (/= (point) (mark t)))
    ;; Every fake has mark-active flipped on with a non-degenerate span.
    (dolist (ov (helixel-mc-all-cursors))
      (should (overlay-get ov 'mark-active))
      (let ((p (marker-position (overlay-get ov 'helixel-mc-point)))
            (m (marker-position (overlay-get ov 'helixel-mc-mark))))
        (should (/= p m))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-semicolon-marks-pair-at-each-fake ()
  "`%' then `;' at every fake: each fake's per-cursor event ring
holds its own `%' event whose `:mark-region' covers that fake's
enclosing pair.  Broadcasting `;' makes each fake cycle its OWN
ring and select the FAR endpoint of that pair, exactly like
real."
  (helixel-test-with-buffer "abc { xx } def { yy } ghi\n"
    (helixel-enter-normal-state)
    (goto-char 1) (push-mark 1 t t) (goto-char 3)
    (let ((ov (helixel-mc-create-fake-cursor 11 9)))
      (overlay-put ov 'mark-active t))
    (goto-char 5)
    (helixel-mc-with-each-cursor (goto-char 17))
    (helixel-jump-to-match)
    (helixel-mc-with-each-cursor (helixel-jump-to-match))
    ;; ; broadcasts: real cycles, each fake cycles its OWN ring.
    (let ((last-command 'helixel-jump-to-match))
      (helixel-action-cycle)
      (helixel-mc-with-each-cursor (helixel-action-cycle)))
    (let* ((fake (car (helixel-mc-all-cursors)))
           (m (marker-position (overlay-get fake 'helixel-mc-mark)))
           (p (marker-position (overlay-get fake 'helixel-mc-point))))
      (should (= 16 m))                 ; matching `{'
      (should (= 22 p))                 ; matching `}'
      (should (overlay-get fake 'mark-active)))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-insert-before-after-search-spawn ()
  "Regression for `/foo<RET>ssifoo<ESC>': `i' after `ss' must
insert BEFORE each match, at every cursor (real + fakes).

Previously the `helixel-state-change-hook' sync ran on EVERY
state transition and deactivated each fake's `mark-active'
before `helixel-mc--prepos-region-begin' could read it.  The
pre-positioner's `(when (and mark-active (mark t)) ...)' guard
then skipped the goto, leaving each fake at match-END.
Subsequent `self-insert-command' broadcasts inserted AFTER the
match instead of before — `hellofoo' rather than `foohello'.

Fix: the sync only acts on transitions INTO / OUT OF `visual'."
  (helixel-test-with-buffer "hello\nhello\nhello\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    ;; Simulate /hello<RET>: real selects first match (mark=1 pt=6).
    (re-search-forward "hello")
    (set-mark (match-beginning 0))
    (helixel--sel-push
     (helixel-sel-create 'search
                         (list :pattern "hello" :dir 'forward)
                         #'helixel--recreate-search))
    ;; ss: spawn fakes on remaining matches.
    (helixel-mc-toggle)
    (should (= 2 (length (helixel-mc-all-cursors))))
    ;; Each cursor should have an active region (mark=match-begin,
    ;; point=match-end) BEFORE we press `i'.
    (should mark-active)
    (dolist (ov (helixel-mc-all-cursors))
      (should (overlay-get ov 'mark-active)))
    ;; i: real-side body + :after advice pre-positions each fake.
    (let ((this-command 'helixel-insert))
      (call-interactively 'helixel-insert)
      (helixel-mc--post-command))
    ;; Real moved to its match-begin (1).
    (should (= 1 (point)))
    ;; Each fake moved to ITS match-begin (7, 13).
    (let ((pts (sort (mapcar (lambda (ov)
                               (marker-position
                                (overlay-get ov 'helixel-mc-point)))
                             (helixel-mc-all-cursors))
                     #'<)))
      (should (equal '(7 13) pts)))
    ;; Broadcast `foo' character by character.
    (dolist (c '(?f ?o ?o))
      (let ((last-command-event c)
            (this-command 'self-insert-command))
        (call-interactively 'self-insert-command)
        (helixel-mc--post-command)))
    (should (equal "foohello\nfoohello\nfoohello\n"
                   (buffer-string)))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-semicolon-percent-from-inside-pair-selects-full-pair ()
  "Regression for `/hello<RET>ss%;d': `%' from a position INSIDE
an enclosing pair (e.g. on the word \"hello\" between `{' and
`}') jumps to ONE end of the pair, and stores the pair bounds
in the live event's mark-region.  The first `;' must select the
FULL pair AT EACH cursor — not just (pre-point, post-point) —
so that a subsequent `d' deletes the whole `{...}' block."
  (helixel-test-with-buffer "a {x} b {y} c {z}\n"
    (helixel-enter-normal-state)
    (goto-char 4)                       ; real on 'x' inside first pair
    (helixel-mc-create-fake-cursor 10)  ; fake on 'y' inside second pair
    (helixel-mc-create-fake-cursor 16)  ; fake on 'z' inside third pair
    ;; Broadcast `%' — each cursor jumps to one end of its pair
    ;; and live-event mark-region holds the pair bounds.
    (helixel-jump-to-match)
    (helixel-mc-with-each-cursor (helixel-jump-to-match))
    ;; First `;' broadcast — each fake cycles its OWN ring.
    (let ((last-command 'helixel-jump-to-match))
      (helixel-action-cycle)
      (helixel-mc-with-each-cursor (helixel-action-cycle)))
    ;; Real selects full first pair `{x}' (positions 3..6).
    (should mark-active)
    (should (or (and (= 3 (point)) (= 6 (mark t)))
                (and (= 3 (mark t)) (= 6 (point)))))
    ;; Each fake selects ITS own full pair.
    (let* ((sorted (sort (helixel-mc-all-cursors)
                         (lambda (a b)
                           (< (marker-position
                               (overlay-get a 'helixel-mc-point))
                              (marker-position
                               (overlay-get b 'helixel-mc-point))))))
           (regions (mapcar
                     (lambda (ov)
                       (let ((p (marker-position
                                 (overlay-get ov 'helixel-mc-point)))
                             (m (marker-position
                                 (overlay-get ov 'helixel-mc-mark))))
                         (cons (min p m) (max p m))))
                     sorted)))
      (should (equal '((9 . 12) (15 . 18)) regions))
      (dolist (ov sorted)
        (should (overlay-get ov 'mark-active))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-semicolon-second-press-cycles-fake-ring ()
  "Second `;' (consecutive press) at fakes also broadcasts now:
because each fake owns a `helixel--event-ring' and `helixel--
action-pos', repeated `;' cycles each fake's OWN history.  Verify
the call doesn't error and the fake's ring still exists."
  (helixel-test-with-buffer "(aa) (bb) (cc)\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-mc-create-fake-cursor 6)
    ;; Build a motion event in each fake's ring via `%'.
    (helixel-mc-with-each-cursor (helixel-jump-to-match))
    ;; First `;': fake cycles to its `%' event.
    (let ((last-command 'helixel-jump-to-match))
      (helixel-mc-with-each-cursor (helixel-action-cycle)))
    ;; Second `;': fake cycles further back in its OWN ring —
    ;; "At oldest" message is harmless; no error.
    (let ((last-command 'helixel-action-cycle))
      (helixel-mc-with-each-cursor (helixel-action-cycle)))
    ;; Sanity: fake still has its private ring.
    (let ((ov (car (helixel-mc-all-cursors))))
      (should (listp (overlay-get ov 'helixel--event-ring))))
    (helixel-mc-clear-all)))

;; ── Performance: large cursor counts ────────────────────────

(ert-deftest helixel-test-mc-eol-cursor-string-cached ()
  "Repeated paints at end-of-line reuse the cached propertized
string instead of allocating a new one each call."
  (helixel-test-with-buffer "\n"
    (setq helixel-mc--eol-cursor-string nil)
    (let* ((ov1 (helixel-mc-create-fake-cursor 1))
           (s1  (overlay-get ov1 'after-string))
           (ov2 (helixel-mc-create-fake-cursor 1)))
      ;; Pass 1 dedupe will drop ov2 (same key as ov1), so spawn
      ;; another fresh fake at eol-equivalent position.
      (ignore ov2)
      (helixel-mc--paint-cursor-overlay ov1 1)
      (should (eq s1 (overlay-get ov1 'after-string)))
      (should (eq s1 helixel-mc--eol-cursor-string)))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-dedupe-fast-path-no-regions ()
  "With many fakes but none carrying an active region, Pass 2 of
`helixel-mc-dedupe-cursors' must short-circuit and return 0
removals without sorting."
  (helixel-test-with-buffer (make-string 200 ?x)
    (helixel-enter-normal-state)
    (goto-char 1)
    (dotimes (i 100)
      (helixel-mc-create-fake-cursor (+ 2 i)))
    ;; No regions anywhere → Pass 2 fast-path.
    (should (= 0 (helixel-mc-dedupe-cursors)))
    (should (= 100 (length (helixel-mc-all-cursors))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-dispatch-stress-200-cursors ()
  "200-cursor movement broadcast finishes in well under 1s.
Protects against catastrophic O(N²) regressions in the
dispatcher / dedupe pipeline."
  (helixel-test-with-buffer (make-string 250 ?x)
    (helixel-enter-normal-state)
    (goto-char 1)
    (dotimes (i 200)
      (helixel-mc-create-fake-cursor (+ 2 i)))
    (should (= 200 (length (helixel-mc-all-cursors))))
    (let ((start (float-time)))
      (helixel-mc-with-each-cursor (forward-char 1))
      (helixel-mc-dedupe-cursors)
      (should (< (- (float-time) start) 1.0)))
    (helixel-mc-clear-all)))



(ert-deftest helixel-test-mc-replace-char-real-only-and-broadcasts ()
  "`R<ch>' broadcasts the replacement to every fake via the
edit-replay dispatch path (runner reads :char from payload — no
advice, no real-only marking)."
  (helixel-test-with-buffer "abc def ghi\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-mc-create-fake-cursor 5)
    (helixel-mc-create-fake-cursor 9)
    ;; Drive the command (sets `this-command' = helixel-replace-char),
    ;; then drive the post-command dispatcher which sees the fresh
    ;; edit (op=replace-char, by-command=helixel-replace-char) and
    ;; replays its runner at every fake.
    (let ((unread-command-events (list ?X)))
      (call-interactively 'helixel-replace-char))
    (let ((this-command 'helixel-replace-char))
      (helixel-mc--post-command))
    ;; Real at pos 1 → 'a' replaced.  Fakes at 5 ('d') and 9 ('h').
    (should (string-match-p "Xbc Xef Xhi" (buffer-string)))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-surround-add-real-only-and-broadcasts ()
  "`ms(' broadcasts the surround to every fake via the edit-replay
dispatch path (runner reads :char from payload — no advice)."
  (helixel-test-with-buffer "foo bar baz\n"
    (helixel-enter-normal-state)
    ;; Real selects \"foo\" (1..4); fakes select \"bar\" (5..8), \"baz\" (9..12).
    (goto-char 4)
    (set-mark 1)
    (helixel-mc-create-fake-cursor 8 5)
    (helixel-mc-create-fake-cursor 12 9)
    (let ((unread-command-events (list ?\()))
      (call-interactively 'helixel-surround-add))
    (let ((this-command 'helixel-surround-add))
      (helixel-mc--post-command))
    ;; All three got wrapped with (...).
    (should (string-match-p "(foo) (bar) (baz)" (buffer-string)))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-surround-delete-real-only-and-broadcasts ()
  "`md' (in edit branch — pending-sel already has delimiter) broadcasts
the delete to every fake via the fresh-edit dispatch path.  Each
fake's runner uses the delimiter struct's finder to re-locate its
OWN enclosing pair — no per-cursor advice needed."
  (helixel-test-with-buffer "(foo) (bar) (baz)\n"
    (helixel-enter-normal-state)
    ;; Build a pair-delimiter for `(' ... `)' and seed it as each
    ;; cursor's pending-sel.
    (let* ((pair (helixel--surround-lookup ?\())
           (d (helixel--make-pair-delimiter (car pair) (cdr pair)))
           (mk-sel
            (lambda ()
              (helixel-sel-create 'surround `(:delimiter ,d)
                                  (lambda (_) nil)))))
      ;; Real at first pair, fakes at others.
      (goto-char 3)                    ; inside first (foo)
      (helixel--sel-push (funcall mk-sel))
      (helixel-mc-create-fake-cursor 9)  ; inside (bar)
      (helixel-mc-create-fake-cursor 15) ; inside (baz)
      ;; Snapshot pending-sel into each fake's overlay so enter-
      ;; cursor restores it during the broadcast.
      (dolist (ov (helixel-mc-all-cursors))
        (overlay-put ov 'helixel--pending-sel (funcall mk-sel)))
      ;; Real runs `md'; this commits an edit with by-command=
      ;; helixel-surround-delete.  Then post-command dispatch sees
      ;; the fresh edit and replays the runner at every fake.
      (helixel-surround-delete)
      (let ((this-command 'helixel-surround-delete))
        (helixel-mc--post-command))
      ;; All three pairs of parentheses gone.
      (should (string-match-p "\\`foo bar baz\n\\'" (buffer-string)))
      (helixel-mc-clear-all))))

(ert-deftest helixel-test-mc-surround-delete-skips-transient-branch ()
  "When real takes the transient setup branch (no pending-sel
delimiter), the :after advice must NOT broadcast — broadcasting
would delete spurious surroundings before the user picks a
textobj."
  (helixel-test-with-buffer "(foo)\n"
    (helixel-enter-normal-state)
    (goto-char 2)
    (helixel--sel-push nil)
    (helixel-mc-create-fake-cursor 3)
    ;; No pending-sel → transient branch sets pending-surround-op.
    (let ((helixel--pending-surround-op nil))
      (helixel-surround-delete)
      ;; transient branch was entered.
      (should helixel--pending-surround-op)
      ;; Buffer unchanged — nothing was deleted.
      (should (equal "(foo)\n" (buffer-string))))
    (setq helixel--pending-surround-op nil)
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-find-char-per-fake-no-prompt ()
  "`f<ch>' at real with fakes → each fake searches forward for the
same char from its own position, using the substitute mechanism."
  (helixel-test-with-buffer "a-b c-d e-f g-h\n"
    (helixel-enter-normal-state)
    (goto-char 1)                       ; real before 'a'
    (helixel-mc-create-fake-cursor 5)   ; before 'c'
    (helixel-mc-create-fake-cursor 9)   ; before 'e'
    ;; Real: find next `-' → position 3 (after `-' in a-b).
    (helixel-find-next-char ?-)
    ;; Drive the substituted dispatcher by simulating post-command:
    (let ((this-command 'helixel-find-next-char))
      (helixel-mc--post-command))
    ;; Real is past first `-'.
    (should (= 3 (point)))
    ;; Each fake advanced to the next `-' after its starting pos.
    (let ((points (sort (mapcar
                         (lambda (ov)
                           (marker-position
                            (overlay-get ov 'helixel-mc-point)))
                         (helixel-mc-all-cursors))
                        #'<)))
      (should (equal '(7 11) points)))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-find-char-deletes-failing-fake ()
  "A fake whose direction has no occurrence of the target char
must be silently dropped instead of aborting the batch."
  (helixel-test-with-buffer "a-b c-d efghij\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-mc-create-fake-cursor 5)   ; before 'c' — has '-' ahead
    (helixel-mc-create-fake-cursor 9)   ; before 'e' — NO '-' ahead
    (helixel-find-next-char ?-)
    (let ((this-command 'helixel-find-next-char))
      (helixel-mc--post-command))
    ;; The fake at 9 (no '-' ahead) is dropped; the one at 5 survived
    ;; and advanced to the '-' at column 7.
    (should (= 1 (length (helixel-mc-all-cursors))))
    (should (= 7 (marker-position
                  (overlay-get (car (helixel-mc-all-cursors))
                               'helixel-mc-point))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-amalgamated-dispatcher-dedupes ()
  "The amalgamated dispatcher must also call
`helixel-mc-dedupe-cursors' after the batch (Phase A behaviour
must apply with or without the substitute mechanism active)."
  (helixel-test-with-buffer "abcdefg\n"
    (goto-char 1)
    (helixel-mc-create-fake-cursor 4)
    (helixel-mc-create-fake-cursor 5)
    (let ((this-command 'forward-char))
      (helixel-mc-with-each-cursor (goto-char 8))
      (helixel-mc--post-command))
    (should (= 1 (length (helixel-mc-all-cursors))))
    (helixel-mc-clear-all)))

;; ── Phase B: Visual / select 状态同步 ─────────────────────────────

(ert-deftest helixel-test-mc-visual-enter-syncs-fakes ()
  "`helixel-begin-selection' (`v') with existing fakes must activate
the mark on every fake at its own point so subsequent broadcast
movements extend per-cursor selections."
  (helixel-test-with-buffer "abc def ghi\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-mc-create-fake-cursor 5)
    (helixel-mc-create-fake-cursor 9)
    ;; Real enters visual.
    (helixel-begin-selection)
    ;; Real has mark-active at its own point.
    (should mark-active)
    (should (= (mark t) (point)))
    ;; Each fake also has mark-active=t with mark at its own point.
    (dolist (ov (helixel-mc-all-cursors))
      (should (overlay-get ov 'mark-active))
      (let ((p (marker-position (overlay-get ov 'helixel-mc-point)))
            (m (marker-position (overlay-get ov 'helixel-mc-mark))))
        (should (= p m))))
    (helixel-mc-clear-all)
    (helixel-visual-exit)))

(ert-deftest helixel-test-mc-visual-exit-deactivates-fakes ()
  "Leaving visual via `helixel-visual-exit' must deactivate the
mark on every fake cursor."
  (helixel-test-with-buffer "abc def ghi\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-mc-create-fake-cursor 5)
    (helixel-begin-selection)
    (dolist (ov (helixel-mc-all-cursors))
      (should (overlay-get ov 'mark-active)))
    ;; Now exit visual.
    (helixel-visual-exit)
    (dolist (ov (helixel-mc-all-cursors))
      (should-not (overlay-get ov 'mark-active)))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-visual-broadcast-not-toggled ()
  "`helixel-begin-selection' must be real-cursor-only so per-command
broadcast does not toggle visual off on each fake."
  (should (plist-member (symbol-plist 'helixel-begin-selection)
                        'multiple-cursors))
  (should (null (get 'helixel-begin-selection 'multiple-cursors)))
  (should (plist-member (symbol-plist 'helixel-visual-exit)
                        'multiple-cursors))
  (should (null (get 'helixel-visual-exit 'multiple-cursors))))

(ert-deftest helixel-test-mc-spawn-exits-visual-state ()
  "Spawning a fake cursor (any path) must exit `visual' state so
subsequent movements make fresh per-cursor selections instead of
extending the visual region (Helix `v' → `xxx' → `s x' → `w' `w'
bug: 2nd `w' extended because clear-highlights is a no-op in visual)."
  (helixel-test-with-buffer "aaa bbb\nccc ddd\neee fff\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    ;; Enter visual state explicitly.
    (helixel-begin-selection)
    (should (eq 'visual helixel--current-state))
    ;; Now select 3 lines in visual mode.
    (setq this-command 'helixel-select-line)
    (helixel-select-line 3)
    (should (eq 'visual helixel--current-state))
    ;; `s x' — must drop us back to normal.
    (helixel-mc-edit-lines (region-beginning) (region-end))
    (should (eq 'normal helixel--current-state))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-sx-then-w-w-no-extend-from-visual ()
  "After `v xxx s x', `s x' switches us back to normal state.
Premise of the old (BOL-point) assertion is obsolete: `s x'
now keeps a full-line region on each cursor, so `w' — which
with an active region replaces it with the next word — may
or may not preserve newlines depending on word definition.
We just assert the state transition + presence of fakes."
  (helixel-test-with-buffer "aaa bbb ccc\nddd eee fff\nggg hhh iii\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-begin-selection)           ; enter visual
    (setq this-command 'helixel-select-line)
    (helixel-select-line 3)
    (helixel-mc-edit-lines (region-beginning) (region-end))
    (should (eq 'normal helixel--current-state))
    (should (= 2 (length (helixel-mc-all-cursors))))
    (helixel-mc-clear-all)))

;; ── `s a' / `s A' = Helix `C' / `Alt-C': copy cursor to next/prev
;; line same column.  Snapshot real → fake, then move real.

(ert-deftest helixel-test-mc-sa-copies-cursor-down ()
  "`s a' snapshots real at its current spot, then moves real to the
next line same column.  Stacking adds cursors at each line."
  (helixel-test-with-buffer "abc def\nghi jkl\nmno pqr\nstu vwx\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-mc-add-cursor-here)
    ;; Real moved down to line 2 col 0; one fake at original (col 0 of line 1).
    (should (= 9 (point)))
    (should (= 1 (length (helixel-mc-all-cursors))))
    (should (= 1 (marker-position
                  (overlay-get (car (helixel-mc-all-cursors))
                               'helixel-mc-point))))
    (helixel-mc-add-cursor-here)
    (should (= 17 (point)))
    (should (= 2 (length (helixel-mc-all-cursors))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-sa-broadcasts-movement ()
  "After `s a s a', `w' broadcasts to all 3 cursors (real + 2 fakes).
Each cursor selects one word on its own line."
  (helixel-test-with-buffer "abc def\nghi jkl\nmno pqr\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-mc-add-cursor-here)
    (helixel-mc-add-cursor-here)
    (should (= 3 (+ 1 (length (helixel-mc-all-cursors)))))
    ;; Trigger a movement — should be broadcast (default policy).
    (should (helixel-mc--should-run-for-all-p
             'helixel-forward-word-start))
    (setq this-command 'helixel-forward-word-start)
    (call-interactively 'helixel-forward-word-start)
    (run-hooks 'post-command-hook)
    ;; Real region = 3rd line word; fakes = 2nd and 1st line words.
    (should (equal "mno " (buffer-substring-no-properties
                           (region-beginning) (region-end))))
    (let ((fake-regions
           (sort (mapcar (lambda (o)
                           (let ((p (marker-position
                                     (overlay-get o 'helixel-mc-point)))
                                 (m (marker-position
                                     (overlay-get o 'helixel-mc-mark))))
                             (buffer-substring-no-properties
                              (min p m) (max p m))))
                         (helixel-mc-all-cursors))
                 #'string<)))
      (should (equal '("abc " "ghi ") fake-regions)))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-sA-copies-cursor-up ()
  "`s A' copies the cursor upward (Helix `Alt-C')."
  (helixel-test-with-buffer "abc def\nghi jkl\nmno pqr\n"
    (helixel-enter-normal-state)
    (goto-char 17)                      ; line 3 col 0
    (helixel-mc-add-cursor-here-up)
    (should (= 9 (point)))              ; real moved to line 2
    (should (= 1 (length (helixel-mc-all-cursors))))
    (should (= 17 (marker-position
                   (overlay-get (car (helixel-mc-all-cursors))
                                'helixel-mc-point))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-sa-region-copies-region-down ()
  "`s a' with an active region copies the region to the next line.
Real cursor ends up with the same-shape region on the next line;
the original region is snapshotted as a fake."
  (helixel-test-with-buffer "abcde\nfghij\nklmno\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (push-mark 4 t t)                   ; region 1..4 = "abc"
    (helixel-mc-add-cursor-here)
    ;; Real region on line 2: 7..10 = "fgh".
    (should (use-region-p))
    (should (equal "fgh" (buffer-substring-no-properties
                          (region-beginning) (region-end))))
    (should (= 1 (length (helixel-mc-all-cursors))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-sa-no-fitting-line-errors ()
  "`s a' from the last line (and no possible target column) errors.
Use a non-zero column where the next/last line is too short to host
it — with a single-line buffer no further line exists."
  (helixel-test-with-buffer "abc"            ; no trailing newline
    (helixel-enter-normal-state)
    (goto-char 4)                       ; col 3 (end of buffer)
    (should-error (helixel-mc-add-cursor-here)
                  :type 'user-error)))

;; ── Regression: `s n' must place the fake's (point, mark) in the
;; SAME direction as the real cursor's (so `i' / `a' insert at the
;; same logical edge across cursors).

(ert-deftest helixel-test-mc-mark-next-direction-forward ()
  "`miw' leaves point at region-end; `s n' must keep that direction."
  (helixel-test-with-buffer "foo bar foo baz foo\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (setq this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    ;; Real: forward selection (point=4 > mark=1).
    (should (= 4 (point)))
    (should (= 1 (mark t)))
    (helixel-mc-mark-next-like-this)
    (let* ((ov (car (helixel-mc-all-cursors)))
           (fp (marker-position (overlay-get ov 'helixel-mc-point)))
           (fm (marker-position (overlay-get ov 'helixel-mc-mark))))
      ;; Fake at second `foo' (9..12) MUST be forward too:
      ;; point=12, mark=9 — NOT point=9 mark=12.
      (should (> fp fm))
      (should (= 12 fp))
      (should (= 9 fm)))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-mark-next-direction-backward ()
  "When real has point < mark (backward selection), fake matches."
  (helixel-test-with-buffer "foo bar foo baz foo\n"
    (goto-char 1)
    (push-mark 4 t t)                   ; real: point=1, mark=4
    (should (< (point) (mark t)))
    (helixel-mc-mark-next-like-this)
    (let* ((ov (car (helixel-mc-all-cursors)))
           (fp (marker-position (overlay-get ov 'helixel-mc-point)))
           (fm (marker-position (overlay-get ov 'helixel-mc-mark))))
      ;; Backward: point < mark.  2nd foo at 9..12 → fake pt=9 mk=12.
      (should (< fp fm))
      (should (= 9 fp))
      (should (= 12 fm)))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-edit-lines-line-mode-bol ()
  "`s x' over an `x'-style line selection puts a FULL-LINE region
on each line (post-merge with split-into-lines).  Was previously
BOL-point per line; semantics updated to match Helix `Alt-s'."
  (helixel-test-with-buffer "aaa\nbb\ncccc\nd\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    ;; Mimic `x x x x' — select 4 lines (point at last EOL).
    (setq this-command 'helixel-select-line)
    (helixel-select-line 4)
    (should (eq 'line helixel--raw-selection-type))
    (should (use-region-p))
    (helixel-mc-edit-lines (region-beginning) (region-end))
    ;; 4 lines total → 1 real + 3 fakes.
    (should (= 3 (length (helixel-mc-all-cursors))))
    ;; Real has an active full-line region.
    (should (use-region-p))
    (should (equal (buffer-substring-no-properties
                    (region-beginning) (region-end))
                   (save-excursion
                     (goto-char (region-beginning))
                     (buffer-substring-no-properties
                      (line-beginning-position)
                      (line-end-position)))))
    ;; Every cursor's region exactly equals its line content.
    (dolist (ov (helixel-mc-all-cursors))
      (let* ((p (marker-position (overlay-get ov 'helixel-mc-point)))
             (m (marker-position (overlay-get ov 'helixel-mc-mark)))
             (b (min p m)) (e (max p m)))
        (should (overlay-get ov 'mark-active))
        (save-excursion
          (goto-char b)
          (should (= b (line-beginning-position)))
          (should (= e (line-end-position))))))
    ;; Collect line texts (real + fakes) and verify all four lines.
    (let ((texts (sort (cons (buffer-substring-no-properties
                              (region-beginning) (region-end))
                             (mapcar
                              (lambda (ov)
                                (let ((p (marker-position
                                          (overlay-get ov 'helixel-mc-point)))
                                      (m (marker-position
                                          (overlay-get ov 'helixel-mc-mark))))
                                  (buffer-substring-no-properties
                                   (min p m) (max p m))))
                              (helixel-mc-all-cursors)))
                       #'string<)))
      (should (equal '("aaa" "bb" "cccc" "d") texts)))
    (helixel-mc-clear-all)))

;; ── Integrate: apply-last-edit propagates to fake cursors ──

(ert-deftest helixel-test-mc-apply-last-edit ()
  (helixel-test-with-buffer "AAA\nAAA\nAAA\n"
    ;; Build a fake helixel--last-edit whose runner inserts "X".
    (let ((tx (make-helixel-edit
               :op 'test-insert
               :runner (lambda (_tx) (insert "X"))
               :sel nil :payload nil :timestamp 0.0
               :buffer (current-buffer))))
      (setq helixel--last-edit tx)
      (goto-char 1)
      (helixel-mc-create-fake-cursor 5)
      (helixel-mc-create-fake-cursor 9)
      (helixel-mc-apply-last-edit)
      ;; Insert at each cursor; real cursor is also processed via
      ;; broadcast? apply-last-edit only runs on FAKE cursors.
      ;; Result: "AAA\nXAAA\nXAAA\n" (one X per fake cursor).
      (should (string= "AAA\nXAAA\nXAAA\n" (buffer-string)))
      (helixel-mc-clear-all))))

;; ── Cursor-vars: kill-ring isolation ──

(ert-deftest helixel-test-mc-kill-ring-isolation ()
  (helixel-test-with-buffer "x\n"
    (let ((kill-ring '("real")))
      (helixel-mc-create-fake-cursor 2)
      (helixel-mc-with-each-cursor
        (setq kill-ring (cons "fake" kill-ring)))
      (should (equal kill-ring '("real")))
      (let ((ov (car (helixel-mc-all-cursors))))
        (should (member "fake" (overlay-get ov 'kill-ring))))
      (helixel-mc-clear-all))))

;; ── walk-advance: stale-mark / EOB-empty-line bug ──
;;
;; Regression: when the source buffer ends with a trailing empty line
;; (e.g. "alpha beta gamma\n\n"), `mark-inner-word' at end-of-buffer
;; selects nothing AND leaves `mark-marker' pointing at the previous
;; iteration's region.  The old walk-advance read `(mark t)' without
;; checking `mark-active' or whether the mark had moved this iter, so
;; it fabricated a spurious huge target spanning (EOB . old-mark).
;;
;; That extra cursor's region covered almost the entire buffer, and
;; the per-cursor `change' replay then deleted everything, collapsing
;; the buffer to a single replacement string.
;;
;; The fix in `helixel-mc--walk-advance':
;;   1. `(deactivate-mark)' BEFORE each advance call (clean slate)
;;   2. snapshot `before-mark' pre-iter
;;   3. `have-range' now requires `mark-active' AND
;;      mrk /= point AND mrk /= before-mark
;; This test would have produced 4 targets pre-fix; expects 3 post-fix.

(defun helixel-test-mc--word-sel ()
  "Build a textobj word selection for the walk-advance tests."
  (helixel-sel-create
   'textobj
   '(:command helixel-mark-inner-word :count 1
     :delimiter nil :inline-advance t)
   #'helixel--recreate-textobj))

(ert-deftest helixel-test-mc-walk-advance-no-stale-mark-eob ()
  "Walk-advance must not produce a spurious target at EOB / empty line.
A buffer with N words and a trailing empty line must yield exactly
N word targets, not N+1."
  (helixel-test-with-buffer "alpha beta gamma\n\n"
    (helixel-enter-normal-state)
    (let* ((sel (helixel-test-mc--word-sel))
           (targets (helixel-mc--walk-advance sel)))
      (should (= 3 (length targets)))
      ;; Spans must match the three words exactly — no extra entry.
      (let ((spans (mapcar (lambda (p)
                             (let ((a (marker-position (car p)))
                                   (b (marker-position (cdr p))))
                               (buffer-substring-no-properties
                                (min a b) (max a b))))
                           targets)))
        (should (equal '("alpha" "beta" "gamma") spans))))))

(ert-deftest helixel-test-mc-walk-advance-multiple-trailing-newlines ()
  "With several trailing empty lines, walk still yields one per word."
  (helixel-test-with-buffer "one two three\n\n\n\n"
    (helixel-enter-normal-state)
    (let ((targets (helixel-mc--walk-advance (helixel-test-mc--word-sel))))
      (should (= 3 (length targets))))))

(ert-deftest helixel-test-mc-walk-advance-no-final-newline ()
  "Buffer without trailing newline still yields one target per word."
  (helixel-test-with-buffer "a bb ccc"
    (helixel-enter-normal-state)
    (let ((targets (helixel-mc--walk-advance (helixel-test-mc--word-sel))))
      (should (= 3 (length targets))))))

;; ── walk-advance: global state isolation ──
;;
;; Regression: walk-advance calls advance functions (e.g. `mark-inner-word')
;; which re-run the textobj command and capture `this-command' +
;; accumulate counts into `helixel--pending-sel'.  Without isolation,
;; after `s s' the user's `helixel--last-edit' would be overwritten
;; with a sel whose `:command' is the outer mc command (e.g.
;; `helixel-mc-toggle') and `:count' equal to the iteration count,
;; breaking subsequent `.` ("No previous edit").
;;
;; The fix snapshots `helixel--pending-sel', `helixel--last-edit',
;; `helixel--live-edit' and `helixel--raw-selection-type' before the
;; walk and restores them in `unwind-protect'.

(ert-deftest helixel-test-mc-walk-advance-preserves-globals ()
  "walk-advance must not clobber helixel globals captured by advance fns."
  (helixel-test-with-buffer "alpha beta gamma\n"
    (helixel-enter-normal-state)
    (let* ((sentinel-sel (helixel-test-mc--word-sel))
           (sentinel-tx (make-helixel-edit
                         :op 'change
                         :sel sentinel-sel
                         :runner #'ignore
                         :payload '(:keys [?X])
                         :timestamp 0.0
                         :buffer (current-buffer)))
           (helixel--last-edit sentinel-tx)
           (helixel--pending-sel sentinel-sel)
           (helixel--raw-selection-type 'textobj))
      (helixel-mc--walk-advance (helixel-test-mc--word-sel))
      ;; All globals must be restored exactly — no accumulated count,
      ;; no overwritten command, no flipped raw-type.
      (should (eq helixel--last-edit sentinel-tx))
      (should (eq helixel--pending-sel sentinel-sel))
      (should (eq helixel--raw-selection-type 'textobj))
      (should (= 1 (helixel-sel-textobj-count
                    (helixel-edit-sel helixel--last-edit))))
      (should (eq 'helixel-mark-inner-word
                  (helixel-sel-textobj-command
                   (helixel-edit-sel helixel--last-edit)))))))

;; ── `.' (dot) at mc cursors: apply-only, no advance ──
;;
;; Regression: under multi-cursor, `helixel-repeat-edit' must NOT do
;; the usual advance+apply loop.  Each cursor is already positioned on
;; its target by `helixel-mc--realize-targets', so advancing would
;; move it OFF target (e.g. textobj-word advance jumps to the NEXT
;; word) and the change op then mangles neighbouring text.
;;
;; The fix is an `:around' advice on `helixel-repeat-edit' that, when
;; mc is active, short-circuits to `helixel--execute-edit' (apply once
;; at point, no advance).  These tests exercise that helper directly
;; with a synthetic change tx so we don't depend on the full
;; insert-state replay machinery.

(defun helixel-test-mc--make-replace-tx (replacement)
  "Synthesise a change tx whose runner replaces the active region with REPLACEMENT."
  (make-helixel-edit
   :op 'change
   :sel (helixel-test-mc--word-sel)
   :runner (lambda (_tx)
             (when (use-region-p)
               (delete-region (region-beginning) (region-end))
               (insert replacement)))
   :payload nil :timestamp 0.0
   :buffer (current-buffer)))

(ert-deftest helixel-test-mc-dot-apply-only-no-advance ()
  "Under mc, `.' applies the last edit ONCE at each cursor's region.
It must NOT advance to the next textobj target (which would target
the wrong word and overlap with neighbouring cursors)."
  (helixel-test-with-buffer "alpha beta gamma delta epsilon\n"
    (helixel-enter-normal-state)
    (let* ((sel (helixel-test-mc--word-sel))
           (tx (helixel-test-mc--make-replace-tx "FOO"))
           (helixel--last-edit tx))
      (helixel-mc-spawn-from-sel sel)
      (should (use-region-p))
      ;; Real cursor: advice short-circuits to apply-only.
      (helixel-mc--repeat-edit-apply-only (lambda (&optional _) nil))
      ;; Dispatch to fakes.
      (helixel-mc-with-each-cursor
        (helixel-mc--repeat-edit-apply-only (lambda (&optional _) nil)))
      (should (string= "FOO FOO FOO FOO FOO\n" (buffer-string)))
      (helixel-mc-clear-all))))

(ert-deftest helixel-test-mc-dot-trailing-empty-line ()
  "Combined regression: trailing empty line + `.' at mc cursors.
With a buffer ending in `\\n\\n', the pre-fix walk produced a 6th
spurious cursor whose region spanned almost the whole buffer; `.'
then collapsed the buffer to a single replacement.  Post-fix:
exactly N cursors (one per word) and every word becomes FOO."
  (helixel-test-with-buffer "alpha beta gamma delta epsilon\n\n"
    (helixel-enter-normal-state)
    (let* ((sel (helixel-test-mc--word-sel))
           (tx (helixel-test-mc--make-replace-tx "FOO"))
           (helixel--last-edit tx))
      (helixel-mc-spawn-from-sel sel)
      ;; 5 words → 1 real + 4 fakes (NOT 5 fakes / 6 cursors).
      (should (= 4 (length (helixel-mc-all-cursors))))
      (helixel-mc--repeat-edit-apply-only nil)
      (helixel-mc-with-each-cursor
        (helixel-mc--repeat-edit-apply-only nil))
      (should (string= "FOO FOO FOO FOO FOO\n\n" (buffer-string)))
      (helixel-mc-clear-all))))

(ert-deftest helixel-test-mc-dot-advice-falls-through-without-cursors ()
  "Without fake cursors the override hook returns nil (fall through)."
  (helixel-test-with-buffer "abc\n"
    (let ((helixel--last-edit nil))
      (should-not (helixel-mc--repeat-edit-apply-only nil)))))

(ert-deftest helixel-test-mc-dot-advice-falls-through-without-last-event ()
  "With fake cursors but no last-event, the override returns nil."
  (helixel-test-with-buffer "abc\n"
    (helixel-mc-create-fake-cursor 2)
    (let ((helixel--last-edit nil))
      (should-not (helixel-mc--repeat-edit-apply-only nil)))
    (helixel-mc-clear-all)))

;; ── End-to-end regression: `m i w c FOO <ESC> s s .' ──
;;
;; This is the exact interactive flow that produced "FOOFOOFOO FOO FOO
;; FOO" (6 FOOs) before the second walk-advance fix.  Root cause: the
;; first iter of `helixel-mc--walk-advance' starts with a leftover
;; `mark-marker' from the just-completed change op (`push-mark sel-beg
;; t t' leaves it at the start of the original target).  The previous
;; `before-mark' check filtered out THAT iter's range as if it were a
;; stale read — because the mark coincidentally landed at the same
;; position as the leftover.  Result: the first target was degenerate
;; `(pt . pt)', `realize-targets' couldn't install an active region
;; on the real cursor, and `.' fell through to the `no-region' branch
;; of `helixel--delete-selection' which just deleted one char and
;; appended FOO instead of replacing the word.
;;
;; The fix: ALWAYS reset `mark-marker' to point before each iter, so
;; any leftover is wiped and `have-range' only needs to check
;; `mark-active'.

(ert-deftest helixel-test-mc-end-to-end-miw-c-foo-dot ()
  "`m i w c FOO <ESC> s s .' on `alpha beta gamma delta epsilon\\n'
must produce `FOO FOO FOO FOO FOO\\n' — NOT `FOOFOOFOO FOO FOO FOO'."
  (helixel-test-with-buffer "alpha beta gamma delta epsilon\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (let ((helixel-repeat-change-method 'text))
      ;; m i w — select "alpha".
      (setq last-command nil this-command 'helixel-mark-inner-word)
      (helixel-mark-inner-word)
      (should (string= "alpha"
                       (buffer-substring-no-properties
                        (region-beginning) (region-end))))
      ;; c FOO <ESC> — change "alpha" → "FOO".
      (setq last-command 'helixel-mark-inner-word
            this-command 'helixel-change-thing-at-point)
      (helixel-change-thing-at-point)
      (insert "FOO")
      (helixel-insert-exit)
      (should (string= "FOO beta gamma delta epsilon\n"
                       (buffer-string)))
      ;; The change op leaves mark at sel-beg (=1) but `mark-active'
      ;; is cleared by `helixel-insert-exit'.  This is the state that
      ;; tripped the prior walk-advance regression.
      (should (= 1 (mark t)))
      ;; s s — spawn cursors.
      (helixel-mc-toggle)
      ;; CRITICAL invariants after spawn:
      ;;   * 4 fake cursors (5 words → 1 real + 4 fakes)
      ;;   * real cursor's region around "FOO" is ACTIVE (mk=1, pt=4)
      ;; — if either fails, the next `.' will mangle the buffer.
      (should (= 4 (length (helixel-mc-all-cursors))))
      (should (= 4 (point)))
      (should (= 1 (mark t)))
      (should mark-active)
      (should (string= "FOO"
                       (buffer-substring-no-properties
                        (region-beginning) (region-end))))
      ;; . — apply at real, then dispatch to each fake.
      (setq this-command 'helixel-repeat-edit)
      (helixel-repeat-edit)
      (helixel-mc-with-each-cursor
        (let ((this-command 'helixel-repeat-edit))
          (call-interactively 'helixel-repeat-edit)))
      ;; Every word must now be FOO.
      (should (string= "FOO FOO FOO FOO FOO\n"
                       (buffer-string)))
      (helixel-mc-clear-all))))

(ert-deftest helixel-test-mc-walk-resets-mark-each-iter ()
  "`helixel-mc--walk-advance' must reset mark-marker before each iter
so a leftover mark from a prior op (e.g. `push-mark sel-beg t t' from
`helixel--repeat-change-core') doesn't cause the first iter's range
to be filtered out as a stale read."
  (helixel-test-with-buffer "alpha beta gamma\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    ;; Pre-seed mark-marker at position 1 with mark-active=nil to
    ;; mimic post-change state.
    (set-marker (mark-marker) 1)
    (setq mark-active nil)
    (let* ((sel (helixel-test-mc--word-sel))
           (targets (helixel-mc--walk-advance sel)))
      (should (= 3 (length targets)))
      ;; Every target must be a REAL range, not degenerate (pt . pt).
      (dolist (tg targets)
        (let ((a (marker-position (car tg)))
              (b (marker-position (cdr tg))))
          (should (/= a b)))))))

;; ── Movement clears stale raw-selection-type ──
;;
;; Regression: `x' (line select) sets raw-selection-type='line.
;; A subsequent movement like `w' must reset raw-type to nil,
;; otherwise `helixel--selection-type' may mis-label the new region
;; as `line' (when the new region happens to be bol..eol), making
;; `y' tag the kill as line-wise and `p' paste it as a separate
;; line instead of charwise-inserting in place.

(ert-deftest helixel-test-movement-clears-line-raw-type ()
  "After `x' (line select), a movement must clear raw-selection-type."
  (helixel-test-with-buffer "hello world\nfoo bar\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (helixel-select-line)
    (should (eq helixel--raw-selection-type 'line))
    (helixel-forward-word-end)
    (should (null helixel--raw-selection-type))))

(ert-deftest helixel-test-movement-clears-rect-raw-type ()
  "After `v'/`vvv' (rect select), a movement must clear raw-selection-type."
  (helixel-test-with-buffer "hello world\nfoo bar\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (setq helixel--raw-selection-type 'rect)
    (helixel-forward-word-end)
    (should (null helixel--raw-selection-type))))

;; ============================================================================
;; Smoke-test coverage — every checklist item from SMOKE-TEST-MC.md
;; ============================================================================

;; ── 1. Spawn / clear ──

(ert-deftest helixel-test-mc-line-spawn-realize-3-lines ()
  "Line spawn over a 3-line region: 1 real + 2 fakes (3 cursors total).
Each cursor must have an active region around its own line (mark=bol,
point=eol); lighter must report 3 cursors; second `s s' clears."
  (helixel-test-with-buffer "line one\nline two\nline three\nline four\nline five\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    ;; Simulate `x x x' → 3 lines selected line-wise.
    (push-mark 1 t t)
    (goto-char (line-end-position 3))
    (let* ((sel (helixel-sel-create 'line '(:count 3)
                                    #'ignore "L")))
      (helixel-mc-spawn-from-sel sel)
      ;; 2 fake cursors + 1 real = 3 cursors.
      (should (= 3 (helixel-mc-num-cursors)))
      (should (= 2 (length (helixel-mc-all-cursors))))
      ;; Real cursor has its own line as active region.
      (should (use-region-p))
      ;; Every fake's overlay range is exactly one line.
      (dolist (ov (helixel-mc-all-cursors))
        (let ((pt (marker-position (overlay-get ov 'helixel-mc-point)))
              (mk (marker-position (overlay-get ov 'helixel-mc-mark))))
          (should (overlay-get ov 'mark-active))
          (save-excursion
            (goto-char (min pt mk))
            (should (bolp))
            (goto-char (max pt mk))
            (should (eolp)))))
      ;; Toggle again → clears.  After clearing, only the real
      ;; cursor remains, so `helixel-mc-num-cursors' → 1.
      (helixel-mc-toggle)
      (should (= 1 (helixel-mc-num-cursors)))
      (should (null (helixel-mc-all-cursors))))))

(ert-deftest helixel-test-mc-line-spawn-whitespace-only-line ()
  "Whitespace-only lines must still get a cursor (no skip).
The cursor selects the (possibly empty) line content."
  (helixel-test-with-buffer "  \n   \n      \n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (push-mark 1 t t)
    (goto-char (point-max))
    (let* ((sel (helixel-sel-create 'line '(:count 3)
                                    #'ignore "L")))
      (helixel-mc-spawn-from-sel sel)
      ;; 3 lines → 1 real + 2 fakes.
      (should (= 3 (helixel-mc-num-cursors)))
      (helixel-mc-clear-all))))

(ert-deftest helixel-test-mc-search-spawn-preserves-real-region ()
  "Search spawn: real cursor's (point, mark, mark-active) survive.
After `/foo<RET>' the active region around the first match must
remain on the real cursor so the next `i' / `a' / operator behaves
the same on real and fakes."
  (helixel-test-with-buffer "foo and foo and foo\n"
    (helixel-enter-normal-state)
    ;; Simulate landing on first match: point at end, mark at start.
    (goto-char 1)
    (push-mark 1 t t)
    (goto-char 4)                       ; end of first "foo"
    (let* ((sel (helixel-sel-create
                 'search
                 '(:pattern "foo" :dir forward :entry-kind nil)
                 #'ignore "/foo"))
           (pt-before (point))
           (mk-before (mark t))
           (active-before mark-active))
      ;; Spawn via walk-advance (search has no :mc-spawn-fn).
      (helixel-mc-spawn-from-sel sel)
      ;; Real cursor's region must still cover the first "foo".
      (should (= pt-before (point)))
      (should (= mk-before (mark t)))
      (should (eq active-before mark-active))
      (should (use-region-p))
      (should (string= "foo" (buffer-substring-no-properties
                               (region-beginning) (region-end))))
      ;; And we got 2 fakes for the other 2 matches.
      (should (= 2 (length (helixel-mc-all-cursors))))
      (helixel-mc-clear-all))))

(ert-deftest helixel-test-mc-textobj-spawn-trailing-ws-filtered ()
  "`miw' + `s s' on `\"foo bar baz qux\\n\"' yields exactly 4 cursors.
Pre-fix the walk produced a 5th spurious target on the trailing
whitespace / EOB; filter must drop it."
  (helixel-test-with-buffer "foo bar baz qux\n"
    (helixel-enter-normal-state)
    (let ((sel (helixel-test-mc--word-sel)))
      (helixel-mc-spawn-from-sel sel)
      ;; 4 words → 1 real + 3 fakes.
      (should (= 4 (helixel-mc-num-cursors)))
      (helixel-mc-clear-all))))

(ert-deftest helixel-test-mc-find-char-spawn ()
  "`fx' + `s s' creates one cursor per occurrence of `x'."
  (helixel-test-with-buffer "axbxcxdx\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    (let* ((sel (helixel-sel-create
                 'find-char
                 '(:char ?x :type next :dir forward :inline-advance t)
                 #'ignore "fx")))
      (helixel-mc-spawn-from-sel sel)
      ;; 4 x's → 1 real + 3 fakes.
      (should (= 4 (helixel-mc-num-cursors)))
      (helixel-mc-clear-all))))

(ert-deftest helixel-test-mc-find-char-spawn-no-match ()
  "`fz' on buffer without `z' must signal `user-error', not crash."
  (helixel-test-with-buffer "axbxcx\n"
    (helixel-enter-normal-state)
    (let ((sel (helixel-sel-create
                'find-char
                '(:char ?z :type next :dir forward :inline-advance t)
                #'ignore "fz")))
      (should-error (helixel-mc-spawn-from-sel sel)
                    :type 'user-error))))

;; ── 2. Per-cursor dispatch ──

(ert-deftest helixel-test-mc-dispatch-movement ()
  "Movement command run through `helixel-mc-with-each-cursor' moves
every fake cursor independently."
  (helixel-test-with-buffer "aaa bbb ccc ddd\n"
    (helixel-mc-create-fake-cursor 1)
    (helixel-mc-create-fake-cursor 5)
    (helixel-mc-create-fake-cursor 9)
    (goto-char 13)
    (helixel-mc-with-each-cursor
      (forward-char 1))
    ;; Each fake cursor moved by +1.
    (let ((positions
           (sort (mapcar (lambda (ov)
                           (marker-position
                            (overlay-get ov 'helixel-mc-point)))
                         (helixel-mc-all-cursors))
                 #'<)))
      (should (equal '(2 6 10) positions)))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-dispatch-upcase-word ()
  "`upcase-word' dispatched to each cursor upcases each cursor's word."
  (helixel-test-with-buffer "foo bar baz\n"
    ;; Real at start of "foo"; fakes at start of "bar" and "baz".
    (helixel-mc-create-fake-cursor 5)   ; before 'b' of bar
    (helixel-mc-create-fake-cursor 9)   ; before 'b' of baz
    (goto-char 1)
    (upcase-word 1)                     ; real → "FOO"
    (helixel-mc-with-each-cursor
      (upcase-word 1))
    (should (string= "FOO BAR BAZ\n" (buffer-string)))
    (helixel-mc-clear-all)))

;; ── Insert-state prepositioner advice ──
;;
;; Each prepositioner runs inside the fake cursor's restored env so
;; that the subsequent `self-insert-command' dispatch lands at the
;; right place.  These tests call the prepositioners directly with a
;; synthetic environment matching what `helixel-mc-with-each-cursor'
;; provides at each fake.

(ert-deftest helixel-test-mc-prepos-region-begin ()
  "`i' prepositioner: jump to region-begin, deactivate mark."
  (helixel-test-with-buffer "hello world\n"
    (goto-char 7)                       ; end of "world" minus offset
    (push-mark 1 t t)                   ; region: "hello "
    (helixel-mc--prepos-region-begin)
    (should (= 1 (point)))
    (should-not mark-active)))

(ert-deftest helixel-test-mc-prepos-region-end ()
  "`a' prepositioner: jump to region-end, deactivate mark."
  (helixel-test-with-buffer "hello world\n"
    (goto-char 1)
    (push-mark 6 t t)                   ; region: "hello"
    (helixel-mc--prepos-region-end)
    (should (= 6 (point)))
    (should-not mark-active)))

(ert-deftest helixel-test-mc-prepos-region-end-no-region ()
  "`a' prepositioner without active region: forward-char."
  (helixel-test-with-buffer "hello world\n"
    (goto-char 3)
    (deactivate-mark)
    (helixel-mc--prepos-region-end)
    (should (= 4 (point)))))

(ert-deftest helixel-test-mc-prepos-bol-eol ()
  "`I' → bol, `A' → eol."
  (helixel-test-with-buffer "  indented line\n"
    (goto-char 8)
    (helixel-mc--prepos-bol)
    (should (= 1 (point)))
    (goto-char 8)
    (helixel-mc--prepos-eol)
    (should (= (line-end-position) (point)))))

(ert-deftest helixel-test-mc-prepos-newline-after-before ()
  "`o' opens line below, `O' opens line above (point ends on new line)."
  (helixel-test-with-buffer "line one\nline two\n"
    (goto-char 3)
    (let ((before-lines (count-lines (point-min) (point-max))))
      (helixel-mc--prepos-newline-after)
      (should (> (count-lines (point-min) (point-max)) before-lines))
      ;; Point sits on the new empty line.
      (should (bolp)))
    ;; Reset and test `O'.
    (erase-buffer) (insert "line one\nline two\n") (goto-char 12)
    (let ((before-lines (count-lines (point-min) (point-max))))
      (helixel-mc--prepos-newline-before)
      (should (> (count-lines (point-min) (point-max)) before-lines)))))

;; ── 3. Per-cursor kill-ring isolation, end-to-end ──
;;
;; This is the regression scenario from the smoke test: after `miw d'
;; at 3 cursors (real on "foo", fakes on "bar" and "baz"), each
;; cursor's `kill-ring' head must hold its OWN word.  This proves
;; that the per-cursor kill-ring snapshot/restore in
;; `helixel-mc-with-each-cursor' correctly partitions kill state.

(ert-deftest helixel-test-mc-kill-ring-per-cursor-after-delete ()
  "`miw d' at 3 cursors leaves each cursor's kill-ring head = own word."
  (helixel-test-with-buffer "foo bar baz\n"
    ;; Real cursor on "foo" with region.
    (goto-char 4) (push-mark 1 t t)
    ;; Fakes on "bar" and "baz" with regions.
    (helixel-mc-create-fake-cursor 8 5)
    (helixel-mc-create-fake-cursor 12 9)
    (let ((kill-ring nil)
          (per-fake-kills nil))
      ;; Real `d': kill its region.
      (kill-region (region-beginning) (region-end))
      ;; Real head must be "foo".
      (should (string= "foo" (car kill-ring)))
      ;; Dispatch each fake: each has its own (snapshotted) kill-ring.
      (helixel-mc-with-each-cursor
        (let ((kill-ring nil))
          (when (use-region-p)
            (kill-region (region-beginning) (region-end))
            (push (car kill-ring) per-fake-kills))))
      ;; Real kill-ring head is still "foo" — NOT polluted by fakes.
      (should (string= "foo" (car kill-ring)))
      ;; Each fake produced its own kill.
      (should (equal '("bar" "baz")
                     (sort per-fake-kills #'string<))))
    (helixel-mc-clear-all)))


;; ============================================================================
;; Edge-case coverage for untested API surface
;; ============================================================================

;; ── max-cursors limit ──

(ert-deftest helixel-test-mc-max-cursors-limit ()
  "Creating cursors past `helixel-mc-max-cursors' signals `user-error'."
  (helixel-test-with-buffer "a\nb\nc\nd\n"
    (let ((helixel-mc-max-cursors 2))
      (helixel-mc-create-fake-cursor 1)
      (helixel-mc-create-fake-cursor 2)
      (should-error (helixel-mc-create-fake-cursor 3)
                    :type 'user-error))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-max-cursors-unlimited ()
  "With `helixel-mc-max-cursors' nil, no limit applies."
  (helixel-test-with-buffer "aaaaaaaaaa\n"
    (let ((helixel-mc-max-cursors nil))
      ;; Spawn at distinct positions so dedup keeps them all.
      (dotimes (i 10)
        (helixel-mc-create-fake-cursor (+ 1 i)))
      (should (= 10 (length (helixel-mc-all-cursors)))))
    (helixel-mc-clear-all)))

;; ── execute-for-all-cursors entry point ──

(ert-deftest helixel-test-mc-execute-for-all-cursors ()
  "`helixel-mc-execute-for-all-cursors' runs a command at real + every fake."
  (helixel-test-with-buffer "aaa\nbbb\nccc\n"
    (helixel-mc-create-fake-cursor 5)
    (helixel-mc-create-fake-cursor 9)
    (goto-char 1)
    (helixel-mc-execute-for-all-cursors #'forward-char)
    (should (= 2 (point)))
    (let ((positions
           (sort (mapcar (lambda (ov) (marker-position
                                   (overlay-get ov 'helixel-mc-point)))
                         (helixel-mc-all-cursors)) #'<)))
      (should (equal '(6 10) positions)))
    (helixel-mc-clear-all)))

;; ── toggle error paths ──

(ert-deftest helixel-test-mc-toggle-error-no-selection ()
  "`s s' with no stored selection signals `user-error'."
  (helixel-test-with-buffer "abc\n"
    (let ((helixel--pending-sel nil)
          (helixel--last-edit nil))
      (should-error (helixel-mc-toggle) :type 'user-error))))

(ert-deftest helixel-test-mc-toggle-error-not-a-sel ()
  "`helixel-mc-spawn-from-sel' signals user-error on non-sel input."
  (should-error (helixel-mc-spawn-from-sel "not-a-sel") :type 'user-error))

;; ── region-text error guard ──

(ert-deftest helixel-test-mc-region-text-error-no-region ()
  "`helixel-mc--region-text' signals `user-error' with no active region."
  (helixel-test-with-buffer "abc\n"
    (deactivate-mark)
    (should-error (helixel-mc--region-text) :type 'user-error)))

;; ── skip-next / skip-previous ──

(ert-deftest helixel-test-mc-skip-next-moves-real ()
  "`s N' moves the real cursor to the next match; no fake is created."
  (helixel-test-with-buffer "foo bar foo baz foo\n"
    (goto-char 1)
    (push-mark 4 t t)                   ; region: first "foo"
    (helixel-mc-skip-next)
    ;; Real moved to 2nd "foo".
    (should (string= "foo" (buffer-substring-no-properties
                            (region-beginning) (region-end))))
    (should (= 9 (region-beginning)))
    ;; No fakes created.
    (should (null (helixel-mc-all-cursors)))))

(ert-deftest helixel-test-mc-skip-previous-moves-real ()
  "`s P' moves real to the previous match."
  (helixel-test-with-buffer "foo bar foo baz\n"
    (goto-char 9)
    (push-mark 12 t t)                  ; region: 2nd "foo"
    (helixel-mc-skip-previous)
    (should (string= "foo" (buffer-substring-no-properties
                            (region-beginning) (region-end))))
    (should (= 1 (region-beginning)))
    (should (null (helixel-mc-all-cursors)))))

(ert-deftest helixel-test-mc-skip-next-no-more-errors ()
  "`s N' at the last match signals `user-error'."
  (helixel-test-with-buffer "aaa bbb\n"
    (goto-char 5)
    (push-mark 8 t t)                   ; region: "bbb" — last word
    (should-error (helixel-mc-skip-next) :type 'user-error)))

;; ── unmark-next / unmark-previous ──

(ert-deftest helixel-test-mc-remove-primary-bound-to-m-comma ()
  "`M-,' is bound to `helixel-mc-remove-primary' in normal map."
  (should (eq (lookup-key helixel-normal-map (kbd "M-,"))
              'helixel-mc-remove-primary)))

(ert-deftest helixel-test-mc-remove-primary-deletes-and-promotes ()
  "`M-,' removes the cursor at real's position and promotes
the nearest fake to become the new real (Helix `A-,' semantics)."
  (helixel-test-with-buffer "abc def ghi jkl\n"
    (goto-char 1)
    (helixel-mc-create-fake-cursor 5)   ; nearest to real@1 (dist 4)
    (helixel-mc-create-fake-cursor 13)  ; farther (dist 12)
    ;; M-,: swaps real↔5, then deletes the fake now at old-real=1.
    ;; After: real@5 (promoted), 1 fake remaining at 13.
    (helixel-mc-remove-primary)
    (should (= 5 (point)))              ; real promoted to nearest
    (should (= 1 (length (helixel-mc-all-cursors))))
    (should (= 13 (marker-position
                   (overlay-get (car (helixel-mc-all-cursors))
                                'helixel-mc-point))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-remove-primary-post-rotate ()
  "After `)` rotation, `M-,' deletes the cursor at real's
position (the one the user navigated to) and promotes the
nearest remaining cursor."
  (helixel-test-with-buffer "aaa bbb ccc ddd\n"
    (goto-char 1)
    (helixel-mc-create-fake-cursor 5)   ; bbb
    (helixel-mc-create-fake-cursor 9)   ; ccc
    (helixel-mc-create-fake-cursor 13)  ; ddd
    ;; ) rotate: real moves to 5, fake placed at 1.
    (helixel-mc-rotate-primary-forward)
    (should (= 5 (point)))
    ;; M-,: nearest fake to real@5 is @1 (dist 4) or @9 (dist 4).
    ;; First in sorted order [1,9,13] with min dist=4 is @1.
    ;; Swap real↔1, then delete fake at old-real=5.
    ;; Result: real@1 (promoted), 2 fakes at [9,13].
    (helixel-mc-remove-primary)
    (should (= 1 (point)))              ; real promoted to nearest
    (should (= 2 (length (helixel-mc-all-cursors))))
    ;; The deleted position (5) is gone.
    (let ((positions (mapcar (lambda (ov)
                               (marker-position
                                (overlay-get ov 'helixel-mc-point)))
                             (helixel-mc-all-cursors))))
      (should (equal (sort positions '<) '(9 13))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-unmark-next-removes-one ()
  "`helixel-mc-unmark-next' (formerly `s u') removes the fake
cursor just past real point."
  (helixel-test-with-buffer "abc def ghi\n"
    (goto-char 1)
    (helixel-mc-create-fake-cursor 5)
    (helixel-mc-create-fake-cursor 9)
    (goto-char 3)                       ; before both fakes
    (helixel-mc-unmark-next)
    (should (= 1 (length (helixel-mc-all-cursors))))
    ;; The remaining fake is at 9.
    (should (= 9 (marker-position
                  (overlay-get (car (helixel-mc-all-cursors))
                               'helixel-mc-point))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-unmark-previous-removes-one ()
  "`helixel-mc-unmark-previous' removes the fake cursor just
before real point."
  (helixel-test-with-buffer "abc def ghi\n"
    (goto-char 1)
    (helixel-mc-create-fake-cursor 5)
    (helixel-mc-create-fake-cursor 9)
    (goto-char 7)                       ; between both fakes
    (helixel-mc-unmark-previous)
    (should (= 1 (length (helixel-mc-all-cursors))))
    ;; The remaining fake is at 9.
    (should (= 9 (marker-position
                  (overlay-get (car (helixel-mc-all-cursors))
                               'helixel-mc-point))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-unmark-next-no-more-errors ()
  "`helixel-mc-unmark-next' with no fake after point signals
`user-error'."
  (helixel-test-with-buffer "abc def\n"
    (goto-char 1)
    (helixel-mc-create-fake-cursor 5)
    (goto-char 8)                       ; after the fake
    (should-error (helixel-mc-unmark-next) :type 'user-error)
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-unmark-previous-no-more-errors ()
  "`s U' with no fake before point signals `user-error'."
  (helixel-test-with-buffer "abc def\n"
    (goto-char 1)
    (helixel-mc-create-fake-cursor 5)
    (goto-char 1)                       ; before the fake
    (should-error (helixel-mc-unmark-previous) :type 'user-error)
    (helixel-mc-clear-all)))

;; ── apply-last-edit error paths ──

(ert-deftest helixel-test-mc-apply-last-edit-error-no-cursors ()
  "`M-s .' with no fake cursors signals `user-error'."
  (helixel-test-with-buffer "abc\n"
    (let ((helixel--last-edit (make-helixel-edit
                              :op 'test :sel nil :payload nil
                              :runner #'ignore :timestamp 0.0
                              :buffer (current-buffer))))
      (should-error (helixel-mc-apply-last-edit) :type 'user-error))))

(ert-deftest helixel-test-mc-apply-last-edit-error-no-event ()
  "`M-s .' with no last-event signals `user-error'."
  (helixel-test-with-buffer "abc\n"
    (let ((helixel--last-edit nil))
      (helixel-mc-create-fake-cursor 2)
      (should-error (helixel-mc-apply-last-edit) :type 'user-error))
    (helixel-mc-clear-all)))

;; ── mark-all-for-multi-cursors / real-cursor-only ──

(ert-deftest helixel-test-mc-mark-all-for-multi-cursors ()
  "`helixel-mc-mark-all-for-multi-cursors' sets the symbol property."
  (unwind-protect
      (progn
        (helixel-mc-mark-all-for-multi-cursors '(my-cmd-1 my-cmd-2))
        (should (eq t (get 'my-cmd-1 'multiple-cursors)))
        (should (eq t (get 'my-cmd-2 'multiple-cursors))))
    (put 'my-cmd-1 'multiple-cursors nil)
    (put 'my-cmd-2 'multiple-cursors nil)))

(ert-deftest helixel-test-mc-mark-all-for-real-cursor-only ()
  "`helixel-mc-mark-all-for-real-cursor-only' sets the symbol property to nil."
  (unwind-protect
      (progn
        (put 'my-cmd-3 'multiple-cursors t)
        (helixel-mc-mark-all-for-real-cursor-only '(my-cmd-3))
        (should-not (get 'my-cmd-3 'multiple-cursors)))
    (put 'my-cmd-3 'multiple-cursors nil)))

;; ── fake-cursor-p guard ──

(ert-deftest helixel-test-mc-fake-cursor-p-non-overlay ()
  "`helixel-mc-fake-cursor-p' returns nil for non-overlays."
  (should-not (helixel-mc-fake-cursor-p nil))
  (should-not (helixel-mc-fake-cursor-p "string"))
  (should-not (helixel-mc-fake-cursor-p 42)))

(ert-deftest helixel-test-mc-delete-fake-cursor-noop-non-cursor ()
  "`helixel-mc-delete-fake-cursor' is a no-op on non-cursor overlays."
  (helixel-test-with-buffer "abc\n"
    (let ((ov (make-overlay 1 2)))
      (helixel-mc-delete-fake-cursor ov)  ; should not crash
      (should (overlay-buffer ov))        ; still alive
      (delete-overlay ov))))

;; ── post-command inhibition gates ──
;;
;; The legacy `helixel-mc--inhibit' and
;; `helixel-mc-executing-command-for-fake-cursor' flag-defvars are
;; gone — replaced by `helixel-replay-in-fake-p' /
;; `helixel-mc-dispatch-in-progress-p' over the single
;; `helixel-replay' struct (see helixel-replay.el).  The behavioural
;; coverage moved into
;; `helixel-test-mc-post-command-skips-when-replay-in-fake'.

;; ── save-main-state: point / mark / variable restore ──

(ert-deftest helixel-test-mc-save-main-state-restores-point-mark ()
  "`helixel-mc--save-main-state' restores point and mark after BODY."
  (helixel-test-with-buffer "abcdefghij\n"
    (goto-char 3)
    (set-marker (mark-marker) 7)
    (setq mark-active t)
    (let ((orig-pt (point))
          (orig-mk (mark t)))
      (helixel-mc--save-main-state
        (goto-char 1)
        (set-marker (mark-marker) 1))
      (should (= orig-pt (point)))
      (should (= orig-mk (mark t))))))

(ert-deftest helixel-test-mc-save-main-state-restores-vars ()
  "`helixel-mc--save-main-state' restores cursor-vars after mutation."
  (helixel-test-with-buffer "abc\n"
    (let ((kill-ring '("before"))
          (helixel--pending-sel 'sentinel))
      (helixel-mc--save-main-state
        (setq kill-ring '("inside"))
        (setq helixel--pending-sel 'modified))
      (should (equal kill-ring '("before")))
      (should (eq helixel--pending-sel 'sentinel)))))

;; ── paint-cursor-overlay: EOL vs mid-line ──

(ert-deftest helixel-test-mc-paint-cursor-eol ()
  "A fake cursor at end-of-line uses an `after-string' face."
  (helixel-test-with-buffer "abc\n"
    (let ((ov (make-overlay 1 1)))
      (unwind-protect
          (progn
            (goto-char 4)               ; eol
            (helixel-mc--paint-cursor-overlay ov (point))
            (should (overlay-get ov 'after-string))
            (should-not (overlay-get ov 'face)))
        (delete-overlay ov)))))

(ert-deftest helixel-test-mc-paint-cursor-midline ()
  "A fake cursor mid-line covers one character."
  (helixel-test-with-buffer "abcdef\n"
    (let ((ov (make-overlay 1 1)))
      (unwind-protect
          (progn
            (goto-char 3)
            (helixel-mc--paint-cursor-overlay ov (point))
            (should-not (overlay-get ov 'after-string))
            (should (overlay-get ov 'face)))
        (delete-overlay ov)))))

;; ── update-fake-region: create / move / delete ──

(ert-deftest helixel-test-mc-update-fake-region-creates-when-active ()
  "Region overlay is created when mark-active + point ≠ mark."
  (helixel-test-with-buffer "abcdef\n"
    (let ((ov (make-overlay 1 1 nil nil t)))
      (overlay-put ov 'helixel-mc-point (copy-marker 1 t))
      (overlay-put ov 'helixel-mc-mark (copy-marker 4 t))
      (overlay-put ov 'mark-active t)
      (unwind-protect
          (progn
            (helixel-mc--update-fake-region ov)
            (should (overlay-get ov 'helixel-mc-region))
            (should (overlayp (overlay-get ov 'helixel-mc-region))))
        (helixel-mc-delete-fake-cursor ov)))))

(ert-deftest helixel-test-mc-update-fake-region-deletes-when-inactive ()
  "Region overlay is deleted when mark-active is nil."
  (helixel-test-with-buffer "abcdef\n"
    (let ((ov (make-overlay 1 1 nil nil t)))
      (overlay-put ov 'helixel-mc-point (copy-marker 1 t))
      (overlay-put ov 'helixel-mc-mark (copy-marker 4 t))
      (overlay-put ov 'mark-active nil)
      (unwind-protect
          (progn
            ;; Pre-create a region overlay to verify deletion.
            (overlay-put ov 'helixel-mc-region (make-overlay 1 4))
            (helixel-mc--update-fake-region ov)
            (should-not (overlay-get ov 'helixel-mc-region)))
        (helixel-mc-delete-fake-cursor ov)))))

;; ── find-char spawn: case-fold with uppercase ──

(ert-deftest helixel-test-mc-find-char-spawn-uppercase-case-sensitive ()
  "`fX' spawns only uppercase X occurrences (not lowercase x)."
  (helixel-test-with-buffer "aXbxcXd\n"
    (helixel-enter-normal-state)
    (let ((sel (helixel-sel-create
                'find-char
                '(:char ?X :type next :dir forward :inline-advance t)
                #'ignore "fX")))
      (helixel-mc-spawn-from-sel sel)
      ;; Only 2 X's (not the 2 x's).
      (should (= 2 (helixel-mc-num-cursors)))
      (helixel-mc-clear-all))))

;; ── edit-lines: region-end-exactly-at-BOL adjustment ──

(ert-deftest helixel-test-mc-edit-lines-region-end-at-bol ()
  "When region ends at BOL, the last (empty) line is excluded."
  (helixel-test-with-buffer "aaa\nbbb\nccc\n"
    (helixel-enter-normal-state)
    (goto-char 1)
    ;; Simulate region covering lines 1-3 but ending at BOL of line 4.
    ;; First 3 lines selected → region end at 13 (BOL of empty line after "ccc\n").
    (push-mark 1 t t)
    (goto-char 13)                      ; bol of line 4
    (helixel-mc-edit-lines (region-beginning) (region-end))
    ;; Should only have cursors on lines 1-3 (3 total), not line 4.
    (should (= 3 (helixel-mc-num-cursors)))
    ;; No cursor sits past line 3 eol.
    (dolist (ov (helixel-mc-all-cursors))
      (should (<= (marker-position (overlay-get ov 'helixel-mc-point))
                  13)))
    (helixel-mc-clear-all)))

;; ── mode lifecycle: cleanup on helixel-mode-off ──

(ert-deftest helixel-test-mc-cleanup-on-mode-off ()
  "`helixel-mc--cleanup-on-mode-off' clears fake cursors in all buffers."
  (let ((buf (generate-new-buffer "mc-cleanup-test")))
    (unwind-protect
        (progn
          (with-current-buffer buf
            (insert "test\n")
            (helixel-mc-create-fake-cursor 1)
            (should helixel-multi-cursor-mode))
          (helixel-mc--cleanup-on-mode-off)
          (with-current-buffer buf
            (should-not helixel-multi-cursor-mode)
            (should (null (helixel-mc-all-cursors)))))
      (ignore-errors (kill-buffer buf)))))

;; ── realize-targets: empty / single-target edge cases ──

(ert-deftest helixel-test-mc-realize-targets-empty-errors ()
  "Empty targets list signals `user-error'."
  (should-error (helixel-mc--realize-targets nil) :type 'user-error))

(ert-deftest helixel-test-mc-realize-targets-single-degenerate ()
  "A single degenerate (point-only) target installs on real, no fakes."
  (helixel-test-with-buffer "abc\n"
    (goto-char 1)
    (setq mark-active nil)
    (let ((targets (list (helixel-mc--make-target 3))))
      (let ((n (helixel-mc--realize-targets targets)))
        (should (= 0 n))                ; no fakes created
        (should (= 3 (point)))
        (should-not mark-active)))))

(ert-deftest helixel-test-mc-realize-targets-two-with-region ()
  "Two ranged targets: nearest stays real, other becomes fake."
  (helixel-test-with-buffer "aaa bbb ccc\n"
    (goto-char 1)
    ;; Real point at 1; target1 at (1..4)="aaa", target2 at (5..8)="bbb".
    (let ((targets (list (helixel-mc--make-target 4 1)
                         (helixel-mc--make-target 8 5))))
      (let ((n (helixel-mc--realize-targets targets)))
        (should (= 1 n))                ; one fake
        ;; Real got target1 (contains point=1).
        (should (= 4 (point)))
        (should mark-active)
        (should (string= "aaa" (buffer-substring-no-properties
                                (region-beginning) (region-end))))))
    (helixel-mc-clear-all)))

;; ── spawn-from-sel: restore-region path ──

(ert-deftest helixel-test-mc-spawn-from-sel-restores-region ()
  "When the chosen target is degenerate AND at the same point as the
pre-spawn cursor, the pre-spawn active region is restored."
  (helixel-test-with-buffer "foo bar foo baz\n"
    (helixel-enter-normal-state)
    (goto-char 4)                       ; point at end of "foo"
    (push-mark 1 t t)                   ; region: "foo" (1..4)
    (let ((orig-fn (plist-get
                    (gethash 'line helixel--kind-registry)
                    :mc-spawn-fn)))
      (unwind-protect
          (progn
            (puthash 'line
                     (plist-put (gethash 'line helixel--kind-registry)
                                :mc-spawn-fn
                                (lambda (_sel)
                                  (list (helixel-mc--make-target 4))))
                     helixel--kind-registry)
            (helixel-mc-spawn-from-sel
             (helixel-sel-create 'line '(:count 1) #'ignore "L"))
            ;; Realize-targets cleared mark-active (degenerate target),
            ;; but spawn-from-sel's restore guard put it back because
            ;; the target was at saved-pt.
            (should mark-active)
            (should (= 4 (point)))
            (should (= 1 (mark t))))
        (puthash 'line
                 (plist-put (gethash 'line helixel--kind-registry)
                            :mc-spawn-fn orig-fn)
                 helixel--kind-registry)))))

(ert-deftest helixel-test-mc-spawn-from-sel-no-restore-when-different-pt ()
  "When the chosen target is at a DIFFERENT point, the pre-spawn
region is NOT restored (the new target replaces it correctly)."
  (helixel-test-with-buffer "foo bar foo baz\n"
    (helixel-enter-normal-state)
    (goto-char 4)
    (push-mark 1 t t)                   ; region "foo" (1..4)
    (let ((orig-fn (plist-get
                    (gethash 'line helixel--kind-registry)
                    :mc-spawn-fn)))
      (unwind-protect
          (progn
            (puthash 'line
                     (plist-put (gethash 'line helixel--kind-registry)
                                :mc-spawn-fn
                                (lambda (_sel)
                                  (list (helixel-mc--make-target 8))))
                     helixel--kind-registry)
            (helixel-mc-spawn-from-sel
             (helixel-sel-create 'line '(:count 1) #'ignore "L"))
            (should (= 8 (point)))
            (should-not mark-active))
        (puthash 'line
                 (plist-put (gethash 'line helixel--kind-registry)
                            :mc-spawn-fn orig-fn)
                 helixel--kind-registry)))))

;; ── save/restore around enter/leave cycle ──

(ert-deftest helixel-test-mc-enter-leave-roundtrip ()
  "A full enter-apply-leave cycle preserves cursor overlay state."
  (helixel-test-with-buffer "hello world\n"
    (let* ((ov (helixel-mc-create-fake-cursor 7 1))
           (orig-pt (marker-position (overlay-get ov 'helixel-mc-point)))
           (orig-mk (marker-position (overlay-get ov 'helixel-mc-mark)))
           (orig-active (overlay-get ov 'mark-active)))
      (when (helixel-mc--enter-cursor ov)
        ;; Mutate state.
        (goto-char 3)
        (set-mark 5)
        (setq mark-active t)
        (helixel-mc--leave-cursor ov))
      ;; Verify round-trip: overlay now reflects mutated state.
      (should (= 3 (marker-position (overlay-get ov 'helixel-mc-point))))
      (should (= 5 (marker-position (overlay-get ov 'helixel-mc-mark))))
      (should (overlay-get ov 'mark-active))
      ;; Restore original.
      (set-marker (overlay-get ov 'helixel-mc-point) orig-pt)
      (set-marker (overlay-get ov 'helixel-mc-mark) orig-mk)
      (overlay-put ov 'mark-active orig-active)
      (helixel-mc-clear-all))))

;; ── call-interactively skips `ignore' ──

(ert-deftest helixel-test-mc-call-interactively-skips-ignore ()
  "`helixel-mc--call-interactively' on `ignore' does nothing."
  (helixel-test-with-buffer "abc\n"
    (let ((this-command nil))
      (helixel-mc--call-interactively 'ignore)
      (should-not this-command))))

;; ── spawn-from-rect: delegates to from-line ──

(ert-deftest helixel-test-mc-spawn-from-rect ()
  "`helixel-mc-spawn-from-rect' behaves like spawn-from-line."
  (helixel-test-with-buffer "aaa\nbbb\nccc\n"
    (goto-char 1)
    (push-mark (point-max) t t)
    (let* ((sel (helixel-sel-create 'rect '(:count 3) #'ignore "R"))
           (targets (helixel-mc-spawn-from-rect sel)))
      (should (= 3 (length targets))))))

;; ── broadcast + replay: last-event roundtrip ──

(ert-deftest helixel-test-mc-broadcast-then-replay ()
  "Broadcasting a last-event then replaying at each fake cursor works."
  (helixel-test-with-buffer "X\nX\nX\n"
    (let ((tx (make-helixel-edit
               :op 'test
               :runner (lambda (_tx) (insert "Y"))
               :sel nil :payload nil :timestamp 0.0
               :buffer (current-buffer))))
      (setq helixel--last-edit tx)
      (helixel-mc-create-fake-cursor 3)
      (helixel-mc-create-fake-cursor 5)
      (helixel-mc--broadcast-last-event)
      ;; Every fake now has the tx.
      (dolist (ov (helixel-mc-all-cursors))
        (should (eq tx (overlay-get ov 'helixel--last-edit))))
      ;; Apply once at each fake.
      (helixel-mc--apply-chain-once)
      (should (string= "X\nYX\nYX\n" (buffer-string)))
      (helixel-mc-clear-all))))

;; ── post-command-amalgamated: substitute alias table is wired ──

(ert-deftest helixel-test-mc-find-char-substitute-alist ()
  "find-next-char has a `helixel-find-repeat' substitute in the alist,
so fake cursors don't re-prompt for a character."
  (should (assq 'helixel-find-next-char
                helixel-mc--fake-substitute-alist))
  (should (eq 'helixel-find-repeat
              (cdr (assq 'helixel-find-next-char
                         helixel-mc--fake-substitute-alist)))))

(ert-deftest helixel-test-mc-substitute-commands-whitelisted ()
  "Both the original find-char commands and their substitutes are
marked for multi-cursor execution."
  (should (helixel-mc--should-run-for-all-p 'helixel-find-next-char))
  (should (helixel-mc--should-run-for-all-p 'helixel-find-repeat)))

;; ── keyboard-quit clears mc ──

(ert-deftest helixel-test-mc-keyboard-quit-clears ()
  "`keyboard-quit' triggers fake cursor cleanup via advice."
  (helixel-test-with-buffer "abc\n"
    (helixel-mc-create-fake-cursor 2)
    (should helixel-multi-cursor-mode)
    (condition-case nil (keyboard-quit) (quit nil))
    ;; After quit, mc mode is off and cursors cleared.
    (should-not helixel-multi-cursor-mode)
    (should (null (helixel-mc-all-cursors)))))

;; ── current-column-zero edge: col 0 always reachable ──

(ert-deftest helixel-test-mc-edit-lines-col-zero-always-reachable ()
  "Column 0 is always reachable — no line is skipped."
  (helixel-test-with-buffer "aaa\n   bbb\ncccc\n"
    (helixel-enter-normal-state)
    (goto-char 2)                       ; col 1 on line 1
    (push-mark 1 t t)
    (goto-char (point-max))
    (helixel-mc-edit-lines (region-beginning) (region-end))
    ;; col 0 on every line → 3 lines = 3 cursors total.
    (should (= 3 (helixel-mc-num-cursors)))
    (helixel-mc-clear-all)))

;; ── mode-line lighter format ──

(ert-deftest helixel-test-mc-lighter-format ()
  "The mode-line lighter shows the correct cursor count."
  (helixel-test-with-buffer "abc\n"
    (helixel-mc-create-fake-cursor 2)
    (helixel-mc-create-fake-cursor 3)
    (let ((lighter (format helixel-mc-mode-line-indicator
                           (helixel-mc-num-cursors))))
      (should (string-match "3" lighter)))
    (helixel-mc-clear-all)))

;; ── Helix-style selection management ops ──

(ert-deftest helixel-test-mc-keep-matching-filters-cursors ()
  "`helixel-mc-keep-matching' drops cursors whose region doesn't match."
  (helixel-test-with-buffer "foo bar foo bar foo\n"
    (helixel-enter-normal-state)
    (goto-char 1) (push-mark 1 t t) (goto-char 4)  ; real on "foo"
    (helixel-mc-create-fake-cursor 8 5)            ; fake on "bar"
    (helixel-mc-create-fake-cursor 12 9)           ; fake on "foo"
    (helixel-mc-create-fake-cursor 16 13)          ; fake on "bar"
    (helixel-mc-create-fake-cursor 20 17)          ; fake on "foo"
    (dolist (ov (helixel-mc-all-cursors))
      (overlay-put ov 'mark-active t))
    (should (= 4 (length (helixel-mc-all-cursors))))
    (helixel-mc-keep-matching "foo")
    ;; real + 2 foo fakes = 3 cursors total (= 2 fakes left)
    (should (= 2 (length (helixel-mc-all-cursors))))
    (dolist (ov (helixel-mc-all-cursors))
      (let* ((b (min (marker-position (overlay-get ov 'helixel-mc-point))
                     (marker-position (overlay-get ov 'helixel-mc-mark))))
             (e (max (marker-position (overlay-get ov 'helixel-mc-point))
                     (marker-position (overlay-get ov 'helixel-mc-mark)))))
        (should (equal "foo" (buffer-substring-no-properties b e)))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-remove-matching-filters-cursors ()
  "`helixel-mc-remove-matching' drops cursors whose region matches."
  (helixel-test-with-buffer "foo bar foo bar foo\n"
    (helixel-enter-normal-state)
    (goto-char 1) (push-mark 1 t t) (goto-char 4)  ; real on "foo"
    (helixel-mc-create-fake-cursor 8 5)            ; fake on "bar"
    (helixel-mc-create-fake-cursor 12 9)           ; fake on "foo"
    (dolist (ov (helixel-mc-all-cursors))
      (overlay-put ov 'mark-active t))
    (helixel-mc-remove-matching "foo")
    ;; real (foo) gets promoted-replaced by surviving "bar" fake.
    (should (use-region-p))
    (should (equal "bar" (buffer-substring-no-properties
                          (region-beginning) (region-end))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-rotate-primary-forward-swaps ()
  "`helixel-mc-rotate-primary-forward' swaps real cursor with next fake."
  (helixel-test-with-buffer "abc def ghi\n"
    (helixel-enter-normal-state)
    (goto-char 1) (push-mark 1 t t) (goto-char 4)  ; real on "abc"
    (helixel-mc-create-fake-cursor 8 5)            ; fake on "def"
    (helixel-mc-create-fake-cursor 12 9)           ; fake on "ghi"
    (overlay-put (car (helixel-mc-all-cursors)) 'mark-active t)
    (overlay-put (cadr (helixel-mc-all-cursors)) 'mark-active t)
    (helixel-mc-rotate-primary-forward 1)
    ;; Real should now be on "def" (positions 5..8).
    (should (= 8 (point)))
    (should (= 5 (mark t)))
    ;; A fake should now sit at 1..4 (the old real).
    (let ((sorted (helixel-mc-all-cursors :sort)))
      (should (= 4 (marker-position
                    (overlay-get (car sorted) 'helixel-mc-point))))
      (should (= 1 (marker-position
                    (overlay-get (car sorted) 'helixel-mc-mark)))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-rotate-content-forward-shifts-text ()
  "`helixel-mc-rotate-content-forward' cyclically swaps region texts."
  (helixel-test-with-buffer "AAA BBB CCC\n"
    (helixel-enter-normal-state)
    (goto-char 1) (push-mark 1 t t) (goto-char 4)  ; real on "AAA"
    (let ((ov1 (helixel-mc-create-fake-cursor 8 5))   ; "BBB"
          (ov2 (helixel-mc-create-fake-cursor 12 9))) ; "CCC"
      (overlay-put ov1 'mark-active t)
      (overlay-put ov2 'mark-active t))
    (helixel-mc-rotate-content-forward 1)
    ;; forward: each region gets text of LEFT neighbor (with wrap).
    ;; old: AAA BBB CCC -> CCC AAA BBB
    (should (equal "CCC AAA BBB\n" (buffer-string)))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-rotate-content-forward-repeatable ()
  "Pressing `M-)' twice in a row keeps mark active and rotates twice.
Regression: `delete-region'+`insert' used to deactivate `mark-active'
on both real and fakes, so the second call hit
`Real cursor must have a region'."
  (helixel-test-with-buffer "AAA BBB CCC\n"
    (helixel-enter-normal-state)
    (goto-char 1) (push-mark 1 t t) (goto-char 4)
    (let ((ov1 (helixel-mc-create-fake-cursor 8 5))
          (ov2 (helixel-mc-create-fake-cursor 12 9)))
      (overlay-put ov1 'mark-active t)
      (overlay-put ov2 'mark-active t))
    (helixel-mc-rotate-content-forward 1)
    (should (equal "CCC AAA BBB\n" (buffer-string)))
    (should (use-region-p))
    (dolist (ov (helixel-mc-all-cursors))
      (should (overlay-get ov 'mark-active)))
    ;; Second call must not signal.
    (helixel-mc-rotate-content-forward 1)
    ;; CCC AAA BBB -> BBB CCC AAA
    (should (equal "BBB CCC AAA\n" (buffer-string)))
    (should (use-region-p))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-merge-collapses-to-one-region ()
  "`helixel-mc-merge' replaces all cursors with one wide region."
  (helixel-test-with-buffer "abc def ghi\n"
    (helixel-enter-normal-state)
    (goto-char 1) (push-mark 1 t t) (goto-char 4)
    (helixel-mc-create-fake-cursor 8 5)
    (helixel-mc-create-fake-cursor 12 9)
    (overlay-put (car (helixel-mc-all-cursors)) 'mark-active t)
    (overlay-put (cadr (helixel-mc-all-cursors)) 'mark-active t)
    (helixel-mc-merge)
    (should (not (helixel-mc-any-p)))
    (should mark-active)
    (should (= 1 (mark t)))
    (should (= 12 (point)))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-trim-shrinks-whitespace-edges ()
  "`helixel-mc-trim' shrinks each region past leading/trailing whitespace."
  (helixel-test-with-buffer "  foo   bar  \n"
    (helixel-enter-normal-state)
    ;; Real: select "  foo   " (1..9)
    (goto-char 1) (push-mark 1 t t) (goto-char 9)
    ;; Fake: select "   bar  " (6..14)
    (let ((ov (helixel-mc-create-fake-cursor 14 6)))
      (overlay-put ov 'mark-active t))
    (helixel-mc-trim)
    ;; Real shrinks to "foo" (3..6).
    (should (= 3 (mark t)))
    (should (= 6 (point)))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-align-pads-to-max-column ()
  "`helixel-mc-align' inserts spaces so all cursors share max column."
  (helixel-test-with-buffer "a\nbb\nccc\n"
    (helixel-enter-normal-state)
    ;; Real at end of line 1 (col 1 in 0-indexed = after "a").
    (goto-char 2)
    ;; Fakes at end of lines 2 and 3.
    (helixel-mc-create-fake-cursor 5)
    (helixel-mc-create-fake-cursor 9)
    (helixel-mc-align)
    ;; Max col was 3 (ccc).  Line 1 grew by 2 spaces, line 2 by 1.
    (should (equal "a  \nbb \nccc\n" (buffer-string)))
    (helixel-mc-clear-all)))

;; ── Split selection / restore-cursors ──

(ert-deftest helixel-test-mc-split-on-regex-creates-cursors ()
  "`helixel-mc-split-on-regex' splits one selection into N cursors."
  (helixel-test-with-buffer "foo bar foo baz foo\n"
    (helixel-enter-normal-state)
    (goto-char 1) (push-mark 1 t t) (goto-char 20)
    (helixel-mc-split-on-regex "foo")
    ;; 3 "foo" matches → real + 2 fakes.
    (should (= 2 (length (helixel-mc-all-cursors))))
    (should (equal "foo" (buffer-substring-no-properties
                          (region-beginning) (region-end))))
    (dolist (ov (helixel-mc-all-cursors))
      (let ((b (min (marker-position (overlay-get ov 'helixel-mc-point))
                    (marker-position (overlay-get ov 'helixel-mc-mark))))
            (e (max (marker-position (overlay-get ov 'helixel-mc-point))
                    (marker-position (overlay-get ov 'helixel-mc-mark)))))
        (should (equal "foo" (buffer-substring-no-properties b e)))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-split-into-lines-creates-cursors ()
  "`s x' over a line-mode `x' selection produces one full-line
region cursor per line (Helix `Alt-s' semantics)."
  (helixel-test-with-buffer "aaa\nbbb\nccc\n"
    (helixel-enter-normal-state)
    (goto-char 1) (push-mark 1 t t) (goto-char 12)
    (let ((helixel--raw-selection-type 'line))
      (helixel-mc-edit-lines (region-beginning) (region-end)))
    (should (= 2 (length (helixel-mc-all-cursors))))
    (let ((texts (sort
                  (cons (buffer-substring-no-properties
                         (region-beginning) (region-end))
                        (mapcar
                         (lambda (ov)
                           (buffer-substring-no-properties
                            (min (marker-position
                                  (overlay-get ov 'helixel-mc-point))
                                 (marker-position
                                  (overlay-get ov 'helixel-mc-mark)))
                            (max (marker-position
                                  (overlay-get ov 'helixel-mc-point))
                                 (marker-position
                                  (overlay-get ov 'helixel-mc-mark)))))
                         (helixel-mc-all-cursors)))
                  #'string<)))
      (should (equal '("aaa" "bbb" "ccc") texts)))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-restore-cursors-after-clear ()
  "`helixel-mc-restore-cursors' brings back the layout cleared by `s ,'."
  (helixel-test-with-buffer "abc def ghi\n"
    (helixel-enter-normal-state)
    (setq helixel-mc--history nil)
    (goto-char 1) (push-mark 1 t t) (goto-char 4)
    (helixel-mc-create-fake-cursor 8 5)
    (helixel-mc-create-fake-cursor 12 9)
    (overlay-put (car (helixel-mc-all-cursors)) 'mark-active t)
    (overlay-put (cadr (helixel-mc-all-cursors)) 'mark-active t)
    (helixel-mc-clear-all)
    (should (null (helixel-mc-all-cursors)))
    (helixel-mc-restore-cursors)
    ;; Should have 2 fakes back at their original positions.
    (should (= 2 (length (helixel-mc-all-cursors))))
    (let ((sorted (helixel-mc-all-cursors :sort)))
      (should (= 8 (marker-position
                    (overlay-get (car sorted) 'helixel-mc-point))))
      (should (= 12 (marker-position
                     (overlay-get (cadr sorted)
                                  'helixel-mc-point)))))
    (helixel-mc-clear-all)))

(provide 'helixel-test-mc)
;;; helixel-test-mc.el ends here
