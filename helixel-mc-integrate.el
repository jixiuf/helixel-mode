;;; helixel-mc-integrate.el --- mc + repeat/chain/insert glue -*- lexical-binding: t; -*-

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

;; Wires the multi-cursor model into helixel-mode's repeat (`.'),
;; chain (`q' ... ESC) and insert subsystems.
;;
;; Strategy:
;;   * insert mode             — `self-insert-command' is whitelisted,
;;                               so each fake cursor gets its own
;;                               character via the post-command-hook
;;                               dispatcher.  Nothing else to do.
;;   * dot-repeat (`.')        — whitelisted ON: each cursor runs
;;                               `helixel-repeat-edit' with its own
;;                               snapshotted `helixel--last-tx'.
;;   * repeat-selection (`,')  — same.
;;   * chain end               — `:after' advice: if any fake cursors,
;;                               propagate the newly built chain
;;                               transaction to every fake cursor and
;;                               immediately apply it once at each
;;                               position, all within a single undo
;;                               group.
;;   * keyboard-quit / ESC     — clears fake cursors.

;;; Code:

(require 'cl-lib)
(require 'helixel-core)
(require 'helixel-mc-core)
(require 'helixel-repeat)
(require 'helixel-chain)

(defvar helixel--last-tx)
;; defined in helixel-last-edit.el (loaded transitively via
;; helixel-mc-core → ...; explicit defvar here keeps byte-compile happy).

;; ── `.' / `,' semantics under multi-cursor ──
;;
;; Without mc, `.' does advance+apply: it moves to the NEXT target
;; (e.g. next word for a textobj sel) and applies the edit there.
;; Under mc this is wrong: every fake cursor (and the real cursor,
;; after `helixel-mc--realize-targets') is already positioned exactly
;; on a target by spawn, so advancing would move them off-target and
;; clobber neighbouring text.  The natural mc semantic is "apply the
;; last edit once at each cursor's current position" — i.e. the same
;; thing `helixel-mc-apply-last-action' does.
;;
;; We override `helixel-repeat-edit' (`.') via
;; `helixel-repeat-edit-override-functions' so that whenever fake
;; cursors exist, both the real-cursor invocation AND the per-fake
;; dispatches collapse to a single `helixel-tx-replay' (no advance
;; loop).  All N applications are then amalgamated into one undo
;; step by the dispatcher's `undo-amalgamate-change-group' wrapper.
;;
;; The override is installed/removed on `helixel-multi-cursor-mode'
;; toggle so it doesn't persist when mc is off.

(defun helixel-mc--repeat-edit-apply-only (raw-prefix)
  "Hook function for `helixel-repeat-edit-override-functions' under mc.
Return non-nil (handled) when `helixel-multi-cursor-mode' is on AND
fake cursors exist; run `helixel-tx-replay' once at point
instead of the full advance + apply loop.  Return nil to fall
through to the default `.' otherwise.  RAW-PREFIX is ignored in
the override path — mc dispatches the same edit at each fake."
  (ignore raw-prefix)
  (when (and (bound-and-true-p helixel-multi-cursor-mode)
             (helixel-mc-any-p)
             helixel--last-tx)
    (helixel-with-replay-as 'dot
      (helixel-tx-replay helixel--last-tx))
    t))

;; Install via `helixel-multi-cursor-mode' toggle — no top-level
;; add-hook needed.

;; ── Whitelist tweaks ──

;; `.` and `,` should run at every cursor: each cursor has its own
;; last-event snapshot, so they all replay independently.
(helixel-mc-mark-all-for-multi-cursors
 '(helixel-repeat-edit
   helixel-repeat-selection))

;; ── Substitute commands for fake-cursor dispatch ──
;;
;; Phase 4.3 unification: every prompting command (find-char, replace-
;; char, surround-add, etc.) now produces a `helixel-tx' whose payload
;; carries the prompted decisions.  The unified mc dispatcher reads
;; this tx via `helixel-mc--fresh-action-from-real' and replays the
;; runner at every fake.  No substitute-alist is needed — the previous
;; `helixel-mc-defcmd' calls for find-next-char / find-prev-char /
;; find-till-char / find-prev-till-char have been deleted.

;; The dispatcher (with atomic-undo amalgamation) lives in
;; helixel-mc-core.el as `helixel-mc--post-command'.

