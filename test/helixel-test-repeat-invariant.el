;;; helixel-test-repeat-invariant.el --- Repeat subsystem invariants  -*- lexical-binding: t; -*-

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

;; Invariant tests for the repeat subsystem (dot-repeat `.', selection
;; repeat `,').  Asserts structural properties the implementation MUST
;; maintain so that future refactors (tx/action merge, preposition
;; first-class slot, etc.) can be validated quickly.

;;; Code:

(require 'ert)
(require 'helixel)
(require 'helixel-repeat)

(defmacro helixel-repeat-inv-with-buffer (content &rest body)
  "Execute BODY in a temp buffer with CONTENT.
Resets last-tx and pending sel before BODY."
  (declare (indent 1))
  `(with-temp-buffer
     (transient-mark-mode 1)
     (insert ,content)
     (goto-char (point-min))
     (setq helixel--last-tx nil)
     (setq helixel--pending-sel nil)
     (setq helixel--repeat-permanent-flip nil)
     ,@body))

;; ── INV-REPEAT-1: replay context inhibits re-recording ──

(ert-deftest helixel-test-inv-repeat-replay-context-active ()
  "INV: `helixel-replaying-p' is t while a `dot' origin context is active.
This is what prevents `.' from recording itself."
  (helixel-repeat-inv-with-buffer "abc\n"
    (should-not (helixel-replaying-p))
    (helixel-with-replay 'dot
      (should (helixel-replaying-p)))
    (should-not (helixel-replaying-p))))

;; ── INV-REPEAT-2: last-tx is buffer-local ──

(ert-deftest helixel-test-inv-repeat-last-tx-is-buffer-local ()
  "INV: `helixel--last-tx' is buffer-local; setting in one buffer
does not bleed into another."
  (let* ((b1 (generate-new-buffer " *inv-repeat-b1*"))
         (b2 (generate-new-buffer " *inv-repeat-b2*"))
         (tx-1 (make-helixel-tx :op 'kill))
         (tx-2 (make-helixel-tx :op 'change)))
    (unwind-protect
        (progn
          (with-current-buffer b1
            (setq helixel--last-tx tx-1))
          (with-current-buffer b2
            (setq helixel--last-tx tx-2))
          (with-current-buffer b1
            (should (eq helixel--last-tx tx-1)))
          (with-current-buffer b2
            (should (eq helixel--last-tx tx-2))))
      (kill-buffer b1)
      (kill-buffer b2))))

;; ── INV-REPEAT-3: tx-replay does NOT mutate last-tx ──

(ert-deftest helixel-test-inv-repeat-tx-replay-does-not-mutate ()
  "INV: replaying a tx via `helixel-tx-replay' must not mutate the tx.
Otherwise `.' twice in a row would produce different second results."
  (helixel-repeat-inv-with-buffer "abcde\n"
    (let* ((calls 0)
           (tx (make-helixel-tx
                :op 'change
                :runner (lambda (_tx) (cl-incf calls)))))
      (setq helixel--last-tx tx)
      (helixel-tx-replay tx)
      (helixel-tx-replay tx)
      (helixel-tx-replay tx)
      (should (eq calls 3))
      ;; tx is the same object, unchanged.
      (should (eq helixel--last-tx tx))
      (should (eq (helixel-tx-op tx) 'change)))))

;; ── INV-REPEAT-4: preposition runs before runner ──

(ert-deftest helixel-test-inv-repeat-pre-replay-before-runner ()
  "INV: when both present, preposition fires strictly before runner."
  (helixel-repeat-inv-with-buffer "abc\n"
    (let* ((seq nil)
           (tx (make-helixel-tx
                :op 'foo
                :preposition (lambda (_tx) (push 'pre seq))
                :runner (lambda (_tx) (push 'run seq)))))
      (helixel-tx-replay tx)
      ;; pushed in order pre then run; head of seq is 'run.
      (should (equal seq '(run pre))))))

;; ── INV-REPEAT-5: replay context cleans up on body exit ──

(ert-deftest helixel-test-inv-repeat-replay-context-cleanup ()
  "INV: `helixel-with-replay' restores nil context on body exit, even on error."
  (helixel-repeat-inv-with-buffer "abc\n"
    (ignore-errors
      (helixel-with-replay 'dot
        (error "boom")))
    (should-not helixel--replay)
    (should-not (helixel-replaying-p))))

(provide 'helixel-test-repeat-invariant)
;;; helixel-test-repeat-invariant.el ends here
