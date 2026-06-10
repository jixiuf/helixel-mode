;;; helixel-test-cycle.el --- Tests for ; action cycle  -*- lexical-binding: t; -*-

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

;; Tests for ; cycle behavior:
;;   - newest-for-mark (edit by default)
;;   - subcategory filtering in helixel-action-cycle-categories
;;   - mark-region preservation in live-action-set
;;   - kill (d) excluded from default cycle-categories
;;   - copy (y) mark-region set

;;; Code:

(require 'ert)
(require 'helixel)
(require 'helixel-core)
(require 'helixel-ring)
(require 'helixel-editing)
(require 'helixel-macros)
(require 'helixel-test-common)

;; ---------------------------------------------------------------------------
;; helixel-action--newest-for-mark-p
;; ---------------------------------------------------------------------------

(ert-deftest helixel-test-cycle-newest-for-mark-p-edit ()
  "newest-for-mark-p returns t for edit events by default."
  (should (helixel-action--newest-for-mark-p
           (make-helixel-action :category 'edit :subcat 'paste-after))))

(ert-deftest helixel-test-cycle-newest-for-mark-p-movement ()
  "newest-for-mark-p returns nil for movement events by default."
  (should-not (helixel-action--newest-for-mark-p
               (make-helixel-action :category 'movement :subcat 'word))))

(ert-deftest helixel-test-cycle-newest-for-mark-p-subcat-match ()
  "newest-for-mark-p respects (CATEGORY . SUBCAT) pairs."
  (let ((helixel-action-cycle-newest-for-mark
         '((edit . paste-after))))
    (should (helixel-action--newest-for-mark-p
             (make-helixel-action :category 'edit :subcat 'paste-after)))
    (should-not (helixel-action--newest-for-mark-p
                 (make-helixel-action :category 'edit :subcat 'paste-before)))))

(ert-deftest helixel-test-cycle-newest-for-mark-p-nil ()
  "newest-for-mark-p returns nil when defcustom is nil."
  (let ((helixel-action-cycle-newest-for-mark nil))
    (should-not (helixel-action--newest-for-mark-p
                 (make-helixel-action :category 'edit :subcat 'paste-after)))))

;; ---------------------------------------------------------------------------
;; helixel-action-cycle-categories subcat filtering
;; ---------------------------------------------------------------------------

(ert-deftest helixel-test-cycle-categories-default-excludes-kill ()
  "Default helixel-action-cycle-categories excludes kill (d)."
  (should-not (helixel-action--cycle-visible-p
               (make-helixel-action :category 'edit :subcat 'kill))))

(ert-deftest helixel-test-cycle-categories-default-includes-paste ()
  "Default helixel-action-cycle-categories includes paste-after."
  (should (helixel-action--cycle-visible-p
           (make-helixel-action :category 'edit :subcat 'paste-after))))

(ert-deftest helixel-test-cycle-categories-default-includes-copy ()
  "Default helixel-action-cycle-categories includes copy (y)."
  (should (helixel-action--cycle-visible-p
           (make-helixel-action :category 'edit :subcat 'copy))))

(ert-deftest helixel-test-cycle-categories-subcat-pair ()
  "helixel-action-cycle-categories respects (CATEGORY . SUBCAT) pairs."
  (let ((helixel-action-cycle-categories
         '((edit . paste-after) (edit . replace))))
    (should (helixel-action--cycle-visible-p
             (make-helixel-action :category 'edit :subcat 'paste-after)))
    (should (helixel-action--cycle-visible-p
             (make-helixel-action :category 'edit :subcat 'replace)))
    (should-not (helixel-action--cycle-visible-p
                 (make-helixel-action :category 'edit :subcat 'copy)))
    (should-not (helixel-action--cycle-visible-p
                 (make-helixel-action :category 'movement :subcat 'word)))))

;; ---------------------------------------------------------------------------
;; helixel--live-action-set preserves non-degenerate mark-region
;; ---------------------------------------------------------------------------

(ert-deftest helixel-test-cycle-live-action-set-preserves-mark-region ()
  "live-action-set does not overwrite a deliberately-set mark-region."
  (let ((helixel--live-action nil)
        (helixel--last-tx nil)
        (helixel--action-ring nil))
    (unwind-protect
        (helixel-test-with-buffer "hello world"
				  (helixel--tracking-open 'edit 'paste-after)
				  (helixel--set-mark-region
				   (cons (save-excursion (goto-char 1) (point))
					 (save-excursion (goto-char 5) (point))))
				  (let ((old-mr (helixel-action-mark-region helixel--live-action)))
				    (let* ((tx (helixel-action-create 'paste-after nil
								      :runner (lambda (_) nil))))
				      (helixel--live-action-set tx))
				    (let ((mr (helixel-action-mark-region helixel--live-action)))
				      (should mr)
				      (should (consp mr))
				      (should (= (marker-position (car mr)) 1))
				      (should (= (marker-position (cdr mr)) 5)))))
      (setq helixel--live-action nil))))

;; ---------------------------------------------------------------------------
;; helixel-action--cycle-mark-group-span
;; ---------------------------------------------------------------------------

(ert-deftest helixel-test-cycle-mark-group-span-basic ()
  "cycle-mark-group-span marks from group-start begin to newest end."
  (let ((helixel--action-ring nil))
    (unwind-protect
        (helixel-test-with-buffer "abcdefghij"
				  (let ((ev1 (make-helixel-action
					      :category 'edit :subcat 'paste-after
					      :mark-region
					      (cons (set-marker (make-marker) 2)
						    (set-marker (make-marker) 4)))))
				    (let ((ev2 (make-helixel-action
						:category 'edit :subcat 'paste-after
						:mark-region
						(cons (set-marker (make-marker) 6)
						      (set-marker (make-marker) 8)))))
				      (setq helixel--action-ring (list ev2 ev1))
				      (goto-char 10)
				      (let ((gpos (helixel-action--cycle-mark-group-span
						   helixel--action-ring 0)))
					(should (= (mark t) 2))
					(should (= (point) 8))
					(should (region-active-p))
					(should (= gpos 1))
					;; Clean up markers
					(set-marker (car (helixel-action-mark-region ev1)) nil)
					(set-marker (cdr (helixel-action-mark-region ev1)) nil)
					(set-marker (car (helixel-action-mark-region ev2)) nil)
					(set-marker (cdr (helixel-action-mark-region ev2)) nil)))))
  (setq helixel--action-ring nil))))

;; ---------------------------------------------------------------------------
;; Integration: ; after paste selects newest then full group
;; ---------------------------------------------------------------------------

;; ---------------------------------------------------------------------------
;; After y (copy), ; re-selects copied region
;; ---------------------------------------------------------------------------

(ert-deftest helixel-test-cycle-copy-sets-mark-region ()
  "After y, the event mark-region covers the copied text."
  (let ((helixel--action-ring nil)
        (helixel--live-action nil))
    (unwind-protect
        (helixel-test-with-buffer "hello world"
				  (push-mark (point) t t)
				  (goto-char 6)
				  (setq helixel--sel-type-override nil)
				  (let ((this-command 'helixel-kill-ring-save))
				    (helixel-kill-ring-save))
				  (should helixel--action-ring)
				  (let ((mr (helixel-action-mark-region
					     (car helixel--action-ring))))
				    (should mr)
				    (should (consp mr))
				    (should (> (marker-position (cdr mr))
					       (marker-position (car mr))))
				    (should (string= (buffer-substring (marker-position (car mr))
								       (marker-position (cdr mr)))
						     "hello"))))
      (setq helixel--action-ring nil)
      (setq helixel--live-action nil))))

;; ---------------------------------------------------------------------------
;; After d (kill), mark-region is degenerate
;; ---------------------------------------------------------------------------

(ert-deftest helixel-test-cycle-kill-mark-region-degenerate ()
  "After d, the committed event has a degenerate mark-region."
  (let ((helixel--action-ring nil)
        (helixel--live-action nil))
    (unwind-protect
        (helixel-test-with-buffer "hello world"
				  (push-mark (point) t t)
				  (goto-char 6)
				  (setq helixel--sel-type-override nil)
				  (helixel--tracking-open 'edit 'kill)
				  (let* ((tx (helixel-action-create 'kill nil
								    :runner (lambda (_) nil))))
				    (helixel--live-action-set tx)
				    (helixel-action-commit))
				  (should helixel--action-ring)
				  (let ((mr (helixel-action-mark-region
					     (car helixel--action-ring))))
				    (should mr)
				    (should (consp mr))
				    (should (= (marker-position (car mr))
					       (marker-position (cdr mr))))))
      (setq helixel--action-ring nil)
      (setq helixel--live-action nil))))

;; ---------------------------------------------------------------------------
;; Subcat pair: (edit . paste-after) in newest-for-mark
;; ---------------------------------------------------------------------------

(ert-deftest helixel-test-cycle-newest-for-mark-subcat ()
  "Subcat-level newest-for-mark: only paste-after, not paste-before."
  (let ((helixel-action-cycle-newest-for-mark
         '((edit . paste-after))))
    (should (helixel-action--newest-for-mark-p
             (make-helixel-action :category 'edit :subcat 'paste-after)))
    (should-not (helixel-action--newest-for-mark-p
                 (make-helixel-action :category 'edit :subcat 'paste-before)))
    (should-not (helixel-action--newest-for-mark-p
                 (make-helixel-action :category 'edit :subcat 'replace)))))

(provide 'helixel-test-cycle)
;;; helixel-test-cycle.el ends here
