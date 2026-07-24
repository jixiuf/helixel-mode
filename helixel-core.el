;;; helixel-core.el --- Core data layer for helixel-mode -*- lexical-binding: t; -*-

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
;; Core data layer for helixel-mode — the single foundation module.
;;
;; This file defines the core data types and registries consumed by
;; all helixel modules.  It depends only on `helixel-debug' (error
;; capture) and has NO side effects.
;;
;; Contents:
;;   — helixel-sel          : selection descriptor + pending-sel
;;   — Kind Registry        : centralised kind protocol
;;   — Surround-pair entry  : shared surround/delimiter-char queries
;;   — Category matcher     : (CAT . SUBCAT) checklist matching
;;   — helixel-action       : unified replay + history event struct
;;   — Operator Registry    : hash-table based op registration
;;   — Selection type       : `helixel--sel-type' / `helixel--region-type'
;;   — Invisible-text mode  : `helixel-invisible' defcustom
;;   — Replay context       : `helixel-replay' struct + `helixel-with-replay'
;;   — Last-action pointer  : `helixel-last-action' (buffer-local)
;;
;; Domain code that used to live here moved to honest modules in the
;; 2026 core split (see plan.md Phase 1):
;;   debug infra       -> helixel-debug.el
;;   motion recording  -> helixel-motion.el
;;   named registers   -> helixel-register.el
;;   delimiter bounds  -> helixel-textobj-pair.el
;;   search filter     -> helixel-search.el
;;   grouped-ring fns  -> helixel-ring.el

;;; Code:

(require 'cl-lib)
(require 'helixel-debug)

;; ----------------------------------------------------------------------
;; helixel-sel: Selection Descriptor
;; ----------------------------------------------------------------------

(cl-defstruct (helixel-sel (:constructor nil)
                           (:copier nil)
                           (:predicate nil))
  "Abstract base struct for selection descriptors.
Concrete per-kind structs include this base (e.g. `helixel-line-sel'
in helixel-move.el).  SPAN and INLINE-ADVANCE are cross-kind flags
promoted to base slots.  Protocol methods (recreate, advance,
display) are `cl-defgeneric' dispatches on the concrete type.
Construct concrete kinds with their `make-helixel-*-sel' constructors."
  (span nil)
  (inline-advance nil))

