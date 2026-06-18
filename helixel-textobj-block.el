;;; helixel-textobj-block.el --- Regex / fenced block text objects -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

;; Author: jixiuf <https://github.com/jixiuf>
;; Keywords: convenience
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

;;; Commentary:
;;
;; Regex-defined block text objects: org #+begin_/#+end_ blocks,
;; markdown code fences, and any mode-specific begin/end delimiter
;; pair registered in `helixel-block-textobj-alist'.
;;
;; Public:
;;   helixel-block-textobj-alist            user spec table
;;   helixel-block-textobj-fallback-alist   bracket-search fallback
;;   helixel-up-regex-block                 climb to enclosing block
;;   helixel-select-regex-block             build a textobj selection
;;   helixel-up-block-at-point              dispatch by major mode
;;   helixel-select-block-at-point          ditto, as a select-block
;;   helixel-make-block-delimiter          delimiter constructor
;;   helixel-make-regex-delimiter          delimiter constructor
;;
;; Depends on engine (helixel-range, helixel-with-restriction,
;; helixel--block-chosen-spec) and pair (helixel-select-block).

;;; Code:

(require 'cl-lib)
(require 'helixel-core)              ; helixel--block-chosen-spec
(require 'helixel-textobj-engine)
(require 'helixel-textobj-pair)      ; helixel-select-block

;; ── Block-spec customs and helpers ──

(defcustom helixel-block-textobj-alist
  '((org-mode . ("^#\\+begin_\\([^ \n\r]+\\)[^\n]*"
                 "^#\\+end_\\([^ \n\r]+\\)[^\n]*" 1))
    (org-mode . ("^```.+$" "^```[ \t]*$" nil))
    (markdown-mode . ("^```.+$" "^```[ \t]*$" nil))
    (gfm-mode . ("^```.+$" "^```[ \t]*$" nil)))
  "Alist mapping major modes to block delimiter patterns for `mi c' / `ma c'.

Each entry has the form (MODE . (BEGIN-RE END-RE NAME-GROUP)).
You may have multiple entries for the same MODE; all matching
entries are tried and the tightest enclosing block is selected.

