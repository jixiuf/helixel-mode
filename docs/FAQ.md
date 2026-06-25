# helixel-mode FAQ

## Q: How do I disable helixel for certain buffers?

Use `helixel-major-mode-default-states` to set `insert` state (acts like
helixel is off in those buffers), or use `helixel-mode-maybe-activate`
to prevent activation:

```elisp
(add-to-list  'helixel-major-mode-default-states '(reb-mode . insert))
```

## Q: How do I repeat the last motion (`f`, `t`, `%`, etc.)?

Use `,` (comma).  This works for find-char, match/pair jumps, paragraph,
sentence, function, and search.  It reads from a self-contained snapshot
so it survives intervening operations.

## Q: What's the difference between `;` and `C-;`?

`;` selects the full span (from the motion's origin to its destination).
`C-;` pushes mark to the motion's origin position only.  Both cycle through
the same history, but they maintain independent positions.

## Q: How does `N` differ from `-.`?

`N` permanently flips the search direction for subsequent `n` presses.
`-.` permanently flips the dot-repeat direction for subsequent `.` presses.
Both are toggles — press again to flip back.

## Q: How do I add custom text objects?

Use `helixel-define-mark-object` for thing-based text objects, or
`helixel-define-regex-textobj` for regex-delimited ones.  See the
**Custom Text Objects** section in the User Guide, or the full API at
`docs/API.md`.

## Q: How do I report bugs?

Open an issue at <https://github.com/jixiuf/helixel-mode>.  Include:
- Emacs version (`M-x emacs-version`)
- helixel version (`M-x list-packages` shows installed version)
- Steps to reproduce
- Expected vs actual behavior
