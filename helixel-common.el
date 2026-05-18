;;; helixel-common.el --- Editing and dot-repeat  -*- lexical-binding: t; -*-

;; Copyright (C) 2025-2026  jixiuf

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

;; Editing commands and dot-repeat replay for helixel-mode.
;;
;; Editing commands (kill, change, copy, replace, yank, indent) plus
;; the `helixel-register-op' dot-repeat runners that replay them.
;; Also houses selection recreation functions consumed by `.` and the
;; `helixel--selection-type' validator.
;;
;; Keymaps are NOT loaded here — `helixel-keymap' is loaded separately
;; by `helixel.el' after this file.

;;; Code:

(require 'cl-lib)
(require 'helixel-state)
(require 'helixel-move)

(declare-function helixel-search--search "helixel-search"
                  (pattern dir &optional bound noerror))

;; ── Selection recreation ──
;; These functions rebuild selections from ctx during `.` replay.
;; Referenced by `helixel-sel-create' in helixel-state and helixel-move
;; as stored closures; called at runtime by `helixel--execute-edit'.

(defun helixel--recreate-line (ctx)
  "Replay a linewise selection from CTX.
When :entry-kind is present (insert ops), position cursor
at the appropriate offset on the selected line:
  :entry-kind insert \=`region-beginning' + cursor-offset
  :entry-kind append \=`region-end' + cursor-offset"
  (let ((n (helixel-sel-line-count ctx))
        (entry-kind (plist-get ctx :entry-kind)))
    (if (eq (helixel-sel-line-dir ctx) 'backward)
        (helixel-select-line-up n)
      (helixel-select-line n))
    (when entry-kind
      ;; Position cursor for key/text insertion.
      ;; Use region-beginning/region-end because helixel-select-line
      ;; leaves point on the LAST selected line, so
      ;; line-beginning-position/line-end-position would target
      ;; the wrong line for multi-line selections.
      (if (eq entry-kind 'append)
          (goto-char (region-end))
        (let ((rend (region-end)))
          (goto-char (region-beginning))
          ;; If point landed on the mark (zero-length region),
          ;; restore the visible region so the selection highlight
          ;; shows the full target range.
          (when (= (point) (mark))
            (set-mark rend))))
      (let ((off (helixel-sel-insert-cursor-offset ctx)))
        (when off (forward-char off))))))

(defun helixel--recreate-rect (ctx)
  "Replay a rectangular selection from CTX."
  (let ((n (helixel-sel-rect-count ctx)))
    (unless rectangle-mark-mode
      (helixel--switch-state 'visual)
      (push-mark (point) t t)
      (rectangle-mark-mode 1))
    (dotimes (_ (1- n))
      (forward-line 1)
      (rectangle--reset-point-crutches))
    (setq helixel--selection-type 'rect)))

(defun helixel--recreate-movement (ctx)
  "Replay movement selection from CTX."
  (let ((helixel--current-state 'visual))
    (dolist (m (reverse (helixel-sel-movement-moves ctx)))
      (dotimes (_ (cdr m))
        (funcall (car m))))))

(defun helixel--recreate-search (ctx)
  "Replay search selection from CTX.
Finds the next match, activates the region on it.
If CTX has :entry-kind (insert or append), positions the cursor
at the appropriate offset within the match for insert-text ops.
For insert operations, skips past a current match if point
sits on the pattern start so chained `.` advances correctly."
  (let* ((pat (helixel-sel-search-pattern ctx))
         (dir (helixel-sel-search-dir ctx)))
    (unless pat
      (user-error "No search pattern to repeat"))
    ;; For insert ops, skip past the current match if point sits on
    ;; or near it.  Insert ops preserve the match text (e.g. iX →
    ;; Xhello still contains "hello"), so `.` would otherwise re-find
    ;; the same match.  Change ops delete the match so no skip needed.
    ;;
    ;; Two cases: point at match-start (i after search) → looking-at
    ;; succeeds; point at match-end (a after search) → looking-at
    ;; fails but a backward search from point finds the match ending
    ;; nearby.
    (when (and (helixel-sel-search-entry-kind ctx)
               (let ((orig (point)))
                 (or (looking-at pat)
                     (save-excursion
                       (condition-case nil
                           (progn
                             (helixel-search--search
                              pat 'backward)
                             (let ((m-end (match-end 0))
                                   (m-beg (match-beginning 0)))
                               (if (= m-beg m-end)
                                   ;; Zero-length anchor ($,^,\b):
                                   ;; check same-line proximity
                                   (= (line-number-at-pos orig)
                                      (line-number-at-pos m-end))
                                 (<= (- orig m-end) (length pat)))))
                         (search-failed nil))))))
      (if (eq dir 'backward)
          ;; Backward: go before match-beginning to skip this match.
          (goto-char (max (point-min)
                          (1- (match-beginning 0))))
        ;; Forward: go to match-end to skip this match.
        ;; For zero-length anchors (e.g. $, ^) advance one
        ;; extra char so the subsequent search doesn't re-find
        ;; the same position.
        (goto-char (if (= (match-beginning 0) (match-end 0))
                        (min (point-max) (1+ (match-end 0)))
                      (match-end 0)))))
    (condition-case nil
        (helixel-search--search pat dir)
      (search-failed
       (user-error "Search pattern not found: %s" pat)))
    (push-mark (match-beginning 0) t t)
    (goto-char (match-end 0))
    (setq helixel--selection-type 'char)
    ;; For insert operations: position cursor within the match
    (when-let* ((entry-kind (helixel-sel-search-entry-kind ctx)))
      (let* ((base (if (eq entry-kind 'append)
                       (match-end 0)
                     (match-beginning 0)))
             (cursor-offset (or (helixel-sel-search-cursor-offset ctx) 0)))
        (goto-char (+ base cursor-offset))))))

(defun helixel--recreate-insert-selection-start (ctx)
  "Replay insert-selection-start.  CTX holds :cursor-offset (int or nil)."
  (goto-char (region-beginning))
  (let ((off (helixel-sel-insert-cursor-offset ctx)))
    (when off (forward-char off))))

(defun helixel--recreate-insert-selection-end (ctx)
  "Replay insert-selection-end.  CTX holds :cursor-offset (int or nil)."
  (goto-char (region-end))
  (let ((off (helixel-sel-insert-cursor-offset ctx)))
    (when off (forward-char off))))

(defun helixel--recreate-insert-beginning-line (_ctx)
  "Replay insert-beginning-line.  CTX is ignored."
  (beginning-of-line))

(defun helixel--recreate-insert-end-line (_ctx)
  "Replay insert-end-line.  CTX is ignored."
  (end-of-line))

(defun helixel--recreate-insert-search-offset (ctx)
  "Replay insert-search-offset.  CTX holds :offset (integer)."
  (let ((offset (helixel-sel-insert-offset ctx)))
    (goto-char (+ (match-beginning 0) offset))))

;; ── Region swap utilities ──

(defun helixel--replace-region (str beg end)
  "Replace region from BEG to END with STR.
Return the region replaced as (NEW-BEG . NEW-END)."
  (let* ((len (length str))
         (i-end 0)
         (i-beg 0)
         (i-end-ofs nil)
         (max-skip (min (- end beg) len)))
    ;; Skip common suffix.
    (while (and (< i-end max-skip)
                (eq (aref str (- len i-end 1))
                    (char-after (- end i-end 1))))
      (cl-incf i-end))
    (when (> i-end 0)
      (cl-decf len i-end)
      (cl-decf end i-end)
      (setq i-end-ofs i-end))
    ;; Skip common prefix.
    (setq max-skip (min (- end beg) len))
    (while (and (< i-beg max-skip)
                (eq (aref str i-beg)
                    (char-after (+ beg i-beg))))
      (cl-incf i-beg))
    (when (> i-beg 0)
      (cl-incf beg i-beg))
    ;; Trim common parts from str.
    (when (or (> i-beg 0) (> i-end 0))
      (setq str (substring-no-properties str i-beg len)))
    ;; Replace.
    (goto-char beg)
    (unless (eq beg end)
      (delete-region beg end))
    (unless (string-empty-p str)
      (insert str))
    (when i-end-ofs
      (goto-char (+ (point) i-end-ofs)))
    (cons beg (+ beg (length str)))))

(defun helixel--rect-ranges (beg end)
  "Return a list of (BEG . END) ranges for each line in rectangle BEG..END."
  (let ((result (list)))
    (apply-on-rectangle
     (lambda (col-beg col-end)
       (let ((pos-beg nil)
             (pos-end nil))
         (save-excursion
           (move-to-column col-beg)
           (setq pos-beg (point))
           (move-to-column col-end)
           (setq pos-end (point))
           (push (cons pos-beg pos-end) result))))
     beg end)
    (nreverse result)))

(defun helixel--ranges-overlap (list-a list-b)
  "Return t if any range in LIST-A overlaps any range in LIST-B.
Each range is a cons (BEG . END)."
  (let ((found nil))
    (while (and list-a (null found))
      (let* ((range-a (car list-a))
             (a-beg (car range-a))
             (a-end (cdr range-a))
             (b-list list-b))
        (while (and b-list (null found))
          (let* ((range-b (car b-list))
                 (b-beg (car range-b))
                 (b-end (cdr range-b)))
            (when (and (< a-beg b-end) (< b-beg a-end))
              (setq found t)))
          (setq b-list (cdr b-list))))
      (setq list-a (cdr list-a)))
    found))

(defun helixel--ranges->markers (ranges)
  "Convert RANGES (list of (BEG . END) integers) to marker pairs."
  (mapcar
   (lambda (item)
     (let ((mark-beg (set-marker (make-marker) (car item)))
           (mark-end (set-marker (make-marker) (cdr item))))
       (set-marker-insertion-type mark-beg nil)
       (set-marker-insertion-type mark-end t)
       (cons mark-beg mark-end)))
   ranges))

(defun helixel--columns-from-point (beg end)
  "Return the column offset between points BEG and END."
  (save-excursion
    (let ((col-beg
           (progn
             (goto-char beg)
             (current-column)))
          (col-end
           (progn
             (goto-char end)
             (current-column))))
      (- col-end col-beg))))

;; ── Region swap defcustom ──

(defcustom helixel-swap-imply-region t
  "When non-nil, `helixel-swap' implies a region when none is active.
The implied region extends from point with the same dimensions
as the swap source (stored by `y' or `Y')."
  :type 'boolean
  :group 'helixel)

;; ── Region swap helpers ──

(defun helixel--swap-source-line-count (beg end)
  "Return number of full lines spanned by region BEG..END.
Normalizes BEG to bol and END to include trailing newline."
  (let ((beg-bol (save-excursion (goto-char beg) (pos-bol)))
        (end-eol (save-excursion
                   (goto-char end)
                   (if (bolp) (point)
                     (min (1+ (pos-eol)) (point-max))))))
    (count-lines beg-bol end-eol)))

(defun helixel--swap-imply-range (beg-a end-a is-line-wise)
  "Compute implied region range from source bounds BEG-A..END-A.
When IS-LINE-WISE is non-nil, the implied range starts at bol
and spans the same number of full lines as the source.
Returns (BEG-B . END-B) for the implied region."
  (if is-line-wise
      ;; Line-wise: swap N full lines starting from current line.
      (let* ((nlines (helixel--swap-source-line-count beg-a end-a))
             (beg-b (pos-bol)))
        (save-excursion
          (goto-char beg-b)
          (forward-line (1- nlines))
          (cons beg-b (pos-eol))))
    ;; Column-based / character-based implied region.
    (let* ((beg-a-eol (save-excursion (goto-char beg-a) (pos-eol)))
           (beg-b (point))
           end-b)
      (if (<= end-a beg-a-eol)
          ;; Single-line source: match column span.
          (let ((col-count-a (helixel--columns-from-point beg-a end-a)))
            (save-excursion
              (move-to-column (+ (current-column) col-count-a))
              (setq end-b (point))))
        ;; Multi-line source.
        (save-excursion
          (goto-char end-a)
          (if (bolp)
              (progn
                (cl-decf end-a)
                (unless (<= beg-a end-a)
                  (error "Assertion failed"))
                (goto-char beg-b)
                (beginning-of-line)
                (let ((range-a-lines (1- (count-lines beg-a end-a))))
                  (unless (zerop (forward-line range-a-lines))
                    (user-error
                     (concat "Region swap failed,"
                             " expected %d line(s) after the point")
                     range-a-lines)))
                (setq end-b (pos-eol)))
            (let ((col-end-a (progn (goto-char end-a) (current-column))))
              (goto-char beg-b)
              (beginning-of-line)
              (let ((range-a-lines (1- (count-lines beg-a end-a))))
                (unless (zerop (forward-line range-a-lines))
                  (user-error
                   (concat "Region swap failed,"
                           " expected %d line(s) after the point")
                   range-a-lines)))
              (move-to-column col-end-a)
              (setq end-b (point))))))
      (unless end-b
        (error "Assertion failed"))
      (cons beg-b end-b))))

(defun helixel--swap-rect-imply-region (source-beg source-end len-b)
  "Compute implied rectangle region from source bounds.
SOURCE-BEG, SOURCE-END are positions in current buffer.
LEN-B is the number of lines in source rectangle.
Returns (REGION-BEG . REGION-END)."
  (save-excursion
    (let* ((pos-init (point))
           (col-beg (progn (goto-char source-beg) (current-column)))
           (col-end (progn (goto-char source-end) (current-column)))
           (col-init (progn (goto-char pos-init) (current-column))))
      (when (> col-beg col-end)
        (cl-rotatef col-beg col-end))
      (goto-char (pos-bol))
      (when (> len-b 1)
        (let ((remaining (forward-line (1- len-b))))
          (unless (zerop remaining)
            (user-error
             (concat "Rectangle line count mismatch"
                     " for implied region (%d and %d)")
             (- len-b remaining) len-b))))
      (move-to-column (+ col-init (- col-end col-beg)))
      (when (< (current-column) col-init)
        (user-error
         (concat "Rectangle can't compute implied region"
                 " (last line doesn't meet current column)")))
      (cons pos-init (point)))))

;; ── Region swap implementation ──

(defun helixel--swap-from-source (beg-mark end-mark is-line-wise)
  "Swap current region with the source region at BEG-MARK..END-MARK.
When IS-LINE-WISE is non-nil, treat the source as whole lines.
Returns the source boundaries after swap for updating the swap-source."
  (let* ((beg-a (marker-position beg-mark))
         (end-a (marker-position end-mark))
         (range-a (cons beg-a end-a))
         (is-forward nil)
         (range-b
          (cond
           ((region-active-p)
            (when (eq (point) (region-end))
              (setq is-forward t))
            (cons (region-beginning) (region-end)))
           (helixel-swap-imply-region
            (helixel--swap-imply-range beg-a end-a is-line-wise))
           (t
            (cons (point) (point)))))
         (range-region range-b))
    ;; Ensure range-a is before range-b, no overlap.
    (when (> (car range-a) (car range-b))
      (cl-rotatef range-a range-b))
    (when (> (cdr range-a) (car range-b))
      (user-error "Region swap unsupported for overlapping regions"))
    ;; Swap.
    (let ((str-a (buffer-substring-no-properties
                  (car range-a) (cdr range-a)))
          (str-b (buffer-substring-no-properties
                  (car range-b) (cdr range-b))))
      (helixel--replace-region str-a (car range-b) (cdr range-b))
      (setcdr range-b (+ (cdr range-b)
                         (- (length str-a)
                            (- (cdr range-b) (car range-b)))))
      (helixel--replace-region str-b (car range-a) (cdr range-a))
      (let ((delta (- (length str-b)
                      (- (cdr range-a) (car range-a)))))
        (cl-incf (car range-b) delta)
        (cl-incf (cdr range-b) delta)
        (cl-incf (cdr range-a) delta)))
    ;; Restore region (without activating it).
    (if is-forward
        (progn
          (set-marker (mark-marker) (car range-region))
          (goto-char (cdr range-region)))
      (set-marker (mark-marker) (cdr range-region))
      (goto-char (car range-region)))
    (cons (car range-a) (cdr range-a))))

(defun helixel--extend-rect-ranges (ranges n)
  "Extend RANGES to N lines by adding lines downward.
Each added line uses the same column span as the original last range.
RANGES is a list of (BEG . END) cons cells."
  (let* ((last (car (last ranges)))
         (col-beg (save-excursion
                    (goto-char (car last)) (current-column)))
         (col-end (save-excursion
                    (goto-char (cdr last)) (current-column)))
         (extra (- n (length ranges))))
    (if (<= extra 0)
        ranges
      (append ranges
              (save-excursion
                (goto-char (cdr last))
                (cl-loop repeat extra
                         do (forward-line 1)
                         collect (progn
                                   (move-to-column col-beg)
                                   (let ((b (point)))
                                     (move-to-column col-end)
                                     (cons b (point))))))))))

(defun helixel--swap-from-source-rect (beg-mark end-mark &optional truncate)
  "Swap current region with the source rect at BEG-MARK..END-MARK.
By default extends the shorter rectangle to match the longer one.
When TRUNCATE is non-nil, swap only min(N,M) line pairs instead.
Returns the new source end position for updating the swap-source."
  (let* ((source-beg (marker-position beg-mark))
         (source-end (marker-position end-mark))
         (line-ranges-b (helixel--rect-ranges source-beg source-end))
         (len-b (length line-ranges-b))
         (is-forward nil)
         (is-swap nil)
         region-beg region-end region-end-next source-end-next)
    ;; Determine region bounds.
    (if (region-active-p)
        (progn
          (setq region-beg (region-beginning))
          (setq region-end (region-end))
          (when (eq (point) (region-end))
            (setq is-forward t)))
      (let ((implied (helixel--swap-rect-imply-region
                      source-beg source-end len-b)))
        (setq region-beg (car implied))
        (setq region-end (cdr implied))))
    ;; Compute and validate line ranges.
    (let* ((line-ranges-a (helixel--rect-ranges region-beg region-end))
           (len-a (length line-ranges-a)))
      ;; Adjust line counts when they differ.
      (cond
       (truncate
        (when (> len-a len-b)
          (setq line-ranges-a (cl-subseq line-ranges-a 0 len-b)))
        (when (> len-b len-a)
          (setq line-ranges-b (cl-subseq line-ranges-b 0 len-a))))
       (t
        (let ((nswap (max len-a len-b)))
          (setq line-ranges-a (helixel--extend-rect-ranges
                               line-ranges-a nswap)
                line-ranges-b (helixel--extend-rect-ranges
                               line-ranges-b nswap)))))
      (when (helixel--ranges-overlap line-ranges-a line-ranges-b)
        (user-error
         "Region swap unsupported for overlapping (rectangle) regions"))
      (when (> (car (car line-ranges-a))
               (car (car line-ranges-b)))
        (cl-rotatef line-ranges-a line-ranges-b)
        (setq is-swap t))
      ;; Convert to markers and swap line-by-line.
      (let ((markers-a (helixel--ranges->markers line-ranges-a))
            (markers-b (helixel--ranges->markers line-ranges-b)))
        (save-excursion
          (while markers-a
            (let* ((range-a (pop markers-a))
                   (range-b (pop markers-b))
                   (text-a (buffer-substring-no-properties
                            (car range-a) (cdr range-a)))
                   (text-b (buffer-substring-no-properties
                            (car range-b) (cdr range-b))))
              (unless (string-equal text-a text-b)
                ;; Snapshot positions to avoid adjacent-marker shift.
                (let ((ra-beg (marker-position (car range-a)))
                      (ra-end (marker-position (cdr range-a)))
                      (rb-beg (marker-position (car range-b)))
                      (rb-end (marker-position (cdr range-b))))
                  ;; Replace target first (rb after ra, won't shift ra).
                  (helixel--replace-region text-a rb-beg rb-end)
                  (helixel--replace-region text-b ra-beg ra-end)))
              (unless markers-a
                (if is-swap
                    (setq source-end-next
                          (marker-position (cdr range-a))
                          region-end-next
                          (marker-position (cdr range-b)))
                  (setq source-end-next
                        (marker-position (cdr range-b))
                        region-end-next
                        (marker-position (cdr range-a)))))
              (set-marker (car range-a) nil)
              (set-marker (cdr range-a) nil)
              (set-marker (car range-b) nil)
              (set-marker (cdr range-b) nil))))))
    ;; Restore region position.
    (if is-forward
        (goto-char region-end-next)
      (set-marker (mark-marker) region-end-next))
    source-end-next))

;; ── Swap source helpers ──

(defun helixel--swap-source-type ()
  "Return the swap-source type for the current selection.
Returns nil (char), `line', or `rect'.
More permissive than `helixel--selection-type' — detects
`rectangle-mark-mode' directly."
  (cond
   ((eq (helixel--selection-type) 'rect) 'rect)
   ((eq (helixel--selection-type) 'line) 'line)
   ((bound-and-true-p rectangle-mark-mode) 'rect)
   (t nil)))

(defun helixel--swap-source-from-kill ()
  "Extract swap-source plist from the current kill/register top.
Returns the plist if markers are live in their native buffer,
regardless of whether that buffer is the current one.
Returns nil if no valid swap-source property is found."
  (when-let* ((text (helixel--current-kill 0 t))
              (src (get-text-property 0 'helixel-swap-source text)))
    (let ((beg (plist-get src :beg))
          (end (plist-get src :end))
          (buf (plist-get src :buffer))
          (type (plist-get src :type)))
      (when (and (markerp beg) (markerp end)
                 (eq (marker-buffer beg) buf)
                 (marker-position beg)
                 (marker-position end))
        (list :beg beg :end end :buffer buf :type type)))))

;; ── Region swap command ──

(helixel-define-command helixel-swap
    (:category edit :subcat swap :params (&optional arg))
  (interactive "*P")
  (let* ((truncate arg)
         (source (helixel--swap-source-from-kill)))
    (unless source
      (user-error
       (if (helixel--register-active-p)
           "Register \"%c has no swap source"
         "No swap source — use `y' to copy first")
       (or helixel--current-register helixel-default-register)))
    (let* ((beg (plist-get source :beg))
           (end (plist-get source :end))
           (source-buf (plist-get source :buffer))
           (swaptype (plist-get source :type))
           (same-buf (eq source-buf (current-buffer))))
      (if same-buf
          ;; Same buffer: position-aware swap.
          (let ((is-line-wise (eq swaptype 'line))
                (is-rect-wise (eq swaptype 'rect)))
            (when (and (region-active-p)
                       (bound-and-true-p rectangle-mark-mode))
              (setq is-rect-wise t)
              (setq is-line-wise nil))
            (cond
             (is-rect-wise
              (helixel--swap-from-source-rect beg end truncate))
             (t
              (helixel--swap-from-source beg end is-line-wise))))
        ;; Cross-buffer: read source text, exchange, write back.
        (let* ((source-text (with-current-buffer source-buf
                              (buffer-substring-no-properties
                               (marker-position beg)
                               (marker-position end))))
               (has-region (region-active-p))
               (target-beg (if has-region
                               (region-beginning)
                             (point)))
               (target-end (if has-region (region-end) (point)))
               (target-text
                (cond
                 (has-region
                  (buffer-substring-no-properties
                   target-beg target-end))
                 ((eq swaptype 'line)
                  (let ((nlines
                         (with-current-buffer source-buf
                           (helixel--swap-source-line-count
                            (marker-position beg)
                            (marker-position end)))))
                    (setq target-beg (pos-bol))
                    (save-excursion
                      (goto-char target-beg)
                      (forward-line (1- nlines))
                      (setq target-end (pos-eol)))
                    (buffer-substring-no-properties
                     target-beg target-end)))
                 (t
                  (setq target-end target-beg)
                  ""))))
          ;; Write target text into source buffer at marker positions.
          (with-current-buffer source-buf
            (helixel--replace-region target-text
                                     (marker-position beg)
                                     (marker-position end)))
          ;; Write source text into current buffer.
          (helixel--replace-region source-text target-beg target-end)
          (message "Swapped with buffer `%s'" (buffer-name source-buf))
          ;; Store target text as new swap source (now in current buffer).
          (let* ((new-end (+ target-beg (length source-text)))
                 (stored-text (if (string-empty-p target-text)
                                  source-text
                                target-text)))
            (helixel--kill-new
             (propertize stored-text
                         'helixel-swap-source
                         (list :beg (copy-marker target-beg)
                               :end (copy-marker new-end)
                               :buffer (current-buffer)
                               :type nil))
             :replace)
            (if has-region
                (progn
                  (set-marker (mark-marker) target-beg)
                  (goto-char new-end))
              (goto-char new-end))))))))

;; ── Edit-op change runner ──

(defun helixel--repeat-change-core (tx)
  "Repeat change TX: delete selection, replay kmacro keys or insert text.
TX is the complete edit transaction (see `helixel-edit-make').
Kmacro keys/commands (primary) capture the full insert-mode keystrokes.
Text (fallback) is used when keys/commands are unavailable (tests).

For rect selections the stored text is replayed on every subsequent
rectangle line via `helixel--rect-replay' — no state-switching side
-effect (avoids an unnecessary helixel-insert-exit during replay)."
  (let* ((keys (helixel--repeat-get-keys tx))
         (cmds (plist-get (helixel-edit-payload tx) :commands))
         (text (plist-get (helixel-edit-payload tx) :inserted-text)))
    (cond
     ((and (use-region-p) (eq (helixel--selection-type) 'rect))
      (helixel--rect-change)
      (if (or keys cmds)
          (helixel--execute-keys keys cmds)
        (when text (insert text)))
      (helixel--rect-replay))
     (t
      (helixel--delete-selection)
      (if (or keys cmds)
          (helixel--execute-keys keys cmds)
        (when text (insert text)))))))

;; ── Edit-op registry ──
;; Each operator registers a `:runner' (called by `.`) and a `:display'
;; label via `helixel-register-op' or `helixel-define-operator'.
;; Runners call the editing commands defined below.

;; Ops whose `.` runner IS the command → use `helixel-define-operator'
;; below (kill, copy, replace, paste-after, paste-before).

;; Ops with non-trivial runners (need tx payload) → register separately:
(helixel-register-op change :display "c" :repeat-advance nil
  :runner #'helixel--repeat-change-core)

(helixel-register-op replace-char :repeat-advance 'line
  :display (lambda (tx)
             (let ((c (plist-get (helixel-edit-payload tx) :char)))
               (if c (format "R[%c]" c) "R")))
  :runner (lambda (tx)
            (helixel-replace-char
             (plist-get (helixel-edit-payload tx) :char))))

(helixel-register-op insert-text :display "i" :repeat-advance 'line
  :runner (lambda (tx)
            (let ((keys (plist-get (helixel-edit-payload tx) :keys))
                  (cmds (plist-get (helixel-edit-payload tx) :commands)))
              (if (or keys cmds)
                  (progn (helixel--execute-keys keys cmds))
                (insert (or (plist-get (helixel-edit-payload tx) :text)
                            ""))))))


;; ── Selection type validator ──

(defun helixel--selection-type ()
  "Return current selection type, or nil.
Validates that the region actually matches the claimed type.
Supports `line' and `rect'."
  (when (region-active-p)
    (cond
     ((eq helixel--selection-type 'rect)
      (when rectangle-mark-mode 'rect))
     ((eq helixel--selection-type 'line)
      (let ((beg (region-beginning))
            (end (region-end)))
        (when (and (save-excursion (goto-char beg) (bolp))
                   (save-excursion (goto-char end) (or (eolp) (eobp))))
          'line)))
     ((eq helixel--selection-type 'textobj)
      'textobj))))

;; ── Kill & Change ──

(helixel-define-operator helixel-kill-thing-at-point
    (:op kill :display "d" :repeat-advance nil)
  (helixel--record-edit 'kill)
  (helixel--delete-selection)
  (helixel--register-consume)
  (helixel--clear-data))

(helixel-define-command helixel-change-thing-at-point
    (:category edit :subcat change)
  (helixel--record-edit 'change)
  (if (and (use-region-p) (eq (helixel--selection-type) 'rect))
      (progn (helixel--rect-change)
             (helixel--register-consume))
    (helixel--delete-selection)
    (helixel--register-consume)
    (setq helixel--change-track-marker (point-marker))
    (helixel--enter-insert)))

;; ── Replace ──

(defvar helixel--replace-pop-bounds nil
  "Bounds (BEG . END) of text from `helixel-replace' or `helixel-replace-pop'.
Value is nil after a rectangle replace.
Used to support cycling through the kill ring after a replace.")

(helixel-define-operator helixel-replace
    (:op replace :display "r" :repeat-advance 'line)
  (helixel--record-edit 'replace)
  (if (and (not (helixel--register-active-p))
           (= 0 (length kill-ring)))
      (message "nothing to yank")
    (let* ((text (or (helixel--current-kill 0 t) (current-kill 0 t)))
           (linewise-p (helixel--linewise-kill-p text))
           (rectwise-p (helixel--rect-wise-kill-p text))
           (bare (string-trim-right (substring-no-properties text) "\n"))
           (pop-start nil)
           (_bare-rect (unless (or linewise-p rectwise-p) bare)))
      (cond
       ;; Rect selection — no pop tracking (rect bounds are multi-line)
       ((and (use-region-p) (eq (helixel--selection-type) 'rect))
        (let* ((beg (region-beginning))
               (end (region-end))
               (lines (nth 1 (get-text-property 0 'yank-handler text))))
          (delete-rectangle beg end)
          (goto-char beg)
          (if (and rectwise-p lines)
              (insert-rectangle lines)
            (insert bare)))
        (setq helixel--replace-pop-bounds nil))
       ;; Line-wise selection: expand to full line bounds
       ((and (use-region-p) (eq (helixel--selection-type) 'line))
        (when-let* ((bounds (helixel--line-bounds-of-region)))
          (delete-region (car bounds) (cdr bounds))
          (setq pop-start (point))
          (insert (if linewise-p text (concat bare "\n")))
          (setq helixel--replace-pop-bounds
                (cons pop-start (point)))))
       ;; Charwise region
       ((use-region-p)
        (delete-region (region-beginning) (region-end))
        (setq pop-start (point))
        (insert (if (or linewise-p rectwise-p)
                    bare
                  (substring-no-properties text)))
        (setq helixel--replace-pop-bounds
              (cons pop-start (point))))
       ;; No region — replace char at point
       (t
        (when helixel-replace-delete-char-p
          (delete-char 1))
        (setq pop-start (point))
        (let ((helixel--inhibit-repeat-record t))
          (helixel-yank))
        (setq helixel--replace-pop-bounds
              (cons pop-start (point)))))
      (helixel--register-consume)
      (helixel--clear-data))))

;; `helixel-replace-pop' cycles through the `kill-ring' to replace
;; the text inserted by the previous `helixel-replace' or
;; `helixel-replace-pop', similar to `yank-pop'.
;;
;; When called after `helixel-replace' or `helixel-replace-pop',
;; ARG advances N kills forward (default 1).
;;
;; When called directly, prompts to select a `kill-ring' entry and
;; replaces the region/char-at-point with it, like `helixel-replace'
;; but letting you choose which kill to use.  Subsequent calls
;; then cycle through the `kill-ring' as usual.
(helixel-define-command helixel-replace-pop
    (:category edit :subcat replace-pop :params (&optional arg))
  (interactive "*p")
  (setq arg (or arg 1))
  (if (memq last-command '(helixel-replace helixel-replace-pop))
      ;; ── Cycle: replace bounds text with next kill-ring entry ──
      (progn
        (unless helixel--replace-pop-bounds
          (user-error "No replace text to cycle"))
        (setq this-command 'helixel-replace-pop)
        (let* ((beg (car helixel--replace-pop-bounds))
               (end (cdr helixel--replace-pop-bounds))
               (inhibit-read-only t)
               (text (helixel--current-kill arg))
               (ends-with-newline (char-equal (char-before end) ?\n)))
          (delete-region beg end)
          (goto-char beg)
          (if (and ends-with-newline
                   (not (string-suffix-p "\n" text)))
              (insert (concat text "\n"))
            (insert-for-yank text))
          (setq helixel--replace-pop-bounds
                (cons beg (point)))))
    ;; ── Direct call: browse kill-ring and replace ──
    (let* ((candidates
            (mapcar #'substring-no-properties kill-ring))
           (selected
            (completing-read "Replace with: " candidates nil t))
           (idx (cl-position selected candidates :test #'string=))
           (text (nth idx kill-ring))
           (linewise-p (helixel--linewise-kill-p text))
           (rectwise-p (helixel--rect-wise-kill-p text))
           (bare (string-trim-right
                  (substring-no-properties text) "\n"))
           (pop-start nil))
      (unless text
        (user-error "No kill-ring entry selected"))
      (setq this-command 'helixel-replace-pop)
      (cond
       ;; Rect selection — no pop tracking
       ((and (use-region-p)
             (eq (helixel--selection-type) 'rect))
        (let* ((beg (region-beginning))
               (end (region-end))
               (lines (nth 1 (get-text-property
                              0 'yank-handler text))))
          (delete-rectangle beg end)
          (goto-char beg)
          (if (and rectwise-p lines)
              (insert-rectangle lines)
            (insert bare)))
        (setq helixel--replace-pop-bounds nil))
       ;; Line-wise selection
       ((and (use-region-p)
             (eq (helixel--selection-type) 'line))
        (when-let* ((bounds (helixel--line-bounds-of-region)))
          (delete-region (car bounds) (cdr bounds))
          (setq pop-start (point))
          (insert (if linewise-p text (concat bare "\n")))
          (setq helixel--replace-pop-bounds
                (cons pop-start (point)))))
       ;; Charwise region
       ((use-region-p)
        (delete-region (region-beginning) (region-end))
        (setq pop-start (point))
        (insert (if (or linewise-p rectwise-p)
                    bare
                  (substring-no-properties text)))
        (setq helixel--replace-pop-bounds
              (cons pop-start (point))))
       ;; No region — replace char at point
       (t
        (when helixel-replace-delete-char-p
          (delete-char 1))
        (setq pop-start (point))
        (insert-for-yank text)
        (setq helixel--replace-pop-bounds
              (cons pop-start (point))))))))

;; ── Copy ──

(helixel-define-operator helixel-kill-ring-save
    (:op copy :display "y" :repeat-advance 'line)
  (helixel--record-edit 'copy)
  (when (use-region-p)
    (let ((swap-source
           (list :beg (copy-marker (region-beginning))
                 :end (copy-marker (region-end))
                 :buffer (current-buffer)
                 :type (helixel--swap-source-type))))
      (cond
       ((eq (helixel--selection-type) 'rect)
        (let ((lines (extract-rectangle (region-beginning) (region-end))))
          (helixel--kill-new
           (propertize (helixel--rect-wise-text lines)
                       'helixel-swap-source swap-source)
           :copy)))
       ((eq (helixel--selection-type) 'line)
        (when-let* ((bounds (helixel--line-bounds-of-region))
                    (text (filter-buffer-substring
                           (car bounds) (cdr bounds))))
          (helixel--kill-new
           (propertize (helixel--linewise-text text)
                       'helixel-swap-source swap-source)
           :copy)))
       (t
        (helixel--kill-new
         (propertize
          (filter-buffer-substring (region-beginning) (region-end))
          'helixel-swap-source swap-source)
         :copy)))))
  (helixel--register-consume)
  (helixel--clear-data))

;; ── Yank ──

(helixel-define-operator helixel-yank
    (:op paste-after :display "p" :repeat-advance 'line
     :params (&optional arg))
  (interactive "*P")
  (helixel--record-edit 'paste-after)
  (prog1
      (cond
       ((helixel--rect-wise-kill-p)
        (let* ((text (helixel--current-kill 0 t))
               (lines (when text
                        (nth 1 (get-text-property
                                0 'yank-handler text)))))
          (if lines
              (insert-rectangle lines)
            (when text (insert-for-yank text)))))
       ((helixel--linewise-kill-p)
        (let ((text (helixel--current-kill 0 t)))
          (when text (insert-for-yank text))))
       (t
        (helixel--yank arg)))
    (helixel--register-consume)))

(helixel-define-operator helixel-yank-before
    (:op paste-before :display "P" :repeat-advance 'line
     :params (&optional arg))
  (interactive "*P")
  (helixel--record-edit 'paste-before)
  (prog1
      (cond
       ((helixel--rect-wise-kill-p)
        (let* ((text (helixel--current-kill 0 t))
               (lines (when text
                        (nth 1 (get-text-property
                                0 'yank-handler text)))))
          (if lines
              (insert-rectangle lines)
            (when text (insert-for-yank text)))))
       ((helixel--linewise-kill-p)
        (let ((text (helixel--current-kill 0 t)))
          (when text (insert-for-yank text))))
       (t
        (helixel--yank arg)))
    (helixel--register-consume)))

;; ── Indent ──
;; helixel--replay-multiplier is bound by the op runner during `.`
;; replay so that the indent count is taken from the amalgamated
;; :multiplier payload instead of the interactive prefix.

(defvar helixel--replay-multiplier nil
  "When non-nil, overrides the indent count during `.` replay.
Set by the op runner from the transaction's :multiplier payload.")

(helixel-define-operator helixel-indent-left
    (:op indent-left :display "<" :repeat-advance 'line
     :params (&optional count))
  (interactive "p")
  (let* ((n (or helixel--replay-multiplier count 1))
         (consecutive-p nil))
    (unless (use-region-p)
      ;; Consecutive (same op): reuse selection, indent 1 level,
      ;; amalgamate multiplier into the last tx.
      (when-let* ((tx helixel--last-tx)
                  (sel (helixel-edit-sel tx)))
        (when (eq (helixel-edit-op tx) 'indent-left)
          (when-let* ((m (helixel-edit-marker tx))
                      (pos (marker-position m)))
            (goto-char pos))
          (let ((helixel--inhibit-action-track t))
            (helixel--recreate-selection sel))
          (indent-rigidly (region-beginning) (region-end) (- 1))
          (let* ((payload (helixel-edit-payload tx))
                 (mult (or (plist-get payload :multiplier) 1)))
            (setf (helixel-edit-payload tx)
                  (plist-put (copy-sequence payload)
                             :multiplier (1+ mult))))
          (goto-char (region-beginning))
          (setq consecutive-p t))))
    (unless consecutive-p
      (if (use-region-p)
          (indent-rigidly (region-beginning) (region-end) (- n))
        (indent-rigidly (line-beginning-position) (line-end-position)
                        (- n)))
      (when (use-region-p)
        (goto-char (region-beginning)))
      (helixel--record-edit 'indent-left :multiplier n)))
  (helixel--clear-data))

(put 'indent-left 'helixel-op-runner
     (lambda (tx)
       (let ((helixel--replay-multiplier
              (or (plist-get (helixel-edit-payload tx) :multiplier) 1)))
         (helixel-indent-left))))

(helixel-define-operator helixel-indent-right
    (:op indent-right :display ">" :repeat-advance 'line
     :params (&optional count))
  (interactive "p")
  (let* ((n (or helixel--replay-multiplier count 1))
         (consecutive-p nil))
    (unless (use-region-p)
      ;; Consecutive (same op): reuse selection, indent 1 level,
      ;; amalgamate multiplier into the last tx.
      (when-let* ((tx helixel--last-tx)
                  (sel (helixel-edit-sel tx)))
        (when (eq (helixel-edit-op tx) 'indent-right)
          (when-let* ((m (helixel-edit-marker tx))
                      (pos (marker-position m)))
            (goto-char pos))
          (let ((helixel--inhibit-action-track t))
            (helixel--recreate-selection sel))
          (indent-rigidly (region-beginning) (region-end) 1)
          (let* ((payload (helixel-edit-payload tx))
                 (mult (or (plist-get payload :multiplier) 1)))
            (setf (helixel-edit-payload tx)
                  (plist-put (copy-sequence payload)
                             :multiplier (1+ mult))))
          (goto-char (region-beginning))
          (setq consecutive-p t))))
    (unless consecutive-p
      (if (use-region-p)
          (indent-rigidly (region-beginning) (region-end) n)
        (indent-rigidly (line-beginning-position) (line-end-position) n))
      (when (use-region-p)
        (goto-char (region-beginning)))
      (helixel--record-edit 'indent-right :multiplier n)))
  (helixel--clear-data))

(put 'indent-right 'helixel-op-runner
     (lambda (tx)
       (let ((helixel--replay-multiplier
              (or (plist-get (helixel-edit-payload tx) :multiplier) 1)))
         (helixel-indent-right))))

;; ── Case operations ──

(helixel-define-operator helixel-toggle-case
    (:op toggle-case :display "~" :subcat case
     :params (&optional count))
  (interactive "p")
  (helixel--record-edit 'toggle-case :count (or count 1))
  (if (use-region-p)
      (let ((text (buffer-substring (region-beginning) (region-end))))
        (delete-region (region-beginning) (region-end))
        (insert (mapconcat (lambda (c)
                             (char-to-string
                              (if (eq c (upcase c)) (downcase c) (upcase c))))
                           text "")))
    (dotimes (_ (or count 1))
      (let ((c (following-char)))
        (delete-char 1)
        (insert (if (eq c (upcase c)) (downcase c) (upcase c))))))
  (helixel--clear-data))

(helixel-define-operator helixel-downcase
    (:op downcase :display "gu" :repeat-advance 'line
     :subcat case :params (&optional count))
  (interactive "p")
  (helixel--record-edit 'downcase :count (or count 1))
  (if (use-region-p)
      (downcase-region (region-beginning) (region-end))
    (downcase-word (or count 1)))
  (helixel--clear-data))

(helixel-define-operator helixel-upcase
    (:op upcase :display "gU" :repeat-advance 'line
     :subcat case :params (&optional count))
  (interactive "p")
  (helixel--record-edit 'upcase :count (or count 1))
  (if (use-region-p)
      (upcase-region (region-beginning) (region-end))
    (upcase-word (or count 1)))
  (helixel--clear-data))

;; ── Comment toggle ──

(helixel-define-operator helixel-comment-toggle
    (:op comment-toggle :display "gc" :subcat comment)
  (helixel--record-edit 'comment-toggle)
  (if (use-region-p)
      (comment-or-uncomment-region (region-beginning) (region-end))
    (comment-dwim nil))
  (helixel--clear-data))

;; ── Shell command filter ──

(helixel-define-operator helixel-shell-command
    (:op shell-command :display "!" :repeat-advance 'line
     :subcat shell)
  (helixel--record-edit 'shell-command)
  (let ((cmd (read-shell-command "!")))
    (if (use-region-p)
        (shell-command-on-region
         (region-beginning) (region-end) cmd nil nil
         (when current-prefix-arg
           (get-buffer-create "*Shell Command Output*")))
      (shell-command-on-region
       (line-beginning-position) (line-end-position) cmd nil nil
       (when current-prefix-arg
         (get-buffer-create "*Shell Command Output*")))))
  (helixel--clear-data))

;; ── Text formatting ──

(helixel-define-operator helixel-fill
    (:op fill :display "gq" :subcat fill)
  (helixel--record-edit 'fill)
  (if (use-region-p)
      (fill-region (region-beginning) (region-end))
    (fill-paragraph nil))
  (helixel--clear-data))

;; ── Join lines ──

(helixel-register-op join-lines :display "J" :repeat-advance nil
  :runner (lambda (tx)
            (let ((n (or (plist-get (helixel-edit-payload tx) :count) 2)))
              (dotimes (_ (1- n))
                (join-line 1)))))

(helixel-define-command helixel-join-lines
    (:category edit :subcat join-lines :params (&optional count))
  (interactive "p")
  (let ((n (max (or count 1) 2)))
    (helixel--record-edit 'join-lines :count n)
    (dotimes (_ (1- n))
      (join-line 1))
    (helixel--clear-data)))

(provide 'helixel-common)
;;; helixel-common.el ends here
