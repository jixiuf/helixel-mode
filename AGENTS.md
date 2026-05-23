# AGENTS.md — helixel-mode

> AI reference. Add new mistakes to Pitfalls.

## File Map

| File | Role |
|------|------|
| `helixel-data.el` | **Unified data layer**: `helixel-sel` struct (with `advance` slot), `helixel-edit` struct, delimiter protocol, op registry. Zero helixel deps. |
| `helixel-action.el` | Action ring, `;` jumping. Depends on helixel-data. |
| `helixel-repeat.el` | Dot-repeat (`.`): record, replay, insert recording, advance functions (line/search/movement/textobj/find-char). Push/pop sel API. Chain lifecycle in `helixel-chain.el`, strategy in `helixel-repeat-strategy.el`. |
| `helixel-repeat-strategy.el` | Strategy builder: kind-agnostic 3-branch dispatch. Returns `helixel-repeat-action` from txs for both chain and non-chain. |
| `helixel-chain.el` | Chain lifecycle: start/end/cancel, post-command hook runner, chain op registration. No circular deps. |
| `helixel-state.el` | Modal state machine, minor modes, `helixel-define-command`/`helixel-define-operator` macros, insert entry/exit. |
| `helixel-move.el` | Movement/selection commands (line/rect/word), rect change/replay. |
| `helixel-common.el` | Editing commands (kill, change, copy, replace, yank) + selection recreate + op runners. |
| `helixel-keymap.el` | All keymaps. Populates `helixel-state-map-alist`. |
| `helixel-search.el` | Search/find-char + `n`/`N` repeat. |
| `helixel-textobj-engine.el` | Selection engine: motion-loop, select-block, up-paren, up-block, regex-block, word/symbol/sentence/paragraph forward. Delimiter builders included. |
| `helixel-textobj.el` | Text object command macros + concretions + keymaps + recreate. Depends on textobj-engine. |
| `helixel-textobj.el` | Text object command macros + concretions + keymaps + recreate. Depends on textobj-engine. |
| `helixel-surround.el` | Surround add/delete/replace. |
| `test/helixel-test-move.el` | Movement/word/symbol/find-char tests. |
| `test/helixel-test-keymap.el` | Keymap and define-key tests. |
| `test/helixel-test-line.el` | Line-wise editing tests. |
| `test/helixel-test-rect.el` | Rectangle selection and editing tests. |
| `test/helixel-test-operator.el` | Operator tests (case, comment, fill, join). |
| `test/helixel-test-swap.el` | Swap tests. |
| `test/helixel-test-textobj.el` | Text object and regex block tests. |
| `test/helixel-test-search.el` | Search and search history tests. |
| `test/helixel-test-action.el` | Action tracking and command execution tests. |
| `test/helixel-test-edit.el` | Edit transactions, sel struct, dot-repeat tests. |
| `test/helixel-test-jump.el` | Jump navigation tests. |
| `test/helixel-test-repeat.el` | Line selection auto-advance repeat tests. |
| `test/helixel-test-repeat-new.el` | Tests for movement (w/e/b), textobj, find-char, chain dot-repeat. |
| `test/helixel-test-register.el` | Register tests. |

## Deps (one-way)

```
helixel-data → helixel-action → helixel-repeat → helixel-repeat-strategy → helixel-state
            → helixel-move → helixel-common → helixel-keymap → helixel-search
            → helixel-chain (via helixel-keymap)

helixel-data → helixel-textobj-engine → helixel-textobj → helixel-surround

;; helixel-search pushes find-char sel via helixel-repeat.helixel--sel-push
;; (runtime require, no compile dep)
```

## Key Structs

### helixel-sel (selection descriptor)
```elisp
(cl-defstruct helixel-sel kind ctx recreate advance display)
;; CTX keys per kind:
;;   line          :dir (forward|backward) :count (int≥1)
;;   rect          :count (int≥1)
;;   movement      :moves ((CMD . COUNT)…) :inline-advance t
;;   textobj       :command :count :delimiter :inline-advance t
;;   search        :pattern :dir
;;   find-char     :char :type (next|till) :dir :inline-advance t
;;   surround      :delimiter
;;   insert-selection-*  :cursor-offset
;;   insert-search-offset :offset
;;
;; :inline-advance — when t, the advance fn creates the region
;;   as part of its positioning (movement, textobj, find-char).
;;   The strategy skips the extra recreate to avoid double-moving.
```

### helixel-edit tx (plist)
```elisp
(:op symbol :sel sel|nil :payload plist :marker marker :runner fn :display str|fn)
```

## Key APIs

