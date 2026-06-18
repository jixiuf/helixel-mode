;;; helixel-textobj-pair.el --- Paren / quote / xml-tag text objects -*- lexical-binding: t; -*-

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
;; The three "matched-pair" text-object families that share the
;; "find inner pair → return helixel-range" shape:
;;
;;   paren / bracket / brace / angle  (helixel-select-paren, helixel-up-paren)
;;   quote (single / double / back / etc.)  (helixel-select-quote,
;;                                            helixel-forward-quote)
;;   xml / sgml tag  (helixel-select-xml-tag, helixel-up-xml-tag)
;;
;; Plus the shared inner-bound helper `helixel-select-block' and the
;; delimiter constructors `helixel--make-pair-delimiter' and
;; `helixel--make-tag-delimiter'.
;;
;; Depends on engine (helixel-range, helixel-with-restriction,
;; helixel-motion-loop, helixel-textobj-visual-state-p-function).

;;; Code:

(require 'cl-lib)
(require 'helixel-textobj-engine)

;; ── Paren-or-quote inner-bound helpers ──

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
          ;; For delimiters with a :match-close method (tags), use
          ;; targeted forward search so nested different-name pairs
          ;; don't steal the close.
          (let ((mc (and (symbolp thing)
                         (get thing 'helixel--match-close))))
            (if (and mc (match-string 1))
                (progn
                  (funcall mc (match-string 1))
                  (when (match-beginning 0)
                    (setq cl-end (cons (match-beginning 0)
                                       (match-end 0)))))
              (when (and (zerop (funcall thing +1)) (match-beginning 0))
                (setq cl-end (cons (match-beginning 0) (match-end 0)))))))
        ;; Bug #607: use the tightest selection that contains the
        ;; original selection.  If non selection contains the original,
        ;; use the larger one.
        (cond
         ((and (not op) (not cl-end))
          (user-error "No surrounding delimiters found"))
         ((or (not op) ; first not found
              (and cl-end ; second found
                   (>= (car op-end) (car op)) ; second smaller
                   (<= (cdr cl-end) (cdr cl))
                   (<= (car op-end) beg)      ; second contains orig
                   (>= (cdr cl-end) end)))
          (setq op op-end cl cl-end)))
        ;; When there is no active region and scan 1's opening starts
        ;; at or after the scan position, prefer scan 2 (backward-first)
        ;; because scan 1 found the next tag rather than the enclosing
        ;; one.  This matters when point is between tags.
        (when (and op-end cl-end
                   (not orig-beg) (not orig-end)
                   (>= (car op) beg))
          (setq op op-end cl cl-end))
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
          ;; When there is no active region and the selected pair
          ;; does not contain the cursor (e.g., cursor between
          ;; </div> and </p>), expand one level outward so the
          ;; enclosing tag is found.
          (when (and (or (not orig-beg) (not orig-end))
                     (or (< beg (car op))
                         (> beg (cdr cl))))
            (setq cnt 1))
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
          (user-error "No surrounding delimiters found"))
         ((save-excursion
            (and (not (and helixel-textobj-visual-state-p-function
                           (funcall helixel-textobj-visual-state-p-function)))
                 (eq type 'inclusive)
                 (progn (goto-char op) (bolp))
                 (progn (goto-char cl) (bolp))))
          (helixel-range op cl 'line :expanded t))
         (t (helixel-range op cl type :expanded t)))))))

;; ── Paren selection ──

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
OPEN and CLOSE are characters specifying the opening and closing
delimiters.  BEG END TYPE are the currently selected (visual)
range.  If INCLUSIVE is non-nil, OPEN and CLOSE are included in
the range; otherwise they are excluded.

If you aren't inside a pair of the opening and closing delimiters,
it jumps you inside the next one.  If there isn't one, it errors.

Uses `helixel-up-paren' with syntax-table awareness to handle
nesting and string/comment boundaries.

