# Refactor Status (live)

This file tracks actual progress vs the plan in [README.md](README.md).
Updated after each commit.

## Completed

### Phase 1 (partial) — Rename + Grouped-Ring
- **Commit**: `829b1db` (combined with Phase 2)
- ✅ Mass rename `helixel-event*` → `helixel-edit*`,
  `--last-event` → `--last-edit`, `--live-event` → `--live-edit`
  (~700 sites across 29 files)
- ✅ Extracted `helixel-grouped-ring.el` (5 query primitives,
  zero helixel deps); `helixel--grouped-ring-*` → `helixel-gr-*`
- ⏳ Deferred: full 3-struct split (`helixel-edit` vs
  `helixel-history-entry` vs `helixel-jump-mark`).  The struct is still
  triple-purpose; rename alone gave the clarity win without the risk.

### Phase 2 — Unified Replay Context
- **Commit**: `829b1db`
- ✅ New `helixel-replay.el` with `helixel-replay` struct (origin +
  fake-cursor + edit + reverse-p + 3 search-advance scratch fields)
  and `helixel-with-replay` / `helixel-with-replay-as` macros
- ✅ Deleted globals (was 9 dynvars):
  - `helixel--in-replay`
  - `helixel-mc--inhibit`
  - `helixel-mc-executing-command-for-fake-cursor`
  - `helixel--search-advance-done`
  - `helixel--advance-search-last-pos`
  - `helixel--advance-search-edge-seen`
- ✅ Now 1 dynvar (`helixel--replay`) plus ctx fields
- ✅ Predicates: `helixel-replaying-p` (dot/comma/chain/insert),
  `helixel-replay-in-fake-p`, `helixel-mc-dispatch-in-progress-p`,
  `helixel-search-advance-*-p/-set`
- ⏳ Deferred: deleting the legacy `helixel-with-replay-context` macro
  alias (still used by 4 call sites; trivial follow-up)

### Phase 5 (partial) — Chain Hook
- **Commit**: `c55864e`
- ✅ New `helixel-chain-recorded-functions` abnormal hook in
  `helixel-chain.el`, fired with the new chain TX
- ✅ `helixel-mc--on-chain-recorded` registered on that hook;
  `advice-add 'helixel-repeat-chain-end` deleted
- ✅ Confirms principle #3: helixel-self advice forbidden

## Pending

### Phase 3 — decide/execute split  (BLOCKED on design)
**Status**: First attempt reverted.  The "edit-replay dispatch at fakes"
idea is correct, but `fresh-edit` detection via
`pre-command-hook` snapshot breaks the 5+ tests that call
`(helixel-mc--post-command)` directly without firing pre-hook.

**Design fix needed**: stamp each `helixel-edit` with a command-counter
(or `this-command-keys` hash) at record time so detection works even
when pre-hook is bypassed.  Then the dispatcher can choose between
"replay edit at fake" vs "call-interactively at fake" without needing
pre-snapshot.

Once fixed, this unlocks deletion of:
- `helixel-mc--replace-char-advice` + `--last-replace-char` defvar
- `helixel-mc--surround-add-advice` + `--last-surround-pair` defvar
- `helixel-mc--surround-delete-advice`
- `helixel-mc--surround-replace-advice`
- `helixel-mc--fake-substitute-alist` (find-char substitutes)

### Phase 4 — Repeat strategy → cl-defgeneric
Untouched.  Independent of Phase 3.

### Phase 5 (remainder) — Chain state struct
Untouched.  The hook part is done; the 7 buffer-local → 1 struct
collapse is independent.

### Phase 6 — MC per-cursor struct + dispatcher cleanup
Untouched.  Depends on Phase 3 to delete the advice net.

### Phase 7 — Final cleanup
Untouched.

## Metrics (current vs target)

| Metric                         | Baseline | Now    | Target |
|--------------------------------|----------|--------|--------|
| Total `defvar` count           | 117      | 111    | ≤ 80   |
| Total `defvar-local` count     | 23       | 22     | ≤ 20   |
| `advice-add` in mc-integrate   | 6        | 5      | 0      |
| `advice-add` total             | 19       | 19     | ≤ 8    |
| Tests passing                  | 847      | 847    | ≥ 847  |
| Total line count               | 14166    | ~14200 | ≤ 10500|

Total lines went up slightly because we added new modules
(`helixel-replay.el`, `helixel-grouped-ring.el`) without yet deleting
the old code those replaced.  Phase 3-6 should drop the count substantially.

## Notes / Lessons

1. **Test framework gotcha**: many mc tests bypass
   `pre-command-hook` / `post-command-hook` and call dispatch
   functions directly.  Any new mechanism that relies on the full
   command loop must either (a) have an in-band detection that doesn't
   need pre-hook, or (b) update tests to manually invoke pre-hook.

2. **Replay-ctx subtlety**: the predicate `helixel-replaying-p` does
   NOT include `mc-fake` / `mc-batch` origins, because at fakes we
   WANT recording to happen into the fake's own ring.  Only
   `dot` / `comma` / `chain` / `insert` count as "true replay".
   `helixel-mc-dispatch-in-progress-p` is the predicate for the mc
   guards (covers both mc origins).

3. **Paren-counting after sed**: when sed-replacing
   `(let ((x y))` → `(macro arg`, both have net +1 opens so balance is
   preserved.  But multi-binding lets (`(let ((a b) (x y))`) break
   under naive sed — those needed manual edits.  See commit `829b1db`
   for the manual fixes around `mc-integrate.el:466,470`.
