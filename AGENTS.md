# AGENTS.md — helixel-mode

> User docs: `docs/USER-GUIDE.org` | Extension API: `docs/API.org`
> Architecture: `docs/ARCHITECTURE.org` | Debug: `docs/DEBUG-SKILL.org`

## File Map

| File | Role |
|------|------|
| `helixel-debug.el` | **Error capture**: `helixel-debug` toggle, per-buffer error ring with backtraces, `helixel--with-debug-log` macro, debug-log viewer mode. Zero helixel deps (cl-lib only); required by core. |
| `helixel-core.el` | **Pure data layer**: `helixel-sel` base struct + protocol generics, `helixel-action` struct, `helixel-last-action`, op registry, surround-pair entry queries, category matcher, selection-type helpers, replay context. Depends only on `helixel-debug`. |
| `helixel-motion.el` | **Motion recording + repeat**: `helixel--last-motion` struct, `helixel-record-motion`, motion repeater registry, command-reverse property, motion repeat/select category defcustoms, `helixel-repeat-last-motion` (`,`) + `helixel--motion-flip-dir` (`-,`). Depends only on core. |
| `helixel-register.el` | **Named registers**: `helixel-register-backends` (kill-ring/clipboard/primary/register-alist), `helixel--current-register`, numbered delete registers, `helixel--kill-new`, swap-source register. Depends only on core. |
| `helixel-ring.el` | **Event storage + history navigation**: `helixel--action-ring` (commit/dedup/cap), `helixel--global-jump-log`, `helixel--tracking-open`, `helixel--cancel-action`, `helixel--live-action-set`, live-event management, generic grouped-ring queries (`helixel--gr-*`), `;' action-cycle, C-o/C-i jump commands. |
| `helixel-macros.el` | **Command definition macros**: `helixel-define-command`, `helixel-define-operator`, `helixel-with-action-tracking`. |
| `helixel-repeat.el` | Dot-repeat (`.`) and selection-repeat (`M-.`): record (`helixel-record-action`), replay, unified `helixel--repeat-advance` (delegates to `helixel-sel-advance-fn' methods), all-buffer/all-dir dispatch, kind-specific `:all-buffer-fn`/`:all-dir-fn` via cl-defgeneric, line-pass helper, interactive entry points.  Also includes insert-mode key + text recording (segment-based capture via after-change-functions + `helixel--keyrec-capture`) — each insert-mode command becomes either `(:keys VEC)` (no buffer change) or `(:text STR :delete-before N :offset O)` (any buffer change).  Replay helper `helixel--execute-keys' accepts canonical segment lists only; `helixel--repeat-get-keys' is the single place that normalizes a raw key vector/string into segment form.  **Chain lifecycle** (start/end/cancel): chain accumulates a list of `helixel-action' values committed during the chain (via `helixel-action-commit-hook') and stores it as `:action-list' payload; replay iterates the list and `helixel-action-replay's each entry.  No kmacro / keystroke capture. |
| `helixel-state.el` | Modal state machine, pending-op system, keymap shells, insert entry/exit, visual state, minor modes, shared kill core. |
| `helixel-move.el` | Movement/selection commands (line/rect/word), rect change/replay. |
| `helixel-editing.el` | Editing commands (kill, change, copy, replace, yank) + selection recreate fns + op runners + `helixel--replace-region` + `helixel--delete-selection` + `helixel--swap-source-type`.  **Swap commands** (same-buffer and cross-buffer) live at the end of this file. |
| `helixel-keymap.el` | All keymaps. Populates `helixel-state-map-alist`. 7 `declare-function` for flymake/eglot (third-party only). |
| `helixel-search.el` | Search/find-char + `n`/`N` repeat + `helixel--active-search` state + invisible-text search filter loop. |
| `helixel-next-error.el` | **Next-error (grep/compile) snapshot**: pure-data `helixel-ne--target` vector, tick-invalidated cache, index navigation (`helixel-ne--step` / `--step-in-file` over shared `helixel-ne--step-index`), grep face-run column extraction, `next-error` kind registration, `next-error-hook` integration (`helixel-ne--after-jump`; every visited target buffer is seeded with buffer-local repeat state via `helixel-ne--seed-repeat-state`). |
| `helixel-textobj-engine.el` | Forward primitives (forward-word/WORD/symbol/sentence/paragraph/function), generic select-inner/a-object + restricted variants, range struct, type-properties, motion-loop / with-restriction macros, activate-textobj-range, recreate-textobj + advance-textobj. Pure primitives, no per-textobj-type code. |
| `helixel-textobj-pair.el` | **Delimiter protocol** (`helixel-delimiter` struct, `helixel-delimiter-bounds`, `helixel--generic-bounds-next/-previous` navigation) + paren / quote / xml-tag selection (the matched-pair families): get-block-range, select-block, up-paren, select-paren, forward-quote, select-quote, select-xml-tag, tag-* helpers, make-pair-delimiter, make-tag-delimiter. |
| `helixel-textobj-block.el` | Regex / fenced block text objects: up-regex-block, select-regex-block, up-block-at-point, select-block-at-point, block-textobj-alist (customs), block-spec-at-point, block-adjust-for-jump, regex-adjust-for-jump, make-block-delimiter, make-regex-delimiter. |
| `helixel-textobj-marks.el` | User-facing surface: define-mark-pair/-quote/-object/-regex-textobj macros, mark-inner-*/mark-a-* commands (including tag and block), tree-sitter helper, all default registrations, `textobj' kind registration. |
| `helixel-textobj.el` | Facade: requires engine, pair, block, marks. |
| `helixel-surround.el` | Surround add/delete/replace. |
| `helixel-mc-core.el` | **Multi-cursor core + target computation + integration**: fake-cursor overlays, per-cursor state vars, dispatch loop via `post-command-hook` / `pre-command-hook`, cursor-ID hash table, undo-step management (begin/finish + `buffer-undo-list` `apply` entry injection for cursor-position persistence across undo/redo), whitelist policy, `helixel-multi-cursor-mode`.  Target computation: `helixel-mc--realize-targets`, advance-walk fallback, `helixel-mc--spawn-from-sel/-line/-rect/-find-char`, `helixel-mc-spawn-fn' methods.  **Integration glue** (end of file): dot-repeat / chain / insert per-cursor execution + atomic undo. |
| `helixel-mc-spawn.el` | **High-level user commands**: toggle, add-cursor-here, edit-lines, mark-next-like-this, primary/content rotation, keep/remove-matching, merge/trim/align, split-on-regex, restore-cursors. |
| `helixel-shims.el` | `with-eval-after-load` shims for third-party integration (info, help-mode, shortdoc, man, woman, eww) + multi-cursor completion-preview shim. 29 `declare-function` (all third-party). |
| `helixel-treesit-core.el` | **Tree-sitter foundation**: readiness gates, node utilities, query provider (evil-textobj-tree-sitter integration), capture normalization, object resolution, index cache, selection activation, kind registration, type specification table. Soft-depends on `treesit` and `evil-textobj-tree-sitter-core`. |
| `helixel-treesit-commands.el` | **Tree-sitter command layer**: data-driven `helixel-ts--define-type' macro generates textobj, inner-move, outer-nav commands for each semantic type. Also expand/shrink, sibling nav, comma-repeat repeater. Requires `helixel-treesit-core' + `helixel-macros'. |
| `helixel-treesit.el` | **Tree-sitter facade**: `helixel-treesit-setup' entry point, dispatch var generation, keybinding registration, motion reverse/repeater wiring. Requires both core + commands. |
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
| `test/helixel-test-next-error.el` | Next-error snapshot: grep face-run extraction, targets-for-file, build+cache, step/step-in-file across files, after-jump sync, cross-buffer n/N |
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
| `test/helixel-test-treesit.el` | Tree-sitter text objects and motions (helixel-ts-* commands) |

## Deps (one-way, compile-time — actual `require` graph)

```
helixel-debug (cl-lib only, zero helixel deps)
  │
  └── helixel-core (→ debug)
        │
        ├── helixel-motion (→ core)
        │     └── consumed by: move, search, next-error, engine,
        │         marks, treesit-commands, mc-spawn, shims
        ├── helixel-register (→ core)
        │     └── consumed by: search, editing
        ├── helixel-ring (→ core)
        │     └── helixel-macros (→ core + ring)
        │           └── helixel-treesit-core (→ core)
        │     └── helixel-treesit-commands (→ treesit-core + macros
        │                                 + motion)
        │           └── helixel-treesit (facade: requires core + commands)
        │
        ├── helixel-textobj-engine (→ core + motion)
        │     ├── helixel-textobj-pair (→ textobj-engine)
        │     │     └── helixel-textobj-block (→ core + textobj-engine
        │     │                              + textobj-pair)
        │     │           └── helixel-textobj-marks (→ textobj-engine
        │     │                                    + textobj-pair
        │     │                                    + textobj-block
        │     │                                    + motion)
        │     └── helixel-textobj (facade: requires the four above)
        │     └── helixel-surround (→ core + ring + repeat + textobj)
        │
        ├── helixel-repeat (→ core + ring + macros; includes chain)
        │
        ├── helixel-mc-core (→ core + ring + repeat; includes integrate)
        │     └── helixel-mc-spawn (→ core + mc-core + search + motion)
        │
        └── helixel-state (→ core + ring + macros + repeat
                            + textobj + surround)
              │
              ├── helixel-move (→ state + macros + motion)
              │     │
              │     └── helixel-editing (→ state + move + core + macros
              │                          + search + register + rect;
              │                          includes swap)
              │           │
              │           ├── helixel-search (→ state + core + macros
              │           │                   + repeat + move + motion
              │           │                   + register)
              │           │     └── helixel-next-error (→ core + search
              │           │                           + motion)
              │           │
              │           └── helixel-keymap (→ state + move + editing
                                                + surround + search
                                                + mc-core + mc-spawn)
              │
              └── helixel-shims (→ state + keymap + motion)
