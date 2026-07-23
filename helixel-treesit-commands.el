;;; helixel-treesit-commands.el --- Tree-sitter commands: textobj, move, nav, sibling -*- lexical-binding: t; -*-

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

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; Command layer for tree-sitter integration.
;;
;; Defines all treesit commands via a single data-driven macro
;; `helixel-ts--define-type'.  Each type gets:
;;   - Plain implementation functions (no tracking — for dispatch vars)
;;   - helixel-define-command wrappers (for direct keymap binding)
;;   - Comma-repeat support
;;
;; Also provides: expand/shrink, sibling navigation.

;;; Code:

(require 'helixel-treesit-core)
(require 'helixel-macros)
(require 'helixel-motion)

;; Cross-module declarations
(declare-function helixel--track-visual-move "helixel-move" t t)
(declare-function helixel--clear-highlights "helixel-state" t t)
(declare-function helixel--repeat-movement-motion "helixel-move" t t)
(declare-function helixel--motion-select-category-p "helixel-core" t t)
(declare-function helixel--set-mark-region "helixel-core" t t)
(declare-function helixel--motion-invoke "helixel-move" t t)
(declare-function helixel--motion-eff-cmd "helixel-move" t t)
(declare-function helixel--comment-block-bounds "helixel-move" t t)

(defvar helixel-textobj-action-function)
(defvar helixel--motion-permanent-flip)

;; ----------------------------------------------------------------------
;; Shared implementation: select object at point
;; ----------------------------------------------------------------------

(defun helixel-ts--select-object (base part &optional count)
  "Select innermost enclosing BASE object PART at point.
COUNT is selection count.  Returns non-nil on success.
When region is already a textobj, advances past it first."
  (unless (helixel-ts-ready-p)
    (message
     (concat
      "No tree-sitter parser in this buffer.  "
      "Install a tree-sitter grammar and `evil-textobj-tree-sitter'."))
    nil)
  (let ((followup-p (and (use-region-p)
                         (eq (helixel--region-type) 'textobj))))
    (when followup-p
      (goto-char (region-end))
      (skip-chars-forward " \t\n\r\f,;:")
      (when-let* ((node (helixel-ts--node-at-point))
                  ((> (treesit-node-end node) (point))))
        (goto-char (treesit-node-end node))
        (skip-chars-forward " \t\n\r\f,;:")))
    (and (helixel-ts-ready-p)
         (when-let* ((range (or (helixel-ts--object-at
                                 base part 0 followup-p)
                                (and (not followup-p)
                                     (helixel-ts--nearest-forward
                                      base part))))
                     ;; For comments, merge adjacent comment lines
                     ;; into a single block.
                     (final-range
                      (if (equal base "comment")
                          (or (helixel--comment-block-bounds range)
                              range)
                        range)))
           (helixel-ts--activate-selection
            (car final-range) (cdr final-range) base part 0 count)
           t))))

;; ----------------------------------------------------------------------
;; Shared implementation: apply navigation
;; ----------------------------------------------------------------------

(defun helixel-ts--apply-navigation (beg end base-name part forward-p select-p)
  "Apply shared navigation for treesit node movement.
BEG/END are raw node bounds (END exclusive).
BASE-NAME identifies the node type, PART is `around' or `inside'.
FORWARD-P places cursor at END when t, at BEG when nil.
SELECT-P non-nil activates region; nil does move-only."
  (if select-p
      (progn
        (push-mark (if forward-p beg end) nil t)
        (goto-char (if forward-p end beg))
        (helixel--set-mark-region (cons beg end))
        (helixel-ts--push-selection-with beg end base-name))
    (goto-char (if forward-p end beg))
    (helixel-ts--setup-nav-state beg end base-name part)))

(defun helixel-ts--push-selection-with (beg end base)
  "Push a treesit selection spanning BEG..END with type BASE."
  (let* ((prev helixel--pending-sel)
         (total-n (if (and prev
                           (eq (helixel-sel-kind prev) 'treesit))
                      (plist-get (helixel-sel-ctx prev) :level)
                    0)))
    (helixel--sel-push
     (helixel-sel-create
      'treesit
      `(:command grow
                 :start ,beg
                 :end ,end
                 :level ,(1+ total-n)
                 :base ,base)))))

(defun helixel-ts--setup-nav-state (beg end base part)
  "Set up tracking state for treesit navigation at [BEG, END).
BASE and PART identify the treesit object."
  (helixel--set-mark-region (cons beg end))
  (helixel--sel-push
   (helixel-sel-create
    'treesit `(:base ,base :part ,part :level 0
                     :start ,beg :end ,end
                     :count 1 :inline-advance t))))

;; ----------------------------------------------------------------------
;; Shared implementation: apply nav with select-category check
;; ----------------------------------------------------------------------

(defun helixel-ts--apply-nav (bounds base forward-p &optional outer-p)
  "Apply navigation BOUNDS (BEG . END) for object BASE.
FORWARD-P → cursor at end; nil → cursor at start.
When `helixel-motion-select-categories' includes the subcat,
activates the region.  OUTER-P enables parameter comma expansion."
  (let ((beg (car bounds))
        (end (cdr bounds))
        (select-p (helixel--motion-select-category-p
                   'movement (or (intern-soft base) (intern base)))))
    (if select-p
        (let ((sel-beg beg)
              (sel-end end))
          (when (and outer-p (equal base "parameter"))
            (let ((expanded (helixel-ts--parameter-outer-bounds
                             beg end)))
              (setq sel-beg (car expanded)
                    sel-end (cdr expanded))))
          (helixel-ts--apply-navigation
           sel-beg sel-end base 'around forward-p t))
      (helixel-ts--apply-navigation
       beg end base 'around forward-p nil))))

;; ----------------------------------------------------------------------
;; Shared implementation: inner move (navigate to inside bounds)
;; ----------------------------------------------------------------------

(defun helixel-ts--inner-move (base forward-p count)
  "Move by treesit node BASE using inside-part bounds, COUNT times.
FORWARD-P non-nil → forward (end of node), nil → backward (start)."
  (let ((n (abs (or count 1)))
        (flipped (< (or count 1) 0))
        bounds
        eff-forward-p)
    (dotimes (_ n)
      (when (and helixel--pending-sel
                 (eq (helixel-sel-kind helixel--pending-sel) 'treesit)
                 (equal (helixel-sel-field helixel--pending-sel :base)
                        base))
        (let* ((ps-start (helixel-sel-field helixel--pending-sel :start))
               (ps-end (helixel-sel-field helixel--pending-sel :end))
               (outer (and ps-start ps-end
                           (helixel-ts--enclosing-node base ps-start))))
          (if forward-p
              (let ((end (or (cdr outer) ps-end)))
                (when (>= end (point))
                  (goto-char end)
                  (skip-chars-forward " \t\n\r\f,;:")))
            (let ((start (or (car outer) ps-start)))
              (when (<= start (point))
                (goto-char (1- start))
                (skip-chars-backward " \t\n\r\f,;:"))))))
      (setq eff-forward-p (if flipped (not forward-p) forward-p)
            bounds (helixel-ts--nav-bounds base eff-forward-p))
      (unless bounds
        (user-error "No %s found" base))
      (let ((outer-beg (car bounds))
            (outer-end (cdr bounds)))
        (save-excursion
          (goto-char outer-beg)
          (let ((inner-range
                 (helixel-ts--object-at base 'inside 0 t)))
            (if (and inner-range
                     (>= (car inner-range) outer-beg)
                     (<= (cdr inner-range) outer-end))
                (setq bounds inner-range)
              nil))))
      (helixel-ts--apply-nav bounds base eff-forward-p))))

;; ----------------------------------------------------------------------
;; Shared implementation: outer nav with tracking
;; ----------------------------------------------------------------------

(defun helixel-ts--outer-move (base forward-p count)
  "Move by treesit outer node BASE, COUNT times.
FORWARD-P → forward; nil → backward."
  (let ((n (abs (or count 1)))
        (flipped (< (or count 1) 0))
        bounds
        eff-forward-p)
    (dotimes (_ n)
      (setq eff-forward-p (if flipped (not forward-p) forward-p)
            bounds (helixel-ts--nav-bounds base eff-forward-p))
      (unless bounds
        (user-error "No more %ss" base))
      (helixel-ts--apply-nav bounds base eff-forward-p t))))

;; ----------------------------------------------------------------------
;; Comment-specific navigation
;; ----------------------------------------------------------------------

(defun helixel-ts--comment-move (forward-p count &optional select-p)
  "Move by treesit comment in direction FORWARD-P, COUNT times.
Each step jumps over a full comment block, not individual
comment nodes.  SELECT-P non-nil activates region."
  (let ((n (abs (or count 1)))
        (flipped (< (or count 1) 0))
        bounds
        eff-forward-p)
    (dotimes (_ n)
      (setq eff-forward-p (if flipped (not forward-p) forward-p)
            bounds (helixel-ts--nav-bounds "comment" eff-forward-p))
      (unless bounds
        (user-error "No comment found"))
      ;; Expand to comment block.
      (when-let* ((block (helixel--comment-block-bounds bounds)))
        (setq bounds block))
      (let ((beg (car bounds))
            (end (cdr bounds)))
        (helixel-ts--apply-navigation
         beg end "comment" 'around eff-forward-p select-p)))))

;; ----------------------------------------------------------------------
;; Expand / Shrink
;; ----------------------------------------------------------------------

(defvar-local helixel-ts--expand-stack nil
  "Stack of previous selections for expand/shrink.
Each element is (BEG END LEVEL BASE PART).")

(defun helixel-ts--push-selection ()
  "Push current treesit selection onto expand stack."
  (when helixel--pending-sel
    (push (list (region-beginning)
                (region-end)
                (or (plist-get (helixel-sel-ctx helixel--pending-sel) :level) 0)
                (plist-get (helixel-sel-ctx helixel--pending-sel) :base)
                'around)
          helixel-ts--expand-stack)))

(defun helixel-ts--grow-selection ()
  "Expand current treesit selection to parent node.
Returns non-nil on success."
  (helixel-ts--check-ready)
  (if (and helixel--pending-sel
           (eq (helixel-sel-kind helixel--pending-sel) 'treesit))
      (let* ((ctx (helixel-sel-ctx helixel--pending-sel))
             (level (or (plist-get ctx :level) 0))
             (sel-beg (region-beginning))
             (sel-end (region-end)))
        (helixel-ts--push-selection)
        (if-let* ((parent-bounds (helixel-ts--parent-range sel-beg sel-end)))
            (progn
              (helixel-ts--activate-selection
               (car parent-bounds) (cdr parent-bounds)
               (or (when-let* ((n (treesit-node-at
                                   (car parent-bounds) nil t)))
                     (treesit-node-type n))
                   "unknown")
               'around (1+ level))
              t)
          nil))
    (when-let* ((node (helixel-ts--node-at-point)))
      (let* ((bounds (helixel-ts--node->bounds node))
             (cap-name (treesit-node-type node)))
        (helixel-ts--activate-selection
         (car bounds) (cdr bounds) cap-name 'around 0)
        t))))

(defun helixel-ts--shrink-selection ()
  "Shrink treesit selection by restoring from expand stack.
Returns non-nil on success."
  (helixel-ts--check-ready)
  (if helixel-ts--expand-stack
      (let ((prev (pop helixel-ts--expand-stack)))
        (helixel-ts--activate-selection
         (nth 0 prev) (nth 1 prev) (nth 3 prev) (nth 4 prev) (nth 2 prev))
        t)
    (user-error "Cannot shrink further")))

;; ----------------------------------------------------------------------
;; Sibling navigation
;; ----------------------------------------------------------------------

(defun helixel-ts--sibling-bounds (forward-p)
  "Return (BEG . END) of next/prev sibling, or nil.
FORWARD-P non-nil for next sibling, nil for previous."
  (helixel-ts--check-ready)
  (let ((node
         (if (and helixel--pending-sel
                  (eq (helixel-sel-kind helixel--pending-sel) 'treesit))
             (let* ((ctx (helixel-sel-ctx helixel--pending-sel))
                    (start (plist-get ctx :start))
                    (end (plist-get ctx :end)))
               (if (and start end)
                   (helixel-ts--node-matching-bounds start end)
                 (helixel-ts--node-at-point)))
           (helixel-ts--node-at-point))))
    (unless node
      (let ((raw (treesit-node-at (point) nil nil)))
        (when raw
          (setq node (if (treesit-node-check raw 'named) raw
                       (helixel-ts--named-parent raw))))))
    (and node
         (helixel-ts--sibling-range
          (treesit-node-start node) (treesit-node-end node) forward-p))))

(defun helixel-ts--apply-sibling (bounds)
  "Apply sibling BOUNDS (BEG . END) to current selection."
  (let* ((node (helixel-ts--node-matching-bounds
                (car bounds) (cdr bounds)))
         (base (if node (treesit-node-type node)
                 (treesit-node-type
                  (treesit-node-at (car bounds) nil t)))))
    (helixel-ts--apply-navigation
     (car bounds) (cdr bounds) base 'around nil
     (helixel--motion-select-category-p 'movement 'sibling))))

;; ----------------------------------------------------------------------
;; Comma-repeat helpers
;; ----------------------------------------------------------------------

(defun helixel-ts--cmd->base-part (cmd)
  "Extract (BASE . PART) from a treesit command symbol.
CMD examples: `helixel-ts-mark-inner-parameter',
`helixel-ts--backward-inner-function'.
Returns (\"base\" . inside|around) or nil."
  (let ((name (symbol-name cmd)))
    (cond
     ;; Text-object: helixel-ts-mark-{inner|a}-{type}
     ((string-prefix-p "helixel-ts-mark-" name)
      (let* ((rest (substring name (length "helixel-ts-mark-")))
             (part (cond ((string-prefix-p "inner-" rest) 'inside)
                         ((string-prefix-p "a-" rest) 'around)))
             (base (when part
                     (substring rest (if (eq part 'inside)
                                         (length "inner-")
                                       (length "a-"))))))
        (when base (cons base part))))
     ;; Inner-left move: helixel-ts--backward-inner-{type}
     ((string-prefix-p "helixel-ts--backward-inner-" name)
      (cons (substring name (length "helixel-ts--backward-inner-"))
            'inside))
     ;; Inner-right move: helixel-ts--forward-inner-{type}
     ((string-prefix-p "helixel-ts--forward-inner-" name)
      (cons (substring name (length "helixel-ts--forward-inner-"))
            'inside)))))

(defun helixel-ts--repeat-treesit-motion (rec)
  "Replay a treesit motion from REC (comma-repeat)."
  (let* ((cmd (helixel--last-motion-command rec))
         (effective-cmd (helixel--motion-eff-cmd cmd rec))
         (has-reverse (or (helixel--last-motion-reverse-command rec)
                          (helixel--motion-reverse-lookup cmd)))
         (backward-p helixel--motion-permanent-flip)
         (saved-flip (and (not has-reverse)
                          helixel--motion-permanent-flip)))
    (if has-reverse
        (let ((orig (point)))
          (helixel--motion-invoke rec effective-cmd orig))
      (let* ((rb (when (use-region-p) (region-beginning)))
             (re (when (use-region-p) (region-end)))
             (bp (helixel-ts--cmd->base-part cmd))
             (search-pos (if backward-p
                             (or rb (point))
                           (save-excursion
                             (goto-char (or re (point)))
                             (skip-chars-backward " \t\n\r\f,;:")
                             (point))))
             (next (and bp
                        (helixel-ts--next-capture
                         (car bp) search-pos (not backward-p)))))
        (when (and backward-p next rb re
                   (<= (car next) rb) (>= (cdr next) re))
          (setq next (helixel-ts--next-capture
                      (car bp) (max (point-min) (1- (car next))) nil)))
        (unless next
          (when (and (not backward-p) bp
                     (> search-pos (point-min)))
            (setq next (helixel-ts--next-capture
                        (car bp) (1- search-pos) t)))
          (unless next
            (user-error "No more targets for motion repeat")))
        (deactivate-mark)
        (goto-char (if backward-p (1- (cdr next)) (car next)))
        (let ((orig (point)))
          (helixel--motion-invoke rec effective-cmd orig))))
    (when saved-flip
      (setq helixel--motion-permanent-flip saved-flip))))

;; ----------------------------------------------------------------------
;; Data-driven type definition macro
;; ----------------------------------------------------------------------

(defmacro helixel-ts--define-type (name &rest keys)
  "Define all commands for treesit type NAME.
NAME is a string like \"function\".
KEYS is a plist with keys :textobj, :inner-move, :outer-nav."
  (declare (indent 1))
  (let* ((name-str name)
         (name-sym (intern name-str))
         (textobj (plist-get keys :textobj))
         (inner-move (plist-get keys :inner-move))
         (outer-nav (plist-get keys :outer-nav))
         ;; Plain impls (no tracking — for dispatch vars)
         (select-around-fn
          (intern (format "helixel-ts--select-%s-around" name-str)))
         (select-inside-fn
          (intern (format "helixel-ts--select-%s-inside" name-str)))
         (move-forward-inner-fn
          (intern (format "helixel-ts--move-forward-inner-%s" name-str)))
         (move-backward-inner-fn
          (intern (format "helixel-ts--move-backward-inner-%s" name-str)))
         (move-forward-outer-fn
          (intern (format "helixel-ts--move-forward-outer-%s" name-str)))
         (move-backward-outer-fn
          (intern (format "helixel-ts--move-backward-outer-%s" name-str)))
         ;; Command wrappers (with tracking — for keymap binding)
         (mark-a-cmd
          (intern (format "helixel-ts-mark-a-%s" name-str)))
         (mark-inner-cmd
          (intern (format "helixel-ts-mark-inner-%s" name-str)))
         (forward-inner-cmd
          (intern (format "helixel-ts-forward-inner-%s" name-str)))
         (backward-inner-cmd
          (intern (format "helixel-ts-backward-inner-%s" name-str)))
         (forward-outer-cmd
          (intern (format "helixel-ts-forward-outer-%s" name-str)))
         (backward-outer-cmd
          (intern (format "helixel-ts-backward-outer-%s" name-str))))
    `(progn
       ;; ── Plain implementations (no tracking) ──
       ,@(when textobj
           `((defun ,select-around-fn (count)
               ,(format "Select a %s using tree-sitter." name-str)
               (when helixel-textobj-action-function
                 (funcall helixel-textobj-action-function
                          'textobj ',name-sym))
               (helixel-ts--select-object ,name-str 'around count))
             (defun ,select-inside-fn (count)
               ,(format "Select inner %s using tree-sitter." name-str)
               (when helixel-textobj-action-function
                 (funcall helixel-textobj-action-function
                          'textobj ',name-sym))
               (helixel-ts--select-object ,name-str 'inside count))))
       ,@(when inner-move
           `((defun ,move-forward-inner-fn (count)
               ,(format "Move to inner end of current/next %s." name-str)
               (helixel-ts--inner-move ,name-str t count))
             (defun ,move-backward-inner-fn (count)
               ,(format "Move to inner start of current/previous %s." name-str)
               (helixel-ts--inner-move ,name-str nil count))))
       ,@(when outer-nav
           `((defun ,move-forward-outer-fn (count)
               ,(format "Move to next %s." name-str)
               (helixel-ts--outer-move ,name-str t count))
             (defun ,move-backward-outer-fn (count)
               ,(format "Move to previous %s." name-str)
               (helixel-ts--outer-move ,name-str nil count))))
       ;; ── Command wrappers (with tracking) ──
       ,@(when textobj
           `((helixel-define-command ,mark-a-cmd
                 (:category movement :subcat ,name-sym
                            :params (&optional count))
               ,(format "Select a %s using tree-sitter." name-str)
               (,select-around-fn (or count 1)))
             (helixel-define-command ,mark-inner-cmd
                 (:category movement :subcat ,name-sym
                            :params (&optional count))
               ,(format "Select inner %s using tree-sitter." name-str)
               (,select-inside-fn (or count 1)))))
       ,@(when inner-move
           `((helixel-define-command ,forward-inner-cmd
                 (:category movement :subcat ,name-sym
                            :params (&optional count))
               ,(format "Move to inner end of current/next %s." name-str)
               (,move-forward-inner-fn (or count 1)))
             (helixel-define-command ,backward-inner-cmd
                 (:category movement :subcat ,name-sym
                            :params (&optional count))
               ,(format "Move to inner start of current/previous %s." name-str)
               (,move-backward-inner-fn (or count 1)))))
       ,@(when outer-nav
           `((helixel-define-command ,forward-outer-cmd
                 (:category movement :subcat ,name-sym
                            :params (&optional count))
               ,(format "Move to next %s." name-str)
               (,move-forward-outer-fn (or count 1)))
             (helixel-define-command ,backward-outer-cmd
                 (:category movement :subcat ,name-sym
                            :params (&optional count))
               ,(format "Move to previous %s." name-str)
               (,move-backward-outer-fn (or count 1))))))))

;; ── Generate all type commands ──

(helixel-ts--define-type "function"
  :textobj t :inner-move t :outer-nav t)
(helixel-ts--define-type "class"
  :textobj t :inner-move t :outer-nav t)
(helixel-ts--define-type "parameter"
  :textobj t :inner-move t :outer-nav t)
(helixel-ts--define-type "loop"
  :textobj t :inner-move t :outer-nav t)
(helixel-ts--define-type "conditional"
  :textobj t :inner-move t :outer-nav t)

;; ── Comment: uses shared impls directly ──

(defun helixel-ts--select-comment-around (count)
  "Select a comment using tree-sitter.
With COUNT, select that many comments."
  (when helixel-textobj-action-function
    (funcall helixel-textobj-action-function 'textobj 'comment))
  (helixel-ts--select-object "comment" 'around count))

(defun helixel-ts--select-comment-inside (count)
  "Select inner comment using tree-sitter.
With COUNT, select that many comments."
  (when helixel-textobj-action-function
    (funcall helixel-textobj-action-function 'textobj 'comment))
  (helixel-ts--select-object "comment" 'inside count))

(defun helixel-ts--move-forward-outer-comment (count)
  "Move to next comment using tree-sitter.
With COUNT, repeat that many times."
  (helixel-ts--comment-move t count
                            (helixel--motion-select-category-p 'movement 'comment)))

(defun helixel-ts--move-backward-outer-comment (count)
  "Move to previous comment using tree-sitter.
With COUNT, repeat that many times."
  (helixel-ts--comment-move nil count
                            (helixel--motion-select-category-p 'movement 'comment)))

(defun helixel-ts--move-forward-inner-comment (count)
  "Move to inner end of next comment using tree-sitter.
With COUNT, repeat that many times."
  (helixel-ts--comment-move t count nil))

(defun helixel-ts--move-backward-inner-comment (count)
  "Move to inner start of previous comment using tree-sitter.
With COUNT, repeat that many times."
  (helixel-ts--comment-move nil count nil))

(helixel-define-command helixel-ts-mark-a-comment
    (:category movement :subcat comment
               :params (&optional count))
  "Select a comment using tree-sitter."
  (helixel-ts--select-comment-around (or count 1)))

(helixel-define-command helixel-ts-mark-inner-comment
    (:category movement :subcat comment
               :params (&optional count))
  "Select inner comment using tree-sitter."
  (helixel-ts--select-comment-inside (or count 1)))

;; ── Sibling navigation ──

(defun helixel-ts--sibling-move (forward-p count)
  "Move to next/prev sibling, COUNT times.
FORWARD-P non-nil moves to next sibling, nil to previous."
  (let ((n (or count 1)))
    (dotimes (_ n)
      (if-let* ((bounds (helixel-ts--sibling-bounds forward-p)))
          (helixel-ts--apply-sibling bounds)
        (user-error (if forward-p "No next sibling" "No previous sibling"))))))

(helixel-define-command helixel-ts-forward-outer-sibling
    (:category movement :subcat sibling
               :params (&optional count))
  "Move to next sibling node at same level."
  (helixel-ts--sibling-move t count))

(helixel-define-command helixel-ts-backward-outer-sibling
    (:category movement :subcat sibling
               :params (&optional count))
  "Move to previous sibling node at same level."
  (helixel-ts--sibling-move nil count))

;; ── Expand / Shrink ──

(helixel-define-command helixel-ts-grow-selection
    (:category movement :subcat grow-shrink
               :params (&optional count))
  "Expand selection to next outer treesit scope."
  (let ((n (or count 1)))
    (dotimes (_ n)
      (unless (helixel-ts--grow-selection)
        (user-error "Cannot expand selection further")))))

(helixel-define-command helixel-ts-shrink-selection
    (:category movement :subcat grow-shrink
               :params (&optional count))
  "Shrink selection to next inner treesit scope."
  (let ((n (or count 1)))
    (dotimes (_ n)
      (unless (helixel-ts--shrink-selection)
        (user-error "Cannot shrink selection further")))))

;; ── Comment command wrappers for direct keymap binding ──

(helixel-define-command helixel-ts-forward-outer-comment
    (:category movement :subcat comment
               :params (&optional count))
  "Move to next comment using tree-sitter."
  (helixel-ts--move-forward-outer-comment (or count 1)))

(helixel-define-command helixel-ts-backward-outer-comment
    (:category movement :subcat comment
               :params (&optional count))
  "Move to previous comment using tree-sitter."
  (helixel-ts--move-backward-outer-comment (or count 1)))

;; Note: inner-comment move commands use dispatch only;
;; no direct keymap wrappers needed since they are only
;; reached via {; and }; prefix maps.

(provide 'helixel-treesit-commands)
;;; helixel-treesit-commands.el ends here
