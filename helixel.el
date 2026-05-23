;;; helixel.el --- A minor mode like Helix keys  -*- lexical-binding: t; -*-

;; Copyright (C) 2025  jixiuf

;; Author: jixiuf
;; Keywords: convenience
;; Version: 0.9.0
;; Package-Requires: ((emacs "29.1"))
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
;;
;; helixel-mode is a minor mode that provides modal editing inspired by
;; the Helix editor.  It loads helixel-state (modal state machine),
;; helixel-move (movement commands), helixel-common (editing commands
;; and dot-repeat replay), helixel-keymap (keymap definitions),
;; helixel-search (isearch-backed search), and helixel-textobj
;; (text objects).


;;; Code:

(require 'helixel-action)
(require 'helixel-register)
(require 'helixel-common)
(require 'helixel-keymap)
(require 'helixel-search)
(require 'helixel-delimiter)
(require 'helixel-textobj)
(require 'helixel-surround)
(require 'helixel-swap)
(require 'helixel-repeat-strategy)
(require 'helixel-chain)
(require 'helixel-shims)

(provide 'helixel)
;;; helixel.el ends here
