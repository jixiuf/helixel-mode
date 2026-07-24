;;; helixel-motion.el --- Motion recording and repeat for helixel-mode -*- lexical-binding: t; -*-

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
;; Motion recording and motion-repeat infrastructure for helixel-mode.
;;
;; Contents:
;;   — `helixel--last-motion' struct: the last repeatable motion,
;;     consumed by `helixel-repeat-last-motion' (motion repeat) and
;;     the search repeat commands.
;;   — Motion repeat/select category defcustoms.
;;   — `helixel-record-motion' + `helixel--record-movement-motion'.
;;   — Motion repeater registry: extensible dispatch for
;;     `helixel-repeat-last-motion'.
;;   — Command-reverse property: direction-flipped counterparts of
;;     movement commands.
;;   — `helixel-repeat-last-motion' (the \=`,\=' repeat command) +
;;     `helixel--motion-flip-dir' (\=`-,\=' permanent direction flip).
;;
;; Depends only on `helixel-core'.  Consumers: helixel-move,
;; helixel-search, helixel-next-error, helixel-textobj-engine/marks,
;; helixel-treesit-commands, helixel-mc-spawn, helixel-shims.

;;; Code:

(require 'cl-lib)
(require 'helixel-core)

;; ── Last-Motion Struct (unified motion + search state) ──
;;
;; The single struct for the last repeatable motion — consumed by both
;; \\[helixel-repeat-last-motion\\] (motion repeat) and
;; \\[helixel-search-repeat-next\\]/\\[helixel-search-repeat-reverse\\]
;; (search repeat).
;;
;; Two buffer-local variables hold this struct with different update
;; policies:
;;   helixel--last-motion-cmd — updated by EVERY motion (for
;;   \\[helixel-repeat-last-motion\\] repeat)
;;   helixel--active-search   — updated only by search/find-char
;;                                (for \\[helixel-search-repeat-next\\]/
;;                                \\[helixel-search-repeat-reverse\\],
;;                                survives intervening movements)
;;
(cl-defstruct (helixel--last-motion (:copier nil))
  "Self-contained record of the last repeatable motion.
Slots:
  CATEGORY    — 'movement, 'search, or 'find-char.
  SUBCAT      — 'pair, 'match, 'paragraph, 'sentence, 'function, or nil.
  DIR         — 'forward or 'backward.
  COMMAND     — command symbol (nil for search).
  PREFIX-ARG  — raw `current-prefix-arg' at record time.
  CHAR        — (find-char) the searched character.
  TYPE        — (find-char) 'next or 'till.
  PATTERN     — (search) the regexp string.
  ENTRY-KIND  — (search) 'insert, 'append, or nil.
  REGEXP      — (search) non-nil when search is regexp-based.
  DELIM-OPEN  — (pair) opener character.
  DELIM-CLOSE — (pair) closer character.
  DELIM         — (pair) function () → delimiter struct.
                  Captured at macro-expansion time; call at repeat
                  time to rebuild the delimiter for bounds queries.
  DELIM-INNER-P — (pair) non-nil for inner.
  DELIM-FORWARD-P — (pair) non-nil for forward.
  LAST-MATCH-DELIMITER — (match) `helixel-delimiter' struct from % jump.
  REVERSE-COMMAND — (movement) the opposite-direction command for
                     \=`-,' permanent flip, or nil."
  category subcat dir command prefix-arg
  char type pattern entry-kind
  (regexp t)
  delim delim-inner-p delim-forward-p
  last-match-delimiter
  reverse-command)

(defcustom helixel-motion-repeat-categories
  '((movement . pair) (movement . match) (movement . paragraph)
    (movement . sentence) (movement . function) (movement . scroll)
    (movement . class) (movement . parameter)
    (movement . comment) (movement . loop)
    (movement . conditional) (movement . sibling)
    (movement . grow-shrink)
    search find-char next-error mc-spawn textobj)
  "Motion categories that \\[helixel-repeat-last-motion] can repeat.
Each element is either a plain category symbol (matches all
subcats) or a cons (CATEGORY . SUBCAT) for precise matching —
the same format as `helixel-action-cycle-categories'.

Plain symbols \='search, \='find-char, and \='mc-spawn match
their respective commands.  Cons entries like (movement . pair)
match only the specified subcat under that category.

Set to nil to disable motion repeat entirely."
  :type '(repeat (choice symbol (cons symbol symbol)))
  :group 'helixel)

(defcustom helixel-motion-select-categories
  '((movement . word) (movement . WORD) (movement . symbol)
    (movement . pair)
    (movement . function) (movement . class)
    (movement . parameter) (movement . comment)
    (movement . loop) (movement . conditional)
    (movement . sibling) (movement . grow-shrink))
  "Motion subcats that auto-activate visual selection.
When a motion's (CATEGORY . SUBCAT) or plain CATEGORY appears in
this list, the movement creates a visible region (selection).
Otherwise it only moves point without activating the mark.

Used by thing-move commands and treesit sibling/mark-* commands.
Set to nil to disable selection for all motions."
  :type '(repeat (choice symbol (cons symbol symbol)))
  :group 'helixel)

(defun helixel--motion-select-category-p (category subcat)
  "Return t if (CATEGORY . SUBCAT) appears in `helixel-motion-select-categories'."
  (helixel--category-match-p category subcat helixel-motion-select-categories))

