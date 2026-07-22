;;; helixel-mc-spawn.el --- High-level multi-cursor commands -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

;; Author: jixiuf <https://github.com/jixiuf>
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Keywords: convenience

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;;; Commentary:

;; High-level multi-cursor user commands.
;;
;; Target computation (spawn-from-* + advance walk + kind registry
;; hooks) lives in `helixel-mc-core' (see "Target computation"
;; section).  This file builds the
;; interactive layer on top:
;;
;;   helixel-mc-toggle                — spawn from sel / clear
;;   helixel-mc-add-cursor-here / -up
;;   helixel-mc-edit-lines
;;   helixel-mc-mark-next-like-this / -previous-like-this
;;   helixel-mc-skip-next / -skip-previous
;;   helixel-mc-unmark-next / -unmark-previous
;;   helixel-mc-remove-primary / -keep-primary
;;   helixel-mc-rotate-primary-forward / -backward
;;   helixel-mc-rotate-content-forward / -backward
;;   helixel-mc-keep-matching / -remove-matching
;;   helixel-mc-merge / -trim / -align
;;   helixel-mc-split-selection
;;   helixel-mc-restore-cursors       — g v history
;;
;; this file (user-facing commands).

;;; Code:

(require 'cl-lib)
(require 'helixel-core)
(require 'helixel-mc-core)
(require 'helixel-search)

;; ── Forward declarations for treesit integration ──
(declare-function helixel-ts--next-after "helixel-treesit-core" t t)
(declare-function helixel-ts--prev-before "helixel-treesit-core" t t)

(declare-function helixel-ne--step-in-file "helixel-next-error" (dir))
(declare-function helixel-search--safe-category "helixel-search" ())

;; Special vars from helixel-repeat — must be `defvar' so the `let'
;; bindings below are treated as dynamic, not lexical.
(defvar helixel--pending-sel)
(defvar helixel-last-action)
(defvar helixel--live-action)

;; ── High-level entry points ──

(defun helixel-mc-toggle ()
  "Toggle multi-cursor: spawn from last selection, or clear if any.

If fake cursors exist → clear them.
Otherwise spawn from:
  1. `helixel--pending-sel' (most recent selection) if non-nil
  2. `helixel-last-action' sel (last edit's selection)
  3. signal `user-error' if neither has a usable selection."
  (interactive)
  (cond
   ((helixel-mc-any-p) (helixel-mc-clear-all))
   (t
    (let ((sel (or (and (boundp 'helixel--pending-sel)
                        helixel--pending-sel)
                   (and (boundp 'helixel-last-action)
                        helixel-last-action
                        (helixel-action-sel helixel-last-action)))))
      (unless sel
        (user-error "No selection to spawn cursors from"))
      (let ((n (helixel-mc--spawn-from-sel sel)))
        (message "helixel-mc: %d fake cursor%s spawned"
                 n (if (= n 1) "" "s")))))))

;; ── Incremental cursor manipulation ──

(defun helixel-mc--copy-cursor-to-direction (direction)
  "Snapshot real cursor to a fake, then move real to next line.
DIRECTION is +1 (down) or -1 (up).

Mirrors Helix C / Alt-C:
  - if a region is active, the region is copied to the next line
    keeping the same column span (point/mark direction preserved);
  - otherwise the point is copied to the next line, same column.

Lines too short to host the column / region span are skipped.
No-op (returns nil) if no suitable target line exists."
  (let* ((had-region (use-region-p))
         (pt-col (current-column))
         (mk (mark t))
         (mk-col (and had-region
                      (save-excursion (goto-char mk) (current-column))))
         (target-pt nil)
         (target-mk nil))
    (save-excursion
      (cl-loop while (zerop (forward-line direction))
               when (and (= (move-to-column pt-col) pt-col)
                         (not (and had-region
                                   (save-excursion
                                     (beginning-of-line)
                                     (end-of-line)
                                     (< (current-column)
                                        (max pt-col mk-col))))))
               return (setq target-pt (point))))
    (when target-pt
      (when had-region
        (save-excursion
          (goto-char target-pt)
          (forward-line 0)
          (move-to-column mk-col)
          (setq target-mk (point))))
      ;; Snapshot the current real position as a fake (unless a fake
      ;; already exists exactly there).
      (unless (cl-find-if
               (lambda (ov)
                 (= (point) (marker-position
                             (helixel-mc-cursor-point ov))))
               (helixel-mc-all-cursors))
        (helixel-mc--create-fake-cursor
         (point) (and had-region mk)))
      ;; Move real to the new target.
      (when had-region (deactivate-mark))
      (goto-char target-pt)
      (when (and had-region target-mk)
        (set-mark target-mk)
        (activate-mark))
      t)))

(defun helixel-mc-add-cursor-here ()
  "Copy current selection / cursor to the line below (Helix C).

Snapshot the real cursor (with its region, if any) as a fake at
the current position, then move the real cursor to the next line
at the same column.  Repeated invocations stack cursors down the
buffer — the typical Helix multi-cursor entry point.

If the target line is too short to host the column / region
span, skip ahead to the first line that fits.  Signals
`user-error' when no such line exists."
  (interactive)
  ;; Record motion BEFORE spawning fake so the inherited
  ;; helixel--last-motion-cmd is mc-spawn, not stale.
  (helixel-record-motion 'helixel-mc-add-cursor-here
                         :category 'mc-spawn :subcat 'add :dir 'forward)
  (unless (helixel-mc--copy-cursor-to-direction 1)
    (user-error "No line below fits this column/selection"))
  (let ((n (helixel-mc-num-cursors)))
    (message "Added cursor (line %d, %d cursor%s)"
             (line-number-at-pos) n (if (> n 1) "s" ""))))

(defun helixel-mc-add-cursor-here-up ()
  "Copy current selection / cursor to the line above (Helix `Alt-C').

Like `helixel-mc-add-cursor-here' but moves the real cursor up
instead of down."
  (interactive)
  (helixel-record-motion 'helixel-mc-add-cursor-here-up
                         :category 'mc-spawn :subcat 'add :dir 'backward)
  (unless (helixel-mc--copy-cursor-to-direction -1)
    (user-error "No line above fits this column/selection"))
  (let ((n (helixel-mc-num-cursors)))
    (message "Added cursor (line %d, %d cursor%s)"
             (line-number-at-pos) n (if (> n 1) "s" ""))))

;;;###autoload
(defun helixel-mc-edit-lines (&optional beg end)
  "Create one cursor per line of the region BEG..END.
With no region, signals `user-error'.

Behavior depends on `helixel--sel-type':

- Line-wise selection (`x'): each cursor gets a full-line REGION
  spanning BOL..EOL of its line.  Apply edits to whole lines (`d',
  `c', `~', etc.) and have them affect each line independently.
  This is the Helix `Alt-s' (split-into-lines) semantics.

- Character-wise selection: each cursor sits at `current-column'
  on its line as a single POINT (no region).  This is mc.el-style
  column editing — useful for inserting / aligning at the same
  visual column.  Lines shorter than that column are skipped.

The line nearest to point keeps the real cursor; every other
line becomes a fake cursor."
  (interactive (when (use-region-p)
                 (list (region-beginning) (region-end))))
  (unless (and beg end) (user-error "Region required"))
  (let* ((line-mode (eq (helixel--sel-type) 'line))
         (col (and (not line-mode)
                   (save-excursion (goto-char (point)) (current-column))))
         (sl (line-number-at-pos beg))
         (el (line-number-at-pos end))
         ;; If the region ends exactly at BOL of a line, that line
         ;; isn't really part of the selection (line-mode `x' may
         ;; behave that way after the last full line).
         (el (if (and (> el sl)
                      (save-excursion
                        (goto-char end) (bolp)))
                 (1- el)
               el))
         (targets nil))
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- sl))
      (dotimes (_ (1+ (- el sl)))
        (unless (eobp)
          (save-excursion
            (cond
             (line-mode
              ;; Full-line region: point=EOL, mark=BOL (forward).
              (let ((b (line-beginning-position))
                    (e (line-end-position)))
                (push (helixel-mc--make-target e b) targets)))
             (t
              (move-to-column col)
              (when (and (= (current-column) col)
                         (not (eolp)))
                (push (helixel-mc--make-target (point)) targets)))))
          (forward-line 1))))
    (deactivate-mark)
    (helixel-mc--realize-targets (nreverse targets))))

