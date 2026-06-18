;;; helixel-search.el --- search & find-char engine  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

;; Author: jixiuf <https://github.com/jixiuf>
;; Keywords: convenience
;; URL: https://github.com/jixiuf/helixel-mode
;; SPDX-License-Identifier: GPL-3.0-or-later

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

;; ── Forward declarations for variables in later-loaded modules ──
(defvar helixel--action-ring)
(defvar helixel--live-action)

(require 'helixel-state)
(require 'helixel-core)
(require 'helixel-macros)
(require 'helixel-repeat)
(require 'helixel-move)

;; ---------------------------------------------------------------------------
;; Groups and customs

(defgroup helixel-search nil
  "Search and find-char for `helixel-mode'."
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
;; PCRE support (soft dependency on pcre2el)

(defcustom helixel-search-pcre nil
  "When non-nil, convert PCRE regexp syntax to Emacs regexp during search.

When t and the pcre2el package is available, patterns like \\d,
\\w, \\s etc. are translated to Emacs-compatible equivalents
\(e.g. [[:digit:]]) before searching.  Affects both interactive
isearch (\=/, \=?) and n/N repeat.

Requires pcre2el (<https://github.com/joddie/pcre2el>)."
  :type 'boolean
  :group 'helixel-search)

(defun helixel-search--pcre-to-elisp (pattern)
  "Convert PATTERN from PCRE to elisp regexp if pcre2el is available.
Returns PATTERN unchanged on failure, when pcre2el is absent,
or when PATTERN contains elisp-specific regex constructs that
PCRE would not understand (\\_<, \\_>, \\=<, \\=> — Emacs
symbol/word-boundary markers automatically inserted by \\=`*' / \\=`#'
and other search-at-point commands)."
  (if (and (fboundp 'rxt-pcre-to-elisp)
           (not (helixel-search--has-elisp-boundary pattern)))
      (helixel--with-debug-log search-compile-pcre
          (rxt-pcre-to-elisp pattern)
        (error pattern))
    pattern))

(defun helixel-search--has-elisp-boundary (pattern)
  "Return non-nil if PATTERN contains elisp-specific boundary syntax.
Detects \\_<, \\_>, \\=<, \\=> — Emacs-only regex constructs that
would confuse a PCRE→elisp converter."
  (let ((case-fold-search nil))
    (string-match-p
     (concat (regexp-quote "\\_<") "\\|"
             (regexp-quote "\\_>") "\\|"
             (regexp-quote "\\<") "\\|"
             (regexp-quote "\\>"))
     pattern)))

(defun helixel-search--pcre-isearch-search-fun-function ()
  "Value for `isearch-search-fun-function' that converts PCRE→elisp.
When `helixel-search-pcre' is nil or pcre2el is unavailable,
returns the default search function unchanged."
  (if (and helixel-search-pcre (fboundp 'rxt-pcre-to-elisp))
      (lambda (string bound noerror)
        (funcall (isearch-search-fun-default)
                 (if isearch-regexp
                     (helixel-search--pcre-to-elisp string)
                   string)
                 bound noerror))
    (isearch-search-fun-default)))

(defun helixel-search--buffer-setup-pcre ()
  "Set up buffer-local isearch for PCRE conversion.
Called from `helixel-state-change-hook'."
  (set (make-local-variable 'isearch-search-fun-function)
       #'helixel-search--pcre-isearch-search-fun-function))

;; ---------------------------------------------------------------------------
;; Active Search — single mutable search state
;;
;; `helixel--active-search' is the single source of truth for
;; what n/N repeats and in which direction.
;;
;; Set by /, ?, *, #, f, F, t, T, C-u n/N
;; Read by n/N commands and `.` / `,` repeat
;;
;; :dir is MUTABLE — N flips it.  Event-ring entries are immutable
;; snapshots and never store mutable state.

(defvar-local helixel--active-search nil
  "Active repeat target as a `helixel--last-motion' struct.
Set by \=/, \=?, \=*, \=#, f, F, t, T.
Read by n/N commands and `.` / `,` repeat.
The :dir slot is MUTABLE — N flips it.
Event-ring entries are immutable snapshots and never store
mutable state.

Holds the same struct type as `helixel--last-motion-cmd' —
a helixel--last-motion.  This variable is only overwritten
by search/find-char commands, so n/N survives intervening
movements (unlike `helixel--last-motion-cmd' which tracks the
most recent motion of any category for \=`,`\=').")

(defsubst helixel-search--current-dir ()
  "Return current repeat direction from `helixel--active-search'.
Defaults to `forward' when the search state has no direction set."
  (if helixel--active-search
      (helixel--last-motion-dir helixel--active-search)
    'forward))

(defsubst helixel-search--safe-category ()
  "Return category slot from `helixel--active-search', or nil."
  (and helixel--active-search
       (helixel--last-motion-category helixel--active-search)))

(defsubst helixel-search--safe-pattern ()
  "Return pattern slot from `helixel--active-search', or nil."
  (and helixel--active-search
       (helixel--last-motion-pattern helixel--active-search)))

(defsubst helixel-search--safe-type ()
  "Return type slot from `helixel--active-search', or nil."
  (and helixel--active-search
       (helixel--last-motion-type helixel--active-search)))

(defsubst helixel-search--safe-char ()
  "Return char slot from `helixel--active-search', or nil."
  (and helixel--active-search
       (helixel--last-motion-char helixel--active-search)))

(defun helixel-search--flip-dir ()
  "Toggle repeat direction in `helixel--active-search'."
  (let ((new (if (eq (helixel-search--current-dir) 'forward)
                 'backward 'forward)))
    (if helixel--active-search
        (setf (helixel--last-motion-dir helixel--active-search) new)
      (setq helixel--active-search
            (make-helixel--last-motion :dir new)))))

(defun helixel-search--set-dir (dir)
  "Set DIR in `helixel--active-search'."
  (if helixel--active-search
      (setf (helixel--last-motion-dir helixel--active-search) dir)
    (setq helixel--active-search
          (make-helixel--last-motion :dir dir))))


;; ---------------------------------------------------------------------------
;; Direction sync on ring entries (see above for PCRE isearch setup)

(defvar helixel-search--had-region nil
  "Non-nil if a region was active before the search started.
Let-bound by `helixel-search--at-point'.")

;; ---------------------------------------------------------------------------
;; Invisible text bridge

(defmacro helixel--with-invisible-search (&rest body)
  "Run BODY with invisible-search vars set from `helixel-invisible'.
Binds `search-invisible' and `isearch-invisible' to `helixel-invisible'."
  (declare (indent 0) (debug t))
  `(let ((search-invisible helixel-invisible)
         (isearch-invisible helixel-invisible))
     ,@body))


;; ---------------------------------------------------------------------------
;; Isearch-compatible search helper — used by n/N repeat and . replay
;;
;; `isearch-search-string' respects all isearch settings:
;;   case-fold-search, isearch-invisible, isearch-regexp-function, etc.
;; This ensures `.` repeat uses the same search behavior as
;; the original / ? search, including case folding and hidden chars.

(cl-defun helixel-search--search (pattern dir
                                  &optional bound noerror (regexp t))
  "Search for PATTERN in DIR using isearch-compatible settings.
DIR is \=`forward' or \=`backward'.
BOUND limits the search range (nil = whole buffer).
REGEXP controls `isearch-regexp' (t = regexp, nil = literal).
When REGEXP is omitted, defaults to t.
Signals \=`search-failed' when not found (NOERROR is nil).
Returns the match position (point moves to \=`match-end').

`isearch-search-string' does not call `isearch-filter-predicate';
we bridge that via `helixel--search-filter-loop'."
  (helixel--with-invisible-search
    (let ((isearch-string pattern)
          (isearch-regexp regexp)
          (isearch-forward (eq dir 'forward)))
      (if helixel-invisible
          (isearch-search-string pattern bound noerror)
        (or (helixel--search-filter-loop
             (lambda () (isearch-search-string pattern bound t))
             (eq dir 'forward))
            (unless noerror
              (signal 'search-failed (list pattern))))))))

;; ---------------------------------------------------------------------------
;; Selection context for `.` repeat

(defun helixel-search--set-sel-ctx ()
  "Store the current search in `helixel--pending-sel'.
Increments :n-count each time (0 for initial search, 1 for first n,
2 for second n, etc.) so . advance skips the correct number of
matches to match the original n count.
Also stores :regexp from `helixel--active-search' so \\=`,' and \\=`.'
respect the \\=`M-r' toggle."
  (when-let* ((s helixel--active-search)
              (pat (helixel-search--safe-pattern))
              (dir (helixel-search--current-dir)))
    ;; Read previous n-count from existing pending-sel and increment.
    (let* ((prev-n (plist-get (helixel-sel-ctx
                               helixel--pending-sel)
                              :n-count))
           (n-count (if prev-n (1+ prev-n) 0))
           (regexp (helixel--last-motion-regexp s)))
      (helixel--push-selection
       'search `(:pattern ,pat :dir ,dir :n-count ,n-count
                 :regexp ,regexp)))))

(defun helixel-search--done-hook ()
  "Hook called at the end of isearch to mark the match.
On cancel (\[keyboard-quit]) discards the stale live-action so it
is not committed by the next command."
  (remove-hook 'isearch-mode-end-hook #'helixel-search--done-hook t)
  (if (and isearch-success isearch-string
           (not (string-empty-p isearch-string)))
      ;; Successful search — commit with proper sel.
      (let ((dir (if isearch-forward 'forward 'backward)))
        (when (and isearch-other-end helixel--live-action)
          (helixel--set-mark-region
           (cons (min isearch-other-end (point))
                 (max isearch-other-end (point)))))
        (setq helixel--active-search
              (make-helixel--last-motion
               :category 'search :pattern isearch-string
               :dir dir :regexp isearch-regexp))
        ;; Record for motion repeat (bound to `,'):
        ;; store category+pattern+dir+regexp so `,' can replay search
        ;; via `helixel-search--isearch-repeat'.
        (helixel-record-motion nil
          :category 'search :pattern isearch-string
          :dir dir :regexp isearch-regexp)
        (helixel-search--set-sel-ctx)
        ;; Stash pattern + dir + regexp in the payload and attach a
        ;; runner so the unified mc dispatcher can replay this search
        ;; at every fake cursor without re-entering isearch mode.
        (when helixel--live-action
          (setf (helixel-action-payload helixel--live-action)
                (list :pattern isearch-string :dir dir
                      :regexp isearch-regexp))
          (setf (helixel-action-runner helixel--live-action)
                #'helixel-search--mc-runner))
        (helixel--action-commit)
        (helixel-search--echo-repeat-hint))
    ;; Cancelled — discard the tracking-open shell so the next
    ;; command's tracking-open does not commit a stale entry.
    (when (and helixel--live-action
               (eq (helixel-action-category helixel--live-action) 'search))
      (helixel-action--release-markers helixel--live-action)
      (setq helixel--live-action nil)))
  (helixel-search--handle-done helixel-search--had-region))

(defun helixel-search--mc-runner (tx)
  "Replay a search TX at a fake cursor position.
Used as the :runner attached to search actions so the unified
mc dispatcher can replay searches at every fake cursor.
Reads :pattern, :dir, and :regexp from TX's payload, calls
`helixel-search--search', and activates a region around the
match.  For forward search point ends at `match-end'; for backward
search point ends at `match-beginning' (matching isearch behavior)."
  (let* ((pat (helixel-action-payload-get tx :pattern))
         (d (helixel-action-dir tx))
         (regexp (helixel-action-payload-get tx :regexp))
         (forwardp (eq d 'forward)))
    (setq helixel--active-search
          (make-helixel--last-motion
           :category 'search :pattern pat :dir d :regexp regexp))
    (helixel-search--search pat d nil nil regexp)
    (if forwardp
        (progn
          (push-mark (match-beginning 0) t t)
          (goto-char (match-end 0)))
      (push-mark (match-end 0) t t))))

(defun helixel-search--handle-done (_had-region)
  "Handle region after isearch finishes.
Always activates the mark on the match for visual feedback.
_HAD-REGION is ignored (kept for signature compatibility)."
  (when (and isearch-success isearch-other-end)
    (unless (helixel--pure-visual-state-p)
      (set-marker (mark-marker) isearch-other-end))
    (activate-mark)
    (setq transient-mark-mode (cons 'only t))))

;; ---------------------------------------------------------------------------
;; / ?  — prompt isearch-regexp

(helixel-define-command helixel-search-forward
  (:category search :subcat search :clear-highlights nil)
  (add-hook 'isearch-mode-end-hook #'helixel-search--done-hook 0 t)
  (helixel--with-invisible-search
    (call-interactively #'isearch-forward-regexp)))

(helixel-define-command helixel-search-backward
  (:category search :subcat search :clear-highlights nil)
  (add-hook 'isearch-mode-end-hook #'helixel-search--done-hook 0 t)
  (helixel--with-invisible-search
    (call-interactively #'isearch-backward-regexp)))

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
    (helixel--with-invisible-search
      (if (< dir 0)
          (progn
            (goto-char (if (= (point-min) (car bounds))
                           (point-max)
                         (1- (car bounds))))
            (call-interactively #'isearch-backward-regexp))
        (goto-char (cdr bounds))
        (call-interactively #'isearch-forward-regexp)))
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
Reads pattern and regexp flag from `helixel--active-search'.
Respects the \\=`M-r' toggle by reading the stored :regexp value
instead of hardcoding `isearch-regexp' to t."
  (helixel--with-invisible-search
    (let ((inhibit-redisplay t)
          (isearch-wrap-pause 'no-ding)
          (isearch-repeat-on-direction-change t)
          (had-region (region-active-p)))
      (when-let* ((pat (helixel-search--safe-pattern)))
        (setq isearch-string pat
              isearch-regexp (helixel--last-motion-regexp
                              helixel--active-search)
              isearch-forward (eq (helixel-search--current-dir) 'forward)))
      (if (< dir 0)
          (isearch-repeat-backward (- dir))
        (isearch-repeat-forward dir))
      (helixel-search--handle-done had-region)
      (helixel-search--set-sel-ctx))))

;; ---------------------------------------------------------------------------
;; Find-char: f F t T

(defun helixel-search--find-char-set-sel (char type dir)
  "Push a find-char sel for CHAR, TYPE, DIR with incremented :n-count.
Tracks how many times n was pressed so . repeats the full sequence."
  (let* ((prev-pending helixel--pending-sel)
         (prev-n (when (and prev-pending
                            (eq (helixel-sel-kind prev-pending)
                                'find-char))
                   (plist-get (helixel-sel-ctx prev-pending)
                              :n-count)))
         (n-count (if prev-n (1+ prev-n) 0)))
    (helixel--sel-push
     (helixel-sel-create 'find-char
       `(:char ,char :type ,type :dir ,dir :inline-advance t
         :n-count ,n-count)))))

(defun helixel-search--find-char-jump (char type forwardp)
  "Perform the search-and-position step for find-char.
CHAR is the target character; TYPE is `next' or `till'; FORWARDP
is t for forward search.  Caller is responsible for binding
`case-fold-search' and pushing the pre-mark, etc.

Bridges `search-forward'/`search-backward' (which bypass
`isearch-filter-predicate') via `helixel--search-filter-loop'.
Signals `search-failed' if no visible match is found."
  (helixel--with-invisible-search
    (let ((needle (char-to-string char))
          (search-fn (if forwardp #'search-forward #'search-backward)))
      (or (helixel--search-filter-loop
           (lambda ()
             ;; search-forward signals search-failed on failure,
             ;; which the loop catches.
             (funcall search-fn needle))
           forwardp)
          (signal 'search-failed (list needle)))
      ;; Apply the till offset AFTER the visible match is confirmed.
      (when (eq type 'till)
        (if forwardp (backward-char) (forward-char))))))
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
    (helixel-search--find-char-jump char type forwardp)
    (unless (use-region-p)
      (push-mark current t 'activate))
    ;; Push find-char sel with tracked n-count.
    (helixel-search--find-char-set-sel
     char type (if forwardp 'forward 'backward))
    ;; Attach a tx so the unified mc dispatcher can replay this
    ;; find-char at every fake cursor without re-prompting.  Payload
    ;; carries the prompted CHAR + TYPE + DIR; runner installs them
    ;; into the fake's `helixel--active-search' and re-executes the
    ;; jump.
    (let ((sym-dir (if forwardp 'forward 'backward)))
      (when helixel--live-action
        (setf (helixel-action-payload helixel--live-action)
              (list :char char :type type :dir sym-dir))
        (setf (helixel-action-runner helixel--live-action)
              (lambda (tx)
                (let ((c (helixel-action-char tx))
                      (ty (helixel-action-type tx))
                      (d (helixel-action-dir tx)))
                  (setq helixel--active-search
                        (make-helixel--last-motion
                         :category 'find-char :type ty
                         :char c :dir d))
                  (helixel-search--find-char-core d)))))
      (helixel--action-commit)
      (helixel-search--set-dir sym-dir)
      (setq helixel--active-search
            (make-helixel--last-motion
             :category 'find-char :type type :char char :dir sym-dir))
      (helixel-search--echo-repeat-hint))))

(defun helixel-search--echo-repeat-hint ()
  "Echo a hint showing which key repeats the last search/find-char.
Uses `substitute-command-keys' to dynamically look up the
current keybinding for `helixel-search-repeat-next' and
`helixel-search-repeat-reverse'."
  (message "%s repeat, %s reverse direction and repeat"
           (substitute-command-keys
            "\\[helixel-search-repeat-next] or \\[helixel-repeat-last-motion]")
           (substitute-command-keys
            "\\[helixel-search-repeat-reverse]")))

(defun helixel-search--find-char-core (&optional dir char type)
  "Execute find-char in direction DIR.
When CHAR and TYPE are non-nil, use them directly.
Otherwise read from `helixel--active-search'."
  (let* ((type (or type (helixel-search--safe-type)))
         (char (or char (helixel-search--safe-char))))
    (when (and type char)
      (let* ((fdir (if (eq (or dir (helixel-search--current-dir)) 'forward)
                       'forward 'backward))
             (forwardp (eq fdir 'forward))
             (case-fold-search
              (if (char-uppercase-p char) nil case-fold-search))
             (current (point)))
        (when (eq type 'till)
          (if forwardp (forward-char) (backward-char)))
        (helixel--clear-highlights)
        (helixel-search--find-char-jump char type forwardp)
        (unless (use-region-p)
          (push-mark current t 'activate))))))

(defmacro helixel--def-find-char (name type dir doc)
  "Define a find-char command NAME with TYPE (`next' or `till') and DIR.
DIR is the base direction (+1 forward, -1 backward).
A negative COUNT flips the direction (\\=`-f x' = find backward,
\\=`-3f x' = find 3rd backward).
DOC is the docstring."
  `(defun ,name (char &optional count)
     ,doc
     (interactive "c\np")
     ;; Bind `helixel--current-command' so the action committed by
     ;; `helixel--action-commit' carries the correct `by-command' stamp
     ;; for unified mc dispatch.  `this-command' is already set by
     ;; Emacs's command loop for interactive invocation.
     (let ((helixel--current-command ',name)
           (n (abs (or count 1)))
           (effective-dir (* ,dir (if (and count (< count 0)) -1 1))))
       (helixel--tracking-open 'find-char ',type)
       ;; Record this as the last motion for `,' repeat.
       ;; Stash char/type/dir so `,' replays self-contained
       ;; without consulting `helixel--active-search'.
       (let ((sym-dir (if (> effective-dir 0) 'forward 'backward)))
         (helixel-record-motion ',name
           :category 'find-char :char char :type ',type :dir sym-dir))
       ;; unwind-protect: on error, discard the stale live-action.
       (unwind-protect
           (dotimes (_ n)
             (helixel-search--find-char-exec char ',type effective-dir))
         (when (and helixel--live-action
                    (eq (helixel-action-category helixel--live-action)
                        'find-char))
           (helixel-action--release-markers helixel--live-action)
           (setq helixel--live-action nil))))))

(helixel--def-find-char helixel-find-next-char next 1
                        "Find next CHAR forward.")
(helixel--def-find-char helixel-find-prev-char next -1
                        "Find next CHAR backward.")
(helixel--def-find-char helixel-find-till-char till 1
                        "Find till CHAR forward.")
(helixel--def-find-char helixel-find-prev-till-char till -1
                        "Find till CHAR backward.")

;; ── Search re-creation helpers ──

(defun helixel-search--skip-current-match (pat dir entry-kind &optional regexp)
  "Skip past the current match of PAT if point is inside one.
DIR is `forward' or `backward'.  Only operates when ENTRY-KIND is non-nil.
REGEXP controls `isearch-regexp', forwarded to `helixel-search--search'.
Returns t if a skip was performed, nil otherwise."
  (when entry-kind
    (when (or (looking-at pat)
              (let ((orig-pt (point)))
                (save-excursion
                  (helixel--with-debug-log search-entry-prep
                      (progn
                        (helixel-search--search pat 'backward nil nil regexp)
                        (>= orig-pt (match-beginning 0)))
                    (search-failed nil)))))
      (if (eq dir 'backward)
          (goto-char (max (point-min) (1- (match-beginning 0))))
        (goto-char (if (= (match-beginning 0) (match-end 0))
                       (min (point-max) (1+ (match-end 0)))
                     (match-end 0))))
      t)))

(defun helixel-search--advance-n-count (ctx search-fn)
  "Advance :n-count extra matches per CTX using SEARCH-FN.
SEARCH-FN is a zero-arg function called once per extra match.
Stops silently on `search-failed'."
  (when-let* ((n (plist-get ctx :n-count))
              ((> n 0)))
    (helixel--with-debug-log search-advance-n-count
        (dotimes (_ n)
          (funcall search-fn))
      (search-failed nil))))

(defun helixel-search--backward-unstick (dir)
  "Step back from a backward match before searching.
When DIR is `backward' and point sits at the active region end,
moves point just before the region beginning so the next backwards
search finds the PREVIOUS match rather than re-matching the current
one.  Needed by \=`,\`= preview where no edit moves point forward.
Shared by `helixel--recreate-search' and `helixel--repeat-advance-search'."
  (when (and (eq dir 'backward)
             (use-region-p)
             (= (point) (region-end)))
    (goto-char (max (point-min) (1- (region-beginning))))))

(defun helixel--recreate-search (ctx)
  "Replay search selection from CTX.
Finds the next match, activates the region on it.
If `(helixel--search-advance-done-p)' is t, skips the internal search
\(the advance function already positioned point and set `match-data').
If CTX has :entry-kind (insert or append), positions the cursor
at the appropriate offset within the match for insert-text ops.
Uses :regexp from CTX to respect the \\=`M-r' toggle."
  (let* ((pat (helixel-sel-search-pattern ctx))
         (dir (helixel-sel-search-dir ctx))
         (regexp (helixel-sel-search-regexp ctx))
         (pre-skip-pos (point)))
    (unless pat
      (user-error "No search pattern to repeat"))
    (helixel--with-span ctx
      (if (helixel--search-advance-done-p)
          (helixel--search-advance-done-set nil)
        ;; Internal search — only run when advance wasn't already done.
        (when (helixel-search--skip-current-match
               pat dir (helixel-sel-search-entry-kind ctx)
               regexp)
          (when (or (= (point) pre-skip-pos)
                    (and (eq dir 'forward) (eobp))
                    (and (eq dir 'backward) (bobp)))
            (user-error "No more matches for %s" pat)))
        (helixel-search--backward-unstick dir)
        (condition-case nil
            (helixel-search--search pat dir nil nil regexp)
          (search-failed
           (user-error "Search pattern not found: %s" pat))))
      (helixel-search--advance-n-count
       ctx (lambda () (helixel-search--search pat dir nil nil regexp)))
      (push-mark (match-beginning 0) t t)
      (goto-char (match-end 0)))
    (when-let* ((entry-kind (helixel-sel-search-entry-kind ctx)))
      (let* ((base (if (eq entry-kind 'append)
                       (match-end 0)
                     (match-beginning 0)))
             (cursor-offset (or (helixel-sel-search-cursor-offset ctx) 0)))
        (goto-char (+ base cursor-offset))))))

(defun helixel--recreate-find-char (ctx)
  "Recreate a find-char selection from CTX at point for dot-repeat.
Does :n-count extra searches after finding the char, so . repeats
the full f x n n sequence.  Extends region back to origin when
:span is set (from ; push)."
  (let ((n (or (plist-get ctx :n-count) 0))
        (dir (or (helixel-sel-find-char-dir ctx)
                 (helixel-search--current-dir))))
    (helixel-with-replay-as 'dot
     (helixel--with-span ctx
      (helixel-search--find-char-core dir)
      (when (> n 0)
        (helixel--with-debug-log search-find-char-n
            (dotimes (_ n)
              (helixel-search--find-char-core dir))
          (search-failed nil))))
     t)))

(defun helixel-search--repeat-find-char (&optional char type dir)
  "Repeat the last find-char.
When CHAR, TYPE and DIR are given (from \=`,'), use them directly.
Otherwise (from \=`n') read from `helixel--active-search'.
Passes CHAR/TYPE/DIR explicitly to `helixel-search--find-char-core'
so no temp dynamic binding of `helixel--active-search' is needed.
Updates n-count in the pending sel so \=`.' repeats the full sequence.
Also attaches a runner + payload so the unified mc dispatcher can
replay this repeat at every fake cursor without re-entering `n'."
  (let ((char (or char (helixel-search--safe-char)))
        (type (or type (helixel-search--safe-type)))
        (dir  (or dir  (helixel-search--current-dir))))
    (unless (and char type)
      (user-error "No find-char to repeat"))
    (helixel--tracking-open 'find-char type)
    ;; Attach runner + payload (mirrors helixel-search--find-char-exec)
    ;; so mc dispatch and . replay can use this entry.
    (when helixel--live-action
      (setf (helixel-action-payload helixel--live-action)
            (list :char char :type type :dir dir))
      (setf (helixel-action-runner helixel--live-action)
            (lambda (tx)
              (let ((c (helixel-action-char tx))
                    (ty (helixel-action-type tx))
                    (d (helixel-action-dir tx)))
                (setq helixel--active-search
                      (make-helixel--last-motion
                       :category 'find-char :type ty
                       :char c :dir d))
                (helixel-search--find-char-core d)))))
    (helixel-search--find-char-core dir char type)
    (helixel--action-commit)
    ;; Track n-count so . repeats the full n sequence.
    (helixel-search--find-char-set-sel char type dir)))

(defun helixel-repeat-last-motion (&optional raw-prefix)
  "Repeat the last motion (f, t, /, ?, \\=`%', \\=`[', \\=`]', \\=`{', \\=`}').
Reads self-contained replay data from `helixel--last-motion-cmd'.
The stored category+subcat is checked against
`helixel-motion-repeat-categories' via `helixel--category-match-p'.
Dispatches via `helixel--motion-repeater-alist' — extend by
calling `helixel-register-motion-repeater'.
Never consults the global `helixel--active-search'.

Prefix RAW-PREFIX semantics:
  \\=`-,'    — permanently flip direction (like N for search)
  Subsequent , repeats in the flipped direction.
  \\=`-,' again flips back.
  \\=`-3,'  — repeat 3 times in flipped direction.
  \\=`3,'   — repeat 3 times in stored direction.

Direction flip works for search, find-char, match, and movement
categories.  Movement commands use the reverse-command registry
\(`helixel--motion-reverse-alist') to call the opposite command."
  (interactive "P")
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
                  (helixel--last-motion-category rec)))))

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

;; Motion repeaters registered via `helixel-register-motion-repeater'

(defun helixel--repeat-search-motion (rec)
  "Replay a search (/) motion from REC.
Creates a temporary `helixel--active-search' from the stored
pattern, direction, and regexp flag, then calls
`helixel-search--isearch-repeat'."
  (let ((helixel--active-search
         (make-helixel--last-motion
          :category 'search
          :pattern (helixel--last-motion-pattern rec)
          :dir (helixel--last-motion-dir rec)
          :regexp (helixel--last-motion-regexp rec))))
    (helixel-search--isearch-repeat
     (if (eq (helixel--last-motion-dir rec) 'forward) 1 -1))))

(defun helixel--repeat-find-char-motion (rec)
  "Replay a find-char (f/t) motion from REC.
Passes the stored char, type, and direction directly to
`helixel-search--repeat-find-char' — no `helixel--active-search'
consultation needed."
  (helixel-search--repeat-find-char
   (helixel--last-motion-char rec)
   (helixel--last-motion-type rec)
   (helixel--last-motion-dir rec)))

(helixel-register-motion-repeater 'search nil
  #'helixel--repeat-search-motion)
(helixel-register-motion-repeater 'find-char nil
  #'helixel--repeat-find-char-motion)

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
;; Direction lives in `helixel--repeat-dir', never in the event.
;; The event `:dir' is a historical record set at creation.

;; ── n ──

(defun helixel-search-repeat-next (&optional arg)
  "Repeat last repeatable action in current direction.
With prefix ARG (\\[universal-argument]), pick from history."
  (interactive "P")
  (if arg
      (helixel-search--from-history t)
    (let ((cat (helixel-search--safe-category))
          (dir (helixel-search--current-dir)))
      (pcase cat
        ('find-char (helixel-search--repeat-find-char))
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
                    (and (helixel-action-p e)
                         (memq (helixel-action-category e)
                               helixel-search-repeat-categories)))
                  helixel--action-ring)))
    (unless entries
      (user-error "No search history"))
    (mapcar (lambda (e) (cons (helixel--action-display-format e) e)) entries)))

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
  "Execute EVENT (a `helixel-action' struct) in direction USE-DIR.
Sets `helixel--active-search' and pushes the pending sel BEFORE
committing, so the new ring entry carries its selection descriptor
and appears correctly in `C-u n' history and \=`;\=' cycling."
  (let ((cat (helixel-action-category event)))
    (helixel-search--set-dir use-dir)
    (pcase cat
      ('find-char
       (let* ((sel (helixel-action-sel event))
              (ctx (and sel (helixel-sel-ctx sel)))
              (type (helixel-sel-find-char-type ctx))
              (char (helixel-sel-find-char-char ctx)))
         ;; Set up search state and sel BEFORE commit so the
         ;; committed entry carries its descriptor.
         (setq helixel--active-search
               (make-helixel--last-motion
                :category 'find-char :type type :char char :dir use-dir))
         (helixel-search--find-char-set-sel char type use-dir)
         (helixel--tracking-open cat (helixel-action-subcat event))
         ;; Attach payload + runner (mirrors helixel-search--find-char-exec)
         ;; so mc dispatch and . replay can use this entry.
         (when helixel--live-action
           (setf (helixel-action-payload helixel--live-action)
                 (list :char char :type type :dir use-dir))
           (setf (helixel-action-runner helixel--live-action)
                 (lambda (tx)
                   (let ((c (helixel-action-char tx))
                         (ty (helixel-action-type tx))
                         (d (helixel-action-dir tx)))
                     (setq helixel--active-search
                           (make-helixel--last-motion
                            :category 'find-char :type ty
                            :char c :dir d))
                     (helixel-search--find-char-core d)))))
         (helixel--action-commit)
         (helixel-search--find-char-core use-dir)))
       ('search
        (let* ((sel (helixel-action-sel event))
               (pattern (or (and sel (helixel-sel-search-pattern sel))
                            (helixel-action-payload-get event :pattern)))
               (regexp (or (and sel (helixel-sel-search-regexp sel))
                           (helixel-action-payload-get event :regexp)
                           t))
               (had-region (region-active-p))
               (isearch-success nil)
               (isearch-other-end nil))
          ;; Set up search state and sel BEFORE commit.
          (setq helixel--active-search
                (make-helixel--last-motion
                 :category 'search :pattern pattern :dir use-dir
                 :regexp regexp))
          (helixel-search--set-sel-ctx)
          (helixel--tracking-open cat (helixel-action-subcat event))
          (helixel--action-commit)
          ;; Now execute the actual search.
          (condition-case nil
              (helixel-search--search pattern use-dir nil nil regexp)
            (search-failed (message "Search failed: %s" pattern)))
          (setq isearch-success (and (match-beginning 0) t))
          (when isearch-success
            (setq isearch-other-end (match-beginning 0)))
          (helixel-search--handle-done had-region))))))

(defun helixel-search--from-history (forwardp)
  "Select and execute a search/find-char from `helixel--action-ring'.
FORWARDP: t = use stored direction, nil = toggle it."
  (let* ((alist (helixel-search--history-collect))
         (event (helixel-search--history-select
                 alist
                 (if forwardp
                     "search next (history): "
                   "search prev (history): "))))
    (when event
      (let* ((cat (helixel-action-category event))
             (stored-dir
              (if (eq cat 'search)
                  (when-let* ((sel (helixel-action-sel event)))
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
  "Enable lazy-count, custom isearch prompt, highlight cleanup, and PCRE.
Also demotes `isearch-lazy-highlight' overlay priority so region
overlays (real and fake) render above lazy-highlight matches.
Called by `helixel-mode' activation, NOT at load time."
  (setq isearch-lazy-count t)
  (add-hook 'helixel-keyboard-quit-functions #'helixel-search--unhighlight)
  (add-hook 'lazy-count-update-hook #'helixel-search--count-hook)
  ;; PCRE support: set isearch-search-fun-function per-buffer
  (add-hook 'helixel-state-change-hook #'helixel-search--buffer-setup-pcre)
  ;; Demote lazy-highlight overlay priority so region overlays
  ;; (real + fake-cursor) appear above isearch matches.
  (when (fboundp 'isearch-lazy-highlight-update)
    (advice-add 'isearch-lazy-highlight-update :after
                #'helixel-search--demote-lazy-highlight-priority)))

(defun helixel-search--demote-lazy-highlight-priority (&rest _)
  "Set lazy-highlight overlay priorities below region overlays.
Used as :after advice on `isearch-lazy-highlight-update'."
  (when (and (boundp 'isearch-lazy-highlight-overlays)
             isearch-lazy-highlight-overlays)
    (dolist (ov isearch-lazy-highlight-overlays)
      (when (overlay-buffer ov)
        (overlay-put ov 'priority -10)))))

(defun helixel-search-teardown ()
  "Disable search-related global settings.
Called by `helixel-mode' deactivation."
  (remove-hook 'helixel-keyboard-quit-functions
               #'helixel-search--unhighlight)
  (remove-hook 'lazy-count-update-hook #'helixel-search--count-hook)
  (remove-hook 'helixel-state-change-hook #'helixel-search--buffer-setup-pcre)
  (when (fboundp 'isearch-lazy-highlight-update)
    (advice-remove 'isearch-lazy-highlight-update
                   #'helixel-search--demote-lazy-highlight-priority)))

;; ---------------------------------------------------------------------------

;; ── Search advance state (defined in helixel-repeat.el) ──

;; Search-advance scratch now lives on the replay context (see
;; `helixel--search-advance-done-p' etc in helixel-replay.el).

;; ── Search and insert advance ──

(defun helixel--repeat-advance-search (tx)
  "Find next search match for TX, skip current match for insert ops.
Positions point and sets `match-data' so `helixel--recreate-search'
can reuse it without re-searching.  Returns nil if no more matches.
Guards against zero-width patterns (`$', `^') that would
otherwise cause infinite loops at buffer edges.

When TX's sel has no `:pattern' (e.g. `insert-selection-end' outside
a search context), fall back to recreating the selection in-place."
  (let* ((sel (helixel-action-sel tx))
         (pat (helixel-sel-search-pattern sel)))
    (if (not pat)
        ;; Not a search-initiated insert — just recreate the
        ;; selection at point and return t (in-place repeat).
        (helixel--with-debug-log search-advance-non-search
            (progn (helixel-sel-call-recreate sel) t)
          (error nil))
      (let* ((dir (helixel-sel-search-dir sel))
             (entry-kind (helixel-sel-search-entry-kind sel))
             (regexp (helixel-sel-search-regexp sel)))
    (helixel-search--skip-current-match pat dir entry-kind regexp)
    (unless entry-kind
      (helixel-search--backward-unstick dir))
    (helixel--with-debug-log search-advance-core
        (progn
          (helixel-search--search pat dir nil nil regexp)
          (helixel-search--guard-repeat-advance pat dir regexp)
          (helixel--search-advance-done-set t)
          (helixel--search-advance-last-pos-set (match-beginning 0))
          (helixel-search--advance-n-count
           (helixel-sel-ctx sel)
           (lambda () (helixel-search--search pat dir nil nil regexp)))
          (helixel--with-span (helixel-sel-ctx sel)
            (helixel--recreate-selection sel))
          t)
      (search-failed nil))))))

(defsubst helixel-search--advance-past-zero-width (dir)
  "Step one char past a zero-width match in DIR.
Signals `search-failed' at buffer edge."
  (if (eq dir 'forward)
      (if (eobp) (signal 'search-failed nil) (forward-char 1))
    (if (bobp) (signal 'search-failed nil) (forward-char -1))))

(defun helixel-search--guard-repeat-advance (pat dir &optional regexp)
  "Guard against zero-width / repeated-match infinite loops.
Signals `search-failed' on deadlock; advances past zero-width repeats.
PAT and DIR are the current search pattern and direction.
REGEXP controls `isearch-regexp', forwarded to `helixel-search--search'."
  (let ((m-beg (match-beginning 0))
        (m-end (match-end 0)))
    ;; Zero-width pattern at buffer edge: allow first match only.
    (when (and (= m-beg m-end)
               (or (= m-beg (point-min))
                   (= m-beg (point-max))))
      (if (helixel--search-advance-edge-seen-p)
          (signal 'search-failed nil)
        (helixel--search-advance-edge-seen-set t)))
    ;; Repeated match at same position.
    (when (equal m-beg (helixel--search-advance-last-pos))
      (if (= m-beg m-end)
          ;; Zero-width: step over and re-search.
          (progn
            (helixel-search--advance-past-zero-width dir)
            (helixel-search--search pat dir nil nil regexp))
        ;; Non-zero-width repeated match — true deadlock.
        (signal 'search-failed nil)))))

(defun helixel--allbuffer-search-insert (tx sel start-pos dir)
  "Insert TX payload text at every SEL match from START-POS in DIR.
For `insert-search-offset' and `insert-selection-*' entry-kinds.
Uses :regexp from SEL to respect the \\=`M-r' toggle."
  (save-excursion
    (goto-char start-pos)
    (let* ((pat (helixel-sel-search-pattern sel))
           (entry-kind (helixel-sel-search-entry-kind sel))
           (regexp (helixel-sel-search-regexp sel))
           (txt (or (helixel-action-payload-get tx :inserted-text)
                    (helixel-action-payload-get tx :text)
                    ""))
           (last-pos nil)
           (cnt 0))
      (catch 'done
        (while (helixel-search--search pat dir nil 'noerror regexp)
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
  (let* ((sel (helixel-action-sel edit))
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
             (forced-action (helixel-action-copy edit)))
        (setf (helixel-action-sel forced-action) forced-sel)
        ;; Remember the start of the original edit so we can skip the
        ;; already-edited match when the replacement text happens to
        ;; contain the search pattern again (e.g. hello → helloworld).
        ;; The marker auto-tracks buffer changes so it stays correct.
        (let ((orig-edit-pos
               (when-let* ((m (car (helixel-action-mark-region
                                   forced-action))))
                 (copy-marker (marker-position m)))))
          (when orig-edit-pos
            (goto-char orig-edit-pos))
          (save-excursion
            (goto-char (if reverse-p (point-max) (point-min)))
            (let ((cnt 0))
              (while (helixel--repeat-advance forced-action forced-action)
                (if (and orig-edit-pos
                         (= (region-beginning)
                            (marker-position orig-edit-pos)))
                    ;; This match sits at the same position as the
                    ;; original edit (the replacement contains the
                    ;; search pattern).  Skip it so we don't re-edit.
                    (progn
                      (goto-char (region-end))
                      (set-marker orig-edit-pos nil)
                      (setq orig-edit-pos nil))
                  (cl-incf cnt)
                  (helixel-action-replay forced-action)))
              (when orig-edit-pos
                (set-marker orig-edit-pos nil))
              (helixel--repeat-echo cnt))))))))

;; ── Kind registrations ──

(helixel-register-kind search
  :ctx-schema '(:required (:pattern :dir)
                :optional (:entry-kind :n-count :cursor-offset :regexp))
  :recreate #'helixel--recreate-search
  :advance  #'helixel--repeat-advance-search
  :all-buffer-fn #'helixel--all-buffer-search
  :flip-dir-fn (lambda (sel)
                 (helixel-sel-update-ctx
                  sel :dir (helixel--flip-dir
                            (helixel-sel-search-dir sel))))
  :display  (lambda (ctx)
              (format "/%s/" (or (helixel-sel-search-pattern ctx) "?"))))

(helixel-register-kind find-char
  :ctx-schema '(:required (:char :type :dir) :optional (:inline-advance))
  :recreate #'helixel--recreate-find-char
  :advance  #'helixel--repeat-advance-movement
  :display  (lambda (ctx)
              (let* ((c (helixel-sel-find-char-char ctx))
                     (ty (helixel-sel-find-char-type ctx))
                     (dir (helixel-sel-find-char-dir ctx))
                     (prefix (if (eq ty 'till)
                                 (if (eq dir 'forward) ?t ?T)
                               (if (eq dir 'forward) ?f ?F))))
                (if c (format "%c→%c" prefix c) (string prefix)))))

;; ── Hook registrations ──

(defun helixel-search--init ()
  "Wire search lifecycle hooks."
  (add-hook 'helixel-mode-on-hook #'helixel-search-setup)
  (add-hook 'helixel-mode-off-hook #'helixel-search-teardown))
(helixel-search--init)

(provide 'helixel-search)
;;; helixel-search.el ends here
