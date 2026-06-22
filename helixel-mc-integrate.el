;;; helixel-mc-integrate.el --- mc + repeat/chain/insert glue -*- lexical-binding: t; -*-

;; Copyright (C) 2026  jixiuf

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

;;; Commentary:

;; Wires the multi-cursor model into helixel-mode's repeat
;; (\\[helixel-repeat-edit]),
;; chain (\\[helixel-repeat-chain-start] ... ESC) and insert subsystems.
;;
;; Strategy:
;;   * insert mode             — `self-insert-command' is whitelisted,
;;                               so each fake cursor gets its own
;;                               character via the post-command-hook
;;                               dispatcher.  Nothing else to do.
;;   * dot-repeat (\\[helixel-repeat-edit]) — whitelisted ON: each cursor runs
;;                               `helixel-repeat-edit' with its own
;;                               snapshotted `helixel-last-action'.
;;   * repeat-selection (\\[helixel-repeat-last-motion])  — same.
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

(defvar helixel-last-action)
;; defined in helixel-last-edit.el (loaded transitively via
;; helixel-mc-core → ...; explicit defvar here keeps byte-compile happy).

;; ── \\[helixel-repeat-edit] / \\[helixel-repeat-last-motion] under
;; multi-cursor ──
;;
;; Without mc, \\[helixel-repeat-edit] does advance+apply: it moves to the NEXT
;; target
;; (e.g. next word for a textobj sel) and applies the edit there.
;; Under mc this is wrong: every fake cursor (and the real cursor,
;; after `helixel-mc--realize-targets') is already positioned exactly
;; on a target by spawn, so advancing would move them off-target and
;; clobber neighbouring text.  The natural mc semantic is "apply the
;; last edit once at each cursor's current position" — i.e. the same
;; thing `helixel-mc-apply-last-action' does.
;;
;; The override is installed/removed on `helixel-mc-mode'
;; toggle so it doesn't persist when mc is off.
;;
;; Undo amalgamation is handled by the mc undo-step wrapper
;; (`helixel-mc--pre-command' / `helixel-mc--post-command') which
;; injects `apply' entries into `buffer-undo-list' and strips
;; internal boundaries — no `undo-amalgamate-change-group' needed.

(defun helixel-mc--repeat-edit-apply-only (raw-prefix)
  "Hook function for `helixel-repeat-edit-override-functions' under mc.
Return non-nil (handled) when `helixel-mc-mode' is on AND
fake cursors exist; run `helixel-action-replay' once at point
instead of the full advance + apply loop.  Return nil to fall
through to the default \\[helixel-repeat-edit] otherwise.
RAW-PREFIX is ignored in
the override path — mc dispatches the same edit at each fake."
  (ignore raw-prefix)
  (when (and (bound-and-true-p helixel-mc-mode)
             (helixel-mc-any-p)
             helixel-last-action)
    (helixel-with-replay-as 'dot
      (helixel-action-replay helixel-last-action))
    t))

;; Install via `helixel-mc-mode' toggle — no top-level
;; add-hook needed.

;; ── Whitelist tweaks ──

;; `.` and `,` should run at every cursor: each cursor has its own
;; last-event snapshot, so they all replay independently.
(helixel-mc-mark-all-for-multi-cursors
 '(helixel-repeat-edit
   helixel-repeat-selection))

;; ── Chain end: broadcast the new chain action ──

(defun helixel-mc--broadcast-last-event ()
  "Snapshot `helixel-last-action' into every fake cursor's overlay.
