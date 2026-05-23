;;; helixel-delimiter.el --- Delimiter builder functions -*- lexical-binding: t; -*-

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
;; Delimiter builder functions for helixel-mode.
;;
;; Constructs delimiter plists for pair, quote, tag, block, and regex
;; delimited regions.  Each builder returns a plist conforming to the
;; delimiter protocol defined in helixel-data.el.
;;
;; Depends on helixel-data (accessors, protocol schema) and
;; helixel-textobj-engine (for the actual finder implementations).

;;; Code:

(require 'helixel-data)

(declare-function helixel-up-paren "helixel-textobj-engine")
(declare-function helixel-up-xml-tag "helixel-textobj-engine")
(declare-function helixel-up-block-at-point "helixel-textobj-engine")
(declare-function helixel-up-regex-block "helixel-textobj-engine")

;; ---------------------------------------------------------------------------
;; Builder — construct delimiter plists for each type
;; ---------------------------------------------------------------------------

(defun helixel--make-pair-delimiter (open close)
  "Create a pair delimiter for OPEN and CLOSE characters."
  (let ((equal-p (= open close)))
    (list :type (if equal-p 'quote 'pair)
          :open open :close close
          :finder (if equal-p
                      `(lambda (dir) (helixel--find-equal-char ,open dir))
                    `(lambda (dir) (helixel-up-paren ,open ,close dir)))
          :nl-p nil)))

(defun helixel--make-tag-delimiter ()
  "Create a tag delimiter."
  (list :type 'tag
        :finder (lambda (dir) (helixel-up-xml-tag dir))
        :nl-p t))

(defun helixel--make-block-delimiter (&optional open close)
  "Create a block delimiter for OPEN and CLOSE strings.
If OPEN/CLOSE are nil, the finder resolves the spec at runtime."
  (list :type 'block
        :open open :close close
        :finder (lambda (dir) (helixel-up-block-at-point dir))
        :nl-p t))

(defun helixel--make-regex-delimiter (begin-re end-re &optional name-group)
  "Create a regex delimiter for BEGIN-RE and END-RE.
Optional NAME-GROUP specifies the match group index for the name."
  (list :type 'regex
        :open begin-re :close end-re
        :begin-re begin-re :end-re end-re
        :name-group name-group
        :finder `(lambda (dir)
                   (helixel-up-regex-block ,begin-re ,end-re dir ,name-group))
        :nl-p t))

(provide 'helixel-delimiter)
;;; helixel-delimiter.el ends here
