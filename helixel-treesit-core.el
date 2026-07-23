;;; helixel-treesit-core.el --- Tree-sitter foundation: queries, objects, index -*- lexical-binding: t; -*-

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
;; Foundation layer for tree-sitter integration in helixel-mode.
;;
;; Provides:
;;   - Readiness gates and node utilities
;;   - Query provider (evil-textobj-tree-sitter integration)
;;   - Capture normalization and object resolution
;;   - Index cache for O(1) lookup
;;   - Selection activation and kind registration
;;   - Type specification table (data-driven)
;;
;; Dependencies:
;;   `treesit' — soft (Emacs 29+ built-in).
;;   `evil-textobj-tree-sitter-core' — soft (query files for 151+ langs).

;;; Code:

(require 'treesit nil t)
(require 'helixel-core)

;; ----------------------------------------------------------------------
;; Forward declarations (cross-module)
;; ----------------------------------------------------------------------

(declare-function helixel--set-mark-region "helixel-core" t t)
(declare-function helixel--activate-textobj-range
                  "helixel-textobj-engine" t t)
(declare-function helixel-mc--make-target "helixel-mc-core" t t)
(defvar helixel-textobj-action-function)

;; ----------------------------------------------------------------------
;; Readiness & language detection
;; ----------------------------------------------------------------------

(defun helixel-ts-ready-p ()
  "Return non-nil when tree-sitter is usable in the current buffer."
  (and (fboundp 'treesit-available-p)
       (treesit-available-p)
       (fboundp 'treesit-parser-list)
       (treesit-parser-list)))

(defun helixel-ts--check-ready ()
  "Signal `user-error' when tree-sitter is not ready in current buffer.
The error message includes a hint about installing a tree-sitter
grammar and `evil-textobj-tree-sitter' for full support."
  (unless (helixel-ts-ready-p)
    (user-error
     (concat
      "No tree-sitter parser in this buffer.  "
      "Install a tree-sitter grammar for this language "
      "(e.g., `treesit-install-language-grammar') "
      "and `evil-textobj-tree-sitter' for text-object support."))))

(defun helixel-ts--language ()
  "Return tree-sitter language symbol for current buffer, or nil."
  (cond
   ((fboundp 'treesit-language-at)
    (treesit-language-at (point)))
   ((helixel-ts-ready-p)
    (let ((parsers (treesit-parser-list)))
      (and parsers
           (treesit-parser-language (car parsers)))))))

;; ----------------------------------------------------------------------
;; Node utilities
;; ----------------------------------------------------------------------

(defun helixel-ts--node-at-point ()
  "Return the named tree-sitter node at point, or nil."
  (when (helixel-ts-ready-p)
    (treesit-node-at (point) nil t)))

(defun helixel-ts--node->bounds (node)
  "Return NODE bounds as (BEG . END), or nil."
  (when node
    (cons (treesit-node-start node) (treesit-node-end node))))

(defun helixel-ts--named-parent (node)
  "Return nearest named parent of NODE, or nil."
  (when node
    (let ((p (treesit-node-parent node)))
      (while (and p (not (treesit-node-check p 'named)))
        (setq p (treesit-node-parent p)))
      p)))

(defun helixel-ts--node-matching-bounds (start end)
  "Return node whose bounds exactly match START..END, or nil."
  (when (and start end (helixel-ts-ready-p))
    (let ((n (treesit-node-at start nil nil)))
      (while (and n
                  (or (/= (treesit-node-start n) start)
                      (/= (treesit-node-end n) end)))
        (setq n (treesit-node-parent n)))
      n)))

;; ----------------------------------------------------------------------
;; Query provider (evil-textobj-tree-sitter integration)
;; ----------------------------------------------------------------------

(defun helixel-ts--evil-provider-available-p ()
  "Return non-nil when evil-textobj-tree-sitter can provide captures."
  (and (require 'evil-textobj-tree-sitter-core nil t)
       (fboundp 'evil-textobj-tree-sitter--treesit-get-nodes)))

(defun helixel-ts--lang-has-queries-p ()
  "Return non-nil if evil-textobj-tree-sitter has query files for this buffer."
  (and (require 'evil-textobj-tree-sitter-core nil t)
       (boundp 'evil-textobj-tree-sitter-major-mode-language-alist)
       (boundp 'evil-textobj-tree-sitter--get-queries-dir-func)
       (functionp evil-textobj-tree-sitter--get-queries-dir-func)
       (let* ((lang (alist-get major-mode
                               evil-textobj-tree-sitter-major-mode-language-alist))
              (dir (and lang
                        (funcall evil-textobj-tree-sitter--get-queries-dir-func))))
         (and lang dir
              (file-exists-p
               (expand-file-name "textobjects.scm"
                                 (expand-file-name lang dir)))))))

(defun helixel-ts--captures-available-p ()
  "Return non-nil if tree-sitter captures are available for this buffer."
  (and (helixel-ts-ready-p)
       (helixel-ts--evil-provider-available-p)
       (helixel-ts--lang-has-queries-p)))

(defun helixel-ts--evil-textobj-captures ()
  "Get captures via evil-textobj-tree-sitter."
  (declare-function evil-textobj-tree-sitter--treesit-get-nodes
                    "ext:evil-textobj-tree-sitter-core" t t)
  (require 'evil-textobj-tree-sitter-core)
  (evil-textobj-tree-sitter--treesit-get-nodes '()))

(defun helixel-ts--captures ()
  "Return all tree-sitter captures for current buffer.
Each element is (CAPTURE-SYMBOL START END).
Filters out separator/punctuation nodes."
  (helixel-ts--check-ready)
  (let ((result (and (helixel-ts--evil-provider-available-p)
                     (condition-case nil
                         (helixel-ts--evil-textobj-captures)
                       (error nil)))))
    (cl-remove-if
     (lambda (cap)
       (let ((pos (nth 1 cap)))
         (and (< pos (point-max))
              (memq (char-after pos) '(?, ?\; ?:)))))
     result)))

;; ----------------------------------------------------------------------
;; Capture normalization
;; ----------------------------------------------------------------------

(defun helixel-ts--capture->base-part (capture-sym)
  "Normalize CAPTURE-SYM to (BASE . PART).
PART is `around' for .outer/.around captures,
        `inside' for .inner/.inside captures.
Returns nil for span markers and unrecognised names."
  (let ((name (symbol-name capture-sym)))
    (cond
     ((string-suffix-p "_start" name) nil)
     ((string-suffix-p "_end" name) nil)
     ((string-suffix-p ".outer" name)
      (cons (substring name 0 -6) 'around))
     ((string-suffix-p ".around" name)
      (cons (substring name 0 -7) 'around))
     ((string-suffix-p ".inner" name)
      (cons (substring name 0 -6) 'inside))
     ((string-suffix-p ".inside" name)
      (cons (substring name 0 -7) 'inside))
     (t nil))))

;; ----------------------------------------------------------------------
;; Index cache
;; ----------------------------------------------------------------------

(defvar-local helixel-ts--index nil
  "Hash table mapping (BASE . PART) to sorted vector of (BEG . END).")

(defvar-local helixel-ts--index-tick -1
  "Value of `buffer-modified-tick' when index was last built.")

(defun helixel-ts--ensure-index ()
  "Build index from `helixel-ts--captures' if stale."
  (when (or (not helixel-ts--index)
            (/= helixel-ts--index-tick (buffer-modified-tick)))
    (let ((raw (helixel-ts--captures))
          (groups (make-hash-table :test #'equal)))
      (dolist (cap raw)
        (pcase-let* ((`(,sym ,beg ,end) cap)
                     (`(,base . ,part)
                      (helixel-ts--capture->base-part sym)))
          (when (and base
                     (or (not (eq part 'around))
                         (> (- end beg) 1)
                         (not (and (< beg (point-max))
                                   (memq (char-after beg)
                                         '(?, ?\; ?:))))))
            (push (cons beg end)
                  (gethash (cons base part) groups)))))
      (maphash (lambda (k v)
                 (puthash k (vconcat (cl-sort v #'< :key #'car)) groups))
               groups)
      (setq helixel-ts--index groups
            helixel-ts--index-tick (buffer-modified-tick))))
  helixel-ts--index)

(defun helixel-ts--next-after (base part pt)
  "First (BASE . PART) node after PT, or nil."
  (let ((vec (gethash (cons base part) (helixel-ts--ensure-index))))
    (cl-find-if (lambda (r) (> (car r) pt)) vec)))

(defun helixel-ts--prev-before (base part pt)
  "Last (BASE . PART) node before PT, or nil."
  (let ((vec (gethash (cons base part) (helixel-ts--ensure-index)))
        (best nil))
    (seq-doseq (r vec) (when (< (cdr r) pt) (setq best r)))
    best))

;; ----------------------------------------------------------------------
;; Object resolution
;; ----------------------------------------------------------------------

(defun helixel-ts--collect-matching-captures (captures base part pt)
  "Return (BEG . END) ranges from CAPTURES matching BASE,PART at PT."
  (let ((matching nil))
    (dolist (cap captures)
      (let* ((cap-sym (nth 0 cap))
             (start (nth 1 cap))
             (end (nth 2 cap))
             (bp (helixel-ts--capture->base-part cap-sym)))
        (when (and bp
                   (equal (car bp) base)
                   (eq (cdr bp) part)
                   (<= start pt)
                   (< pt end))
          (push (cons start end) matching))))
    matching))

(defun helixel-ts--find-first-inner-in-outer (captures base pt)
  "Return first inner capture within BASE outer node enclosing PT.
CAPTURES is the list from `helixel-ts--captures'.
BASE is the node type string, PT is the buffer position.
Returns (BEG . END) or nil."
  (let* ((outer-range
          (cl-some
           (lambda (cap)
             (let ((bp (helixel-ts--capture->base-part (nth 0 cap))))
               (and bp (equal (car bp) base)
                    (eq (cdr bp) 'around)
                    (<= (nth 1 cap) pt)
                    (< pt (nth 2 cap))
                    (cons (nth 1 cap) (nth 2 cap)))))
           captures)))
    (when outer-range
      (let ((candidates nil))
        (dolist (cap captures)
          (let ((bp (helixel-ts--capture->base-part (nth 0 cap))))
            (when (and bp (equal (car bp) base)
                       (eq (cdr bp) 'inside)
                       (>= (nth 1 cap) pt)
                       (>= (nth 1 cap) (car outer-range))
                       (<= (nth 2 cap) (cdr outer-range)))
              (push (cons (nth 1 cap) (nth 2 cap)) candidates))))
        (when candidates
          (setq candidates
                (sort candidates
                      (lambda (a b) (< (car a) (car b)))))
          (car candidates))))))

(defun helixel-ts--object-at (base part &optional level no-fallback)
  "Return (BEG . END) for LEVEL-th enclosing BASE object at point.
BASE is a string (\"function\", \"class\", ...).
PART is `around' or `inside'.
LEVEL defaults to 0 (innermost).
When NO-FALLBACK is nil, falls back to (1- (point)) at boundaries.
For `inside': when point is on an outer header, finds first inner within."
  (let* ((vec (gethash (cons base part) (helixel-ts--ensure-index)))
         (pt (point))
         (matching nil))
    ;; Collect matches from the pre-built index (O(n) over index size).
    (when vec
      (dotimes (i (length vec))
        (let ((r (aref vec i)))
          (when (and (<= (car r) pt) (< pt (cdr r)))
            (push r matching)))))
    ;; Boundary fallback: check (1- pt).
    (unless (or matching no-fallback)
      (let ((pt-1 (max (point-min) (1- pt))))
        (when vec
          (dotimes (i (length vec))
            (let ((r (aref vec i)))
              (when (and (<= (car r) pt-1) (< pt-1 (cdr r)))
                (push r matching)))))))
    ;; For `inside' with no match yet, try finding inner within outer.
    ;; Falls back to full captures (expensive, but rare edge case).
    (when (and (not matching) (eq part 'inside))
      (when-let* ((inner (helixel-ts--find-first-inner-in-outer
                          (helixel-ts--captures) base pt)))
        (push inner matching)))
    ;; Sort by width (narrowest first), deduplicate, pick LEVEL-th.
    (setq matching (cl-sort matching
                            (lambda (a b) (< (- (cdr a) (car a))
                                             (- (cdr b) (car b))))))
    (let ((seen nil) (uniq nil))
      (dolist (m matching)
        (unless (member m seen)
          (push m seen) (push m uniq)))
      (setq matching (nreverse uniq)))
    (or (nth (or level 0) matching)
        (and (equal base "comment") (eq part 'inside)
             (helixel-ts--object-at base 'around level no-fallback)))))

;; ----------------------------------------------------------------------
;; Selection activation
;; ----------------------------------------------------------------------

(defun helixel-ts--parameter-outer-bounds (beg end)
  "Return parameter outer bounds expanded around BEG..END.
Includes trailing comma+whitespace, excludes leading separator."
  (save-excursion
    (goto-char end)
    (skip-chars-forward " \t\n\r\f")
    (if (eq (char-after) ?,)
        (progn
          (forward-char 1)
          (skip-chars-forward " \t\n\r\f")
          (cons beg (point)))
      (cons beg end))))

(defun helixel-ts--normalize-selection-bounds (beg end base part)
  "Return normalized selection bounds for BEG END BASE PART."
  (if (and (equal base "parameter") (eq part 'around))
      (helixel-ts--parameter-outer-bounds beg end)
    (cons beg end)))

(defun helixel-ts--activate-selection (beg end base part
                                           &optional level count)
  "Activate region [BEG, END) as a treesit selection.
BASE is object name, PART is `around'/`inside'.
LEVEL is nesting level, COUNT is selection count."
  (let ((node-beg beg)
        (node-end end)
        (bounds (helixel-ts--normalize-selection-bounds
                 beg end base part)))
    (setq beg (car bounds)
          end (cdr bounds))
    (push-mark beg nil t)
    (goto-char end)
    (helixel--set-mark-region (cons beg end))
    (let* ((n (or count 1))
           (prev helixel--pending-sel)
           (total-n
            (if (and prev
                     (eq (helixel-sel-kind prev) 'treesit)
                     (equal (helixel-sel-field prev :base) base)
                     (eq (helixel-sel-field prev :part) part))
                (+ (helixel-sel-field prev :count) n)
              n)))
      (helixel--sel-push
       (helixel-sel-create
        'treesit `(:base ,base :part ,part :level ,(or level 0)
                         :start ,node-beg :end ,node-end
                         :count ,total-n :inline-advance t))))))

;; ----------------------------------------------------------------------
;; Kind registration
;; ----------------------------------------------------------------------

(cl-defstruct (helixel-treesit-sel (:include helixel-sel)
                                   (:copier nil))
  "Tree-sitter text-object selection.
Slots: BASE, PART, LEVEL, COUNT, QUERY, START, END, COMMAND."
  base part level count query start end command)

(cl-defmethod helixel-sel--construct ((_kind (eql treesit)) ctx)
  "Construct the sel struct from ctx plist CTX."
  (make-helixel-treesit-sel
   :base (plist-get ctx :base)
   :part (plist-get ctx :part)
   :level (plist-get ctx :level)
   :count (plist-get ctx :count)
   :query (plist-get ctx :query)
   :start (plist-get ctx :start)
   :end (plist-get ctx :end)
   :command (plist-get ctx :command)))

(cl-defmethod helixel-sel-type ((_sel helixel-treesit-sel))
  "Sel type method for SEL."
  'treesit)

(cl-defmethod helixel-sel--to-plist ((sel helixel-treesit-sel))
  "Sel  to plist method for SEL."
  (list :base (helixel-treesit-sel-base sel)
        :part (helixel-treesit-sel-part sel)
        :level (helixel-treesit-sel-level sel)
        :count (helixel-treesit-sel-count sel)
        :query (helixel-treesit-sel-query sel)
        :start (helixel-treesit-sel-start sel)
        :end (helixel-treesit-sel-end sel)
        :command (helixel-treesit-sel-command sel)))

(cl-defmethod helixel-sel-recreate ((sel helixel-treesit-sel))
  "Sel recreate method for SEL."
  (helixel-ts--recreate sel))

(cl-defmethod helixel-sel-advance-fn ((_sel helixel-treesit-sel))
  "Sel advance fn method for SEL."
  #'helixel-ts--advance-by-recreate)

(cl-defmethod helixel-sel-display ((sel helixel-treesit-sel))
  "Sel display method for SEL."
  (format "%s(%s)" (helixel-treesit-sel-base sel)
          (if (eq (helixel-treesit-sel-part sel) 'around) "a" "i")))

(cl-defmethod helixel-sel-region-type ((_sel helixel-treesit-sel))
  "Sel region type method for SEL."
  'textobj)

(defun helixel-ts--recreate (sel)
  "Recreate a treesit selection from SEL."
  (let* ((base (helixel-treesit-sel-base sel))
         (part (helixel-treesit-sel-part sel))
         (level (or (helixel-treesit-sel-level sel) 0))
         (range (helixel-ts--object-at base part level)))
    (when range
      (helixel-ts--activate-selection
       (car range) (cdr range) base part level))))

(defun helixel-ts--advance-by-recreate (tx)
  "Advance past current target by recreating TX's selection.
Returns t on success, nil when no more targets."
  (let ((sel (helixel-action-sel tx)))
    (when sel
      (let ((saved-region-beg (when (use-region-p)
                                (region-beginning))))
        ;; Step past the previous target so we don't re-select it.
        (if (use-region-p)
            (progn
              (goto-char (region-end))
              (skip-chars-forward " \t\n\r\f,;:"))
          (when-let* ((base (helixel-sel-field sel :base))
                      (part (helixel-sel-field sel :part))
                      (range (helixel-ts--object-at
                              base part 0))
                      ;; Only skip past if point is still inside the
                      ;; current target; after deletion point is
                      ;; already past it (text is gone).
                      ((< (point) (cdr range))))
            (goto-char (cdr range))
            (skip-chars-forward " \t\n\r\f,;:")))
        ;; After stepping past, if point is NOT inside any target
        ;; (e.g. after deletion left us at a position where the index
        ;; has no enclosing node), find the next capture and jump to
        ;; its start so `helixel-ts--recreate' can find it.
        (unless (and (helixel-sel-field sel :base)
                     (helixel-sel-field sel :part)
                     (helixel-ts--object-at
                      (helixel-sel-field sel :base)
                      (helixel-sel-field sel :part) 0))
          (when-let* ((base (helixel-sel-field sel :base))
                      (next (helixel-ts--next-capture
                             base (point) t)))
            (goto-char (car next))))
        (condition-case nil
            (progn
              (helixel--recreate-selection sel)
              (and (use-region-p)
                   (or (not saved-region-beg)
                       (> (region-beginning) saved-region-beg))))
          (error nil))))))

;; ----------------------------------------------------------------------
;; Multi-cursor spawn (bulk target collection for s s / mc-toggle)
;; ----------------------------------------------------------------------

(defun helixel-ts--mc-spawn (sel)
  "Spawn fake cursors for every treesit object matching SEL.
SEL must be a \=`treesit\=' selection with :base and :part in its
ctx.  Uses the pre-built index cache (`helixel-ts--ensure-index')
for O(n) single-pass iteration — faster and more reliable than
the walk-advance fallback.

Containment filtering: when one entry fully contains another
\(e.g. an outer function wrapping an inner one), only the
innermost is kept.  This matches \=`maf\=' semantics —
\=`maf\=' selects the innermost enclosing function at point, so
spawning from that selection should produce cursors at similar
innermost positions throughout the buffer.  Duplicate ranges are
also collapsed to a single target.

The reverse-pass algorithm is O(n): iterate from last to first,
tracking the minimum end position of all kept entries.  An entry
whose `end' ≥ that minimum is a superset (or duplicate) and is
skipped.

Returns a list of (POINT . MARK) marker pairs suitable for
`helixel-mc--realize-targets'.  Each cursor has mark at the
object start and point at the object end — matching the
direction that \=`maf\=' / \=`mif\=' leaves."
  (let* ((ctx (helixel-sel-ctx sel))
         (base (plist-get ctx :base))
         (part (plist-get ctx :part))
         (min-end most-positive-fixnum)
         (targets nil))
    (unless (and base part)
      (user-error "Treesit selection missing :base or :part"))
    (let ((vec (gethash (cons base part) (helixel-ts--ensure-index))))
      (unless vec
        (user-error "No treesit objects of type %s(%s) in buffer"
                    base part))
      ;; Reverse pass: keep only non-superset entries.
      ;; The index is sorted by beg.  Iterating from last to first
      ;; with a running min-end lets us detect containment in one
      ;; pass: if current.end ≥ min-end, current contains (or
      ;; duplicates) some later entry → skip it.
      (cl-loop for i from (1- (length vec)) downto 0
               for r = (aref vec i)
               for beg = (car r)
               for end = (cdr r)
               unless (>= end min-end)
               do (push (helixel-mc--make-target end beg) targets)
               (setq min-end end)))
    (unless targets
      (user-error "No non-overlapping treesit targets"))
    targets))

(cl-defmethod helixel-mc-spawn-fn ((_sel helixel-treesit-sel))
  "Mc spawn fn method for SEL."
  #'helixel-ts--mc-spawn)

;; ----------------------------------------------------------------------
;; Type specification table
;; ----------------------------------------------------------------------

(defconst helixel-ts--type-specs
  '((function
     :textobj t
     :inner-move t
     :outer-nav t)
    (class
     :textobj t
     :inner-move t
     :outer-nav t)
    (parameter
     :textobj t
     :inner-move t
     :outer-nav t)
    (loop
     :textobj t
     :inner-move t
     :outer-nav t)
    (conditional
     :textobj t
     :inner-move t
     :outer-nav t)
    (comment
     :textobj t
     :inner-move t
     :outer-nav t))
  "Type specifications for tree-sitter semantic objects.
Each entry is (TYPE-NAME . PLIST) where PLIST keys are:
  :textobj       — generate mark-inner-/mark-a- commands
  :inner-move    — generate backward/forward-inner- commands
  :outer-nav     — generate backward/forward-outer- nav + dispatch vars")

;; ----------------------------------------------------------------------
;; Tree walking (for expand/shrink and sibling nav)
;; ----------------------------------------------------------------------

(defun helixel-ts--parent-range (beg end)
  "AST parent bounds of node covering BEG..END, or nil."
  (when (helixel-ts-ready-p)
    (when-let* ((lang (helixel-ts--language))
                (root (treesit-buffer-root-node lang)))
      (let* ((node (or (treesit-node-descendant-for-range root beg (1+ beg))
                       (treesit-node-descendant-for-range root beg end)))
             (anc node) (result nil))
        (while (and anc (not result))
          (let ((parent (helixel-ts--named-parent anc)))
            (when parent
              (let ((pb (treesit-node-start parent))
                    (pe (treesit-node-end parent)))
                (when (or (< pb beg) (> pe end))
                  (setq result (cons pb pe))))
              (setq anc parent))
            (unless parent (setq anc nil))))
        result))))

(defun helixel-ts--enclosing-node (base pt)
  "Return (START . END) of innermost BASE node enclosing PT."
  (let ((vec (gethash (cons base 'around) (helixel-ts--ensure-index)))
        (best nil) (best-width most-positive-fixnum))
    (when vec
      (dotimes (i (length vec))
        (let ((r (aref vec i)))
          (when (and (<= (car r) pt) (<= pt (cdr r)))
            (let ((w (- (cdr r) (car r))))
              (when (< w best-width)
                (setq best r best-width w)))))))
    best))

(defun helixel-ts--sibling-from-node (node forward-p depth)
  "Find NODE's sibling, ascending up to 6 levels if needed.
FORWARD-P non-nil for next sibling, nil for previous.
DEPTH guards against infinite recursion."
  (when (and node (< depth 6))
    (let* ((parent (helixel-ts--named-parent node))
           (count (and parent (treesit-node-child-count parent t)))
           (my-start (treesit-node-start node)) (my-index nil))
      (when parent
        (dotimes (i count)
          (let ((c (treesit-node-child parent i t)))
            (when (and c (= (treesit-node-start c) my-start))
              (setq my-index i))))
        (when (null my-index)
          (let ((anc node))
            (while (and anc (null my-index))
              (dotimes (i count)
                (let ((c (treesit-node-child parent i t)))
                  (when (and c (= (treesit-node-start c)
                                  (treesit-node-start anc)))
                    (setq my-index i))))
              (setq anc (helixel-ts--named-parent anc)))))
        (if my-index
            (let ((target (if forward-p (1+ my-index) (1- my-index))))
              (if (and (>= target 0) (< target count))
                  (let ((sib (treesit-node-child parent target t)))
                    (when sib (cons (treesit-node-start sib)
                                    (treesit-node-end sib))))
                (helixel-ts--sibling-from-node
                 parent forward-p (1+ depth))))
          (helixel-ts--sibling-from-node
           parent forward-p (1+ depth)))))))

(defun helixel-ts--sibling-range (beg end forward-p)
  "Return sibling bounds of node at BEG..END.
FORWARD-P non-nil finds the next sibling, nil finds the previous.
Ascends to parent level if no sibling found."
  (when (helixel-ts-ready-p)
    (when-let* ((node (or (helixel-ts--node-matching-bounds beg end)
                          (treesit-node-at beg nil t)
                          (treesit-node-at beg nil nil))))
      (helixel-ts--sibling-from-node node forward-p 0))))

;; ----------------------------------------------------------------------
;; Navigation bounds helper
;; ----------------------------------------------------------------------

(defun helixel-ts--nav-bounds (base forward-p)
  "Return boundary-aware navigation bounds for BASE.
FORWARD-P non-nil moves forward; nil moves backward.
When point is at a boundary AND a next/prev node exists, advances.
Otherwise returns the current enclosing node."
  (let* ((pt (point))
         (current (helixel-ts--enclosing-node base pt)))
    (if (null current)
        (or (helixel-ts--next-node-of-type base forward-p)
            current)
      (let ((start (car current))
            (end (cdr current)))
        (if forward-p
            (if (= pt end)
                (or (helixel-ts--next-node-of-type base t)
                    current)
              current)
          (if (= pt start)
              (or (helixel-ts--next-node-of-type base nil)
                  current)
            current))))))

(defun helixel-ts--next-node-of-type (base forward-p)
  "Return (BEG . END) of next (or previous) node of type BASE.
FORWARD-P non-nil finds next node; nil finds previous."
  (helixel-ts--check-ready)
  (if forward-p
      (helixel-ts--next-after base 'around (point))
    (helixel-ts--prev-before base 'around (point))))

;; ----------------------------------------------------------------------
;; Nearest-forward (for initial selection from bol)
;; ----------------------------------------------------------------------

(defun helixel-ts--nearest-forward (base part)
  "Return (BEG . END) of nearest BASE object at or after point.
For PART=`inside': finds outer then innermost inner within."
  (let ((nearest-outer (helixel-ts--next-capture base (point) t)))
    (when nearest-outer
      (if (eq part 'around)
          nearest-outer
        (let* ((captures (helixel-ts--captures))
               (inner-caps nil))
          (dolist (cap captures)
            (let ((bp (helixel-ts--capture->base-part (nth 0 cap))))
              (when (and bp (equal (car bp) base)
                         (eq (cdr bp) 'inside)
                         (>= (nth 1 cap) (car nearest-outer))
                         (<= (nth 2 cap) (cdr nearest-outer)))
                (push (cons (nth 1 cap) (nth 2 cap)) inner-caps))))
          (if inner-caps
              (progn
                (setq inner-caps
                      (sort inner-caps
                            (lambda (a b) (< (- (cdr a) (car a))
                                             (- (cdr b) (car b))))))
                (car inner-caps))
            (and (equal base "comment") nearest-outer)))))))

(defun helixel-ts--next-capture (base start-pos forward-p)
  "Return (BEG . END) of next outer capture matching BASE.
START-POS is the reference position.
FORWARD-P non-nil for next, nil for previous."
  (if forward-p
      (helixel-ts--next-after base 'around start-pos)
    (helixel-ts--prev-before base 'around start-pos)))

;; ----------------------------------------------------------------------
;; Public API: user-facing textobj factory
;; ----------------------------------------------------------------------

(defun helixel-get-tree-sitter-textobj (group &optional query)
  "Return a command for a tree-sitter text object of GROUP.
GROUP is a string like \"function.inner\" or a list thereof.
QUERY is an optional alist mapping major-mode to custom query strings.
Requires `evil-textobj-tree-sitter' to be installed."
  (when (or (featurep 'evil-textobj-tree-sitter-core)
            (require 'evil-textobj-tree-sitter-core nil t))
    (declare-function evil-textobj-tree-sitter--range
                      "ext:evil-textobj-tree-sitter-core" t t)
    (declare-function evil-textobj-tree-sitter--message-not-found
                      "ext:evil-textobj-tree-sitter-core" t t)
    (let* ((groups (if (listp group) group (list group)))
           (interned-groups (mapcar #'intern groups)))
      (lambda (&optional count)
        (interactive "p")
        (when helixel-textobj-action-function
          (funcall helixel-textobj-action-function 'textobj 'treesit))
        (let ((range (evil-textobj-tree-sitter--range
                      count interned-groups query)))
          (if range
              (helixel--activate-textobj-range range nil count 'treesit)
            (evil-textobj-tree-sitter--message-not-found groups)))))))

(provide 'helixel-treesit-core)
;;; helixel-treesit-core.el ends here
