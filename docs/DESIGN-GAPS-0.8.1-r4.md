# Design gaps 0.8.1 — re-inventory r4

Branch `heap2/0.8.1` at fa0e541. Fresh, independent pass: every sheet in `New heap design/screens` (H2-/N- bold, Q-/X- quiet; PNG + .dc.html copy) compared side by side with offscreen captures of the real `Main.qml` (QuickTest harness, isolated profiles, seeded working day with meetings and planned tasks, calendars at 09:00; 1440×900, 1280×720 for X-Oth-Small, light theme for X-Oth-Light; menus, dialogs, toasts, empty/error states, first run, sync/trackers). Site: `heap-site-2` prototype vs built `site/`. Earlier reports (`DESIGN-GAPS-0.8.1*.md`) were context only.

Not gaps (accepted): `docs/DESIGN-DECISIONS.md`, KEEP rows of `docs/DESIGN-DECISIONS-REVIEW.md`, owner decisions (one detail line on bold cards, sort chip, recap line on Today, lavender accent, "только здесь", Ctrl F = filter, tone, bold is the default style, git "working on" line on by default). Fix-Hotkeys and the "h." mark in X-Oth-Small are outdated sheets. Harness artifacts (no modal scrim offscreen, context menus drawn at (0,0), unopened menus) are not counted; such states are judged from code and marked "(code)".

Severity: **S** wrong structure / legacy component / broken · **A** clearly off from the sheet · **B** visible detail · **C** minor · **D** cosmetic nit.

Captures: `C:/Users/Fin/AppData/Local/Temp/claude/C--Users-Fin-CLionProjects-todolist/94cfdb4b-65f9-46d8-b85c-958b3a86d2cd/scratchpad/r5/app` (`bold-*` / `quiet-*` / `t-*` tracker seed); site: `C:/Users/Fin/AppData/Local/Temp/claude/C--Users-Fin-CLionProjects-todolist/94cfdb4b-65f9-46d8-b85c-958b3a86d2cd/scratchpad/r5/site`.

## Summary

| area | S | A | B | C | D |
|---|---|---|---|---|---|
| Today, notifications, system | 0 | 1 | 8 | 7 | 4 |
| Tasks, menus, drag | 0 | 0 | 4 | 16 | 2 |
| Calendar, dialogs | 0 | 0 | 11 | 9 | 3 |
| Knowledge, command line, keys | 0 | 1 | 7 | 6 | 4 |
| Settings | 0 | 0 | 2 | 10 | 4 |
| Errors, sync, empty states | 0 | 0 | 6 | 9 | 0 |
| Site | 0 | 0 | 0 | 6 | 6 |
| **total (126)** | **0** | **2** | **38** | **63** | **23** |

### S — structure / broken

- none

### A — clearly off

