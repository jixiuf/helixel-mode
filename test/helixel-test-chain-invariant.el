;;; helixel-test-chain-invariant.el --- Chain subsystem invariants  -*- lexical-binding: t; -*-

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

;; Invariant tests for the chain subsystem.  These tests assert
;; structural properties that the chain implementation MUST maintain
;; across all code paths.  They are intentionally lightweight: each
;; test exercises one invariant in isolation so that future refactors
;; (e.g. helixel-tx/action merge, preposition first-class slot) can be
;; validated by running this file alone.

;;; Code:

(require 'ert)
(require 'helixel)
(require 'helixel-chain)

(defmacro helixel-chain-inv-with-buffer (content &rest body)
  "Execute BODY in a temp buffer with CONTENT.
Resets chain session and pending sel before BODY; releases markers
after BODY to keep ert clean."
  (declare (indent 1))
  `(with-temp-buffer
     (transient-mark-mode 1)
     (insert ,content)
     (goto-char (point-min))
     (setq helixel--chain-session nil)
     (setq helixel--pending-sel nil)
     (unwind-protect (progn ,@body)
       (when helixel--chain-session
         (when-let* ((b (helixel-chain-session-init-bounds
                         helixel--chain-session)))
           (ignore-errors (set-marker (car b) nil))
           (ignore-errors (set-marker (cdr b) nil))))
       (setq helixel--chain-session nil))))

;; ── INV-CHAIN-1: start sets active-p, end clears it ──

(ert-deftest helixel-test-inv-chain-lifecycle-active-flag ()
  "INV: chain-start sets active-p t; chain-end sets it nil; cancel sets it nil."
  (helixel-chain-inv-with-buffer "abc\n"
    (should-not (helixel--chain-active-p))
    (helixel-repeat-chain-start)
    (should (helixel--chain-active-p))
    (helixel-repeat-chain-cancel)
    (should-not (helixel--chain-active-p))
    ;; Start, then end via end command.
    (helixel-repeat-chain-start)
    (should (helixel--chain-active-p))
    (helixel-repeat-chain-end)
    (should-not (helixel--chain-active-p))))

;; ── INV-CHAIN-2: chain-control commands never enter tx-list ──

(ert-deftest helixel-test-inv-chain-control-cmds-excluded ()
  "INV: actions stamped with chain-control by-command stay out of tx-list."
  (helixel-chain-inv-with-buffer "abc\n"
    (helixel-repeat-chain-start)
    ;; Synthesise an action that LOOKS like chain-end committing.
    (let* ((tx (make-helixel-tx :op 'kill :runner #'identity))
           (entry (make-helixel-action
                   :category 'edit
                   :subcat 'kill
                   :by-command 'helixel-repeat-chain-end
                   :tx tx
                   :mark-region (cons (point-marker)
                                      (copy-marker (point) t)))))
      (helixel--chain-on-commit entry)
      (should (null (helixel-chain-session-tx-list
                     helixel--chain-session))))
    ;; Now a real edit action should be appended.
    (let* ((tx (make-helixel-tx :op 'kill :runner #'identity))
           (entry (make-helixel-action
                   :category 'edit
                   :subcat 'kill
                   :by-command 'helixel-kill-thing
                   :tx tx
                   :mark-region (cons (point-marker)
                                      (copy-marker (point) t)))))
      (helixel--chain-on-commit entry)
      (should (equal (length (helixel-chain-session-tx-list
                              helixel--chain-session))
                     1)))
    (helixel-repeat-chain-cancel)))

;; ── INV-CHAIN-3: actions without runner stay out of tx-list ──

(ert-deftest helixel-test-inv-chain-runnerless-tx-excluded ()
  "INV: a committed action whose tx has no runner does NOT enter tx-list.
Movement / textobj selections produce txs with op=nil + runner=nil
that participate in mc dispatch but must not be replayed via chain."
  (helixel-chain-inv-with-buffer "abc\n"
    (helixel-repeat-chain-start)
    (let* ((tx (make-helixel-tx :op nil :runner nil))
           (entry (make-helixel-action
                   :category 'movement
                   :subcat 'word
                   :by-command 'helixel-forward-word
                   :tx tx
                   :mark-region (cons (point-marker)
                                      (copy-marker (point) t)))))
      (helixel--chain-on-commit entry)
      (should (null (helixel-chain-session-tx-list
                     helixel--chain-session))))
    (helixel-repeat-chain-cancel)))

;; ── INV-CHAIN-4: cancel releases init-bounds markers ──

(ert-deftest helixel-test-inv-chain-cancel-releases-markers ()
  "INV: chain-cancel nulls any init-bounds markers it held."
  (helixel-chain-inv-with-buffer "abcdef\n"
    (goto-char 2)
    (push-mark 5 t t)
    (helixel-repeat-chain-start)
    (let* ((b (helixel-chain-session-init-bounds helixel--chain-session))
           (mb (car b))
           (me (cdr b)))
      (should (markerp mb))
      (should (marker-position mb))
      (helixel-repeat-chain-cancel)
      (should-not (marker-position mb))
      (should-not (marker-position me))
      ;; Session itself is gone.
      (should-not helixel--chain-session))))

(provide 'helixel-test-chain-invariant)
;;; helixel-test-chain-invariant.el ends here
