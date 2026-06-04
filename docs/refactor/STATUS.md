# Refactor Status (live)

This file tracks actual progress vs the plan in [README.md](README.md).
Updated after each commit.

## Completed Phases

### Phase 1 (partial) — Rename + Grouped-Ring
- **Commit**: `829b1db`
- Mass rename `helixel-event*` → `helixel-edit*`,
  `--last-event` → `--last-edit`, `--live-event` → `--live-edit`
  (~700 sites).
- Extracted `helixel-grouped-ring.el` (zero helixel deps),
  `helixel--grouped-ring-*` → `helixel-gr-*`.
- ⏳ **Deferred**: full 3-struct split (still single triple-purpose
  `helixel-edit`; in practice the unified struct works and the cost
  of splitting outweighs the clarity win).

### Phase 2 — Unified Replay Context
- **Commit**: `829b1db`
- New `helixel-replay.el` with `helixel-replay` struct + macros.
- **9 globals → 1**: deleted `helixel--in-replay`,
  `helixel-mc--inhibit`,
  `helixel-mc-executing-command-for-fake-cursor`,
  `helixel--search-advance-done`,
  `helixel--advance-search-last-pos`,
  `helixel--advance-search-edge-seen` (+ 3 obsolete shims).
- Predicates: `helixel-replaying-p`, `helixel-replay-in-fake-p`,
  `helixel-mc-dispatch-in-progress-p`.

### Phase 3 — Decide/Execute via `by-command` Stamp
- **Commits**: `ba1e391` + `8c709a3`
- New `:by-command` slot on `helixel-edit` (auto-stamped in
  `helixel-edit-commit`).
- `helixel-mc--post-command` gains a **fresh-edit dispatch path**:
  detects the just-committed edit via
  `(eq (helixel-edit-by-command cur) this-command)` and replays
  the runner at each fake — runners read prompted decisions from
  the edit payload so fakes never re-prompt.
- `helixel-define-command` macro binds `this-command` to the
  function symbol on entry.
- New `helixel-with-command` macro for plain-`defun` helixel commands.
- **Deleted 5 advices** in mc-integrate (6 → 1):
  - `helixel-replace-char` :after (+ `--last-replace-char` defvar)
  - `helixel-surround-add` :after (+ `--last-surround-pair` defvar)
  - `helixel-surround-delete` :after
  - `helixel-surround-replace` :after

### Phase 5 (hook) — Chain Recorded Hook
- **Commit**: `c55864e`
- New `helixel-chain-recorded-functions` abnormal hook.
- `advice-add 'helixel-repeat-chain-end` deleted from mc-integrate.

### Phase 5 (full) — Chain Session Struct
- **Commit**: `70dd13b`
- New `helixel-chain-session` struct.
- **7 buffer-locals → 1 defvar-local + 1 struct**:
  - `helixel--repeat-chaining`
  - `helixel--repeat-chain-init-ctx`
  - `helixel--repeat-chain-init-bounds`
  - `helixel--chain-move-keys`
  - `helixel--chain-edit-keys`
  - `helixel--chain-in-edit-phase`
  - `helixel--chain-last-event-snapshot`
- New `helixel--chain-active-p` predicate.
- All tests rewritten to use struct accessors.

### Phase 7 — Consolidation (3 waves) + Naming + Dead Code

**Wave 1** (commits `35c0d58`, `5398335`, `7e02f29`, `3719174`,
`02f2db2`, `390534c`): mc-spawn dedupe, drop bulk seed, drop
duplicate section headers, drop 5 stale `declare-function`, drop
`helixel-mc--cursor-var-docs`, drop redundant `:chain-init-ctx`
payload, drop 2 dead private fns (`helixel--jump-message`,
`helixel--rect-bounds-of-region`).  Test cleanup: 2 stale tests
removed.

**Wave 2** (commits `646a7c8`, `514e428`, `34ceb45`, `c65a9c7`,
`238894c`, `533faca`, `c916589`, `aa6b8ae`, `79085ba`, `a534b27`,
`1268c8b`):
- `editing.el`: merge insert-after search/line branches; extract
  `helixel--replace-do`; share `helixel--yank-body` /
  `helixel--indent-body`; collapse downcase/upcase via
  `helixel--def-case-op` macro.
- `search.el`: extract `helixel-search--find-char-jump`; collapse
  4 find-char wrappers via `helixel--def-find-char` macro.
- `move.el`: 24 forward/backward × word/WORD/symbol/paragraph/
  sentence/function commands → `helixel--def-thing-move` macro
  (198 lines → 36 one-liners).
- `core.el`: 18 `helixel-sel-*-ctx` accessors → `helixel--def-sel-accessor`
  macro; 7 `helixel--kind-*` registry accessors → `helixel--def-kind-accessor`.
- `surround.el`: extract `helixel--surround-prompt-target` shared by
  delete/replace.

