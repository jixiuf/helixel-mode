;;; helixel-next-error.el --- Next-error target snapshot for helixel  -*- lexical-binding: t -*-

;; Copyright (C) 2024  Free Software Foundation, Inc.

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

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Builds a snapshot of all compilation/grep target positions as a
;; pure-data vector, then navigates it by index: one step function
;; handles both in-buffer and cross-buffer movement by visiting the
;; target file directly.  No `next-error' calls during navigation —
;; the only stateful entry point is `next-error-hook', which syncs
;; the initial index from `compilation-current-error'.
;;
;; Data model:
;;   - `helixel-ne--target'   one match: absolute FILE, LINE,
;;                            COL-BEG/COL-END (nil COL-END = whole line),
;;                            ENTRY-POS in the compilation buffer.
;;   - snapshot vector        all targets in compilation-buffer order,
;;                            cached per compilation buffer, invalidated
;;                            on `buffer-chars-modified-tick' change.
;;   - `helixel-ne--target-idx'  current index (buffer-local in the
;;                            compilation buffer).
;;
;; Consumers: n/N repeat (`helixel-search'), `,' motion repeat,
;; multi-cursor spawn (`helixel-mc-core') and mark/skip
;; (`helixel-mc-spawn').

;;; Code:

(require 'cl-lib)
(require 'helixel-core)
(require 'helixel-motion)
(require 'helixel-search)

(eval-when-compile
  (require 'compile)
  (require 'grep))

(declare-function compilation-next-error "compile"
                  (n &optional different-file pt))
(declare-function compilation--ensure-parse "compile" (limit))
(declare-function next-error "simple" (&optional arg reset))
(declare-function previous-error "simple" (&optional arg))

;; ── Target struct (data only, no markers) ──

(cl-defstruct (helixel-ne--target
               (:constructor helixel-ne--target--create)
               (:copier nil))
  "A single next-error navigation target stored in the snapshot.
FILE is the absolute filename string.
FILE-TRUE is FILE normalized with `file-truename', computed once
at snapshot build time; all file comparisons use it via
`helixel-ne--target-truename'.
LINE is the 1-indexed line number.
COL-BEG is the 0-indexed column start of the match.
COL-END is the 0-indexed exclusive column end, or nil for
line-level entries without precise column info.
ENTRY-POS is the position in the compilation/grep buffer
of the entry that produced this target."
  file
  file-true
  line
  col-beg
  col-end
  entry-pos)

;; ── Cache (buffer-local in compilation buffer) ──

(defvar-local helixel-ne--all-targets nil
  "Vector of `helixel-ne--target' for all \=`next-error' entries.
Buffer-local in the compilation/grep buffer.  Built once and
invalidated when `buffer-chars-modified-tick' changes.")

(defvar-local helixel-ne--all-targets-tick nil
  "`buffer-chars-modified-tick' at the time of the last snapshot build.")

(defvar-local helixel-ne--target-idx nil
  "Index into `helixel-ne--all-targets' of the last visited target.
Buffer-local in the compilation/grep buffer.  nil means no target
has been visited yet: forward stepping starts at index 0,
backward stepping at the last index.")

;; ── Snapshot API ──

(defun helixel-ne--targets (&optional force)
  "Return the cached snapshot vector, building it if stale.
FORCE non-nil rebuilds unconditionally.
Returns nil when `next-error-last-buffer' is unavailable.

The returned vector is in compilation-buffer order (the order
`next-error' would visit entries).  Callers should NOT mutate it."
  (when-let* ((src-buf next-error-last-buffer)
              ((buffer-live-p src-buf)))
    (with-current-buffer src-buf
      (let ((tick (buffer-chars-modified-tick)))
        (when (or force
                  (not helixel-ne--all-targets)
                  (not (eq helixel-ne--all-targets-tick tick)))
          (setq helixel-ne--all-targets (helixel-ne--collect-targets)
                helixel-ne--all-targets-tick tick)))
      helixel-ne--all-targets)))

(defun helixel-ne--index-of-entry (targets entry-pos)
  "Return the index of the first target in TARGETS with ENTRY-POS.
Returns nil when no target matches."
  (let ((n (length targets))
        (result nil)
        (i 0))
    (while (and (< i n) (not result))
      (when (= (helixel-ne--target-entry-pos (aref targets i)) entry-pos)
        (setq result i))
      (setq i (1+ i)))
    result))

(defsubst helixel-ne--target-truename (tgt)
  "Return TGT's file truename.
Uses the value normalized at snapshot build time; falls back to
computing `file-truename' on demand for hand-built targets."
  (or (helixel-ne--target-file-true tgt)
      (and (helixel-ne--target-file tgt)
           (file-truename (helixel-ne--target-file tgt)))))

(defun helixel-ne--targets-for-file (filename &optional targets)
  "Return a list of targets in TARGETS whose FILE equals FILENAME.
FILENAME is compared with `file-truename'.
TARGETS defaults to `helixel-ne--targets'.
Returns a list preserving compilation-buffer order."
  (let ((normalized (file-truename filename)))
    (seq-filter
     (lambda (tgt)
       (and (helixel-ne--target-file tgt)
            (string-equal (helixel-ne--target-truename tgt)
                          normalized)))
     (or targets (helixel-ne--targets)))))

;; ── Navigation ──

(defun helixel-ne--comp-buf ()
  "Return the live `next-error' source buffer, or signal `user-error'."
  (unless (and (boundp 'next-error-last-buffer)
               next-error-last-buffer
               (buffer-live-p next-error-last-buffer))
    (user-error "No live compilation buffer for next-error repeat"))
  next-error-last-buffer)

(defun helixel-ne--step-index (targets cur dir &optional truename)
  "Return the next index into TARGETS from CUR in DIR.
CUR is the current index, or nil to start before the first
target (forward) or after the last (backward).  When TRUENAME is
non-nil, skip targets whose file truename differs.  Return nil
when no qualifying target exists in DIR."
  (let* ((n (length targets))
         (delta (if (eq dir 'forward) 1 -1))
         (idx (+ (or cur (if (eq dir 'forward) -1 n)) delta)))
    (while (and (>= idx 0) (< idx n) truename
                (not (string-equal
                      (helixel-ne--target-truename (aref targets idx))
                      truename)))
      (setq idx (+ idx delta)))
    (and (>= idx 0) (< idx n) idx)))

(defun helixel-ne--step (dir)
  "Navigate one step in DIR through the snapshot.
DIR is `forward' or `backward'.

Uniform for in-buffer and cross-buffer movement: visits the
target's file, jumps to its line/column, and selects the match.
Backward across a file boundary correctly lands on the LAST
match of the previous entry (index arithmetic, not entry sync).

Signals `user-error' at the first/last target.
When the snapshot is empty (e.g. xref buffers), delegates to
`next-error' / `previous-error' so non-compilation sources
keep working."
  (let* ((comp-buf (helixel-ne--comp-buf))
         (targets (with-current-buffer comp-buf (helixel-ne--targets)))
         (n (length targets)))
    (if (zerop n)
        (if (eq dir 'forward) (next-error 1) (previous-error 1))
      (let ((next (helixel-ne--step-index
                   targets
                   (buffer-local-value 'helixel-ne--target-idx comp-buf)
                   dir)))
        (unless next
          (user-error (if (eq dir 'forward)
                          "Moved past last next-error match"
                        "Moved before first next-error match")))
        (with-current-buffer comp-buf
          (setq helixel-ne--target-idx next))
        (helixel-ne--visit-target (aref targets next) comp-buf dir)
        t))))

(defun helixel-ne--step-in-file (dir)
  "Navigate one step in DIR, visiting only targets in the current file.
DIR is `forward' or `backward'.
Returns non-nil and moves point/mark when a target in this file
is found; returns nil when no further target exists in this file.

Used by multi-cursor commands that must stay in one buffer.
Updates `helixel-ne--target-idx' so a later `helixel-ne--step'
continues from the visited target."
  (let* ((comp-buf (helixel-ne--comp-buf))
         (targets (with-current-buffer comp-buf (helixel-ne--targets)))
         (my-file (buffer-file-name)))
    (when (and my-file (> (length targets) 0))
      (when-let* ((idx (helixel-ne--step-index
                        targets
                        (buffer-local-value 'helixel-ne--target-idx
                                            comp-buf)
                        dir
                        (file-truename my-file))))
        (with-current-buffer comp-buf
          (setq helixel-ne--target-idx idx))
        (helixel-ne--visit-target (aref targets idx) comp-buf dir)
        t))))

(defun helixel-ne--seed-repeat-state (dir)
  "Seed `next-error' repeat state in the current buffer.
DIR is the step direction.  Sets `helixel--active-search' and
records the motion so n/N/, keep working after a step lands in
a freshly-visited file buffer (both states are buffer-local)."
  (setq helixel--active-search
        (make-helixel--last-motion :category 'next-error :dir dir))
  (helixel-record-motion nil :category 'next-error :dir dir))

(defun helixel-ne--visit-target (tgt comp-buf dir)
  "Display TGT's file and select its match region.
TGT is a `helixel-ne--target'.  COMP-BUF is the compilation
buffer owning the snapshot; stored buffer-locally as
`next-error-last-buffer' in the target buffer so both raw
\=`next-error' and `helixel-ne--step' keep working from there.
DIR is the step direction, seeded into the target buffer's
repeat state via `helixel-ne--seed-repeat-state'."
  (let ((buf (find-file-noselect (helixel-ne--target-file tgt))))
    (let ((display-buffer-overriding-action
           '((display-buffer-same-window) (inhibit-same-window . nil))))
      (pop-to-buffer buf))
    (set (make-local-variable 'next-error-last-buffer) comp-buf)
    (helixel-ne--seed-repeat-state dir)
    (helixel-ne--select-target tgt)))

(defun helixel-ne--target-bounds (tgt)
  "Return TGT's match region in the current buffer as (BEG . END).
The current buffer must be visiting TGT's file.  When TGT has
COL-END, the region is the precise column range; otherwise it
spans the whole line."
  (save-excursion
    (goto-char (point-min))
    (forward-line (1- (helixel-ne--target-line tgt)))
    (let ((bol (line-beginning-position))
          (col-beg (helixel-ne--target-col-beg tgt))
          (col-end (helixel-ne--target-col-end tgt)))
      (cons (+ bol col-beg)
            (if col-end (+ bol col-end) (line-end-position))))))

(defun helixel-ne--select-target (tgt)
  "Select TGT's match region in the current buffer.
The current buffer must be visiting TGT's file.
When TGT has COL-END, selects the precise column range;
otherwise selects the whole line."
  (deactivate-mark)
  (let ((bounds (helixel-ne--target-bounds tgt)))
    (goto-char (car bounds))
    (push-mark (cdr bounds) t t)
    (activate-mark)))

;; ── Internal: snapshot builder ──

(defun helixel-ne--collect-targets ()
  "Walk the current compilation/grep buffer and collect all targets.
Returns a vector of `helixel-ne--target' in compilation-buffer order,
or nil when the buffer lacks `next-error-function'."
  (and next-error-function
       (derived-mode-p 'compilation-mode)
       (let* ((is-grep (derived-mode-p 'grep-mode))
              (match-face (and is-grep
                               (ignore-errors grep-match-face)))
              (raw-targets nil)
              (targets nil))
         (save-excursion
           (goto-char (point-min))
           ;; Ensure the buffer is fully parsed before walking.
           (condition-case nil
               (compilation--ensure-parse (point-max))
             (error nil))
           ;; Collect the first entry at point-min.
           (let ((new-targets (helixel-ne--collect-entry
                               is-grep match-face)))
             (when new-targets
               (setq raw-targets (nconc raw-targets new-targets))))
           ;; Walk remaining entries.
           (catch 'done
             (while t
               (condition-case nil
                   (compilation-next-error 1)
                 (user-error (throw 'done nil)))
               (let ((new-targets (helixel-ne--collect-entry
                                   is-grep match-face)))
                 (when new-targets
                   (setq raw-targets
                         (nconc raw-targets new-targets)))))))
         (setq targets (vconcat raw-targets))
         ;; Normalize each target's file truename once here, so
         ;; later per-file navigation compares plain strings.
         (let ((truenames (make-hash-table :test #'equal)))
           (dotimes (i (length targets))
             (when-let* ((f (helixel-ne--target-file (aref targets i))))
               (setf (helixel-ne--target-file-true (aref targets i))
                     (or (gethash f truenames)
                         (setf (gethash f truenames)
                               (file-truename f)))))))
         targets)))

(defsubst helixel-ne--entry-col-end (end-loc line first-col)
  "Return the 0-based exclusive end column from END-LOC, or nil.
END-LOC is the compilation message's end loc; LINE is the
target's 1-indexed line; FIRST-COL is `compilation-first-column'
in the compilation buffer.  Upstream stores END-COL as an
exclusive upper bound in the same 1-based basis as the loc
column (see `compilation-error-properties'); -1 means end of
line.  Returns nil when the range spans multiple lines or ends
at end of line."
  (when-let* ((end-col (and end-loc (compilation--loc->col end-loc)))
              ((> end-col 0))
              ((= (compilation--loc->line end-loc) line)))
    (max 0 (- end-col first-col))))

(defun helixel-ne--collect-entry (is-grep match-face)
  "Collect targets from the compilation entry at point.
IS-GREP non-nil when in \=`grep-mode'.  MATCH-FACE is the face symbol
for grep match highlights.
Message columns are 1-based per `compilation-first-column'
\(grep buffers rebind it to 0); they are normalized here to
the target struct's 0-based convention, with the end column
taken from the message's END-LOC when it describes a same-line
range.
Returns a list of `helixel-ne--target' values (may be empty)."
  (let* ((msg (get-text-property (point) 'compilation-message))
         (loc (and msg (compilation--message->loc msg)))
         (entry-pos (point)))
    (when loc
      (let* ((fs (compilation--loc->file-struct loc))
             ;; file-spec is the (FILENAME DIRECTORY) list (or just
             ;; FILENAME); DIRECTORY may be nil.
             (file-spec (compilation--file-struct->file-spec fs))
             (filename (if (consp file-spec) (car file-spec) file-spec))
             (directory (when (consp file-spec) (cadr file-spec)))
             (abs-file (cond
                        ((bufferp filename)
                         (or (buffer-file-name filename)
                             (buffer-name filename)))
                        ((stringp filename)
                         (expand-file-name
                          filename (or directory default-directory)))
                        (t nil)))
             (line (compilation--loc->line loc))
             (col (compilation--loc->col loc))
             (first-col compilation-first-column)
             (col-beg (if col (max 0 (- col first-col)) 0))
             (col-end (helixel-ne--entry-col-end
                       (compilation--message->end-loc msg)
                       line first-col)))
        (when (and abs-file line)
          (if (and is-grep match-face)
              ;; grep: try face-run extraction first, fall back to
              ;; single-target when no font-lock-face runs exist
              ;; (e.g. before grep-filter runs, or --no-color).
              (or (helixel-ne--collect-grep-runs
                   abs-file line entry-pos match-face col-beg filename)
                  (list (helixel-ne--target--create
                         :file abs-file :line line
                         :col-beg col-beg :col-end col-end
                         :entry-pos entry-pos)))
            (list (helixel-ne--target--create
                   :file abs-file :line line
                   :col-beg col-beg :col-end col-end
                   :entry-pos entry-pos))))))))

;; ── Face-run extraction for grep ──

(defun helixel-ne--collect-grep-runs (file line entry-pos match-face
                                           &optional col filename)
  "Extract MATCH-FACE runs on the grep entry line at point.
FILE is the absolute filename.  LINE is the 1-indexed line number.
ENTRY-POS is the buffer position of the grep entry in the
compilation buffer.  MATCH-FACE is the face symbol to look for.
COL is the entry's column from the compilation message (0-indexed,
for grep --column output), or nil.  FILENAME is the filename as
printed in the entry line (used to locate the content start).

Face-run columns are buffer-column offsets within the grep entry
line, which includes the printed FILENAME:LINE: (or
FILENAME:LINE:COL:) prefix.  They must be converted to source-line
columns:
- when COL is non-nil, the first run corresponds to COL, so
  source_col(run_i) = COL + (run_i.beg - run_0.beg);
- otherwise the printed prefix length is scanned from the entry
  line and subtracted from each run.
Returns a list of `helixel-ne--target' values in left-to-right
order, or nil when no runs are found or the prefix cannot be
determined."
  (let ((line-end (line-end-position))
        (line-beg (line-beginning-position))
        runs)
    (save-excursion
      (goto-char line-beg)
      (while (< (point) line-end)
        (let ((face (get-text-property (point) 'font-lock-face)))
          (if (eq face match-face)
              (let* ((beg (point))
                     (end (or (next-single-property-change
                               (point) 'font-lock-face nil line-end)
                              line-end)))
                (push (cons (- beg line-beg)
                            (- end line-beg))
                      runs)
                (goto-char end))
            (forward-char 1)))))
    (setq runs (nreverse runs))   ; left-to-right
    (when runs
      (let ((base (cond
                   ;; Anchor on the message column: the first run
                   ;; IS the match at column COL.
                   (col (- (caar runs) col))
                   ;; Scan the printed FILENAME:LINE: prefix.
                   ((and (stringp filename))
                    (helixel-ne--grep-prefix-length
                     filename line line-beg line-end))
                   (t nil))))
        (when (and base (>= base 0))
          (let ((result nil))
            (dolist (run runs)
              (push (helixel-ne--target--create
                     :file file :line line
                     :col-beg (- (car run) base)
                     :col-end (- (cdr run) base)
                     :entry-pos entry-pos)
                    result))
            (nreverse result)))))))

(defun helixel-ne--grep-prefix-length (filename line line-beg line-end)
  "Return the length of the printed FILENAME:LINE: prefix.
Scans the grep entry line between LINE-BEG and LINE-END for the
printed FILENAME followed by :LINE:.  Returns the column offset
where match content begins, or nil when not found."
  (save-excursion
    (goto-char line-beg)
    (when (and (search-forward filename line-end t)
               (looking-at ":")
               (progn
                 (forward-char 1)
                 (looking-at (concat (number-to-string line) ":"))))
      (goto-char (match-end 0))
      (- (point) line-beg))))

;; ── Kind registration ──

(defun helixel-ne--recreate-next-error (ctx)
  "Recreate a \=`next-error' selection from CTX at point.
Navigates one step via the snapshot."
  (helixel-ne--step (or (helixel-sel-field ctx :dir) 'forward)))

(defun helixel-ne--advance-next-error (_tx)
  "Advance to the next \=`next-error' match via the snapshot."
  (helixel-ne--step (or (helixel-search--current-dir) 'forward)))

(helixel-register-kind next-error
  :ctx-schema '(:required (:dir))
  :recreate #'helixel-ne--recreate-next-error
  :advance  #'helixel-ne--advance-next-error
  :flip-dir-fn (lambda (sel)
                 (helixel-sel-update-ctx
                  sel :dir
                  (let ((d (helixel-sel-field sel :dir)))
                    (if (eq d 'forward) 'backward 'forward))))
  :display  (lambda (_ctx) "next-error")
  :skip-reverse-exchange t)

(helixel-register-motion-repeater 'next-error nil
                                  #'helixel-ne--repeat-next-error-motion)

(defun helixel-ne--repeat-next-error-motion (rec)
  "Replay a \=`next-error' motion from REC for \[helixel-repeat-last-motion].
Reads :dir from REC to determine forward/backward direction."
  (helixel-ne--step (helixel--last-motion-dir rec)))

;; ── `next-error-hook' integration ──

(defun helixel-ne--after-jump ()
  "Set up helixel `next-error' repeat state after a jump.
Called from `next-error-hook' in the target buffer.
Sets `helixel--active-search' so n/N/, navigate the target
snapshot built from the compilation buffer.

Works for any buffer with `next-error-function' — compilation,
grep, diff, xref, etc.  Excludes occur buffers (which use the
`search' category via their own integration)."
  (when (and (buffer-live-p next-error-last-buffer)
             (buffer-local-value 'next-error-function
                                 next-error-last-buffer)
             (not (with-current-buffer next-error-last-buffer
                    (derived-mode-p 'occur-mode))))
    (let* ((comp-buf next-error-last-buffer)
           (targets (with-current-buffer comp-buf
                      (helixel-ne--targets))))
      ;; Sync the navigation index from `compilation-current-error'
      ;; so the first n continues right after the entry just visited.
      (with-current-buffer comp-buf
        (when (and (boundp 'compilation-current-error)
                   (markerp compilation-current-error)
                   (marker-position compilation-current-error))
          (setq helixel-ne--target-idx
                (helixel-ne--index-of-entry
                 targets
                 (marker-position compilation-current-error)))))
      ;; Select the match of the entry just visited, so the region
      ;; is active for s n / s p / operators right after the jump.
      (let ((idx (buffer-local-value 'helixel-ne--target-idx
                                     comp-buf)))
        (when (and idx (< idx (length targets)))
          (helixel-ne--select-target (aref targets idx)))))
    ;; Fresh state: after any compile-driven jump, n moves forward.
    (helixel-ne--seed-repeat-state 'forward)
    ;; Push sel so s s can spawn without needing n/N first.
    (helixel--push-selection
     'next-error `(:dir ,(helixel-search--current-dir)))))

(provide 'helixel-next-error)
;;; helixel-next-error.el ends here
