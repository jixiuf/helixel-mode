# helixel-mode Architecture

> File map, dep graph, structs, and APIs are in project root `AGENTS.md`.

---

## Core Modules

| Module | Role |
|--------|------|
| `helixel-core.el` | Pure data layer: structs, registries, delimiter protocol, tx helpers, replay context, named registers |
| `helixel-ring.el` | Event storage: ring + jump-log + tracking-open + live-event |
| `helixel-macros.el` | Command/operator definition macros |

---

## Data Layer (`helixel-core.el`)

### Three Structs

| Struct | Role | Mutable? |
|--------|------|----------|
| `helixel-sel` | Selection descriptor (kind + ctx + recreate closure) | Immutable (copy on update) |
| `helixel-tx` | Replay transaction (op + sel + payload + runner + display) | `helixel--last-tx` is the latest tx, mutable cell |
| `helixel-action` | Ring/jump-log event (category + subcat + by-command + optional embedded `tx`) | Immutable after commit |

Phase 4.1 split: `helixel-tx` carries everything needed to re-execute
an edit (Pass 1).  `helixel-action` wraps it with history metadata
(Pass 2).  Polymorphic helpers (`helixel-action-op`, `-sel`,
`-payload`, `-runner`) accept either struct — on a tx they read
directly, on an action they delegate to its embedded `tx`.

### Kind Registry

Centralizes per-kind protocol. Each kind (line, rect, search, movement, textobj, insert-*) registers:

```
:recreate      fn(ctx) → nil        recreate selection at point
:advance       fn(edit) → t|nil     move to next target, return t on success
:display       fn(ctx) → string     display string for history
:all-buffer-fn fn(edit prefix) → nil  custom all-buffer scan (line, search)
:all-dir-fn    fn(edit) → nil         custom all-dir scan (line)
```

Access: `(helixel--kind-advance 'line)`, `(helixel--kind-all-buffer-fn 'search)`, etc.

### Operator Registry

Centralizes per-operator protocol:

```
:runner            fn(tx) → nil      execute edit at replay time
:display           string|fn         display string for history
:moves-point-p    boolean           t = op self-advances, no auto-advance
:strategy-builder  fn(edit rev) → strategy  custom strategy (chain)
```

Access: `(helixel--op-runner 'kill)`, `(helixel--op-moves-point-p 'insert-text)`, etc.

---

## Event Ring (`helixel-ring.el`)

### Two Containers, One Event Type

| Ring | Scope | Purpose | Key |
|------|-------|---------|-----|
| `helixel--event-ring` | buffer-local | `;` cycling, dot-repeat picker | C-g |
| `helixel--jump-list` | global | C-o/C-i jump navigation | C-o |

Both store `helixel-action` structs. The jump-list stores a subset of ring events (filtered by `helixel-jump-categories`).

### Commit Pipeline

```
Editing command
  → helixel--record-action (creates an event tx, stores as helixel--last-tx)
  → helixel-action-commit
    → stamp :by-command
    → push to helixel--event-ring (dedup, cap)
    → push to helixel--jump-list (filtered)
    → run helixel-action-commit-hook (entry)   ; chain accumulator
```

`helixel-action-commit-hook` is an abnormal hook called with the
committed entry.  It is the sole integration point for cross-cutting
observers — chain (`helixel-chain.el`) hooks into it to append the
committed tx onto the chain session's `:tx-list`.  Adding new
observers should not require touching ring or commit code.

### Dedup

Events are deduplicated by content: same op, category, subcat, sel, payload, and marker position → skip push. Cancel sentinels (C-g) create dedup boundaries.

---

## Repeat Engine

### Strategy Struct

```elisp
(cl-defstruct helixel-repeat-strategy
  advance        ;; fn(edit) → t|nil   next target
  apply          ;; fn(edit) → nil     execute edit
  reset          ;; fn(edit) → nil     goto marker (all-buffer)
  all-buffer-fn  ;; fn(edit prefix) → nil   custom all-buffer (or nil)
  all-dir-fn     ;; fn(edit) → nil          custom all-dir (or nil))
```

### Strategy Builder

`helixel--build-strategy(edit, reverse-p)` → strategy:

