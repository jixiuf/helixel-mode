;;; helixel-core.el --- Core data layer for helixel-mode -*- lexical-binding: t; -*-

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
;;
;; Core data layer for helixel-mode — the single foundation module.
;;
;; This file defines the core data types and registries consumed by
;; all helixel modules.  It has ZERO dependencies on other helixel
;; modules and NO side effects.
;;
;; Contents:
;;   Part 1 — helixel-sel          : selection descriptor + pending-sel
;;   Part 2 — Delimiter Protocol   : delimiter plist accessors
;;   Part 3 — Kind Registry        : centralised kind protocol
;;   Part 4 — helixel-event        : unified event struct
;;   Part 5 — Transaction helpers  : make-tx, copy-tx, tx-display, etc.
;;   Part 6 — Operator Registry    : hash-table based op registration
;;   Part 7 — Swap-source type     : helper for editing and swap modules

;;; Code:

(require 'cl-lib)

;; ----------------------------------------------------------------------
;; Part 1 — helixel-sel: Selection Descriptor
;; ----------------------------------------------------------------------

(cl-defstruct (helixel-sel (:conc-name helixel-sel--)
                           (:constructor helixel-sel--internal)
                           (:copier helixel-sel--shallow-copy))
  "Selection descriptor for dot-repeat.
KIND is a symbol identifying the selection type.
CTX is a plist of mutable extra data (:count, :dir, :moves, ...).
Protocol methods (recreate, advance, display) are looked up from
the kind registry via `helixel-register-kind'."
  kind
  ctx)

;; ── CTX schema ──
;;
;; Each selection kind uses a specific subset of ctx keys.
;; This table is the single source of truth for valid ctx keys per kind.
;; Recreate functions (in their respective modules) are the sole consumers.
;;
;; Kind                      CTX keys                     Setter(s)
;; ----                      ------                       ---------
;; line                      :dir    (forward|backward)   movement cmd
;;                           :count  (integer ≥ 1)         same
;; rect                      :count  (integer ≥ 1)         movement cmd
;; movement                  :moves  ((CMD . COUNT) ...)   visual move fns
;;                           :inline-advance  t             same
;; textobj                   :command  (symbol)            textobj fns
;;                           :count    (integer)            same
;;                           :delimiter (plist)             same
;;                           :inline-advance  t             same
;; search                    :pattern  (string)            search fns
;;                           :dir      (forward|backward)   same
;; find-char                 :char     (character)          find-char fns
;;                           :type     (next|till)           same
;;                           :dir      (forward|backward)    same
;;                           :inline-advance  t              same
;; surround                  :delimiter (plist)            surround fns
;; insert-selection-start    :cursor-offset (int|nil)      insert-exit
;; insert-selection-end      :cursor-offset (int|nil)      insert-exit
;; insert-beginning-line     (none)                        —
;; insert-end-line           (none)                        —
;; insert-search-offset      :offset (integer)             insert cmd
;;
;; All kinds accept an optional :inline-advance flag.
;; When t, the advance function creates the region as part
;; of its positioning (movement, textobj, find-char).
;; The strategy reads this flag to avoid double-recreating.

;; ── CTX schema validation ──
;;
;; `helixel--ctx-schema' is the machine-readable counterpart to the
;; comment table above.  `helixel--validate-ctx' checks a (kind . ctx-plist)
;; pair against this schema.  It never runs in production — gated by
;; `helixel--ctx-validation-enabled'.

(defvar helixel--ctx-schema
  '((line         :required (:count :dir) :optional (:entry-kind :span))
    (rect         :required (:count) :optional ())
    (movement     :required (:moves)
                  :optional (:inline-advance :normal-mode))
    (textobj      :required (:command :count :delimiter)
                  :optional (:inline-advance))
    (search       :required (:pattern :dir)
                  :optional (:entry-kind :n-count :cursor-offset))
    (find-char    :required (:char :type :dir)
                  :optional (:inline-advance))
    (surround     :required (:delimiter) :optional ())
    (insert-selection-start
     :required () :optional (:cursor-offset :entry-kind))
    (insert-selection-end
     :required () :optional (:cursor-offset :entry-kind))
    (insert-beginning-line   :required () :optional ())
    (insert-end-line         :required () :optional ())
    (insert-search-offset    :required (:offset) :optional ()))
  "Per-kind schema: (KIND :required (KEYS…) :optional (KEYS…)).
Must match the CTX schema comment table exactly.")

(defvar helixel--ctx-validation-enabled nil
  "When non-nil, `helixel--validate-ctx' checks ctx against the schema.
Enabled during `make lint' and in test suites.
Never set in production — ctx are validated at author time only.")

(defun helixel--validate-ctx (kind ctx-plist)
  "Validate CTX-PLIST against the schema for KIND.
Returns t if valid.  When `helixel--ctx-validation-enabled' is nil,
returns t immediately (no-op).

Checks:
  1. All :required keys present in CTX-PLIST.
  2. No keys outside the union of :required and :optional.
Signals `helixel-ctx-error' on mismatch with details."
  (or (not helixel--ctx-validation-enabled)
      (let ((entry (assq kind helixel--ctx-schema)))
        (unless entry
          (signal 'helixel-ctx-error
                  (list (format "Unknown kind: %s" kind))))
        (let* ((spec (cdr entry))
               (required (plist-get spec :required))
               (optional (plist-get spec :optional))
               (allowed (append required optional)))
          (dolist (key required)
            (unless (plist-member ctx-plist key)
              (signal 'helixel-ctx-error
                      (list (format "Kind %s: missing required key :%s"
                                    kind key)))))
          (cl-loop for (k _v) on ctx-plist by #'cddr
                   unless (memq k allowed)
                   do (signal 'helixel-ctx-error
                              (list (format
                                     "Kind %s: unknown key :%s in ctx"
                                     kind k))))
          t))))

(defun helixel-sel-create (kind ctx &rest _)
  "Create a `helixel-sel' struct for selection KIND with data CTX.
All protocol methods (recreate, advance, display) are looked up
from the kind registry.  Extra args accepted for legacy callers.
When `helixel--ctx-validation-enabled' is non-nil, validates CTX
against the schema for KIND."
  (when helixel--ctx-validation-enabled
    (helixel--validate-ctx kind ctx))
  (helixel-sel--internal :kind kind :ctx ctx))

;; ── Span extension helper ──

(defmacro helixel--with-span (ctx &rest body)
  "Execute BODY with `:span' region extension.
If CTX plist has `:span', captures point before BODY
as the span origin and extends the mark back to it after BODY.
For `;' + `.' repeating the full session-start-to-point span."
  (declare (indent 1))
  `(let ((span-origin (when (plist-get ,ctx :span) (point))))
     (prog1 (progn ,@body)
       (when span-origin
         (push-mark span-origin t t)))))

;; ── Core accessors ──

(defun helixel-sel-call-recreate (sel)
  "Recreate selection described by SEL, looking up from kind registry."
  (when (helixel-sel-p sel)
    (when-let* ((fn (helixel--kind-recreate (helixel-sel--kind sel))))
      (funcall fn (helixel-sel--ctx sel)))))

(defun helixel-sel-call-display (sel)
  "Return display string for SEL, from kind registry."
  (when (helixel-sel-p sel)
    (let ((d (helixel--kind-display (helixel-sel--kind sel))))
      (if (functionp d)
          (funcall d (helixel-sel--ctx sel))
        (or d (symbol-name (helixel-sel--kind sel)))))))

(defun helixel-sel-kind (sel)
  "Return the :kind from `helixel-sel' struct SEL."
  (when (helixel-sel-p sel)
    (helixel-sel--kind sel)))

(defun helixel-sel-advance (sel)
  "Return the advance function for SEL from the kind registry."
  (when (helixel-sel-p sel)
    (helixel--kind-advance (helixel-sel--kind sel))))

(defun helixel-sel-ctx (sel)
  "Return the CTX (data plist) from `helixel-sel' struct SEL."
  (when (helixel-sel-p sel)
    (helixel-sel--ctx sel)))

(defun helixel-sel-field (sel key)
  "Get KEY from `helixel-sel' struct SEL's ctx.
Returns nil if SEL is nil."
  (when sel
    (plist-get (helixel-sel-ctx sel) key)))

(defun helixel-sel-count (sel)
  "Return :count from `helixel-sel' struct SEL's ctx, or 0 if absent.
Returns 0 if SEL is nil."
  (if (null sel) 0
    (or (plist-get (helixel-sel-ctx sel) :count) 0)))

(defun helixel-sel-equal-p (s1 s2)
  "Return non-nil if S1 and S2 represent the same selection.
Compares kind and ctx.  Returns t when both are nil."
  (if (or (null s1) (null s2))
      (eq s1 s2)
    (and (eq (helixel-sel-kind s1) (helixel-sel-kind s2))
         (equal (helixel-sel-ctx s1) (helixel-sel-ctx s2)))))

(defun helixel-sel-update-ctx (sel key value)
  "Return a new `helixel-sel' struct from SEL with CTX updated.
Sets KEY to VALUE in the ctx plist."
  (if (helixel-sel-p sel)
      (helixel-sel--internal
       :kind (helixel-sel--kind sel)
       :ctx (plist-put (copy-sequence (helixel-sel--ctx sel))
                       key value))
    sel))

;; ── Kind-specific ctx accessors ──
;;
;; Each function takes either a `helixel-sel' struct or a raw ctx
;; plist (for use inside recreate closures).  These are the preferred
;; way to read ctx fields; they document the valid keys per kind
;; through their names.  See the CTX schema table above for details.

(defsubst helixel-sel--ctx-ensure (obj)
  "If OBJ is a `helixel-sel' struct, return its ctx; else return OBJ."
  (if (helixel-sel-p obj) (helixel-sel--ctx obj) obj))

;;;; line

(defsubst helixel-sel-line-dir (obj)
  "Return :dir from line ctx (\=`forward' or \=`backward'), default \=`forward'.
OBJ is a `helixel-sel' struct or raw ctx plist."
  (or (plist-get (helixel-sel--ctx-ensure obj) :dir) 'forward))

(defsubst helixel-sel-line-count (obj)
  "Return :count from line ctx, default 1.
OBJ is a `helixel-sel' struct or raw ctx plist."
  (or (plist-get (helixel-sel--ctx-ensure obj) :count) 1))

;;;; rect

(defsubst helixel-sel-rect-count (obj)
  "Return :count from rect ctx, default 1.
OBJ is a `helixel-sel' struct or raw ctx plist."
  (or (plist-get (helixel-sel--ctx-ensure obj) :count) 1))

;;;; movement

(defsubst helixel-sel-movement-moves (obj)
  "Return :moves list from movement ctx ((CMD . COUNT) ...).
OBJ is a `helixel-sel' struct or raw ctx plist."
  (plist-get (helixel-sel--ctx-ensure obj) :moves))

(defsubst helixel-sel-movement-inline-advance-p (obj)
  "Return non-nil if movement ctx has :inline-advance set.
OBJ is a `helixel-sel' struct or raw ctx plist."
  (plist-get (helixel-sel--ctx-ensure obj) :inline-advance))

(defsubst helixel-sel-movement-normal-mode-p (obj)
  "Return non-nil if movement was recorded in normal mode.
When set, each movement command resets the selection during
dot-repeat replay (only the final target is selected).
OBJ is a `helixel-sel' struct or raw ctx plist."
  (plist-get (helixel-sel--ctx-ensure obj) :normal-mode))

;;;; textobj

(defsubst helixel-sel-textobj-command (obj)
  "Return :command (symbol) from textobj ctx.
OBJ is a `helixel-sel' struct or raw ctx plist."
  (plist-get (helixel-sel--ctx-ensure obj) :command))

(defsubst helixel-sel-textobj-count (obj)
  "Return :count from textobj ctx, default 1.
OBJ is a `helixel-sel' struct or raw ctx plist."
  (or (plist-get (helixel-sel--ctx-ensure obj) :count) 1))

(defsubst helixel-sel-textobj-delimiter (obj)
  "Return :delimiter (plist) from textobj ctx.
OBJ is a `helixel-sel' struct or raw ctx plist."
  (plist-get (helixel-sel--ctx-ensure obj) :delimiter))

;;;; search

(defsubst helixel-sel-search-pattern (obj)
  "Return :pattern (string) from search ctx.
OBJ is a `helixel-sel' struct or raw ctx plist."
  (plist-get (helixel-sel--ctx-ensure obj) :pattern))

(defsubst helixel-sel-search-dir (obj)
  "Return :dir from search ctx, default \=`forward'.
OBJ is a `helixel-sel' struct or raw ctx plist."
  (or (plist-get (helixel-sel--ctx-ensure obj) :dir) 'forward))

(defsubst helixel-sel-search-entry-kind (obj)
  "Return :entry-kind (insert or append) from search ctx, or nil.
OBJ is a `helixel-sel' struct or raw ctx plist."
  (plist-get (helixel-sel--ctx-ensure obj) :entry-kind))

(defsubst helixel-sel-search-cursor-offset (obj)
  "Return :cursor-offset (integer) from search ctx, or nil.
OBJ is a `helixel-sel' struct or raw ctx plist."
  (plist-get (helixel-sel--ctx-ensure obj) :cursor-offset))

;;;; find-char

(defsubst helixel-sel-find-char-dir (obj)
  "Return :dir (`forward' or `backward') from find-char ctx.
OBJ is a `helixel-sel' struct or raw ctx plist."
  (or (plist-get (helixel-sel--ctx-ensure obj) :dir) 'forward))

(defsubst helixel-sel-find-char-type (obj)
  "Return :type (`next' or `till') from find-char ctx.
