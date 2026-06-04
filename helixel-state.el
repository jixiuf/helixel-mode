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
;; mode activation, keymap management, and helixel-mode toggle entry points.
;;
;; Keymaps are NOT defined here — see `helixel-keymap' for keymap
;; definitions that populate `helixel-state-map-alist'.
;; Editing commands live in `helixel-editing', macros in `helixel-macros'.

;;; Code:

(require 'cl-lib)
(require 'helixel-core)
(require 'helixel-ring)
(require 'helixel-macros)
(require 'helixel-register)
(require 'helixel-action)
(require 'helixel-repeat)
(require 'helixel-textobj)
(require 'helixel-surround)

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
  '(special-mode Custom-mode wdired-mode occur-edit-mode grep-edit-mode)
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

(defvar helixel-mode-on-hook nil
  "Hook run after helixel-mode activates in a buffer.")

(defvar helixel-mode-off-hook nil
  "Hook run after helixel-mode deactivates in a buffer.")

(defvar helixel-state-change-hook nil
  "Hook run after the modal state changes.
The new state is available in `helixel--current-state'.")

(defvar-local helixel--rect-replay-info nil
  "Plist for rect change replay: (:col N :line-count N :marker M).
Set by `helixel--rect-change', consumed by `helixel-insert-exit'
via `helixel--rect-replay-get' and `helixel--rect-replay-clear'.")

(defun helixel--rect-replay-get ()
  "Return the rect-replay info plist, or nil."
  helixel--rect-replay-info)

(defun helixel--rect-replay-clear ()
  "Clear rect-replay info, releasing the marker."
  (when-let* ((m (plist-get helixel--rect-replay-info :marker)))
    (set-marker m nil))
  (setq helixel--rect-replay-info nil))

(defvar helixel-global-mode nil
  "Enable Helixel mode in all buffers.")

;; ── Keymap shells ──
;;
;; Convention:
;;   * State maps    (normal / motion / visual / insert) use
;;     `define-keymap' — they are full keymaps with many bindings.
;;     `:suppress' is set on modal states that should ignore
;;     self-insert (normal, motion, visual); insert state stays
;;     unsuppressed so typing keys still self-inserts.
;;   * Prefix maps   (view / goto / window / space / textobj /
;;     textobj-inner / textobj-outer) use `make-sparse-keymap' +
;;     `suppress-keymap' — they hold a small number of bindings
;;     and are entered through a prefix key.
;;
;; Shells are created here so `:keymap' in `define-minor-mode'
;; captures a real keymap object.  `helixel-keymap' fills them with
;; `define-key' (same object — reference never breaks).

;; State maps
(defvar helixel-normal-map (define-keymap :suppress t))
(defvar helixel-motion-map (define-keymap :suppress t))
(defvar helixel-visual-map (define-keymap :suppress t))
(defvar helixel-insert-map (define-keymap))

;; Prefix maps
(defvar helixel-view-map (make-sparse-keymap))
(suppress-keymap helixel-view-map)

(defvar helixel-goto-map (make-sparse-keymap))
(suppress-keymap helixel-goto-map)
(set-keymap-parent helixel-goto-map goto-map)

(defvar helixel-window-map (make-sparse-keymap))
(suppress-keymap helixel-window-map)

(defvar helixel-space-map (make-sparse-keymap))
(suppress-keymap helixel-space-map)

(defvar helixel-textobj-map (make-sparse-keymap))
(suppress-keymap helixel-textobj-map)

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

;; ── Pending-op system (selection-first pattern) ──
;;
;; Helixel is selection-first: user selects a region (w/b/e/iw/aw/line/
;; rect/search/find-char), THEN presses an operator (d/c/y).
;;
;; `helixel--pending-sel' holds the selection descriptor (helixel-sel
;; struct) created by the selection command.  The operator command
;; consumes it.
;;
;; `helixel--pending-op' is NOT a vim-style operator-pending state
;; machine — it's just a marker that the next command should consume
;; the pending selection.

(defvar-local helixel--pending-op nil
  "The current pending operator: \='kill | \='change | \='copy | nil.
Set by operator commands (d, c, y) when awaiting a selection.
Consumed alongside `helixel--pending-sel'.")

(defun helixel--commit-pending-event ()
  "Finalize the pending event after operator+selection are both ready.
Creates the helixel-sel from pending-sel, sets it on the current live-event,
and commits the event.  This is called from `post-command-hook'."
  (when (and helixel--pending-op helixel--pending-sel)
    (let ((sel helixel--pending-sel))
      (setq helixel--pending-op nil
            helixel--pending-sel nil)
      (when helixel--live-edit
        (setf (helixel-edit-sel helixel--live-edit) sel)
        (helixel-edit-commit)))))

;; Wire textobj hooks for action recording and visual state detection.
(setq helixel-textobj-action-function #'helixel--tracking-open)
(setq helixel-textobj-visual-state-p-function
      #'helixel--pure-visual-state-p)
(setq helixel-jump-cleanup-function #'helixel--clear-data)

(defun helixel--switch-state (state)
  "Switch to STATE."
  (unless (eq state helixel--current-state)
    (when-let* ((mode (alist-get helixel--current-state helixel-state-alist)))
      (funcall mode -1))
    (helixel--clear-data)
    (setq-local helixel--current-state state)
    (let ((mode (alist-get state helixel-state-alist)))
      (funcall mode 1))
    (run-hooks 'helixel-state-change-hook)))

(defun helixel--clear-highlights ()
  "Clear any active highlight, unless in visual state.
Also preserve highlights when `rectangle-mark-mode' is active."
  (unless (or (helixel--pure-visual-state-p) rectangle-mark-mode)
    (deactivate-mark)))

(declare-function rectangle-exchange-point-and-mark "rect")

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
    (setq helixel--raw-selection-type nil)
    (push-mark-command t t)))

(defun helixel-visual-exchange-point-and-mark ()
  "Exchange point and mark, preserving selection-type semantics.

- For rect selections (`rectangle-mark-mode' active), delegates to
  `rectangle-exchange-point-and-mark' which preserves the rectangle
  corner positions correctly.
- For line selections, exchanges point/mark AND flips `:dir' in
  the pending selection context.
- For char visual selections, delegates to plain
  `exchange-point-and-mark'."
  (interactive)
  (cond
   (rectangle-mark-mode
    (rectangle-exchange-point-and-mark))
   ((and (eq helixel--raw-selection-type 'line)
         helixel--pending-sel
         (eq (helixel-sel-kind helixel--pending-sel) 'line))
    (exchange-point-and-mark)
    (when-let* ((fn (helixel--kind-flip-dir-fn 'line)))
      (helixel--sel-push (funcall fn helixel--pending-sel))))
   (t
    (exchange-point-and-mark))))

;; ── Minor modes ──

(define-minor-mode helixel-insert-state
  "Helixel INSERT state minor mode."
  :lighter " helixel[I]"
  :init-value nil
  :interactive nil
  :global nil
  :keymap helixel-insert-map
  (if helixel-insert-state
      (setq cursor-type 'bar)
    (setq cursor-type 'box)))

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
      (setq cursor-type 'box)))

(define-minor-mode helixel-visual-state
  "Helixel VISUAL state minor mode."
  :lighter " helixel[V]"
  :init-value nil
  :interactive nil
  :global nil
  :keymap helixel-visual-map
  (if helixel-visual-state
      (setq cursor-type 'box)))

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
      (setq cursor-type 'box)))

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
;; ── Enter insert (state transition helper) ──
(defun helixel--enter-insert ()
  "Enter insert mode, recording buffer changes via the change hooks.
Sets up change-hook recording and switches to insert state."
  (helixel--insert-begin)
  (helixel--switch-state 'insert))

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

(defun helixel--pure-visual-state-p ()
  "Return non-nil if in pure visual state (not entered via line/rect).
Line and rect selections are in `visual' state but should NOT behave
like pure visual for highlight clearing, textobj expansion, or
search mark handling."
  (and (eq helixel--current-state 'visual)
       (not (memq (helixel--selection-type) '(line rect)))))

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
        (when-let* ((lookup (assq helixel--current-state
                                 helixel-state-alist)))
          (funcall (cdr lookup) -1))
      (let ((state (helixel--default-state-for-buffer)))
        (setq-local helixel--current-state state)
        (funcall (alist-get state helixel-state-alist)
                 (if status status 1))
        (run-hooks 'helixel-state-change-hook)))))

;;;###autoload
(defun helixel-mode-all (&optional status)
  "Activate Helixel mode in all buffers with their default states.

Argument STATUS is passed through to `helixel-mode-maybe-activate'."
  (interactive)
  (helixel--tracking-open 'state 'toggle)
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
  (helixel--tracking-open 'state 'toggle)
  (setq helixel-global-mode (not helixel-global-mode))
  (if helixel-global-mode
      (progn
        ;; Ensure \\[keyboard-quit] clears state and breaks session continuity.
        (advice-add #'keyboard-quit :before #'helixel--clear-data)
        (advice-add #'keyboard-quit :before #'helixel--cancel-action)
        (add-hook 'after-change-major-mode-hook #'helixel-mode-maybe-activate)
        (run-hooks 'helixel-mode-on-hook)
        (helixel-mode-maybe-activate 1))
    (cond
     (helixel-normal-state (helixel-normal-state -1))
     (helixel-insert-state (helixel-insert-state -1))
     (helixel-motion-state (helixel-motion-state -1))
     (helixel-visual-state (helixel-visual-state -1)))
    (advice-remove #'keyboard-quit #'helixel--clear-data)
    (advice-remove #'keyboard-quit #'helixel--cancel-action)
    (remove-hook 'after-change-major-mode-hook #'helixel-mode-maybe-activate)
    (run-hooks 'helixel-mode-off-hook)))
    ;; helixel-action-push-functions removed — event-ring handles this now

;; Register xref/eglot jump commands so they push to the jump list.
(dolist (cmd '(xref-find-definitions
               xref-find-references
               eglot-find-typeDefinition
               eglot-find-implementation))
  (helixel-define-jump-command cmd))


(provide 'helixel-state)
;;; helixel-state.el ends here
