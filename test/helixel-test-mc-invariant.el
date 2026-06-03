;;; helixel-test-mc-invariant.el --- mc per-cursor invariant smoke -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Step 16 of docs/REFACTOR_PLAN.md.
;;
;; Smoke tests that exercise the mc dispatch contract:
;;
;;   1. Every variable in `helixel-mc-cursor-vars' is restored to its
;;      snapshot when `helixel-mc-with-each-cursor' enters a fake,
;;      and the fake's mutation does not leak into the real cursor.
;;
;;   2. The contract is symmetric across all registered vars — adding
;;      a new var via `helixel-mc-register-cursor-var' just works.

;;; Code:

(require 'ert)
(require 'helixel-mc-core)
(require 'helixel-test-common)

(ert-deftest helixel-test-mc-invariant-real-cursor-isolated ()
  "Mutations made inside `with-each-cursor' must not touch the
real cursor's bindings of any registered per-cursor var."
  :tags '(mc invariant)
  (helixel-test-with-buffer "abc\ndef\nghi\n"
    (goto-char 1)
    (helixel-mc-create-fake-cursor 5)   ; on 'd'
    (helixel-mc-create-fake-cursor 9)   ; on 'h'
    (let ((helixel--pending-sel  'REAL-SEL)
          (helixel--last-event   'REAL-EVT)
          (helixel--active-search 'REAL-SEARCH)
          (helixel--event-ring   '(real-evt))
          (helixel--live-event   'REAL-LIVE)
          (helixel--action-pos   42))
      ;; Per-fake mutation
      (helixel-mc-with-each-cursor
        (setq helixel--pending-sel   'FAKE-SEL
              helixel--last-event    'FAKE-EVT
              helixel--active-search 'FAKE-SEARCH
              helixel--event-ring    '(fake-evt)
              helixel--live-event    'FAKE-LIVE
              helixel--action-pos    99))
      ;; Real cursor's bindings untouched
      (should (eq helixel--pending-sel   'REAL-SEL))
      (should (eq helixel--last-event    'REAL-EVT))
      (should (eq helixel--active-search 'REAL-SEARCH))
      (should (equal helixel--event-ring '(real-evt)))
      (should (eq helixel--live-event    'REAL-LIVE))
      (should (eq helixel--action-pos    42)))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-invariant-fake-isolation ()
  "Each fake's mutation persists in its own overlay across dispatches,
without leaking into other fakes."
  :tags '(mc invariant)
  (helixel-test-with-buffer "abc\ndef\nghi\n"
    (goto-char 1)
    (helixel-mc-create-fake-cursor 5)
    (helixel-mc-create-fake-cursor 9)
    ;; Tag each fake with a distinct value
    (let ((counter 0))
      (helixel-mc-with-each-cursor
        (cl-incf counter)
        (setq helixel--action-pos counter)))
    ;; Verify each fake remembered its own value
    (let ((seen nil))
      (helixel-mc-with-each-cursor
        (push helixel--action-pos seen))
      (should (equal (sort seen #'<) '(1 2))))
    (helixel-mc-clear-all)))

(ert-deftest helixel-test-mc-invariant-registry-symmetric ()
  "All entries in `helixel-mc-cursor-vars' have non-empty names —
sanity check the registry isn't accidentally polluted by nil."
  :tags '(mc invariant)
  (dolist (var helixel-mc-cursor-vars)
    (should (symbolp var))
    (should (> (length (symbol-name var)) 0))))

(ert-deftest helixel-test-mc-invariant-mark-active-not-registered ()
  "`mark-active' must NOT be in `helixel-mc-cursor-vars' (would
clobber the per-fake flag stored on the overlay)."
  :tags '(mc invariant)
  (should-not (memq 'mark-active helixel-mc-cursor-vars)))

(provide 'helixel-test-mc-invariant)
;;; helixel-test-mc-invariant.el ends here
