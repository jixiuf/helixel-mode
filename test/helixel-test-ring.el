;;; helixel-test-ring.el --- Tests for event ring & jump log  -*- lexical-binding: t; -*-

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

;; Tests for helixel-ring.el: event ring, commit, dedup, cap, and
;; global jump log.

;;; Code:

(require 'ert)
(require 'helixel)
(require 'helixel-core)

;;; Event commit basics

(ert-deftest helixel-test-ring-commit-basic ()
  "`helixel-action-commit' pushes live-event to ring (movement: no tx)."
  (let ((helixel--event-ring nil)
        (helixel--live-action nil)
        (helixel--last-tx nil))
    (helixel-test-with-buffer "hello world"
      (helixel--tracking-open 'movement 'char)
      (let ((entry (helixel-action-commit)))
        (should entry)
        (should (helixel-action-p entry))
        (should (= (length helixel--event-ring) 1))
        (should (eq (car helixel--event-ring) entry))
        ;; Movement has no tx — last-tx unchanged.
        (should (null helixel--last-tx))
        (should (null helixel--live-action))))))

(ert-deftest helixel-test-ring-commit-nil-live ()
  "`helixel-action-commit' with nil live-event returns nil."
  (let ((helixel--event-ring nil)
        (helixel--live-action nil)
        (helixel--last-tx nil))
    (should (null (helixel-action-commit)))
    (should (null helixel--event-ring))
    (should (null helixel--last-tx))))

(ert-deftest helixel-test-ring-commit-sets-last-event ()
  "After committing an EDIT (with op), `helixel--last-tx' points to that event.
Movement commits leave `helixel--last-tx' unchanged."
  (let ((helixel--event-ring nil)
        (helixel--live-action nil)
        (helixel--last-tx nil))
    (helixel-test-with-buffer "hello world"
      (helixel--tracking-open 'edit 'kill 'kill)
      (let* ((e1 (helixel-action-commit))
             (tx1 e1))
        (should e1)
        (should tx1)
        (should (eq helixel--last-tx tx1))
        (helixel--tracking-open 'edit 'change 'change)
        (let* ((e2 (helixel-action-commit))
               (tx2 e2))
          (should e2)
          (should (eq helixel--last-tx tx2))
          (should (not (eq tx1 tx2)))
          (should (= (length helixel--event-ring) 2)))))))

;;; Dedup

(ert-deftest helixel-test-ring-commit-dedup ()
  "Committing same event twice in a row pushes only once."
  (let ((helixel--event-ring nil)
        (helixel--live-action nil)
        (helixel--last-tx nil))
    (helixel-test-with-buffer "hello world"
      (helixel--tracking-open 'movement 'char)
      (let ((sel (helixel-sel-create 'line '(:dir forward :count 1))))
        (setf (helixel-action-sel helixel--live-action) sel)
        (setf (helixel-action-op helixel--live-action) 'kill)
        (setf (helixel-action-payload helixel--live-action) '(:text "x")))
      (helixel-action-commit)
      (should (= (length helixel--event-ring) 1))
      ;; Re-create identical live-event and commit again
      (helixel--tracking-open 'movement 'char)
      (let ((sel (helixel-sel-create 'line '(:dir forward :count 1))))
        (setf (helixel-action-sel helixel--live-action) sel)
        (setf (helixel-action-op helixel--live-action) 'kill)
        (setf (helixel-action-payload helixel--live-action) '(:text "x")))
      (helixel-action-commit)
      ;; Dedup should prevent the push — ring still has 1 entry
      (should (= (length helixel--event-ring) 1)))))

(ert-deftest helixel-test-ring-commit-no-dedup-different-op ()
  "Different ops are NOT deduped."
  (let ((helixel--event-ring nil)
        (helixel--live-action nil)
        (helixel--last-tx nil))
    (helixel-test-with-buffer "hello world"
      (helixel--tracking-open 'movement 'char)
      (setf (helixel-action-op helixel--live-action) 'kill)
      (helixel-action-commit)
      (should (= (length helixel--event-ring) 1))
      (helixel--tracking-open 'movement 'char)
      (setf (helixel-action-op helixel--live-action) 'change)
      (helixel-action-commit)
      ;; Different op — no dedup
      (should (= (length helixel--event-ring) 2)))))

(ert-deftest helixel-test-ring-commit-dedup-different-sel ()
  "Events with different sel but same op/payload are still deduped\n(sel content is compared via `helixel-sel-equal-p')."
  (let ((helixel--event-ring nil)
        (helixel--live-action nil)
        (helixel--last-tx nil))
    (helixel-test-with-buffer "hello world"
      (helixel--tracking-open 'movement 'char)
      (let ((sel (helixel-sel-create 'line '(:dir forward :count 2))))
        (setf (helixel-action-sel helixel--live-action) sel)
        (setf (helixel-action-op helixel--live-action) 'kill))
      (helixel-action-commit)
      (should (= (length helixel--event-ring) 1))
      ;; Different sel — should NOT be deduped
      (helixel--tracking-open 'movement 'char)
      (let ((sel (helixel-sel-create 'line '(:dir forward :count 1))))
        (setf (helixel-action-sel helixel--live-action) sel)
        (setf (helixel-action-op helixel--live-action) 'kill))
      (helixel-action-commit)
      (should (= (length helixel--event-ring) 2)))))

;;; Ring cap

(ert-deftest helixel-test-ring-cap ()
  "Event ring respects `helixel-action-ring-max' truncation."
  (let ((helixel--event-ring nil)
        (helixel--live-action nil)
        (helixel--last-tx nil)
        (helixel-action-ring-max 3))
    (helixel-test-with-buffer "hello"
      (dotimes (i 5)
        (helixel--tracking-open 'movement 'char)
        (setf (helixel-action-op helixel--live-action) 'forward-char)
        (setf (helixel-action-payload helixel--live-action) `(:n ,i))
        (helixel-action-commit))
      (should (<= (length helixel--event-ring) 3))
      ;; Most recent entries are kept (front of ring)
      (should (= (plist-get (helixel-action-payload (nth 0 helixel--event-ring)) :n)
                 4))
      (should (= (plist-get (helixel-action-payload (nth 1 helixel--event-ring)) :n)
                 3))
      (should (= (plist-get (helixel-action-payload (nth 2 helixel--event-ring)) :n)
                 2)))))

(ert-deftest helixel-test-ring-cap-marker-cleanup ()
  "Evicted entries have their markers released."
  (let ((helixel--event-ring nil)
        (helixel--live-action nil)
        (helixel--last-tx nil)
        (helixel-action-ring-max 1))
    (helixel-test-with-buffer "hello"
      (helixel--tracking-open 'movement 'char)
      (let ((m1 (car (helixel-action-mark-region helixel--live-action))))
        (should (marker-buffer m1))
        (helixel-action-commit))
      ;; Push second entry — first is evicted
      (helixel--tracking-open 'movement 'line)
      (let ((m2 (car (helixel-action-mark-region helixel--live-action))))
        (should (marker-buffer m2))
        (helixel-action-commit))
      (should (= (length helixel--event-ring) 1)))))

;;; Global jump log

(ert-deftest helixel-test-ring-jump-log-push ()
  "Event commit also pushes to global jump log."
  (let ((helixel--event-ring nil)
        (helixel--live-action nil)
        (helixel--last-tx nil)
        (helixel--global-jump-log nil)
        (helixel--jump-pos nil))
    (helixel-test-with-buffer "hello world"
      (helixel--tracking-open 'movement 'char)
      (helixel-action-commit)
      (should helixel--global-jump-log)
      (should (= (length helixel--global-jump-log) 1)))))

(ert-deftest helixel-test-ring-jump-log-dedup ()
  "Jump log deduplicates on same content (same category + marker position)."
  (let ((helixel--event-ring nil)
        (helixel--live-action nil)
        (helixel--last-tx nil)
        (helixel--global-jump-log nil)
        (helixel--jump-pos nil))
    (helixel-test-with-buffer "hello world"
      (goto-char 3)
      (helixel--tracking-open 'movement 'char)
      (helixel-action-commit)
      (should (= (length helixel--global-jump-log) 1))
      ;; Same position, same category → dedup
      (goto-char 3)
      (helixel--tracking-open 'movement 'char)
      (helixel-action-commit)
      (should (= (length helixel--global-jump-log) 1))
      ;; Different position → no dedup
      (goto-char 7)
      (helixel--tracking-open 'movement 'char)
      (helixel-action-commit)
      (should (= (length helixel--global-jump-log) 2)))))

(provide 'helixel-test-ring)
;;; helixel-test-ring.el ends here
