# AGENTS.md — helixel-mode

> User docs: `docs/USER-GUIDE.md` | Extension API: `docs/API.md`
> Architecture: `docs/ARCHITECTURE.md` | Debug: `docs/DEBUG-SKILL.md`

## File Map

| File | Role |
|------|------|
| `helixel-core.el` | **Pure data layer**: `helixel-sel`, `helixel-action` structs, `helixel-last-action`, kind registry, op registry, delimiter protocol, transaction helpers, swap-source type, keyrec utilities. Zero helixel deps (cl-lib only). |
| `helixel-ring.el` | **Event storage + history navigation**: `helixel--action-ring` (commit/dedup/cap), `helixel--global-jump-log`, `helixel--tracking-open`, `helixel--cancel-action`, `helixel--live-action-set`, live-event management, `;' action-cycle, C-o/C-i jump commands. |
| `helixel-macros.el` | **Command definition macros**: `helixel-define-command`, `helixel-define-operator`, `helixel-with-action-tracking`. |
| `helixel-repeat.el` | Dot-repeat (`.`) and selection-repeat (`M-.`): record (`helixel-record-action`), replay, unified `helixel--repeat-advance` (delegates to kind-registry advance fns), all-buffer/all-dir dispatch, kind-specific `:all-buffer-fn`/`:all-dir-fn` from kind registry, line-pass helper, interactive entry points.  Also includes insert-mode key + text recording (segment-based capture via after-change-functions) — each insert-mode command becomes either `(:keys VEC)` (no buffer change) or `(:text STR :delete-before N :offset O)` (any buffer change).  Replay helper `helixel--execute-keys' accepts both segment lists and raw key vectors. |
| `helixel-chain.el` | Chain lifecycle: start/end/cancel.  Chain accumulates a list of `helixel-action' values committed during the chain (via `helixel-action-commit-hook') and stores it as `:action-list' payload.  Replay iterates the list and `helixel-action-replay`s each entry.  No more kmacro / keystroke capture. |
| `helixel-state.el` | Modal state machine, pending-op system, keymap shells, insert entry/exit, visual state, minor modes, shared kill core. |
| `helixel-move.el` | Movement/selection commands (line/rect/word), rect change/replay. |
| `helixel-editing.el` | Editing commands (kill, change, copy, replace, yank) + selection recreate fns + op runners + `helixel--replace-region` + `helixel--delete-selection`. |
| `helixel-keymap.el` | All keymaps. Populates `helixel-state-map-alist`. 7 `declare-function` for flymake/eglot (third-party only). |
| `helixel-search.el` | Search/find-char + `n`/`N` repeat + `helixel--active-search` state. |
| `helixel-textobj-engine.el` | Forward primitives (forward-word/WORD/symbol/sentence/paragraph/function), generic select-inner/a-object + restricted variants, range struct, type-properties, motion-loop / with-restriction macros, activate-textobj-range, recreate-textobj + advance-textobj. Pure primitives, no per-textobj-type code. |
| `helixel-textobj-pair.el` | Paren / quote / xml-tag selection (the matched-pair families): get-block-range, select-block, up-paren, select-paren, forward-quote, select-quote, select-xml-tag, tag-* helpers, make-pair-delimiter, make-tag-delimiter. |
| `helixel-textobj-block.el` | Regex / fenced block text objects: up-regex-block, select-regex-block, up-block-at-point, select-block-at-point, block-textobj-alist (customs), block-spec-at-point, block-adjust-for-jump, regex-adjust-for-jump, make-block-delimiter, make-regex-delimiter. |
| `helixel-textobj-marks.el` | User-facing surface: define-mark-pair/-quote/-object/-regex-textobj macros, mark-inner-*/mark-a-* commands (including tag and block), tree-sitter helper, all default registrations, `textobj' kind registration. |
| `helixel-textobj.el` | Facade: requires engine, pair, block, marks. |
| `helixel-surround.el` | Surround add/delete/replace. |
| `helixel-swap.el` | Swap commands. Depends on `helixel-editing` for `helixel--replace-region` (one-way, no circular dep). |
| `helixel-mc-core.el` | **Multi-cursor core**: fake-cursor overlays, per-cursor state vars, dispatch loop via `post-command-hook` / `pre-command-hook`, cursor-ID hash table, undo-step management (begin/finish + `buffer-undo-list` `apply` entry injection for cursor-position persistence across undo/redo), whitelist policy, `helixel-multi-cursor-mode`. |
| `helixel-mc-targets.el` | **Target computation**: `helixel-mc--realize-targets`, advance-walk fallback, `helixel-mc--spawn-from-sel/-line/-rect/-find-char`, kind registry hooks. |
| `helixel-mc-spawn.el` | **High-level user commands**: toggle, add-cursor-here, edit-lines, mark-next-like-this, primary/content rotation, keep/remove-matching, merge/trim/align, split-on-regex, restore-cursors. |
| `helixel-mc-integrate.el` | Glue: dot-repeat / chain / insert per-cursor execution + atomic undo. |
| `helixel-shims.el` | `with-eval-after-load` shims for third-party integration (info, help-mode, shortdoc, man, woman, eww) + multi-cursor completion-preview shim. 29 `declare-function` (all third-party). |
| `helixel.el` | Package entry point. Requires all domain files. |

### Test Files

| File | Covers |
|------|--------|
| `test/helixel-test-common.el` | `helixel-test-with-buffer` macro |
| `test/helixel-test-editing.el` | Edit transactions, sel struct, editing commands |
| `test/helixel-test-action.el` | Action tracking and command execution |
| `test/helixel-test-repeat.el` | Line selection auto-advance, flip-dir, movement, textobj, find-char dot-repeat |
| `test/helixel-test-chain.el` | Chain dot/comma tests |
| `test/helixel-test-search.el` | Search, search history, n/N repeat |
| `test/helixel-test-move.el` | Movement/word/symbol/find-char |
| `test/helixel-test-keymap.el` | Keymap and define-key |
| `test/helixel-test-line.el` | Line-wise editing |
| `test/helixel-test-rect.el` | Rectangle selection and editing |
| `test/helixel-test-operator.el` | Operators (case, comment, fill, join) |
| `test/helixel-test-swap.el` | Swap |
| `test/helixel-test-textobj.el` | Text object and regex block |
| `test/helixel-test-register.el` | Register |
| `test/helixel-test-ring.el` | Event ring + jump log |
| `test/helixel-test-jump.el` | Jump navigation + all-buffer/all-dir repeat tests |
| `test/helixel-test-mc.el` | Multi-cursor: create/clear, whitelist, with-each-cursor isolation, dispatch insert, spawn-from-line, edit-lines, add-cursor-here, mark-next-like-this, apply-last-edit, kill-ring isolation.  Undo: marker injection, number filtering, noop step, capture/restore roundtrip, restore creates cursors, delete undo, insert undo, full cycle, mark-active capture, ID persistence, independent steps, callback roundtrip |
| `test/helixel-test-chain-invariant.el` | Chain subsystem invariants (lifecycle flag, chain-control exclusion, runnerless tx exclusion, marker release) |
| `test/helixel-test-repeat-invariant.el` | Repeat subsystem invariants (replay context, buffer-local last-action, tx-replay immutability, pre-replay order, cleanup on error) |
| `test/helixel-test-ring-invariant.el` | Ring + jump-log invariants (dedup, cap, marker release, commit-hook contract, by-command fallback, jump-log lightweight) |
| `test/helixel-test-cycle.el` | `;` action-cycle and `C-;` jump-cycle: group-start selection, push-mark, start-point vs full-span, per-fake cycling, cancel-session boundary |
| `test/helixel-test-mc-invariant.el` | MC dispatch contract invariants: per-fake state isolation, undo-step amalgamation, kill-ring independence, fake-cursor overlay lifecycle |

## Deps (one-way, compile-time — actual `require` graph)

```
helixel-core (cl-lib only, zero helixel deps)
  │
  ├── helixel-ring (→ core)
  │     └── helixel-macros (→ core + ring)
  │
  ├── helixel-textobj-engine (→ core)
  │     ├── helixel-textobj-pair (→ core + textobj-engine)
  │     │     └── helixel-textobj-block (→ core + textobj-engine
  │     │                              + textobj-pair)
  │     │           └── helixel-textobj-marks (→ core + textobj-engine
  │     │                                    + textobj-pair
  │     │                                    + textobj-block)
  │     └── helixel-textobj (facade: requires the four above)
  │     └── helixel-surround (→ core + ring + repeat + textobj)
  │
  ├── helixel-repeat (→ core + ring)
  │     └── helixel-chain (→ core + ring + macros + repeat)
  │
  ├── helixel-mc-core (→ core + ring)
  │     ├── helixel-mc-targets (→ core + mc-core)
  │     │     └── helixel-mc-spawn (→ core + mc-core + mc-targets)
  │     └── helixel-mc-integrate (→ core + mc-core + repeat + chain)
  │
  └── helixel-state (→ core + ring + macros + repeat
                      + textobj + surround)
        │
        ├── helixel-move (→ state + macros)
        │     │
        │     └── helixel-editing (→ state + move + core + macros
        │                          + search)
        │           │
        │           ├── helixel-search (→ state + core + macros
        │           │                   + repeat + move)
        │           │
        │           ├── helixel-swap (→ state + macros + editing)
        │           │
        │           └── helixel-keymap (→ state + move + editing
                                          + chain + surround + swap
                                          + search + mc-core + mc-spawn
                                          + mc-integrate)
        │
        └── helixel-shims (→ state + keymap)
