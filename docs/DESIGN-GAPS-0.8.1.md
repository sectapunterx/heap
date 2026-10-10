# Design gap inventory for 0.8.1

What lowkey 0.8.0 (`heap2/0.8.0` at `1c05591`) still does differently from its design references. This file only lists the gaps; nothing in it has been fixed yet.

- **App reference:** `Desktop\Code\New heap design`: `screens/*.dc.html`, `png/` (77 sheets) and `keymap.md`.
- **Site reference:** `Desktop\Code\heap-site-2`.
- **How the app was captured:** the real `Main.qml` ran offscreen through a scratch QuickTest harness, in an isolated test profile with the Example profile seeded. Window 1440×900 (plus 1280×720), RU UI (EN spot check), both styles (`Style.apply("bold" | "quiet")`), dark theme (plus a light check).
- **Severity:**
  - **S**: wrong structure, or a legacy component visible.
  - **A**: clearly off from the sheet.
  - **B**: a detail.
- **Capture limits:**
  - Modal scrims are not reproduced in the captures, so dimming is not judged.
  - The date is the real one, 9 Oct 2026 (Fri), while the sheets show Thu 8 Oct. Differences that come only from the example data (which tasks happen to be in progress, dates) are not counted.

## Summary

| Severity | Count |
|---|---|
| S | 10 |
| A | 49 |
| B | 27 |
| **Total (app)** | **86** |
| Site (SG-*) | 0 S, 3 A, 12 B |

### Top 15

1. **DG-002 (S)** The legacy right panel (MiniWeek, day calendar and the "Кому написать" contacts list with coloured avatars) is still on screen at 1440 px in Knowledge, Archive and Timeline, and on Board/List after Ctrl \.
2. **DG-070 (S)** Knowledge opens the legacy Docs catalogue ("Доки · спеки и справочники", Страницы/Справочник, coloured sections, Контакты) behind the tabs Заметки/Ссылки. The sheet has one list pane, a document and a backlinks column.
3. **DG-001 (S)** A full-width example banner ("Пример … Убрать пример") sits above every screen. No sheet has it.
4. **DG-120 (S)** The event editor is the legacy modal form. The sheet has a right panel that saves on its own, the same as the task document.
5. **DG-092 (S)** Settings → Задачи и процесс has no columns table (stage, WIP, count, ⋯, + Колонка). Legacy sliders and toggles stand in its place.
6. **DG-093 (S)** Settings → Трекеры is the legacy long page: explainer, warning, health, ICS form, auto-sync. It should be the tracker list with a detail pane and the status mapping.
7. **DG-040 (S)** In the calendar (week, month, day), an extra toolbar row with "В архиве" sits above the grid.
8. **DG-161 / DG-162 (S)** The legacy Archive view and the legacy "Лента · по дедлайнам" view still exist as their own screens.
9. **DG-131 (S)** The legacy welcome tour popup ("Первая задача", step dots). The sheets replace the tour with empty states and the first-run hero.
10. **DG-004 (A)** The quiet style is mostly the bold layout with counters and key hints hidden. Settings, task document, palette, calendar events, query bar, first run and the Today cards are not drawn the quiet way.
11. **DG-020 (A)** The query bar is a plain search field: no committed chips, no "добавить условие…", no "Сохранить как вид". The default "не готово" filter is not applied, so the List shows done tasks.
12. **DG-060 / DG-061 (A)** The full task document:
    - It sits below the Tasks header instead of replacing it.
    - The meta column has no PR/CI, tracker, history or timer readout.
13. **DG-012 (A)** Quiet Today is drawn as the card timeline instead of plain rows with icons. The calm right column is not quiet either.
14. **DG-050 / DG-051 (A)** Month cells are separate cards and the day view is the legacy layout. The sheets draw a flat hairline grid and compact rows.
15. **DG-080 / DG-083 (A)**
    - The command line does not turn what you type into chips, and a status + priority query finds no task.
    - The quiet palette is identical to the bold one.

### Owner-decided deviations (not counted)

- The sort chip next to the lens tabs.
- Bold cards show one rest line (PR, checklist or excerpt).
- P2/P3 show on detailed cards.
- The weekly recap link on Today on the last workday.
- Ctrl F is the section filter.
- The sheet `Fix-Hotkeys` is outdated (pre-Vim, Ctrl 1–7); `X-Keys` and `keymap.md` replace it.
- The "h." logo on `X-Oth-Small` is outdated.
- N-* sheets are the bold renders of X-*. They were compared through the bold captures of the same states.

### Not captured (still to verify by hand)

