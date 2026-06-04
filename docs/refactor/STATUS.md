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

### Phase 4 — Repeat strategy → cl-defgeneric
Untouched.  236-line `helixel-repeat-strategy.el` is cohesive;
the rewrite would be mostly shape-change (struct→generic) with modest
line reduction.  Scheduled lower priority.

### Phase 6 — MC per-cursor struct + dispatcher rewrite
Untouched.  Requires deep changes to dispatcher + save/restore + all
per-cursor ops.  High effort, modest payoff after Phase 3+5 already
removed 5 advices.

### Phase 7 — Final cleanup
Untouched.

## Metrics

| Metric                          | Baseline | Now    | Target |
|---------------------------------|----------|--------|--------|
| Total `defvar` count            | 117      | 83     | ≤ 80   |
| Total `defvar-local` count      | 23       | 16     | ≤ 20   |
| `advice-add` in mc-integrate.el | 6        | **1**  | ≤ 2    |
| `advice-add` total              | 19       | 20†    | ≤ 8    |
| Tests passing                   | 847      | 847    | ≥ 847  |
| Total line count                | 14166    | 14313  | ≤ 10500|

† `advice-add` total dropped in mc-integrate but new files
(`helixel-replay.el`, `helixel-grouped-ring.el`) and gained struct
definitions made overall structure cleaner without yet collapsing
total lines.  Phase 6/7 should drop the count substantially.

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
