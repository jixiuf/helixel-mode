;;; helixel-replay.el --- Unified replay context  -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

;; Author: jixiuf
;; Keywords: convenience

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; Single context object that replaces the former four overlapping
;; flags:
;;
;;   helixel--in-replay
;;   helixel-with-replay-context
;;   helixel-mc--inhibit
;;   helixel-mc-executing-command-for-fake-cursor
;;
;; Plus three formerly-global search-advance scratch variables that
;; now live as fields on the context.
;;
;; Usage:
;;
;;   (helixel-with-replay 'dot
;;     (helixel-execute-edit edit))
;;
;; Any code can ask `(helixel-replaying-p)' or
;; `(helixel-replay-origin-p 'mc-fake)' to branch on context.
;; Nested `helixel-with-replay' preserves the outermost origin
;; UNLESS a more specific origin is supplied — see
;; `helixel-with-replay-as'.

;;; Code:

(require 'cl-lib)

(cl-defstruct (helixel-replay (:conc-name helixel-replay--))
  "Replay-time context.  Bound dynamically via `helixel-with-replay'."
  ;; What kind of replay?  One of:
  ;;   dot       — `.' dot-repeat
  ;;   comma     — `,' selection-repeat (preview)
  ;;   chain     — chain runner replaying a compound edit
  ;;   mc-fake   — dispatcher running at a fake cursor
  ;;   mc-batch  — mc broadcast outer loop (suppress re-dispatch)
  ;;   insert    — insert-mode replay
  (origin nil :read-only t)
  ;; Fake-cursor overlay (only set when origin = mc-fake).
  fake-cursor
  ;; Edit being replayed (helixel-edit struct), if any.
  edit
  ;; t when this replay is direction-flipped (e.g. `-.').
  reverse-p
  ;; --- search-advance scratch (per-session) ---
  ;; Last match-beginning processed, to detect zero-width loops.
  search-last-pos
  ;; t when a zero-width buffer-edge match was already processed.
  search-edge-seen
  ;; t when `helixel--repeat-advance-search' has positioned point,
  ;; so `helixel--recreate-search' should skip its internal search.
  search-advance-done)

(defvar helixel--replay nil
  "Current `helixel-replay' context, or nil when not replaying.
Dynamically bound by `helixel-with-replay'.")

(defsubst helixel-replaying-p ()
  "Return non-nil when the current replay is replaying a stored edit.
Does NOT include `mc-fake' / `mc-batch' origins — those wrap normal
command execution at fake cursors and should not suppress per-fake
recording.  Use `helixel-replay-in-fake-p' / `helixel-replay-origin-p'
for mc-specific guards."
  (and helixel--replay
       (memq (helixel-replay--origin helixel--replay)
             '(dot comma chain insert))))

(defsubst helixel-replay-origin ()
  "Return the origin of the current replay context, or nil."
  (and helixel--replay (helixel-replay--origin helixel--replay)))

(defsubst helixel-replay-origin-p (origin)
  "Return non-nil when current replay origin is ORIGIN."
  (and helixel--replay
       (eq (helixel-replay--origin helixel--replay) origin)))

(defsubst helixel-replay-in-fake-p ()
  "Return non-nil when replaying inside a fake cursor body."
  (helixel-replay-origin-p 'mc-fake))

(defsubst helixel-mc-dispatch-in-progress-p ()
  "Return non-nil when an mc dispatch is in progress.
Covers both `mc-batch' (outer broadcast loop) and `mc-fake'
\(inside one fake cursor's body).  Used by guards that must not
re-enter the dispatcher."
  (and helixel--replay
       (memq (helixel-replay--origin helixel--replay)
             '(mc-batch mc-fake))))

;; ── Search-advance scratch (per-session, was 3 globals) ──
;;
;; These fields live on the replay context so they reset for each new
;; `.' / `,' session automatically.  When called outside a replay
;; (interactive search), the getters return nil and the setters are
;; no-ops — exactly the right semantics.

(defsubst helixel-search-advance-done-p ()
  "Non-nil if `helixel--repeat-advance-search' positioned point this session."
  (and helixel--replay
       (helixel-replay--search-advance-done helixel--replay)))

(defsubst helixel-search-advance-done-set (val)
  "Set the search-advance-done flag to VAL on the current replay ctx."
  (when helixel--replay
    (setf (helixel-replay--search-advance-done helixel--replay) val)))

(defsubst helixel-search-advance-last-pos ()
  "Last `match-beginning' processed by `helixel--repeat-advance-search'."
  (and helixel--replay
       (helixel-replay--search-last-pos helixel--replay)))

(defsubst helixel-search-advance-last-pos-set (val)
  "Set the last-match-position field on the current replay ctx to VAL."
  (when helixel--replay
    (setf (helixel-replay--search-last-pos helixel--replay) val)))

(defsubst helixel-search-advance-edge-seen-p ()
  "Non-nil if a zero-width buffer-edge match was already processed."
  (and helixel--replay
       (helixel-replay--search-edge-seen helixel--replay)))

(defsubst helixel-search-advance-edge-seen-set (val)
  "Set the edge-seen field on the current replay ctx to VAL."
  (when helixel--replay
    (setf (helixel-replay--search-edge-seen helixel--replay) val)))

(defmacro helixel-with-replay (origin &rest body)
  "Run BODY with a fresh replay context tagged ORIGIN.
ORIGIN is one of the symbols listed in `helixel-replay'."
  (declare (indent 1) (debug t))
  `(let ((helixel--replay (make-helixel-replay :origin ,origin)))
     ,@body))

(defmacro helixel-with-replay-as (origin &rest body)
  "Like `helixel-with-replay' but only set ORIGIN if not already replaying.
Use when nesting: outer wrapper should win over inner.  BODY is the
form to evaluate."
  (declare (indent 1) (debug t))
  `(if helixel--replay
       (progn ,@body)
     (helixel-with-replay ,origin ,@body)))

(provide 'helixel-replay)
;;; helixel-replay.el ends here