(defsubst helixel-sel-p (obj)
  "Return non-nil if OBJ is a `helixel-sel' (any concrete subtype)."
  (cl-typep obj 'helixel-sel))

;; ----------------------------------------------------------------------
;; Selection protocol generics (cl-defgeneric dispatch)
;; ----------------------------------------------------------------------
;;
;; Each concrete `helixel-sel' subtype implements the protocol by
;; defining methods next to its struct in the owning module.
;; Base-type methods below provide the nil/identity defaults, so a
;; subtype only defines the methods it actually supports.
;;
;;  struct                        file
;;  ------                        ----
;;  helixel-line-sel              helixel-move.el
;;  helixel-rect-sel              helixel-move.el
;;  helixel-movement-sel          helixel-move.el
;;  helixel-search-sel            helixel-search.el
;;  helixel-find-char-sel         helixel-search.el
;;  helixel-textobj-sel           helixel-textobj-marks.el
;;  helixel-surround-sel          helixel-surround.el
;;  helixel-insert-*-sel (x5)     helixel-editing.el
;;  helixel-next-error-sel        helixel-next-error.el
;;  helixel-treesit-sel           helixel-treesit-core.el

(cl-defgeneric helixel-sel-recreate (sel)
  "Recreate the selection described by SEL at point.
Returns non-nil on success.")

(cl-defmethod helixel-sel-recreate ((_sel helixel-sel))
  "Default: no recreate support."
  nil)

(cl-defgeneric helixel-sel-display (sel)
  "Return a short display string for SEL (history/cycle messages).")

(cl-defmethod helixel-sel-display ((sel helixel-sel))
  "Default: display the kind symbol name of SEL."
  (symbol-name (type-of sel)))

(cl-defgeneric helixel-sel-flip-dir (sel)
  "Return a new sel like SEL with its direction flipped, or nil.
Kinds without a direction concept use the base method (nil).")

(cl-defmethod helixel-sel-flip-dir ((_sel helixel-sel))
  "Default: no direction concept."
  nil)

(cl-defgeneric helixel-sel-advance-fn (sel)
  "Return the advance function (TX TAG) -> boolean for SEL, or nil.")

(cl-defmethod helixel-sel-advance-fn ((_sel helixel-sel))
  "Default: no advance function."
  nil)

(cl-defgeneric helixel-sel-all-buffer-fn (sel)
  "Return the all-buffer repeat function (EDIT PREFIX) for SEL, or nil.")

(cl-defmethod helixel-sel-all-buffer-fn ((_sel helixel-sel))
  "Default: no custom all-buffer repeat."
  nil)

(cl-defgeneric helixel-sel-all-dir-fn (sel)
  "Return the all-dir repeat function (EDIT) for SEL, or nil.")

(cl-defmethod helixel-sel-all-dir-fn ((_sel helixel-sel))
  "Default: no custom all-dir repeat."
  nil)

(cl-defgeneric helixel-sel-region-type (sel)
  "Return SEL's region type: nil, `line', `rect', or `textobj'.")

(cl-defmethod helixel-sel-region-type ((_sel helixel-sel))
  "Default: no region type."
  nil)

(cl-defgeneric helixel-sel-skip-reverse-exchange-p (kind)
  "Return non-nil if KIND manages point/mark itself on N reverse.")

(cl-defmethod helixel-sel-skip-reverse-exchange-p ((_kind t))
  "Default: kinds do not skip `exchange-point-and-mark'."
  nil)

(cl-defgeneric helixel-sel-entry-kind (sel)
  "Return the entry-kind of SEL, or nil.")

(cl-defmethod helixel-sel-entry-kind ((_sel null))
  "Nil has no entry kind."
  nil)

(cl-defmethod helixel-sel-entry-kind ((_sel helixel-sel))
  "Default: no entry kind."
  nil)

(cl-defgeneric helixel-sel-n-count (sel)
  "Return the n-count of SEL, or nil.")

(cl-defmethod helixel-sel-n-count ((_sel null))
  "Nil has no n-count."
  nil)

(cl-defmethod helixel-sel-n-count ((_sel helixel-sel))
  "Default: no n-count."
  nil)

(cl-defgeneric helixel-sel-insert-cursor-offset (sel)
  "Return the cursor offset of an insert-selection SEL, or nil.")

(cl-defmethod helixel-sel-insert-cursor-offset ((_sel null))
  "Nil has no cursor offset."
  nil)

(cl-defmethod helixel-sel-insert-cursor-offset ((_sel helixel-sel))
  "Default: no cursor offset."
  nil)

(cl-defgeneric helixel-mc-spawn-fn (sel)
  "Return the mc spawn function (SEL) -> target list for SEL, or nil.
Methods return a quoted function symbol (the implementations live
in `helixel-mc-core', which the sel-defining modules must not
require).  When nil, multi-cursor falls back to walking the
kind's advance function from `point-min'.")

(cl-defmethod helixel-mc-spawn-fn ((_sel helixel-sel))
  "Default: no spawn function; use the advance-walk fallback."
  nil)

;; ── Span extension helper ──

(defmacro helixel--with-span (sel &rest body)
  "Execute BODY with span region extension.
If SEL's `span' slot is non-nil, captures point before BODY
as the span origin and extends the mark back to it after BODY.
For \\[helixel-action-cycle] + \\[helixel-repeat-edit] repeating
the full session-start-to-point span."
  (declare (indent 1))
  `(let ((span-origin (when (helixel-sel-span ,sel) (point))))
     (prog1 (progn ,@body)
       (when span-origin
         (push-mark span-origin t t)))))

;; ── Core accessors ──

(defsubst helixel-sel-kind (sel)
  "Return the concrete struct type of `helixel-sel' struct SEL.
The result is the struct type symbol (e.g. \=`helixel-line-sel'),
which doubles as the kind identifier."
  (when (helixel-sel-p sel)
    (type-of sel)))

(defsubst helixel-sel-call-recreate (sel)
  "Recreate selection described by SEL via `helixel-sel-recreate'."
  (when (helixel-sel-p sel)
    (helixel-sel-recreate sel)))

(defsubst helixel-sel-call-display (sel)
  "Return display string for SEL via `helixel-sel-display'."
  (when (helixel-sel-p sel)
    (helixel-sel-display sel)))

(defsubst helixel-sel-advance (sel)
  "Return the advance function (TX TAG) for SEL, or nil."
  (when (helixel-sel-p sel)
    (helixel-sel-advance-fn sel)))

(cl-defgeneric helixel-sel-count (sel)
  "Return the repeat count of SEL, or 0 when absent / nil.")

(cl-defmethod helixel-sel-count ((_sel null))
  "Nil has count 0."
  0)

(cl-defmethod helixel-sel-count ((_sel helixel-sel))
  "Default: kinds without a count slot have count 0."
  0)

(defun helixel-sel-update-ctx (sel key value)
  "Return a copy of SEL with the slot named by KEY set to VALUE.
KEY is a keyword whose name matches a struct slot (e.g. :dir)."
  (when (helixel-sel-p sel)
    (let ((new (copy-sequence sel))
          (slot (intern (substring (symbol-name key) 1))))
      (setf (cl-struct-slot-value (type-of sel) slot new) value)
      new)))

;; ----------------------------------------------------------------------
;; Pending selection (selection-first protocol)
;; ----------------------------------------------------------------------
;;
;; Helixel is selection-first: selection commands push a `helixel-sel'
;; descriptor; the next editing command pops and consumes it.

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

(defsubst helixel--clear-non-movement-pending-sel ()
  "Clear `helixel--pending-sel' unless it is of kind \='movement.
When a command creates a fresh movement/visual selection, any
stale line/rect/textobj pending-sel from a prior selection command
must be discarded so it doesn't leak into dot-repeat."
  (when (and helixel--pending-sel
             (not (eq (helixel-sel-kind helixel--pending-sel) 'helixel-movement-sel)))
    (setq helixel--pending-sel nil)))


;; ── Surround-pair entry struct ──
;;
;; Each entry in `helixel--surround-pairs' is a `helixel--surround-entry'
;; struct.  Accessors below are thin wrappers that also accept block cons
;; cells (OPEN . CLOSE) for code that receives union types from
;; `helixel--surround-lookup'.

(cl-defstruct (helixel--surround-entry
               (:constructor helixel--make-surround-entry)
               (:conc-name helixel--sre-)
               (:copier nil))
  "A surround-pair or block entry.
OPEN  — opening delimiter (character or string).
CLOSE — closing delimiter (character or string).
TYPE  — :pair, :quote, or :block.
META  — plist (supports :modes key) or nil."
  open
  close
  type
  meta)

(defvar helixel--surround-pairs)  ; forward-declare, defined in textobj-engine

(defsubst helixel--surround-entry-open (e)
  "Return the opening delimiter from `helixel--surround-entry' E."
  (helixel--sre-open e))

(defsubst helixel--surround-entry-close (e)
  "Return the closing delimiter from `helixel--surround-entry' E."
  (helixel--sre-close e))

(defsubst helixel--surround-entry-type (e)
  "Return the type (:pair, :quote, or :block) from `helixel--surround-entry' E."
  (helixel--sre-type e))

(defsubst helixel--surround-entry-meta (e)
  "Return the META plist from `helixel--surround-entry' E."
  (helixel--sre-meta e))

(defun helixel--surround-entry-applicable-p (e)
  "Return non-nil if surround-pairs entry E applies in current `major-mode'.
Checks the :modes key in the META plist.  Entries without
:modes are universal — always applicable.
Entries with :modes apply only when the current `major-mode'
is `derived-mode-p' from one of the listed modes."
  (if-let* ((modes (plist-get (helixel--surround-entry-meta e) :modes)))
      (cl-some #'derived-mode-p modes)
    t))

(defun helixel--surround-pairs-active ()
  "Return surround-pair entries valid for the current `major-mode'.
Filters `helixel--surround-pairs' through
`helixel--surround-entry-applicable-p'."
  (cl-remove-if-not #'helixel--surround-entry-applicable-p
                    helixel--surround-pairs))

(defsubst helixel--canonical-pair-p (open close)
  "Return non-nil if (OPEN . CLOSE) is in canonical (forward) direction.
An entry is canonical when OPEN's codepoint <= CLOSE's.
This is the single source of truth for forward/reverse
entry discrimination — both `helixel--active-delim-chars'
and `helixel--jump-to-match-core' delegate here."
  (<= open close))



(defun helixel--category-match-p (category subcat checklist)
  "Return non-nil if (CATEGORY . SUBCAT) matches CHECKLIST.

Each element of CHECKLIST is a plain symbol (matches any subcat
under that category) or a cons (C . S) (matches the specific
subcat S of category C).

Used by \\[helixel-action-cycle] cycling visibility,
\\[helixel-repeat-last-motion] motion-repeat filtering,
and semicolon mark-thing selection.  They share the
same (CAT . SUBCAT) or CAT pattern for precise category+subcat
matching."
  (cl-some
   (lambda (entry)
     (if (consp entry)
         (and (eq category (car entry))
              (eq subcat (cdr entry)))
       (eq category entry)))
   checklist))


;; ── Unified delimiter-char query ──
;; All delimiter-char enumeration uses this single function.
;; The per-type/-direction helpers below are thin wrappers.

(cl-defun helixel--active-delim-chars (&key type open-only close-only)
  "Return deduplicated delimiter chars from active surround-pairs.
TYPE   — :pair, :quote, or nil (all types).
OPEN-ONLY — if t, return only open chars.
CLOSE-ONLY — if t, return only close chars.

For CLOSE-ONLY / OPEN-ONLY, only entries where open and close
are characters AND canonical (close >= open codepoint, per
`helixel--canonical-pair-p') are included.  String-delimiter
entries (e.g. block fences) are excluded from char-based queries."
  (let (result)
    (dolist (e (helixel--surround-pairs-active))
      (when (or (null type)
                (eq (helixel--surround-entry-type e) type))
        (let ((open (helixel--surround-entry-open e))
              (close (helixel--surround-entry-close e)))
          (when (and (characterp open) (characterp close))
            (let ((canonical (helixel--canonical-pair-p open close)))
              (cond
               (close-only
                (when canonical (push close result)))
               (open-only
                (when canonical (push open result)))
               (t
                (push open result)
                (push close result))))))))
    (delete-dups (nreverse result))))


;; ----------------------------------------------------------------------
;; helixel-action: unified replay + history event struct
;; ----------------------------------------------------------------------
;;
;; ONE struct serves two roles:
;;
;;   1. Replay transaction — carries OP, SEL, PAYLOAD, RUNNER,
;;      PREPOSITION, MARK-REGION.  Position-agnostic; \\[helixel-repeat-edit] /
;; \\[helixel-repeat-last-motion]
;;      / chain / mc all replay via `helixel-action-replay'.
;;
;;   2. History event — carries CATEGORY, SUBCAT, DISPLAY, TIMESTAMP,
;;      BUFFER, BY-COMMAND.  Recorded in `helixel--action-ring' and
;;      `helixel--global-jump-log'.
;;
;; Pure movement / search / state events leave OP/SEL/PAYLOAD/RUNNER
;; nil; replay events leave CATEGORY/SUBCAT/TIMESTAMP/BUFFER nil when
;; constructed via `helixel-action-create' standalone.

(cl-defstruct (helixel-action (:conc-name helixel-action-)
                              (:copier helixel-action--shallow-copy))
  "Unified replay/history event.  See module commentary above.

Replay slots (used by \\[helixel-repeat-edit]
/\\[helixel-repeat-last-motion]/chain/mc):
  OP            — symbol: registered operator name (kill, change, ...)
                  or nil for pure movement/search/state events.
  SEL           — `helixel-sel' struct or nil.
  PAYLOAD       — plist of operator-specific data (:text :keys ...).
  RUNNER        — function (EVENT) → nil, executes the edit at
                  replay time.  nil for non-replayable events.
  PREPOSITION — optional function (EVENT) → nil, called BEFORE
                  RUNNER at replay time.  Used by `:preposition' clauses
                  on insert-entry commands (mc fake positioning).
                  Single-write invariant: at most one per command.
  MARK-REGION   — cons (START . END) of two markers; the position
                  where the event was originally recorded.  Used
                  for \\[helixel-action-cycle] jump targets AND by some runners.
  START-POINT   — marker; the original cursor position at
                  `tracking-open' time, before any movement.
                  Used by \\[helixel-action-cycle-mark-start] to
                  push mark to the pre-motion cursor position.
                  Never modified after creation.  Free-standing
                  marker — not part of `mark-region'.
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
  preposition
  mark-region
  start-point
  display
  ;; History slots
  category
  subcat
  timestamp
  buffer
  by-command)

(cl-defun helixel-action-create (op sel-ctx payload &key runner display)
  "Create a `helixel-action' carrying replay data for dot-repeat.
OP is a registered operator symbol.
SEL-CTX is a `helixel-sel' descriptor or nil.
PAYLOAD is a plist of operator-specific data (:text :keys ...), passed
as ONE explicit argument — it is never parsed for special keys, so
payload entries named :runner or :display are safe.
RUNNER is a function (EVENT) -> nil stored in the RUNNER slot.
DISPLAY is a string or function (EVENT) -> string for the DISPLAY slot.
MARK-REGION is initialised from `point' at call time.
START-POINT is intentionally left nil — it is set at
`tracking-open' time by `helixel--live-action-set' which
captures the pre-motion cursor position.  For edit events
where start-point is nil, \\[helixel-action-cycle-mark-start] falls back to the
mark-region car (which is the pre-edit point)."
  (make-helixel-action
   :op op
   :sel sel-ctx
   :payload payload
   :runner runner
   :display display
   :mark-region (let ((pm (point-marker)))
                  (cons pm (copy-marker pm t)))))

(defsubst helixel-action-shallow-copy (event)
  "Return a shallow copy of EVENT (alias-friendly name)."
  (helixel-action--shallow-copy event))

(defun helixel-action-with-payload (event key value)
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

(defsubst helixel-action-char (obj)
  "Return the :char payload from OBJ.
Used by find-char, replace-char, and surround commands."
  (helixel-action-payload-get obj :char))

(defsubst helixel-action-type (obj)
  "Return the :type payload from OBJ.
Used by find-char (next | till)."
  (helixel-action-payload-get obj :type))

(defsubst helixel-action-dir (obj)
  "Return the :dir payload from OBJ.
Used by find-char (forward | backward)."
  (helixel-action-payload-get obj :dir))


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
      (when-let* ((sp (helixel-action-start-point event))
                  ((markerp sp)))
        (setf (helixel-action-start-point copy) (copy-marker sp)))
      (when-let* ((s (helixel-action-sel event)))
        (setf (helixel-action-sel copy) (helixel-sel--copy s)))
      copy)))

(defun helixel-action--release-markers (event)
  "Free all markers in EVENT via `set-marker' nil.
Releases mark-region and start-point.  No-op if EVENT is nil
or not a `helixel-action-p'.

Call this before discarding an action struct to prevent marker
leaks — Emacs GC eventually collects orphaned markers, but
pending markers still track buffer changes and waste CPU."
  (when (helixel-action-p event)
    (when-let* ((mr (helixel-action-mark-region event))
                ((consp mr)))
      (when (markerp (car mr)) (set-marker (car mr) nil))
      (when (markerp (cdr mr)) (set-marker (cdr mr) nil)))
    (when-let* ((sp (helixel-action-start-point event))
                ((markerp sp)))
      (set-marker sp nil))))

(defun helixel-action--same-content-p (e1 e2)
  "Return non-nil if E1 and E2 have identical key content.
Compares category, subcat, marker positions (car and cdr), and — if
both carry an op — op/sel/payload.  Two events with different extents
are never the same (prevents consecutive paste amalgamation)."
  (if (or (null e1) (null e2))
      (eq e1 e2)
    (let* ((op1 (helixel-action-op e1))
           (op2 (helixel-action-op e2))
           (mr1 (helixel-action-mark-region e1))
           (mr2 (helixel-action-mark-region e2)))
      (and (eq (helixel-action-category e1) (helixel-action-category e2))
           (eq (helixel-action-subcat e1) (helixel-action-subcat e2))
           (= (marker-position (car mr1))
              (marker-position (car mr2)))
           (= (marker-position (cdr mr1))
              (marker-position (cdr mr2)))
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
                    (equal (helixel-action-sel e1)
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
;; Operator Registry
;; ----------------------------------------------------------------------
;;
;; Operators are registered in a module-private hash table — no symbol
;; property pollution, no accidental clobbering, discoverable via
;; `helixel-list-ops'.
;;
;; Each operator entry is a plist with keys:
;;   :runner        — named function symbol (TX) -> nil, for `.`
;;                    replay (never a lambda — pure-data rule)
;;   :display       — string or named function symbol (TX) -> string
;;                    for history
;;   :self-advancing — boolean.  t when the operator handles its
;;                    own positioning (kill, change, join-lines);
;;                    nil when the repeat engine must auto-advance
;;                    (insert, replace, paste, indent, surround, …).
;;
;;                    Controls two things in one bool:
;;                      1. Whether `.` auto-advances after apply.
;;                         t → no auto-advance (op handles
;;                         positioning); nil → use the kind's
;;                         :advance fn.
;;                      2. The stepping algorithm in line-pass
;;                         (all-buffer / all-dir):
;;                         nil → simple `forward-line';
;;                         t   → check bol/eol first (op may have
;;                         eaten the newline).
;;
;; Modules define ops at load-time via `helixel-register-op'.

(defvar helixel--op-registry (make-hash-table :test #'eq)
  "Hash table mapping operator symbols (e.g. `kill', `change')
to their property plists (:runner :display :self-advancing).")

(defmacro helixel-register-op (op &rest props)
  "Register edit operator OP with keyword PROPS.

PROPS is a plist with keys:
  :runner           — named function symbol (TX) -> nil, for `.`
                      replay (never a lambda — pure-data rule)
  :display          — string or named function symbol (TX) -> string
                      for history
  :self-advancing   — boolean.  t when OP handles its own
                       positioning, nil otherwise.
                       See the comment block above for full semantics.

Stores all props in the internal hash table."
  (declare (indent 1))
  `(puthash ',op (list ,@(mapcan (lambda (kv) (list kv)) props))
            helixel--op-registry))

(defsubst helixel--op-runner (op)
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

(defsubst helixel--op-self-advancing-p (op)
  "Return the :self-advancing property for OP (boolean).
Non-nil means OP handles its own positioning and the repeat engine
should NOT auto-advance; nil means the kind's :advance fn drives
stepping between targets."
  (plist-get (gethash op helixel--op-registry) :self-advancing))

(defun helixel--op-set-runner (op runner)
  "Override the :runner for OP in the operator registry to RUNNER.
Preserves existing :display and :self-advancing.
Stores a fresh copy so callers holding a reference to the old
plist are not affected by the mutation."
  (when-let* ((entry (gethash op helixel--op-registry)))
    (puthash op (plist-put (copy-sequence entry) :runner runner)
             helixel--op-registry)))

(defun helixel-list-ops ()
  "Display all registered operators with their properties.
Shows operator name, display label, and `self-advancing' flag."
  (interactive)
  (let ((buf (get-buffer-create "*helixel-ops*"))
        (ops nil))
    (maphash (lambda (op props)
               (push (list op
                           (plist-get props :display)
                           (plist-get props :self-advancing)
                           (and (plist-get props :runner) t))
                     ops))
             helixel--op-registry)
    (setq ops (sort ops (lambda (a b) (string< (symbol-name (car a))
                                               (symbol-name (car b))))))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "%-22s %-12s %-12s %s\n"
                        "Operator" "Display" "SelfAdv" "Runner")
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
;; Selection type (used by helixel-editing and helixel-swap)
;; ----------------------------------------------------------------------

(defvar rectangle-mark-mode)            ; defined in rect.el

(defsubst helixel--sel-type ()
  "Return the selection type from pending-sel: nil, `line', `rect', `textobj'.
Looks up :sel-type from the kind registry — extensible by registering
new kinds with `:sel-type'.  Falls back to nil for unregistered kinds.
During replay, `helixel-action-replay' temporarily binds
`helixel--pending-sel' from the action's stored selection so the
operator sees the same type it saw during recording.
Pending-sel is NOT popped until `clear-data', so this function returns
the correct type throughout the operator body."
  (when helixel--pending-sel
    (helixel-sel-region-type helixel--pending-sel)))

(defvar-local helixel-invisible 'auto
  "How helixel handles invisible text during search and movement.
Defaults to \='auto, which dynamically follows `search-invisible'
\(typically \='open).

Value \='open (default):  like t, but also temporarily reveal
  invisible text when a search or find-char match lands inside
  it, matching Emacs' `search-invisible' = \='open behavior
  (e.g. unfolding folded sections in `org-mode' during
  \[helixel-search-repeat-next] or \[helixel-repeat-last-motion]).
Value t:  treat invisible text as real content — \"x\"/\"X\"
  selections expand into it, and search finds matches inside,
  but invisible text is NOT revealed (stays folded).
Value nil:  skip invisible matches entirely — use this in
  buffers like `grep-mode' with `consult-focus-line' where
  invisible text is filtered-out content to ignore.

Set per-buffer via `setq-local' or dir-locals.
Toggle with \[helixel-toggle-invisible].")

(defsubst helixel--invisible-effective ()
  "Return the effective invisible-handling mode.
If `helixel-invisible' is \='auto (never explicitly set), follow
`search-invisible' so new buffers inherit the user's Emacs preference.
Otherwise return `helixel-invisible' as-is (explicit user choice)."
  (if (eq helixel-invisible 'auto)
      search-invisible
    helixel-invisible))


;; ----------------------------------------------------------------------
;; Shared utilities (used by repeat engine and domain modules)
;; ----------------------------------------------------------------------

(defsubst helixel--blank-line-p ()
  "Return non-nil if the current line is blank (empty or whitespace only)."
  (save-excursion
    (beginning-of-line)
    (looking-at-p "[ \t]*$")))

(defsubst helixel--recreate-selection (sel-ctx)
  "Recreate a selection from SEL-CTX at the current point.
Thin wrapper around `helixel-sel-call-recreate' —
dispatches on struct closures."
  (when sel-ctx
    (helixel-sel-call-recreate sel-ctx)))

(defsubst helixel--advance-by-recreate (tx)
  "Advance past the current target by recreating TX's selection.
For selection kinds whose recreate IS the advance (movement,
textobj), this is the preferred advance function.  Calls
`helixel--recreate-selection' inside `helixel--with-debug-log'
to catch user-errors silently.  Returns t on success, nil when
recreate fails with a user-error (e.g. no more targets)."
  (let ((sel (helixel-action-sel tx)))
    (when sel
      (helixel--with-debug-log advance-by-recreate
        (progn (helixel--recreate-selection sel) t)
        (error nil)))))

(defun helixel-action-replay (event)
  "Execute replay data in EVENT: preposition (if any) then runner.
Reads :preposition and :runner from EVENT (a `helixel-action').
Falls back to the operator registry if :runner is nil but :op is set.
If neither runner nor op resolves but preposition ran, EVENT is
treated as a pure positioner (movement commands at fake cursors).

Temporarily binds `helixel--pending-sel' from the action's stored
selection so operators see the same type via `helixel--sel-type'
as they did during recording (when `helixel--pending-sel' was set)."
  (let* ((op (helixel-action-op event))
         (runner (or (helixel-action-runner event)
                     (and op (helixel--op-runner op))))
         ;; Restore the pending-sel that was active during recording
         ;; so `helixel--sel-type' returns the correct type.
         (helixel--pending-sel (helixel-action-sel event)))
    (when-let* ((pre (helixel-action-preposition event)))
      (funcall pre event))
    (when runner
      (funcall runner event))))

(defsubst helixel--flip-dir (dir)
  "Return the opposite direction of DIR.  `forward' <-> `backward'."
  (if (eq dir 'forward) 'backward 'forward))



(defun helixel--region-type ()
  "Return current selection type, or nil.
Validates that the region actually matches the sel type.
Supports `line', `rect' and `textobj'.

When `helixel--sel-type' does not indicate a specific type
\(e.g. after visual-mode movement commands like `j'/`k' that
replace a rect/line sel with a movement sel), falls back to
direct detection of `rectangle-mark-mode'."
  (when (region-active-p)
    (cond
     ((eq (helixel--sel-type) 'rect)
      (when rectangle-mark-mode 'rect))
     ((eq (helixel--sel-type) 'line)
      (let ((beg (region-beginning))
            (end (region-end)))
        (when (and (save-excursion (goto-char beg) (bolp))
                   (save-excursion (goto-char end) (or (eolp) (eobp))))
          'line)))
     ((eq (helixel--sel-type) 'textobj)
      'textobj)
     ;; Fallback: when `rectangle-mark-mode' is active, treat as rect
     ;; even if the pending-sel was replaced by a movement kind.
     ;; This preserves correct d/y/c dispatch after visual-mode
     ;; motion commands (j/k/h/l) extended a rect selection.
     ((bound-and-true-p rectangle-mark-mode) 'rect))))

;; ----------------------------------------------------------------------
;; helixel-sel deep copy (used by tx deep-copy)
;; ----------------------------------------------------------------------

(defun helixel-sel--copy (sel)
  "Deep-copy `helixel-sel' struct SEL.
Copies the slots and their mutable sub-structures (e.g. the moves
list whose elements' cdrs are mutated by `setcdr' in
track-visual-move) so the copy is fully independent.  Every cons
slot value is `copy-tree'd; only :moves is mutated in practice,
and the rest are tiny immutable plists."
  (when (helixel-sel-p sel)
    (let ((new (copy-sequence sel)))
      (dotimes (i (length new))
        (when (consp (aref new i))
          (setf (aref new i) (copy-tree (aref new i)))))
      new)))


;; ----------------------------------------------------------------------
;; Most-recent-action pointer (single source of truth)
;; ----------------------------------------------------------------------
;;
;; `helixel-last-action' is the pointer that `.` (dot-repeat) and
;; \\[helixel-repeat-last-motion]
;; (selection-repeat) consume.  Buffer-local — dot-repeat is scoped
;; to the current buffer.

(defvar-local helixel-last-action nil
  "Pointer to the most recent committed `helixel-action' in this buffer.
Consumed by \\[helixel-repeat-edit] and
\\[helixel-repeat-last-motion] for repeat.  Buffer-local.")

(defvar helixel--current-command nil
  "Symbol of the currently-executing helixel command.
Bound by `helixel-define-command' (and by `helixel--with-command'
for manually-defined commands) so that `helixel--action-commit'
can stamp `by-command' on each committed action — enabling the
multi-cursor dispatcher to detect a fresh edit produced by THIS
command even when `this-command' isn't set (e.g. in batch tests
or when called programmatically without going through the
command loop).")

(defmacro helixel--with-command (name &rest body)
  "Run BODY tagged as if it were inside the command NAME.
Binds `helixel--current-command' AND overrides `this-command'
to NAME so committed actions carry the right `by-command' stamp.
Use for plain `defun' helixel commands that don't go through
`helixel-define-command'."
  (declare (indent 1) (debug t))
  `(let ((helixel--current-command ',name)
         (this-command ',name))
     ,@body))

(defun helixel--update-last-action (new-action)
  "Update the payload of `helixel-last-action' from NEW-ACTION.

Only the payload plist is copied; the op, sel, runner, mark-region
of the existing `helixel-last-action' are left untouched.  Used by
operator commands that need to inject replay metadata (e.g.
`:keys', `:replacement') into the most recent action after it was
already committed."
  (when (and helixel-last-action (helixel-action-p helixel-last-action))
    (setf (helixel-action-payload helixel-last-action)
          (helixel-action-payload new-action))))


;; ── Replay context ──

(cl-defstruct (helixel-replay (:conc-name helixel-replay--))
  "Replay-time context.  Bound dynamically via `helixel-with-replay'.
The ORIGIN field is one of:
  dot       — \\[helixel-repeat-edit]
            / \\[helixel-repeat-last-motion]
            / chain / insert replay of a stored edit
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
True only for the `dot' origin (used by
\\[helixel-repeat-edit]
/ \\[helixel-repeat-last-motion] / chain / insert
replay paths).  Does NOT include `mc-fake' / `mc-batch' origins —
those wrap normal command execution at fake cursors and should not
suppress per-fake recording.  Use `helixel--replay-in-fake-p' /
`helixel-mc--dispatch-in-progress-p' for mc-specific guards."
  (and helixel--replay
       (eq (helixel-replay--origin helixel--replay) 'dot)))

(defsubst helixel--replay-in-fake-p ()
  "Return non-nil when replaying inside a fake cursor body."
  (and helixel--replay
       (eq (helixel-replay--origin helixel--replay) 'mc-fake)))

(defsubst helixel--search-advance-done-p ()
  "Non-nil if `helixel--repeat-advance-search' positioned point this session."
  (and helixel--replay
       (helixel-replay--search-advance-done helixel--replay)))

(defsubst helixel--search-advance-done-set (val)
  "Set the search-advance-done flag to VAL on the current replay ctx."
  (when helixel--replay
    (setf (helixel-replay--search-advance-done helixel--replay) val)))

(defsubst helixel--search-advance-last-pos ()
  "Last `match-beginning' processed by `helixel--repeat-advance-search'."
  (and helixel--replay
       (helixel-replay--search-last-pos helixel--replay)))

(defsubst helixel--search-advance-last-pos-set (val)
  "Set the last-match-position field on the current replay ctx to VAL."
  (when helixel--replay
    (setf (helixel-replay--search-last-pos helixel--replay) val)))

(defsubst helixel--search-advance-edge-seen-p ()
  "Non-nil if a zero-width buffer-edge match was already processed."
  (and helixel--replay
       (helixel-replay--search-edge-seen helixel--replay)))

(defsubst helixel--search-advance-edge-seen-set (val)
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

(provide 'helixel-core)
;;; helixel-core.el ends here
