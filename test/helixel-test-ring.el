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
  "`helixel-edit-commit' pushes live-event to ring and sets last-event."
  (let ((helixel--event-ring nil)
        (helixel--live-edit nil)
        (helixel--last-edit nil))
    (helixel-test-with-buffer "hello world"
      (helixel--tracking-open 'movement 'char)
      (let ((entry (helixel-edit-commit)))
        (should entry)
        (should (helixel-edit-p entry))
        (should (= (length helixel--event-ring) 1))
        (should (eq (car helixel--event-ring) helixel--last-edit))
        (should (eq entry helixel--last-edit))
        (should (null helixel--live-edit))))))

(ert-deftest helixel-test-ring-commit-nil-live ()
  "`helixel-edit-commit' with nil live-event returns nil."
  (let ((helixel--event-ring nil)
        (helixel--live-edit nil)
        (helixel--last-edit nil))
    (should (null (helixel-edit-commit)))
    (should (null helixel--event-ring))
    (should (null helixel--last-edit))))

(ert-deftest helixel-test-ring-commit-sets-last-event ()
  "After commit, `helixel--last-edit' points to committed entry."
  (let ((helixel--event-ring nil)
        (helixel--live-edit nil)
        (helixel--last-edit nil))
    (helixel-test-with-buffer "hello world"
      (helixel--tracking-open 'movement 'line)
      (let ((e1 (helixel-edit-commit)))
        (should e1)
        (should (eq helixel--last-edit e1))
        (helixel--tracking-open 'movement 'char)
        (let ((e2 (helixel-edit-commit)))
          (should e2)
          (should (eq helixel--last-edit e2))
          (should (not (eq e1 e2)))
          (should (= (length helixel--event-ring) 2)))))))

;;; Dedup

