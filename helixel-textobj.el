;;; helixel-textobj.el --- Text objects for Helixel  -*- lexical-binding: t; -*-

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

;; Text objects for Helixel Mode.

;;; Code:

(require 'cl-lib)
(require 'thingatpt)
(require 'helixel-core)

(defvar helixel-textobj-visual-state-p-function nil
  "If non-nil, called with no args, return t when in visual state.")

(defvar helixel-textobj-after-select-functions nil
  "Hook run after a textobj selection is activated.
Called with no arguments.  Use this to chain operations that need
a textobj selection to be in place (e.g. pending surround ops).")


;; ============================================================================

;; Internal Variables and Configuration
;; ============================================================================

(defvar helixel-restriction-stack nil
  "List of previous restrictions for helixel-with-restriction macro.")

(defcustom helixel-cjk-word-separating-categories
  '(;; Kanji
    (?C . ?H) (?C . ?K) (?C . ?k) (?C . ?A) (?C . ?G)
    ;; Hiragana
    (?H . ?C) (?H . ?K) (?H . ?k) (?H . ?A) (?H . ?G)
    ;; Katakana
    (?K . ?C) (?K . ?H) (?K . ?k) (?K . ?A) (?K . ?G)
    ;; half-width Katakana
    (?k . ?C) (?k . ?H) (?k . ?K) ; (?k . ?A) (?k . ?G)
    ;; full-width alphanumeric
    (?A . ?C) (?A . ?H) (?A . ?K) ; (?A . ?k) (?A . ?G)
    ;; full-width Greek
    (?G . ?C) (?G . ?H) (?G . ?K) ; (?G . ?k) (?G . ?A)
    )
  "List of pair (cons) of categories for word boundary detection in CJK.
See the documentation of `word-separating-categories'."
  :type '(alist :key-type (choice character (const nil))
                :value-type (choice character (const nil)))
  :group 'helixel)

(defcustom helixel-cjk-word-combining-categories
  '(;; default value in word-combining-categories
    (nil . ?^) (?^ . nil)
    ;; Roman
    (?r . ?k) (?r . ?A) (?r . ?G)
    ;; half-width Katakana
    (?k . ?r) (?k . ?A) (?k . ?G)
    ;; full-width alphanumeric
    (?A . ?r) (?A . ?k) (?A . ?G)
    ;; full-width Greek
    (?G . ?r) (?G . ?k) (?G . ?A))
  "List of pair (cons) of categories for word boundary detection in CJK.
See the documentation of `word-combining-categories'."
  :type '(alist :key-type (choice character (const nil))
                :value-type (choice character (const nil)))
  :group 'helixel)

;; ============================================================================
;; Macro and Helper Functions (copied from evil-common.el)
;; ============================================================================

(defmacro helixel-motion-loop (spec &rest body)
  "Loop a certain number of times.
SPEC is a list (VAR COUNT [RESULT]).
Evaluate BODY repeatedly COUNT times with VAR bound to 1 or -1,
depending on the sign of COUNT.  Set RESULT, if specified, to the
number of unsuccessful iterations, which is 0 if the loop completes
successfully.  This is also the return value.

Each iteration must move point; if point does not change, the loop
immediately quits.

\(fn (VAR COUNT [RESULT]) BODY...)"
  (declare (indent defun)
           (debug ((symbolp form &optional symbolp) body)))
  (let* ((var (or (pop spec) (make-symbol "unitvar")))
         (count (or (pop spec) 0))
         (result (or (pop spec) var))
         (i (make-symbol "loopvar")))
    `(let* ((,i ,count)
            (,var (if (< ,i 0) -1 1)))
       (while (and (/= ,i 0)
                   (/= (point) (progn ,@body (point))))
         (setq ,i (if (< ,i 0) (1+ ,i) (1- ,i))))
       (setq ,result ,i))))

(defmacro helixel-with-restriction (beg end &rest body)
  "Execute BODY with the buffer narrowed to BEG and END.
BEG or END may be nil to specify a one-sided restriction."
  (declare (indent 2) (debug t))
  `(save-restriction
     (let ((helixel-restriction-stack
            (cons (cons (point-min) (point-max)) helixel-restriction-stack)))
       (narrow-to-region (or ,beg (point-min)) (or ,end (point-max)))
       ,@body)))

(defun helixel-forward-chars (chars &optional count)
  "Move point to the end or beginning of a sequence of CHARS.
CHARS is a character set as inside [...] in a regular expression.
COUNT is the number of sequences to move over."
  (let ((notchars (if (= (aref chars 0) ?^)
                      (substring chars 1)
                    (concat "^" chars))))
    (helixel-motion-loop (dir (or count 1))
      (cond
       ((< dir 0)
        (skip-chars-backward notchars)
        (skip-chars-backward chars))
       (t
        (skip-chars-forward notchars)
        (skip-chars-forward chars))))))

(defun helixel-forward-nearest (count &rest forwards)
  "Move point forward to the first of several motions.
FORWARDS is a list of forward motion functions (i.e. each moves
point forward to the next end of a text object (if passed a +1)
or backward to the preceeding beginning of a text object (if
passed a -1)).  This function calls each of these functions once
and moves point to the nearest of the resulting positions.  If
COUNT is positive point is moved forward COUNT times, if negative
point is moved backward -COUNT times."
  (helixel-motion-loop (dir (or count 1))
    (let ((pnt (point))
          (nxt (if (< dir 0) (point-min) (point-max))))
      (dolist (fwd forwards)
        (goto-char pnt)
        (ignore-errors
          (helixel-with-restriction
              (when (< dir 0)
                (save-excursion
                  (goto-char nxt)
                  (line-beginning-position 0)))
              (when (> dir 0)
                (save-excursion
                  (goto-char nxt)
                  (line-end-position 2)))
            (and (zerop (funcall fwd dir))
                 (/= (point) pnt)
                 (if (< dir 0) (> (point) nxt) (< (point) nxt))
                 (setq nxt (point))))))
      (goto-char nxt))))

(defun helixel--forward-empty-line (&optional count)
  "Move forward COUNT empty lines."
  (setq count (or count 1))
  (cond
   ((> count 0)
    (while (and (> count 0) (not (eobp)))
      (when (and (bolp) (eolp))
        (setq count (1- count)))
      (forward-line 1)))
   (t
    (while (and (< count 0) (not (bobp))
                (zerop (forward-line -1)))
      (when (and (bolp) (eolp))
        (setq count (1+ count))))))
  count)

(defun helixel--forward-word (&optional count)
  "Move forward COUNT words.
Moves point COUNT words forward or (- COUNT) words backward if
COUNT is negative.  Point is placed after the end of the word (if
forward) or at the first character of the word (if backward).  A
word is a sequence of word characters matching
\[[:word:]] (recognized by `forward-word'), a sequence of
non-whitespace non-word characters '[^[:word:]\\n\\r\\t\\f ]', or
an empty line matching ^$."
  (helixel-forward-nearest
   count
   #'(lambda (&optional cnt)
       (let ((word-separating-categories helixel-cjk-word-separating-categories)
             (word-combining-categories helixel-cjk-word-combining-categories)
             (pnt (point)))
         (forward-word cnt)
         (if (= pnt (point)) cnt 0)))
   #'(lambda (&optional cnt)
       (helixel-forward-chars "^[:word:]\n\r\t\f " cnt))
   #'helixel--forward-empty-line))
(put 'helixel-word 'forward-op #'helixel--forward-word)

(defun helixel--forward-WORD (&optional count)
  "Move forward COUNT \"WORDS\".
Moves point COUNT WORDS forward or (- COUNT) WORDS backward if
COUNT is negative.  Point is placed after the end of the WORD (if
forward) or at the first character of the WORD (if backward).  A
WORD is a sequence of non-whitespace characters
'[^\\n\\r\\t\\f ]', or an empty line matching ^$."
  (helixel-forward-nearest count
                           #'(lambda (&optional cnt)
                               (helixel-forward-chars "^\n\r\t\f " cnt))
                           #'helixel--forward-empty-line))
(put 'helixel-WORD 'forward-op #'helixel--forward-WORD)

(defun helixel--forward-beginning (thing &optional count)
  "Move forward to beginning of THING.
The motion is repeated COUNT times.
When the current THING ends at end of line (but not end of buffer),
do not cross the newline; stop at the end of the current THING instead."
  (setq count (or count 1))
  (if (< count 0)
      (let ((pt (point)))
        (forward-thing thing count)
        (when (< (point) pt) (point)))
    (let ((bnd (bounds-of-thing-at-point thing))
          (pt (point))
          (inside-word nil))
      (when (and bnd (< (point) (cdr bnd)))
        (setq inside-word t)
        (goto-char (cdr bnd)))
      ;; Skip forward movement when inside a word at end of line,
      ;; unless we are at eob AND extending an existing region.
      (unless (and inside-word (eolp)
                   (not (and (eobp) (use-region-p))))
        (ignore-errors
          (forward-thing thing count)
          (setq bnd (bounds-of-thing-at-point thing))
          (when (and bnd (not (bobp))
                     (not (and (bolp) (eobp))))
            (backward-char))
          (when bnd (beginning-of-thing thing))
          (when (> (point) pt) pt))))))

(defun helixel--forward-end (thing &optional count backward-char-p)
  "Move forward to end of THING.
The motion is repeated COUNT times.
When BACKWARD-CHAR-P is non-nil, adjust point by one char after motion."
  (setq count (or count 1))
  (if (> count 0)
      (let ((pt (point)))
        (when (and backward-char-p) (not (eobp))
              (forward-char))
        (prog2
            (forward-thing thing count)
            (when (> (point) pt) (point))
          (when (and backward-char-p (not (bobp)))
            (backward-char))))
    (unless (bobp) (forward-char -1))
    (let ((bnd (bounds-of-thing-at-point thing))
          (pt (point)))
      (when (and bnd (<= (point) (cdr bnd) ))
        (goto-char (car bnd)))
      (ignore-errors
        (forward-thing thing count)
        (setq bnd (bounds-of-thing-at-point thing))
        (if bnd
            (prog2 (end-of-thing thing) (point)
              (when backward-char-p (backward-char)))
          (when (< (point) pt) (point)))))))

(defun helixel-forward-not-thing (thing &optional count)
  "Move point to the end or beginning of the complement of THING.
COUNT is the number of complements to move over."
  (helixel-motion-loop (dir (or count 1))
    (let (bnd)
      (cond
       ((> dir 0)
        (while (and (setq bnd (bounds-of-thing-at-point thing))
                    (< (point) (cdr bnd)))
          (goto-char (cdr bnd)))
        ;; no thing at (point)
        (if (zerop (forward-thing thing))
            ;; now at the end of the next thing
            (let ((bnd (bounds-of-thing-at-point thing)))
              (if (or (< (car bnd) (point))    ; end of a thing
                      (= (car bnd) (cdr bnd))) ; zero width thing
                  (goto-char (car bnd))
                ;; beginning of yet another thing, go back
                (forward-thing thing -1)))
          (goto-char (point-max))))
       (t
        (while (and (not (bobp))
                    (setq bnd (progn (backward-char)
                                     (bounds-of-thing-at-point thing)))
                    (< (point) (cdr bnd)))
          (goto-char (car bnd)))
        ;; either bob or no thing at point
        (goto-char
         (if (and (not (bobp))
                  (zerop (forward-thing thing -1))
                  (setq bnd (bounds-of-thing-at-point thing)))
             (cdr bnd)
           (point-min))))))))

(defun helixel-bounds-of-not-thing-at-point (thing &optional which)
  "Return the bounds of a complement of THING at point.
If there is a THING at point nil is returned.  Otherwise if WHICH
is nil or 0 a cons cell (BEG .  END) is returned.  If WHICH is
negative the beginning is returned.  If WHICH is positive the END
is returned."
  (let ((pnt (point)))
    (let ((beg (save-excursion
                 (and (zerop (forward-thing thing -1))
                      (forward-thing thing))
                 (if (> (point) pnt) (point-min) (point))))
          (end (save-excursion
                 (and (zerop (forward-thing thing))
                      (forward-thing thing -1))
                 (if (< (point) pnt) (point-max) (point)))))
      (when (and (<= beg (point) end) (< beg end))
        (cond
         ((or (not which) (zerop which)) (cons beg end))
         ((< which 0) beg)
         ((> which 0) end))))))

(defun helixel-select-inner-object (thing beg end &optional count)
  "Return an inner text object range of COUNT objects.
If COUNT is positive, return objects following point; if COUNT is
negative, return objects preceding point.  If one is unspecified,
the other is used with a negative argument.  THING is a symbol
understood by `thing-at-point'.  BEG, END specify the current
selection."
  (let* ((count (or count 1))
         (bnd (or (let ((b (bounds-of-thing-at-point thing)))
                    (and b (< (point) (cdr b)) b))
                  (helixel-bounds-of-not-thing-at-point thing)
                  (cons (point-min) (point-max)))))
    ;; check if current object is selected
    (when (or (not beg) (not end)
              (> beg (car bnd))
              (< end (cdr bnd)))
      (when (or (not beg) (< (car bnd) beg)) (setq beg (car bnd)))
      (when (or (not end) (> (cdr bnd) end)) (setq end (cdr bnd)))
      (setq count (if (> count 0) (1- count) (1+ count))))
    (goto-char (if (< count 0) beg end))
    (helixel-forward-nearest count
                             #'(lambda (cnt) (forward-thing thing cnt))
                             #'(lambda (cnt)
                                 (helixel-forward-not-thing thing cnt)))
    (cons (if (>= count 0) beg (point))
          (if (< count 0) end (point)))))

(defun helixel-select-a-object (thing beg end &optional count)
  "Return an outer text object range of COUNT objects.
If COUNT is positive, return objects following point; if COUNT is
negative, return objects preceding point.  If one is unspecified,
the other is used with a negative argument.  THING is a symbol
understood by `thing-at-point'.  BEG, END specify the current
selection."
  (let* ((dir (if (> (or count 1) 0) +1 -1))
         (count (abs (or count 1)))
         (objbnd (let ((b (bounds-of-thing-at-point thing)))
                   (and b (< (point) (cdr b)) b)))
         (bnd (or objbnd
                  (helixel-bounds-of-not-thing-at-point thing)
                  (cons (point-min) (point-max))))
         addcurrent other)
    ;; check if current object is not selected
    (when (or (not beg) (not end)
              (> beg (car bnd))
              (< end (cdr bnd)))
      ;; if not, enlarge selection
      (when (or (not beg) (< (car bnd) beg)) (setq beg (car bnd)))
      (when (or (not end) (> (cdr bnd) end)) (setq end (cdr bnd)))
      (if objbnd (setq addcurrent t)))
    ;; make other and (point) reflect the selection
    (cond
     ((> dir 0) (goto-char end) (setq other beg))
     (t (goto-char beg) (setq other end)))
    (cond
     ;; do nothing more than only current is selected
     ((not (and (= beg (car bnd)) (= end (cdr bnd)))))
     ;; current match is thing, add whitespace
     (objbnd
      (let ((wsend (helixel-with-restriction
                       ;; restrict to current line if we do non-line selection
                       (line-beginning-position)
                       (line-end-position)
                     (helixel-bounds-of-not-thing-at-point thing dir))))
        (cond
         (wsend
          ;; add whitespace at end
          (goto-char wsend)
          (setq addcurrent t))
         (t
          ;; no whitespace at end, try beginning
          (save-excursion
            (goto-char other)
            (setq wsend
                  (helixel-with-restriction
                      ;; restrict to current line if we do non-line selection
                      (if (member thing '(helixel-word helixel-WORD))
                          (save-excursion (back-to-indentation) (point))
                        (line-beginning-position))
                      (line-end-position)
                    (helixel-bounds-of-not-thing-at-point thing (- dir))))
            (when wsend (setq other wsend addcurrent t)))))))
     ;; current match is whitespace, add thing
     (t
      (forward-thing thing dir)
      (setq addcurrent t)))
    ;; possibly count current object as selection
    (if addcurrent (setq count (1- count)))
    ;; move
    (dotimes (_ count)
      (let ((wsend (helixel-bounds-of-not-thing-at-point thing dir)))
        (if (and wsend (/= wsend (point)))
            ;; start with whitespace
            (forward-thing thing dir)
          ;; start with thing
          (forward-thing thing dir)
          (setq wsend (helixel-bounds-of-not-thing-at-point thing dir))
          (when wsend (goto-char wsend)))))
    ;; return range
    (cons (if (> dir 0) other (point))
          (if (< dir 0) other (point)))))

(defun helixel-select-inner-restricted-object (thing beg end &optional count)
  "Return an inner text object range of COUNT objects.
Selection is restricted to the current line, unless it is empty.
If COUNT is positive, return objects following point; if COUNT is
negative, return objects preceding point.  If one is unspecified,
the other is used with a negative argument.  THING is a symbol
understood by `thing-at-point'.  BEG, END specify the current
selection."
  (save-restriction
    (let ((start (line-beginning-position))
          (end (line-end-position)))
      (unless (= start end)
        (narrow-to-region start end)))
    (helixel-select-inner-object thing beg end count)))

(defun helixel-select-a-restricted-object (thing beg end &optional count)
  "Return an outer text object range of COUNT objects.
Selection is restricted to the current line, unless it is empty.
If COUNT is positive, return objects following point; if COUNT is
negative, return objects preceding point.  If one is unspecified,
the other is used with a negative argument.  THING is a symbol
understood by `thing-at-point'.  BEG, END specify the current
selection."
  (save-restriction
    (let ((start (line-beginning-position))
          (end (line-end-position)))
      (when (/= start end)
        (narrow-to-region start end)))
    (helixel-select-a-object thing beg end count)))

;; ============================================================================
;; Text Object Interactive Commands
;; ============================================================================

;; ============================================================================
;; Text Object Interactive Commands (now defined via helixel-define-mark-object)
;; ============================================================================

(defun helixel--forward-symbol (&optional count)
  "Move forward COUNT symbols.
Moves point COUNT symbols forward or (- COUNT) symbols backward
if COUNT is negative.  Point is placed after the end of the
symbol (if forward) or at the first character of the symbol (if
backward).  A symbol is either determined by `forward-symbol', or
is a sequence of characters not in the word, symbol or whitespace
syntax classes."
  (helixel-forward-nearest
   count
   #'(lambda (&optional cnt)
       (helixel-forward-syntax "^w_->" cnt))
   #'(lambda (&optional cnt)
       (let ((pnt (point)))
         (forward-symbol cnt)
         (if (= pnt (point)) cnt 0)))
   #'helixel--forward-empty-line))
(put 'helixel-symbol 'forward-op #'helixel--forward-symbol)

(defun helixel-forward-syntax (syntax &optional count)
  "Move point to the end or beginning of a sequence of characters in SYNTAX.
Stop on reaching a character not in SYNTAX.
COUNT is the number of sequences to move over."
  (let ((notsyntax (if (= (aref syntax 0) ?^)
                       (substring syntax 1)
                     (concat "^" syntax))))
    (helixel-motion-loop (dir (or count 1))
      (cond
       ((< dir 0)
        (skip-syntax-backward notsyntax)
        (skip-syntax-backward syntax))
       (t
        (skip-syntax-forward notsyntax)
        (skip-syntax-forward syntax))))))

;; ============================================================================
;; Sentence Text Objects
;; ============================================================================

(defun helixel--forward-sentence (&optional count)
  "Move forward COUNT sentences.
Moves point COUNT sentences forward or (- COUNT) sentences
backward if COUNT is negative.  This function is the same as
`forward-sentence' but returns the number of sentences that could
NOT be moved over."
  (helixel-motion-loop (dir (or count 1))
    (ignore-errors (forward-sentence dir))))
(put 'helixel-sentence 'forward-op #'helixel--forward-sentence)

;; ============================================================================
;; Paragraph Text Objects
;; ============================================================================

(defun helixel--forward-paragraph (&optional count)
  "Move forward COUNT paragraphs.
Moves point COUNT paragraphs forward or (- COUNT) paragraphs backward
if COUNT is negative.  A paragraph is defined by
`start-of-paragraph-text' and `forward-paragraph' functions."
  (helixel-motion-loop (dir (or count 1))
    (cond
     ((> dir 0) (forward-paragraph))
     ((not (bobp)) (start-of-paragraph-text) (beginning-of-line)))))
(put 'helixel-paragraph 'forward-op #'helixel--forward-paragraph)

;; ============================================================================
;; Parenthesis/Bracket Text Objects
;; ============================================================================
(defvar helixel-type-properties nil
  "Specifications made by `helixel-define-type'.
Entries have the form (TYPE .  PLIST), where PLIST is a property
list specifying functions for handling the type: expanding it,
describing it, etc.")

(defun helixel-type-p (sym)
  "Whether SYM is the name of a type."
  (assq sym helixel-type-properties))

(defun helixel-normalize-position (pos)
  "Return POS if it does not exceed the buffer boundaries.
If POS is less than `point-min', return `point-min'.
Is POS is more than `point-max', return `point-max'.
If POS is a marker, return its position."
  (cond
   ((not (number-or-marker-p pos))
    pos)
   ((< pos (point-min))
    (point-min))
   ((> pos (point-max))
    (point-max))
   ((markerp pos)
    (marker-position pos))
   (t
    pos)))

(defmacro helixel-sort (&rest vars)
  "Sort the symbol values of VARS.
Place the smallest value in the first argument and the largest in the
last, sorting in between."
  (if (= (length vars) 2)
      `(when (> ,@vars) (cl-rotatef ,@vars))
    (let ((sorted (make-symbol "sortvar")))
      `(let ((,sorted (sort (list ,@vars) #'<)))
         (setq ,@(apply #'nconc
                        (mapcar (lambda (var) (list var `(pop ,sorted)))
                                vars)))))))

(defun helixel-range (beg end &optional type &rest properties)
  "Return a list (BEG END [TYPE] PROPERTIES...).
BEG and END are buffer positions (numbers or markers),
TYPE is a type as per `helixel-type-p', and PROPERTIES is
a property list."
  (let ((beg (helixel-normalize-position beg))
        (end (helixel-normalize-position end)))
    (when (and (numberp beg) (numberp end))
      (helixel-sort beg end)
      (nconc (list beg end)
             (when (helixel-type-p type) (list type))
             properties))))

(defun helixel-up-block (beg end &optional count)
  "Move point to the end or beginning of text enclosed by BEG and END.
BEG and END should be regular expressions matching the opening
and closing delimiters, respectively.  If COUNT is greater than
zero point is moved forward otherwise it is moved
backwards.  Whenever an opening delimiter is found the COUNT is
increased by one, if a closing delimiter is found the COUNT is
decreased by one.  The motion stops when COUNT reaches zero.  The
`match-data' reflects the last successful match (that caused COUNT
to reach zero).  The behaviour of this functions is similar to
`up-list'."
  (let* ((count (or count 1))
         (forwardp (> count 0))
         (dir (if forwardp +1 -1)))
    (catch 'done
      (while (not (zerop count))
        (let* ((pnt (point))
               (cl (save-excursion
                     (and (re-search-forward (if forwardp end beg) nil t dir)
                          (or (/= pnt (point))
                              (progn
                                ;; zero size match, repeat search from
                                ;; the next position
                                (forward-char dir)
                                (re-search-forward
                                 (if forwardp end beg)
                                 nil t dir)))
                          (point))))
               (match (match-data t))
               (op (save-excursion
                     (and (not (equal beg end))
                          (re-search-forward (if forwardp beg end) cl t dir)
                          (or (/= pnt (point))
                              (progn
                                ;; zero size match, repeat search from
                                ;; the next position
                                (forward-char dir)
                                (re-search-forward
                                 (if forwardp beg end)
                                 cl t dir)))
                          (point)))))
          (cond
           ((not cl)
            (goto-char (if forwardp (point-max) (point-min)))
            (set-match-data nil)
            (throw 'done count))
           (t
            (if op
                (progn
                  (setq count (if forwardp (1+ count) (1- count)))
                  (goto-char op))
              (setq count (if forwardp (1- count) (1+ count)))
              (if (zerop count) (set-match-data match))
              (goto-char cl))))))
      0)))

(defun helixel--get-block-range (op cl selection-type)
  "Return the exclusive range of a visual selection.
OP and CL are pairs of buffer positions for the opening and
closing delimiter of a range.  SELECTION-TYPE is the desired type
of selection.  It is a symbol that determines which parts of the
block are selected.  If it is `inclusive' or t the returned range
is \(cons (car OP) (cdr CL)).  If it is `exclusive' or nil the
returned range is (cons (cdr OP) (car CL)).  If it is
`exclusive-line' the returned range will skip whitespace at the
end of the line of OP and at the beginning of the line of CL."
  (cond
   ((memq selection-type '(inclusive t)) (cons (car op) (cdr cl)))
   ((memq selection-type '(exclusive nil)) (cons (cdr op) (car cl)))
   ((eq selection-type 'exclusive-line)
    (let ((beg (cdr op))
          (end (car cl)))
      (save-excursion
        (goto-char beg)
        (when (and (eolp) (not (eobp)))
          (setq beg (line-beginning-position 2)))
        (goto-char end)
        (skip-chars-backward " \t")
        (when (bolp)
          (setq end (point))
          (goto-char beg)
          (when (and (not (bolp)) (< beg end))
            (setq end (1- end)))))
      (cons beg end)))
   (t (user-error "Unknown selection-type `%s'" selection-type))))

(defun helixel-select-block (thing beg end type count
                                   &optional
                                   selection-type
                                   countcurrent
                                   fixedscan)
  "Return a range (BEG END) of COUNT delimited text objects.
BEG END TYPE are the currently selected (visual) range.  The
delimited object must be given by THING-up function (see
`helixel-up-block').

SELECTION-TYPE is symbol that determines which parts of the block
are selected.  If it is `inclusive' or t OPEN and CLOSE are
included in the range.  If it is `exclusive' or nil the delimiters
are not contained.  If it is `exclusive-line' the delimiters are
not included as well as adjacent whitespace until the beginning
of the next line or the end of the previous line.  If the
resulting selection consists of complete lines only and visual
state is not active, the returned selection is linewise.

If COUNTCURRENT is non-nil an objected is counted if the current
selection matches that object exactly.

Usually scanning for the surrounding block starts at (1+ beg)
and (1- end).  If this might fail due to the behavior of THING
then FIXEDSCAN can be set to t.  In this case the scan starts at
BEG and END.  One example where this might fail is if BEG and END
are the delimiters of a string or comment."
  (save-excursion
    (save-match-data
      (let* ((orig-beg beg)
             (orig-end end)
             (beg (or beg (point)))
             (end (or end (point)))
             (count (abs (or count 1)))
             op cl op-end cl-end)
        ;; We always assume at least one selected character.
        (if (= beg end) (setq end (1+ end)))
        ;; We scan twice: starting at (1+ beg) forward and at (1- end)
        ;; backward.  The resulting selection is the smaller one.
        (goto-char (if fixedscan beg (1+ beg)))
        (when (and (zerop (funcall thing +1)) (match-beginning 0))
          (setq cl (cons (match-beginning 0) (match-end 0)))
          (goto-char (car cl))
          (when (and (zerop (funcall thing -1)) (match-beginning 0))
            (setq op (cons (match-beginning 0) (match-end 0)))))
        ;; start scanning from end
        (goto-char (if fixedscan end (1- end)))
        (when (and (zerop (funcall thing -1)) (match-beginning 0))
          (setq op-end (cons (match-beginning 0) (match-end 0)))
          (goto-char (cdr op-end))
          (when (and (zerop (funcall thing +1)) (match-beginning 0))
            (setq cl-end (cons (match-beginning 0) (match-end 0)))))
        ;; Bug #607: use the tightest selection that contains the
        ;; original selection.  If non selection contains the original,
        ;; use the larger one.
        (cond
         ((and (not op) (not cl-end))
          (error "No surrounding delimiters found"))
         ((or (not op) ; first not found
              (and cl-end ; second found
                   (>= (car op-end) (car op)) ; second smaller
                   (<= (cdr cl-end) (cdr cl))
                   (<= (car op-end) beg)      ; second contains orig
                   (>= (cdr cl-end) end)))
          (setq op op-end cl cl-end)))
        ;; Validate that op/cl form a matched pair. Scan 1 can produce
        ;; mismatched tags (e.g., <div> with </p>) when point is between
        ;; the inner closing tag and the outer closing tag.
        ;; If mismatched, prefer scan 2 if it forms a valid pair.
        (when (and op cl op-end cl-end)
          (let ((op-tag (helixel--xml-tag-name op))
                (cl-tag (helixel--xml-tag-name cl)))
            (unless (string= op-tag cl-tag)
              (let ((op2-tag (helixel--xml-tag-name op-end))
                    (cl2-tag (helixel--xml-tag-name cl-end)))
                (when (string= op2-tag cl2-tag)
                  (setq op op-end cl cl-end))))))
        (setq op-end op cl-end cl) ; store copy
        ;; if the current selection contains the surrounding
        ;; delimiters, they do not count as new selection
        (let ((cnt (if (and orig-beg orig-end (not countcurrent))
                       (let ((sel (helixel--get-block-range op cl
                                                            selection-type)))
                         (if (and (<= orig-beg (car sel))
                                  (>= orig-end (cdr sel)))
                             count
                           (1- count)))
                     (1- count))))
          ;; starting from the innermost surrounding delimiters
          ;; increase selection
          (when (> cnt 0)
            (setq op (progn
                       (goto-char (car op-end))
                       (funcall thing (- cnt))
                       (if (match-beginning 0)
                           (cons (match-beginning 0) (match-end 0))
                         op))
                  cl (progn
                       (goto-char (cdr cl-end))
                       (funcall thing cnt)
                       (if (match-beginning 0)
                           (cons (match-beginning 0) (match-end 0))
                         cl)))))
        (let ((sel (helixel--get-block-range op cl selection-type)))
          (setq op (car sel)
                cl (cdr sel)))
        (cond
         ((and (equal op orig-beg) (equal cl orig-end)
               (or (not countcurrent) (/= count 1)))
          (error "No surrounding delimiters found"))
         ((save-excursion
            (and (not (and helixel-textobj-visual-state-p-function
                           (funcall helixel-textobj-visual-state-p-function)))
                 (eq type 'inclusive)
                 (progn (goto-char op) (bolp))
                 (progn (goto-char cl) (bolp))))
          (helixel-range op cl 'line :expanded t))
         (t (helixel-range op cl type :expanded t)))))))

(defun helixel-up-paren (open close &optional count)
  "Move point to the end or beginning of balanced parentheses.
OPEN and CLOSE should be characters identifying the opening and
closing parenthesis, respectively.  If COUNT is greater than zero
point is moved forward otherwise it is moved backwards.  Whenever
an opening delimiter is found the COUNT is increased by one, if a
closing delimiter is found the COUNT is decreased by one.  The
motion stops when COUNT reaches zero.  The `match-data' reflects the
last successful match (that caused COUNT to reach zero)."
  ;; Always use the default `forward-sexp-function'.  This is important
  ;; for modes that use a custom one like `python-mode'.
  ;; (addresses #364)
  (let (forward-sexp-function)
    (with-syntax-table (copy-syntax-table (syntax-table))
      (modify-syntax-entry open (format "(%c" close))
      (modify-syntax-entry close (format ")%c" open))
      (let ((rest (helixel-motion-loop (dir count)
                    (let ((pnt (point)))
                      (condition-case nil
                          (cond
                           ((> dir 0)
                            (while (progn
                                     (up-list dir t)
                                     (/= (char-before) close))))
                           (t
                            (while (progn
                                     (up-list dir t)
                                     (/= (char-after) open)))))
                        (error (goto-char pnt)))))))
        (cond
         ((= rest count) (set-match-data nil))
         ((> count 0) (set-match-data (list (1- (point)) (point))))
         (t (set-match-data (list (point) (1+ (point))))))
        rest))))

(defun helixel-select-paren (open close beg end type count &optional inclusive)
  "Return a range (BEG END) of COUNT delimited text objects.
OPEN and CLOSE specify the opening and closing delimiter,
respectively.  BEG END TYPE are the currently selected (visual)
range.  If INCLUSIVE is non-nil, OPEN and CLOSE are included in
the range; otherwise they are excluded.

If you aren't inside a pair of the opening and closing delimiters,
it jumps you inside the next one.  If there isn't one, it errors.

The types of OPEN and CLOSE specify which kind of THING is used
for parsing with `helixel-select-block'.  If OPEN and CLOSE are
characters `helixel-up-paren' is used.  Otherwise OPEN and CLOSE
must be regular expressions and `helixel-up-block' is used.

If the selection is exclusive, whitespace at the end or at the
beginning of the selection until the end-of-line or beginning-of-line
is ignored."
  (condition-case nil
      (progn
        ;; we need special linewise exclusive selection
        (unless inclusive (setq inclusive 'exclusive-line))
        (cond
         ((and (characterp open) (characterp close))
          (let ((thing #'(lambda (&optional cnt)
                           (helixel-up-paren open close cnt)))
                (bnd (or (bounds-of-thing-at-point 'helixel-string)
                         (bounds-of-thing-at-point 'helixel-comment)
                         ;; If point is at the opening quote of a string,
                         ;; this must be handled as if point is within the
                         ;; string, i.e. the selection must be extended
                         ;; around the string.  Otherwise
                         ;; `helixel-select-block' might do the wrong thing
                         ;; because it accidentally moves point inside the
                         ;; string (for inclusive selection) when looking
                         ;; for the current surrounding block. (re #364)
                         (and (= (point) (or beg (point)))
                              (save-excursion
                                (goto-char (1+ (or beg (point))))
                                (or (bounds-of-thing-at-point
                                     'helixel-string)
                                    (bounds-of-thing-at-point
                                     'helixel-comment)))))))
            (if (not bnd)
                (helixel-select-block thing beg end type count inclusive)
              (or (helixel-with-restriction (car bnd) (cdr bnd)
                    (ignore-errors
                      (helixel-select-block thing beg end type count
                                            inclusive)))
                  (save-excursion
                    (setq beg (or beg (point))
                          end (or end (point)))
                    (goto-char (car bnd))
                    (let ((extbeg (min beg (car bnd)))
                          (extend (max end (cdr bnd))))
                      (helixel-select-block thing
                                            extbeg extend
                                            type
                                            count
                                            inclusive
                                            (or (< extbeg beg) (> extend end))
                                            t)))))))
         (t
          (helixel-select-block #'(lambda (&optional cnt)
                                    (helixel-up-block open close cnt))
                                beg end type count inclusive))))
    (error ; we aren't in the parens, so find next instance
     (save-match-data
       (goto-char (or (if (and count (> 0 count)) end beg)
                      (point)))
       (let ((re (if (characterp open) (regexp-quote (string open)) open)))
         (if (and (not (looking-at-p re))
                  (re-search-forward re nil t count))
             (progn
               (goto-char (match-beginning 0))
               (let* ((mbeg (match-beginning 0))
                      (res (helixel-select-paren open close mbeg mbeg
                                                 type nil inclusive)))
                 (if (< (car res) mbeg)
                     ;; Error if found paren begins before target.
                     ;; Prevents g2ci( on `prova ( verder "((testo)")`
                     ;; from putting cursor inside deleted `()` after `prova`.
                     ;; Without this, it would go to the 2nd paren
                     ;; (the unbalanced one inside the quotes).
                     (error "No surrounding delimiters found")
                   res)))
           (error "No surrounding delimiters found")))))))

(defun helixel--bounds-of-string-at-point (&optional state)
  "Return the bounds of a string at point.
If STATE is given it used a parsing state at point."
  (save-excursion
    (let ((state (or state (syntax-ppss))))
      (when (nth 3 state)
        (cons (nth 8 state)
              (when (parse-partial-sexp
                     (point) (point-max) nil nil state 'syntax-table)
                (point)))))))
(put 'helixel-string 'bounds-of-thing-at-point
     #'helixel--bounds-of-string-at-point)

(defun helixel--bounds-of-comment-at-point ()
  "Return the bounds of a string at point."
  (save-excursion
    (let ((state (syntax-ppss)))
      (when (nth 4 state)
        (cons (nth 8 state)
              (when (parse-partial-sexp
                     (point) (point-max) nil nil state 'syntax-table)
                (point)))))))
(put 'helixel-comment 'bounds-of-thing-at-point
     #'helixel--bounds-of-comment-at-point)


(defun helixel-forward-quote (quote &optional count)
  "Move point to the end or beginning of a string.
QUOTE is the character delimiting the string.  If COUNT is greater
than zero point is moved forward otherwise it is moved
backwards."
  (let (reset-parser)
    (with-syntax-table (copy-syntax-table (syntax-table))
      (unless (= (char-syntax quote) ?\")
        (modify-syntax-entry quote "\"")
        (syntax-ppss-flush-cache (point-min))
        (setq reset-parser t))
      ;; global parser state is out of state, use local one
      (let* ((pnt (point))
             (state (save-excursion
                      (beginning-of-defun)
                      (parse-partial-sexp (point) pnt nil nil (syntax-ppss))))
             (bnd (helixel--bounds-of-string-at-point state)))
        (when (and bnd (< (point) (cdr bnd)))
          ;; currently within a string
          (if (> count 0)
              (progn
                (goto-char (cdr bnd))
                (setq count (1- count)))
            (goto-char (car bnd))
            (setq count (1+ count))))
        ;; forward motions work with local parser state
        (cond
         ((> count 0)
          ;; no need to reset global parser state because we only use
          ;; the local one
          (setq reset-parser nil)
          (catch 'done
            (while (and (> count 0) (not (eobp)))
              (setq state (parse-partial-sexp
                           (point) (point-max) nil nil state 'syntax-table))
              (cond
               ((nth 3 state)
                (setq bnd (bounds-of-thing-at-point 'helixel-string))
                (goto-char (cdr bnd))
                (setq count (1- count)))
               ((eobp) (goto-char pnt) (throw 'done nil))))))
         ((< count 0)
          ;; need to update global cache because of backward motion
          (setq reset-parser (and reset-parser (point)))
          (save-excursion
            (beginning-of-defun)
            (syntax-ppss-flush-cache (point)))
          (catch 'done
            (while (and (< count 0) (not (bobp)))
              (setq pnt (point))
              (while (and (not (bobp))
                          (or (eobp) (/= (char-after) quote)))
                (backward-char))
              (cond
               ((setq bnd (bounds-of-thing-at-point 'helixel-string))
                (goto-char (car bnd))
                (setq count (1+ count)))
               ((bobp) (goto-char pnt) (throw 'done nil))
               (t (backward-char))))))
         (t (setq reset-parser nil)))))
    (when reset-parser
      ;; reset global cache
      (save-excursion
        (goto-char reset-parser)
        (beginning-of-defun)
        (syntax-ppss-flush-cache (point))))
    count))

(defvar helixel-forward-quote-char ?\"
  "The character to be used by `helixel--forward-quote-default'.")

(defun helixel--forward-quote (&optional count)
  "Move forward COUNT strings.
The quotation character is specified by the global variable
`helixel-forward-quote-char'.  This character is passed to
`helixel-forward-quote'."
  (helixel-forward-quote helixel-forward-quote-char count))
(defvar helixel--bounds-quote-char nil
  "Quote character for `helixel--bounds-of-quote-at-point'.")

(defun helixel--bounds-of-quote-at-point ()
  "Return bounds of quoted string at point using `helixel--bounds-quote-char'.
Temporarily sets the quote character's syntax to string-quote."
  (when helixel--bounds-quote-char
    (with-syntax-table (copy-syntax-table (syntax-table))
      (unless (= (char-syntax helixel--bounds-quote-char) ?\")
        (modify-syntax-entry helixel--bounds-quote-char "\""))
      (syntax-ppss-flush-cache (point-min))
      (helixel--bounds-of-string-at-point))))
(put 'helixel-quote 'forward-op #'helixel--forward-quote)
(put 'helixel-quote 'bounds-of-thing-at-point
     #'helixel--bounds-of-quote-at-point)

(defun helixel-select-quote-thing
    (thing beg end _type count &optional inclusive)
  "Selection THING as if it described a quoted object.
THING is typically either `helixel-quote' or `helixel-chars'.  This
function is called from `helixel-select-quote'.
BEG and END specify the current selection bounds.
COUNT is the number of objects to select.
INCLUSIVE indicates whether to include the delimiters."
  (save-excursion
    (let* ((count (or count 1))
           (dir (if (> count 0) 1 -1))
           (bnd (let ((b (bounds-of-thing-at-point thing)))
                  (and b (< (point) (cdr b)) b)))
           addcurrent
           wsboth)
      (if inclusive (setq inclusive t)
        (when (= (abs count) 2)
          (setq count dir)
          (setq inclusive 'quote-only))
        ;; never extend with exclusive selection
        (setq beg nil end nil))
      ;; check if the previously selected range does not contain a
      ;; string
      (unless (and beg end
                   (save-excursion
                     (goto-char (if (> dir 0) beg end))
                     (forward-thing thing dir)
                     (and (<= beg (point)) (< (point) end))))
        ;; if so forget the range
        (setq beg nil end nil))
      ;; check if there is a current object, if not fetch one
      (when (not bnd)
        (unless (and (zerop (forward-thing thing dir))
                     (setq bnd (bounds-of-thing-at-point thing)))
          (error "No quoted string found"))
        (if (> dir 0)
            (setq end (point))
          (setq beg (point)))
        (setq addcurrent t))
      ;; check if current object is not selected
      (when (or (not beg) (not end) (> beg (car bnd)) (< end (cdr bnd)))
        ;; if not, enlarge selection
        (when (or (not beg) (< (car bnd) beg)) (setq beg (car bnd)))
        (when (or (not end) (> (cdr bnd) end)) (setq end (cdr bnd)))
        (setq addcurrent t wsboth t))
      ;; maybe count current element
      (when addcurrent
        (setq count (if (> dir 0) (1- count) (1+ count))))
      ;; enlarge selection
      (goto-char (if (> dir 0) end beg))
      (when (and (not addcurrent)
                 (= count (forward-thing thing count)))
        (error "No quoted string found"))
      (if (> dir 0) (setq end (point)) (setq beg (point)))
      ;; add whitespace
      (cond
       ((not inclusive) (setq beg (1+ beg) end (1- end)))
       ((not (eq inclusive 'quote-only))
        ;; try to add whitespace in forward direction
        (goto-char (if (> dir 0) end beg))
        (if (setq bnd (bounds-of-thing-at-point 'helixel-space))
            (if (> dir 0) (setq end (cdr bnd)) (setq beg (car bnd)))
          ;; if not found try backward direction
          (goto-char (if (> dir 0) beg end))
          (if (and wsboth (setq bnd (bounds-of-thing-at-point 'helixel-space)))
              (if (> dir 0) (setq beg (car bnd)) (setq end (cdr bnd)))))))
      (helixel-range beg end
                     ;; HACK: fixes #583
                     ;; When not in visual state, an empty range is
                     ;; possible.  However, this cannot be achieved with
                     ;; inclusive ranges, hence we use exclusive ranges
                     ;; in this case.  In visual state the range must be
                     ;; inclusive because otherwise the selection would
                     ;; be wrong.
                     (if (and helixel-textobj-visual-state-p-function
                              (funcall helixel-textobj-visual-state-p-function))
                         'inclusive
                       'exclusive)
                     :expanded t))))

(defun helixel-select-quote (quote beg end type count &optional inclusive)
  "Return a range (BEG END) of COUNT quoted text objects.
QUOTE specifies the quotation delimiter.  BEG END TYPE are the
currently selected (visual) range.

If INCLUSIVE is nil the previous selection is ignore.  If there is
quoted string at point this object will be selected, otherwise
the following (if (> COUNT 0)) or preceeding object (if (< COUNT
0)) is selected.  If (/= (abs COUNT) 2) the delimiting quotes are not
contained in the range, otherwise they are contained in the range.

If INCLUSIVE is non-nil the selection depends on the previous
selection.  If the currently selection contains at least one
character that is contained in a quoted string then the selection
is extended, otherwise it is thrown away.  If there is a
non-selected object at point then this object is added to the
selection.  Otherwise the selection is extended to the
following (if (> COUNT 0)) or preceeding object (if (< COUNT
0)).  Any whitespace following (or preceeding if (< COUNT 0)) the
new selection is added to the selection.  If no such whitespace
exists and the selection contains only one quoted string then the
preceeding (or following) whitespace is added to the range."
  (let ((helixel-forward-quote-char quote))
    (or (let ((bnd (or (bounds-of-thing-at-point 'helixel-comment)
                       (bounds-of-thing-at-point 'helixel-string))))
          (when (and bnd (< (point) (cdr bnd))
                     (/= (char-after (car bnd)) quote)
                     (/= (char-before (cdr bnd)) quote))
            (helixel-with-restriction (car bnd) (cdr bnd)
              (ignore-errors (helixel-select-quote-thing
                              'helixel-quote-simple
                              beg end type
                              count
                              inclusive)))))
        (let ((helixel-forward-quote-char quote)
              (helixel--bounds-quote-char quote))
          (helixel-select-quote-thing 'helixel-quote
                                      beg end type
                                      count
                                      inclusive)))))
(defun helixel-range-p (object)
  "Whether OBJECT is a range."
  (and (listp object)
       (numberp (nth 0 object))
       (numberp (nth 1 object))))

(defun helixel-range-end (range)
  "Return end of RANGE."
  (when (helixel-range-p range)
    (let ((beg (helixel-normalize-position (nth 0 range)))
          (end (helixel-normalize-position (nth 1 range))))
      (max beg end))))

(defun helixel-range-beginning (range)
  "Return beginning of RANGE."
  (when (helixel-range-p range)
    (let ((beg (helixel-normalize-position (nth 0 range)))
          (end (helixel-normalize-position (nth 1 range))))
      (min beg end))))

(defun helixel--activate-textobj-range (range &optional delimiter count)
  "Activate RANGE as a textobj selection with optional DELIMITER and COUNT.
RANGE may be a cons (BEG . END) or a list (BEG END ...).
COUNT (default 1) is stored in the descriptor so dot-repeat replays
the same multiplier."
  (when range
    (push-mark (car range) nil t)
    (goto-char (if (consp (cdr range)) (cadr range) (cdr range)))
    (let ((cmd this-command)
          (n (or count 1))
          (delim delimiter))
      (setq helixel--selection-type 'textobj)
      (helixel--pending-sel-set
       (helixel-sel-create
        'textobj `(:command ,cmd :count ,n :delimiter ,delim
                    :inline-advance t)
             #'helixel--recreate-textobj
             ;; display closure
             (lambda (c)
               (if-let* ((command (helixel-sel-textobj-command c)))
                   (replace-regexp-in-string "^helixel-mark-" ""
                                            (symbol-name command))
                 "textobj"))))
      (run-hook-with-args 'helixel-textobj-after-select-functions))))


(defun helixel-select-xml-tag (beg end type &optional count inclusive)
  "Return a range (BEG END) of COUNT matching XML tags.
TYPE is the selection type.  If INCLUSIVE is non-nil, the tags
themselves are included from the range."
  (cond
   ((and (not inclusive) (= (abs (or count 1)) 1))
    (let ((rng (helixel-select-block #'helixel-up-xml-tag beg end type
                                     count nil t)))
      (if (or (and beg (= beg (helixel-range-beginning rng))
                   end (= end (helixel-range-end rng))))
          (helixel-select-block #'helixel-up-xml-tag beg end type count t)
        rng)))
   (t
    (helixel-select-block #'helixel-up-xml-tag beg end type count inclusive))))

(defun helixel--xml-tag-name (bounds)
  "Extract XML tag name from tag BOUNDS (BEG . END).
Returns the tag name without <, </, or >."
  (let ((str (buffer-substring (car bounds) (cdr bounds))))
    (if (string-match "\\`<\\(/\\)?\\([^ >\n]+\\)" str)
        (match-string 2 str)
      "")))

(defun helixel-up-xml-tag (&optional count)
  "Move point to the end or beginning of balanced xml tags.
If COUNT is greater than zero point is moved forward otherwise it is moved
backwards.  Whenever an opening delimiter is found the COUNT is increased by
one, if a closing delimiter is found the COUNT is decreased by one.  The motion
stops when COUNT reaches zero.  The match data reflects the last successful
match (that caused COUNT to reach zero)."
  (let* ((dir (if (> (or count 1) 0) +1 -1))
         (count (abs (or count 1)))
         (op (if (> dir 0) 1 2))
         (cl (if (> dir 0) 2 1))
         (orig (point))
         pnt tags match)
    (catch 'done
      (while (> count 0)
        ;; find the previous opening tag
        (while
            (and (setq match
                       (re-search-forward
                        (concat "<\\([^/ >\n]+\\)"
                                "\\(?:=>?\\|[^\"/>]\\|"
                                "\"[^\"]*\"\\)*?>\\|"
                                "</\\([^>]+?\\)>")
                        nil t dir))
                 (cond
                  ((match-beginning op)
                   (push (match-string op) tags))
                  ((null tags) nil) ; free closing tag
                  ((and (< dir 0)
                        (string= (car tags) (match-string cl)))
                   ;; in backward direction we only accept matching
                   ;; tags.  If the current tag is a free opener
                   ;; without matching closing tag, the subsequent
                   ;; test will make us ignore this tag
                   (pop tags)
                   tags)
                  ((and (> dir 0))
                   ;; non matching openers are considered free openers
                   (while (and tags
                               (not (string= (car tags)
                                             (match-string cl))))
                     (pop tags))
                   (pop tags)
                   tags))))
        (unless (setq match (and match (match-data t)))
          (setq match nil)
          (throw 'done count))
        ;; found closing tag, look for corresponding opening tag
        (cond
         ((> dir 0)
          (setq pnt (match-end 0))
          (goto-char (match-beginning 0)))
         (t
          (setq pnt (match-beginning 0))
          (goto-char (match-end 0))))
        (let* ((tag (match-string cl))
               (refwd (concat "<\\(/\\)?"
                              (regexp-quote tag)
                              "\\(?:>\\|[ \n]\\(?:[^\"/>]\\|"
                              "\"[^\"]*\"\\)*?>\\)"))
               (cnt 1))
          (while (and (> cnt 0) (re-search-backward refwd nil t dir))
            (setq cnt (+ cnt (if (match-beginning 1) dir (- dir)))))
          (if (zerop cnt) (setq count (1- count) tags nil))
          (goto-char pnt)))
      (if (> count 0)
          (set-match-data nil)
        (set-match-data match)
        (goto-char (if (> dir 0) (match-end 0) (match-beginning 0)))))
    ;; if not found, set to point-max/point-min
    (unless (zerop count)
      (set-match-data nil)
      (goto-char (if (> dir 0) (point-max) (point-min)))
      (if (/= (point) orig) (setq count (1- count))))
    (* dir count)))

;; ============================================================================
;; Generic Regex Block Text Objects (org begin/end, markdown fences, etc.)
;; ============================================================================

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
                   (not (null tags)))
                  ((> dir 0)
                   ;; forward: pop matching closer (skip non-matching first)
                   (while (and tags
                               (not (string= (car tags)
                                             (match-string cl-name))))
                     (pop tags))
                   (pop tags)
                   (not (null tags)))           ; break if stack now empty
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

(defun helixel--use-region-p()
  "Return non-nil when in visual state and the region is active."
  (and (use-region-p)
       helixel-textobj-visual-state-p-function
       (funcall helixel-textobj-visual-state-p-function)))

(defun helixel--region-has-content-p ()
  "Return non-nil if the active region contains non-whitespace chars."
  (and (region-active-p)
       (let ((end (region-end)))
       (and (< (region-beginning) end)
            (save-excursion
              (goto-char (region-beginning))
              (re-search-forward "[^ \t\n\r\f]" end t))))))

(defun helixel--ensure-point-in-thing ()
  "Adjust point so `bounds-of-thing-at-point' finds the current thing.
If region is active with content and point is at or past `region-end',
move point into the region content.  Otherwise if point is on
whitespace, skip whitespace backward then backward one char."
  (cond
   ((and (region-active-p) (>= (point) (region-end))
         (helixel--region-has-content-p))
    (goto-char (region-end))
    (skip-chars-backward " \t\n\r\f")
    (when (and (not (bobp)) (> (point) (region-beginning)))
      (backward-char)))
   ((looking-at "[ \t\n\r\f]")
    (skip-chars-backward " \t\n\r\f")
    (unless (bobp)
      (backward-char)))))


(defvar helixel--block-chosen-spec)  ; defined in helixel-core.el

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
           (bracket-pairs (when fallback-needed
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


(defvar helixel--surround-pairs nil
  "Alist mapping a delimiter char to (open . close) for surround.
Auto-populated by `helixel-define-mark-pair' and `helixel-define-mark-quote'.")


(declare-function evil-textobj-tree-sitter--range
                  "evil-textobj-tree-sitter-core" t t)
(declare-function evil-textobj-tree-sitter--message-not-found
                  "evil-textobj-tree-sitter-core" t t)
(defvar evil-textobj-tree-sitter-use-next-if-not-within)

(defvar helixel-textobj-action-function nil
  "If non-nil, called with (CATEGORY SUBCAT) on textobj action start.")

;; helixel--current-selection removed; use visual state checks instead


(defmacro helixel-define-mark-pair (name open close doc inner-p)
  "Define mark inner/a functions for a pair of brackets.
NAME is the name of the bracket pair.  OPEN and CLOSE are the
opening and closing delimiters.  DOC is a description of the
pair.  INNER-P non-nil means inner, nil means a."
  (let ((func-name (intern (format "helixel-mark-%s-%s"
                                   (if inner-p "inner" "a")
                                   name)))
        (func-doc (format "Select %s %s."
                          (if inner-p "inner" "a")
                          doc))
        (inclusive (if inner-p nil t)))
    `(progn
       (defun ,func-name (&optional count)
         ,func-doc
         (interactive "p")
         (when helixel-textobj-action-function
           (funcall helixel-textobj-action-function 'textobj 'pair))
         (helixel--activate-textobj-range
          (helixel-select-paren ,open ,close
                                (when (helixel--use-region-p)
                                  (region-beginning))
                                (when (helixel--use-region-p)
                                  (region-end))
                                nil count ,inclusive)
          (helixel--make-pair-delimiter ,open ,close)
          count))
       ,@(unless inner-p
           `((push (cons ,open ,close) helixel--surround-pairs)
             (push (cons ,close ,open) helixel--surround-pairs))))))

(defmacro helixel-define-mark-quote (name quote-char doc inner-p)
  "Define mark inner/a functions for a quote character.
NAME is the name of the quote character.  QUOTE-CHAR is the
quotation character.  DOC is a description of the quote.
INNER-P non-nil means inner, nil means a."
  (let ((func-name (intern (format "helixel-mark-%s-%s"
                                   (if inner-p "inner" "a")
                                   name)))
        (func-doc (format "Select %s %s."
                          (if inner-p "inner" "a")
                          doc))
        (inclusive (if inner-p nil t)))
    `(progn
       (defun ,func-name (&optional count)
         ,func-doc
         (interactive "p")
         (when helixel-textobj-action-function
           (funcall helixel-textobj-action-function 'textobj 'quote))
         (helixel--activate-textobj-range
          (helixel-select-quote ,quote-char
                                (when (helixel--use-region-p)
                                  (region-beginning))
                                (when (helixel--use-region-p)
                                  (region-end))
                                nil count ',inclusive)
          (helixel--make-pair-delimiter ,quote-char ,quote-char)
          count))
       ,@(unless inner-p
           `((push (cons ,quote-char ,quote-char) helixel--surround-pairs))))))

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

(defun helixel--recreate-textobj (ctx)
  "Replay a textobj selection from CTX.
Skips past the current target (if cursor is inside one), then
skips whitespace, then re-executes the textobj command.
Signals errors when no more targets exist."
  (when-let* ((command (helixel-sel-textobj-command ctx))
              (cnt (helixel-sel-textobj-count ctx)))
    (unless (region-active-p)
      ;; Skip past the current target if cursor is inside one.
      ;; This handles ciw→. where the inserted text becomes
      ;; the new current target.
      (condition-case nil
          (save-excursion
            (funcall command 1)
            (when (and (use-region-p)
                       (<= (region-beginning) (point))
                       (< (point) (region-end)))
              (goto-char (region-end))))
        (error nil))
      (when (looking-at-p "[ \t\n\r\f]")
        (skip-chars-forward " \t\n\r\f")))
    (condition-case nil
        (funcall command cnt)
      (error
       (save-match-data
         (let ((orig (point)))
           (forward-word 1)
           (when (= (point) orig)
             (forward-char 1))
           (funcall command cnt))))))
  (setq helixel--selection-type 'textobj))


;; ── Textobj advance (from helixel-repeat.el) ──

(defun helixel--repeat-advance-textobj (tx)
  "Advance to next target for TX's textobj selection.
Calls the selection's recreate function from the current cursor
position.  The recreate IS the advance (inline — textobj commands
inherently create the region).  Returns t on success, nil when
recreate fails.
The strategy skips the separate `recreate-selection' call for inline
advance functions to avoid double-moving."
  (let ((sel (helixel-event-sel tx)))
    (when sel
      (condition-case nil
          (progn (helixel--recreate-selection sel) t)
        (error nil)))))

;; ── Kind registration ──

(helixel-register-kind textobj
  :recreate nil
  :advance  #'helixel--repeat-advance-textobj
  :display  (lambda (ctx) (symbol-name (helixel-sel-textobj-command ctx))))

(provide 'helixel-textobj)
;;; helixel-textobj.el ends here