**Wave 3** (commits `22e2d4a`, `6858e66`, `c2be229`, `8f25c19`,
`4e93231`, `a0c6042`, `a0040d2`, `1fb969e`, `9539b48`, `afd309d`,
`582727c`, `ce225b3`):
- `keymap.el`: 4 bracket-prefix keymaps (`]`/`[`/`}`/`{`) and 2 inner/
  outer textobj maps unified via tables; 10 digit-arg bindings →
  `dotimes`; 12 org-mode emphasis textobj bindings → `pcase-dolist`.
- `textobj-marks.el`: drop INNER-P arg from `define-mark-pair` /
  `-mark-quote`; each entry registers inner+a in one call.
- `mc-integrate.el`: 6 `(put 'helixel-insert-* ...)` registrations
  → `pcase-dolist`.
- `state.el`: 4 `(helixel-define-jump-command ...)` → `dolist`;
  drop unused `helixel--rect-replay-set`.
- `move.el`: drop dead `:advice` branch in `helixel-define-movement`
  (eliminates one of the rule-violating `advice-add` calls).
- `state.el`: centralise keyboard-quit advice via new abnormal hook
  `helixel-keyboard-quit-functions` — 3 scattered `advice-add` calls
  (search.el, mc-integrate.el, state.el ×2) → 1 in state.el.
- **Dead-code sweep**: removed 6 dead functions across action.el,
  chain.el, core.el, mc-integrate.el, move.el, state.el
  (`helixel--jump-display`, `helixel--chain-preview-strategy`,
  `helixel-edit-equal-p`, `helixel-mc--repeat-edit-hook-uninstall`,
  `helixel--commit-pending-event`, `helixel-surround-thing-at-point`).

## Skipped Phases

### Phase 4 — Repeat strategy → cl-defgeneric  (SKIPPED)
After review, `helixel-repeat-strategy.el` is already a clean struct +
dispatcher.  Migrating to `cl-defgeneric` would change the dispatch
shape (struct slots → method dispatch) but not reduce complexity.

### Phase 6 — MC per-cursor struct  (SKIPPED)
The current `helixel-mc-cursor-vars` mechanism (overlay properties
snapshotted by the dispatcher) is acceptable.  A struct migration
would require deep changes to dispatcher + save/restore + every
per-cursor op, with modest payoff after Phase 3+5 already removed
5 advices and 7 buffer-locals.

## Pending / Open

- **3-struct split** (Phase 1 deferred): `helixel-edit` still plays
  three roles (edit descriptor, history entry, jump mark).  Splitting
  would be a sweeping mechanical change with limited semantic gain;
  consider only if a third subsystem starts demanding edit metadata
  the unified struct can't carry cleanly.
- `helixel-action.el` still has one `advice-add` (advising third-party
  `xref-find-*` / `eglot-find-*` via `helixel-define-jump-command`).
  Functionally a shim; could move into `helixel-shims.el` if strict
  rule compliance is required.

## Metrics

| Metric                          | Baseline | Now    | Target |
|---------------------------------|----------|--------|--------|
| Total `defvar` count            | 117      | 82     | ≤ 80   |
| Total `defvar-local` count      | 23       | 16     | ≤ 20   |
| `advice-add` in mc-integrate.el | 6        | **0**  | ≤ 2    |
| `advice-add` total              | 19       | **12** | ≤ 8    |
| Tests passing                   | 847      | 845†   | ≥ 847  |
| Total line count                | 14166    | **13859** | ≤ 10500 |

† 845 = 847 baseline − 2 stale `helixel-mc--inhibit` tests removed
in Phase 2.

Remaining `advice-add` breakdown:
- `helixel-shims.el` ×10 (legitimate third-party shims:
  info/help-mode/shortdoc/man/woman/eww)
- `helixel-state.el` ×1 (the keyboard-quit fan-out advice)
- `helixel-action.el` ×1 (`helixel-define-jump-command` ⇒ third-party
  xref/eglot — see "Pending" above)

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
   to 1; replay from 6+ flags to 1 struct.
5. **Single keyboard-quit entry point**: 4 scattered advices collapsed
   to one (state.el) + an abnormal hook
   `helixel-keyboard-quit-functions`.

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
   positions automatically enables mc replay at fakes.
4. **Test framework gotchas**: many mc tests bypass post-command-hook
   and call `(helixel-mc--post-command)` directly.  This is FINE
   because fresh-edit detection uses `by-command` stamp instead of
   pre-command snapshot.
5. **Indirect references break naive dead-code grep**: text-objects
   instantiate function symbols via `(intern (format "helixel--%s" sym))`,
   so a literal grep for `helixel--forward-end` finds zero hits even
   though the macro emits it.  Always recompile after a delete; the
   byte-compiler catches what grep misses.
6. **Load-time advices for tests**: registering `keyboard-quit` advice
   inside `helixel-mode` toggle breaks tests that exercise mc/search
   without enabling helixel-mode globally.  Top-level advice with
   per-fn gates inside is more test-robust.
