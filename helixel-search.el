;;; helixel-search.el --- search & find-char engine  -*- lexical-binding: t; -*-

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
;; Search and find-char for helixel-mode.
;;
;; Keybindings in normal state:
;;   /  ?        prompt then isearch-regexp forward/backward
;;   *  #        search for symbol at point forward/backward
;;   f  t  F  T  find-char/till-char forward/backward
;;   n  N        repeat last search or find (N toggles direction)

;;; Code:

(require 'helixel-common)

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
;; Repeat context
;;
;; n/N repeat the last search or find-char.  The repeat target and
;; direction live here, separate from `helixel--action :dir' which
;; records the historical direction for display purposes only.
;;
;; Design rationale —— why separate repeat-direction from action :dir:
;;   - `helixel--action :dir' is set once at action creation and must
;;     never be mutated after commit (otherwise action-start's dedup
;;     would see changed content and push duplicate ring entries).
;;   - `helixel--repeat-dir' is the "where does n go next" state, set
;;     by /,?,*,f,F,t,T,C-u n,N and flipped by N.
;;   - This separation makes it impossible for N to corrupt committed
;;     ring entries — a class of bugs that existed when direction was
;;     coupled to `helixel--action :dir'.
;;
;; Session-continuity design:
;;   `helixel-find-repeat' passes the original find-char variant
;;   (`next' or `till') as subcat to `helixel-action-start', not the
;;   literal `repeat'.  This ensures `f h → n → n' all share the same
;;   (find-char next) type, so action-start treats them as one session
;;   (same as `w w w' sharing (movement word)).  No duplicate ring
;;   entries; `;' jumps to the original `f' start position.

(defvar-local helixel--repeat-dir 'forward
  "Direction for the next n/N repeat.")

(defvar-local helixel--repeat-data nil
  "Plist describing what n/N repeats.
Keys: :category, :pattern (for search), :type and :char (for find-char).")

(defsubst helixel-repeat-dir ()
  "Return the current repeat direction."
  helixel--repeat-dir)

(defun helixel-repeat-set-dir (dir)
  "Set the repeat direction to DIR."
  (setq helixel--repeat-dir dir))

(defun helixel-repeat-flip-dir ()
  "Toggle the repeat direction (forward ↔ backward)."
  (setq helixel--repeat-dir
        (if (eq helixel--repeat-dir 'forward) 'backward 'forward)))

(defun helixel-repeat-set (category &rest data)
  "Record what n/N should repeat: CATEGORY with DATA as plist attrs.
DATA is keyword-value pairs, e.g. :pattern \"foo\" or :type next :char ?x."
  (setq helixel--repeat-data
        (append `(:category ,category) data)))

(defun helixel-repeat-category ()
  "Return the repeat category (search, find-char, or nil)."
  (helixel--action-get helixel--repeat-data :category))


;; ---------------------------------------------------------------------------
;; Direction sync on ring entries

(defun helixel-search--sync-ring-front-dir (dir)
  "Set :dir on ring front's category sub-plist to DIR.
Only affects entries whose :category is repeatable."
  (let ((front (car helixel--action-ring)))
    (when (and front (memq (helixel--action-get front :category)
                           helixel-search-repeat-categories))
      (let* ((cat (helixel--action-get front :category))
             (kwd (intern (format ":%s" cat)))
             (sub (plist-get front kwd)))
        (plist-put front kwd (plist-put sub :dir dir))))))

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
  "Store the current search in `helixel--repeat-sel-ctx'.
So the next edit command (c/d/y) records it for `.` and `,` repeat."
  (when-let* ((pat (helixel--action-get helixel--repeat-data :pattern))
              (dir (helixel-repeat-dir)))
    (helixel--repeat-sel-set
          (helixel-sel-create
           'search `(:pattern ,pat :dir ,dir)
           #'helixel--recreate-search
           ;; display closure
           (lambda (c)
             (concat "/" (or (helixel-sel-search-pattern c) "?")))
           :advance #'helixel--repeat-advance-search))))

(defun helixel-search--done-hook ()
  "Hook called at the end of isearch to mark the match."
  (remove-hook 'isearch-mode-end-hook #'helixel-search--done-hook t)
  (when (and isearch-success isearch-string
             (not (string-empty-p isearch-string)))
    (helixel--live-search-set isearch-string
                              (if isearch-forward 'forward 'backward))
    (helixel-action-commit)
    (helixel-repeat-set 'search :pattern isearch-string)
    (helixel-repeat-set-dir
     (helixel--live-cat-get :dir)))
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
Reads the pattern from `helixel--repeat-data' and sets `isearch-string'
so that `isearch-repeat-forward' / `isearch-repeat-backward' find it."
  (let ((inhibit-redisplay t)
        (isearch-wrap-pause 'no-ding)
        (isearch-repeat-on-direction-change t)
        (had-region (region-active-p)))
    (let ((pat (helixel--action-get helixel--repeat-data :pattern)))
      (when pat
        (setq isearch-string pat
              isearch-regexp t
              isearch-forward (eq (helixel-repeat-dir) 'forward))))
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
    (require 'helixel-repeat)
    (helixel--sel-push
     (helixel-sel-create 'find-char
       `(:char ,char :type ,type
         :dir ,(if forwardp 'forward 'backward)
         :inline-advance t)
       #'helixel--recreate-find-char
       (format "f%c" char)
       :advance #'helixel--repeat-advance-movement))
    (helixel--live-find-char-set type char
                                 (if forwardp 'forward 'backward))
    (helixel-action-commit)
    (helixel-repeat-set 'find-char :type type :char char)
    (helixel-repeat-set-dir (helixel--live-cat-get :dir))))

(defun helixel-search--find-char-core (&optional action dir)
  "Execute find-char from ACTION plist in direction DIR.
If ACTION is nil, searches `helixel--action-ring' for the most recent
find-char entry.  Does NOT call session start.
If DIR is nil, uses `helixel-repeat-dir'."
  (let* ((fc (or action
                 (and (eq (helixel--live-get :category) 'find-char)
                      (helixel--live-cat-get :type)
                      helixel--action)
                 (cl-find-if
                  (lambda (x) (eq (helixel--action-get x :category) 'find-char))
                  helixel--action-ring)))
         (type (helixel--action-cat-get fc :type))
         (char (helixel--action-cat-get fc :char)))
    (when (and type char)
      (let ((fdir (if (eq (or dir (helixel-repeat-dir)) 'forward)
                      'forward 'backward)))
        (unless action
          (helixel--live-find-char-set type char fdir))
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
  (helixel-action-start 'find-char 'next)
  (helixel-search--find-char-exec char 'next 1))

(defun helixel-find-prev-char (char)
  "Find next CHAR backward."
  (interactive "c")
  (helixel-action-start 'find-char 'next)
  (helixel-search--find-char-exec char 'next -1))

(defun helixel-find-till-char (char)
  "Find till CHAR forward."
  (interactive "c")
  (helixel-action-start 'find-char 'till)
  (helixel-search--find-char-exec char 'till 1))

(defun helixel-find-prev-till-char (char)
  "Find till CHAR backward."
  (interactive "c")
  (helixel-action-start 'find-char 'till)
  (helixel-search--find-char-exec char 'till -1))

(defun helixel--recreate-find-char (_ctx)
  "Recreate a find-char selection at point for dot-repeat.
Uses `helixel-search--find-char-core' which reads the character
and type from the action ring, searches for the next match from
the current cursor position, and creates the region.
The search IS the advance (inline — no separate advance fn needed)."
  (let ((helixel--inhibit-repeat-record t)
        (helixel--inhibit-action-track t))
    (helixel-search--find-char-core nil (helixel-repeat-dir))
    t))

(defun helixel-find-repeat ()
  "Repeat the last find-char in the current direction.
Fetches the original find-char marker from the ring because the live
action may have been replaced by an intervening non-find-char operation
\(e.g. f x then j then n).  The ring still holds the original find-char
entry with the correct :marker from when f was first pressed.

Session-continuity design: the subcat passed to `helixel-action-start'
is the original find-char variant (`next' or `till') taken from
`helixel--repeat-data :type', NOT the literal symbol `repeat'.
This ensures that `f h' → `n' → `n' all share the same
\(category subcat) pair, so `helixel-action-start' treats them as
continuing the session — no duplicate ring entries and `;' jumps
to the original `f' start position.  The same principle ensures
`w w w' records only the first word movement."
  (interactive)
  (let* ((fc (or (and (eq (helixel--live-get :category) 'find-char)
                      (helixel--live-cat-get :type)
                      helixel--action)
                 (cl-find-if
                  (lambda (x) (eq (helixel--action-get x :category) 'find-char))
                  helixel--action-ring)))
         (marker (and fc (helixel--action-get fc :marker))))
    (helixel-action-start 'find-char
                          (or (helixel--action-get helixel--repeat-data :type)
                              'repeat))
    (when marker
      (helixel--live-put :marker marker))
    (helixel-search--find-char-core nil (helixel-repeat-dir))))

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
  "Repeat last repeatable action in the current direction.
With prefix ARG (\\[universal-argument]), pick from history and
execute in the entry's stored direction."
  (interactive "P")
  (if arg
      (helixel-search--from-history t)
    (let ((cat (helixel-repeat-category))
          (dir (helixel-repeat-dir)))
      (pcase cat
        ('find-char (helixel-find-repeat))
        (_ (helixel-search--isearch-repeat
            (if (eq dir 'forward) 1 -1)))))))

;; ── N ──

(defun helixel-search-repeat-reverse (&optional arg)
  "Toggle direction, go back to start, then repeat.
With prefix ARG (\\[universal-argument]), pick from history and
execute in the opposite of the entry's stored direction."
  (interactive "P")
  (if arg
      (progn (helixel-repeat-flip-dir)
             (helixel-search--from-history nil))
    (helixel-repeat-flip-dir)
    (exchange-point-and-mark)
    (progn (helixel-search-repeat-next)
           (helixel-search--sync-ring-front-dir
            (helixel-repeat-dir)))))

;; ── C-u n / C-u N  from-history ──

(defun helixel-search--history-collect ()
  "Return alist of (display . action) for valid repeatable entries."
  (let ((actions (cl-remove-if-not
                  (lambda (a)
                    (and (memq (helixel--action-get a :category)
                               helixel-search-repeat-categories)
                         (helixel--action-valid-p a)))
                  helixel--action-ring)))
    (unless actions
      (user-error "No search history"))
    (mapcar (lambda (a) (cons (helixel-action-display a) a)) actions)))

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

(defun helixel-search--history-execute (action use-dir)
  "Execute ACTION (a ring entry) in direction USE-DIR.
For search entries, sets up `isearch-string' and `isearch-regexp' and
`variable isearch-forward'
\(let-bound) so that `helixel-search--handle-done' handles the region
consistent with / ? * #.  Stores the pattern in `helixel--repeat-data'
so that subsequent n/N picks it up via `helixel-search--isearch-repeat'."
  (let ((cat (helixel--action-get action :category)))
    (helixel-repeat-set-dir use-dir)
    (pcase cat
      ('find-char
       (helixel-action-start cat (helixel--action-get action :subcat))
       (helixel--live-find-char-set
        (helixel--action-cat-get action :type)
        (helixel--action-cat-get action :char)
        use-dir)
       (helixel-repeat-set 'find-char
                           :type (helixel--action-cat-get action :type)
                           :char (helixel--action-cat-get action :char))
       (helixel-search--find-char-core action use-dir))
       ('search
        (let* ((pattern (helixel--action-cat-get action :pattern))
               (had-region (region-active-p))
               (isearch-success nil)
               (isearch-other-end nil))
          (helixel-action-start cat (helixel--action-get action :subcat))
          (helixel--live-search-set pattern use-dir)
          (helixel-action-commit)
          (helixel-repeat-set 'search :pattern pattern)
          (condition-case nil
              (helixel-search--search pattern use-dir)
            (search-failed (message "Search failed: %s" pattern)))
          (setq isearch-success (and (match-beginning 0) t))
          (when isearch-success
            (setq isearch-other-end (match-beginning 0)))
          (helixel-search--handle-done had-region)
          (helixel-search--set-sel-ctx))))
    (when (eq action (car helixel--action-ring))
      (helixel-search--sync-ring-front-dir use-dir))))

(defun helixel-search--from-history (forwardp)
  "Select and execute a search/find-char from `helixel--action-ring'.
FORWARDP: t = use the entry's stored direction as-is,
          nil = toggle the entry's stored direction."
  (let* ((alist (helixel-search--history-collect))
         (action (helixel-search--history-select
                  alist
                  (if forwardp
                      "search next (history): "
                    "search prev (history): "))))
    (when action
      (let* ((stored-dir (helixel--action-cat-get action :dir))
             (use-dir (if forwardp stored-dir
                        (if (eq stored-dir 'forward)
                            'backward 'forward))))
        (helixel-search--history-execute action use-dir)))))
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
                      (let ((c (if (eq (helixel-repeat-dir) 'backward) ?? ?/)))
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
  "Enable lazy-count, custom isearch prompt, and highlight cleanup."
  (setq isearch-lazy-count t)
  (advice-add 'keyboard-quit :before #'helixel-search--unhighlight)
  (add-hook 'lazy-count-update-hook #'helixel-search--count-hook))

;; ---------------------------------------------------------------------------
;; Search selection replay (for `.` and `,`)

;; Register keybindings

(helixel-define-key 'normal "/" #'helixel-search-forward)
(helixel-define-key 'normal "?" #'helixel-search-backward)
(helixel-define-key 'normal "*" #'helixel-search-at-point-next)
(helixel-define-key 'normal "#" #'helixel-search-at-point-prev)
(helixel-define-key 'normal "f" #'helixel-find-next-char)
(helixel-define-key 'normal "F" #'helixel-find-prev-char)
(helixel-define-key 'normal "t" #'helixel-find-till-char)
(helixel-define-key 'normal "T" #'helixel-find-prev-till-char)
(helixel-define-key 'normal "n" #'helixel-search-repeat-next)
(helixel-define-key 'normal "N" #'helixel-search-repeat-reverse)
(helixel-define-key 'normal "M-." #'helixel-find-repeat)

(helixel-search-setup)

(provide 'helixel-search)
;;; helixel-search.el ends here
