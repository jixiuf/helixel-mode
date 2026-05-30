;;; helixel-register.el --- Named register support for helixel-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

;; Author: jixiuf
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
;; Named register support bridging Emacs `register-alist'.
;;
;; Provides register-aware wrappers around Emacs kill-ring operations.
;; When `helixel--current-register' is a non-default named register
;; (e.g. \"a), kill/yank operations redirect to that register's backend.
;; Otherwise they use the standard kill-ring.

;;; Code:

(require 'cl-lib)
(require 'helixel-core)

;; ----------------------------------------------------------------------
;; Customization
;; ----------------------------------------------------------------------

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

(defcustom helixel-register-numbered-delete-start ?1
  "First character of the numbered delete register range.
Together with `helixel-register-numbered-delete-count', defines
a rotating ring of registers that store recent deletes.
The default range is ?1 through ?9."
  :type 'character
  :group 'helixel)

(defcustom helixel-register-numbered-delete-count 9
  "Number of numbered delete registers to rotate.
Defines how many consecutive characters starting from
`helixel-register-numbered-delete-start' are used for
the delete register ring.  Default is 9 (registers 1-9)."
  :type 'natnum
  :group 'helixel)

;; ----------------------------------------------------------------------
;; State
;; ----------------------------------------------------------------------

(defvar helixel--current-register nil
  "Character identifying the register for the next operator.
Set by `helixel-select-register' (bound to `\\\"' in normal mode).
Consumed and cleared by each operator that uses it.
When nil or equal to `helixel-default-register', the `kill-ring'
is used directly.")

;; ----------------------------------------------------------------------
;; Register selection
;; ----------------------------------------------------------------------

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
      (message "\"%c" char))))

;; ----------------------------------------------------------------------
;; Backend lookup
;; ----------------------------------------------------------------------

(defun helixel-register-backend (char)
  "Return the storage backend keyword for register CHAR.
Looks up CHAR in `helixel-register-backends'.  Returns nil when
CHAR is not in the alist (meaning it uses `register-alist')."
  (cdr (assq char helixel-register-backends)))

;; ----------------------------------------------------------------------
;; Register I/O
;; ----------------------------------------------------------------------

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

;; ----------------------------------------------------------------------
;; Register-aware kill-ring wrappers
;;
;; These replace direct `kill-new' / `current-kill' / `yank' calls
;; throughout the codebase.  When `helixel--current-register' is a
;; non-default register (not nil and not `helixel-default-register'),
;; they redirect to the configured backend.  When nil or the default
;; register, they use the real kill-ring.
;; ----------------------------------------------------------------------

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
  "Rotate numbered delete registers and store TEXT in the first slot.
Uses `helixel-register-numbered-delete-start' and
`helixel-register-numbered-delete-count' to define the range.
Old registers shift: slot N-1 → N, ..., slot 1 → 2."
  (let ((start helixel-register-numbered-delete-start)
        (count helixel-register-numbered-delete-count))
    (when (> count 1)
      (cl-loop for i from (- count 2) downto 0
               for src = (+ start i)
               do (set-register (1+ src) (get-register src))))
    ;; Always store the new text in the first (start) slot,
    ;; even when count is 1 (no rotation needed).
    (set-register start text)))

(defun helixel--kill-new (text &optional kind)
  "Like `kill-new', but also populates numbered registers.
TEXT is a string with optional yank-handler text properties.
KIND is :copy for yank operations (sets register 0), otherwise
a delete (rotates registers 1-9, sets register - for small deletes).
When a named register is active, TEXT is also stored there.
Does NOT clear the register -- callers should call
`helixel--register-consume' separately when done."
  ;; Save external clipboard/selection content to kill ring before
  ;; a delete overwrites it.  This ensures `helixel-replace-pop' can
  ;; cycle back to externally-copied content (e.g. from outside Emacs).
  ;; Copy operations (:copy kind) don't need this — they preserve
  ;; the clipboard rather than overwriting it.
  (unless (eq kind :copy)
    (when interprogram-paste-function
      (let ((clip (funcall interprogram-paste-function)))
        (when (and clip (> (length clip) 0)
                   (or (null kill-ring)
                       (not (string= clip (car kill-ring)))))
          (kill-new clip)))))
  ;; Always push to kill-ring (unnamed register).
  (kill-new text)
  ;; Numbered / special registers.
  (if (eq kind :copy)
      ;; Last yank (copy) register.
      (set-register helixel-register-yank-char text)
    ;; Rotate numbered delete registers.
    (helixel-register-rotate-delete text)
    ;; Small delete register (no newline).
    (when (and text (not (string-match-p "\n" text)))
      (set-register helixel-register-small-delete-char text)))
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
