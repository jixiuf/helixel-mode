;;; helixel-keymap.el --- Keymap definitions  -*- lexical-binding: t; -*-

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

;; Keymap definitions and the `helixel-state-map-alist' for helixel-mode.
;;
;; Each state (normal, insert, visual, motion) and each prefix (goto,
;; view, space, window, textobj) is populated here via `define-key' on
;; the empty keymap shells created by `helixel-state'.  Using
;; `define-key' (not `setq') ensures the same keymap object is modified
;; in-place — `:keymap' references in `define-minor-mode' stay valid.
;;
;; The `helixel-state-map-alist' is populated below.
;; Also provides the colon-command system.

;;; Code:

(declare-function flymake-show-buffer-diagnostics "flymake")
(declare-function flymake-goto-next-error "flymake")
(declare-function flymake-goto-prev-error "flymake")
(declare-function eglot-find-typeDefinition "eglot")
(declare-function eglot-find-implementation "eglot")
(declare-function eglot-code-action-quickfix "eglot")
(declare-function eglot-rename "eglot")
(require 'helixel-state)
(require 'helixel-move)
(require 'helixel-editing)
(require 'helixel-chain)
(require 'helixel-surround)
(require 'helixel-swap)
(require 'helixel-search)

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


;; ── Prefix keymaps ──

(define-key helixel-goto-map "l" #'helixel-go-end-line)
(define-key helixel-goto-map "h" #'helixel-go-beginning-line)
(define-key helixel-goto-map "s" #'helixel-go-first-nonwhitespace)
(define-key helixel-goto-map "g" #'helixel-go-beginning-buffer)
(define-key helixel-goto-map "e" #'helixel-go-end-buffer)
(define-key helixel-goto-map "j" #'helixel-next-line)
(define-key helixel-goto-map "k" #'helixel-previous-line)
(define-key helixel-goto-map "r" #'xref-find-references)
(define-key helixel-goto-map "d" #'xref-find-definitions)
(define-key helixel-goto-map "y" #'eglot-find-typeDefinition)
(define-key helixel-goto-map "i" #'eglot-find-implementation)
(define-key helixel-goto-map "u" #'helixel-downcase)
(define-key helixel-goto-map "U" #'helixel-upcase)
(define-key helixel-goto-map "c" #'helixel-comment-toggle)
(define-key helixel-goto-map "q" #'helixel-fill)
(define-key helixel-goto-map "." #'helixel-repeat-edit-pick)

(define-key helixel-view-map "z" #'recenter-top-bottom)

(define-key helixel-space-map "f" #'project-find-file)
(define-key helixel-space-map "b" #'project-switch-to-buffer)
(define-key helixel-space-map "j" #'project-switch-project)
(define-key helixel-space-map "/" #'project-find-regexp)
(define-key helixel-space-map "a" #'eglot-code-action-quickfix)
(define-key helixel-space-map "r" #'eglot-rename)
(define-key helixel-space-map "d" #'flymake-show-buffer-diagnostics)

(define-key helixel-window-map "h" #'windmove-left)
(define-key helixel-window-map "l" #'windmove-right)
(define-key helixel-window-map "j" #'windmove-down)
(define-key helixel-window-map "k" #'windmove-up)
(define-key helixel-window-map "w" #'other-window)
(define-key helixel-window-map "v" #'split-window-right)
(define-key helixel-window-map "s" #'split-window-below)
(define-key helixel-window-map "q" #'delete-window)
(define-key helixel-window-map "o" #'delete-other-windows)

;; ── Textobj keymap ──

;; Populate outer-map (shell created in helixel-state.el)
(define-key helixel-textobj-outer-map "w"  #'helixel-mark-a-word)
(define-key helixel-textobj-outer-map "W"  #'helixel-mark-a-WORD)
(define-key helixel-textobj-outer-map "o"  #'helixel-mark-a-symbol)
(define-key helixel-textobj-outer-map "s"  #'helixel-mark-a-sentence)
(define-key helixel-textobj-outer-map "p"  #'helixel-mark-a-paragraph)
(define-key helixel-textobj-outer-map "("  #'helixel-mark-a-paren)
(define-key helixel-textobj-outer-map ")"  #'helixel-mark-a-paren)
(define-key helixel-textobj-outer-map "b"  #'helixel-mark-a-paren)
(define-key helixel-textobj-outer-map "["  #'helixel-mark-a-bracket)
(define-key helixel-textobj-outer-map "]"  #'helixel-mark-a-bracket)
(define-key helixel-textobj-outer-map "B"  #'helixel-mark-a-brace)
(define-key helixel-textobj-outer-map "{"  #'helixel-mark-a-brace)
(define-key helixel-textobj-outer-map "}"  #'helixel-mark-a-brace)
(define-key helixel-textobj-outer-map "<"  #'helixel-mark-a-angle)
(define-key helixel-textobj-outer-map ">"  #'helixel-mark-a-angle)
(define-key helixel-textobj-outer-map "t"  #'helixel-mark-a-tag)
(define-key helixel-textobj-outer-map "c"  #'helixel-mark-a-block)
(define-key helixel-textobj-outer-map "\`" #'helixel-mark-a-back-quote)
(define-key helixel-textobj-outer-map "'"  #'helixel-mark-a-single-quote)
(define-key helixel-textobj-outer-map "\"" #'helixel-mark-a-double-quote)

;; Populate inner-map (shell created in helixel-state.el)
(define-key helixel-textobj-inner-map "w"  #'helixel-mark-inner-word)
(define-key helixel-textobj-inner-map "W"  #'helixel-mark-inner-WORD)
(define-key helixel-textobj-inner-map "o"  #'helixel-mark-inner-symbol)
(define-key helixel-textobj-inner-map "s"  #'helixel-mark-inner-sentence)
(define-key helixel-textobj-inner-map "p"  #'helixel-mark-inner-paragraph)
(define-key helixel-textobj-inner-map "("  #'helixel-mark-inner-paren)
(define-key helixel-textobj-inner-map ")"  #'helixel-mark-inner-paren)
(define-key helixel-textobj-inner-map "b"  #'helixel-mark-inner-paren)
(define-key helixel-textobj-inner-map "["  #'helixel-mark-inner-bracket)
(define-key helixel-textobj-inner-map "]"  #'helixel-mark-inner-bracket)
(define-key helixel-textobj-inner-map "B"  #'helixel-mark-inner-brace)
(define-key helixel-textobj-inner-map "{"  #'helixel-mark-inner-brace)
(define-key helixel-textobj-inner-map "}"  #'helixel-mark-inner-brace)
(define-key helixel-textobj-inner-map "<"  #'helixel-mark-inner-angle)
(define-key helixel-textobj-inner-map ">"  #'helixel-mark-inner-angle)
(define-key helixel-textobj-inner-map "t"  #'helixel-mark-inner-tag)
(define-key helixel-textobj-inner-map "c"  #'helixel-mark-inner-block)
(define-key helixel-textobj-inner-map "\`" #'helixel-mark-inner-back-quote)
(define-key helixel-textobj-inner-map "'"  #'helixel-mark-inner-single-quote)
(define-key helixel-textobj-inner-map "\"" #'helixel-mark-inner-double-quote)

(set-keymap-parent helixel-textobj-map helixel-textobj-inner-map)
(define-key helixel-textobj-map "i" helixel-textobj-inner-map)
(define-key helixel-textobj-map "a" helixel-textobj-outer-map)
(define-key helixel-textobj-map "s" #'helixel-surround-add)
(define-key helixel-textobj-map "t" #'helixel-surround-add-tag)
(define-key helixel-textobj-map "d" #'helixel-surround-delete)
(define-key helixel-textobj-map "r" #'helixel-surround-replace)
;; ── State keymaps ──

;; helixel-normal-map
(define-key helixel-normal-map "q" #'helixel-repeat-chain-start)
(define-key helixel-normal-map "Q" #'helixel-repeat-chain-end)
(define-key helixel-normal-map "." #'helixel-repeat-edit)
(define-key helixel-normal-map "," #'helixel-repeat-selection)

(define-key helixel-normal-map "c" #'helixel-change-thing-at-point)
(define-key helixel-normal-map "d" #'helixel-kill-thing-at-point)
(define-key helixel-normal-map "y" #'helixel-kill-ring-save)
(define-key helixel-normal-map "S" #'helixel-swap)
(define-key helixel-normal-map "r" #'helixel-replace)
(define-key helixel-normal-map "R" #'helixel-replace-char)
(define-key helixel-normal-map "\M-r" #'helixel-replace-pop)
(define-key helixel-normal-map "p" #'helixel-yank)
(define-key helixel-normal-map "P" #'helixel-yank-before)
(define-key helixel-normal-map "\"" #'helixel-select-register)
(define-key helixel-normal-map "x" #'helixel-select-line)
(define-key helixel-normal-map "v" #'helixel-backward-word-end)
(define-key helixel-normal-map "\C-v" #'helixel-select-rectangle)
(define-key helixel-normal-map "u" #'undo)
(define-key helixel-normal-map "U" #'undo-redo)
(define-key helixel-normal-map "o" #'helixel-insert-newline)
(define-key helixel-normal-map "O" #'helixel-insert-prevline)
(define-key helixel-normal-map "<" #'helixel-indent-left)
(define-key helixel-normal-map ">" #'helixel-indent-right)
(define-key helixel-normal-map "~" #'helixel-toggle-case)
(define-key helixel-normal-map "!" #'helixel-shell-command)
(define-key helixel-normal-map "i" #'helixel-insert)
(define-key helixel-normal-map "I" #'helixel-insert-beginning-line)
(define-key helixel-normal-map "a" #'helixel-insert-after)
(define-key helixel-normal-map "A" #'helixel-insert-after-end-line)
(define-key helixel-normal-map ":" #'helixel-execute-command)
(define-key helixel-normal-map [escape] #'keyboard-quit)
(define-key helixel-normal-map [delete] #'ignore)
(define-key helixel-normal-map "h" #'helixel-backward-char)
(define-key helixel-normal-map "l" #'helixel-forward-char)
(define-key helixel-normal-map "j" #'helixel-next-line)
(define-key helixel-normal-map "J" #'helixel-join-lines)
(define-key helixel-normal-map "k" #'helixel-previous-line)
(define-key helixel-normal-map "G" #'helixel-goto-line)
(define-key helixel-normal-map "%" #'mark-whole-buffer)
(define-key helixel-normal-map ";" #'helixel-action-cycle)
(define-key helixel-normal-map "\C-o" #'helixel-jump-backward)
(define-key helixel-normal-map "\C-i" #'helixel-jump-forward)
(define-key helixel-normal-map "\C-f" #'helixel-scroll-up-command)
(define-key helixel-normal-map "\C-b" #'helixel-scroll-down-command)
;; Digit arguments via C-u prefix
(define-key helixel-normal-map "1" "\C-u1")
(define-key helixel-normal-map "2" "\C-u2")
(define-key helixel-normal-map "3" "\C-u3")
(define-key helixel-normal-map "4" "\C-u4")
(define-key helixel-normal-map "5" "\C-u5")
(define-key helixel-normal-map "6" "\C-u6")
(define-key helixel-normal-map "7" "\C-u7")
(define-key helixel-normal-map "8" "\C-u8")
(define-key helixel-normal-map "9" "\C-u9")
(define-key helixel-normal-map "0" "\C-u0")
(define-key helixel-normal-map "-" 'negative-argument)
(define-key helixel-normal-map "=" #'indent-for-tab-command)
;; Word movement
(define-key helixel-normal-map "w" #'helixel-forward-word-start)
(define-key helixel-normal-map "W" #'helixel-forward-WORD-start)
(define-key helixel-normal-map "e" #'helixel-forward-word-end)
(define-key helixel-normal-map "E" #'helixel-forward-WORD-end)
(define-key helixel-normal-map "b" #'helixel-backward-word-start)
(define-key helixel-normal-map "B" #'helixel-backward-WORD)
;; Unimpaired
(define-key helixel-normal-map "] d" #'flymake-goto-next-error)
(define-key helixel-normal-map "[ d" #'flymake-goto-prev-error)
;; Prefix maps
(define-key helixel-normal-map "m" helixel-textobj-map)

(define-key helixel-normal-map "g" helixel-goto-map)
;; Chain recording for compound dot-repeat
(define-key helixel-normal-map "z" helixel-view-map)
(define-key helixel-normal-map " " helixel-space-map)
(define-key helixel-normal-map "\C-w" helixel-window-map)

;; helixel-visual-map (inherits normal-map)
(set-keymap-parent helixel-visual-map helixel-normal-map)
(define-key helixel-visual-map "v" #'helixel-visual-exit)
(define-key helixel-visual-map [escape] #'helixel-visual-exit)

;; helixel-motion-map stays empty (full t, user adds bindings)

;; helixel-insert-map
(define-key helixel-insert-map [escape] #'helixel-insert-exit)

;; ── State → keymap alist ──

(setq helixel-state-map-alist
      `((insert . ,helixel-insert-map)
        (normal . ,helixel-normal-map)
        (visual . ,helixel-visual-map)
        (motion . ,helixel-motion-map)
        (textobj . ,helixel-textobj-map)
        (textobj-inner . ,helixel-textobj-inner-map)
        (textobj-outer . ,helixel-textobj-outer-map)
        (view . ,helixel-view-map)
        (goto . ,helixel-goto-map)
        (window . ,helixel-window-map)
        (space . ,helixel-space-map)))

