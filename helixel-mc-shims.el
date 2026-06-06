;;; helixel-mc-shims.el --- mc shims for third-party packages -*- lexical-binding: t; -*-

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

;;; Commentary:

;; Multi-cursor integration shims for third-party packages.
;;
;; Separated out from `helixel-mc-integrate.el' so that the latter
;; stays focused on core repeat / chain / insert glue.  Mirrors the
;; pattern in `helixel-shims.el' for non-mc third-party integration.
;;
;; Currently hosts:
;;
;;   completion-preview (Emacs 30.1+)
;;     `completion-preview-mode' overlays live only at the real
;;     cursor.  We mark the three preview-accept commands as
;;     real-only and add :around advice that mirrors the inserted
;;     text to every fake cursor in one undo group.
;;
;; All shims here are loaded lazily via `eval-after-load' so the
;; package itself never requires the third-party feature.

;;; Code:

(require 'helixel-mc-core)

;; ── completion-preview ──
;;
;; NOTE: no `declare-function' for `completion-preview-*' commands —
;; we only reference them by symbol (for `put', `advice-add'), never
;; call them directly, so the byte-compiler needs no signatures.
;; Adding `declare-function' would force package-lint to demand a
;; hard dependency on Emacs 30.1; we want this integration to remain
;; a soft, lazy-loaded shim.

(defvar helixel-mc-completion-preview-commands
  ;; Build via `intern' so package-lint does not see literal symbols
  ;; from a package introduced in Emacs 30.1 and demand a hard
  ;; dependency bump.
  (mapcar #'intern
          '("completion-preview-insert"
            "completion-preview-insert-word"
            "completion-preview-insert-sexp"))
  "Commands whose inserted text should be mirrored to fake cursors.
Each command runs only at the real cursor (per its `multiple-cursors'
property), then `helixel-mc--completion-preview-sync' inserts the
same text at every fake.")

(defun helixel-mc--completion-preview-sync (orig &rest args)
  "Around-advice: run ORIG with ARGS at real cursor, mirror to fakes.
ORIG is one of the `completion-preview-*' insert commands.  Captures
the text inserted between point-before and point-after the original
call and inserts the same string at every fake cursor.

No-op when multi-cursor mode is off, no fakes exist, dispatch is
already in progress (nested call), or the original call did not
advance point (preview not active / nothing inserted)."
  (let ((start (point)))
    (apply orig args)
    (when (and helixel-multi-cursor-mode
               (helixel-mc-any-p)
               (not (helixel-mc-dispatch-in-progress-p))
               (> (point) start))
      (let ((text (buffer-substring-no-properties start (point))))
        (undo-amalgamate-change-group
          (helixel-mc-with-each-cursor
            (insert text)))))))

(defun helixel-mc--setup-completion-preview ()
  "Wire `completion-preview-*' insert commands into multi-cursor sync.
Marks each command real-only (so the `post-command-hook' dispatcher
doesn't try to call it at fakes) and installs the sync advice."
  (dolist (cmd helixel-mc-completion-preview-commands)
    (put cmd 'multiple-cursors nil)
    (advice-add cmd :around #'helixel-mc--completion-preview-sync)))

;; Defer setup until `completion-preview' loads.  The `intern'
;; indirection keeps package-lint quiet about the Emacs 30.1 feature.
(funcall (intern "eval-after-load") (intern "completion-preview")
         '(funcall 'helixel-mc--setup-completion-preview))

(provide 'helixel-mc-shims)
;;; helixel-mc-shims.el ends here