- **R4-019** (OS notifications, timer, update, what's new, tray (N-Ntf-OS, X-Ntf-OS)) — sheet: a quiet update line at the bottom of the sidebar, inside its gutters → app: the line ("0.8.1 доступна · скачать · что нового") has no width limit, so its implicit width pushes out the whole sidebar column: the new-task field, timer chip, Ctrl hints, counters and the profile dot run into the sidebar border with no right gutter, and the dot is clipped (bold and quiet) · files: qml/Sidebar.qml (Row updateLine ~l.450, no Layout.maximumWidth/elide)
- **R4-073** (Quick capture over other windows (N-Oth-Capture, X-Oth-Capture)) — sheet: quick note header "быстрая заметка → «Входящие»" (a global capture goes to the Inbox) → app: it appends to whichever note was last open ("→ «Дизайн rate-limit»", "→ «Схема повторов платежа»"); Inbox only when no note is open · files: src/AppController.cpp (quickNoteTarget / appendNoteEntry), qml/QuickCaptureNotesPopup.qml

### B — visible detail

- **R4-001** (Today (H2-Today, H2-Today-Calm)) — sheet: main padding 28/36 px in bold, 40/48 in quiet (H2-Today, H2-Today-Calm, H2-First, Q-First) → app: 16/24 bold and 32/34 quiet, so the header and day sit about 12 px tighter to the sidebar and the top · files: qml/TodayView.qml (anchors.*Margin ~l.294-296)
- **R4-006** (First run (H2-First, Q-First)) — sheet H2-First: the first-run sidebar has no Ctrl key hints on Сегодня/Задачи/Знания/Настройки, no "Ctrl K — всё остальное" footer and no dot by the profile name → app: shows all three, as in the full app · files: qml/Sidebar.qml
- **R4-007** (First run (H2-First, Q-First)) — sheet: input placeholder 16px, "например:" muted and the example brighter (#c4ccd6) → app: the whole placeholder one muted colour, smaller · files: qml/FirstRunHero.qml
- **R4-010** (Small window 1280 (N-Oth-Small, X-Oth-Small)) — sheet: the date title in the small window is 22px/600 in both styles → app: keeps the full-size 30px (bold) / 26px (quiet) · files: qml/TodayView.qml (fsDayTitle not reduced when stacked), qml/Theme.qml
- **R4-011** (Small window 1280 (N-Oth-Small, X-Oth-Small)) — sheet: the active section in the folded sidebar is a 34×34 rounded tile (#171b21) behind the icon → app: no tile, a lavender underline bar under the icon · files: qml/Sidebar.qml (NavRow / CursorBar when !expanded)
- **R4-013** (Light theme (N-Oth-Light, X-Oth-Light)) — sheet: quiet "Новая задача…" is a transparent field with a hairline border (light #dcdfe4, dark H2-Today-Calm/Q-First also `background: transparent`) → app: filled with Theme.panel, which shows as a white box on the light sidebar · files: qml/Sidebar.qml (newTask color)
- **R4-017** (Toasts and sync indicator (N-Ntf-Toasts, X-Ntf-Toasts)) — sheet: the sync popover lists every source with its status (Jira, GitHub, Календарь ICS · 10 мин назад, GitLab) → app (t-bold-sync-popover): a second "Jira" row with a red dot and no status text, no reason or action · files: qml/SyncPopover.qml
- **R4-020** (OS notifications, timer, update, what's new, tray (N-Ntf-OS, X-Ntf-OS)) — sheet: "Что нового" text in 13px body type, heading 15px/600 → app: rows and descriptions ~11–12px, heading ~14px; the card reads one step smaller · files: qml/WhatsNewDialog.qml
- **R4-021** (Board (H2-Board, Q-Board)) — sheet: card title line-height 1.35 of the 13 px font (two lines about 17.5 px apart) → app: lines about 20.5 px apart, because Qt's proportional lineHeight multiplies the font's own leading, not the em. Every card is about 15 % taller, and so is the board · files: qml/TaskCard.qml (title Text, `lineHeight: Style.fills ? 1.35 : 1.4`)
- **R4-037** (Select & drag (N-Oth-Select-Drag, X-Oth-Select-Drag)) — sheet: while a selection exists, the unselected cards show an empty ring where the selected ones show the check ("Настройки уведомлений", "Тюнинг кэша поиска") → app: only the selected cards carry a mark; the others show nothing, so the choice is not offered on them · files: qml/TaskCard.qml (tc-selected-mark visible only when _selected)
- **R4-038** (Select & drag (N-Oth-Select-Drag, X-Oth-Select-Drag)) — sheet (quiet): the drag origin is a dashed, faded placeholder with the faded title → app (quiet-drag): only a barely visible dashed outline, with no title in it (bold-drag shows the title) · files: qml/TaskCard.qml (originComp DashedRect, opacity 0.35 + textMuted in quiet)
- **R4-039** (Archive & people (N-Oth-Archive-People, X-Oth-Archive-People)) — sheet: the people list's ask line is 13 px in #8f99a6, the detail values 13 px #c4ccd6 at line-height 1.7, the person's name 16 px → app: the ask line is 12 px and brighter, the detail values 12 px and tight, the name 14 px, so the dialog reads a step smaller and denser than the sheet · files: qml/PeopleDialog.qml (fsSm/fsLg on rows, detail)
- **R4-043** (Calendar week (H2-Calendar, Q-Calendar)) — sheet: task blocks show time + title only (no flag; the deadline sits in the flag row above the grid) → app: every task block with any `due` draws a flag icon before the title; in bold the flag takes its own column so the wrapped title is indented ("Оформление / заказа: таймаут 10с") · files: qml/WeekView.qml (Icon name "flag", ~l.2318)
- **R4-044** (Calendar week (H2-Calendar, Q-Calendar)) — sheet (Q): hour labels sit fully visible above their line, "09" readable under the day header → app quiet: at the 09:00 scroll position the "09" label is cut in half under the header row (week and day, quiet only; bold is fine) · files: qml/WeekView.qml
- **R4-047** (Calendar day and month (N-Oth-DayMonth, X-Oth-DayMonth)) — sheet (N): day-zoom task row is a 1px #262c34 subtle outline, radius 8 → app bold: day zoom reuses the week's bright 1.5px #c4ccd6 task border (quiet is correct) · files: qml/WeekView.qml (dayZoom)
- **R4-048** (Calendar day and month (N-Oth-DayMonth, X-Oth-DayMonth)) — sheet: day-zoom blocks are inset 8px from both sides with radius 8 → app: blocks span the full column edge to edge, square-looking corners against the hour line (both styles) · files: qml/WeekView.qml
- **R4-050** (Calendar day and month (N-Oth-DayMonth, X-Oth-DayMonth)) — same "09:00" half-clipped label as the quiet week (quiet day) · files: qml/WeekView.qml
- **R4-051** (Meeting panel and series question (N-Dlg-Event, X-Dlg-Event)) — sheet: scope dialog radios are 32px rows with clearly visible white outline circles → app: rows ~50px apart (rowH + spacing) and the unselected circles are a 1px borderStrong ring that is nearly invisible on the panel (same radio in Import profile dialog) · files: qml/SeriesScopeDialog.qml, qml/ProfileImportDialog.qml
- **R4-052** (Meeting panel and series question (N-Dlg-Event, X-Dlg-Event)) — sheet: "Отмена Esc" / "Перенести ↵" carry key hints (both styles) → app: plain "Отмена" / "Перенести", no hints · files: qml/SeriesScopeDialog.qml (shortcutId "")
- **R4-056** (Schedule / deadline field (N-Dlg-Schedule, X-Dlg-Schedule)) — sheet: hint line "↵ поставить · …", "↵ всё равно поставить" → app: the ↵ glyph renders as "←" (glyph missing in the UI font, falls back), reads as "back"; same in the slot menu "Перейти к этому дню ←" · files: qml/I18n.qml (schedule.keys, schedule.keys.clash), qml/SchedulePopup.qml
- **R4-059** (Recap, end of day, standup (N-Dlg-Recap, X-Dlg-Recap)) — sheet: standup draft box line-height 1.7 (22px lines), 12/14 padding → app: lines at ~15px, text packed tight in the box · files: qml/StandupDraftDialog.qml
- **R4-062** (Small dialogs and confirmations (N-Dlg-Small, X-Dlg-Small)) — sheet: one template — title, fact right under it, field, buttons right after → app: "Открыть ссылку в браузере?" is off the template: wider (460), ~14px extra gap between title and fact and ~35px dead space between the field and the buttons · files: qml/LinkConfirmDialog.qml
- **R4-065** (Event log and import (N-Dlg-Log-Import, X-Dlg-Log-Import)) — sheet (N): an error row's source carries a ⚠ mark ("GitHub ⚠") → app bold: error rows look like any other row, no mark · files: qml/EventLogDialog.qml
- **R4-066** (Knowledge (H2-Knowledge, Q-Knowledge)) — sheet: bold pane title "Знания" 18px/600 → app: Theme.fsLg = 15px (quiet 19 vs 20 is fine) · files: qml/NotesListPane.qml (~l.363)
- **R4-067** (Knowledge (H2-Knowledge, Q-Knowledge)) — sheet: 18px gap between the meta line ("Заметка · изменена …") and the note title (title top ≈ meta + 43px) → app: the title sits right under the meta (≈ +27px), so the whole document starts ~16px higher, both styles · files: qml/NotesView.qml, qml/MdView.qml (level-1 heading topMargin 0)
- **R4-071** (Knowledge inserts and "/" menu (N-Oth-Knowledge, X-Oth-Knowledge)) — sheet: an image is a framed block (filename · size) with its caption under it → app: an image that fails to load has zero height; "Изображение не найдено" is drawn unframed and overlaps the caption line (bold-k-knowledge) · files: qml/MdView.qml (localImage, ~l.615)
- **R4-074** (Quick capture over other windows (N-Oth-Capture, X-Oth-Capture)) — sheet (N and X): parsed chips are outlined (1px #262c34, no fill), value in regular #c4ccd6 → app bold: filled chips with no border and bold values (quiet matches) · files: qml/QuickCapturePopup.qml
- **R4-077** (Command line (H2-Command, Q-Command)) — sheet: one way to reach Knowledge → app: the empty command list also offers legacy "Перейти к докам" and "Перейти к заметкам" (both open Знания) beside "Перейти в «Знания»" · files: src/AppController.cpp (shortcut.view.docs/notes labels ~l.815, catalogue ~l.14261), qml/CommandPalette.qml
- **R4-080** (Key cheat sheet (N-Keys, X-Keys)) — sheet: "Открыть" key is the ↵ glyph (as everywhere else in the app's hints) → app: the word "Enter" · files: qml/KeyCheatSheet.qml, src/AppController.cpp (keyText)
- **R4-081** (Key cheat sheet (N-Keys, X-Keys)) — sheet: Вид area has "Панель дня  Ctrl \" → app: row missing; no day-panel toggle exists in the key catalogue (code) · files: qml/KeyCheatSheet.qml (view area), src/AppController.cpp (catalogue)
- **R4-086** (Style and keys (N-Set-StyleKeys, X-Set-StyleKeys)) — sheet: keycaps outlined with a dim hairline (#262c34), dim key text → app: keycap border is the bright field border, so every one of the ~40 rows shows a bright box (both styles) · files: qml/SettingsView.qml (keyCap)
- **R4-091** (Calendar, notifications, safety (N-Set-CalNotif, X-Set-CalNotif)) — sheet: "Ctrl Shift F — одна задача, уведомления ждут" → app: "Ctrl+Shift+F — …" (raw shortcut string with plus signs, unlike every other key label in the app) · files: qml/SettingsView.qml:2183 (shortcutFor, not keyText)
- **R4-100** (Empty states and special cases (N-Err-Empty, X-Err-Empty)) — sheet: a filter that finds nothing reads "Ничего под «…»" + "сбросить фильтр · Esc" (board/list do this) → app: week and month with a search show the old generic "По поиску ничего не найдено" + "Сбросьте поиск или фильтры, чтобы снова видеть всё." (code; week/month captures had events) · files: qml/WeekView.qml, qml/MonthView.qml
- **R4-104** (Saving, restore, damaged file, crash (N-Err-Storage, X-Err-Storage)) — sheet: damaged-file body starts "state.json не читается с позиции 18 230." then "Ничего не удалено: …" → app: only "Ничего не удалено: повреждённый файл сохранён рядом как …" (where the file breaks is not said) · files: qml/DamagedFileDialog.qml, qml/I18n.qml (storage.damaged.fact)
- **R4-105** (Saving, restore, damaged file, crash (N-Err-Storage, X-Err-Storage)) — sheet: card body 13 px, line-height ~1.5, dim grey (#8f99a6); option rows 13 px → app: body ~12 px set tight (~1.2 line-height) and brighter, rows/counts ~12/11 px; the damaged, keychain and "Тикет назначен" cards read cramped next to the sheet · files: qml/DamagedFileDialog.qml, qml/KeychainDialog.qml, qml/TrackerPushConfirmDialog.qml (shared small-dialog body text)
- **R4-107** (Tracker errors (N-Err-Tracker, X-Err-Tracker)) — sheet (bold): waiting lines (429, Нет сети) use an amber dashed ring (#f2a65a), errors a red one → app: the waiting ring is drawn in the text colour (only the error icon takes danger) · files: qml/TrackerStrip.qml (Icon color)
- **R4-112** (Sync conflict and writing to a tracker (N-Dlg-Conflict, X-Dlg-Conflict)) — sheet: field row label "Название" → app: "Заголовок" · files: qml/I18n.qml (ticket.conflict.title), qml/SyncConflictDialog.qml
- **R4-113** (Sync conflict and writing to a tracker (N-Dlg-Conflict, X-Dlg-Conflict)) — sheet: the picked cell is a 1 px #4a525d outline on the dialog background, white text; the other side dim → app: picked cells get a filled raised background plus outline (a column of grey boxes) · files: qml/SyncConflictDialog.qml

## Per sheet

## Today, notifications, system

### Today (H2-Today, H2-Today-Calm)

captures: bold-today, quiet-today, bold-today-mon, bold-today-empty, quiet-today-mon, bold-x-today-fri/-mon, quiet-x-today-fri/-mon

- **R4-001** [B] sheet: main padding 28/36 px in bold, 40/48 in quiet (H2-Today, H2-Today-Calm, H2-First, Q-First) → app: 16/24 bold and 32/34 quiet, so the header and day sit about 12 px tighter to the sidebar and the top · files: qml/TodayView.qml (anchors.*Margin ~l.294-296)
- **R4-002** [C] sheet: free time is a row with a dashed left rule; short gaps are left out and the end row sits at the last block's end ("18:30 Конец рабочего дня в 19:00") → app: solid rule, also a "Свободно 30 мин" row for 30-min gaps, end row labelled 19:00 · files: qml/TodayView.qml (rows / DayRow)
- **R4-003** [C] sheet: day-row titles are weight 500 (`font-weight: 500`) → app: bold Today rows use 600 (R2-005 covers cards and list rows, not the Today day rows) · files: qml/TodayView.qml
- **R4-004** [C] sheet: eyebrow "Сегодня" → app: on another day the eyebrow repeats the title's date in lowercase ("понедельник, 12 октября" above "Понедельник, 12 октября") · files: qml/TodayView.qml (today-label)
- **R4-005** [D] sheet: quiet "▸ Кому написать · 2" with a filled triangle → app: a line chevron › · files: qml/TodayView.qml

### First run (H2-First, Q-First)

captures: bold-first-today, quiet-first-today, quiet-first-1280, bold-first-*

- **R4-006** [B] sheet H2-First: the first-run sidebar has no Ctrl key hints on Сегодня/Задачи/Знания/Настройки, no "Ctrl K — всё остальное" footer and no dot by the profile name → app: shows all three, as in the full app · files: qml/Sidebar.qml
- **R4-007** [B] sheet: input placeholder 16px, "например:" muted and the example brighter (#c4ccd6) → app: the whole placeholder one muted colour, smaller · files: qml/FirstRunHero.qml
- **R4-008** [C] sheet: 28px gap input→cards and cards→divider, card padding 14px (cards ~86px tall) → app: ~16px gaps, cards ~72px · files: qml/FirstRunHero.qml
- **R4-009** [D] sheet Q-First: "Ctrl K" in the hint line is mono → app: UI font · files: qml/FirstRunHero.qml

### Small window 1280 (N-Oth-Small, X-Oth-Small)

captures: bold-1280-today, quiet-1280-today, quiet-first-1280, bold-1280-*

- **R4-010** [B] sheet: the date title in the small window is 22px/600 in both styles → app: keeps the full-size 30px (bold) / 26px (quiet) · files: qml/TodayView.qml (fsDayTitle not reduced when stacked), qml/Theme.qml
- **R4-011** [B] sheet: the active section in the folded sidebar is a 34×34 rounded tile (#171b21) behind the icon → app: no tile, a lavender underline bar under the icon · files: qml/Sidebar.qml (NavRow / CursorBar when !expanded)
- **R4-012** [C] sheet: day-row titles 13px/500 with a 12px detail → app: titles look smaller and lighter, close in size to the detail · files: qml/TodayView.qml

### Light theme (N-Oth-Light, X-Oth-Light)

captures: bold-light-today, quiet-light-today, bold-light-*, quiet-light-*

- **R4-013** [B] sheet: quiet "Новая задача…" is a transparent field with a hairline border (light #dcdfe4, dark H2-Today-Calm/Q-First also `background: transparent`) → app: filled with Theme.panel, which shows as a white box on the light sidebar · files: qml/Sidebar.qml (newTask color)

### Focus mode and launch (N-Ntf-Focus, X-Ntf-Focus)

captures: bold-immersion, quiet-immersion, bold-splash, quiet-splash, bold-splash-crash, quiet-splash-crash

- **R4-014** [C] sheet: focus-mode title 30px/500, footer text 13px, timer 15px mono → app: title looks 600, footer ~12px, timer ~14px · files: qml/ImmersionView.qml
- **R4-015** [D] sheet: "Готово D" with D in the body font, the same size → app: D is a tiny mono key glyph · files: qml/ImmersionView.qml
- **R4-016** [D] sheet: timer key "⏸ T" (capital) in both places → app: sidebar timer shows "t", focus mode shows "T" · files: qml/Sidebar.qml, qml/ImmersionView.qml

### Toasts and sync indicator (N-Ntf-Toasts, X-Ntf-Toasts)

captures: bold-toast, bold-toast-done, quiet-toast, quiet-toast-done, bold/quiet-e-hiddentoast, t-*-sync-*, t-*-strip, t-*-trk-today

- **R4-017** [B] sheet: the sync popover lists every source with its status (Jira, GitHub, Календарь ICS · 10 мин назад, GitLab) → app (t-bold-sync-popover): a second "Jira" row with a red dot and no status text, no reason or action · files: qml/SyncPopover.qml
- **R4-018** [C] sheet: popover source names and status at 13px → app: ~11–12px, rows look small next to the indicator · files: qml/SyncPopover.qml

### OS notifications, timer, update, what's new, tray (N-Ntf-OS, X-Ntf-OS)

captures: bold-timer-update, quiet-timer-update, t-*-timer-update, bold-whatsnew, quiet-whatsnew, t-*-whatsnew; tray/OS (code)

- **R4-019** [A] sheet: a quiet update line at the bottom of the sidebar, inside its gutters → app: the line ("0.8.1 доступна · скачать · что нового") has no width limit, so its implicit width pushes out the whole sidebar column: the new-task field, timer chip, Ctrl hints, counters and the profile dot run into the sidebar border with no right gutter, and the dot is clipped (bold and quiet) · files: qml/Sidebar.qml (Row updateLine ~l.450, no Layout.maximumWidth/elide)
- **R4-020** [B] sheet: "Что нового" text in 13px body type, heading 15px/600 → app: rows and descriptions ~11–12px, heading ~14px; the card reads one step smaller · files: qml/WhatsNewDialog.qml

## Tasks, menus, drag

### Board (H2-Board, Q-Board)

captures: bold-board, quiet-board, bold-1280-board, quiet-1280-board, bold-donecol, bold-taskmenu

- **R4-021** [B] sheet: card title line-height 1.35 of the 13 px font (two lines about 17.5 px apart) → app: lines about 20.5 px apart, because Qt's proportional lineHeight multiplies the font's own leading, not the em. Every card is about 15 % taller, and so is the board · files: qml/TaskCard.qml (title Text, `lineHeight: Style.fills ? 1.35 : 1.4`)
- **R4-022** [C] sheet: the folded "Готово 2" header sits on the same baseline as the other headers, with the same bottom rule (border-bottom #1f252d) and "Показать" under that rule → app: no rule under "Готово", the header sits about 1 px lower than the others, and "Показать" hangs right under the name · files: qml/KanbanBoard.qml (folded Done column)
- **R4-023** [C] sheet: "добавить условие…" starts 8 px after the last chip → app: a gap of about 30–50 px between the last chip and the placeholder (bold query line) · files: qml/TopBar.qml (query Flow / input width)
- **R4-024** [C] sheet: 8 px column gap between key, date and priority on a card → app: about 14 px between the key and the date · files: qml/TaskCard.qml (facts row spacing)
- **R4-025** [C] sheet (quiet): chip row to column headers about 52 px → app: about 62 px, so the columns start lower · files: qml/TopBar.qml, qml/KanbanBoard.qml

### List (H2-List, Q-List)

captures: bold-list, quiet-list, bold-1280-list, quiet-1280-list

- **R4-026** [C] sheet: P0/P1 at font-weight 600 (cards and list rows) → app: Theme.fwTitle = Medium (500), so the priority reads lighter than the sheet · files: qml/TaskListView.qml (list-row-priority), qml/TaskCard.qml (tc-priority)
- **R4-027** [C] sheet (bold list): dates that are not "hot" in #8f99a6 (dim) → app: Theme.textMuted, a step brighter, so the date column competes with the titles · files: qml/TaskListView.qml (list-row-date colour)
- **R4-028** [C] sheet: bold footer keys in mono #c4ccd6 and labels in #8f99a6 → app: keys and labels in about the same dim tone, keys not emphasised · files: qml/TaskListView.qml (footer key hints) / KeyHint
- **R4-029** [C] sheet (quiet): group headings 14 px/500 #c4ccd6, about 35 px from the heading to the first row, and "Без даты · 3" all dim → app: headings at regular weight, rows tighter under the heading (about 34 px vs 50 px heading-to-row pitch), and "Без даты" drawn in the heading tone · files: qml/TaskListView.qml (group header, quiet)
- **R4-030** [D] sheet (quiet): priority mark in #aeb7c2 → app: brighter, near the title tone · files: qml/TaskListView.qml

### Task document (H2-Task, Q-Task)

captures: bold-task, bold-task-full, quiet-task, quiet-task-full, bold-1280-task, quiet-1280-task

- **R4-031** [C] sheet: "+ свойство" on its own row under the property chips → app: inline at the end of the chip row (both styles, panel and full) · files: qml/TaskDocument.qml (chips Flow)
- **R4-032** [C] sheet: История always has lines (the sheet's 3rd is "2 окт · создана из Jira") → app: the section disappears when there is no log entry and no statusChangedAt, though the creation date is known (bold-task-full, quiet-task-full show no История) (code) · files: qml/TaskDocument.qml (_historyRows fallback)

### Task menu & selection bar (N-Menus-Task, X-Menus-Task)

captures: bold-m-task, bold-taskmenu, bold-taskmenu-status, bold-x-m-status, bold-m-priority, quiet-taskmenu, quiet-x-m-task

- **R4-033** [C] sheet: menu outline is a hairline barely above the surface (#232a33 on #13161b) → app: popupBorder = fieldBorder, a light grey stroke (about rgb 106,111,118) that outlines every menu loudly (all menus: task, column, slot, status, priority) · files: qml/PopupSurface.qml, qml/Theme.qml (popupBorder)
- **R4-034** [C] sheet: the highlighted row is a rounded fill with a light inner left edge, and its label turns 600 (Открыть, К выполнению, P2) → app: a separate thin lavender bar beside the fill, and the label stays regular · files: qml/AppMenuItem.qml (highlight bar, labelWeight)
- **R4-035** [D] sheet: menu about 292 px wide, keys inset about 35 px from the right edge → app: about 222 px, keys about 12 px from the edge, so it reads cramped · files: qml/AppMenu.qml (minWidth / padding)

### Column & calendar menus (N-Menus-Column, X-Menus-Column)

captures: bold-m-column, quiet-m-column, bold-m-slot, bold-m-event (shows the slot menu: harness), bold-confirm-column

- **R4-036** [C] sheet: the slot menu's context line "пт, 9 окт · 14:00" is flush with the rows → app: the header line is indented about 11 px further than the rows ("сб, 10 окт · 11:30"), unlike the task and column menu headers · files: qml/CalendarView.qml / WeekView.qml (slot menu AppMenuHeader)

### Select & drag (N-Oth-Select-Drag, X-Oth-Select-Drag)

captures: bold-multiselect, bold-drag, bold-x-drag, quiet-drag

- **R4-037** [B] sheet: while a selection exists, the unselected cards show an empty ring where the selected ones show the check ("Настройки уведомлений", "Тюнинг кэша поиска") → app: only the selected cards carry a mark; the others show nothing, so the choice is not offered on them · files: qml/TaskCard.qml (tc-selected-mark visible only when _selected)
- **R4-038** [B] sheet (quiet): the drag origin is a dashed, faded placeholder with the faded title → app (quiet-drag): only a barely visible dashed outline, with no title in it (bold-drag shows the title) · files: qml/TaskCard.qml (originComp DashedRect, opacity 0.35 + textMuted in quiet)

### Archive & people (N-Oth-Archive-People, X-Oth-Archive-People)

captures: bold-archive, quiet-archive, bold-archive-empty, bold-people, bold-r3-people, quiet-r3-people

- **R4-039** [B] sheet: the people list's ask line is 13 px in #8f99a6, the detail values 13 px #c4ccd6 at line-height 1.7, the person's name 16 px → app: the ask line is 12 px and brighter, the detail values 12 px and tight, the name 14 px, so the dialog reads a step smaller and denser than the sheet · files: qml/PeopleDialog.qml (fsSm/fsLg on rows, detail)
- **R4-040** [C] sheet: list names in regular weight #e9edf2, and "Написал" as the stronger button (border #4a525d, white) beside a quiet "Ответил" → app: names bold, and both buttons equal in weight · files: qml/PeopleDialog.qml
- **R4-041** [C] sheet (quiet): state reads "ждёт" with no dot, and the footer is "+ человек · Ctrl Shift U" → app quiet: "• ждёт" with a dot, and "+ человек" with no key · files: qml/PeopleDialog.qml
- **R4-042** [C] sheet: "+ человек · Ctrl Shift U" right after the last person → app: pinned to the bottom of a fixed-height dialog, with a large empty band above it · files: qml/PeopleDialog.qml

## Calendar, dialogs

### Calendar week (H2-Calendar, Q-Calendar)

captures: bold-week, quiet-week, bold-1280-week, quiet-calendar, bold-calendar

- **R4-043** [B] sheet: task blocks show time + title only (no flag; the deadline sits in the flag row above the grid) → app: every task block with any `due` draws a flag icon before the title; in bold the flag takes its own column so the wrapped title is indented ("Оформление / заказа: таймаут 10с") · files: qml/WeekView.qml (Icon name "flag", ~l.2318)
- **R4-044** [B] sheet (Q): hour labels sit fully visible above their line, "09" readable under the day header → app quiet: at the 09:00 scroll position the "09" label is cut in half under the header row (week and day, quiet only; bold is fine) · files: qml/WeekView.qml
- **R4-045** [C] sheet (Q): today's column has no tint (only the header is white/500) → app quiet: today's column is tinted like bold · files: qml/WeekView.qml
- **R4-046** [D] sheet (Q): a 30-min meeting shows its title only (second line clipped by 22px height) → app quiet: shows "11:00–11:30" under the title in the 30-min block · files: qml/WeekView.qml

### Calendar day and month (N-Oth-DayMonth, X-Oth-DayMonth)

captures: bold-day, quiet-day, bold-month, quiet-month

- **R4-047** [B] sheet (N): day-zoom task row is a 1px #262c34 subtle outline, radius 8 → app bold: day zoom reuses the week's bright 1.5px #c4ccd6 task border (quiet is correct) · files: qml/WeekView.qml (dayZoom)
- **R4-048** [B] sheet: day-zoom blocks are inset 8px from both sides with radius 8 → app: blocks span the full column edge to edge, square-looking corners against the hour line (both styles) · files: qml/WeekView.qml
- **R4-049** [C] sheet (N): meeting icon in day zoom is accent blue (#7aa7ff) → app bold: icon in text colour · files: qml/WeekView.qml
- **R4-050** [B] same "09:00" half-clipped label as the quiet week (quiet day) · files: qml/WeekView.qml

### Meeting panel and series question (N-Dlg-Event, X-Dlg-Event)

captures: bold-event-new, bold-event-open, bold-series, quiet-event-open, quiet-series

- **R4-051** [B] sheet: scope dialog radios are 32px rows with clearly visible white outline circles → app: rows ~50px apart (rowH + spacing) and the unselected circles are a 1px borderStrong ring that is nearly invisible on the panel (same radio in Import profile dialog) · files: qml/SeriesScopeDialog.qml, qml/ProfileImportDialog.qml
- **R4-052** [B] sheet: "Отмена Esc" / "Перенести ↵" carry key hints (both styles) → app: plain "Отмена" / "Перенести", no hints · files: qml/SeriesScopeDialog.qml (shortcutId "")
- **R4-053** [C] sheet: panel header calendar icon in accent blue (bold) → app: icon in muted text colour · files: qml/EventEditor.qml
- **R4-054** [C] sheet: parsed parts in the one-line input are muted blue #a9c3dd → app: brighter accent blue · files: qml/EventCapture.qml
- **R4-055** [D] sheet: scope preselected "Все в серии" → app preselects "Только эту встречу" · files: qml/SeriesScopeDialog.qml

### Schedule / deadline field (N-Dlg-Schedule, X-Dlg-Schedule)

captures: bold-schedule, -overlap, -unknown, -picker, -picker-hours, -due (+ quiet)

- **R4-056** [B] sheet: hint line "↵ поставить · …", "↵ всё равно поставить" → app: the ↵ glyph renders as "←" (glyph missing in the UI font, falls back), reads as "back"; same in the slot menu "Перейти к этому дню ←" · files: qml/I18n.qml (schedule.keys, schedule.keys.clash), qml/SchedulePopup.qml
- **R4-057** [C] sheet: input has a visible #4a525d border, 14px text → app: faint field border, smaller text · files: qml/SchedulePopup.qml
- **R4-058** [C] sheet: date picker hour list shows whole rows (6 slots) → app: last row cut in half at the bottom of the list ("16:00" sliced) · files: qml/DatePickerPopup.qml

### Recap, end of day, standup (N-Dlg-Recap, X-Dlg-Recap)

captures: bold-recap, bold-endofday, bold-standup, quiet-endofday (+ quiet-recap, quiet-standup)

- **R4-059** [B] sheet: standup draft box line-height 1.7 (22px lines), 12/14 padding → app: lines at ~15px, text packed tight in the box · files: qml/StandupDraftDialog.qml
- **R4-060** [C] sheet: end-of-day action chips are 26px, 12px text, filled #1a1f26 → app: 30px outline buttons with 13px text, heavier than the sheet · files: qml/EndOfDayDialog.qml
- **R4-061** [C] sheet: weekly bars rows 26px apart → app: ~19px, list feels cramped · files: qml/WeeklyRecapDialog.qml

### Small dialogs and confirmations (N-Dlg-Small, X-Dlg-Small)

captures: bold-confirm-column, -confirm-link, -confirm-example, -profile-new, -r3-profiledelete (+ quiet)

- **R4-062** [B] sheet: one template — title, fact right under it, field, buttons right after → app: "Открыть ссылку в браузере?" is off the template: wider (460), ~14px extra gap between title and fact and ~35px dead space between the field and the buttons · files: qml/LinkConfirmDialog.qml
- **R4-063** [C] sheet: fact text 13px like the other dialogs → app: "Убрать пример?" fact is smaller (12px) and the card a different width (440) · files: qml/Main.qml (example-remove dialog) / qml/SmallDialog.qml
- **R4-064** [D] sheet: column picker "К выполнению ▾" with the caret next to the value → app: caret pinned at the far right of a full-width combo · files: qml/AppComboBox.qml

### Time machine (N-Dlg-TimeMachine, X-Dlg-TimeMachine)

captures: bold-timemachine, quiet-timemachine

- no gaps

### Event log and import (N-Dlg-Log-Import, X-Dlg-Log-Import)

captures: bold-log, quiet-log, bold-import, bold-r3-import (+ quiet)

- **R4-065** [B] sheet (N): an error row's source carries a ⚠ mark ("GitHub ⚠") → app bold: error rows look like any other row, no mark · files: qml/EventLogDialog.qml

## Knowledge, command line, keys

### Knowledge (H2-Knowledge, Q-Knowledge)

captures: bold-knowledge, quiet-knowledge, bold-k-knowledge, bold-e-knowledge, quiet-1280-knowledge, bold-r3-knowledge

- **R4-066** [B] sheet: bold pane title "Знания" 18px/600 → app: Theme.fsLg = 15px (quiet 19 vs 20 is fine) · files: qml/NotesListPane.qml (~l.363)
- **R4-067** [B] sheet: 18px gap between the meta line ("Заметка · изменена …") and the note title (title top ≈ meta + 43px) → app: the title sits right under the meta (≈ +27px), so the whole document starts ~16px higher, both styles · files: qml/NotesView.qml, qml/MdView.qml (level-1 heading topMargin 0)
- **R4-068** [C] sheet: list rows, group labels, search and pane title share one left edge → app: group labels/rows are inset 8px from the "Знания" title and search field, both styles · files: qml/NotesListPane.qml
- **R4-069** [C] sheet: links column keeps ~40px right margin and wraps "RFC 6585 · 429 Too Many Requests" → app: text runs to ~19px from the window edge, no wrap · files: qml/NotesView.qml
- **R4-070** [D] sheet (quiet): only "APP-101" is underlined, the ring sits before it → app: the underline also runs under the ring glyph · files: qml/MdView.qml

### Knowledge inserts and "/" menu (N-Oth-Knowledge, X-Oth-Knowledge)

captures: bold-r3-slash, quiet-r3-slash, bold-k-slash, bold-k-knowledge, bold-x-vault

- **R4-071** [B] sheet: an image is a framed block (filename · size) with its caption under it → app: an image that fails to load has zero height; "Изображение не найдено" is drawn unframed and overlaps the caption line (bold-k-knowledge) · files: qml/MdView.qml (localImage, ~l.615)
- **R4-072** [D] sheet: "/" menu's left edge lines up with the typed "/" → app: menu starts ~7px to the right of it · files: qml/MdBlockEditor.qml

### Quick capture over other windows (N-Oth-Capture, X-Oth-Capture)

captures: bold-capture-empty, bold-capture-typed, quiet-capture-typed, bold-k-capture, bold-r3-quicknote, bold-x-quicknote, quiet-r3-quicknote

- **R4-073** [A] sheet: quick note header "быстрая заметка → «Входящие»" (a global capture goes to the Inbox) → app: it appends to whichever note was last open ("→ «Дизайн rate-limit»", "→ «Схема повторов платежа»"); Inbox only when no note is open · files: src/AppController.cpp (quickNoteTarget / appendNoteEntry), qml/QuickCaptureNotesPopup.qml
- **R4-074** [B] sheet (N and X): parsed chips are outlined (1px #262c34, no fill), value in regular #c4ccd6 → app bold: filled chips with no border and bold values (quiet matches) · files: qml/QuickCapturePopup.qml
- **R4-075** [C] sheet: quick-note card padding 16px; footer "Ctrl ↵ сохранить   Esc — черновик сохранится" as two separate hints → app: ~10px left padding (header/text start at 430 vs card 420), hints joined with "·" · files: qml/QuickCaptureNotesPopup.qml
- **R4-076** [D] sheet: title underline is the strong rule (#4a525d) and the profile caret is a small filled triangle → app: dim hairline and a chevron · files: qml/QuickCapturePopup.qml

### Other menus (N-Menus-Other, X-Menus-Other)

captures: bold-x-m-note, bold-x-m-savedview, bold-m-profile, quiet-x-m-savedview, quiet-x-m-profile, bold-m-textfield (unopened, judged by code)

- no gaps

### Command line (H2-Command, Q-Command)

captures: bold-palette-query, quiet-palette-query, bold-palette, bold-palette-empty, bold-k-palette

- **R4-077** [B] sheet: one way to reach Knowledge → app: the empty command list also offers legacy "Перейти к докам" and "Перейти к заметкам" (both open Знания) beside "Перейти в «Знания»" · files: src/AppController.cpp (shortcut.view.docs/notes labels ~l.815, catalogue ~l.14261), qml/CommandPalette.qml
- **R4-078** [C] sheet (both styles): chips in the line are plain → app: every chip carries a permanent "×" · files: qml/CommandPalette.qml
- **R4-079** [C] sheet: selected task row and the "Один язык везде" examples (p0 … p3, завтра 15:00 …) in bright semibold → app: regular weight, dimmer; quiet rows also start 4px left of the chips/labels edge · files: qml/CommandPalette.qml

### Key cheat sheet (N-Keys, X-Keys)

captures: bold-cheatsheet, quiet-cheatsheet, bold-k-cheatsheet

- **R4-080** [B] sheet: "Открыть" key is the ↵ glyph (as everywhere else in the app's hints) → app: the word "Enter" · files: qml/KeyCheatSheet.qml, src/AppController.cpp (keyText)
- **R4-081** [B] sheet: Вид area has "Панель дня  Ctrl \" → app: row missing; no day-panel toggle exists in the key catalogue (code) · files: qml/KeyCheatSheet.qml (view area), src/AppController.cpp (catalogue)
- **R4-082** [C] sheet: intro ends "менять в Настройках → Клавиши", wrapped at ~900px; footer "Изменить сочетание — Настройки → Клавиши · Ctrl / тоже…" → app: "менять в «Изменить сочетания…»", intro runs the full panel width; footer is a link "Изменить сочетания…" · files: qml/KeyCheatSheet.qml, qml/I18n.qml (keys.sheet.intro)
- **R4-083** [D] sheet: "было Ctrl 1–8" on its own line under "Доска, Лента, Неделя…" → app: wraps inline beside the label · files: qml/KeyCheatSheet.qml

## Settings

### Settings overview (H2-Settings, Q-Settings)

captures: bold-settings, quiet-settings, bold-light-settings, bold-set-data

- **R4-084** [C] sheet: nav items inset ~8px from the search field's left edge (H2, Q) → app: nav labels flush with the search field edge · files: qml/SettingsView.qml
- **R4-085** [C] sheet Q-Settings: quiet accent options лаванда / чернила / янтарь → app: лаванда / чернила / графит in quiet (H2 bold says Графит) · files: qml/SettingsView.qml

### Style and keys (N-Set-StyleKeys, X-Set-StyleKeys)

captures: bold-set-appearance, quiet-settings, bold-set-shortcuts, bold-k-set-shortcuts, bold-set-keys-conflict, quiet-set-keys-conflict

- **R4-086** [B] sheet: keycaps outlined with a dim hairline (#262c34), dim key text → app: keycap border is the bright field border, so every one of the ~40 rows shows a bright box (both styles) · files: qml/SettingsView.qml (keyCap)
- **R4-087** [C] sheet: an unbound action shows a dashed box with "—" → app: solid box at 0.6 opacity · files: qml/SettingsView.qml (keyCap)
- **R4-088** [C] sheet: key rows ~45px → app: ~54px per row, so the long list is ~20% taller · files: qml/SettingsView.qml, qml/SettingsRow.qml
- **R4-089** [C] sheet: style picker has no tray, only the picked option in a filled/outlined pill → app (bold): picker sits in a filled tray like the other segments · files: qml/SettingsView.qml
- **R4-090** [D] sheet: conflict box "Заменить" is the emphasised (bright border, bold) button → app: Заменить and Другое сочетание look the same · files: qml/SettingsView.qml (settings-keys-replace)

### Calendar, notifications, safety (N-Set-CalNotif, X-Set-CalNotif)

captures: bold-set-calendar, bold-set-notifications, bold-set-safety, quiet-set-notifications, quiet-set-tasks

- **R4-091** [B] sheet: "Ctrl Shift F — одна задача, уведомления ждут" → app: "Ctrl+Shift+F — …" (raw shortcut string with plus signs, unlike every other key label in the app) · files: qml/SettingsView.qml:2183 (shortcutFor, not keyText)
- **R4-092** [C] sheet: day options written the same way on both rows (пн … вс; Неделя начинается пн / вс) → app (bold): Рабочие дни "пн вт …" but Неделя начинается "Пн / Вс" right beneath it · files: qml/SettingsView.qml
- **R4-093** [D] sheet: "Хранить снимков" → app: "Хранить снимков, дней" · files: qml/I18n.qml

### Columns (N-Set-Columns, X-Set-Columns)

captures: bold-set-tasks, quiet-set-tasks

- **R4-094** [C] sheet: Этап dropdown has a dim outline and a tiny caret, drag handles are faint dots → app: brighter dropdown border with a large ▼ and brighter, larger drag dots (both styles) · files: qml/SettingsView.qml
- **R4-095** [D] sheet X: "+ Колонка" → app quiet: "+ колонка" (lowercased by the quiet option rule) · files: qml/SettingsView.qml

### Git, language, help, about (N-Set-GitLangAbout, X-Set-GitLangAbout)

captures: bold-set-git, bold-set-language, bold-set-help, bold-set-about, quiet-set-about

- **R4-096** [C] sheet: Помощь has a heading only → app: extra description line "Клавиши, гид, сообщение о проблеме" · files: qml/SettingsView.qml, qml/I18n.qml (settings.section.help.sub)
- **R4-097** [C] quiet: options are lowercase (DG-090) → app quiet: "Проверить сейчас" (About) and "Синхронизировать" (Trackers) keep a capital among lowercase options · files: qml/SettingsView.qml

### Trackers (N-Set-Trackers, X-Set-Trackers)

captures: bold-set-trackers-jira, quiet-set-trackers-jira, bold-k-set-trackers, bold-set-integrations, t-bold-trk-settings, t-quiet-trk-settings

- **R4-098** [C] sheet: "Какие тикеты брать" is a normal row, JQL field right-aligned in the control column → app: JQL field is a full-width input under the label, breaking the page's one-row rule (DG-090) · files: qml/SettingsView.qml
- **R4-099** [D] sheet: "не распознан — выбрано по умолчанию" on one line → app: wraps to two lines in the narrow detail column and makes the QA row taller · files: qml/SettingsView.qml

## Errors, sync, empty states

### Empty states and special cases (N-Err-Empty, X-Err-Empty)

captures: bold/quiet-e-board, -e-list, -e-filter, -e-hiddentoast, -e-week, -e-month, -e-today, -today-empty, -e-knowledge, -e-palette, -empty-filter-list

- **R4-100** [B] sheet: a filter that finds nothing reads "Ничего под «…»" + "сбросить фильтр · Esc" (board/list do this) → app: week and month with a search show the old generic "По поиску ничего не найдено" + "Сбросьте поиск или фильтры, чтобы снова видеть всё." (code; week/month captures had events) · files: qml/WeekView.qml, qml/MonthView.qml
- **R4-101** [C] sheet: free day = "Ничего не запланировано" + one "в «Задачах» 12 без даты" line → app (bold): the undated count is stated twice, "в «Задачах» 3 без даты" under День and "3 задачи без даты — посмотреть и решить" in the side column · files: qml/TodayView.qml
- **R4-102** [C] sheet: command line miss "↵ — создать задачу «релиз пятн»" → app: "Enter — создать задачу «релиз пятн»" (key text instead of the ↵ glyph) · files: qml/I18n.qml (cmd.createLine), palette caller
- **R4-103** [C] sheet: empty Knowledge = the one empty line → app: the empty list line plus a blank editor pane on the right ("Заметка / Начните писать заметку… (поддерживается markdown…)") with no note behind it · files: qml/KnowledgeView.qml (notes editor placeholder)

### Saving, restore, damaged file, crash (N-Err-Storage, X-Err-Storage)

captures: bold/quiet-storage, -damaged, -damaged-start, -damaged-sidebar, -keychain, -report

- **R4-104** [B] sheet: damaged-file body starts "state.json не читается с позиции 18 230." then "Ничего не удалено: …" → app: only "Ничего не удалено: повреждённый файл сохранён рядом как …" (where the file breaks is not said) · files: qml/DamagedFileDialog.qml, qml/I18n.qml (storage.damaged.fact)
- **R4-105** [B] sheet: card body 13 px, line-height ~1.5, dim grey (#8f99a6); option rows 13 px → app: body ~12 px set tight (~1.2 line-height) and brighter, rows/counts ~12/11 px; the damaged, keychain and "Тикет назначен" cards read cramped next to the sheet · files: qml/DamagedFileDialog.qml, qml/KeychainDialog.qml, qml/TrackerPushConfirmDialog.qml (shared small-dialog body text)
- **R4-106** [C] sheet: each snapshot row shows its task count → app: a snapshot holding only notes/docs is offered as "Последний снимок — сегодня 07:12 · 0 задач" and preselected; the count reads as an empty restore · files: qml/DamagedFileDialog.qml (options/label count)

### Tracker errors (N-Err-Tracker, X-Err-Tracker)

captures: t-bold-strip, t-quiet-strip, t-bold-trk-board, t-quiet-trk-board, t-bold-trk-task-conflict

- **R4-107** [B] sheet (bold): waiting lines (429, Нет сети) use an amber dashed ring (#f2a65a), errors a red one → app: the waiting ring is drawn in the text colour (only the error icon takes danger) · files: qml/TrackerStrip.qml (Icon color)
- **R4-108** [C] sheet: strip line 13 px, fact semibold, reason dim → app: 12 px (fsSm) throughout; the line reads smaller than the sheet's · files: qml/TrackerStrip.qml
- **R4-109** [C] sheet: "Нет сети. 2 изменения ждут отправки, всё сохранено локально." → app: "Нет сети. В очереди на отправку: 2. Всё сохранено локально." · files: qml/I18n.qml (trk.strip.offlineWaiting)
- **R4-110** [C] sheet: amber card note "ждёт отправки статуса" → app: "статус не отправлен" · files: qml/I18n.qml, qml/TrackerMark.qml
- **R4-111** [C] sheet: a conflicted card says "изменён и у вас, и в Jira · решить" → app: card has it, but opening that task (APP-109) shows no conflict line or "решить" anywhere in the task document · files: qml/TaskDocument*.qml

### Sync conflict and writing to a tracker (N-Dlg-Conflict, X-Dlg-Conflict)

captures: t-bold-conflict, t-quiet-conflict, bold/quiet-conflict, t-bold-push-confirm, t-quiet-push-confirm, bold/quiet-confirm-push

- **R4-112** [B] sheet: field row label "Название" → app: "Заголовок" · files: qml/I18n.qml (ticket.conflict.title), qml/SyncConflictDialog.qml
- **R4-113** [B] sheet: the picked cell is a 1 px #4a525d outline on the dialog background, white text; the other side dim → app: picked cells get a filled raised background plus outline (a column of grey boxes) · files: qml/SyncConflictDialog.qml
- **R4-114** [C] sheet: row text 13–14 px, field labels dim blue-grey → app: rows ~12–13 px, labels near text colour · files: qml/SyncConflictDialog.qml

## Site

### Landing, ru + en, desktop 1440 + mobile 390 (heap-site-2 / , /ru/)

captures: site/proto-{en,ru}-{d,m}.png vs site/ship-{en,ru}-{d,m}.png; side-by-side site/cmp_rud_00..08.png, site/cmp_rum_00..07.png

- **R4-115** [C] sheet: Git scene = `git switch -c …` terminal + card with a branch line (⎇ APP-112-flaky-sync-test), body 1 paragraph → app: `git switch APP-112-…`, an extra "В работе APP-112 · PR #57 · на ревью" bar, the card is now highlighted (accent border) with "PR #57 · на ревью" instead of the branch line, an extra caption under it (auto "В работу"), body rewritten (Settings → Git, .git/HEAD, gh/glab). Deliberate (PROMISES #12–18; cards show no branch). Note: PROMISES #14 still marks the heading «нужная задача уже подсвечена» as an open gap against the app (card not highlighted in TaskCard) — the site scene now draws the highlight the app does not have · files: site/src/components/Landing.astro, site/src/data/i18n.ts (git.*), site/PROMISES.md
- **R4-116** [C] sheet: Keyboard grid of 6 cards (3×2) → app: 9 cards (3×3: adds Разделы Ctrl 1–3, Скопировать номер y y, Шпаргалка ?; Перейти gains g l; Готово "вернуть / Ctrl Z") + extra footnote paragraph (single letters, the site's own keys); section ~260 px taller on desktop, 3 cards longer on mobile. Deliberate · files: site/src/data/i18n.ts (keys.*), site/src/components/Landing.astro
- **R4-117** [C] sheet: landing download block ends with a "Через Scoop" code box → app: no Scoop box; "Все способы установки" link after the files note instead (Scoop moved to /download/ and is gated off in this build). Deliberate · files: site/src/components/Landing.astro, site/src/components/Download.astro, site/src/lib/scoop.ts
- **R4-118** [D] sheet: "Ваши данные" — four short cards; left column (paths + 1 paragraph + schema-11 JSON) and right column ("Что приложение отправляет само", 5 items) end at about the same height → app: «Трекеры — только чтение» / «Ничего не теряется» 6–7 lines (uneven cards); left column has 4 paragraphs + taller schema-12 JSON with `statuses` + note under it, right column 7 items (adds Состояние PR, Картинки в заметках) yet still ends ~450 px above the left one, leaving a tall empty area on desktop; extra sign-in caption under the tracker marquee. Deliberate · files: site/src/data/i18n.ts (trust.*), site/src/data/state-example.json, site/src/components/Landing.astro
- **R4-119** [D] sheet: FAQ 6 questions → app: 7 (adds «У меня heap 0.7. Что будет с данными?»). Deliberate · files: site/src/data/i18n.ts (faq.items)
- **R4-120** [D] sheet: footer logo · English · GitHub → app: logo · Скачать · English · MIT · GitHub (fills the row at 390, still fits). Deliberate · files: site/src/layouts/Page.astro
- **R4-121** [D] sheet: file sizes "≈ 40 МБ", "Размеры — по последнему релизу." → app: exact sizes, "Размеры файлов версии 0.7.2." (Releases API; accepted, listed only because the note line changes) · files: site/src/data/i18n.ts (get.filesNote)

### Download page (/download/, /ru/download/) — ship only, no prototype page

captures: site/ship-download-{d,m}.png, site/ship-download-ru-{d,m}.png

- **R4-122** [C] sheet: (none) → app: at 390 the "Из исходников / From source" box wraps commands mid-flag (`cmake -S lowkey -B build -` / `DCMAKE_BUILD_TYPE=Release`) and the clone URL drops to its own line, so the command reads as broken (copy button is fine) · files: site/src/styles/site.css (.way pre, line 397: pre-wrap + overflow-wrap:anywhere)
- **R4-123** [C] sheet: (none) → app: Scoop way absent in this build (version gate), while the landing link promises «Все способы установки»; page shows only AppImage + source as other ways · files: site/src/components/Download.astro (line 25–27), site/src/lib/scoop.ts
- **R4-124** [D] sheet: (none) → app: desktop, the two code boxes (AppImage 2 lines, source 3 lines) differ in height, so their captions sit at different heights (846 vs 868 px) · files: site/src/components/Download.astro, site/src/styles/site.css

### 404 — ship only, no prototype page

captures: site/ship-404-{d,m}.png (shot at /lowkey/404.html; the python test server does not route unknown paths)

- **R4-125** [C] sheet: (none) → app: one bilingual page: English h1/subtitle/Home+Download buttons, then the Russian line «Возможно, она переехала… На главную» as plain lede text with no Russian heading (i18n defines notFound.h «Такой страницы нет.» but 404.astro never renders it) and no Russian buttons; reads as a leftover rather than a second language block. Page is lang=en with the EN nav even when hit under /ru/ · files: site/src/pages/404.astro, site/src/data/i18n.ts (notFound)

### Global: nav, links, console, horizontal scroll

captures: site/probe.log (site/shoot.cjs over proto + ship landing en/ru, download en/ru, 404, at 1440 and 390)

- **R4-126** [D] sheet: (none) → app: release-asset links still point at github.com/sectapunterx/heap/releases/download/v0.7.2/heap-v0.7.2-*.(exe|zip|dmg|AppImage) and the download page shows heap-v0.7.2-* file names under "Download lowkey / Версия 0.7.2" — this is Releases API data (works via GitHub's rename redirect), so not a design gap; it resolves with the first lowkey release · files: site/src/lib/site.ts (release fetch)