If the selection is exclusive, whitespace at the end or at the
beginning of the selection until the end-of-line or beginning-of-line
is ignored."
  (condition-case nil
      (progn
        ;; we need special linewise exclusive selection
        (unless inclusive (setq inclusive 'exclusive-line))
        (let ((thing (lambda (&optional cnt)
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
    (error ; we aren't in the parens, so find next instance
     (save-match-data
       (goto-char (or (if (and count (> 0 count)) end beg)
                      (point)))
       (let ((re (regexp-quote (string open))))
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
                     (user-error "No surrounding delimiters found")
                   res)))
           (user-error "No surrounding delimiters found")))))))

;; ── String / comment bounds helpers ──

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



;; ── Quote selection ──

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
      ;; Ensure backslash has escape syntax (see
      ;; `helixel--bounds-of-quote-at-point').
      (unless (= (char-syntax ?\\) ?\\)
        (modify-syntax-entry ?\\ "\\")
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
Temporarily sets the quote character's syntax to string-quote and
ensures backslash has escape syntax."
  (when helixel--bounds-quote-char
    (with-syntax-table (copy-syntax-table (syntax-table))
      (unless (= (char-syntax helixel--bounds-quote-char) ?\")
        (modify-syntax-entry helixel--bounds-quote-char "\""))
      ;; Ensure backslash acts as an escape character so that \"
      ;; inside strings is treated as an escaped quote, not a string
      ;; terminator.  Necessary in modes like text-mode where \ has
      ;; no escape syntax by default.
      (unless (= (char-syntax ?\\) ?\\)
        (modify-syntax-entry ?\\ "\\"))
      (syntax-ppss-flush-cache (point-min))
      (helixel--bounds-of-string-at-point))))

(put 'helixel-quote 'forward-op #'helixel--forward-quote)
(put 'helixel-quote 'bounds-of-thing-at-point
     #'helixel--bounds-of-quote-at-point)

;; ── Simple quote (character-based, for use inside comments/strings) ──

(defun helixel--preceded-by-odd-backslashes-p (pos)
  "Return non-nil if POS is preceded by an odd number of backslashes."
  (let ((n 0))
    (while (and (> pos (point-min))
                (eq (char-before pos) ?\\))
      (setq n (1+ n)
            pos (1- pos)))
    (= (logand n 1) 1)))

(defun helixel--bounds-of-quote-simple-at-point ()
  "Return bounds (BEG . END) of a simple quoted string at point.
Uses `helixel--bounds-quote-char' as delimiter and searches
literally without syntax tables.  Handles backslash-escaped quotes.
Returns nil if point is not inside a simple quoted string."
  (when helixel--bounds-quote-char
    (let* ((q helixel--bounds-quote-char)
           (qstr (char-to-string q))
           (orig (point)))
      (save-excursion
        ;; Start backward search from one past point so that
        ;; a quote at the current position is included.
        (unless (eobp) (forward-char))
        (catch 'helixel--found
          (while (search-backward qstr nil t)
            (unless (helixel--preceded-by-odd-backslashes-p (point))
              (let ((candidate-open (point)))
                ;; Use save-excursion so failed forward searches
                ;; don't move point away from the backward scan.
                (save-excursion
                  (goto-char (1+ candidate-open))
                  (let (close)
                    (while (and (not close)
                                (search-forward qstr nil t))
                      (let ((qpos (1- (point))))
                        (unless (helixel--preceded-by-odd-backslashes-p
                                 qpos)
                          (setq close (point)))))
                    (when (and close
                               (>= orig candidate-open)
                               (<= orig close))
                      (throw 'helixel--found
                             (cons candidate-open close))))))))
          nil)))))

(defun helixel--forward-quote-simple (&optional count)
  "Move forward COUNT simple quoted strings.
Uses `helixel-forward-quote-char' as delimiter and searches literally
without syntax tables.  Returns 0 on success, or (* dir remaining) on
failure."
  (setq count (or count 1))
  (let* ((q helixel-forward-quote-char)
         (qstr (char-to-string q))
         (dir (if (> count 0) 1 -1))
         (n (abs count)))
    (while (and (> n 0)
                (if (> dir 0)
                    ;; ── Forward ──
                    ;; Find next unescaped opening quote.
                    (let ((open nil))
                      (while (and (not open) (not (eobp)))
                        (if (search-forward qstr nil t)
                            (let ((qpos (1- (point))))
                              (unless (helixel--preceded-by-odd-backslashes-p
                                       qpos)
                                (setq open qpos)))
                          (setq n 0)))
                      (when open
                        ;; Find matching unescaped closing quote.
                        (goto-char (1+ open))
                        (let ((close nil))
                          (while (and (not close) (not (eobp)))
                            (if (search-forward qstr nil t)
                                (let ((qpos (1- (point))))
                                  (unless
                                      (helixel--preceded-by-odd-backslashes-p
                                       qpos)
                                    (setq close (point))))
                              (setq n 0)))
                          (if close
                              (progn (goto-char close) (setq n (1- n)) t)
                            (setq n 0) nil))))
                  ;; ── Backward ──
                  ;; Find previous unescaped quote (treat as closer).
                  (let ((close nil))
                    (while (and (not close) (not (bobp)))
                      (if (search-backward qstr nil t)
                          (unless (helixel--preceded-by-odd-backslashes-p
                                   (point))
                            (setq close (point)))
                        (setq n 0)))
                    (when close
                      ;; Find matching opener before this closer.
                      (let ((open nil))
                        (while (and (not open) (not (bobp)))
                          (if (search-backward qstr nil t)
                              (unless (helixel--preceded-by-odd-backslashes-p
                                       (point))
                                (setq open (point)))
                            (setq n 0)))
                        (if open
                            (progn (goto-char open) (setq n (1- n)) t)
                          (setq n 0) nil)))))))
    (* dir n)))

(put 'helixel-quote-simple 'forward-op #'helixel--forward-quote-simple)
(put 'helixel-quote-simple 'bounds-of-thing-at-point
     #'helixel--bounds-of-quote-simple-at-point)

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
          (user-error "No quoted string found"))
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
        (user-error "No quoted string found"))
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
  (let ((helixel-forward-quote-char quote)
        (helixel--bounds-quote-char quote))
    (or (let* ((comment-bnd (bounds-of-thing-at-point 'helixel-comment))
               (bnd (or comment-bnd
                        (bounds-of-thing-at-point 'helixel-string))))
          (when (and bnd (< (point) (cdr bnd))
                     (/= (char-after (car bnd)) quote)
                     ;; Only check the closing delimiter when we are
                     ;; inside a string (not a comment).  Comments are
                     ;; delimited by //, \n or /*, */ — never by a
                     ;; quote character, so the closing-delimiter check
                     ;; is both unnecessary and harmful (e.g. when the
                     ;; last character before the comment end is a
                     ;; quote).
                     (or comment-bnd
                         (/= (char-before (cdr bnd)) quote)))
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

;; ── XML / SGML tag selection ──

(defun helixel-select-xml-tag (beg end type &optional count inclusive)
  "Return a range (BEG END) of COUNT matching XML tags.
TYPE is the selection type.  If INCLUSIVE is non-nil, the tags
themselves are included from the range."
  (unless inclusive (setq inclusive 'exclusive-line))
  (cond
   ((and (eq inclusive 'exclusive-line) (= (abs (or count 1)) 1))
    (let ((rng (helixel-select-block #'helixel-up-xml-tag beg end type
                                     count 'exclusive-line t)))
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

(defun helixel--tag-regex (tag-name)
  "Return a regex matching <TAG-NAME...> or </TAG-NAME>.
Group 1 captures the slash for closing tags."
  (concat "<\\(/\\)?" (regexp-quote tag-name)
          "\\(?:>\\|[ \n]\\(?:[^\"/>]\\|\"[^\"]*\"\\)*?>\\)"))

(defun helixel--find-matching-tag-close (tag-name)
  "Search forward from point for matching </TAG-NAME>, counting nested pairs.
Point should be right after the opening <TAG-NAME>.
Sets `match-data' for the closing tag on success, returns 0."
  (let ((regex (helixel--tag-regex tag-name))
        (depth 1))
    (while (and (> depth 0) (re-search-forward regex nil t))
      (setq depth (+ depth (if (match-string 1) -1 +1))))
    (if (zerop depth)
        0
      (user-error "No matching closing tag for %s" tag-name))))

(defun helixel--tag-move-past-markup (&optional dir)
  "Move point past XML tag markup if inside one.
This lets the tag finder locate the enclosing pair.

For backward search (DIR < 0):
  - On or inside opening tag like <div|> → move after >
  - On or inside closing tag like </div|> → move before <

For forward search (DIR > 0):
  - On or inside opening tag like <div|> → move before <
  - On or inside closing tag like </div|> → move after >

Returns non-nil if point was adjusted."
  (let* (;; If point is on <, that's the tag we're inside.
         (on-lt (and (eq (char-after) ?<) (point)))
         ;; Otherwise search backward for the nearest < before point.
         (lt-pos (or on-lt
                     (save-excursion
                       (search-backward "<"
                                        (line-beginning-position) t)))))
    (when lt-pos
      (let ((gt-pos (save-excursion
                      (goto-char lt-pos)
                      (search-forward ">" (line-end-position) t))))
        (when (and gt-pos (> gt-pos (point)))
          ;; Point is strictly between < and > (not at >)
          (if (eq (char-after (1+ lt-pos)) ?/)
              ;; Closing tag
              (if (< (or dir 0) 0)
                  (goto-char lt-pos)    ; backward: move before <
                (goto-char gt-pos))     ; forward: move after >
            ;; Opening tag
            (if (< (or dir 0) 0)
                (goto-char gt-pos)      ; backward: move after >
              (goto-char lt-pos)))      ; forward: move before <
          t)))))

(defun helixel--tag-find-opener-backward ()
  "Search backward for the nearest *unclosed* XML opening tag.
Balances closing tags as we go backward so the returned opener
is the innermost tag that still encloses point.  When a matched
opener is found (depth drops to 0), it is returned as the
enclosing tag.  Returns 0 on success with `match-data' set, 1 on
failure."
  (let ((depth 0)
        (saved-match nil)
        (regex (concat "<\\([^/ >\n]+\\)"
                       "\\(?:=>?\\|[^\"/>]\\|\"[^\"]*\"\\)*?>\\|"
                       "</\\([^>]+?\\)>")))
    (catch 'helixel--found
      (while (re-search-backward regex nil t)
        (if (match-beginning 1)
            ;; Opening tag
            (if (> depth 0)
                (progn
                  (setq depth (1- depth))
                  ;; When depth reaches 0, this opener balances the
                  ;; pending closer — it is our enclosing tag.
                  (when (zerop depth)
                    (setq saved-match (match-data t))))
              ;; depth=0: unclosed opener found — this is the
              ;; innermost enclosing tag.
              (throw 'helixel--found 0))
          ;; Closing tag
          (setq depth (1+ depth))))
      ;; If we exhausted the buffer, use the last balanced opener.
      (if saved-match
          (progn
            (set-match-data saved-match)
            0)
        1))))

(defun helixel--tag-adjust-for-jump ()
  "Move point inside the tag pair whose boundary point is on.
If point is on or inside an opening tag (<div|>), move after >.
If point is on or after a closing tag (</div|>), move before <.
This is used by `helixel-jump-to-match' so that the enclosing-pair
lookup finds the pair whose delimiter point is on, rather than the
outer enclosing pair."
  (let ((c (char-after)))
    (cond
     ;; On < of an opening tag → move after >
     ((and c (eq c ?<)
           (not (eq (char-after (1+ (point))) ?/)))
      (search-forward ">" (line-end-position) t))
     ;; On < of a closing tag → move before <
     ((and c (eq c ?<)
           (eq (char-after (1+ (point))) ?/))
      (backward-char))
     ;; Right after > of a closing tag → move before < of that tag
     ((and (not (bobp)) (eq (char-before) ?>))
      (backward-char)
      (let ((lt (search-backward "<" (line-beginning-position) t)))
        (when (and lt (eq (char-after (1+ lt)) ?/))
          (goto-char lt))))
     ;; Inside a closing tag (after </ and before >) → move before <
     ((and (not (bobp))
           (save-excursion
             (search-backward "<" (line-beginning-position) t)
             (eq (char-after (1+ (point))) ?/)))
      ;; Point is inside </xxx> markup
      (search-backward "<" (line-beginning-position) t)
      (goto-char (match-beginning 0))))))

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
                  ((and (< dir 0) tags)
                   ;; backward: non-matching opener nested inside — skip
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
               (refwd (helixel--tag-regex tag))
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
      (goto-char (if (> dir 0) (point-max) (point-min))))
    (* dir count)))