OBJ is a `helixel-sel' struct or raw ctx plist."
  (plist-get (helixel-sel--ctx-ensure obj) :type))

(defsubst helixel-sel-find-char-char (obj)
  "Return :char (character) from find-char ctx.
OBJ is a `helixel-sel' struct or raw ctx plist."
  (plist-get (helixel-sel--ctx-ensure obj) :char))

;;;; surround

(defsubst helixel-sel-surround-delimiter (obj)
  "Return :delimiter (plist) from surround ctx.
OBJ is a `helixel-sel' struct or raw ctx plist."
  (plist-get (helixel-sel--ctx-ensure obj) :delimiter))

;;;; insert-search-offset

(defsubst helixel-sel-insert-offset (obj)
  "Return :offset (integer) from insert-search-offset ctx.
OBJ is a `helixel-sel' struct or raw ctx plist."
  (plist-get (helixel-sel--ctx-ensure obj) :offset))

;;;; insert-selection-start / insert-selection-end

(defsubst helixel-sel-insert-cursor-offset (obj)
  "Return :cursor-offset (integer) from insert ctx, or nil.
OBJ is a `helixel-sel' struct or raw ctx plist."
  (plist-get (helixel-sel--ctx-ensure obj) :cursor-offset))


;; ----------------------------------------------------------------------
;; Pending selection (selection-first protocol)
;; ----------------------------------------------------------------------
;;
;; Helixel is selection-first: selection commands push a `helixel-sel'
;; descriptor; the next editing command pops and consumes it.
;; Pairs with `helixel--pending-op' defined in helixel-state.el.

(defvar-local helixel--pending-sel nil
  "The pending selection descriptor (`helixel-sel' struct or nil).
Set by selection commands (w, b, e, iw, aw, line, rect, search,
find-char, textobj).  Consumed by operator commands (d, c, y).")

(defsubst helixel--sel-push (sel)
  "Push SEL onto the pending-selection stack.
Selection commands call this; editing commands consume via
`helixel--sel-pop'."
  (setq helixel--pending-sel sel))

(defsubst helixel--sel-pop ()
  "Pop and return the pending selection, or nil.
Editing commands call this to consume the selection set by the
previous selection command."
  (prog1 helixel--pending-sel
    (setq helixel--pending-sel nil)))

;; ── Convenience: push a freshly created selection ──

(defun helixel--push-selection (kind ctx &rest _)
  "Create a `helixel-sel' of KIND with CTX and push as pending selection.
Extra args accepted for legacy callers.  Returns the created sel."
  (let ((sel (helixel-sel-create kind ctx)))
    (helixel--sel-push sel)
    sel))


;; ----------------------------------------------------------------------
;; Part 2 — Delimiter Protocol
;; ----------------------------------------------------------------------
;;
;; A delimiter plist describes a delimited region (pair of brackets,
;; a quoted string, XML tags, mode-specific blocks, or regex-defined
;; blocks).  It carries enough information for both text-object
;; selection and surround add/delete/replace.
;;
;; Schema:
;;   (:type    pair|tag|regex
;;    :open    char|string   ;; opening delimiter (for char-at detection)
;;    :close   char|string   ;; closing delimiter
;;    :finder  function      ;; (fn dir) → 0|N, moves point, sets match-data
;;    :nl-p    boolean       ;; t → add/delete handles adjacent newlines
;;    :match-close function) ;; (fn tag-name) → 0, for tag delimiters only
;;    :adjust-for-jump fn)   ;; move point into content before jump
;;
;; Builder functions live in helixel-textobj.el (they reference
;; textobj-engine functions via closures).

