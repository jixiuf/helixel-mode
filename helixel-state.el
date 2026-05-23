;;; helixel-state.el --- Modal state machine  -*- lexical-binding: t; -*-

;; Copyright (C) 2025-2026  jixiuf

;; Author: jixiuf
;; Keywords: convenience
;; URL: https://github.com/jixiuf/helixel-mode

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

;; Modal state machine for helixel-mode.
;;
;; Provides the modal editing framework: state switching, minor modes,
;; mode activation, keymap management, insert entry/exit, and the
;; `helixel-define-command' macro for action-tracking command definition.
;; Also houses the shared kill core, visual state, and all insert-variant
;; commands (i, a, I, A, o, O).
;;
;; Keymaps are NOT defined here — see `helixel-keymap' for keymap
;; definitions that populate `helixel-state-map-alist'.

;;; Code:

(require 'cl-lib)
(require 'helixel-action)
(require 'helixel-repeat)
(require 'helixel-register)
(require 'helixel-textobj)
(require 'helixel-surround)
(declare-function helixel-search--search "helixel-search")
(declare-function helixel--recreate-movement "helixel-common")
(declare-function helixel--recreate-insert-selection-start "helixel-common")
(declare-function helixel--recreate-insert-selection-end "helixel-common")
(declare-function helixel--recreate-insert-beginning-line "helixel-common")
(declare-function helixel--recreate-insert-end-line "helixel-common")
(declare-function helixel--linewise-text "helixel-move")
(declare-function helixel--rect-wise-text "helixel-move")
(declare-function helixel--line-bounds-of-region "helixel-move")

(defvar rectangle-mark-mode)


(defcustom helixel-major-mode-default-states
  '((calc-mode . insert)
    (Custom-mode . normal))
  "Alist mapping major modes to default Helixel states.
Each element should be a cons cell (MAJOR-MODE . STATE), where
MAJOR-MODE is a symbol like `dired-mode', and STATE is one of
`normal', `motion' or `insert'.
When `helixel-mode' is activated in a buffer, the state is chosen by
looking up the current major mode in this alist, falling back to guess
based on key bindings: if letters a-z are bound to self-insert commands,
use `normal', otherwise `motion'."
  :type '(alist :key-type symbol :value-type
                (choice (const normal) (const motion) (const insert)))
  :group 'helixel)

