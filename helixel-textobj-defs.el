;;; helixel-textobj-defs.el --- Text object macro definitions -*- lexical-binding: t; -*-

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
;; Text object macro definitions for Helixel.
;; Define-mark-pair/-quote/-object/-regex-textobj macros.
;;

;;; Code:

(require 'helixel-textobj-engine)

(declare-function evil-textobj-tree-sitter--range
              "evil-textobj-tree-sitter-core" t t)
(declare-function evil-textobj-tree-sitter--message-not-found
              "evil-textobj-tree-sitter-core" t t)
(defvar evil-textobj-tree-sitter-use-next-if-not-within)

(defmacro helixel--define-mark-delimited (kind name open close doc inner-p)
  "Internal: define inner/a mark functions for a delimited textobj.
KIND is `:pair' or `:quote'.  NAME is the object name.
OPEN and CLOSE are the opening and closing delimiters (characters).
DOC is the description.  INNER-P non-nil means inner, nil means a."
  (declare (indent defun))
  (let* ((func-name (intern (format "helixel-mark-%s-%s"
                                    (if inner-p "inner" "a")
                                    name)))
         (func-doc (format "Select %s %s."
                           (if inner-p "inner" "a")
                           doc))
         (inclusive (if inner-p nil t))
         (subcat (if (eq kind :quote) 'quote 'pair))
         (selector
          (if (eq kind :quote)
              `(helixel-select-quote ,open
                                     (when (helixel--use-region-p)
                                       (region-beginning))
                                     (when (helixel--use-region-p)
                                       (region-end))
                                     nil count ,inclusive)
            `(helixel-select-paren ,open ,close
                                   (when (helixel--use-region-p)
                                     (region-beginning))
                                   (when (helixel--use-region-p)
                                     (region-end))
                                   nil count ,inclusive)))
         (surround-pushes
          (if (eq kind :quote)
              `((push (cons ,open ,close) helixel--surround-pairs))
            `((push (cons ,open ,close) helixel--surround-pairs)
              (push (cons ,close ,open) helixel--surround-pairs)))))
    `(progn
       (defun ,func-name (&optional count)
         ,func-doc
         (interactive "p")
         (when helixel-textobj-action-function
           (funcall helixel-textobj-action-function 'textobj ',subcat))
         (helixel--activate-textobj-range
          ,selector
          (helixel--make-pair-delimiter ,open ,close)
          count))
       ,@(unless inner-p surround-pushes))))

(defmacro helixel-define-mark-pair (name open close doc inner-p)
  "Define mark inner/a functions for a pair of brackets.
NAME is the name of the bracket pair.  OPEN and CLOSE are the
opening and closing delimiters.  DOC is a description of the
pair.  INNER-P non-nil means inner, nil means a."
  (declare (indent defun))
  `(helixel--define-mark-delimited :pair ,name ,open ,close ,doc ,inner-p))

(defmacro helixel-define-mark-quote (name quote-char doc inner-p)
  "Define mark inner/a functions for a quote character.
NAME is the name of the quote character.  QUOTE-CHAR is the
quotation character.  DOC is a description of the quote.
INNER-P non-nil means inner, nil means a."
  (declare (indent defun))
  `(helixel--define-mark-delimited :quote ,name
                                     ,quote-char ,quote-char
                                     ,doc ,inner-p))

(defmacro helixel-define-mark-object
    (name thing doc subcat &optional restricted-p)
  "Define mark inner/a functions for a text object.
NAME is the name of the text object.  DOC is a description of the
object.  THING should be a quoted symbol like \='helixel-word.
SUBCAT is the textobj subcat symbol (e.g. word, pair, quote).
RESTRICTED-P non-nil means use restricted version (for word/WORD)."
  (let ((inner-name (intern (format "helixel-mark-inner-%s" name)))
        (outer-name (intern (format "helixel-mark-a-%s" name)))
        (inner-doc (format "Select inner %s." doc))
        (outer-doc (format "Select a %s." doc))
        (inner-func (if restricted-p
                        'helixel-select-inner-restricted-object
                      'helixel-select-inner-object))
        (outer-func (if restricted-p
                        'helixel-select-a-restricted-object
                      'helixel-select-a-object)))
    `(progn
       (defun ,inner-name (&optional count)
         ,inner-doc
         (interactive "p")
         (when helixel-textobj-action-function
           (funcall helixel-textobj-action-function 'textobj ,subcat))
         (let ((use-bounds (helixel--use-region-p))
               (followup-p (and (use-region-p)
                                (eq (helixel--selection-type) 'textobj))))
           (cond
            (followup-p
             (goto-char (region-end))
             (skip-chars-forward " \t\n\r\f"))
            ((not use-bounds)
             (helixel--ensure-point-in-thing)))
           (let ((beg (when use-bounds (region-beginning)))
                 (end (when use-bounds (region-end))))
             (helixel--activate-textobj-range
              (,inner-func ,thing beg end count) nil count))))
       (defun ,outer-name (&optional count)
         ,outer-doc
         (interactive "p")
         (when helixel-textobj-action-function
           (funcall helixel-textobj-action-function 'textobj ,subcat))
         (let ((use-bounds (helixel--use-region-p))
               (followup-p (and (use-region-p)
                                (eq (helixel--selection-type) 'textobj))))
           (unless (or use-bounds followup-p)
             (helixel--ensure-point-in-thing))
           (let ((beg (when use-bounds (region-beginning)))
                 (end (when use-bounds (region-end))))
             (helixel--activate-textobj-range
              (,outer-func ,thing beg end count) nil count)))))))

(defmacro helixel-define-regex-textobj (name begin-re end-re
                                             &optional name-group
                                             subcat)
  "Define text object commands for blocks delimited by BEGIN-RE and END-RE.

NAME is a symbol for the command suffix (e.g. \='my-block).
BEGIN-RE and END-RE are the opening/closing delimiter regexps.
NAME-GROUP, if an integer, enables name-based matching using that group.
SUBCAT is the textobj subcat symbol (default: \='block)."
  (declare (indent defun))
  (let ((inner-name (intern (format "helixel-mark-inner-%s" name)))
        (outer-name (intern (format "helixel-mark-a-%s" name)))
        (inner-doc (format "Select inner %s." name))
        (outer-doc (format "Select a %s." name))
        (cat (or subcat 'block))
        (delimiter (helixel--make-regex-delimiter begin-re end-re name-group)))
    `(progn
       (defun ,inner-name (&optional count)
         ,inner-doc
         (interactive "p")
         (when helixel-textobj-action-function
           (funcall helixel-textobj-action-function 'textobj ,cat))
         (helixel--activate-textobj-range
          (helixel-select-regex-block
           ,begin-re ,end-re
           (when (helixel--use-region-p) (region-beginning))
           (when (helixel--use-region-p) (region-end))
           nil count nil ,name-group)
          ',delimiter
          count))
       (defun ,outer-name (&optional count)
         ,outer-doc
         (interactive "p")
         (when helixel-textobj-action-function
           (funcall helixel-textobj-action-function 'textobj ,cat))
         (helixel--activate-textobj-range
          (helixel-select-regex-block
           ,begin-re ,end-re
           (when (helixel--use-region-p) (region-beginning))
           (when (helixel--use-region-p) (region-end))
           nil count t ,name-group)
          ',delimiter
          count)))))

(provide 'helixel-textobj-defs)
;;; helixel-textobj-defs.el ends here
