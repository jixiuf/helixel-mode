;;; helixel-action.el --- Action tracking & ring  -*- lexical-binding: t; -*-

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
;; Action data model for helixel-mode.
;;
;; Every editing operation (movement, search, find-char, textobj) records
;; an *action* — a plist with keys like :category, :subcat, :dir, :marker.
;;
;; The live action (`helixel--action') tracks the current operation.
;; Completed actions are pushed to `helixel--action-ring' for:
;;   - session jumping (`;')
;;   - repeat detection (`n' / `N')
;;   - history browsing (`C-u n' / `C-u N')
;;
;; Note: direction for n/N repeat is managed by `helixel--repeat-dir'
;; in helixel-search.el — NOT by `helixel--action :dir'.  The :dir key
;; on actions is set at creation and never mutated after commit; it
;; serves as a historical record for display purposes only.
;;
;; ── KEY INVARIANT ──
;; Ring entries are INDEPENDENT from the live action.  Every push goes
;; through `helixel-action--ring-push' which deep-copies and deduplicates.
;; You may freely `plist-put' on `helixel--action' without affecting any
;; ring entry.
;; ── END ──

;;; Code:

(require 'cl-lib)
(require 'helixel-data)

(defvar helixel--inhibit-action-track)
(defvar helixel--selection-type)

;; ── Custom group ──

(defgroup helixel nil
  "Custom group for Helixel."
  :group 'helixel)

(defcustom helixel-action-ring-max 50
  "Maximum number of actions stored in `helixel--action-ring'."
  :type 'integer
  :group 'helixel)

(defcustom helixel-action-cycle-categories
  '(movement textobj search find-char edit)
  "Action :category symbols that `;' (`helixel-action-cycle') navigates.
Categories not listed here are invisible during cycling (e.g. `state'
for cancel sentinels).  They remain in the ring for dedup purposes."
  :type '(repeat (choice
                  (const :tag "Movement" movement)
                  (const :tag "Text object" textobj)
                  (const :tag "Search" search)
                  (const :tag "Find char" find-char)
                  (const :tag "Edit" edit)))
  :group 'helixel)

(defcustom helixel-jump-list-max 100
  "Maximum number of entries in `helixel--jump-list'."
  :type 'integer
  :group 'helixel)

(defcustom helixel-jump-categories
  '(movement textobj search find-char edit goto user jump)
  "Action :category symbols that are recorded into `helixel--jump-list'.
Categories not listed here do not generate jump entries.
See also `helixel-jump-cycle-categories' for controlling
`helixel-jump-backward' / `helixel-jump-forward' visibility."
  :type '(repeat (choice
                  (const :tag "Movement" movement)
                  (const :tag "Text object" textobj)
                  (const :tag "Search" search)
                  (const :tag "Find char" find-char)
                  (const :tag "Edit" edit)
                  (const :tag "Goto" goto)
                  (const :tag "User" user)
                  (const :tag "Jump return" jump)))
  :group 'helixel)

(defcustom helixel-jump-cycle-categories
  '(movement textobj search find-char edit goto user jump)
  "Action :category symbols visible during jump cycling.
Only categories listed here are shown when pressing
`helixel-jump-backward' or `helixel-jump-forward'.
Entries from other categories remain in `helixel--jump-list' but are skipped.
This can be narrower than `helixel-jump-categories' to record everything
while only navigating a subset."
  :type '(repeat (choice
                  (const :tag "Movement" movement)
                  (const :tag "Text object" textobj)
                  (const :tag "Search" search)
                  (const :tag "Find char" find-char)
                  (const :tag "Edit" edit)
                  (const :tag "Goto" goto)
                  (const :tag "User" user)
                  (const :tag "Jump return" jump)))
  :group 'helixel)

;; ── Buffer-local state ──

(defvar-local helixel--action nil
  "Current active action plist.

Data structure — actions are plists.  Universal keys plus one
category-specific sub-plist keyed by :category symbol:

  Universal (all actions):
    :category  symbol   movement | search | find-char | textobj | state
    :subcat    symbol   char|line|word|WORD|goto|next|till|pair|quote|etc.
    :marker    marker   Session start position (for `;' jump).
    :display   boolean  t = committed to ring (history listing).

  Category sub-plists (optional, key matches :category):
    :search    plist    (:pattern \"regexp\" :dir forward|backward)
    :find-char plist    (:type next|till :char CHAR :dir forward|backward)
    :movement  plist    (:dir forward|backward)

External code must use the accessor functions below instead of
direct `plist-get'/`plist-put' on this variable:
  (helixel--live-get :category)                  ;; flat read
  (helixel--live-put :display t)                 ;; flat write
  (helixel--live-cat-get :type)                  ;; cat sub-plist read (live)
  (helixel--live-search-set pattern dir)         ;; set :search on live
  (helixel--live-find-char-set type char dir)    ;; set :find-char on live
  (helixel--live-cat-set-dir dir)                ;; set :dir on live
  (helixel--action-get ring-entry :subcat)       ;; flat read from ring
  (helixel--action-cat-get ring-entry :dir)      ;; cat read from ring

Internal helixel-action.el code may use plist-get/put directly.")

(defvar-local helixel--action-ring nil
  "Ring of actions, most recent first.  Each entry is a plist.
Shared by session jump (`;'), repeat (`n'/`N'), and history (`C-u n').
Capped at `helixel-action-ring-max'.")

(defvar-local helixel--action-pos nil
  "Ring position for `;' cycling: nil=live, 0=newest, 1=next, ...")

;; ── Global jump list ──

(defvar helixel--jump-list nil
  "Global jump list for `helixel-jump-backward' / `helixel-jump-forward'.
Most recent first.
Each entry: (:marker MARKER :buffer BUFFER :category CAT :subcat SUBCAT)")

(defvar helixel--jump-pos nil
  "Current position in `helixel--jump-list' for jump cycling.
nil = not cycling.  0 = newest (list head).  N = older.")

(defvar helixel-jump-cleanup-function nil
  "Function called after a successful jump to clean up selection state.
Set by helixel-common.el.  Takes no arguments.
Typically `helixel--clear-data'.")

(defvar helixel-action-push-functions nil
  "Abnormal hook run after an action is pushed to `helixel--action-ring'.
Each function is called with one argument, the action plist.
The jump-list subsystem subscribes here to mirror actions globally.")

;; ── Accessor API ──
;;
;; External code (search, common) must use these instead of raw
;; plist-get/plist-put on helixel--action.

(defsubst helixel--live-get (key)
  "Read KEY from the live action `helixel--action'."
  (plist-get helixel--action key))

(defun helixel--live-put (key value)
  "Set KEY to VALUE on the live action `helixel--action'.
Safe: the live action is never aliased to ring entries."
  (plist-put helixel--action key value))

(defsubst helixel--action-get (action key)
  "Read KEY from ACTION plist (a ring entry or repeat-data plist)."
  (plist-get action key))

(defun helixel--live-cat-get (key)
  "Read KEY from the live action's category sub-plist.
The sub-plist is keyed by the keyword form of :category'."
  (let ((cat (plist-get helixel--action :category)))
    (when cat
      (plist-get (plist-get helixel--action
                            (intern (format ":%s" cat)))
                 key))))

;; ── Atomic data setters ──
;;
;; Each setter requires ALL fields for its category — the function
;; signature IS the contract.  No generic key-value writer exists.

(defun helixel--live-search-set (pattern dir)
  "Set :search sub-plist on the live action.  PATTERN and DIR required."
  (plist-put helixel--action :search `(:pattern ,pattern :dir ,dir)))

(defun helixel--live-find-char-set (type char dir)
  "Set :find-char sub-plist.  TYPE, CHAR, and DIR all required."
  (plist-put helixel--action :find-char `(:type ,type :char ,char :dir ,dir)))

(defun helixel--live-cat-set-dir (dir)
  "Set direction to DIR in the live action's category sub-plist.
:dir is the only field shared across search, find-char, and movement.
No-op when `helixel--inhibit-action-track' is non-nil."
  (unless helixel--inhibit-action-track
    (let ((cat (plist-get helixel--action :category)))
      (when cat
        (let* ((kwd (intern (format ":%s" cat)))
               (sub (plist-get helixel--action kwd)))
          (plist-put helixel--action kwd (plist-put sub :dir dir)))))))

(defsubst helixel--action-cat-get (action key)
  "Read KEY from ACTION's category sub-plist."
  (let ((cat (plist-get action :category)))
    (when cat
      (plist-get (plist-get action
                            (intern (format ":%s" cat)))
                 key))))

(defun helixel--live-edit-set (tx)
  "Set :edit sub-plist on the live action to transaction TX.
TX is a plist (:op OP :sel SEL :payload PAYLOAD :marker MARKER)
as produced by `helixel-edit-make'."
  (plist-put helixel--action :edit tx))

;; ── Content comparison ──

(defun helixel-action--same-content-p (a1 a2)
  "Return non-nil if actions A1 and A2 have identical key content.
Compares universal keys and category sub-plists."
  (and a1 a2
       (eq (plist-get a1 :category) (plist-get a2 :category))
       (equal (plist-get a1 :subcat) (plist-get a2 :subcat))
       (equal (plist-get a1 :search) (plist-get a2 :search))
       (equal (plist-get a1 :find-char) (plist-get a2 :find-char))
       (equal (plist-get a1 :movement) (plist-get a2 :movement))
       (helixel-edit-equal-p (plist-get a1 :edit) (plist-get a2 :edit))
       (let ((m1 (plist-get a1 :marker))
             (m2 (plist-get a2 :marker)))
         (if (and (markerp m1) (markerp m2))
             (= (marker-position m1) (marker-position m2))
           t))))

;; ── Ring push (UNIFIED) ──
;;
;; All ring mutations go through this function.  It deep-copies,
;; deduplicates, and caps.  Callers never push or copy-tree directly.

(defun helixel-action--ring-cap ()
  "Truncate `helixel--action-ring' to `helixel-action-ring-max' entries.
Releases markers of evicted entries to prevent leaks."
  (when (> (length helixel--action-ring) helixel-action-ring-max)
    (let ((old (nthcdr helixel-action-ring-max helixel--action-ring)))
      (dolist (a old)
        (let ((m (plist-get a :marker)))
          (when (markerp m) (set-marker m nil)))))
    (setcdr (nthcdr (1- helixel-action-ring-max) helixel--action-ring) nil)))

(defun helixel-action--ring-push (action)
  "Push ACTION to `helixel--action-ring' with deep-copy and dedup.
Skips the push if the ring front already has identical key content
\(same universal keys and same category sub-plists).
Returns non-nil if the push actually happened.
Also pushes to `helixel--jump-list' if the category is in
`helixel-jump-categories'."
  (when action
    (let ((entry (copy-tree action))
          (dup (car helixel--action-ring)))
      ;; copy-tree does NOT deep-copy markers — ensure ring entries
      ;; get independent marker objects so the source can be freed safely.
      (let ((m (plist-get entry :marker)))
        (when (markerp m)
          (plist-put entry :marker
                     (copy-marker m (marker-insertion-type m)))))
      (unless (and dup (helixel-action--same-content-p dup entry))
        (push entry helixel--action-ring)
        (helixel-action--ring-cap)
        (run-hook-with-args 'helixel-action-push-functions entry)
        t))))

;; ── Jump list push ──

(defun helixel--jump-list-push (action)
  "Push ACTION to the global `helixel--jump-list' with buffer context.
Deduplicates against the jump list front based on same content and buffer.
Caps at `helixel-jump-list-max'.
Only pushes if ACTION's :category is in `helixel-jump-categories'.
Creates its own marker copy so the jump list entry is independent
of the action-ring entry."
  (when (and action (memq (plist-get action :category) helixel-jump-categories))
    (let* ((src-m (plist-get action :marker))
           (buf (or (when (markerp src-m) (marker-buffer src-m))
                    (current-buffer)))
           (m (if (markerp src-m)
                  (copy-marker src-m (marker-insertion-type src-m))
                src-m))
           (entry `(:marker ,m
                    :buffer ,buf
                    :category ,(plist-get action :category)
                    :subcat ,(plist-get action :subcat))))
      (unless (helixel--jump-same-content-p entry (car helixel--jump-list))
        (push entry helixel--jump-list)
        (setq helixel--jump-pos nil)
        (when (> (length helixel--jump-list) helixel-jump-list-max)
          (let ((tail (nthcdr helixel-jump-list-max helixel--jump-list)))
            (dolist (e tail)
              (let ((em (plist-get e :marker)))
                (when (markerp em) (set-marker em nil)))))
          (setcdr (nthcdr (1- helixel-jump-list-max)
                          helixel--jump-list) nil))))))

(defun helixel--jump-same-content-p (a b)
  "Return non-nil if jump entries A and B have identical content.
Compares :buffer, :category, :subcat, and marker position."
  (and a b
       (eq (plist-get a :buffer) (plist-get b :buffer))
       (eq (plist-get a :category) (plist-get b :category))
       (equal (plist-get a :subcat) (plist-get b :subcat))
       (let ((m1 (plist-get a :marker))
             (m2 (plist-get b :marker)))
         (if (and (markerp m1) (markerp m2))
             (= (marker-position m1) (marker-position m2))
           t))))

;; ── Ring commit ──

(defun helixel-action-commit ()
  "Commit `helixel--action' to `helixel--action-ring'.
Sets :display to t so the entry appears in history completion.
Uses `helixel-action--ring-push' which deep-copies and deduplicates."
  (when helixel--action
    (plist-put helixel--action :display t)
    (helixel-action--ring-push helixel--action)))

;; ── Validation ──

(defvar helixel--action-required-keys
  '((search . :search)
    (find-char . :find-char))
  "Alist mapping action :category to its required sub-plist key.
An action is invalid (not worth keeping) if its required sub-plist is nil.
Categories not listed here are always considered valid.")

(defun helixel--action-valid-p (action)
  "Return non-nil if ACTION has the required keys for its category.
Uses `helixel--action-required-keys' to determine what each category needs."
  (let* ((cat (plist-get action :category))
         (req (cdr (assq cat helixel--action-required-keys))))
    (or (null req)
        (plist-get action req))))

;; ── Display ──

(defun helixel-action-display (action)
  "Format ACTION plist for display in completion.
Returns \"/pat/\" or \"?pat?\" for search, \"f→X\" etc. for find-char,
and \"cat.subcat\" for other actions."
  (let ((cat (plist-get action :category)))
    (cond
     ((eq cat 'search)
      (let* ((sub (plist-get action :search))
             (dir (plist-get sub :dir))
             (pat (plist-get sub :pattern))
              (c (if (eq dir 'backward) ?\? ?/)))
        (format "%c%s%c" c pat c)))
     ((eq cat 'find-char)
      (let* ((sub (plist-get action :find-char))
             (type (plist-get sub :type))
             (char (plist-get sub :char))
             (dir (plist-get sub :dir)))
        (format "%c→%c"
                (if (eq type 'next)
                    (if (eq dir 'forward) ?f ?F)
                  (if (eq dir 'forward) ?t ?T))
                char)))
      ((eq cat 'edit)
       (helixel-edit-display (plist-get action :edit)))
     ((and (eq cat 'state) (eq (plist-get action :subcat) 'cancel))
      "C-g")
     (t (format "%s.%s" cat (plist-get action :subcat))))))

;; ── Start / continue an action ──

(defvar helixel--inhibit-action-track nil
  "When non-nil, `helixel-action-start' and visual tracking are no-ops.
Bound by `helixel-repeat-edit' so dot-repeat does not re-record actions
and pollute the action ring.")

(defun helixel-action-start (category subcat)
  "Start a new action of CATEGORY and SUBCAT.
Always pushes the previous valid `helixel--action' to ring.
Always creates a fresh marker at point.
Callers that need a specific marker should call
`helixel--live-put :marker' afterward.

No-op when `helixel--inhibit-action-track' is non-nil.

RING SAFETY: Old actions are deep-copied before pushing.
The new live action is a fresh plist, never aliased to any
ring entry."
  (unless helixel--inhibit-action-track
  (let* ((marker (point-marker))
         (action `(:category ,category :subcat ,subcat :marker ,marker)))
    ;; Any non-textobj action clears textobj selection state
    (when (and (eq helixel--selection-type 'textobj)
               (not (eq category 'textobj)))
      (setq helixel--selection-type nil))
    ;; Always push old action to ring if valid
    (when (and helixel--action
               (helixel--action-valid-p helixel--action))
      (helixel-action--ring-push helixel--action))
    ;; Replace live action
    (setq helixel--action action
          helixel--action-pos nil)
    action)))

;; ── Marker jump ──

(defun helixel--jump-to-marker (marker)
  "Set mark at MARKER (session start), keeping point unchanged.
MARKER must be a live marker (has a buffer).  Dead markers (e.g. from
killed buffers) are silently ignored."
  (when (and (markerp marker) (marker-buffer marker))
    (push-mark marker t t)))

;; ── Generic grouped-ring helpers ──
;;
;; Both `;' cycling (action ring) and C-o/C-i (jump list) share the
;; same core algorithm: walk a list, skip invisible entries, group
;; consecutive same-category entries, navigate via group-start.
;; These generic helpers are parameterized by visibility predicate
;; and same-group predicate.

(defun helixel--grouped-ring-group-start (list pos same-group-pred)
  "Return the oldest (largest) index in LIST of the group containing POS.
Consecutive entries where `same-group-pred' returns non-nil form a group.
SAME-GROUP-PRED is called with two successive entries."
  (let ((len (length list)))
    (while (and (< (1+ pos) len)
                (funcall same-group-pred (nth pos list) (nth (1+ pos) list)))
      (cl-incf pos))
    pos))

(defun helixel--grouped-ring-group-newest (list pos same-group-pred)
  "Return the newest (smallest) index in LIST of the group containing POS.
SAME-GROUP-PRED is called with two adjacent entries to test group
membership."
  (let ((i pos))
    (while (and (> i 0)
                (funcall same-group-pred (nth i list) (nth (1- i) list)))
      (cl-decf i))
    i))

(defun helixel--grouped-ring-visible-index (list pos visible-pred)
  "Return index of first visible entry starting at POS in LIST, or nil.
VISIBLE-PRED is called with each entry; the first one returning
non-nil is selected."
  (cl-loop for i from pos below (length list)
           when (funcall visible-pred (nth i list))
           return i))

(defun helixel--grouped-ring-visible-count (list visible-pred)
  "Count visible entries in LIST.
VISIBLE-PRED is called with each entry in LIST."
  (cl-loop for a in list
           when (funcall visible-pred a)
           count 1))

(defun helixel--grouped-ring-find (list pos direction visible-pred)
  "Find index of next visible entry in LIST from POS in DIRECTION.
LIST is searched for entries where VISIBLE-PRED returns non-nil.
DIRECTION: +1 = older (toward end), -1 = newer (toward 0).
Returns the index or nil."
  (let ((len (length list)))
    (cl-loop for i from (+ pos direction) by direction
             while (if (> direction 0) (< i len) (>= i 0))
             when (funcall visible-pred (nth i list))
             return i)))

;; ─── ; cycle helpers ───

(defun helixel-action--cycle-visible-p (action)
  "Return non-nil if ACTION should be visible during `;' cycling."
  (memq (plist-get action :category) helixel-action-cycle-categories))

(defun helixel-action--cycle-display (action pos ring)
  "Format cycling message: [POS/MAX] with display string for ACTION."
  (let* ((total (helixel--grouped-ring-visible-count
                 ring #'helixel-action--cycle-visible-p))
         (display-pos (1+ (cl-loop for i from 0 below pos
                                   count (helixel-action--cycle-visible-p
                                          (nth i ring))))))
    (format "[%d/%d] %s" display-pos total
            (helixel-action-display action))))

(defun helixel-action--cycle-show (pos ring)
  "Show the group-start action for the group containing RING[POS]."
  (let* ((gpos (helixel-action--cycle-group-start pos ring))
         (action (nth gpos ring)))
    (setq helixel--action-pos gpos)
    (helixel--jump-to-marker (plist-get action :marker))
    (message "%s" (helixel-action--cycle-display action gpos ring))))

(defun helixel-action--same-group-p (a b)
  "Return non-nil if A and B belong to the same display group.
Same group = same :category and same :subcat."
  (and a b
       (eq (helixel--action-get a :category) (helixel--action-get b :category))
       (eq (helixel--action-get a :subcat) (helixel--action-get b :subcat))))

(defun helixel-action--cycle-group-start (pos ring)
  "Return the group-start index in RING for the group containing POS.
Delegates to `helixel--grouped-ring-group-start' with
`helixel-action--same-group-p' as the same-group predicate."
  (helixel--grouped-ring-group-start ring pos #'helixel-action--same-group-p))

(defun helixel-action--cycle-group-newest (pos ring)
  "Return the newest index in RING for the group containing POS.
Delegates to `helixel--grouped-ring-group-newest' with
`helixel-action--same-group-p' as the same-group predicate."
  (helixel--grouped-ring-group-newest ring pos #'helixel-action--same-group-p))

(defun helixel-action--cycle-commit ()
  "Commit live action to ring if valid, discard otherwise.
Frees marker for invalid actions.  Returns t if pushed."
  (when helixel--action
    (prog1
        (if (helixel--action-valid-p helixel--action)
            (progn (helixel-action--ring-push helixel--action) t)
          (let ((m (plist-get helixel--action :marker)))
            (when (markerp m) (set-marker m nil)))
          nil)
      (setq helixel--action nil))))

;; ── Session cycling (`;') ──
;;
;; Bound to `;' in helixel-normal-map.  Jump targets are
;; reached via `helixel--jump-to-marker'.

(defun helixel-action-cycle (&optional arg)
  "Cycle through visible entries in `helixel--action-ring'.
Point stays unchanged — mark moves to show where each session started.
Filters via `helixel-action-cycle-categories' (e.g. state/cancel hidden).
Without prefix ARG: go to older action.
With prefix ARG (`C-u'): go to newer action or restore live session.
Bound to `;' in normal mode."
  (interactive "P")
   (if arg
       ;; C-u ; → go forward (newer)
       (cond
        ((and helixel--action-pos (> helixel--action-pos 0))
         (let* ((newest (helixel-action--cycle-group-newest
                         helixel--action-pos helixel--action-ring))
                (prev (when (> newest 0)
                        (helixel--grouped-ring-visible-index
                         helixel--action-ring (1- newest)
                         #'helixel-action--cycle-visible-p))))
           (if prev
               (helixel-action--cycle-show prev helixel--action-ring)
             (message "At newest"))))
        ((eq helixel--action-pos 0)
         (if helixel--action
             (progn
               (setq helixel--action-pos nil)
               (helixel--jump-to-marker (plist-get helixel--action :marker))
               (message "[live] %s" (helixel-action-display helixel--action)))
           (message "At newest")))
        (t (message "At newest")))
    ;; ; → go back (older)
    (cond
     (helixel--action-pos
      (let ((pos (helixel--grouped-ring-find
                  helixel--action-ring helixel--action-pos 1
                  #'helixel-action--cycle-visible-p)))
        (if pos
            (helixel-action--cycle-show pos helixel--action-ring)
          (message "No more"))))
     (helixel--action
      (helixel-action--cycle-commit)
      (let ((pos (helixel--grouped-ring-visible-index
                  helixel--action-ring 0 #'helixel-action--cycle-visible-p)))
        (if pos
            (helixel-action--cycle-show pos helixel--action-ring)
          (message "No saved actions"))))
     (helixel--action-ring
      (let ((pos (helixel--grouped-ring-visible-index
                  helixel--action-ring 0 #'helixel-action--cycle-visible-p)))
        (if pos
            (helixel-action--cycle-show pos helixel--action-ring)
          (message "No saved actions"))))
     (t (message "No saved actions")))))

;; ── Cancel action (C-g) ──

(defun helixel--cancel-action ()
  "Called on \\[keyboard-quit] to break session continuity.
Pushes the current meaningful action to ring (deep-copied), then resets it.
Also pushes a `state/cancel' sentinel to enable natural dedup: the next
same-type command won't be dedup'd against the previous session."
  (when helixel--action
    (when (helixel--action-valid-p helixel--action)
      (helixel-action--ring-push helixel--action))
    (let ((m (plist-get helixel--action :marker)))
      (when (markerp m) (set-marker m nil)))
    (setq helixel--action nil))
  ;; Push cancel sentinel — acts as session boundary for dedup.
  ;; Not visible in `;' cycling (state ∉ cycle-categories).
  (helixel-action--ring-push
   `(:category state :subcat cancel :marker ,(point-marker))))

;; ── Jump list public API ──

(defun helixel-register-jump (&optional category subcat)
  "Register current point as a jump position in `helixel--jump-list'.
CATEGORY defaults to \='user, SUBCAT defaults to \='jump.
Call this from any command to make its start position reachable via
`helixel-jump-backward' / `helixel-jump-forward'."
  (let ((cat (or category 'user))
        (sub (or subcat 'jump)))
    (let ((action `(:category ,cat
                    :subcat ,sub
                    :marker ,(point-marker))))
      (helixel--jump-list-push action))))

(defun helixel-define-jump-command (symbol)
  "Mark SYMBOL as a jump command.
Adds :before advice to call `helixel-register-jump' before SYMBOL runs,
so its position is automatically recorded in the jump list.
Also deactivates the mark so xref's (unless (region-active-p) (push-mark ...))
fires correctly instead of silently skipping when a region is active.
The advice is named `helixel-jump--before' on SYMBOL."
  (advice-add symbol :before
              (lambda (&rest _)
                (deactivate-mark t)
                (helixel-register-jump 'goto 'jump))
              '((name . helixel-jump--before))))

;; ── Jump display helpers ──

(defun helixel--jump-display (action)
  "Format jump entry ACTION for display during jump cycling."
  (let ((cat (plist-get action :category))
        (sub (plist-get action :subcat))
        (buf (plist-get action :buffer)))
    (format "%s.%s [%s]"
            (or cat ?\?)
            (or sub ?\?)
            (if (buffer-live-p buf)
                (buffer-name buf)
              "(dead)"))))

;; ── Jump cycle predicates ──

(defun helixel--jump-visible-p (action)
  "Return non-nil if ACTION is visible during jump cycling."
  (and (memq (plist-get action :category) helixel-jump-cycle-categories)
       (let ((m (plist-get action :marker))
             (buf (plist-get action :buffer)))
         (and (markerp m) (marker-buffer m) (buffer-live-p buf)))))

(defun helixel--jump-same-group-p (a b)
  "Return non-nil if A and B belong to the same jump group.
Same group = same :category, :subcat, and :buffer."
  (and a b
       (eq (plist-get a :category) (plist-get b :category))
       (eq (plist-get a :subcat) (plist-get b :subcat))
       (eq (plist-get a :buffer) (plist-get b :buffer))))

(defun helixel--jump-group-start (pos)
  "Return the group-start index for the jump entry at POS.
Delegates to `helixel--grouped-ring-group-start' with
`helixel--jump-same-group-p' as the same-group predicate."
  (helixel--grouped-ring-group-start helixel--jump-list pos
    #'helixel--jump-same-group-p))

(defun helixel--jump-group-newest (pos)
  "Return the newest index for the jump group containing POS.
Delegates to `helixel--grouped-ring-group-newest' with
`helixel--jump-same-group-p' as the same-group predicate."
  (helixel--grouped-ring-group-newest helixel--jump-list pos
    #'helixel--jump-same-group-p))

(defun helixel--jump-message (pos)
  "Format and message the current jump position POS.
POS is an index into `helixel--jump-list'."
  (let* ((action (nth pos helixel--jump-list))
         (total (helixel--grouped-ring-visible-count
                 helixel--jump-list #'helixel--jump-visible-p))
         (display-pos (1+ (cl-loop for i from 0 below pos
                                   count (helixel--jump-visible-p
                                          (nth i helixel--jump-list))))))
    (message "[%d/%d] %s" display-pos total
             (helixel--jump-display action))))

(defun helixel--jump-goto (pos)
  "Go to the group-start of jump entry at POS in `helixel--jump-list'.
Moves point, switching buffers if needed.
Returns non-nil on success.
If the group-start entry is dead, walks back to the last alive entry
in the same group."
  (let* ((gpos (helixel--jump-group-start pos))
         (action (nth gpos helixel--jump-list)))
    (while (and (not (helixel--jump-visible-p action))
                (> gpos 0)
                (helixel--jump-same-group-p
                 (nth (1- gpos) helixel--jump-list) action))
      (cl-decf gpos)
      (setq action (nth gpos helixel--jump-list)))
    (let ((buf (plist-get action :buffer))
          (m (plist-get action :marker)))
      (when (and (markerp m) (marker-buffer m) (buffer-live-p buf))
        (let ((cross-buffer (not (eq buf (current-buffer)))))
          (setq helixel--jump-pos gpos)
          (when cross-buffer
            (switch-to-buffer buf))
          (goto-char (marker-position m))
          (when (functionp helixel-jump-cleanup-function)
            (funcall helixel-jump-cleanup-function))
          t)))))

;; ── Jump commands (`helixel-jump-backward'/`helixel-jump-forward') ──

(defun helixel-jump-backward ()
  "Jump to the previous (older) position in the global jump list.
Moves point to the recorded position, switching buffers if needed.
Pushes a return entry so `helixel-jump-forward' can navigate forward
to the starting point."
  (interactive)
  (let* ((saved-pos helixel--jump-pos))
    (helixel-register-jump 'jump 'return)
    (setq helixel--jump-pos (if saved-pos (1+ saved-pos) nil))
    (let* ((start (if helixel--jump-pos helixel--jump-pos 0))
           (pos (helixel--grouped-ring-find
                 helixel--jump-list start 1 #'helixel--jump-visible-p))
           (found nil))
      (while pos
        (if (helixel--jump-goto pos)
            (setq found t pos nil)
          (setq helixel--jump-pos pos
                pos (helixel--grouped-ring-find
                     helixel--jump-list pos 1 #'helixel--jump-visible-p))))
      (unless found
        (message (if helixel--jump-pos "At oldest" "No jump positions"))))))

(defun helixel-jump-forward ()
  "Jump to the next (newer) position in the global jump list.
Moves point to the recorded position, switching buffers if needed.
Bound to `helixel-jump-forward' in normal mode."
  (interactive)
  (if helixel--jump-pos
      (let ((newest (helixel--jump-group-newest helixel--jump-pos))
            (pos nil))
        (while (and (not pos) (> newest 0))
          (setq pos (helixel--grouped-ring-visible-index
                     helixel--jump-list (1- newest)
                     #'helixel--jump-visible-p))
          (when pos
            (let ((success (helixel--jump-goto pos)))
              (unless success
                (setq helixel--jump-pos pos
                      newest pos
                      pos nil)))))
        (unless pos
          (message "At newest")))
    (message "At newest")))

(provide 'helixel-action)
;;; helixel-action.el ends here
