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
        (helixel--last-action nil)
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

;; ── `C-;' jump cycle tests ──

(ert-deftest helixel-test-jump-cycle-first-press ()
  "First `C-;' shows ring\=[0] and sets jump-cycle-pos."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--jump-cycle-pos nil helixel--action-pos nil)
    (insert "hello world")
    (deactivate-mark)
    (goto-char 1)
    (helixel-forward-word-start)
    (helixel-action-cycle-jump)
    (should helixel--jump-cycle-pos)
    (should (region-active-p))))

(ert-deftest helixel-test-jump-cycle-empty-ring ()
  "`C-;' on empty ring shows a message."
  (with-temp-buffer
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--jump-cycle-pos nil)
    (helixel-action-cycle-jump)
    (should-not helixel--jump-cycle-pos)))

(ert-deftest helixel-test-semicolon-always-mark-thing ()
  "`;' always does mark-thing on first press regardless of category."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--action-pos nil)
    (insert "hello world")
    (deactivate-mark)
    (goto-char 1)
    (helixel-forward-word-start)
    ;; ; should mark the full thing (the word we moved into)
    (helixel-action-cycle)
    (should (region-active-p))
    (should helixel--action-pos)))

(ert-deftest helixel-test-jump-cycle-live-action ()
  "`C-;' commits live action before showing ring\=[0]."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--jump-cycle-pos nil helixel--action-pos nil)
    (insert "hello world")
    (deactivate-mark)
    (goto-char 1)
    (helixel-forward-word-start)
    (should helixel--live-action)
    (helixel-action-cycle-jump)
    ;; Live action should be committed, ring should have 1 entry
    (should-not helixel--live-action)
    (should (= (length helixel--action-ring) 1))
    (should helixel--jump-cycle-pos)))

(ert-deftest helixel-test-jump-cycle-second-press ()
  "Second `C-;' advances or shows group-span without error."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--jump-cycle-pos nil helixel--action-pos nil)
    (insert "hello world")
    (deactivate-mark)
    (goto-char 1)
    (helixel-forward-word-start)
    (goto-char 1)
    (helixel-forward-WORD-start)  ;; different subcat — no group
    ;; First C-; commits live → 2 ring entries
    (helixel-action-cycle-jump)
    (should (= (length helixel--action-ring) 2))
    (should helixel--jump-cycle-pos)
    (should (region-active-p))
    ;; Second C-; should not error (may advance or show group-span)
    (deactivate-mark)
    (helixel-action-cycle-jump)
    (should (region-active-p))))

(ert-deftest helixel-test-jump-cycle-c-u-prefix ()
  "`C-u C-;' returns to live action or shows \"At newest\" without error."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--jump-cycle-pos nil helixel--action-pos nil)
    (insert "hello world")
    (deactivate-mark)
    (goto-char 1)
    (helixel-forward-word-start)
    ;; First C-; commits and shows the event.
    (helixel-action-cycle-jump)
    (should (= (length helixel--action-ring) 1))
    (should helixel--jump-cycle-pos)
    (should (region-active-p))
    ;; Now jump-cycle-pos is non-nil.  C-u C-; with a live action
    ;; returns to the live state and pushes mark.
    (deactivate-mark)
    (goto-char 1)
    (helixel-forward-word-start)  ;; new live action
    (helixel-action-cycle-jump 1)  ;; C-u C-; → shows live
    (should (region-active-p))))

(ert-deftest helixel-test-jump-cycle-independent-from-semicolon ()
  "`C-;' and `;' have independent cycle positions."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--jump-cycle-pos nil helixel--action-pos nil)
    (insert "hello world")
    (deactivate-mark)
    (goto-char 1)
    (helixel-forward-word-start)
    (goto-char 1)
    (helixel-forward-word-start)
    ;; Press ; twice to advance
    (helixel-action-cycle)
    (helixel-action-cycle)
    (let ((semicolon-pos helixel--action-pos))
      ;; Press C-; — should start from beginning, not from ;'s position
      (setq last-command nil)  ;; force reset
      (helixel-action-cycle-jump)
      (should helixel--jump-cycle-pos)
      ;; ;'s position should be unchanged
      (should (equal helixel--action-pos semicolon-pos)))))

(ert-deftest helixel-test-jump-cycle-uses-start-point ()
  "`C-;' pushes mark to start-point, not mark-region car."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--jump-cycle-pos nil helixel--action-pos nil)
    (insert "hello world")
    (deactivate-mark)
    (goto-char 4)  ;; between two l's
    (helixel-forward-word-start)  ;; moves to "world" start (pos 7)
    ;; Live action exists with start-point at pos 4.
    ;; mark-region car = thing-start of "hello" (pos 1).
    (should helixel--live-action)
    (should (helixel-action-start-point helixel--live-action))
    (let ((sp-pos (marker-position
                   (helixel-action-start-point helixel--live-action))))
      (should (= sp-pos 4)))  ;; original cursor, not thing-start
    ;; C-; commits live action and pushes mark to start-point.
    (helixel-action-cycle-jump)
    (should (region-active-p))
    ;; Region begins at start-point (=4), not thing-start (=1).
    (should (= (region-beginning) 4))))

(ert-deftest helixel-test-jump-cycle-multi-event-group ()
  "`C-;' handles multi-event groups using group-start's start-point."
  (with-temp-buffer
    (transient-mark-mode 1)
    (setq helixel--action-ring nil helixel--live-action nil
          helixel--jump-cycle-pos nil helixel--action-pos nil)
    (insert "hello world")
    (deactivate-mark)
    (goto-char 4)  ;; between two l's
    (helixel-forward-word-start)  ;; first w: pos4 → pos7, mark-region=(1 . 7)
    (helixel-forward-word-start)  ;; second w: pos7 → pos12, mark-region=(7 . 12)
    ;; Two events form a group (movement.word).
    ;; group-span-mr = (1 . 12), group-start is the first event.
    ;; For C-;, mr car should be group-start's start-point (=4), not thing-start (=1).
    (helixel-action-cycle-jump)
    (should (region-active-p))
    ;; Region begins at original cursor position (4), not at "hello" start (1)
    (should (= (region-beginning) 4))))

(provide 'helixel-test-cycle)
;;; helixel-test-cycle.el ends here
