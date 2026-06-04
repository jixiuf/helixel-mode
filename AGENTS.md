# AGENTS.md — helixel-mode

## File Map

| File | Role |
|------|------|
| `helixel-core.el` | **Pure data layer**: `helixel-sel`, `helixel-edit` structs, `helixel--last-edit`, kind registry, op registry, delimiter protocol, transaction helpers, swap-source type, keyrec utilities. Zero helixel deps (cl-lib only). |
| `helixel-ring.el` | **Event storage**: `helixel--event-ring` (commit/dedup/cap), `helixel--global-jump-log`, `helixel--tracking-open`, `helixel--cancel-action`, `helixel--live-edit-set`, live-event management. |
| `helixel-macros.el` | **Command definition macros**: `helixel-define-command`, `helixel-define-operator`, `helixel-with-edit-tracking`. |
| `helixel-register.el` | **Named register system**: register backends (kill-ring, clipboard, primary), `helixel--kill-new`, `helixel--current-kill`, `helixel--yank`, register-aware wrappers. |
| `helixel-action.el` | `;` cycling + C-o/C-i jump navigation (thin consumers of event-ring). |
| `helixel-insert-record.el` | Insert-mode key recording (pre-command-hook based); replay helper `helixel--execute-keys`. |

| `helixel-repeat-strategy.el` | `helixel-repeat-strategy` struct, default strategy builder, dispatch, generic advance/apply/preview loops. |
| `helixel-repeat.el` | Dot-repeat (`.`) and selection-repeat (`,`): record, replay, kind-specific advance/all-buffer/all-dir functions, line-pass helper, interactive entry points. |
| `helixel-chain.el` | Chain lifecycle: start/end/cancel, chain strategy builder, chain preview. |
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
| `helixel-mc-core.el` | **Multi-cursor core**: fake-cursor overlays, per-cursor state vars, dispatch loop via `post-command-hook`, whitelist policy, `helixel-multi-cursor-mode`. |
| `helixel-mc-targets.el` | **Target computation**: `helixel-mc--realize-targets`, advance-walk fallback, `helixel-mc-spawn-from-sel/-line/-rect/-find-char`, kind registry hooks. |
| `helixel-mc-spawn.el` | **High-level user commands**: toggle, add-cursor-here, edit-lines, mark-next-like-this, primary/content rotation, keep/remove-matching, merge/trim/align, split-on-regex, restore-cursors. |
| `helixel-mc-integrate.el` | Glue: dot-repeat / chain / insert per-cursor execution + atomic undo. |
| `helixel-shims.el` | `with-eval-after-load` shims for third-party integration (info, help-mode, shortdoc, man, woman, eww). 29 `declare-function` (all third-party). |
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
| `test/helixel-test-mc.el` | Multi-cursor: create/clear, whitelist, with-each-cursor isolation, dispatch insert, spawn-from-line, edit-lines, add-cursor-here, mark-next-like-this, apply-last-edit, kill-ring isolation |

## Deps (one-way, compile-time — actual `require` graph)

```
helixel-core (cl-lib only, zero helixel deps)
  │
  ├── helixel-ring (→ core)
  │     ├── helixel-macros (→ core + ring)
  │     └── helixel-action (→ core + ring)
  │
  ├── helixel-register (→ core)
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
  ├── helixel-repeat (→ core + action)   [action→ring→core]
  │     └── helixel-chain (→ core + macros + repeat)
  │
  ├── helixel-mc-core (→ core)
  │     ├── helixel-mc-spawn (→ core + mc-core)
  │     └── helixel-mc-integrate (→ core + mc-core + repeat + chain)
  │
  └── helixel-state (→ core + ring + macros + register + action
                      + repeat + textobj + surround)
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
- `helixel--delete-selection` lives in `helixel-editing.el` (moved from state.el in Phase 5).
- `helixel--swap-source-type` lives in `helixel-core.el`.
- `helixel--last-edit` lives in `helixel-core.el` (buffer-local).
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

### helixel-edit (unified transaction and ring storage)
```elisp
(cl-defstruct helixel-edit op sel payload runner mark-region
              category subcat display timestamp buffer)
