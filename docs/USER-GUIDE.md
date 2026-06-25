# helixel-mode User Guide

Helix-style modal editing for Emacs.  Requires **Emacs ≥ 29.1**.

## Table of Contents

- [Philosophy](#philosophy)
- [Installation](#installation)
- [Basic Concepts](#basic-concepts)
  - [States](#states)
  - [The Selection-First Workflow](#the-selection-first-workflow)
- [Selection & Movement](#selection--movement)
  - [Basic Movement](#basic-movement)
  - [Line Selection](#line-selection)
  - [Goto Prefix](#goto-prefix)
  - [View / Scroll](#view--scroll)
  - [Pair & Structure Movement](#pair--structure-movement)
- [Editing](#editing)
  - [Edit Commands](#edit-commands)
  - [Registers](#registers)
  - [Entering Insert Mode](#entering-insert-mode)
- [Text Objects](#text-objects)
  - [Built-in Text Objects](#built-in-text-objects)
  - [Region-aware Behavior](#region-aware-behavior)
  - [Block Text Object](#block-text-object)
  - [Custom Text Objects](#custom-text-objects)
  - [Regex Text Objects](#regex-text-objects)
  - [Tree-sitter Text Objects](#tree-sitter-text-objects)
- [Search & Find](#search--find)
  - [Interactive Search](#interactive-search)
  - [Find Char](#find-char)
  - [Search History & Repeat](#search-history--repeat)
  - [PCRE Support](#pcre-support)
- [Dot-Repeat (`.`)](#dot-repeat-)
  - [Prefix Modes](#prefix-modes)
  - [Per-Kind Examples](#per-kind-examples)
- [Action Cycle (`;`) & Mark Cycle (`C-;`)](#action-cycle---mark-cycle-c-)
  - [How They Differ](#how-they-differ)
  - [Session Groups](#session-groups)
  - [Examples](#examples-1)
- [Jump Navigation (`C-o` / `C-i`)](#jump-navigation-c-o--c-i)
  - [Registering Jump Commands](#registering-jump-commands)
  - [Configuration](#configuration-1)
- [Multi-Cursor (`s`)](#multi-cursor-s)
  - [Spawning Cursors](#spawning-cursors)
  - [Managing Cursors](#managing-cursors)
  - [Workflows](#workflows)
  - [`;` with Multi-Cursor](#-with-multi-cursor)
  - [Integration with `.` and `@`](#integration-with--and-)
  - [Whitelist](#whitelist)
- [Motion Repeat (`,`)](#motion-repeat-)
  - [Supported Types](#supported-types)
  - [Layer-by-layer Outward](#layer-by-layer-outward)
  - [`,` with `;`](#-with-)
  - [find-char: `,` vs `n`](#find-char--vs-n)
  - [For Pair Motions](#for-pair-motions)
  - [Configuration](#configuration-2)
- [Surround](#surround)
  - [Surround Keys](#surround-keys)
  - [Custom Block Pairs](#custom-block-pairs)
- [Swap (`S`)](#swap-s)
  - [Basic Flow](#basic-flow)
  - [Implied Region](#implied-region)
  - [Rectangle Swap](#rectangle-swap)
  - [Register Integration](#register-integration)
  - [Edge Cases](#edge-cases)
- [Chain Recording (`@`)](#chain-recording-)
  - [How It Works](#how-it-works)
  - [Capture & Advance](#capture--advance)
  - [Third-party Integration](#third-party-integration)
  - [Examples](#examples)
- [Configuration](#configuration-2)
  - [Key Options](#key-options)
  - [Adding Keybindings](#adding-keybindings)
  - [Excluding Buffers](#excluding-buffers)

---

## Philosophy

Helixel is **selection-first**: you select a region first, then act on it.
This is the opposite of Vim's operator-pending model where `d3w` means
"delete 3 words" with the operator coming *first*.  In Helixel you type
`w w w ; d` or `3wd` — select three words, then delete.

If you're coming from Vim, this is the one paradigmatic difference to
internalize.  Every action follows: **select → act**.

---

## Installation

### Via `use-package` with `:vc` (Emacs ≥ 30)

```elisp
(use-package helixel
  :vc (:url "https://github.com/jixiuf/helixel-mode")
  :config (helixel-mode))
```

### Manual Install

```elisp
(add-to-list 'load-path "/path/to/helixel-mode")
(require 'helixel)
(helixel-mode)
```

### Quick Try

```bash
make run
# or
emacs -Q -L . -l helixel.el --eval '(progn (helixel-mode) (which-key-mode))'
```

---

## Basic Concepts

### States

| State    | Indicator    | Purpose                 | Enter via               |
| -------- | ------------ | ----------------------- | ----------------------- |
| normal   | `NORMAL`     | Default editing state   | `ESC`                   |
| insert   | `INSERT`     | Text input              | `i` `a` `I` `A` `o` `O` |
| visual   | `VISUAL`     | Selection mode          | `v`                     |
| motion   | `MOTION`     | Read-only navigation    | (certain modes)         |

- **Normal mode** — your home base.  All movement, selection, and editing
  commands are available here.  Press `ESC` to return from any other state.
- **Insert mode** — type text.  `ESC` returns to normal and saves typed
  text for `.` repeat.
- **Visual mode** — behave like Helix's visual mode; each movement
  extends the selection.
- **Motion mode** — read-only buffers (info, help, man, eww) use this
  instead of normal mode.  Edit commands (`d`, `c`, `i`) are unavailable.

### The Selection-First Workflow

1. **Select** something (a word, a line, a search match, a text object)
2. **Act** on it (delete, change, copy, indent, surround, swap, case-toggle…)
3. **Repeat** with `.` (dot-repeat)

```
w w w ; d     # select 3 words forward, then delete
3 x >         # select 3 lines, then indent
/foo RET cbar # search "foo", then change to "bar"
miw d         # select inner word, delete
```

---

## Selection & Movement

### Basic Movement

| Key   | Action                       |
| ----- | ---------------------------- |
| `h`   | Left (backward-char)         |
| `j`   | Down (next-line)             |
| `k`   | Up (previous-line)           |
| `l`   | Right (forward-char)         |
| `w`   | Word start (forward)         |
| `b`   | Word start (backward)        |
| `e`   | Word end (forward)           |
| `W`   | WORD start (forward)         |
| `B`   | WORD start (backward)        |
| `E`   | WORD end (forward)           |
| `g h` | Beginning of line            |
| `g s` | First non-whitespace         |
| `g l` | End of line                  |
| `g g` | Beginning of buffer          |
| `G`   | End of buffer                |
| `g e` | End of buffer                |
| `%`   | Jump to matching bracket     |

### Line Selection

| Key        | Action                                            |
| ---------- | ------------------------------------------------- |
| `x`        | Select current line (extend downward)             |
| `X`        | Select current line (extend upward)               |
| `- x`      | Flip line direction (if already selecting lines)  |

`x` followed by `d` deletes the line.  `x x x d` selects 3 lines then deletes.
Use `-` as a prefix to flip the permanent direction of line selection,
or to shrink an existing selection back toward the mark.

### Goto Prefix (`g`)

| Key    | Action                       |
| ------ | ---------------------------- |
| `g h`  | Beginning of line            |
| `g l`  | End of line                  |
| `g s`  | First non-whitespace         |
| `g g`  | Beginning of buffer          |
| `g e`  | End of buffer                |
| `g j`  | Down (next-line)             |
| `g k`  | Up (previous-line)           |
| `g d`  | Go to definition             |
| `g r`  | Go to references             |
| `g i`  | Go to implementation         |
| `g y`  | Go to type definition        |
| `g u`  | Downcase region              |
| `g U`  | Upcase region                |
| `g c`  | Comment toggle               |
| `g q`  | Fill paragraph               |
| `g .`  | Pick past edit to repeat     |
| `g ;`  | Go to line number            |
| `g :`  | Go to character position     |
| `g \|` | Move to column               |
| `g v`  | Restore last cursor layout   |

### View / Scroll

| Key     | Action                   |
| ------- | ------------------------ |
| `C-f`   | Scroll up (forward)      |
| `C-b`   | Scroll down (backward)   |
| `z z`   | Recenter cursor          |

### Pair & Structure Movement (`[` / `]` / `{` / `}`)

These prefixes mirror the text-object keys.  Each character from
the text-object maps (paren, bracket, brace, angle, quote, tag, block)
works as a sub-key for pair/structure movement.

| Prefix     | Direction   | Jumps to                             |
| ---------- | ----------- | ------------------------------------ |
| `[` key    | outward     | enclosing pair's opening delimiter   |
| `]` key    | forward     | next pair's closing end              |
| `{` key    | outward     | enclosing inner opening              |
| `}` key    | forward     | next inner closing end               |

Pair sub-keys (same chars as text objects):

| Key     | Text Object            | Example                              |
| ------- | ---------------------- | ------------------------------------ |
| `(`     | parens                 | `[ (` outward enclosing `(`          |
| `[`     | brackets               | `] [` forward next `[...]` end       |
| `{`     | braces                 | `[ {` outward enclosing `{`          |
| `<`     | angle                  | `] <` forward next `<...>` end       |
| `"`     | double-quote           | `[ "` outward enclosing `"`          |
| `'`     | single-quote           | `] '` forward next `'...'` end       |
| `` ` `` | back-quote             | `` [ ` `` outward enclosing `` ` ``  |
| `t`     | XML tag                | `] t` forward next tag end           |
| `c`     | code block             | `[ c` outward enclosing block        |

Structure sub-keys (`[` / `]` only):

| Key   | `[`                    | `]`                  |
| ----- | ---------------------- | -------------------- |
| `d`   | prev flymake error     | next flymake error   |
| `p`   | prev paragraph start   | next paragraph end   |
| `s`   | prev sentence start    | next sentence end    |
| `f`   | prev function start    | next function end    |

After any pair/structure movement:
- `,` repeats the motion (reads from a self-contained snapshot)
- `;` selects the full span traversed by the motion
- `C-;` pushes mark to the pre-motion cursor position

Examples:
- `[ (` — jump outward to the nearest enclosing `(`
- `] (` — jump forward to the end of the next `(...)` pair
- `%` then `,` — jump to match, then repeat outward one nesting level
- `] p` then `;` — jump to next paragraph end, then select the span

---

## Editing

### Edit Commands

| Key           | Action                  | Notes                                      |
| ------------- | ----------------------- | ------------------------------------------ |
| `d`           | Delete (kill)           | Saves to kill-ring                         |
| `D`           | Delete (no kill-ring)   | Delete without saving                      |
| `c`           | Change                  | Delete then enter insert                   |
| `C`           | Change (no kill-ring)   | Delete without kill-ring, then insert      |
| `y`           | Copy (kill-ring-save)   | Also stores as swap source                 |
| `r`           | Replace with yanked     | Replace selection with last kill-ring text |
| `R`           | Replace-char            | Replace char(s) with a single character    |
| `p`           | Paste after             | Also pasted after line if yanked line      |
| `P`           | Paste before            |                                            |
| `>`           | Indent right            | Supports `.` repeat for next lines         |
| `<`           | Indent left             | Supports `.` repeat for next lines         |
| `~`           | Toggle case             |                                            |
| `J`           | Join lines              |                                            |
| `=`           | Indent for tab          | Indent line or region                      |
| `u`           | Undo                    |                                            |
| `U`           | Redo                    |                                            |
| `g u`         | Downcase region         |                                            |
| `g U`         | Upcase region           |                                            |
| `g q`         | Fill paragraph          |                                            |
| `g c`         | Comment toggle          |                                            |
| `!`           | Shell command           | Pipe region through command                |
| `BS`          | Delete backward char    | Backspace in normal mode                   |
| `C-BS`/`M-BS` | Delete backward word    | Ctrl/Meta Backspace in normal mode         |

### Registers

helixel has a Helix-style register system:

| Register   | Purpose                               |
| ---------- | ------------------------------------- |
| `"`        | Default register (kill-ring and yank) |
| `0`        | Last yanked text                      |
| `1-9`      | Numbered delete registers             |
| `-`        | Small delete (< 1 line)               |
| `a-z`      | Named registers                       |

Usage: `"a y` (copy to register a), `"a p` (paste from a),
`"a /` (search forward for register a text), etc.

### Entering Insert Mode

| Key   | Action                                        |
| ----- | --------------------------------------------- |
| `i`   | Insert at current position                    |
| `a`   | Append (insert after cursor)                  |
| `I`   | Insert at beginning of line                   |
| `A`   | Insert at end of line                         |
| `o`   | Open new line below                           |
| `O`   | Open new line above                           |

---

## Text Objects

`m` is the text-object prefix.  `mi` selects **inner**, `ma` selects **a/around**.
Inner objects are additionally available directly under `m` prefix to reduce keystrokes:
`mw` is the same as `miw` — select word.

### Built-in Text Objects

| Key        | Text Object   | Example              |
| ---------- | ------------- | -------------------- |
| `w`        | word          | `miw` `maw`          |
| `W`        | WORD          | `miW` `maW`          |
| `o`        | symbol        | `mio` `mao`          |
| `s`        | sentence      | `mis` `mas`          |
| `p`        | paragraph     | `mip` `map`          |
| `f`        | function      | `mif` `maf`          |
| `(` `b`    | parens        | `mi(` `ma(`          |
| `[`        | brackets      | `mi[` `ma[`          |
| `{`        | braces        | `mi{` `ma{`          |
| `<`        | angle         | `mi<` `ma<`          |
| `"`        | double-quote  | `mi"` `ma"`          |
| `'`        | single-quote  | `mi'` `ma'`          |
| `` ` ``    | back-quote    | `` mi` `` ma` ``     |
| `t`        | XML tag       | `mit` `mat`          |
| `c`        | code block    | `mic` `mac`          |


After selecting a text object, chain any editing command (`d`, `c`, `y`, etc.).

`m h` selects the whole buffer directly.

### Region-aware Behavior

In normal mode when a region is already active, `mi`/`ma` selects the text
object *within* the current region (not at point).
- Example: `hello |world` with region `hello ` active: `miw` selects `hello`.
- In **visual** mode: pressing repeatedly *expands* the selection outward.
- White space adjustment: cursor on whitespace between words automatically
  finds the adjacent word.

### Block Text Object

`mi c` / `ma c` selects the nearest enclosing block (org
`#+begin_src`/`#+end_src`, markdown fences, or bracket
pairs `()` `[]` `{}`).  Mode-specific patterns via
`helixel-block-textobj-alist`:

```elisp
(setq helixel-block-textobj-alist
      '((org-mode . ("^#\\+begin_\\([^ \n\r]+\\)[^\n]*"
                     "^#\\+end_\\([^ \n\r]+\\)[^\n]*" 1))
        (markdown-mode . ("^```.+$" "^```[ \t]*$" nil))
        (gfm-mode . ("^```.+$" "^```[ \t]*$" nil))))
```

Each entry is `(MODE . (BEGIN-RE END-RE NAME-GROUP))`.  Multiple entries
for the same MODE are tried; the tightest enclosing block wins.
`NAME-GROUP` nil = counter-based balancing (fences), integer = name-based.

### Custom Text Objects

Define a thing-based text object (e.g. Go package names like
`github.com/foo/bar`):

```elisp
(require 'thingatpt)

;; 1. Define the character set for the thing
(define-thing-chars gopkg "-/[:alnum:]_.@:*")

;; 2. Set forward-op so forward-thing knows how to move
(put 'gopkg 'forward-op
     (lambda (&optional count)
       (helixel-forward-chars "-/[:alnum:]_.@:*" count)))

;; 3. Define inner / a text-object commands
(helixel-define-mark-object "gopkg" 'gopkg "gopkg" 'gopkg t)

;; 4. Bind to keys
(helixel-define-key 'textobj-inner "y" #'helixel-mark-inner-gopkg)
(helixel-define-key 'textobj-outer "y" #'helixel-mark-a-gopkg)
;; or mode-specific:
(helixel-define-key 'textobj-inner "y" #'helixel-mark-inner-gopkg 'go-mode)
(helixel-define-key 'textobj-outer "y" #'helixel-mark-a-gopkg 'go-mode)
```

### Regex Text Objects

Define text objects delimited by arbitrary regexp patterns — useful for
org blocks, markdown fences, LaTeX environments, etc.:

```elisp
;; Org mode #+begin_src / #+end_src blocks
(helixel-define-regex-textobj org-block
  "^#\\+begin_\\([^ \n\r]+\\)[^\n]*"
  "^#\\+end_\\([^ \n\r]+\\)[^\n]*" 1 'block)

;; Markdown ``` fences (counter-based: name-group nil)
(helixel-define-regex-textobj md-fence
  "^```[^\n]*$" "^```[ \t]*$" nil 'block)

;; LaTeX \begin{env} / \end{env}
(helixel-define-regex-textobj latex-env
  "\\\\begin{\\([^}]+\\)}" "\\\\end{\\([^}]+\\)}" 1 'block)
```

Arguments: `(NAME BEGIN-RE END-RE &optional NAME-GROUP SUBCAT)`.

- **NAME**: unquoted symbol for the command suffix
  (e.g. `org-block` → `helixel-mark-inner-org-block`)
- **BEGIN-RE** / **END-RE**: regexps matching the opening/closing delimiter lines
- **NAME-GROUP**: integer = name-based balancing, `nil` = counter-based
- **SUBCAT**: subcategory for `;` session grouping (default `'block`)

### Tree-sitter Text Objects

Requires [evil-textobj-tree-sitter](https://github.com/meain/evil-textobj-tree-sitter)
as a soft dependency (it does NOT require evil-mode):

```elisp
(define-key helixel-textobj-inner-map "f"
  (helixel-get-tree-sitter-textobj "function.inner"))
(define-key helixel-textobj-outer-map "f"
  (helixel-get-tree-sitter-textobj "function.outer"))
```

Custom query alist per major-mode:

```elisp
(define-key helixel-textobj-outer-map "m"
  (helixel-get-tree-sitter-textobj "import"
    '((python-mode . "((import_statement) @import)")
      (python-ts-mode . "((import_statement) @import)")
      (rust-mode . "((use_declaration) @import)"))))
```

If `evil-textobj-tree-sitter` is not installed, the function returns
`nil` and bindings are silently ignored.

---

## Search & Find

### Interactive Search

| Key   | Action                                     |
| ----- | ------------------------------------------ |
| `/`   | Search forward (regexp)                    |
| `?`   | Search backward (regexp)                   |
| `*`   | Search symbol at point forward             |
| `#`   | Search symbol at point backward            |
| `"a /` | Search forward for register a text (regex) |
| `"a *` | Search forward for register a text (word)  |
| `n`   | Repeat search forward                      |
| `,`   | Repeat last search (motion repeat)         |
| `N`   | reverse direction                          |

Within `/` / `?`, `M-r` toggles between literal and regexp mode.

### Find Char

| Key   | Action                                |
| ----- | ------------------------------------- |
| `f`   | Find next char (inclusive)            |
| `t`   | Till next char (exclusive)            |
| `F`   | Find previous char (inclusive)        |
| `T`   | Till previous char (exclusive)        |
| `n`   | Repeat last find-char forward         |
| `N`   | Reverse Direction                     |
| `,`   | Repeat last find-char (motion repeat) |

`n` and `N` repeat both search and find-char.  `,` also repeats
find-char (and other motions) from a self-contained snapshot.

### Search History & Repeat

`n` / `N` repeat both search and find-char from a combined history ring.
`C-u n` / `C-u N` lets you pick from history.

| Key       | Context                 | Behavior                                 |
| --------- | ----------------------- | ---------------------------------------- |
| `n`       | After `/` or `?`        | Repeat search forward                    |
| `N`       | After `/` or `?`        | Reverse direction then repeat            |
| `n`       | After `f`/`F`/`t`/`T`   | Repeat find-char forward                 |
| `N`       | After `f`/`F`/`t`/`T`   | Reverse direction then repeat            |
| `C-u n`   | anytime                 | Pick from combined history & execute     |
| `C-u N`   | anytime                 | Toggle direction + pick from history     |

`N` flips the search direction; subsequent `n` continues in the new direction.

```
/foo<RET>   search "foo"
n           next match forward
N           reverse direction, go back to previous match
n           continue backward

fb          find next "b"
n           find next "b" again
N           reverse direction, find previous "b"
C-u n       pick a past search/find-char from history
```

### PCRE Support

Enable PCRE-style regexp (`\d`, `\w`, `\s`, etc.) via the optional
[pcre2el](https://github.com/joddie/pcre2el) package:

```elisp
(require 'pcre2el)
(setq helixel-search-pcre t)
```

| PCRE     | Emacs equivalent   | Matches                  |
| -------- | ------------------ | ------------------------ |
| `\d`     | `[[:digit:]]`      | Digits 0-9               |
| `\D`     | `[^[:digit:]]`     | Non-digits               |
| `\w`     | `[[:word:]]`       | Word characters          |
| `\W`     | `[^[:word:]]`      | Non-word characters      |
| `\s`     | `[[:space:]]`      | Whitespace               |
| `\S`     | `[^[:space:]]`     | Non-whitespace           |

If pcre2el is not installed, patterns are passed through unchanged.

---

## Dot-Repeat (`.`)

`.` repeats the last edit.  Works for all selection kinds.
`M-.` repeats the selection *without* editing (preview mode).

### Prefix Modes

| Prefix          | Behavior                                      |
| --------------- | --------------------------------------------- |
| `.`             | Repeat once in stored direction               |
| `3.`            | Repeat 3 times                                |
| `0.`            | Repeat all remaining targets till end         |
| `C-u .`         | Repeat all targets, entire buffer             |
| `- .`           | Flip direction permanently, 1 repeat          |
| `- 3 .`         | Flip direction permanently, 3 repeats         |

- `0.` stops silently when no more targets are found.
- `C-u .` starts from `point-min` and processes every target forward.
- `-.` / `-N.` *permanently* flip direction.  `-.` again flips back.
- Subsequent `.` presses continue in the flipped direction.
- All selection kinds support all prefix modes.

### Per-Kind Examples

**Search-based repeat** (advances to next match):
```
/hello<RET>   search "hello"
cWORLD<ESC>   change to "WORLD"
.             change next "hello" → "WORLD"
3.            change next 3 "hello"s → "WORLD"
M-.           move to next hello (preview)
.             change current "hello" to "WORLD"
```

**Line-based repeat** (auto-advances to next line):
```
x             select line
>>>>          indent right
.             indent next line (auto-advance)
3.            indent next 3 lines

x             select line
ihello<ESC>   insert "hello" at bol
.             insert "hello" on next line
```

**Movement-based repeat** (w/e/b — next word each time):
```
w             select forward word
d             delete
.             delete next word
.             delete next word
```

**Textobj-based repeat** (iw/aw — next textobj each time):
```
miw           select inner word
cXXX<ESC>     change to "XXX"
.             change next inner word to "XXX"
```

**Find-char repeat** (f/t — next char each time):
```
fx            find-char to next "x"
d             delete up to "x"
.             delete up to next "x"
```

---

## Action Cycle (`;`) & Mark Cycle (`C-;`)

`;` and `C-;` navigate the event history.

### How They Differ

- **`;`** (action cycle): First press selects the full span (from the
  motion's origin to its destination). Subsequent presses cycle to older
  events.
- **`C-;`** (mark cycle): Every press pushes mark to the original
  pre-motion cursor position. Never selects the full span.

Both share grouping logic: consecutive same-kind motions form a group,
and the cycle shows the group-start. Independent cycle positions.

| Key                 | Behavior                                                                |
| ------------------- | ----------------------------------------------------------------------- |
| `;`                 | Select full span of current session, then cycle to older sessions       |
| `C-u ;`             | Cycle to newer sessions                                                 |

After `p` / `P` / `r` / `M-y`, the pasted or replaced text bounds are
stored in the event.  The first `;` after a paste or replace jumps back to
the edit spot and marks the full span of the pasted/replaced text.

`C-g` cancels the current session — the next command starts a fresh session
even if the type matches.

### Session Groups

Consecutive events with the same category and subcat form a session
group.  `;` cycles between groups, setting mark to each group's start.

**Movement sessions**

| Subcat          | Keys                                          |
| --------------- | --------------------------------------------- |
| `char`          | `h` `l`                                       |
| `line`          | `j` `k`                                       |
| `word`          | `w` `e` `b`                                   |
| `WORD`          | `W` `E` `B`                                   |
| `symbol`        | `o` (forward/backward symbol start/end)       |
| `paragraph`     | `{` `}` (forward/backward paragraph)          |
| `sentence`      | `(` `)` (forward/backward sentence)           |
| `function`      | `[ f` `] f` (forward/backward function)       |
| `goto`          | `g` prefix, `G`                               |
| `scroll`        | `C-f` `C-b`                                   |
| `lineselect`    | `x` `X`                                       |
| `rectselect`    | `v`                                           |
| `pair`          | `[` `]` (pair/structure movement)             |
| `match`         | `%` (jump to matching bracket)                |

**Search & find sessions**

| Category       | Subcat       | Keys                           |
| -------------- | ------------ | ------------------------------ |
| `search`       | `search`     | `/` `?` `*` `#`                |
| `find-char`    | `next`/`till`| `f` `F` `t` `T`               |

**Text-object sessions**

| Subcat          | Keys                                          |
| --------------- | --------------------------------------------- |
| `word`          | `miw` `maw`                                   |
| `WORD`          | `miW` `maW`                                   |
| `symbol`        | `mio` `mao`                                   |
| `sentence`      | `mis` `mas`                                   |
| `paragraph`     | `mip` `map`                                   |
| `function`      | `mif` `maf`                                   |
| `pair`          | `mi(` `ma(` `mi[` `ma[` `mi{` `ma{` `mi<` `ma<` |
| `quote`         | `mi"` `ma"` `mi'` `ma'` `` mi` `` ma` ``    |
| `tag`           | `mit` `mat`                                   |
| `block`         | `mic` `mac` (org blocks, markdown fences)     |
| `treesit`       | tree-sitter objects (custom bindings)         |

**Edit sessions** (each operation is its own session group)

| Subcat                | Keys                                          |
| --------------------- | --------------------------------------------- |
| `kill`                | `d`                                           |
| `delete`              | `D`                                           |
| `delete-backward-char`| `BS`                                          |
| `delete-backward-word`| `C-BS` `M-BS`                                 |
| `change`              | `c`                                           |
| `change-noyank`       | `C`                                           |
| `replace`             | `r`                                           |
| `copy`                | `y`                                           |
| `yank`                | `p`                                           |
| `yank-before`         | `P`                                           |
| `yank-pop`            | `M-y`                                         |
| `indent-left`         | `<`                                           |
| `indent-right`        | `>`                                           |
| `case`                | `~`                                           |
| `comment`             | `g c`                                         |
| `shell`               | `!`                                           |
| `fill`                | `g q`                                         |
| `join-lines`          | `J`                                           |
| `replace-char`        | `R`                                           |
| `surround-add`        | `m s`                                         |
| `surround-delete`     | `m d`                                         |
| `surround-replace`    | `m r`                                         |
| `swap`                | `S`                                           |

**State sessions**

| Subcat    | Keys                                    |
| --------- | --------------------------------------- |
| `insert`  | `i` `a` `I` `A` `o` `O`                |
| `exit`    | `ESC` (exit insert mode)               |

### Examples

Example 1 — Buffer `hello world`, cursor at `hel|lo`:
```
w w        two word-forward movements, point at buffer end
;          selects the full span: "hello world" (1..12)
C-;        selects "lo world" (4..12), from original cursor to end
```

Example 2:
```
w w        move forward two words
;          mark start of this w w session

j j        move down two lines
;          mark start of j j (NOT the w w start!)
;          again: mark start of w w
C-u ;      back to j j mark

f x        find char "x"
n n        next "x" twice
;          mark start of this find session
;          again: older session ...

C-g        cancel session
w          new session, new start position
;          mark start of this new w
;          again: mark start of the old w w
```

---

## Jump Navigation (`C-o` / `C-i`)

Global, cross-buffer jump navigation.

| Key                 | Behavior                                                             |
| ------------------- | -------------------------------------------------------------------- |
| `C-o`               | Jump to previous (older) position, switching buffers if needed       |
| `C-i`               | Jump to next (newer) position                                        |

Unlike `;` which sets the mark, jump commands *move point* and support
cross-buffer navigation.  Every action recorded for `;` is also in the
jump list.

### Registering Jump Commands

```elisp
;; Method 1: one line — adds :before advice
(helixel-define-jump-command 'my-goto-command)

;; Method 2: call from inside your command body
(defun my-command ()
  (interactive)
  (helixel-register-jump 'goto 'my-cmd)
  ...)
```

### Configuration

```elisp
;; Max entries (default 100)
(setq helixel-jump-log-max 200)

;; Categories recorded (default: all)
(setq helixel-jump-categories '(movement search find-char edit goto))

;; Categories visible during C-o / C-i cycling
(setq helixel-jump-cycle-categories '(search find-char edit goto))
```

---

## Multi-Cursor (`s`)

`s` is the multi-cursor prefix.  `s s` toggles spawning from the most
recent selection or last edit.  When active, fake cursors carry their
*own* point, mark, `mark-active`, `kill-ring` and helixel state — any
whitelisted command runs at every cursor in one undo step.

### Spawning Cursors

`s s` pulls the current selection:

| Selection kind             | Cursor layout                                  |
| -------------------------- | ---------------------------------------------- |
| line / rect                | column cursors at `current-column` per line    |
| search (`/` `?` `*` `#`)   | one cursor per match in the whole buffer       |
| textobj (`miw` `maw` …)    | one cursor per same-kind thing in the buffer   |
| find-char (`f` `t` …)      | one cursor per occurrence                      |
| movement (`w` `e` `b` …)   | one cursor per advance step                    |

### Managing Cursors

#### `s` prefix (always available in normal mode)

| Key                      | Action                                                   | Helix       |
| ------------------------ | ---------------------------------------------------------| ----------- |
| `s s`                    | Toggle (spawn from last selection / clear)               |             |
| `s ,`                    | Clear all fake cursors (keep primary only)               |             |
| `s a` `s A`              | Add fake at point, move real to next / previous line     | `C` `Alt-C` |
| `s x`                    | Per-line cursors: line-mode → REGION; char-mode → POINT  | `Alt-s`     |
| `s n` `s p`              | Add cursor at next / previous occurrence                 |             |
| `s N` `s P`              | Skip next / previous match (no cursor added)             |             |
| `s u` `s U`              | Unmark next / previous fake cursor                       |             |
| `s .`                    | Apply last edit at every fake cursor                     |             |
| `s k` `s K`              | Keep / remove cursors whose region matches a regex       | `K` `Alt-K` |
| `s r`                    | Select all regex matches within selections              | `s`         |
| `s S` `s d`              | Split each selection on regex                           | `S`         |
| `s -`                    | Merge all cursors into one big region                    | `Alt--`     |
| `s &`                    | Column-align cursors by padding with spaces              | `&`         |
| `s _`                    | Trim leading / trailing whitespace from each region      | `_`         |

#### Top-level keys (always available, enable mc automatically)

| Key    | Action                                                | Helix     |
| ------ | ----------------------------------------------------- | --------- |
| `C`    | Add fake at point, move real down (same as `s a`)     | `C`       |
| `M-c`  | Add fake at point, move real up (same as `s A`)       | `Alt-C`   |

#### Top-level keys (when multi-cursor is active)

When fake cursors exist, these keys work directly — no `s` prefix needed:

| Key              | Action                                          | Helix       |
| ---------------- | ----------------------------------------------- | ----------- |
| `K`              | Keep cursors matching a regex                   | `K`         |
| `M-k`            | Remove cursors matching a regex                 | `Alt-K`     |
| `&`              | Column-align cursors by padding with spaces     | `&`         |
| `_`              | Trim whitespace from each region                | `_`         |
| `M--`            | Merge all cursors into one big region           | `Alt--`     |
| `M-,`            | Remove primary cursor, promote nearest          | `Alt-,`     |

#### Top-level rotation keys (when multi-cursor is active)

| Key             | Action                                            | Helix         |
| --------------- | ------------------------------------------------- | ------------- |
| `(` / `)`       | Rotate primary cursor backward / forward          | `(` / `)`     |
| `M-(` / `M-)`   | Rotate selection content backward / forward       | `Alt-(` / `Alt-)` |
| `g v`           | Restore last cursor layout (history stack)        | `g v`         |

**Tip**: After any `s n`/`s p`/`s N`/`s P`/`s u`/`s U`/`s a`/`s A`, press
`,` (normal mode) to repeat the last action — no need for the `s` prefix.
See [Motion Repeat (`,`)](#motion-repeat-) for details.

### Workflows

Edit every occurrence of a word:
```
miw c FOO <ESC> s s s .
# select word → change to FOO → spawn cursors → apply to all
```

Search-and-replace at every match:
```
/foo<RET> s s c bar <ESC>
# search foo → spawn cursors → change to bar
```

Per-line editing:
```
x x x s s i // <ESC>
# line-select 3 lines → spawn column cursors → insert // on each
```

### `;` with Multi-Cursor

Each fake cursor owns its own event ring.  When `;` broadcasts,
every cursor cycles its OWN history:

```
/foobar<RET> s s w w w ; d
# search → spawn → 3 words forward at each → ; selects the traversed
# span at each cursor → d deletes each cursor's selected span
```

Caveats: fakes have empty history at spawn; `C-o` / `C-i` are real-only.

### Integration with `.` and `@`

- `.` replays each cursor's own last edit independently
- `@ ... ESC` while multi-cursor is active: the chain transaction is
  broadcast to every fake cursor, applied once at each position (one undo step)
- `ESC` in normal mode: if chaining → finish chain; else if cursors
  visible → clear them; else `keyboard-quit`
- `C-g` always clears fake cursors before propagating

### Whitelist

Control dispatch via the `helixel-multiple-cursors` symbol property:

```elisp
(put 'my-edit-cmd 'helixel-multiple-cursors t)   ;; all cursors
(put 'my-global-cmd 'helixel-multiple-cursors nil) ;; real cursor only

;; Bulk whitelist
(helixel-mc-mark-all-for-multi-cursors '(cmd1 cmd2))
(helixel-mc-mark-all-for-real-cursor-only '(cmd3 cmd4))

;; Default policy for commands without the property
(setq helixel-mc-default-policy 'all)  ;; 'all | 'once | 'prompt
```

---

## Motion Repeat (`,`)

`,` repeats the most recent motion from a self-contained snapshot —
it does not depend on the current active search or region.

### Supported Types

| Kind        | Subcat                                  | Example                                      |
| ----------- | --------------------------------------- | -------------------------------------------- |
| find-char   | `next` / `till`                         | `f x` → `,` finds next x (like `n`)          |
| movement    | `pair`                                  | `]` → `,` skip past next paren boundary      |
| movement    | `match`                                 | `%` → `,` expand one nesting level outward   |
| movement    | `paragraph` / `sentence` / `function`   | `}` → `,` skip past next boundary            |
| search      | —                                       | `/foo` → `,` find next match (like `n`)      |
| mc-spawn    | `mark` / `skip` / `unmark` / `add`     | `s n` → `,` mark another next occurrence     |

### mc-spawn: Multi-Cursor Repeat

After any multi-cursor spawn command under `s`, pressing `,` (in normal
mode) repeats the last action — no need to type the `s` prefix again:

| First key | Then `,` repeats      |
| --------- | --------------------- |
| `s n`     | mark next occurrence  |
| `s p`     | mark previous         |
| `s N`     | skip next             |
| `s P`     | skip previous         |
| `s u`     | unmark next           |
| `s U`     | unmark previous       |
| `s a`     | add cursor below      |
| `s A`     | add cursor above      |

Prefix arguments work as usual:

- `-,` — permanently flip direction (e.g. `s n` then `-,` → now marks
  previous occurrences until you flip again)
- `3,` — repeat 3 times

`,` always repeats the *most recent* motion.  If you perform a find-char
or search after `s n`, `,` will replay that find-char instead.

### Layer-by-layer Outward

Inside a nested pair, `%` jumps to the matching delimiter.  `,` then moves
one level outward to the enclosing pair:

```
(a (b (c)))
      ↑
%     → jump to ) after (c)
,     → outward to ) after (b)
,     → outward to ) after (a)
```

Works through mixed brackets and block delimiters:

```
#+begin_src elisp
(let ((x 1))
  (message x))
#+end_src
;; % inside (message x) → matching )
;; , → outward to (let ...)
;; , → outward to #+begin_src
```

### `,` with `;`

Every motion repeated by `,` records its own event.  Pressing `;` after
`,` selects the full span just traversed:

```
(a (b (c)))
      ↑
%     → jump to ) after (c)
,     → outward to ) after (b)
;     → select (b (c))
,     → outward to ) after (a)
;     → select (a (b (c)))
```

### find-char: `,` vs `n`

Both `n` and `,` repeat find-char, but `,` reads from a self-contained
snapshot — it survives across an intervening search:

```
f x        find x — recorded for ,
/pattern   active-search now points to search, not find-char
,          still finds the next x (from snapshot)
n          repeats /pattern (from active-search)
```

### For Pair Motions

`, ` skips past the current pair before re-invoking the original command:

```
(a) (b) (c)
]     → after ) of (a)
,     → after ) of (b)
,     → after ) of (c)
```

### Configuration

```elisp
;; Categories repeatable by ,
(setq helixel-motion-repeat-categories
      '((movement . pair) (movement . match) (movement . paragraph)
        (movement . sentence) (movement . function) search find-char
        mc-spawn))

;; Disable motion repeat entirely
(setq helixel-motion-repeat-categories nil)

;; Add custom motion subcats
(push '(movement . my-thing) helixel-motion-repeat-categories)
```

---

## Surround

### Surround Keys

`m s` reads a character and looks it up first in
`helixel-surround-block-alist` (per-mode string pairs), then in the
built-in char pairs.  `m t` reads a tag name string and wraps in XML tags.
`m d` / `m r` use the previous text object selection (mi/ma).

| Key           | Selection type             | Behavior                                      |
| ------------- | -------------------------- | --------------------------------------------- |
| `m s` `(`     | Active region              | Wrap region in `( )`                          |
| `m s` `[`     | Active region              | Wrap region in `[ ]`                          |
| `m s` `{`     | Active region              | Wrap region in `{ }`                          |
| `m s` `<`     | Active region              | Wrap region in `< >`                          |
| `m s` `'`     | Active region              | Wrap region in `' '`                          |
| `m s` `"`     | Active region              | Wrap region in `" "`                          |
| `m s` `` ` `` | Active region              | Wrap region in `` ` ``                        |
| `m s` `s`     | Active region (org)        | Wrap in `#+begin_src` / `#+end_src`           |
| `m s` `e`     | Active region (org)        | Wrap in `#+begin_example` / `#+end_example`   |
| `m s` `q`     | Active region (org)        | Wrap in `#+begin_quote` / `#+end_quote`       |
| `m t`         | Active region              | Wrap in `<tag>` / `</tag>`                    |
| `m d`         | After mi/ma                | Delete surrounding delimiters                 |
| `m r`         | After mi/ma                | Replace surrounding delimiters                |

After `m s` or `m r`, the new region stays selected.

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

---

## Swap (`S`)

Swaps the active region with a *swap source* — text previously copied
with `y`.  Position-aware and cross-buffer.

### Basic Flow

1. Select text → `y` (copy + store as swap source)
2. Select other text → `S` (swap)

| Key   | Behavior                                                          |
| ----- | ----------------------------------------------------------------- |
| `y`   | Copy selection to `kill-ring` *and* store as swap source          |
| `S`   | Swap active region with swap source (position-aware)              |

### Implied Region

When `S` is pressed without an active region, a target region is *implied*
starting at point:

| Source type      | Implied region                                                     |
| ---------------- | ------------------------------------------------------------------ |
| character-wise   | Same character-length range starting at point                      |
| line-wise        | Same number of *full lines* starting from current line             |
| rect-wise        | Same column span × same line count, starting from current column   |

Example: `3x y` to yank 3 lines line-wise, then move elsewhere and `S` —
3 full lines starting at the current line are swapped.

### Rectangle Swap

Rectangle selections swap line-by-line.  Each line pair is exchanged
independently, preserving column alignment where possible.

- **Default**: shorter rectangle is extended downward (new lines use same column span)
- **`C-u S`**: truncates to `min(N,M)` lines

### Register Integration

| Key     | Behavior                                                      |
| ------- | ------------------------------------------------------------- |
| `"aS`   | Swap with register `a` (position-aware if stored by `"a y`)   |
| `"0S`   | Swap with last yanked text (register 0)                       |
| `"1S`   | Swap with last deleted text (register 1)                      |

### Edge Cases

- **Cross-buffer**: works — source markers carry their native buffer
- **Overlapping regions**: `user-error`
- **No source**: `user-error` — use `y` first
- **Rectangle at buffer end**: stops at last line

---

## Chain Recording (`@`)

> **⚠ Experimental.** This feature is under active development.
> Behavior and APIs may change in future releases.

Record a sequence of commands and replay as a unit with `.`.

| Key     | Action                           |
| ------- | -------------------------------- |
| `@`     | Start chain recording            |
| `ESC`   | End chain, create compound tx    |
| `.`     | Advance to next target, replay   |
| `C-g`   | Cancel chain (discard)           |

### How It Works

1. Select a target (line with `x`, search match with `/`) — this establishes
   the *advance context*.
2. `@` — starts recording, snapshots the selection.
3. Perform any editing operations — all commands (helixel and vanilla Emacs)
   are captured as replayable entries.
4. `ESC` — stops recording, creates a chain transaction.
5. `.` — advances to the *next* target and replays the recorded sequence.

### Capture & Advance

| Command type             | Capture mechanism                          | Replay method                            |
| ------------------------ | ------------------------------------------ | ---------------------------------------- |
| Helixel edits (d, c)     | `action-commit-hook`                       | Runner function                          |
| Helixel movements (w)    | `action-commit-hook`                       | Selection recreate                       |
| Insert-mode typing       | after-change-functions                     | Text segments verbatim                   |
| Vanilla commands (C-a)   | `post-command-hook`                        | `execute-kbd-macro` with original keys   |

Insert-mode commands are captured exclusively by the insert-recording
mechanism and NOT duplicated as vanilla entries (prevents double-replay).

| Init ctx       | Advance                                                 |
| -------------- | ------------------------------------------------------- |
| Line (`x`)     | Next line (EOL positioning matches recording context)   |
| Search (`/`)   | Next match                                              |
| None           | In-place (no advance, replay at cursor position)        |

### Third-party Integration

```elisp
;; Exclude commands from vanilla capture
(add-hook 'helixel-chain-vanilla-exclude-predicates
          (lambda (cmd) (memq cmd '(my-custom-cmd))))

;; Custom replay for vanilla commands
(setq helixel-chain-vanilla-replay-function
      (lambda (cmd entry)
        (my-replay-command cmd (helixel-action-payload-get entry :prefix))))

;; Chain lifecycle hooks
(add-hook 'helixel-chain-start-hook  #'my-chain-setup)
(add-hook 'helixel-chain-end-hook    #'my-chain-commit)
(add-hook 'helixel-chain-cancel-hook #'my-chain-cleanup)
```

### Examples

```
x             select line (advance by line)
@             start chain
bb;           select 2 words backward 
d             kill
ESC           end chain
.             next line: select 2 words backward, kill

/foo<RET>     search for "foo" (advance by search match)
@             start chain
cbar<ESC>     change to "bar"
ESC           end chain
.             next "foo" match: change to "bar"
```

---

## Configuration

All configurable options are available via `M-x customize-group RET helixel RET`.

### Key Options

```elisp
;; PCRE-style regexp search (requires pcre2el)
(setq helixel-search-pcre t)

;; Max entries in action ring (default 50)
(setq helixel-action-ring-max 200)

;; Max entries in jump log (default 100)
(setq helixel-jump-log-max 200)

;; Max multi-cursors (default 200)
(setq helixel-mc-max-cursors 500)

;; Replace delete char behavior
(setq helixel-replace-delete-char-p t)

;; Multi-cursor history depth (default 16)
(setq helixel-mc-history-max 32)

;; Default register for yank (default `"`)
(setq helixel-default-register ?\")
```

### Space Leader Key

`helixel-space-map` is a leader keymap bound to SPC in normal state.
Add bindings via `helixel-define-key' and SPC is automatically enabled:

```elisp
(helixel-define-key 'space "w" #'my-command)  ; auto-enables SPC
(helixel-define-key 'space "f" #'find-file)   ; add more bindings
```

When all user bindings are removed, SPC is automatically unbound.

For a more flexible leader-key experience, consider
[leadkey](https://github.com/jixiuf/emacs-leadkey).
leadkey translates leader keys via `key-translation-map', so SPC f
arrives as `C-c C-f` without any manual rebinding — all your existing
C-c / C-x / M- bindings work automatically through the leader key.

### Adding Keybindings

```elisp
(helixel-define-key 'space "w" #'my-command)
(helixel-define-key 'normal "S" #'my-command)
(helixel-define-key 'insert "C-d" #'my-command 'python-mode)
```

### Excluding Buffers

```elisp
(add-to-list  'helixel-major-mode-default-states '(reb-mode . insert))
```

---

## FAQ

See [docs/FAQ.md](FAQ.md).
