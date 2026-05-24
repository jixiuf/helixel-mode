# helixel-mode Architecture

> File map, dep graph, structs, and APIs are in project root `AGENTS.md`.

---

## Data Layer (`helixel-data.el`)

### Three Structs

| Struct | Role | Mutable? |
|--------|------|----------|
| `helixel-sel` | Selection descriptor (kind + ctx + recreate closure) | Immutable (copy on update) |
| `helixel-event` | Transaction and ring entry (op + sel + payload + runner + category + subcat) | `helixel--last-tx` is mutable; ring entries are copies |
| `helixel-event` | Unified event for ring storage (`;` jumping + event history) | Immutable after commit |

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
:repeat-advance    nil|'line|fn      auto-advance tag for `.`
:strategy-builder  fn(edit rev) → strategy  custom strategy (chain)
```

Access: `(helixel--op-runner 'kill)`, `(helixel--op-advance 'insert-text)`, etc.

---

## Event Ring (`helixel-ring.el`)

### Two Containers, One Event Type

| Ring | Scope | Purpose | Key |
|------|-------|---------|-----|
| `helixel--event-ring` | buffer-local | `;` cycling, dot-repeat picker | C-g |
| `helixel--jump-list` | global | C-o/C-i jump navigation | C-o |

Both store `helixel-event` structs. The jump-list stores a subset of ring events (filtered by `helixel-jump-categories`).

### Commit Pipeline

```
Editing command
  → helixel--record-edit (creates an event tx, stores as helixel--last-tx)
  → helixel-event-commit
    → push to helixel--event-ring (dedup, cap)
      → push to helixel--jump-list (filtered)
```

### Dedup

Events are deduplicated by content: same op, category, subcat, sel, payload, and marker position → skip push. Cancel sentinels (C-g) create dedup boundaries.

---

## Repeat Strategy (`helixel-repeat-strategy.el`)

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
   - Check `:repeat-advance` tag from op registry (nil → no advance)
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

`helixel--record-edit(op, &rest extra)`:
1. Pop pending sel via `helixel--sel-pop`
2. Look up runner from op registry
3. Create event tx via `helixel--make-tx`
4. Store as `helixel--last-tx`
5. Commit event via `helixel-event-commit`

### Insert Recording

Insert-mode keystrokes are recorded via `pre-command-hook` → `helixel--insert-keys` (vectors from `this-single-command-keys`). On exit: keys stored in tx payload as `:keys`, text as `:text` fallback. No kmacro, no `:commands` layer.

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

Chain records a compound operation (move + edit) as a single repeatable unit.

### Lifecycle

1. `helixel-repeat-chain-start` — begin recording (pre-command-hook collects keys)
2. Move keys → `helixel--chain-move-keys`; First edit triggers phase switch
3. Edit keys → `helixel--chain-edit-keys`
4. `helixel-repeat-chain-end` — create tx with op='chain', payload includes kmacro
5. `.` replays: strategy builder = `helixel--chain-strategy-builder`

### Strategy

Chain has a custom `:strategy-builder` in the op registry:
- Advance: kind's advance-fn + replay move-keys
- Apply: replay edit-keys via chain runner
- All-buffer-fn: from kind registry

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

### Legacy Accessors

Removed in Phase 1-4.  Search direction is managed solely via
`helixel--active-search` and `helixel-search--current-dir` /
`helixel-search--set-dir`.

---

## Action Tracking (`helixel-action.el`)

### `;` Cycling

Uses `helixel--event-ring`. Group-skipping: consecutive entries with same (category, subcat) form a group; `;` jumps to the oldest entry of each group.

### C-o/C-i Jump Navigation

Uses `helixel--jump-list` (global). Same group-skipping algorithm as `;`, with buffer identity included in grouping.

### Bridge Functions

Removed in Phase 3.  `helixel--tracking-open` in `helixel-macros.el`
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
`helixel-with-edit-tracking`.

### `helixel-define-command`

Defines a helixel command.  Expands to a `defun` that calls
`helixel--tracking-open`, then auto-injects:
- `helixel--clear-highlights` — for movement commands
- `helixel--track-visual-move` — visual-mode `.` support

### `helixel-define-operator`

Like `helixel-define-command` but also registers the operator via
`helixel-register-op` for `.` repeat.

### `helixel-with-edit-tracking`

For self-contained commands (chain).  Wraps body in
`helixel--tracking-open` + `unwind-protect` commit.

---

## File Dependency Graph

```
helixel-data (cl-lib only)
  ├── helixel-ring
  │     ├── helixel-action
  │     └── helixel-repeat → helixel-repeat-strategy → helixel-chain
  │
  ├── helixel-register
  ├── helixel-macros (→ data only)
  ├── helixel-state (→ macros + action + repeat + ring + register
  │     │              + textobj + surround)
  │     ├── helixel-move (→ state)
  │     ├── helixel-editing (→ state + move + data;
  │     │                    runtime → swap for circular-dep avoidance)
  │     │     ├── helixel-search (→ editing)
  │     │     ├── helixel-keymap (→ state + move + editing + chain + surround)
  │     │     └── helixel-swap (→ state)
  │     └── helixel-textobj-engine → helixel-textobj → helixel-surround
  └── helixel-shims (→ state)
```

## Key Shared Variables

| Variable | Location | Purpose |
|----------|----------|---------|
| `helixel--pending-sel` | `helixel-data.el` | Pending selection descriptor |
| `helixel--last-tx` | `helixel-data.el` | Most recent edit transaction |
| `helixel--live-event` | `helixel-ring.el` | Current in-progress event |
| `helixel--active-search` | `helixel-search.el` | Active search direction+pattern |

---

## Test Architecture

570 ERT tests across 16 test files. Key conventions:

- `(helixel-test-with-buffer "content" body...)` — creates temp buffer with `transient-mark-mode 1`
- Set `last-command` and `this-command` before calling selection/edit functions
- For dot-repeat tests: build tx with `helixel--make-tx` and set `helixel--last-tx`
- For chain tests: use `helixel-chain--make-test-tx` helper
- Max 12s timeout per test run; zero hangs expected
