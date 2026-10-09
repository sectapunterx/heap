# Design decisions (0.8.1)

Questions the sheets leave open, decided against the sheets (ui-ux-pro-max:
progressive disclosure, content priority, state preservation). One entry each.

## Knowledge

- **DG-070 · Where the rest of the Docs catalogue goes.** The list shows
  Закреплено / Заметки / Сниппеты only. A reference stands in Закреплено when it
  is pinned (`pinned: true` in the docs blob; the starter catalogue pins RFC
  9110, RFC 6749 and OpenAPI). Unpinned references and contacts appear only
  while searching the list ("Ссылки", "Контакты" groups) and in Ctrl K, which
  opens the list searched for the hit. Right-click a reference to pin or unpin
  it. Why: progressive disclosure keeps the sheet's list at rest, and nothing
  of the catalogue is lost or unreachable. A collapsed group was rejected: it
  is UI the sheet does not show.
- **DG-070 · Docs pages.** Pages of the former catalogue are listed flat under
  "Страницы" (only when a profile has any) and open in the same document area,
  drawn and edited like a note, with "Страница · изменена …" above. The page
  tree, new pages and moving pages are gone with DocsView; rename and delete
  stay on the row's right-click menu. Notes replace new pages.
- **DG-071 · What left the toolbar.** Attach (Ctrl+Shift+A in the editor), the
  list toggle (Ctrl+Alt+L, Ctrl K "notes.toggleList"), the whole source
  (Ctrl+Shift+M) stay on their keys. The links column shows itself when the
  view is wider than 1000 px; there is no toggle.
- **DG-072 · Column order and content.** Bold: Задачи в заметке, Ссылаются
  сюда, Внешние ссылки; quiet: Ссылаются сюда first (as Q-Knowledge). An empty
  group is not drawn. "Ссылки из заметки" (outgoing) is not in the sheets and
  left the column; the links stay visible in the note itself. An external
  link's title (`[RFC 6585](url "429 Too Many Requests")`) reads after its
  label.
- **DG-073 · Note order.** Newest first by creation time. The sheet's order is
  not alphabetical; ordering by last edit would make the note being typed in
  jump to the top of the list (state preservation), creation order does not.

## Settings (DG-090…103)

- **DG-090 — settings the sheets do not show.** Rows a user may have set
  (scale, contrast, own cursor colour, own themes, close to tray, start at
  login; showing weekends, grid snap, focus blocks, standup time; default
  priority, blocked highlight, branch before review; desktop notifications and
  a test, deadline lead, snooze lengths, standup reminder, digests, volume,
  chime minutes; end-of-day, waiting, seen-before, standup draft; shortcut
  hints, reset all keys; auto backup and its interval, restoring a backup copy,
  JSON import, unused attachments, reset settings, wipe; storage path, engine,
  logs) are folded under a quiet "Ещё настройки" line at the end of their
  section. At rest every section shows exactly the sheet's rows; nothing a user
  configured is lost or unreachable, and a settings search opens the fold so a
  hit can still be revealed. [progressive-disclosure; consistency — a fold in
  place beats a command-only path, which hides a setting from the page it
  belongs to.]
- **DG-101 — Профиль removed.** `settings.profile` (name, handle, role, team,
  avatar colour) is read by nothing outside the section; the stored values stay
  in the JSON untouched. The old `settings:profile` deep link opens the top.
- **DG-091 — sections.** The X sheets' eleven plus Помощь, in their order;
  "Слежение за Git" is the block heading, "Git" the nav name; no version footer
  or debug toggle in the nav (the version is under О программе).
- **DG-090 — layout of a row.** One rule for the whole page: label and hint on
  the left, options right-aligned (H2-Settings / Q-Settings, X-Set-Columns,
  X-Set-StyleKeys). The three-column composites (CalNotif, GitLangAbout) set
  options under the label only for want of width. [consistency, visual-hierarchy.]
- **DG-090 — which style is "quiet" here.** The settings page follows the
  chip-fill switch (`Style.chipFill`), the same switch as the rest of the quiet
  look: off = no fills, lowercase options, outline pill on the picked one.
- **DG-093 — sign-in state cards.** The three cards under the list ("Не
  подключено / Ждём подтверждения / Подключено как") illustrate the states; the
  app shows the picked tracker's actual state in its detail (header line, the
  device code while waiting, "Выйти" when connected) instead of three static
  cards. [state-clarity; no decorative duplicates of live state.]
