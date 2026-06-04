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
;;                               snapshotted `helixel--last-event'.
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

(defvar helixel--last-event)
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
;; thing `helixel-mc-apply-last-edit' does.
;;
;; We override `helixel-repeat-edit' (`.') via the
;; `helixel-repeat-edit-function' hook (set up in
;; `helixel-multi-cursor-mode' enable below) so that whenever fake
;; cursors exist, both the real-cursor invocation AND the per-fake
;; dispatches collapse to a single `helixel--execute-edit' (no
;; advance loop).  All N applications are then amalgamated into
;; one undo step by the dispatcher's `undo-amalgamate-change-group'
;; wrapper.

(defun helixel-mc--repeat-edit-apply-only (raw-prefix)
  "Hook-impl for `helixel-repeat-edit-function' under mc.
Return non-nil (handled) when `helixel-multi-cursor-mode' is on AND
fake cursors exist; run `helixel--execute-edit' once at point
instead of the full advance + apply loop.  Return nil to fall
through to the default `.' otherwise.  RAW-PREFIX is ignored in
the override path — mc dispatches the same edit at each fake."
  (ignore raw-prefix)
  (when (and (bound-and-true-p helixel-multi-cursor-mode)
             (helixel-mc-any-p)
             helixel--last-event)
    (helixel-with-replay-context
      (helixel--execute-edit helixel--last-event))
    t))

;; Install / uninstall the override on mc-mode toggle.
(defun helixel-mc--repeat-edit-hook-install ()
  "Set `helixel-repeat-edit-function' to the mc override impl."
  (setq helixel-repeat-edit-function
        #'helixel-mc--repeat-edit-apply-only))

(defun helixel-mc--repeat-edit-hook-uninstall ()
  "Clear `helixel-repeat-edit-function' if it was set by mc."
  (when (eq helixel-repeat-edit-function
            #'helixel-mc--repeat-edit-apply-only)
    (setq helixel-repeat-edit-function nil)))

;; Install immediately so existing buffers with mc already on pick
;; up the override.  helixel-multi-cursor-mode hooks below keep it
;; in sync.
(helixel-mc--repeat-edit-hook-install)

;; ── Whitelist tweaks ──

;; `.` and `,` should run at every cursor: each cursor has its own
;; last-event snapshot, so they all replay independently.
(helixel-mc-mark-all-for-multi-cursors
 '(helixel-repeat-edit
   helixel-repeat-selection))

;; ── Atomic undo around mc dispatch ──
;;
;; Replace the post-command dispatcher with a wrapper that
;; amalgamates every fake-cursor execution into one undo step.

;; ── Substitute commands for fake-cursor dispatch ──
;;
;; Some commands prompt for input via `(interactive "c")' etc.
;; Re-running them at each fake cursor would re-read input.  Instead
;; we map them to a no-prompt substitute that uses the state the real
;; cursor's call already established.

;; Populate the substitute-alist defined in helixel-mc-core.el.
;; Original commands prompt for input via `(interactive "c")' etc.;
;; the substitute uses state already established by the real cursor.
(setq helixel-mc--fake-substitute-alist
      '((helixel-find-next-char      . helixel-find-repeat)
        (helixel-find-prev-char      . helixel-find-repeat)
        (helixel-find-till-char      . helixel-find-repeat)
        (helixel-find-prev-till-char . helixel-find-repeat)))

;; Mark all substitute commands as mc-friendly.
(declare-function helixel-find-repeat "helixel-search" ())

;; Find-char dispatch: substitute the prompting variants with the
;; non-prompting `helixel-find-repeat' at each fake cursor.  Each
;; `helixel-mc-defcmd' call also auto-marks the substitute as
;; mc-friendly.
(helixel-mc-defcmd helixel-find-next-char
  :substitute #'helixel-find-repeat)
(helixel-mc-defcmd helixel-find-prev-char
  :substitute #'helixel-find-repeat)
(helixel-mc-defcmd helixel-find-till-char
  :substitute #'helixel-find-repeat)
(helixel-mc-defcmd helixel-find-prev-till-char
  :substitute #'helixel-find-repeat)

;; ── Atomic undo around mc dispatch ──
;;
;; The dispatcher lives in helixel-mc-core.el as `helixel-mc--post-command'.


;; ── Chain end: broadcast the new chain tx ──

(defun helixel-mc--broadcast-last-event ()
  "Snapshot `helixel--last-event' into every fake cursor's overlay.
Call after building a new chain transaction so subsequent `.' at
each fake cursor replays the chain (not the pre-chain edit)."
  (dolist (ov (helixel-mc-all-cursors))
    (overlay-put ov 'helixel--last-event helixel--last-event)))

(defun helixel-mc--apply-chain-once ()
  "Execute `helixel--last-event' once at every fake cursor.
Assumes the current `helixel--last-event' is a chain transaction
\(or any replayable edit).  Wraps the batch in one undo step."
  (when (and helixel-multi-cursor-mode helixel--last-event)
    (let ((helixel-mc--inhibit t)
          (tx helixel--last-event))
      (undo-amalgamate-change-group
        (helixel-mc-with-each-cursor
          (let ((helixel--inhibit-repeat-record t))
            (helixel--execute-edit tx)))))))

(defun helixel-mc--chain-end-advice (&rest _)
  "After-advice on `helixel-repeat-chain-end'.
During chain recording, the per-command broadcast at
`post-command-hook' already applied every keystroke at every fake
cursor live, so the chain TX is just stored for later `.' replay
— we do NOT re-run it here (that would double the edit at each
fake).  We only emit the user-visible confirmation message,
broadcasting the new chain TX to fake cursors so a future `.' at
any fake replays the same chain."
  (when (and helixel-multi-cursor-mode
             helixel--last-event
             (eq (helixel-event-op helixel--last-event) 'chain))
    (helixel-mc--broadcast-last-event)
    (let ((n (length (helixel-mc-all-cursors))))
      (message "helixel-mc: chain recorded for %d fake cursor%s"
               n (if (= n 1) "" "s")))))

(advice-add 'helixel-repeat-chain-end :after
            #'helixel-mc--chain-end-advice)

;; ── Insert-state per-cursor pre-positioning ──
;;
;; The helixel-insert / -after / -beginning-line / -after-end-line /
;; -newline / -prevline commands are real-cursor-only (they call
;; `helixel--enter-insert' which we don't want to recurse).  Instead
;; we pre-position each fake cursor at insert-state entry so the
;; subsequent self-insert-command dispatches insert at the right place.
;;
;; Each insert-entry command declares its prepositioner via the
;; symbol property `helixel-mc-prepos':
;;
;;   (put 'my-insert-cmd 'helixel-mc-prepos #'my-prepos-fn)
;;
;; The fn runs once at each fake cursor (inside its restored
;; point/mark environment) and should leave point where the next
;; insertion should start.  No advice is registered — dispatch is
;; driven from `helixel-mc--post-command' (via
;; `helixel-mc--maybe-preposition' below).

(defun helixel-mc--prepos-region-begin ()
  "Move to region-begin if `mark-active', else stay."
  (when (and mark-active (mark t))
    (goto-char (min (point) (mark t))))
  (setq mark-active nil))

(defun helixel-mc--prepos-region-end ()
  "Move to `region-end' if `mark-active', else `forward-char'."
  (if (and mark-active (mark t))
      (goto-char (max (point) (mark t)))
    (unless (eolp) (forward-char)))
  (setq mark-active nil))

(defun helixel-mc--prepos-bol ()
  "Move to beginning of line at this fake cursor."
  (beginning-of-line))

(defun helixel-mc--prepos-eol ()
  "Move to end of line at this fake cursor."
  (end-of-line))

(defun helixel-mc--prepos-newline-after ()
  "Open a new line below this fake cursor (`o' semantics)."
  (end-of-line)
  (newline-and-indent))

(defun helixel-mc--prepos-newline-before ()
  "Open a new line above this fake cursor (`O' semantics)."
  (beginning-of-line)
  (let ((electric-indent-mode nil))
    (newline nil t)
    (forward-line -1)
    (indent-according-to-mode)))

;; Register prepositioners on each helixel insert-entry command.
(put 'helixel-insert               'helixel-mc-prepos
     #'helixel-mc--prepos-region-begin)
(put 'helixel-insert-after         'helixel-mc-prepos
     #'helixel-mc--prepos-region-end)
(put 'helixel-insert-beginning-line 'helixel-mc-prepos
     #'helixel-mc--prepos-bol)
(put 'helixel-insert-after-end-line 'helixel-mc-prepos
     #'helixel-mc--prepos-eol)
(put 'helixel-insert-newline       'helixel-mc-prepos
     #'helixel-mc--prepos-newline-after)
(put 'helixel-insert-prevline      'helixel-mc-prepos
     #'helixel-mc--prepos-newline-before)

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
(defun helixel-mc-apply-last-edit ()
  "Apply `helixel--last-event' once at every fake cursor.
Useful when you spawned cursors AFTER an edit and want to retro-
fit it onto the new positions.  Acts on the real cursor's
`helixel--last-event' so cursors all replay the SAME edit."
  (interactive)
  (unless (helixel-mc-any-p)
    (user-error "No fake cursors"))
  (unless helixel--last-event
    (user-error "No edit to apply"))
  (helixel-mc--broadcast-last-event)
  (helixel-mc--apply-chain-once))

;; Mark these helpers as real-cursor-only for safety.
(helixel-mc-mark-all-for-real-cursor-only
 '(helixel-mc-apply-last-edit))

;; ── ESC / quit clear-up ──

(defun helixel-mc--maybe-clear-on-quit ()
  "Clear fake cursors when `keyboard-quit' fires.
Wired into `helixel--clear-data' / `keyboard-quit' pipeline via
helixel-state advice (no extra hook required here)."
  (when helixel-multi-cursor-mode
    (helixel-mc-clear-all)))

(advice-add 'keyboard-quit :before #'helixel-mc--maybe-clear-on-quit)

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
        (let ((helixel-mc--inhibit t))
          (helixel-mc-with-each-cursor
            (set-marker (mark-marker) (point))
            (setq mark-active t))))
       ;; Leaving visual: deactivate each fake's mark.
       ((and (eq prev 'visual) (not (eq curr 'visual)))
        (let ((helixel-mc--inhibit t))
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

;; ── Replace-char (`R<char>') / surround-add (`ms<char>') per-cursor ──
;;
;; Both prompt for a delimiter / replacement char interactively.  If
;; broadcast naively, each fake re-prompts.  Strategy: mark real-only,
;; capture state in `:after' advice, replay at each fake's region.

(declare-function helixel--replace-region "helixel-editing"
                  (str beg end))
(declare-function helixel--surround-add "helixel-surround"
                  (open close))
(declare-function helixel-sel-surround-delimiter "helixel-core" (obj))
(declare-function helixel-delimiter-open "helixel-core" (d))
(declare-function helixel-delimiter-close "helixel-core" (d))

(defvar helixel-mc--last-replace-char nil
  "Char most recently used by `helixel-replace-char'.
Captured so fake cursors can replay the replacement without
re-prompting the user.")

(defun helixel-mc--replace-char-advice (char)
  "After-advice for `helixel-replace-char'.
Replays the replacement at every fake cursor's region (or point
when no region is active), using CHAR captured from the real-
cursor call."
  (setq helixel-mc--last-replace-char char)
  (when (and helixel-multi-cursor-mode (helixel-mc-any-p))
    (let ((helixel-mc--inhibit t))
      (helixel-mc-with-each-cursor
        (if (use-region-p)
            (helixel--replace-region
             (make-string (- (region-end) (region-beginning)) char)
             (region-beginning) (region-end))
          (helixel--replace-region
           (char-to-string char) (point) (1+ (point)))))
      (helixel-mc-dedupe-cursors))))

(advice-add 'helixel-replace-char :after
            #'helixel-mc--replace-char-advice)

(helixel-mc-mark-all-for-real-cursor-only '(helixel-replace-char))

(defvar helixel-mc--last-surround-pair nil
  "Last delimiter struct used by `helixel-surround-add'.
Captured so fake cursors can replay the surround without re-
prompting the user.")

(defun helixel-mc--surround-add-advice (&rest _)
  "After-advice for `helixel-surround-add'.
Replays the surround at every fake cursor's active region using
the delimiter pair the real cursor just used (read off the
pending selection).  Fakes without an active region are skipped."
  (let* ((sel helixel--pending-sel)
         (d (and sel (helixel-sel-surround-delimiter sel))))
    (when d
      (setq helixel-mc--last-surround-pair d)
      (when (and helixel-multi-cursor-mode (helixel-mc-any-p))
        (let* ((open  (helixel-delimiter-open d))
               (close (helixel-delimiter-close d))
               (helixel-mc--inhibit t))
          (helixel-mc-with-each-cursor
            (when (use-region-p)
              (helixel--surround-add open close)))
          (helixel-mc-dedupe-cursors))))))

(advice-add 'helixel-surround-add :after
            #'helixel-mc--surround-add-advice)

(helixel-mc-mark-all-for-real-cursor-only '(helixel-surround-add))

;; ── Surround-delete / surround-replace per-cursor (md / mr)
;;
;; `md' / `mr' have two execution paths:
;;   A) `helixel--pending-sel' already carries a delimiter at entry —
;;      the command performs the edit immediately.
;;   B) No delimiter — the command sets `helixel--pending-surround-op'
;;      and a transient map; user picks a textobj; the textobj's
;;      after-select hook re-invokes the surround command (which now
;;      takes path A).
;;
;; Both commands run only at the real cursor.  Each fake's
;; `helixel--pending-sel' was already populated by the broadcast of
;; the preceding textobj (in case B) or pre-existing (case A).  After
;; real finishes the edit-branch, replay the same surround command at
;; every fake.  Each fake's pending-sel drives its own delimiter
;; lookup via the delimiter's `:finder' (bounds re-derived at the
;; fake's point, so position shifts from earlier fakes' edits are
;; tolerated automatically).
;;
;; To distinguish the edit-branch (path A's actual run) from the
;; transient-setup branch (path B's first call), check
;; `helixel--pending-surround-op': SET => transient branch (skip);
;; nil => edit branch (broadcast).

(defvar helixel--pending-surround-op)   ; from `helixel-surround'
(declare-function helixel-surround-delete  "helixel-surround" ())
(declare-function helixel-surround-replace "helixel-surround" ())

(defun helixel-mc--surround-delete-advice (&rest _)
  "Replay `helixel-surround-delete' at each fake on edit branch.
When real took the edit branch (i.e. did not enter the transient
textobj wait), broadcast the delete to every fake whose pending
selection carries a surround delimiter."
  (when (and helixel-multi-cursor-mode
             (not helixel-mc--inhibit)
             (helixel-mc-any-p)
             (null helixel--pending-surround-op))
    (let ((helixel-mc--inhibit t))
      (helixel-mc-with-each-cursor
        (let* ((sel helixel--pending-sel)
               (d (and sel (helixel-sel-surround-delimiter sel))))
          (when d
            (ignore-errors (helixel-surround-delete)))))
      (helixel-mc-dedupe-cursors))))

(declare-function helixel--surround-replace-tag "helixel-surround"
                  (new-tag-name d))
(declare-function helixel--surround-delete-delimiter
                  "helixel-surround" (d))
(declare-function helixel--surround-lookup-delimiter
                  "helixel-surround" (char))

(defun helixel-mc--surround-replace-advice (&rest _)
  "Replay `helixel-surround-replace' at each fake on edit branch.
The replacement delimiter (char or tag) is read from the real-
side `helixel--last-event' payload so fakes do NOT re-prompt.
Each fake re-derives its OWN surrounding delimiter D from its
pending-sel and applies the same kind of substitution."
  (when (and helixel-multi-cursor-mode
             (not helixel-mc--inhibit)
             (helixel-mc-any-p)
             (null helixel--pending-surround-op)
             helixel--last-event)
    (let* ((new-char (helixel-event-payload-get helixel--last-event :new-char))
           (new-tag  (helixel-event-payload-get helixel--last-event :tag)))
      (when (or new-char new-tag)
        (let ((helixel-mc--inhibit t))
          (helixel-mc-with-each-cursor
            (let* ((sel helixel--pending-sel)
                   (d (and sel (helixel-sel-surround-delimiter sel))))
              (when d
                (ignore-errors
                  (cond
                   (new-tag
                    (helixel--surround-replace-tag new-tag d))
                   (new-char
                    (let ((new-d
                           (helixel--surround-lookup-delimiter
                            new-char)))
                      (when new-d
                        (helixel--surround-delete-delimiter d)
                        (helixel--surround-add
                         (helixel-delimiter-open new-d)
                         (helixel-delimiter-close new-d))))))))))
          (helixel-mc-dedupe-cursors))))))

(advice-add 'helixel-surround-delete :after
            #'helixel-mc--surround-delete-advice)
(advice-add 'helixel-surround-replace :after
            #'helixel-mc--surround-replace-advice)

(helixel-mc-mark-all-for-real-cursor-only
 '(helixel-surround-delete helixel-surround-replace))

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
;; `helixel--event-ring' / `--live-event' / `--action-pos').
;; When `;' broadcasts, each fake runs the SAME `helixel-action--
;; cycle-show' code path against its OWN ring — the first `;'
;; press selects the traversed span, subsequent presses cycle
;; the history, and group-start logic all work naturally with
;; no mc-specific bookkeeping.

(provide 'helixel-mc-integrate)
;;; helixel-mc-integrate.el ends here
