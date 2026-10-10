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
  задачи" (tasks waiting on the person, WaitingOn) and "Встречи" (the next two weeks' meetings
  whose attendees line names them: full name, handle, or the first name alone) are shown under the
  question, each hidden when empty (review CHANGE; facts lowkey already stores).
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

## Calendar (wave 2)

- **DG-041 · The day's load moved into the day name's tooltip.** H2/Q-Calendar draw no load bar and no "2 ч 15 мин из 10 ч" on the week columns, so the week follows the sheet. The fact (APP-247) stays one hover away on the day name ("встречи 2 ч · задачи 1 ч · свободно …"), and Today keeps its own load line, where the sheets show load. [progressive-disclosure, content-priority, tooltip-on-interact.]
- **DG-041 · The deadline row is a flag and a title.** No key and no priority mark, because the sheet's row has neither. A task planned for the day without a time reads with its status ring, the same language as everywhere else; the old "◷" glyph is gone (DG-003). Four lines, then "+N ещё", which selects the day.
- **DG-044 · The query row hides on the calendar at rest.** The sheets draw none. It shows while a query holds something, and opens on Ctrl F or type-to-search, so a filter on the grid is never invisible. [state-clarity: no hidden active filter.]
- **DG-045 · "Перенести…" and "Связать с задачей…" open the meeting's panel.** The panel already has the typed "Когда" and the task row and saves on its own; a second editor in a menu would be two ways to do one thing. "Длительность…" is a short list (15 мин … 2 ч), the same as stretching the edge (Ctrl Shift J / K). "Дублировать" makes one single meeting at the same time, even from a series. "Удалить серию…" asks this / following / all, the question the grid already asks. "Новая задача на это время" opens the capture with the day and time typed in; nothing is made without a name. Subscribed (read-only) meetings keep only Открыть and the call.
- **DG-050 · Month order inside a day.** Deadlines and planned tasks first, then meetings, as before: the keyboard cursor walks a day in that order and "+N ещё" follows it. The sheet's mix by time is not drawn; a meeting's time is its tooltip.
- **DG-051 · Day zoom.** The header line is "пт, 9 октября · 2 встречи · 1 задача · срок:" with the deadlines after it as links (they keep their menu, drag and cursor). Rows carry the icon, the title and the range at the right; the second line is where (location / context) or how a series repeats for a meeting, the key for a task.

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

## Tasks group (wave 2)

