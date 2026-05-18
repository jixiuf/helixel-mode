;;; helixel-register.el --- Named registers  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

;; Author: jixiuf
;; Keywords: convenience
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

;; Named register support for helixel-mode, bridging Emacs `register-alist'.
;;
;; Usage:
;;   \"ay  — copy to register a
;;   \"ap  — paste from register a
;;   \"ad  — delete to register a
;;   \"ac  — change to register a
;;   \"ar  — replace with register a
;;   \"\"y  — copy to default register (kill-ring, same as y)
;;
;; Register names: any character can be mapped to a storage backend.
;; By default: a-z → Emacs `register-alist', \" → kill-ring,
;; + → system clipboard, * → primary selection.
;; Customize `helixel-register-backends' to change these mappings.
;;
;; This module is required by `helixel-state' so the wrappers are
;; available everywhere in the helixel dependency tree.

;;; Code:

(require 'cl-lib)

(defcustom helixel-register-backends
  '((?\" . kill-ring)
    (?+ . clipboard)
    (?* . primary))
  "Alist mapping register characters to storage backends.
Each entry is (CHAR . BACKEND) where BACKEND is a keyword:
- `kill-ring': Emacs kill ring (default for \\=\").
- `clipboard': System clipboard (`CLIPBOARD' selection).
- `primary': Primary selection (`PRIMARY' selection).
Characters not listed here use Emacs `register-alist' (via
`get-register'/`set-register'), which supports a-z, 0-9, and
any other character Emacs registers accept."
  :type '(alist :key-type character
                :value-type (choice (const :tag "Kill Ring" kill-ring)
                                    (const :tag "Clipboard" clipboard)
                                    (const :tag "Primary Selection" primary)))
  :group 'helixel)

(defcustom helixel-default-register ?\"
  "Character for the default (unnamed) register.
When `helixel--current-register' is nil or this character,
operators use the kill ring directly rather than a named
register.  Pressing \\\"\\\" in normal mode selects this register."
  :type 'character
  :group 'helixel)

(defvar helixel--current-register nil
  "Character identifying the register for the next operator.
Set by `helixel-select-register' (bound to `\\\"' in normal mode).
Consumed and cleared by each operator that uses it.
When nil or equal to `helixel-default-register', the `kill-ring'
is used directly.")

