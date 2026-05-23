;;; helixel-edit.el --- Backward-compat shim for helixel-data -*- lexical-binding: t; -*-

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
;; Backward-compatibility shim.  All data types (helixel-sel, helixel-edit,
;; operator registry, delimiter protocol) now live in helixel-data.el.
;; This file exists so existing (require 'helixel-edit) calls keep working.
;; New code should (require 'helixel-data) directly.

;;; Code:

(require 'helixel-data)

(provide 'helixel-edit)
;;; helixel-edit.el ends here
