;;; helixel-insert-record.el --- Insert-mode key + text recording -*- lexical-binding: t; -*-

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
;;
;; Records insert-mode user activity for dot-repeat (`.') and
;; multi-cursor broadcast.  Each command run during insert mode is
;; captured as ONE of two segment kinds:
;;
;;   (:keys VEC)
;;     The command did NOT modify the buffer (pure motion, no-op, ...).
;;     Replay via `execute-kbd-macro' / `insert-char'.
;;
;;   (:text STR :delete-before N :offset O)
;;     The command DID modify the buffer (self-insert, electric-pair
;;     pair insertion, completion-preview accept, snippet expand, ...).
;;     STR is the net inserted substring (the post-state buffer text
;;     within the command's change span).
;;     N is the number of characters to delete BEFORE the insertion
;;     site at replay time \u2014 used when the command did a
;;     replace-with-completion (e.g. `completion-preview-insert'
;;     replacing the prefix `fo' with `foo' \u2014 N=2, STR="foo").
;;     O is the offset of point from the END of the insertion at
;;     recording time (e.g. -1 for `()' from `electric-pair-mode' to
;;     land point between the parens).
;;     Replay = `(delete-char -N)' then `(insert STR)' then
;;     `(goto-char (+ (point) O))'.  `post-self-insert-hook' is NOT
;;     re-fired, because STR already reflects whatever the hook
;;     produced live \u2014 re-firing would double-insert pairs.
;;
;; The text-chunk path makes `.' faithful for commands whose effect
;; isn't reproducible by replaying the keystroke alone:
;;   - `completion-preview-insert' (and other completion-accept
;;     commands) insert text that depends on the overlay state at
;;     accept time \u2014 not present at replay time.
;;   - `yasnippet'-style expansions, `tempel', emmet expansion, ...
;;   - any custom binding that inserts more (or different) text than
;;     the typed key.
;;
;; Public API (consumed by helixel-state, helixel-editing,
;; helixel-repeat):
;;   helixel--insert-begin
;;   helixel--insert-finish    \u2192 list of segments (replaces key-vec)
;;   helixel--execute-keys     \u2192 accepts segment list OR raw key vec
;;   helixel--repeat-get-keys

;;; Code:

(require 'helixel-core)

(defvar-local helixel--insert-segments nil
  "List of insert-mode segments captured during the current insert session.
Each element is one of:
  (:keys VEC)
  (:text STR :delete-before N :offset O)
Pushed in reverse order; finalized (nreverse) by
`helixel--insert-finish'.")

(defvar-local helixel--insert-cmd-keys nil
  "Key vector captured at `pre-command-hook' for the current command.")

(defvar-local helixel--insert-cmd-start-point nil
  "Point (integer) at `pre-command-hook' time of the current command.")

(defvar-local helixel--insert-cmd-events nil
  "List of (BEG END LEN) triples from `after-change-functions'.
Accumulated during the current command; consumed by
`helixel--insert-classify-segment'.")

;; \u2500\u2500 after-change-functions \u2500\u2500

(defun helixel--insert-after-change (beg end len)
  "Push (BEG END LEN) onto `helixel--insert-cmd-events'."
  (push (list beg end len) helixel--insert-cmd-events))

;; \u2500\u2500 pre / post-command hooks \u2500\u2500

(defun helixel--on-insert-command ()
  "Pre-command-hook: snapshot key + reset per-command change tracking.
Skips `helixel-insert-exit'."
  (unless (eq this-command 'helixel-insert-exit)
    (setq helixel--insert-cmd-keys        (helixel-keyrec-capture)
          helixel--insert-cmd-start-point (point)
          helixel--insert-cmd-events      nil)))

(defun helixel--insert-classify-segment ()
  "Return the segment plist for the just-finished command.
Reads `helixel--insert-cmd-events' along with the pre-command
snapshot of point.  Returns one of:
  (:keys VEC)
  (:text STR :delete-before N :offset O)
or nil for an effectively empty change."
  (let ((events helixel--insert-cmd-events))
    (if (null events)
        ;; No buffer modification: replay the keystroke verbatim.
        (list :keys helixel--insert-cmd-keys)
      (let* ((mn (apply #'min (mapcar #'car  events)))
             (mx (apply #'max (mapcar #'cadr events)))
             (span (- mx mn)))
        (cond
         ;; Span collapsed to empty range \u2014 pure deletion or fully
         ;; reverted change.  Safest replay is the keystroke.
         ((<= span 0)
          (list :keys helixel--insert-cmd-keys))
         (t
          (let* ((str   (buffer-substring-no-properties mn mx))
                 (offset (- (point) mx))
                 ;; `delete-before' \u2014 chars to remove just-before the
                 ;; insertion site at replay time.  Approximation:
                 ;; how many chars BEFORE the post-state insertion
                 ;; site existed pre-command and were eaten by the
                 ;; replace-style change.
                 (start helixel--insert-cmd-start-point)
                 (delete-before (max 0 (- start mn))))
            (list :text str
                  :delete-before delete-before
                  :offset offset))))))))

(defun helixel--insert-post-command ()
  "Post-command-hook: build a segment for the just-finished command."
  (when (and helixel--insert-cmd-keys
             (not (eq this-command 'helixel-insert-exit)))
    (let ((seg (helixel--insert-classify-segment)))
      (when seg
        (push seg helixel--insert-segments)))
    (setq helixel--insert-cmd-keys        nil
          helixel--insert-cmd-events      nil
          helixel--insert-cmd-start-point nil)))

;; \u2500\u2500 Public lifecycle \u2500\u2500

(defun helixel--insert-begin ()
  "Start insert-mode recording.
Installs pre/post-command hooks + an after-change hook."
  (setq helixel--insert-segments         nil
        helixel--insert-cmd-keys         nil
        helixel--insert-cmd-events       nil
        helixel--insert-cmd-start-point  nil)
  (add-hook 'pre-command-hook       #'helixel--on-insert-command nil t)
  (add-hook 'post-command-hook      #'helixel--insert-post-command nil t)
  (add-hook 'after-change-functions #'helixel--insert-after-change nil t))

(defun helixel--insert-finish ()
  "End insert-mode recording.  Returns the finalized segment list."
  (remove-hook 'pre-command-hook       #'helixel--on-insert-command t)
  (remove-hook 'post-command-hook      #'helixel--insert-post-command t)
  (remove-hook 'after-change-functions #'helixel--insert-after-change t)
  (let ((segs (nreverse helixel--insert-segments)))
    (setq helixel--insert-segments nil
          helixel--insert-cmd-keys nil)
    segs))

;; \u2500\u2500 Replay \u2500\u2500

(defsubst helixel--repeat-get-keys (tx)
  "Return the :keys payload from TX (segment list OR legacy key vector)."
  (helixel-action-payload-get tx :keys))

(defun helixel--execute-keys (keys-or-segments)
  "Execute insert-mode replay payload KEYS-OR-SEGMENTS.

Accepted shapes:
  * Segment list: each element is (:keys VEC) or
    (:text STR :delete-before N :offset O).  Produced by
    `helixel--insert-finish'.
  * Raw key vector / string: legacy / hand-built payloads.  Replayed
    char-by-char with `post-self-insert-hook' firing so
    `electric-pair-mode' works.

A `:text' segment is replayed by deleting N chars before point
\\(if N > 0\\), inserting STR, and moving point by O.  The
`post-self-insert-hook' is NOT re-fired \u2014 STR already contains
whatever the hook produced live."
  (helixel-with-replay-as 'dot
    (cond
     ;; Empty payload.
     ((or (null keys-or-segments)
          (and (or (vectorp keys-or-segments)
                   (stringp keys-or-segments))
               (= 0 (length keys-or-segments))))
      nil)
     ;; Segment list (plist with keyword cars).
     ((and (listp keys-or-segments)
           (consp (car keys-or-segments))
           (keywordp (caar keys-or-segments)))
      (dolist (seg keys-or-segments)
        (cond
         ((plist-member seg :text)
          (let* ((str    (plist-get seg :text))
                 (del    (or (plist-get seg :delete-before) 0))
                 (offset (or (plist-get seg :offset) 0))) ; ctx-lint-ok
            (when (> del 0)
              (delete-char (- (min del (- (point) (point-min))))))
            (insert str)
            (unless (zerop offset)
              (goto-char (+ (point) offset)))))
         ((plist-member seg :keys)
          (helixel--execute-keys-vector (plist-get seg :keys))))))
     ;; Legacy raw key vector OR key string (`kbd' returns a string).
     ((or (vectorp keys-or-segments) (stringp keys-or-segments))
      (helixel--execute-keys-vector
       (if (stringp keys-or-segments)
           (vconcat keys-or-segments)
         keys-or-segments))))))

(defun helixel--execute-keys-vector (keys)
  "Replay raw key vector KEYS char-by-char.
Printable chars use `insert-char' + `post-self-insert-hook' so
`electric-pair-mode' fires.  Non-printable keys use
`execute-kbd-macro'."
  (when (and keys (> (length keys) 0))
    (dolist (key (append keys nil))
      (if (and (characterp key) (>= key 32) (/= key 127))
          (let ((last-command-event key))
            (insert-char key 1 t)
            (deactivate-mark)
            (run-hooks 'post-self-insert-hook))
        (let ((win (selected-window)))
          (if (and win (not (eq (window-buffer win)
                                (current-buffer))))
              (let ((prev-buf (window-buffer win)))
                (unwind-protect
                    (progn
                      (set-window-buffer win (current-buffer))
                      (execute-kbd-macro (vector key) 1))
                  (set-window-buffer win prev-buf)))
            (execute-kbd-macro (vector key) 1)))))))

(provide 'helixel-insert-record)
;;; helixel-insert-record.el ends here