(put 'helixel-up-xml-tag 'helixel--match-close
     #'helixel--find-matching-tag-close)

;; ── Delimiter constructors ──

(defun helixel--find-quote-pair (quote-char dir)
  "Find matching quote pair for QUOTE-CHAR in direction DIR.
DIR = -1: find opening unescaped quote before point, set `match-data', return 0.
DIR = +1: find matching closing unescaped quote, set `match-data', return 0.
Returns non-zero on failure.
Handles backslash-escaped quotes via `helixel--preceded-by-odd-backslashes-p'."
  (let ((qstr (char-to-string quote-char)))
    (if (> dir 0)
        ;; Forward balanced search: count depth, stop at 0.
        (let ((depth 1))
          (while (and (> depth 0) (re-search-forward qstr nil t))
            (unless (helixel--preceded-by-odd-backslashes-p (1- (point)))
              (setq depth (1- depth))))
          (if (zerop depth) 0 1))
      ;; Backward: find the first unescaped quote before point.
      (if (and (re-search-backward qstr nil t)
               (not (helixel--preceded-by-odd-backslashes-p (point))))
          0
        1))))

(defun helixel--make-pair-delimiter (open close)
  "Create a pair delimiter for OPEN and CLOSE characters."
  (let ((equal-p (= open close)))
    (list :type 'pair
          :open open :close close
          :finder (if equal-p
                      `(lambda (dir)
                         (helixel--find-quote-pair ,open dir))
                    `(lambda (dir) (helixel-up-paren ,open ,close dir)))
          :adjust-for-jump
          (unless equal-p
            `(lambda () (when (eq (char-after) ,open) (forward-char))))
          :nl-p nil)))

(defun helixel--make-tag-delimiter ()
  "Create a tag delimiter."
  (list :type 'tag
        :open "<"
        :finder (lambda (dir)
                  (helixel--tag-move-past-markup dir)
                  (if (< dir 0)
                      (helixel--tag-find-opener-backward)
                    (helixel-up-xml-tag dir)))
        :match-close #'helixel--find-matching-tag-close
        :adjust-for-jump #'helixel--tag-adjust-for-jump
        :nl-p t))


(provide 'helixel-textobj-pair)
;;; helixel-textobj-pair.el ends here