```

### helixel-repeat-strategy (dot-repeat strategy)
```elisp
(cl-defstruct helixel-repeat-strategy advance apply reset all-buffer-fn all-dir-fn)
```

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
(helixel-edit-create op sel &rest kv) → struct
  ;; Special kv: :runner fn, :display str|fn — rest becomes :payload
(helixel-edit-op tx)
(helixel-edit-sel tx)
(helixel-edit-payload tx)
(helixel-edit-runner tx)
(helixel-edit-mark-region tx)
(helixel-edit-display tx)
(helixel-edit-with-payload tx k v)  → new tx with payload entry added
(helixel-edit-copy tx)              → shallow copy

;; ── Event ──
(helixel-edit-op event)
(helixel-edit-payload event)
(helixel-edit-sel event)
(helixel-edit-category event)
(helixel-edit-subcat event)

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
  ;; props: :runner :display :repeat-advance :strategy-builder
(helixel--op-runner op)         → fn
(helixel--op-advance op)        → nil|'line|fn
(helixel--op-strategy-builder op) → fn|nil

;; ── Repeat ──
(helixel--record-edit op &rest extra)  ; stores tx + commits event
(helixel--execute-edit tx)             ; calls :runner on tx
(helixel-repeat-edit &optional prefix) ; bound to .
(helixel-repeat-selection &optional prefix) ; bound to ,
(helixel--build-strategy edit &optional reverse-p) → strategy struct

;; ── Chain ──
(helixel-repeat-chain-start/end/cancel)  ; interactive commands
;;   q = start, ESC = end (normal map), C-g = cancel

;; ── Multi-cursor (`s' prefix + top-level) ──
(helixel-mc-toggle)              ; s s  toggle (spawn from sel / clear)
(helixel-mc-clear-all)           ; s SPC / s ,
(helixel-mc-add-cursor-here)     ; s a / s A
(helixel-mc-edit-lines)          ; s x  line-mode → region / char-mode → col
(helixel-mc-mark-next-like-this) ; s n / s p / s N / s P / s u / s U
(helixel-mc-apply-last-edit)     ; s .
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

### Docstring rules
- Max 80 cols per line (`make lint` checks this)
- Lisp symbols in backticks: ``` `foo' ```
- Closing `"` must stay — missing it → "End of file during parsing"
- Open paren at column 0 in docstring must be escaped: `\\(`
- First line must be a complete sentence
- Function args must appear in docstring (uppercase)

### helixel--last-edit is buffer-local
`. ` replays the last edit from the current buffer only.

### helixel-edit-create keyword handling
`helixel-edit-create` extracts `:runner` and `:display` as special keys. All other keywords form the `:payload` plist. Never pass `:payload` as a keyword — spread payload keys individually, or use `helixel-edit-copy` + `setf`.

### Never trust match-data in helixel-insert / helixel-insert-after
Search hooks invalidate `match-data`. Use `(region-beginning)` / `(region-end)` instead.

### insert-text runner must NOT deactivate-mark
Selection is recreated before execute. `deactivate-mark` destroys it → invisible after `.`/`,`.

### helixel--recreate-line: use region-beginning/region-end
After `helixel-select-line`, point is on the LAST selected line. `line-beginning-position` targets the wrong line for count≥2.

### Never set `defining-kbd-macro` to t in long-lived insert recording
`defining-kbd-macro` being non-nil causes `sit-for` to skip its `read-event` wait. Use manual key collection via hooks instead.

### transient-mark-mode and region extension
When `transient-mark-mode` is on, `helixel-select-line-up`/`helixel-select-line` detect an active region and enter "extending" mode. Call `(deactivate-mark)` before recreate to ensure a fresh region.

### Zero-width search patterns ($, ^) and infinite loops
`helixel--repeat-advance-search` uses `helixel--advance-search-edge-seen` to prevent infinite loops with zero-width patterns at buffer edges. Both `helixel-repeat-edit` and `helixel-repeat-selection` reset this flag.

