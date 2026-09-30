# Keyboard reference

Every shortcut below is **rebindable** — open the floating Hotkeys panel
(`Ctrl+/`) or **Settings → Shortcuts**, click a binding, and press the new
combination. Conflicts are resolved VS Code-style: the new binding wins and the
previous owner is unbound (you'll see a toast naming what was freed). *Reset*
restores a single default; *Reset all* restores the whole catalog.

## Global

| Action | Default |
|--------|---------|
| Open Command Palette | `Ctrl+K` (also the fixed alias `Ctrl+P`) |
| New task | `Ctrl+N` |
| Quick-capture task | `Ctrl+Shift+Space` |
| Quick-capture note | `Ctrl+Shift+N` |
| Focus the header search | `Ctrl+F` |
| Undo the last action | `Ctrl+Z` (not while a dialog is open; in a text field it undoes the typing) |
| Redo | `Ctrl+Shift+Z` |

The header search also takes `field:value` clauses — `status:` (a column by
id or by the name the board shows: `status:"Code Review"`, `status:in-progress`),
`priority:`, `due:`/`deadline:` (`today`, `overdue`, `week`, `<7d`, `friday`,
`none`), `tag:` or `#label`, `mention:`, `is:open`/`done`/`archived`/`overdue` —
mixed freely with ordinary search words. `-` in front of a clause or word
excludes it, `OR` (or `|`) joins alternatives. A clause heap cannot read is
flagged on the search box instead of silently searching for it. See
[TUTORIAL.md](TUTORIAL.md#7-the-search-box-is-a-query-box).

## Views

| Action | Default |
|--------|---------|
| Board | `Ctrl+1` |
| Timeline | `Ctrl+2` |
| Week | `Ctrl+3` |
| Month | `Ctrl+4` |
| Archive | `Ctrl+5` |
| Docs | `Ctrl+6` |
| Notes | `Ctrl+7` |
| Settings | `Ctrl+8` |

The numbers follow the side rail, top to bottom.

## Board cursor

Bare letters, so a focused text field still types them. Arrow keys work
alongside each one.

| Action | Default |
|--------|---------|
| Next / previous card | `J` / `K` |
| Previous / next column | `H` / `L` |
| Open the card | `Return` |
| Add to the selection | `Space` |
| Move the card | `Shift+J` / `Shift+K` / `Shift+H` / `Shift+L` |
| Card menu (status, priority, archive, …) | `M` (or the `Menu` key) |
| Archive the card (or the selection) | `E` |
| Fold / unfold the cursor's column | `Z` |

While a card's menu is open its arrows and letters belong to the menu.

## Timeline

`J` / `K` (or `↓` / `↑`) walk the rows, `Return` opens one, `Space` adds it to
the selection, and `O` opens the row's issue in its tracker.

## Calendar

Live on the week and month views only, where the board's own letters are not.

| Action | Default |
|--------|---------|
| Go to today | `T` |
| Previous / next period | `←` / `→` |
| Go to a date… | `G` |

## Profiles

| Action | Default |
|--------|---------|
| Next profile | `Ctrl+]` |
| Previous profile | `Ctrl+[` |
| Export active profile to Markdown (clipboard) | `Ctrl+Shift+E` |

## Panels

| Action | Default |
|--------|---------|
| Open Tweaks (theme / density / a11y) | `Ctrl+,` |
| Open Hotkeys panel | `Ctrl+/` |

## Selection (Board / Timeline / Week / Archive)

| Action | Default |
|--------|---------|
| Select all visible tickets | `Ctrl+A` |
| Clear selection | `Esc` |
| Delete selection (undoable 5 s) | `Del` |
| Open ticket in its tracker | `O` |

`O` acts on the one selected card, or — with nothing selected — on the card
under the cursor. It does nothing for a locally-created task, and it stands
down entirely while a dialog is open or the cursor is in a text field.

## Notes editor

These work while the cursor is in the notes editor, and only there — `Ctrl+K`
still opens the command palette everywhere else.

| Action | Shortcut |
|---|---|
| Bold | `Ctrl+B` |
| Italic | `Ctrl+I` |
| Inline code | `Ctrl+E` |
| Link | `Ctrl+K` |
| Strikethrough | `Ctrl+Shift+X` |
| Highlight (`==text==`) | `Ctrl+Shift+H` |
| Heading level — cycles none → H1 … H6 → none | `Ctrl+Shift+L` |
| Indent / outdent list line | `Tab` / `Shift+Tab` |
| Tick the checkbox on this line | `Ctrl+Enter` |
| Cycle edit → split → preview | `Ctrl+Shift+M` |

`Enter` continues whatever the line is: another bullet, the next number,
another unticked checkbox, another quote marker. On an empty item it removes
the marker instead, which is how you end a list. Inside a fenced code block
`Enter` keeps the indentation and `Tab` inserts spaces.

Pasting a URL over selected text turns it into a link.

Every one of these is a single undo step.

## Notes

- **Quick-capture** opens a single-field popup that parses your line as you type
  — see [TUTORIAL.md](TUTORIAL.md#quick-capture-syntax) for the syntax.
  `Return` adds and closes, `Ctrl+Return` adds and stays open for the next
  item; `Tab` (or the arrows, then `Return`) takes a suggestion. From
  another app it comes up on its own, without the main window, and a
  notification confirms what was created.
- `Esc` also closes any open modal or popup before it clears a selection.
- **Task editor:** `Ctrl+Return` saves. `Esc` (or a click on the backdrop) closes
  a task with no changes; with changes it asks — `Return` saves, `D` discards,
  `Esc` keeps editing.
