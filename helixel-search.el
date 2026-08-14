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
;;   \\[helixel-search-forward\\] \\[helixel-search-backward\\]
;;       isearch-regexp forward/backward
;;   \\[helixel-search-at-point-next\\] \\[helixel-search-at-point-prev\\]
;;       search for symbol at point forward/backward
;;   \\[helixel-find-next-char\\] \\[helixel-find-prev-char\\]
;;   \\[helixel-find-till-char\\] \\[helixel-find-prev-till-char\\]
;;       find-char/till-char forward/backward
;;   \\[helixel-search-repeat-next\\] \\[helixel-search-repeat-reverse\\]
;;       repeat last search or find (reverse toggles direction)

;;; Code:

;; ── Forward declarations for variables in later-loaded modules ──
(defvar helixel--action-ring)
(defvar helixel--live-action)

(require 'helixel-state)
(require 'helixel-core)
(require 'helixel-macros)
(require 'helixel-repeat)
(require 'helixel-move)
(require 'helixel-motion)
(require 'helixel-register)

;; ── Search filter loop ──

(defun helixel--open-invisible-at (beg end)
  "Open invisible overlays covering BEG..END.

Calls `isearch-open-overlay-temporary' on each overlay that has an
`invisible' property and is not already opened (no `isearch-invisible'
flag).  This temporarily reveals hidden text (e.g. folded sections in
`org-mode') when a search or find-char match lands inside it, matching
the `search-invisible' = \='open behavior."
  (dolist (ov (overlays-in beg end))
    (when (and (overlay-get ov 'invisible)
               (not (overlay-get ov 'isearch-invisible)))
      (isearch-open-overlay-temporary ov))))

(defsubst helixel--search-advance-one (forwardp)
  "Advance one char past a zero-width match, or throw done.
FORWARDP is t for forward, nil for backward."
  (if forwardp
      (if (eobp) (throw 'search-filter-done nil)
        (forward-char 1))
    (if (bobp) (throw 'search-filter-done nil)
      (forward-char -1))))

(defsubst helixel--search-filter-loop (search-fn forwardp)
  "Call SEARCH-FN (zero-arg) repeatedly, skipping invisible matches.
SEARCH-FN must move point and set `match-data' on success; it should
return non-nil on success.  FORWARDP determines the direction for
skipping empty matches.  Returns the match position or nil.

Uses `isearch-filter-predicate' to check whether a match is visible,
respecting custom predicates (e.g. org-fold) and `search-invisible'.
The caller should bind `search-invisible' appropriately."
  (catch 'search-filter-done
    (while t
      (if (helixel--with-debug-log search-filter
            (funcall search-fn)
            (search-failed nil))
          (if (or (helixel--invisible-effective)
                  (funcall isearch-filter-predicate
                           (match-beginning 0) (match-end 0)))
              (progn
                (when (eq (helixel--invisible-effective) 'open)
                  (helixel--open-invisible-at (match-beginning 0)
                                              (match-end 0)))
                (throw 'search-filter-done (match-beginning 0)))
            ;; Invisible — advance past match and retry.
            (if (= (match-beginning 0) (match-end 0))
                (helixel--search-advance-one forwardp)
              (goto-char (match-end 0))))
        (throw 'search-filter-done nil)))))

;; ---------------------------------------------------------------------------
;; Groups and customs

(defgroup helixel-search nil
  "Search and find-char for `helixel-mode'."
  :group 'helixel)

(defcustom helixel-search-repeat-categories '(search find-char next-error)
  "Action :category symbols that `helixel-search-repeat-next' can repeat.
Supported values: `search', `find-char', and `next-error'."
  :type '(repeat (choice
                  (const :tag "Search (/ ? * #)" search)
                  (const :tag "Find-char (f F t T)" find-char)
                  (const :tag "Compilation next-error" next-error)))
  :set (lambda (sym val)
         (dolist (cat val)
           (unless (memq cat '(search find-char next-error))
             (display-warning 'helixel-search
                              (format "Unsupported repeat category: %s" cat))))
         (set-default sym val))
  :group 'helixel-search)

;; ---------------------------------------------------------------------------
;; PCRE support (soft dependency on pcre2el)

(defcustom helixel-search-pcre t
  "When non-nil, convert PCRE regexp syntax to Emacs regexp during search.

When t and the pcre2el package is available, patterns like \\d,
\\w, \\s etc. are translated to Emacs-compatible equivalents
\(e.g. [[:digit:]]) before searching.  Affects both interactive
isearch (\=/, \=?) and n/N repeat.

Requires pcre2el (<https://github.com/joddie/pcre2el>)."
  :type 'boolean
  :group 'helixel-search)

(defcustom helixel-search-use-region nil
  "When non-nil, / ? use active region text as search pattern.
When a region is active and this is enabled:
  - / ?  → literal search (regexp-quote region text)
Point is positioned past the selection before searching.
When nil, the normal interactive isearch prompt is used.

\\[universal-argument] / (\\[universal-argument] ?) toggles this:
  - when off → forces region-search for this invocation
  - when on  → forces interactive prompt
Does NOT affect * # (they always use `symbol-at-point' or
single-line region, regardless of this setting)."
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
returns the default search function unchanged.

The returned search function accepts the conventional optional COUNT
argument so that other providers can chain it safely.  When another
provider (such as liberime-regexp) is installed globally, searches
delegate to it so that its expansion applies; PCRE conversion is then
skipped because the provider already returns an elisp regexp."
  (if (and helixel-search-pcre (fboundp 'rxt-pcre-to-elisp))
      (lambda (string &optional bound noerror _count)
        (let ((global (or (default-value 'isearch-search-fun-function)
                          #'isearch-search-fun-default)))
          (if (eq global #'isearch-search-fun-default)
              (funcall (isearch-search-fun-default)
                       (if isearch-regexp
                           (helixel-search--pcre-to-elisp string)
                         string)
                       bound noerror)
            ;; A global provider is installed: delegate to it.  The provider
            ;; returns an elisp regexp, so PCRE conversion must be skipped.
            (funcall (funcall global) string bound noerror))))
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
;; what \\[helixel-search-repeat-next\\]/
;; \\[helixel-search-repeat-reverse\\] repeats and in which direction.
;;
;; Set by search, find-char, and \\[universal-argument\\]
;; \\[helixel-search-repeat-next\\]/\\[helixel-search-repeat-reverse\\].
;; Read by \\[helixel-search-repeat-next\\]/
;; \\[helixel-search-repeat-reverse\\] commands and
;; \\[helixel-repeat-edit\\] / \\[helixel-repeat-last-motion\\] repeat.
;;
;; :dir is MUTABLE — N flips it.  Event-ring entries are immutable
;; snapshots and never store mutable state.

(defvar-local helixel--active-search nil
  "Active repeat target as a `helixel--last-motion' struct.
Set by search and find-char commands.
Read by \\[helixel-search-repeat-next\\]/
\\[helixel-search-repeat-reverse\\] and \\[helixel-repeat-edit\\] /
\\[helixel-repeat-last-motion\\] repeat.
The :dir slot is MUTABLE —
\\[helixel-search-repeat-reverse\\] flips it.
Event-ring entries are immutable snapshots and never store
mutable state.

Holds the same struct type as `helixel--last-motion-cmd' —
a helixel--last-motion.  This variable is only overwritten
by search/find-char commands, so n/N survives intervening
movements (unlike `helixel--last-motion-cmd' which tracks the
most recent motion of any category for \\[helixel-repeat-last-motion]).")

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
Binds `search-invisible' and `isearch-invisible' to the effective
invisible mode (via `helixel--invisible-effective')."
  (declare (indent 0) (debug t))
  `(let ((search-invisible (helixel--invisible-effective))
         (isearch-invisible (helixel--invisible-effective)))
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
          (isearch-forward (eq dir 'forward))
          (isearch-case-fold-search case-fold-search)
          ;; When case-fold-search is nil, also suppress
          ;; search-upper-case so isearch-update-from-string-properties
          ;; doesn't re-enable case-insensitivity behind our back.
          (search-upper-case (and case-fold-search search-upper-case)))
      (if (helixel--invisible-effective)
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
Also stores :regexp from `helixel--active-search' so
\\[helixel-repeat-last-motion] and \\[helixel-repeat-edit]
respect toggle \\[isearch-toggle-regexp] the."
  (when-let* ((s helixel--active-search)
              (pat (helixel-search--safe-pattern))
              (dir (helixel-search--current-dir)))
    ;; Read previous n-count from existing pending-sel and increment.
    (let* ((prev-n (helixel-sel-n-count helixel--pending-sel))
           (n-count (if prev-n (1+ prev-n) 0))
           (regexp (helixel--last-motion-regexp s)))
      (helixel--sel-push (make-helixel-search-sel :pattern pat :dir dir :n-count n-count
                                                  :regexp regexp)))))

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
        ;; Record for motion repeat (bound to \\[helixel-repeat-last-motion]):
        ;; store category+pattern+dir+regexp so \\[helixel-repeat-last-motion]
        ;; can replay search
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

(defun helixel--find-char-runner (tx)
  "Replay a `find-char' action TX: restore search state and re-find.
Named runner so `find-char' ring entries stay pure data."
  (let ((c (helixel-action-char tx))
        (ty (helixel-action-type tx))
        (d (helixel-action-dir tx)))
    (setq helixel--active-search
          (make-helixel--last-motion
           :category 'find-char :type ty
           :char c :dir d))
    (helixel-search--find-char-core d)))

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
;; / ?  — prompt isearch-regexp (with register support)

(defun helixel-search--isearch-literal (pattern dir)
  "Enter isearch, feed PATTERN in DIR direction, and exit.
DIR is \=`forward' or \=`backward'.
Sets `isearch-regexp' to t and feeds PATTERN as a regexp.
The `isearch-mode-end-hook' fires `helixel-search--done-hook'
for commit/mark/echo — the caller must let-bind
`helixel-search--had-region' beforehand."
  (let ((inhibit-redisplay t)
        (isearch-wrap-pause 'no-ding))
    (add-hook 'isearch-mode-end-hook #'helixel-search--done-hook 0 t)
    (helixel--with-invisible-search
      (if (eq dir 'backward)
          (call-interactively #'isearch-backward-regexp)
        (call-interactively #'isearch-forward-regexp)))
    (setq isearch-regexp t)
    (isearch-process-search-string
     pattern (mapconcat #'isearch-text-char-description pattern ""))
    (isearch-exit)))

(defun helixel-search--from-register (dir &optional word-bound-p)
  "Search using active register content in DIR direction.
DIR is \=`forward' or \=`backward'.
When WORD-BOUND-P is non-nil, symbol-bound the pattern
\(for \=`*' and \=`#').
Reads text from `helixel--current-register' and consumes it.
Delegates to `helixel-search--isearch-literal' — the existing
`helixel-search--done-hook' machinery handles all state setup."
  (let ((text (helixel--register-get helixel--current-register)))
    (unless text
      (user-error "Register \"%c is empty" helixel--current-register))
    (helixel--register-consume)
    ;; When searching from a register the current region state is
    ;; irrelevant — the search target is the register content, not
    ;; the region.  `helixel-search--had-region' is not set here
    ;; because the done-hook ignores it anyway.
    (let ((pat (if word-bound-p
                   (concat "\\_<" (regexp-quote text) "\\_>")
                 (regexp-quote text))))
      (helixel-search--isearch-literal pat dir))))

(defun helixel-search--from-region (dir &optional word-bound-p)
  "Search for the active region's text in DIR direction.
DIR is \=`forward' or \=`backward'.
When WORD-BOUND-P is non-nil, wrap with \\_<...\\_>
\(for \=`*' and \=`#').  Otherwise `regexp-quote' the text
\(for \=`/' and \=`?').
Positions point past the current selection so the search finds
the next occurrence, not the selected one."
  (let* ((beg (region-beginning))
         (end (region-end))
         (text (filter-buffer-substring beg end))
         (helixel-search--had-region t)
         (pat (if word-bound-p
                  (concat "\\_<" (regexp-quote text) "\\_>")
                (regexp-quote text))))
    (deactivate-mark)
    (if (eq dir 'forward)
        (goto-char end)
      (goto-char (max (point-min) (1- beg))))
    (helixel-search--isearch-literal pat dir)))

(helixel-define-command helixel-search-forward
    (:category search :subcat search :clear-highlights nil
               :params (&optional arg))
  (interactive "P")
  (cond
   ((and (use-region-p)
         (if arg (not helixel-search-use-region) helixel-search-use-region))
    (helixel-search--from-region 'forward))
   ((helixel--register-active-p)
    (helixel-search--from-register 'forward))
   (t
    (when (use-region-p) (deactivate-mark))
    (add-hook 'isearch-mode-end-hook #'helixel-search--done-hook 0 t)
    (helixel--with-invisible-search
      (call-interactively #'isearch-forward-regexp)))))

(helixel-define-command helixel-search-backward
    (:category search :subcat search :clear-highlights nil
               :params (&optional arg))
  (interactive "P")
  (cond
   ((and (use-region-p)
         (if arg (not helixel-search-use-region) helixel-search-use-region))
    (helixel-search--from-region 'backward))
   ((helixel--register-active-p)
    (helixel-search--from-register 'backward))
   (t
    (when (use-region-p) (deactivate-mark))
    (add-hook 'isearch-mode-end-hook #'helixel-search--done-hook 0 t)
    (helixel--with-invisible-search
      (call-interactively #'isearch-backward-regexp)))))

;; ---------------------------------------------------------------------------
;; * #  — symbol at point

(defun helixel-search--bounds-at-point ()
  "Return (BEG . END) of the thing to search for at point.
When a single-line region is active, uses the region bounds;
otherwise uses the symbol at point."
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
         (bounds (helixel-search--bounds-at-point)))
    (if (< dir 0)
        (goto-char (if (= (point-min) (car bounds))
                       (point-max)
                     (1- (car bounds))))
      (goto-char (cdr bounds)))
    (helixel-search--isearch-literal
     (helixel-search--extract-regex bounds)
     (if (< dir 0) 'backward 'forward))))

(helixel-define-command helixel-search-at-point-next
    (:category search :subcat search :clear-highlights nil)
  (if (helixel--register-active-p)
      (helixel-search--from-register 'forward 'word)
    (helixel-search--at-point 1)))

(helixel-define-command helixel-search-at-point-prev
    (:category search :subcat search :clear-highlights nil)
  (if (helixel--register-active-p)
      (helixel-search--from-register 'backward 'word)
    (helixel-search--at-point -1)))

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
          (had-region (region-active-p))
          (isearch-case-fold-search case-fold-search))
      (when-let* ((pat (helixel-search--safe-pattern)))
        (setq isearch-string pat
              isearch-regexp (helixel--last-motion-regexp
                              helixel--active-search)
              isearch-forward (eq (helixel-search--current-dir) 'forward)))
      (if (< dir 0)
          (isearch-repeat-backward (- dir))
        (isearch-repeat-forward dir))
      (helixel-search--handle-done had-region)
      (helixel-search--set-sel-ctx)
      (helixel-search--echo-repeat-hint))))

;; ---------------------------------------------------------------------------
;; Find-char: f F t T

(defun helixel-search--find-char-set-sel (char type dir)
  "Push a find-char sel for CHAR, TYPE, DIR with incremented :n-count.
Tracks how many times n was pressed so . repeats the full sequence."
  (let* ((prev-pending helixel--pending-sel)
         (prev-n (when (and prev-pending
                            (eq (helixel-sel-kind prev-pending)
                                'helixel-find-char-sel))
                   (helixel-sel-n-count prev-pending)))
         (n-count (if prev-n (1+ prev-n) 0)))
    (helixel--sel-push
     (make-helixel-find-char-sel :char char :type type :dir dir :inline-advance t
                                 :n-count n-count))))

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
              #'helixel--find-char-runner))
      (helixel--action-commit)
      (helixel-search--set-dir sym-dir)
      (setq helixel--active-search
            (make-helixel--last-motion
             :category 'find-char :type type :char char :dir sym-dir))
      (helixel-search--echo-repeat-hint))))

(defun helixel-search--repeat-hint-prefix ()
  "Return a short description of the current search/find-char for echo.
Returns nil when `helixel--active-search' is nil.
For search: \"/hello\" for forward, \"?hello\" for backward.
For find-char: \"f->c\" (next-forward), \"F-<c\" (next-backward),
\"t->c\" (till-forward), \"T-<c\" (till-backward)."
  (when-let* ((s helixel--active-search)
              (cat (helixel--last-motion-category s)))
    (cl-case cat
      (search
       (let ((pat (helixel--last-motion-pattern s))
             (dir (helixel--last-motion-dir s)))
         (concat (if (eq dir 'forward) "/" "?")
                 pat)))
      (find-char
       (let ((char (helixel--last-motion-char s))
             (type (helixel--last-motion-type s))
             (dir (helixel--last-motion-dir s)))
         (concat
          (pcase (cons type dir)
            (`(next . forward)     "f")
            (`(next . backward)    "F")
            (`(till . forward)     "t")
            (`(till . backward)    "T")
            (_                     "f"))
          "->"
          (char-to-string char)))))))

(defun helixel-search--display-hint (&optional show-repeat)
  "Display search/find-char info and lazy count in the echo area.
When SHOW-REPEAT is non-nil, also show repeat key hints
\(\\[helixel-search-repeat-next] / \\[helixel-search-repeat-reverse]).

During isearch, the term is built from `isearch-string' directly
because `helixel--active-search' has not been set yet.
After isearch/find-char, the term comes from
`helixel--active-search' via `helixel-search--repeat-hint-prefix'."
  (let* ((in-isearch (bound-and-true-p isearch-mode))
         (prefix (if in-isearch
                     (when (and isearch-string
                                (not (string-empty-p isearch-string)))
                       (if isearch-regexp
                           (let ((c (if isearch-forward ?/ ??)))
                             (format "%c%s" c isearch-string))
                         isearch-string))
                   (helixel-search--repeat-hint-prefix)))
         (count (and isearch-lazy-count-current
                     (or in-isearch
                         (eq (helixel-search--safe-category) 'search))
                     (isearch-lazy-count-format)))
         (repeat-keys (when (and show-repeat (not in-isearch))
                        (concat "  "
                                (substitute-command-keys
                                 "\\[helixel-search-repeat-next] or \\[helixel-repeat-last-motion]")
                                " repeat, "
                                (substitute-command-keys
                                 "\\[helixel-search-repeat-reverse]")
                                " reverse direction and repeat")))
         (case-hint (propertize (if case-fold-search " [ci]" " [CS]")
                                'face 'font-lock-keyword-face)))
    (when prefix
      (message "%s%s%s%s"
               (propertize prefix 'face 'font-lock-variable-name-face)
               (if count
                   (concat " " (propertize count
                                           'face
                                           'font-lock-function-name-face))
                 "")
               case-hint
               (or repeat-keys "")))))

(defun helixel-search--echo-repeat-hint ()
  "Compatibility wrapper for `helixel-search--display-hint' with repeat."
  (helixel-search--display-hint t))

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
  (declare (indent 0) (debug (&define name sexp sexp stringp def-body)))
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
       ;; Record this as the last motion for \\[helixel-repeat-last-motion]
       ;; repeat.
       ;; Stash char/type/dir so \\[helixel-repeat-last-motion] replays
       ;; self-contained
       ;; without consulting `helixel--active-search'.
       (let ((sym-dir (if (> effective-dir 0) 'forward 'backward)))
         (helixel-record-motion ',name
                                :category 'find-char :char char
                                :type ',type :dir sym-dir))
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
  (when-let* ((n (or (helixel-sel-n-count ctx) 0))
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
  (let* ((pat (helixel-search-sel-pattern ctx))
         (dir (helixel-search-sel-dir ctx))
         (regexp (helixel-search-sel-regexp ctx))
         (pre-skip-pos (point)))
    (unless pat
      (user-error "No search pattern to repeat"))
    (helixel--with-span ctx
      (if (helixel--search-advance-done-p)
          (helixel--search-advance-done-set nil)
        ;; Internal search — only run when advance wasn't already done.
        (when (helixel-search--skip-current-match
               pat dir (helixel-sel-entry-kind ctx)
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
    (when-let* ((entry-kind (helixel-sel-entry-kind ctx)))
      (let* ((base (if (eq entry-kind 'append)
                       (match-end 0)
                     (match-beginning 0)))
             (cursor-offset (or (helixel-search-sel-cursor-offset ctx) 0)))
        (goto-char (+ base cursor-offset))))))

(defun helixel--recreate-find-char (ctx)
  "Recreate a find-char selection from CTX at point for dot-repeat.
Does :n-count extra searches after finding the char, so . repeats
the full f x n n sequence.  Extends region back to origin when
:span is set (from ; push)."
  (let ((n (or (helixel-sel-n-count ctx) 0))
        (dir (or (helixel-find-char-sel-dir ctx)
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
When CHAR, TYPE and DIR are given
\(from \\[helixel-repeat-last-motion]\), use them directly.
Otherwise (from \=`n') read from `helixel--active-search'.
Passes CHAR/TYPE/DIR explicitly to `helixel-search--find-char-core'
so no temp dynamic binding of `helixel--active-search' is needed.
Updates n-count in the pending sel so
\\[helixel-repeat-edit] repeats the full sequence.
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
            #'helixel--find-char-runner))
    (helixel-search--find-char-core dir char type)
    (helixel--action-commit)
    ;; Track n-count so . repeats the full n sequence.
    (helixel-search--find-char-set-sel char type dir)
    (helixel-search--echo-repeat-hint)))

;; Motion repeaters registered via `helixel-register-motion-repeater'

(defun helixel--repeat-search-motion (rec)
  "Replay a search (/) motion from REC.
Opens tracking, attaches a runner (`helixel-search--mc-runner'),
does the isearch at the real cursor, and commits.  This ensures
the unified mc dispatcher can replay this search at every fake
cursor via path 1 (runner replay, no isearch re-entry at fakes).

Note: `helixel-search--done-hook' is NOT on `isearch-mode-end-hook'
during `isearch-repeat', so we must populate and commit manually."
  (let* ((pat (helixel--last-motion-pattern rec))
         (dir (helixel--last-motion-dir rec))
         (regexp (helixel--last-motion-regexp rec))
         (forwardp (eq dir 'forward)))
    ;; Open tracking — the live action will carry the runner for mc dispatch.
    (helixel--tracking-open 'search nil)
    (when helixel--live-action
      (setf (helixel-action-payload helixel--live-action)
            (list :pattern pat :dir dir :regexp regexp))
      (setf (helixel-action-runner helixel--live-action)
            #'helixel-search--mc-runner))
    ;; Temporary active-search for the isearch-repeat at real cursor.
    (let ((helixel--active-search
           (make-helixel--last-motion
            :category 'search
            :pattern pat :dir dir :regexp regexp)))
      (helixel-search--isearch-repeat (if forwardp 1 -1)))
    ;; Commit the live action — it now has payload + runner for the
    ;; mc dispatcher to find and replay at fake cursors.
    (helixel--action-commit)))

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
;; \\[helixel-search-repeat-next\\] repeats the last search or find-char.
;; \\[helixel-search-repeat-reverse\\] flips direction, exchanges
;; point and mark, then delegates to
;; \\[helixel-search-repeat-next\\].
;;
;; \\[universal-argument\\] \\[helixel-search-repeat-next\\] picks
;; from history → executes in stored direction.
;; \\[universal-argument\\] \\[helixel-search-repeat-reverse\\] picks
;; from history → executes in opposite of stored direction.
;;
;; Direction lives in `helixel--repeat-dir', never in the event.
;; The event `:dir' is a historical record set at creation.

;; ── Internal: single-step repeat ──

(defun helixel-search--repeat-step ()
  "Execute one step of search/find-char/next-error repeat.
Reads category and direction from `helixel--active-search'.
Does NOT flip direction — callers handle direction changes."
  (let ((cat (helixel-search--safe-category))
        (dir (helixel-search--current-dir)))
    (pcase cat
      ('find-char (helixel-search--repeat-find-char))
      ('next-error
       (helixel-ne--step dir))
      (_ (helixel-search--isearch-repeat
          (if (eq dir 'forward) 1 -1))))))

;; ── n ──

(defun helixel-search-repeat-next (&optional arg)
  "Repeat last repeatable action in current direction.
ARG is the raw prefix argument.

Without prefix: repeat 1 time in current direction.
\\[negative-argument] (M--): flip direction permanently, repeat 1 time.
\\[negative-argument] N: flip direction, repeat |N| times.
Numeric prefix N: repeat N times in current direction.
\\[universal-argument]: pick from search history (stored direction)."
  (interactive "P")
  (cond
   ;; \\[universal-argument\\] → history
   ((consp arg)
    (helixel-search--from-history t))
   ;; \\[negative-argument\\] → flip direction permanently
   ((or (eq arg '-)
        (and (integerp arg) (< arg 0)))
    (helixel-search--flip-dir)
    (dotimes (_ (if (eq arg '-) 1 (abs arg)))
      (helixel-search--repeat-step)))
   ;; Numeric prefix → repeat N times
   ((integerp arg)
    (dotimes (_ arg)
      (helixel-search--repeat-step)))
   ;; No prefix → single repeat
   ((null arg)
    (helixel-search--repeat-step))
   ;; Any other non-nil (e.g. `t' for programmatic callers) → history
   (t
    (helixel-search--from-history t))))

;; ── N ──

(defun helixel-search-repeat-reverse (&optional arg)
  "Toggle direction, go back to start, then repeat.
ARG is the raw prefix argument.

Without prefix: flip direction, exchange point and mark, repeat 1.
\\[negative-argument] (M--): cancel the flip (i.e. repeat in
  current direction, undoing N's default flip), repeat 1.
\\[negative-argument] N: flip direction, repeat |N| times.
Numeric prefix N: flip direction, repeat N times.
\\[universal-argument]: pick from search history (opposite direction).

For kinds with `:skip-reverse-exchange' in the kind registry,
skips `exchange-point-and-mark' since those kinds manage
point and mark independently."
  (interactive "P")
  (let ((keep-mark (helixel-sel-skip-reverse-exchange-p
                    (helixel-search--safe-category))))
    (cond
     ;; \\[universal-argument\\] → history
     ((consp arg)
      (helixel-search--from-history nil))
     ;; \\[negative-argument\\] alone: undo N's default flip
     ((eq arg '-)
      (unless keep-mark (exchange-point-and-mark))
      (helixel-search--repeat-step))
     ;; \\[negative-argument\\] N → flip dir + repeat |N|
     ((and (integerp arg) (< arg 0))
      (helixel-search--flip-dir)
      (unless keep-mark (exchange-point-and-mark))
      (dotimes (_ (abs arg))
        (helixel-search--repeat-step)))
     ;; Numeric prefix → flip dir + repeat N
     ((integerp arg)
      (helixel-search--flip-dir)
      (unless keep-mark (exchange-point-and-mark))
      (dotimes (_ arg)
        (helixel-search--repeat-step)))
     ;; No prefix → single repeat with flip
     ((null arg)
      (helixel-search--flip-dir)
      (unless keep-mark (exchange-point-and-mark))
      (helixel-search--repeat-step))
     ;; Any other non-nil (e.g. `t' for programmatic callers) → history
     (t
      (helixel-search--from-history nil)))))

;; ── \\[universal-argument\\] \\[helixel-search-repeat-next\\] /
;;     \\[universal-argument\\] \\[helixel-search-repeat-reverse\\]
;;     from-history ──

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
and appears correctly in
\\[universal-argument\\] \\[helixel-search-repeat-next\\] history
and \\[helixel-action-cycle\\] cycling."
  (let ((cat (helixel-action-category event)))
    (helixel-search--set-dir use-dir)
    (pcase cat
      ('find-char
       (let* ((sel (helixel-action-sel event))
              (type (and sel (helixel-find-char-sel-type sel)))
              (char (and sel (helixel-find-char-sel-char sel))))
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
                 #'helixel--find-char-runner))
         (helixel--action-commit)
         (helixel-search--find-char-core use-dir)))
      ('search
       (let* ((sel (helixel-action-sel event))
              (pattern (or (and sel (helixel-search-sel-pattern sel))
                           (helixel-action-payload-get event :pattern)))
              (regexp (or (and sel (helixel-search-sel-regexp sel))
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
                    (helixel-search-sel-dir sel))
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
  "Display search term and match count in the echo area.
Delegates to `helixel-search--display-hint' which handles both
isearch and post-search/find-char display with unified formatting."
  (save-mark-and-excursion
    (helixel-search--display-hint t)))

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
         (pat (helixel-search-sel-pattern sel)))
    (if (not pat)
        ;; Not a search-initiated insert — just recreate the
        ;; selection at point and return t (in-place repeat).
        (helixel--with-debug-log search-advance-non-search
          (progn (helixel-sel-call-recreate sel) t)
          (error nil))
      (let* ((dir (helixel-search-sel-dir sel))
             (entry-kind (helixel-sel-entry-kind sel))
             (regexp (helixel-search-sel-regexp sel)))
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
             sel
             (lambda () (helixel-search--search pat dir nil nil regexp)))
            (helixel--with-span sel
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
REGEXP controls `isearch-regexp', forwarded to `helixel-search--search'.

Order matters: repeat guard runs FIRST — it steps past same-position
zero-width matches (e.g. \\b at a fixed position).  Edge guard runs
SECOND on whatever `match-data' remains (possibly clobbered by the
step-and-re-search).  This prevents false positives where \\b at
point-min would be incorrectly blocked by the edge guard, while
still catching \=`$' at a shifting point-max (the only case where
the edge guard is essential)."
  (let ((m-beg (match-beginning 0))
        (m-end (match-end 0)))
    ;; Repeated match at same position (runs first).
    (when (equal m-beg (helixel--search-advance-last-pos))
      (if (= m-beg m-end)
          ;; Zero-width: step over and re-search.
          (progn
            (helixel-search--advance-past-zero-width dir)
            (helixel-search--search pat dir nil nil regexp))
        ;; Non-zero-width repeated match — true deadlock.
        (signal 'search-failed nil)))
    ;; Zero-width pattern at buffer edge: allow first match only.
    ;; Uses whatever match-data is current (may have been updated by
    ;; the repeat guard's re-search above).
    (let ((m-beg (match-beginning 0))
          (m-end (match-end 0)))
      (when (and (= m-beg m-end)
                 (or (= m-beg (point-min))
                     (= m-beg (point-max))))
        (if (helixel--search-advance-edge-seen-p)
            (signal 'search-failed nil)
          (helixel--search-advance-edge-seen-set t))))))

(defun helixel--allbuffer-search-insert (tx sel start-pos dir)
  "Insert TX payload text at every SEL match from START-POS in DIR.
For `insert-search-offset' and `insert-selection-*' entry-kinds.
Uses :regexp from SEL to respect the \\=`M-r' toggle."
  (save-excursion
    (goto-char start-pos)
    (let* ((pat (helixel-search-sel-pattern sel))
           (entry-kind (helixel-sel-entry-kind sel))
           (regexp (helixel-search-sel-regexp sel))
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
            (when zlen
              (if (eobp) (throw 'done nil) (forward-char 1))))))
      (helixel--repeat-echo cnt))))

(defun helixel--all-buffer-search (edit prefix)
  "All-buffer repeat handler for search selections, for EDIT and PREFIX.
For entry-kind searches, inserts text at every match from
buffer edge.  For non-entry-kind, scans from point-min
using advance+apply without recursion."
  (let* ((sel (helixel-action-sel edit))
         (entry-kind (helixel-sel-entry-kind sel)))
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
             (forced-action (helixel-action-shallow-copy edit)))
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

(cl-defstruct (helixel-search-sel (:include helixel-sel)
                                  (:copier nil))
  "Search selection.  Slots: PATTERN, DIR, ENTRY-KIND, N-COUNT,
CURSOR-OFFSET, REGEXP."
  pattern
  (dir 'forward)
  entry-kind
  n-count
  cursor-offset
  (regexp t))


(cl-defstruct (helixel-find-char-sel (:include helixel-sel)
                                     (:copier nil))
  "Find-char selection.  Slots: CHAR, TYPE, DIR, N-COUNT
\(+ base INLINE-ADVANCE)."
  char
  (type 'next)
  (dir 'forward)
  n-count)


;; ── search protocol methods ──

(cl-defmethod helixel-sel-recreate ((sel helixel-search-sel))
  "Sel recreate method for SEL."
  (helixel--recreate-search sel))

(cl-defmethod helixel-sel-advance-fn ((_sel helixel-search-sel))
  "Sel advance fn method for SEL."
  #'helixel--repeat-advance-search)

(cl-defmethod helixel-sel-all-buffer-fn ((_sel helixel-search-sel))
  "Sel all buffer fn method for SEL."
  #'helixel--all-buffer-search)

(cl-defmethod helixel-sel-entry-kind ((sel helixel-search-sel))
  "Return the entry-kind of SEL."
  (helixel-search-sel-entry-kind sel))

(cl-defmethod helixel-sel-n-count ((sel helixel-search-sel))
  "Return the n-count of SEL."
  (helixel-search-sel-n-count sel))

(cl-defmethod helixel-sel-flip-dir ((sel helixel-search-sel))
  "Sel flip dir method for SEL."
  (helixel-sel-update-ctx
   sel :dir (helixel--flip-dir (helixel-search-sel-dir sel))))

(cl-defmethod helixel-sel-display ((sel helixel-search-sel))
  "Sel display method for SEL."
  (format "/%s/" (or (helixel-search-sel-pattern sel) "?")))

;; ── find-char protocol methods ──

(cl-defmethod helixel-sel-recreate ((sel helixel-find-char-sel))
  "Sel recreate method for SEL."
  (helixel--recreate-find-char sel))

(cl-defmethod helixel-sel-advance-fn ((_sel helixel-find-char-sel))
  "Sel advance fn method for SEL."
  #'helixel--advance-by-recreate)

(cl-defmethod helixel-sel-n-count ((sel helixel-find-char-sel))
  "Return the n-count of SEL."
  (helixel-find-char-sel-n-count sel))

(cl-defmethod helixel-mc-spawn-fn ((_sel helixel-find-char-sel))
  "Mc spawn fn method for SEL."
  'helixel-mc--spawn-from-find-char)

(cl-defmethod helixel-sel-flip-dir ((sel helixel-find-char-sel))
  "Sel flip dir method for SEL."
  (helixel-sel-update-ctx
   sel :dir (helixel--flip-dir (helixel-find-char-sel-dir sel))))

(cl-defmethod helixel-sel-display ((sel helixel-find-char-sel))
  "Sel display method for SEL."
  (let* ((c (helixel-find-char-sel-char sel))
         (ty (helixel-find-char-sel-type sel))
         (dir (helixel-find-char-sel-dir sel))
         (prefix (if (eq ty 'till)
                     (if (eq dir 'forward) ?t ?T)
                   (if (eq dir 'forward) ?f ?F))))
    (if c (format "%c→%c" prefix c) (string prefix))))

;; ── Hook registrations ──

;; ── Toggle case-fold ──

;;;###autoload
(defun helixel-toggle-case-fold ()
  "Toggle `case-fold-search' for search and multi-cursor commands.
Affects \\[helixel-search-repeat-next] (n), \\[helixel-search-repeat-reverse] (N),
\\[helixel-mc-mark-next-like-this] (s n), \\[helixel-mc-mark-previous-like-this] (s p),
\\[helixel-mc-select-regex] (s r), and find-char (f/F/t/T).
Also clears isearch lazy-highlight so stale highlights don't persist."
  (interactive)
  (setq-local case-fold-search (not case-fold-search))
  ;; Clear lazy-highlight so the next n/N shows matches with updated
  ;; case sensitivity, not stale pre-toggle highlights.
  (helixel-search--unhighlight)
  (helixel-search--display-hint)
  (message (concat "helixel: "
                   (propertize "case-fold-search "
                               'face 'font-lock-variable-name-face)
                   (propertize (if case-fold-search "on" "off")
                               'face 'font-lock-keyword-face)
                   " ("
                   (propertize (if case-fold-search
                                   "case-insensitive"
                                 "case-sensitive")
                               'face 'font-lock-keyword-face)
                   ")")))

(defun helixel-search--init ()
  "Wire search lifecycle hooks."
  (add-hook 'helixel-mode-on-hook #'helixel-search-setup)
  (add-hook 'helixel-mode-off-hook #'helixel-search-teardown))
(helixel-search--init)

(declare-function helixel-ne--step "helixel-next-error" (dir))

(provide 'helixel-search)
;;; helixel-search.el ends here