BEGIN-RE is a regexp matching the opening delimiter (e.g. `#+begin_src`).
END-RE is a regexp matching the closing delimiter (e.g. `#+end_src`).
NAME-GROUP is an integer specifying which capture group in both
  BEGIN-RE and END-RE holds the block name.  Use nil for
  counter-based matching (e.g. markdown ``` fences)."
  :type '(alist :key-type symbol
                :value-type
                (list (regexp :tag "Begin regexp")
                      (regexp :tag "End regexp")
                      (choice (integer :tag "Name capture group")
                              (const :tag "Counter-based" nil))))
  :group 'helixel)

(defcustom helixel-block-textobj-fallback-alist
  nil
  "Additional fallback block patterns for the current major mode.
Used when `helixel-block-textobj-alist' has no matching entry.

Each element has the form (MODE BEGIN-RE END-RE NAME-GROUP) where
MODE is currently reserved (use nil).  BEGIN-RE and END-RE are
regexps for the opening and closing delimiters.  NAME-GROUP nil
means counter-based balancing.

NOTE: bracket pairs (), [], {} are handled automatically via
`helixel-up-paren' (syntax-table aware, respects strings/comments).
You do not need to add them here.

When no spec from `helixel-block-textobj-alist' matches by
`derived-mode-p', this alist plus the built-in bracket pairs are
tried.  The tightest enclosing delimiter wins."
  :type '(alist :key-type (choice (const nil) symbol)
                :value-type
                (list (regexp :tag "Begin regexp")
                      (regexp :tag "End regexp")
                      (choice (integer :tag "Name capture group")
                              (const :tag "Counter-based" nil))))
  :group 'helixel)

(defvar helixel--block-no-bracket-fallback nil
  "Skip bracket pair fallback in `helixel-up-block-at-point'.
When non-nil, `helixel-up-block-at-point' does not fall back to
bracket pairs ((), [], {}).  Bound by callers that handle bracket pairs
through a different mechanism (e.g. `jump-to-match').")

(defun helixel--block-spec-at-point ()
  "Return the matching block spec (MODE . (BEGIN-RE END-RE ...)) at point.
Consults `helixel-block-textobj-alist' for the current major mode.
Returns nil when point is not on a block delimiter line.
Used by `helixel-jump-to-match' to distinguish fenced code-block
delimiters from single-char quotes, and by `helixel-up-block-at-point'."
  (let ((specs (cl-remove-if-not (lambda (e) (derived-mode-p (car e)))
                                 helixel-block-textobj-alist)))
    (catch 'found
      (dolist (spec specs)
        (let* ((data (cdr spec))
               (begin-re (nth 0 data))
               (end-re (nth 1 data)))
          (when (and begin-re end-re
                     (save-excursion
                       (beginning-of-line)
                       (or (looking-at begin-re)
                           (looking-at end-re))))
            (throw 'found spec)))))))

(defun helixel--block-adjust-for-jump ()
  "If point is on a block delimiter line, move inside the block.
On an opener line moves one line down; on a closer line moves
one line up."
  (when-let* ((spec (helixel--block-spec-at-point))
              (data (cdr spec))
              (begin-re (nth 0 data)))
    (if (save-excursion (beginning-of-line) (looking-at begin-re))
        (forward-line 1)
      (forward-line -1))))

(defun helixel--regex-adjust-for-jump (begin-re end-re)
  "If point is on a regex delimiter line, move inside.
BEGIN-RE and END-RE are the opening and closing patterns."
  (save-excursion (beginning-of-line)
                  (cond ((looking-at begin-re) (forward-line 1))
                        ((looking-at end-re) (forward-line -1)))))

;; ── Regex-block scanning ──

(defun helixel-up-regex-block (begin-re end-re &optional count name-group)
  "Move point past matching delimiters defined by BEGIN-RE and END-RE.

With positive COUNT, move forward COUNT levels.  With negative COUNT,
move backward |COUNT| levels.

If NAME-GROUP is an integer, only match blocks with the same name
captured by that regex group in both BEGIN-RE and END-RE (e.g., 1 for
`org-mode' #+begin_foo / #+end_foo).  The two regexps must capture the
block name in the same group number.

If NAME-GROUP is nil, use counter-based balancing: each BEGIN-RE match
increments the counter, each END-RE match decrements it.  When the
counter reaches zero, a matching pair has been found.  When BEGIN-RE
equals END-RE (e.g., markdown ``` fences), each match simply toggles
the counter.

Sets `match-data' on success so callers can extract the delimiter
bounds via `match-beginning' / `match-end'.

Returns 0 on success, or (* dir remaining) when not all levels found."
  (if name-group
      (helixel--up-regex-block-named begin-re end-re count name-group)
    (helixel--up-regex-block-counter begin-re end-re count)))

(defun helixel--regexp-group-count (regexp)
  "Count the number of \\(...\\) capture groups in REGEXP.
Handles escaped backslashes."
  (let ((count 0) (i 0) (len (length regexp)))
    (while (< i len)
      (when (and (eq (aref regexp i) ?\\)
                 (< (1+ i) len))
        (let ((next (aref regexp (1+ i))))
          (cond
           ((eq next ?\() (setq count (1+ count) i (1+ i)))
           ((eq next ?\\) (setq i (1+ i))))))
      (setq i (1+ i)))
    count))

(defun helixel--up-regex-block-named (begin-re end-re count name-group)
  "Named-block variant of `helixel-up-regex-block'.
COUNT specifies the number of levels to traverse.
NAME-GROUP specifies which capture group in BEGIN-RE and END-RE
contains the block name (1-based)."
  (let* ((dir (if (> count 0) +1 -1))
         (count (abs count))
         (orig (point))
         ;; In the combined regex \(begin-re\)\|\(end-re\):
         ;; - Group 1 = outer begin wrapper
         ;; - Groups 2..1+N = sub-groups of begin-re (N = ngroups in begin-re)
         ;; - Group 2+N = outer end wrapper
         ;; - Groups 3+N.. = sub-groups of end-re
         (ngroups-begin (helixel--regexp-group-count begin-re))
         (begin-outer 1)
         (end-outer   (+ 2 ngroups-begin))
         ;; Name groups within the combined regex (same for begin/end)
         (begin-name  (+ 1 name-group))
         (end-name    (+ end-outer name-group))
         ;; In forward direction: opener=begin, closer=end; backward swaps
         (op-outer (if (> dir 0) begin-outer end-outer))
         (op-name  (if (> dir 0) begin-name end-name))
         (cl-name  (if (> dir 0) end-name begin-name))
         pnt tags match
         (combined-re (concat "\\(" begin-re "\\)\\|\\(" end-re "\\)")))
    (catch 'done
      (while (> count 0)
        ;; Step 1: find the target closer/opener
        (while
            (and (setq match (re-search-forward combined-re nil t dir))
                 (cond
                  ((match-beginning op-outer)   ; found opener (in search dir)
                   (push (match-string op-name) tags))
                  ((null tags) nil) ; closer with empty stack: target
                  ((and (< dir 0)
                        (string= (car tags) (match-string cl-name)))
                   ;; backward: matching closer, pop; break if stack empty
                   (pop tags)
                   tags)
                  ((> dir 0)
                   ;; forward: pop matching closer (skip non-matching first)
                   (while (and tags
                               (not (string= (car tags)
                                             (match-string cl-name))))
                     (pop tags))
                   (pop tags)
                   tags)           ; break if stack now empty
                  (t t))))                       ; non-matching closer: skip
        (unless (setq match (and match (match-data t)))
          (setq match nil)
          (throw 'done count))
        ;; Step 2: find the matching counterpart from target position
        (cond
         ((> dir 0)
          (setq pnt (match-end 0))
          (goto-char (match-beginning 0)))
         (t
          (setq pnt (match-beginning 0))
          (goto-char (match-end 0))))
        (let* ((balanced-re (concat "\\(" begin-re "\\)\\|\\(" end-re "\\)"))
               (cnt 1))
          ;; Search for both begin and end, using the same formula as
          ;; helixel-up-xml-tag step 2.  Nesting is tracked purely by
          ;; the counter; names do not need filtering because the
          ;; begin/end alternation alone correctly balances nested
          ;; blocks in well-formed documents.
          (while (and (> cnt 0)
                      (re-search-forward balanced-re nil t (- dir)))
            (let ((is-begin (match-beginning begin-outer)))
              (setq cnt (+ cnt (if is-begin (- dir) dir)))))
          (if (zerop cnt)
              (setq count (1- count) tags nil)
            (goto-char pnt))))
      (if (> count 0)
          (set-match-data nil)
        (progn
          (set-match-data match)
          (goto-char (if (> dir 0) (match-end 0) (match-beginning 0))))))
    ;; not found: go to limit
    (unless (zerop count)
      (set-match-data nil)
      (goto-char (if (> dir 0) (point-max) (point-min)))
      (when (/= (point) orig)
        (setq count (1- count))))
    (* dir count)))

(defun helixel--up-regex-block-counter (begin-re end-re count)
  "Counter-based variant of `helixel-up-regex-block'.
BEGIN-RE and END-RE are regexps for the opening and closing delimiters.
COUNT specifies the number of levels to traverse."
  (let* ((dir (if (> count 0) +1 -1))
         (remaining (abs count)))
    (if (string= begin-re end-re)
        ;; Simple: each match is both open and close, just toggle
        (let ((match nil))
          (while (> remaining 0)
            (setq match (re-search-forward begin-re nil t dir))
            (if match
                (progn
                  (setq remaining (1- remaining))
                  (unless (zerop remaining)
                    (goto-char (if (> dir 0)
                                   (match-end 0)
                                 (match-beginning 0)))))
              (goto-char (if (> dir 0) (point-max) (point-min)))
              (setq remaining 0)))
          (if match
              (progn
                (set-match-data (list (match-beginning 0) (match-end 0)))
                0)
            (* dir 1)))
      ;; Different begin/end: balanced counter
      (let ((balanced-re (concat "\\(" begin-re "\\)\\|\\(" end-re "\\)"))
            match)
        (while (> remaining 0)
          (setq match (re-search-forward balanced-re nil t dir))
          (unless match
            (goto-char (if (> dir 0) (point-max) (point-min)))
            (setq remaining 0))
          (when match
            (if (match-beginning 1)
                ;; Found begin: going forward = deeper nesting,
                ;; going backward = target
                (if (> dir 0)
                    (setq remaining (1+ remaining))
                  (setq remaining (1- remaining)))
              ;; Found end: going forward = target,
              ;; going backward = deeper nesting
              (if (> dir 0)
                  (setq remaining (1- remaining))
                (setq remaining (1+ remaining))))
            (when (> remaining 0)
              (goto-char (if (> dir 0) (match-end 0) (match-beginning 0))))))
        (if (and match (zerop remaining))
            (progn (set-match-data (list (match-beginning 0) (match-end 0))) 0)
          (* dir (if match remaining 1)))))))

(defun helixel-select-regex-block (begin-re end-re beg end type count
                                            &optional inclusive name-group)
  "Return a range of COUNT delimited blocks defined by BEGIN-RE and END-RE.

BEG END TYPE are the currently selected (visual) range.
If INCLUSIVE is non-nil, the delimiters are included; otherwise excluded.
NAME-GROUP, if an integer, enables name-based matching using that group."
  (helixel-select-block
   (lambda (&optional cnt)
     (helixel-up-regex-block begin-re end-re cnt name-group))
   beg end type count inclusive))

;; ── Block-at-point user entry points ──

(defun helixel-up-block-at-point (&optional count)
  "Move point past the nearest matching block delimiter.

COUNT specifies the number of block levels to traverse.
Consults `helixel-block-textobj-alist' and tries every pattern
whose MODE satisfies `derived-mode-p'.  The tightest enclosing
delimiter wins, so nested blocks of different types (e.g. a
markdown ``` fence inside an org #+begin_ai block) resolve to
the innermost one.

When no mode-specific entry matches, bracket pairs (), [], {}
are tried via `helixel-up-paren' (syntax-table aware, respects
strings and comments).  Additional patterns from
`helixel-block-textobj-fallback-alist' are also tried.

When `helixel--block-chosen-spec' is non-nil the previously chosen
spec is reused directly (for consistency across the +1/-1 calls
made by `helixel-select-block').

Returns 0 on success, non-zero if not all levels found."
  (if helixel--block-chosen-spec
      ;; Subsequent call: reuse the remembered spec
      (if (characterp (car helixel--block-chosen-spec))
          ;; Bracket spec: (OPEN . CLOSE)
          (helixel-up-paren (car helixel--block-chosen-spec)
                            (cdr helixel--block-chosen-spec)
                            count)
        ;; Regex spec: (BEGIN-RE END-RE . NAME-GROUP)
        (apply #'helixel-up-regex-block
               (nth 0 helixel--block-chosen-spec)
               (nth 1 helixel--block-chosen-spec)
               count (cddr helixel--block-chosen-spec)))
    ;; First call: try all matching specs, pick nearest
    (let* ((dir (if (> (or count 1) 0) +1 -1))
           (orig (point))
           (mode-specs (cl-remove-if-not
                        (lambda (entry) (derived-mode-p (car entry)))
                        helixel-block-textobj-alist))
           (fallback-needed (null mode-specs))
           ;; When no mode-specific spec matches, collect fallback regex specs
           (regex-specs (if fallback-needed
                            (cl-remove-if-not
                             (lambda (entry)
                               (or (null (car entry))
                                   (derived-mode-p (car entry))))
                             helixel-block-textobj-fallback-alist)
                          mode-specs))
           ;; Built-in bracket pairs (syntax-aware, only in fallback mode)
           (bracket-pairs (when (and fallback-needed
                                     (not helixel--block-no-bracket-fallback))
                            '((?\( . ?\)) (?\[ . ?\]) (?\{ . ?\}))))
           best-spec best-dist best-match-data)
      (when (and (null regex-specs) (null bracket-pairs))
        (user-error "No block text object for %s" major-mode))
      ;; Try regex-based specs
      (dolist (spec regex-specs)
        (goto-char orig)
        (let* ((spec-data (cdr spec))
               (result (apply #'helixel-up-regex-block
                              (nth 0 spec-data) (nth 1 spec-data)
                              count (cddr spec-data))))
          (when (and (zerop result) (match-beginning 0))
            (let ((dist (abs (- (match-beginning 0) orig))))
              (when (or (null best-dist) (< dist best-dist))
                (setq best-dist dist
                      best-spec (cons 'regex spec-data)
                      best-match-data (match-data)))))))
      ;; Try bracket pairs via syntax-aware helixel-up-paren
      (dolist (paren bracket-pairs)
        (goto-char orig)
        (let ((result (condition-case nil
                          (helixel-up-paren (car paren) (cdr paren) count)
                        (error nil))))
          (when (and result (zerop result) (match-beginning 0))
            (let ((dist (abs (- (match-beginning 0) orig))))
              (when (or (null best-dist) (< dist best-dist))
                (setq best-dist dist
                      best-spec (cons 'paren paren)
                      best-match-data (match-data)))))))
      (if best-spec
          (progn
            (setq helixel--block-chosen-spec
                  (if (eq (car best-spec) 'paren)
                      (cdr best-spec)
                    (cdr best-spec)))
            (set-match-data best-match-data)
            (goto-char (if (> dir 0)
                           (match-end 0)
                         (match-beginning 0)))
            0)
        (user-error "No block text object for %s" major-mode)))))

(defun helixel-select-block-at-point (beg end type count &optional inclusive)
  "Select block delimited text for the current major mode.

BEG and END are the region boundaries.  TYPE is the selection type.
COUNT specifies the number of block levels to traverse.
INCLUSIVE determines whether the selection includes the delimiters.
See `helixel-up-block-at-point' for supported modes."
  (unless inclusive (setq inclusive 'exclusive-line))
  (unwind-protect
      (helixel-select-block #'helixel-up-block-at-point
                            beg end type count inclusive)
    (setq helixel--block-chosen-spec nil)))


;; ── Delimiter constructors ──

(defun helixel-make-block-delimiter (&optional open close)
  "Create a block delimiter for OPEN and CLOSE strings.
OPEN and CLOSE are display/accessor values; the actual finder always
resolves the spec from `helixel-block-textobj-alist' for the current
mode at call time (via `helixel-up-block-at-point')."
  (list :type 'regex
        :open (or open
                  (let ((specs (cl-remove-if-not
                                (lambda (e) (derived-mode-p (car e)))
                                helixel-block-textobj-alist)))
                    (when specs (nth 0 (cdr (car specs))))))
        :close (or close
                  (let ((specs (cl-remove-if-not
                                (lambda (e) (derived-mode-p (car e)))
                                helixel-block-textobj-alist)))
                    (when specs (nth 1 (cdr (car specs))))))
        :finder (lambda (dir) (helixel-up-block-at-point dir))
        :adjust-for-jump #'helixel--block-adjust-for-jump
        :nl-p t))

(defun helixel-make-regex-delimiter (begin-re end-re &optional name-group)
  "Create a regex delimiter for BEGIN-RE and END-RE.
Optional NAME-GROUP specifies the match group index for the name."
  (list :type 'regex
        :open begin-re :close end-re
        :begin-re begin-re :end-re end-re
        :name-group name-group
        :finder `(lambda (dir)
                   (helixel-up-regex-block ,begin-re ,end-re dir ,name-group))
        :adjust-for-jump
        `(lambda ()
           (helixel--regex-adjust-for-jump ,begin-re ,end-re))
        :nl-p t))



(provide 'helixel-textobj-block)
;;; helixel-textobj-block.el ends here
