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
;;   Part 4 — helixel-action      : unified event struct
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
;; Each selection kind uses a specific subset of ctx keys.  The
;; schema lives in the kind registry (`helixel-register-kind') under
;; the `:ctx-schema (:required (...) :optional (...))' key; the
;; registry is the single source of truth.  `helixel--validate-ctx'
;; reads it at author/lint time.
;;
;; All kinds accept an optional :inline-advance flag.
;; When t, the advance function creates the region as part
;; of its positioning (movement, textobj, find-char).
;; The strategy reads this flag to avoid double-recreating.

;; ── CTX schema validation ──
;;
;; Schemas are stored on each kind's registry entry (see
;; `helixel-register-kind').  `helixel--validate-ctx' looks them up
;; at runtime.  Gated by `helixel--ctx-validation-enabled' — it
;; never runs in production.

(defvar helixel--ctx-validation-enabled nil
  "When non-nil, `helixel--validate-ctx' checks ctx against the schema.
Enabled during `make lint' and in test suites.
Never set in production — ctx are validated at author time only.")

(defvar helixel--kind-registry)         ; defined in Part 3 below.

(defun helixel--validate-ctx (kind ctx-plist)
  "Validate CTX-PLIST against the schema registered for KIND.
Returns t if valid.  When `helixel--ctx-validation-enabled' is nil,
returns t immediately (no-op).

Reads `:ctx-schema' from the kind registry.  Kinds without a
registered schema are accepted (no validation).

Checks:
  1. All :required keys present in CTX-PLIST.
  2. No keys outside the union of :required and :optional.
Signals `helixel-ctx-error' on mismatch with details."
  (or (not helixel--ctx-validation-enabled)
      (let* ((entry (gethash kind helixel--kind-registry))
             (spec (and entry (helixel-kind-ctx-schema entry))))
        ;; Kinds with no :ctx-schema in their registration are
        ;; permissive — useful for transient/internal kinds.
        (or (null spec)
            (let* ((required (plist-get spec :required))
                   (optional (plist-get spec :optional))
                   (allowed (append required optional)))
              (dolist (key required)
                (unless (plist-member ctx-plist key)
                  (signal 'helixel-ctx-error
                          (list (format
                                 "Kind %s: missing required key :%s"
                                 kind key)))))
              (cl-loop for (k _v) on ctx-plist by #'cddr
                       unless (memq k allowed)
                       do (signal 'helixel-ctx-error
                                  (list (format
                                         "Kind %s: unknown key :%s in ctx"
                                         kind k))))
              t)))))

