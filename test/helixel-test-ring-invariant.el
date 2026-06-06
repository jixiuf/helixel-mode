;;; helixel-test-ring-invariant.el --- Ring subsystem invariants  -*- lexical-binding: t; -*-

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
     (setq helixel--event-ring nil)
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
    (helixel-action-commit)
    (let ((after-first (length helixel--event-ring)))
      (setq helixel--live-action
            (helixel-ring-inv--make-event 'movement 'word 1))
      (helixel-action-commit)
      (should (= (length helixel--event-ring) after-first)))))

;; ── INV-RING-2: cap respected ──

(ert-deftest helixel-test-inv-ring-cap-respected ()
  "INV: ring length never exceeds `helixel-action-ring-max'."
  (helixel-ring-inv-with-buffer (make-string 200 ?x)
    (let ((helixel-action-ring-max 10))
      (dotimes (i 25)
        (setq helixel--live-action
              (helixel-ring-inv--make-event 'movement 'word (1+ i)))
        (helixel-action-commit))
      (should (<= (length helixel--event-ring) 10)))))

;; ── INV-RING-3: cap releases markers of evicted entries ──

(ert-deftest helixel-test-inv-ring-cap-releases-markers ()
  "INV: when cap evicts older entries, their markers are nulled."
  (helixel-ring-inv-with-buffer (make-string 200 ?x)
    (let ((helixel-action-ring-max 3)
          (oldest-marker nil))
      (setq helixel--live-action
            (helixel-ring-inv--make-event 'movement 'word 1))
      (helixel-action-commit)
      ;; Capture pointer to the marker of the entry that WILL be evicted.
      (setq oldest-marker
            (car (helixel-action-mark-region (car helixel--event-ring))))
      (should (marker-position oldest-marker))
      ;; Push enough to force eviction.
      (dotimes (i 8)
        (setq helixel--live-action
              (helixel-ring-inv--make-event 'movement 'word (+ 2 i)))
        (helixel-action-commit))
      (should (= (length helixel--event-ring) 3))
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
        (helixel-action-commit)
        (should received)
        ;; Received entry is the same as the one now on the ring front.
        (should (eq received (car helixel--event-ring)))))))

;; ── INV-RING-5: by-command auto-stamped from this-command if not set ──

(ert-deftest helixel-test-inv-ring-by-command-fallback ()
  "INV: commit fills in by-command from `this-command' when not pre-stamped."
  (helixel-ring-inv-with-buffer "abc\n"
    (let ((this-command 'some-test-command))
      (setq helixel--live-action
            (helixel-ring-inv--make-event 'movement 'word 1))
      ;; ensure by-command is nil so the fallback path runs
      (setf (helixel-action-by-command helixel--live-action) nil)
      (helixel-action-commit)
      (should (eq (helixel-action-by-command (car helixel--event-ring))
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

(provide 'helixel-test-ring-invariant)
;;; helixel-test-ring-invariant.el ends here