;; ── Mark next / previous like this ──

(defun helixel-mc--region-text ()
  "Return the active region text, or signal `user-error'."
  (unless (use-region-p)
    (user-error "Need an active region (e.g. `miw') to mark like this"))
  (buffer-substring-no-properties (region-beginning) (region-end)))

(defun helixel-mc--search-for-next (text dir)
  "Search for TEXT in direction DIR (1 forward, -1 backward).
Returns (BEG . END) marker pair on success, nil on failure.
Does not move point.

Filters invisible matches via `isearch-filter-predicate' when
`helixel-invisible' is nil (e.g. `grep-mode' with consult-focus-line)."
  (save-excursion
    (let ((case-fold-search case-fold-search)
          (search-invisible (helixel--invisible-effective))
          (search-fn (if (> dir 0) #'search-forward #'search-backward)))
      (catch 'found
        (while t
          ;; search-forward with noerror=t returns nil on failure.
          (if (funcall search-fn text nil t)
              (if (or (helixel--invisible-effective)
                      (funcall isearch-filter-predicate
                               (match-beginning 0) (match-end 0)))
                  (throw 'found
                         (helixel-mc--make-target
                          (match-beginning 0) (match-end 0)))
                ;; Invisible — skip empty match and retry.
                (when (= (match-beginning 0) (match-end 0))
                  (if (> dir 0)
                      (if (eobp) (throw 'found nil) (forward-char 1))
                    (if (bobp) (throw 'found nil)
                      (forward-char -1)))))
            ;; No match at all.
            (throw 'found nil)))))))

;; ── Treesit-aware mark-like-this helpers ──

(defun helixel-mc--treesit-selection-p ()
  "Return non-nil when the active selection is a treesit object."
  (and (boundp 'helixel--pending-sel)
       helixel--pending-sel
       (eq (helixel-sel-kind helixel--pending-sel) 'treesit)))

(defun helixel-mc--treesit-capture-has-fake-p (beg end)
  "Return non-nil if any fake cursor's point lies in [BEG, END]."
  (cl-find-if
   (lambda (ov)
     (let ((fp (marker-position (helixel-mc-cursor-point ov))))
       (and fp (>= fp beg) (<= fp end))))
   (helixel-mc-all-cursors)))

(defun helixel-mc--treesit-next-unmarked (base part start forward-p)
  "Find next unmarked treesit capture of (BASE . PART) from START.
FORWARD-P non-nil searches forward, nil backward.
Skips captures whose range already contains a fake cursor.
Returns (BEG . END) cons, or nil if none found."
  (let ((search-fn (if forward-p
                       #'helixel-ts--next-after
                     #'helixel-ts--prev-before))
        (result nil)
        (pos start))
    (while (and (not result) pos)
      (let ((capture (funcall search-fn base part pos)))
        (if (null capture)
            (setq pos nil)
          (let ((cb (car capture))
                (ce (cdr capture)))
            (if (helixel-mc--treesit-capture-has-fake-p cb ce)
                ;; Collision — skip past this capture and retry.
                (setq pos (if forward-p
                              (max ce (1+ pos))
                            (min cb (1- pos))))
              (setq result capture))))))
    result))

(defun helixel-mc--mark-like-this-treesit (dir)
  "Treesit-aware variant: move to next/prev semantic object.
DIR is 1 (forward) or -1 (backward).  Snapshots the current real
cursor as a fake, then advances real to the next object of the
same (BASE . PART) type."
  (let* ((sel (or (and (boundp 'helixel--pending-sel)
                       helixel--pending-sel)
                  (and (boundp 'helixel-last-action)
                       helixel-last-action
                       (helixel-action-sel helixel-last-action))))
         (base (helixel-sel-field sel :base))
         (part (helixel-sel-field sel :part))
         (forward-p (> dir 0))
         ;; Farthest edge among ALL cursors (same as text-search path).
         (farthest
          (let ((fwd (max (point) (or (mark t) (point))))
                (bwd (min (point) (or (mark t) (point)))))
            (dolist (ov (helixel-mc-all-cursors))
              (let* ((p (marker-position (helixel-mc-cursor-point ov)))
                     (m (marker-position (helixel-mc-cursor-mark ov)))
                     (hi (max p m))
                     (lo (min p m)))
                (setq fwd (max fwd hi))
                (setq bwd (min bwd lo))))
            (if forward-p fwd bwd)))
         (start (if forward-p
                    (max farthest (region-end))
                  (min farthest (region-beginning))))
         (target (helixel-mc--treesit-next-unmarked
                  base part start forward-p))
         (old-point (point))
         (old-mark (and (use-region-p) (mark t)))
         (had-region (use-region-p)))
    (unless target
      (user-error "No more %s(%s) objects" base part))
    ;; Create fake at old position if not already there.
    (unless (cl-find-if
             (lambda (ov)
               (= old-point (marker-position
                             (helixel-mc-cursor-point ov))))
             (helixel-mc-all-cursors))
      (helixel-mc--create-fake-cursor old-point
                                      (and had-region old-mark)))
    ;; Move real to the new target and recreate the selection.
    ;; Jumping to the capture start lets `helixel-ts--recreate'
    ;; find the correct innermost object for :part inside/around.
    (goto-char (car target))
    (helixel--recreate-selection sel)))

;; ── next-error dispatch helpers ──

(defun helixel-mc--next-error-context-p ()
  "Return non-nil when currently in a \=`next-error' repeat context.
True when `helixel--active-search' category is \=`next-error'."
  (eq (helixel-search--safe-category) 'next-error))

(defun helixel-mc--mark-like-this-next-error (dir)
  "Next-error variant: move to next match, leave fake at old position.
DIR is 1 (forward) or -1 (backward)."
  (let* ((dir-sym (if (> dir 0) 'forward 'backward))
         (old-point (point))
         (old-mark (and (use-region-p) (mark t)))
         (had-region (use-region-p))
         (found (helixel-ne--step-in-file dir-sym)))
    (unless found
      (user-error "No more next-error matches in current buffer"))
    ;; Create fake at old position if not already there.
    (unless (cl-find-if
             (lambda (ov)
               (= old-point (marker-position
                             (helixel-mc-cursor-point ov))))
             (helixel-mc-all-cursors))
      (helixel-mc--create-fake-cursor old-point
                                      (and had-region old-mark)))
    (message "Marked next-error at line %d (%d cursor%s)"
             (line-number-at-pos)
             (helixel-mc-num-cursors)
             (if (> (helixel-mc-num-cursors) 1) "s" ""))))

(defun helixel-mc--skip-in-dir-next-error (dir)
  "Next-error variant: jump to next match without adding a cursor.
DIR is 1 (forward) or -1 (backward)."
  (let ((dir-sym (if (> dir 0) 'forward 'backward)))
    (unless (helixel-ne--step-in-file dir-sym)
      (user-error "No more next-error matches in current buffer"))
    (message "Skipped to line %d" (line-number-at-pos))))

(defun helixel-mc--mark-like-this (dir)
  "Move real cursor to the next occurrence, leaving a fake at its old position.
DIR is 1 (forward) or -1 (backward).

Finds the next occurrence of the region text, snapshots the current
real cursor position as a fake, then moves real to the new match —
so the view always scrolls to show what was just marked.

Repeated calls chain: real always sits at the latest match (visible),
fakes accumulate at all previously visited positions.  The search
anchor is the farthest edge among ALL cursors (real + fakes) to
guarantee no two cursors share a position.

Dispatch:
  - treesit selection → `helixel-mc--mark-like-this-treesit'
  - `next-error' context → `helixel-mc--mark-like-this-next-error'
  - default → literal text search"
  (cond
   ((helixel-mc--treesit-selection-p)
    (helixel-mc--mark-like-this-treesit dir))
   ((helixel-mc--next-error-context-p)
    (helixel-mc--mark-like-this-next-error dir))
   (t
    (let* ((text (helixel-mc--region-text))
           ;; Collect farthest edge among ALL cursors (real + fakes).
           (farthest
            (let ((fwd (max (point) (or (mark t) (point))))
                  (bwd (min (point) (or (mark t) (point)))))
              (dolist (ov (helixel-mc-all-cursors))
                (let* ((p (marker-position (helixel-mc-cursor-point ov)))
                       (m (marker-position (helixel-mc-cursor-mark ov)))
                       (hi (max p m))
                       (lo (min p m)))
                  (setq fwd (max fwd hi))
                  (setq bwd (min bwd lo))))
              (if (> dir 0) fwd bwd)))
           (start (if (> dir 0)
                      (max farthest (region-end))
                    (min farthest (region-beginning))))
           (target (save-excursion
                     (goto-char start)
                     (helixel-mc--search-for-next text dir)))
           ;; Snapshot current real position before moving.
           (old-point (point))
           (old-mark (and (use-region-p) (mark t)))
           (had-region (use-region-p)))
      (unless target
        (user-error "No more matches for `%s'" text))
      ;; Create a fake cursor at the old real position — unless a fake
      ;; already sits exactly there.
      (unless (cl-find-if
               (lambda (ov)
                 (= old-point (marker-position
                               (helixel-mc-cursor-point ov))))
               (helixel-mc-all-cursors))
        (helixel-mc--create-fake-cursor old-point
                                        (and had-region old-mark)))
      ;; Move real to the new match (view scrolls with it).
      (let ((tb (marker-position (car target)))
            (te (marker-position (cdr target)))
            (forward-p (if had-region
                           (>= old-point old-mark)
                         t)))
        (deactivate-mark)
        (goto-char (if forward-p te tb))
        (set-mark (if forward-p tb te))
        (activate-mark))
      (helixel-mc--free-targets (list target))
      (let ((n (helixel-mc-num-cursors)))
        (message "Marked \"%s\" at line %d (%d cursor%s)"
                 text (line-number-at-pos) n (if (> n 1) "s" "")))))))

;;;###autoload
(defun helixel-mc-mark-next-like-this ()
  "Add a fake cursor at the next occurrence of the region text."
  (interactive)
  ;; Record motion BEFORE mark-like-this so the fake cursor (created
  ;; by mark-like-this via state-clone) inherits the mc-spawn motion
  ;; rather than a stale search/movement motion.
  (helixel-record-motion 'helixel-mc-mark-next-like-this
                         :category 'mc-spawn :subcat 'mark :dir 'forward)
  (helixel-mc--mark-like-this 1))

;;;###autoload
(defun helixel-mc-mark-previous-like-this ()
  "Add a fake cursor at the previous occurrence of the region text."
  (interactive)
  (helixel-record-motion 'helixel-mc-mark-previous-like-this
                         :category 'mc-spawn :subcat 'mark :dir 'backward)
  (helixel-mc--mark-like-this -1))

;; Internal helper — not autoloaded (private "--" name).
(defun helixel-mc--skip-in-dir-treesit (dir)
  "Treesit-aware skip: advance to next/prev object without adding cursor.
DIR is 1 (forward) or -1 (backward)."
  (let* ((sel (or (and (boundp 'helixel--pending-sel)
                       helixel--pending-sel)
                  (and (boundp 'helixel-last-action)
                       helixel-last-action
                       (helixel-action-sel helixel-last-action))))
         (base (helixel-sel-field sel :base))
         (part (helixel-sel-field sel :part))
         (forward-p (> dir 0))
         (start (if forward-p (region-end) (region-beginning)))
         (target (helixel-mc--treesit-next-unmarked
                  base part start forward-p))
         ;; Preserve original point/mark direction.
         (orig-forward-p (if (use-region-p)
                             (>= (point) (mark t))
                           t)))
    (unless target
      (user-error "No more %s(%s) objects" base part))
    (let ((cb (car target))
          (ce (cdr target)))
      (if orig-forward-p
          (progn (goto-char ce) (set-mark cb))
        (goto-char cb) (set-mark ce))
      (activate-mark))
    (message "Skipped to line %d" (line-number-at-pos))))

(defun helixel-mc--skip-in-dir (dir)
  "Skip occurrence in DIR (+1 / -1) without adding a cursor.
Skips past positions that already have a fake cursor, so the real
cursor never lands on an existing fake.  Preserves the original
point/mark direction (forward-p).

Dispatch:
  - treesit selection → `helixel-mc--skip-in-dir-treesit'
  - `next-error' context → `helixel-mc--skip-in-dir-next-error'
  - default → literal text search"
  (cond
   ((helixel-mc--treesit-selection-p)
    (helixel-mc--skip-in-dir-treesit dir))
   ((helixel-mc--next-error-context-p)
    (helixel-mc--skip-in-dir-next-error dir))
   (t
    (let* ((text (helixel-mc--region-text))
           (start (if (> dir 0) (region-end) (region-beginning)))
           (target nil)
           (search-start start)
           ;; Capture original direction before moving.
           (forward-p (if (use-region-p)
                          (>= (point) (mark t))
                        t)))
      (while (not target)
        (let ((candidate (save-excursion
                           (goto-char search-start)
                           (helixel-mc--search-for-next text dir))))
          (unless candidate (user-error "No more matches"))
          (let ((cand-beg (marker-position (car candidate)))
                (cand-end (marker-position (cdr candidate))))
            ;; Check if any existing fake already covers this position.
            (if (cl-find-if
                 (lambda (ov)
                   (let ((fp (marker-position (helixel-mc-cursor-point ov)))
                         (fm (marker-position (helixel-mc-cursor-mark ov))))
                     (and (>= cand-beg (min fp fm))
                          (<= cand-end (max fp fm)))))
                 (helixel-mc-all-cursors))
                ;; Collision — advance search-start past this match and retry.
                (progn
                  (helixel-mc--free-targets (list candidate))
                  (setq search-start
                        (if (> dir 0) (max cand-end (1+ search-start))
                          (min cand-beg (1- search-start)))))
              ;; No collision — accept this target.
              (setq target candidate)))))
      ;; Preserve original direction: if point was after mark (forward),
      ;; set point at target-end and mark at target-begin.
      (let ((tb (marker-position (car target)))
            (te (marker-position (cdr target))))
        (if forward-p
            (progn (goto-char te) (set-mark tb))
          (goto-char tb) (set-mark te))
        (activate-mark))
      (helixel-mc--free-targets (list target))
      (message "Skipped to line %d" (line-number-at-pos))))))

;;;###autoload
(defun helixel-mc-skip-next ()
  "Skip the next occurrence of the region text without adding a cursor."
  (interactive)
  (helixel-mc--skip-in-dir 1)
  (helixel-record-motion 'helixel-mc-skip-next
                         :category 'mc-spawn :subcat 'skip :dir 'forward))

;;;###autoload
(defun helixel-mc-skip-previous ()
  "Skip the previous occurrence of the region text without adding a cursor."
  (interactive)
  (helixel-mc--skip-in-dir -1)
  (helixel-record-motion 'helixel-mc-skip-previous
                         :category 'mc-spawn :subcat 'skip :dir 'backward))

;;;###autoload
(defun helixel-mc-remove-primary ()
  "Remove the primary cursor and promote the nearest neighbor.
This matches Helix `A-,' semantics.

Swaps real with the nearest fake (next-by-distance cursor),
then deletes the fake that now sits at real's former position.
The net effect: the cursor at real's position is deleted, and
real moves to the nearest remaining cursor — exactly how Helix
removes the primary selection and promotes the next.

After `)` / `(` rotation this deletes the position the user
navigated to, then real moves back to the nearest neighbor
\(typically the cursor they just rotated from)."
  (interactive)
  (unless (helixel-mc-any-p)
    (user-error "No fake cursors"))
  (let* ((sorted (helixel-mc-all-cursors :sort))
         (real-pos (point))
         (nearest nil)
         (nearest-dist most-positive-fixnum))
    ;; Find the nearest fake — this will become the new primary
    ;; after the current one is deleted.
    (dolist (ov sorted)
      (let* ((fp (marker-position (helixel-mc-cursor-point ov)))
             (dist (abs (- fp real-pos))))
        (when (< dist nearest-dist)
          (setq nearest ov
                nearest-dist dist))))
    (unless nearest
      (user-error "No fake cursor to remove"))
    ;; Step 1: swap real with nearest fake.
    ;;   real moves to the neighbor's position (new primary).
    ;;   The old real position (the one to delete) becomes a fake.
    (helixel-mc--swap-real-and-fake nearest)
    ;; Step 2: delete the fake at the position real just vacated
    ;;   (the former primary position).
    (helixel-mc--delete-fake-cursor nearest)))

;;;###autoload
(defun helixel-mc-keep-primary ()
  "Remove all fake cursors except the real cursor.
\(Helix \\[helixel-mc-clear-all] equivalent).
Keeps only the current primary (real cursor) and discards every
other fake cursor."
  (interactive)
  (helixel-mc-clear-all))

;;;###autoload
(defun helixel-mc-unmark-next ()
  "Remove the fake cursor at the next match-position after point.
Move real cursor to the removed fake's position, so the view follows."
  (interactive)
  (let ((cursor
         (cl-find-if
          (lambda (ov)
            (> (marker-position (helixel-mc-cursor-point ov))
               (point)))
          (helixel-mc-all-cursors :sort))))
    (unless cursor (user-error "No fake cursor after point"))
    ;; Move real to the fake's position before deleting it.
    (let ((fp (marker-position (helixel-mc-cursor-point cursor)))
          (fm (marker-position (helixel-mc-cursor-mark cursor)))
          (had-region (marker-position (helixel-mc-cursor-mark cursor))))
      (if (and had-region fm)
          (progn
            (deactivate-mark)
            (goto-char fp)
            (set-mark fm)
            (activate-mark))
        (goto-char fp)))
    (helixel-mc--delete-fake-cursor cursor))
  (let ((n (helixel-mc-num-cursors)))
    (message "Unmarked (%d cursor%s remaining)"
             n (if (> n 1) "s" "")))
  (helixel-record-motion 'helixel-mc-unmark-next
                         :category 'mc-spawn :subcat 'unmark :dir 'forward))

;;;###autoload
(defun helixel-mc-unmark-previous ()
  "Remove the fake cursor at the previous match-position before point.
Move real cursor to the removed fake's position, so the view follows."
  (interactive)
  (let ((cursor
         (cl-find-if
          (lambda (ov)
            (< (marker-position (helixel-mc-cursor-point ov))
               (point)))
          (reverse (helixel-mc-all-cursors :sort)))))
    (unless cursor (user-error "No fake cursor before point"))
    ;; Move real to the fake's position before deleting it.
    (let ((fp (marker-position (helixel-mc-cursor-point cursor)))
          (fm (marker-position (helixel-mc-cursor-mark cursor))))
      (if (and fm (not (= fp fm)))
          (progn
            (deactivate-mark)
            (goto-char fp)
            (set-mark fm)
            (activate-mark))
        (goto-char fp)))
    (helixel-mc--delete-fake-cursor cursor))
  (let ((n (helixel-mc-num-cursors)))
    (message "Unmarked (%d cursor%s remaining)"
             n (if (> n 1) "s" "")))
  (helixel-record-motion 'helixel-mc-unmark-previous
                         :category 'mc-spawn :subcat 'unmark :dir 'backward))

;; ── Motion repeater for mc-spawn commands ──
;;
;; Registered so \\[helixel-repeat-last-motion] (\`,') can replay
;; the last mark/skip/unmark action.  Subcat+dir determine the
;; specific function to call; \\=`-,' flips dir → opposite command.

(helixel-register-motion-repeater 'mc-spawn nil
                                  (lambda (rec)
                                    ;; MC safety: when \, dispatches to fake
                                    ;; cursors, mc-spawn commands must NOT run
                                    ;; at fakes because they modify the global
                                    ;; cursor set during the `with-each-cursor'
                                    ;; iteration, corrupting the cursor list.
                                    ;; The real cursor already ran the command,
                                    ;; so the cursor set is correct.
                                    (unless (helixel-mc--dispatch-in-progress-p)
                                      (let ((subcat (helixel--last-motion-subcat rec))
                                            (dir (helixel--last-motion-dir rec)))
                                        (cl-case subcat
                                          (mark (if (eq dir 'forward)
                                                    (call-interactively
                                                     #'helixel-mc-mark-next-like-this)
                                                  (call-interactively
                                                   #'helixel-mc-mark-previous-like-this)))
                                          (skip (if (eq dir 'forward)
                                                    (call-interactively
                                                     #'helixel-mc-skip-next)
                                                  (call-interactively
                                                   #'helixel-mc-skip-previous)))
                                          (unmark (if (eq dir 'forward)
                                                      (call-interactively
                                                       #'helixel-mc-unmark-next)
                                                    (call-interactively
                                                     #'helixel-mc-unmark-previous)))
                                          (add (if (eq dir 'forward)
                                                   (call-interactively
                                                    #'helixel-mc-add-cursor-here)
                                                 (call-interactively
                                                  #'helixel-mc-add-cursor-here-up))))))))

;; Whitelist: helixel-mc commands themselves run only at real cursor.
(helixel-mc-mark-all-for-real-cursor-only
 '(helixel-mc-toggle
   helixel-mc-add-cursor-here
   helixel-mc-add-cursor-here-up
   helixel-mc-edit-lines
   helixel-mc-mark-next-like-this
   helixel-mc-mark-previous-like-this
   helixel-mc-skip-next
   helixel-mc-skip-previous
   helixel-mc-unmark-next
   helixel-mc-unmark-previous
   helixel-mc-remove-primary
   helixel-mc-keep-primary
   helixel-mc-keep-matching
   helixel-mc-remove-matching
   helixel-mc-rotate-primary-forward
   helixel-mc-rotate-primary-backward
   helixel-mc-rotate-content-forward
   helixel-mc-rotate-content-backward
   helixel-mc-merge
   helixel-mc-align
   helixel-mc-trim
   helixel-mc-split-selection
   helixel-mc-select-regex
   helixel-mc-restore-cursors))

;; ── Helix-style selection management ──
;;
;; These commands mirror Helix's native multi-selection ops and
;; hel-mode's `hel-multiple-cursors-mode-map' bindings.  They are
;; meaningful only when fake cursors exist; outside an mc session
;; they are no-ops (with a `user-error' message).

(defun helixel-mc--cursor-region-text (ov)
  "Return `buffer-substring' of fake cursor OV's selection.
When OV's mark is inactive or degenerate, returns an empty string."
  (let ((p (marker-position (helixel-mc-cursor-point ov)))
        (m (marker-position (helixel-mc-cursor-mark ov)))
        (a (helixel-mc-cursor-mark-active ov)))
    (if (and a (/= p m))
        (buffer-substring-no-properties (min p m) (max p m))
      "")))

(defun helixel-mc--current-real-region-text ()
  "Return `buffer-substring' of the real cursor's region, or \"\"."
  (if (use-region-p)
      (buffer-substring-no-properties (region-beginning) (region-end))
    ""))

(defun helixel-mc--filter-cursors (keep-p regex)
  "Keep or remove cursors whose selection text matches REGEX.
When KEEP-P is non-nil, keep cursors matching REGEX (inverse of
`helixel-mc-remove-matching').  When KEEP-P is nil, remove
cursors matching REGEX (inverse of `helixel-mc-keep-matching').

The real cursor is also tested; if it fails the predicate it is
replaced by the first surviving fake (or all cleared if none
survive).  Errors outside an mc session."
  (unless (helixel-mc-any-p)
    (user-error "No fake cursors"))
  (let* ((real-keep
          (if keep-p
              (string-match-p regex
                              (helixel-mc--current-real-region-text))
            (not (string-match-p
                  regex (helixel-mc--current-real-region-text)))))
         (survivors
          (if keep-p
              (cl-remove-if-not
               (lambda (ov)
                 (string-match-p regex (helixel-mc--cursor-region-text ov)))
               (helixel-mc-all-cursors))
            (cl-remove-if
             (lambda (ov)
               (string-match-p regex (helixel-mc--cursor-region-text ov)))
             (helixel-mc-all-cursors)))))
    (dolist (ov (helixel-mc-all-cursors))
      (unless (memq ov survivors)
        (helixel-mc--delete-fake-cursor ov)))
    (unless real-keep
      (if (null survivors)
          (helixel-mc-clear-all)
        (helixel-mc--promote-fake-to-real (car survivors))))
    (message "helixel-mc: %d cursor%s remain"
             (1+ (length (helixel-mc-all-cursors)))
             (if (= 0 (length (helixel-mc-all-cursors))) "" "s"))))

;;;###autoload
(defun helixel-mc-keep-matching (regex)
  "Keep only cursors whose selection text matches REGEX.
Real cursor is also tested; if it fails to match it is REPLACED
by the first surviving fake (or all cleared if none survive).
No-op outside an mc session.

Delegates to `helixel-mc--filter-cursors' with KEEP-P = t."
  (interactive
   (list (read-regexp "Keep cursors matching: ")))
  (helixel-mc--filter-cursors t regex))

;;;###autoload
(defun helixel-mc-remove-matching (regex)
  "Remove cursors whose selection text matches REGEX.
Inverse of `helixel-mc-keep-matching'.  No-op outside mc.

Delegates to `helixel-mc--filter-cursors' with KEEP-P = nil."
  (interactive
   (list (read-regexp "Remove cursors matching: ")))
  (helixel-mc--filter-cursors nil regex))

(defun helixel-mc--promote-fake-to-real (ov)
  "Move real cursor onto fake OV's state, then delete OV.
If the resulting set has no fakes left, fully disables mc mode."
  (let ((p (marker-position (helixel-mc-cursor-point ov)))
        (m (marker-position (helixel-mc-cursor-mark ov)))
        (a (helixel-mc-cursor-mark-active ov)))
    (helixel-mc--delete-fake-cursor ov)
    (goto-char p)
    (set-marker (mark-marker) m)
    (setq mark-active a)))

(defun helixel-mc--rotate-primary (dir)
  "Rotate the primary cursor one step in direction DIR.
DIR is a comparison operator (`>', `<').
`>' moves forward to the next fake (by buffer position);
`<' moves backward to the previous fake.  Returns non-nil when a
rotation was performed, nil when there are no fakes.

After rotation, the old primary becomes a fake at its position
and the new primary takes over all per-cursor state."
  (unless (helixel-mc-any-p)
    (user-error "No fake cursors"))
  (let* ((sorted (helixel-mc-all-cursors :sort))
         (real (point))
         (candidates (if (eq dir '<) (reverse sorted) sorted))
         (next (or (cl-find-if
                    (lambda (ov)
                      (funcall dir
                               (marker-position
                                (helixel-mc-cursor-point ov))
                               real))
                    candidates)
                   ;; Wrap around: forward → first, backward → last.
                   (if (eq dir '<)
                       (car (last sorted))
                     (car sorted)))))
    (helixel-mc--swap-real-and-fake next)))

;;;###autoload
(defun helixel-mc-rotate-primary-forward (&optional count)
  "Make the NEXT fake cursor (by buffer position) the primary one.
The old primary becomes a fake at its previous position.  Wraps
from last fake back to first.  Prefix COUNT repeats.

Delegates to `helixel-mc--rotate-primary'."
  (interactive "p")
  (dotimes (_ (or count 1))
    (helixel-mc--rotate-primary '>)))

;;;###autoload
(defun helixel-mc-rotate-primary-backward (&optional count)
  "Make the PREVIOUS fake cursor (by buffer position) the primary one.
Wraps from first fake back to last.  Prefix COUNT repeats.

Delegates to `helixel-mc--rotate-primary'."
  (interactive "p")
  (dotimes (_ (or count 1))
    (helixel-mc--rotate-primary '<)))

(defun helixel-mc--swap-real-and-fake (ov)
  "Swap real cursor state with fake OV's `helixel-pc-state'.
After the call, the real cursor sits at OV's old position with
OV's old per-cursor state (kill-ring, pending-sel, event-ring, …),
and OV holds what used to be the real cursor's position and state.

The fake overlay gets a fresh `helixel-pc-state' (cloned from the
real cursor's pre-swap state).  OV's old markers are released — no
caller holds references to them outside the struct on OV itself."
  (let* ((real-cs (helixel-mc--pcs-clone))         ; snapshot of real
         (fake-cs (overlay-get ov 'helixel-pc-state)))
    ;; Move real cursor onto fake's state.
    (helixel-mc--pcs-swap-in fake-cs)
    ;; Store real's old state on the fake overlay (replaces entire struct).
    (overlay-put ov 'helixel-pc-state real-cs)
    ;; Release fake's old markers — no longer referenced.
    (helixel-mc--pcs-release fake-cs)
    (helixel-mc--update-fake-region ov)
    (helixel-mc--paint-cursor-overlay
     ov (marker-position (helixel-pcs-point real-cs)))))

;;;###autoload
(defun helixel-mc-rotate-content-forward (&optional count)
  "Cyclically shift each cursor's selection text FORWARD by one cursor.
Every cursor (real included) must have an active non-degenerate
region.  Selection regions must be non-overlapping.  Prefix COUNT
repeats."
  (interactive "p")
  (helixel-mc--rotate-content (or count 1) 'forward))

;;;###autoload
(defun helixel-mc-rotate-content-backward (&optional count)
  "Cyclically shift each cursor's selection text BACKWARD by one cursor.
Inverse of `helixel-mc-rotate-content-forward'.  Prefix COUNT repeats."
  (interactive "p")
  (helixel-mc--rotate-content (or count 1) 'backward))

(defun helixel-mc--collect-all-cursors-sorted ()
  "Return all cursors (real as virtual entry) sorted by region begin.
Each entry is a plist:
  (:cursor OV-OR-NIL :beg MARKER :end MARKER :forward BOOL)
BEG/END are fresh markers (begin insertion-type nil, end
insertion-type t) so they bracket their region across
delete+insert.  :forward is t when point > mark for that cursor.
The real cursor has :cursor nil."
  (let ((all
         (cons
          (let* ((p (point)) (m (mark t))
                 (b (min p m)) (e (max p m)))
            (list :cursor nil
                  :beg (copy-marker b nil)
                  :end (copy-marker e t)
                  :forward (> p m)))
          (mapcar (lambda (ov)
                    (let* ((p (marker-position
                               (helixel-mc-cursor-point ov)))
                           (m (marker-position
                               (helixel-mc-cursor-mark ov)))
                           (b (min p m)) (e (max p m)))
                      (list :cursor ov
                            :beg (copy-marker b nil)
                            :end (copy-marker e t)
                            :forward (> p m))))
                  (helixel-mc-all-cursors)))))
    (sort all (lambda (a b)
                (< (marker-position (plist-get a :beg))
                   (marker-position (plist-get b :beg)))))))

(defun helixel-mc--rotate-content (count dir)
  "Shift content of every cursor's region by COUNT positions in DIR.
DIR is `forward' or `backward'.  All cursors must have active
regions.  Implementation: snapshot every region's text, then
replace each region with the text of its DIR-rotated neighbor.
Regions are processed RIGHT-to-LEFT to keep marker positions
stable across replacements.  Region activation (real and fake
`mark-active') is preserved across the rotation so the command
can be pressed repeatedly."
  (unless (helixel-mc-any-p)
    (user-error "No fake cursors"))
  (unless (use-region-p)
    (user-error "Real cursor must have a region"))
  (helixel-mc--validate-all-cursor-regions)
  (let ((deactivate-mark nil))
    (dotimes (_ count)
      (helixel-mc--rotate-content-once dir))))

(defun helixel-mc--validate-all-cursor-regions ()
  "Signal `user-error' if any cursor lacks a non-degenerate region."
  (dolist (ov (helixel-mc-all-cursors))
    (unless (and (helixel-mc-cursor-mark-active ov)
                 (/= (marker-position (helixel-mc-cursor-point ov))
                     (marker-position (helixel-mc-cursor-mark ov))))
      (user-error "Every cursor must have a non-degenerate region"))))

(defun helixel-mc--rotate-content-once (dir)
  "Perform one rotation step in DIR.
Collects entries, replaces text right-to-left, re-anchors
cursors, and frees temp markers."
  (let* ((entries (helixel-mc--collect-all-cursors-sorted))
         (n (length entries))
         (texts (mapcar (lambda (e)
                          (buffer-substring-no-properties
                           (marker-position (plist-get e :beg))
                           (marker-position (plist-get e :end))))
                        entries))
         (new-texts (helixel-mc--rotate-texts texts n dir))
         (pairs (cl-mapcar #'cons entries new-texts)))
    (helixel-mc--rotate-replace pairs)
    (helixel-mc--rotate-reanchor entries)
    (helixel-mc--rotate-free-markers entries)))

(defun helixel-mc--rotate-texts (texts n dir)
  "Return TEXTS rotated by one step in DIR.
N is the length of TEXTS.
DIR is `forward' or `backward'."
  (mapcar (lambda (i)
            (nth (if (eq dir 'forward) (mod (1- i) n) (mod (1+ i) n))
                 texts))
          (number-sequence 0 (1- n))))

(defun helixel-mc--rotate-replace (pairs)
  "Replace each region entry in PAIRS with its paired text, right-to-left.
PAIRS is a list of (ENTRY . TEXT) cons cells."
  (dolist (cell (reverse pairs))
    (let ((b (marker-position (plist-get (car cell) :beg)))
          (e (marker-position (plist-get (car cell) :end)))
          (txt (cdr cell)))
      (save-excursion
        (goto-char b)
        (delete-region b e)
        (insert txt)))))

(defun helixel-mc--rotate-reanchor (entries)
  "Re-anchor each cursor onto its rotated region from ENTRIES.
Preserves `mark-active' state."
  (dolist (entry entries)
    (let* ((ov (plist-get entry :cursor))
           (b (marker-position (plist-get entry :beg)))
           (e (marker-position (plist-get entry :end)))
           (fwd (plist-get entry :forward)))
      (if ov
          (helixel-mc--rotate-reanchor-fake ov b e fwd)
        (helixel-mc--rotate-reanchor-real b e fwd)))))

(defun helixel-mc--rotate-reanchor-fake (ov b e fwd)
  "Re-anchor fake cursor OV onto bounds B..E with FWD direction."
  (let ((pm (helixel-mc-cursor-point ov))
        (mm (helixel-mc-cursor-mark ov)))
    (if fwd
        (progn (set-marker pm e) (set-marker mm b))
      (set-marker pm b) (set-marker mm e))
    (setf (helixel-pcs-mark-active (helixel-mc-cursor-state ov)) t)
    (helixel-mc--update-fake-region ov)))

(defun helixel-mc--rotate-reanchor-real (b e fwd)
  "Re-anchor real cursor onto bounds B..E with FWD direction."
  (if fwd
      (progn (goto-char e) (set-marker (mark-marker) b))
    (goto-char b) (set-marker (mark-marker) e))
  (setq mark-active t))

(defun helixel-mc--rotate-free-markers (entries)
  "Free temp markers in ENTRIES."
  (dolist (entry entries)
    (set-marker (plist-get entry :beg) nil)
    (set-marker (plist-get entry :end) nil)))

;; ── Region-set helpers (shared by trim, merge, split, etc.) ──

(defun helixel-mc--regions-of-all-cursors ()
  "Return list of (CURSOR-OR-NIL BEG END FORWARD) for all cursors.
Real cursor's CURSOR is nil.  Only non-degenerate, active
regions are included.  Result is sorted by BEG."
  (let (acc)
    (when (use-region-p)
      (push (list nil (region-beginning) (region-end)
                  (> (point) (mark t)))
            acc))
    (dolist (ov (helixel-mc-all-cursors))
      (let ((p (marker-position (helixel-mc-cursor-point ov)))
            (m (marker-position (helixel-mc-cursor-mark ov)))
            (a (helixel-mc-cursor-mark-active ov)))
        (when (and a (/= p m))
          (push (list ov (min p m) (max p m) (> p m)) acc))))
    (sort acc (lambda (a b) (< (nth 1 a) (nth 1 b))))))

(defun helixel-mc--install-regions (region-specs)
  "Replace all cursors with regions described by REGION-SPECS.
REGION-SPECS is a list of (BEG END FORWARD) triples.  The FIRST
spec is installed on the real cursor; the rest become fakes.
All existing fakes are cleared first.  If REGION-SPECS is empty
the mc session is fully disabled.

A triple with BEG = END represents a point-only cursor (no active
region)."
  (helixel-mc-clear-all)
  (cond
   ((null region-specs)
    nil)
   (t
    (let* ((first (car region-specs))
           (b (nth 0 first)) (e (nth 1 first)) (fwd (nth 2 first)))
      (if (= b e)
          ;; Point-only real cursor: just move point, no region.
          (progn (goto-char b) (deactivate-mark))
        (if fwd (progn (goto-char e) (set-marker (mark-marker) b))
          (goto-char b) (set-marker (mark-marker) e))
        (setq mark-active t)))
    (dolist (spec (cdr region-specs))
      (let* ((b (nth 0 spec)) (e (nth 1 spec)) (fwd (nth 2 spec))
             (empty-p (= b e))
             (p (if fwd e b))
             (m (if empty-p p (if fwd b e)))
             (ov (helixel-mc--create-fake-cursor p m)))
        (when ov
          (unless empty-p
            (setf (helixel-pcs-mark-active
                   (overlay-get ov 'helixel-pc-state)) t)
            (helixel-mc--update-fake-region ov))))))))

(defmacro helixel-mc-with-regions (regions-var &rest body)
  "Bind REGIONS-VAR to active (BEG END FORWARD) triples; install BODY's result.
REGIONS-VAR (a symbol) is bound to a list of (BEG END FORWARD)
triples — one per cursor (real + fake) with an active
non-degenerate region, sorted by BEG.  BODY must return a list of
three-element specs — the new layout to install via
`helixel-mc--install-regions'.  Returning an empty list disables
the mc session.

This macro is the shared shape for commands that compute a new
cursor layout from the existing one: trim, merge, split,
keep-matching, etc.  Commands that mutate buffer contents while
relying on cursor overlays staying anchored (e.g.
`helixel-mc-rotate-content') do NOT fit this pattern."
  (declare (indent 1) (debug (symbolp body)))
  `(let* ((,regions-var
           (mapcar #'cdr (helixel-mc--regions-of-all-cursors))))
     (helixel-mc--install-regions (progn ,@body))))

;;;###autoload
(defun helixel-mc-merge ()
  "Merge real + every fake cursor's active region into ONE big selection.
The merged region spans from the leftmost edge to the rightmost
edge of all active regions.  All fakes are cleared."
  (interactive)
  (unless (helixel-mc-any-p)
    (user-error "No fake cursors"))
  (helixel-mc-with-regions regions
    (unless regions (user-error "No active regions to merge"))
    (list (list (apply #'min (mapcar #'car  regions))
                (apply #'max (mapcar #'cadr regions))
                t))))

(defun helixel-mc--trim-region (beg end)
  "Return (TRIMMED-BEG . TRIMMED-END) for region [BEG, END).
When the region consists entirely of whitespace, returns
\(POS . POS) where POS is the end of the leading whitespace
\(i.e. the start of non-whitespace content)."
  (save-excursion
    (let* ((s (buffer-substring-no-properties beg end))
           (lead (if (string-match "\\`[ \t\r\n]+" s)
                     (match-end 0) 0))
           (trail (if (string-match "[ \t\r\n]+\\'" s)
                      (- (length s) (match-beginning 0)) 0)))
      (if (>= (+ lead trail) (- end beg))
          ;; Region is all whitespace — collapse to point-only at
          ;; the end of leading whitespace.
          (let ((pos (+ beg lead)))
            (cons pos pos))
        (cons (+ beg lead) (- end trail))))))

(defun helixel-mc-trim ()
  "Trim leading and trailing whitespace from every cursor's region.
Regions that become empty after trimming are converted to
point-only cursors instead of being removed."
  (interactive)
  (helixel-mc-with-regions regions
    (cl-loop for (b e fwd) in regions
             for trimmed = (helixel-mc--trim-region b e)
             collect (list (car trimmed) (cdr trimmed) fwd))))

;;;###autoload
(defun helixel-mc-align ()
  "Insert spaces to align all cursor columns.
For each line that has multiple cursors, pads earlier ones with
spaces so every cursor sits at the rightmost cursor's column on
its group of lines.  Simpler than hel-mode's full multi-column
align, but covers the common case of column-aligning a vertical
column-of-cursors created via `s a' / `xs'."
  (interactive)
  (unless (helixel-mc-any-p)
    (user-error "No fake cursors"))
  (let* ((points
          (sort (cons (copy-marker (point) t)
                      (mapcar (lambda (ov)
                                (copy-marker
                                 (marker-position
                                  (helixel-mc-cursor-point ov))
                                 t))
                              (helixel-mc-all-cursors)))
                (lambda (a b) (< (marker-position a)
                                 (marker-position b)))))
         ;; Compute max column across all points.
         (max-col
          (cl-loop for p in points
                   maximize (save-excursion
                              (goto-char (marker-position p))
                              (current-column)))))
    ;; Right-to-left so insertions don't shift earlier markers.
    (dolist (p (reverse points))
      (save-excursion
        (goto-char (marker-position p))
        (let ((need (- max-col (current-column))))
          (when (> need 0)
            (insert (make-string need ?\s))))))
    (dolist (p points) (set-marker p nil))))

;;;###autoload
(defun helixel-mc-split-selection (regex)
  "Split every cursor's selection on REGEX into multiple cursors.
For each existing selection, splits it at every match of REGEX,
discarding the matches themselves.  Each non-empty segment
between matches becomes a new cursor.

Example: select `apple,banana,orange' and split on `,' →
3 cursors selecting `apple', `banana', `orange'.

Selections with no match are removed.  If the resulting set is
empty the mc session is disabled."
  (interactive (list (read-regexp "Split selection on: ")))
  (helixel-mc--push-history)
  (let (count)
    (helixel-mc-with-regions regions
      (let ((new-specs
             (cl-loop
              for (b e fwd) in regions
              append (helixel-mc--split-region b e fwd regex))))
        (setq count (length new-specs))
        new-specs))
    (message "helixel-mc: split into %d cursor%s"
             count (if (= 1 count) "" "s"))))

(defun helixel-mc--regex-match-positions (beg end regex &optional skip-zero)
  "Return visible (BEG . END) conses for each REGEX match in BEG..END.
Skips invisible matches.  When SKIP-ZERO is non-nil, also skip
zero-width matches (for splitting, where you cannot split on a
zero-width boundary).  Respects `helixel-invisible'."
  (helixel--with-invisible-search
    (save-excursion
      (goto-char beg)
      (cl-loop with continue = t
               while (and continue (re-search-forward regex end t))
               for z-w = (= (match-beginning 0) (match-end 0))
               if (and skip-zero z-w)
               do (if (eobp) (setq continue nil) (forward-char 1))
               else if (or (helixel--invisible-effective)
                           (funcall isearch-filter-predicate
                                    (match-beginning 0) (match-end 0)))
               collect (cons (match-beginning 0) (match-end 0))
               and when z-w
               do (if (eobp) (setq continue nil) (forward-char 1))))))

(defun helixel-mc--split-region (beg end fwd regex)
  "Split region BEG..END on REGEX matches.
Return a list of (BEG END FWD) triples, one per non-empty segment
between matches (or between boundary and match).
Matches themselves are discarded."
  (let ((segments nil)
        (pos beg))
    (dolist (m (helixel-mc--regex-match-positions beg end regex t))
      (unless (= pos (car m))
        (push (list pos (car m) fwd) segments))
      (setq pos (cdr m)))
    (unless (= pos end)
      (push (list pos end fwd) segments))
    (nreverse segments)))

(defun helixel-mc--collect-regex-matches (beg end fwd regex)
  "Return (BEG END FWD) specs for each visible REGEX match between BEG..END."
  (mapcar (lambda (m) (list (car m) (cdr m) fwd))
          (helixel-mc--regex-match-positions beg end regex)))

;;;###autoload
(defun helixel-mc-select-regex (regex)
  "Select every match of REGEX within each cursor's selection.
For each existing selection, replaces it with one cursor per
REGEX match found inside it.  Matches are highlighted as
selections (not discarded).  Selections with no match are
removed.  If the resulting set is empty the mc session is
disabled."
  (interactive (list (read-regexp "Select regex matches: ")))
  (helixel-mc--push-history)
  (let (count)
    (helixel-mc-with-regions regions
      (let ((new-specs (cl-loop for (b e fwd) in regions
                                append (helixel-mc--collect-regex-matches
                                        b e fwd regex))))
        (setq count (length new-specs))
        new-specs))
    (message "helixel-mc: %d regex match%s selected"
             count (if (= 1 count) "" "es"))))

;;;###autoload

;; ── Restore cursor layout history (g v) ──

(defvar helixel-mc--history nil
  "List of past cursor-layout snapshots.
Most-recent first.  Each entry is a list of (P M ACTIVE) triples
\(first entry is the real cursor at snapshot time).")

(defcustom helixel-mc-history-max 16
  "Maximum number of cursor-layout snapshots remembered for `g v'."
  :type 'integer
  :group 'helixel-mc)

(defun helixel-mc--snapshot-layout ()
  "Return current layout as a list of (P M ACTIVE) triples.
First entry is the real cursor.  Returns nil when there are no
fake cursors AND no real region (nothing worth remembering)."
  (let ((entries
         (cons (list (point) (mark t) (and mark-active t))
               (mapcar
                (lambda (ov)
                  (list (marker-position
                         (helixel-mc-cursor-point ov))
                        (marker-position
                         (helixel-mc-cursor-mark ov))
                        (and (helixel-mc-cursor-mark-active ov) t)))
                (helixel-mc-all-cursors)))))
    (when (or (cdr entries)
              (cadar entries)) ; real has mark
      entries)))

(defun helixel-mc--push-history ()
  "Snapshot current layout (if any) and push onto history.
No-op unless the snapshot contains at least one FAKE cursor
\(real-only layouts aren't worth restoring).  Dedupes against
most recent entry.  Caps at `helixel-mc-history-max'.  Callers
that want to suppress recording locally can rebind
`helixel-mc-before-clear-hook' to nil around their work."
  (let ((snap (helixel-mc--snapshot-layout)))
    (when (and snap
               (cdr snap)             ; require >= 1 fake
               (not (equal snap (car helixel-mc--history))))
      (push snap helixel-mc--history)
      (when (> (length helixel-mc--history) helixel-mc-history-max)
        (setq helixel-mc--history
              (cl-subseq helixel-mc--history
                         0 helixel-mc-history-max))))))

;;;###autoload
(defun helixel-mc-restore-cursors ()
  "Restore the most recent cursor layout snapshot.
Useful after \\[helixel-mc-clear-all] / `s ,' / `s SPC'
\(clear-all): press `g v' to
bring back the prior set of fakes.  Repeated `g v' walks deeper
into history."
  (interactive)
  (let ((snap (pop helixel-mc--history)))
    (unless snap
      (user-error "No previous multi-cursor layout to restore"))
    (let ((helixel-mc-before-clear-hook nil))
      ;; Snapshot CURRENT layout first so user can re-redo by
      ;; pushing it back.  We push it onto the END so successive
      ;; `g v' calls walk back through history, not bounce.
      (let ((cur (helixel-mc--snapshot-layout)))
        (when cur
          (setq helixel-mc--history
                (append helixel-mc--history (list cur)))
          (when (> (length helixel-mc--history) helixel-mc-history-max)
            (setq helixel-mc--history
                  (cl-subseq helixel-mc--history
                             0 helixel-mc-history-max)))))
      (helixel-mc-clear-all)
      (let* ((real (car snap))
             (rp (nth 0 real)) (rm (nth 1 real)) (ra (nth 2 real)))
        (goto-char rp)
        (set-marker (mark-marker) (or rm rp))
        (setq mark-active (and ra (numberp rm) (/= rp rm))))
      (dolist (entry (cdr snap))
        (let* ((p (nth 0 entry)) (m (nth 1 entry)) (a (nth 2 entry))
               (ov (helixel-mc--create-fake-cursor p (or m p))))
          (when ov
            (setf (helixel-pcs-mark-active (overlay-get ov 'helixel-pc-state))
                  (and a (numberp m) (/= p m)))
            (helixel-mc--update-fake-region ov)))))))

;; Auto-snapshot before `clear-all' destroys cursors.  Done via
;; `helixel-mc-before-clear-hook' (cleaner than advice).  The
;; recursive call from `(helixel-mc-mode -1)' inside
;; `clear-all' is harmless: `--push-history' requires at least
;; one fake cursor in the snapshot, and by that point the fakes
;; have already been deleted.
(defun helixel-mc-spawn--init ()
  "Wire mc-spawn internals."
  (add-hook 'helixel-mc-before-clear-hook #'helixel-mc--push-history))
;; helixel-mc-spawn--init registered via `helixel--register-mode-hooks'
;; in helixel.el.

(provide 'helixel-mc-spawn)
;;; helixel-mc-spawn.el ends here
