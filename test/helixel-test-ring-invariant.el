;;; helixel-test-ring-invariant.el --- Ring subsystem invariants  -*- lexical-binding: t; -*-

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

;;; Commentary:

;; Invariant tests for the event ring + global jump log.

;;; Code:

(require 'ert)
(require 'helixel)
(require 'helixel-ring)

(defmacro helixel-ring-inv-with-buffer (content &rest body)
  "Execute BODY in a temp buffer with CONTENT, resetting ring state."
  (declare (indent 1))
  `(with-temp-buffer
     (transient-mark-mode 1)
     (insert ,content)
     (goto-char (point-min))
     (setq helixel--action-ring nil)
     (setq helixel--live-action nil)
     (setq helixel--action-pos nil)
     ,@body))

(defun helixel-ring-inv--make-event (cat sub &optional pos by-command)
  "Build a `helixel-action' for testing."
  (let* ((p (or pos (point)))
         (m (copy-marker p))
         (e (copy-marker p t)))
    (make-helixel-action
     :category cat
     :subcat sub
     :mark-region (cons m e)
     :timestamp (float-time)
     :buffer (current-buffer)
     :by-command by-command)))

;; ── INV-RING-1: commit dedups identical-content entries ──

(ert-deftest helixel-test-inv-ring-commit-dedups ()
  "INV: two consecutive commits with identical content keep only one entry."
  (helixel-ring-inv-with-buffer "abc\n"
    (setq helixel--live-action
          (helixel-ring-inv--make-event 'movement 'word 1))
    (helixel--action-commit)
    (let ((after-first (length helixel--action-ring)))
      (setq helixel--live-action
            (helixel-ring-inv--make-event 'movement 'word 1))
      (helixel--action-commit)
      (should (= (length helixel--action-ring) after-first)))))

(ert-deftest helixel-test-inv-ring-commit-no-dedup-different-cdr ()
  "INV: two commits with same car but different cdr are NOT deduped.
Prevents consecutive pastes at the same cursor position from
amalgamating into a single ring entry (Bug: ; newest-for-mark)."
  (helixel-ring-inv-with-buffer "abc\n"
    (setq helixel--live-action
          (make-helixel-action
           :category 'edit :subcat 'paste-after
           :mark-region (cons (copy-marker 1) (copy-marker 5 t))
           :timestamp (float-time)
           :buffer (current-buffer)))
    (helixel--action-commit)
    (let ((after-first (length helixel--action-ring)))
      (setq helixel--live-action
            (make-helixel-action
             :category 'edit :subcat 'paste-after
             :mark-region (cons (copy-marker 1) (copy-marker 3 t))
             :timestamp (float-time)
             :buffer (current-buffer)))
      (helixel--action-commit)
      ;; Same car (1), different cdr (5 vs 3) — must NOT dedup.
      (should (= (length helixel--action-ring) (1+ after-first))))))

(ert-deftest helixel-test-inv-ring-commit-dedups-same-car-and-cdr ()
  "INV: two commits with same car AND cdr still dedup."
  (helixel-ring-inv-with-buffer "abc\n"
    (setq helixel--live-action
          (make-helixel-action
           :category 'edit :subcat 'paste-after
           :mark-region (cons (copy-marker 1) (copy-marker 5 t))
           :timestamp (float-time)
           :buffer (current-buffer)))
    (helixel--action-commit)
    (let ((after-first (length helixel--action-ring)))
      (setq helixel--live-action
            (make-helixel-action
             :category 'edit :subcat 'paste-after
             :mark-region (cons (copy-marker 1) (copy-marker 5 t))
             :timestamp (float-time)
             :buffer (current-buffer)))
      (helixel--action-commit)
      ;; Same car AND cdr — still dedup.
      (should (= (length helixel--action-ring) after-first)))))

;; ── INV-RING-2: cap respected ──

(ert-deftest helixel-test-inv-ring-cap-respected ()
  "INV: ring length never exceeds `helixel-action-ring-max'."
  (helixel-ring-inv-with-buffer (make-string 200 ?x)
    (let ((helixel-action-ring-max 10))
      (dotimes (i 25)
        (setq helixel--live-action
              (helixel-ring-inv--make-event 'movement 'word (1+ i)))
        (helixel--action-commit))
      (should (<= (length helixel--action-ring) 10)))))

;; ── INV-RING-3: cap releases markers of evicted entries ──

(ert-deftest helixel-test-inv-ring-cap-releases-markers ()
  "INV: when cap evicts older entries, their markers are nulled."
  (helixel-ring-inv-with-buffer (make-string 200 ?x)
    (let ((helixel-action-ring-max 3)
          (oldest-marker nil))
      (setq helixel--live-action
            (helixel-ring-inv--make-event 'movement 'word 1))
      (helixel--action-commit)
      ;; Capture pointer to the marker of the entry that WILL be evicted.
      (setq oldest-marker
            (car (helixel-action-mark-region (car helixel--action-ring))))
      (should (marker-position oldest-marker))
      ;; Push enough to force eviction.
      (dotimes (i 8)
        (setq helixel--live-action
              (helixel-ring-inv--make-event 'movement 'word (+ 2 i)))
        (helixel--action-commit))
      (should (= (length helixel--action-ring) 3))
      ;; Original marker has been nulled (released).
      (should-not (marker-position oldest-marker)))))

;; ── INV-RING-4: commit-hook fires after push, with the entry ──

(ert-deftest helixel-test-inv-ring-commit-hook-fires-with-entry ()
  "INV: `helixel-action-commit-hook' fires with the just-committed entry."
  (helixel-ring-inv-with-buffer "abc\n"
    (let ((received nil))
      (cl-letf ((helixel-action-commit-hook
                 (list (lambda (e) (setq received e)))))
        (setq helixel--live-action
              (helixel-ring-inv--make-event 'movement 'word 1))
        (helixel--action-commit)
        (should received)
        ;; Received entry is the same as the one now on the ring front.
        (should (eq received (car helixel--action-ring)))))))

;; ── INV-RING-5: by-command auto-stamped from this-command if not set ──

(ert-deftest helixel-test-inv-ring-by-command-fallback ()
  "INV: commit fills in by-command from `this-command' when not pre-stamped."
  (helixel-ring-inv-with-buffer "abc\n"
    (let ((this-command 'some-test-command))
      (setq helixel--live-action
            (helixel-ring-inv--make-event 'movement 'word 1))
      ;; ensure by-command is nil so the fallback path runs
      (setf (helixel-action-by-command helixel--live-action) nil)
      (helixel--action-commit)
      (should (eq (helixel-action-by-command (car helixel--action-ring))
                  'some-test-command)))))

;; ── INV-RING-6: jump-log entry is lightweight (no embedded tx) ──

(ert-deftest helixel-test-inv-ring-jump-log-is-lightweight ()
  "INV: `helixel--global-jump-log' entries are plists without :tx data."
  (helixel-ring-inv-with-buffer "abc\n"
    (let ((helixel--global-jump-log nil))
      (helixel--global-jump-log-push
       (helixel-ring-inv--make-event 'movement 'word 1))
      (should helixel--global-jump-log)
      (let ((entry (car helixel--global-jump-log)))
        ;; plist with :category :subcat :mark-region :buffer, no :tx.
        (should (plist-get entry :category))
        (should (plist-get entry :buffer))
        (should-not (plist-member entry :tx))))))

;; ── INV-RING-7: start-point is deep-copied to ring ──

(ert-deftest helixel-test-inv-ring-start-point-copied ()
  "INV: start-point marker is deep-copied into ring entries."
  (helixel-ring-inv-with-buffer "hello world\n"
    (goto-char 4)
    (helixel--tracking-open 'movement 'word)
    (should (helixel-action-start-point helixel--live-action))
    (let ((live-sp (helixel-action-start-point helixel--live-action)))
      (should (markerp live-sp))
      (helixel--action-commit)
      (let ((ring-entry (car helixel--action-ring)))
        (should (helixel-action-start-point ring-entry))
        (should (markerp (helixel-action-start-point ring-entry)))
        (should-not (eq live-sp (helixel-action-start-point ring-entry)))))))

;; ── INV-RING-8: ring cap releases start-point markers ──

(ert-deftest helixel-test-inv-ring-start-point-released ()
  "INV: evicted ring entries have their start-point markers released."
  (helixel-ring-inv-with-buffer "hello world\n"
    (let ((helixel-action-ring-max 2))
      (goto-char 1)
      (helixel--tracking-open 'movement 'word)
      (helixel--action-commit)
      (let ((sp1 (helixel-action-start-point (car helixel--action-ring))))
        (should (markerp sp1))
        (should (marker-buffer sp1))
        (goto-char 5)
        (helixel--tracking-open 'movement 'WORD)
        (helixel--action-commit)
        (goto-char 9)
        (helixel--tracking-open 'movement 'symbol)
        (helixel--action-commit)
        (should (null (marker-buffer sp1)))))))

;; ── INV-RING-PD: ring entries are pure data (no closures) ──

(ert-deftest helixel-test-inv-ring-op-registry-pure-data ()
  "INV: every op :runner and functional :display is a named symbol.
Closures would make ring entries unprintable and not `equal'-able."
  (maphash
   (lambda (op entry)
     (let ((runner (plist-get entry :runner))
           (display (plist-get entry :display)))
       (when runner
         (should (symbolp runner)))
       (when (and display (functionp display))
         (should (symbolp display))))
     op)
   helixel--op-registry))

(ert-deftest helixel-test-inv-ring-insert-preposition-is-symbol ()
  "INV: a committed insert action carries a symbol preposition."
  (let ((helixel-last-action nil))
    (helixel-ring-inv-with-buffer "abc"
      (goto-char 2)
      (setq last-command nil this-command 'helixel-insert)
      (helixel-insert)
      (insert "Z")
      (helixel-insert-exit)
      (let ((front (car helixel--action-ring)))
        (should front)
        (when-let* ((pre (helixel-action-preposition front)))
          (should (symbolp pre)))))))

(ert-deftest helixel-test-inv-ring-find-char-runner-is-symbol ()
  "INV: a committed find-char action carries a symbol runner."
  (helixel-ring-inv-with-buffer "foo bar foo"
    (goto-char (point-min))
    (setq last-command nil this-command 'helixel-find-next-char)
    (helixel-find-next-char ?b)
    (let ((front (car helixel--action-ring)))
      (should front)
      (when-let* ((runner (helixel-action-runner front)))
        (should (symbolp runner))))))

(ert-deftest helixel-test-inv-ring-delimiter-printable-roundtrip ()
  "INV: delimiter structs print-read round-trip (pure data)."
  (require 'helixel-textobj-pair)
  (dolist (d (list (helixel-make-pair-delimiter ?\( ?\))
                   (helixel-make-pair-delimiter ?\" ?\")
                   (helixel-make-tag-delimiter)))
    (should (equal d (read (prin1-to-string d))))))

(provide 'helixel-test-ring-invariant)
;;; helixel-test-ring-invariant.el ends here
