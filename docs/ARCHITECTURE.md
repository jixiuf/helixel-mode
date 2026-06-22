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

### Two Structs

| Struct | Role | Mutable? |
|--------|------|----------|
| `helixel-sel` | Selection descriptor (kind + ctx + recreate closure) | Immutable (copy on update) |
| `helixel-action` | Unified struct for replay AND history (op + sel + payload + runner + display + category + subcat + by-command + preposition + mark-region + timestamp + buffer) | `helixel-last-action` is the latest action, mutable cell; ring entries are immutable after commit |

The single `helixel-action` struct serves both replay and history.
All accessors (`helixel-action-op`, `helixel-action-sel`,
`helixel-action-payload-get`, `helixel-action-runner`,
`helixel-action-preposition`) operate on the unified struct.

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
:self-advancing    boolean           t = op handles positioning, no auto-advance
```

Access: `(helixel--op-runner 'kill)`, `(helixel--op-self-advancing-p 'insert-text)`, etc.

---

## Event Ring (`helixel-ring.el`)

### Two Containers, One Event Type

| Ring | Scope | Purpose | Key |
|------|-------|---------|-----|
| `helixel--action-ring` | buffer-local | `;` cycling, dot-repeat picker | C-g |
| `helixel--global-jump-log` | global | C-o/C-i jump navigation | C-o |

Both store `helixel-action` structs. The jump-log stores a subset of ring events (filtered by `helixel-jump-categories`).

### Commit Pipeline

```
Editing command
  → helixel-record-action (creates an event tx, stores as helixel-last-action)
  → helixel--action-commit
    → stamp :by-command
    → push to helixel--action-ring (dedup, cap)
    → push to helixel--global-jump-log (filtered)
    → run helixel-action-commit-hook (entry)   ; chain accumulator