- Storage and tracker error banners and cards.
- OS notifications.
- The sync indicator and its popover.
- Splash and crash screens.
- The update line and "What's new".
- The global capture window (Ctrl Shift Space) and the quick note.
- Drag-and-drop states.
- The sync conflict dialog and the tracker push confirm.
- Small dialogs: link, delete column, delete profile, remove example.
- Knowledge embeds and the slash menu.
- The note and person context menus (the right-click did not open them in the harness).
- The calendar task-block menu.

---

## Global (cross-cutting)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| DG-001 | S | No banner. Example is only the profile name in the sidebar. | A 36 px bar "Пример … [Убрать пример]" across the top of every view. It pushes the headers down. | `qml/Main.qml` (example-banner) |
| DG-002 | S | No right panel anywhere. People live in "Кому написать" on Today and in their own dialog. | A legacy right panel: MiniWeek, DayCalendar and PeopleList with coloured avatars and Написать/Написал buttons. Shown in Knowledge (both tabs), Archive and Timeline at 1440 px, and on Board/List after Ctrl \. | `qml/Main.qml` (rightPanel), `MiniWeek.qml`, `DayCalendar.qml`, `PeopleList.qml` |
| DG-003 | A | One line icon set: status rings, calendar glyph, flag ⚑, chevrons. | Text and emoji glyphs instead of icons, in many places (listed below this table). | `TopBar.qml`, `QueryBar.qml`, `SettingsView.qml`, `TaskCard.qml`, `WeekView.qml`, `MonthView.qml`, `TaskDocument.qml`, `Toast.qml`, `WelcomePopup.qml`, `EventEditor.qml`, sample data (`src/…/SampleData`) |
| DG-004 | A | Quiet = no fills, outline chips, lowercase text options, text links, no side cards. | Quiet differs from bold only by counters and key hints. These screens are identical in both styles: Settings (DG-090), task document (DG-065), palette (DG-083), calendar events (DG-044), query bar (DG-021), first run (DG-111), Today cards (DG-012). | `Style.qml` and its consumers |
| DG-005 | A | Selected segment: neutral fill (bold) or outline pill (quiet). Primary buttons are outlined, not filled. | Selected segments, switches and primary buttons are filled lavender everywhere: Settings, Создать, Сохранить, Закрыть, Готово, Копировать. | `Theme.qml` tokens, `PillButton.qml`, `DialogFooter.qml`, `SettingsView.qml` segment control |
| DG-006 | B | The active section is bold with the underline bar. Bold has 4 starter views with counts. Quiet has no profile dot. | The active section is regular weight. There are 5 views ("Срок на этой неделе", "Просрочено" with no count). The coloured dot shows in quiet too. | `Sidebar.qml`, starter views (`src/savedviews`) |
| DG-007 | B | Profiles are named "Example" and "Личное". Starter views are in the UI language. | "Пример" and "Personal". In a profile made before a language switch the starter views stay English (Blocked, In review, Urgent, Due this week, Overdue) in the RU UI. | `AppController.cpp` (`buildExampleProfile`, default profile), `savedviews::starterViews` |
| DG-008 | A | 1280×720: the sidebar folds to the icon rail and the Today right column moves under the day as 3 columns (`X-Oth-Small`). | At 1280×720 the full sidebar stays and the right column stays beside the day. The fold threshold is 1100 px. | `Main.qml` (`_sideRailMinWidth`), `TodayView.qml` |

Glyphs used instead of icons (DG-003):

- Two "⌕" glyphs (rendered like "ρ ρ") in the Tasks query field; "⌕" in the Settings search and the palette.
- "⤢" / "⤡" for full mode in the task document.
- 🔒 in the Фокус-блок line.
- "▫" squares and "▲" / "◆" priority marks on calendar chips.
- "⎇" on cards.
- "↓" / "↑" on the Data buttons.
- ⓘ in toasts.
- ⚡ in the welcome tour.
- 📅 in the event editor.
- 📎 and "▫ Ссылки" in the notes toolbar.

