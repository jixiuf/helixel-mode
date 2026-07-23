;;; helixel-register.el --- Named registers for helixel-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

;; Author: jixiuf <https://github.com/jixiuf>
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Keywords: convenience

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
;;
;; Named register system for helixel-mode.
;;
;; Register characters map to storage backends via
;; `helixel-register-backends' (kill-ring, system clipboard, primary
;; selection, or Emacs `register-alist').  Operators read
;; `helixel--current-register' (set by `helixel-select-register',
;; consumed by the next operator).  Delete/yank operations populate
;; the numbered delete registers and the yank register automatically
;; (`helixel--kill-new').
;;
;; Also hosts the swap-source register (`helixel--yank-register') used
;; by copy/swap, and the per-cursor swap-source variable
;; `helixel--yank-register-source'.
;;
;; Depends only on `helixel-core'.  Consumers: helixel-search,
;; helixel-editing, helixel-swap, helixel-mc-core (state snapshot).

;;; Code:

(require 'cl-lib)
(require 'helixel-core)

;; Forward declaration: mc dispatch consults this minor mode in
;; `helixel--register-consume'.  Defined in helixel-mc-core.el.
(defvar helixel-mc-mode)

(defconst helixel--yank-register ?Y
  "Dedicated register for swap-source from yank/copy.
Set only by copy (\"y\") at the real cursor.  In multi-cursor mode
fake cursors write to `helixel--yank-register-source' instead.
Read by swap (\"S\") — falls back to this register when the
per-cursor variable is nil (real cursor, non-mc mode).
Contains (:beg MARKER :end MARKER :buffer BUFFER :type TYPE).")

(defvar-local helixel--yank-register-source nil
  "Per-cursor swap-source plist for multi-cursor mode.
Set by copy (`y') only when running inside a fake cursor body.
Saved/restored by `helixel-pc-state' along with other per-cursor vars.
Format: (:beg MARKER :end MARKER :buffer BUFFER :type TYPE).")


;; ── Named registers ──

(defcustom helixel-register-backends
  '((?\" . kill-ring)
    (?+ . clipboard)
    (?* . primary))
  "Alist mapping register characters to storage backends.
Each entry is (CHAR . BACKEND) where BACKEND is a keyword:
- :kill-ring: Emacs kill ring (default for \\=\").
- :clipboard: System clipboard (CLIPBOARD selection).
- :primary: Primary selection (PRIMARY selection).
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

(defcustom helixel-register-yank-char ?0
  "Register character for the last yank (copy) operation.
Set by `helixel--kill-new' with :copy kind.  Users can paste
from it with \"0p."
  :type 'character
  :group 'helixel)

(defcustom helixel-register-small-delete-char ?-
  "Register character for small deletes (no newline).
Set by `helixel--kill-new' when the deleted text does not
contain a newline."
  :type 'character
  :group 'helixel)

(defcustom helixel-register-delete-registers
  '(?1 ?2 ?3 ?4 ?5 ?6 ?7 ?8 ?9)
  "List of characters identifying numbered delete registers.
These form a rotating ring: each delete shifts older entries
right (losing the last) and stores the new text in the first
register (car of the list).  Default is registers 1 through 9.

Example for d e f g:
  (setq helixel-register-delete-registers
        \='(?d ?e ?f ?g))"
  :type '(repeat character)
  :group 'helixel)

(defvar helixel--current-register nil
  "Character identifying the register for the next operator.
Set by `helixel-select-register' (bound to `\\\"' in normal mode).
Consumed and cleared by each operator that uses it.
When nil or equal to `helixel-default-register', the `kill-ring'
is used directly.")

(defun helixel-select-register ()
  "Read a register name for the next operator.
Valid register names: a-z (named), \" (unnamed/`kill-ring'),
+ (system clipboard), * (primary selection).
Users can customize these via `helixel-register-backends'.
Press \\[keyboard-quit] to cancel."
  (interactive)
  (let ((char (read-char "Register: ")))
    (when (= char helixel--yank-register)
      (user-error "Register %c is reserved" helixel--yank-register))
    (if (= char ?\e)
        (progn
          (setq helixel--current-register nil)
          (message "Register cancelled"))
      (setq helixel--current-register char)
      (message "\"%c" char))))

(defsubst helixel--register-backend (char)
  "Return the storage backend keyword for register CHAR.
Looks up CHAR in `helixel-register-backends'.  Returns nil when
CHAR is not in the alist (meaning it uses `register-alist')."
  (cdr (assq char helixel-register-backends)))

(defun helixel--register-get (char)
  "Return text contents of register CHAR, or nil if empty.
Dispatch is determined by `helixel-register-backends':
- `kill-ring' → top of `kill-ring'.
- `clipboard' → system clipboard (CLIPBOARD selection).
- `primary' → primary selection.
- nil (unlisted) → Emacs `register-alist' via `get-register'."
  (cl-case (helixel--register-backend char)
    (kill-ring (and kill-ring (current-kill 0 t)))
    (clipboard (and (display-graphic-p)
                    (gui-get-selection 'CLIPBOARD)))
    (primary   (and (display-graphic-p)
                    (gui-get-selection 'PRIMARY)))
    (t (get-register char))))

(defun helixel--register-set (char text)
  "Store TEXT in register CHAR.
Dispatch is determined by `helixel-register-backends':
- `kill-ring' → push to `kill-ring' via `kill-new'.
- `clipboard' → system clipboard via `gui-set-selection'.
- `primary' → primary selection via `gui-set-selection'.
- nil (unlisted) → Emacs `register-alist' via `set-register'.
TEXT is a string preserving any yank-handler properties."
  (cl-case (helixel--register-backend char)
    (kill-ring (kill-new text))
    (clipboard (gui-set-selection 'CLIPBOARD text))
    (primary   (gui-set-selection 'PRIMARY text))
    (t (set-register char text))))

(defsubst helixel--register-active-p ()
  "Return non-nil when a non-default named register is selected.
A register is considered active when `helixel--current-register'
is non-nil and not equal to `helixel-default-register'."
  (and helixel--current-register
       (not (eq helixel--current-register helixel-default-register))))

(defun helixel--register-consume ()
  "Return and clear `helixel--current-register'.
When multi-cursor mode is active the real cursor runs first and
would consume the register before fake cursors can replay.  We
suppress the clear here; `helixel-mc--post-command' clears it
after all cursors have run."
  (prog1 helixel--current-register
    (unless (bound-and-true-p helixel-mc-mode)
      (setq helixel--current-register nil))))

(defun helixel--register-rotate-delete (text)
  "Rotate numbered delete registers and store TEXT in the first slot.
Uses `helixel-register-delete-registers' to define the ring.
Old registers shift right: each register's content moves to the next
register in the list; the last register's content is discarded."
  (let ((regs helixel-register-delete-registers))
    (when (cdr regs)                    ; more than one register
      (cl-loop for i from (- (length regs) 2) downto 0
               do (set-register (nth (1+ i) regs)
                                (get-register (nth i regs)))))
    (set-register (car regs) text)))

(defun helixel--register-store-delete (text)
  "Store TEXT in numbered-delete and small-delete registers.
Rotates `helixel-register-delete-registers' and sets
`helixel-register-small-delete-char' when TEXT has no newline.
Does NOT push to `kill-ring'.  Named register is also populated
when `helixel--current-register' is active."
  (helixel--register-rotate-delete text)
  (when (and text (not (string-match-p "\n" text)))
    (set-register helixel-register-small-delete-char text))
  (when (helixel--register-active-p)
    (helixel--register-set helixel--current-register text)))

(defun helixel--kill-new (text &optional kind)
  "Like `kill-new', but also populates numbered registers.
TEXT is a string with optional yank-handler text properties.
KIND is :copy for yank operations (sets register 0), otherwise
a delete (rotates the numbered delete registers,
sets register - for small deletes).
When a named register is active, TEXT is also stored there.
Does NOT clear the register -- callers should call
`helixel--register-consume' separately when done."
  (unless (eq kind :copy)
    (when interprogram-paste-function
      (let ((clip (funcall interprogram-paste-function)))
        (when (and clip (> (length clip) 0)
                   (or (null kill-ring)
                       (not (string= clip (car kill-ring)))))
          (kill-new clip)))))
  (kill-new text)
  (if (eq kind :copy)
      (progn
        (set-register helixel-register-yank-char text)
        (when (helixel--register-active-p)
          (helixel--register-set helixel--current-register text)))
    (helixel--register-store-delete text)))

(defun helixel--current-kill (n &optional no-move)
  "Like `current-kill', but reads from named register when active.
N is the `kill-ring' index (unused when reading from register).
NO-MOVE is passed to `current-kill' as DO-NOT-MOVE when using `kill-ring'.
Returns the text or nil.  Does NOT alter the `kill-ring' yanking-point
when reading from a register."
  (if (helixel--register-active-p)
      (or (helixel--register-get helixel--current-register)
          (current-kill 0 t))
    (current-kill n no-move)))

(defun helixel--yank (&optional arg)
  "Like `yank', but reads from named register when active.
ARG is passed through to `yank' when using the `kill-ring'."
  (if (helixel--register-active-p)
      (let ((text (helixel--register-get helixel--current-register)))
        (if text
            (insert-for-yank text)
          (message "Register \"%c is empty" helixel--current-register)))
    (yank arg)))


(provide 'helixel-register)
;;; helixel-register.el ends here