;; ── Chain end: broadcast the new chain tx ──

(defun helixel-mc--broadcast-last-event ()
  "Snapshot `helixel--last-tx' into every fake cursor's overlay.
Call after building a new chain transaction so subsequent `.' at
each fake cursor replays the chain (not the pre-chain edit)."
  (dolist (ov (helixel-mc-all-cursors))
    (setf (helixel-pcs-last-action (overlay-get ov 'helixel-pc-state))
          helixel--last-tx)))

(defun helixel-mc--apply-chain-once ()
  "Execute `helixel--last-tx' once at every fake cursor.
Assumes the current `helixel--last-tx' is a chain transaction
\(or any replayable edit).  Wraps the batch in one undo step."
  (when (and helixel-multi-cursor-mode helixel--last-tx)
    (helixel-with-replay-as 'mc-batch
      (let ((tx helixel--last-tx))
        (undo-amalgamate-change-group
          (helixel-mc-with-each-cursor
            (helixel-with-replay-as 'dot
              (helixel-tx-replay tx))))))))

(defun helixel-mc--on-chain-end (entry)
  "If ENTRY is the chain-end commit, broadcast to all fake cursors.
Runs from `helixel-action-commit-hook' (replaces the former
`helixel-chain-recorded-functions' dedicated hook).  The chain
end action has by-command=`helixel-repeat-chain-end'.  We only
broadcast — during recording the per-command dispatch already
applied every keystroke at every fake cursor live."
  (when (and helixel-multi-cursor-mode
             (eq (helixel-action-by-command entry)
                 'helixel-repeat-chain-end))
    (helixel-mc--broadcast-last-event)
    (let ((n (length (helixel-mc-all-cursors))))
      (message "helixel-mc: chain recorded for %d fake cursor%s"
               n (if (= n 1) "" "s")))))

(add-hook 'helixel-action-commit-hook
          #'helixel-mc--on-chain-end)

;; ── Insert-state per-cursor pre-positioning ──
;;
;; The helixel-insert / -after / -beginning-line / -after-end-line /
;; -newline / -prevline commands each declare a `:tx-runner' in their
;; `helixel-define-command' form (see helixel-editing.el).  The runner
;; calls one of the `helixel-mc--prepos-*' helpers; the unified mc
;; dispatcher invokes it at every fake cursor via the standard
;; fresh-action replay path.
;;
;; Phase 4.4 follow-up: the helpers themselves now live in
;; `helixel-editing.el' alongside the commands that reference them —
;; this eliminates the cross-module forward `declare-function' that
;; used to be required here.  Nothing left to define in this section.

;; ── Lifecycle: ensure mc cleans up with helixel-mode ──

(defun helixel-mc--cleanup-on-mode-off ()
  "Clear fake cursors and unhook when `helixel-mode' is turned off.
Called from `helixel-mode-off-hook'."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when helixel-multi-cursor-mode
        (helixel-multi-cursor-mode -1)))))

(add-hook 'helixel-mode-off-hook #'helixel-mc--cleanup-on-mode-off)

;; ── Public command: explicitly apply last edit to all cursors ──

;;;###autoload
(defun helixel-mc-apply-last-action ()
  "Apply `helixel--last-tx' once at every fake cursor.
Useful when you spawned cursors AFTER an edit and want to retro-
fit it onto the new positions.  Acts on the real cursor's
`helixel--last-tx' so cursors all replay the SAME edit."
  (interactive)
  (unless (helixel-mc-any-p)
    (user-error "No fake cursors"))
  (unless helixel--last-tx
    (user-error "No edit to apply"))
  (helixel-mc--broadcast-last-event)
  (helixel-mc--apply-chain-once))

;; Mark these helpers as real-cursor-only for safety.
(helixel-mc-mark-all-for-real-cursor-only
 '(helixel-mc-apply-last-action))

;; ── ESC / quit clear-up ──

(defun helixel-mc--maybe-clear-on-quit ()
  "Clear fake cursors when `keyboard-quit' fires.
Wired via `helixel-keyboard-quit-functions'."
  (when helixel-multi-cursor-mode
    (helixel-mc-clear-all)))

(add-hook 'helixel-keyboard-quit-functions #'helixel-mc--maybe-clear-on-quit)

;; ── Visual state sync ──
;;
;; `helixel-begin-selection' / `helixel-visual-exit' toggle a GLOBAL
;; state (`helixel--current-state').  If we broadcast them per-command,
;; the first fake sees the post-real state and toggles AGAIN — a chain
;; of cancellations.  Instead, mark them real-cursor-only and use a
;; hook on `helixel-state-change-hook' to mirror the new state onto
;; every fake cursor in one pass.

(defvar helixel--current-state)        ; from `helixel-state'
(defvar helixel-mc--prev-state nil
  "Previous value of `helixel--current-state' seen by the sync hook.
Used to detect transitions INTO and OUT OF `visual' so that
entering / leaving other states (e.g. `insert' from `normal' with
an active region from `/foo<RET>ss') does NOT clobber each
fake's `mark-active' — which the insert pre-positioner needs.")

(defun helixel-mc--sync-visual-state ()
  "Mirror real cursor's visual state onto every fake cursor.
Fires on transitions INTO `visual' (activate fake mark at fake
point) and OUT OF `visual' (deactivate fake mark).  All other
state transitions are ignored — in particular entering `insert'
from `normal' with an active region (the `/foo<RET>ss i' path)
must NOT wipe each fake's mark, because `helixel-mc--prepos-
region-begin' relies on `mark-active' to know where the fake's
selection started."
  (let ((prev helixel-mc--prev-state)
        (curr helixel--current-state))
    (setq helixel-mc--prev-state curr)
    (when (and helixel-multi-cursor-mode (helixel-mc-any-p))
      (cond
       ;; Entering visual: activate each fake's mark at its point.
       ((and (eq curr 'visual) (not (eq prev 'visual)))
        (helixel-with-replay-as 'mc-batch
          (helixel-mc-with-each-cursor
            (set-marker (mark-marker) (point))
            (setq mark-active t))))
       ;; Leaving visual: deactivate each fake's mark.
       ((and (eq prev 'visual) (not (eq curr 'visual)))
        (helixel-with-replay-as 'mc-batch
          (helixel-mc-with-each-cursor
            (setq mark-active nil))))))))

(add-hook 'helixel-state-change-hook #'helixel-mc--sync-visual-state)

(helixel-mc-mark-all-for-real-cursor-only
 '(helixel-begin-selection
   helixel-visual-exit))