1. Check op registry for custom `:strategy-builder` (chain uses this)
2. Fall back to `helixel--default-strategy-builder`:
   - Read kind from sel, advance-fn from kind registry
   - Check `:moves-point-p` flag from op registry (t → no auto-advance)
   - Handle `reverse-p` by creating reversed-edit copy
   - Set `:all-buffer-fn` and `:all-dir-fn` from kind registry

### `.` Dispatch (4 branches)

```
helixel-repeat-edit
  ├── :all-buffer  → helixel--repeat-all-buffer(strategy, tx, prefix)
  │                    ├── all-buffer-fn set? → delegate
  │                    └── else: reset → scan from point-min
  ├── :all-dir     → helixel--repeat-all-dir(strategy, tx)
  │                    ├── all-dir-fn set? → delegate
  │                    └── else: advance+apply loop
  ├── :n-times     → helixel--repeat-n (or execute directly if preview)
  └── :preview     → execute once at current position
```

---

## Repeat Edit (`.`)

### Recording

`helixel--record-action(op, &rest extra)`:
1. Pop pending sel via `helixel--sel-pop`
2. Look up runner from op registry
3. Create event tx via `helixel-tx-create`
4. Store as `helixel--last-tx`
5. Commit event via `helixel-action-commit`

### Insert Recording (Phase 4.4)

Insert-mode commands are captured as a list of **segments** via
`after-change-functions` + `pre-command-hook` / `post-command-hook`:

- `(:keys VEC)` — command did not modify the buffer (motion, no-op).
  Replay via `execute-kbd-macro`.