(ert-deftest helixel-test-ring-commit-dedup ()
  "Committing same event twice in a row pushes only once."
  (let ((helixel--event-ring nil)
        (helixel--live-edit nil)
        (helixel--last-edit nil))
    (helixel-test-with-buffer "hello world"
      (helixel--tracking-open 'movement 'char)
      (let ((sel (helixel-sel-create 'line '(:dir forward :count 1)
                   #'ignore "L")))
        (setf (helixel-edit-sel helixel--live-edit) sel)
        (setf (helixel-edit-op helixel--live-edit) 'kill)
        (setf (helixel-edit-payload helixel--live-edit) '(:text "x")))
      (helixel-edit-commit)
      (should (= (length helixel--event-ring) 1))
      ;; Re-create identical live-event and commit again
      (helixel--tracking-open 'movement 'char)
      (let ((sel (helixel-sel-create 'line '(:dir forward :count 1)
                   #'ignore "L")))
        (setf (helixel-edit-sel helixel--live-edit) sel)
        (setf (helixel-edit-op helixel--live-edit) 'kill)
        (setf (helixel-edit-payload helixel--live-edit) '(:text "x")))
      (helixel-edit-commit)
      ;; Dedup should prevent the push — ring still has 1 entry
      (should (= (length helixel--event-ring) 1)))))

(ert-deftest helixel-test-ring-commit-no-dedup-different-op ()
  "Different ops are NOT deduped."
  (let ((helixel--event-ring nil)
        (helixel--live-edit nil)
        (helixel--last-edit nil))
    (helixel-test-with-buffer "hello world"
      (helixel--tracking-open 'movement 'char)
      (setf (helixel-edit-op helixel--live-edit) 'kill)
      (helixel-edit-commit)
      (should (= (length helixel--event-ring) 1))
      (helixel--tracking-open 'movement 'char)
      (setf (helixel-edit-op helixel--live-edit) 'change)
      (helixel-edit-commit)
      ;; Different op — no dedup
      (should (= (length helixel--event-ring) 2)))))

(ert-deftest helixel-test-ring-commit-dedup-different-sel ()
  "Events with different sel but same op/payload are still deduped\n(sel content is compared via `helixel-sel-equal-p')."
  (let ((helixel--event-ring nil)
        (helixel--live-edit nil)
        (helixel--last-edit nil))
    (helixel-test-with-buffer "hello world"
      (helixel--tracking-open 'movement 'char)
      (let ((sel (helixel-sel-create 'line '(:dir forward :count 2)
                   #'ignore "L")))
        (setf (helixel-edit-sel helixel--live-edit) sel)
        (setf (helixel-edit-op helixel--live-edit) 'kill))
      (helixel-edit-commit)
      (should (= (length helixel--event-ring) 1))
      ;; Different sel — should NOT be deduped
      (helixel--tracking-open 'movement 'char)
      (let ((sel (helixel-sel-create 'line '(:dir forward :count 1)
                   #'ignore "L")))
        (setf (helixel-edit-sel helixel--live-edit) sel)
        (setf (helixel-edit-op helixel--live-edit) 'kill))
      (helixel-edit-commit)
      (should (= (length helixel--event-ring) 2)))))

;;; Ring cap

(ert-deftest helixel-test-ring-cap ()
  "Event ring respects `helixel-edit-ring-max' truncation."
  (let ((helixel--event-ring nil)
        (helixel--live-edit nil)
        (helixel--last-edit nil)
        (helixel-edit-ring-max 3))
    (helixel-test-with-buffer "hello"
      (dotimes (i 5)
        (helixel--tracking-open 'movement 'char)
        (setf (helixel-edit-op helixel--live-edit) 'forward-char)
        (setf (helixel-edit-payload helixel--live-edit) `(:n ,i))
        (helixel-edit-commit))
      (should (<= (length helixel--event-ring) 3))
      ;; Most recent entries are kept (front of ring)
      (should (= (plist-get (helixel-edit-payload (nth 0 helixel--event-ring)) :n)
                 4))
      (should (= (plist-get (helixel-edit-payload (nth 1 helixel--event-ring)) :n)
                 3))
      (should (= (plist-get (helixel-edit-payload (nth 2 helixel--event-ring)) :n)
                 2)))))

(ert-deftest helixel-test-ring-cap-marker-cleanup ()
  "Evicted entries have their markers released."
  (let ((helixel--event-ring nil)
        (helixel--live-edit nil)
        (helixel--last-edit nil)
        (helixel-edit-ring-max 1))
    (helixel-test-with-buffer "hello"
      (helixel--tracking-open 'movement 'char)
      (let ((m1 (car (helixel-edit-mark-region helixel--live-edit))))
        (should (marker-buffer m1))
        (helixel-edit-commit))
      ;; Push second entry — first is evicted
      (helixel--tracking-open 'movement 'line)
      (let ((m2 (car (helixel-edit-mark-region helixel--live-edit))))
        (should (marker-buffer m2))
        (helixel-edit-commit))
      (should (= (length helixel--event-ring) 1)))))

;;; Global jump log

(ert-deftest helixel-test-ring-jump-log-push ()
  "Event commit also pushes to global jump log."
  (let ((helixel--event-ring nil)
        (helixel--live-edit nil)
        (helixel--last-edit nil)
        (helixel--global-jump-log nil)
        (helixel--jump-pos nil))
    (helixel-test-with-buffer "hello world"
      (helixel--tracking-open 'movement 'char)
      (helixel-edit-commit)
      (should helixel--global-jump-log)
      (should (= (length helixel--global-jump-log) 1)))))

(ert-deftest helixel-test-ring-jump-log-dedup ()
  "Jump log deduplicates on same content (same category + marker position)."
  (let ((helixel--event-ring nil)
        (helixel--live-edit nil)
        (helixel--last-edit nil)
        (helixel--global-jump-log nil)
        (helixel--jump-pos nil))
    (helixel-test-with-buffer "hello world"
      (goto-char 3)
      (helixel--tracking-open 'movement 'char)
      (helixel-edit-commit)
      (should (= (length helixel--global-jump-log) 1))
      ;; Same position, same category → dedup
      (goto-char 3)
      (helixel--tracking-open 'movement 'char)
      (helixel-edit-commit)
      (should (= (length helixel--global-jump-log) 1))
      ;; Different position → no dedup
      (goto-char 7)
      (helixel--tracking-open 'movement 'char)
      (helixel-edit-commit)
      (should (= (length helixel--global-jump-log) 2)))))

(provide 'helixel-test-ring)
;;; helixel-test-ring.el ends here