;; ── Bulk whitelist: helixel interactive commands ──
;;
;; With `helixel-mc-default-policy = 'all' every unmarked command runs at
;; all cursors automatically.  These explicit marks are a safety net for
;; users who set the policy to `'once' or `'prompt' — they ensure all
;; helixel modal commands are dispatched to every fake cursor without
;; prompting, while guard commands (chain, escape, mc management) stay
;; real-cursor-only.

(defun helixel-mc--whitelist-helixel-commands ()
  "Mark safe helixel interactive commands for multi-cursor dispatch.
Iterates all interned symbols starting with \"helixel-\", skipping
only those EXPLICITLY marked nil (real-cursor-only) via
`helixel-mc-mark-all-for-real-cursor-only'.  Use `plist-member' to
distinguish \"property missing\" (mark it) from \"property is nil\"
\(leave it).

Call this AFTER every helixel module is loaded (see `helixel.el')
so the obarray walk actually sees all defined commands — calling
it from `helixel-mc-integrate' top-level only catches the handful
of commands from modules `mc-integrate' itself depends on."
  (mapatoms
   (lambda (sym)
     (when (and (commandp sym)
                (string-prefix-p "helixel-" (symbol-name sym))
                (not (plist-member (symbol-plist sym)
                                   'multiple-cursors)))
       (put sym 'multiple-cursors t)))))

;; NOTE: do NOT call `helixel-mc--whitelist-helixel-commands' here.
;; It must run after every helixel module has loaded — the call
;; lives at the bottom of `helixel.el'.

;; ── Shims: third-party commands are real-cursor-only ──
;;
;; Navigation / browsing commands from built-in / third-party modes
;; have no meaningful per-cursor semantics.  Mark them explicitly nil
;; via `put' so they never duplicate at fake cursors under any policy.
;; `put' on a not-yet-fbound symbol is safe — it just sets the
;; property — so no `with-eval-after-load' is needed.

(helixel-mc-mark-all-for-real-cursor-only
 '(;; info.el
   Info-next Info-prev Info-up Info-top-node Info-directory
   Info-menu Info-follow-reference Info-search Info-index
   Info-virtual-index Info-history Info-index-next Info-summary
   ;; help-mode.el
   help-go-back help-go-forward help-goto-next-page
   help-goto-previous-page help-view-source help-goto-info help-customize
   ;; shortdoc.el
   shortdoc-next-section shortdoc-previous-section
   ;; man.el
   Man-next-manpage Man-previous-manpage
   ;; woman.el
   WoMan-next-manpage WoMan-previous-manpage
   ;; eww.el
   eww-back-url eww-forward-url eww-reload))

