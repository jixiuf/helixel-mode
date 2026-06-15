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
(declare-function helixel-collapse-selection "helixel-mc-core")
(require 'helixel-state)
(require 'helixel-move)
(require 'helixel-editing)
(require 'helixel-chain)
(require 'helixel-surround)
(require 'helixel-swap)
(require 'helixel-search)
(require 'helixel-mc-core)
(require 'helixel-mc-spawn)
(require 'helixel-mc-integrate)

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
(define-key helixel-goto-map "|" #'move-to-column)
(define-key helixel-goto-map ":" #'goto-char)
(define-key helixel-goto-map ";" #'goto-line)

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

(defconst helixel--textobj-delims
  ;; (KEYS . TYPE) used to populate inner and outer textobj maps.
  ;; helixel-mark-{inner|a}-TYPE is the target function.
  '(("w"     . "word")
    ("W"     . "WORD")
    ("o"     . "symbol")
    ("s"     . "sentence")
    ("p"     . "paragraph")
    ("()b"   . "paren")
    ("[]"    . "bracket")
    ("B{}"   . "brace")
    ("<>"    . "angle")
    ("t"     . "tag")
    ("f"     . "function")
    ("c"     . "block")
    ("`"     . "back-quote")
    ("'"     . "single-quote")
    ("\""   . "double-quote"))
  "Table mapping textobj KEYS to TYPE name suffix.
Shared by `helixel-textobj-inner-map' and `-outer-map'.")

(defun helixel--textobj-populate (map fn-template)
  "Populate MAP from `helixel--textobj-delims'.
FN-TEMPLATE is a format string with one %s for the type suffix,
e.g. \"helixel-mark-a-%s\"."
  (dolist (cell helixel--textobj-delims)
    (let ((fn (intern (format fn-template (cdr cell)))))
      (dolist (ch (string-to-list (car cell)))
        (define-key map (char-to-string ch) fn)))))

;; Populate outer-map (shell created in helixel-state.el)
(helixel--textobj-populate helixel-textobj-outer-map "helixel-mark-a-%s")
;; Populate inner-map (shell created in helixel-state.el)
(helixel--textobj-populate helixel-textobj-inner-map
                           "helixel-mark-inner-%s")

(set-keymap-parent helixel-textobj-map helixel-textobj-inner-map)
(define-key helixel-textobj-map "i" helixel-textobj-inner-map)
(define-key helixel-textobj-map "a" helixel-textobj-outer-map)
(define-key helixel-textobj-map "h" #'mark-whole-buffer)
(define-key helixel-textobj-map "s" #'helixel-surround-add)
(define-key helixel-textobj-map "t" #'helixel-surround-add-tag)
(define-key helixel-textobj-map "d" #'helixel-surround-delete)
(define-key helixel-textobj-map "r" #'helixel-surround-replace)

;; ── [ ] { } prefix keymaps ──
;; [ key → outer (a) textobj, outward to opening
;; ] key → outer (a) textobj, forward to closing end
;; { key → inner (i) textobj, outward to opening
;; } key → inner (i) textobj, forward to closing end

(defconst helixel--bracket-prefix-delims
  ;; (KEYS . TYPE-INFIX)
  ;; TYPE-INFIX is the substring inserted into helixel-{prefix}-{TYPE}
  ;; -end (for ] / }) or helixel-{prefix}-{TYPE} (for [ / {).
  '(("()b"   . "paren")
    ("[]"    . "bracket")
    ("B{}"   . "brace")
    ("<>"    . "angle")
    ("\""   . "double-quote")
    ("'"     . "single-quote")
    ("`"     . "back-quote")
    ("t"     . "tag")
    ("c"     . "block"))
  "Table mapping bracket-prefix KEYS to textobj TYPE-INFIX.
Used to populate `helixel-right-map' / `-left-map' /
`-inner-right-map' / `-inner-left-map'.")

(defun helixel--bracket-prefix-populate (map fn-template)
  "Populate MAP from `helixel--bracket-prefix-delims'.
FN-TEMPLATE is a format string that takes one %s for the type-infix,
e.g. \"helixel-next-%s-end\"."
  (dolist (cell helixel--bracket-prefix-delims)
    (let ((fn (intern (format fn-template (cdr cell)))))
      (dolist (ch (string-to-list (car cell)))
        (define-key map (char-to-string ch) fn)))))

(defvar-keymap helixel-right-map
  :doc "Keymap for `]' prefix."
  "d" #'flymake-goto-next-error
  "p" #'helixel-forward-paragraph-end
  "s" #'helixel-forward-sentence-end
  "f" #'helixel-forward-function-end)
(helixel--bracket-prefix-populate helixel-right-map
                                  "helixel-next-%s-end")

(defvar-keymap helixel-left-map
  :doc "Keymap for `[' prefix."
  "d" #'flymake-goto-prev-error
  "p" #'helixel-backward-paragraph-start
  "s" #'helixel-backward-sentence-start
  "f" #'helixel-backward-function-start)
(helixel--bracket-prefix-populate helixel-left-map
                                  "helixel-outer-%s")

(defvar-keymap helixel-inner-right-map
  :doc "Keymap for `}' prefix.")
(helixel--bracket-prefix-populate helixel-inner-right-map
                                  "helixel-inner-next-%s-end")

(defvar-keymap helixel-inner-left-map
  :doc "Keymap for `{' prefix.")
(helixel--bracket-prefix-populate helixel-inner-left-map
                                  "helixel-inner-outer-%s")

;; ── State keymaps ──

;; helixel-normal-map
(define-key helixel-normal-map "@" #'helixel-repeat-chain-start)
(define-key helixel-normal-map "." #'helixel-repeat-edit)
(define-key helixel-normal-map "," #'helixel-repeat-last-motion)

(define-key helixel-normal-map "c" #'helixel-change)
(define-key helixel-normal-map "C" #'helixel-change-noyank)
(define-key helixel-normal-map "d" #'helixel-kill)
(define-key helixel-normal-map "D" #'helixel-delete)
(define-key helixel-normal-map "y" #'helixel-kill-ring-save)
(define-key helixel-normal-map "S" #'helixel-swap)
(define-key helixel-normal-map "r" #'helixel-replace)
(define-key helixel-normal-map "R" #'helixel-replace-char)
(define-key helixel-normal-map [remap yank-pop] #'helixel-yank-pop)
(define-key helixel-normal-map "p" #'helixel-yank)
(define-key helixel-normal-map "P" #'helixel-yank-before)
(define-key helixel-normal-map "\"" #'helixel-select-register)
(define-key helixel-normal-map "x" #'helixel-select-line)
(define-key helixel-normal-map "X" #'helixel-select-line-up)
(define-key helixel-normal-map "v" #'helixel-begin-selection)
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
(define-key helixel-normal-map [escape] #'helixel-normal-escape)
(define-key helixel-normal-map [delete] #'ignore)
(define-key helixel-normal-map [backspace] #'helixel-delete-backward-char)
(define-key helixel-normal-map [C-backspace] #'helixel-delete-backward-word)
(define-key helixel-normal-map [M-backspace] #'helixel-delete-backward-word)
(define-key helixel-normal-map "h" #'helixel-backward-char)
(define-key helixel-normal-map "l" #'helixel-forward-char)
(define-key helixel-normal-map "j" #'helixel-next-line)
(define-key helixel-normal-map "J" #'helixel-join-lines)
(define-key helixel-normal-map "k" #'helixel-previous-line)
(define-key helixel-normal-map "G" #'helixel-goto-line)
(define-key helixel-normal-map "%" #'helixel-jump-to-match)
(define-key helixel-normal-map ";" #'helixel-action-cycle)
(define-key helixel-normal-map (kbd "C-;") #'helixel-action-cycle-jump)
(define-key helixel-normal-map "\C-o" #'helixel-jump-backward)
(define-key helixel-normal-map "\C-i" #'helixel-jump-forward)
(define-key helixel-normal-map "\C-f" #'helixel-scroll-up-command)
(define-key helixel-normal-map "\C-b" #'helixel-scroll-down-command)
;; Digit arguments via C-u prefix
(dotimes (i 10)
  (define-key helixel-normal-map (number-to-string i)
              (format "\C-u%d" i)))
(define-key helixel-normal-map "-" 'negative-argument)
(define-key helixel-normal-map "=" #'indent-for-tab-command)
;; Word movement
(define-key helixel-normal-map "w" #'helixel-forward-word-start)
(define-key helixel-normal-map "W" #'helixel-forward-WORD-start)
(define-key helixel-normal-map "e" #'helixel-forward-word-end)
(define-key helixel-normal-map "E" #'helixel-forward-WORD-end)
(define-key helixel-normal-map "b" #'helixel-backward-word-start)
(define-key helixel-normal-map "B" #'helixel-backward-WORD)
;; Paragraph / Sentence / Function movement
(define-key helixel-normal-map "}" #'helixel-forward-paragraph-start)
(define-key helixel-normal-map "{" #'helixel-backward-paragraph-start)
;; Unimpaired — [ ] { } as textobj prefix keymaps
(define-key helixel-normal-map "]" helixel-right-map)
(define-key helixel-normal-map "[" helixel-left-map)
(define-key helixel-normal-map "}" helixel-inner-right-map)
(define-key helixel-normal-map "{" helixel-inner-left-map)
;; Prefix maps
(define-key helixel-normal-map "m" helixel-textobj-map)

(define-key helixel-normal-map "g" helixel-goto-map)
(define-key helixel-normal-map "z"    helixel-view-map)
(define-key helixel-normal-map " "    helixel-space-map)
(define-key helixel-normal-map "\C-w" helixel-window-map)

;; M-s prefix: incremental multi-cursor commands
(defvar-keymap helixel-mc-map
  :doc "Keymap for helixel multi-cursor `s' prefix.
Helix-style top-level keys live directly in `helixel-normal-map'
\(`(' `)' `M-(' `M-)') because they are typically pressed in
rapid succession (rotating through cursors).  Less frequently
used selection management lives here under `s'."
  "s"   #'helixel-mc-toggle
  "x"   #'helixel-mc-edit-lines
  "a"   #'helixel-mc-add-cursor-here
  "A"   #'helixel-mc-add-cursor-here-up
  "n"   #'helixel-mc-mark-next-like-this
  "p"   #'helixel-mc-mark-previous-like-this
  "N"   #'helixel-mc-skip-next
  "P"   #'helixel-mc-skip-previous
  "u"   #'helixel-mc-unmark-next
  "U"   #'helixel-mc-unmark-previous
  "."   #'helixel-mc-apply-last-action
  ;; Helix-style selection ops
  ";"   #'helixel-collapse-selection ; like Helix `;'
  ","   #'helixel-mc-clear-all       ;`,' = remove fakes
  "v"   #'helixel-mc-restore-cursors ; like Helix gv
  "k"   #'helixel-mc-keep-matching   ; like Helix `K'
  "K"   #'helixel-mc-remove-matching ; like Helix `M-K'
  "-"   #'helixel-mc-merge           ; like Helix `M--'
  "&"   #'helixel-mc-align           ; like Helix `&'
  "_"   #'helixel-mc-trim            ; like Helix `_'
  "S"   #'helixel-mc-split-on-regex) ; like Helix `S'

(define-key helixel-normal-map "s" helixel-mc-map)
(define-key helixel-goto-map   "v" #'helixel-mc-restore-cursors)
;; Top-level Helix-style rotation: typically pressed repeatedly
;; to cycle through cursors.
(define-key helixel-normal-map "K"    #'helixel-mc-keep-matching)
(define-key helixel-normal-map "\M-k" #'helixel-mc-remove-matching)
(define-key helixel-normal-map "&"    #'helixel-mc-align)
(define-key helixel-normal-map "_"    #'helixel-mc-trim)
(define-key helixel-normal-map "\M--" #'helixel-mc-merge)
(define-key helixel-normal-map "C"    #'helixel-mc-add-cursor-here)
(define-key helixel-normal-map "\M-c" #'helixel-mc-add-cursor-here-up)
(define-key helixel-normal-map "("    #'helixel-mc-rotate-primary-backward)
(define-key helixel-normal-map ")"    #'helixel-mc-rotate-primary-forward)
(define-key helixel-normal-map "\M-," #'helixel-mc-remove-primary)  ; Helix A-,
(define-key helixel-normal-map "\M-(" #'helixel-mc-rotate-content-backward)
(define-key helixel-normal-map "\M-)" #'helixel-mc-rotate-content-forward)


;; helixel-visual-map (inherits normal-map)
(set-keymap-parent helixel-visual-map helixel-normal-map)
(define-key helixel-visual-map "v"    #'helixel-visual-exit)
(define-key helixel-visual-map "o"    #'helixel-visual-exchange-point-and-mark)
(define-key helixel-visual-map [escape] #'helixel-visual-exit)
(define-key helixel-normal-map "\M-;" #'helixel-visual-exchange-point-and-mark)

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

(defun helixel-normal-escape ()
  "Escape handler: chain end → clear cursors → `keyboard-quit'.
When a chain recording is active (see `helixel--chain-active-p'),
finishes the chain (which may also apply the chain at every fake
cursor via the mc integration hook).
Else, when any fake cursors are visible, clear them.
Else fall back to `keyboard-quit'."
  (interactive)
  (cond
   ((helixel--chain-active-p)
    (helixel-repeat-chain-end))
   ((and (boundp 'helixel-multi-cursor-mode)
         helixel-multi-cursor-mode)
    (helixel-mc-clear-all))
   (t (keyboard-quit))))

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


(helixel-define-key 'normal "/"    #'helixel-search-forward)
(helixel-define-key 'normal "?"    #'helixel-search-backward)
(helixel-define-key 'normal "*"    #'helixel-search-at-point-next)
(helixel-define-key 'normal "#"    #'helixel-search-at-point-prev)
(helixel-define-key 'normal "f"    #'helixel-find-next-char)
(helixel-define-key 'normal "F"    #'helixel-find-prev-char)
(helixel-define-key 'normal "t"    #'helixel-find-till-char)
(helixel-define-key 'normal "T"    #'helixel-find-prev-till-char)
(helixel-define-key 'normal "n"    #'helixel-search-repeat-next)
(helixel-define-key 'normal "N"    #'helixel-search-repeat-reverse)
(helixel-define-key 'normal "\M-." #'helixel-repeat-selection)

;; ── Org-mode emphasis marker text objects (~ = _ / * +) ──
;; These are quote-style text objects that only activate in org-mode
;; and derived modes, where ~...~ =...= _..._ /.../ *...* +...+ are
;; standard Org emphasis delimiters (code, verbatim, underline, italic,
;; bold, strikethrough).
(helixel-define-key 'textobj-inner "~" #'helixel-mark-inner-tilde
                    'org-mode)
(helixel-define-key 'textobj-outer "~" #'helixel-mark-a-tilde
                    'org-mode)
(helixel-define-key 'textobj-inner "=" #'helixel-mark-inner-equal
                    'org-mode)
(helixel-define-key 'textobj-outer "=" #'helixel-mark-a-equal
                    'org-mode)
(helixel-define-key 'textobj-inner "_" #'helixel-mark-inner-underscore
                    'org-mode)
(helixel-define-key 'textobj-outer "_" #'helixel-mark-a-underscore
                    'org-mode)
(helixel-define-key 'textobj-inner "/" #'helixel-mark-inner-slash
                    'org-mode)
(helixel-define-key 'textobj-outer "/" #'helixel-mark-a-slash
                    'org-mode)
(helixel-define-key 'textobj-inner "*" #'helixel-mark-inner-star
                    'org-mode)
(helixel-define-key 'textobj-outer "*" #'helixel-mark-a-star
                    'org-mode)
(helixel-define-key 'textobj-inner "+" #'helixel-mark-inner-plus
                    'org-mode)
(helixel-define-key 'textobj-outer "+" #'helixel-mark-a-plus
                    'org-mode)


(add-hook 'helixel-state-change-hook #'helixel--refresh-overriding-maps)
(add-hook 'helixel-state-change-hook #'helixel--refresh-textobj-overrides)

(provide 'helixel-keymap)
;;; helixel-keymap.el ends here
