;;; helixel-test-common.el --- Shared test helpers  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

;; Author: jixiuf <https://github.com/jixiuf>
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Keywords: tests

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

;; Shared test helpers used across multiple test files.

;;; Code:

(require 'ert)

(defmacro helixel-test-with-buffer (content &rest body)
  "Execute BODY in a temp buffer with CONTENT and transient-mark-mode on.
Buffer starts at point 1.  Internal hooks are activated without enabling
`helixel-mode' (avoids state-machine side-effects in tests)."
  (declare (indent 1))
  `(with-temp-buffer
     (transient-mark-mode 1)
     (insert ,content)
     (goto-char 1)
     (helixel--activate-all-hooks)
     (unwind-protect
         (progn ,@body)
       (helixel--deactivate-all-hooks))))

(provide 'helixel-test-common)
;;; helixel-test-common.el ends here
