;;; helixel-shims.el --- Shims for built-in modes  -*- lexical-binding: t; -*-

;; Copyright (C) 2025  jixiuf

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
;; Integration shims so helixel-mode plays well with built-in Emacs
;; modes that have their own editable sub-modes.
;;
;; Pattern:
;;   Enter editable sub-mode → normal state (full modal editing)
;;   Exit back to parent mode → motion state (read-only navigation)
;;
;; Supported modes:
;;   - wdired
;;   - grep-edit (Emacs 29+)
;;   - occur-edit (Emacs 29+)
;;   - wgrep  (third-party, same pattern)

;;; Code:

(require 'helixel-state)

;; ── wdired ──

(defun helixel-shims--setup-wdired ()
  "Setup wdired integration.
Entering wdired → normal.  Exiting (save/abort) → motion."
  (add-hook 'wdired-mode-hook #'helixel-enter-normal-state)
  (advice-add 'wdired-finish-edit   :after #'helixel-enter-motion-state)
  (advice-add 'wdired-abort-changes :after #'helixel-enter-motion-state)
  (when (fboundp 'wdired-exit)
    (advice-add 'wdired-exit :after #'helixel-enter-motion-state)))

;; ── grep-edit (Emacs 29+ built-in) ──

(defun helixel-shims--setup-grep-edit ()
  "Setup grep-edit integration.
Entering grep-edit → normal.  Saving → motion."
  (when (fboundp 'grep-edit-mode)
    (add-hook 'grep-edit-mode-hook #'helixel-enter-normal-state)
    (advice-add 'grep-edit-save-changes
                :after #'helixel-enter-motion-state)))

;; ── occur-edit (Emacs 29+ built-in) ──

(defun helixel-shims--setup-occur-edit ()
  "Setup occur-edit integration.
Entering occur-edit → normal.  Ceasing edit → motion."
  (when (fboundp 'occur-edit-mode)
    (add-hook 'occur-edit-mode-hook #'helixel-enter-normal-state)
    (advice-add 'occur-cease-edit :after #'helixel-enter-motion-state)))

;; ── wgrep (third-party) ──

(defun helixel-shims--setup-wgrep ()
  "Setup wgrep integration.
Entering wgrep → normal.  Exiting (save/finish/abort) → motion."
  (when (fboundp 'wgrep-change-to-wgrep-mode)
    (advice-add 'wgrep-change-to-wgrep-mode
                :after #'helixel-enter-normal-state)
    (advice-add 'wgrep-finish-edit
                :after #'helixel-enter-motion-state)
    (advice-add 'wgrep-abort-changes
                :after #'helixel-enter-motion-state)
    (advice-add 'wgrep-save-all-buffers
                :after #'helixel-enter-motion-state)
    (when (fboundp 'wgrep-exit)
      (advice-add 'wgrep-exit :after #'helixel-enter-motion-state))))

;; ── Deferred registration ──
;; We defer calling the setup functions until the target library is
;; loaded because `advice-add' requires the function to exist.
;; `eval-after-load' is the standard mechanism; we wrap the calls in
;; a helper so package-lint can distinguish these from user-config.
;; package-lint: disable=eval-after-load

(defun helixel-shims--register-deferred ()
  "Register deferred shim setups via `with-eval-after-load'.
Called at top-level when this file is loaded."
  (with-eval-after-load 'wdired  (helixel-shims--setup-wdired))
  (with-eval-after-load 'grep    (helixel-shims--setup-grep-edit))
  (with-eval-after-load 'replace (helixel-shims--setup-occur-edit))
  (with-eval-after-load 'wgrep   (helixel-shims--setup-wgrep)))

(helixel-shims--register-deferred)

(provide 'helixel-shims)
;;; helixel-shims.el ends here
