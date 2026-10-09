# Review of the 0.8.1 design decisions

Every entry of `docs/DESIGN-DECISIONS.md` (heap2/0.8.1 @ 406d188), checked with ui-ux-pro-max
(Quick Reference rule ids; `search.py --domain ux` hits named "ux:<Issue>") against the sheets in
`New heap design/screens` (X- = quiet, N-/H2- = bold, Q- = quiet full screens) and `keymap.md`.
Weighed: the sheets are the spec; no data loss; keyboard-first; lowkey shows facts and never
decides for the person.

Result: **77 KEEP · 5 CHANGE · 0 OWNER** (82 decisions).

| Section | Decision (short) | Verdict | Reason (guideline · sheet) | Change needed |
|---|---|---|---|---|
| Knowledge | DG-070 list = Закреплено/Заметки/Сниппеты; refs & contacts only in search / Ctrl K | KEEP | progressive-disclosure, content-priority; nothing unreachable · Q-Knowledge, X-Oth-Knowledge draw only these groups | — |
| Knowledge | DG-070 old Docs pages flat under "Страницы", edited like a note | KEEP | no data loss (pages stay editable), consistency · X-Oth-Knowledge has no page tree | — |
| Knowledge | DG-071 attach / list toggle / source on keys; links column by width | KEEP | keyboard-shortcuts, overflow-menu (actions kept on keys) · Q-Knowledge toolbar | — |
| Knowledge | DG-072 column order, empty group hidden, outgoing links out of column | KEEP | empty-states (no empty headers), visual-hierarchy · Q-Knowledge / H2-Knowledge column | — |
| Knowledge | DG-073 notes newest-first by creation | KEEP | state-preservation (the row being typed in does not jump) · Q-Knowledge order is not alphabetical | — |
| Settings | DG-090 unsheeted rows under "Ещё настройки"; search opens the fold | KEEP | progressive-disclosure, no lost settings · H2/Q-Settings show exactly the sheet rows | — |
| Settings | DG-101 Профиль removed, values kept in JSON | KEEP | no data loss; disabled-states (no inert fields) · X sheets have no Профиль | — |
| Settings | DG-091 eleven X sections + Помощь, Git nav name | KEEP | navigation-consistency, nav-hierarchy · X-Set-* order | — |
| Settings | DG-090 one row layout (label left, options right) | KEEP | consistency, visual-hierarchy · H2-Settings, X-Set-Columns, X-Set-StyleKeys | — |
| Settings | DG-090 quiet = chip-fill switch | KEEP | consistency (one style switch) · X-Set-StyleKeys | — |
| Settings | DG-093 live sign-in state instead of 3 static cards | KEEP | state-clarity; no decorative duplicate of live state · X-Set-Trackers (cards illustrate states) | — |
| Settings | DG-093 one sync cadence for all trackers, Синхронизировать beside | KEEP | honest UI over an invented per-tracker schedule; manual sync kept · X-Set-Trackers | — |
| Settings | DG-093 rows without a function omitted (ask-before-send); "только здесь" | KEEP | disabled-states (no controls that do nothing); external writes off by default · X-Set-Trackers | Follow-up ticket for ask-before-send (as written) |
| Settings | DG-093 MR/PR switches under sheet rows; connection fields folded | KEEP | progressive-disclosure · X-Set-Trackers | — |
| Settings | DG-095 deadline lead "за 24 ч", not 9:00 | KEEP | honest copy (no promise the scheduler cannot keep) · X-Set-CalNotif | — |
| Settings | DG-096 deleted-task retention omitted; snapshot options wired; 90 d kept as 4th option | KEEP | disabled-states; no data loss (stored 90 stays) · X-Set-GitLangAbout / Данные | — |
| Settings | DG-099 Git rows wired, rest folded | KEEP | progressive-disclosure · X-Set-GitLangAbout | — |
| Settings | DG-100 date format = clock format; parser row informative | KEEP | number-formatting (locale), honest copy · X-Set-GitLangAbout | — |
| Settings | DG-102 Помощь three rows, guide in a reader | KEEP | consistent-help · X-Set-GitLangAbout | — |
| Settings | DG-103 channel omitted, shown in section line; check-now kept | KEEP | disabled-states; "только вручную" keeps an escape route · X-Set-GitLangAbout | — |
| Settings | DG-097 one row per action, conflict box under the row | KEEP | error-placement (error next to the field) · X-Set-StyleKeys | — |
| Settings | DG-003 drawn dots / StatusRing until Icon.qml lands | KEEP | icon-style-consistent, no-emoji-icons (interim, vector) | Swap to Icon.qml when it lands (as written) |
| Shell (wave 1) | DG-002 Ctrl \ removed; people in an Archive-People-shaped dialog without "Связанные задачи" / "Встречи" | CHANGE | Removing the key is right (no sheet draws a day panel; DESIGN-GAPS DG-002 "no right panel"). The omission rests on a false premise: lowkey stores person↔task links (`WaitingOn{taskId, personId}`, src/safety/WaitingOn.h) and meeting `attendees` (src/Models.h). Showing them is a fact, not autopilot. content-priority · X-Oth-Archive-People draws both blocks | `qml/PeopleDialog.qml`: add "Связанные задачи" (tasks whose WaitingOn.personId is the person; key + title, Enter opens) and "Встречи" (upcoming events whose attendees name the person: "пт 11:00 · title"); hide a block when empty. `docs/HOTKEYS.md:149`: drop the Ctrl+\ day-panel sentence. |
| Shell (wave 1) | DG-161 archive month = last status change | KEEP | closest stored fact, nothing invented · X-Oth-Archive-People "группа по месяцу" | — |
| Shell (wave 1) | DG-161 no "вернуть U" on the row | CHANGE | The sheet draws "вернуть" on the selected archive row; dropping it hides the archive's main action (primary-action, gesture-alternative). The key objection is valid (keymap rule 2: a bare capital is never written; `u` = Undo), so drop the key, not the action | `qml/TaskListView.qml`: while the query holds `is:archived`, show a quiet "вернуть" text action on the current/hovered row, running the same restore as the task menu / SelectionBar; no key hint (no binding exists). |
| Shell (wave 1) | DG-162 "timeline"/"archive" names open the list | KEEP | deep-linking, back-stack-integrity (saved links never dead) | — |
| Shell (wave 1) | DG-140 one toast, "+N" waiting, ring kinds, key after action | KEEP | ux:Toast Notifications, toast-accessibility, color-not-only (ring shape carries the kind) · X-Ntf-Toasts "не больше одного, остальные в «+N»" | — |
| Shell (wave 1) | DG-005 danger outranks primary | KEEP | destructive-emphasis · X-Dlg-Small dan('Удалить колонку'), X-Menus-Column danger item | — |
| Shell (wave 1) | DG-004 quiet flags derived from chip fill | KEEP | consistency; the seven switches as drawn · X-Set-StyleKeys | — |
| Shell (wave 1) | DG-007 "Example" in RU UI; stored "Пример" kept | KEEP | no data loss; sheets use Example (X-Menus-Other, X-Oth-Capture, X-Set-Columns, X-Dlg-TimeMachine) | — |
| Shell (wave 1) | DG-008 small layout below 1360 px | KEEP | breakpoint-consistency; X-Oth-Small frame is 1280 (its note says ~1100), 1366 laptops keep the full sidebar | — |
| Dialogs | DG-120 non-move edits apply to the series without asking | KEEP | form-autosave, undo-support; the sheet's question is about move/duration/delete · X-Dlg-Event | — |
| Dialogs | DG-120 new meetings only via the one-line input | KEEP | keyboard-first, nothing made without a name · X-Dlg-Event / X-Oth-Capture | — |
| Dialogs | DG-120 location/context/type/custom RRULE kept off-panel, never lost | KEEP | no data loss, progressive-disclosure · X-Dlg-Event | — |
| Dialogs | DG-121 per-item restore via diff links | KEEP | undo-support; X-Dlg-TimeMachine has "Открыть копией…", no per-item list | — |
| Dialogs | DG-121 retention behind one quiet line | KEEP | progressive-disclosure · X-Dlg-TimeMachine | — |
| Dialogs | DG-122 log source by kind; undo only on the newest entry | KEEP | honest data (no invented provider); state-clarity · X-Dlg-Log-Import | — |
| Dialogs | DG-123 next week opens the calendar; "Перенесено" omitted | KEEP | support, not autopilot; no invented counts · X-Dlg-Recap | — |
| Dialogs | DG-124 closed today = count; timer sentence | KEEP | content-priority · X-Dlg-Recap / X-Ntf-Focus | — |
| Dialogs | DG-126 person = name + what to ask | KEEP | redundant-entry (handle derived), stored fields kept · X-Dlg-Small "Человек" | — |
| Dialogs | DG-133 nine X-Keys areas; "Сдвинуть колонку Ctrl Shift H/L" left out | CHANGE | Areas: right. Column move with no key breaks keyboard-first while keymap.md line 81, X-Keys and X-Menus-Column all list it; keymap scopes it "на заголовке колонки", so it can coexist with log Ctrl Shift L (keymap line 108) | Bind column move left/right to Ctrl+Shift+H / Ctrl+Shift+L, active only while the board cursor is on a column header (catalogue in `src/AppController.cpp` ~13600, handler in `qml/Main.qml` board keys); elsewhere Ctrl+Shift+L stays the log. Show the row in `qml/KeyCheatSheet.qml` and the keys in the column menu. |
| Dialogs | DG-132 focus screen under toasts; D done; no empty toast | KEEP | z-index-management; success-feedback only when there is something · X-Ntf-Focus | — |
| Calendar | DG-041 day load moved into the day-name tooltip | CHANGE | Week follows the sheet (no load bar on H2/Q-Calendar), right. But a hover-only fact fails tooltip-keyboard / ux:Hover vs Tap in a keyboard-first app | `qml/WeekView.qml` (day header): show the same load text when the keyboard cursor enters that day (tooltip on cursor, or the bottom hint line), not only on hover. Same for the month meeting-time tooltip (DG-050, `qml/MonthView.qml`). |
| Calendar | DG-041 deadline row = flag + title, +N selects the day | KEEP | consistency with the sheet row · X-Oth-DayMonth ("срок — флажок", "+N ещё") | — |
| Calendar | DG-044 query row hidden at rest, shown when active | KEEP | state-clarity (no hidden active filter) · H2-Calendar has no query row | — |
| Calendar | DG-045 event menu items open the panel / short lists | KEEP | one way per action, nothing made without a name · X-Menus-Other / X-Dlg-Event | — |
| Calendar | DG-050 month order: deadlines & tasks, then meetings | KEEP | keyboard-nav (cursor order = drawn order); the sheet itself is inconsistent (day 8 task last, day 16 task first), deadlines first matches · X-Oth-DayMonth | Tooltip: see DG-041 change |
| Calendar | DG-051 day zoom header and rows | KEEP | visual-hierarchy · X-Oth-DayMonth day view | — |
| Today | DG-010 zero parts left out | KEEP | empty-states, honest copy · H2-Today, H2-Today-Calm, X-Oth-Small | — |
| Today | DG-011 no arrows where sheets have none; keys still work | KEEP | keyboard alternatives kept · H2-First, Q-First, X-Oth-Small | — |
| Today | DG-012 quiet free time = gap; 🔒 removed | KEEP | whitespace-balance, no-emoji-icons · H2-Today-Calm | — |
| Today | DG-013 quiet side = sheet; overdue dim line kept | KEEP | content-priority without hiding facts · H2-Today-Calm, X-Err-Empty | — |
| Today | DG-014 one card + rest as lines | KEEP | content-priority; nothing in progress hidden · H2-Today | — |
| Today | DG-015 "Написал" button / text link | KEEP | style consistency (textLinks) · H2-Today / H2-Today-Calm | — |
| Today | DG-110 "?" key on cards; Enter text hint | KEEP | no text glyphs as icons · H2-First, Q-First | — |
| Today | DG-131 tour removed, guide stays, id kept | KEEP | consistent-help; stored bindings kept · no tour in any sheet | — |
| Today | DG-160 Esc in two steps, filter named | KEEP | escape-routes, state-preservation, ux:No Results (offer the reset) · X-Err-Empty | — |
| Tasks | DG-020 default `is:open` chip | KEEP | state-clarity (visible, removable chip) · H2-Board / H2-List "статус не готово" | — |
| Tasks | DG-020 profile chip without × | KEEP | disabled-states (no dead ×), compact-label-overflow (chip semantics) · H2-Board | — |
| Tasks | DG-020 "Сохранить как вид" always on the bold line | KEEP | consistency (stable placement) · H2-Board | — |
| Tasks | DG-020/046 calendar query line only when it says more | KEEP | state-clarity · H2-Calendar | — |
| Tasks | DG-022 folded Done ignores "не готово" | KEEP | content-priority · H2-Board "Готово 2 · Показать" | — |
| Tasks | DG-021 quiet lens option as an outline chip | KEEP | consistency · Q-List | — |
| Tasks | DG-021 quiet field folds on hand-back only | KEEP | state-preservation (no edits in a hidden field) · Q-List | — |
| Tasks | DG-022 no add-column on the board | KEEP | sheet has none · H2-Board; X-Set-Columns "+ Колонка" | — |
| Tasks | DG-025 column extras as Ctrl K commands | KEEP | overflow-menu, keyboard-first · X-Menus-Column | — |
| Tasks | DG-026 selection-bar extras as Ctrl K commands | KEEP | overflow-menu · X-Menus-Task (selection bar) | — |
| Tasks | DG-027 "Перенести…" out of the task menu; "сейчас" marker | KEEP | one way per action · X-Menus-Task | — |
| Tasks | DG-031 dates without the dot, quiet weekday | KEEP | number-formatting · Q-List / H2-List | — |
| Tasks | DG-150 saved view menu trimmed | KEEP | one way per action · X-Menus-Other | — |
| Tasks | DG-151 profile switcher; delete = one undoable click "Удалить профиль" | CHANGE | Switcher, sync line, Ctrl ] row: right (X-Menus-Other). Delete is not: the sheet labels it "Удалить профиль…" (danger) and X-Dlg-Small draws its confirmation ("Удалить профиль «Платежи»? 87 задач и 12 заметок. Снимок сохранится…"). ux:Confirmation Dialogs (High), confirmation-dialogs; a whole profile is too big for one click | `qml/ProfileSwitcher.qml`: label "Удалить профиль…", danger style; open the X-Dlg-Small confirmation (task/note counts, snapshot note, Отмена + danger "Удалить профиль"); keep Ctrl Z undo after it. Strings in `qml/I18n.qml`. |
| Tasks | DG-152 text field menu trimmed | KEEP | consistency · X-Menus-Other text field menu | — |
| Document | DG-060 panel first, full on Enter | KEEP | state-preservation, back-behavior · X-Ntf-OS / X-Dlg-Event ("панель справа"), H2/Q-Task widths | — |
| Document | DG-061 local layer hidden at rest, one click from "+ свойство"; delete via menu/Del | KEEP | progressive-disclosure, undo-support · H2-Task / Q-Task | — |
| Document | DG-061 CI from gh/glab, История from the log | KEEP | facts only, nothing invented · H2-Task | — |
| Document | DG-063 "Сохранено" state at rest / "сохраняю…" | KEEP | submit-feedback, form-autosave · H2-Task | — |
| Document | DG-065 quiet Готово, timer text link | KEEP | primary-action subdued in quiet · Q-Task | — |
| Document | DG-080/082 bold chips tinted by signal, quiet outline | KEEP | color-not-only (text kept), consistency · H2-Command | — |
| Document | DG-081 command line matches by name only | KEEP | content-priority; full text one Enter away · H2-Command / Q-Command | — |
| Document | DG-082/083 "?" toggle removed, card by width | KEEP | progressive-disclosure · H2-Command / Q-Command | — |
| Document | DG-130 "встреча" as a chip; Enter/Esc | KEEP | nothing put in the calendar without a click (support, not autopilot); keyboard-first · X-Oth-Capture | — |
| Document | DG-003 ⤢/⤡ as expand/collapse line icons | KEEP | icon-style-consistent, no-emoji-icons | — |

## CHANGE items

1. **DG-002 people dialog**: add "Связанные задачи" (WaitingOn) and "Встречи" (attendees) to
   `qml/PeopleDialog.qml`, hidden when empty; remove the Ctrl+\ sentence from `docs/HOTKEYS.md`.
2. **DG-161 archive row**: restore the sheet's "вернуть" row action in `qml/TaskListView.qml`
   (only under `is:archived`), no key hint.
3. **DG-133 column move**: Ctrl+Shift+H/L on a column header (scoped; the log keeps
   Ctrl+Shift+L elsewhere); catalogue in `src/AppController.cpp`, handler in `qml/Main.qml`, row
   in `qml/KeyCheatSheet.qml`.
4. **DG-151 profile delete**: "Удалить профиль…" + the X-Dlg-Small confirmation in
   `qml/ProfileSwitcher.qml`, undo kept.
5. **DG-041 / DG-050 tooltips**: day load (week) and meeting time (month) also shown when the
   keyboard cursor is on the day / item, not on hover only.