```

Notes:
- **Zero circular deps.** `swap→editing` is one-way (editing does NOT require swap).
- `helixel--replace-region` lives in `helixel-editing.el`.
- `helixel--delete-selection` lives in `helixel-editing.el`.
- `helixel--swap-source-type` lives in `helixel-core.el`.
- `helixel-last-action` lives in `helixel-core.el` (buffer-local).
  Every module that requires `helixel-core` can read/write the most recent transaction.
- `declare-function` counts are minimal and only for third-party packages:
  - `helixel-keymap.el`: 7 (flymake, eglot)
  - `helixel-repeat.el`: 0
  - `helixel-textobj-engine.el`: 0
  - `helixel-textobj-pair.el`: 0
  - `helixel-textobj-block.el`: 0
  - `helixel-textobj-marks.el`: 2 (evil-tree-sitter)
  - `helixel-shims.el`: 29 (info, help-mode, shortdoc, man, woman, eww)

## Key Structs

### helixel-sel (selection descriptor)
```elisp
(cl-defstruct helixel-sel kind ctx)
;; Protocol methods (recreate, advance, display) looked up from
;; kind registry via helixel-register-kind.
;; CTX keys per kind:
;;   line          :dir (forward|backward) :count (int≥1) :entry-kind
;;   rect          :count (int≥1)
;;   movement      :moves ((CMD . COUNT)…) :inline-advance t
;;   textobj       :command :count :delimiter :inline-advance t
;;   search        :pattern :dir :entry-kind
;;   find-char     :char :type (next|till) :dir :inline-advance t
;;   surround      :delimiter
;;   insert-selection-*  :cursor-offset
;;   insert-search-offset :offset

