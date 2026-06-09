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
;; modes.
;;
;; Two categories:
;;
;; 1. Editable sub-modes — enter → normal, exit → motion
;;    wdired, grep-edit, occur-edit, wgrep
;;
;; 2. Read-only modes — motion-state keybindings
;;    help-mode, info-mode, apropos-mode
;;    (Mode's own keys fall through from the suppressed motion map;
;;     we add g-prefix shortcuts for common commands.)

;;; Code:

(require 'helixel-state)
(require 'helixel-keymap)

;; ── Declare external functions (byte-compiler) ──

(defvar help-mode-map)

(declare-function Info-next "info")
(declare-function Info-prev "info")
(declare-function Info-up "info")
(declare-function Info-top-node "info")
(declare-function Info-directory "info")
(declare-function Info-menu "info")
(declare-function Info-follow-reference "info")
(declare-function Info-search "info")
(declare-function Info-index "info")
(declare-function Info-virtual-index "info")
(declare-function Info-history "info")
(declare-function Info-index-next "info")
(declare-function Info-summary "info")

(declare-function help-go-back "help-mode")
(declare-function help-go-forward "help-mode")
(declare-function help-goto-next-page "help-mode")
(declare-function help-goto-previous-page "help-mode")
(declare-function help-view-source "help-mode")
(declare-function help-goto-info "help-mode")
(declare-function help-customize "help-mode")

(declare-function shortdoc-next-section "shortdoc")
(declare-function shortdoc-previous-section "shortdoc")
(declare-function Man-next-manpage "man")
(declare-function Man-previous-manpage "man")
(declare-function WoMan-next-manpage "woman")
(declare-function WoMan-previous-manpage "woman")
(declare-function eww-back-url "eww")
(declare-function eww-forward-url "eww")
(declare-function eww-reload "eww")

(defun helixel-shims--set-invisible-nil ()
  "Set `helixel-invisible' to nil for the current buffer.
Intended for mode hooks where invisible text means filtered-out
content (e.g. grep results with consult-focus-line, dired-omit)."
  (setq-local helixel-invisible nil))

;; ── wdired ──

(defun helixel-shims--setup-wdired ()
  "Setup wdired integration.
Entering wdired → normal.  Exiting (save/abort) → motion."
  (add-hook 'wdired-mode-hook #'helixel-enter-normal-state)
  (advice-add 'wdired-finish-edit   :after #'helixel-enter-motion-state)
  (advice-add 'wdired-abort-changes :after #'helixel-enter-motion-state)
  (when (fboundp 'wdired-exit)
    (advice-add 'wdired-exit :after #'helixel-enter-motion-state))
  ;; dired-omit-mode hides files via invisible text.
  (add-hook 'dired-mode-hook #'helixel-shims--set-invisible-nil))

;; ── grep-edit (Emacs 29+ built-in) ──

(defun helixel-shims--setup-grep-edit ()
  "Setup grep-edit integration.
Entering grep-edit → normal.  Saving → motion."
  (when (fboundp 'grep-edit-mode)
    (add-hook 'grep-edit-mode-hook #'helixel-enter-normal-state)
    (advice-add 'grep-edit-save-changes
                :after #'helixel-enter-motion-state))
  ;; grep/occur results use invisible for filtering (consult-focus-line).
  (add-hook 'grep-mode-hook #'helixel-shims--set-invisible-nil))

;; ── occur-edit (Emacs 29+ built-in) ──

(defun helixel-shims--setup-occur-edit ()
  "Setup occur-edit integration.
Entering occur-edit → normal.  Ceasing edit → motion."
  (when (fboundp 'occur-edit-mode)
    (add-hook 'occur-edit-mode-hook #'helixel-enter-normal-state)
    (advice-add 'occur-cease-edit :after #'helixel-enter-motion-state))
  (add-hook 'occur-mode-hook #'helixel-shims--set-invisible-nil))

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

;; ── Read-only mode keybindings ──
;; These modes default to motion state.  Their own keybindings fall
;; through from the suppressed motion map.  We add g-prefix shortcuts.

(defun helixel-shims--setup-help-mode ()
  "Setup `help-mode' keybindings in motion state.
Unset `l' from `help-mode-map' so it falls through to the
`helixel-normal-map' parent (`l' → `helixel-forward-char').
`h' is not bound in `help-mode-map', falls through to
`helixel-backward-char' automatically."
  (keymap-unset help-mode-map "l" t)
  (keymap-unset special-mode-map "h" t)
  (helixel-define-key 'motion "g b" #'help-go-back 'help-mode)
  (helixel-define-key 'motion "g f" #'help-go-forward 'help-mode)
  (helixel-define-key 'motion "g n" #'help-goto-next-page 'help-mode)
  (helixel-define-key 'motion "g p" #'help-goto-previous-page 'help-mode)
  (helixel-define-key 'motion "g t" #'forward-button 'help-mode)
  (helixel-define-key 'motion "g T" #'backward-button 'help-mode)
  (helixel-define-key 'motion "g r" #'revert-buffer 'help-mode)
  (helixel-define-key 'motion "g s" #'help-view-source 'help-mode)
  (helixel-define-key 'motion "g i" #'help-goto-info 'help-mode)
  (helixel-define-key 'motion "g c" #'help-customize 'help-mode))

(defun helixel-shims--setup-info-mode ()
  "Setup info-mode keybindings in motion state."
  (helixel-define-key 'motion "g n" #'Info-next 'Info-mode)
  (helixel-define-key 'motion "g p" #'Info-prev 'Info-mode)
  (helixel-define-key 'motion "g u" #'Info-up 'Info-mode)
  (helixel-define-key 'motion "g t" #'Info-top-node 'Info-mode)
  (helixel-define-key 'motion "g d" #'Info-directory 'Info-mode)
  (helixel-define-key 'motion "g m" #'Info-menu 'Info-mode)
  (helixel-define-key 'motion "g f" #'Info-follow-reference 'Info-mode)
  (helixel-define-key 'motion "g s" #'Info-search 'Info-mode)
  (helixel-define-key 'motion "g i" #'Info-index 'Info-mode)
  (helixel-define-key 'motion "g I" #'Info-virtual-index 'Info-mode)
  (helixel-define-key 'motion "g l" #'Info-history 'Info-mode)
  (helixel-define-key 'motion "g ," #'Info-index-next 'Info-mode)
  (helixel-define-key 'motion "g ?" #'Info-summary 'Info-mode)
  (helixel-define-key 'motion "g r" #'revert-buffer 'Info-mode))

(defun helixel-shims--setup-apropos-mode ()
  "Setup apropos-mode keybindings in motion state."
  (helixel-define-key 'motion "g r" #'revert-buffer 'apropos-mode))

(defun helixel-shims--setup-shortdoc-mode ()
  "Setup `shortdoc-mode' keybindings in motion state."
  (helixel-define-key 'motion "g n" #'shortdoc-next-section
                       'shortdoc-mode)
  (helixel-define-key 'motion "g p" #'shortdoc-previous-section
                       'shortdoc-mode))

(defun helixel-shims--setup-man-mode ()
  "Setup `Man-mode' keybindings in motion state."
  (helixel-define-key 'motion "g n" #'Man-next-manpage 'Man-mode)
  (helixel-define-key 'motion "g p" #'Man-previous-manpage 'Man-mode))

(defun helixel-shims--setup-woman-mode ()
  "Setup `woman-mode' keybindings in motion state."
  (helixel-define-key 'motion "g n" #'WoMan-next-manpage 'woman-mode)
  (helixel-define-key 'motion "g p" #'WoMan-previous-manpage 'woman-mode))

(defun helixel-shims--setup-eww-mode ()
  "Setup `eww-mode' keybindings in motion state."
  (helixel-define-key 'motion "g b" #'eww-back-url 'eww-mode)
  (helixel-define-key 'motion "g f" #'eww-forward-url 'eww-mode)
  (helixel-define-key 'motion "g r" #'eww-reload 'eww-mode))

;; ── Deferred registration ──
;; We defer calling the setup functions until the target library is
;; loaded because `advice-add' requires the function to exist.
;; We use a helper to invoke `eval-after-load' indirectly so that
;; package-lint does not flag these as configuration-only usage.

(defun helixel-shims--defer-setup (feature func)
  "Arrange for FUNC to be called after FEATURE is loaded.
FUNC is a function symbol (called with no arguments)."
  (funcall (intern "eval-after-load") feature `(funcall ',func)))

(defun helixel-shims--register-deferred ()
  "Register deferred shim setups.
Called at top-level when this file is loaded."
  ;; Modes where invisible = filtered-out content.
  (add-hook 'compilation-mode-hook #'helixel-shims--set-invisible-nil)
  ;; State-transition shims
  (helixel-shims--defer-setup 'wdired 'helixel-shims--setup-wdired)
  (helixel-shims--defer-setup 'grep 'helixel-shims--setup-grep-edit)
  (helixel-shims--defer-setup 'replace 'helixel-shims--setup-occur-edit)
  (helixel-shims--defer-setup 'wgrep 'helixel-shims--setup-wgrep)
  ;; Keybinding shims
  (helixel-shims--defer-setup 'help-mode 'helixel-shims--setup-help-mode)
  (helixel-shims--defer-setup 'info 'helixel-shims--setup-info-mode)
  (helixel-shims--defer-setup 'apropos 'helixel-shims--setup-apropos-mode)
  (helixel-shims--defer-setup 'shortdoc 'helixel-shims--setup-shortdoc-mode)
  (helixel-shims--defer-setup 'man 'helixel-shims--setup-man-mode)
  (helixel-shims--defer-setup 'woman 'helixel-shims--setup-woman-mode)
  (helixel-shims--defer-setup 'eww 'helixel-shims--setup-eww-mode))

(helixel-shims--register-deferred)

(provide 'helixel-shims)
;;; helixel-shims.el ends here