;; ── Accessors ──

(defsubst helixel-delimiter-type (d)
  "Return the :type of delimiter D."
  (plist-get d :type))

(defsubst helixel-delimiter-open (d)
  "Return the :open delimiter character or string of D."
  (plist-get d :open))

(defsubst helixel-delimiter-close (d)
  "Return the :close delimiter character or string of D."
  (plist-get d :close))

(defsubst helixel-delimiter-finder (d)
  "Return the :finder function of delimiter D."
  (plist-get d :finder))

(defsubst helixel-delimiter-nl-p (d)
  "Return non-nil if delimiter D uses newline handling."
  (plist-get d :nl-p))

(defsubst helixel-delimiter-match-close (d)
  "Return the :match-close function of delimiter D, or nil.
The function takes a tag name and searches forward from point
for the matching closing tag, counting nested same-name pairs."
  (plist-get d :match-close))

(defsubst helixel-delimiter-adjust-for-jump (d)
  "Return the :adjust-for-jump function of delimiter D, or nil.
If non-nil, callers like `jump-to-match' call this function before
`helixel-delimiter-bounds' to move point inside the pair, so that
the enclosing-pair lookup finds the pair whose delimiter point is
on rather than an outer enclosing pair."
  (plist-get d :adjust-for-jump))

;; ── Delimiter operations (stateless, no external deps) ──