- `(:text STR :delete-before N :offset O)` — command modified the
  buffer.  STR is the post-state text in the change span; N is
  characters to delete BEFORE the insertion point at replay (for
  completion-style replace); O is the offset from end-of-insertion to
  final point (e.g. `-1` for `electric-pair-mode' `()`).

Replay for `:text` segments uses `delete-char` + `insert` +
`goto-char` directly — it does NOT re-fire `post-self-insert-hook`,
so `electric-pair-mode`, snippet expansion, and completion
providers never double-trigger on replay.  `helixel--execute-keys`
accepts a segment list, a raw key vector, or a kbd string.

### Line Advance

`helixel--repeat-advance-line(tx)`:
- Moves `forward-line` by selection count in sel's direction
- Skips blank lines
- For `:entry-kind append`: advances 1 line
- After advancing: calls `(deactivate-mark)` then `helixel--recreate-selection` to position point (bol for insert, eol for append)

### Search Advance

`helixel--repeat-advance-search(tx)`:
- Skips past current match (if entry-kind present)
- Searches for next match in sel's direction
- Guards against zero-width patterns (`$`, `^`) at buffer edges via `helixel--advance-search-edge-seen`
- Guards against repeated matches at same position via `helixel--advance-search-last-pos`
- Calls `helixel--recreate-selection` to position cursor

### All-Buffer Handlers

- **Line**: `helixel--all-buffer-line` — forward+backward pass from marker using `helixel--repeat-line-pass`
- **Search**: `helixel--all-buffer-search` — entry-kind: text insertion at every match; non-entry-kind: force-dir scan
- **Other kinds**: generic advance+apply scan from point-min

### All-Dir Handler

- **Line**: `helixel--all-dir-line` — uses `helixel--repeat-line-pass` from current position
- **Other kinds**: generic advance+apply loop

---

## Chain (`helixel-chain.el`)

Chain records a compound operation (any sequence of motions + edits)
as a single repeatable unit.  Phase 4.4 reworked chain to be a
list-of-txs rather than a kmacro recorder.

### Lifecycle

1. `helixel-repeat-chain-start` — snapshot pending sel + bounds;
   set session active; `helixel-action-commit-hook` becomes the
   accumulator.
2. Each helixel command commits an action via
   `helixel-action-commit`; if the action's tx has a runner AND the
   by-command is not in the chain-control set
   (chain-start / -end / -cancel / normal-escape), the tx is appended
   to `helixel-chain-session-tx-list`.
3. `helixel-repeat-chain-end` — finalize: merge init-ctx into a
   chain tx with op=`chain`, payload `:tx-list LIST`; runner
   iterates LIST and replays each sub-tx; broadcast to fake cursors
   via `helixel-chain-recorded-functions`.
4. `.` replays via custom `:strategy-builder` registered for `chain`:
   - Advance: kind's `advance-fn`
   - Apply: `helixel--repeat-chain-runner` iterates `:tx-list`

### Why list-of-txs (vs kmacro)

Every helixel command already produces a `helixel-tx` (Phase 4.3),
and each tx is fully position-agnostic with its own runner.  Chain
just collects them; replay just dispatches each in order.  No
`execute-kbd-macro`, no separate move-keys / edit-keys phases, no
key-capture pre-command-hook.  Result in Phase 4.4: chain session
struct shrank from 7 slots to 4, and per-cursor chain replay reuses
the same `helixel-tx-replay` path as `.`-repeat on a single fake.

---

## Search (`helixel-search.el`)

### Active Search State

`helixel--active-search` is the single mutable search state (replaces the old 3-location direction storage):

```elisp
(:category search|find-char :pattern PAT :dir forward|backward [:type TYPE :char CHAR])
```

- `n` reads direction from active-search
- `N` flips direction in active-search
- `.` replay uses direction from event's sel (immutable snapshot)
- History selection copies direction to active-search

---

## Action Tracking (`helixel-ring.el`)

### `;` Cycling

Uses `helixel--event-ring`. Group-skipping: consecutive entries with same (category, subcat) form a group; `;` jumps to the oldest entry of each group.

### C-o/C-i Jump Navigation

Uses `helixel--jump-list` (global). Same group-skipping algorithm as `;`, with buffer identity included in grouping.

### Bridge Functions

Removed in Phase 3.  `helixel--tracking-open` in `helixel-ring.el`
is the single entry point; no bridge functions needed.

---

## Command Definition (`helixel-macros.el`)

### `helixel--tracking-open` (unified entry)

```elisp
(defun helixel--tracking-open (category subcat &optional op))
```

Single function for opening a tracking event: commits the previous
live-event and creates a new one.  Used by all three command-definition
paths: `helixel-define-command`, `helixel-define-operator`, and
`helixel-with-action-tracking`.

### `helixel-define-command`

Defines a helixel command.  Expands to a `defun` that calls
`helixel--tracking-open`, then auto-injects:
- `helixel--clear-highlights` — for movement commands
- `helixel--track-visual-move` — visual-mode `.` support

### `helixel-define-operator`

Like `helixel-define-command` but also registers the operator via
`helixel-register-op` for `.` repeat.

### `helixel-with-action-tracking`

For self-contained commands (chain).  Wraps body in
`helixel--tracking-open` + `unwind-protect` commit.

---

## File Dependency Graph

```
helixel-core (cl-lib only; includes replay context + named registers)
  ├── helixel-ring (→ core)
  │     ├── helixel-macros (→ core + ring)
  │     └── helixel-action (→ core + ring)
  │
  ├── helixel-repeat (→ core + action)
  │     └── helixel-chain (→ core + repeat + macros)
  │
  ├── helixel-textobj (→ core)
  │     └── helixel-surround (→ core + ring + repeat + textobj)
  │
  └── helixel-state (→ core + ring + macros + action
                      + repeat + textobj + surround)
        ├── helixel-move (→ state + macros)
        ├── helixel-editing (→ state + move + core + macros + search)
        │     ├── helixel-search (→ state + core + macros + repeat + move)
        │     ├── helixel-keymap (→ state + move + editing
        │     │                   + chain + surround + swap + search)
        │     └── helixel-swap (→ state + macros + editing)
        └── helixel-shims (→ state + keymap)
```

## Key Shared Variables

| Variable | Location | Purpose |
|----------|----------|---------|
| `helixel--pending-sel` | `helixel-core.el` | Pending selection descriptor |
| `helixel--last-tx` | `helixel-core.el` | Most recent edit transaction |
| `helixel--live-action` | `helixel-ring.el` | Current in-progress event |
| `helixel--active-search` | `helixel-search.el` | Active search direction+pattern |

---

## Test Architecture

852 ERT tests across 17 test files.  Key conventions:

- `(helixel-test-with-buffer "content" body...)` — creates temp buffer with `transient-mark-mode 1`
- Set `last-command` and `this-command` before calling selection/edit functions
- For dot-repeat tests: build tx with `helixel-tx-create` and set `helixel--last-tx`
- For chain tests: use `helixel-chain--make-test-tx` helper
- Max 12s timeout per test run; zero hangs expected

---

## Dot-Repeat (`.`) End-to-End Data Flow

When the user presses `.` (bound to `helixel-repeat-edit`), here is the
complete flow through the module graph:

```
User presses `.`
  │
  ▼
helixel-repeat.el:helixel-repeat-edit
  ├── Resolves helixel--last-tx (global, cross-buffer)
  ├── Decodes prefix via helixel-repeat-prefix struct (in core.el)
  │
  ▼
helixel-repeat.el:helixel--build-strategy(edit, reverse-p)
  ├── Checks op registry for :strategy-builder (chain uses this)
  ├── Falls back to helixel--default-strategy-builder:
  │     ├── Reads :moves-point-p flag from op registry
  │     │     (nil=no advance, 'line=line-advance, fn=custom)
  │     ├── Reads :advance/:recreate from kind registry
  │     └── Reads :all-buffer-fn/:all-dir-fn from kind registry
  │
  ▼
helixel-repeat.el:advance+apply loop (with helixel-with-replay-as 'dot)
  ├── Advance: recreate sel at next target
  │     ├── helixel-core.el:helixel-sel-call-recreate → struct closure
  │     └── (recreate functions live in helixel-move.el,
  │          helixel-search.el, helixel-textobj.el)
  │
  ├── Apply: execute edit at current position
  │     ├── helixel-core.el:helixel-tx-replay(tx)
  │     │     └── calls helixel-action-runner(tx) — closure stored at record time
  │     └── (runners live in helixel-editing.el, registered via
  │          helixel-register-op / helixel-define-operator)
  │
  └── All-buffer/all-dir: scan from point-min or marker
        └── kind-specific handlers from helixel-repeat.el
              (line:line-pass, search:inline scan, others:generic loop)
```

Key invariants:
- Both `helixel--inhibit-repeat-record` and `helixel--inhibit-action-track`
  are bound to t during replay (via `helixel-with-replay-as').
- `helixel--last-tx` is NOT buffer-local — `.` replays cross-buffer.
- The runner closure stored in the event struct was captured at record time
  from the op registry, so replay never queries the registry.
- All iterations within a single `.` press are wrapped in one undo step.

---

## Design Invariants (from refactor)

These are load-bearing decisions that the codebase actively depends on
— change them only with full-suite testing.

1. **Single command-identity stamp.**  Every `helixel-action` carries
   `:by-command` (auto-stamped in `helixel-action-commit`).  Dispatch
   decisions — mc fresh-edit replay vs `call-interactively`, `.` vs
   `,` — all key off this one field instead of separate flag
   networks.

2. **Single replay context.**  The `helixel-replay` struct's `origin`
   slot (`dot` / `comma` / `chain` / `insert` / `mc-fake` /
   `mc-batch`) is the one authoritative answer to "what's happening
   right now", consumed by `helixel-replaying-p` and
   `helixel-mc-dispatch-in-progress-p`.  Do not reintroduce
   per-feature inhibit flags.

3. **Runner-replay over advice.**  Prompt commands store their
   decisions in `helixel-action-payload`; runners are
   position-independent (operate on current region/point + payload).
   Multi-cursor and `.`-repeat both reuse the runner — no per-command
   `advice-add` needed.

4. **One state struct per subsystem.**  Chain went from 7
   buffer-locals to 1 (`helixel-chain-session`); replay from 6+ flags
   to 1 struct (`helixel-replay`).  New per-subsystem state must
   follow this pattern.

5. **Single keyboard-quit entry point.**  Modules contribute to
   `helixel-keyboard-quit-functions` (abnormal hook); only one
   `advice-add` on `keyboard-quit` lives in `helixel-state.el`.
   Never advise `keyboard-quit` from another module.

## Decisions Considered and Rejected

These alternatives were proposed during architectural review and
explicitly rejected.  Documented so future contributors do not
re-litigate them without new evidence.

### 1. Merge `helixel-tx` into `helixel-action` — REJECTED

Proposal: collapse the two structs into one 11-slot struct, eliminating
~56 LOC of polymorphic accessors.

Why rejected:
- The split encodes two genuine domains: **history** (ring, `;`,
  C-o/C-i, consumed by `helixel-ring` + jump-log) and **replay**
  (`.`, `,`, chain, mc, consumed by `helixel-repeat` + `helixel-chain`
  + `helixel-mc-*`).  Most callsites operate in ONE domain.
- Polymorphic accessors are a BRIDGE at the ~67 sites where the two
  domains genuinely overlap, not a tax at every call site.  The other
  ~150 callsites use `helixel-tx-*` directly with no polymorphism.
- A merged 11-slot struct would surface 4 always-nil slots on every
  movement entry to every reader; the current nested-tx structure
  visually groups the replay fields.
- The `mc-tx` deletion (which removed the strongest practical argument
  for keeping the split) demonstrated that the split is a CONTAINER
  that absorbs architectural changes, not a CONSTRAINT that obstructs
  them.

### 2. Context-aware runners `(lambda (tx &optional context) ...)` — REJECTED

Proposal: replace the dual-tx (`tx` + `mc-tx`) model with a single
runner that branches internally on a `:real` / `:fake` context
parameter.

Why rejected: the `:pre-replay-fn` payload approach achieves the same
conceptual unification at lower cost (no runner signature change, no
N small conditionals scattered across runners).  See
`helixel-tx-replay' in `helixel-core.el'.

### 3. Eliminate deferred commit / audit all `helixel--tracking-open' raw call sites — REJECTED

Proposal: force every command body through
`helixel-with-action-tracking'; commit immediately in unwind-protect.

Why rejected: the 11 raw call sites are legitimate.  Surround commands
(5/11) have a prompt→mark→wrap→commit lifecycle that spans multiple
interactive steps and does not fit a single-body macro.  Search
commands (4/11) call `tracking-open' from non-command helpers.  Mode
toggles (2/11) have their own lifecycle.

### 4. Generalize `:pre-replay-fn' to a list of hooks — REJECTED

Proposal: change the payload entry from a single function to a list.

Why rejected: no command currently attaches more than one
`:tx-runner'.  Generalizing is a 5-line change when actually needed,
so pre-solving has negative value.  The single-write invariant is
documented in `helixel-define-command's docstring.

### 5. Marker → integer for `helixel-repeat-preview-pos' — REJECTED

Proposal: replace the marker with a buffer-position integer.

Why rejected: regression risk.  Markers auto-track buffer edits
between `,` and `.'; integers don't.  Any intermediate insertion
would shift the target position.

### 6. Consolidate `helixel-keyboard-quit-functions' into `helixel-state-change-hook' — REJECTED

Why rejected: C-g does not always trigger a state change (e.g. C-g
in normal mode stays in normal).  Hooks model independent events.

### 7. Replace `helixel-repeat-edit-function' with `:around' advice — REJECTED

Why rejected: violates Design Invariant #3 ("Runner-replay over
advice. No per-command advice-add").

### 8. File merges beyond `helixel-replay.el' + `helixel-register.el' — REJECTED

Proposals to merge: `macros.el' → `ring.el' (cycle), `chain.el' →
`repeat.el' (produces 1000-LOC mega-file), `mc-integrate.el' →
`mc-core.el' (pulls repeat+chain deps into mc-core, violating
mc-core's minimal-deps invariant), `insert-record.el' → `repeat.el'
(no callsite reduction).

## Refactor Lessons (load-bearing gotchas)

1. **`this-command` is nil in batch + ert.**  `call-interactively`
   does NOT set `this-command` outside the command loop.
   `helixel-define-command` binds `this-command` to the function
   symbol on entry to be both production- and test-correct.

2. **Override, not defensive-`or`.**  Use unconditional
   `(let ((this-command ',name)) ...)` instead of
   `(or this-command 'NAME)` — the latter preserves stale outer
   values and causes subtle test failures.

3. **Position-independent runners enable mc replay for free.**
   Registering an op runner that uses `(region-beginning)`/`(point)`
   instead of `tx`-stored positions automatically works at fake
   cursors.

4. **MC tests bypass `post-command-hook`.**  Many call
   `(helixel-mc--post-command)` directly.  This is FINE because
   fresh-edit detection uses the `by-command` stamp, not a
   pre-command snapshot.

5. **Indirect references defeat naive dead-code grep.**  Text
   objects instantiate symbols via `(intern (format "helixel--%s"
   sym))`, so grep can report a function as unused even when a macro
   emits it.  Always recompile + run tests after deletion; the
   byte-compiler catches what grep misses.

6. **Load-time advice for test-reachability.**  Advices needed by
   tests that don't enable `helixel-mode` globally (e.g. mc
   keyboard-quit cleanup) must be installed at module load with a
   per-fn gate inside, not inside the `helixel-mode` toggle body.