;; ── Register selection (bound to `\"' in normal mode) ──

(defun helixel-select-register ()
  "Read a register name for the next operator.
Valid register names: a-z (named), \" (unnamed/`kill-ring'),
+ (system clipboard), * (primary selection).
Users can customize these via `helixel-register-backends'.
Press \\[keyboard-quit] to cancel."
  (interactive)
  (let ((char (read-char "Register: ")))
    (if (= char ?\e)
        (progn
          (setq helixel--current-register nil)
          (message "Register cancelled"))
      (setq helixel--current-register char)
      ;; Show the register name in echo area so user knows
      ;; it's pending (e.g. \"a).
      (message "\"%c" char))))

;; ── Backend lookup ──

(defun helixel-register-backend (char)
  "Return the storage backend keyword for register CHAR.
Looks up CHAR in `helixel-register-backends'.  Returns nil when
CHAR is not in the alist (meaning it uses `register-alist')."
  (cdr (assq char helixel-register-backends)))

;; ── Register I/O ──

(defun helixel-register-get (char)
  "Return text contents of register CHAR, or nil if empty.
Dispatch is determined by `helixel-register-backends':
- `kill-ring' → top of `kill-ring'.
- `clipboard' → system clipboard (CLIPBOARD selection).
- `primary' → primary selection.
- nil (unlisted) → Emacs `register-alist' via `get-register'."
  (cl-case (helixel-register-backend char)
    (kill-ring (and kill-ring (current-kill 0 t)))
    (clipboard (and (display-graphic-p)
                    (gui-get-selection 'CLIPBOARD)))
    (primary   (and (display-graphic-p)
                    (gui-get-selection 'PRIMARY)))
    (t (get-register char))))

(defun helixel-register-set (char text)
  "Store TEXT in register CHAR.
Dispatch is determined by `helixel-register-backends':
- `kill-ring' → push to `kill-ring' via `kill-new'.
- `clipboard' → system clipboard via `gui-set-selection'.
- `primary' → primary selection via `gui-set-selection'.
- nil (unlisted) → Emacs `register-alist' via `set-register'.
TEXT is a string preserving any yank-handler properties."
  (cl-case (helixel-register-backend char)
    (kill-ring (kill-new text))
    (clipboard (gui-set-selection 'CLIPBOARD text))
    (primary   (gui-set-selection 'PRIMARY text))
    (t (set-register char text))))

;; ── Register-aware kill-ring wrappers ──
;;
;; These replace direct `kill-new' / `current-kill' / `yank' calls
;; throughout the codebase.  When `helixel--current-register' is a
;; non-default register (not nil and not `helixel-default-register'),
;; they redirect to the configured backend.  When nil or the default
;; register, they use the real kill-ring.

(defun helixel--register-active-p ()
  "Return non-nil when a non-default named register is selected.
A register is considered active when `helixel--current-register'
is non-nil and not equal to `helixel-default-register'."
  (and helixel--current-register
       (not (eq helixel--current-register helixel-default-register))))

(defun helixel--register-consume ()
  "Return and clear `helixel--current-register'."
  (prog1 helixel--current-register
    (setq helixel--current-register nil)))


(defun helixel-register-rotate-delete (text)
  "Rotate delete registers 1-9 and store TEXT in register 1.
Old register 8 shifts to 9, 7 to 8, ..., 1 to 2."
  (dotimes (i 8)
    (let ((src (+ ?1 (- 7 i))))
      (set-register (+ src 1) (get-register src))))
  (set-register ?1 text))

(defun helixel--kill-new (text &optional kind)
  "Like `kill-new', but also populates numbered registers.
TEXT is a string with optional yank-handler text properties.
KIND is :copy for yank operations (sets register 0), otherwise
a delete (rotates registers 1-9, sets register - for small deletes).
When a named register is active, TEXT is also stored there.
Does NOT clear the register -- callers should call
`helixel--register-consume' separately when done."
  ;; Always push to kill-ring (unnamed register).
  (kill-new text)
  ;; Numbered / special registers.
  (if (eq kind :copy)
      ;; Register 0 -- last yank (copy).
      (set-register ?0 text)
    ;; Rotate delete registers 1-9, new text goes to 1.
    (helixel-register-rotate-delete text)
    ;; Register - (small delete, no newline).
    (when (and text (not (string-match-p "\n" text)))
      (set-register ?- text)))
  ;; Named register selected by user (e.g. "a).
  (when (helixel--register-active-p)
    (helixel-register-set helixel--current-register text)))

(defun helixel--current-kill (n &optional no-move)
  "Like `current-kill', but reads from named register when active.
N is the `kill-ring' index (unused when reading from register).
NO-MOVE is passed to `current-kill' as DO-NOT-MOVE when using `kill-ring'.
Returns the text or nil.  Does NOT alter the `kill-ring' yanking-point
when reading from a register."
  (if (helixel--register-active-p)
      (or (helixel-register-get helixel--current-register)
          (current-kill 0 t))
    (current-kill n no-move)))

(defun helixel--yank (&optional arg)
  "Like `yank', but reads from named register when active.
ARG is passed through to `yank' when using the `kill-ring'."
  (if (helixel--register-active-p)
      (let ((text (helixel-register-get helixel--current-register)))
        (if text
            (insert-for-yank text)
          (message "Register \"%c is empty" helixel--current-register)))
    (yank arg)))

(provide 'helixel-register)
;;; helixel-register.el ends here