;; ── Colon commands ──

(defun helixel-quit (&optional force)
  "Kill Emacs if only one window, otherwise quit current window.

If FORCE is non-nil, don't prompt for save when killing Emacs."
  (if (one-window-p)
      (if force
          (kill-emacs)
        (call-interactively #'save-buffers-kill-terminal))
    (delete-window)))

(defun helixel-revert-all-buffers-quick ()
  "Execute `revert-buffer-quick' on all file-associated buffers."
  (let ((target-buffers (cl-remove-if-not
                         (lambda (buf)
                           (and
                            (buffer-file-name buf)
                            (file-readable-p (buffer-file-name buf))))
                         (buffer-list))))
    (mapc (lambda (buf)
            (with-current-buffer buf
              (revert-buffer-quick)))
          target-buffers)
    (message "Reverted %s buffers" (length target-buffers))))

(defvar helixel--command-alist
  `((("w" "write") ,#'save-buffer)
    (("q" "quit") ,#'helixel-quit)
    (("q!" "quit!") ,(lambda () (helixel-quit t)))
    (("wq" "write-quit") ,#'save-buffer ,#'helixel-quit)
    (("o" "open" "e" "edit") ,#'find-file)
    (("n" "new") ,#'scratch-buffer)
    (("rl" "reload") ,#'revert-buffer-quick)
    (("reload-all") ,#'helixel-revert-all-buffers-quick)
    (("pwd" "show-directory") ,#'pwd)
    (("vs" "vsplit") ,#'split-window-right)
    (("hs" "hsplit") ,#'split-window-below)
    (("config-open") ,(lambda () (find-file user-init-file))))
  "Alist of commands executed by `helixel-execute-command'.")

(defun helixel-define-ex-command (command callback)
  "Add COMMAND to `helixel--command-alist' that can be invoked via ':<command>'.

Argument CALLBACK is a function, command symbol, or list thereof.
Each element of CALLBACK is executed in order:
- If `commandp' is non-nil, it is called via `call-interactively'.
- Otherwise, it is called via `funcall'.

Example that defines the typable command ':build':
\(helixel-define-ex-command \"build\" #\\='compile)

Example with multiple callbacks:
\(helixel-define-ex-command \"build\" \\='(save-buffer compile))"
  (add-to-list 'helixel--command-alist
               (cons (if (listp command) command (list command))
                     (if (and (listp callback) (not (functionp callback)))
                         callback
                       (list callback)))))

(defun helixel-execute-command (input)
  "Look for INPUT in `helixel--command-alist' and execute it, if present."
  (interactive "s:")
  (let ((command (string-trim input)))
    (if-let* ((callbacks
               (catch 'found
                 (dolist (entry helixel--command-alist)
                   (let ((names (car entry)))
                     (when (member command names)
                       (throw 'found (cdr entry))))))))
        (dolist (cb callbacks)
          (if (and (symbolp cb) (commandp cb))
              (progn
                (call-interactively cb)
                (setq this-command cb))
            (when (symbolp cb)
              (setq this-command cb))
            (funcall cb)))
      (message "no such command '%s'" command))))

;; ── Search & find-char keybindings ──


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

;; ── Hook registrations ──

(add-hook 'helixel-state-change-hook #'helixel--refresh-overriding-maps)
(add-hook 'helixel-state-change-hook #'helixel--refresh-textobj-overrides)

(provide 'helixel-keymap)
;;; helixel-keymap.el ends here