## A · Today: H2-Today (bold) / H2-Today-Calm (quiet) → view `today`

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| DG-010 | A | One facts line: "2 встречи · 2 задачи в плане · 1 срок истекает сегодня". | A second "load" line, "встречи 2 ч 15 мин · свободно 7 ч 45 мин", in both styles. The planned-tasks fact is missing when there are none. | `TodayView.qml` |
| DG-011 | B | ‹ › at the far right edge (bold). Bare chevrons in quiet. | Boxed ‹ › buttons at the end of the left column (x≈870), in both styles. Also shown on the empty first-run day. | `TodayView.qml` |
| DG-012 | A | Quiet: no eyebrow, no cards, no "День" heading, no free gaps. Rows: mono time, calendar icon or status ring, title, muted "встреча · 30 мин · Zoom". A thin grey now-line with the time at the right. | Quiet uses the bold timeline: the eyebrow "Сегодня", "День", bordered meeting cards with a left bar, "Свободно …" rows and "Конец рабочего дня". | `TodayView.qml` |
| DG-013 | A | Quiet right column: a small "В работе" row with the timer, "Срок сегодня" only, and "▸ Кому написать · 2". | Outlined "Сейчас в работе" cards, the full "Сроки" list, plus the links "3 задачи без даты →" and "Сводка недели →". | `TodayView.qml` |
| DG-014 | B | Bold "Сейчас в работе": one card with "PR #482 · CI ✓" and an orange timer dot 0:42. | One card per in-progress task, showing "⎇ branch" instead of PR/CI. No timer readout. | `TodayView.qml` |
| DG-015 | B | Button "Написал". A footer row with a divider and a right-aligned →. | "Написано". The footer is two small inline links with no divider. | `TodayView.qml`, `I18n.qml` |

## B · Tasks Board: H2-Board / Q-Board → `tasks` + board lens

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| DG-020 | A | Query bar: a funnel icon, committed chips "статус не готово ×" and "профиль Example ×", the placeholder "добавить условие: p1, @неделя, #метка…" and "Сохранить как вид" at the right. "не готово" is the default. | A plain field "Поиск задач, ID, веток…" with Ctrl F and no chips. "Сохранить как вид" appears only while typing. No default "не готово" filter, so done tasks show (see DG-030). | `TopBar.qml`, `QueryBar.qml`, `PropertyChip.qml` |
| DG-021 | A | Quiet: a row of outline chips "не готово", "Example" and the link "изменить фильтр". No box. | The same boxed search field as bold. | `TopBar.qml`, `QueryBar.qml` |
| DG-022 | A | Folded Done: "Готово 2" + "Показать" (bold), "Готово · 2" (quiet). No add-column control. | Quiet header truncated to "Готов…". Both styles have an extra "+" add-column button at the far right. | `KanbanBoard.qml` |
| DG-023 | B | Cards: key + date, P0/P1 right. No branch. | A "⎇" branch glyph on most cards, with no text. | `TaskCard.qml` |
| DG-024 | B | Bold column names are bold. | Regular weight. | `KanbanBoard.qml` |
| DG-025 | A | Column menu (`X-Menus-Column`): the header "Колонка «В работе» · 2 задачи", Новая задача в колонке `o`, Переименовать `F2`, Этап колонки › (with rings), Свернуть `z a`, WIP-лимит…, the two Сдвинуть items and Удалить колонку… | No header and no keys for o/F2/z a. "Добавить задачу". Legacy items "Сменить цвет…", "Лимит незавершённого…", "Автоархив…", "Бронировать фокус-время при входе". No "Этап колонки" submenu. | `KanbanBoard.qml` (colHeaderMenu) |
| DG-026 | A | Multi-select bar: "3 выбрано · Готово d · Запланировать s · Приоритет 1–4 · Переместить Shift H / L · В архив e · Удалить Del · Снять Esc". A selected card has a check in its ring and a fill. | "Выделено: 2 · Переместить… · Приоритет · Перенести… · Метка · Архивировать · Удалить (red, filled) · Снять". No keys, no Готово or Запланировать. A ✓ badge in the card's corner marks selection. | `SelectionBar.qml`, `TaskCard.qml` |
| DG-027 | B | Task menu: a proportional header, ⏎ for Open, "Создать ветку git". No "Перенести". | Mono header, "Enter" as text, an extra "Перенести… ›", "Создать ветку". The priority submenu adds a ✓. | `TaskMenuHost.qml`, `AppMenuItem.qml` |

## C · Tasks List: H2-List / Q-List → list lens

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| DG-030 | A | Only open tasks (filter "не готово"). | A "Раньше" group with done tasks (APP-111, APP-112). | `TaskListView.qml`, filter default (`TopBar.qml`) |
| DG-031 | B | A label pill (payments/auth/ui) before the priority. Dates "9 окт". | No label pills. Dates "сб, 10 окт." with a trailing dot. | `TaskListView.qml`, `I18n` date pattern |
| DG-032 | B | Quiet rows are ~900 px wide, with key/P/date close to the title. | Rows stretch across the whole width (1416 px). | `TaskListView.qml` |

