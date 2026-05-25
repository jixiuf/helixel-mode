;;; helixel-test-edit.el --- Tests for Helixel: edit transactions and dot-repeat  -*- lexical-binding: t; -*-

;; Copyright (C) 2025  jixiuf

;; Author: jixiuf
;; Keywords: tests
;; Version: 0
;; URL: https://github.com/jixiuf/helixel-mode

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

;; Helixel tests.

;;; Code:

(require 'ert)
(require 'helixel)


(require 'ert)
(require 'helixel)

;;; Repeat Edit tests

;; ---------------------------------------------------------------------------
;; helixel-sel struct API tests

(ert-deftest helixel-test-sel-create-basic ()
  "`helixel-sel-create' builds a valid struct."
  (let ((sel (helixel-sel-create 'line '(:count 3)
                                 (lambda (_) nil)
                                 "L")))
    (should (helixel-sel-p sel))
    (should (eq (helixel-sel--kind sel) 'line))
    (should (equal (helixel-sel--ctx sel) '(:count 3)))
    (should (string= (helixel-sel--display sel) "L"))))

(ert-deftest helixel-test-sel-get-kind ()
  "`helixel-sel-get-kind' works for struct."
  (let ((struct (helixel-sel-create 'line nil (lambda (_) nil))))
    (should (eq (helixel-sel-get-kind struct) 'line))
    (should (eq (helixel-sel-get-kind (helixel-sel-create 'rect '(:count 2) #'helixel--recreate-rect "r")) 'rect))
    (should (null (helixel-sel-get-kind nil)))))

(ert-deftest helixel-test-sel-get-field ()
  "`helixel-sel-get-field' extracts from ctx."
  (let ((struct (helixel-sel-create 'line '(:count 3 :dir backward)
                                    (lambda (_) nil))))
    (should (= (helixel-sel-get-field struct :count) 3))
    (should (eq (helixel-sel-get-field struct :dir) 'backward))
    (should (null (helixel-sel-get-field struct :missing)))
    (should (null (helixel-sel-get-field nil :count)))
    (should (= (helixel-sel-get-field (helixel-sel-create 'line '(:count 5) #'helixel--recreate-line "L") :count) 5))))

(ert-deftest helixel-test-sel-count ()
  "`helixel-sel-count' returns :count from ctx or 0."
  (let ((sel (helixel-sel-create 'line '(:count 3) (lambda (_) nil))))
    (should (= (helixel-sel-count sel) 3)))
  (let ((sel (helixel-sel-create 'line nil (lambda (_) nil))))
    (should (= (helixel-sel-count sel) 0)))
  (should (= (helixel-sel-count nil) 0))
  (should (= (helixel-sel-count (helixel-sel-create 'line '(:count 7) #'helixel--recreate-line "L")) 7)))

(ert-deftest helixel-test-sel-update-ctx ()
  "`helixel-sel-update-ctx' returns a new sel with updated ctx."
  (let* ((s1 (helixel-sel-create 'line '(:count 3) (lambda (_) nil)))
         (s2 (helixel-sel-update-ctx s1 :count 5)))
    (should (= (helixel-sel-get-field s1 :count) 3))
    (should (= (helixel-sel-get-field s2 :count) 5))
    (should (helixel-sel-p s2))
    (should (eq (helixel-sel--kind s2) 'line))
    (let ((p2 (helixel-sel-update-ctx (helixel-sel-create 'line '(:count 1) #'helixel--recreate-line "L") :count 9)))
      (should (equal p2 (helixel-sel-create 'line '(:count 9) #'helixel--recreate-line "L"))))))

(ert-deftest helixel-test-sel-equal-p ()
  "`helixel-sel-equal-p' compares kind and ctx."
  (let ((a (helixel-sel-create 'line '(:count 3) (lambda (_) nil)))
        (b (helixel-sel-create 'line '(:count 3) (lambda (_) nil)))
        (c (helixel-sel-create 'line '(:count 5) (lambda (_) nil)))
        (d (helixel-sel-create 'rect '(:count 3) (lambda (_) nil))))
    (should (helixel-sel-equal-p a b))
    (should-not (helixel-sel-equal-p a c))
    (should-not (helixel-sel-equal-p a d))
    (should (helixel-sel-equal-p nil nil))
    (should-not (helixel-sel-equal-p a nil))
    (should (helixel-sel-equal-p (helixel-sel-create 'line '(:count 3) #'helixel--recreate-line "L")
                                 (helixel-sel-create 'line '(:count 3) #'helixel--recreate-line "L")))
    (should-not (helixel-sel-equal-p (helixel-sel-create 'line '(:count 3) #'helixel--recreate-line "L")
                                     (helixel-sel-create 'rect '(:count 3) #'helixel--recreate-rect "r")))))

(ert-deftest helixel-test-sel-call-recreate ()
  "`helixel-sel-call-recreate' dispatches to struct closure."
  (with-temp-buffer
    (insert "hello world")
    (goto-char 1)
    (let ((sel (helixel-sel-create 'line nil
                                   (lambda (_) (goto-char 7))
                                   "L")))
      (helixel-sel-call-recreate sel)
      (should (= (point) 7)))
    (let ((pt (point)))
      (helixel-sel-call-recreate nil)
      (should (= (point) pt)))))

(ert-deftest helixel-test-sel-call-display ()
  "`helixel-sel-call-display' returns display string for struct."
  (should (string= (helixel-sel-call-display
                    (helixel-sel-create 'line nil (lambda (_) nil) "L"))
                   "L"))
  (should (string= (helixel-sel-call-display (helixel-sel-create 'line '(:count 3) #'helixel--recreate-line "L"))
                   "L"))
  (should (null (helixel-sel-call-display nil))))

;; ---------------------------------------------------------------------------
;; insert-* sel structs (was raw plists, now proper structs)

(ert-deftest helixel-test-sel-insert-selection-start ()
  "insert-selection-start sel struct: kind, recreate, display."
  (let ((sel (helixel-sel-create
              'insert-selection-start nil
              #'helixel--recreate-insert-selection-start "is")))
    (should (eq (helixel-sel-get-kind sel) 'insert-selection-start))
    (should (string= (helixel-sel-call-display sel) "is"))
    (should (helixel-sel-p sel))))

(ert-deftest helixel-test-sel-insert-selection-end ()
  "insert-selection-end sel struct: kind, recreate, display."
  (let ((sel (helixel-sel-create
              'insert-selection-end nil
              #'helixel--recreate-insert-selection-end "ie")))
    (should (eq (helixel-sel-get-kind sel) 'insert-selection-end))
    (should (string= (helixel-sel-call-display sel) "ie"))
    (should (helixel-sel-p sel))))

(ert-deftest helixel-test-sel-insert-beginning-line ()
  "insert-beginning-line sel struct: kind, recreate, display."
  (let ((sel (helixel-sel-create
              'insert-beginning-line nil
              #'helixel--recreate-insert-beginning-line "I")))
    (should (eq (helixel-sel-get-kind sel) 'insert-beginning-line))
    (should (string= (helixel-sel-call-display sel) "I"))
    (should (helixel-sel-p sel))))

(ert-deftest helixel-test-sel-insert-end-line ()
  "insert-end-line sel struct: kind, recreate, display."
  (let ((sel (helixel-sel-create
              'insert-end-line nil
              #'helixel--recreate-insert-end-line "A")))
    (should (eq (helixel-sel-get-kind sel) 'insert-end-line))
    (should (string= (helixel-sel-call-display sel) "A"))
    (should (helixel-sel-p sel))))

(ert-deftest helixel-test-sel-insert-search-offset ()
  "insert-search-offset sel struct: kind, recreate, display."
  (let ((sel (helixel-sel-create
              'insert-search-offset '(:offset 3)
              #'helixel--recreate-insert-search-offset "io")))
    (should (eq (helixel-sel-get-kind sel) 'insert-search-offset))
    (should (string= (helixel-sel-call-display sel) "io"))
    (should (= (helixel-sel-insert-offset sel) 3))
    (should (helixel-sel-p sel))))

(ert-deftest helixel-test-recreate-insert-selection-start ()
  "recreate-insert-selection-start moves to region-beginning + offset."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (push-mark 6 t t)
    (activate-mark)
    (let ((sel (helixel-sel-update-ctx
                (helixel-sel-create
                 'insert-selection-start nil
                 #'helixel--recreate-insert-selection-start "is")
                :cursor-offset 2)))
      (helixel-sel-call-recreate sel)
      (should (= (point) 3)))))

(ert-deftest helixel-test-recreate-insert-selection-end ()
  "recreate-insert-selection-end moves to region-end + offset."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (push-mark 6 t t)
    (activate-mark)
    (let ((sel (helixel-sel-update-ctx
                (helixel-sel-create
                 'insert-selection-end nil
                 #'helixel--recreate-insert-selection-end "ie")
                :cursor-offset 1)))
      (helixel-sel-call-recreate sel)
      (should (= (point) 7)))))

(ert-deftest helixel-test-recreate-insert-beginning-line ()
  "recreate-insert-beginning-line moves to beginning of line."
  (helixel-test-with-buffer "hello\nworld"
    (goto-char 7)
    (let ((sel (helixel-sel-create
                'insert-beginning-line nil
                #'helixel--recreate-insert-beginning-line "I")))
      (helixel-sel-call-recreate sel)
      (should (= (point) 7)))))

(ert-deftest helixel-test-recreate-insert-end-line ()
  "recreate-insert-end-line moves to end of line."
  (helixel-test-with-buffer "hello\nworld"
    (goto-char 5)
    (let ((sel (helixel-sel-create
                'insert-end-line nil
                #'helixel--recreate-insert-end-line "A")))
      (helixel-sel-call-recreate sel)
      (should (= (point) 6)))))

(ert-deftest helixel-test-recreate-insert-search-offset ()
  "recreate-insert-search-offset moves to match-beginning + offset."
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (re-search-forward "hello")
    (let ((sel (helixel-sel-create
                'insert-search-offset '(:offset 2)
                #'helixel--recreate-insert-search-offset "io")))
      (helixel-sel-call-recreate sel)
      ;; match-beginning of first "hello" = 1, + 2 = 3
      (should (= (point) 3)))))

;; ---------------------------------------------------------------------------
;; edit transaction runner/display tests

(ert-deftest helixel-test-edit-make-stores-runner ()
  "`helixel--make-tx' stores :runner in the struct slot."
  (let ((dummy-fn #'ignore))
    (let ((tx (helixel--make-tx 'kill nil :runner dummy-fn)))
      (should (eq (helixel-event-runner tx) dummy-fn))
      (should (null (plist-get (helixel-event-payload tx) :runner))))))

(ert-deftest helixel-test-edit-make-stores-display ()
  "`helixel--make-tx' stores :display in DISPLAY-FIELD slot, not in :payload."
  (let ((tx (helixel--make-tx 'kill nil :display "d.K")))
    (should (string= (helixel-event-display tx) "d.K"))
    (should (null (plist-get (helixel-event-payload tx) :display)))))

(ert-deftest helixel-test-execute-edit-uses-stored-runner ()
  "`helixel--execute-edit' calls the :runner stored in TX."
  (with-temp-buffer
    (insert "hello")
    (goto-char 1)
    (let ((tx (helixel--make-tx 'test nil
                :runner (lambda (_tx) (insert "X")))))
      (helixel--execute-edit tx)
      (should (string= (buffer-string) "Xhello")))))

(ert-deftest helixel-test-execute-edit-fallback-registry ()
  "`helixel--execute-edit' falls back to registry when :runner missing."
  ;; kill op is registered; a plist without :runner should still
  ;; execute via the registry lookup fallback.
  (with-temp-buffer
    (insert "hello")
    (goto-char 2)  ; on "e"
    ;; Create a tx without :runner (tests registry fallback)
    (let ((tx (helixel--make-tx 'kill nil)))
      (should (helixel--op-runner 'kill)) ;; registry has runner
      ;; Should not error — just verify the fallback path runs
      (should (progn (helixel--execute-edit tx) t)))))

(ert-deftest helixel-test-edit-display-uses-stored-field ()
  "`helixel--tx-display' prefers :display stored in TX."
  (let ((tx (helixel--make-tx 'kill nil :display "custom-label")))
    (should (string= (helixel--tx-display tx) "custom-label"))))

(ert-deftest helixel-test-repeat-edit-no-prev ()
  "Test repeat-edit with no previous edit signals error."
  (helixel-test-with-buffer "hello world"
    (setq helixel--last-tx nil)
    (setq helixel--last-event nil)
    (should-error (helixel-repeat-edit))))

(ert-deftest helixel-test-repeat-edit-paste ()
  "Test repeat paste."
  (helixel-test-with-buffer "hello world"
    (goto-char 7)
    (kill-word 1)
    (setq last-command nil this-command 'helixel-yank)
    (helixel-yank)
    (should (string= (buffer-string) "hello world"))
    (goto-char 7)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "hello worldworld"))))

(ert-deftest helixel-test-repeat-edit-replace-char ()
  "Test repeat replace-char."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-replace-char)
    (helixel-replace-char ?X)
    (should (string= (buffer-string) "Xello world"))
    (goto-char 2)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "XXllo world"))))

(ert-deftest helixel-test-repeat-edit-indent ()
  "Test repeat indent right with line selection."
  (helixel-test-with-buffer "hello\nworld\n"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (setq last-command 'helixel-select-line this-command 'helixel-indent-right)
    (helixel-indent-right)
    (let ((after-first (buffer-string)))
      (should-not (string= "hello\nworld\n" after-first))
      (helixel-repeat-edit)
      (should-not (string= after-first (buffer-string))))))

(ert-deftest helixel-test-repeat-edit-kill-textobj ()
  "Test repeat kill with textobj selection (diw style)."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 3)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (string= (buffer-string) " world foo"))
    (goto-char 3)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "  foo"))))

(ert-deftest helixel-test-repeat-edit-kill-linewise ()
  "Test repeat kill with linewise selection (x d style)."
  (helixel-test-with-buffer "first line\nsecond line\nthird line\n"
    (goto-char 3)
    (setq last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (setq last-command 'helixel-select-line this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (string= (buffer-string) "second line\nthird line\n"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "third line\n"))))

(ert-deftest helixel-test-repeat-edit-change-textobj ()
  "Test repeat change with textobj (ciw style)."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 3)
    (setq helixel--last-tx
          (helixel--make-tx 'change
            (helixel-sel-create 'textobj '(:command helixel-mark-inner-word :count 1)
            #'helixel--recreate-textobj
            (replace-regexp-in-string "^helixel-mark-" "" (symbol-name 'helixel-mark-inner-word)))
            :inserted-text "CHANGED"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "CHANGED world foo"))
    (goto-char 1)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "CHANGED world foo"))))

(ert-deftest helixel-test-repeat-edit-preserves-last-edit ()
  "Test that repeat-edit does not overwrite helixel--last-tx."
  (helixel-test-with-buffer "hello world"
    (goto-char 7)
    (kill-word 1)
    (setq last-command nil this-command 'helixel-yank)
    (helixel-yank)
    (let ((before helixel--last-tx))
      (helixel-repeat-edit)
      (should (equal helixel--last-tx before)))))

(ert-deftest helixel-test-repeat-edit-clear-data ()
  "Test repeat-edit clears selection data after operation."
  (helixel-test-with-buffer "hello world"
    (goto-char 7)
    (kill-word 1)
    (setq last-command nil this-command 'helixel-yank)
    (helixel-yank)
    (helixel-repeat-edit)
    (should (null helixel--selection-type))))

(ert-deftest helixel-test-repeat-edit-copy ()
  "Test repeat copy (yank)."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word this-command 'helixel-kill-ring-save)
    (helixel-kill-ring-save)
    (should (string= (current-kill 0 t) "hello"))
    (goto-char 7)
    (helixel-repeat-edit)
    (should (string= (current-kill 0 t) "world"))))

(ert-deftest helixel-test-repeat-edit-insert-text ()
  "Test repeat insert-text (i style)."
  (helixel-test-with-buffer "hello world"
    (goto-char 7)
    (setq helixel--last-tx
          (helixel--make-tx 'insert-text nil :text "INSERTED"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "hello INSERTEDworld"))))

(ert-deftest helixel-test-repeat-edit-insert-text-empty ()
  "Test repeat insert-text with empty text does nothing."
  (helixel-test-with-buffer "hello world"
    (goto-char 7)
    (setq helixel--last-tx
          (helixel--make-tx 'insert-text nil :text ""))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "hello world"))))

(ert-deftest helixel-test-repeat-edit-count-prefix ()
  "Numeric prefix to `helixel-repeat-edit' replays N times."
  (helixel-test-with-buffer "hello world"
    (goto-char 7)
    (setq helixel--last-tx
          (helixel--make-tx 'insert-text nil :text "x"))
    (helixel-repeat-edit 5)
    (should (string= (buffer-string) "hello xxxxxworld"))))

(ert-deftest helixel-test-repeat-edit-preserves-on-error ()
  "`helixel-repeat-edit' does not discard `helixel--last-tx' on failure."
  (helixel-test-with-buffer "hello"
    (setq helixel--last-tx
          (helixel--make-tx 'kill (helixel-sel-create 'unknown-kind-no-method nil #'ignore "?")))
    (let ((before helixel--last-tx))
      (helixel-repeat-edit)
      (should (equal helixel--last-tx before)))))

(ert-deftest helixel-test-repeat-edit-change-end-to-end ()
  "End-to-end: c<text><esc> records inserted text; `.' replays it."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-change-thing-at-point)
    (helixel-change-thing-at-point)
    (insert "X")
    (helixel-insert-exit)
    (should (string= (buffer-string) "X world foo"))
    ;; Repeat inside "world"
    (goto-char 4)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "X X foo"))))

(ert-deftest helixel-test-repeat-edit-insert-end-to-end ()
  "End-to-end: i<text><esc> records inserted text; `.' replays it."
  (let ((helixel--last-tx nil)
        (helixel-repeat-change-method 'text))
    (helixel-test-with-buffer "abc"
      (set-match-data nil) ; clear stale match data from prior tests
      (goto-char 2)
      (setq last-command nil this-command 'helixel-insert)
      (helixel-insert)
      (insert "Z")
      (helixel-insert-exit)
      (should (string= (buffer-string) "aZbc"))
      (goto-char 4)
      (helixel-repeat-edit)
      (should (string= (buffer-string) "aZbZc")))))

(ert-deftest helixel-test-edit-ring-push-and-dedup ()
  "Edits are stored as :edit entries in the unified action ring.
The action ring stores all action types (textobj, edit, etc.);
eduplication is against the ring front by content."
  (helixel-test-with-buffer "hello world"
    (setq helixel--last-tx nil)
    (goto-char 1)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    ;; Edit should be accessible via event ring
    (should helixel--event-ring)
    (should helixel--last-tx)
    (should (helixel-event-p (car helixel--event-ring)))))

(ert-deftest helixel-test-edit-display ()
  "`helixel--tx-display' formats op + sel + payload hints."
  (should (string= (helixel--tx-display
                    (helixel--make-tx 'kill
                      (helixel-sel-create 'line '(:count 3)
                        #'helixel--recreate-line "L")))
                   "d.Lx3"))
  (should (string= (helixel--tx-display
                    (helixel--make-tx 'kill
                      (helixel-sel-create 'line '(:dir backward :count 2)
                        #'helixel--recreate-line "L^")))
                   "d.L^x2"))
  (should (string= (helixel--tx-display
                    (helixel--make-tx 'replace-char nil :char ?Q))
                   "R[Q]"))
  (should (string= (helixel--tx-display
                    (helixel--make-tx 'kill
                      (helixel-sel-create 'textobj
                        '(:command helixel-mark-inner-word :count 1)
                        #'helixel--recreate-textobj
                        "inner-word")))
                   "d.inner-word"))
  (should (string= (helixel--tx-display
                    (helixel--make-tx 'kill
                      (helixel-sel-create 'movement
                        '(:moves ((helixel-forward-word-start . 3)))
                        #'helixel--recreate-movement
                        "v3")))
                   "d.v3")))

(ert-deftest helixel-test-repeat-edit-movement-kill ()
  "Test repeat kill with movement selection (v w d style)."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel--make-tx 'kill
            (helixel-sel-create 'movement '(:moves ((helixel-forward-word-start . 2)))
            #'helixel--recreate-movement
            (format "v%d" 2))))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "foo"))))

(ert-deftest helixel-test-repeat-edit-movement-change ()
  "Test repeat change with movement selection (v w c style)."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel--make-tx 'change
            (helixel-sel-create 'movement '(:moves ((helixel-forward-word-start . 1)))
            #'helixel--recreate-movement
            (format "v%d" 1))
            :inserted-text "X"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "Xworld foo"))))

(ert-deftest helixel-test-repeat-invariant-sel-ctx-consumed ()
  "Test record-edit consumes helixel--pending-sel."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (should helixel--pending-sel)
    (setq last-command 'helixel-mark-inner-word this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (null helixel--pending-sel))))

(ert-deftest helixel-test-repeat-invariant-repeat-no-pollute-ring ()
  "Test repeat-edit does not add extra entries to the action ring beyond record-edit."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (let ((ring-len (length helixel--event-ring)))
      (helixel-repeat-edit)
      (should (= (length helixel--event-ring) ring-len)))))

(ert-deftest helixel-test-repeat-invariant-insert-after-records ()
  "Test helixel-insert-after (a) records insert-text."
  (helixel-test-with-buffer "hello world"
    (goto-char 3)
    (setq helixel--last-tx nil
          helixel--change-track-marker nil)
    (helixel-insert-after)
    (should (eq (helixel-event-op helixel--last-tx) 'insert-text))
    (should helixel--change-track-marker)
    (set-marker helixel--change-track-marker nil)
    (setq helixel--change-track-marker nil)))

(ert-deftest helixel-test-execute-keys-meta ()
  "`helixel--execute-keys' handles meta keys (e.g. M-f) gracefully.
Meta keys are non-character integers; they must go through
key-binding dispatch, not `insert-char'."
  (helixel-test-with-buffer ""
    (helixel--execute-keys (kbd "foo"))
    (should (string= (buffer-string) "foo")))
  (helixel-test-with-buffer "one two three"
    (goto-char 1)
    ;; M-f goes through key-binding -> forward-word
    (helixel--execute-keys (kbd "M-f"))
    (should (= (point) 4)))
  (helixel-test-with-buffer "one two three"
    (goto-char 1)
    ;; M-f mixed with character keys
    (helixel--execute-keys (kbd "a M-f b"))
    (should (string= (buffer-string) "aoneb two three"))))

(ert-deftest helixel-test-execute-keys-backspace ()
  "`helixel--execute-keys' replays DEL via `execute-kbd-macro'.
Key-based replay handles DEL (127) as non-printable."
  (helixel-test-with-buffer "hello"
    (goto-char 6)
    ;; A (65), DEL (127), x (120): DEL triggers delete-backward-char
    (helixel--execute-keys [65 127 120])
    (should (string= (buffer-string) "hellox"))))

(ert-deftest helixel-test-execute-keys-control-d ()
  "`helixel--execute-keys' replays C-d via `execute-kbd-macro'.
C-d is non-printable and dispatched through macro replay."
  (helixel-test-with-buffer "hello"
    (goto-char 1)
    (helixel--execute-keys (kbd "C-d"))
    (should (string= (buffer-string) "ello"))))

(ert-deftest helixel-test-execute-keys-mixed-backspace ()
  "`helixel--execute-keys' replays mixed insert + DEL + insert.
Simulates typing 'bao' then DEL (deletes 'o') then 'r'."
  (helixel-test-with-buffer "hello"
    (goto-char 6)
    ;; b, a, o, DEL (127), r: DEL triggers delete-backward-char
    (helixel--execute-keys [98 97 111 127 114])
    (should (string= (buffer-string) "hellobar"))))

(ert-deftest helixel-test-execute-keys-symbol-no-crash ()
  "`helixel--execute-keys' handles symbol keys without crashing.
Unbound symbols (like backspace on some Emacs) go through
`execute-kbd-macro' — may beep but must not raise
wrong-type-argument."
  (helixel-test-with-buffer "hello"
    (goto-char 1)
    (condition-case err
        (helixel--execute-keys [backspace])
      (wrong-type-argument
       (ert-fail
        (format "crashed with wrong-type-argument: %S" err)))
      (error nil))  ;; other errors (unbound key) are OK
    (should t)))

;; ============================================================================
;; Cross-buffer repeat tests (Item 5)
;; ============================================================================

(ert-deftest helixel-test-repeat-cross-buffer ()
  "`. replays the last edit across buffers when `helixel--last-tx' is global."
  (helixel-test-with-buffer "hello world"
    (goto-char 7)
    (kill-word 1)
    (setq last-command nil this-command 'helixel-yank)
    (helixel-yank)
    (should (string= (buffer-string) "hello world"))
    (let ((cross-tx helixel--last-tx))
      (with-temp-buffer
        (insert "foo bar")
        (goto-char 8)                   ; end of buffer, after "bar"
        (setq helixel--last-tx cross-tx)
        (helixel-repeat-edit)
        ;; "p" pastes the killed word "world" after "bar"
        (should (string= (buffer-string) "foo barworld"))))))

(ert-deftest helixel-test-repeat-cross-buffer-change ()
  "Cross-buffer `.` replays a change+insert operation from another buffer."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-mark-inner-word)
    (helixel-mark-inner-word)
    (setq last-command 'helixel-mark-inner-word
          this-command 'helixel-change-thing-at-point)
    (helixel-change-thing-at-point)
    (insert "X")
    (helixel-insert-exit)
    (should (string= (buffer-string) "X world"))
    (let ((cross-tx helixel--last-tx))
      (with-temp-buffer
        (insert "abc def")
        (goto-char 1)
        (setq helixel--last-tx cross-tx)
        (helixel-repeat-edit)
        (should (string= (buffer-string) "X def"))))))

;; ============================================================================
;; Keys-mode change replay tests (Item 4)
;; ============================================================================

(ert-deftest helixel-test-repeat-change-keys-mode ()
  "`helixel-repeat-change-method' = `keys' replays raw key sequence."
  (helixel-test-with-buffer "hello world"
    (let ((helixel-repeat-change-method 'keys))
      (goto-char 1)
      ;; Directly construct a tx with :keys payload, simulating
      ;; what c X Y <esc> would record.  The keys are only the
      ;; productive insert-mode keystrokes (X Y), not the initiating c.
      (setq helixel--last-tx
            (helixel--make-tx 'change
              (helixel-sel-create 'textobj '(:command helixel-mark-inner-word :count 1)
            #'helixel--recreate-textobj
            (replace-regexp-in-string "^helixel-mark-" "" (symbol-name 'helixel-mark-inner-word)))
              :inserted-text "XY" :keys (kbd "XY")))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "XY world"))
      ;; Replay in keys mode on another word
      (goto-char 4)
      (helixel-repeat-edit)
      (should (string= (buffer-string) "XY XY")))))

(ert-deftest helixel-test-repeat-insert-keys-mode ()
  "`helixel-repeat-change-method' = `keys' replays insert key sequence."
  (helixel-test-with-buffer "abc"
    (let ((helixel-repeat-change-method 'keys))
      (goto-char 2)
      ;; Directly construct a tx with :keys payload (simulating i Z <esc>)
      (setq helixel--last-tx
            (helixel--make-tx 'insert-text nil
              :text "Z" :keys (kbd "Z")))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "aZbc"))
      (should (helixel--repeat-get-keys helixel--last-tx))
      (goto-char 4)
      (helixel-repeat-edit)
      (should (string= (buffer-string) "aZbZc")))))

(ert-deftest helixel-test-repeat-keys-fallback-to-text ()
  "When :keys is absent from payload, keys-mode falls back to :text."
  (helixel-test-with-buffer "hello"
    (let ((helixel-repeat-change-method 'keys))
      (goto-char 1)
      ;; Manually construct a tx without :keys (old-format tx)
      (setq helixel--last-tx
            (helixel--make-tx 'insert-text nil :text "OLD"))
      (helixel-repeat-edit)
      (should (string= (buffer-string) "OLDhello")))))

(ert-deftest helixel-test-repeat-change-keys-preferred ()
  "`:keys' payload is always preferred over `:inserted-text'."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    ;; A tx with both :inserted-text and :keys — :keys wins
    (setq helixel--last-tx
          (helixel--make-tx 'change
            (helixel-sel-create 'textobj
              '(:command helixel-mark-inner-word :count 1)
              #'helixel--recreate-textobj
              (replace-regexp-in-string
               "^helixel-mark-" ""
               (symbol-name 'helixel-mark-inner-word)))
            :inserted-text "XY" :keys (kbd "ZZ")))
    (helixel-repeat-edit)
    ;; :keys "ZZ" is used, not :inserted-text "XY"
    (should (string= (buffer-string) "ZZ world"))
    (goto-char 4)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "ZZ ZZ"))))

;; ============================================================================
;; Repeat-selection (,`) tests
;; ============================================================================

(ert-deftest helixel-test-repeat-selection-textobj ()
  "`,` recreates the last textobj selection without applying the edit."
  (helixel-test-with-buffer "hello world"
    (goto-char 3)
    (setq helixel--last-tx
          (helixel--make-tx 'change
            (helixel-sel-create 'textobj '(:command helixel-mark-inner-word :count 1)
            #'helixel--recreate-textobj
            (replace-regexp-in-string "^helixel-mark-" "" (symbol-name 'helixel-mark-inner-word)))
            :inserted-text "X"))
    (helixel-repeat-selection)
    (should (region-active-p))
    (should (= (region-beginning) 1))
    (should (= (region-end) 6))))

(ert-deftest helixel-test-repeat-selection-line ()
  "`,` recreates a linewise selection without applying the edit."
  (helixel-test-with-buffer "line one\nline two\nline three\n"
    (goto-char 3)
    (setq helixel--last-tx
          (helixel--make-tx 'kill
            (helixel-sel-create 'line '(:count 1)
              #'helixel--recreate-line "L")))
    (helixel-repeat-selection)
    (should (region-active-p))
    (should (= (region-beginning) 1))))

(ert-deftest helixel-test-repeat-selection-count ()
  "`,` with count prefix selects multiple units."
  (helixel-test-with-buffer "line one\nline two\nline three\n"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel--make-tx 'kill (helixel-sel-create 'line '(:count 1) #'helixel--recreate-line "L")))
    (helixel-repeat-selection 2)
    (should (region-active-p))
    (should (= (region-beginning) 1))
    (should (>= (region-end) 1))))

(ert-deftest helixel-test-repeat-dot-on-existing-region ()
  "`.` on an active region (from `,`) uses it without recreating."
  (helixel-test-with-buffer "hello world"
    (goto-char 3)
    (setq helixel--last-tx
          (helixel--make-tx 'change
            (helixel-sel-create 'textobj '(:command helixel-mark-inner-word :count 1)
            #'helixel--recreate-textobj
            (replace-regexp-in-string "^helixel-mark-" "" (symbol-name 'helixel-mark-inner-word)))
            :inserted-text "X"))
    (helixel-repeat-selection)
    (helixel-repeat-edit)
    (should (string= (buffer-string) "X world"))))

(ert-deftest helixel-test-repeat-selection-extend ()
  "`,` in visual state extends an existing selection using the stored method."
  (helixel-test-with-buffer "hello world foo bar"
    (goto-char 3)
    (setq helixel--last-tx
          (helixel--make-tx 'change
            (helixel-sel-create 'textobj '(:command helixel-mark-inner-word :count 1)
            #'helixel--recreate-textobj
            (replace-regexp-in-string "^helixel-mark-" "" (symbol-name 'helixel-mark-inner-word)))
            :inserted-text "X"))
    ;; Enter visual state then recreate selection
    (setq-local helixel--current-state 'visual)
    (helixel-repeat-selection)     ;; selects "hello"
    (should (string= (buffer-substring (region-beginning) (region-end)) "hello"))
    (helixel-repeat-selection)     ;; extends to next word
    (should (string= (buffer-substring (region-beginning) (region-end)) "hello world"))))

(ert-deftest helixel-test-repeat-selection-no-prev ()
  "`,` without a previous edit signals an error."
  (let ((helixel--last-tx nil)
        (helixel--last-event nil))
    (should-error (helixel-repeat-selection))))

(ert-deftest helixel-test-repeat-selection-no-sel ()
  "`,` with an edit that has no selection context signals an error."
  (helixel-test-with-buffer "hello"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel--make-tx 'insert-text nil :text "X"))
    (should-error (helixel-repeat-selection))))

;; ============================================================================
;; Forward-seek for textobj sel-recreate tests
;; ============================================================================

(ert-deftest helixel-test-repeat-forward-seek-whitespace ()
  "`.` when cursor is on whitespace skips forward to the next textobj."
  (helixel-test-with-buffer "hello   world"
    (goto-char 3)                                ;; on "l" of "hello"
    (setq helixel--last-tx
          (helixel--make-tx 'change
            (helixel-sel-create 'textobj '(:command helixel-mark-inner-word :count 1)
            #'helixel--recreate-textobj
            (replace-regexp-in-string "^helixel-mark-" "" (symbol-name 'helixel-mark-inner-word)))
            :inserted-text "X"))
    (goto-char 7)                                ;; on whitespace between words
    (helixel-repeat-edit)
    ;; Skips whitespace forward, selects "world", changes to "X"
    (should (string= (buffer-string) "hello   X"))))

(ert-deftest helixel-test-repeat-forward-seek-at-word-start ()
  "`.` on whitespace after a word jumps forward to the next word."
  (helixel-test-with-buffer "hello world foo"
    (goto-char 3)
    (setq helixel--last-tx
          (helixel--make-tx 'change
            (helixel-sel-create 'textobj '(:command helixel-mark-inner-word :count 1)
            #'helixel--recreate-textobj
            (replace-regexp-in-string "^helixel-mark-" "" (symbol-name 'helixel-mark-inner-word)))
            :inserted-text "X"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "X world foo"))
    ;; Cursor on space between "X" and "world"
    (goto-char 2)
    (helixel-repeat-edit)
    ;; Skips whitespace forward, selects "world", changes to "X"
    (should (string= (buffer-string) "X X foo"))))

;; ============================================================================
;; Search selection replay (`, .) tests
;; ============================================================================

(ert-deftest helixel-test-repeat-selection-search ()
  "`,` recreates a search-based selection from the stored :pattern."
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel--make-tx 'change
            (helixel-sel-create 'search '(:pattern "hello" :dir forward)
            #'helixel--recreate-search
            "/hello")
            :inserted-text "X"))
    (helixel-repeat-selection)
    (should (region-active-p))
    (should (string= (buffer-substring (region-beginning) (region-end)) "hello"))))

(ert-deftest helixel-test-repeat-search-then-dot ()
  "`.` replays a search-based change on the next match."
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel--make-tx 'change
            (helixel-sel-create 'search '(:pattern "hello" :dir forward)
            #'helixel--recreate-search
            "/hello")
            :inserted-text "X"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "X world hello"))
    ;; cursor after "X " — next . should find next "hello"
    (helixel-repeat-edit)
    (should (string= (buffer-string) "X world X"))))

(ert-deftest helixel-test-repeat-search-comma-then-dot ()
  "`,` previews the search match, `.` applies the edit."
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel--make-tx 'change
            (helixel-sel-create 'search '(:pattern "hello" :dir forward)
            #'helixel--recreate-search
            "/hello")
            :inserted-text "X"))
    (helixel-repeat-selection)
    (should (string= (buffer-substring (region-beginning) (region-end)) "hello"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "X world hello"))))

(ert-deftest helixel-test-repeat-search-n-dot ()
  "Simulate /hello cX<Esc> then n . n . pattern."
  (helixel-test-with-buffer "a hello b hello c hello d"
    (goto-char 3)
    (setq helixel--last-tx
          (helixel--make-tx 'change
            (helixel-sel-create 'search '(:pattern "hello" :dir forward)
            #'helixel--recreate-search
            "/hello")
            :inserted-text "X"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "a X b hello c hello d"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "a X b X c hello d"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "a X b X c X d"))))

(ert-deftest helixel-test-repeat-search-backward ()
  "`.` replays a backward search change."
  (helixel-test-with-buffer "hello world hello"
    (goto-char (point-max))
    (setq helixel--last-tx
          (helixel--make-tx 'change
            (helixel-sel-create 'search '(:pattern "hello" :dir backward)
            #'helixel--recreate-search
            "?hello")
            :inserted-text "X"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "hello world X"))))

(ert-deftest helixel-test-repeat-search-change-with-DEL ()
  "`.` replays a search-based change whose keys include DEL (127).
Simulates `/hello c foo <backspace> o <ESC> .` — the recorded
keys [f o o DEL o] should produce 'foo' on the next match, not 'o'."
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    ;; Construct the tx that /hello c foo <backspace> o <ESC> records.
    (setq helixel--last-tx
          (helixel--make-tx 'change
            (helixel-sel-create 'search '(:pattern "hello" :dir forward)
              #'helixel--recreate-search
              "/hello")
            :inserted-text "foo"
            :keys [102 111 111 127 111]))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "foo world hello"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "foo world foo"))))

(ert-deftest helixel-test-repeat-search-change-with-backspace-symbol ()
  "`.` replays a search-based change whose keys include backspace symbol.
Like `helixel-test-repeat-search-change-with-DEL' but records
backspace as a symbol (GUI Emacs) instead of DEL (127)."
  (helixel-test-with-buffer "hello world hello"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel--make-tx 'change
            (helixel-sel-create 'search '(:pattern "hello" :dir forward)
              #'helixel--recreate-search
              "/hello")
            :inserted-text "foo"
            :keys [102 111 111 backspace 111]))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "foo world hello"))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "foo world foo"))))

(ert-deftest helixel-test-repeat-change-deactivates-mark ()
  "`.` replays keys with no active region, so delete-backward-char
deletes exactly one char rather than an entire region."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    (setq helixel--last-tx
          (helixel--make-tx 'change
            (helixel-sel-create 'search '(:pattern "hello" :dir forward)
              #'helixel--recreate-search
              "/hello")
            :runner #'helixel--repeat-change-core
            :keys (kbd "foo DEL o")))
    (helixel-repeat-edit)
    ;; f o o DEL o should produce "foo", not "o" (which is what
    ;; would happen if the mark were active during key replay).
    (should (string= (buffer-string) "foo world"))))

(ert-deftest helixel-test-repeat-search-change-with-C-d ()
  "`.` replays a search-based change whose keys include C-d.
C-d is a non-printable key — verifies `execute-kbd-macro' replay
works in the dot-repeat context."
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    ;; c ab<C-d>X <esc>: deletes "hello", types "ab", C-d deletes the
    ;; space after "ab", then types "X".
    (setq helixel--last-tx
          (helixel--make-tx 'change
            (helixel-sel-create 'search '(:pattern "hello" :dir forward)
              #'helixel--recreate-search
              "/hello")
            :inserted-text "abX"
            :keys (kbd "ab C-d X")))
    (helixel-repeat-edit)
    (should (string= (buffer-string) "abXworld"))))

(ert-deftest helixel-test-search-sel-display ()
  "`helixel-sel-call-display' for search shows /pattern."
  (should (string= (helixel-sel-call-display
                    (helixel-sel-create 'search
                      '(:pattern "hello" :dir forward)
                      #'helixel--recreate-search
                      "/hello"))
                   "/hello")))

;; ============================================================================
;; Surround tests
;; ============================================================================

(ert-deftest helixel-test-surround-add-paren ()
  "Test `helixel--surround-add' with (pair."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\( ?\))
    (should (equal (buffer-string) "(hello)"))
    (should (region-active-p))
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

(ert-deftest helixel-test-surround-add-bracket ()
  "Test `helixel--surround-add' with [pair."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\[ ?\])
    (should (equal (buffer-string) "[hello]"))
    (should (= (region-beginning) 1))
    (should (= (region-end) 8))))

(ert-deftest helixel-test-surround-add-quote ()
  "Test `helixel--surround-add' with 'pair."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\' ?\')
    (should (equal (buffer-string) "'hello'"))
    (should (region-active-p))))

(ert-deftest helixel-test-surround-add-block ()
  "Test `helixel--surround-add' with string block pair."
  (with-temp-buffer
    (org-mode)
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add "#+begin_quote " "#+end_quote")
    (should (string-match "\\`#\\+begin_quote .*\nhello\n#\\+end_quote\\'" (buffer-string)))))

(ert-deftest helixel-test-surround-add-tag ()
  "Test `helixel--surround-add-tag'."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add-tag "div")
    (should (equal (buffer-string) "<div>\nhello\n</div>"))))

(ert-deftest helixel-test-surround-add-tag-inline ()
  "Test `helixel--surround-add-tag' on content with leading newline.
The leading newline is part of content so mt adds newline only before close."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "\nhello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 7) (activate-mark)
    (helixel--surround-add-tag "b")
    (should (equal (buffer-string) "<b>\nhello\n</b>"))))

(ert-deftest helixel-test-surround-delete-pair-inner ()
  "Test delete surrounding () when point is inside (mi()."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 4)
    (helixel--surround-delete-delimiter (helixel--make-pair-delimiter ?\( ?\)))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-surround-delete-pair-outer ()
  "Test delete surrounding () when point is after the close (ma()."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 7)
    (helixel--surround-delete-delimiter (helixel--make-pair-delimiter ?\( ?\)))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-surround-delete-quote ()
  "Test delete surrounding '' when point is inside."
  (with-temp-buffer
    (insert "'hello'")
    (goto-char 4)
    (helixel--surround-delete-delimiter (helixel--make-pair-delimiter ?\' ?\'))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-surround-delete-quote-outer ()
  "Test delete surrounding \"\" when point is after the close (ma\")."
  (with-temp-buffer
    (insert "\"hello\"")
    (goto-char 8)
    (helixel--surround-delete-delimiter (helixel--make-pair-delimiter ?\" ?\"))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-surround-delete-tag ()
  "Test delete surrounding XML tags."
  (with-temp-buffer
    (insert "<div>hello</div>")
    (goto-char 8)
    (helixel--surround-delete-delimiter (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-surround-delete-tag-with-newlines ()
  "Test delete surrounding XML tags with newlines."
  (with-temp-buffer
    (insert "<div>\nhello\n</div>")
    (goto-char 9)
    (helixel--surround-delete-delimiter (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-surround-replace-pair ()
  "Test replace () with []."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 4)
    (helixel--surround-replace-pair (helixel--make-pair-delimiter ?\( ?\)) ?\[ ?\])
    (should (equal (buffer-string) "[hello]"))))

(ert-deftest helixel-test-surround-replace-quote ()
  "Test replace '' with \"\"."
  (with-temp-buffer
    (insert "'hello'")
    (goto-char 4)
    (helixel--surround-replace-pair (helixel--make-pair-delimiter ?\' ?\') ?\" ?\")
    (should (equal (buffer-string) "\"hello\""))))

(ert-deftest helixel-test-surround-replace-tag ()
  "Test replace tag div -> p."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add-tag "div")
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<p>\nhello\n</p>"))))

(ert-deftest helixel-test-surround-replace-equal-repeated ()
  "Test repeated mr does not accumulate newlines."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add-tag "div")
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (helixel--surround-replace-tag "span" (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<span>\nhello\n</span>"))))

(ert-deftest helixel-test-surround-chain-ms-md ()
  "Chain ms( then md."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\( ?\))
    (let ((d (helixel--make-pair-delimiter ?\( ?\))))
      (let ((pos (helixel--surround-delete-delimiter d)))
        (goto-char pos)
        (should (equal (buffer-string) "hello"))))))

(ert-deftest helixel-test-surround-chain-ms-mr-md ()
  "Chain ms[ then mr{ then md."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\[ ?\])
    (helixel--surround-replace-pair (helixel--make-pair-delimiter ?\[ ?\]) ?\{ ?\})
    (let ((d (helixel--make-pair-delimiter ?\{ ?\})))
      (let ((pos (helixel--surround-delete-delimiter d)))
        (goto-char pos)
        (should (equal (buffer-string) "hello"))))))

(ert-deftest helixel-test-surround-chain-mt-mr-md ()
  "Chain mt div -> mr p -> md."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add-tag "div")
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (let ((d (helixel--make-tag-delimiter)))
      (let ((pos (helixel--surround-delete-delimiter d)))
        (goto-char pos)
        (should (equal (buffer-string) "hello"))))))

(ert-deftest helixel-test-surround-replace-trailing-newline ()
  "Test replace () with [] when content has trailing newline."
  (with-temp-buffer
    (insert "(hello)\n")
    (goto-char 4)
    (helixel--surround-replace-pair (helixel--make-pair-delimiter ?\( ?\)) ?\[ ?\])
    (should (equal (buffer-string) "[hello]\n"))))

(ert-deftest helixel-test-surround-block-lookup ()
  "Test block pair lookup returns (STRING . STRING)."
  (with-temp-buffer
    (org-mode)
    (let ((pair (helixel--surround-block-lookup ?s)))
      (should pair)
      (should (stringp (car pair)))
      (should (stringp (cdr pair)))
      (should (string-match "begin_src" (car pair)))
      (should (string-match "end_src" (cdr pair))))))

(ert-deftest helixel-test-surround-block-lookup-fallback ()
  "Test block pair lookup in fundamental mode returns nil."
  (with-temp-buffer
    (fundamental-mode)
    (should-not (helixel--surround-block-lookup ?s))))

(ert-deftest helixel-test-surround-available-keys ()
  "Test `helixel--surround-available-keys' returns expected keys."
  (with-temp-buffer
    (fundamental-mode)
    (let ((keys-str (string-join (helixel--surround-available-keys) " ")))
      (should (string-match-p "(" keys-str))
      (should (string-match-p "\\[" keys-str))
      (should (string-match-p "'" keys-str))
      (should (string-match-p "\"" keys-str)))))

(ert-deftest helixel-test-surround-available-keys-org ()
  "Test `helixel--surround-available-keys' includes block keys in org."
  (with-temp-buffer
    (org-mode)
    (let ((keys (helixel--surround-available-keys)))
      (should (cl-some (lambda (k) (string-match "src" k)) keys)))))

(ert-deftest helixel-test-surround-delete-block ()
  "Test delete block after ms s in org-mode."
  (with-temp-buffer
    (org-mode)
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (let ((pair (helixel--surround-block-lookup ?s)))
      (helixel--surround-add (car pair) (cdr pair))
      (let ((d (helixel--make-block-delimiter (car pair) (cdr pair))))
        (let ((pos (helixel--surround-delete-delimiter d)))
          (goto-char pos)
          (should (equal (buffer-string) "hello")))))))

;; ============================================================================
;; surround: delimiter protocol + edge cases
;; ============================================================================

;; --- helixel-up-xml-tag match-data fix ---

(ert-deftest helixel-test-up-xml-tag-match-data-from-opener ()
  "match-data is preserved when starting on opening tag."
  (with-temp-buffer
    (insert "<div>hello</div>")
    (goto-char 1)
    (should (zerop (helixel-up-xml-tag 1)))
    (should (match-beginning 0))
    (should (= (match-beginning 0) 11))))

(ert-deftest helixel-test-up-xml-tag-match-data-from-eob ()
  "match-data is preserved when starting from end of buffer."
  (with-temp-buffer
    (insert "<div>\nhello\n</div>")
    (goto-char (point-max))
    (should (zerop (helixel-up-xml-tag -1)))
    (should (match-beginning 0))
    (should (= (match-beginning 0) 1))))

(ert-deftest helixel-test-up-xml-tag-nested-from-inside ()
  "Find innermost tag pair when point is inside content."
  (with-temp-buffer
    (insert "<div><span>hello</span></div>")
    (goto-char 14) ;; inside "hello"
    (should (zerop (helixel-up-xml-tag 1)))
    (should (string= (match-string 0) "</span>"))
    (should (zerop (helixel-up-xml-tag -1)))
    (should (string= (match-string 0) "<span>"))))

;; --- helixel--strip-adjacent-newlines ---

(ert-deftest helixel-test-strip-adjacent-newlines-both ()
  "Strip newlines on both sides."
  (with-temp-buffer
    (insert "open\ncontent\nclose")
    (pcase-let ((`(,oe . ,cb) (helixel--strip-adjacent-newlines 5 14)))
      (should (= oe 6))
      (should (= cb 13)))))

(ert-deftest helixel-test-strip-adjacent-newlines-none ()
  "No newlines to strip."
  (with-temp-buffer
    (insert "openXcontentYclose")
    (pcase-let ((`(,oe . ,cb) (helixel--strip-adjacent-newlines 5 13)))
      (should (= oe 5))
      (should (= cb 13)))))

;; --- helixel-delimiter-bounds / unified delete ---

(ert-deftest helixel-test-delimiter-bounds-pair ()
  "Bounds for pair () from inside."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 4)
    (let* ((d (helixel--make-pair-delimiter ?\( ?\)))
           (b (helixel-delimiter-bounds d)))
      (should (= (caar b) 1))  ;; open-beg
      (should (= (cdar b) 2))  ;; open-end
      (should (= (cadr b) 7))  ;; close-beg
      (should (= (cddr b) 8))))) ;; close-end

(ert-deftest helixel-test-delimiter-bounds-pair-after-close ()
  "Bounds for pair from after closing delimiter."
  (with-temp-buffer
    (insert "(hello)")
    (goto-char 8) ;; after )
    (let* ((d (helixel--make-pair-delimiter ?\( ?\)))
           (b (helixel-delimiter-bounds d)))
      (should (= (caar b) 1))
      (should (= (cddr b) 8)))))

(ert-deftest helixel-test-delimiter-bounds-quote ()
  "Bounds for quote from inside (uses char-scanning fallback)."
  (with-temp-buffer
    (insert "\"hello\"")
    (goto-char 4)
    (should (> (helixel--surround-delete-delimiter
                (helixel--make-pair-delimiter ?\" ?\")) 0))
    (should (equal (buffer-string) "hello"))))

(ert-deftest helixel-test-delimiter-bounds-tag ()
  "Bounds for tag from inside."
  (with-temp-buffer
    (insert "<div>hello</div>")
    (goto-char 8)
    (let* ((d (helixel--make-tag-delimiter))
           (b (helixel-delimiter-bounds d)))
      (should (= (caar b) 1))
      (should (= (cadr b) 11)))))

(ert-deftest helixel-test-delimiter-bounds-block-org ()
  "Bounds for org block."
  (with-temp-buffer
    (org-mode)
    (insert "#+begin_src emacs-lisp\nhello\n#+end_src")
    (goto-char 25)
    (let* ((d (helixel--make-block-delimiter))
           (b (helixel-delimiter-bounds d)))
      (should b)
      (should (>= (caar b) 1)))))

(ert-deftest helixel-test-delete-block-via-delimiter ()
  "Delete org block via unified delimiter-delete."
  (with-temp-buffer
    (org-mode)
    (insert "#+begin_src emacs-lisp\nhello\n#+end_src")
    (goto-char 26)
    (let ((d (helixel--make-block-delimiter)))
      (helixel--surround-delete-delimiter d)
      (should (equal (buffer-string) "hello")))))

;; --- replace-tag fix: trailing text + newline correctness ---

(ert-deftest helixel-test-replace-tag-trailing-text ()
  "Replace tag when text follows closing tag."
  (with-temp-buffer
    (insert "prefix\n<div>\nhello\n</div>\nsuffix")
    (goto-char 14) ;; inside content
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "prefix\n<p>\nhello\n</p>\nsuffix"))))

(ert-deftest helixel-test-replace-tag-inline-no-newlines ()
  "Replace inline tag, add newlines."
  (with-temp-buffer
    (insert "<div>hello</div>")
    (goto-char 8)
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<p>\nhello\n</p>"))))

(ert-deftest helixel-test-replace-tag-preexisting-newlines ()
  "Replace tag that already has newlines."
  (with-temp-buffer
    (insert "<div>\nhello\n</div>")
    (goto-char 9)
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<p>\nhello\n</p>"))))

(ert-deftest helixel-test-replace-tag-eob-no-extra-newlines ()
  "Replace tag at end of buffer, no extra \\n."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add-tag "div")
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    ;; Must not have double newline
    (should-not (string-match "\n\n</p>" (buffer-string)))
    (should (equal (buffer-string) "<p>\nhello\n</p>"))))

;; --- nested tags ---

(ert-deftest helixel-test-delete-tag-nested-same-name ()
  "Delete innermost pair of same-name nested tags."
  (with-temp-buffer
    (insert "<div><div>hello</div></div>")
    (goto-char 14) ;; inside inner content
    (helixel--surround-delete-delimiter (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<div>hello</div>"))))

(ert-deftest helixel-test-delete-tag-nested-different-name ()
  "Delete innermost pair of different-name nested tags."
  (with-temp-buffer
    (insert "<div><span>hello</span></div>")
    (goto-char 15)
    (helixel--surround-delete-delimiter (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<div>hello</div>"))))

(ert-deftest helixel-test-replace-tag-innermost-nested ()
  "Replace innermost pair in nested tags."
  (with-temp-buffer
    (insert "<div><span>hello</span></div>")
    (goto-char 15)
    (helixel--surround-replace-tag "b" (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<div><b>\nhello\n</b></div>"))))

(ert-deftest helixel-test-nested-tag-mat-mr-replaces-inner ()
  "After mat on inner tag of nested tags, mr replaces inner (not outer)."
  (with-temp-buffer
    (insert "<p>\n<div>\nhello\n</div>\n</p>\n\nworld")
    ;; Simulate mat selecting outer <div> — region spans <div> to </div>
    (push-mark 5 nil t)
    (goto-char 25)
    (activate-mark)
    ;; position at midpoint of selection for finder
    (goto-char (/ (+ 5 25) 2))
    (helixel--surround-replace-tag "a" (helixel--make-tag-delimiter))
    (should (equal (buffer-string)
                   "<p>\n<a>\nhello\n</a>\n</p>\n\nworld"))))

(ert-deftest helixel-test-nested-tag-mat-md-deletes-inner ()
  "After mat on inner tag of nested tags, md deletes inner (not outer)."
  (with-temp-buffer
    (insert "<p>\n<div>\nhello\n</div>\n</p>\n\nworld")
    ;; Simulate mat selecting outer <div> — region spans <div> to </div>
    (push-mark 5 nil t)
    (goto-char 25)
    (activate-mark)
    ;; position at midpoint of selection for finder
    (goto-char (/ (+ 5 25) 2))
    (helixel--surround-delete-delimiter (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "<p>\nhello\n</p>\n\nworld"))))

;; --- unified delete via delimiter protocol ---

(ert-deftest helixel-test-delete-delimiter-pair ()
  "Unified delete for pair via delimiter."
  (with-temp-buffer
    (insert "[hello]")
    (goto-char 4)
    (let ((d (helixel--make-pair-delimiter ?\[ ?\])))
      (helixel--surround-delete-delimiter d)
      (should (equal (buffer-string) "hello")))))

(ert-deftest helixel-test-delete-delimiter-regex ()
  "Unified delete for regex block."
  (with-temp-buffer
    (insert "#+begin_quote\nhello\n#+end_quote")
    (goto-char 18)
    (let ((d (helixel--make-regex-delimiter
              "#\\+begin_quote" "#\\+end_quote")))
      (helixel--surround-delete-delimiter d)
      (should (equal (buffer-string) "hello")))))

(ert-deftest helixel-test-chain-mt-mr-md-via-delimiter ()
  "Chain mt→mr→md via delimiter protocol."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add-tag "div")
    (helixel--surround-replace-tag "p" (helixel--make-tag-delimiter))
    (let ((d (helixel--make-tag-delimiter)))
      (helixel--surround-delete-delimiter d)
      (should (equal (buffer-string) "hello")))))

;; --- delete-tag newline cleanup ---

(ert-deftest helixel-test-delete-tag-strips-newlines ()
  "Delete tag strips adjacent newlines."
  (with-temp-buffer
    (insert "<div>\nhello\n</div>")
    (goto-char 9)
    (helixel--surround-delete-delimiter (helixel--make-tag-delimiter))
    (should (equal (buffer-string) "hello"))))

;; --- ms add with new delimiter types ---

(ert-deftest helixel-test-surround-add-brace ()
  "Test `helixel--surround-add' with { pair."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\{ ?\})
    (should (equal (buffer-string) "{hello}"))))

(ert-deftest helixel-test-surround-add-angle ()
  "Test `helixel--surround-add' with < pair."
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "hello")
    (goto-char 1) (push-mark (point) nil t) (goto-char 6) (activate-mark)
    (helixel--surround-add ?\< ?\>)
    (should (equal (buffer-string) "<hello>"))))
;; ---------------------------------------------------------------------------
;; Count-aware repeat tests

(ert-deftest helixel-test-repeat-count-line-select ()
  "Test `3x d .` repeats killing 3 lines."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\nline5\nline6\n"
    (goto-char 1)
    ;; Select 3 lines: x x x
    (setq last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (setq last-command 'helixel-select-line this-command 'helixel-select-line)
    (helixel-select-line)
    (setq last-command 'helixel-select-line this-command 'helixel-select-line)
    (helixel-select-line)
    ;; Verify count stored
    (should (= (helixel-sel-count helixel--pending-sel) 3))
    ;; Kill
    (setq last-command 'helixel-select-line this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (string= (buffer-string) "line4\nline5\nline6\n"))
    ;; Repeat at line4 — should kill 3 lines again
    (goto-char 1)
    (helixel-repeat-edit)
    (should (string= (buffer-string) ""))))

(ert-deftest helixel-test-repeat-count-prefix-line ()
  "Test `3x d .` with prefix arg selects 3 lines at once."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\nline5\nline6\n"
    (goto-char 1)
    ;; Select 3 lines at once with prefix
    (setq last-command nil this-command 'helixel-select-line)
    (helixel-select-line 3)
    ;; Verify count stored
    (should (= (helixel-sel-count helixel--pending-sel) 3))
    ;; Kill
    (setq last-command 'helixel-select-line this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (string= (buffer-string) "line4\nline5\nline6\n"))
    ;; Repeat
    (goto-char 1)
    (helixel-repeat-edit)
    (should (string= (buffer-string) ""))))

(ert-deftest helixel-test-repeat-count-line-up ()
  "Test count-aware repeat for line-up selection."
  (helixel-test-with-buffer "line1\nline2\nline3\nline4\n"
    (goto-char (point-max))
    (forward-line -1)
    ;; Select 2 lines upward
    (setq last-command nil this-command 'helixel-select-line-up)
    (helixel-select-line-up 2)
    (should (= (helixel-sel-count helixel--pending-sel) 2))
    ;; Kill
    (setq last-command 'helixel-select-line-up this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    (should (string= (buffer-string) "line1\nline2\n"))))

(ert-deftest helixel-test-select-line-count-stored-in-tx ()
  "Test that count is preserved through record-edit into the transaction."
  (helixel-test-with-buffer "a\nb\nc\nd\n"
    (goto-char 1)
    (setq last-command nil this-command 'helixel-select-line)
    (helixel-select-line)
    (helixel-select-line)
    (setq last-command 'helixel-select-line this-command 'helixel-kill-thing-at-point)
    (helixel-kill-thing-at-point)
    ;; The tx sel should have count 2
    (should (= (helixel-sel-count (helixel-event-sel helixel--last-tx)) 2))))

;;; helixel-test-edit.el ends here
