;;; helixel-textobj-marks.el --- Text object commands, macros, defaults -*- lexical-binding: t; -*-

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

;;; Commentary:
;;
;; User-facing text-object surface:
;;
;;   * `helixel-define-mark-pair' / -quote / -object / -regex-textobj
;;     macros that expand into mark-inner-*/mark-a-* command pairs.
;;   * tag and block mark commands.
;;   * Tree-sitter helper.
;;   * All default mark registrations (word/WORD/symbol/sentence/
;;     paragraph/function/paren/bracket/brace/angle/single-quote/
;;     double-quote/back-quote/tilde/equal/underscore/slash/star/plus).
;;   * `textobj' kind registration.

;;; Code:

(require 'helixel-textobj-engine)
(require 'helixel-textobj-pair)
(require 'helixel-textobj-block)

(declare-function evil-textobj-tree-sitter--range
              "evil-textobj-tree-sitter-core" t t)
(declare-function evil-textobj-tree-sitter--message-not-found
              "evil-textobj-tree-sitter-core" t t)
(defvar evil-textobj-tree-sitter-use-next-if-not-within)

;; ============================================================================
;; Definition macros (define-mark-pair / -quote / -object / -regex-textobj)
;; ============================================================================

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

(defmacro helixel-define-mark-pair (name open close doc)
  "Define both `mark-inner-NAME' and `mark-a-NAME' for a bracket pair.
NAME is the name of the bracket pair.  OPEN and CLOSE are the
opening and closing delimiters.  DOC is a description of the pair."
  (declare (indent defun))
  `(progn
     (helixel--define-mark-delimited :pair ,name ,open ,close ,doc t)
     (helixel--define-mark-delimited :pair ,name ,open ,close ,doc nil)))

(defmacro helixel-define-mark-quote (name quote-char doc)
  "Define both `mark-inner-NAME' and `mark-a-NAME' for a quote char.
NAME is the name of the quote character.  QUOTE-CHAR is the quotation
character.  DOC is a description of the quote."
  (declare (indent defun))
  `(progn
     (helixel--define-mark-delimited
      :quote ,name ,quote-char ,quote-char ,doc t)
     (helixel--define-mark-delimited
      :quote ,name ,quote-char ,quote-char ,doc nil)))

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
                                (eq (helixel--region-type) 'textobj))))
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
                                (eq (helixel--region-type) 'textobj))))
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


;; ============================================================================
;; Tag mark commands
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

(helixel-define-mark-pair "paren" ?\( ?\) "parenthesis")
(helixel-define-mark-pair "bracket" ?\[ ?\] "bracket")
(helixel-define-mark-pair "brace" ?\{ ?\} "brace")
(helixel-define-mark-pair "angle" ?\< ?\> "angle")


(helixel-define-mark-quote "single-quote" ?' "single-quoted string")
(helixel-define-mark-quote "double-quote" ?\" "double-quoted string")
(helixel-define-mark-quote "back-quote" ?` "back-quoted string")

;; org-mode emphasis markers: ~code~ =verbatim= _underline_
;; /italic/ *bold* +strikethrough+
(helixel-define-mark-quote "tilde" ?~ "tilde-delimited string")
(helixel-define-mark-quote "equal" ?= "equal-delimited string")
(helixel-define-mark-quote "underscore"  ?_ "underscore-delimited string")
(helixel-define-mark-quote "slash" ?/ "slash-delimited string")
(helixel-define-mark-quote "star" ?* "star-delimited string")
(helixel-define-mark-quote "plus" ?+ "plus-delimited string")


(helixel-register-kind textobj
  :ctx-schema '(:required (:command :count :delimiter)
                :optional (:inline-advance))
  :recreate #'helixel--recreate-textobj
  :advance  #'helixel--repeat-advance-textobj
  :display  (lambda (ctx)
              (let ((cmd (helixel-sel-textobj-command ctx)))
                (if cmd
                    (let* ((name (symbol-name cmd))
                           (pos (string-match "mark-" name)))
                      (if pos (substring name (+ pos 5)) name))
                  "textobj"))))

(provide 'helixel-textobj-marks)
;;; helixel-textobj-marks.el ends here