## D · Tasks Calendar: H2-Calendar / Q-Calendar → week lens

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| DG-040 | S | The grid starts right under the header. | A legacy toolbar row with only "▤ В архиве" above the grid. Also in month and day. | `WeekView.qml`, `MonthView.qml`, `CalendarView.qml` |
| DG-041 | A | Day header: "пн 5". A deadline row of orange ⚑ titles. | A load bar per day, "2 ч 15 мин из 10 ч" / "30 мин", and chips with "▫" plus "▲" / "◆" priority glyphs. | `WeekView.qml` |
| DG-042 | A | A compact header, 09 visible. | A ~120 px header. The 09:00 label is clipped under it. | `WeekView.qml` |
| DG-043 | B | Bold today column: orange top line. Hours "10". | A lavender top line. Hours "10:00". | `WeekView.qml`, `Theme.qml` (`signalNow`) |
| DG-044 | A | Quiet: events with a calendar icon and no bar or fill. "‹ 5 – 11 октября ›" under the title. Lowercase "день · неделя · месяц" at the right. | Events with blue bars and fill, as in bold. Day/Week/Month inline after the tabs. Boxed ‹ › at the right. | `WeekView.qml`, `CalendarNav.qml`, `TopBar.qml` |
| DG-045 | A | Context menus on a meeting (Открыть, Подключиться к звонку, Перенести, Длительность, Дублировать, Связать с задачей, Удалить вхождение/серию) and on an empty slot (Новая встреча здесь Ctrl Alt E, Новая задача на это время, Поставить из «Без даты», Перейти к этому дню). | Right-click handlers exist only for task chips and task blocks. Meetings and empty slots have no menu. | `WeekView.qml`, `DayCalendar.qml` |
| DG-046 | B | No count. Hint "…нажмите s". | "15 задач" next to the date. "нажмите S". | `TopBar.qml`, `UnscheduledRail.qml` |

## X/N-Oth-DayMonth → day and month lenses

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| DG-050 | A | Month: a flat hairline grid, 5 rows, items with calendar icon / ring / flag, "+2 ещё", today tinted. | Each day is a separate rounded card with gaps. 6 rows, with trailing next-month days. Items use "▲ / ◆ / ▫" glyphs and dots. | `MonthView.qml` |
| DG-051 | A | Day: the inline header "пт, 9 октября · 2 встречи · 1 задача · срок: …". Rows with an icon, the title and the time range at the right. | A large header with a load bar and a deadline chip. Events are full-width blue-bar blocks. | `WeekView.qml` (day mode), `DayCalendar.qml` |

