# Design decisions for 0.8.1

Questions the sheets leave open, decided against them so the work could go on.
One entry per decision, with the gap it belongs to (`docs/DESIGN-GAPS-0.8.1.md`).

## Shell (wave 1)

- **DG-002 · No Ctrl \ any more.** The day panel it toggled is gone, so the key is free. The
  keymap still lists it; the sheets have no panel to toggle, and the sheets win. The people the
  panel held open from Today (a name in "Кому написать") and from the command line ("Кому
  написать: все", `people.open`) in a dialog shaped like `X-Oth-Archive-People`: the list, one
  person beside it, "Написал / Ответил", edit and "убрать из списка". The sheet's "Связанные
  задачи" and "Встречи" are left out: lowkey keeps no link between a person and a task or a
  meeting, and making one up would be the autopilot the product is not.
- **DG-161 · The archive's month is the month the status last changed.** A task has no
  "archived at" date. The status change is what sent it to the archive (done, then 14 days), so
  its month is the closest fact. "By month" is offered in the grouping chip only while the query
  holds "is:archived", and the list picks it on its own there unless another grouping was chosen.
- **DG-161 · No "вернуть U" on the row.** `U` is the second key of Undo (keymap.md). The row
  restores from its menu and the selection bar ("Вернуть"), which already did.
- **DG-162 · Old names still land.** "timeline" and "archive" from a state file, a saved view or
  `--view` open the list (the archive with "is:archived"), so nothing a user saved points nowhere.
- **DG-140 · "+N" counts the waiting toasts.** One toast at a time; the others wait and show as
  "+N" on the one on screen. The kind is a ring (StatusRing): done filled, notice a ring, warning
  a quarter, error a barred ring; coloured only in the bold style. An action that has a key shows
  it after the action (Undo: "Ctrl Z").
- **DG-005 · Danger outranks primary** on a button with both: a destructive main action reads as
  destructive (the sheet's "Удалить колонку" is outlined red, never the bright line).
- **DG-004 · The quiet flags follow "chip fill".** `Style.fills`, `sideCards`, `textOptions`,
  `textLinks`, `plainRows` are derived from the one switch the Appearance page shows ("Заливка и
  цвет чипов"), so the style page keeps the sheet's seven switches and "custom" still means a
  mix of those.
- **DG-007 · "Example" in both languages.** The sheets name the example profile "Example" in
  the Russian UI too. A profile already stored as "Пример" keeps its name (it is the user's data);
  starter views whose names were never changed follow the UI language.
- **DG-008 · Small is below 1360 px of window width.** The sheet draws the small layout at
  1280×720 (its note says ~1100, its frame is 1280). 1280 folds, 1366 (the common laptop width)
  keeps the full sidebar.