(defun helixel-sel-create (kind ctx)
  "Create a `helixel-sel' struct for selection KIND with data CTX.
All protocol methods (recreate, advance, display) are looked up
from the kind registry.
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
;; Each accessor takes either a `helixel-sel' struct or a raw ctx
;; plist (for use inside recreate closures).  These are the preferred
;; way to read ctx fields; they document the valid keys per kind
;; through their names.  See the CTX schema table above for details.
;;
;; All accessors share the same body shape
;;     (or (plist-get (helixel-sel--ctx-ensure OBJ) KEY) DEFAULT)
;; so we generate them via `helixel--def-sel-accessor'.

(defsubst helixel-sel--ctx-ensure (obj)
  "If OBJ is a `helixel-sel' struct, return its ctx; else return OBJ."
  (if (helixel-sel-p obj) (helixel-sel--ctx obj) obj))

(defmacro helixel--def-sel-accessor (name key &optional default doc)
  "Define a `defsubst' NAME that reads ctx KEY (with optional DEFAULT).
DOC is the docstring (the OBJ/ctx-plist clarification is appended
automatically)."
  (let ((doc (concat (or doc (format "Return %s from ctx." key))
                     "\nOBJ is a `helixel-sel' struct or raw ctx plist.")))
    `(defsubst ,name (obj)
       ,doc
       ,(if default
            `(or (plist-get (helixel-sel--ctx-ensure obj) ,key) ,default)
          `(plist-get (helixel-sel--ctx-ensure obj) ,key)))))

;;;; line
(helixel--def-sel-accessor helixel-sel-line-dir   :dir   'forward
  "Return :dir from line ctx (`forward' or `backward'), default `forward'.")
(helixel--def-sel-accessor helixel-sel-line-count :count 1
  "Return :count from line ctx, default 1.")

;;;; rect
(helixel--def-sel-accessor helixel-sel-rect-count :count 1
  "Return :count from rect ctx, default 1.")

;;;; movement
(helixel--def-sel-accessor helixel-sel-movement-moves :moves nil
  "Return :moves list from movement ctx ((CMD . COUNT) ...).")
(helixel--def-sel-accessor helixel-sel-movement-inline-advance-p
  :inline-advance nil
  "Return non-nil if movement ctx has :inline-advance set.")
(helixel--def-sel-accessor helixel-sel-movement-normal-mode-p
  :normal-mode nil
  "Return non-nil if movement was recorded in normal mode.
When set, each movement command resets the selection during
dot-repeat replay (only the final target is selected).")

;;;; textobj
(helixel--def-sel-accessor helixel-sel-textobj-command :command nil
  "Return :command (symbol) from textobj ctx.")
(helixel--def-sel-accessor helixel-sel-textobj-count   :count   1
  "Return :count from textobj ctx, default 1.")
(helixel--def-sel-accessor helixel-sel-textobj-delimiter :delimiter nil
  "Return :delimiter (plist) from textobj ctx.")

;;;; search
(helixel--def-sel-accessor helixel-sel-search-pattern :pattern nil
  "Return :pattern (string) from search ctx.")
(helixel--def-sel-accessor helixel-sel-search-dir :dir 'forward
  "Return :dir from search ctx, default `forward'.")
(helixel--def-sel-accessor helixel-sel-search-entry-kind :entry-kind nil
  "Return :entry-kind (insert or append) from search ctx, or nil.")
(helixel--def-sel-accessor helixel-sel-search-cursor-offset :cursor-offset nil
  "Return :cursor-offset (integer) from search ctx, or nil.")

;;;; find-char
(helixel--def-sel-accessor helixel-sel-find-char-dir :dir 'forward
  "Return :dir (`forward' or `backward') from find-char ctx.")
(helixel--def-sel-accessor helixel-sel-find-char-type :type nil
  "Return :type (`next' or `till') from find-char ctx.")
(helixel--def-sel-accessor helixel-sel-find-char-char :char nil
  "Return :char (character) from find-char ctx.")

;;;; surround
(helixel--def-sel-accessor helixel-sel-surround-delimiter :delimiter nil
  "Return :delimiter (plist) from surround ctx.")

;;;; insert-search-offset
(helixel--def-sel-accessor helixel-sel-insert-offset :offset nil
  "Return :offset (integer) from insert-search-offset ctx.")

;;;; insert-selection-start / insert-selection-end
(helixel--def-sel-accessor helixel-sel-insert-cursor-offset :cursor-offset nil
  "Return :cursor-offset (integer) from insert ctx, or nil.")


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

(defun helixel--push-selection (kind ctx)
  "Create a `helixel-sel' of KIND with CTX and push as pending selection.
Returns the created sel."
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
  "Hash table: kind symbol → `helixel-kind' struct.")

(cl-defstruct (helixel-kind (:constructor helixel--make-kind)
                            (:copier nil))
  "Selection-kind protocol struct.  Lives in `helixel--kind-registry'.
Slots map 1:1 to the keyword properties documented for
`helixel-register-kind'."
  recreate advance display
  all-buffer-fn all-dir-fn flip-dir-fn mc-spawn-fn
  ctx-schema)

(cl-defmacro helixel-register-kind (kind &rest props)
  "Register selection KIND with protocol PROPS.
PROPS is a keyword plist supporting:
  :recreate :advance :display
  :all-buffer-fn :all-dir-fn :flip-dir-fn :mc-spawn-fn
  :ctx-schema (:required (...) :optional (...))"
  (declare (indent 1))
  `(puthash ',kind (helixel--make-kind ,@props) helixel--kind-registry))

;; Kind-registry accessors.  Thin wrappers around the struct accessors
;; that handle the \"kind not registered\" case (gethash returns nil)
;; by returning nil, matching the previous plist-get-on-nil semantics.

(defun helixel--kind-recreate (kind)
  "Return the :recreate function for KIND from the registry."
  (when-let* ((k (gethash kind helixel--kind-registry)))
    (helixel-kind-recreate k)))

(defun helixel--kind-advance (kind)
  "Return the :advance function for KIND from the registry."
  (when-let* ((k (gethash kind helixel--kind-registry)))
    (helixel-kind-advance k)))

(defun helixel--kind-display (kind)
  "Return the :display function/string for KIND from the registry."
  (when-let* ((k (gethash kind helixel--kind-registry)))
    (helixel-kind-display k)))

(defun helixel--kind-all-buffer-fn (kind)
  "Return the :all-buffer-fn for KIND from the registry, or nil."
  (when-let* ((k (gethash kind helixel--kind-registry)))
    (helixel-kind-all-buffer-fn k)))

(defun helixel--kind-mc-spawn-fn (kind)
  "Return the :mc-spawn-fn for KIND from the registry, or nil.
The spawn function takes one argument SEL (a `helixel-sel') and
returns a list of (POINT . MARK) marker pairs — one fake cursor
target per element.  When nil, the multi-cursor module falls back
to walking the kind's :advance function from `point-min'."
  (when-let* ((k (gethash kind helixel--kind-registry)))
    (helixel-kind-mc-spawn-fn k)))

(defun helixel--kind-all-dir-fn (kind)
  "Return the :all-dir-fn for KIND from the registry, or nil."
  (when-let* ((k (gethash kind helixel--kind-registry)))
    (helixel-kind-all-dir-fn k)))

(defun helixel--kind-flip-dir-fn (kind)
  "Return the :flip-dir-fn for KIND from the registry, or nil.
The flip-dir function takes a `helixel-sel' and returns a new
sel with its direction reversed.  Used by `.' /
`helixel-repeat-edit' with a prefix argument or while
`helixel--repeat-permanent-flip' is non-nil.

Kinds whose selections have no notion of direction (e.g. textobj,
rect, movement, find-char) leave this nil; the repeat engine
then simply does not flip."
  (when-let* ((k (gethash kind helixel--kind-registry)))
    (helixel-kind-flip-dir-fn k)))


;; ----------------------------------------------------------------------
;; Part 4 — helixel-action: unified replay + history event struct
;; ----------------------------------------------------------------------
;;
;; ONE struct serves two roles:
;;
;;   1. Replay transaction — carries OP, SEL, PAYLOAD, RUNNER,
;;      PRE-REPLAY-FN, MARK-REGION.  Position-agnostic; `.' / `,'
;;      / chain / mc all replay via `helixel-tx-replay'.
;;
;;   2. History event — carries CATEGORY, SUBCAT, DISPLAY, TIMESTAMP,
;;      BUFFER, BY-COMMAND.  Recorded in `helixel--event-ring' and
;;      `helixel--global-jump-log'.
;;
;; Pure movement / search / state events leave OP/SEL/PAYLOAD/RUNNER
;; nil; replay events leave CATEGORY/SUBCAT/TIMESTAMP/BUFFER nil when
;; constructed via `helixel-tx-create' standalone.
;;
;; History (pre-v5): the codebase had TWO structs — `helixel-tx' (7
;; slots) wrapped by `helixel-action' (8 slots, one of which was
;; `:tx').  The split required 4 polymorphic accessors and a hidden
;; `helixel-action--ensure-tx' mutator.  Merging removes ~100 LOC of
;; bridge code; the 5 nil slots on pure-movement events cost ~40B per
;; entry × ring cap = ~2KB / buffer (negligible).  See plan-v5.md.

(cl-defstruct (helixel-action (:conc-name helixel-action-)
                              (:copier helixel-action--shallow-copy))
  "Unified replay/history event.  See module commentary above.

Replay slots (used by `.'/`,'/chain/mc):
  OP            — symbol: registered operator name (kill, change, ...)
                  or nil for pure movement/search/state events.
  SEL           — `helixel-sel' struct or nil.
  PAYLOAD       — plist of operator-specific data (:text :keys ...).
  RUNNER        — function (EVENT) → nil, executes the edit at
                  replay time.  nil for non-replayable events.
  PRE-REPLAY-FN — optional function (EVENT) → nil, called BEFORE
                  RUNNER at replay time.  Used by `:tx-runner' clauses
                  on insert-entry commands (mc fake prepositioning).
                  Single-write invariant: at most one per command.
  MARK-REGION   — cons (START . END) of two markers; the position
                  where the event was originally recorded.  Used
                  for `;' jump targets AND by some runners.
  DISPLAY       — string or function (EVENT) → string for history.

History slots (used by ring + jump-log):
  CATEGORY    — symbol: classification (edit search movement ...)
  SUBCAT      — symbol: sub-classification (kill search word ...)
  TIMESTAMP   — float from `float-time'.
  BUFFER      — buffer object where the event occurred.
  BY-COMMAND  — symbol of the command that produced this event."
  ;; Replay slots
  op
  sel
  payload
  runner
  pre-replay-fn
  mark-region
  display
  ;; History slots
  category
  subcat
  timestamp
  buffer
  by-command)

;; ── Backwards-compatible aliases ──
;;
;; Old code (and tests) read/write via `helixel-tx-*' or check via
;; `helixel-tx-p'.  Post-merge these are pure aliases.  External
;; packages should migrate to `helixel-action-*' over time; this file
;; will keep the aliases for the foreseeable future as zero-cost
;; redirections.

(defalias 'helixel-tx-p             #'helixel-action-p)
(defalias 'make-helixel-tx          #'make-helixel-action)
(defalias 'helixel-tx-op            #'helixel-action-op)
(defalias 'helixel-tx-sel           #'helixel-action-sel)
(defalias 'helixel-tx-payload       #'helixel-action-payload)
(defalias 'helixel-tx-runner        #'helixel-action-runner)
(defalias 'helixel-tx-pre-replay-fn #'helixel-action-pre-replay-fn)
(defalias 'helixel-tx-mark-region   #'helixel-action-mark-region)
(defalias 'helixel-tx-display       #'helixel-action-display)

(defun helixel-tx-create (op sel-ctx &rest payload-kv)
  "Create a `helixel-action' carrying replay data for dot-repeat.
OP is a registered operator symbol.
SEL-CTX is a `helixel-sel' descriptor or nil.
PAYLOAD-KV are keyword/value pairs.  Special keys:
  :runner  FUNCTION       — stored in RUNNER slot.
  :display STRING|FUNCTION — stored in DISPLAY slot.
All other keys form the :payload plist.
MARK-REGION is initialised from `point' at call time.

Name retained for compatibility — returns a `helixel-action'."
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
    (make-helixel-action
     :op op
     :sel sel-ctx
     :payload (nreverse rest)
     :runner runner
     :display display-field
     :mark-region (let ((pm (point-marker)))
                    (cons pm (copy-marker pm t))))))

(defun helixel-tx-copy (event)
  "Return a shallow copy of EVENT (alias-friendly name)."
  (helixel-action--shallow-copy event))

(defun helixel-tx-with-payload (event key value)
  "Return a new event equal to EVENT with :payload KEY set to VALUE.
Does not mutate EVENT."
  (let* ((payload (copy-sequence (helixel-action-payload event)))
         (new-payload (plist-put payload key value))
         (copy (helixel-action--shallow-copy event)))
    (setf (helixel-action-payload copy) new-payload)
    copy))

;; Transparent payload helpers.

(defsubst helixel-action-payload-get (obj key)
  "Return KEY from OBJ's payload plist, or nil."
  (plist-get (helixel-action-payload obj) key))

;; ── Convenience accessors for common payload keys ──
;;
;; A handful of payload keys are shared across many prompted commands:
;; find-char (:char :type :dir), replace-char (:char), surround (:char).
;; These thin wrappers replace raw `plist-get' call sites.

(defsubst helixel-tx-char (obj)
  "Return the :char payload from OBJ.
Used by find-char, replace-char, and surround commands."
  (helixel-action-payload-get obj :char)) ; ctx-lint-ok

(defsubst helixel-tx-type (obj)
  "Return the :type payload from OBJ.
Used by find-char (next | till)."
  (helixel-action-payload-get obj :type)) ; ctx-lint-ok

(defsubst helixel-tx-dir (obj)
  "Return the :dir payload from OBJ.
Used by find-char (forward | backward)."
  (helixel-action-payload-get obj :dir)) ; ctx-lint-ok


(defun helixel-action--copy (event)
  "Deep-copy EVENT — copies markers and the sel ctx.
The result is fully independent of EVENT for ring storage."
  (when (helixel-action-p event)
    (let ((copy (helixel-action--shallow-copy event)))
      (when-let* ((mr (helixel-action-mark-region event))
                  ((consp mr)))
        (setf (helixel-action-mark-region copy)
              (cons (copy-marker (car mr))
                    (copy-marker (cdr mr) t))))
      (when-let* ((s (helixel-action-sel event)))
        (setf (helixel-action-sel copy) (helixel-sel--copy s)))
      copy)))

(defun helixel-action--same-content-p (e1 e2)
  "Return non-nil if E1 and E2 have identical key content.
Compares category, subcat, marker position, and — if both carry an
op — op/sel/payload.  Two events at different positions are never
the same."
  (if (or (null e1) (null e2))
      (eq e1 e2)
    (let ((op1 (helixel-action-op e1))
          (op2 (helixel-action-op e2)))
      (and (eq (helixel-action-category e1) (helixel-action-category e2))
           (eq (helixel-action-subcat e1) (helixel-action-subcat e2))
           (= (marker-position (car (helixel-action-mark-region e1)))
              (marker-position (car (helixel-action-mark-region e2))))
           ;; If exactly one side has an op, they differ.
           (eq (and op1 t) (and op2 t))
           ;; If both have no replay data (no op, no payload, no sel),
           ;; they're same.  But if one has payload and the other
           ;; doesn't, they differ — the payload distinguishes them.
           (or (and (not op1) (not (helixel-action-payload e1))
                    (not (helixel-action-sel e1))
                    (not (helixel-action-payload e2))
                    (not (helixel-action-sel e2)))
               (and (eq op1 op2)
                    (helixel-sel-equal-p (helixel-action-sel e1)
                                         (helixel-action-sel e2))
                    (equal (helixel-action-payload e1)
                           (helixel-action-payload e2))))))))

(defun helixel-action-format (event)
  "Return display string for EVENT.
Format: OP[.SEL][xCOUNT].  EVENT's :display takes precedence;
falls through to `helixel--op-display'."
  (let* ((op (helixel-action-op event))
         (sel (helixel-action-sel event))
         (op-str (or (helixel-action-display event)
                     (and op (helixel--op-display op event))))
         (sel-str (when sel (helixel-sel-call-display sel)))
         (count (and sel (helixel-sel-count sel))))
    (concat op-str
            (when sel-str (concat "." sel-str))
            (when (and count (> count 1)) (format "x%d" count)))))


;; ----------------------------------------------------------------------
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
;;   :moves-point-p — boolean.  t when the operator moves point
;;                    itself (kill, change, join-lines); nil when
;;                    the operator leaves point in place and the
;;                    repeat engine must auto-advance (insert,
;;                    replace, paste, indent, surround, …).
;;
;;                    Controls two things in one bool:
;;                      1. Whether `.` auto-advances after apply.
;;                         t → no auto-advance (op already moved
;;                         point); nil → use the kind's :advance fn.
;;                      2. The stepping algorithm in line-pass
;;                         (all-buffer / all-dir):
;;                         nil → simple `forward-line';
;;                         t   → check bol/eol first (op may have
;;                         eaten the newline).
;;
;; Modules define ops at load-time via `helixel-register-op'.

(defvar helixel--op-registry (make-hash-table :test #'eq)
  "Hash table mapping operator symbols (e.g. `kill', `change')
to their property plists (:runner :display :moves-point-p).")

(defmacro helixel-register-op (op &rest props)
  "Register edit operator OP with keyword PROPS.

PROPS is a plist with keys:
  :runner           — function (TX) -> nil for `.` replay
  :display          — string or function (TX) -> string for history
  :moves-point-p    — boolean.  t when OP moves point itself
                       (suppresses auto-advance), nil otherwise.
                       See the comment block above for full semantics.

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

(defun helixel--op-moves-point-p (op)
  "Return the :moves-point-p property for OP (boolean).
Non-nil means OP advances point on its own and the repeat engine
should NOT auto-advance; nil means the kind's :advance fn drives
stepping between targets."
  (plist-get (gethash op helixel--op-registry) :moves-point-p))

(defun helixel-op-set-runner (op runner)
  "Override the :runner for OP in the operator registry to RUNNER.
Preserves existing :display and :moves-point-p."
  (let ((entry (gethash op helixel--op-registry)))
    (when entry
      (plist-put entry :runner runner))))

(defun helixel-list-ops ()
  "Display all registered operators with their properties.
Shows operator name, display label, and `moves-point-p' flag."
  (interactive)
  (let ((buf (get-buffer-create "*helixel-ops*"))
        (ops nil))
    (maphash (lambda (op props)
               (push (list op
                           (plist-get props :display)
                           (plist-get props :moves-point-p)
                           (and (plist-get props :runner) t))
                     ops))
             helixel--op-registry)
    (setq ops (sort ops (lambda (a b) (string< (symbol-name (car a))
                                               (symbol-name (car b))))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "%-22s %-12s %-12s %s\n"
                        "Operator" "Display" "MovesPt" "Runner")
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

(defun helixel-tx-replay (tx)
  "Execute transaction TX on the current buffer.
Does NOT record, does NOT switch state.

If TX has a `pre-replay-fn', call it first (used by mc-fake replay
of insert-entry commands to position point before the main runner
inserts text).  Then call the :runner stored in TX.  If :runner is
missing, falls back to the operator registry.  If neither runner nor
op resolves but a pre-replay-fn ran, TX is treated as a pure
positioner (used by movement commands at fake cursors)."
  (when-let* ((pre (helixel-tx-pre-replay-fn tx)))
    (funcall pre tx))
  (when-let* ((runner (or (helixel-tx-runner tx)
                          (and (helixel-tx-op tx)
                               (helixel--op-runner (helixel-tx-op tx))))))
    (funcall runner tx)))

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

;; ----------------------------------------------------------------------
;; Part 7b — helixel-sel deep copy (used by tx deep-copy)
;; ----------------------------------------------------------------------

(defun helixel-sel--copy (sel)
  "Deep-copy `helixel-sel' struct SEL.
Copies the ctx plist so the copy is independent."
  (when (helixel-sel-p sel)
    (helixel-sel--internal
     :kind (helixel-sel--kind sel)
     :ctx (copy-sequence (helixel-sel--ctx sel)))))


;; ----------------------------------------------------------------------
;; Part 8 — Most-recent-tx pointer (single source of truth)
;; ----------------------------------------------------------------------
;;
;; `helixel--last-tx' is the pointer that `.` (dot-repeat) and `,'
;; (selection-repeat) consume.  Buffer-local — dot-repeat is scoped
;; to the current buffer.

(defvar-local helixel--last-tx nil
  "Pointer to the most recent committed `helixel-tx' in this buffer.
Consumed by `.' and `,' for repeat.  Buffer-local.")

(defvar helixel--current-command nil
  "Symbol of the currently-executing helixel command.
Bound by `helixel-define-command' (and by `helixel-with-command'
for manually-defined commands) so that `helixel-action-commit'
can stamp `by-command' on each committed action — enabling the
multi-cursor dispatcher to detect a fresh edit produced by THIS
command even when `this-command' isn't set (e.g. in batch tests
or when called programmatically without going through the
command loop).")

(defmacro helixel-with-command (name &rest body)
  "Run BODY tagged as if it were inside the command NAME.
Binds `helixel--current-command' AND overrides `this-command'
to NAME so committed actions carry the right `by-command' stamp.
Use for plain `defun' helixel commands that don't go through
`helixel-define-command'."
  (declare (indent 1) (debug t))
  `(let ((helixel--current-command ',name)
         (this-command ',name))
     ,@body))

(defun helixel--update-last-event (new-tx)
  "Update the payload of `helixel--last-tx' from NEW-TX.

Only the payload plist is copied; the op, sel, runner, mark-region
of the existing `helixel--last-tx' are left untouched.  Used by
operator commands that need to inject replay metadata (e.g.
`:keys', `:replacement') into the most recent tx after it was
already committed."
  (when (and helixel--last-tx (helixel-tx-p helixel--last-tx))
    (setf (helixel-action-payload helixel--last-tx)
          (helixel-action-payload new-tx))))


;; ----------------------------------------------------------------------
;; Part 9 — Shared key-sequence recording utilities
;; ----------------------------------------------------------------------
;;
;; Tiny utility shared by insert-mode recording
;; (`helixel-insert-record.el').  Chain recording used to share
;; this with insert-record but Phase 4.4 replaced chain's
;; keystroke capture with tx-list accumulation — only the
;; per-keystroke insert recorder still needs `keyrec-capture'.

(defsubst helixel-keyrec-capture ()
  "Return the current single-command key sequence for hook capture.

A semantic alias for `this-single-command-keys'.  The insert
recorder pushes the return value of this function onto its
accumulator inside `pre-command-hook'."
  (this-single-command-keys))

;; ----------------------------------------------------------------------
;; Part 10 — Generic grouped-ring queries
;; ----------------------------------------------------------------------
;;
;; Pure data primitives: an ordered list of entries with two query
;; axes — visibility (skip entries the caller wants hidden) and
;; grouping (consecutive entries that should be treated as one
;; navigation step).  Consumed by both `;' cycling and C-o/C-i.
;;
;; The "ring" is a plain list, NEWEST FIRST.  The caller owns
;; mutation (push / pop / cap); this section only provides query
;; primitives parameterised by predicates:
;;
;;   visible-pred  : (entry) -> non-nil if entry counts
;;   same-group-p  : (a b)   -> non-nil if a and b belong to same group

;; ── Group navigation ──

(defun helixel-gr-group-start (list pos same-group-p)
  "Return the oldest (largest) index in LIST of the group containing POS.
SAME-GROUP-P is a predicate of two adjacent entries."
  (let ((len (length list)))
    (while (and (< (1+ pos) len)
                (funcall same-group-p
                         (nth pos list) (nth (1+ pos) list)))
      (cl-incf pos))
    pos))

(defun helixel-gr-group-newest (list pos same-group-p)
  "Return the newest (smallest) index in LIST of the group containing POS.
SAME-GROUP-P is a predicate of two adjacent entries."
  (let ((i pos))
    (while (and (> i 0)
                (funcall same-group-p
                         (nth i list) (nth (1- i) list)))
      (cl-decf i))
    i))

;; ── Visibility queries ──

(defun helixel-gr-visible-index (list pos visible-p)
  "Return index of first visible entry at or after POS in LIST, or nil.
VISIBLE-P is a predicate on entries."
  (cl-loop for i from pos below (length list)
           when (funcall visible-p (nth i list))
           return i))

(defun helixel-gr-visible-count (list visible-p)
  "Count entries in LIST for which VISIBLE-P returns non-nil."
  (cl-loop for a in list
           when (funcall visible-p a)
           count 1))

(defun helixel-gr-find (list pos direction visible-p)
  "Find next visible entry index from POS in DIRECTION (+1 or -1).
LIST is the ring, VISIBLE-P the visibility predicate.  Returns nil
if no further visible entry exists in that direction."
  (let ((len (length list)))
    (cl-loop for i from (+ pos direction) by direction
             while (if (> direction 0) (< i len) (>= i 0))
             when (funcall visible-p (nth i list))
             return i)))


;; ──────────────────────────────────────────────────────────────────────
;;  Replay context (formerly helixel-replay.el)
;; ──────────────────────────────────────────────────────────────────────

(cl-defstruct (helixel-replay (:conc-name helixel-replay--))
  "Replay-time context.  Bound dynamically via `helixel-with-replay'.
The ORIGIN field is one of:
  dot       — `.' / `,' / chain / insert replay of a stored edit
  mc-fake   — dispatcher running a command at a fake cursor
  mc-batch  — mc broadcast outer loop (suppresses re-dispatch)

The three search-advance fields are per-replay scratch used by
`helixel--repeat-advance-search' to prevent infinite loops on
zero-width patterns ($ / ^) at buffer edges.  They live here so
nested replays don't clobber each other."
  (origin nil :read-only t)
  ;; --- search-advance scratch (per-session) ---
  search-last-pos
  search-edge-seen
  search-advance-done)

(defvar helixel--replay nil
  "Current `helixel-replay' context, or nil when not replaying.
Dynamically bound by `helixel-with-replay'.")

(defsubst helixel-replaying-p ()
  "Return non-nil when the current replay is replaying a stored edit.
True only for the `dot' origin (used by `.' / `,' / chain / insert
replay paths).  Does NOT include `mc-fake' / `mc-batch' origins —
those wrap normal command execution at fake cursors and should not
suppress per-fake recording.  Use `helixel-replay-in-fake-p' /
`helixel-mc-dispatch-in-progress-p' for mc-specific guards."
  (and helixel--replay
       (eq (helixel-replay--origin helixel--replay) 'dot)))

(defsubst helixel-replay-in-fake-p ()
  "Return non-nil when replaying inside a fake cursor body."
  (and helixel--replay
       (eq (helixel-replay--origin helixel--replay) 'mc-fake)))

(defsubst helixel-mc-dispatch-in-progress-p ()
  "Return non-nil when an mc dispatch is in progress.
Covers both `mc-batch' (outer broadcast loop) and `mc-fake'
\(inside one fake cursor's body).  Used by guards that must not
re-enter the dispatcher."
  (and helixel--replay
       (memq (helixel-replay--origin helixel--replay)
             '(mc-batch mc-fake))))

(defsubst helixel-search-advance-done-p ()
  "Non-nil if `helixel--repeat-advance-search' positioned point this session."
  (and helixel--replay
       (helixel-replay--search-advance-done helixel--replay)))

(defsubst helixel-search-advance-done-set (val)
  "Set the search-advance-done flag to VAL on the current replay ctx."
  (when helixel--replay
    (setf (helixel-replay--search-advance-done helixel--replay) val)))

(defsubst helixel-search-advance-last-pos ()
  "Last `match-beginning' processed by `helixel--repeat-advance-search'."
  (and helixel--replay
       (helixel-replay--search-last-pos helixel--replay)))

(defsubst helixel-search-advance-last-pos-set (val)
  "Set the last-match-position field on the current replay ctx to VAL."
  (when helixel--replay
    (setf (helixel-replay--search-last-pos helixel--replay) val)))

(defsubst helixel-search-advance-edge-seen-p ()
  "Non-nil if a zero-width buffer-edge match was already processed."
  (and helixel--replay
       (helixel-replay--search-edge-seen helixel--replay)))

(defsubst helixel-search-advance-edge-seen-set (val)
  "Set the edge-seen field on the current replay ctx to VAL."
  (when helixel--replay
    (setf (helixel-replay--search-edge-seen helixel--replay) val)))

(defmacro helixel-with-replay (origin &rest body)
  "Run BODY with a fresh replay context tagged ORIGIN.
ORIGIN is one of the symbols listed in `helixel-replay'."
  (declare (indent 1) (debug t))
  `(let ((helixel--replay (make-helixel-replay :origin ,origin)))
     ,@body))

(defmacro helixel-with-replay-as (origin &rest body)
  "Like `helixel-with-replay' but only set ORIGIN if not already replaying.
Use when nesting: outer wrapper should win over inner.  BODY is the
form to evaluate."
  (declare (indent 1) (debug t))
  `(if helixel--replay
       (progn ,@body)
     (helixel-with-replay ,origin ,@body)))

;; ──────────────────────────────────────────────────────────────────────
;;  Named registers (formerly helixel-register.el)
;; ──────────────────────────────────────────────────────────────────────

(defcustom helixel-register-backends
  '((?\" . kill-ring)
    (?+ . clipboard)
    (?* . primary))
  "Alist mapping register characters to storage backends.
Each entry is (CHAR . BACKEND) where BACKEND is a keyword:
- `kill-ring': Emacs kill ring (default for \\=\").
- `clipboard': System clipboard (`CLIPBOARD' selection).
- `primary': Primary selection (`PRIMARY' selection).
Characters not listed here use Emacs `register-alist' (via
`get-register'/`set-register'), which supports a-z, 0-9, and
any other character Emacs registers accept."
  :type '(alist :key-type character
                :value-type (choice (const :tag "Kill Ring" kill-ring)
                                    (const :tag "Clipboard" clipboard)
                                    (const :tag "Primary Selection" primary)))
  :group 'helixel)

(defcustom helixel-default-register ?\"
  "Character for the default (unnamed) register.
When `helixel--current-register' is nil or this character,
operators use the kill ring directly rather than a named
register.  Pressing \\\"\\\" in normal mode selects this register."
  :type 'character
  :group 'helixel)

(defcustom helixel-register-yank-char ?0
  "Register character for the last yank (copy) operation.
Set by `helixel--kill-new' with :copy kind.  Users can paste
from it with \"0p."
  :type 'character
  :group 'helixel)

(defcustom helixel-register-small-delete-char ?-
  "Register character for small deletes (no newline).
Set by `helixel--kill-new' when the deleted text does not
contain a newline."
  :type 'character
  :group 'helixel)

(defcustom helixel-register-numbered-delete-start ?1
  "First character of the numbered delete register range.
Together with `helixel-register-numbered-delete-count', defines
a rotating ring of registers that store recent deletes.
The default range is ?1 through ?9."
  :type 'character
  :group 'helixel)

(defcustom helixel-register-numbered-delete-count 9
  "Number of numbered delete registers to rotate.
Defines how many consecutive characters starting from
`helixel-register-numbered-delete-start' are used for
the delete register ring.  Default is 9 (registers 1-9)."
  :type 'natnum
  :group 'helixel)

(defvar helixel--current-register nil
  "Character identifying the register for the next operator.
Set by `helixel-select-register' (bound to `\\\"' in normal mode).
Consumed and cleared by each operator that uses it.
When nil or equal to `helixel-default-register', the `kill-ring'
is used directly.")

(defun helixel-select-register ()
  "Read a register name for the next operator.
Valid register names: a-z (named), \" (unnamed/`kill-ring'),
+ (system clipboard), * (primary selection).
Users can customize these via `helixel-register-backends'.
Press \\[keyboard-quit] to cancel."
  (interactive)
  (let ((char (read-char "Register: ")))
    (if (= char ?\e)
        (progn
          (setq helixel--current-register nil)
          (message "Register cancelled"))
      (setq helixel--current-register char)
      (message "\"%c" char))))

(defun helixel-register-backend (char)
  "Return the storage backend keyword for register CHAR.
Looks up CHAR in `helixel-register-backends'.  Returns nil when
CHAR is not in the alist (meaning it uses `register-alist')."
  (cdr (assq char helixel-register-backends)))

(defun helixel-register-get (char)
  "Return text contents of register CHAR, or nil if empty.
Dispatch is determined by `helixel-register-backends':
- `kill-ring' → top of `kill-ring'.
- `clipboard' → system clipboard (CLIPBOARD selection).
- `primary' → primary selection.
- nil (unlisted) → Emacs `register-alist' via `get-register'."
  (cl-case (helixel-register-backend char)
    (kill-ring (and kill-ring (current-kill 0 t)))
    (clipboard (and (display-graphic-p)
                    (gui-get-selection 'CLIPBOARD)))
    (primary   (and (display-graphic-p)
                    (gui-get-selection 'PRIMARY)))
    (t (get-register char))))

(defun helixel-register-set (char text)
  "Store TEXT in register CHAR.
Dispatch is determined by `helixel-register-backends':
- `kill-ring' → push to `kill-ring' via `kill-new'.
- `clipboard' → system clipboard via `gui-set-selection'.
- `primary' → primary selection via `gui-set-selection'.
- nil (unlisted) → Emacs `register-alist' via `set-register'.
TEXT is a string preserving any yank-handler properties."
  (cl-case (helixel-register-backend char)
    (kill-ring (kill-new text))
    (clipboard (gui-set-selection 'CLIPBOARD text))
    (primary   (gui-set-selection 'PRIMARY text))
    (t (set-register char text))))

(defun helixel--register-active-p ()
  "Return non-nil when a non-default named register is selected.
A register is considered active when `helixel--current-register'
is non-nil and not equal to `helixel-default-register'."
  (and helixel--current-register
       (not (eq helixel--current-register helixel-default-register))))

(defun helixel--register-consume ()
  "Return and clear `helixel--current-register'."
  (prog1 helixel--current-register
    (setq helixel--current-register nil)))

(defun helixel-register-rotate-delete (text)
  "Rotate numbered delete registers and store TEXT in the first slot.
Uses `helixel-register-numbered-delete-start' and
`helixel-register-numbered-delete-count' to define the range.
Old registers shift: slot N-1 → N, ..., slot 1 → 2."
  (let ((start helixel-register-numbered-delete-start)
        (count helixel-register-numbered-delete-count))
    (when (> count 1)
      (cl-loop for i from (- count 2) downto 0
               for src = (+ start i)
               do (set-register (1+ src) (get-register src))))
    (set-register start text)))

(defun helixel--kill-new (text &optional kind)
  "Like `kill-new', but also populates numbered registers.
TEXT is a string with optional yank-handler text properties.
KIND is :copy for yank operations (sets register 0), otherwise
a delete (rotates registers 1-9, sets register - for small deletes).
When a named register is active, TEXT is also stored there.
Does NOT clear the register -- callers should call
`helixel--register-consume' separately when done."
  (unless (eq kind :copy)
    (when interprogram-paste-function
      (let ((clip (funcall interprogram-paste-function)))
        (when (and clip (> (length clip) 0)
                   (or (null kill-ring)
                       (not (string= clip (car kill-ring)))))
          (kill-new clip)))))
  (kill-new text)
  (if (eq kind :copy)
      (set-register helixel-register-yank-char text)
    (helixel-register-rotate-delete text)
    (when (and text (not (string-match-p "\n" text)))
      (set-register helixel-register-small-delete-char text)))
  (when (helixel--register-active-p)
    (helixel-register-set helixel--current-register text)))

(defun helixel--current-kill (n &optional no-move)
  "Like `current-kill', but reads from named register when active.
N is the `kill-ring' index (unused when reading from register).
NO-MOVE is passed to `current-kill' as DO-NOT-MOVE when using `kill-ring'.
Returns the text or nil.  Does NOT alter the `kill-ring' yanking-point
when reading from a register."
  (if (helixel--register-active-p)
      (or (helixel-register-get helixel--current-register)
          (current-kill 0 t))
    (current-kill n no-move)))

(defun helixel--yank (&optional arg)
  "Like `yank', but reads from named register when active.
ARG is passed through to `yank' when using the `kill-ring'."
  (if (helixel--register-active-p)
      (let ((text (helixel-register-get helixel--current-register)))
        (if text
            (insert-for-yank text)
          (message "Register \"%c is empty" helixel--current-register)))
    (yank arg)))

(provide 'helixel-core)
;;; helixel-core.el ends here