### helixel-action / helixel-action (unified replay + history event)

```elisp
(cl-defstruct helixel-action op sel payload runner preposition mark-region
               display category subcat timestamp buffer by-command)
```
A SINGLE struct serving both replay (`.`, `M-.`, chain, mc) and history
(`;`, C-o/C-i).  Slots op/sel/payload/runner/preposition are nil for
pure movement/search/state events (~40B per entry negligible).

- `helixel-action-create' constructs an `helixel-action' directly.
- `helixel-action--copy' performs deep copies for ring storage.

## Key APIs

```elisp
;; ── Selection ──
(helixel-sel-create kind ctx)   → struct (extra args ignored)
(helixel-sel-kind sel)          → symbol
(helixel-sel-call-recreate sel) → recreates region via kind registry
(helixel-sel-update-ctx sel k v)→ new sel
(helixel-sel-count sel)         → :count or 0
;; Kind accessors (work on struct or raw ctx plist):
(helixel-sel-line-dir obj)          → :dir, default 'forward
(helixel-sel-line-count obj)        → :count, default 1
(helixel-sel-search-pattern obj)
(helixel-sel-search-dir obj)        → :dir, default 'forward
(helixel-sel-search-entry-kind obj)
(helixel-sel-textobj-command obj)

;; ── Pending selection ──
(helixel--sel-push sel)             ; selection cmds push
(helixel--sel-pop)                  → sel|nil  ; edit cmds pop

;; ── Transaction ──
(helixel-action-create op sel &rest kv) → struct  ;; returns helixel-action
  ;; Special kv: :runner fn, :display str|fn — rest becomes :payload
  ;; Common payload keys: :keys, :text, :char
(helixel-action-op tx)
(helixel-action-sel tx)
(helixel-action-payload tx)
(helixel-action-runner tx)
(helixel-action-mark-region tx)
(helixel-action-display tx)
(helixel-action-preposition tx) ;; preposition function set via :preposition
(helixel-action-with-payload tx k v) → new action with payload entry added
(helixel-action--copy action)              → deep copy

