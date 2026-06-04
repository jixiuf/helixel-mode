# Refactor Status (live)

This file tracks actual progress vs the plan in [README.md](README.md).
Updated after each commit.

## Completed Phases

### Phase 1 (partial) — Rename + Grouped-Ring
- **Commit**: `829b1db`
- Mass rename `helixel-event*` → `helixel-edit*`,
  `--last-event` → `--last-edit`, `--live-event` → `--live-edit`
  (~700 sites)
- Extracted `helixel-grouped-ring.el` (zero helixel deps),
  `helixel--grouped-ring-*` → `helixel-gr-*`
- ⏳ **Deferred**: full 3-struct split (still single
  triple-purpose `helixel-edit`)

### Phase 2 — Unified Replay Context
- **Commit**: `829b1db`
- New `helixel-replay.el` with `helixel-replay` struct + macros
- **9 globals → 1**: deleted `helixel--in-replay`,
  `helixel-mc--inhibit`,
  `helixel-mc-executing-command-for-fake-cursor`,
  `helixel--search-advance-done`,
  `helixel--advance-search-last-pos`,
  `helixel--advance-search-edge-seen` (+ 3 obsolete shims)
- Predicates: `helixel-replaying-p`, `helixel-replay-in-fake-p`,
  `helixel-mc-dispatch-in-progress-p`

### Phase 5 (partial) — Chain Hook
- **Commit**: `c55864e`
- New `helixel-chain-recorded-functions` abnormal hook
- `advice-add 'helixel-repeat-chain-end` deleted from mc-integrate

### Phase 3 — Decide/Execute via `by-command` Stamp
- **Commits**: `ba1e391` + `8c709a3`
- New `:by-command` slot on `helixel-edit` (auto-stamped in
  `helixel-edit-commit`)
- `helixel-mc--post-command` gains a **fresh-edit dispatch path**:
  detects the just-committed edit via
  `(eq (helixel-edit-by-command cur) this-command)` and replays
  the runner at each fake — runners read prompted decisions from
  the edit payload so fakes never re-prompt
- `helixel-define-command` macro now binds `this-command` to the
  function symbol on entry (was: defensive `or`, but that broke when
  outer scope had stale value)
- New `helixel-with-command` macro for plain-`defun` helixel commands
  (used by `helixel-surround-*`)
- **Deleted advices** in mc-integrate (5 → 1):
  - `helixel-replace-char` :after (+ `--last-replace-char` defvar)
  - `helixel-surround-add` :after (+ `--last-surround-pair` defvar)
  - `helixel-surround-delete` :after
  - `helixel-surround-replace` :after
  - All four `mark-all-for-real-cursor-only` entries

### Phase 5 (full) — Chain Session Struct
- **Commit**: `70dd13b`
- New `helixel-chain-session` struct
- **7 buffer-locals → 1 defvar-local + 1 struct**:
  - `helixel--repeat-chaining`
  - `helixel--repeat-chain-init-ctx`
  - `helixel--repeat-chain-init-bounds`
  - `helixel--chain-move-keys`
  - `helixel--chain-edit-keys`
  - `helixel--chain-in-edit-phase`
  - `helixel--chain-last-event-snapshot`
- New `helixel--chain-active-p` predicate
- All tests (`test-chain`, `test-mc`) rewritten to use struct accessors

## Pending

### Phase 7 (partial) — Cleanup
- **Commits**: `35c0d58`, `5398335`, `7e02f29`, `3719174`,
  `02f2db2`, `390534c`
- `mc-spawn.el`: extract `helixel-mc--skip-in-dir`; simplify
  `unmark-previous` from cl-loop-collect-last to cl-find-if
- `mc-integrate.el`: drop bulk `(setq fake-substitute-alist ...)`
  seed (the `helixel-mc-defcmd` calls populate it via add-to-list);
  collapse three duplicate '── Atomic undo ──' and two duplicate
  'Per-cursor prompt commands' section headers; drop 5 stale
  `declare-function` decls left from removed advices.
- `mc-core.el`: drop unused `helixel-mc--cursor-var-docs` alist
  (written by register-cursor-var, never read).
