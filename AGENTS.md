# AGENTS.md — helixel-mode

> AI reference. Architecture status: Phase 1-4 complete, Phase 5 partial,
> Phase 3 enhanced (helixel-with-edit-tracking now has guards;
> chain command migrated).
> See `docs/architecture-redesign-plan.md` §9 for full status.

## File Map

| File | Role |
|------|------|
| `helixel-data.el` | **Foundation layer**: `helixel-sel`, `helixel-event` structs, `helixel--last-tx`, kind registry, op registry, delimiter protocol. Zero helixel deps (cl-lib only). |
| `helixel-ring.el` | Event ring (buffer-local) + global jump-log. Commit, dedup, cap. |
| `helixel-action.el` | `;` cycling + C-o/C-i jump navigation (thin consumers of event-ring). |
| `helixel-repeat.el` | Dot-repeat (`.`) and selection-repeat (`,`): record, replay, insert recording, kind-specific advance/all-buffer/all-dir functions, line-pass helper. |
| `helixel-repeat-strategy.el` | Strategy protocol: `helixel-repeat-strategy` struct (advance/apply/reset/all-buffer-fn/all-dir-fn), prefix parsing, default/chain builders, generic repeat loops. |
| `helixel-chain.el` | Chain lifecycle: start/end/cancel, chain strategy builder, chain preview. |
| `helixel-register.el` | Register integration (kill-ring side). |
| `helixel-macros.el` | `helixel-define-command`/`helixel-define-operator`/`helixel-with-edit-tracking` macros. Extracted from helixel-state. |
| `helixel-state.el` | Modal state machine, pending-op system, keymap shells, insert entry/exit, visual state, minor modes. |
| `helixel-move.el` | Movement/selection commands (line/rect/word), rect change/replay. |
| `helixel-editing.el` | Editing commands (kill, change, copy, replace, yank) + selection recreate fns + op runners. Depends on helixel-state, helixel-move, helixel-data. Runtime require for helixel-swap (circular-dep avoidance). |
| `helixel-keymap.el` | All keymaps. Populates `helixel-state-map-alist`. |
| `helixel-search.el` | Search/find-char + `n`/`N` repeat + `helixel--active-search` state. |
| `helixel-textobj-engine.el` | Selection engine: motion-loop, select-block, up-paren, up-block, regex-block, word/symbol/sentence/paragraph forward. Delimiter builders. |
| `helixel-textobj.el` | Text object command macros + concretions + keymaps + recreate. Depends on textobj-engine. |
| `helixel-surround.el` | Surround add/delete/replace. |
| `helixel-swap.el` | Swap commands. |
| `helixel-shims.el` | `with-eval-after-load` shims for third-party integration. |
| `helixel.el` | Package entry point. |

### Test Files

| File | Covers |
|------|--------|
| `test/helixel-test-common.el` | `helixel-test-with-buffer` macro |
| `test/helixel-test-edit.el` | Edit transactions, sel struct, dot-repeat core tests |
| `test/helixel-test-action.el` | Action tracking and command execution |
| `test/helixel-test-repeat.el` | Line selection auto-advance, flip-dir |
| `test/helixel-test-repeat-chain.el` | Chain dot/comma tests |
| `test/helixel-test-repeat-new.el` | Movement, textobj, find-char, chain dot-repeat |
| `test/helixel-test-search.el` | Search, search history, n/N repeat |
| `test/helixel-test-move.el` | Movement/word/symbol/find-char |
| `test/helixel-test-keymap.el` | Keymap and define-key |
| `test/helixel-test-line.el` | Line-wise editing |
| `test/helixel-test-rect.el` | Rectangle selection and editing |
| `test/helixel-test-operator.el` | Operators (case, comment, fill, join) |
| `test/helixel-test-swap.el` | Swap |
| `test/helixel-test-textobj.el` | Text object and regex block |
| `test/helixel-test-register.el` | Register |
| `test/helixel-test-jump.el` | Jump navigation + all-buffer/all-dir repeat tests |

## Deps (one-way, compile-time — actual `require` graph)

```
helixel-data (cl-lib only, zero helixel deps)
  ├── helixel-ring
  │     ├── helixel-action  (; cycling, C-o/C-i — thin consumers)
  │     └── helixel-repeat → helixel-repeat-strategy → helixel-chain
  │       (chain also → helixel-repeat directly)
  │
  ├── helixel-register (zero helixel deps)
  ├── helixel-textobj-engine
  │     ├── helixel-textobj (→ data + engine)
  │     └── helixel-surround (→ data + engine)
  │
  ├── helixel-macros (→ data)
  └── helixel-state (→ macros + action + repeat + ring + register + textobj + surround)
        ├── helixel-move (→ state)
        ├── helixel-editing (→ state + move + data;
        │                    runtime → helixel-swap for circular-dep avoidance)
        │     ├── helixel-search (→ common)
        │     ├── helixel-keymap (→ state + move + common + chain + surround)
        │     └── helixel-swap (→ state)
        └── helixel-shims (→ state)
```

