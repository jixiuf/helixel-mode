;;; helixel-swap.el --- Region swap command -*- lexical-binding: t; -*-

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
;;
;; Region swap command (bound to `S' in normal mode).
;;
;; Swaps the current region (or implied region) with a previously
;; yanked/copied source stored as a text property on the kill-ring
;; entry.  Supports character-wise, line-wise, and rectangle swaps,
;; same-buffer and cross-buffer.

;;; Code:

(require 'cl-lib)
(require 'rect)
(require 'helixel-state)
(require 'helixel-macros)
(require 'helixel-editing)

;; ── Region swap utilities ──

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
      (let* ((nlines (helixel--swap-source-line-count beg-a end-a))
             (beg-b (pos-bol)))
        (save-excursion
          (goto-char beg-b)
          (forward-line (1- nlines))
          (cons beg-b (pos-eol))))
    (let* ((beg-a-eol (save-excursion (goto-char beg-a) (pos-eol)))
           (beg-b (point))
           end-b)
      (if (<= end-a beg-a-eol)
          (let ((col-count-a (helixel--columns-from-point beg-a end-a)))
            (save-excursion
              (move-to-column (+ (current-column) col-count-a))
              (setq end-b (point))))
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
    (when (> (car range-a) (car range-b))
      (cl-rotatef range-a range-b))
    (when (> (cdr range-a) (car range-b))
      (user-error "Region swap unsupported for overlapping regions"))
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
    (let* ((line-ranges-a (helixel--rect-ranges region-beg region-end))
           (len-a (length line-ranges-a)))
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
                (let ((ra-beg (marker-position (car range-a)))
                      (ra-end (marker-position (cdr range-a)))
                      (rb-beg (marker-position (car range-b)))
                      (rb-end (marker-position (cdr range-b))))
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
    (if is-forward
        (goto-char region-end-next)
      (set-marker (mark-marker) region-end-next))
    source-end-next))

;; ── Swap source helpers ──

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
          (with-current-buffer source-buf
            (helixel--replace-region target-text
                                     (marker-position beg)
                                     (marker-position end)))
          (helixel--replace-region source-text target-beg target-end)
          (message "Swapped with buffer `%s'" (buffer-name source-buf))
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

(provide 'helixel-swap)
;;; helixel-swap.el ends here
