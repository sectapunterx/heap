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
| Undo last deletion | `Ctrl+Z` |

## Views

| Action | Default |
|--------|---------|
| Board | `Ctrl+1` |
| Timeline | `Ctrl+2` |
| Week | `Ctrl+3` |
| Docs | `Ctrl+4` |
| Notes | `Ctrl+5` |
| Settings | `Ctrl+6` |

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

## Selection (Board / Timeline / Week)

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
- `Esc` also closes any open modal or popup before it clears a selection.
