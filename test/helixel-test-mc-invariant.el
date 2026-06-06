;;; helixel-test-mc-invariant.el --- mc per-cursor invariant smoke -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Smoke tests for the mc dispatch contract:
;;
;;   1. Per-cursor helixel vars (`helixel--pending-sel',
;;      `helixel--last-tx', `helixel--active-search',
;;      `helixel--event-ring', `helixel--live-action',
;;      `helixel--action-pos') are restored to their pre-dispatch
;;      values by `helixel-mc-with-each-cursor', and per-fake
;;      mutation persists across dispatches in the fake's own
;;      `helixel-pc-state' struct.
;;
;;   2. `helixel-pc-state' struct shape — every documented
;;      slot is present and CONSTRUCTOR / ACCESSORS exist.  This
;;      catches accidental slot drift.

;;; Code:

(require 'ert)
(require 'cl-lib)
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
          (helixel--last-tx   'REAL-EVT)
          (helixel--active-search 'REAL-SEARCH)
          (helixel--event-ring   '(real-evt))
          (helixel--live-action   'REAL-LIVE)
          (helixel--action-pos   42))
      ;; Per-fake mutation
      (helixel-mc-with-each-cursor
        (setq helixel--pending-sel   'FAKE-SEL
              helixel--last-tx    'FAKE-EVT
              helixel--active-search 'FAKE-SEARCH
              helixel--event-ring    '(fake-evt)
              helixel--live-action    'FAKE-LIVE
              helixel--action-pos    99))
      ;; Real cursor's bindings untouched
      (should (eq helixel--pending-sel   'REAL-SEL))
      (should (eq helixel--last-tx    'REAL-EVT))
      (should (eq helixel--active-search 'REAL-SEARCH))
      (should (equal helixel--event-ring '(real-evt)))
      (should (eq helixel--live-action    'REAL-LIVE))
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

(ert-deftest helixel-test-mc-invariant-cursor-state-slots ()
  "`helixel-pc-state' struct exposes every per-cursor slot.
Guards against accidental slot drift — every slot listed here
MUST exist on the struct or the snapshot/restore machinery in
`helixel-mc-core' silently misses state."
  :tags '(mc invariant)
  (dolist (accessor '(helixel-pcs-point
                      helixel-pcs-mark
                      helixel-pcs-mark-active
                      helixel-pcs-kill-ring
                      helixel-pcs-kill-ring-yank-pointer
                      helixel-pcs-mark-ring
                      helixel-pcs-pending-sel
                      helixel-pcs-last-action
                      helixel-pcs-active-search
                      helixel-pcs-event-ring
                      helixel-pcs-live-action
                      helixel-pcs-action-pos))
    (should (fboundp accessor))))

(ert-deftest helixel-test-mc-invariant-mark-active-in-struct ()
  "`mark-active' is now a slot of `helixel-pc-state' — historically
it was managed separately as an overlay property; the struct-based
refactor brought it inside the standard snapshot/restore path."
  :tags '(mc invariant)
  (should (fboundp 'helixel-pcs-mark-active))
  ;; And the snapshot fn reads it.
  (helixel-test-with-buffer ""
    (setq mark-active t)
    (should (helixel-pcs-mark-active (helixel-pcs-clone)))
    (setq mark-active nil)
    (should-not (helixel-pcs-mark-active (helixel-pcs-clone)))))

(provide 'helixel-test-mc-invariant)
;;; helixel-test-mc-invariant.el ends here