(defvar-local helixel--block-chosen-spec nil
  "Internal: stores the spec chosen by block-finder at resolve time.
Set by block finder functions during `helixel-delimiter-bounds'.
Consumed by callers that need to know which block spec was matched.")

(defun helixel-delimiter-find (d dir)
  "Find delimiter D in DIR (+1 forward, -1 backward).
Returns 0 on success, non-zero on failure.  Moves point and sets `match-data'."
  (funcall (helixel-delimiter-finder d) dir))

(defun helixel-delimiter-bounds (d &optional no-close-backoff)
  "Return ((OB . OE) . (CB . CE)) for the innermost delimiter D at point.
OB, OE: open delimiter beg/end.  CB, CE: close delimiter beg/end.
When NO-CLOSE-BACKOFF is non-nil, skip stepping back before a
closing delimiter.  Callers that just moved inside from the
opening delimiter (e.g. `helixel--generic-bounds-next' step 2)
should set this to avoid a false match for equal open/close chars."
  (let ((close (helixel-delimiter-close d)))
    (when (eobp) (skip-chars-backward " \t\n\r"))
    (when (and (not no-close-backoff)
               (characterp close) (> (point) 1)
               (= (char-before) close))
      (backward-char))
    (unwind-protect
        (progn
          (unless (zerop (helixel-delimiter-find d -1))
            (user-error "No enclosing delimiter"))
          (let ((ob (match-beginning 0)) (oe (match-end 0)))
            (goto-char oe)
            ;; For delimiters with a :match-close method (tags), use
            ;; targeted search so nested different-name pairs don't
            ;; steal the match.
            (if-let* ((mc (helixel-delimiter-match-close d))
                     (tag (match-string 1)))
                (funcall mc tag)
              (unless (zerop (helixel-delimiter-find d 1))
                (user-error "No enclosing delimiter")))
            (let ((cb (match-beginning 0)) (ce (match-end 0)))
              (cons (cons ob oe) (cons cb ce)))))
      (setq helixel--block-chosen-spec nil))))

(defun helixel-delimiter-bounds-flat (d &optional no-close-backoff)
  "Return (OB OE CB CE) for the innermost delimiter D at point.
OB, OE: open delimiter beg/end.  CB, CE: close delimiter beg/end.
Like `helixel-delimiter-bounds' but returns a flat list instead
of nested cons cells for easier destructuring.
Optional NO-CLOSE-BACKOFF is passed through to `helixel-delimiter-bounds'."
  (pcase-let* ((`((,ob . ,oe) . (,cb . ,ce))
                (helixel-delimiter-bounds d no-close-backoff)))
    (list ob oe cb ce)))

