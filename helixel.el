;;; helixel.el --- A minor mode like Helix keys  -*- lexical-binding: t; -*-

;; Copyright (C) 2025  jixiuf

;; Author: jixiuf
;; Keywords: convenience
;; Version: 0.9.0
;; Package-Requires: ((emacs "29.1"))
;; URL: https://github.com/jixiuf/helixel-mode
;; SPDX-License-Identifier: GPL-3.0-or-later

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
;; helixel-mode is a minor mode that provides modal editing inspired by
;; the Helix editor.  It loads helixel-core (core data, event ring,
;; macros), helixel-state (modal state machine), helixel-move
;; (movement commands), helixel-editing (editing commands and
;; dot-repeat replay), helixel-keymap (keymap definitions),
;; helixel-search (search engine), and helixel-textobj (text objects).


;;; Code:

(require 'helixel-core)
(require 'helixel-ring)
(require 'helixel-macros)
(require 'helixel-repeat)
(require 'helixel-chain)
(require 'helixel-state)
(require 'helixel-search)
(require 'helixel-editing)
(require 'helixel-textobj-engine)
(require 'helixel-textobj-pair)
(require 'helixel-textobj-block)
(require 'helixel-textobj-marks)
(require 'helixel-textobj)
(require 'helixel-surround)
(require 'helixel-swap)
(require 'helixel-keymap)
(require 'helixel-mc-core)
(require 'helixel-mc-targets)
(require 'helixel-mc-spawn)
(require 'helixel-mc-integrate)
(require 'helixel-shims)

;; All helixel modules are loaded — NOW we can safely walk the obarray
;; and bulk-whitelist every helixel interactive command for multi-
;; cursor dispatch.  Doing this from `helixel-mc-integrate' itself is
;; too early: that module only requires core/mc-core/repeat/chain, so
;; ~80% of modal commands (defined in state/move/editing/textobj/…)
;; would be missed.
(helixel-mc--whitelist-helixel-commands)

(defun helixel--register-mode-hooks ()
  "Register all module init functions on `helixel-mode-on-hook'.
Each init function registers its module's internal hooks only when
`helixel-mode' is enabled."
  (add-hook 'helixel-mode-on-hook #'helixel-keymap--init-hooks)
  (add-hook 'helixel-mode-on-hook #'helixel-surround--init)
  (add-hook 'helixel-mode-on-hook #'helixel-mc-spawn--init)
  (add-hook 'helixel-mode-on-hook #'helixel-mc-integrate--init)
  (add-hook 'helixel-mode-on-hook #'helixel--init-chain-hooks))
(helixel--register-mode-hooks)

(defun helixel--init-chain-hooks ()
  "Wire chain subsystem hooks."
  (add-hook 'helixel-action-commit-hook #'helixel--chain-push-entry)
  (add-hook 'helixel-chain-insert-entry-functions
            #'helixel--chain-propagate-entry-kind))
;; helixel--init-chain-hooks registered via `helixel--register-mode-hooks'
;; in helixel.el.

(defun helixel--activate-all-hooks ()
  "Run `helixel-mode-on-hook' to register internal hooks.
For use in tests and other contexts where the full mode isn't desired."
  (run-hooks 'helixel-mode-on-hook))

(defun helixel--deactivate-all-hooks ()
  "Remove internal hooks registered via `helixel-mode-on-hook'.
For use in tests to clean up after `helixel--activate-all-hooks'."
  (run-hooks 'helixel-mode-off-hook))

(provide 'helixel)
;;; helixel.el ends here