Call after building a new chain transaction so subsequent
\\[helixel-repeat-edit] at
each fake cursor replays the chain (not the pre-chain edit)."
  (dolist (ov (helixel-mc-all-cursors))
    (setf (helixel-pcs-last-action (overlay-get ov 'helixel-pc-state))
          helixel-last-action)))

(defun helixel-mc--apply-chain-once ()
  "Execute `helixel-last-action' once at every fake cursor.
Assumes the current `helixel-last-action' is a chain transaction
\(or any replayable edit).  Wraps the batch in one undo step
via `helixel-mc--undo-step-begin' / `helixel-mc--undo-step-end-cb'."
  (when (and helixel-mc-mode helixel-last-action)
    (helixel-mc--with-undo-step
      (helixel-with-replay-as 'mc-batch
        (let ((tx helixel-last-action))
          (helixel-mc-with-each-cursor
            (helixel-with-replay-as 'dot
              (helixel-action-replay tx))))))))

(defun helixel-mc--on-chain-end (entry)
  "If ENTRY is the chain-end commit, broadcast to all fake cursors.
Hooked into `helixel-action-commit-hook'.  The chain
end action has by-command=`helixel-repeat-chain-end'.  We only
broadcast — during recording the per-command dispatch already
applied every keystroke at every fake cursor live."
  (when (and helixel-mc-mode
             (eq (helixel-action-by-command entry)
                 'helixel-repeat-chain-end))
    (helixel-mc--broadcast-last-event)
    (let ((n (length (helixel-mc-all-cursors))))
      (message "helixel-mc: chain recorded for %d fake cursor%s"
               n (if (= n 1) "" "s")))))


;; ── Insert-state per-cursor pre-positioning ──
;;
;; The helixel-insert / -after / -beginning-line / -after-end-line /
;; -newline / -prevline commands each declare a `:preposition' in their
;; `helixel-define-command' form (see helixel-editing.el).  The runner
;; calls one of the `helixel-mc--prepos-*' helpers; the unified mc
;; dispatcher invokes it at every fake cursor via the standard
;; fresh-action replay path.

;; ── Lifecycle: ensure mc cleans up with helixel-mode ──

(defun helixel-mc--cleanup-on-mode-off ()
  "Clear fake cursors and unhook when `helixel-mode' is turned off.
Called from `helixel-mode-off-hook'."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when helixel-mc-mode
        (helixel-mc-mode -1)))))

;; Mode-off hook deferred to `helixel-mc-integrate--init' (see end of file).

;; ── Public command: explicitly apply last edit to all cursors ──

;;;###autoload
(defun helixel-mc-apply-last-action ()
  "Apply `helixel-last-action' once at the real cursor and every fake cursor.
Useful when you spawned cursors AFTER an edit and want to retro-
fit it onto the new positions.  Acts on the real cursor's
`helixel-last-action' so all cursors replay the SAME edit.
Signals `user-error' when there are no fake cursors."
  (interactive)
  (unless (helixel-mc-any-p)
    (user-error "No fake cursors"))
  (unless helixel-last-action
    (user-error "No edit to apply"))
  (helixel-mc--broadcast-last-event)
  ;; Apply at real cursor AND every fake, wrapped in one undo step.
  (helixel-mc--with-undo-step
    (helixel-with-replay-as 'dot
      (helixel-action-replay helixel-last-action))
    (helixel-with-replay-as 'mc-batch
      (let ((tx helixel-last-action))
        (helixel-mc-with-each-cursor
          (helixel-with-replay-as 'dot
            (helixel-action-replay tx)))))))

;; Mark these helpers as real-cursor-only for safety.
(helixel-mc-mark-all-for-real-cursor-only
 '(helixel-mc-apply-last-action))

;; ── ESC / quit clear-up ──

(defun helixel-mc--maybe-clear-on-quit ()
  "Clear fake cursors when `keyboard-quit' fires.
Wired via `helixel-keyboard-quit-functions'."
  (when helixel-mc-mode
    (helixel-mc-clear-all)))


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
selection started.

When leaving visual, deactivation is only triggered for direct
toggles (`helixel-begin-selection', `helixel-visual-exit').
For edit commands (kill, change, etc.) that exit visual as a
side-effect via `helixel-clear-data', the mc post-command
dispatch loop replays the edit at each fake and handles mark
deactivation there — deactivating here would destroy the region
before dispatch can use it."
  (let ((prev helixel-mc--prev-state)
        (curr helixel--current-state))
    (setq helixel-mc--prev-state curr)
    (when (and helixel-mc-mode (helixel-mc-any-p))
      (cond
       ;; Entering visual: activate each fake's mark at its point.
       ((and (eq curr 'visual) (not (eq prev 'visual)))
        (helixel-with-replay-as 'mc-batch
          (helixel-mc-with-each-cursor
            (set-marker (mark-marker) (point))
            (setq mark-active t))))
       ;; Leaving visual: only sync deactivation for direct
       ;; toggles.  Edit commands (kill, change, ...) exit visual
       ;; as a side-effect — their per-fake replay in the
       ;; post-command dispatch loop handles deactivation.
       ((and (eq prev 'visual) (not (eq curr 'visual)))
        (when (memq this-command
                    '(helixel-begin-selection helixel-visual-exit))
          (helixel-with-replay-as 'mc-batch
            (helixel-mc-with-each-cursor
              (setq mark-active nil)))))))))


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

;; ── Action cycle (\\[helixel-action-cycle]) and jump cycle
;; (\\[helixel-action-cycle-mark-start]) ──
;;
;; `helixel-action-cycle' and `helixel-action-cycle-mark-start' are
;; dispatched to fake cursors.  Each fake owns its own
;; `helixel--action-ring', `helixel--live-action', `helixel--action-pos',
;; and `helixel--mark-cycle-pos' via `helixel-pc-state'.  When
;; broadcast, each fake navigates its OWN ring independently.
;;
;; Global jump nav (\\[helixel-jump-backward\\] / \\[helixel-jump-forward\\])
;; uses the shared
;; `helixel--global-jump-log' and is real-cursor-only.

(helixel-mc-mark-all-for-real-cursor-only
 '(helixel-jump-backward
   helixel-jump-forward))

(helixel-mc-mark-all-for-multi-cursors
 '(helixel-action-cycle
   helixel-action-cycle-mark-start))

;; ── \\[helixel-action-cycle] and
;; \\[helixel-action-cycle-mark-start] at fakes
;; are handled by the per-fake event
;; ring (see `helixel-pc-state' slots `event-ring', `live-action',
;; `action-pos', and `jump-cycle-pos').
;; When \\[helixel-action-cycle] or \\[helixel-action-cycle-mark-start]
;; broadcasts, each fake runs against its OWN
;; ring — \\[helixel-action-cycle] marks the traversed span on first press,
;; \\[helixel-action-cycle-mark-start] pushes
;; mark to the event start position.  Subsequent presses cycle
;; the history, and all logic works naturally with no mc-specific
;; bookkeeping.

;; ── Third-party shims ──
;;
;; Lazy-loaded integration with third-party packages (e.g.
;; completion-preview) has moved to `helixel-shims.el' to keep
;; this file focused on core repeat / chain / insert glue.  Mirrors
;; the split between `helixel-state' and `helixel-shims'.

(defun helixel-mc-integrate--init ()
  "Wire mc-integrate internals."
  (add-hook 'helixel-mode-off-hook #'helixel-mc--cleanup-on-mode-off)
  (add-hook 'helixel-action-commit-hook
            #'helixel-mc--on-chain-end)
  (add-hook 'helixel-keyboard-quit-functions #'helixel-mc--maybe-clear-on-quit)
  (add-hook 'helixel-state-change-hook #'helixel-mc--sync-visual-state))
;; helixel-mc-integrate--init registered via `helixel--register-mode-hooks'
;; in helixel.el.

;; ── Input cache for third-party commands ──
;;
;; Third-party commands whitelisted for mc dispatch may call
;; `read-char', `read-string', etc.  Without caching, each fake
;; cursor would block waiting for user input.  This mechanism
;; caches the real cursor's response and replays it at fakes.
;;
;; The cache is cleared at the start of every mc undo step
;; (`helixel-mc--pre-command'), so each command starts fresh.
;; Advice is only active during mc dispatch (`mc-batch' or
;; `mc-fake' replay context) inside `helixel-mc-mode'.

(defvar-local helixel-mc--input-cache nil
  "Alist of ((FN-NAME . PROMPT) . VALUE) during mc dispatch.
Cleared at the start of each mc undo step so each command
starts with a fresh cache.")

(defmacro helixel-mc--def-input-cache (fn-name)
  "Install advice on FN-NAME that caches user input during mc dispatch.
FN-NAME must take an optional PROMPT as its first argument.
The advice only intercepts when `helixel-mc-mode' is
active AND we are inside a fake-cursor dispatch
\(`helixel-mc--dispatch-in-progress-p')."
  (let ((advice-name (intern (format "helixel-mc--cache-%s" fn-name))))
    `(progn
       (defun ,advice-name (orig-fun &rest args)
         (if (bound-and-true-p helixel-mc-mode)
             (let* ((prompt (car-safe args))
                    (key (cons ',fn-name prompt))
                    (cached (cdr (assoc key helixel-mc--input-cache
                                       (lambda (k1 k2) (equal k1 k2))))))
               (or cached
                   (let ((val (apply orig-fun args)))
                     (push (cons key val) helixel-mc--input-cache)
                     val)))
           (apply orig-fun args)))
       (advice-add ',fn-name :around #',advice-name))))

;; Install advice at top level so the byte-compiler can see each
;; generated `defun' before its `advice-add' reference — this
;; allows sharp-quoting (`#\='') which satisfies melpazoid.
;; `advice-add' is idempotent, so these are safe to call at load
;; time even if `helixel-mc-integrate--init' re-runs later.
(helixel-mc--def-input-cache read-char)
(helixel-mc--def-input-cache read-string)
(helixel-mc--def-input-cache read-from-kill-ring)
(helixel-mc--def-input-cache read-char-from-minibuffer)
(helixel-mc--def-input-cache read-char-by-name)
(helixel-mc--def-input-cache read-quoted-char)
(helixel-mc--def-input-cache register-read-with-preview)

(provide 'helixel-mc-integrate)
;;; helixel-mc-integrate.el ends here