## E · Task document: H2-Task / Q-Task → `win.showTask`

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| DG-060 | A | The document replaces the content area, with the breadcrumb "Задачи / В работе / APP-101" at the top. | Full mode (⤢) renders below the Tasks title, lens tabs, sort chip and search field. The default is a half-width panel over the board. | `TaskDocument.qml`, `Main.qml` |
| DG-061 | A | Meta column: Код (Ветка, PR #482 CI ✓, Трекер Jira APP-101 ↗), Упоминается в, Время (0:42, "Пауза t", "всего 3 ч 10 мин из оценки 4 ч"), История. | Only Ветка under Код. An extra "Связи + связать + ждёт + блокирует". Время is just a "Запустить таймер" button. No История. | `TaskDocument.qml`, `TaskSessions.qml`, `TaskRelations.qml` |
| DG-062 | A | The checklist inline under "План" in the body, and the hint "Пишите прямо здесь. / — вставить чек-лист, код, ссылку на задачу." | "План" pinned to the bottom as a separate input ("Добавить шаг: Enter…", "текстом"). Extra "Удалить задачу" link. No slash hint. | `TaskDocument.qml`, `TaskLocalChecklist.qml`, `MdBlockEditor.qml` |
| DG-063 | B | "Сохранено · Esc назад". Bottom button "Готово d". | No saved indicator. "Готово" with no key. The panel mode has a small "Готово" at the top. | `TaskDocument.qml` |
| DG-064 | A | — | The task panel stays open over Settings after switching sections (seen at `view=settings`). | `Main.qml`, `TaskDocument.qml` |
| DG-065 | A | Quiet: outline lowercase chips and a small outline "Готово" under История. | Quiet = bold: a full-width filled lavender Готово. | `TaskDocument.qml` |

## F · Knowledge: H2-Knowledge / Q-Knowledge (+ X-Oth-Knowledge) → `knowledge`

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| DG-070 | S | No tabs. A list pane (Знания +, search, Закреплено with RFC/API tags, Заметки, Сниппеты), the note document, and a right column of backlinks. | Lens tabs "Заметки / Ссылки". Ссылки (the default) is the legacy DocsView: "Доки · спеки и справочники", Страницы/Справочник segments, sections with coloured bars, reference cards, "Контакты", "+ Новая секция". | `DocsView.qml`, `DocsPagesPane.qml`, `TopBar.qml` (`LensTabs`) |
| DG-071 | A | Above the title: "Заметка · изменена 5 мин назад". No toolbar. | An editor header "С чего начать · 12 строк 0 @упоминаний 0 #тикетов" and toolbar buttons 📎, ≡, "▫ Ссылки", "Исходник". | `NotesView.qml`, `MdEditorPane.qml` |
| DG-072 | A | Right column: "Задачи в заметке", "Ссылаются сюда", "Внешние ссылки". | Missing. The legacy right panel takes its place (DG-002). | `NotesView.qml` |
| DG-073 | A | Закреплено holds 3 items, then Заметки and Сниппеты. | Закреплено lists the whole reference catalogue (~30 docs) and pushes Заметки below the fold. No Сниппеты group. | `NotesListPane.qml` |
| DG-074 | B | — | The starter note mentions UI that no longer exists ("Перетащить задачу в календарь справа", "«Начать с чистого листа» на баннере"). | sample notes in `src` (`SampleData`) |

## G · Command line: H2-Command / Q-Command → `palette.open`

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| DG-080 | A | Typed clauses become chips (статус Заблокировано, приоритет P0). The result offers "Задачи · 1" and "С найденным" (Отметить готовой, Снять блокировку → В работу). | "статус:заблок p0 оформ" stays raw text. Only "С этим фильтром" rows; no task found. | `CommandPalette.qml`, `PaletteMatch.js` |
| DG-081 | A | Only matching results. | For "оформ": 7 unrelated docs under "Заметки, доки, люди". | `CommandPalette.qml`, `PaletteMatch.js` |
| DG-082 | B | 700 px palette at y≈100 and a separate "Один язык везде" card. A "›" prompt. Footer with key glyphs (⏎, Tab, Ctrl ⏎). Task row ends with date + ⏎. | Inside the main column at y≈190, with the side card fused into the palette. "⌕" icon, a "?" button, a plain-text footer. The task row ends with status + "Enter". | `CommandPalette.qml` |
| DG-083 | A | Quiet: centred 620 px, no side card, groups "Задача" / "С ней", the footer line "p1 · завтра · до пт · #метка · > только команды". | Identical to bold. | `CommandPalette.qml` |

## H · Settings: H2-Settings / Q-Settings / X·N-Set-* → `settings` sections

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| DG-090 | A | Flat rows separated by hairlines. Quiet uses lowercase text options with an outline pill. | Rows grouped into bordered cards with sub-headings. Segmented controls are filled lavender. The same in both styles. | `SettingsView.qml`, `SettingsGroup.qml`, `SettingsRow.qml` |
| DG-091 | B | Bold sheet: 6 sections. X sheets: 11, plus Помощь. | 13, including "Профиль" (in no sheet), "Помощь" and "Слежение за Git". A version footer in the nav. | `SettingsIndex.js` |
| DG-092 | S | Задачи и процесс: a columns table (handle, ring, name, Этап dropdown, WIP, count, ⋯), "+ Колонка", Префикс TASK, "Новая задача попадает в", "Готово — архивировать через 14 дней". | No columns table. Prefix + "Переименовать существующие задачи", segments "Дефолтный приоритет/колонка", sliders "Архивировать «Готово» через" and "Подсвечивать заблокированные после", "Требовать ветку перед ревью". | `SettingsView.qml` (sectionTasks) |
| DG-093 | S | Трекеры: on the left, the tracker list with state (чтение / вход истёк) and 3 sign-in state cards. On the right, the detail: JQL, Как часто, Запись выключено, Спрашивать перед отправкой, Тикеты вне фильтра, and the "Статусы Jira → колонки" mapping. | A legacy single page: the "Как работают интеграции" explainer, an orange secrets.json warning, "Здоровье интеграций", the ICS form, "Авто-синк" with "Каждые 0 мин/ч/дн", then "Трекеры и сервисы". | `SettingsView.qml` (sectionIntegrations), `IntegrationsInfoCard.qml`, `IntegrationHealthCard.qml`, `AutoSyncCard.qml`, `CalendarSubscriptionsCard.qml` |
| DG-094 | A | Календарь: ICS subscriptions, working-day chips, the hours pill "10:00 – 19:00", Неделя пн/вс. | Titled "Рабочий день". Hours are sliders. ICS sits under Трекеры. Extra Формат времени, Показывать выходные, Сетка слотов, Фокус-время. | `SettingsView.qml` (sectionCalendar) |
| DG-095 | A | Уведомления as segments: Встречи (за 15 мин / за 5 мин / в начале / выкл), Сроки в 9:00, Начало задачи, Звук, Тихие часы. | Toggles and sliders (hours before a deadline, minutes before a meeting, Кнопки «Отложить», Отложить надолго, Напоминание о дейли), "Каналы доставки" with a test button, two digest toggles. No Тихие часы. | `SettingsView.qml` (sectionNotifications) |
| DG-096 | A | Подстраховка: Снимки (каждый день / каждый час), Хранить 7/14/30, Снимок перед импортом, Удалённые задачи, Режим погружения. | Конец дня, Жду ответа, Уже встречалось, Погружение, Стендап. Snapshot retention lives inside the Time Machine dialog instead. | `SettingsView.qml` (sectionSafety), `TimeMachineDialog.qml` |
| DG-097 | A | Клавиши: a search field and rows with key caps, rebinding in place ("нажмите…", a conflict box, "изменено · вернуть g x"). | A read-only list with a button to a separate panel. Duplicate rows per binding (Командная строка ×2, Перейти в «Сегодня» ×2, Знания ×2). | `SettingsView.qml` (sectionShortcuts), `HotkeysPanel.qml` |
| DG-098 | A | Стиль: Тихий / Насыщенный / **Свой**, and "вернуть «Насыщенный»". | Only Тихий / Насыщенный. | `SettingsView.qml`, `Style.qml` |
| DG-099 | B | Git: Папки, Связывать ветку да/нет, Показывать PR и CI, Строка «работаю над…». | A path input and automations (В работу, фокус-блок, PR status, чей ход). | `SettingsView.qml` (sectionGit) |
| DG-100 | B | Язык: Русский/English, Формат даты, Разбор дат. | Only the language, ordered English \| Русский. | `SettingsView.qml` (sectionLanguage) |
| DG-101 | A | — (no profile card in the design). | A legacy "Профиль" section: avatar, Полное имя, Ник, Роль, Команда, avatar colour. | `SettingsView.qml` (sectionProfile) |
| DG-102 | A | Помощь: rows Все клавиши / С чего начать / Сообщить о проблеме. | The legacy long "Справка lowkey" article ("лента", "панель дня", "документация"). | `HelpContent.qml` |
| DG-103 | B | О программе: Обновления (проверять сами / вручную), Канал stable/beta, Что нового, Лицензии. Данные: Резервные копии + Экспорт. | Logo and tagline card, Хранилище/Движок rows, no "Что нового" or "Лицензии", a developer note mentioning "AppDataLocation". Данные adds "Неиспользуемые вложения", "Опасная зона" and ↓/↑ glyph buttons. | `SettingsView.qml` (sectionAbout, sectionData) |

## I · First run: H2-First / Q-First → empty profile, welcome not seen

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| DG-110 | B | Key cards Ctrl K / d / ?. The input has an emphasized border. No day nav. Sidebar: "Мои виды — Появятся, когда сохраните фильтр". | The third card reads "Ctrl /" and is shorter, so it sits out of line with the other two. The input border is muted. ‹ › are shown. 5 starter views (English, see DG-007). | `FirstRunHero.qml`, `TodayView.qml`, `Sidebar.qml` |
| DG-111 | A | Quiet: an underline input, two hint lines, the links "подключить трекер · импорт Markdown · открыть пример", the sub "пока пусто". | Identical to bold. | `FirstRunHero.qml` |

## Menus: X/N-Menus-Task, -Column, -Other

Task and column menus are covered by DG-025, DG-027 and DG-045.

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| DG-150 | A | Saved view menu: the header "Вид «Заблокировано»", Открыть `g 1`, Изменить запрос…, Переименовать `F2`, Выше `Shift K`, Ниже `Shift J`, Удалить вид. | No header. Применить, "Обновить по текущим фильтрам", Дублировать. Keys "Ctrl+↑/↓" written inline after the text, not right-aligned. | `Sidebar.qml` (savedMenu) |
| DG-151 | A | Profile switcher: a "Найти профиль" field, profiles with sync time and `Ctrl ]`, Новый профиль `Ctrl Shift P`, Переименовать текущий…, Удалить профиль…. | The legacy menu: Дублировать активный, import/export JSON, .ics and notes folder. No search, no status, no keys. | `ProfileSwitcher.qml` |
| DG-152 | B | Text field menu: the header "Описание задачи", keys right (Ctrl Z …), "Ссылка на задачу… [[". | No header, no keys, no task link. Has "Удалить". | `TextEditMenu.qml` |

## Dialogs: X/N-Dlg-*

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| DG-120 | S | Встреча (`X-Dlg-Event`): the right panel, same as the task document, saving on its own. Rows Когда / Повтор / Участники / Звонок / Напоминание / Задача / Профиль, an agenda field, "Удалить…" and "изменения сохраняются сами". A new event comes from the one-line input with chips. | The legacy modal "Событие в календаре": Название, Тип, Участники, Весь день, Начало/Конец, Дата/По with 📅, Повтор, Место, Ссылка, Контекст, Напоминание, Заметки, [Удалить] [Отмена] [Сохранить]. The same form for event.new. | `EventEditor.qml` |
| DG-121 | A | Машина времени: snapshots grouped with kind and count ("18:40 · перед закрытием · 14 задач"). Detail is a diff table (Задачи / Изменения / Заметки / Встречи / Настройки). Buttons: Открыть копией в новом профиле, Показать файл, Восстановить эту версию…. | The list has no kind or counts. The detail lists per-profile "Восстановить копией" and a long per-task list of "Вернуть эту версию". Retention controls (7/30/90 дн., 100/200/500 МБ) are inside the dialog. Buttons Восстановить всё / Закрыть (primary). | `TimeMachineDialog.qml` |
| DG-122 | A | Журнал: filter tabs всё / ошибки / синк / напоминания. Rows: time · source · text · action link (открыть / решить / отменить / войти). | A plain list of time + dot + text. No tabs, no source, no actions. | `EventLogDialog.qml` |
| DG-123 | A | Сводка недели: the current week, per-day bars, the closed list, "Копировать Markdown" and "Следующая неделя →". | Shows the previous week. The empty state is only text + Закрыть. | `WeeklyRecapDialog.qml` |
| DG-124 | B | "Итог дня · чт, 8 окт", the facts line "Закрыто 2 · в таймере 4 ч 10 мин · переходит 2", then carry-over chips. | Titled "Конец дня". No facts line. An extra "Закрыто сегодня" list. | `EndOfDayDialog.qml` |
| DG-125 | B | Стендап: proportional text, [Копировать] [Закрыть]. | Mono text, an extra "Собрать заново", a filled primary button. | `StandupDraftDialog.qml` |
| DG-126 | A | Человек: a small dialog with Имя and Что спросить. | `person.new` opens the legacy contacts picker "Кто нужен?": coloured avatars, roles, @handles, #channels, an on-call "Дежурный". | `PersonPicker.qml`, `PersonEditor.qml` |
| DG-127 | B | Сохранить как вид: the line "Появится в «Моих видах», клавиша Alt 4.", fields Название and Запрос (mono). | Only a name field and a summary line. | `SavedViewNameDialog.qml` |
| DG-128 | B | Новый профиль: the line "Свои задачи, колонки и виды; встречи общие.", 8 swatches, an outline primary button. | No description line, 10 swatches, filled lavender primary. | `ProfileEditor.qml` |
| DG-129 | B | Запланировать / Срок: a proportional input, the parsed result line, hints. | A mono input with the examples as placeholder. Otherwise close. | `SchedulePopup.qml` |
| DG-130 | B | Quick capture: hints only ("⏎ создать · Shift ⏎ строка · Esc закрыть"), "в Example ▾". | Extra [Отмена] [Создать] buttons, an "Ещё и встреча в календаре" switch, a long hint line, "в Пример" with no ▾. | `QuickCapturePopup.qml` |
| DG-131 | S | No tour. Empty states and the first-run hero teach instead (`X-Err-Empty`). | The legacy tour popup "Первая задача": ⚡ icon, step dots, Пропустить / Далее (welcome.replay, first launch). | `WelcomePopup.qml`, `Tour.js` |
| DG-132 | A | Погружение (`X-Ntf-Focus`): full screen with one task (ring, key, title, checklist), timer ⏸ T, "следующая встреча через …" and Готово D. | Ctrl Shift F only shows a header pill "● Погружение 0:01". On leaving, the toast "Отложено уведомлений: 0". | `Main.qml` (`toggleImmersion`) |
| DG-133 | A | Шпаргалка (`X-Keys`): every group fits, plus "Изменилось в 0.8.0" and the footer line. | At 900 px the "Вид" and "Поиск" groups are cut after one row and "Изменилось в 0.8.0" is not visible. Extra rows "(не задан)" for the legacy views (архив, доки, заметки). | `KeyCheatSheet.qml` |

## Notifications: X/N-Ntf-Toasts

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| DG-140 | A | One toast at a time, bottom centre: ring icon, text, underlined action, key hint ("Готово: APP-112 Отменить Ctrl Z"). | One "done" action shows two stacked toasts ("APP-113 → Готово" and "Готово: APP-113"). They sit bottom-right on the board, with an ⓘ icon, an outlined "Отменить" button and no key. | `Toast.qml`, `ToastTiming.js`, `AppController` (toggleDone toasts) |

## Empty states and other screens: X/N-Err-Empty, X/N-Oth-Archive-People

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| DG-160 | A | A filter with no result: one plain line "Ничего под «…»" and "сбросить фильтр · Esc". | A bordered card "По поиску ничего не найдено / Сбросьте поиск…" floating over the board, plus a second line "Ничего не подходит — сбросить запрос" under the field. | `EmptyState.qml`, `KanbanBoard.qml`, `TopBar.qml` |
| DG-161 | S | Archive is not its own section. It is Tasks · List with the chips "статус в архиве ×" and "группа по месяцу", grouped by month, "вернуть U". | A separate legacy ArchiveView ("Архив · 0 архивных тикетов", box icon) with the legacy right panel. | `ArchiveView.qml`, `Main.qml` |
| DG-162 | S | — (no Timeline in the design; List replaces it). | The legacy "Лента · по дедлайнам" (TimelineView) is still reachable: coloured round group badges, "Показывать сделанные", the "В архиве" bar, the right panel. | `TimelineView.qml`, `Main.qml`, `ViewNames.h` |

**Light theme (`X-Oth-Light`):** same structure gaps as quiet Today (DG-012 / DG-013). The palette looked right, but the capture method distorts light text, so it is not graded.

---

## Site: shipped `site/` vs `heap-site-2`

The site matches the prototype closely:

- The first 355 lines of the stylesheet are identical to the prototype's whole stylesheet.
- App screens, wordmark, animations and fonts are identical. The prototype's `@fontsource/unbounded` is never imported, so nothing is missing.
- The differences are in content.

| id | sev | page / section | prototype | shipped | files |
|---|---|---|---|---|---|
| SG-01 | A | Home: get | A "With Scoop" block with Copy | Removed. Scoop only appears on /download/ while the bucket matches the latest tag, so it shows nowhere in the current build. | `site/src/components/Landing.astro`, `site/src/data/i18n.ts`, `site/src/lib/scoop.ts` |
| SG-02 | A | Home: get, /download/ | Static sizes | The build pulls v0.7.2 release data: "Version 0.7.2", `heap-v0.7.2-*` files. Wrong if the site deploys before v0.8.0 is published. | `site/src/lib/github.ts`, `site/src/lib/releases.ts`, `site/src/data/releases.fallback.json`, `.github/workflows/pages.yml` |
| SG-03 | A | Home: keyboard "Done" card | "Close the task under the cursor" | Describes only the reverse ("On a done task, brings it back…"). Same in RU. | `site/src/data/i18n.ts` |
| SG-04 | B | git: task card | Branch row with accent underline | Replaced by "PR #57 · in review", which also appears in the top bar. | `Landing.astro`, `i18n.ts` |
| SG-05 | B | git: top bar | — | The PR text is not right-aligned (`.gbar-on` needs `flex:1`). | `site/src/styles/site.css` |
| SG-06 | B | git: wording | One state label | "Working on" / "in progress" / "In Progress" in one scene. | `i18n.ts` |
| SG-07 | B | git: lede | Promise of no setup | A setup manual tone, one line longer. | `i18n.ts` |
| SG-08 | B | your data: cards | Even 2–5 line cards | Uneven (7 lines next to 2). | `i18n.ts` |
| SG-09 | B | your data: columns | Columns end level | The left column ends ~320 px lower, leaving an empty block on the right. | `Landing.astro`, `site.css`, `i18n.ts` |
| SG-10 | B | FAQ / network list | Active voice | Passive voice, flatter. | `i18n.ts` |
| SG-11 | B | keyboard, 390 px | 6 cards | 9 cards in one column, +752 px. | `site.css` (`.keygrid`) |
| SG-12 | B | keyboard | One key per cap | A "Ctrl 1–3" range cap. | `Landing.astro` |
| SG-13 | B | keyboard note | None | A note mixing app keys and site keys. | `i18n.ts` |
| SG-14 | B | /download/, 390 px | — | The from-source command wraps inside a flag (`build -` / `DCMAKE…`). | `site.css` |
| SG-15 | B | /404 | — | Bilingual on one page, inline styles. | `site/src/pages/404.astro`, `site.css` |

### Accepted copy additions (not counted)

- **Git:** the top bar "Working on APP-112 · PR #57 · in review", the "in progress" card meta, the note about Settings → Git, `git switch`, the factual parts of the lede.
- **Keys:** three extra cards (Sections Ctrl 1–3, y y, ?), "Go to" with g l, the physical-key wording.
- **Your data:** paragraphs on backups, moving from heap 0.7 (MOVED-TO-LOWKEY.txt), tokens, Obsidian; the local-layer note; the schema-12 example; offline wording including the update check; tracker and backup facts; network items (checksum, timer, .ics, PR state, pictures, Mattermost); the sign-in line.
- **FAQ:** the item "I use heap 0.7…", plus the multi-machine, team, Obsidian and offline answers.
- **Demo and day:** `p1` in the placeholder; the 17:30 note-link moment.
- **Get:** the live release file list and the "All ways to install" link.
- **Pages:** the whole /download/ page and the 404 page.
- **Header, footer and head:** the Download nav and footer links, MIT, canonical and og meta, redirects for old heap paths.
