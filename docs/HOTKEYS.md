# Keyboard reference

Every shortcut in the tables below (except the notes-editor and task-editor
keys) is **rebindable** in the floating Hotkeys panel (`Ctrl+/`). Click a
binding — or Tab to it and press `Enter` / `Space` — press the new
combination and `Enter` to save; `Esc` cancels, `Backspace` clears. Conflicts
are resolved VS Code-style: the new binding wins and the previous owner is
unbound (a toast names what was freed). `↺` restores a single default; `↺ all`
restores the whole catalog after a second press. **Settings → Shortcuts** lists
the current bindings read-only and links to the panel.

The same catalog is in the command palette: every app-wide action below is a
command there, under the same name.

## Who gets a key

Keys go to the innermost thing that holds the keyboard:

- `Esc` closes a menu, dialog, the task editor or the palette first; an
  selection and the board cursor are let go of last. In the header
  search `Esc` clears the text, and a second `Esc` (or `Return`) hands the
  keyboard back to the view.
- The board and calendar keys (bare letters, arrows, `Return`, `Esc`, `Del`,
  `Ctrl+A`) stand down while a text field, dialog, popup, menu or inline rename
  has focus, and while a control outside the view that you reached with `Tab`
  (a filter chip, the mini week, the day panel, the people list) has it — press
  `Esc` there to give the keyboard back to the view.
- The global shortcuts (views, new task, palette, undo…) stand down behind a
  modal — the task or event editor, the palette, a capture popup, the welcome
  tour, a confirmation. The Tweaks and Hotkeys popovers are not modal.

## Global

| Action | Default |
|--------|---------|
| Open Command Palette | `Ctrl+K` (also the fixed alias `Ctrl+P`) |
| New task | `Ctrl+N` |
| Quick-capture task | `Ctrl+Shift+Space` |
| Quick-capture note | `Ctrl+Shift+N` |
| Focus the header search (Notes: open the palette) | `Ctrl+F` |
| Undo the last action | `Ctrl+Z` (not while a dialog is open; in a text field it undoes the typing) |
| Redo | `Ctrl+Shift+Z` |
| Toggle light / dark | `Ctrl+Shift+T` |
| New contact | `Ctrl+Shift+U` |

The header search also takes `field:value` clauses — `status:` (a column by
id or by the name the board shows: `status:"Code Review"`, `status:in-progress`),
`priority:`, `due:`/`deadline:` (`today`, `overdue`, `week`, `<7d`, `friday`,
`none`), `tag:` or `#label`, `mention:`, `is:open`/`done`/`archived`/`overdue` —
mixed freely with ordinary search words. `-` in front of a clause or word
excludes it, `OR` (or `|`) joins alternatives. A clause heap cannot read is
flagged on the search box instead of silently searching for it. See
[TUTORIAL.md](TUTORIAL.md#7-the-search-box-is-a-query-box).

## Command palette

An empty query lists what you opened last, then every command. Words match in
any order and a typo or two is forgiven (`ingress kubernetes`, `kubrenetes`).
Commands cover every action in this file plus each Settings section
("Settings: Appearance"), *New event* and *Replay the welcome tour*. Opening a
task keeps the week, month, timeline or archive view you are on.

| Action | Key |
|---|---|
| Next / previous result | `↓` / `↑` |
| Open | `Return` |
| Close | `Esc` |

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

Previous / next period is live on the week and month views only; the rest
works in every view the day panel sits beside (board, timeline, week, month,
archive). None of them fires while a dialog or a text field has the keys.

| Action | Default |
|--------|---------|
| Go to today | `T` |
| Previous / next period | `←` / `→` |
| Previous / next day | `Alt+Left` / `Alt+Right` |
| Go to a date… | `G` |
| New event at the next free slot | `Ctrl+Alt+E` |

In the date picker: arrows move the day (↑/↓ a week), `PgUp`/`PgDn` a month
(`Shift` a year), `Home`/`End` the month's ends, `T` today, `Enter` picks,
`Esc` closes. In the event editor, `Ctrl+Enter` saves; with unsaved changes
the first `Esc` warns and the second discards. When a drag or an edit touches
a repeating event, `Enter` answers "This event".

## Profiles

| Action | Default |
|--------|---------|
| Next profile | `Ctrl+]` |
| Previous profile | `Ctrl+[` |
| New profile | `Ctrl+Shift+P` |
| Export active profile to Markdown (clipboard) | `Ctrl+Shift+E` |
| Weekly shipped report (clipboard) | `Ctrl+Shift+W` |

## Panels

| Action | Default |
|--------|---------|
| Open Tweaks (theme / density / contrast) | `Ctrl+,` |
| Open Hotkeys panel | `Ctrl+/` |
| Show / hide the calendar column | `Ctrl+\` |
| Expand / collapse the sidebar | `Ctrl+Shift+B` |

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

## Task editor

Fixed keys, live while the editor is open.

| Action | Key |
|---|---|
| Save | `Ctrl+Enter` |
| Close without saving | `Esc` |
| Next / previous field (leaves the description too) | `Tab` / `Shift+Tab` |
| Indent / outdent a list line in the description | `Tab` / `Shift+Tab` on that line |
| Insert indentation anywhere in the description | `Ctrl+Tab` |
| Open / close Details, switch edit ↔ preview | `Tab` to it, then `Space` / `Enter` |

A new task's editor opens with the cursor in the title.

## Moving around without a mouse

| Where | Keys |
|---|---|
| Filter bar (P0–P3, Clear, Sort, Archived) | `Tab` to a chip, `Space` / `Enter`; `↓` opens Sort |
| Profile pill, breadcrumbs | `Tab`, then `Enter` (menu / edit; `F2` edits a crumb) |
| Mini week | `←` / `→` a day, `PgUp` / `PgDn` a week, `Home` today |
| Day panel | `←` / `→` a day, `Home` today, `↑` / `↓` walk the events, `Enter` opens one |
| People list | `↑` / `↓`, `Enter` edits, `Menu` or `Shift+F10` for actions |
| Settings | `Enter` in the search opens the first match, `↓` into the sections, `↑` / `↓` move between them; switches `Space`, segmented rows `←` / `→`, sliders `←` / `→` |
| Tweaks, Hotkeys panels | `Tab` through every control; `Esc` closes |

## Notes view

Rebindable in Settings → Hotkeys; live only while Notes is on screen.

| Action | Shortcut |
|---|---|
| New note (cursor goes in) | `Ctrl+Alt+N` |
| Next / previous note in the list | `Ctrl+PgDown` / `Ctrl+PgUp` |
| Rename or re-file the open note | `F2` |
| Show / hide the list of notes | `Ctrl+Alt+L` |
| Filter the notes (title, folder and body) | `Ctrl+F` |

## Notes and doc page editor

These work while the cursor is in the notes editor or a Docs page, and only
there — `Ctrl+K` still opens the command palette everywhere else. With text
selected, the formatting keys wrap the selection, and `Tab`, `Shift+Tab` and
the heading key act on every selected line. `Ctrl+Z` with nothing left to undo
in the text undoes the last app action (a deleted note or page, an import).

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
- **Task editor:** `Ctrl+Return` saves. `Esc` (or a click on the backdrop) closes
  a task with no changes; with changes it asks — `Return` saves, `D` discards,
  `Esc` keeps editing.