```

Notes:
- **Zero circular deps.**
- `helixel--replace-region` lives in `helixel-editing.el`.
- `helixel--delete-selection` lives in `helixel-editing.el`.
- `helixel--swap-source-type` lives in `helixel-editing.el`.
- `helixel-last-action` lives in `helixel-core.el` (buffer-local).
  Every module that requires `helixel-core` can read/write the most recent transaction.
- `declare-function` counts are minimal and only for third-party packages:
  - `helixel-keymap.el`: 7 (flymake, eglot)
  - `helixel-repeat.el`: 0
  - `helixel-textobj-engine.el`: 0
  - `helixel-textobj-pair.el`: 0
  - `helixel-textobj-block.el`: 0
  - `helixel-textobj-marks.el`: 0
  - `helixel-treesit.el`: 18 (15 internal cross-module + 3 third-party evil-textobj-tree-sitter)
  - `helixel-shims.el`: 29 (info, help-mode, shortdoc, man, woman, eww) + 1 internal (next-error hook)
  - `helixel-mc-core.el`: 5 internal (helixel-state ×2, next-error snapshot ×3) + 1 third-party (undo-tree)

## Key Structs

### helixel-sel (selection descriptor)
```elisp
(cl-defstruct (helixel-sel (:constructor nil)) span inline-advance)
;; Abstract base; concrete per-kind structs include it
;; (helixel-line-sel, -rect-sel, -movement-sel, -search-sel,
;;  -find-char-sel, -textobj-sel, -surround-sel, -insert-*-sel,
;;  -next-error-sel, -treesit-sel).
;; Protocol dispatches via cl-defgeneric (see below).
;; Slots per concrete struct (constructor `make-helixel-<kind>-sel'):
;;   line          count dir entry-kind
;;   rect          count
;;   movement      moves ((CMD . COUNT)…)
;;   textobj       command count delimiter
;;   search        pattern dir n-count regexp
;;   find-char     char type (next|till) dir n-count
;;   surround      delimiter
;;   insert-selection-*  (no extra slots)
;;   insert-search-offset offset
;;   treesit       base part level count query start end command

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
(make-helixel-<kind>-sel :slot v …)  ; only constructor form (no sel-create)
(helixel-sel-kind sel)          → struct type symbol (e.g. 'helixel-line-sel)
(helixel-sel-call-recreate sel) → recreates region via cl-defgeneric
(helixel-sel-update-ctx sel k v)→ copy with slot K set (keyword→slot name)
(helixel-sel-count sel)         → count or 0 (generic; per-struct methods)
;; Slot accessors come from cl-defstruct: `helixel-<kind>-sel-<slot>'.
;; Multi-kind slot concepts dispatch via generics with nil defaults:
(helixel-sel-entry-kind obj)    → :entry-kind (line/search), else nil
(helixel-sel-n-count obj)       → :n-count (search/find-char), else nil
(helixel-sel-insert-cursor-offset obj)

;; ── Pending selection ──
(helixel--sel-push sel)             ; selection cmds push
(helixel--sel-pop)                  → sel|nil  ; edit cmds pop

;; ── Transaction ──
(helixel-action-create op sel payload &key runner display) → struct  ;; returns helixel-action
  ;; payload: one explicit plist (:text :keys :action-list ...), never parsed
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

;; ── Sel Protocol Generics (cl-defgeneric, methods per struct) ──
(helixel-sel-recreate sel)          ; recreate region at point
(helixel-sel-display sel)           → short string (default: kind name)
(helixel-sel-flip-dir sel)          → new sel with direction flipped|nil
(helixel-sel-advance-fn sel)        → advance fn (tx tag)|nil
(helixel-sel-all-buffer-fn sel)     → all-buffer repeat fn|nil
(helixel-sel-all-dir-fn sel)        → all-dir repeat fn|nil
(helixel-sel-region-type sel)       → line|rect|textobj|nil
(helixel-mc-spawn-fn sel)           → spawn fn symbol|nil (walk fallback)
(helixel-sel-skip-reverse-exchange-p kind)  ; eql-dispatch, nil default
;; Base-type methods provide nil defaults; each struct defines only
;; the methods it supports, next to the struct in the owning module.

;; ── Op Registry ──
(helixel-register-op op &rest props)
  ;; props: :runner :display :self-advancing
(helixel--op-runner op)         → fn
(helixel--op-self-advancing-p op)        → boolean

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
make lint                                   # checkdoc + package-lint + column-check + check-declare
make depgraph                               # regenerate docs/DEPGRAPH.org from `require' edges

## Refactoring Best Practices
### Keep Lint and Tests Passing

```markdown
After refactoring, run make test and confirm 0 failures.
If semantics shift and a test must change, ask me first.
```

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

### helixel-action-create payload argument
`helixel-action-create` takes the payload as ONE explicit positional argument (a plist), with `:runner`/`:display` as keyword-only arguments. Payload entries named `:runner` or `:display` are safe. Never pass payload keys inline as `&rest` pairs — collect them in a `(list ...)` form first, or use `helixel-action-shallow-copy` + `setf`.

### Marker ownership (action structs)
Every `helixel-action` owns 2-3 markers (`mark-region` cons + `start-point`). Ownership rules:
- **Ring entries** are owned by `helixel--action-ring`; released at cap eviction (`helixel--action--ring-cap`) only.
- **Live action** is owned by `helixel--live-action`; released by commit (after deep-copy) and by every cancel path (`helixel--cancel-action`, search cancel).
- **Dedup path**: on a dedup hit the fresh deep copy is released immediately and the ring-front entry is reused as the canonical object — never release a struct that sits in the ring.
- `helixel-last-action` is a REFERENCE, never an owner (it points at a ring entry, or transiently at a reconstructed tx whose markers are GC'd on overwrite).
- **mc fake cursor rings SHARE action structs with the real ring** (`:fresh (copy-sequence ...)` copies only the list spine). Do NOT release their markers in `helixel-mc--pcs-release` — that would corrupt the real ring. Fake-owned entries pushed during dispatch are GC'd when the fake is destroyed.

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

### Zero-width search patterns ($, ^, \b, \B, \<, \>) and infinite loops
`helixel-search--guard-repeat-advance` runs two guards in order:
  1. **Repeat guard** — steps past same-position zero-width matches
     and re-searches (handles \b, \B, \<, \> at fixed positions).
  2. **Edge guard** — blocks any second zero-width match at
     point-min/point-max (handles \=`$' at shifting point-max).
The order is deliberate: repeat-first ensures word-boundary patterns
at point-min don't trigger false edge-guard blocks.
`search-last-pos` and `search-edge-seen` are fields on the
`helixel-replay` struct, reset per `helixel-with-replay` binding.

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
`by-command' stamp is `helixel-repeat-chain-end'; mc-core's
`action-commit-hook' handler detects this and broadcasts the new
chain tx to every fake cursor — so `@ ... ESC' on N cursors gives N
parallel chain applications, all in one undo step.

### Raw plist-get on a sel
Sels are cl-defstruct vectors — raw `plist-get` on one silently returns nil (the Phase 3.2 `helixel--with-span` regression was exactly this).  Always use the struct slot accessors (`helixel-<kind>-sel-<slot>`) or the multi-kind generics (`helixel-sel-entry-kind`, `helixel-sel-n-count`, `helixel-sel-count`, `helixel-sel-insert-cursor-offset`).  For cross-module slot access without a compile-time struct dependency, either add a `declare-function ... t` (FILEONLY — check-declare cannot see generated accessors) or use `(cl-struct-slot-value type-var 'slot sel)` with a *variable* type (a literal unknown type triggers cl-typep optimization-failure warnings).

### Design notes
- `:self-advancing` boolean on ops: t = op handles its own positioning, suppress auto-advance (kill, change, join-lines); nil = op leaves point alone (insert, replace, paste, indent, surround, ...).
- Insert replay: `pre-command-hook` captures `this-single-command-keys` (key-based replay) with `:text` fallback. No `:commands` layer. No `start-kbd-macro` used.
- Chain and non-chain share the same `helixel--repeat-advance` dispatch. Chain's `:action-list` runner iterates sub-actions at each advance target.
- `helixel-repeat-selection` (`M-.`) uses the same advance + preview path (no apply).
- Kind-specific all-buffer/all-dir logic dispatches via `helixel-sel-all-buffer-fn`/`helixel-sel-all-dir-fn` methods (default nil in `helixel-repeat.el`).
- `search-last-pos` and `search-edge-seen` are fields on the `helixel-replay` struct (per-session scratch), reset implicitly by each new `helixel-with-replay` binding. The repeat guard runs first so word-boundary patterns (\b, \B, \<, \>) at point-min don't trigger false edge-guard blocks.

### Naming Convention for `helixel-sel` Accessors

All `helixel-sel` accessors follow a uniform pattern — no `get-` prefix:

- **Base-slot accessors**: `helixel-sel-kind`, `helixel-sel-span`,
  `helixel-sel-inline-advance` (from the base cl-defstruct)
- **Concrete-slot accessors**: `helixel-line-sel-dir`,
  `helixel-search-sel-pattern`, `helixel-textobj-sel-command`, etc.
  (generated by each cl-defstruct; take structs only, never plists)
- **Multi-kind generics**: `helixel-sel-count`, `helixel-sel-entry-kind`,
  `helixel-sel-n-count`, `helixel-sel-insert-cursor-offset`
- **Closure-call accessors**: `helixel-sel-call-recreate`,
  `helixel-sel-call-display` (the `call-` prefix signals side-effect)

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
accumulator (`helixel--chain-on-commit') and mc-core
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
`docs/API.org` — including auto-injected behavior
(`helixel--tracking-open`, highlight clearing, visual-move tracking)
and a decision flowchart for choosing the right macro.