(defvar-local helixel--last-motion-cmd nil
  "The last motion, nil or a `helixel--last-motion' struct.
Set by eligible movement commands (pair, match, paragraph,
sentence, function subcats) and find-char / search commands.
Read by `helixel-repeat-last-motion' and its accessors.")

(defvar-local helixel--motion-permanent-flip nil
  "When non-nil, reverses the motion repeat direction.
\\[helixel-repeat-last-motion] repeats the last motion in
reversed direction.  Toggled by \\=`-,'.
Analogous to `helixel--repeat-permanent-flip' for
\\[helixel-repeat-edit].")

(defun helixel-record-motion (cmd &rest extra-kv)
  "Record CMD as the last motion, with EXTRA-KV as keyword arguments.

EXTRA-KV accepts: :category :subcat :dir :char :type :pattern
:entry-kind :delim :delim-inner-p :delim-forward-p
:last-match-delimiter :reverse-command.

Respects `helixel-motion-repeat-categories': when :category and
:subcat don't match, recording is silently skipped.

Resets `helixel--motion-permanent-flip' so a fresh motion starts
with its recorded direction."
  (let ((cat (plist-get extra-kv :category))
        (sub (plist-get extra-kv :subcat)))
    (when (or (not cat)
              (helixel--category-match-p
               cat sub helixel-motion-repeat-categories))
      (setq helixel--last-motion-cmd
            (apply #'make-helixel--last-motion
                   :command cmd :prefix-arg current-prefix-arg
                   extra-kv))
      ;; New motion resets the permanent direction flip.
      (setq helixel--motion-permanent-flip nil))))

(defun helixel--record-movement-motion
    (cmd subcat origin &optional motion-extra)
  "Record CMD as the last motion for movement SUBCAT.
Determines :dir from (point) vs ORIGIN — captures direction
from actual cursor movement.  MOTION-EXTRA is an optional plist
of extra keys passed directly by the caller.
Keys commonly found in MOTION-EXTRA:
  :reverse-command    — opposite-direction command for \=`-,' flip.
  Other pair-specific keys for delimiter movements.

Called from the code injected by `helixel-define-command'
for :category movement commands."
  (let* ((dir (if (> (point) origin) 'forward 'backward)))
    (apply #'helixel-record-motion cmd
           :category 'movement :subcat subcat :dir dir
           motion-extra)))

;; ── Motion Repeater Registry ──
;;
;; Extensible dispatch for `helixel-repeat-last-motion'.
;; ── Motion Repeater Registry ──
;;
;; Motion repeaters are stored in a private hash table (same pattern
;; as kind/op registries).  Third-party packages register repeater
;; functions for custom categories via `helixel-register-motion-repeater'.

(defvar helixel--motion-repeater-registry (make-hash-table :test #'eq)
  "Hash table: category symbol → subcat→fn alist for motion replay.
Used by `helixel-register-motion-repeater' and
`helixel--lookup-motion-repeater'.")

(defun helixel-register-motion-repeater (category subcat fn)
  "Store FN as the motion repeater for (CATEGORY . SUBCAT).
CATEGORY is a symbol like \='movement, \='search, or \='find-char.
SUBCAT is a symbol like \='pair, \='match, or nil for \='any subcat\='.
FN receives the `helixel--last-motion' struct and should replay it.

Stored in `helixel--motion-repeater-registry' as a subcat→fn alist
per category.  Later registrations (specific subcat) push to the
front; `assq' finds the first match, so specific entries take priority
over nil-subcat fallbacks."
  (let* ((alist (gethash category helixel--motion-repeater-registry))
         (entry (cons subcat fn)))
    (puthash category (cons entry alist)
             helixel--motion-repeater-registry)))

(defsubst helixel--lookup-motion-repeater (rec)
  "Return the repeater function for motion REC, or nil.
Looks up SUBCAT first (specific), then falls back to nil (any)."
  (let* ((cat (helixel--last-motion-category rec))
         (sub (helixel--last-motion-subcat rec))
         (alist (gethash cat helixel--motion-repeater-registry)))
    (cdr (or (assq sub alist)
             (assq nil alist)))))