- **DG-093 — "Как часто".** The cadence is one setting for all trackers
  (`integrations.autoSyncMinutes`); every tracker's detail shows it and says so
  in the hint, instead of inventing a per-tracker schedule. "Синхронизировать"
  sits beside it, so the old manual sync is not lost.
- **DG-093 — rows without a function behind them are omitted**: "Спрашивать
  перед отправкой" (writes already confirm on a remote conflict; asking before
  every write needs a new flow) — follow-up ticket. "Тикеты вне фильтра" shows
  the real behaviour: kept as "только здесь", with "в архив" offered when there
  are any. [disabled-states: no controls that look usable but do nothing.]
- **DG-093 — MR/PR switches** (pull reviews, roles, may move) stay inside the
  tracker detail under the sheet's rows; the connection fields fold behind
  "Поля подключения".
- **DG-095 — Сроки.** The scheduler reminds a set number of hours before the
  deadline, not at 9:00; the option says the real lead ("за 24 ч") instead of
  promising a morning reminder. Morning mode is a follow-up.
- **DG-096 — Удалённые задачи (30 дней / навсегда)** is omitted: deletion is
  final today (Undo only), so there is nothing to keep; it needs a trash store
  (schema change). Снимки каждый день / каждый час, Хранить 7/14/30 and Снимок
  перед импортом и обновлением are wired (`data.historyEvery`,
  `data.historyDays`, `data.snapshotBeforeImport`). A stored 90 days stays and
  shows as a fourth option.
- **DG-099 — Git.** "Связывать ветку с задачей" switches branch→task matching
  off (`git.linkBranches`); "Строка «работаю над …»" hides the branch line over
  the view (`git.workingOnLine`); auto-move, auto focus block and "whose move"
  went to the fold.