### Strategy all-buffer-fn recursion
`helixel--all-buffer-search` for non-entry-kind must NOT call `helixel--repeat-all-buffer` with a strategy that has `:all-buffer-fn` set (would recurse). Instead it does the scan inline.

### Multi-cursor (mc) — fake cursor model
`helixel-mc-core.el` provides REAL fake cursors with per-cursor state
(point/mark/mark-active + kill-ring, pending-sel, last-event,
active-search, **event-ring, live-event, action-pos**).  Per-cursor
state is registered via `helixel-mc-register-cursor-var'; the dispatcher
snapshots/restores it around each fake's body via `--enter-cursor' /
`--leave-cursor'.  `post-command-hook` dispatches `this-command` at each
fake cursor when the command's `multiple-cursors` symbol property is t
(or default policy is `all`).  All N dispatches are wrapped in a single
`undo-amalgamate-change-group`.  `with-each-cursor` also binds
`inhibit-message t' so chatty commands (e.g. `;') don't echo N times.
`mark-active' must NOT be in `helixel-mc-cursor-vars' — it would
clobber the per-cursor flag set at creation time; it lives on the
overlay as a property.

### `;' multi-cursor: per-fake event ring
Each fake owns its own `helixel--event-ring' / `--live-event' /
`--action-pos' (registered as cursor-vars).  When `;' broadcasts, each
fake runs `helixel-action--cycle-show' against its OWN ring —
first-press span selection, prev/next cycling, and group-start logic all
work via the real cycle code path with no mc-specific bookkeeping.
Caveats: fakes inherit NO history at spawn time; the ring populates
from commands run AFTER spawn.  `helixel--global-jump-log-push' is a
no-op during fake dispatch to avoid polluting the shared jump log.
C-o / C-i remain real-only.

### Multi-cursor + `.` / `q` integration
`helixel-repeat-edit' is whitelisted ON for multi-cursors: each
cursor's snapshotted `helixel--last-edit' is replayed at its own
position.  After `helixel-repeat-chain-end' an `:after' advice
broadcasts the new chain tx to every fake cursor and applies it once
immediately — so `q ... ESC' on N cursors gives N parallel chain
applications, all in one undo step.

### ctx-lint keys
CTX_UNIQUE keys (`:kind`, `:cursor-offset`, `:moves`, `:command`) must not use raw `plist-get` outside `helixel-core.el`. Use `helixel-sel-*` accessors instead (`helixel-sel-field`, `helixel-sel-textobj-command`, etc.).

### Design notes
- `:repeat-advance` tag on ops gates auto-advance. nil = no advance (kill, change); 'line = line advance (insert-text).
- Insert replay: `pre-command-hook` captures `this-single-command-keys` (key-based replay) with `:text` fallback. No `:commands` layer. No `start-kbd-macro` used.
- Chain and non-chain share the same strategy architecture. Chain has a custom `:strategy-builder` in the op registry.
- `helixel-repeat-selection` (`,`) uses the same strategy + preview path.
- Kind-specific all-buffer/all-dir logic lives in `helixel-repeat.el` via `:all-buffer-fn`/`:all-dir-fn` in the kind registry.
- `helixel--advance-search-last-pos` and `helixel--advance-search-edge-seen` are reset per `helixel-repeat-edit` / `helixel-repeat-selection` call.

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

### `defsubst` Compilation Order

Several `defsubst` functions in `helixel-core.el` are inlined across
module boundaries.  The Makefile `FILES` order ensures that every file
that calls a `defsubst` defined in `helixel-core.el` is compiled AFTER
`helixel-core.elc`.  When adding a new file, place it after
`helixel-core.el` in the `FILES` list if it uses core accessors.

### Macro Definition Documentation

`helixel-define-command`, `helixel-define-operator`, and
`helixel-with-edit-tracking` are documented in detail in
[docs/MACROS.md](docs/MACROS.md) — including auto-injected behavior
(`helixel--tracking-open`, highlight clearing, visual-move tracking)
and a decision flowchart for choosing the right macro.