(defun helixel--generic-bounds-at (d &optional inner-p no-close-backoff)
  "Return (BEG . END) of enclosing delimiter D.
If INNER-P is non-nil, exclude delimiters from bounds.
When NO-CLOSE-BACKOFF is non-nil, skip the `backward-char' heuristic
in `helixel-delimiter-bounds' for the case where point is right
after the closing delimiter."
  (pcase-let* ((`(,ob ,oe ,cb ,ce)
                (helixel-delimiter-bounds-flat d no-close-backoff)))
    (if inner-p (cons oe cb) (cons ob ce))))

(defun helixel--strip-adjacent-newlines (open-end close-beg)
  "Adjust OPEN-END and CLOSE-BEG to exclude adjacent newlines.
Returns (OPEN-END . CLOSE-BEG)."
  (cons (if (eq (char-after open-end) ?\n) (1+ open-end) open-end)
        (if (eq (char-before close-beg) ?\n) (1- close-beg) close-beg)))

(defun helixel--generic-bounds-next (d &optional inner-p)
  "Skip past current delimiter D, find next, return (BEG . END).
If INNER-P is non-nil, exclude delimiters from bounds.
If no next opening delimiter exists, falls back to the current
pair's bounds so callers can still move to that closing."
  (save-excursion
    (let* ((orig-pt (point))
           (cur-bounds (save-excursion
                         (condition-case nil
                             (helixel--generic-bounds-at d inner-p)
                           (error nil))))
           (open (helixel-delimiter-open d))
           (open-str (and open (if (characterp open)
                                   (char-to-string open)
                                 open)))
           (tag-p (eq (helixel-delimiter-type d) 'tag)))
      ;; Step 1: skip past current enclosing pair (or climb outward
      ;; if already at its closing edge).
      (when cur-bounds
        (setq cur-bounds
              (condition-case nil
                  (pcase-let* ((`(,_ob ,_oe ,cb ,ce)
                                (helixel-delimiter-bounds-flat d))
                               (at-closing
                                (>= orig-pt cb)))
                    (if at-closing
                        (save-excursion
                          (goto-char ce)
                          (helixel--generic-bounds-at d inner-p t))
                      (goto-char ce)
                      cur-bounds))
                (error cur-bounds))))
      ;; Step 2: return enclosing pair's bounds, or search forward
      ;; for the first opening delimiter if not inside any pair.
      (or cur-bounds
          (when open-str
            (when (search-forward open-str nil t)
              (goto-char (1+ (match-beginning 0)))
              (when tag-p (search-forward ">" nil t))
              (helixel--generic-bounds-at d inner-p t)))))))


;; ----------------------------------------------------------------------
;; Part 2b — Active Search State (mutable, per-buffer)
;; ----------------------------------------------------------------------
;;
;; Defined here (zero deps) so both helixel-search.el and
;; helixel-repeat.el can access its fields via struct accessors.

(cl-defstruct (helixel-active-search (:conc-name helixel-active-search--)
                                      (:copier copy-helixel-active-search))
  "Mutable active search state — set by \=/, \=?, \=*, \=#, f, F, t, T.
Slots:
  CATEGORY  — \='search or \='find-char
  PATTERN   — regexp string (search only)
  DIR       — \='forward or \='backward (mutable — N flips it)
  TYPE      — \='next or \='till (find-char only)
  CHAR      — character (find-char only)
  ENTRY-KIND — \='insert, \='append, or nil"
  (category nil :read-only t)
  (pattern  nil :read-only t)
  dir
  (type    nil :read-only t)
  (char    nil :read-only t)
  entry-kind)

;; ----------------------------------------------------------------------
;; Part 3 — Kind Registry (centralised kind protocol)
;; ----------------------------------------------------------------------
;;
;; Each selection kind registers four protocol methods:
;;   :recreate  — function (ctx) to recreate selection at point
;;   :advance   — function (tx tag) → boolean for next target
;;   :display   — function (ctx) → string for history display
;;
;; The strategy builder looks up :advance and :recreate from this
;; registry, eliminating kind-specific cond branches.