- **DG-020 · "не готово" is `is:open`.** The default condition is the query clause `is:open`, drawn as the chip "статус не готово". A fresh start, a profile switch and the first start after the upgrade begin from it, unless the saved query already names a status or state (`status:` / `is:`) or is an OR query. Removing the chip shows every task again, as the user asked.
- **DG-020 · The profile chip has no ×.** The board shows one profile; a × that cannot remove the scope would be a dead control (ui-ux-pro-max: a removable chip only where removing does something). Clicking the chip opens the profile switcher. Only the board shows it: H2-List has none, and the list can list every profile (grouping "по профилю").
- **DG-020 · "Сохранить как вид" is always on the bold query line**, including with only the default condition (H2-Board shows it; H2-List does not). One place for one action beats a control that comes and goes (consistency).
- **DG-020 / DG-046 · The calendar has no query line at rest.** It appears there only when the query says more than "не готово", so a filter is never at work out of sight (H2-Calendar shows no line and no count).
- **DG-022 · The folded Done ignores "не готово".** The fold is how the board keeps done work aside, so the column keeps its count and cards: "Готово 2" + "Показать", as H2-Board draws it next to the chip. Every other column is unaffected (they hold no done tasks).
- **DG-021 · Quiet: the lens option is one more outline chip.** "по сроку" on the list (Q-List) and the sort ("вручную") on the board, in the conditions row, since quiet has no button beside the tabs. The sort stays reachable in both styles (owner decision: the sort chip).
- **DG-021 · Quiet field folds on hand-back only.** "изменить фильтр" (or `/`, Ctrl F) opens the field; Esc on an empty field, Return or a lens change fold it back to chips. A plain focus loss does not: the field's own right-click menu takes focus, and folding under it would edit a hidden field.
- **DG-022 · No add-column control on the board.** Columns are added in Settings → Задачи и процесс ("+ Колонка", DG-092). The board's "+" tile and its dialog are gone.
- **DG-025 · What left the column menu.** Colour, auto-archive and "book focus time on entry" are Ctrl K commands that act on the column under the board cursor (else the first): "Колонка: цвет…", "Колонка: автоархив…", "Колонка: бронировать фокус-время при входе". "Этап колонки ›" sets the stage, as Settings does.
- **DG-026 · What left the selection bar.** The label and carry-on actions are Ctrl K commands while a selection exists ("Метка для выбранных…", "Перенести выбранные…"); End of day still carries leftovers. "Готово d" and "Запланировать s" run the same commands as the keys.
- **DG-027 · "Перенести… ›" left the task menu.** Planning another day is "Запланировать… s" (the schedule popup); carrying on stays in End of day and in Ctrl K for a selection. The status and priority lists mark the current row with "сейчас" only, no check.
- **DG-031 · Dates without the locale's dot.** Russian short months read "9 окт", "сб, 10 окт" everywhere (`I18n.fmtDate`). On the list, tomorrow is "9 окт" in bold; quiet writes a weekday alone while it is this week ("пт", "пт, 15:00"), as Q-List. The example tasks carry the sheet's area labels (payments, auth, ui…).
- **DG-150 · Saved view menu.** "Обновить по текущим фильтрам" and "Дублировать" are gone from it: the open view's own line ("обновить" / "сохранить как новый") does both. "Изменить запрос…" opens the view's name and query in one dialog. Shift K / J move a view, as the menu says; Ctrl ↑/↓ still work.
- **DG-151 · Profile switcher.** Always the searchable list. The active profile shows its last good sync ("синк 2 мин назад"); "Ctrl ]" sits on the row it would switch to. Import / export (JSON in Settings → Данные; .ics and the notes folder) and duplicating a profile are Ctrl K commands. Delete is "Удалить профиль…" with a confirmation (see the r3 entry below; review CHANGE).
- **DG-152 · Text field menu.** "Удалить" is gone (Cut and Backspace cover it). "Вставить без форматирования" pastes plain text, which every field here keeps anyway. "Ссылка на задачу… [[" is offered in the Markdown editors (task description, notes); the description's menu carries the context line "Описание задачи".

## Document group (wave 2)

- **DG-060 · Panel first, full on Enter.** The sheets name the document "панель справа" (X-Ntf-OS,
  X-Dlg-Event) and draw it full in H2-Task / Q-Task. It opens as the panel, so the board or list
  it came from stays in sight (state-preservation); Enter or the expand icon makes it replace the
  whole content area, the Tasks header and the query row included, with the sheet's widths
  (780 px of text + a 300 px meta column; 760 + 280 quiet) and empty space after them. Esc goes
  back to the same task in the view. The bottom Готово takes the place of the panel's small
  head Готово when the panel is too narrow for the meta column.
- **DG-061 · The local layer keeps a place without showing at rest.** Progressive disclosure, and
  every extra stays one click from "+ свойство":
  - My checklist is the body's "План" (DG-062); hidden while it is empty, "+ свойство → План"
    starts it.
  - Связи show in the meta column only while a task has any, under "Упоминается в"; "+ свойство
    → Связь с задачей" adds one, the row's own "+ связать / ждёт / блокирует" shows on hover.
  - Сессии stay folded under Время ("2 сессии ›").
  - My tags are a chip like any property (shown when set, added from "+ свойство").
  - The comment draft (tracker cards only) sits in the body's tail under the plan, folded to one
    line until it is opened, as before.
  - "Удалить задачу" left the document; delete stays in the task menu (right-click) and on the
    card's Delete key, and Ctrl Z brings it back.
