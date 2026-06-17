;;; helixel-macros.el --- Command and operator definition macros -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

;; Author: jixiuf
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
;; Command definition macros for helixel-mode.
;;
;; `helixel-with-action-tracking'  — full wrapper: open + body + commit
;; `helixel-define-command'      — define command with auto-injected tracking
;; `helixel-define-operator'     — editing operator (command + op reg)
;;
;; All macros expand to inline code (zero hooks).  They depend on
;; `helixel--tracking-open' and `helixel-action-commit' from
;; `helixel-ring', and `helixel-register-op' from `helixel-core'.

;;; Code:

(require 'cl-lib)
(require 'helixel-core)
(require 'helixel-ring)

;; ── Full tracking macro: open + body + commit ──

(cl-defmacro helixel-with-action-tracking ((&key op category subcat)
                                         &body body)
  "Execute BODY with full event tracking (open → body → commit).

OP — operator symbol (nil for movement/search).
CATEGORY + SUBCAT — classification for \=`;\=` and jump-list.

Calls `helixel--tracking-open' for the open phase.  Commits the
event in an `unwind-protect' so it always finalises even on error."
  (declare (indent 1))
  `(progn
     (helixel--tracking-open ,category ,subcat ,op)
     (unwind-protect
         (progn ,@body)
       (unless (helixel-replaying-p)
         (helixel-action-commit)))))

;; ── Command definition macro ──

(defmacro helixel-define-command (name metadata &rest body)
  "Define a helixel command NAME with METADATA auto-tracking.

METADATA is a plist:
  :category CAT — action category (movement, edit, search, state, etc.)
  :subcat   SUB — action subcategory (word, kill, insert, etc.)
  :clear-highlights — default t for :category movement, nil otherwise
  :params   PARAM-LIST — optional function parameter list
  :motion-extra FORM — optional form whose value is a plist of extra
                        keys for \=`helixel--record-movement-motion'.
                        Only meaningful for :category movement.
                        The plist is passed directly to the recording
                        function, eliminating symbol-property
                        indirection.  Useful for compile-time-known
                        data (pair delimiters) or nil (the body can
                        `setq' `helixel--motion-extra' at runtime).
  :preposition FN — optional unary function (TX) to attach to the live
                   action's tx as a `:preposition' slot.
                   Used to make the command's effect replayable at
                   multi-cursors and other replay sites: FN is called
                   before the main runner in `helixel-action-replay'.
                   For insert-entry commands, the prepos FN survives
                   the later `record-action' for \='insert-text that
                   creates the insert-text tx (preserved by
                   `helixel--record-action').
                   When omitted, no preposition is attached.
                   Invariant: at most one :preposition per command.
                   A second :preposition silently overwrites the first
                   (the payload plist holds a single :preposition).

For :category movement:
  - Auto-injects `helixel--track-visual-move' for \=`.\=` replay.
  - Auto-injects `helixel--clear-highlights' (unless :clear-highlights nil).
  - A `let'-bound variable `helixel--motion-extra' is available
    inside BODY — commands can `setq' it to pass runtime-discovered
    data (e.g. a matched delimiter plist) into the motion recording.

All tracking code is expanded inline at compile time — zero hooks.
BODY is the command's business logic."
  (declare (indent 2))
  (let* ((cat (plist-get metadata :category))
         (sub (plist-get metadata :subcat))
         (clear (if (plist-member metadata :clear-highlights)
                    (plist-get metadata :clear-highlights)
                  (eq cat 'movement)))
         (has-interactive (and (consp (car body))
                               (eq (caar body) 'interactive)))
         (interactive-form (if has-interactive (car body) '(interactive)))
         (rest-body (if has-interactive (cdr body) body))
         (params (plist-get metadata :params))
         (motion-extra-form (plist-get metadata :motion-extra))
         (preposition-fn (plist-get metadata :preposition))
         (track-visual
          (when (eq cat 'movement)
            `((helixel--track-visual-move ',name))))
         (attach-preposition preposition-fn))
    `(defun ,name ,(or params ())
       ,(format "Helixel %s.%s command." cat sub)
       ,interactive-form
       ;; ── Tag this command so `helixel-action-commit' can stamp
       ;; `by-command' on committed edits.  `helixel--current-command'
       ;; is the single source of truth — committed actions use it
       ;; directly; Emacs's command loop already sets `this-command'
       ;; to ',name for interactive invocation, so we don't override it.
       (let ((helixel--current-command ',name))
         ;; ── Open tracking event (via unified entry point) ──
         (helixel--tracking-open ',cat ',sub)
         ;; ── Optional :preposition attachment (for unified replay) ──
         ;; Attach BEFORE the body so eager record-action commits keep
         ;; the prepos fn on the committed ring entry.
         ;; `record-action' preserves :preposition across recording.
         ,@(when attach-preposition
             `((unless (helixel-replaying-p)
                 (when helixel--live-action
                   ;; Single-write invariant: cl-assert no sibling
                   ;; :preposition has set this slot already.
                   (cl-assert
                    (null (helixel-action-preposition
                           helixel--live-action))
                    nil
                    "helixel: preposition already set (multiple :preposition?)")
                   (setf (helixel-action-preposition
                          helixel--live-action)
                         ,preposition-fn)))))
         ;; ── Highlight clearing ──
         ,@(when clear '((helixel--clear-highlights)))
         ;; ── Body + motion tracking + visual tracking ──
         ;; Wrap in a let to capture origin so :dir is computed
         ;; from the actual point movement.  `helixel--motion-extra'
         ;; is available for the body to `setq' with runtime-discovered
         ;; data (e.g. matched delimiter from `helixel--jump-to-match-core').
         ,@(if (eq cat 'movement)
               `((let ((helixel--motion-origin (point))
                       (helixel--motion-extra ,motion-extra-form))
                   ,@rest-body
                   (helixel--record-movement-motion
                    ',name ',sub helixel--motion-origin
                    helixel--motion-extra)
                   ,@track-visual))
             `(,@rest-body
               ,@track-visual))))))

;; ── Operator definition macro ──

(defmacro helixel-define-operator (name metadata &rest body)
  "Define a helixel editing operator NAME.

Combines command definition (action tracking for \=`;\=` jumping
and jump-list navigation) with op registration (for \=`.\=` repeat)
into a single form.

METADATA is a plist:
  :op OP              — operator symbol for \=`.\=` (required)
  :display DISPLAY    — label string or function (TX) -> string
  :moves-point-p P    — boolean; see `helixel-register-op'.
  :subcat SUB         — action subcategory (default: OP)
  :params PARAMS      — function parameter list

Expands to:
  1. (helixel-register-op OP :display ... :runner (lambda () (NAME)))
  2. (helixel-define-command NAME (:category edit ...) BODY)

The command body SHOULD call (helixel--record-action OP ...) to record
the edit for \=`.\=` replay."
  (declare (indent 2))
  (let* ((op (plist-get metadata :op))
         (display (plist-get metadata :display))
         (moves-point (plist-get metadata :moves-point-p))
         (subcat (or (plist-get metadata :subcat) op)))
    (unless op
      (error "helixel-define-operator: :op is required"))
    `(progn
       ;; ── Op registration (for . replay) ──
       (helixel-register-op ,op
         :display ,display
         :moves-point-p ,moves-point
         :runner (lambda (_tx) (,name)))
       ;; ── Command definition (for action tracking) ──
       (helixel-define-command ,name
           (:category edit :subcat ,subcat
            ,@(when-let* ((p (plist-get metadata :params)))
                (list :params p)))
         ,@body))))

(provide 'helixel-macros)
;;; helixel-macros.el ends here