- **DG-100 — Формат даты** is the clock format (как в системе / 24 ч / 12 ч,
  `calendar.timeFormat`, "system" = the locale's). "Разбор дат в вводе" states
  what the parser does (ru + en) and offers no other choice.
- **DG-102 — Помощь.** Three rows. "С чего начать" opens the existing guide
  (HelpContent) in a reader over the page — the guide had no note in Knowledge
  to point at, and the welcome tour's "Learn more" still lands in it.
- **DG-103 — О программе.** "Канал stable/beta" is omitted (the updater reads
  only stable releases); the channel is in the section line ("lowkey 0.8.1 ·
  stable"). "Проверить сейчас" stays on the Обновления row: with "только
  вручную" it is the only way to check. "Что нового" and "Лицензии" open the
  release notes and THIRD_PARTY_NOTICES on GitHub. Данные: export offers JSON
  (profile) or Markdown (notes), as the sheet's hint says.
- **DG-097 — Клавиши.** One row per action name (the catalogue keeps a few
  actions twice); a key is rebound in place; a conflict opens its box under the
  row, not at the end of a long list; the read-only rail panel stays.
- **DG-003 — glyphs.** `qml/Icon.qml` is not on heap2/0.8.1 yet: the drag
  handle and the column menu are drawn dots, the stage is StatusRing;
  dropdown chevrons come from the shared AppComboBox. Swap in Icon when it
  lands.

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

## Dialogs group

- **DG-120 · A series' words belong to the series.** In the auto-saving meeting panel, edits to the title, agenda, people, call, reminder, task and profile of a recurring meeting apply to the whole series without a question. Only a move, a rule change or a delete asks "only this / this and following / all" (the sheet's question is about "перенос, длительность, удаление"). Asking on every pause in typing would break the auto-save; all of it is undoable with Ctrl Z.
- **DG-120 · New meetings come only from the one-line input.** Ctrl Alt E, `event.new` and a click or drag on the calendar grid all open the one-line input with chips (the slot pre-fills "когда"). Enter makes the meeting and opens it in the panel. Nothing is made without a name.
- **DG-120 · Kept off the panel, never lost.** Location stays as the placeholder of the Call row and is saved as it is. Context is saved as it is. Type moves into the header word ("встреча" opens a menu with the types). A rule the repeat menu cannot show (days, an end date, a count) is edited as RRULE text under "Повтор → Своё правило". The weekday chips and the date pickers are gone: you type "Когда" ("пт 14:00", "завтра 10–11", "весь день").
- **DG-121 · Per-item restore goes into the diff.** The deleted task IDs in the "Задачи" row are links. Each one brings back just that task (undoable). The long per-item list with "Вернуть эту версию" is gone: "Открыть копией в новом профиле" covers comparing versions.
- **DG-121 · Retention behind one quiet line.** The dialog has no 7/30/90 and MB pills now. "хранить 30 дн., до 200 МБ" sits under the snapshot list and opens a menu.
- **DG-122 · Source by kind.** Log entries carry no provider yet, so the source column says Синк / Задачи / Напоминание / Данные / lowkey by entry kind. "отменить" shows only on the newest undoable entry, the one Ctrl Z takes back. "решить" and "войти" wait for entries that carry a target.
- **DG-123 · "Следующая неделя →" opens the calendar.** It shows next week in the week view, to look at, not a planning view (lowkey supports, it does not plan). Opened by hand, the recap shows the current week, and [ and ] step back through earlier weeks. Opened on its own on Monday, it shows last week. "Перенесено" is left out of the facts line: nothing records a carry yet.
- **DG-124 · Closed today is a count.** It shows as "Закрыто N" in the facts line, not as a list. A running timer is a sentence with "остановить?" one click away.
- **DG-126 · Person = name + what to ask.** The handle is made from the name. Role, state and colour stay as stored (they come from imports and the Today rail). The contacts picker no longer opens from `person.new`. It stays only as the waiting-on picker inside the legacy TaskEditor.
- **DG-133 · Only the sheet's areas.** The cheat sheet shows the nine X-Keys areas, and rows with no key are hidden. Every other catalogue key still turns up under a search, so a key that exists can always be found. "Сдвинуть колонку Ctrl Shift H/L" is left out: there is no such binding, and Ctrl Shift L is the log.
- **DG-132 · The focus screen sits under the toasts.** Meeting reminders still show over it. D marks the task done and ends the session. Leaving with nothing held back shows no toast.

## Today and first run (wave 2)

- **DG-010 · Facts only where they are not zero.** The line keeps the sheet's parts (встречи · задачи в плане · сроки) and leaves a zero part out instead of writing "0 задач в плане"; a day with none says "Ничего не запланировано". Quiet and the small window say "1 срок сегодня" (H2-Today-Calm, X-Oth-Small), bold "1 срок истекает сегодня" (H2-Today). The "load" line is gone from Today; the week still shows the load per day.
- **DG-011 · No arrows where the sheets have none.** ‹ › stand at the far right of the header (boxed in bold, bare chevrons in quiet) and are not drawn on the first run or in the small window (H2-First, Q-First, X-Oth-Small); [ ] and Alt ←/→ still move the day there.
- **DG-012 · Quiet free time is a gap.** A free window of an hour or more is a blank 22 px, as on H2-Calm; the end of the working day is not drawn in quiet. A focus block's people field is a note ("глубокая работа"), so Today shows it as "встреча с собой" only, in both styles; the 🔒 is gone from the sample data and from new time blocks.
- **DG-013 · Quiet side = what the sheet shows.** "В работе", "Срок сегодня" (tomorrow's deadlines stay bold-only), "▸ Кому написать · N" folded. Overdue keeps its one dim line ("раньше: N"), since dropping it would hide a fact. The undated link is bold-only; quiet reaches undated tasks through the empty day's line ("в «Задачах» N без даты", X-Err-Empty) and the Tasks list. The weekly recap line stays in both styles (owner).
- **DG-014 · One card, the rest as lines.** With several tasks in progress, the card shows the one with a running timer, else the one whose branch is checked out, else the first; the others follow as compact lines under it, so nothing in progress is hidden. [content-priority; progressive-disclosure without hiding facts.] PR and CI show for the checked-out branch's task, the only one lowkey has repo facts for.
- **DG-015 · "Написал".** Bold: the outlined button. Quiet: an underlined "написал" text link (textLinks). The footer is a hairline row with the text on the left and → on the right.
- **DG-110 · The third key is "?".** The cards show the `hotkeys.open.alt` key (the sheet's "?"), not Ctrl /; all three take the row's height. The ↵ glyph in the input became a mono "Enter" key hint (no text glyphs as icons).
- **DG-131 · The tour is gone, the guide stays.** WelcomePopup, Tour.js and the "continue tour" pill are removed. `welcome.replay` keeps its id (stored key bindings still point at it) and is now "С чего начать" in Ctrl K: it opens the guide in Settings → Помощь, like the "С чего начать" row. The guide's own "Пройти тур заново" button is gone.
- **DG-160 · Esc in two steps.** "Ничего под «…»" names the filter as typed, its words joined with " · " (plus a priority filter). "сбросить фильтр" clears the query and the priority filter; Esc does the same while the keyboard is in the view. In the search field Esc first clears what was typed, as before. [escape-routes; state-preservation: one Esc never throws away more than the user expects.] The second "Ничего не подходит — сбросить запрос" line under the field is gone.