(defvar helixel--kind-registry (make-hash-table :test #'eq)
  "Hash table: kind symbol → plist.
Keys: :recreate :advance :display :all-buffer-fn.")

(cl-defmacro helixel-register-kind (kind &rest props)
  "Register selection KIND with protocol PROPS.
PROPS is a keyword plist."
  (declare (indent 1))
  `(puthash ',kind (list ,@props) helixel--kind-registry))

(defun helixel--kind-advance (kind)
  "Return the :advance function for KIND from the registry."
  (plist-get (gethash kind helixel--kind-registry) :advance))

(defun helixel--kind-recreate (kind)
  "Return the :recreate function for KIND from the registry."
  (plist-get (gethash kind helixel--kind-registry) :recreate))

(defun helixel--kind-display (kind)
  "Return the :display function/string for KIND from the registry."
  (plist-get (gethash kind helixel--kind-registry) :display))

(defun helixel--kind-all-buffer-fn (kind)
  "Return the :all-buffer-fn for KIND from the registry, or nil."
  (plist-get (gethash kind helixel--kind-registry) :all-buffer-fn))

(defun helixel--kind-mc-spawn-fn (kind)
  "Return the :mc-spawn-fn for KIND from the registry, or nil.
The spawn function takes one argument SEL (a `helixel-sel') and
returns a list of (POINT . MARK) marker pairs — one fake cursor
target per element.  When nil, the multi-cursor module falls back
to walking the kind's :advance function from `point-min'."
  (plist-get (gethash kind helixel--kind-registry) :mc-spawn-fn))

(defun helixel--kind-all-dir-fn (kind)
  "Return the :all-dir-fn for KIND from the registry, or nil."
  (plist-get (gethash kind helixel--kind-registry) :all-dir-fn))

(defun helixel--kind-flip-dir-fn (kind)
  "Return the :flip-dir-fn for KIND from the registry, or nil.
The flip-dir function takes a `helixel-sel' and returns a new
sel with its direction reversed.  Used by `.' /
`helixel-repeat-edit' with a prefix argument or while
`helixel--repeat-permanent-flip' is non-nil.

Kinds whose selections have no notion of direction (e.g. textobj,
rect, movement, find-char) leave this nil; the repeat engine
then simply does not flip."
  (plist-get (gethash kind helixel--kind-registry) :flip-dir-fn))


;; ----------------------------------------------------------------------
;; Part 4 — helixel-event: Unified Event Struct
;; ----------------------------------------------------------------------
;;
;; Unified event struct for dot-repeat (`.`) replay, `;` jumping,
;; and history selection.

(cl-defstruct (helixel-event (:conc-name helixel-event-)
                             (:copier helixel-event--shallow-copy))
  "Immutable editing event — serves both `.` replay and `;` jumping.
Slots:
  OP        — symbol: operator name (kill, change, chain, ...)
  SEL       — `helixel-sel' struct or nil
  PAYLOAD   — plist of operator-specific data (:text :keys ...)
  RUNNER    — function (event) → nil, executes the edit at replay time
  MARK-REGION — cons (START . END) of two markers; start serves
                 as the `;` jump target; degenerate (= point . point)
                 when no explicit region is set by the command
  CATEGORY  — symbol for action classification (edit search movement ...)
  SUBCAT    — symbol sub-classification (kill search word ...)
  DISPLAY   — string or function (event) → string for history
  TIMESTAMP — float from `float-time'
  BUFFER    — buffer object where the event occurred"
  op
  sel
  payload
  runner
  mark-region
  category
  subcat
  display
  timestamp
  buffer)

(defun helixel-event--copy (event)
  "Deep-copy `helixel-event' struct EVENT.
Copies marker (via `copy-marker') and sel (via `helixel-sel--copy')
so the copy is fully independent of the original."
  (when (helixel-event-p event)
    (let ((copy (helixel-event--shallow-copy event)))
      (when-let* ((mr (helixel-event-mark-region event))
                  ((consp mr)))
        (setf (helixel-event-mark-region copy)
              (cons (copy-marker (car mr))
                    (copy-marker (cdr mr) t))))
      (when-let* ((s (helixel-event-sel event)))
        (setf (helixel-event-sel copy) (helixel-sel--copy s)))
      copy)))

(defun helixel-event--same-content-p (e1 e2)
  "Return non-nil if E1 and E2 have identical key content.
Compares op, sel, payload, category, subcat, and marker position.
Two events at different positions are never considered the same."
  (if (or (null e1) (null e2))
      (eq e1 e2)
    (and (eq (helixel-event-op e1) (helixel-event-op e2))
         (eq (helixel-event-category e1) (helixel-event-category e2))
         (eq (helixel-event-subcat e1) (helixel-event-subcat e2))
         (helixel-sel-equal-p (helixel-event-sel e1)
                              (helixel-event-sel e2))
         (equal (helixel-event-payload e1)
                (helixel-event-payload e2))
         (= (marker-position (car (helixel-event-mark-region e1)))
            (marker-position (car (helixel-event-mark-region e2)))))))

(defun helixel-event-format (event)
  "Return display string for EVENT.
Format: OP[.SEL][xCOUNT].  Uses DISPLAY slot if stored;
otherwise falls back to `helixel--op-display'."
  (let* ((op (helixel-event-op event))
         (sel (helixel-event-sel event))
         (op-str (or (helixel-event-display event)
                     (helixel--op-display op event)))
         (sel-str (when sel (helixel-sel-call-display sel)))
         (count (helixel-sel-count sel)))
    (concat op-str
            (when sel-str (concat "." sel-str))
            (when (and count (> count 1)) (format "x%d" count)))))


;; ----------------------------------------------------------------------
;; ----------------------------------------------------------------------
;; Part 5 — Transaction helpers (build on `helixel-event')
;; ----------------------------------------------------------------------
;;
;; Dot-repeat transactions are `helixel-event' structs.

(defun helixel-event-create (op sel-ctx &rest payload-kv)
  "Create a `helixel-event' transaction for dot-repeat.
OP is a registered operator symbol.
SEL-CTX is a selection descriptor or nil.
PAYLOAD-KV are keyword/value pairs.  Special keys:
  :runner  FUNCTION — stored in slot, called at replay time
  :display STRING|FUNCTION — stored in DISPLAY slot, for history
All other keys form the :payload plist."
  (let (runner display-field rest)
    (while payload-kv
      (pcase (car payload-kv)
        (:runner
         (setq runner (cadr payload-kv))
         (setq payload-kv (cddr payload-kv)))
        (:display
         (setq display-field (cadr payload-kv))
         (setq payload-kv (cddr payload-kv)))
        (_
         (push (car payload-kv) rest)
         (push (cadr payload-kv) rest)
         (setq payload-kv (cddr payload-kv)))))
    (make-helixel-event
     :op op
     :sel sel-ctx
     :payload (nreverse rest)
     :mark-region (let ((pm (point-marker))) (cons pm (copy-marker pm t)))
     :runner runner
     :display display-field
     :timestamp (float-time)
     :buffer (current-buffer))))

(defun helixel-event-copy (tx)
  "Return a shallow copy of transaction TX."
  (helixel-event--shallow-copy tx))

;; ── Equality (for event ring dedup) ──

(defun helixel-event-equal-p (tx1 tx2)
  "Return non-nil if TX1 and TX2 represent the same editing operation.
Compares op, sel, and payload.  Ignores marker (position differs
on replay).  Returns t when both are nil."
  (if (or (null tx1) (null tx2))
      (eq tx1 tx2)
    (and (eq (helixel-event-op tx1) (helixel-event-op tx2))
         (helixel-sel-equal-p (helixel-event-sel tx1)
                              (helixel-event-sel tx2))
         (equal (helixel-event-payload tx1)
                (helixel-event-payload tx2)))))

;; ── Payload helpers ──

(defun helixel-event-with-payload (tx key value)
  "Return a new transaction equal to TX with :payload KEY set to VALUE.
Does not mutate TX."
  (let* ((payload (copy-sequence (helixel-event-payload tx)))
         (new-payload (plist-put payload key value))
         (new-tx (helixel-event-copy tx)))
    (setf (helixel-event-payload new-tx) new-payload)
    new-tx))

;; ── Display ──

;; ── Deep copy ──

(defun helixel-sel--copy (sel)
  "Deep-copy `helixel-sel' struct SEL.
Copies the ctx plist so the copy is independent."
  (when (helixel-sel-p sel)
    (helixel-sel--internal
     :kind (helixel-sel--kind sel)
     :ctx (copy-sequence (helixel-sel--ctx sel)))))


;; ----------------------------------------------------------------------
;; Part 6 — Operator Registry
;; ----------------------------------------------------------------------
;;
;; Operators are registered in a module-private hash table — no symbol
;; property pollution, no accidental clobbering, discoverable via
;; `helixel-list-ops'.
;;
;; Each operator entry is a plist with keys:
;;   :runner        — function (TX) -> nil for `.` replay
;;   :display       — string or function (TX) -> string for history
;;   :repeat-advance — nil, `line', or function for `.` auto-advance
;;
;;     nil    = no advance (op moves point itself: kill, change, join-lines)
;;     `line' = advance using the sel kind's advance fn:
;;              line→line-advance, movement→movement-advance, etc.
;;              In line-pass (all-buffer/all-dir), `line' vs nil also
;;              controls the stepping algorithm:
;;                `line' → simple forward-line (op doesn't move point)
;;                nil    → check bol/eol first (op may have moved point)
;;
;; Modules define ops at load-time via `helixel-register-op'.

(defvar helixel--op-registry (make-hash-table :test #'eq)
  "Hash table mapping operator symbols (e.g. `kill', `change')
to their property plists (:runner :display :repeat-advance).")

(defmacro helixel-register-op (op &rest props)
  "Register edit operator OP with keyword PROPS.

PROPS is a plist with keys:
  :runner           — function (TX) -> nil for `.` replay
  :display          — string or function (TX) -> string for history
  :repeat-advance   — nil, `line', or function for `.` auto-advance
                       See the comment block above for semantics.
  :strategy-builder — function (event &optional reverse-p)
                       → helixel-repeat-strategy or nil

Stores all props in the internal hash table."
  (declare (indent 1))
  `(puthash ',op (list ,@(mapcan (lambda (kv) (list kv)) props))
            helixel--op-registry))

(defun helixel--op-runner (op)
  "Return the runner function for OP from the operator registry."
  (plist-get (gethash op helixel--op-registry) :runner))

(defun helixel--op-display (op &optional tx)
  "Return display label for OP, optionally evaluated with TX.
Reads the :display entry from the operator registry.
Falls back to `symbol-name'."
  (let ((d (plist-get (gethash op helixel--op-registry) :display)))
    (cond
     ((stringp d) d)
     ((functionp d) (or (funcall d tx) (symbol-name op)))
     (t (symbol-name op)))))

(defun helixel--op-advance (op)
  "Return the :repeat-advance property for OP, or nil."
  (plist-get (gethash op helixel--op-registry) :repeat-advance))

(defun helixel--op-strategy-builder (op)
  "Return the :strategy-builder for OP, or nil."
  (plist-get (gethash op helixel--op-registry) :strategy-builder))

(defun helixel-op-set-runner (op runner)
  "Override the :runner for OP in the operator registry to RUNNER.
Preserves existing :display and :repeat-advance."
  (let ((entry (gethash op helixel--op-registry)))
    (when entry
      (plist-put entry :runner runner))))

(defun helixel-list-ops ()
  "Display all registered operators with their properties.
Shows operator name, display label, and advance tag."
  (interactive)
  (let ((buf (get-buffer-create "*helixel-ops*"))
        (ops nil))
    (maphash (lambda (op props)
               (push (list op
                           (plist-get props :display)
                           (plist-get props :repeat-advance)
                           (and (plist-get props :runner) t))
                     ops))
             helixel--op-registry)
    (setq ops (sort ops (lambda (a b) (string< (symbol-name (car a))
                                               (symbol-name (car b))))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "%-22s %-12s %-12s %s\n"
                        "Operator" "Display" "Advance" "Runner")
                (make-string 60 ?-) "\n")
        (dolist (entry ops)
          (insert (format "%-22s %-12s %-12s %s\n"
                          (car entry)
                          (or (nth 1 entry) "-")
                          (or (nth 2 entry) "-")
                          (if (nth 3 entry) "yes" "-")))))
      (goto-char (point-min)))
    (display-buffer buf)))


;; ----------------------------------------------------------------------
;; Part 7 — Swap-source type (used by helixel-editing and helixel-swap)
;; ----------------------------------------------------------------------

(defvar rectangle-mark-mode)            ; defined in rect.el

(defvar-local helixel--raw-selection-type nil
  "Internal flag: raw selection type before validation.
Set by selection commands (line, rect, textobj, char).
nil means charwise, `line' means linewise, `rect' means rectangle.
Use `helixel--selection-type' for the validated version.")

(defun helixel--swap-source-type ()
  "Return the swap-source type for the current selection.
Returns nil (char), \=`line', or \=`rect'.
More permissive than `helixel--selection-type' — detects
`rectangle-mark-mode' directly."
  (cond
   ((eq helixel--raw-selection-type 'rect) 'rect)
   ((eq helixel--raw-selection-type 'line) 'line)
   ((bound-and-true-p rectangle-mark-mode) 'rect)
   (t nil)))


;; ----------------------------------------------------------------------
;; Shared utilities (used by repeat engine and domain modules)
;; ----------------------------------------------------------------------

(defun helixel--blank-line-p ()
  "Return non-nil if the current line is blank (empty or whitespace only)."
  (save-excursion
    (goto-char (line-beginning-position))
    (looking-at-p "[ \t]*$")))

(defun helixel--recreate-selection (sel-ctx)
  "Recreate a selection from SEL-CTX at the current point.
Thin wrapper around `helixel-sel-call-recreate' —
dispatches on struct closures."
  (when sel-ctx
    (helixel-sel-call-recreate sel-ctx)))

(defun helixel--execute-edit (tx)
  "Execute transaction TX on the current buffer.
Does NOT record, does NOT switch state.
Calls the :runner stored in TX (set at record time by
`helixel--op-runner').  If :runner is missing,
falls back to the operator registry."
  (when-let* ((runner (or (helixel-event-runner tx)
                         (helixel--op-runner (helixel-event-op tx)))))
    (funcall runner tx)))

;; ── Replay context ──

(defvar-local helixel--in-replay nil
  "When non-nil, dot-repeat recording and action tracking are suppressed.
Bound during `helixel-repeat-edit', `.` replay, chain replay,
and mc-broadcast to prevent re-recording the replay as a new edit.
Single flag replacing the former `helixel--inhibit-repeat-record'
and `helixel--inhibit-action-track'.")

(defmacro helixel-with-replay-context (&rest body)
  "Execute BODY with replay recording inhibited.
Binds `helixel--in-replay' to t.  Use in dot-repeat / chain /
mc-broadcast paths that must not re-record their own replay."
  (declare (indent 0) (debug t))
  `(let ((helixel--in-replay t))
     ,@body))

(defsubst helixel--repeat-echo (count)
  "Echo COUNT of repeated iterations."
  (unless (zerop count)
    (message "Repeated %d time%s" count (if (> count 1) "s" "")))
  nil)

(defun helixel--flip-dir (dir)
  "Return the opposite direction of DIR.  `forward' <-> `backward'."
  (if (eq dir 'forward) 'backward 'forward))



(defun helixel--selection-type ()
  "Return current selection type, or nil.
Validates that the region actually matches the claimed type.
Supports `line', `rect' and `textobj'."
  (when (region-active-p)
    (cond
     ((eq helixel--raw-selection-type 'rect)
      (when rectangle-mark-mode 'rect))
     ((eq helixel--raw-selection-type 'line)
      (let ((beg (region-beginning))
            (end (region-end)))
        (when (and (save-excursion (goto-char beg) (bolp))
                   (save-excursion (goto-char end) (or (eolp) (eobp))))
          'line)))
     ((eq helixel--raw-selection-type 'textobj)
      'textobj))))

;; ── Payload accessors ──

(defsubst helixel-event-payload-get (event key)
  "Return the KEY entry from EVENT's payload plist, or nil.
Preferred over raw `(plist-get (helixel-event-payload EVENT) KEY)'
at call sites; keeps payload access greppable and centralised."
  (plist-get (helixel-event-payload event) key))

(defsubst helixel-event-payload-put (event key value)
  "Set KEY → VALUE in EVENT's payload plist (mutating EVENT).
Returns the updated payload list.  Used by op runners that need
to inject replay metadata into an existing event in-place."
  (setf (helixel-event-payload event)
        (plist-put (helixel-event-payload event) key value)))


;; ----------------------------------------------------------------------
;; Part 8 — Most-recent-edit pointer (single source of truth)
;; ----------------------------------------------------------------------
;;
;; `helixel--last-event' is the pointer that `.` (dot-repeat) and
;; `,` (selection-repeat) consume.  It is global (NOT buffer-local)
(defvar-local helixel--last-event nil
  "Pointer to the most recent committed event in this buffer.
Consumed by `.` and `,` for repeat.
Buffer-local — dot-repeat is scoped to the current buffer.")

(defun helixel--update-last-event (new-tx)
  "Update the payload of `helixel--last-event' from NEW-TX.

Only the payload plist is copied; the operator, selection and
runner of the existing `helixel--last-event' are left untouched.
Used by operator commands that need to inject replay metadata
\(e.g. `:keys', `:replacement') into the most recent edit after
it was already committed."
  (when (and helixel--last-event (helixel-event-p helixel--last-event))
    (setf (helixel-event-payload helixel--last-event)
          (helixel-event-payload new-tx))))

;; ----------------------------------------------------------------------
;; Part 9 — Shared key-sequence recording utilities
;; ----------------------------------------------------------------------
;;
;; Tiny utilities shared by insert-mode recording
;; (`helixel-insert-record.el') and chain recording
;; (`helixel-chain.el').  Both use a `pre-command-hook' that pushes
;; `this-single-command-keys' onto a reversed list, then concatenate
;; at the end.  These two functions isolate the one operation they
;; unambiguously share.

(defsubst helixel-keyrec-capture ()
  "Return the current single-command key sequence for hook capture.

A semantic alias for `this-single-command-keys'.  Both recorders
push the return value of this function onto their accumulator
inside `pre-command-hook'."
  (this-single-command-keys))

(defsubst helixel-keyrec-finalize-list (key-vector-list)
  "Concatenate KEY-VECTOR-LIST (reversed) into a single key vector.

Returns nil when KEY-VECTOR-LIST is empty.  Both recorders
accumulate by `push'-ing onto a buffer-local list, so the list is
reversed at finalize time."
  (when key-vector-list
    (apply #'vconcat (nreverse key-vector-list))))

(provide 'helixel-core)
;;; helixel-core.el ends here