;; ── Event ──
(helixel-action-op event)
(helixel-action-payload event)
(helixel-action-sel event)
(helixel-action-category event)
(helixel-action-subcat event)

;; ── Kind Registry ──
(helixel-register-kind kind &rest props)
  ;; props: :recreate :advance :display :all-buffer-fn :all-dir-fn
  ;;        :flip-dir-fn :mc-spawn-fn
(helixel--kind-advance kind)        → fn|nil
(helixel--kind-recreate kind)       → fn|nil
(helixel--kind-all-buffer-fn kind)  → fn|nil
(helixel--kind-all-dir-fn kind)     → fn|nil
(helixel--kind-flip-dir-fn kind)    → fn|nil  ; sel → reversed sel

;; ── Op Registry ──
(helixel-register-op op &rest props)
  ;; props: :runner :display :moves-point-p
(helixel--op-runner op)         → fn
(helixel--op-moves-point-p op)        → boolean

;; ── Repeat ──
(helixel-record-action op &rest extra)  ; stores action + commits event
(helixel-action-replay action)           ; calls :preposition (if any), then :runner on action
(helixel-repeat-edit &optional prefix) ; bound to .
(helixel-repeat-selection &optional prefix) ; bound to M-.  (preview, no edit)

;; ── Chain ──
(helixel-repeat-chain-start/end/cancel)  ; interactive commands
;;   @ = start, ESC = end (normal map), C-g = cancel

