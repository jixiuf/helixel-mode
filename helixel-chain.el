;;; helixel-chain.el --- chain recording & compound dot-repeat  -*- lexical-binding: t; -*-

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
;; Compound dot-repeat: `q' starts a chain, ESC ends it, `C-g'
;; cancels.  After Phase 4.4 chain recording captures the LIST of
;; helixel-tx values produced by the commands run during the chain
;; (every helixel command produces a tx via Phase 4.3).  Replay
;; iterates the list and calls `helixel-tx-replay' on each tx in
;; chronological order.  No more keystroke / kmacro capture.
;;
;; Accumulation: chain registers a function on
;; `helixel-action-commit-hook' (in `helixel-ring.el').  Every time
;; an action commits to the ring, the hook checks if a chain is
;; active and the committed action's tx has a runner (i.e. it can be
;; replayed).  If yes, append the tx to the session's `tx-list'.
;;
;; Inter-command motion: Phase 4.3 made every movement command
;; produce a tx whose runner re-invokes the command.  These motion
;; txs land in the same `tx-list', so replay positions point exactly
;; as during recording \u2014 no separate move-keys / edit-keys split.

;;; Code:

(require 'cl-lib)
(require 'helixel-core)         ; helixel-tx-create
(require 'helixel-ring)         ; helixel-action-commit-hook
(require 'helixel-macros)       ; helixel-with-action-tracking
(require 'helixel-repeat)       ; helixel--maybe-flip-dir-action, strategy

;; ── Session struct (single buffer-local) ──

(cl-defstruct (helixel-chain-session
               (:conc-name helixel-chain-session-)
               (:copier nil))
  "Per-buffer chain recording session.
Slots:
  ACTIVE-P    \u2014 non-nil while recording.
  TX-LIST     \u2014 list of `helixel-tx' values committed during the
                chain (chronological after `nreverse').
  INIT-CTX    \u2014 `helixel-sel' snapshotted at chain-start; drives
                advance behaviour at replay time.
  INIT-BOUNDS \u2014 (BEG . END) markers of the initial region, or nil."
  active-p
  tx-list
  init-ctx
  init-bounds)

(defvar-local helixel--chain-session nil
  "Per-buffer `helixel-chain-session' for the in-progress chain, or nil.")

(defsubst helixel--chain-active-p ()
  "Return non-nil while a chain is being recorded in this buffer."
  (and helixel--chain-session
       (helixel-chain-session-active-p helixel--chain-session)))

;; ── tx-list accumulator: hook on action-commit ──

(defun helixel--chain-on-commit (entry)
  "Append ENTRY's replayable tx to the active chain session, if any.
Hooked into `helixel-action-commit-hook'.  Skips ENTRYs whose
`by-command' is a chain-control command (so chain-start / ESC /
chain-end / chain-cancel are not themselves replayed)."
  (when (helixel--chain-active-p)
    (let ((cmd (helixel-action-by-command entry)))
      (unless (memq cmd
                    '(helixel-repeat-chain-start
                      helixel-repeat-chain-end
                      helixel-repeat-chain-cancel
                      helixel-normal-escape))
        ;; Only edit txs (those with a runner) contribute to the chain.
        ;; Movement-only events (op nil, preposition only) are not
        ;; replayed as part of chain dot-repeat.
        (when (helixel-action-runner entry)
          (push entry (helixel-chain-session-tx-list
                       helixel--chain-session)))))))

(add-hook 'helixel-action-commit-hook #'helixel--chain-on-commit)

;; ── Runner ──

