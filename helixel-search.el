;;; helixel-search.el --- search & find-char engine  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

;; Author: jixiuf

;; ── Forward declarations for variables in later-loaded modules ──
(defvar helixel--event-ring)
(defvar helixel--live-event)

;; ── Cross-module forward declarations ──
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
;; Search and find-char for helixel-mode.
;;
;; Keybindings in normal state:
;;   /  ?        prompt then isearch-regexp forward/backward
;;   *  #        search for symbol at point forward/backward
;;   f  t  F  T  find-char/till-char forward/backward
;;   n  N        repeat last search or find (N toggles direction)

;;; Code:

(require 'helixel-state)
(require 'helixel-core)
(require 'helixel-macros)
(require 'helixel-repeat)
(require 'helixel-move)

;; ---------------------------------------------------------------------------
;; Groups and customs

(defgroup helixel-search nil
  "Search and find-char for helixel-mode."
  :group 'helixel)

(defcustom helixel-search-repeat-categories '(search find-char)
  "Action :category symbols that `helixel-search-repeat-next' can repeat.
Supported values: `search' and `find-char'."
  :type '(repeat (choice
                  (const :tag "Search (/ ? * #)" search)
                  (const :tag "Find-char (f F t T)" find-char)))
  :set (lambda (sym val)
         (dolist (cat val)
           (unless (memq cat '(search find-char))
             (display-warning 'helixel-search
                              (format "Unsupported repeat category: %s" cat))))
         (set-default sym val))
  :group 'helixel-search)
;; ---------------------------------------------------------------------------
;; Active Search — single mutable search state
;;
;; `helixel--active-search' replaces the old `helixel--repeat-data' +
;; `helixel--repeat-dir' pair.  It's the single source of truth for
;; what n/N repeats and in which direction.
;;
;; Set by /, ?, *, #, f, F, t, T, C-u n/N
;; Read by n/N commands and `.` / `,` repeat
;;
;; :dir is MUTABLE — N flips it.  Event-ring entries are immutable
;; snapshots and never store mutable state.

(defvar-local helixel--active-search nil
  "Active repeat target as a plist with keys:
:category — `search' or `find-char'
:pattern  — regexp string (search only)
:dir      — `forward' or `backward' (mutable — N flips it)
:type     — `next' or `till' (find-char only)
:char     — character (find-char only)
:entry-kind — `insert' / `append' / nil")

;; ── Active-search accessors (delegate to `helixel--active-search') ──
;;
;; All access to `helixel--active-search' plist goes through these
;; functions — no raw `plist-get' outside this block.  This keeps
;; ctx-lint clean and makes refactoring to a struct trivial.

(defsubst helixel-search--active-category ()
  "Return :category from `helixel--active-search'."
  (plist-get helixel--active-search :category))

(defsubst helixel-search--active-pattern ()
  "Return :pattern from `helixel--active-search'."
  (plist-get helixel--active-search :pattern))

(defsubst helixel-search--active-type ()
  "Return :type from `helixel--active-search'."
  (plist-get helixel--active-search :type))

(defsubst helixel-search--active-char ()
  "Return :char from `helixel--active-search'."
  (plist-get helixel--active-search :char))

(defsubst helixel-search--current-dir ()
  "Return current repeat direction from `helixel--active-search'.
Defaults to \='forward' when the search state has no direction set."
  (or (plist-get helixel--active-search :dir) 'forward))

(defun helixel-search--flip-dir ()
  "Toggle repeat direction in `helixel--active-search'."
  (let* ((old (helixel-search--current-dir))
         (new (if (eq old 'forward) 'backward 'forward)))
    (setq helixel--active-search
          (plist-put (or (copy-sequence helixel--active-search)
                         (list :dir new))
                     :dir new))))

(defun helixel-search--set-dir (dir)
  "Set DIR in `helixel--active-search'."
  (setq helixel--active-search
        (plist-put (or (copy-sequence helixel--active-search)
                       (list :dir dir))
                   :dir dir)))


;; ---------------------------------------------------------------------------
;; Direction sync on ring entries

;; ---------------------------------------------------------------------------
;; Isearch helpers

(defvar helixel-search--had-region nil
  "Non-nil if a region was active before the search started.
Let-bound by `helixel-search--at-point'.")

;; ---------------------------------------------------------------------------
;; Isearch-compatible search helper — used by n/N repeat and . replay
;;
;; `isearch-search-string' respects all isearch settings:
;;   case-fold-search, isearch-invisible, isearch-regexp-function, etc.
;; This ensures `.` repeat uses the same search behavior as
;; the original / ? search, including case folding and hidden chars.

(defun helixel-search--search (pattern dir &optional bound noerror)
  "Search for PATTERN in DIR using isearch-compatible settings.
DIR is \=`forward' or \=`backward'.
BOUND limits the search range (nil = whole buffer).
Pattern is searched as a regexp (isearch-regexp = t).
Signals \=`search-failed' when not found (NOERROR is nil).
Returns the match position (point moves to \=`match-end')."
  (let ((isearch-string pattern)
        (isearch-regexp t)
        (isearch-forward (eq dir 'forward)))
    (isearch-search-string pattern bound noerror)))

;; ---------------------------------------------------------------------------
;; Selection context for `.` repeat

(defun helixel-search--set-sel-ctx ()
  "Store the current search in `helixel--pending-sel'.
So the next edit command (c/d/y) records it for `.` and `,` repeat."
  (when-let* ((s helixel--active-search)
              (pat (helixel-search--active-pattern))
              (dir (helixel-search--current-dir)))
    (helixel--pending-sel-set
          (helixel-sel-create
           'search `(:pattern ,pat :dir ,dir)
           #'helixel--recreate-search
           (lambda (c)
             (concat "/" (or (helixel-sel-search-pattern c) "?")))
           :advance #'helixel--repeat-advance-search))))

(defun helixel-search--done-hook ()
  "Hook called at the end of isearch to mark the match."
  (remove-hook 'isearch-mode-end-hook #'helixel-search--done-hook t)
  (when (and isearch-success isearch-string
             (not (string-empty-p isearch-string)))
    (let ((dir (if isearch-forward 'forward 'backward)))
      (helixel-event-commit)
      
      (setq helixel--active-search
            `(:category search :pattern ,isearch-string :dir ,dir))))
  (helixel-search--handle-done helixel-search--had-region)
  (helixel-search--set-sel-ctx))

(defun helixel-search--handle-done (_had-region)
  "Handle region after isearch finishes.
Always activates the mark on the match for visual feedback.
_HAD-REGION is ignored (kept for signature compatibility)."
  (when (and isearch-success isearch-other-end)
    (unless (eq helixel--current-state 'visual)
      (set-marker (mark-marker) isearch-other-end))
    (activate-mark)
    (setq transient-mark-mode (cons 'only t))))

;; ---------------------------------------------------------------------------
;; / ?  — prompt isearch-regexp

(helixel-define-command helixel-search-forward
  (:category search :subcat search :clear-highlights nil)
  (add-hook 'isearch-mode-end-hook #'helixel-search--done-hook 0 t)
  (call-interactively #'isearch-forward-regexp))

(helixel-define-command helixel-search-backward
  (:category search :subcat search :clear-highlights nil)
  (add-hook 'isearch-mode-end-hook #'helixel-search--done-hook 0 t)
  (call-interactively #'isearch-backward-regexp))

;; ---------------------------------------------------------------------------
;; * #  — symbol at point

(defun helixel-search--bounds-at-point ()
  "Return (BEG . END) of the thing to search for at point.
If there is a single-line region, use it; otherwise use the symbol at point."
  (if (and (region-active-p)
           (= (line-number-at-pos (region-end))
              (line-number-at-pos (region-beginning))))
      (cons (region-beginning) (region-end))
    (or (bounds-of-thing-at-point 'symbol)
        (user-error "No symbol at point"))))

(defun helixel-search--extract-regex (bounds)
  "Build a word-bounded regexp from the text in BOUNDS."
  (let ((text (buffer-substring-no-properties (car bounds) (cdr bounds)))
        beg end)
    (save-excursion
      (goto-char (car bounds))
      (catch 'done
        (dolist (test '("\\_<" "\\<" "\\b"))
          (when (looking-at-p test)
            (setq beg test)
            (throw 'done nil))))
      (goto-char (cdr bounds))
      (catch 'done
        (dolist (test '("\\_>" "\\>" "\\b"))
          (when (looking-at-p test)
            (setq end test)
            (throw 'done nil)))))
    (concat (or beg "") (regexp-quote text) (or end ""))))

(defun helixel-search--at-point (dir)
  "Search for symbol at point in direction DIR (>0 forward, <0 backward)."
  (let* ((helixel-search--had-region (region-active-p))
         (bounds (helixel-search--bounds-at-point))
         (inhibit-redisplay t)
         (isearch-wrap-pause 'no-ding))
    (add-hook 'isearch-mode-end-hook #'helixel-search--done-hook 0 t)
    (if (< dir 0)
        (progn
          (goto-char (if (= (point-min) (car bounds))
                         (point-max)
                       (1- (car bounds))))
          (call-interactively #'isearch-backward-regexp))
      (goto-char (cdr bounds))
      (call-interactively #'isearch-forward-regexp))
    (let ((text (helixel-search--extract-regex bounds)))
      (setq isearch-regexp t)
      (setq isearch-yank-flag t)
      (isearch-process-search-string
       text (mapconcat #'isearch-text-char-description text "")))
    (isearch-exit)))

(helixel-define-command helixel-search-at-point-next
  (:category search :subcat search :clear-highlights nil)
  (helixel-search--at-point 1))

(helixel-define-command helixel-search-at-point-prev
  (:category search :subcat search :clear-highlights nil)
  (helixel-search--at-point -1))

;; ---------------------------------------------------------------------------
;; Isearch repeat

(defun helixel-search--isearch-repeat (dir)
  "Repeat isearch in direction DIR (>0 forward, <0 backward).
Reads pattern from `helixel--active-search'."
  (let ((inhibit-redisplay t)
        (isearch-wrap-pause 'no-ding)
        (isearch-repeat-on-direction-change t)
        (had-region (region-active-p)))
    (when-let* ((pat (helixel-search--active-pattern)))
      (setq isearch-string pat
            isearch-regexp t
            isearch-forward (eq (helixel-search--current-dir) 'forward)))
    (if (< dir 0)
        (isearch-repeat-backward (- dir))
      (isearch-repeat-forward dir))
    (helixel-search--handle-done had-region)
    (helixel-search--set-sel-ctx)))

;; ---------------------------------------------------------------------------
;; Find-char: f F t T

(defun helixel-search--find-char-exec (char type dir)
  "Find CHAR as TYPE (`next' or `till') in direction DIR (>0 forward)."
  (let ((forwardp (> dir 0))
        (case-fold-search (if (char-uppercase-p char) nil case-fold-search))
        (current (point)))
    ;; For till: skip adjacent char before searching
    (when (eq type 'till)
      (if forwardp
          (when (eq (char-after) char) (forward-char))
        (when (eq (char-before) char) (backward-char))))
    (helixel--clear-highlights)
    (if forwardp
        (progn (search-forward (char-to-string char))
               (when (eq type 'till) (backward-char)))
      (search-backward (char-to-string char))
      (when (eq type 'till) (forward-char)))
    (unless (use-region-p)
      (push-mark current t 'activate))
    ;; Push find-char sel onto pending-selection stack.
    ;; The action command that follows (d, c, y) will pop it.
    (helixel--sel-push
     (helixel-sel-create 'find-char
       `(:char ,char :type ,type
         :dir ,(if forwardp 'forward 'backward)
         :inline-advance t)
       #'helixel--recreate-find-char
       (format "f%c" char)
       :advance #'helixel--repeat-advance-movement))
    (helixel-event-commit)
    
    (let ((dir (if forwardp 'forward 'backward)))
      (helixel-search--set-dir dir)
      (setq helixel--active-search
            `(:category find-char :type ,type :char ,char :dir ,dir)))))

(defun helixel-search--find-char-core (&optional _action dir)
  "Execute find-char in direction DIR.
Reads type/char from `helixel--active-search'.
The _action parameter is kept for caller compatibility but ignored."
  (let* ((type (helixel-search--active-type))
         (char (helixel-search--active-char)))
    (when (and type char)
      (let ((fdir (if (eq (or dir (helixel-search--current-dir)) 'forward)
                      'forward 'backward)))
        (let* ((case-fold-search
                (if (char-uppercase-p char) nil case-fold-search))
               (forwardp (eq fdir 'forward))
               (current (point)))
          (when (eq type 'till)
            (if forwardp (forward-char) (backward-char)))
          (helixel--clear-highlights)
          (if forwardp
              (progn (search-forward (char-to-string char))
                     (when (eq type 'till) (backward-char)))
            (search-backward (char-to-string char))
            (when (eq type 'till) (forward-char)))
          (unless (use-region-p)
            (push-mark current t 'activate)))))))

(defun helixel-find-next-char (char)
  "Find next CHAR forward."
  (interactive "c")
  (helixel--tracking-open 'find-char 'next)
  (helixel-search--find-char-exec char 'next 1))

(defun helixel-find-prev-char (char)
  "Find next CHAR backward."
  (interactive "c")
  (helixel--tracking-open 'find-char 'next)
  (helixel-search--find-char-exec char 'next -1))

(defun helixel-find-till-char (char)
  "Find till CHAR forward."
  (interactive "c")
  (helixel--tracking-open 'find-char 'till)
  (helixel-search--find-char-exec char 'till 1))

(defun helixel-find-prev-till-char (char)
  "Find till CHAR backward."
  (interactive "c")
  (helixel--tracking-open 'find-char 'till)
  (helixel-search--find-char-exec char 'till -1))

(defun helixel--recreate-search (ctx)
  "Replay search selection from CTX.
Finds the next match, activates the region on it.
If `helixel--search-advance-done' is t, skips the internal search
\(the advance function already positioned point and set `match-data').
If CTX has :entry-kind (insert or append), positions the cursor
at the appropriate offset within the match for insert-text ops."
  (let* ((pat (helixel-sel-search-pattern ctx))
         (dir (helixel-sel-search-dir ctx))
         (pre-skip-pos (point)))
    (unless pat
      (user-error "No search pattern to repeat"))
    (if helixel--search-advance-done
        (setq helixel--search-advance-done nil)
      ;; Internal search — only run when advance wasn't already done
      (when (and (helixel-sel-search-entry-kind ctx)
                 (let ((orig (point)))
                   (or (looking-at pat)
                       (save-excursion
                         (condition-case nil
                             (progn
                               (helixel-search--search
                                pat 'backward)
                               (let ((m-end (match-end 0))
                                     (m-beg (match-beginning 0)))
                                 (if (= m-beg m-end)
                                     (= (line-number-at-pos orig)
                                        (line-number-at-pos m-end))
                                   (<= (- orig m-end) (length pat)))))
                           (search-failed nil))))))
        (if (eq dir 'backward)
              (goto-char (max (point-min)
                              (1- (match-beginning 0))))
            (goto-char (if (= (match-beginning 0) (match-end 0))
                            (min (point-max) (1+ (match-end 0)))
                          (match-end 0))))
          (when (or (= (point) pre-skip-pos)
                    (and (eq dir 'forward) (= (point) (point-max)))
                    (and (eq dir 'backward) (= (point) (point-min))))
            (user-error "No more matches for %s" pat)))
      (condition-case nil
          (helixel-search--search pat dir)
        (search-failed
         (user-error "Search pattern not found: %s" pat))))
    (push-mark (match-beginning 0) t t)
    (goto-char (match-end 0))
    (setq helixel--selection-type 'char)
    (when-let* ((entry-kind (helixel-sel-search-entry-kind ctx)))
      (let* ((base (if (eq entry-kind 'append)
                       (match-end 0)
                     (match-beginning 0)))
             (cursor-offset (or (helixel-sel-search-cursor-offset ctx) 0)))
        (goto-char (+ base cursor-offset))))))

(defun helixel--recreate-find-char (_ctx)
  "Recreate a find-char selection at point for dot-repeat.
Uses `helixel-search--find-char-core' which reads the character
and type from the action ring, searches for the next match from
the current cursor position, and creates the region.
The search IS the advance (inline — no separate advance fn needed)."
  (let ((helixel--inhibit-repeat-record t)
        (helixel--inhibit-action-track t))
    (helixel-search--find-char-core nil (helixel-search--current-dir))
    t))

(defun helixel-find-repeat ()
  "Repeat the last find-char in the current direction.
Uses `helixel--active-search' for type/char/dir.
Session-continuity: uses original type (next/till) from
active-search so `;' jumps to the original f/F/t/T position."
  (interactive)
  (let* ((type (helixel-search--active-type))
         (char (helixel-search--active-char))
         (dir (helixel-search--current-dir)))
    (if (and type char)
        (progn
          (helixel--tracking-open 'find-char type)
          (helixel-search--find-char-core nil dir))
      (message "No find-char to repeat"))))

;; ---------------------------------------------------------------------------
;; n / N  — repeat
;;
;; n repeats the last search or find-char recorded by `helixel-repeat-set'.
;; N flips direction, exchanges point and mark, then delegates to n.
;;
;; C-u n picks from history → executes in stored direction.
;; C-u N picks from history → executes in opposite of stored direction.
;; Both update `helixel--repeat-data' so subsequent n repeats the pick.
;;
;; Direction lives in `helixel--repeat-dir', never in `helixel--action :dir'.
;; `helixel--action :dir' is a historical record set at action creation.

;; ── n ──

(defun helixel-search-repeat-next (&optional arg)
  "Repeat last repeatable action in current direction.
With prefix ARG (\\[universal-argument]), pick from history."
  (interactive "P")
  (if arg
      (helixel-search--from-history t)
    (let ((cat (helixel-search--active-category))
          (dir (helixel-search--current-dir)))
      (pcase cat
        ('find-char (helixel-find-repeat))
        (_ (helixel-search--isearch-repeat
            (if (eq dir 'forward) 1 -1)))))))

;; ── N ──

(defun helixel-search-repeat-reverse (&optional arg)
  "Toggle direction, go back to start, then repeat.
With prefix ARG (\\[universal-argument]), pick from history."
  (interactive "P")
  (if arg
      ;; C-u N: from-history with forwardp=nil already toggles the
      ;; stored direction — no pre-flip needed.
      (helixel-search--from-history nil)
    (helixel-search--flip-dir)
    (exchange-point-and-mark)
    (helixel-search-repeat-next)))

;; ── C-u n / C-u N  from-history ──

(defun helixel-search--history-collect ()
  "Return alist of (display . event) for valid repeatable entries."
  (let ((entries (cl-remove-if-not
                  (lambda (e)
                    (and (helixel-event-p e)
                         (memq (helixel-event-category e)
                               helixel-search-repeat-categories)))
                  helixel--event-ring)))
    (unless entries
      (user-error "No search history"))
    (mapcar (lambda (e) (cons (helixel-action-display e) e)) entries)))

(defun helixel-search--history-select (alist prompt)
  "Prompt user with PROMPT to select an entry from ALIST.
ALIST is (display-string . action-plist) pairs.
Returns the chosen action plist or nil."
  (let* ((collection
          (lambda (s p a)
            (if (eq a 'metadata)
                '(metadata (category . helixel-search-history)
                           (cycle-sort-function . identity)
                           (display-sort-function . identity))
              (complete-with-action a alist s p))))
         (choice (completing-read prompt collection nil t)))
    (cdr (assoc choice alist))))

(defun helixel-search--history-execute (event use-dir)
  "Execute EVENT (a `helixel-event' struct) in direction USE-DIR."
  (let ((cat (helixel-event-category event)))
    (helixel-search--set-dir use-dir)
    (pcase cat
      ('find-char
       (let* ((sel (helixel-event-sel event))
              (ctx (and sel (helixel-sel-get-ctx sel)))
              (type (plist-get ctx :type))
              (char (plist-get ctx :char)))
         (helixel--tracking-open cat (helixel-event-subcat event))
         
         (setq helixel--active-search
               `(:category find-char :type ,type :char ,char :dir ,use-dir))
         (helixel-search--find-char-core event use-dir)))
       ('search
        (let* ((sel (helixel-event-sel event))
               (pattern (and sel (helixel-sel-search-pattern sel)))
               (had-region (region-active-p))
               (isearch-success nil)
               (isearch-other-end nil))
          (unless pattern
            (setq pattern (plist-get (helixel-event-payload event) :pattern)))
          (helixel--tracking-open cat (helixel-event-subcat event))
          (helixel-event-commit)
          
          (setq helixel--active-search
                `(:category search :pattern ,pattern :dir ,use-dir))
          (condition-case nil
              (helixel-search--search pattern use-dir)
            (search-failed (message "Search failed: %s" pattern)))
          (setq isearch-success (and (match-beginning 0) t))
          (when isearch-success
            (setq isearch-other-end (match-beginning 0)))
          (helixel-search--handle-done had-region)
          (helixel-search--set-sel-ctx))))))

(defun helixel-search--from-history (forwardp)
  "Select and execute a search/find-char from `helixel--event-ring'.
FORWARDP: t = use stored direction, nil = toggle it."
  (let* ((alist (helixel-search--history-collect))
         (event (helixel-search--history-select
                 alist
                 (if forwardp
                     "search next (history): "
                   "search prev (history): "))))
    (when event
      (let* ((cat (helixel-event-category event))
             (stored-dir
              (if (eq cat 'search)
                  (when-let* ((sel (helixel-event-sel event)))
                    (helixel-sel-search-dir sel))
                (helixel-search--current-dir)))
             (use-dir (if forwardp stored-dir
                        (if (eq stored-dir 'forward)
                            'backward 'forward))))
        (helixel-search--history-execute event use-dir)))))
;; Highlight and count

(defun helixel-search--unhighlight ()
  "Clear isearch highlights."
  (isearch-dehighlight)
  (lazy-highlight-cleanup t))

(defun helixel-search--count-hook ()
  "Display search term and match count in the echo area."
  (save-mark-and-excursion
    (when isearch-lazy-count-current
      (let ((term (if isearch-regexp
                      (let* ((dir (helixel-search--current-dir))
                             (c (if (eq dir 'backward) ?? ?/)))
                        (format "%c%s" c
                                (propertize isearch-string
                                            'face
                                            'font-lock-variable-name-face)))
                    (propertize isearch-string
                                'face 'font-lock-variable-name-face)))
            (count (isearch-lazy-count-format)))
        (message "%s %s" term
                 (propertize count 'face 'font-lock-function-name-face))))))

(defun helixel-search-setup ()
  "Enable lazy-count, custom isearch prompt, and highlight cleanup.
Called by `helixel-mode' activation, NOT at load time."
  (setq isearch-lazy-count t)
  (advice-add 'keyboard-quit :before #'helixel-search--unhighlight)
  (add-hook 'lazy-count-update-hook #'helixel-search--count-hook))
(defun helixel-search-teardown ()
  "Disable search-related global settings.
Called by `helixel-mode' deactivation."
  (advice-remove 'keyboard-quit #'helixel-search--unhighlight)
  (remove-hook 'lazy-count-update-hook #'helixel-search--count-hook))

;; ---------------------------------------------------------------------------

;; ── Search advance state (defined in helixel-repeat.el) ──

(defvar helixel--search-advance-done)
(defvar helixel--advance-search-last-pos)
(defvar helixel--advance-search-edge-seen)
;; ── Search and insert advance ──

(defun helixel--repeat-advance-search (tx)
  "Find next search match for TX, skip current match for insert ops.
Positions point and sets `match-data' so `helixel--recreate-search'
can reuse it without re-searching.  Returns nil if no more matches.
Guards against zero-width patterns (\=`$\=', \=`^\=') that would
otherwise cause infinite loops at buffer edges."
  (let* ((sel (helixel-event-sel tx))
         (pat (helixel-sel-search-pattern sel))
         (dir (helixel-sel-search-dir sel))
         (entry-kind (helixel-sel-search-entry-kind sel)))
    ;; Skip past current match (same logic as `helixel--recreate-search')
    (when entry-kind
      (when (or (looking-at pat)
                  (save-excursion
                    (condition-case nil
                        (progn
                          (helixel-search--search pat 'backward)
                          (let ((m-end (match-end 0))
                                (m-beg (match-beginning 0)))
                            (if (= m-beg m-end)
                                (= (line-number-at-pos)
                                   (line-number-at-pos m-end))
                              (<= (- (point) m-end) (length pat)))))
                      (search-failed nil))))
          (if (eq dir 'backward)
              (goto-char (max (point-min)
                              (1- (match-beginning 0))))
            (goto-char (if (= (match-beginning 0) (match-end 0))
                           (min (point-max) (1+ (match-end 0)))
                         (match-end 0))))))
    ;; Find next match; set flag so recreate-search reuses match-data
    (condition-case nil
        (progn
          (helixel-search--search pat dir)
          ;; Guard against zero-width matches that don't advance:
          ;; if the same match position was already processed,
          ;; we're stuck in a loop (e.g. \=`$\=' at EOB, \=`^\=' at BOB).
          (let ((m-beg (match-beginning 0))
                (m-end (match-end 0)))
            ;; Guard against zero-width patterns at buffer edges
            ;; that re-match after insertions (e.g. \=`$\=' at growing
            ;; EOB).  Allow the first edge match; bail on subsequent.
            (when (and (= m-beg m-end)
                       (or (= m-beg (point-min))
                           (= m-beg (point-max))))
              (if helixel--advance-search-edge-seen
                  (signal 'search-failed nil)
                (setq helixel--advance-search-edge-seen t)))
            ;; Guard against repeated matches at same position
            (when (equal m-beg helixel--advance-search-last-pos)
              (signal 'search-failed nil)))
          (setq helixel--search-advance-done t)
          (setq helixel--advance-search-last-pos (match-beginning 0))
          (helixel--recreate-selection sel)
          t)
      (search-failed nil))))

(defun helixel--allbuffer-search-insert (tx sel start-pos dir)
  "Insert TX payload text at every SEL match from START-POS in DIR.
For `insert-search-offset' and `insert-selection-*' entry-kinds."
  (save-excursion
    (goto-char start-pos)
    (let* ((pat (helixel-sel-search-pattern sel))
           (entry-kind (helixel-sel-search-entry-kind sel))
           (txt (or (plist-get (helixel-event-payload tx) :inserted-text)
                    (plist-get (helixel-event-payload tx) :text)
                    ""))
           (last-pos nil)
           (cnt 0))
      (catch 'done
        (while (helixel-search--search pat dir nil 'noerror)
          (let ((mpos (match-beginning 0)))
            (when (equal mpos last-pos)
              (setq cnt (1- cnt))
              (throw 'done nil))
            (setq last-pos mpos))
          (setq cnt (1+ cnt))
          (let* ((is-insert (eq entry-kind 'insert))
                 (pos (if is-insert (match-beginning 0)
                        (match-end 0)))
                 (zlen (= (match-beginning 0) (match-end 0)))
                 (guard-pos (if zlen (- pos (length txt))
                              (if is-insert (- pos (length txt)) pos))))
            (unless (save-excursion
                      (goto-char guard-pos)
                      (looking-at (regexp-quote txt)))
              (goto-char pos)
              (insert txt)
              (when is-insert (goto-char (match-end 0))))
            (when zlen (unless (eobp) (forward-char 1))))))
      (helixel--repeat-echo cnt))))

(defun helixel--all-buffer-search (edit prefix)
  "All-buffer repeat handler for search selections, for EDIT and PREFIX.
For entry-kind searches, inserts text at every match from
buffer edge.  For non-entry-kind, scans from point-min
using advance+apply without recursion."
  (let* ((sel (helixel-event-sel edit))
         (entry-kind (helixel-sel-search-entry-kind sel)))
    (if entry-kind
        (let ((start-pos (if (helixel-repeat-prefix-reverse-p prefix)
                             (point-max) (point-min)))
              (dir (if (helixel-repeat-prefix-reverse-p prefix)
                       'backward 'forward)))
          (helixel--allbuffer-search-insert edit sel start-pos dir))
      ;; Non-entry-kind: force forward direction, scan via advance+apply
      ;; directly (don't go through helixel--repeat-all-buffer to avoid
      ;; recursion since the kind's :all-buffer-fn is this function).
      (let* ((reverse-p (helixel-repeat-prefix-reverse-p prefix))
             (forced-dir (if reverse-p 'backward 'forward))
             (forced-sel (helixel-sel-update-ctx sel :dir forced-dir))
             (forced-tx (helixel--copy-tx edit))
             (strategy (helixel--build-strategy forced-tx)))
        (setf (helixel-event-sel forced-tx) forced-sel)
        (funcall (helixel-repeat-strategy-reset strategy) forced-tx)
        (save-excursion
          (goto-char (if reverse-p (point-max) (point-min)))
          (let ((cnt 0))
            (while (funcall (helixel-repeat-strategy-advance strategy)
                            forced-tx)
              (cl-incf cnt)
              (funcall (helixel-repeat-strategy-apply strategy)
                       forced-tx))
            (helixel--repeat-echo cnt)))))))

;; ── Kind registrations ──

(helixel-register-kind search
  :recreate #'helixel--recreate-search
  :advance  #'helixel--repeat-advance-search
  :all-buffer-fn #'helixel--all-buffer-search
  :display  (lambda (ctx)
              (format "/%s/" (or (helixel-sel-search-pattern ctx) "?"))))

;; ── Hook registrations ──

(add-hook 'helixel-mode-on-hook #'helixel-search-setup)
(add-hook 'helixel-mode-off-hook #'helixel-search-teardown)

(provide 'helixel-search)
;;; helixel-search.el ends here
