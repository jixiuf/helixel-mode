# helixel-mode API Reference

API for extending helixel with custom commands, text objects, operators,
motion repeaters, and multi-cursor integrations.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Defining Commands](#defining-commands)
  - [`helixel-define-command`](#helixel-define-command)
  - [`helixel-define-movement`](#helixel-define-movement)
  - [`helixel-define-operator`](#helixel-define-operator)
- [Registering Operators](#registering-operators)
  - [`helixel-register-op`](#helixel-register-op)
- [Registering Selection Kinds](#registering-selection-kinds)
  - [`helixel-register-kind`](#helixel-register-kind)
  - [Kind Protocol Methods](#kind-protocol-methods)
- [Recording Edits](#recording-edits)
  - [`helixel-record-action`](#helixel-record-action)
  - [`helixel-action-create`](#helixel-action-create)
  - [`helixel-action-replay`](#helixel-action-replay)
- [Custom Text Objects](#custom-text-objects)
  - [Thing-based Text Objects](#thing-based-text-objects)
  - [Regex Text Objects](#regex-text-objects)
  - [Pair & Quote Text Objects](#pair--quote-text-objects)
  - [Tree-sitter Text Objects](#tree-sitter-text-objects)
- [Motion Repeat](#motion-repeat)
  - [`helixel-register-motion-repeater`](#helixel-register-motion-repeater)
  - [`helixel-record-motion`](#helixel-record-motion)
- [Keybindings](#keybindings)
  - [`helixel-define-key`](#helixel-define-key)
- [Multi-Cursor Integration](#multi-cursor-integration)
  - [Whitelist](#whitelist)
  - [Per-Cursor State](#per-cursor-state)
  - [Hooks](#hooks)
- [Hooks](#hooks-1)
  - [Lifecycle Hooks](#lifecycle-hooks)
  - [Action Commit Hook](#action-commit-hook)
  - [Chain Hooks](#chain-hooks)
  - [Multi-Cursor Hooks](#multi-cursor-hooks)
- [Surround Configuration](#surround-configuration)
- [Swap-Source Protocol](#swap-source-protocol)
- [Register Backends](#register-backends)

---

## Macro Quick Reference

| Macro | Purpose | When to Use |
|-------|---------|-------------|
| `helixel-define-command` | Define a command with action tracking (`;` / jump-list) | Movement, search, state commands |
| `helixel-register-op` | Register an edit op for `.` repeat | Ops with non-trivial runners (need tx payload), ops without a corresponding interactive command |
| `helixel-define-operator` | Define an editing command AND register its op for `.` | Edit commands whose `.` runner IS the command itself |
| `helixel-with-action-tracking` | Wrap arbitrary body with open → body → commit | Chain, self-contained one-shot operations |

### Decision Flowchart

```
Need a command?
├─ Is it an editing command that `.` should repeat?
│  ├─ Does the `.` runner just call the command itself?
│  │  └─ YES → helixel-define-operator
│  └─ NO (runner needs payload, or runner is a different fn)
│     ├─ helixel-register-op  +  helixel-define-command
│     └─ Call (helixel-record-action OP ...) in the body
│
├─ Not an editing command (movement, search, state)?
│  └─ helixel-define-command
│
└─ Just need to wrap a body with tracking (open → commit)?
   └─ helixel-with-action-tracking
```

---

## Defining Commands

### `helixel-define-command`

Define a helixel command with automatic action tracking for `;` (action
cycle), `C-o`/`C-i` (jump navigation), and optional motion tracking for
`.` repeat.

```elisp
(helixel-define-command NAME METADATA &rest BODY)
```

**METADATA plist:**

| Key                 | Type          | Description |
|---------------------|---------------|-------------|
| `:category`         | symbol        | Action category: `movement`, `edit`, `search`, `state` |
| `:subcat`           | symbol        | Subcategory: `word`, `kill`, `search`, `insert`, etc. |
| `:clear-highlights` | boolean       | Clear highlights before body (default `t` for movement) |
| `:params`           | list          | Function parameter list, e.g. `(&optional count)` |
| `:motion-extra`     | form          | Form for extra motion data (pair delimiter, etc.) |
| `:preposition`      | fn `(TX) → nil` | Replay-time pre-hook for mc cursor positioning |

The macro auto-injects tracking infrastructure at compile time:

- **All commands:** Opens a tracking event for `;` / `C-o` / `C-i` navigation.
- **`:category movement`:** Also clears active search highlights
  (unless `:clear-highlights nil`) and accumulates movement for
  visual-mode `.` replay.

**Example — Movement Command:**

```elisp
(helixel-define-command my-forward-two-words
    (:category movement :subcat word)
  (helixel-forward-word-start)
  (helixel-forward-word-start))
```

**Example — Edit Command:**

```elisp
(helixel-define-command my-delete-word
    (:category edit :subcat kill)
  (helixel-record-action 'kill)
  (helixel-delete-selection)
  (helixel-clear-data))
```

For the complete specification see the **Macro Quick Reference** table
and the per-macro subsections above.

### `helixel-define-movement`

Convenience wrapper around `helixel-define-command` for wrapping existing
Emacs movement commands.

```elisp
(helixel-define-movement NAME BUILTIN TYPE &rest OPTIONS)
```

- `NAME` — new command symbol
- `BUILTIN` — existing Emacs command to wrap
- `TYPE` — subcategory symbol for action tracking
- `OPTIONS` — plist supporting `:clear-highlights` (default `t`)

```elisp
;; Wrapper mode — creates a new command
(helixel-define-movement helixel-forward-paragraph
  forward-paragraph paragraph)

;; Bulk registration
(helixel-define-movements
  (helixel-backward-char backward-char char)
  (helixel-forward-char forward-char char)
  (helixel-next-line next-line line)
  (helixel-previous-line previous-line line))

;; Without highlight clearing
(helixel-define-movement helixel-scroll-up
  scroll-up-command scroll
  :clear-highlights nil)
```

### `helixel-with-action-tracking`

Execute a body with full event tracking (open → body → commit).
For self-contained commands (chain, one-shot operations) that don't
fit the `helixel-define-command` pattern.

```elisp
(helixel-with-action-tracking ((&key op category subcat) &rest body)
  body...)
```

- `:op` — operator symbol (`nil` for non-edit events)
- `:category` + `:subcat` — classification for `;` and jump-list

Opens a tracking event for the `;` / jump-list action cycle.
Commits the event in an `unwind-protect` so it always finalises
even on error.

```elisp
(helixel-with-action-tracking
    (:category edit :subcat my-op :op 'my-op)
  (my-do-something)
  (helixel-action-commit))
```

### `helixel-define-operator`

Define an editing command AND register its op for `.` repeat in a single
form.  Use this when the `.` runner IS the command itself.

```elisp
(helixel-define-operator NAME METADATA &rest BODY)
```

**Required metadata key:** `:op` — the operator symbol.

| Key              | Type            | Description |
|------------------|-----------------|-------------|
| `:op`            | symbol          | **(Required)** Operator symbol for `.` repeat |
| `:display`       | string or fn    | Label for edit history |
| `:moves-point-p` | boolean         | `t` = op moves point, skip auto-advance |
| `:subcat`        | symbol          | Action subcategory (default: `:op`) |
| `:params`        | list            | Function parameter list |

**Expansion:** Generates both `(helixel-register-op ...)` and
`(helixel-define-command ...)`.

**Example:**

```elisp
(helixel-define-operator helixel-kill
    (:op kill :display "d" :moves-point-p t)
  (helixel-record-action 'kill)
  (helixel-delete-selection)
  (helixel-clear-data))
```

**Body convention:** Must call `(helixel-record-action OP ...)` to
record the edit for `.` replay.  Call it *before* side effects that
change the selection.

---

## Registering Operators

### `helixel-register-op`

Register an edit operator in the global operator registry.  This tells
`.` how to replay the edit.

```elisp
(helixel-register-op OP &rest PROPS)
```

**PROPS:**

| Key               | Type            | Description |
|-------------------|-----------------|-------------|
| `:runner`         | fn `(TX) → nil` | Replays the edit from a transaction |
| `:display`        | string or fn    | Label for edit history |
| `:moves-point-p`  | boolean         | Does the op move point? → skip auto-advance |

**When to use directly:**
1. Runner needs tx payload access
2. No corresponding interactive command (e.g. `insert-text`)
3. Runner is a different function from the command

**Example — Runner with payload:**

```elisp
(helixel-register-op replace-char :moves-point-p nil
  :display (lambda (tx)
             (let ((c (helixel-action-char tx)))
               (if c (format "R[%c]" c) "R")))
  :runner (lambda (tx)
            (helixel-replace-char (helixel-action-char tx))))
```

**Example — Custom op:**

```elisp
(helixel-register-op my-upper-case :display "uppercase"
  :runner (lambda (tx)
            (let ((text (buffer-substring (region-beginning)
                                          (region-end))))
              (delete-region (region-beginning) (region-end))
              (insert (upcase text)))))
```

---

## Registering Selection Kinds

### `helixel-register-kind`

Register a selection kind so `.` knows how to recreate, advance, and
display it.

```elisp
(helixel-register-kind KIND &rest PROPS)
```

**PROPS:**

| Key              | Type             | Description |
|------------------|------------------|-------------|
| `:recreate`      | fn `(CTX) → nil` | Recreate selection at current point |
| `:advance`       | fn `(EDIT) → t|nil` | Move to next target; return `t` on success |
| `:display`       | fn `(CTX) → string` | Display string for history |
| `:all-buffer-fn` | fn `(EDIT PREFIX) → nil` | Custom all-buffer scan |
| `:all-dir-fn`    | fn `(EDIT) → nil` | Custom all-direction scan |
| `:flip-dir-fn`   | fn `(SEL) → SEL` | Return reversed-direction sel |
| `:mc-spawn-fn`   | fn `(BEG END) → positions` | Multi-cursor spawn positions |

### Kind Protocol Methods

**`:recreate`** — Called by `.` before executing an edit run.  Must
position point and create the selection region.  Example (line):

```elisp
(defun my--recreate-line (ctx)
  (helixel-select-line (helixel-sel-line-dir ctx)
                       (helixel-sel-line-count ctx)))
```

**`:advance`** — Called by `.` before each replay iteration.  Must move
point to the next target and recreate the selection.  Return `t` if
advance succeeded, `nil` if no more targets.

```elisp
(defun my--advance-line (edit)
  (let ((dir (helixel-sel-line-dir (helixel-action-sel edit))))
    (forward-line (if (eq dir 'forward) 1 -1))
    (when (bolp)
      (helixel-sel-call-recreate (helixel-action-sel edit))
      t)))
```

**`:all-buffer-fn`** — Custom handler for `C-u .` (all-buffer) mode.
Must scan the entire buffer, applying the edit at each match.

```elisp
(defun my--all-buffer-search (edit prefix)
  (save-excursion
    (goto-char (point-min))
    ;; The repeat engine calls :advance then :runner in a loop.
    ;; Simply delegate: advance = find next match, replay = execute edit.
    (while (and (helixel-sel-call-recreate (helixel-action-sel edit))
                (helixel-action-replay edit)))))
```

**Accessors for reading sel ctx fields:**

```elisp
;; Generic
(helixel-sel-kind sel)              → symbol
(helixel-sel-field sel :key)        → value
(helixel-sel-count sel)             → :count or 0

;; Kind-specific
(helixel-sel-line-dir sel)          → :dir ('forward or 'backward)
(helixel-sel-search-pattern sel)    → :pattern (string)
(helixel-sel-search-dir sel)        → :dir
(helixel-sel-textobj-command sel)   → :command (symbol)
(helixel-sel-find-char-char sel)    → :char (character)
(helixel-sel-movement-moves sel)    → :moves list
```

All accessors accept either a `helixel-sel` struct or a raw ctx plist.

---

## Recording Edits

### `helixel-record-action`

Record an edit for `.` repeat.  Pops the pending selection, creates a
`helixel-action`, stores it as `helixel-last-action`, and commits to
the event ring.

```elisp
(helixel-record-action OP &rest EXTRA)
```

- `OP` — operator symbol (must be registered via `helixel-register-op`)
- `EXTRA` — keyword-value pairs added to the action's payload plist

```elisp
;; Simple
(helixel-record-action 'kill)

;; With payload
(helixel-record-action 'join-lines :count 3)
(helixel-record-action 'surround-add :char ?\()
```

### `helixel-action-create`

Create a `helixel-action` struct manually (for testing or custom use).

```elisp
(helixel-action-create OP SEL &rest KV)
```

Special keys extracted from KV: `:runner`, `:display`, `:preposition`.
All other keys become the payload.

```elisp
;; Typically you don't call this directly — use `helixel-record-action' instead.
;; For testing, build an action manually:
(let ((tx (helixel-action-create 'kill (helixel-sel-create 'line '(:count 1))
            :category 'edit :subcat 'kill
            :runner (lambda (_tx) (helixel-delete-selection)))))
  (helixel-action-replay tx))
```

### `helixel-action-replay`

Replay a transaction.  Calls `:preposition` (if any) then `:runner`.

```elisp
(helixel-action-replay action)
```

**Action accessors:**

```elisp
;; ── For `:runner` lambdas (helixel-register-op) ──
(helixel-action-payload-get action key) → value from tx payload plist
(helixel-action-char action)            → :char (convenience — find-char, replace, surround)
(helixel-action-type action)            → :type (convenience — find-char next/till)
(helixel-action-dir action)             → :dir  (convenience — forward/backward)

;; ── For `:advance` fns (helixel-register-kind) ──
(helixel-action-sel action)             → helixel-sel struct

;; ── For hooks (action-commit-hook, chain hooks) ──
(helixel-action-op action)              → operator symbol
(helixel-action-category action)        → category symbol (movement, edit, search, …)
(helixel-action-subcat action)          → subcat symbol (kill, paste, word, …)
```

---

## Custom Text Objects

### Thing-based Text Objects

Define text objects based on Emacs "thing" boundaries:

```elisp
(helixel-define-mark-object NAME THING OBJ DESC THING-SYMBOL COUNT-ONE-P)
```

**Parameters:**
- `NAME` — unquoted symbol suffix (`gopkg` → `helixel-mark-inner-gopkg`)
- `THING` — Emacs thing symbol (`'word`, `'sentence`, `'paragraph`)
- `OBJ` — unquoted symbol used internally by the text-object engine for forward/backward movement
- `DESC` — display description string
- `THING-SYMBOL` — the thing symbol for bounds calculation
- `COUNT-ONE-P` — `t` if the thing has a natural count of 1

**Full example — Go package path:**

```elisp
(require 'thingatpt)

;; 1. Define character set
(define-thing-chars gopkg "-/[:alnum:]_.@:*")

;; 2. Set forward-op
(put 'gopkg 'forward-op
     (lambda (&optional count)
       (helixel-forward-chars "-/[:alnum:]_.@:*" count)))

;; 3. Define text object commands
(helixel-define-mark-object "gopkg" 'gopkg "gopkg" 'gopkg t)

;; 4. Bind to keys
(helixel-define-key 'textobj-inner "y" #'helixel-mark-inner-gopkg)
(helixel-define-key 'textobj-outer "y" #'helixel-mark-a-gopkg)
```

### Regex Text Objects

Define text objects delimited by arbitrary regexp patterns:

```elisp
(helixel-define-regex-textobj NAME BEGIN-RE END-RE
                              &optional NAME-GROUP SUBCAT)
```

**Parameters:**
- `NAME` — unquoted symbol for command suffix
- `BEGIN-RE` — regexp matching opening delimiter line
- `END-RE` — regexp matching closing delimiter line
- `NAME-GROUP` — integer (name-based balancing) or `nil` (counter-based)
- `SUBCAT` — subcategory for `;` grouping (default `'block`)

**Examples:**

```elisp
;; Org mode #+begin_src / #+end_src blocks
(helixel-define-regex-textobj org-block
  "^#\\+begin_\\([^ \n\r]+\\)[^\n]*"
  "^#\\+end_\\([^ \n\r]+\\)[^\n]*" 1 'block)

;; Markdown ``` fences (counter-based)
(helixel-define-regex-textobj md-fence
  "^```[^\n]*$" "^```[ \t]*$" nil 'block)

;; LaTeX \begin{env} / \end{env}
(helixel-define-regex-textobj latex-env
  "\\\\begin{\\([^}]+\\)}"
  "\\\\end{\\([^}]+\\)}" 1 'block)
```

### Pair & Quote Text Objects

Define delimiter-pair text objects:

```elisp
;; Pair: define-mark-pair-textobj NAME OPEN-CHAR PAIR-TYPE
(helixel-define-mark-pair-textobj paren ?\( 'paren)
(helixel-define-mark-pair-textobj bracket ?\[ 'bracket)
(helixel-define-mark-pair-textobj brace ?\{ 'brace)

;; Quote: define-mark-quote-textobj NAME CHAR
(helixel-define-mark-quote-textobj double-quote ?\")
(helixel-define-mark-quote-textobj single-quote ?')
```

These macros automatically create `helixel-mark-inner-NAME` and
`helixel-mark-a-NAME` commands.

### Tree-sitter Text Objects

Requires [evil-textobj-tree-sitter](https://github.com/meain/evil-textobj-tree-sitter)
as a soft dependency.

```elisp
;; Built-in text objects (function, class, loop, conditional, etc.)
(define-key helixel-textobj-inner-map "f"
  (helixel-get-tree-sitter-textobj "function.inner"))
(define-key helixel-textobj-outer-map "f"
  (helixel-get-tree-sitter-textobj "function.outer"))

;; Custom query alist
(define-key helixel-textobj-outer-map "m"
  (helixel-get-tree-sitter-textobj "import"
    '((python-mode . "((import_statement) @import)")
      (python-ts-mode . "((import_statement) @import)")
      (rust-mode . "((use_declaration) @import)"))))
```

If `evil-textobj-tree-sitter` is not installed, the function returns
`nil` and bindings are silently ignored.

---

## Motion Repeat

Motion repeat (`,`) replays the most recent motion from a self-contained
snapshot.  Register custom motion types to make them repeatable.

### `helixel-register-motion-repeater`

Register a function that replays a recorded motion of a specific type.

```elisp
(helixel-register-motion-repeater CATEGORY SUBCAT FN)
```

- `CATEGORY` — e.g. `'movement`, `'search`
- `SUBCAT` — e.g. `'pair`, `'match`, `'word`
- `FN` — `(LAST-MOTION-STRUCT) → nil`

```elisp
(helixel-register-motion-repeater 'movement 'pair
  #'my-repeat-pair-motion)
```

### `helixel-record-motion`

Record a motion for `,` repeat.  Call this from your command body.

```elisp
(helixel-record-motion CMD &rest EXTRA-KV)
```

- `CMD` — the command symbol being recorded
- `EXTRA-KV` — additional payload data for the repeater

```elisp
(helixel-record-motion 'my-jump-command
  :delimiter some-delimiter-plist)
```

### `helixel-register-motion-reverse`

Register a reverse direction command for reversing `,` direction.

```elisp
(helixel-register-motion-reverse FORWARD-CMD REVERSE-CMD)
```

```elisp
(helixel-register-motion-reverse
  'helixel-forward-match 'helixel-backward-match)
```

---

## Keybindings

### `helixel-define-key`

Define a helixel keybinding for a specific state and optionally a
specific major mode.

```elisp
(helixel-define-key STATE KEY DEF &rest MODES)
```

- `STATE` — `'normal`, `'insert`, `'visual`, `'motion`, `'goto`,
  `'space`, `'window`, `'textobj-inner`, `'textobj-outer`
- `KEY` — key string (e.g. `"w"`, `"C-c"`, `"RET"`)
- `DEF` — command symbol or keymap
- `MODES` (optional) — major mode symbols for mode-specific bindings

```elisp
;; Global normal-mode binding
(helixel-define-key 'normal "w" #'my-command)

;; Mode-specific
(helixel-define-key 'normal "K" #'my-doc-command
  'python-mode 'go-mode)

;; Space prefix
(helixel-define-key 'space "w" #'my-workspace-command)

;; Text object keys
(helixel-define-key 'textobj-inner "f" #'helixel-mark-inner-function)
```

---

## Multi-Cursor Integration

### Whitelist

Control which commands are dispatched to fake cursors via the
`helixel-multiple-cursors` symbol property:

```elisp
;; All cursors
(put 'my-edit-cmd 'helixel-multiple-cursors t)

;; Real cursor only
(put 'my-global-cmd 'helixel-multiple-cursors nil)

;; Bulk whitelist
(helixel-mc-mark-all-for-multi-cursors '(cmd1 cmd2))
(helixel-mc-mark-all-for-real-cursor-only '(cmd3 cmd4))
```

Default policy (for commands without the property):

```elisp
(setq helixel-mc-default-policy 'all)  ;; 'all | 'once | 'prompt
```

### Per-Cursor State

Each fake cursor maintains independent state for point, mark,
`mark-active`, `kill-ring`, the pending selection, the last edit
transaction, the active search direction, and the event ring.

Per-cursor dispatch is done via the multi-cursor engine's internal
`with-each-cursor` facility.  Extension authors do not call this
directly — use the whitelist mechanism instead.

### Hooks

```elisp
;; Before clearing all cursors (layout snapshot)
(add-hook 'helixel-mc-before-clear-hook #'my-snapshot-layout)

;; After toggling multi-cursor mode
(add-hook 'helixel-mc-mode-hook #'my-on-mc-toggle)
```

---

## Hooks

### Lifecycle Hooks

```elisp
;; When helixel-mode is enabled in a buffer
(add-hook 'helixel-mode-on-hook  #'my-on-helixel-enable)

;; When helixel-mode is disabled
(add-hook 'helixel-mode-off-hook #'my-on-helixel-disable)

;; When state changes (normal → insert → visual → motion)
(add-hook 'helixel-state-change-hook #'my-on-state-change)
```

### Action Commit Hook

Fired after every action commits to the event ring.  The committed
`helixel-action` is passed as the sole argument.

```elisp
(add-hook 'helixel-action-commit-hook
          (lambda (action)
            (message "Action: %s %s"
              (helixel-action-category action)
              (helixel-action-subcat action))))
```

### Chain Hooks

```elisp
(add-hook 'helixel-chain-start-hook  #'my-chain-setup)
(add-hook 'helixel-chain-end-hook    #'my-chain-commit)
(add-hook 'helixel-chain-cancel-hook #'my-chain-cleanup)
```

### Multi-Cursor Hooks

```elisp
(add-hook 'helixel-mc-before-clear-hook #'my-save-cursor-layout)
(add-hook 'helixel-mc-mode-hook #'my-mc-mode-toggle)
```

### Keyboard Quit Functions

Abnormal hook run when `C-g` is pressed in normal state:

```elisp
(add-hook 'helixel-keyboard-quit-functions #'my-quit-handler)
```

---

## Surround Configuration

### Custom Block Pairs

Add major-mode-specific block surround pairs:

```elisp
(setq helixel-surround-block-alist
      '((org-mode
         (?s . ("#+begin_src " . "#+end_src"))
         (?e . ("#+begin_example " . "#+end_example"))
         (?q . ("#+begin_quote " . "#+end_quote")))
        (markdown-mode
         (?\` . ("```" . "```")))))
```

The first element of each entry is the key character pressed after `m s`.
The second is `(OPEN-STRING . CLOSE-STRING)`.

### Custom Block Text Objects

```elisp
(setq helixel-block-textobj-alist
      '((org-mode . ("^#\\+begin_\\([^ \n\r]+\\)[^\n]*"
                     "^#\\+end_\\([^ \n\r]+\\)[^\n]*" 1))
        (markdown-mode . ("^```.+$" "^```[ \t]*$" nil))
        (gfm-mode . ("^```.+$" "^```[ \t]*$" nil))))
```

Each entry is `(MODE . (BEGIN-RE END-RE NAME-GROUP))`.  Multiple entries
for the same MODE are tried; the tightest enclosing block wins.
`NAME-GROUP` nil = counter-based, integer = name-based.

---

## Register Backends

Customize the register system:

```elisp
(setq helixel-register-backends
      '((?a . 'my-custom-backend)
        (?b . 'another-backend)))

;; Default register
(setq helixel-default-register ?\")

;; Yank register character
(setq helixel-register-yank-char ?0)

;; Small delete register
(setq helixel-register-small-delete-char ?-)

;; Numbered delete registers
(setq helixel-register-numbered-delete-start ?1)
(setq helixel-register-numbered-delete-count 9)
```

---

## Delimiter Protocol

The delimiter protocol is used for pair/textobj/surround operations.
Delimiters are represented as plists with these keys:

| Key   | Type    | Description |
|-------|---------|-------------|
| `:type` | symbol | `'pair`, `'block`, `'regex`, `'quote` |
| `:open` | string | Opening delimiter string |
| `:close`| string | Closing delimiter string |
| `:finder`| fn | `(DELIMITER DIR) → bounds|nil` |
| `:nl-p` | boolean | Delimiter spans newlines (block) |
| `:match-close`| fn | `(DELIMITER OPEN-BOUNDS) → close-bounds|nil` |
| `:adjust-for-jump`| fn | `(DELIMITER BOUNDS) → adjusted-bounds` |

### Creating Delimiters

```elisp
;; Pair delimiter
(helixel-make-pair-delimiter "(" ")")

;; Tag delimiter
(helixel-make-tag-delimiter "<div>" "</div>")

;; Block delimiter
(helixel-make-block-delimiter begin-re end-re name-group)

;; Regex delimiter
(helixel-make-regex-delimiter begin-re end-re name-group)
```

### Using Delimiters

```elisp
;; Find next delimiter
(helixel-delimiter-find delimiter dir)  → bounds|nil

;; Get bounds at point
(helixel-delimiter-bounds delimiter)    → (OPEN-BEG . CLOSE-END)|nil

;; Get flat bounds (no preprocessing)
(helixel-delimiter-bounds-flat delimiter) → (OPEN-BEG . CLOSE-END)|nil

;; Accessor functions
(helixel-delimiter-type d)              → :type
(helixel-delimiter-open d)              → :open string
(helixel-delimiter-close d)             → :close string
(helixel-delimiter-finder d)            → :finder function
```

---

## Motion Configuration

```elisp
;; Things that skip visual selection during movement
(setq helixel-thing-move-no-select-things
  '(helixel-paragraph helixel-sentence helixel-function))

;; Categories repeatable by ,
(setq helixel-motion-repeat-categories
  '((movement . pair) (movement . match) search find-char))
```

---

## Action Cycle Configuration

```elisp
;; Categories visible in ; cycling
(setq helixel-action-cycle-categories
  '(movement textobj search find-char
    (edit . copy) (edit . paste-after) (edit . replace)))

;; Categories where first ; marks the newest event's region
(setq helixel-action-cycle-newest-for-mark
  '(edit (movement . pair) (movement . match)))

;; Jump log categories
(setq helixel-jump-categories
  '(movement search find-char edit goto))

;; Jump cycle categories (subset for C-o/C-i)
(setq helixel-jump-cycle-categories
  '(search find-char edit goto))
```

---

## Writing Error-Resilient Commands

Follow these patterns for commands that work in tests and edge cases:

1. **Use position-independent runners**: Replay at any point, not just
   the original position.  Use `(region-beginning)`/`(point)` rather
   than saved positions.

2. **Call `helixel-record-action` BEFORE side effects**: Recording
   must capture the selection before it's modified.

3. **Never trust `match-data` after insert**: Search hooks invalidate
   `match-data`.  Use `(region-beginning)`/`(region-end)` instead.

4. **Don't `deactivate-mark` in insert-text runners**: Selection is
   recreated before execute.  `deactivate-mark` would destroy it.

5. **For test compatibility**: Use `helixel-define-command` which binds
   `this-command` (nil in batch/ERT) to the function symbol.

---

## Testing Your Extensions

Use the test helper macro from `helixel-test-common.el`:

```elisp
(require 'helixel-test-common)

(ert-deftest my-extension-test ()
  (helixel-test-with-buffer "hello world"
    (goto-char 1)
    ;; The buffer has transient-mark-mode on and internal hooks active
    (should (looking-at "hello"))))
```

`helixel-test-with-buffer` activates internal hooks without enabling
`helixel-mode`, avoiding state-machine side effects.
