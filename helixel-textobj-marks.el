;;; helixel-textobj-marks.el --- Text object mark commands -*- lexical-binding: t; -*-

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
;; Text object mark commands and default registrations for Helixel.
;; User-facing mark-inner-*/mark-a-* commands and their default
;; registrations via define-mark-pair/-quote/-object macros.
;;

;;; Code:

(require 'helixel-textobj-engine)
(require 'helixel-textobj-defs)

(declare-function evil-textobj-tree-sitter--range
              "evil-textobj-tree-sitter-core" t t)
(declare-function evil-textobj-tree-sitter--message-not-found
              "evil-textobj-tree-sitter-core" t t)
(defvar evil-textobj-tree-sitter-use-next-if-not-within)


;; ============================================================================
;; tag Text Objects
;; ============================================================================

(defun helixel-mark-inner-tag (&optional count)
  "Select inner tag.
COUNT is the number of tags to select."
  (interactive "p")
  (when helixel-textobj-action-function
    (funcall helixel-textobj-action-function 'textobj 'tag))
  (helixel--activate-textobj-range
   (helixel-select-xml-tag
    (when (helixel--use-region-p) (region-beginning))
    (when (helixel--use-region-p) (region-end))
    nil count nil)
   (helixel--make-tag-delimiter)
   count))
(defun helixel-mark-a-tag (&optional count)
  "Select a tag.
COUNT is the number of tags to select."
  (interactive "p")
  (when helixel-textobj-action-function
    (funcall helixel-textobj-action-function 'textobj 'tag))
  (helixel--activate-textobj-range
   (helixel-select-xml-tag
    (when (helixel--use-region-p) (region-beginning))
    (when (helixel--use-region-p) (region-end))
    nil count t)
   (helixel--make-tag-delimiter)
   count))

;; ============================================================================
;; Generic Block Text Objects (org blocks, markdown fences, etc.)
;; ============================================================================


(defun helixel-mark-inner-block (&optional count)
  "Select inner block (org block, markdown fence, etc.).
COUNT is the number of blocks to select."
  (interactive "p")
  (when helixel-textobj-action-function
    (funcall helixel-textobj-action-function 'textobj 'block))
  (helixel--activate-textobj-range
   (helixel-select-block-at-point
    (when (helixel--use-region-p) (region-beginning))
    (when (helixel--use-region-p) (region-end))
    nil count nil)
   (helixel--make-block-delimiter)
   count))

(defun helixel-mark-a-block (&optional count)
  "Select a block (org block, markdown fence, etc.).
COUNT is the number of blocks to select."
  (interactive "p")
  (when helixel-textobj-action-function
    (funcall helixel-textobj-action-function 'textobj 'block))
  (helixel--activate-textobj-range
   (helixel-select-block-at-point
    (when (helixel--use-region-p) (region-beginning))
    (when (helixel--use-region-p) (region-end))
    nil count t)
   (helixel--make-block-delimiter)
   count))

(defun helixel-get-tree-sitter-textobj (group &optional query)
  "Return a command for a tree-sitter text object of GROUP.

GROUP is a string like \"function.inner\" or a list thereof.
If multiple groups are passed, the first available one is used.
QUERY is an optional alist mapping major-mode to custom query strings.

The returned command can be bound in `helixel-textobj-inner-map'
or `helixel-textobj-outer-map'.
Requires `evil-textobj-tree-sitter' to be installed.

Example:
  (define-key helixel-textobj-inner-map \"f\"
    (helixel-textobj-tree-sitter-get-textobj \"function.inner\"))
  (define-key helixel-textobj-outer-map \"f\"
    (helixel-textobj-tree-sitter-get-textobj \"function.outer\"))"
  (when (or (featurep 'evil-textobj-tree-sitter-core)
            (require 'evil-textobj-tree-sitter-core nil t))
    (let* ((groups (if (listp group) group (list group)))
           (interned-groups (mapcar #'intern groups)))
      (lambda (&optional count)
        (interactive "p")
        (when helixel-textobj-action-function
          (funcall helixel-textobj-action-function 'textobj 'treesit))
        (let ((range (evil-textobj-tree-sitter--range

                      count interned-groups query)))
          (if range
              (helixel--activate-textobj-range range nil count)
            (evil-textobj-tree-sitter--message-not-found groups)))))))

(helixel-define-mark-object "word" 'helixel-word "word" 'word t)
(helixel-define-mark-object "WORD" 'helixel-WORD "WORD" 'WORD t)
(helixel-define-mark-object "symbol" 'helixel-symbol "symbol" 'symbol)
(helixel-define-mark-object "sentence" 'helixel-sentence "sentence" 'sentence)
(helixel-define-mark-object "paragraph" 'helixel-paragraph
                            "paragraph" 'paragraph)

;; ============================================================================
;; Function Text Objects
;; ============================================================================

(helixel-define-mark-object "function" 'helixel-function
                            "function" 'function)

(helixel-define-mark-pair "paren" ?\( ?\) "parenthesis" t)
(helixel-define-mark-pair "paren" ?\( ?\) "parenthesis" nil)
(helixel-define-mark-pair "bracket" ?\[ ?\] "bracket" t)
(helixel-define-mark-pair "bracket" ?\[ ?\] "bracket" nil)
(helixel-define-mark-pair "brace" ?\{ ?\} "brace" t)
(helixel-define-mark-pair "brace" ?\{ ?\} "brace" nil)
(helixel-define-mark-pair "angle" ?\< ?\> "angle" t)
(helixel-define-mark-pair "angle" ?\< ?\> "angle" nil)


(helixel-define-mark-quote "single-quote" ?' "single-quoted string" t)
(helixel-define-mark-quote "single-quote" ?' "single-quoted string" nil)
(helixel-define-mark-quote "double-quote" ?\" "double-quoted string" t)
(helixel-define-mark-quote "double-quote" ?\" "double-quoted string" nil)
(helixel-define-mark-quote "back-quote" ?` "back-quoted string" t)
(helixel-define-mark-quote "back-quote" ?` "back-quoted string" nil)

;; org-mode emphasis markers: ~code~ =verbatim= _underline_
;; /italic/ *bold* +strikethrough+
(helixel-define-mark-quote "tilde" ?~ "tilde-delimited string" t)
(helixel-define-mark-quote "tilde" ?~ "tilde-delimited string" nil)
(helixel-define-mark-quote "equal" ?= "equal-delimited string" t)
(helixel-define-mark-quote "equal" ?= "equal-delimited string" nil)
(helixel-define-mark-quote "underscore"  ?_ "underscore-delimited string" t)
(helixel-define-mark-quote "underscore"  ?_ "underscore-delimited string" nil)
(helixel-define-mark-quote "slash" ?/ "slash-delimited string" t)
(helixel-define-mark-quote "slash" ?/ "slash-delimited string" nil)
(helixel-define-mark-quote "star" ?* "star-delimited string" t)
(helixel-define-mark-quote "star" ?* "star-delimited string" nil)
(helixel-define-mark-quote "plus" ?+ "plus-delimited string" t)
(helixel-define-mark-quote "plus" ?+ "plus-delimited string" nil)


(helixel-register-kind textobj
  :recreate nil
  :advance  #'helixel--repeat-advance-textobj
  :display  (lambda (ctx) (symbol-name (helixel-sel-textobj-command ctx))))

(provide 'helixel-textobj-marks)
;;; helixel-textobj-marks.el ends here