Notes:
- `helixel-editing.el` runtime-requires `helixel-swap` because
  `helixel-swap` requires `helixel-state`, creating a cycle if done at
  toplevel.  The runtime require is confined to op-runner code that
  calls `helixel--swap-source-type' and is documented in the source.
- `helixel--last-tx` lives in `helixel-data.el` (the shared data
  layer).  Every module that requires `helixel-data` (directly or
  transitively) can read/write the most recent transaction.

## Key Structs

### helixel-sel (selection descriptor)
```elisp
(cl-defstruct helixel-sel kind ctx recreate advance display)
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

### helixel-event (unified transaction and ring storage)
```elisp

 
```elisp
(cl-defstruct helixel-event op sel payload runner marker
              category subcat display timestamp buffer)

### helixel-repeat-strategy (dot-repeat strategy)
```elisp
(cl-defstruct helixel-repeat-strategy advance apply reset all-buffer-fn all-dir-fn)

## Key APIs

```elisp
;; ── Selection ──
(helixel-sel-create kind ctx recreate &optional display &rest extras) → struct
(helixel-sel-get-kind sel)          → symbol
(helixel-sel-call-recreate sel)     → recreates region
(helixel-sel-update-ctx sel k v)    → new sel
(helixel-sel-count sel)             → :count or 0
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
(helixel--make-tx op sel &rest kv) → struct
  ;; Special kv: :runner fn, :display str|fn — rest becomes :payload
(helixel-event-op tx)
(helixel-event-sel tx)
(helixel-event-payload tx)
(helixel-event-runner tx)
(helixel-event-marker tx)
(helixel-event-display tx)
(helixel--tx-with-payload tx k v)  → new tx with payload entry added
(helixel--copy-tx tx)              → shallow copy

;; ── Event ──
(helixel-event-op event)
(helixel-event-payload event)
(helixel-event-sel event)
(helixel-event-category event)
(helixel-event-subcat event)
(helixel--event->tx event)           → event (identity, kept for compat)

;; ── Kind Registry ──
(helixel-register-kind kind &rest props)
  ;; props: :recreate :advance :display :all-buffer-fn :all-dir-fn
(helixel--kind-advance kind)        → fn|nil
(helixel--kind-recreate kind)       → fn|nil
(helixel--kind-all-buffer-fn kind)  → fn|nil
(helixel--kind-all-dir-fn kind)     → fn|nil

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

## Build & Test

```bash
rm -f *.elc && make compile && make test   # always fresh compile before test
make lint                                   # checkdoc + package-lint + column-check + ctx-lint

## Pitfalls

### Always recompile after edits
Stale .elc silently hides changes. `rm -f *.elc && make compile` before testing.

### Docstring rules
- Max 80 cols per line (`make lint` checks this)
- Lisp symbols in backticks: `` `foo' ``
- Closing `"` must stay — missing it → "End of file during parsing"
- Open paren at column 0 in docstring must be escaped: `\\(`
- First line must be a complete sentence
- Function args must appear in docstring (uppercase)

### helixel--last-tx is NOT buffer-local (cross-buffer)
`. ` replays the last edit regardless of which buffer it was recorded in.

### helixel--make-tx keyword handling
`helixel--make-tx` extracts `:runner` and `:display` as special keys. All other keywords form the `:payload` plist. Never pass `:payload` as a keyword — spread payload keys individually, or use `helixel--copy-tx` + `setf`.

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

### ctx-lint keys
CTX_UNIQUE keys (`:kind`, `:cursor-offset`, `:moves`, `:command`) must not use raw `plist-get` outside `helixel-data.el`. Use `helixel-sel-*` accessors instead (`helixel-sel-get-field`, `helixel-sel-textobj-command`, etc.).

### Design notes
- `:repeat-advance` tag on ops gates auto-advance. nil = no advance (kill, change); 'line = line advance (insert-text).
- Insert replay: `pre-command-hook` captures `this-single-command-keys` (key-based replay) with `:text` fallback. No `:commands` layer. No `start-kbd-macro` used.
- Chain and non-chain share the same strategy architecture. Chain has a custom `:strategy-builder` in the op registry.
- `helixel-repeat-selection` (`,`) uses the same strategy + preview path.
- Kind-specific all-buffer/all-dir logic lives in `helixel-repeat.el` via `:all-buffer-fn`/`:all-dir-fn` in the kind registry.
- `helixel--advance-search-last-pos` and `helixel--advance-search-edge-seen` are reset per `helixel-repeat-edit` / `helixel-repeat-selection` call.
