;;; helixel-textobj.el --- Text objects for Helixel -*- lexical-binding: t; -*-

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
;;
;; Text objects for Helixel Mode.
;; Facade: requires the four sub-modules.
;;
;;   engine  — forward primitives, range, type properties,
;;             activate-textobj-range, recreate / advance
;;   pair    — paren / quote / xml-tag selection +
;;             make-pair-delimiter, make-tag-delimiter
;;   block   — regex blocks + block-at-point +
;;             make-block-delimiter, make-regex-delimiter
;;   marks   — define-mark-* macros + user mark commands +
;;             default registrations + tree-sitter helper

;;; Code:

(require 'helixel-textobj-engine)
(require 'helixel-textobj-pair)
(require 'helixel-textobj-block)
(require 'helixel-textobj-marks)

(provide 'helixel-textobj)
;;; helixel-textobj.el ends here