;; ── Per-cursor prompt commands (replace-char, surround-*)
;;
;; `R<char>', `ms<char>', `md', `mr' all prompt the user.  Their op
;; runners read the prompted decision from the edit payload (`:char',
;; `:delimiter') and act on `region-beginning'/`region-end' — so they
;; are position-independent.  The mc dispatcher's fresh-edit path
;; detects the just-committed edit via its `by-command' stamp and
;; replays the runner at every fake — NO advice / NO real-only
;; marking / NO per-command broadcast logic needed.
;;
;; For `md' / `mr' path B (no delimiter at entry, transient map
;; collects a textobj at the real cursor), the real cursor enters
;; path A after textobj selection and broadcast goes through
;; fresh-edit dispatch normally.

;; ── Action cycle (`;') and jump nav (C-o / C-i)
;;
;; These commands navigate GLOBAL state:
;;   `helixel--action-pos' + `helixel--event-ring' for `;'
;;   `helixel--jump-pos'   + `helixel--global-jump-log' for C-o/C-i
;; They are not per-cursor: broadcasting them N times advances the
;; same global ring N times, with no useful effect on fakes.
;;
;; Mark them real-only.  For per-cursor movement repeat, users
;; should re-press the underlying motion key (e.g. `])', `]b'),
;; which broadcasts naturally.

(helixel-mc-mark-all-for-real-cursor-only
 '(helixel-jump-backward
   helixel-jump-forward))

(helixel-mc-mark-all-for-multi-cursors
 '(helixel-action-cycle))

;; ── `;' action-cycle at fakes is handled by the per-fake event
;; ring (see `helixel-mc--cursor-vars' registration of
;; `helixel--event-ring' / `--live-edit' / `--action-pos').
;; When `;' broadcasts, each fake runs the SAME `helixel-action--
;; cycle-show' code path against its OWN ring — the first `;'
;; press selects the traversed span, subsequent presses cycle
;; the history, and group-start logic all work naturally with
;; no mc-specific bookkeeping.

;; ── Third-party shims ──
;;
;; Lazy-loaded integration with third-party packages (e.g.
;; completion-preview) has moved to `helixel-mc-shims.el' to keep
;; this file focused on core repeat / chain / insert glue.  Mirrors
;; the split between `helixel-state' and `helixel-shims'.

(require 'helixel-mc-shims)

(provide 'helixel-mc-integrate)
;;; helixel-mc-integrate.el ends here