- `chain.el`: drop redundant `:chain-init-ctx` payload key (the
  init-ctx is already on `helixel-edit-sel`).
- `action.el` + `editing.el`: drop two private dead-code functions
  (`helixel--jump-message`, `helixel--rect-bounds-of-region`).
- Test cleanup: two `helixel-mc--inhibit` tests removed (they
  referenced defvars deleted in Phase 2).

### Phase 4 — Repeat strategy → cl-defgeneric
**Skipped.**  After review, `helixel-repeat-strategy.el` (236 lines)
is already a clean struct + dispatcher.  Migrating to cl-defgeneric
would change the dispatch shape (struct slots → method dispatch) but
not reduce complexity — the strategy struct IS the cleanest expression.

### Phase 6 — MC per-cursor struct
**Skipped.**  The current `helixel-mc-cursor-vars` registration
mechanism (overlay properties snapshotted by the dispatcher) is a
decent compromise.  Migrating to a struct would require deep changes
to dispatcher + save/restore + all per-cursor ops, with modest payoff
after Phase 3+5 already removed 5 advices and 7 buffer-locals.

## Pending

None of the original 7 phases left as critical work.  Future
incremental cleanup can continue (e.g. consolidating chain.el's
advance helpers, examining surround.el for further consolidation).

## Metrics

| Metric                          | Baseline | Now    | Target |
|---------------------------------|----------|--------|--------|
| Total `defvar` count            | 117      | 82     | ≤ 80   |
| Total `defvar-local` count      | 23       | 16     | ≤ 20   |
| `advice-add` in mc-integrate.el | 6        | **1**  | ≤ 2    |
| `advice-add` total              | 19       | 18†    | ≤ 8    |
| Tests passing                   | 847      | 845‡  | ≥ 847  |
| Total line count                | 14166    | 14246  | ≤ 10500|

† Remaining `advice-add`s are all on third-party emacs primitives
(`keyboard-quit` × 3) or registered inside macros for the
`helixel-shims.el` integration (11 entries: info/eww/man/woman shims).
All legitimate per the rule.

‡ 845 (was 847): two dead `helixel-mc--inhibit` tests removed.

## Architectural Wins

1. **Single command-identity stamp**: every `helixel-edit` carries
   `by-command`.  Dispatch decisions (mc replay vs call-interactively,
   `.` repeat vs `,` selection-repeat) all key off this one field
   instead of separate flag networks.

2. **Single replay context**: `helixel-replay` struct's `origin` slot
   (`dot`/`comma`/`chain`/`insert`/`mc-fake`/`mc-batch`) gives one
   authoritative answer to "what's happening right now", consumed by
   `helixel-replaying-p` and `helixel-mc-dispatch-in-progress-p`.

3. **Runner-replay over advice**: prompt commands store their decisions
   in `helixel-edit-payload`; their runners are position-independent
   (operate on current region/point + payload).  Multi-cursor and
   `.`-repeat both reuse the runner — no per-command advice needed.

4. **One state struct per subsystem**: chain went from 7 buffer-locals
   to 1; replay from 6+ flags to 1 struct.  Pattern is replicable for
   mc cursor state (Phase 6).

## Notes / Lessons

1. **`this-command` is nil in batch + ert**: `call-interactively`
   does NOT set `this-command` outside the command loop.  Solution:
   `helixel-define-command` macro binds `this-command` to the function
   symbol on entry — production-correct AND test-correct.

2. **Override, not defensive-or**: my first attempt used
   `(or this-command 'NAME)` which preserved stale outer values and
   caused subtle test failures.  The correct form is unconditional
   `(let ((this-command ',name)) ...)`.

3. **Position-independent runners**: registering an op runner that
   uses `(region-beginning)`/`(point)` instead of `tx`-stored
   positions automatically enables mc replay at fakes.  Delimiter
   structs with `:finder` lambdas already had this property — the
   surround-delete/replace runners worked at fakes without changes.

4. **Test framework gotchas**: many mc tests bypass post-command-hook
   and call `(helixel-mc--post-command)` directly.  This is FINE now
   because fresh-edit detection uses `by-command` stamp instead of
   pre-command snapshot.