- **DG-061 · CI from what gh/glab already say.** The PR row shows the number and the rollup the
  git watcher already fetches ("passing / failing / pending" → CI ✓ / ✗ / ⏱ in bold, "CI прошёл /
  упал / идёт" in quiet). No PR known, no row. История is the task's own history log (APP-165), the
  three newest entries said shortly ("сегодня 14:58 · → В работе", "вчера · срок 9 окт",
  "2 окт · создана из Jira"); with no entries yet, the last column change.
- **DG-063 · "Сохранено" says the state, not an event.** It is shown at rest (the sheet draws it
  at rest), and reads "сохраняю…" while the typing has not been written yet.
- **DG-065 · Quiet Готово.** A small outline button right under История, no key (quiet hides
  keys); the timer is a text line plus a "пауза / запустить таймер" text link.
- **DG-080/082 · Bold chips are tinted by their signal.** Blocked and P0 on red, P1 on amber, as
  H2-Command draws "статус Заблокировано"; any other chip is the neutral outline. Quiet: outline
  only, values in lower case.
- **DG-081 · Only matches by name.** A doc, note or person whose only hit is a word in its body
  is not listed beside a query any more; the full text stays one Enter away in Knowledge search.
- **DG-082/083 · "?" toggle removed.** Bold always draws the "Один язык везде" card beside the line
  when it fits (it hides when the window is too narrow, and for anyone who hid it before);
  quiet never draws it and puts the language in its footer line. Bold offers "Открыть как доску
  g b" with the filter (the list is Ctrl ↵ in the footer); quiet offers "Открыть списком Ctrl ↵".
  Quiet group names follow the count: "Задача / С ней" for one, "Задачи / С ними" for more.
- **DG-130 · "Ещё и встреча" is a chip.** The sheet has no switch and no buttons. The meeting is
  offered as a chip among the parsed chips ("встреча нет"), only while the text has a time, and a
  click makes it "встреча в календаре" — the same language as the other chips, and nothing is
  ever put in the calendar without that click. Создать/Отмена are gone: Enter creates, Esc closes;
  Tab (open the task document) and Ctrl Shift Enter (create and keep open) still work and are
  listed in the cheat sheet. "в Example ▾" opens the profile list; picking one switches the app to
  it, and the task lands there.
- **DG-003 · ⤢ / ⤡** in the document are the `expand` / `collapse` line icons.

## Editor & people (0.8.1 r3)

- **R2-020 · Inline code pill.** Qt's rich text cannot stroke an inline span, so the paragraph
  draws the pill under the text (InlineCodeFrames finds the spans set in the bundled mono): a
  hairline in quiet, a fill in bold (H2-Knowledge fills, Q-Knowledge strokes — the same split as
  `Style.chipFill`). No-break spaces outside the span give it the sheet's padding.
- **R2-024 · "/" menu.** The six rows of the sheet. The "/" is typed as it is and a pick replaces
  it, so Esc leaves a literal "/" (this replaces "Просто /"). Heading and quote are gone from the
  menu; they are one keystroke in markdown (`## `, `> `). "Справочник (RFC, ссылка)" inserts a
  titled link `[](https://)` with the caret on the title — the editor has no other reference
  shape. "Картинка или файл" stores the files under attachments/ and links them where the "/" was.
- **R2-042 · "+ Добавить «…» как человека".** The row adds the person at once (name = the typed
  word, capitalised; id derived; state idle, so they do not enter "Кому написать") and mentions
  them — no dialog mid-sentence. Enter or Tab on an untouched list never takes that row; the
  arrows or a click do, so typing "@foo" and Enter in a form still submits.
- **R2-062 · Note menu.** As the sheet. "Слить с открытой" left the menu; merging stays on drag
  and drop (a row dropped on another). "Экспорт в .md" writes the same file a folder export writes
  for that note; attachment links stay relative to lowkey's attachments folder.
- **R2-063 · Person menu.** "Связанные задачи" opens the people dialog on the person (where
  DG-002 lists them); inside the dialog that row is not shown. "Удалить человека" is undoable.
- **R2-069 · Quick note.** Esc closes and keeps the text as the next open's draft (for the
  session), as the footer says; the discard confirmation is gone. "прикрепить к …" defaults to the
  task the git branch names; the list offers it and the tasks in progress, plus "Не прикреплять".
  An attached entry ends with `[[task-id]]`, so the task's backlinks list it.
- **R2-070 · Markdown folder import.** "Пункты «- [ ]» превращать в задачи" (on, as drawn) turns
  the open items of new notes into tasks in the default column, in the import's one undo step; a
  re-import makes none again. "Следить за папкой" is not drawn: lowkey has no folder watch, and a
  checkbox that does nothing would lie. "Другая папка" reopens the picker.
- **DG-151 · Profile delete.** "Удалить профиль…" opens the X-Dlg-Small confirmation with the
  sheet's typed-name field; the danger button unlocks only on the exact name. Ctrl Z still restores
  the profile afterwards, and the snapshot is taken as before.
