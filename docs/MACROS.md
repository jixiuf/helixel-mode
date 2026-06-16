# Macros — Command & Operator Definition

helixel-mode provides three macros for defining commands and registering
edit operators.  Each has a single, clear responsibility.

## Quick Reference

| Macro | Purpose | When to Use |
|-------|---------|-------------|
| `helixel-define-command` | Define a command with action tracking (`;` / jump-list) | Movement, search, state commands |
| `helixel-register-op` | Register an edit op for `.` repeat | Ops with non-trivial runners (need tx payload), ops without a corresponding interactive command |
| `helixel-define-operator` | Define an editing command AND register its op for `.` | Edit commands whose `.` runner IS the command itself |

---

## 1. `helixel-define-command`

Define a command with automatic action tracking for session jumping (`;`)
and the jump list (`C-o` / `C-i`).

### Signature

```elisp
(helixel-define-command NAME METADATA &rest BODY)
```

### Metadata Keywords

| Key | Type | Description |
|-----|------|-------------|
| `:category` | symbol | Action category: `movement`, `edit`, `search`, `state`, ... |
| `:subcat` | symbol | Action subcategory: `word`, `kill`, `search`, `insert`, ... |
| `:dir` | symbol | Direction for `n`/`N` repeat: `forward`, `backward` |
| `:params` | list | Function parameter list, e.g. `(&optional count)` |
| `:clear-highlights` | boolean | Clear search highlights before executing. Default `t` for `:category movement`, `nil` otherwise. |
| `:tx-runner` | function `(TX) -> nil` | Replay-time pre-hook.  Stored as the `:preposition` slot on the live action; `helixel-action-replay` calls it BEFORE the main runner (at the real cursor on `.`-repeat, at fake cursors during mc dispatch, etc.).  For movement commands (no body record-action), the preposition is the entire replay payload — the action has nil op so `.` ignores it, but mc still replays at fakes.  For insert-entry commands, the prepos survives the later insert-text tx via payload preservation in `helixel--record-action`. |

### Auto-Injected Behavior

**All commands:**
- `(helixel--tracking-open CAT SUBCAT)` — records event in the event ring for `;` / `C-o` / `C-i`

**`:category movement` commands (additional):**
- `(helixel--clear-highlights)` — clears active highlights/mark (unless `:clear-highlights nil`)
- `(helixel--track-visual-move NAME)` — accumulates movement for `.` replay in visual mode

**`:dir` set:**
- `(helixel--live-cat-set-dir DIR)` — sets repeat direction for `n`/`N`

### Examples

**Movement command:**
```elisp
(helixel-define-command helixel-forward-word-start
    (:category movement :subcat word :dir forward)
  (condition-case nil
      (helixel--forward-beginning 'helixel-word)
    (error nil)))
```

**Search command:**
```elisp
(helixel-define-command helixel-search-forward
    (:category search :subcat search :dir forward)
  (helixel-search--isearch t))
```

**State command (no edit):**
```elisp
(helixel-define-command helixel-insert-exit
    (:category state :subcat exit)
  (let* ((result (helixel--insert-finish))
         ...)
    (helixel--switch-state 'normal)))
```

**Edit command with explicit `helixel--record-action`:**

Use this pattern when the command's `.` runner is NOT the command itself
(e.g. `change` uses `helixel--repeat-change-core` as runner):

```elisp
(helixel-define-command helixel-change-thing-at-point
    (:category edit :subcat change)
  (helixel--record-action 'change)  ;; explicit record call
  (if (and (use-region-p) (eq (helixel--selection-type) 'rect))
      (helixel--rect-change)
    (helixel--delete-selection)
    (setq helixel--change-track-marker (point-marker))
    (helixel--enter-insert)))
```

Or when the command has extra payload for `.` replay:

```elisp
(helixel-define-command helixel-join-lines
    (:category edit :subcat join-lines :params (&optional count))
  (interactive "p")
  (let ((n (max (or count 1) 2)))
    (helixel--record-action 'join-lines :count n)  ;; explicit with payload
    (dotimes (_ (1- n))
      (join-line 1))
    (helixel--clear-data)))
```

---

## 2. `helixel-register-op`

Register an edit operator in the operator registry so `.` knows how to
replay it.  This is a data-only registration — no command is defined.

### Signature

```elisp
(helixel-register-op OP &rest PROPS)
```

### Properties

| Key | Type | Description |
|-----|------|-------------|
| `:runner` | function | `(TX) -> nil` — replays the edit from a transaction |
| `:display` | string or function | Label for edit history. If a function: `(TX) -> string` |
| `:moves-point-p` | boolean | `t` = op moves point itself (kill, change, join-lines, suppress auto-advance); `nil` = op leaves point alone and the repeat engine drives stepping via the kind's `:advance` fn (default) |

### When to Use

1. **Runner needs access to tx payload** — the runner reads `:char`, `:count`,
   `:tag`, `:keys`, `:text`, etc. from the recorded transaction.

2. **No corresponding interactive command** — e.g. `insert-text`: recorded by
   `helixel-insert-exit`, not triggered by a user-facing command.

3. **Runner is a different function from the command** — e.g. `change`:
   the command is `helixel-change-thing-at-point`, but `.` replays via
   `helixel--repeat-change-core`.