```elisp
;; Selection
(helixel-sel-create kind ctx recreate &optional display &rest extras) → struct
  ;; extras may include :advance fn
(helixel-sel-get-kind sel)          → symbol
(helixel-sel-advance sel)           → fn|nil  (advance closure)
(helixel-sel-call-recreate sel)     → recreates region
(helixel-sel-update-ctx sel k v)    → new sel
(helixel-sel-count sel)             → :count or 0
;; Kind accessors (work on struct or raw ctx plist):
(helixel-sel-line-dir obj)          → :dir, default 'forward
(helixel-sel-line-count obj)        → :count, default 1
(helixel-sel-search-pattern obj)
(helixel-sel-search-dir obj)        → :dir, default 'forward

;; Pending-selection push/pop API
(helixel--sel-push sel)             ; selection cmds push
(helixel--sel-pop)                  → sel|nil  ; action cmds pop

;; Edit Transaction
(helixel-edit-make op sel &rest kv) → struct
(helixel-edit-op tx) (helixel-edit-sel tx) (helixel-edit-payload tx)
(helixel-edit-runner tx) (helixel-edit-with-payload tx k v)
(helixel-edit-equal-p a b)          → boolean (ignores :marker)

;; Repeat
(helixel--record-edit op &rest extra)  ; stores tx + ring
(helixel--execute-edit tx)             ; calls :runner
(helixel-repeat-edit &optional count)  ; bound to .
;; Repeat Strategy (chain + non-chain unified)
(helixel--repeat-strategy tx &optional reverse-p)  → helixel-repeat-action struct
;; Chain lifecycle
(helixel-repeat-chain-start/end/cancel)  ; interactive commands
```

## Build & Test

```bash
rm -f *.elc && make compile && make test   # always fresh compile before test
make lint                                   # checkdoc + package-lint + ctx-lint
```

## Pitfalls

### Always recompile after edits
Stale .elc silently hides changes. `rm -f *.elc && make compile` before testing.

### Test file parens
Inserting code between ERT tests risks paren mismatch → "End of file during parsing". Verify: `emacs --batch -Q -L . -l helixel-test.el`.

### Docstring rules
- Max 80 cols per line (`make lint` checks this)
- Lisp symbols in backticks: `` `foo' ``
- Closing `"` must stay — missing it → "End of file during parsing"
- `)` not alone on a line (package-lint)

### helixel--last-tx is buffer-local
Tests reading it cross-buffer fail. Use `let` or set it in the target buffer.

### Never trust match-data in helixel-insert / helixel-insert-after
Search hooks invalidate `match-data`. Use `(region-beginning)` / `(region-end)` instead.

### insert-text runner must NOT deactivate-mark
Selection is recreated before execute. `deactivate-mark` destroys it → invisible after `.`/`,`.

### helixel--recreate-line: use region-beginning/region-end, not line-beginning-position
After `helixel-select-line`, point is on the LAST selected line. `line-beginning-position` targets the wrong line for count≥2.

### Never set `defining-kbd-macro` to t in long-lived insert recording
`defining-kbd-macro` being non-nil causes `sit-for` (subr.el ~line 3877) to
skip its `read-event` wait entirely — it returns immediately without
actually sleeping.  This breaks eglot's LSP completion pipeline and any
other code that relies on `sit-for` for timing.  Use manual key collection
via hooks instead of `start-kbd-macro` / `end-kbd-macro` for insert-mode
recording that spans more than a single atomic command.

### sed line numbers shift
Use `git checkout` + pattern-based scripts instead of `sed -i 'N,Md'`.

### Design notes
- `:repeat-advance` tag on ops gates auto-advance. `helixel-repeat-advance-alist` maps kind→advance fn.
- Insert replay: `pre-command-hook` captures both `this-command` (keymap-independent replay) and
  `this-single-command-keys` (key-based fallback).  `:commands` is primary, `:keys` fallback,
  `:text` last resort.  No `start-kbd-macro` used — avoids `defining-kbd-macro` t side-effect.
- Movement `.` replays move sequence, not absolute positions (matches Helix/Vim).
- Swap-source stored as text property on kill-ring string (not overlay).
- `executing-kbd-macro` inhibits `helixel--record-edit`.
- Chain and non-chain share the same repeat-strategy architecture. The only difference
  is the execute-fn in `helixel-repeat-action`: kmacro replay for chain, op runner for non-chain.
- Chain ops store `init-ctx` as `helixel-sel` in tx (no `:chain-advance` payload).
- `helixel-repeat-selection` (`,`) uses the same strategy + preview path for both chain and non-chain.