;; ── Command-reverse property ──
;;
;; When \=`-,', permanently flips the direction, the movement
;; motion repeater reads the `helixel-command-reverse' property
;; on each command to find its opposite-direction counterpart.
;; Only movement commands carry this property — it is set by the
;; movement-definition macros alongside `helixel-command'.
;; Search, find-char, and match repeater functions already read
;; direction from the struct and don't need reverse commands.
;;
;; For motion-repeat (\[helixel-repeat-last-motion]), the reverse
;; command is carried directly on `helixel--last-motion' as the
;; `:reverse-command' slot — no lookup needed.
;; For dot-repeat flip-dir, the `flip-dir-fn' lambda reads
;; `(get cmd 'helixel-command-reverse)' from each movement command.

(defun helixel-register-motion-reverse (cmd reverse-cmd)
  "Store REVERSE-CMD as the direction-flipped counterpart of CMD.
Both are command symbols.  Called by movement definition macros.
Sets the `helixel-command-reverse' symbol property on CMD."
  (put cmd 'helixel-command-reverse reverse-cmd))

(defsubst helixel--motion-reverse-lookup (cmd)
  "Return the reverse command for CMD, or nil if not registered.
Reads the `helixel-command-reverse' symbol property."
  (get cmd 'helixel-command-reverse))

;; ── Motion repeat command ──

(defun helixel-repeat-last-motion (&optional raw-prefix)
  "Repeat the last motion (f, t, /, ?, \\=`%', \\=`[', \\=`]', \\=`{', \\=`}').
Reads self-contained replay data from `helixel--last-motion-cmd'.
The stored category+subcat is checked against
`helixel-motion-repeat-categories' via `helixel--category-match-p'.
Dispatches via `helixel-register-motion-repeater' — extend by
calling it with (CATEGORY SUBCAT FN).
Never consults the global `helixel--active-search'.

Prefix RAW-PREFIX semantics:
  \\=`-,'    — permanently flip direction (like N for search)
  Subsequent , repeats in the flipped direction.
  \\=`-,' again flips back.
  \\=`-3,'  — repeat 3 times in flipped direction.
  \\=`3,'   — repeat 3 times in stored direction.

Direction flip works for search, find-char, match, and movement
categories.  Movement commands use the `helixel-motion-reverse'
symbol property on the command to find the opposite command."
  (interactive "P")
  (helixel--with-command helixel-repeat-last-motion
    (let ((rec helixel--last-motion-cmd)
          (flip-p (or (eq raw-prefix '-)
                      (and (integerp raw-prefix)
                           (< raw-prefix 0))))
          (repeat-n (cond ((not raw-prefix) 1)
                          ((eq raw-prefix '-) 1)
                          ((integerp raw-prefix) (abs raw-prefix))
                          (t 1))))
      (unless rec
        (user-error "No motion to repeat"))
      (unless (helixel--category-match-p
               (helixel--last-motion-category rec)
               (helixel--last-motion-subcat rec)
               helixel-motion-repeat-categories)
        (user-error
         "Last motion `%s' is not in `helixel-motion-repeat-categories'"
         (or (helixel--last-motion-subcat rec)
             (helixel--last-motion-category rec))))
      ;; Permanently flip direction on \\=`-,' (like \\=`-.' for edit repeat).
      (when flip-p
        (helixel--motion-flip-dir rec))
      (if-let* ((fn (helixel--lookup-motion-repeater rec)))
          (dotimes (_ repeat-n)
            (funcall fn rec))
        (user-error "No repeater registered for category `%s'"
                    (helixel--last-motion-category rec))))))

;; ── Motion direction flip (for \\=`-,' permanent flip) ──

(defun helixel--motion-flip-dir (rec)
  "Toggle `helixel--motion-permanent-flip' and flip :dir in REC.
REC is a `helixel--last-motion' struct — modified in-place.
Also flips subcat-specific direction slots (:delim-forward-p for
pair motions, :delim-inner-p flips when both are set).
Called by `helixel-repeat-last-motion' on \\=`-,' prefix."
  (setq helixel--motion-permanent-flip
        (not helixel--motion-permanent-flip))
  (let ((subcat (helixel--last-motion-subcat rec)))
    (setf (helixel--last-motion-dir rec)
          (if (eq (helixel--last-motion-dir rec) 'forward)
              'backward 'forward))
    ;; For pair motions, also flip the forward/backward flag
    ;; so the motion-skip-past and rebuild-delimiter helpers
    ;; see the correct direction.
    (when (eq subcat 'pair)
      (let ((fwd (helixel--last-motion-delim-forward-p rec)))
        (when (memq fwd '(t nil))
          (setf (helixel--last-motion-delim-forward-p rec) (not fwd)))))))
(provide 'helixel-motion)
;;; helixel-motion.el ends here