### Examples

**Runner needs payload access:**
```elisp
(helixel-register-op replace-char :moves-point-p nil
  :display (lambda (tx)
             (let ((c (helixel-action-char tx)))
               (if c (format "R[%c]" c) "R")))
  :runner (lambda (tx)
            (helixel-replace-char (helixel-action-char tx))))
```

Prefer the convenience accessors in `helixel-core.el`
(`helixel-action-char` / `helixel-action-type` / `helixel-action-dir` for
find-char + replace-char + surround; `helixel-sel-field` for
ctx-key lookups; `helixel-action-payload-get` for arbitrary payload
keys) over raw `plist-get` on the payload — the accessors document
intent and stay consistent with the `helixel-sel-{kind}-{key}`
family.

**No corresponding interactive command:**
```elisp
(helixel-register-op insert-text :display "i" :moves-point-p nil
  :runner (lambda (tx)
            (let ((keys (helixel-action-payload-get tx :keys)))
              (if keys
                  (helixel--execute-keys keys)
                (insert (or (helixel-action-payload-get tx :text)
                            ""))))))
```

**Runner ≠ command function:**
```elisp
(helixel-register-op change :display "c" :moves-point-p t
  :runner #'helixel--repeat-change-core)
```

**Dynamic display label:**
```elisp
(helixel-register-op surround-add
  :display (lambda (tx)
             (let ((c (helixel-action-char tx)))
               (if c (format "ms[%c]" c) "ms")))
  :runner (lambda (tx)
            (when-let* ((char (helixel-action-char tx))
                        (pair (helixel--surround-lookup char)))
              (helixel--surround-add (car pair) (cdr pair)))))
```

---

## 3. `helixel-define-operator`

Define an editing command AND register its op for `.` repeat in a single
form.  Use this when the `.` runner IS the command itself.

### Signature

```elisp
(helixel-define-operator NAME METADATA &rest BODY)
```

### Metadata Keywords

| Key | Type | Description |
|-----|------|-------------|
| `:op` | symbol | **(Required)** Operator symbol for `.` repeat |
| `:display` | string or function | Label for edit history |
| `:moves-point-p` | boolean | See `helixel-register-op'. |
| `:subcat` | symbol | Action subcategory (default: `:op` value) |
| `:params` | list | Function parameter list |

### Expansion

`(helixel-define-operator NAME (:op OP :display D ...) BODY)` expands to:

```elisp
(progn
  ;; 1. Register the op
  (helixel-register-op OP
    :display D
    :runner (lambda (_tx) (NAME)))
  ;; 2. Define the command with action tracking
  (helixel-define-command NAME
      (:category edit :subcat OP ...)
    BODY))
```

### Body Convention

The command body **must** call `(helixel--record-action OP ...)` to record
the edit for `.` replay.  The record call should happen before any side
effects that might change the selection or cursor position.

### Examples

**Simple edit command:**
```elisp
(helixel-define-operator helixel-kill-thing-at-point
    (:op kill :display "d" :moves-point-p t)
  (helixel--record-action 'kill)
  (helixel--delete-selection)
  (helixel--clear-data))
```

**Edit command with line advance:**
```elisp
(helixel-define-operator helixel-kill-ring-save
    (:op copy :display "y" :moves-point-p nil)
  (helixel--record-action 'copy)
  (when (use-region-p)
    (cond
     ((eq (helixel--selection-type) 'rect)
      (let ((lines (extract-rectangle ...)))
        (kill-new ...)))
     ...))
  (helixel--clear-data))
```

**Edit command with params:**
```elisp
(helixel-define-operator helixel-yank
    (:op paste-after :display "p" :moves-point-p nil
     :params (&optional arg))
  (interactive "*P")
  (helixel--record-action 'paste-after)
  (cond
   ((helixel--rect-wise-kill-p) ...)
   ((helixel--linewise-kill-p) ...)
   (t (yank arg))))
```

**Edit command with payload for `.`:**
```elisp
(helixel-define-operator helixel-toggle-case
    (:op toggle-case :display "~" :subcat case
     :params (&optional count))
  (interactive "p")
  (helixel--record-action 'toggle-case :count (or count 1))
  (if (use-region-p)
      (let ((text (buffer-substring ...)))
        (delete-region ...)
        (insert (mapconcat ...)))
    (dotimes (_ (or count 1))
      ...))
  (helixel--clear-data))
```

**Edit command with custom subcategory:**
```elisp
(helixel-define-operator helixel-comment-toggle
    (:op comment-toggle :display "gc" :subcat comment)
  (helixel--record-action 'comment-toggle)
  (if (use-region-p)
      (comment-or-uncomment-region ...)
    (comment-dwim nil))
  (helixel--clear-data))
```

---

## Decision Flowchart

```
Need a command?
├─ Is it an editing command that `.` should repeat?
│  ├─ Does the `.` runner just call the command itself?
│  │  └─ YES → helixel-define-operator
│  └─ NO (runner needs payload, or runner is a different fn)
│     ├─ helixel-register-op  +  helixel-define-command
│     └─ Call (helixel--record-action OP ...) in the body
│
└─ Not an editing command (movement, search, state)?
   └─ helixel-define-command

Just need to register an op (no command)?
└─ helixel-register-op
```

