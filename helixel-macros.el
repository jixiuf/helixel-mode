;;; helixel-macros.el --- Command and operator definition macros -*- lexical-binding: t; -*-

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
;; Command definition macros for helixel-mode.
;;
;; `helixel-with-edit-tracking'  — full wrapper: open + body + commit
;; `helixel-define-command'      — define command with auto-injected tracking
;; `helixel-define-operator'     — editing operator (command + op reg)
;;
;; All macros expand to inline code (zero hooks).  They depend on
;; `helixel--tracking-open' and `helixel-event-commit' from
;; `helixel-ring', and `helixel-register-op' from `helixel-core'.

;;; Code:

(require 'cl-lib)
(require 'helixel-core)
(require 'helixel-ring)

(defvar-local helixel--selection-type)  ; defined in helixel-state.el

;; ── Full tracking macro: open + body + commit ──

(cl-defmacro helixel-with-edit-tracking ((&key op category subcat)
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
       (unless helixel--inhibit-action-track
         (helixel-event-commit)))))

;; ── Command definition macro ──

(defmacro helixel-define-command (name metadata &rest body)
  "Define a helixel command NAME with METADATA auto-tracking.

METADATA is a plist:
  :category CAT — action category (movement, edit, search, state, etc.)
  :subcat   SUB — action subcategory (word, kill, insert, etc.)
  :clear-highlights — default t for :category movement, nil otherwise
  :params   PARAM-LIST — optional function parameter list

For :category movement:
  - Auto-injects `helixel--track-visual-move' for \=`.\=` replay.
  - Auto-injects `helixel--clear-highlights' (unless :clear-highlights nil).

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
         (track-visual
          (when (eq cat 'movement)
            `((helixel--track-visual-move ',name)))))
    `(defun ,name ,(or params ())
       ,(format "Helixel %s.%s command." cat sub)
       ,interactive-form
       ;; ── Open tracking event (via unified entry point) ──
       (helixel--tracking-open ',cat ',sub)
       ;; ── Highlight clearing ──
       ,@(when clear '((helixel--clear-highlights)))
       ;; ── Body (pure business logic) ──
       ,@rest-body
       ;; ── Visual-mode tracking (for . replay of movements) ──
       ,@track-visual)))

;; ── Operator definition macro ──

(defmacro helixel-define-operator (name metadata &rest body)
  "Define a helixel editing operator NAME.

Combines command definition (action tracking for \=`;\=` jumping
and jump-list navigation) with op registration (for \=`.\=` repeat)
into a single form.

METADATA is a plist:
  :op OP              — operator symbol for \=`.\=` (required)
  :display DISPLAY    — label string or function (TX) -> string
  :repeat-advance TAG — nil, \=`line', or function
  :subcat SUB         — action subcategory (default: OP)
  :params PARAMS      — function parameter list

Expands to:
  1. (helixel-register-op OP :display ... :runner (lambda () (NAME)))
  2. (helixel-define-command NAME (:category edit ...) BODY)

The command body SHOULD call (helixel--record-edit OP ...) to record
the edit for \=`.\=` replay."
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

(provide 'helixel-macros)
;;; helixel-macros.el ends here
