;;; helixel-textobj-engine.el --- Text object engines for Helixel  -*- lexical-binding: t; -*-

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

;; Low-level text object engines: forward motion, bounds detection,
;; pair/quote/tag/block/regex selection.  Used by helixel-textobj.el.

;;; Code:

(require 'cl-lib)
(require 'thingatpt)
(require 'helixel-core)

(declare-function helixel--set-mark-region "helixel-action")

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
                 (ignore-errors
                   (and (zerop (forward-thing thing -1))
                        (forward-thing thing)))
                 (if (> (point) pnt) (point-min) (point))))
          (end (save-excursion
                 (ignore-errors
                   (and (zerop (forward-thing thing))
                        (forward-thing thing -1)))
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


;; ============================================================================
;; Range Struct (constructor, predicate, accessors)
;; ============================================================================

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
If an existing textobj sel of the same command is pending, accumulates
the count so `.' repeats the full chain of textobj selections."
  (when range
    (push-mark (car range) nil t)
    (goto-char (if (consp (cdr range)) (cadr range) (cdr range)))
    ;; Update the live event's mark-region so `;' can mark the full
    ;; textobj selection (helixel-semicolon-mark-thing).
    (helixel--set-mark-region
     (cons (car range)
           (if (consp (cdr range)) (cadr range) (cdr range))))
    (let* ((cmd this-command)
           (n (or count 1))
           (delim delimiter)
           (prev helixel--pending-sel)
           (total-n (if (and prev
                             (eq (helixel-sel-kind prev) 'textobj)
                             (eq (helixel-sel-textobj-command prev) cmd))
                        (+ (helixel-sel-textobj-count prev) n)
                      n)))
      (setq helixel--raw-selection-type 'textobj)
      (helixel--sel-push
       (helixel-sel-create
        'textobj `(:command ,cmd :count ,total-n :delimiter ,delim
                    :inline-advance t)))
      (run-hook-with-args 'helixel-textobj-after-select-functions))))


;; ============================================================================
;; Visual-state / region helpers (used by mark-* commands)
;; ============================================================================

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

;; ============================================================================
;; Surround / hook plumbing + textobj kind protocol
;; ============================================================================

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

(defun helixel--forward-function (&optional count)
  "Move forward COUNT functions.
Moves point COUNT functions forward or (- COUNT) functions
backward if COUNT is negative.  A function is defined via
`beginning-of-defun' and `end-of-defun'."
  (helixel-motion-loop (dir (or count 1))
    (ignore-errors
      (if (< dir 0) (beginning-of-defun) (end-of-defun)))))
(put 'helixel-function 'forward-op #'helixel--forward-function)

(defun helixel--recreate-textobj (ctx)
  "Replay a textobj selection from CTX.
Skips past the current target (if cursor is inside one), then
skips whitespace, then re-executes the textobj command.
When :span is set, extends region back to the pre-recreate origin.
Signals errors when no more targets exist."
  (when-let* ((command (helixel-sel-textobj-command ctx))
              (cnt (helixel-sel-textobj-count ctx)))
    (helixel--with-span ctx
      (unless (region-active-p)
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
             (funcall command cnt)))))))
  (setq helixel--raw-selection-type 'textobj))

(defun helixel--repeat-advance-textobj (tx)
  "Advance to next target for TX's textobj selection.
Calls the selection's recreate function from the current cursor
position.  The recreate IS the advance (inline — textobj commands
inherently create the region).  Returns t on success, nil when
recreate fails.
The strategy skips the separate `recreate-selection' call for inline
advance functions to avoid double-moving."
  (let ((sel (helixel-action-sel tx)))
    (when sel
      (condition-case nil
          (progn (helixel--recreate-selection sel) t)
        (error nil)))))

(provide 'helixel-textobj-engine)
;;; helixel-textobj-engine.el ends here
