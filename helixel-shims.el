;;; helixel-shims.el --- Shims for built-in modes  -*- lexical-binding: t; -*-

;; Copyright (C) 2025  jixiuf

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
;; Integration shims so helixel-mode plays well with built-in Emacs
;; modes.
;;
;; Two categories:
;;
;; 1. Editable sub-modes — enter → normal, exit → motion
;;    wdired, grep-edit, occur-edit, wgrep
;;
;; 2. Read-only modes — motion-state keybindings
;;    help-mode, info-mode, apropos-mode
;;    (Mode's own keys fall through from the suppressed motion map;
;;     we add g-prefix shortcuts for common commands.)

;;; Code:

(require 'helixel-state)
(require 'helixel-keymap)
(eval-when-compile (require 'helixel-mc-core))
(eval-when-compile (require 'helixel-mc-integrate))

;; ── Declare external functions (byte-compiler) ──

(defvar help-mode-map)

(declare-function Info-next "info")
(declare-function Info-prev "info")
(declare-function Info-up "info")
(declare-function Info-top-node "info")
(declare-function Info-directory "info")
(declare-function Info-menu "info")
(declare-function Info-follow-reference "info")
(declare-function Info-search "info")
(declare-function Info-index "info")
(declare-function Info-virtual-index "info")
(declare-function Info-history "info")
(declare-function Info-index-next "info")
(declare-function Info-summary "info")

(declare-function help-go-back "help-mode")
(declare-function help-go-forward "help-mode")
(declare-function help-goto-next-page "help-mode")
(declare-function help-goto-previous-page "help-mode")
(declare-function help-view-source "help-mode")
(declare-function help-goto-info "help-mode")
(declare-function help-customize "help-mode")

(declare-function shortdoc-next-section "shortdoc")
(declare-function shortdoc-previous-section "shortdoc")
(declare-function Man-next-manpage "man")
(declare-function Man-previous-manpage "man")
(declare-function WoMan-next-manpage "woman")
(declare-function WoMan-previous-manpage "woman")
(declare-function eww-back-url "eww")
(declare-function eww-forward-url "eww")
(declare-function eww-reload "eww")

(declare-function diff-hunk-kill "ext:diff-mode--subrs")
(declare-function diff-hunk-next "ext:diff-mode--subrs")
(declare-function diff-hunk-prev "ext:diff-mode--subrs")
(declare-function diff-file-next "ext:diff-mode--subrs")
(declare-function diff-file-prev "ext:diff-mode--subrs")
(declare-function log-view-msg-next "ext:log-view--subrs")
(declare-function log-view-msg-prev "ext:log-view--subrs")

(declare-function xref-edit-save-changes "xref")
(declare-function xref-change-to-xref-edit-mode "xref")

(defun helixel-shims--set-invisible-nil ()
  "Set `helixel-invisible' to nil for the current buffer.
Intended for mode hooks where invisible text means filtered-out
content (e.g. grep results with consult-focus-line, dired-omit)."
  (setq-local helixel-invisible nil))

;; ── wdired ──

(defun helixel-shims--setup-wdired ()
  "Setup wdired integration.
Entering wdired → normal.  Exiting (save/abort) → motion."
  (add-hook 'wdired-mode-hook #'helixel-enter-normal-state)
  (advice-add 'wdired-finish-edit   :after #'helixel-enter-motion-state)
  (advice-add 'wdired-abort-changes :after #'helixel-enter-motion-state)
  (when (fboundp 'wdired-exit)
    (advice-add 'wdired-exit :after #'helixel-enter-motion-state))
  ;; wdired-finish-edit / -abort-changes exit the mode globally —
  ;; mc dispatch would run them again at each fake cursor after the
  ;; mode is already off.
  (put 'wdired-finish-edit 'helixel-multiple-cursors nil)
  (put 'wdired-abort-changes 'helixel-multiple-cursors nil)
  ;; dired-omit-mode hides files via invisible text.
  (add-hook 'dired-mode-hook #'helixel-shims--set-invisible-nil))

;; ── grep-edit (Emacs 29+ built-in) ──

(defun helixel-shims--setup-grep-edit ()
  "Setup grep-edit integration.
Entering grep-edit → normal.  Saving → motion."
  (when (fboundp 'grep-edit-mode)
    (add-hook 'grep-edit-mode-hook #'helixel-enter-normal-state)
    (advice-add 'grep-edit-save-changes
                :after #'helixel-enter-motion-state)
    ;; gre-edit-save-changes exits the mode and saves globally —
    ;; mc dispatch would run it again at each fake cursor after the
    ;; mode is already off.  See also occur-cease-edit, wdired-*, wgre-*.
    (put 'grep-edit-save-changes 'helixel-multiple-cursors nil))
  ;; grep/occur results use invisible for filtering (consult-focus-line).
  (add-hook 'grep-mode-hook #'helixel-shims--set-invisible-nil))

;; ── occur-edit (Emacs 29+ built-in) ──

(defun helixel-shims--setup-occur-edit ()
  "Setup occur-edit integration.
Entering occur-edit → normal.  Ceasing edit → motion."
  (when (fboundp 'occur-edit-mode)
    (add-hook 'occur-edit-mode-hook #'helixel-enter-normal-state)
    (advice-add 'occur-cease-edit :after #'helixel-enter-motion-state)
    ;; occur-cease-edit exits the mode globally — must not
    ;; be dispatched to every fake cursor after the mode is off.
    (put 'occur-cease-edit 'helixel-multiple-cursors nil))
  (add-hook 'occur-mode-hook #'helixel-shims--set-invisible-nil))

;; ── wgrep (third-party) ──

(defun helixel-shims--setup-wgrep ()
  "Setup wgrep integration.
Entering wgrep → normal.  Exiting (save/finish/abort) → motion."
  (when (fboundp 'wgrep-change-to-wgrep-mode)
    (advice-add 'wgrep-change-to-wgrep-mode
                :after #'helixel-enter-normal-state)
    (advice-add 'wgrep-finish-edit
                :after #'helixel-enter-motion-state)
    (advice-add 'wgrep-abort-changes
                :after #'helixel-enter-motion-state)
    (advice-add 'wgrep-save-all-buffers
                :after #'helixel-enter-motion-state)
    (when (fboundp 'wgrep-exit)
      (advice-add 'wgrep-exit :after #'helixel-enter-motion-state))
    ;; These exit the mode globally and save/abort across buffers —
    ;; mc dispatch would run them again at each fake cursor after
    ;; the mode is already gone.
    (put 'wgrep-finish-edit 'helixel-multiple-cursors nil)
    (put 'wgrep-abort-changes 'helixel-multiple-cursors nil)
    (put 'wgrep-save-all-buffers 'helixel-multiple-cursors nil)))

;; ── xref-edit (Emacs 29+ built-in) ──

(defun helixel-shims--setup-xref-edit ()
  "Setup xref-edit integration.
Entering xref-edit → normal.  Saving → motion."
  (when (fboundp 'xref-change-to-xref-edit-mode)
    (add-hook 'xref-edit-mode-hook #'helixel-enter-normal-state)
    (advice-add 'xref-edit-save-changes
                :after #'helixel-enter-motion-state)
    ;; xref-edit-save-changes exits the mode and saves globally —
    ;; mc dispatch would run it again at each fake cursor after the
    ;; mode is already off.  See also occur-cease-edit, wdired-*, wgre-*.
    (put 'xref-edit-save-changes 'helixel-multiple-cursors nil)))

;; ── diff-mode ──

(defun helixel-shims--setup-diff-mode ()
  "Setup `diff-mode' keybindings in motion state.
Override `k' (normally `diff-hunk-kill' in `diff-mode-shared-map')
to move to the previous line, and bind `d' to `diff-hunk-kill'.
`j' already falls through to `helixel-next-line' via the motion
parent-patching mechanism."
  (helixel-define-key 'motion "d" #'diff-hunk-kill 'diff-mode)
  (helixel-define-key 'motion "k" #'helixel-previous-line 'diff-mode)
  (helixel-define-key 'motion "u" #'undo 'diff-mode)
  (helixel-define-key 'motion "gj" #'diff-hunk-next 'diff-mode)
  (helixel-define-key 'motion "gk" #'diff-hunk-prev 'diff-mode)
  (helixel-define-key 'motion "[[" #'diff-file-prev 'diff-mode)
  (helixel-define-key 'motion "]]" #'diff-file-next 'diff-mode))

;; ── log-view ──

(defun helixel-shims--setup-log-view ()
  "Setup `log-view' keybindings in motion state.
Add `g'-prefix shortcuts for common log-view navigation commands."
  (helixel-define-key 'motion "gj" #'log-view-msg-next 'log-view-mode)
  (helixel-define-key 'motion "gk" #'log-view-msg-prev 'log-view-mode))

;; ── Read-only mode keybindings ──
;; These modes default to motion state.  Their own keybindings fall
;; through from the suppressed motion map.  We add g-prefix shortcuts.

(defun helixel-shims--setup-help-mode ()
  "Setup `help-mode' keybindings in motion state.
Unset `l' from `help-mode-map' so it falls through to the
`helixel-normal-map' parent (`l' → `helixel-forward-char').
`h' is not bound in `help-mode-map', falls through to
`helixel-backward-char' automatically."
  (keymap-unset help-mode-map "l" t)
  (keymap-unset special-mode-map "h" t)
  (helixel-define-key 'motion "gb" #'help-go-back 'help-mode)
  (helixel-define-key 'motion "gf" #'help-go-forward 'help-mode)
  (helixel-define-key 'motion "gn" #'help-goto-next-page 'help-mode)
  (helixel-define-key 'motion "gp" #'help-goto-previous-page 'help-mode)
  (helixel-define-key 'motion "gt" #'forward-button 'help-mode)
  (helixel-define-key 'motion "gT" #'backward-button 'help-mode)
  (helixel-define-key 'motion "gr" #'revert-buffer 'help-mode)
  (helixel-define-key 'motion "gs" #'help-view-source 'help-mode)
  (helixel-define-key 'motion "gi" #'help-goto-info 'help-mode)
  (helixel-define-key 'motion "gc" #'help-customize 'help-mode))

(defun helixel-shims--setup-info-mode ()
  "Setup info-mode keybindings in motion state."
  (helixel-define-key 'motion "gn" #'Info-next 'Info-mode)
  (helixel-define-key 'motion "gp" #'Info-prev 'Info-mode)
  (helixel-define-key 'motion "gu" #'Info-up 'Info-mode)
  (helixel-define-key 'motion "gt" #'Info-top-node 'Info-mode)
  (helixel-define-key 'motion "gd" #'Info-directory 'Info-mode)
  (helixel-define-key 'motion "gm" #'Info-menu 'Info-mode)
  (helixel-define-key 'motion "gf" #'Info-follow-reference 'Info-mode)
  (helixel-define-key 'motion "gs" #'Info-search 'Info-mode)
  (helixel-define-key 'motion "gi" #'Info-index 'Info-mode)
  (helixel-define-key 'motion "gI" #'Info-virtual-index 'Info-mode)
  (helixel-define-key 'motion "gl" #'Info-history 'Info-mode)
  (helixel-define-key 'motion "g," #'Info-index-next 'Info-mode)
  (helixel-define-key 'motion "g?" #'Info-summary 'Info-mode)
  (helixel-define-key 'motion "gr" #'revert-buffer 'Info-mode))

(defun helixel-shims--setup-apropos-mode ()
  "Setup apropos-mode keybindings in motion state."
  (helixel-define-key 'motion "gr" #'revert-buffer 'apropos-mode))

(defun helixel-shims--setup-shortdoc-mode ()
  "Setup `shortdoc-mode' keybindings in motion state."
  (helixel-define-key 'motion "gn" #'shortdoc-next-section
                      'shortdoc-mode)
  (helixel-define-key 'motion "gp" #'shortdoc-previous-section
                      'shortdoc-mode))

(defun helixel-shims--setup-man-mode ()
  "Setup `Man-mode' keybindings in motion state."
  (helixel-define-key 'motion "gn" #'Man-next-manpage 'Man-mode)
  (helixel-define-key 'motion "gp" #'Man-previous-manpage 'Man-mode))

(defun helixel-shims--setup-prog-mode ()
  "Setup `prog-mode' keybindings in normal state."
  (when (fboundp 'prog-fill-reindent-defun)
    (helixel-define-key 'normal "gq" #'prog-fill-reindent-defun prog-mode-map)))

(defun helixel-shims--setup-woman-mode ()
  "Setup `woman-mode' keybindings in motion state."
  (helixel-define-key 'motion "gn" #'WoMan-next-manpage 'woman-mode)
  (helixel-define-key 'motion "gp" #'WoMan-previous-manpage 'woman-mode))

(defun helixel-shims--setup-eww-mode ()
  "Setup `eww-mode' keybindings in motion state."
  (helixel-define-key 'motion "gb" #'eww-back-url 'eww-mode)
  (helixel-define-key 'motion "gf" #'eww-forward-url 'eww-mode)
  (helixel-define-key 'motion "gr" #'eww-reload 'eww-mode))

;; ── Deferred registration ──
;; We defer calling the setup functions until the target library is
;; loaded because `advice-add' requires the function to exist.

;; Modes where invisible = filtered-out content.
(with-eval-after-load 'compile
  (add-hook 'compilation-mode-hook #'helixel-shims--set-invisible-nil))

;; State-transition shims
(with-eval-after-load 'wdired       (helixel-shims--setup-wdired))
(with-eval-after-load 'grep         (helixel-shims--setup-grep-edit))
(with-eval-after-load 'replace      (helixel-shims--setup-occur-edit))
(with-eval-after-load 'wgrep        (helixel-shims--setup-wgrep))
;; Keybinding shims
(with-eval-after-load 'help-mode    (helixel-shims--setup-help-mode))
(with-eval-after-load 'info         (helixel-shims--setup-info-mode))
(with-eval-after-load 'apropos      (helixel-shims--setup-apropos-mode))
(with-eval-after-load 'shortdoc     (helixel-shims--setup-shortdoc-mode))
(with-eval-after-load 'man          (helixel-shims--setup-man-mode))
(with-eval-after-load 'prog-mode    (helixel-shims--setup-prog-mode))
(with-eval-after-load 'woman        (helixel-shims--setup-woman-mode))
(with-eval-after-load 'eww          (helixel-shims--setup-eww-mode))
(with-eval-after-load 'xref         (helixel-shims--setup-xref-edit))
(with-eval-after-load 'diff-mode    (helixel-shims--setup-diff-mode))
(with-eval-after-load 'log-view     (helixel-shims--setup-log-view))

;; ── Multi-cursor shims ──
;;
;; completion-preview (Emacs 30.1+):
;;   `completion-preview-mode' overlays live only at the real
;;   cursor.  We mark the three preview-accept commands as
;;   real-only and add :around advice that mirrors the inserted
;;   text to every fake cursor in one undo group.

(defvar helixel-mc-completion-preview-commands
  ;; Build via `intern' so package-lint does not see literal symbols
  ;; from a package introduced in Emacs 30.1 and demand a hard
  ;; dependency bump.
  (mapcar #'intern
          '("completion-preview-insert"
            "completion-preview-insert-word"
            "completion-preview-insert-sexp"))
  "Commands whose inserted text should be mirrored to fake cursors.
Each command runs only at the real cursor (per its `helixel-multiple-cursors'
property), then `helixel-mc--completion-preview-sync' inserts the
same text at every fake within an mc undo step.")

(defun helixel-mc--completion-preview-sync (orig &rest args)
  "Around-advice: run ORIG with ARGS at real cursor, mirror to fakes.
ORIG is one of the `completion-preview-*' insert commands.  Captures
the text inserted between point-before and point-after the original
call and inserts the same string at every fake cursor within an
mc undo step.

No-op when multi-cursor mode is off, no fakes exist, dispatch is
already in progress (nested call), or the original call did not
advance point (preview not active / nothing inserted)."
  (let ((start (point)))
    (apply orig args)
    (when (and helixel-mc-mode
               (helixel-mc-any-p)
               (not (helixel-mc--dispatch-in-progress-p))
               (> (point) start))
      (let ((text (buffer-substring-no-properties start (point))))
        (helixel-mc--with-undo-step
          (helixel-mc-with-each-cursor
            (insert text)))))))

(defun helixel-mc--setup-completion-preview ()
  "Wire `completion-preview-*' insert commands into multi-cursor sync.
Marks each command real-only (so the `post-command-hook' dispatcher
doesn't try to call it at fakes) and installs the sync advice."
  (dolist (cmd helixel-mc-completion-preview-commands)
    (put cmd 'helixel-multiple-cursors nil)
    (advice-add cmd :around #'helixel-mc--completion-preview-sync)))

;; Defer setup until `completion-preview' loads (Emacs 30.1).
(with-eval-after-load 'completion-preview
  (helixel-mc--setup-completion-preview))

;; consult--read — cache during mc dispatch.  Defined at top
;; level so the byte-compiler sees `defun' before `advice-add'.
(defun helixel-mc--cache-consult--read (orig-fun &rest args)
  "Around-advice for `consult--read': cache result during mc dispatch.
ORIG-FUN is the original `consult--read' function; ARGS are its
arguments (usually a prompt string)."
  (if (bound-and-true-p helixel-mc-mode)
      (let* ((prompt (car-safe args))
             (key (cons 'consult--read prompt))
             (cached
              (cdr (assoc key helixel-mc--input-cache
                          (lambda (k1 k2) (equal k1 k2))))))
        (or cached
            (let ((val (apply orig-fun args)))
              (push (cons key val) helixel-mc--input-cache)
              val)))
    (apply orig-fun args)))
(declare-function consult--read "ext:consult")
(defun helixel-shims--setup-consult ()
  "Advise `consult--read' to cache input during mc dispatch."
  (advice-add #'consult--read
              :around #'helixel-mc--cache-consult--read))
(with-eval-after-load 'consult
  (helixel-shims--setup-consult))

(provide 'helixel-shims)
;;; helixel-shims.el ends here
