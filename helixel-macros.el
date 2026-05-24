;;; helixel-macros.el --- Command & operator definition macros  -*- lexical-binding: t; -*-

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
;;
;; Command definition macros and the unified tracking entry point.
;;
;; `helixel--tracking-open'      — unified entry: open event (commit prev)
;; `helixel-with-edit-tracking'  — full wrapper: open + body + commit
;; `helixel-define-command'      — define a command with auto-injected tracking
;; `helixel-define-operator'     — define an editing operator (command + op reg)
;;
;; All tracking flows through `helixel--tracking-open':
;;
;;   helixel--tracking-open  ←  the single entry point (defun)
;;     ↑                ↑
;;     |                helixel-with-edit-tracking (full: open + body + commit)
;;     |
;;     helixel-define-command / direct callers / textobj-hook
;;
;; Extracted from helixel-state.el to reduce fan-in and clarify module
;; boundaries.

;;; Code:

(require 'cl-lib)
(require 'helixel-data)   ; for make-helixel-event, helixel-register-op

(declare-function helixel-event-commit "helixel-ring")
(declare-function helixel--clear-highlights "helixel-state")
(declare-function helixel--track-visual-move "helixel-state")

(defvar helixel--live-event)            ; defined in helixel-ring.el
(defvar helixel--inhibit-action-track)  ; defined in helixel-action.el
(defvar helixel--action-pos)            ; defined in helixel-action.el
(defvar-local helixel--selection-type)  ; defined in helixel-state.el

;; ═══════════════════════════════════════════════════════════════════════
;; Unified entry point: open event (commit prev, create new)
;; ═══════════════════════════════════════════════════════════════════════
;;
;; This is the SINGLE function through which all event-tracking flows.
;; Replaces the old `helixel-action-start'.

(defun helixel--tracking-open (category subcat &optional op)
  "Commit previous `helixel--live-event' and create a new one.
CATEGORY and SUBCAT classify the event for \\=`;\\=` and jump-list.
OP is an optional operator symbol (nil for movement/search).

No-op when `helixel--inhibit-action-track' is non-nil (dot-repeat).
Does NOT commit the new event — caller is responsible for eventual commit."
  (unless helixel--inhibit-action-track
    ;; Clear textobj selection state on non-textobj actions
    (when (and (eq helixel--selection-type 'textobj)
               (not (eq category 'textobj)))
      (setq helixel--selection-type nil))
    (helixel-event-commit)
    (setq helixel--live-event
          (make-helixel-event
           :op op
           :category category
           :subcat subcat
           :marker (point-marker)
           :timestamp (float-time)
           :buffer (current-buffer))
          helixel--action-pos nil)))

;; ═══════════════════════════════════════════════════════════════════════
;; Full tracking macro: open + body + commit
;; ═══════════════════════════════════════════════════════════════════════
;;
;; For standalone (self-contained) commands: opens the event before
;; body, commits in `unwind-protect' after body.

(cl-defmacro helixel-with-edit-tracking ((&key op category subcat)
                                         &body body)
  "Execute BODY with full event tracking (open → body → commit).

OP — operator symbol (nil for movement/search).
CATEGORY + SUBCAT — classification for \\=`;\\=` and jump-list.

Calls `helixel--tracking-open' for the open phase.  Commits the
event in an `unwind-protect' so it always finalises even on error."
  (declare (indent 1))
  `(progn
     (helixel--tracking-open ,category ,subcat ,op)
     (unwind-protect
         (progn ,@body)
       (unless helixel--inhibit-action-track
         (helixel-event-commit)))))

;; ═══════════════════════════════════════════════════════════════════════
;; Command definition macro
;; ═══════════════════════════════════════════════════════════════════════
;;
;; Uses `helixel--tracking-open' for event-open (event stays open
;; for a subsequent editing command to mutate and commit).

(defmacro helixel-define-command (name metadata &rest body)
  "Define a helixel command NAME with METADATA auto-tracking.

METADATA is a plist:
  :category CAT — action category (movement, edit, search, state, etc.)
  :subcat   SUB — action subcategory (word, kill, insert, etc.)
  :clear-highlights — default t for :category movement, nil otherwise
  :params   PARAM-LIST — optional function parameter list

For :category movement:
  - Auto-injects `helixel--track-visual-move' for \\=`.\\=` replay.
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

;; ═══════════════════════════════════════════════════════════════════════
;; Operator definition macro
;; ═══════════════════════════════════════════════════════════════════════

(defmacro helixel-define-operator (name metadata &rest body)
  "Define a helixel editing operator NAME.

Combines command definition (action tracking for \\=`;\\=` jumping
and jump-list navigation) with op registration (for \\=`.\\=` repeat)
into a single form.

METADATA is a plist:
  :op OP              — operator symbol for \\=`.\\=` (required)
  :display DISPLAY    — label string or function (TX) -> string
  :repeat-advance TAG — nil, \\=`line', or function
  :subcat SUB         — action subcategory (default: OP)
  :params PARAMS      — function parameter list

Expands to:
  1. (helixel-register-op OP :display ... :runner (lambda () (NAME)))
  2. (helixel-define-command NAME (:category edit ...) BODY)

The command body SHOULD call (helixel--record-edit OP ...) to record
the edit for \\=`.\\=` replay."
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