(defcustom helixel-replace-delete-char-p nil
  "When non-nil, delete char at point before inserting yanked text.
When no region is active, this controls whether to replace the char
at point (t) or simply insert without deleting (nil)."
  :type 'boolean
  :group 'helixel)

(defcustom helixel-motion-parent-excluded-modes
  '(special-mode Custom-mode)
  "List of major modes excluded from motion-state keymap parent patching.

When a buffer enters motion state and its `major-mode' is not in
this list, the mode's keymap parent is extended with
`helixel-normal-map', giving fallback access to normal-state
commands (scroll, `;' action cycle, etc.)."
  :type '(repeat symbol)
  :group 'helixel)


(defvar-local helixel--current-state 'normal
  "Current modal state, one of normal, insert, or motion.")


(defvar helixel-state-alist
  `((insert . helixel-insert-state)
    (normal . helixel-normal-state)
    (visual . helixel-visual-state)
    (motion . helixel-motion-state))
  "Alist of symbol state name to minor mode.")

(defvar-local helixel--selection-type nil
  "Current selection type.
nil means charwise, `line' means linewise, `rect' means rectangle.")

(defvar-local helixel--rect-replay-info nil
  "Plist for rect change replay: (:col N :line-count N :marker M).
Set by `helixel--rect-change', consumed by `helixel-insert-exit'
via `helixel--rect-replay-get' and `helixel--rect-replay-clear'.")

(defun helixel--rect-replay-get ()
  "Return the rect-replay info plist, or nil."
  helixel--rect-replay-info)

(defun helixel--rect-replay-set (info)
  "Set rect-replay info to INFO plist."
  (setq helixel--rect-replay-info info))

(defun helixel--rect-replay-clear ()
  "Clear rect-replay info, releasing the marker."
  (when-let* ((m (plist-get helixel--rect-replay-info :marker)))
    (set-marker m nil))
  (setq helixel--rect-replay-info nil))

(defvar helixel-global-mode nil
  "Enable Helixel mode in all buffers.")

;; ── Forward declarations for keymap variables ──
;; Created as empty keymap shells so `:keymap' in `define-minor-mode'
;; captures a real keymap object.  `helixel-keymap' fills them with
;; `define-key' (same object — reference never breaks).

(defvar helixel-visual-map (define-keymap))
(defvar helixel-insert-map (define-keymap))
(defvar helixel-view-map (make-sparse-keymap))
(suppress-keymap helixel-view-map)

(defvar helixel-goto-map (make-sparse-keymap))
(suppress-keymap helixel-goto-map)
(set-keymap-parent helixel-goto-map goto-map)

(defvar helixel-window-map (make-sparse-keymap))
(suppress-keymap helixel-window-map)

(defvar helixel-space-map (make-sparse-keymap))
(suppress-keymap helixel-space-map)

(defvar helixel-normal-map (make-sparse-keymap))
(suppress-keymap helixel-normal-map)

(defvar helixel-motion-map (make-sparse-keymap))
(suppress-keymap helixel-motion-map)

(defvar helixel-textobj-map (define-keymap))

(defvar helixel-textobj-inner-map (make-sparse-keymap))
(suppress-keymap helixel-textobj-inner-map)

(defvar helixel-textobj-outer-map (make-sparse-keymap))
(suppress-keymap helixel-textobj-outer-map)

(defvar helixel-state-map-alist nil
  "Alist mapping a state symbol to a Helixel keymap.
Populated by `helixel-keymap' at load time.")

(defvar helixel--mode-keybindings nil
  "Alist of ((MODE . STATE) . sparse-keymap).
MODE is a major or minor mode symbol.  STATE is a helixel state symbol.
Stores mode-specific helixel bindings registered via `helixel-define-key'.")

;; ── Command definition macro ──
;;
;; All helixel commands use `helixel-define-command' to declare their
;; action metadata.  Tracking code (action-start, direction, highlight
;; clearing, visual-mode tracking) is expanded inline at compile time.
;;
;; Editing commands should additionally call `helixel--record-edit'
;; in their body (or use `helixel-define-operator' which handles both).

(defmacro helixel-define-command (name metadata &rest body)
  "Define a helixel command NAME with METADATA auto-tracking.

METADATA is a plist:
  :category CAT — action category (movement, edit, search, state, etc.)
  :subcat   SUB — action subcategory (word, kill, insert, etc.)
  :dir      DIR — direction for n/N repeat context (forward, backward)
  :clear-highlights — default t for :category movement, nil otherwise
  :params   PARAM-LIST — optional function parameter list

For :category movement:
  - Auto-injects `helixel--track-visual-move' for `.` replay in visual mode
  - Auto-injects `helixel--clear-highlights' (unless :clear-highlights nil)

All tracking code is expanded inline at compile time — zero hooks.
BODY is the command's business logic."
  (declare (indent 2))
  (let* ((cat (plist-get metadata :category))
         (sub (plist-get metadata :subcat))
         (dir (plist-get metadata :dir))
         (clear (if (plist-member metadata :clear-highlights)
                    (plist-get metadata :clear-highlights)
                  (eq cat 'movement)))
         (has-interactive (and (consp (car body))
                               (eq (caar body) 'interactive)))
         (interactive-form (if has-interactive (car body) '(interactive)))
         (rest-body (if has-interactive (cdr body) body))
         (params (plist-get metadata :params))
         (track-visual
          (when (eq cat 'movement)
            `((helixel--track-visual-move ',name)))))
    `(defun ,name ,(or params ())
       ,(format "Helixel %s.%s command." cat sub)
       ,interactive-form
       ;; ── Action tracking (for ; and C-o/C-i) ──
       (helixel-action-start ',cat ',sub)
       ;; ── Direction (for n/N repeat) ──
       ,@(when dir `((helixel--live-cat-set-dir ',dir)))
       ;; ── Highlight clearing ──
       ,@(when clear '((helixel--clear-highlights)))
       ;; ── Body (pure business logic) ──
       ,@rest-body
       ;; ── Visual-mode tracking (for . replay of movements) ──
       ;; Only movement commands accumulate moves; edit commands
       ;; record the accumulated moves via `helixel--record-edit'.
       ,@track-visual)))

;; ── Operator definition macro ──
;;
;; Combines command definition + op registration for `.` repeat.
;; Replaces the old :repeatable / :edit-op patterns with a single,
;; explicit form.

(defmacro helixel-define-operator (name metadata &rest body)
  "Define a helixel editing operator NAME.

Combines command definition (action tracking for \=`;\=` jumping
and jump-list navigation) with
op registration (for `.` repeat) into a single form.

METADATA is a plist:
  :op OP              — operator symbol for `.` (required)
  :display DISPLAY    — label string or function (TX) -> string
  :repeat-advance TAG — nil, `line', or function
  :subcat SUB         — action subcategory (default: OP)
  :params PARAMS      — function parameter list

Expands to:
  1. (helixel-register-op OP :display ... :runner (lambda () (NAME)))
  2. (helixel-define-command NAME (:category edit ...) BODY)

The command body SHOULD call (helixel--record-edit OP ...) to record
the edit for `.` replay."
  (declare (indent 2))
  (let* ((op (plist-get metadata :op))
         (display (plist-get metadata :display))
         (advance (plist-get metadata :repeat-advance))
         (subcat (or (plist-get metadata :subcat) op)))
    (unless op
      (error "helixel-define-operator: :op is required"))
    `(progn
       ;; ── Op registration (for . replay) ──
       (helixel-register-op ,op
         :display ,display
         :repeat-advance ,advance
         :runner (lambda (_tx) (,name)))
       ;; ── Command definition (for action tracking) ──
       (helixel-define-command ,name
           (:category edit :subcat ,subcat
            ,@(when-let* ((p (plist-get metadata :params)))
                (list :params p)))
         ,@body))))

;; Wire textobj hooks for action recording and visual state detection.
(setq helixel-textobj-action-function #'helixel-action-start)
(setq helixel-textobj-visual-state-p-function
      (lambda () (eq helixel--current-state 'visual)))
(setq helixel-jump-cleanup-function #'helixel--clear-data)
(add-hook 'helixel-action-push-functions #'helixel--jump-list-push)

(defun helixel--unload-current-state ()
  "Deactivate the minor mode described by `helixel--current-state'."
  (let ((mode (alist-get helixel--current-state helixel-state-alist)))
    (funcall mode -1)))

(defun helixel--switch-state (state)
  "Switch to STATE."
  (unless (eq state helixel--current-state)
    (helixel--unload-current-state)
    (helixel--clear-data)
    (setq-local helixel--current-state state)
    (let ((mode (alist-get state helixel-state-alist)))
      (funcall mode 1))
    (helixel--refresh-overriding-maps)))

(defun helixel--clear-data ()
  "Clear any intermediate data, e.g. selections/mark."
  (setq helixel--selection-type nil)
  (when rectangle-mark-mode
    (rectangle-mark-mode -1))
  (deactivate-mark))

(defun helixel--track-visual-move (cmd)
  "Append movement CMD to `helixel--repeat-sel-ctx'.
Creates/updates a `helixel-sel' struct of kind `movement' whenever
a region is active — from visual mode or `normal-mode' movements that
created a selection (e.g. w, e, b).
No-op during dot-repeat replay, or when no region is active."
  (when (and (not helixel--inhibit-repeat-record)
             (use-region-p))
    (let* ((ctx helixel--repeat-sel-ctx)
           (entry (cons cmd 1)))
      (cond
       ;; Update: extend existing movement sel.
       ((and ctx (eq (helixel-sel-get-kind ctx) 'movement))
        (let* ((moves (helixel-sel-movement-moves ctx))
               (last (car moves)))
          (if (and last (eq (car last) cmd))
              (setcdr last (1+ (cdr last)))
            (helixel--repeat-sel-set
             (helixel-sel-update-ctx ctx :moves
                                     (cons entry moves))))))
       ;; Create: first movement that made a region.
       ;; Only when no sel exists — never clobber line/rect/textobj.
       ((null ctx)
        (helixel--repeat-sel-set
         (helixel-sel-create 'movement
                             `(:moves (,entry) :inline-advance t
                               :normal-mode ,(eq helixel--current-state 'normal))
                             #'helixel--recreate-movement
                             (lambda (c)
                               (let ((ms (helixel-sel-movement-moves c)))
                                 (let ((n (apply #'+ (mapcar #'cdr ms))))
                                   (format "v%d" n))))
                             :advance #'helixel--repeat-advance-movement)))))))

(defun helixel--enter-insert ()
  "Enter insert mode, recording buffer changes via the change hooks.
Sets up change-hook recording and switches to insert state."
  (helixel--insert-begin)
  (helixel--switch-state 'insert))

(helixel-define-command helixel-insert
    (:category state :subcat insert)
  (cond
   ;; Search context: refine the search sel with entry-kind
   ((and (helixel--repeat-sel-get)
         (eq (helixel-sel-get-kind (helixel--repeat-sel-get)) 'search))
     (helixel--repeat-sel-set
          (helixel-sel-update-ctx (helixel--repeat-sel-get)
                                  :entry-kind 'insert))
    (goto-char (region-beginning)))
   ;; Line selection: preserve sel for `.` auto-advance
   ((and (helixel--repeat-sel-get)
         (eq (helixel-sel-get-kind (helixel--repeat-sel-get)) 'line))
     (helixel--repeat-sel-set
          (helixel-sel-update-ctx (helixel--repeat-sel-get)
                                  :entry-kind 'insert))
    (goto-char (region-beginning)))
   ;; Manual region
   ((use-region-p)
     (helixel--repeat-sel-set
          (helixel-sel-create
           'insert-selection-start nil
           #'helixel--recreate-insert-selection-start "is"))
    (goto-char (region-beginning)))
   ;; No context
   (t
    (helixel--repeat-sel-clear)))
  (helixel--record-edit 'insert-text)
  (setq helixel--change-track-marker (point-marker))
  (helixel--enter-insert))

(helixel-define-command helixel-insert-exit
    (:category state :subcat exit)
  (let* ((result (helixel--insert-finish))
         (keys (car result))
         (commands (cdr result))
         (text (when helixel--change-track-marker
                 (and (marker-position helixel--change-track-marker)
                      (buffer-substring
                       helixel--change-track-marker (point))))))
    (unless executing-kbd-macro
      (when helixel--last-tx
        (let ((tx helixel--last-tx))
          ;; Store kmacro keys as primary replay mechanism.
          ;; Skip empty vectors — they are truthy but useless,
          ;; and cause nil-key errors in `helixel--execute-keys'.
          (when (and keys (> (length keys) 0))
            (setq tx (helixel-edit-with-payload tx :keys keys)))
          ;; Store executed commands (keymap-independent replay)
          (when commands
            (setq tx (helixel-edit-with-payload tx :commands commands)))
          ;; Store text as replay fallback (tests, programmatic use)
          (when text
            (setq tx (helixel-edit-with-payload tx :text text))
            ;; For change operations, same text as :inserted-text
            (when (eq (helixel-edit-op tx) 'change)
              (setq tx (helixel-edit-with-payload tx
                                                  :inserted-text text))))
          (helixel--update-last-tx tx))))
    ;; Cleanup
    (when helixel--change-track-marker
      (set-marker helixel--change-track-marker nil)
      (setq helixel--change-track-marker nil))
    ;; Rect replay
    (when (helixel--rect-replay-get)
      (helixel--rect-replay))
    ;; Switch state
    (let ((state (helixel--default-state-for-buffer)))
      (when (eq state 'insert)
        (setq state 'normal))
      (helixel--switch-state state))))

(defun helixel--clear-highlights ()
  "Clear any active highlight, unless in visual state.
Also preserve highlights when `rectangle-mark-mode' is active."
  (unless (or (eq helixel--current-state 'visual) rectangle-mark-mode)
    (deactivate-mark)))

;; ── Insert variant commands ──

(helixel-define-command helixel-insert-after
    (:category state :subcat insert)
  (cond
   ;; Search context: refine the search sel with entry-kind
   ((and (helixel--repeat-sel-get)
         (eq (helixel-sel-get-kind (helixel--repeat-sel-get)) 'search))
     (helixel--repeat-sel-set
          (helixel-sel-update-ctx (helixel--repeat-sel-get)
                                  :entry-kind 'append))
    (goto-char (region-end)))
   ;; Line selection: preserve sel for `.` auto-advance
   ((and (helixel--repeat-sel-get)
         (eq (helixel-sel-get-kind (helixel--repeat-sel-get)) 'line))
     (helixel--repeat-sel-set
          (helixel-sel-update-ctx (helixel--repeat-sel-get)
                                  :entry-kind 'append))
    (goto-char (region-end)))
   ;; Manual region
   ((use-region-p)
     (helixel--repeat-sel-set
          (helixel-sel-create
           'insert-selection-end nil
           #'helixel--recreate-insert-selection-end "ie"))
    (goto-char (region-end)))
   ;; No context
   (t
    (unless (helixel--end-of-line-p)
      (forward-char))
    (helixel--repeat-sel-clear)))
  (helixel--record-edit 'insert-text)
  (setq helixel--change-track-marker (point-marker))
  (helixel--enter-insert))

(helixel-define-command helixel-insert-beginning-line
    (:category state :subcat insert)
  (beginning-of-line)
   (helixel--repeat-sel-set
        (helixel-sel-create
         'insert-beginning-line nil
         #'helixel--recreate-insert-beginning-line "I"))
  (helixel--record-edit 'insert-text)
  (setq helixel--change-track-marker (point-marker))
  (helixel--enter-insert))

(helixel-define-command helixel-insert-after-end-line
    (:category state :subcat insert)
  (end-of-line)
   (helixel--repeat-sel-set
        (helixel-sel-create
         'insert-end-line nil
         #'helixel--recreate-insert-end-line "A"))
  (helixel--record-edit 'insert-text)
  (setq helixel--change-track-marker (point-marker))
  (helixel--enter-insert))

(helixel-define-command helixel-insert-newline
    (:category state :subcat insert)
  (helixel--record-edit 'insert-text)
  (helixel--clear-data)
  (end-of-line)
  (newline-and-indent)
  (setq helixel--change-track-marker (point-marker))
  (helixel--enter-insert))

(helixel-define-command helixel-insert-prevline
    (:category state :subcat insert)
  (helixel--record-edit 'insert-text)
  (helixel--clear-data)
  (beginning-of-line)
  (let ((electric-indent-mode nil))
    (newline nil t)
    (call-interactively #'previous-line)
    (indent-according-to-mode))
  (setq helixel--change-track-marker (point-marker))
  (helixel--enter-insert))

;; ── Visual state ──

(defun helixel-visual-exit ()
  "Exit visual state and return to normal state."
  (interactive)
  (helixel--switch-state (helixel--default-state-for-buffer)))

(defun helixel-begin-selection ()
  "Begin visual selection or exit visual state."
  (interactive)
  (if (eq helixel--current-state 'visual)
      (helixel-visual-exit)
    (when rectangle-mark-mode
      (rectangle-mark-mode -1))
    (helixel--switch-state 'visual)
    (setq helixel--selection-type nil)
    (push-mark-command t t)))

(defun helixel--end-of-line-p ()
  "Return non-nil if current point is at the end of the current line."
  (save-excursion
    (let ((cur (point))
          eol)
      (end-of-line)
      (setq eol (point))
      (= cur eol))))

;; ── Shared kill core ──

(declare-function helixel--rect-change "helixel-move")
(declare-function helixel--rect-replay "helixel-move")

(defun helixel--delete-selection ()
  "Delete current region or char at point, pushing to `kill-ring'.
Does NOT record an edit and does NOT clear selection data.
Used as the shared kill core by `helixel-kill-thing-at-point',
`helixel-change-thing-at-point', and `helixel--repeat-change-core'."
  (cond
   ((not (use-region-p))
    (helixel--kill-new (char-to-string (char-after)))
    (delete-char 1))
   ((eq (helixel--selection-type) 'rect)
    (let ((lines (extract-rectangle (region-beginning) (region-end))))
      (delete-rectangle (region-beginning) (region-end))
      (helixel--kill-new (helixel--rect-wise-text lines))))
   ((eq (helixel--selection-type) 'line)
    (if-let* ((bounds (helixel--line-bounds-of-region))
              (text (filter-buffer-substring (car bounds) (cdr bounds))))
        (progn
          (helixel--kill-new (helixel--linewise-text text))
          (delete-region (car bounds) (cdr bounds)))))
   (t
    (when (and (eolp) (<= (region-beginning) (pos-bol)))
      (forward-visible-line 1))
    (helixel--kill-new
     (filter-buffer-substring (region-beginning) (region-end)))
    (delete-region (region-beginning) (region-end)))))

;; ── Keymap management ──

(defun helixel-define-key (state key def &rest modes)
  "Define a Helixel keybinding for KEY to DEF.

When MODES is nil, bind to the keymap associated with STATE from
`helixel-state-map-alist'.  When MODES is provided, each argument
is a major or minor mode symbol for which the binding takes
precedence via `minor-mode-overriding-map-alist'.

Argument STATE must be one of: insert, normal, motion, visual, view,
goto, window, space, textobj (m prefix), textobj-inner (mi prefix),
textobj-outer (ma prefix).

Argument KEY and DEF follow the same conventions as `define-key'.

Any arguments after DEF are treated as mode symbols.

Example:
  ;; Standard: bind to Helix's normal state keymap
  (helixel-define-key \\='normal \"s\" #\\='my-command)

  ;; Major-mode specific: override normal state bindings in Dired
  (with-eval-after-load \\='Dired
    (helixel-define-key \\='normal \"j\" #\\='dired-next-line \\='dired-mode)
    (helixel-define-key \\='normal \"k\"
      #\\='dired-previous-line \\='dired-mode))

  ;; Motion state with major-mode specific bindings
  (helixel-define-key \\='motion \"j\" #\\='next-line \\='prog-mode)
  (helixel-define-key \\='motion \"k\" #\\='previous-line \\='prog-mode)

  ;; Mode-specific text object binding (org-mode only)
  (helixel-define-key \\='textobj-inner \"o\"
    #\\='helixel-mark-inner-org-block \\='org-mode)
  (helixel-define-key \\='textobj-outer \"o\"
    #\\='helixel-mark-a-org-block \\='org-mode)

  ;; Bind to multiple modes at once
  (helixel-define-key \\='normal \"j\" #\\='next-line
    \\='prog-mode \\='text-mode)
  (helixel-define-key \\='normal (kbd \"C-i\") nil
    \\='org-mode \\='markdown-mode)"
  (unless (alist-get state helixel-state-map-alist)
    (error "Invalid state %s" state))
  (if modes
      ;; Store binding in helixel--mode-keybindings
      (dolist (m modes)
        (let* ((alist-key (cons m state))
               (entry (assoc alist-key helixel--mode-keybindings)))
          (unless entry
            (setq entry (cons alist-key (make-sparse-keymap)))
            (push entry helixel--mode-keybindings))
          (define-key (cdr entry) key def)))
    ;; Bind to global state keymap
    (let ((state-keymap (alist-get state helixel-state-map-alist)))
      (define-key state-keymap key def))))

(defun helixel--refresh-overriding-maps ()
  "Rebuild `minor-mode-overriding-map-alist' for the current buffer."
  (let ((state helixel--current-state)
        (state-mode (alist-get helixel--current-state helixel-state-alist))
        (overrides nil))
    (dolist (entry helixel--mode-keybindings)
      (let ((mode (caar entry)))
        (when (and (eq (cdar entry) state)
                   (or (eq mode major-mode)
                       (and (boundp mode) (symbol-value mode))))
          (push (cdr entry) overrides))))
    (setq minor-mode-overriding-map-alist
          (assq-delete-all state-mode minor-mode-overriding-map-alist))
    (when overrides
      (let ((base-keymap (alist-get state helixel-state-map-alist)))
        (push (cons state-mode (make-composed-keymap overrides base-keymap))
              minor-mode-overriding-map-alist)))
    ;; Textobj sub-map mode-specific overrides
    (helixel--refresh-textobj-overrides)))

(defun helixel--refresh-textobj-overrides ()
  "Build mode-specific composed keymaps for textobj inner/outer.
When `helixel--mode-keybindings' contains entries for `textobj-inner'
or `textobj-outer' in the current `major-mode', make
`helixel-textobj-map' buffer-local and point its \"i\"/\"a\" entries
to composed keymaps with mode overrides on top of the base maps."
  (let ((inner-overrides nil)
        (outer-overrides nil))
    (dolist (entry helixel--mode-keybindings)
      (let ((mode (caar entry))
            (sub (cdar entry)))
        (when (or (eq mode major-mode)
                  (and (boundp mode) (symbol-value mode)))
          (cond ((eq sub 'textobj-inner)
                 (push (cdr entry) inner-overrides))
                ((eq sub 'textobj-outer)
                 (push (cdr entry) outer-overrides))))))
    ;; Restore defaults when no overrides
    (unless (or inner-overrides outer-overrides)
      (when (local-variable-p 'helixel-textobj-map)
        (define-key helixel-textobj-map "i" helixel-textobj-inner-map)
        (define-key helixel-textobj-map "a" helixel-textobj-outer-map)
        (kill-local-variable 'helixel-textobj-map)))
    ;; Build composed keymaps with overrides
    (when (or inner-overrides outer-overrides)
      (make-local-variable 'helixel-textobj-map)
      (when inner-overrides
        (define-key helixel-textobj-map "i"
                    (make-composed-keymap inner-overrides
                                          helixel-textobj-inner-map)))
      (when outer-overrides
        (define-key helixel-textobj-map "a"
                    (make-composed-keymap outer-overrides
                                          helixel-textobj-outer-map))))))

;; ── Minor modes ──

(define-minor-mode helixel-insert-state
  "Helixel INSERT state minor mode."
  :lighter " helixel[I]"
  :init-value nil
  :interactive nil
  :global nil
  :keymap helixel-insert-map
  (if helixel-insert-state
      (progn
        (setq-local helixel--current-state 'insert)
        (setq cursor-type 'bar))
    (setq-local helixel--current-state 'normal)))

;;;###autoload
(define-minor-mode helixel-motion-state
  "Helixel MOTION state minor mode for read-only navigation.
Only j, k, g keys are available by default.
Use `helixel-define-key' to add major-mode specific bindings."
  :lighter " helixel[M]"
  :init-value nil
  :interactive nil
  :global nil
  :keymap helixel-motion-map
  (if helixel-motion-state
      (progn
        (setq-local helixel--current-state 'motion)
        (setq cursor-type 'box)
        (helixel--refresh-overriding-maps))
    (setq-local helixel--current-state 'normal)))

(define-minor-mode helixel-visual-state
  "Helixel VISUAL state minor mode."
  :lighter " helixel[V]"
  :init-value nil
  :interactive nil
  :global nil
  :keymap helixel-visual-map
  (if helixel-visual-state
      (progn
        (setq-local helixel--current-state 'visual)
        (setq cursor-type 'box)
        (helixel--refresh-overriding-maps))
    (setq-local helixel--current-state 'normal)))

;;;###autoload
(define-minor-mode helixel-normal-state
  "Helixel NORMAL state minor mode.
This is the internal minor mode; prefer \[helixel-enter-normal-state]
for state transitions."
  :lighter " helixel[N]"
  :init-value nil
  :interactive t
  :global nil
  :keymap helixel-normal-map
  (if helixel-normal-state
      (progn
        (setq-local helixel--current-state 'normal)
        (setq cursor-type 'box)
        (helixel--refresh-overriding-maps))))

;; ── Public state API ──
;; Safe wrappers around `helixel--switch-state' for hooks, advice,
;; and interactive use.  These properly unload the current state
;; before entering the new one.

;;;###autoload
(defun helixel-enter-normal-state (&rest _)
  "Enter normal state, properly unloading the current state.
Safe for use in hooks and `:after' advice."
  (interactive)
  (helixel--switch-state 'normal))

;;;###autoload
(defun helixel-enter-motion-state (&rest _)
  "Enter motion state, properly unloading the current state.
Safe for use in hooks and `:after' advice."
  (interactive)
  (helixel--switch-state 'motion))

;;;###autoload
(defun helixel-enter-insert-state (&rest _)
  "Enter insert state, properly unloading the current state.
Safe for use in hooks and `:after' advice."
  (interactive)
  (helixel--switch-state 'insert))

;; Predicates — check the current state.

(defun helixel-normal-state-p ()
  "Return non-nil if the current Helixel state is normal."
  (eq helixel--current-state 'normal))

(defun helixel-motion-state-p ()
  "Return non-nil if the current Helixel state is motion."
  (eq helixel--current-state 'motion))

(defun helixel-insert-state-p ()
  "Return non-nil if the current Helixel state is insert."
  (eq helixel--current-state 'insert))

(defun helixel-visual-state-p ()
  "Return non-nil if the current Helixel state is visual."
  (eq helixel--current-state 'visual))

;; ── Motion-state keymap parent patching ──
;; Extend major-mode keymaps with `helixel-normal-map' as fallback
;; parent so that normal-state commands (scroll, `;' action cycle,
;; etc.) are available in motion state.

(defvar helixel--motion-parent-patched (make-hash-table :test #'eq)
  "Set of major modes whose keymap parent has been patched.
Used by `helixel--motion-patch-keymap-parent' to avoid repeated
patching.")

(defun helixel--motion-patch-keymap-parent ()
  "Extend the current major-mode keymap parent for motion state.
Composes the mode's original keymap parent with
`helixel-normal-map' so normal-state fallbacks are available.
Skips modes listed in `helixel-motion-parent-excluded-modes'.

Runs on `helixel-motion-state-hook'."
  (unless (memq major-mode helixel-motion-parent-excluded-modes)
    (when (and (helixel-motion-state-p)
               (not (gethash major-mode
                             helixel--motion-parent-patched)))
      (puthash major-mode t helixel--motion-parent-patched)
      (let ((map (if (keymapp major-mode)
                     major-mode
                   (when-let* ((name (intern (concat (symbol-name major-mode)
                                                     "-map")))
                               ((boundp name)))
                     (symbol-value name)))))
        (when (keymapp map)
          (set-keymap-parent
           map
           (make-composed-keymap (keymap-parent map)
                                 helixel-normal-map)))))))

(add-hook 'helixel-motion-state-hook
          #'helixel--motion-patch-keymap-parent)

;; ── Mode activation ──

(defun helixel--is-self-insert-p (cmd)
  "Return non-nil if CMD is a self-insert command."
  (and (symbolp cmd)
       (string-match-p "\\`.*self-insert.*\\'"
                       (symbol-name cmd))))

(defun helixel--default-state-for-buffer ()
  "Return the default Helixel state for the current buffer.
Look up the current major mode in `helixel-major-mode-default-states'.
If no entry matches, guess based on key bindings: if letters a-z
are bound to self-insert commands, use `normal', otherwise `motion'."
  (or (cl-some (lambda (cell)
                 (when (derived-mode-p (car cell))
                   (cdr cell)))
               helixel-major-mode-default-states)
      (let* ((state-modes (mapcar #'cdr helixel-state-alist))
             (minor-mode-map-alist
              (cl-remove-if (lambda (x) (memq (car x) state-modes))
                            minor-mode-map-alist))
             (minor-mode-overriding-map-alist
              (cl-remove-if (lambda (x) (memq (car x) state-modes))
                            minor-mode-overriding-map-alist))
             (letters (split-string "abcdefghijklmnopqrstuvwxyz" "" t))
             (any-self-insert (cl-some (lambda (letter)
                                         (helixel--is-self-insert-p
                                          (key-binding letter)))
                                       letters)))
        (if any-self-insert 'normal 'motion))))

(defun helixel-mode-maybe-activate (&optional status)
  "Activate or deactivate Helixel state if `helixel-global-mode' is non-nil.

A positive STATUS activates the default state for the current buffer.
A non-positive STATUS deactivates the current state.
The default state is determined by `helixel--default-state-for-buffer'."
  (when (and (not (minibufferp)) helixel-global-mode)
    (if (and status (<= status 0))
        ;; Deactivate current state
        (let ((mode (alist-get helixel--current-state
                               helixel-state-alist)))
          (funcall mode -1))
      ;; Activate default state
      (let* ((state (helixel--default-state-for-buffer))
             (mode (alist-get state helixel-state-alist)))
        (funcall mode (if status status 1))
        (helixel--refresh-overriding-maps)))))

;;;###autoload
(defun helixel-mode-all (&optional status)
  "Activate Helixel mode in all buffers with their default states.

Argument STATUS is passed through to `helixel-mode-maybe-activate'."
  (interactive)
  (helixel-action-start 'state 'toggle)
  ;; Set global mode to t before iterating over the buffers so that we
  ;; send the status directly to `helixel-normal-state' (which checks for
  ;; a non-nil value of `helixel-global-mode'.
  (setq helixel-global-mode t)
  (mapc (lambda (buf)
          (with-current-buffer buf
            (helixel-mode-maybe-activate status)))
        (buffer-list))
  (setq helixel-global-mode (if status status 1)))

;;;###autoload
(defun helixel-mode ()
  "Toggle global Helixel mode."
  (interactive)
  (helixel-action-start 'state 'toggle)
  (setq helixel-global-mode (not helixel-global-mode))
  (if helixel-global-mode
      (progn
        ;; Ensure \\[keyboard-quit] clears state and breaks session continuity.
        (advice-add #'keyboard-quit :before #'helixel--clear-data)
        (advice-add #'keyboard-quit :before #'helixel--cancel-action)
        (add-hook 'after-change-major-mode-hook #'helixel-mode-maybe-activate)
        (helixel-mode-maybe-activate 1))
    (cond
     (helixel-normal-state (helixel-normal-state -1))
     (helixel-insert-state (helixel-insert-state -1))
     (helixel-motion-state (helixel-motion-state -1))
     (helixel-visual-state (helixel-visual-state -1)))
    (advice-remove #'keyboard-quit #'helixel--clear-data)
    (advice-remove #'keyboard-quit #'helixel--cancel-action)
    (remove-hook 'after-change-major-mode-hook #'helixel-mode-maybe-activate)
    (remove-hook 'helixel-action-push-functions #'helixel--jump-list-push)))

;; Register xref/eglot jump commands so they push to the jump list.
(helixel-define-jump-command 'xref-find-definitions)
(helixel-define-jump-command 'xref-find-references)
(helixel-define-jump-command 'eglot-find-typeDefinition)
(helixel-define-jump-command 'eglot-find-implementation)


;; ── Selection type validator ──
;; (moved from helixel-common.el to avoid circular dep with helixel-swap)

(defun helixel--selection-type ()
  "Return current selection type, or nil.
Validates that the region actually matches the claimed type.
Supports `line' and `rect'."
  (when (region-active-p)
    (cond
     ((eq helixel--selection-type 'rect)
      (when rectangle-mark-mode 'rect))
     ((eq helixel--selection-type 'line)
      (let ((beg (region-beginning))
            (end (region-end)))
        (when (and (save-excursion (goto-char beg) (bolp))
                   (save-excursion (goto-char end) (or (eolp) (eobp))))
          'line)))
     ((eq helixel--selection-type 'textobj)
      'textobj))))

(provide 'helixel-state)
;;; helixel-state.el ends here