;; ── Multi-cursor (`s' prefix + top-level) ──
(helixel-mc-toggle)              ; s s  toggle (spawn from sel / clear)
(helixel-mc-clear-all)           ; s SPC / s ,
(helixel-mc-add-cursor-here)     ; s a / s A
(helixel-mc-edit-lines)          ; s x  line-mode → region / char-mode → col
(helixel-mc-mark-next-like-this) ; s n / s p / s N / s P / s u / s U
(helixel-mc-apply-last-action)     ; s .
(helixel-mc-remove-primary)      ; M-,  remove primary cursor (Helix A-,)
(helixel-mc-keep-matching REGEX) ; s k  / s K  (remove-matching)
(helixel-mc-rotate-primary-fwd)  ; ) / ( (rotate-primary-backward)
(helixel-mc-rotate-content-fwd)  ; M-) / M-(
(helixel-mc-merge / -align / -trim / -split-on-regex)  ; s - / s & / s _ / s S
(helixel-mc-restore-cursors)     ; g v  (history stack, depth 16)

;; Hook for layout snapshotting / pre-clear cleanup:
(add-hook 'helixel-mc-before-clear-hook #'my-callback)
```

## Build & Test

```bash
rm -f *.elc && make compile && make test   # always fresh compile before test
make lint                                   # checkdoc + package-lint + column-check + ctx-lint
make depgraph                               # regenerate docs/DEPGRAPH.md from `require' edges

## Pitfalls

### Always recompile after edits
Stale .elc silently hides changes. `rm -f *.elc && make compile` before testing.

### Simulate interactive commands in batch mode
`call-interactively` doesn't work in `--batch` (no real event loop). Use:
```elisp
(execute-kbd-macro (kbd "M-x your-command RET"))
```
This is equivalent to the user pressing `M-x your-command RET` even in batch mode.
Works for any key sequence, e.g. `(kbd "C-x C-f")`.

**Note**: this triggers the full hook chain (`pre-command-hook`, `post-command-hook`,
`after-change-functions`, etc.) — just like real key presses. If you don't want
these side effects in tests, call the underlying function directly instead.

### Docstring rules
- Max 80 cols per line (`make lint` checks this)
- Lisp symbols in backticks: ``` `foo' ```
- Closing `"` must stay — missing it → "End of file during parsing"
- Open paren at column 0 in docstring must be escaped: `\\(`
- First line must be a complete sentence
- Function args must appear in docstring (uppercase)

### helixel-last-action is buffer-local
`. ` replays the last edit from the current buffer only.

### helixel-action-create keyword handling
`helixel-action-create` extracts `:runner` and `:display` as special keys. All other keywords form the `:payload` plist. Never pass `:payload` as a keyword — spread payload keys individually, or use `helixel-action-copy` + `setf`.

### Never trust match-data in helixel-insert / helixel-insert-after
Search hooks invalidate `match-data`. Use `(region-beginning)` / `(region-end)` instead.

### insert-text runner must NOT deactivate-mark
Selection is recreated before execute. `deactivate-mark` destroys it → invisible after `.`/`M-.`.

### helixel--recreate-line: use region-beginning/region-end
After `helixel-select-line`, point is on the LAST selected line. `line-beginning-position` targets the wrong line for count≥2.

### Never set `defining-kbd-macro` to t in long-lived insert recording
`defining-kbd-macro` being non-nil causes `sit-for` to skip its `read-event` wait. Use manual key collection via hooks instead.

### transient-mark-mode and region extension
When `transient-mark-mode` is on, `helixel-select-line-up`/`helixel-select-line` detect an active region and enter "extending" mode. Call `(deactivate-mark)` before recreate to ensure a fresh region.

### Zero-width search patterns ($, ^) and infinite loops
`helixel--repeat-advance` (via the kind's advance fn) uses `helixel-replay` struct fields (`search-edge-seen`, `search-last-pos`) to prevent infinite loops with zero-width patterns at buffer edges. Each new `helixel-with-replay` binding provides a fresh scratch area.

### Strategy all-buffer-fn recursion
`helixel--repeat-all-buffer` for non-entry-kind search must NOT recurse via `:all-buffer-fn` (would loop). Instead it does the scan inline via `helixel--repeat-advance`.

### Multi-cursor (mc) — fake cursor model
`helixel-mc-core.el` provides REAL fake cursors with per-cursor state
held in a single `helixel-pc-state' (`helixel-pcs-') struct
attached to each fake-cursor overlay under the `helixel-pc-state' property.
Slots: point, mark, mark-active, kill-ring, kill-ring-yank-pointer,
mark-ring, pending-sel, last-action, active-search, event-ring,
live-action, action-pos.  The dispatcher swaps the struct in/out
around each fake's body via `helixel-mc--enter-cursor' /
`--leave-cursor', which call `helixel-pcs-swap-in' /
`helixel-pcs-swap-out'.  Real cursor uses the SAME struct
through `helixel-mc--save-main-state' — one type, one snapshot/restore
path, no per-var registry.  `post-command-hook` dispatches `this-command`
at each fake cursor when the command's `multiple-cursors` symbol property
is t (or default policy is `all`).  All N dispatches are wrapped in a
single `undo-amalgamate-change-group`.  `with-each-cursor` also binds
`inhibit-message t' so chatty commands (e.g. `;') don't echo N times.
`mark-active' lives inside the struct just like every other slot —
restoring CS sets globals' `mark-active' to the cursor's stored value.

### `;' multi-cursor: per-fake event ring
Each fake owns its own `helixel--action-ring' / `--live-action' /
`--action-pos' (slots of its `helixel-pc-state').  When `;'
broadcasts, each
fake runs `helixel-action--cycle-show' against its OWN ring —
first-press span selection, prev/next cycling, and group-start logic all
work via the real cycle code path with no mc-specific bookkeeping.
Caveats: fakes inherit NO history at spawn time; the ring populates
from commands run AFTER spawn.  `helixel--global-jump-log-push' is a
no-op during fake dispatch to avoid polluting the shared jump log.
C-o / C-i remain real-only.

### Multi-cursor + `.` / `@` integration
`helixel-repeat-edit' is whitelisted ON for multi-cursors: each
cursor's snapshotted `helixel-last-action' is replayed at its own
position.  `helixel-repeat-chain-end' commits a chain action whose
`by-command' stamp is `helixel-repeat-chain-end'; mc-integrate's
`action-commit-hook' handler detects this and broadcasts the new
chain tx to every fake cursor — so `@ ... ESC' on N cursors gives N
parallel chain applications, all in one undo step.

### ctx-lint keys
CTX_UNIQUE keys (`:kind`, `:cursor-offset`, `:moves`, `:command`) must not use raw `plist-get` outside `helixel-core.el`. Use `helixel-sel-*` accessors instead (`helixel-sel-field`, `helixel-sel-textobj-command`, etc.).

### Design notes
- `:moves-point-p` boolean on ops: t = op moves point itself, suppress auto-advance (kill, change, join-lines); nil = op leaves point alone (insert, replace, paste, indent, surround, ...).
- Insert replay: `pre-command-hook` captures `this-single-command-keys` (key-based replay) with `:text` fallback. No `:commands` layer. No `start-kbd-macro` used.
- Chain and non-chain share the same `helixel--repeat-advance` dispatch. Chain's `:action-list` runner iterates sub-actions at each advance target.
- `helixel-repeat-selection` (`M-.`) uses the same advance + preview path (no apply).
- Kind-specific all-buffer/all-dir logic lives in `helixel-repeat.el` via `:all-buffer-fn`/`:all-dir-fn` in the kind registry.
- `helixel--advance-search-last-pos` and `helixel--advance-search-edge-seen` are now fields on the `helixel-replay` struct (per-session scratch), reset implicitly by each new `helixel-with-replay` binding.

### Naming Convention for `helixel-sel` Accessors

All `helixel-sel` accessors follow a uniform pattern — no `get-` prefix:

- **Struct-slot accessors**: `helixel-sel-kind`, `helixel-sel-ctx`,
  `helixel-sel-advance`, `helixel-sel-count`
- **Kind-specific ctx accessors**: `helixel-sel-line-dir`,
  `helixel-sel-search-pattern`, `helixel-sel-textobj-command`, etc.
- **Closure-call accessors**: `helixel-sel-call-recreate`,
  `helixel-sel-call-display` (the `call-` prefix signals side-effect)
- **Generic ctx key accessor**: `helixel-sel-field`

The kind-specific accessors accept either a `helixel-sel` struct or a
raw ctx plist (for use inside recreate closures).  They are the
preferred way to read ctx fields.

  helixel--action-payload-* removed in favor of payload accessors.
  See `helixel-action-char`, `helixel-action-type`, `helixel-action-dir` for
  shared-payload-key convenience accessors (find-char, replace-char,
  surround).

### Mc undo-step architecture

When `helixel-multi-cursor-mode' is active and fake cursors exist, every
command dispatched to fakes is wrapped in an undo step via
`pre-command-hook' / `post-command-hook'.

  pre-hook  → `helixel-mc--undo-step-begin'
    - Captures cursor positions (real + fake) via
      `helixel-mc--capture-all-positions'
    - Pushes `(apply helixel-mc--undo-step-end-cb POSITIONS-BEFORE)'
      into `buffer-undo-list'

  post-hook → `helixel-mc--undo-step-finish' (after fake dispatch)
    - If buffer changed: pushes after-marker
      `(apply helixel-mc--undo-step-start-cb P1)', strips nil (undo
      boundaries) and number (point adjustments) entries from the
      step segment via `helixel-mc--filter-undo-step'.
    - Maintains `undo-equiv-table' for undo/redo chaining.

During undo, `primitive-undo' processes entries LIFO:
  1. `(apply mc--undo-step-start-cb P1)' — pushes redo counterpart
     `(apply mc--undo-step-end-cb P1)'
  2. Text changes undone
  3. `(apply mc--undo-step-end-cb P0)' — calls
     `helixel-mc--restore-all-positions' with P0, pushes redo
     counterpart `(apply mc--undo-step-start-cb P0)'

Cursors are identified by persistent integer IDs (ID 0 = real,
ID ≥ 1 = fake).  The `helixel-mc--cursors-by-id' hash table
provides O(1) lookup for cursor restoral.  Cursor IDs survive
undo/redo cycles unchanged.

**Do NOT use `undo-amalgamate-change-group' for mc dispatch** —
the undo-step management replaces it entirely.

### `preposition` slot

`helixel-action-preposition` is a first-class slot set by
`helixel-define-command's `:preposition` clause.  It is called BEFORE
the main runner in `helixel-action-replay`.  Single-write invariant
enforced by `cl-assert`.  No inheriting logic between events —
`helixel--live-action-set` preserves the existing preposition
unless the tx provides its own.

### `helixel-action-commit-hook`

Abnormal hook fired after every action commits to the ring.  Called
with one arg — the committed `helixel-action'.  Consumers: chain
accumulator (`helixel--chain-on-commit') and mc-integrate
(`helixel-mc--on-chain-end').  Extend here rather than touching
`helixel--action-commit' or the ring.

### `defsubst` Compilation Order

Several `defsubst` functions in `helixel-core.el` are inlined across
module boundaries.  The Makefile `FILES` order ensures that every file
that calls a `defsubst` defined in `helixel-core.el` is compiled AFTER
`helixel-core.elc`.  When adding a new file, place it after
`helixel-core.el` in the `FILES` list if it uses core accessors.

### Macro Definition Documentation

`helixel-define-command`, `helixel-define-operator`, and
`helixel-with-action-tracking` are documented in detail in
`docs/API.md` — including auto-injected behavior
(`helixel--tracking-open`, highlight clearing, visual-move tracking)
and a decision flowchart for choosing the right macro.