```

`helixel-action-commit-hook` is an abnormal hook called with the
committed entry.  It is the sole integration point for cross-cutting
observers — chain (`helixel-chain.el`) hooks into it to append the
committed tx onto the chain session's `:action-list`.  Adding new
observers should not require touching ring or commit code.

### Dedup

Events are deduplicated by content: same op, category, subcat, sel, payload, and marker position → skip push. Cancel sentinels (C-g) create dedup boundaries.

---

## Repeat Engine

Dot-repeat uses a single `helixel--repeat-advance(edit, effective)`
function that delegates to the kind registry's `:advance` fn.
All-buffer and all-dir scans pull `:all-buffer-fn` / `:all-dir-fn`
directly from the kind registry.

```elisp
;; Unified advance – one function, no closures
(defun helixel--repeat-advance (edit effective)
  "Advance to next replay target.  Return non-nil on success."
  (let* ((op (helixel-action-op edit))
         (advance-fn (helixel--kind-advance (helixel-sel-kind …))))
    (cond
     ((and (eq op 'chain) (null advance-fn)) t)   ; in-place
     ((or (not advance-fn) (helixel--op-self-advancing-p op))
      (helixel-sel-call-recreate …))              ; recreate only
     (t (funcall advance-fn edit)))))              ; kind drives
```

### `.` Dispatch (4 modes, direct)

```
helixel--repeat-edit-default
  ├── :all-buffer  → helixel--repeat-all-buffer(edit, prefix, reverse-p)
  │                    ├── :all-buffer-fn set? → delegate to kind
  │                    └── else: goto marker → scan from point-min
  ├── :all-dir     → helixel--repeat-all-dir(edit, reverse-p)
  │                    ├── :all-dir-fn set? → delegate to kind
  │                    └── else: advance+replay loop from point
  ├── :n-times     → helixel--repeat-n(edit, n, reverse-p)
  └── preview      → helixel--repeat-preview(edit, mode, n, reverse-p)
```

---

## Repeat Edit (`.`)

### Recording

`helixel-record-action(op, &rest extra)`:
1. Pop pending sel via `helixel--sel-pop`
2. Look up runner from op registry
3. Create action via `helixel-action-create`
4. Store as `helixel-last-action`
5. Commit event via `helixel--action-commit`

### Insert Recording

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

### Kind-Driven Advance

Each selection kind registers an `:advance` fn (and optionally
`:all-buffer-fn` / `:all-dir-fn`) in the kind registry.
`helixel--repeat-advance` delegates to the kind's `:advance` fn
for positioning.  The advance fn is responsible for:
- Moving point to the next target (line, search match, word, etc.)
- Calling `helixel-sel-call-recreate` to position point appropriately
- Guarding against edge cases (zero-width patterns, blank lines)

Scratch state for search advance (edge-seen, last-pos, advance-done)
lives as fields on the `helixel-replay` struct — each `.` / `,` press
gets a fresh binding via `helixel-with-replay`.

### All-Buffer / All-Dir Handlers

- **Line**: `helixel--all-buffer-line` — forward+backward pass from marker
  using `helixel--repeat-line-pass`
- **Search**: handled inline in `helixel--repeat-all-buffer` via
  the kind's `:all-buffer-fn` or generic `helixel--repeat-advance` loop
- **Other kinds**: generic advance+replay scan from point-min
- **All-dir line**: `helixel--all-dir-line` — uses `helixel--repeat-line-pass`
  from current position
- **All-dir other**: generic advance+replay loop from point

---

## Chain (`helixel-chain.el`)

Chain records a compound operation (any sequence of motions + edits)
as a single repeatable unit, using a list-of-txs rather
than a kmacro recorder.

### Lifecycle

1. `helixel-repeat-chain-start` — snapshot pending sel + bounds;
   set session active; `helixel-action-commit-hook` becomes the
   accumulator.
2. Each helixel command commits an action via
   `helixel--action-commit`; if the action has a runner AND the
   by-command is not in the chain-control set
   (chain-start / -end / -cancel / normal-escape), the tx is appended
   to `helixel-chain-session-action-list`.
3. `helixel-repeat-chain-end` — finalize: merge init-ctx into a
   chain tx with op=`chain`, payload `:action-list LIST`; runner
   iterates LIST and replays each sub-action; broadcast to fake cursors
   via `helixel-chain-recorded-functions`.
4. `.` replays via `helixel--repeat-advance` (delegates to the kind's
   `:advance` fn for positioning), then `helixel--repeat-chain-runner`
   iterates `:action-list` at each target.

### Why list-of-txs (vs kmacro)

Every helixel command already produces a `helixel-action`, and each
action is fully position-agnostic with its own runner.  Chain
just collects them; replay just dispatches each in order.  No
`execute-kbd-macro`, no separate move-keys / edit-keys phases, no
key-capture pre-command-hook.  Chain session struct: 4 slots
(active-p, action-list, init-ctx, init-bounds).

---

## Search (`helixel-search.el`)

### Active Search State

`helixel--active-search` is the single mutable search state:

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

Uses `helixel--action-ring`. Group-skipping: consecutive entries with same (category, subcat) form a group; `;` jumps to the oldest entry of each group.

### C-o/C-i Jump Navigation

Uses `helixel--global-jump-log` (global). Same group-skipping algorithm as `;`, with buffer identity included in grouping.

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
| `helixel-last-action` | `helixel-core.el` | Most recent edit transaction |
| `helixel--live-action` | `helixel-ring.el` | Current in-progress event |
| `helixel--active-search` | `helixel-search.el` | Active search direction+pattern |

---

## Test Architecture

ERT tests across 22 test files.  Key conventions:

- `(helixel-test-with-buffer "content" body...)` — creates temp buffer with `transient-mark-mode 1`
- Set `last-command` and `this-command` before calling selection/edit functions
- For dot-repeat tests: build action with `helixel-action-create` and set `helixel-last-action`
- For chain tests: use `helixel-chain--make-test-action` helper
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
  ├── Resolves helixel-last-action (per-buffer)
  ├── Decodes prefix via helixel-repeat-prefix struct
  ├── helixel--repeat-setup: flips dir if needed, resets search scratch
  │
  ▼
helixel-repeat.el:helixel--repeat-edit-default (with helixel-with-replay-as 'dot)
  ├── Mode dispatch based on (helixel-repeat-prefix-mode prefix):
  │     ├── :all-buffer → helixel--repeat-all-buffer(edit, prefix, reverse-p)
  │     │     ├── :all-buffer-fn set? → delegate to kind's custom fn
  │     │     └── else: goto marker → scan from point-min
  │     ├── :all-dir    → helixel--repeat-all-dir(edit, reverse-p)
  │     │     ├── :all-dir-fn set? → delegate to kind's custom fn
  │     │     └── else: advance+replay loop from point
  │     └── :n-times    → helixel--repeat-n(edit, n, reverse-p)
  │
  ▼
helixel-repeat.el:helixel--repeat-advance(edit, effective)
  ├── Delegates to kind registry :advance fn
  │     ├── line: advance line(s) then recreate
  │     ├── search: find-next-match then recreate
  │     ├── movement: advance steps then recreate
  │     ├── textobj: advance to next textobj then recreate
  │     └── find-char: find next char then recreate
  │
  ├── Apply: execute edit at current position
  │     └── helixel-core.el:helixel-action-replay(action)
  │           ├── calls :preposition (if any) — mc cursor positioning
  │           └── calls :runner — closure stored at record time
  │
  └── All-buffer/all-dir: scan from point-min or current position
        └── kind-specific handlers from helixel-repeat.el
              (line:line-pass, search:inline scan, others:generic loop)
```

Key invariants:
- The `helixel-replay` struct tracks the current replay context
  (origin: `dot` / `comma` / `chain` / `insert` / `mc-fake` / `mc-batch`);
  `helixel-replaying-p` gates all record/commit side effects.
- `helixel-last-action` IS buffer-local (`defvar-local`).  `.' replays
  the last edit in the current buffer only.
- The runner closure stored in the event struct was captured at record time
  from the op registry, so replay never queries the registry.
- All iterations within a single `.` press are wrapped in one undo step.

---

## Design Invariants

These are load-bearing decisions that the codebase actively depends on
— change them only with full-suite testing.

1. **Single command-identity stamp.**  Every `helixel-action` carries
   `:by-command` (auto-stamped in `helixel--action-commit`).  Dispatch
   decisions — mc fresh-edit replay vs `call-interactively`, `.` vs
   `,` — all key off this one field instead of separate flag
   networks.

2. **Single replay context.**  The `helixel-replay` struct's `origin`
   slot (`dot` / `comma` / `chain` / `insert` / `mc-fake` /
   `mc-batch`) is the one authoritative answer to "what's happening
   right now", consumed by `helixel-replaying-p` and
   `helixel--mc-dispatch-in-progress-p`.  Do not reintroduce
   per-feature inhibit flags.

3. **Runner-replay over advice.**  Prompt commands store their
   decisions in `helixel-action-payload`; runners are
   position-independent (operate on current region/point + payload).
   Multi-cursor and `.`-repeat both reuse the runner — no per-command
   `advice-add` needed.

4. **One state struct per subsystem.**  Chain uses 1 buffer-local
   (`helixel-chain-session`); replay uses 1 struct
   (`helixel-replay`).  New per-subsystem state must follow this
   pattern.

5. **Single keyboard-quit entry point.**  Modules contribute to
   `helixel-keyboard-quit-functions` (abnormal hook); only one
   `advice-add` on `keyboard-quit` lives in `helixel-state.el`.
   Never advise `keyboard-quit` from another module.

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
