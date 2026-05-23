;;; helixel-data.el --- Unified data layer for helixel-mode -*- lexical-binding: t; -*-

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
;; Unified data layer for helixel-mode.
;;
;; This file defines ALL core data types consumed across helixel modules.
;; It has ZERO dependencies on other helixel modules and NO side effects.
;;
;; Contents:
;;   Part 1 — helixel-sel   : selection descriptor (cl-struct)
;;   Part 2 — Delimiter     : delimiter protocol (plist accessors + operations)
;;   Part 3 — helixel-edit  : edit transaction (cl-struct)
;;   Part 4 — Operator registry : symbol-property based op registration
;;
;; Consumed by: helixel-action, helixel-repeat,
;;              helixel-textobj, helixel-surround, helixel-common, etc.
;;
;; helixel-edit.el is now a backward-compat shim that requires this file.

;;; Code:

(require 'cl-lib)

;; ═══════════════════════════════════════════════════════════════════════
;; Part 1 — helixel-sel: Selection Descriptor
;; ═══════════════════════════════════════════════════════════════════════

(cl-defstruct (helixel-sel (:conc-name helixel-sel--)
                           (:constructor helixel-sel--internal))
  "Selection descriptor for dot-repeat with closure-based recreate.
KIND is a symbol identifying the selection type.
CTX is a plist of mutable extra data (:count, :dir, :moves, ...).
RECREATE is a function (CTX) that recreates the selection at point.
DISPLAY is a string or a function (CTX) → string."
  kind
  ctx
  recreate
  display)

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
;; textobj                   :command  (symbol)            textobj fns
;;                           :count    (integer)            same
;;                           :delimiter (plist)             same
;; search                    :pattern  (string)            search fns
;;                           :dir      (forward|backward)   same
;; surround                  :delimiter (plist)            surround fns
;; insert-selection-start    :cursor-offset (int|nil)      insert-exit
;; insert-selection-end      :cursor-offset (int|nil)      insert-exit
;; insert-beginning-line     (none)                        —
;; insert-end-line           (none)                        —
;; insert-search-offset      :offset (integer)             insert cmd

;; ── Builder ──

(defun helixel-sel-create (kind ctx recreate &optional display)
  "Create a `helixel-sel' struct for selection KIND.
CTX is a plist of extra data.
RECREATE is a function (CTX) that recreates the selection at point.
DISPLAY is an optional string or function (CTX) → string."
  (helixel-sel--internal
   :kind kind
   :ctx ctx
   :recreate recreate
   :display (or display (symbol-name kind))))

;; ── Core accessors ──

(defun helixel-sel-call-recreate (sel)
  "Recreate selection described by SEL, a `helixel-sel' struct.
Calls the stored RECREATE closure with CTX."
  (when (helixel-sel-p sel)
    (funcall (helixel-sel--recreate sel) (helixel-sel--ctx sel))))

(defun helixel-sel-call-display (sel)
  "Return display string for `helixel-sel' struct SEL.
Evaluates the DISPLAY field (string or function)."
  (when (helixel-sel-p sel)
    (let ((d (helixel-sel--display sel)))
      (if (functionp d) (funcall d (helixel-sel--ctx sel)) d))))

(defun helixel-sel-get-kind (sel)
  "Return the :kind from `helixel-sel' struct SEL."
  (when (helixel-sel-p sel)
    (helixel-sel--kind sel)))

(defun helixel-sel-get-ctx (sel)
  "Return the CTX (data plist) from `helixel-sel' struct SEL."
  (when (helixel-sel-p sel)
    (helixel-sel--ctx sel)))

(defun helixel-sel-get-field (sel key)
  "Get KEY from `helixel-sel' struct SEL's ctx.
Returns nil if SEL is nil."
  (when sel
    (plist-get (helixel-sel-get-ctx sel) key)))

(defun helixel-sel-count (sel)
  "Return :count from `helixel-sel' struct SEL's ctx, or 0 if absent.
Returns 0 if SEL is nil."
  (if (null sel) 0
    (or (plist-get (helixel-sel-get-ctx sel) :count) 0)))

(defun helixel-sel-equal-p (s1 s2)
  "Return non-nil if S1 and S2 represent the same selection.
Compares kind and ctx.  Returns t when both are nil."
  (if (or (null s1) (null s2))
      (eq s1 s2)
    (and (eq (helixel-sel-get-kind s1) (helixel-sel-get-kind s2))
         (equal (helixel-sel-get-ctx s1) (helixel-sel-get-ctx s2)))))

(defun helixel-sel-update-ctx (sel key value)
  "Return a new `helixel-sel' struct from SEL with CTX updated.
Sets KEY to VALUE in the ctx plist."
  (if (helixel-sel-p sel)
      (let ((new-ctx (plist-put (copy-sequence (helixel-sel--ctx sel))
                                key value)))
        (helixel-sel--internal
         :kind (helixel-sel--kind sel)
         :ctx new-ctx
         :recreate (helixel-sel--recreate sel)
         :display (helixel-sel--display sel)))
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


;; ═══════════════════════════════════════════════════════════════════════
;; Part 2 — Delimiter Protocol
;; ═══════════════════════════════════════════════════════════════════════
;;
;; A delimiter plist describes a delimited region (pair of brackets,
;; a quoted string, XML tags, mode-specific blocks, or regex-defined
;; blocks).  It carries enough information for both text-object
;; selection and surround add/delete/replace.
;;
;; Schema:
;;   (:type    pair|quote|tag|block|regex
;;    :open    char|string   ;; opening delimiter
;;    :close   char|string   ;; closing delimiter
;;    :finder  function      ;; (fn dir) → 0|N, moves point, sets match-data
;;    :nl-p    boolean)      ;; t → add/delete handles adjacent newlines
;;
;; Builder functions live in helixel-textobj-engine.el (they reference
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

;; ── Delimiter operations (stateless, no external deps) ──

(defvar-local helixel--block-chosen-spec nil
  "Internal: stores the spec chosen by block-finder at resolve time.
Set by block finder functions during `helixel-delimiter-bounds'.
Consumed by callers that need to know which block spec was matched.")

(defun helixel--find-equal-char (char dir)
  "Like `helixel-up-paren' but for equal open/close CHAR (quotes).
DIR +1 forward, -1 backward.  Returns 0 on success, 1 on failure."
  (if (> dir 0)
      (if (search-forward (string char) nil t) 0 1)
    (if (search-backward (string char) nil t) 0 1)))

(defun helixel-delimiter-find (d dir)
  "Find delimiter D in DIR (+1 forward, -1 backward).
Returns 0 on success, non-zero on failure.  Moves point and sets `match-data'."
  (funcall (helixel-delimiter-finder d) dir))

(defun helixel-delimiter-bounds (d)
  "Return ((OB . OE) . (CB . CE)) for the innermost delimiter D at point.
OB, OE: open delimiter beg/end.  CB, CE: close delimiter beg/end."
  (let ((close (helixel-delimiter-close d)))
    (when (eobp) (skip-chars-backward " \t\n\r"))
    (when (and (characterp close) (> (point) 1) (= (char-before) close))
      (backward-char))
    (unwind-protect
        (progn
          (unless (zerop (helixel-delimiter-find d -1))
            (user-error "No enclosing delimiter"))
          (let ((ob (match-beginning 0)) (oe (match-end 0)))
            (goto-char oe)
            (unless (zerop (helixel-delimiter-find d 1))
              (user-error "No enclosing delimiter"))
            (let ((cb (match-beginning 0)) (ce (match-end 0)))
              (cons (cons ob oe) (cons cb ce)))))
      (setq helixel--block-chosen-spec nil))))

(defun helixel--strip-adjacent-newlines (open-end close-beg)
  "Adjust OPEN-END and CLOSE-BEG to exclude adjacent newlines.
Returns (OPEN-END . CLOSE-BEG)."
  (cons (if (eq (char-after open-end) ?\n) (1+ open-end) open-end)
        (if (eq (char-before close-beg) ?\n) (1- close-beg) close-beg)))


;; ═══════════════════════════════════════════════════════════════════════
;; Part 3 — helixel-edit: Edit Transaction
;; ═══════════════════════════════════════════════════════════════════════

(cl-defstruct (helixel-edit (:conc-name helixel-edit-))
  "An immutable editing operation for dot-repeat.
Slots:
  OP           — symbol: operator name (kill, change, insert-text, ...)
  SEL          — `helixel-sel' struct or nil (selection descriptor)
  PAYLOAD      — plist of operator-specific data (:text, :char, :keys, ...)
  MARKER       — position marker where the edit started (for `;' jumping)
  RUNNER       — function (TX) → nil, executes the edit at replay time
  DISPLAY-FIELD — string or function (TX) → string, stored at record time"
  op
  sel
  payload
  marker
  runner
  display-field)

;; ── Builder ──

(defun helixel-edit-make (op sel-ctx &rest payload-kv)
  "Create a `helixel-edit' transaction struct.
OP is a registered operator symbol.
SEL-CTX is a selection descriptor or nil.
PAYLOAD-KV are keyword/value pairs.  Special keys:
  :runner  FUNCTION — stored in slot, called at replay time
  :display STRING|FUNCTION — stored in DISPLAY-FIELD slot, for history
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
    (make-helixel-edit :op op
                       :sel sel-ctx
                       :payload (nreverse rest)
                       :marker (point-marker)
                       :runner runner
                       :display-field display-field)))

;; ── Equality (for action ring dedup) ──

(defun helixel-edit-equal-p (tx1 tx2)
  "Return non-nil if TX1 and TX2 represent the same editing operation.
Compares op, sel, and payload.  Ignores marker (position differs
on replay).
Returns t when both are nil (non-edit actions are equal for dedup)."
  (if (or (null tx1) (null tx2))
      (eq tx1 tx2)
    (and (eq (helixel-edit-op tx1) (helixel-edit-op tx2))
         (helixel-sel-equal-p (helixel-edit-sel tx1)
                              (helixel-edit-sel tx2))
         (equal (helixel-edit-payload tx1)
                (helixel-edit-payload tx2)))))

;; ── Display ──

(defun helixel-edit-display (tx)
  "Return a short display string for transaction TX.
Format: OP[.SEL][xCOUNT].  Uses DISPLAY-FIELD slot if stored;
otherwise falls back to `helixel-edit-op-display'."
  (let* ((op (helixel-edit-op tx))
         (sel (helixel-edit-sel tx))
         (op-str (or (helixel-edit-display-field tx)
                     (helixel-edit-op-display op tx)))
         (sel-str (when sel (helixel-sel-call-display sel)))
         (count (helixel-sel-count sel)))
    (concat op-str
            (when sel-str (concat "." sel-str))
            (when (and count (> count 1)) (format "x%d" count)))))

;; ── Payload helpers ──

(defun helixel-edit-with-payload (tx key value)
  "Return a new transaction equal to TX with :payload KEY set to VALUE.
Does not mutate TX."
  (let* ((payload (copy-sequence (helixel-edit-payload tx)))
         (new-payload (plist-put payload key value))
         (new-tx (copy-helixel-edit tx)))
    (setf (helixel-edit-payload new-tx) new-payload)
    new-tx))


;; ═══════════════════════════════════════════════════════════════════════
;; Part 4 — Operator Registry
;; ═══════════════════════════════════════════════════════════════════════
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
;; Modules define ops at load-time via `helixel-register-op'.

(defvar helixel--op-registry (make-hash-table :test #'eq)
  "Hash table mapping operator symbols (e.g. `kill', `change')
to their property plists (:runner :display :repeat-advance).")

(defmacro helixel-register-op (op &rest props)
  "Register edit operator OP with keyword PROPS.

PROPS is a plist with keys:
  :runner        — function (TX) -> nil for `.` replay
  :display       — string or function (TX) -> string for history
  :repeat-advance — nil, `line', or function for `.` auto-advance

Stores runner, display, and advance in the internal hash table."
  (declare (indent 1))
  `(puthash ',op (list ,@(mapcan (lambda (kv) (list kv)) props))
            helixel--op-registry))

(defun helixel-edit-op-runner (op)
  "Return the runner function for OP from the operator registry."
  (plist-get (gethash op helixel--op-registry) :runner))

(defun helixel-edit-op-display (op &optional tx)
  "Return display label for OP, optionally evaluated with TX.
Reads the :display entry from the operator registry.
Falls back to `symbol-name'."
  (let ((d (plist-get (gethash op helixel--op-registry) :display)))
    (cond
     ((stringp d) d)
     ((functionp d) (or (funcall d tx) (symbol-name op)))
     (t (symbol-name op)))))

(defun helixel-edit-op-advance (op)
  "Return the :repeat-advance property for OP, or nil."
  (plist-get (gethash op helixel--op-registry) :repeat-advance))

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

(provide 'helixel-data)
;;; helixel-data.el ends here
