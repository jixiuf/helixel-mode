;;; helixel-test-register.el --- Tests for Helixel: registers  -*- lexical-binding: t; -*-

;; Copyright (C) 2025  jixiuf

;; Author: jixiuf <https://github.com/jixiuf>
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



;;; helixel-register tests

(ert-deftest helixel-test-register-select ()
  "Test `helixel-select-register' sets and can cancel."
  (should (null helixel--current-register))
  ;; Test setting (simulate via direct set, since read-char can't be
  ;; automated in batch ERT).
  (setq helixel--current-register ?a)
  (should (eq helixel--current-register ?a))
  (should (helixel--register-active-p))
  ;; Consume
  (helixel--register-consume)
  (should (null helixel--current-register))
  ;; Default register (\") is NOT active
  (setq helixel--current-register ?\")
  (should (not (helixel--register-active-p)))
  (helixel--register-consume)
  (should (null helixel--current-register)))

(ert-deftest helixel-test-register-set-get ()
  "Test storing and retrieving text in a named register."
  (unwind-protect
      (progn
        (helixel--register-set ?x "test-text")
        (should (string= (helixel--register-get ?x) "test-text")))
    ;; Cleanup
    (set-register ?x nil)))

(ert-deftest helixel-test-register-set-get-with-properties ()
  "Test register preserves yank-handler text properties."
  (unwind-protect
      (let ((text (helixel--linewise-text "hello")))
        (helixel--register-set ?x text)
        (let ((retrieved (helixel--register-get ?x)))
          (should (string= retrieved "hello\n"))
          (should (eq (car-safe (get-text-property 0 'yank-handler retrieved))
                      'helixel--yank-handler-line-wise))))
    (set-register ?x nil)))

(ert-deftest helixel-test-register-kill-new ()
  "Test `helixel--kill-new' stores to named register when active."
  (unwind-protect
      (progn
        (setq helixel--current-register ?x)
        (helixel--kill-new "killed-text")
        (should (string= (helixel--register-get ?x) "killed-text"))
        (should (eq helixel--current-register ?x)) ; not consumed
        (helixel--register-consume))
    (set-register ?x nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-kill-new-default ()
  "Test `helixel--kill-new' uses kill-ring when no register active."
  (let ((prev-kill (and kill-ring (current-kill 0 t)))
        (helixel--current-register nil))
    (helixel--kill-new "test-kill")
    (should (string= (current-kill 0 t) "test-kill"))))

(ert-deftest helixel-test-register-current-kill ()
  "Test `helixel--current-kill' reads from named register when active."
  (unwind-protect
      (progn
        (helixel--register-set ?x "reg-content")
        (setq helixel--current-register ?x)
        (should (string= (helixel--current-kill 0 t) "reg-content"))
        (helixel--register-consume))
    (set-register ?x nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-yank ()
  "Test `helixel--yank' inserts from named register when active."
  (unwind-protect
      (helixel-test-with-buffer "hello"
        (goto-char 6) ; after "hello"
        (helixel--register-set ?x "WORLD")
        (setq helixel--current-register ?x)
        (helixel--yank)
        (should (string= (buffer-string) "helloWORLD"))
        (helixel--register-consume))
    (set-register ?x nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-kill ()
  "Test \"ad deletes to register a (charwise)."
  (unwind-protect
      (helixel-test-with-buffer "hello world"
        (setq helixel--current-register ?a)
        (goto-char 2)
        (push-mark (point) t t)
        (goto-char 7)
        (helixel-kill)
        (should (null helixel--current-register)) ; consumed
        (should (string= (buffer-string) "hworld"))
        (should (string= (helixel--register-get ?a) "ello ")))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-kill-no-region ()
  "Test \"ad deletes single char to register (no region)."
  (unwind-protect
      (helixel-test-with-buffer "hello"
        (setq helixel--current-register ?a)
        (helixel-kill)
        (should (null helixel--current-register))
        (should (string= (buffer-string) "ello"))
        ;; Single char delete goes to kill-ring via delete-char,
        ;; but register was active so we check it was consumed.
        (should (null helixel--current-register)))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-kill-linewise ()
  "Test \"ad with line selection stores linewise to register."
  (unwind-protect
      (helixel-test-with-buffer "line1\nline2\nline3"
        (setq helixel--current-register ?a)
        (helixel-select-line)
        (helixel-kill)
        (should (null helixel--current-register))
        ;; One line deleted
        (should (string= (buffer-string) "line2\nline3"))
        (let ((text (helixel--register-get ?a)))
          (should (string= text "line1\n"))
          (should (eq (car-safe (get-text-property 0 'yank-handler text))
                      'helixel--yank-handler-line-wise))))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-copy ()
  "Test \"ay copies region to register a."
  (unwind-protect
      (helixel-test-with-buffer "hello world"
        (setq helixel--current-register ?a)
        (goto-char 1)
        (push-mark (point) t t)
        (goto-char 6)
        (helixel-kill-ring-save)
        (should (null helixel--current-register))
        ;; Buffer unchanged
        (should (string= (buffer-string) "hello world"))
        (should (string= (helixel--register-get ?a) "hello")))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-copy-linewise ()
  "Test \"ay with line selection copies linewise to register."
  (unwind-protect
      (helixel-test-with-buffer "line1\nline2"
        (setq helixel--current-register ?a)
        (helixel-select-line)
        (helixel-kill-ring-save)
        (should (null helixel--current-register))
        (let ((text (helixel--register-get ?a)))
          (should (string= text "line1\n"))
          (should (eq (car-safe (get-text-property 0 'yank-handler text))
                      'helixel--yank-handler-line-wise))))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-paste ()
  "Test \"ap pastes from register a."
  (unwind-protect
      (helixel-test-with-buffer "hello"
        (goto-char 6) ; after "hello"
        (helixel--register-set ?a "WORLD")
        (setq helixel--current-register ?a)
        (helixel-yank)
        (should (null helixel--current-register))
        (should (string= (buffer-string) "helloWORLD")))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-paste-linewise ()
  "Test \"ap pastes linewise content from register.\"\nFor `helixel-yank' (paste-after), linewise content is inserted on the\nLINE AFTER point's current line (here, after line2)."
  (unwind-protect
      (helixel-test-with-buffer "line1\nline2"
        (helixel--register-set ?a
                              (helixel--linewise-text "INSERTED"))
        (setq helixel--current-register ?a)
        (goto-char 7) ;; start of line2
        (helixel-yank)
        (should (null helixel--current-register))
        (should (string= (buffer-string)
                         "line1\nline2\nINSERTED")))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-paste-before ()
  "Test \"aP pastes before from register a."
  (unwind-protect
      (helixel-test-with-buffer "hello"
        (helixel--register-set ?a "PRE")
        (setq helixel--current-register ?a)
        (helixel-yank-before)
        (should (null helixel--current-register))
        ;; yank-before inserts at point; point is at 1
        (should (string= (buffer-string) "PREhello")))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-replace ()
  "Test \"ar replaces region with register a content."
  (unwind-protect
      (helixel-test-with-buffer "hello world"
        (helixel--register-set ?a "REPLACED")
        (goto-char 1)
        (push-mark (point) t t)
        (goto-char 6)
        (setq helixel--current-register ?a)
        (helixel-replace)
        (should (null helixel--current-register))
        (should (string= (buffer-string) "REPLACED world")))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-replace-no-region ()
  "Test \"ar without region replaces char with register content."
  (let ((helixel-replace-delete-char-p t))
    (unwind-protect
        (helixel-test-with-buffer "hello"
          (helixel--register-set ?a "X")
          (setq helixel--current-register ?a)
          (helixel-replace)
          (should (null helixel--current-register))
          (should (string= (buffer-string) "Xello")))
      (set-register ?a nil)
      (setq helixel--current-register nil))))

(ert-deftest helixel-test-register-change ()
  "Test \"ac changes region, stores deleted text in register a."
  (unwind-protect
      (helixel-test-with-buffer "hello world"
        (setq helixel--current-register ?a)
        (goto-char 1)
        (push-mark (point) t t)
        (goto-char 6)
        (let ((helixel--inhibit-repeat-record t))
          (helixel-change))
        ;; Register is consumed after the kill part
        (should (null helixel--current-register))
        (should (string= (helixel--register-get ?a) "hello"))
        (should (string= (buffer-string) " world")))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-default-unnamed ()
  "Test \"\" y is same as y (uses kill-ring)."
  (helixel-test-with-buffer "hello world"
    (setq helixel--current-register ?\")
    (goto-char 1)
    (push-mark (point) t t)
    (goto-char 6)
    (helixel-kill-ring-save)
    (should (null helixel--current-register))
    (should (string= (buffer-string) "hello world"))
    (should (string= (current-kill 0 t) "hello"))))

(ert-deftest helixel-test-register-empty-paste ()
  "Test pasting from empty register shows a message."
  (unwind-protect
      (helixel-test-with-buffer "hello"
        ;; Ensure register is empty
        (set-register ?z nil)
        (setq helixel--current-register ?z)
        (helixel-yank)
        (should (null helixel--current-register))
        (should (string= (buffer-string) "hello")))
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-repeat-no-register ()
  "Test . after \"ad uses kill-ring not register a."
  (unwind-protect
      (helixel-test-with-buffer "hello world"
        ;; Step 1: kill to register a (ello )
        (setq helixel--current-register ?a)
        (goto-char 2)
        (push-mark (point) t t)
        (goto-char 7)
        (helixel-kill)
        ;; Register consumed, buffer: "hworld"
        (should (null helixel--current-register))
        (should (string= (helixel--register-get ?a) "ello "))
        ;; Step 2: press . — select and kill one char
        (goto-char 1)
        (push-mark (point) t t)
        (goto-char 2)
        (helixel-repeat-edit 1)
        ;; Kill-ring top should be "h" (the char deleted by .)
        (should (string= (current-kill 0 t) "h"))
        ;; Register a should still have "ello " unchanged
        (should (string= (helixel--register-get ?a) "ello ")))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-repeat-with-register ()
  "Test \"b. replays the last edit using register b."
  (unwind-protect
      (helixel-test-with-buffer "hello world"
        ;; Step 1: do a normal kill (stores tx)
        (goto-char 3)
        (push-mark (point) t t)
        (goto-char 7)
        (helixel-kill)
        ;; Buffer: "held"
        ;; Step 2: select register b and press .
        (goto-char 1)
        (push-mark (point) t t)
        (goto-char 2)
        (setq helixel--current-register ?b)
        (helixel-repeat-edit 1)
        ;; Register b should have the char deleted by replay
        (should (string= (helixel--register-get ?b) "h"))
        (should (null helixel--current-register)))
    (set-register ?a nil)
    (set-register ?b nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-persistence ()
  "Test register content persists across operations."
  (unwind-protect
      (helixel-test-with-buffer "hello"
        ;; Store to register a
        (setq helixel--current-register ?a)
        (helixel-kill)
        ;; Register a has "h"
        (should (string= (helixel--register-get ?a) "h"))
        ;; Do another operation (no register)
        (helixel-kill)  ; kill "e", goes to kill-ring
        ;; Register a still has "h"
        (should (string= (helixel--register-get ?a) "h"))
        ;; Now paste from register a
        (goto-char 4) ; after "llo" (remaining: "llo")
        (setq helixel--current-register ?a)
        (helixel-yank)
        (should (string= (buffer-string) "lloh")))
    (set-register ?a nil)
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-numbered-yank ()
  "Test yank (copy) sets register 0."
  (unwind-protect
      (helixel-test-with-buffer "hello world"
        (goto-char 1)
        (push-mark (point) t t)
        (goto-char 6)
        (helixel-kill-ring-save)  ;; copy "hello"
        (should (string= (helixel--register-get ?0) "hello")))
    (set-register ?0 nil)
    (dolist (r '(?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9 ?-))
      (set-register r nil))
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-numbered-delete-rotate ()
  "Test delete rotates registers 1-9."
  (unwind-protect
      (helixel-test-with-buffer "hello world"
        ;; Delete "ello " (positions 2-7)
        (goto-char 2)
        (push-mark (point) t t)
        (goto-char 7)
        (helixel-kill)
        ;; Buffer: "hworld"
        ;; Delete "world" (positions 2-7)
        (goto-char 2)
        (push-mark (point) t t)
        (goto-char 7)
        (helixel-kill)
        ;; Register 1 = "world" (most recent), Register 2 = "ello "
        (should (string= (helixel--register-get ?1) "world"))
        (should (string= (helixel--register-get ?2) "ello ")))
    (dolist (r '(?0 ?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9 ?-))
      (set-register r nil))
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-numbered-small-delete ()
  "Test small delete (single char) sets register -."
  (unwind-protect
      (helixel-test-with-buffer "hello"
        (helixel-kill) ; delete "h"
        (should (string= (helixel--register-get ?-) "h"))
        ;; Also goes to register 1 (rotated)
        (should (string= (helixel--register-get ?1) "h")))
    (dolist (r '(?0 ?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9 ?-))
      (set-register r nil))
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-numbered-linewise-not-small ()
  "Test linewise delete does NOT go to small delete register -."
  (unwind-protect
      (helixel-test-with-buffer "line1\nline2"
        (set-register ?- nil) ; ensure empty
        (helixel-select-line)
        (helixel-kill)
        ;; Linewise delete has newline, should NOT go to -
        (should (null (helixel--register-get ?-)))
        ;; Does go to register 1
        (should (string= (helixel--register-get ?1) "line1\n")))
    (dolist (r '(?0 ?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9 ?-))
      (set-register r nil))
    (setq helixel--current-register nil)))

(ert-deftest helixel-test-register-numbered-yank-preserves-0 ()
  "Test yank sets register 0, subsequent delete does not overwrite."
  (unwind-protect
      (helixel-test-with-buffer "first second"
        ;; Yank "first" → register 0
        (goto-char 1)
        (push-mark (point) t t)
        (goto-char 6)
        (helixel-kill-ring-save)
        (should (string= (helixel--register-get ?0) "first"))
        ;; Delete "second" → register 1, register 0 unchanged
        (goto-char 7)
        (push-mark (point) t t)
        (goto-char 13)
        (helixel-kill)
        (should (string= (helixel--register-get ?1) "second"))
        (should (string= (helixel--register-get ?0) "first")))
    (dolist (r '(?0 ?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9 ?-))
      (set-register r nil))
    (setq helixel--current-register nil)))

;;; helixel-test.el ends here

;;; helixel-test-register.el ends here