(defun helixel--repeat-chain-runner (tx)
  "Replay each tx in chain TX's `:tx-list' payload, in order.
For search-initiated chains, reposition to `match-beginning' before
replay so insert-position semantics match the original recording
\(insert text starts at region-begin, not `match-end')."
  (let* ((sel (helixel-action-sel tx))
         (tx-list (helixel-action-payload-get tx :tx-list)))
    (helixel-with-replay-as 'dot
      (when tx-list
        (when (and sel (eq (helixel-sel-kind sel) 'search)
                   (match-beginning 0))
          (goto-char (match-beginning 0)))
        (dolist (sub-tx tx-list)
          (helixel-tx-replay sub-tx))))))

(helixel-register-op chain
  :display "chain"
  :runner #'helixel--repeat-chain-runner)

;; Note: chain previously had a custom `:strategy-builder' that
;; differed from the default only in allowing in-place repeat when the
;; sel kind had no `:advance' fn (e.g. chain after J / join-lines).
;; That special case is now baked into `helixel--repeat-advance' directly
;; via `(eq op 'chain)' — cleaner than maintaining a separate builder.


;; ── Cleanup helper ──

(defun helixel--chain-reset-state ()
  "Reset all chain bookkeeping state.
Releases any initial-region markers (so they don't pin buffer text),
clears `helixel--chain-session'.  Idempotent."
  (when-let* ((s helixel--chain-session)
              (bounds (helixel-chain-session-init-bounds s)))
    (let ((mb (car bounds)) (me (cdr bounds)))
      (when (marker-position mb) (set-marker mb nil))
      (when (marker-position me) (set-marker me nil))))
  (setq helixel--chain-session nil))


;; ── Lifecycle commands ──

;;;###autoload
(defun helixel-repeat-chain-start ()
  "Start recording a compound dot-repeat chain.
Snapshots the current selection context for advance decisions.
Commands run from now on are accumulated (their replay txs are
appended to the session via `helixel-action-commit-hook').  Call
`helixel-repeat-chain-end' to finish or
`helixel-repeat-chain-cancel' to discard."
  (interactive)
  (when (or (helixel--chain-active-p) executing-kbd-macro)
    (user-error "Already chaining or macro replay in progress"))
  (setq helixel--chain-session
        (make-helixel-chain-session
         :active-p t
         :tx-list nil
         :init-ctx helixel--pending-sel
         :init-bounds (when (use-region-p)
                        (cons (copy-marker (region-beginning))
                              (copy-marker (region-end))))))
  (deactivate-mark)
  (message "Chain rec \u2022 esc to finish"))

;;;###autoload
(defun helixel-repeat-chain-end ()
  "Stop chain recording and create a compound chain transaction.
Builds a chain tx whose `:tx-list' payload is the accumulated
list of sub-txs from this chain.  Advance behaviour is determined
by the initial selection context snapshotted at chain-start."
  (interactive)
  (unless (helixel--chain-active-p)
    (user-error "Not chaining"))
  (let* ((s helixel--chain-session)
         (_ (setf (helixel-chain-session-active-p s) nil))
         (tx-list (nreverse (helixel-chain-session-tx-list s)))
         (init-ctx (helixel-chain-session-init-ctx s))
         ;; Merge entry-kind from live ctx (i/a updates it after
         ;; snapshot, e.g. search + `i' transitions to search-i).
         (live-ctx helixel--pending-sel)
         (init-ctx (if (and init-ctx live-ctx
                            (eq (helixel-sel-kind init-ctx) 'search)
                            (not (helixel-sel-search-entry-kind init-ctx))
                            (helixel-sel-search-entry-kind live-ctx))
                       (helixel-sel-update-ctx
                        init-ctx :entry-kind
                        (helixel-sel-search-entry-kind live-ctx))
                     init-ctx))
         (had-content (and tx-list (consp tx-list))))
    (when had-content
      (let ((tx (helixel-tx-create 'chain init-ctx
                   :runner #'helixel--repeat-chain-runner
                   :display (format "chain(%d)" (length tx-list))
                   :tx-list tx-list)))
        (setq helixel--last-tx (helixel-tx-copy tx))
        (helixel-with-action-tracking
            (:op 'chain :category 'edit :subcat 'chain)
          (helixel--live-action-set tx))))
    (let ((n (length (or tx-list '()))))
      (helixel--chain-reset-state)
      (if had-content
          (message "Chain recorded (%d txs)" n)
        (message "Chain empty \u2014 nothing recorded")))
    ;; The action-commit-hook will fire when the chain action is
    ;; committed (via `helixel-with-action-tracking''s deferred
    ;; commit on the next command).  Integration layers (e.g.
    ;; `helixel-mc-integrate') filter for
    ;; by-command=`helixel-repeat-chain-end' on that hook
    ;; instead of using a separate chain-specific hook.
  ))

;;;###autoload
(defun helixel-repeat-chain-cancel ()
  "Discard the current chain without recording."
  (interactive)
  (helixel--chain-reset-state)
  (message "Chain cancelled"))

(provide 'helixel-chain)
;;; helixel-chain.el ends here
