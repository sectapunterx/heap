# Design gaps 0.8.1 — re-inventory r3

Branch `heap2/0.8.1` at 77388de. Fresh, independent pass: every sheet in `New heap design/screens` (H2-/N- bold, Q-/X- quiet; PNG + .dc.html copy) compared side by side with offscreen captures of the real `Main.qml` (QuickTest harness, isolated profiles, seeded working day with meetings and planned tasks, calendars at 09:00; 1440×900, 1280×720 for X-Oth-Small, light theme for X-Oth-Light; menus, dialogs, toasts, empty/error states, first run, sync/trackers). Site: `heap-site-2` prototype vs built `site/`. Earlier reports were context only.

Not gaps (accepted): `docs/DESIGN-DECISIONS.md`, KEEP rows of `docs/DESIGN-DECISIONS-REVIEW.md`, owner decisions (one detail line on bold cards, sort chip, recap line on Today, lavender accent options, "только здесь", Ctrl F = filter, tone, bold is the default style). Fix-Hotkeys and the "h." mark in X-Oth-Small are outdated sheets.

Severity: **S** wrong structure / legacy component / broken · **A** clearly off from the sheet · **B** visible detail · **C** minor · **D** cosmetic nit. "(code)" = state not captured, judged from QML.

Captures: `C:/Users/Fin/AppData/Local/Temp/claude/C--Users-Fin-CLionProjects-todolist/94cfdb4b-65f9-46d8-b85c-958b3a86d2cd/scratchpad/r3gap` (`bold-*` / `quiet-*` / `t-*` tracker seed; `sites/` for the site).

## Summary

| S | A | B | C | D | total |
|---|---|---|---|---|---|
| 1 | 13 | 69 | 68 | 13 | 164 |

### S — structure / broken

- **R3-017** (Focus mode and launch (N-Ntf-Focus, X-Ntf-Focus)) — sheet: splash = "lowkey" wordmark + version "0.8.0" only → app: legacy brand-book splash (grid canvas, accent glow, tagline "Quiet by default.", gradient loading bar, fake "$ initializing allocator…" line, "V0.8.x" / "STABLE · CHANNEL" footer rail) shown on…

### A — clearly off

- **R3-001** (Today (H2-Today, H2-Today-Calm)) — sheet: "Сроки" (bold: APP-105 "сегодня" + APP-101 "завтра") / "Срок сегодня" (quiet) list the due task even though it is also planned in the day → app: the section disappears whenever the due task has a block in today's plan, while the facts line still says…
- **R3-013** (Small window (N-Oth-Small, X-Oth-Small)) — "Срок сегодня" column missing — same root cause as Today (planned due task skipped) · files: src/AppController.cpp
- **R3-018** (Focus mode and launch (N-Ntf-Focus, X-Ntf-Focus)) — sheet: launch card "Прошлый раз lowkey закрылся неожиданно · Данные целы — последнее сохранение 15:58. Отправить отчёт о сбое разработчику? · Посмотреть отчёт · Не отправлять" → app: no unclean-exit detection or card (code) · files: (missing) qml/Main.qml, …
- **R3-048** (Column & calendar menus (N-Menus-Column, X-Menus-Column)) — (code) sheet: calendar task block menu = Открыть, Готово, Перенести… s, Длительность… Ctrl Shift J/K, "Убрать из календаря · останется задачей" → app: the full generic task menu (TaskMenuHost) on a block; no duration or unplan row · files: qml/WeekView.qml,…
- **R3-054** (Multi-select & drag (N-Oth-Select-Drag, X-Oth-Select-Drag)) — (code) sheet: undated task dragged onto the calendar shows a dashed block sized by the estimate, "14:00–15:00 · по оценке 1 ч" → app: a 2px accent line at the pointer and a small title ghost · files: qml/WeekView.qml, qml/UndatedTray.qml
- **R3-066** (Schedule / deadline field (N-Dlg-Schedule, X-Dlg-Schedule)) — sheet: "Маленькое поле у карточки" — the popup sits right under the card it was opened from (card title visible above it) → app: popup centred on the window at 1/4 height, covering the card and neighbours; nothing says which task is being scheduled for a si…
- **R3-067** (Schedule / deadline field (N-Dlg-Schedule, X-Dlg-Schedule)) — sheet: overlap state hint "↵ всё равно поставить · ↓ ближайшее окно 12:00" (offers the next free slot) → app: same hint as the normal state "↵ поставить · Tab календарь · Esc отмена"; no nearest-free-window line or ↓ action · files: qml/SchedulePopup.qml
- **R3-068** (Schedule / deadline field (N-Dlg-Schedule, X-Dlg-Schedule)) — sheet: Tab picker = month grid + right column "пт, 9 окт · свободно" with hour slots (busy hour "занято"), "без времени · весь день" → app: generic DatePickerPopup with no time column, extra 6th week row and a "Сегодня" button; picks a date only · files: qm…
- **R3-080** (Log & import (N-Dlg-Log-Import, X-Dlg-Log-Import)) — sheet: "Импорт профиля (JSON)" preview card — file · version · counts, radio "Новым профилем «work»" / "Слить с «Example» — совпадающие ID не затираются…", Импортировать → app: picking a file in the OS dialog imports straight away, no preview and no new/mer…
- **R3-103** (Other menus (N-Menus-Other, X-Menus-Other)) — (code) sheet tray menu: header "lowkey", Новая задача… Ctrl Shift Space, Быстрая заметка… Ctrl Shift N, Остановить … timer line, "Далее: 11:00 1:1 с Олегом", Открыть lowkey, Не беспокоить 1 ч, Выход → app: native QMenu with two hard-coded English items "Sho…
- **R3-131** (Пустые состояния и особые случаи (N-Err-Empty, X-Err-Empty)) — sheet: empty board = one plain centred line "Задач пока нет" + "Ctrl N — новая · или подключите трекер" → app: the old card (bordered panel, board icon, "Пока нет задач", two-line hint "Нажмите Ctrl+N, чтобы добавить первую задачу, или откройте быстрый ввод…
- **R3-137** (Пустые состояния и особые случаи (N-Err-Empty, X-Err-Empty)) — sheet: D with no Done-stage column opens a card "Некуда отметить готовой" / "Ни у одной колонки нет этапа «Готово»." with [Создать колонку «Готово»] (primary) and [Выбрать этап у колонки…] → app (code): a toast "Нет колонки этапа «Готово» — создать?" with a…
- **R3-147** (Конфликт синка и запись в трекер (N-Dlg-Conflict, X-Dlg-Conflict)) — sheet: with tracker writes on, a pre-send card "Отправить статус в Jira?" / "APP-101 · <title>" / "В работе → Done" / checkbox "Больше не спрашивать для Jira" / [Только у меня] [Отправить] → app (code): no such dialog and no "don't ask again" setting; only …

### B — visible detail

- **R3-002** (Today (H2-Today, H2-Today-Calm)) — sheet: the waiting reason is shown: bold Сроки "APP-105 · заблокировано: ждёт ответа платёжки", quiet day row "APP-105 · 1 ч · ждёт ответа платёжки", quiet Срок row sub "ждёт ответа платёжки" → app: bold only "заблокировано", quiet day row and Срок row have…
- **R3-012** (First run (H2-First, Q-First)) — (no sheet) "С чего начать" guide reader looks legacy: mono "Справка lowkey" heading, accent "?" tile, card inside card, mono "Оглавление" · files: qml/HelpContent.qml, qml/SettingsView.qml (helpReader)
- **R3-014** (Small window (N-Oth-Small, X-Oth-Small)) — sheet: the three stacked side columns are packed at natural width (В работе / Срок сегодня / Кому написать ~265 px apart) → app: columns fill equal shares (В работе at x=80, Кому написать at x=680) · files: qml/TodayView.qml (side grid, stacked fillWidth)
- **R3-015** (Small window (N-Oth-Small, X-Oth-Small)) — sheet: folded sidebar has only Сегодня / Задачи / Знания (+ settings) → app: adds a divider and 4 numbered saved-view bookmark icons · files: qml/Sidebar.qml (ViewRow folded)
- **R3-019** (Focus mode and launch (N-Ntf-Focus, X-Ntf-Focus)) — sheet (bold): timer "● 0:42" orange dot + orange clock, "следующая встреча через …" in accent → app: bold identical to quiet (white clock, no dot, dim grey next-meeting) · files: qml/ImmersionView.qml
- **R3-025** (OS notifications, timer, update (N-Ntf-OS, X-Ntf-OS)) — sheet: meeting "1:1 с Олегом через 5 мин" / "11:00–11:30 · Zoom", buttons "Подключиться" · "Через 5 мин" → app: title "Через 5 мин", body = meeting title only, buttons snooze short · snooze long · Открыть, no join (code) · files: src/AppController.cpp:15395…
- **R3-026** (OS notifications, timer, update (N-Ntf-OS, X-Ntf-OS)) — sheet: deadline "Срок сегодня" / "Оформление заказа: таймаут 10 с · ждёт платёжки", one button "Открыть" → app: "Дедлайн через N ч" / "title (P1)", 4 buttons (2 snoozes, Открыть, Готово) (code) · files: src/AppController.cpp:15325-15333, src/AppControllerPr…
- **R3-027** (OS notifications, timer, update (N-Ntf-OS, X-Ntf-OS)) — sheet: running timer also in the tray menu and tray tooltip "lowkey · 0:42 Обход…" → app: tooltip static "lowkey", menu only "Show lowkey" / "Quit" (English in Russian UI), no timer (code) · files: src/notify/NotificationCenter_tray.cpp
- **R3-030** (Tasks · Board (H2-Board, Q-Board)) — sheet: priority mark only P0/P1 on bold cards (P2/P3 blank), only P0 on quiet cards → app: grey P2/P3 on every bold card, P1 on quiet cards (same on quiet list rows, Q-List) · files: qml/TaskCard.qml, qml/TaskListView.qml
- **R3-032** (Tasks · Board (H2-Board, Q-Board)) — sheet Q: lens tabs 14px, inactive #8f99a6, 20px apart, 28px after the title, on the title's baseline → app: ~13px, inactive near-white, ~12px apart, close to the title and sitting above its baseline · files: qml/LensTabs.qml
- **R3-034** (Tasks · List (H2-List, Q-List)) — sheet: group headers 15px/600 bold (14px/500 #c4ccd6 quiet), header + rows inset 8px (10px quiet) from the query bar edge → app: ~13px headers, rows and headers flush with the edge (ring at x236 vs 244 / 256 vs 266) · files: qml/TaskListView.qml
- **R3-037** (Task document (H2-Task, Q-Task)) — sheet: title, body and chips share one left edge (248 bold / 256 quiet) → app: title inset ~5px and body ~8px further right than the chips/breadcrumb · files: qml/TaskDocument.qml, qml/MdBlockEditor.qml
- **R3-038** (Task document (H2-Task, Q-Task)) — sheet: body 15px, line-height 1.65, #d7dde5 → app: ~14px, line-height ~1.2, #e9edf2; paragraphs read dense · files: qml/MdBlockEditor.qml
- **R3-041** (Task menu (N-Menus-Task, X-Menus-Task)) — sheet: item labels start on the header's left edge → app: every AppMenuItem reserves an empty check/glyph column, labels sit ~21px right of the header (all menus: task, column, stage, person, saved view) · files: qml/AppMenuItem.qml
- **R3-042** (Task menu (N-Menus-Task, X-Menus-Task)) — sheet: submenu header "‹ Приоритет" / "‹ Колонка" is the small grey header line → app: a normal white row, same size as the items · files: qml/TaskMenuHost.qml, qml/AppMenuItem.qml
- **R3-043** (Task menu (N-Menus-Task, X-Menus-Task)) — sheet N: "P0 · срочно" red 600, P1 amber in the priority list → app: all rows plain · files: qml/TaskMenuHost.qml
- **R3-044** (Task menu (N-Menus-Task, X-Menus-Task)) — sheet: column list has no number keys, separator before "Готово" with key d → app: 1–7 on every row, no separator, Готово without d · files: qml/TaskMenuHost.qml
- **R3-045** (Task menu (N-Menus-Task, X-Menus-Task)) — sheet X: danger items ("Удалить", "Скрыть из lowkey", "Удалить колонку…") in muted #d8a09c → app quiet: same bright #ef6b63 as bold (also X-Menus-Column, X-Menus-Other) · files: qml/AppMenuItem.qml, qml/Theme.qml
- **R3-046** (Task menu (N-Menus-Task, X-Menus-Task)) — (code) sheet tracker menu: Открыть, Открыть в GitHub, Готово / Мой приоритет, Мой срок, Запланировать / Копировать ссылку, Обновить из GitHub / Скрыть из lowkey, disabled "Удалить · из трекера не удаляем" → app: "Обновить из GitHub" and the disabled Удалить…
- **R3-049** (Multi-select & drag (N-Oth-Select-Drag, X-Oth-Select-Drag)) — sheet N: target column framed 1.5px blue #7aa7ff, insertion line orange #f2a65a; X: frame 1px #4a525d, line #c4ccd6 → app: lavender accent frame 2px and lavender line in both styles · files: qml/KanbanBoard.qml
- **R3-050** (Multi-select & drag (N-Oth-Select-Drag, X-Oth-Select-Drag)) — sheet: target frame hugs the column's cards → app: frame runs to the bottom of the window · files: qml/KanbanBoard.qml
- **R3-051** (Multi-select & drag (N-Oth-Select-Drag, X-Oth-Select-Drag)) — sheet: the card's origin keeps a dashed, 35%-opacity placeholder → app: an empty gap · files: qml/KanbanBoard.qml
- **R3-053** (Multi-select & drag (N-Oth-Select-Drag, X-Oth-Select-Drag)) — (code) sheet: folded Done under the pointer becomes a tall framed strip, ring + "Готово" + "отпустите" centred → app: only the top label swaps "Показать" → "отпустите" with a ring outline round the 88px column · files: qml/KanbanBoard.qml
- **R3-055** (Archive & people (N-Oth-Archive-People, X-Oth-Archive-People)) — sheet: archive row = ring, title, then "APP-111 · 6 окт" muted at the right → app: the plain list row (key column on the left, no date) · files: qml/TaskListView.qml
- **R3-056** (Archive & people (N-Oth-Archive-People, X-Oth-Archive-People)) — sheet: month group header carries the count ("Октябрь 6") → app: month groups have no count; a hand-archived task with no status change lands in "Без даты" under "по месяцу" · files: qml/TaskListView.qml
- **R3-057** (Archive & people (N-Oth-Archive-People, X-Oth-Archive-People)) — sheet: state on the right "• ждёт", "написал вчера", "ответила" → app: "написать", "написал" (no when), "ответил" · files: qml/PeopleDialog.qml, qml/I18n.qml
- **R3-063** (Meeting panel (N-Dlg-Event, X-Dlg-Event)) — sheet: bold title "1:1 с Олегом" 22px/600 → app: title at Medium (fwTitle) in bold style · files: qml/EventEditor.qml (titleField font.weight)
- **R3-064** (Meeting panel (N-Dlg-Event, X-Dlg-Event)) — sheet: one-line input "Ретро спринта" plain + parsed words "пт 16:00 на 1 ч", "каждые 2 недели" tinted (#a9c3dd), regular weight → app: whole line one colour, Medium weight, no tint on recognised words · files: qml/EventCapture.qml
- **R3-069** (Schedule / deadline field (N-Dlg-Schedule, X-Dlg-Schedule)) — sheet (bold): overlap result line orange (#f2a65a), unknown-date line red (#ef6b63) → app: overlap in normal text colour, unknown in muted grey (quiet grey is correct) · files: qml/SchedulePopup.qml (schedule-result color)
- **R3-070** (Schedule / deadline field (N-Dlg-Schedule, X-Dlg-Schedule)) — sheet picker: today = orange underline, chosen day = outlined box, title "Октябрь 2026" left with ‹ › at right → app: chosen day filled lavender, today filled grey, lowercase centred "октябрь 2026" between arrows · files: qml/DatePickerPopup.qml
- **R3-072** (Recap, end of day, standup (N-Dlg-Recap, X-Dlg-Recap)) — sheet: standup is prose lines "Вчера: закрыл APP-111, APP-112." / "Сегодня: …" / "Блокеры: …" → app: headings with "- " bullet lists, and an empty day reads "- —" · files: qml/StandupDraftDialog.qml (+ draft builder in src/)
- **R3-073** (Recap, end of day, standup (N-Dlg-Recap, X-Dlg-Recap)) — sheet (bold): one filled white main button per dialog — "Копировать" (standup), "Перенести" (series question), "Восстановить эту версию…" (time machine), "Импортировать" (import) → app: all outlined (PillButton primary is outline only; `solid` exists but is…
- **R3-075** (Small dialogs & confirmations (N-Dlg-Small, X-Dlg-Small)) — sheet: "Новый профиль" 8 muted swatches (#8aa4c2, #7fae9a, #b49cc8, #c2a27a, #c48e8a, #9aa4b1, #6f8fa8, #a3a86e) → app: saturated cyan/blue/purple/red/orange/yellow/green · files: qml/ProfileEditor.qml (Theme.swatches / ThemePresets.js SWATCHES)
- **R3-076** (Small dialogs & confirmations (N-Dlg-Small, X-Dlg-Small)) — sheet: "Открыть ссылку в браузере?" + "Ссылка из задачи ведёт на внешний сайт." + labelled "Адрес" field (mono) + Копировать / Открыть, asked for external web links → app: "Открыть ссылку?" "Это не веб-страница…", bare URL text, Отмена / red "Всё равно откр…
- **R3-077** (Small dialogs & confirmations (N-Dlg-Small, X-Dlg-Small)) — sheet: "Сохранить как вид" name prefilled as readable "Заблокировано · P0" → app: name prefilled with the raw query "статус:заблокировано p0" · files: qml/SavedViewNameDialog.qml
- **R3-079** (Time machine (N-Dlg-TimeMachine, X-Dlg-TimeMachine)) — sheet (bold): selected snapshot row filled (#262d37) with a 2px light bar on the left; quiet filled #1b2027 → app: filled + lavender focus-ring outline round the whole row, no left bar · files: qml/TimeMachineDialog.qml (snapRow border = focusRing)
- **R3-081** (Log & import (N-Dlg-Log-Import, X-Dlg-Log-Import)) — sheet: — → app: the JSON file dialog filter reads "heap. profile (*.json)", the old brand (code) · files: qml/Main.qml (importJsonDialog nameFilters)
- **R3-083** (Knowledge (H2-Knowledge, Q-Knowledge)) — sheet: body paragraphs and lists start flush with the title/heading x (512 bold / 496 quiet), line-height ~1.7 so a paragraph wraps to 2 airy lines, ~16px gap between blocks → app: paragraph text indented ~8px right of the heading, tight single line-height,…
- **R3-084** (Knowledge (H2-Knowledge, Q-Knowledge)) — sheet: heading scale per style — note title 30 bold (H2) / 28 semibold (Q); "##" 17 bold (H2) / 15 semibold (Q) → app: one fixed scale [24,20,17…] in both styles: title ~24, "##" 20 bold, so section headings are louder than the sheet and the title smaller; …
- **R3-085** (Knowledge (H2-Knowledge, Q-Knowledge)) — sheet Q-Knowledge: task refs inline read as underlined text "◑ APP-101" (no pill); RFC 6585 plain, not underlined → app quiet: task refs are filled pills (same as bold) and the external link is underlined · files: qml/MdView.qml, qml/NotesView.qml
- **R3-086** (Knowledge (H2-Knowledge, Q-Knowledge)) — sheet Q-Knowledge: inline code is a hairline-stroked pill (R2-020 says quiet strokes) → app quiet: inline code drawn as a fill, no stroke · files: qml/MdView.qml (InlineCodeFrames), Style.chipFill
- **R3-088** (Knowledge (H2-Knowledge, Q-Knowledge)) — sheet H2: links column headers semibold 12, entries 13 medium with the ID bold and "· В работе" dimmed → app: headers regular-weight look, entries fsSm (~12) regular, ID not bold, status barely dimmer · files: qml/NotesView.qml (LinksHeader/LinksItem ~1097)
- **R3-089** (Knowledge (H2-Knowledge, Q-Knowledge)) — sheet: pinned "OpenAPI нашего бэкенда" tagged API → app: tag is the first word cut to 4 chars → "Open" (any ref whose first word is not a short code gets a broken tag) · files: qml/NotesListPane.qml:61 (_splitRef), :530
- **R3-092** (Knowledge — inserts and "/" menu (N-Oth-Knowledge, X-Oth-Knowledge)) — sheet: "one editor, no modes": typing "/" on a new line shows just "/|" in place, block keeps its rendered position → app: the edited block turns into a bordered panel-filled text box showing raw markdown (`Retry-After` backticks), the paragraph and the new…
- **R3-093** (Knowledge — inserts and "/" menu (N-Oth-Knowledge, X-Oth-Knowledge)) — sheet "/" menu: labels start ~16px from the panel edge, menu ~290px wide → app: an empty ~20px check/glyph column before every label (same in all AppMenu menus, see Menus), menu ~205px · files: qml/AppMenuItem.qml (contentItem check column), qml/MdBlockEdit…
- **R3-094** (Knowledge — inserts and "/" menu (N-Oth-Knowledge, X-Oth-Knowledge)) — (code) sheet: image block with a caption line under it ("Повторы с экспоненциальной паузой") → app: image rows render no caption/alt line · files: qml/MdView.qml (imageRow/localImage)
- **R3-095** (Knowledge — inserts and "/" menu (N-Oth-Knowledge, X-Oth-Knowledge)) — (code) sheet Git line: "работаю над APP-101 · fix/login-throttle · PR #482 · CI прошёл ×", note "(выключена по умолчанию)" → app: copy "В работе %1", and `git.workingOnLine` defaults to on · files: qml/I18n.qml:2705 (topbar.git.workingOn), qml/Theme.qml:35,…
- **R3-096** (Quick capture over other windows (N-Oth-Capture, X-Oth-Capture)) — sheet: task capture header "lowkey  новая задача" (wordmark + label, like the quick note) → app: only "новая задача", no wordmark · files: qml/QuickCapturePopup.qml:486
- **R3-097** (Quick capture over other windows (N-Oth-Capture, X-Oth-Capture)) — (code) sheet: footer right "из ветки fix/APP-105 — связать?" (offer to link the branch's task) → app: no branch hint in the task capture at all · files: qml/QuickCapturePopup.qml
- **R3-098** (Quick capture over other windows (N-Oth-Capture, X-Oth-Capture)) — sheet: input 16px medium white, tokens "завтра 11:00 p1" all in accent; chips ~26px tall, 13px ("когда пт, 9 окт · 11:00") → app: input ~14px light, p1 coloured as priority (orange in bold) not accent; chips ~22px, 11px, value "завтра, вс, 11 окт, 11:00 ×" …
- **R3-101** (Other menus (N-Menus-Other, X-Menus-Other)) — sheet: menu labels start at the row's left padding (~16px) → app: every AppMenuItem reserves an always-on check/glyph column (fsMd + spMd ≈ 22px) so labels sit ~38px in, a blank gutter on menus with no checks (saved view, profile, note, person, text field, …
- **R3-102** (Other menus (N-Menus-Other, X-Menus-Other)) — sheet X-Menus-Other (quiet): highlighted row is a plain fill with no edge marker; danger items in a muted salmon → app quiet: same 3px accent marker and bright red danger as bold · files: qml/AppMenuItem.qml:186 (menu-row-marker), :142 (Theme.danger)
- **R3-106** (Command line (H2-Command, Q-Command)) — sheet H2: "Снять блокировку → В работу" → app: "Снять блокировку → В работе" (status name dropped in raw, not the accusative) · files: qml/I18n.qml:3527 (cmd.unblock)
- **R3-111** (Key cheat sheet (N-Keys, X-Keys)) — sheet: key caps are filled chips (panel fill, bright medium mono) → app: hairline-outlined caps with dim light mono · files: qml/KeyCheatSheet.qml, qml/KeyHint.qml
- **R3-112** (Key cheat sheet (N-Keys, X-Keys)) — sheet: areas in a fixed 4-column grid by rows (Движение | Перейти | Задача | Переместить, then Скопировать | Выделение | Вид | Поиск, then Изменилось в 0.8.0) → app: areas packed masonry-style into 4 columns (Скопировать under Движение, Выделение under Пере…
- **R3-118** (Style & keys (N-Set-StyleKeys, X-Set-StyleKeys)) — sheet: block heading "Изменить сочетания", sub "Отдельный режим; шпаргалка «?» остаётся только для чтения" → app: heading "Клавиши", sub "Щёлкните по клавише, чтобы сменить; шпаргалка «?» остаётся только для чтения" · files: qml/I18n.qml (settings.section.s…
- **R3-127** (Trackers (N-Set-Trackers, X-Set-Trackers)) — sheet: status-mapping dropdown is a compact pill with the column's stage ring + name + small caret, note "не распознан — выбрано по умолчанию" in full → app: wide plain AppComboBox without the stage ring; the note is elided "не распознан — выбрано по…" · fi…
- **R3-128** (Trackers (N-Set-Trackers, X-Set-Trackers)) — sheet: detail column starts at one fixed x beside a fixed-width list → app: detail x jumps between trackers (GitHub detail at ~728px, Jira at ~657px) because the list column (preferredWidth 170) grows/shrinks with the state text · files: qml/SettingsView.qm…
- **R3-132** (Пустые состояния и особые случаи (N-Err-Empty, X-Err-Empty)) — sheet: empty list "Задач пока нет" + dim line "Ctrl N — новая · или подключите трекер" → app: title only, no second line · files: qml/TaskListView.qml:497, qml/I18n.qml (list.empty)
- **R3-133** (Пустые состояния и особые случаи (N-Err-Empty, X-Err-Empty)) — sheet: empty week "На этой неделе ничего не запланировано" / "S на задаче — поставить на день" → app (code): icon + "На этой неделе пусто" + long hint "Здесь появляются задачи с датой и события. Кликните…"; same old pattern in month ("В этом месяце пусто" +…
- **R3-134** (Пустые состояния и особые случаи (N-Err-Empty, X-Err-Empty)) — sheet: empty Knowledge "Заметок пока нет" / "Ctrl Alt N — первая · импорт Markdown" → app: no notes section and no empty message at all (pinned links and snippets are listed, the right pane shows a blank "Заметка" editor with a placeholder); notes.empty cop…
- **R3-135** (Пустые состояния и особые случаи (N-Err-Empty, X-Err-Empty)) — sheet: palette with nothing found = centred "Ничего не нашлось по «релиз пятн»" + dim "↵ — создать задачу «релиз пятн»" → app: one selectable row "Ничего · создать задачу «релиз пятн»" with ↵ on the right · files: qml/CommandPalette.qml, qml/I18n.qml (cmd.c…
- **R3-136** (Пустые состояния и особые случаи (N-Err-Empty, X-Err-Empty)) — sheet: "Ничего под «заблокировано · p0»" → app: a key typed in Russian ("статус:заблокировано") is read as an unknown key and shows as "где заблокировано · p0 · zzz" · files: qml/QueryWords.js (clause: keys map is English only)
- **R3-138** (Пустые состояния и особые случаи (N-Err-Empty, X-Err-Empty)) — sheet: a task whose column was deleted shows a dashed "?" ring + "колонка «На паузе» удалена · перенести…" (underlined link) → app (code): StatusRing has the "orphan" look, but nothing ever sets that category and there is no "удалена · перенести…" line · fi…
- **R3-140** (Сохранение, восстановление, сбой (N-Err-Storage, X-Err-Storage)) — sheet: keychain card has the dim eyebrow "Хранилище ключей ОС недоступно" above the title → app: no eyebrow (the keychain.eyebrow key exists but nothing uses it) · files: qml/KeychainDialog.qml, qml/I18n.qml
- **R3-144** (Ошибки трекеров (N-Err-Tracker, X-Err-Tracker)) — sheet: tracker marks ("ждёт отправки статуса", "вне фильтра Jira — только у вас", "удалён в Jira · оставить у себя / убрать", "изменён и у вас, и в Jira · решить") → app: they appear on board cards only; list rows show the same tasks with no mark, no edge a…
- **R3-148** (Конфликт синка и запись в трекер (N-Dlg-Conflict, X-Dlg-Conflict)) — sheet: row label "Название" → app: "Заголовок" · files: qml/I18n.qml (ticket.conflict.title), qml/SyncConflictDialog.qml
- **R3-149** (Конфликт синка и запись в трекер (N-Dlg-Conflict, X-Dlg-Conflict)) — sheet: "Тикет вне вашего фильтра Jira." / "…в Jira от вашего имени" → app (bold-confirm-push): "Тикет вне вашего фильтра jira." / "в jira": the raw provider id leaks when the provider descriptor is missing · files: src/AppController.cpp:3074 (d ? d->display…
- **R3-151** (Landing, ru + en, desktop + mobile (heap-site-2 index / ru)) — sheet: Git heading «нужная задача уже подсвечена» / "the task is already marked" → app: the heading is kept, but the reworked scene no longer highlights the card (the top bar names the task; the card is not marked). PROMISES #14 is still an open **gap** (re…

## Per sheet

### Today (H2-Today, H2-Today-Calm)

captures: bold-today, quiet-today, bold-today-mon, bold-x-today-fri, quiet-x-today-fri, t-bold-sync-popover (control: Сроки shows there)

- **R3-001** [A] sheet: "Сроки" (bold: APP-105 "сегодня" + APP-101 "завтра") / "Срок сегодня" (quiet) list the due task even though it is also planned in the day → app: the section disappears whenever the due task has a block in today's plan, while the facts line still says "1 срок истекает сегодня / 1 срок сегодня". Real gap, not data: todayData() skips deadlines with `!inDay.contains(t.id)` (AppController.cpp:4493); with the tracker seed (tasks not planned in the day) the section does appear. Also affects N/X-Oth-Small "Срок сегодня" column · files: src/AppController.cpp, qml/TodayView.qml
- **R3-002** [B] sheet: the waiting reason is shown: bold Сроки "APP-105 · заблокировано: ждёт ответа платёжки", quiet day row "APP-105 · 1 ч · ждёт ответа платёжки", quiet Срок row sub "ждёт ответа платёжки" → app: bold only "заблокировано", quiet day row and Срок row have no reason (todayData deadlines/blocks carry no waitingOn text) · files: qml/TodayView.qml (_sub, deadlines sub), src/AppController.cpp
- **R3-003** [C] sheet: the day ends with "18:30 Конец рабочего дня в 19:00" (end row at the last block's end, no free window before it) → app: "18:30 Свободно 30 мин" then "19:00 Конец рабочего дня в 19:00" · files: qml/TodayView.qml (rows)
- **R3-004** [C] sheet: side groups ~40 px apart; quiet side titles medium weight → app: ~24 px apart, quiet side titles regular weight · files: qml/TodayView.qml
- **R3-005** [C] sheet (quiet): fold marker "▶ Кому написать · 2" filled triangle → app: "›" chevron · files: qml/TodayView.qml
- **R3-006** [C] sheet (bold): profile chip "● Example" — dot before the name → app: "Example ●" dot after the name · files: qml/ProfileSwitcher.qml
- **R3-007** [D] (another day, bold-x-today-fri) eyebrow repeats the date already in the title ("пятница, 9 октября" over "Пятница, 9 октября"); bold empty day shows both "в «Задачах» 3 без даты" and the footer "3 задачи без даты — посмотреть и решить" · files: qml/TodayView.qml

### First run (H2-First, Q-First)

captures: bold-first-today, quiet-first-today, bold-first-light-today, quiet-first-1280, bold-guide, quiet-first-guide

- **R3-008** [C] sheet (H2-First): placeholder "например:" dim + "подготовить демо в пятницу 12:00 p1" in text colour → app: whole placeholder dim · files: qml/FirstRunHero.qml
- **R3-009** [C] sheet (H2-First): sidebar on first run shows only "Ctrl N" — no Ctrl 1/2/3, no "Ctrl ,", no "Ctrl K — всё остальное" footer → app: all key hints and the footer shown · files: qml/Sidebar.qml
- **R3-010** [C] sheet: profile "Личное" → app (Russian UI): "Personal" — starting profile named by tr_("profile.personal") before the language applies (may be harness) · files: src/AppController.cpp (makeStartingProfile)
- **R3-011** [D] sheet (Q-First): "Ctrl K" and "?" in mono 12px, links 18 px apart → app: UI font, links ~12 px apart · files: qml/FirstRunHero.qml
- **R3-012** [B] (no sheet) "С чего начать" guide reader looks legacy: mono "Справка lowkey" heading, accent "?" tile, card inside card, mono "Оглавление" · files: qml/HelpContent.qml, qml/SettingsView.qml (helpReader)

### Small window (N-Oth-Small, X-Oth-Small)

captures: bold-1280-today, quiet-1280-today (others bold/quiet-1280-* glanced)

- **R3-013** [A] "Срок сегодня" column missing — same root cause as Today (planned due task skipped) · files: src/AppController.cpp
- **R3-014** [B] sheet: the three stacked side columns are packed at natural width (В работе / Срок сегодня / Кому написать ~265 px apart) → app: columns fill equal shares (В работе at x=80, Кому написать at x=680) · files: qml/TodayView.qml (side grid, stacked fillWidth)
- **R3-015** [B] sheet: folded sidebar has only Сегодня / Задачи / Знания (+ settings) → app: adds a divider and 4 numbered saved-view bookmark icons · files: qml/Sidebar.qml (ViewRow folded)
- **R3-016** [C] sheet: active folded section = filled tile behind the icon → app: underline bar under the icon · files: qml/Sidebar.qml (NavRow/CursorBar)

### Light theme (N-Oth-Light, X-Oth-Light)

captures: bold-light-today, quiet-light-today, bold-first-light-today, quiet-first-light-today

- no gaps

### Focus mode and launch (N-Ntf-Focus, X-Ntf-Focus)

captures: bold-immersion, quiet-immersion

- **R3-017** [S] sheet: splash = "lowkey" wordmark + version "0.8.0" only → app: legacy brand-book splash (grid canvas, accent glow, tagline "Quiet by default.", gradient loading bar, fake "$ initializing allocator…" line, "V0.8.x" / "STABLE · CHANNEL" footer rail) shown on every launch (code) · files: qml/SplashScreen.qml, qml/Main.qml
- **R3-018** [A] sheet: launch card "Прошлый раз lowkey закрылся неожиданно · Данные целы — последнее сохранение 15:58. Отправить отчёт о сбое разработчику? · Посмотреть отчёт · Не отправлять" → app: no unclean-exit detection or card (code) · files: (missing) qml/Main.qml, src/AppController.cpp
- **R3-019** [B] sheet (bold): timer "● 0:42" orange dot + orange clock, "следующая встреча через …" in accent → app: bold identical to quiet (white clock, no dot, dim grey next-meeting) · files: qml/ImmersionView.qml

### Toasts and sync indicator (N-Ntf-Toasts, X-Ntf-Toasts)

captures: bold-toast, quiet-toast, bold-toast-done, quiet-toast-done, bold-e-hiddentoast, quiet-e-hiddentoast, t-bold/quiet-sync-synced/-error/-offline/-popover

- **R3-020** [C] sheet: fact + dim detail "Создано TASK-3  пт 15:00 · К выполнению" → app: one single-colour message Text, no dim detail part · files: qml/Toast.qml
- **R3-021** [C] sheet: stacked "Готово: 3 задачи  +2 события  Журнал Ctrl Shift L" → app: "+2" only, no "события", no Журнал action · files: qml/Toast.qml
- **R3-022** [C] sheet: long operation "◔ Импорт… 38 из 42  Скрыть" (progress pie) → app: no progress kind / hide action in Toast (code) · files: qml/Toast.qml
- **R3-023** [C] sheet: "есть ошибка — слово, не цвет" → app popover: a failing source with an empty error shows a red dot and no words (second "Jira" row) · files: qml/SyncPopover.qml (rows, s.failing branch)
- **R3-024** [D] popover names/details ~11 px vs sheet 13/12 px; quiet "synced" dot white vs sheet dim green · files: qml/SyncPopover.qml, qml/ProfileSwitcher.qml

### OS notifications, timer, update (N-Ntf-OS, X-Ntf-OS)

captures: t-bold-whatsnew (rest code only)

- **R3-025** [B] sheet: meeting "1:1 с Олегом через 5 мин" / "11:00–11:30 · Zoom", buttons "Подключиться" · "Через 5 мин" → app: title "Через 5 мин", body = meeting title only, buttons snooze short · snooze long · Открыть, no join (code) · files: src/AppController.cpp:15395, src/AppControllerPresence.cpp (reminderActions)
- **R3-026** [B] sheet: deadline "Срок сегодня" / "Оформление заказа: таймаут 10 с · ждёт платёжки", one button "Открыть" → app: "Дедлайн через N ч" / "title (P1)", 4 buttons (2 snoozes, Открыть, Готово) (code) · files: src/AppController.cpp:15325-15333, src/AppControllerPresence.cpp
- **R3-027** [B] sheet: running timer also in the tray menu and tray tooltip "lowkey · 0:42 Обход…" → app: tooltip static "lowkey", menu only "Show lowkey" / "Quit" (English in Russian UI), no timer (code) · files: src/notify/NotificationCenter_tray.cpp
- **R3-028** [C] sheet: "Таймер в другом профиле — с именем профиля" → app: runningTimer() reads only the active profile; a timer elsewhere is not shown and no profile name exists (code) · files: src/AppController.cpp:11373, qml/Sidebar.qml
- **R3-029** [C] sheet: what's new title 15px, rows 13px → app: ~13px title, 11–12px rows (smaller, denser) · files: qml/WhatsNewDialog.qml

### Tasks · Board (H2-Board, Q-Board)

captures: bold-board, quiet-board, bold-multiselect

- **R3-030** [B] sheet: priority mark only P0/P1 on bold cards (P2/P3 blank), only P0 on quiet cards → app: grey P2/P3 on every bold card, P1 on quiet cards (same on quiet list rows, Q-List) · files: qml/TaskCard.qml, qml/TaskListView.qml
- **R3-031** [C] sheet: card title line-height 1.35 (bold) / 1.4 (quiet), ~18px between wrapped lines → app: ~15px, titles look cramped · files: qml/TaskCard.qml
- **R3-032** [B] sheet Q: lens tabs 14px, inactive #8f99a6, 20px apart, 28px after the title, on the title's baseline → app: ~13px, inactive near-white, ~12px apart, close to the title and sitting above its baseline · files: qml/LensTabs.qml
- **R3-033** [C] sheet Q: card key #7a8390 (dimmer than the date) → app: key as bright as the date · files: qml/TaskCard.qml

### Tasks · List (H2-List, Q-List)

captures: bold-list, quiet-list

- **R3-034** [B] sheet: group headers 15px/600 bold (14px/500 #c4ccd6 quiet), header + rows inset 8px (10px quiet) from the query bar edge → app: ~13px headers, rows and headers flush with the edge (ring at x236 vs 244 / 256 vs 266) · files: qml/TaskListView.qml
- **R3-035** [C] sheet Q: "Без даты · 3" one muted regular line → app: "Без даты" bold + "· 3" · files: qml/TaskListView.qml
- **R3-036** [C] sheet Q: key column aligned (date column fixed 96px) → app: a long date ("сегодня, 17:00 · срок вс") pushes that row's key and priority left, column jitters · files: qml/TaskListView.qml

### Task document (H2-Task, Q-Task)

captures: bold-task-full, quiet-task-full, bold-task, quiet-task

- **R3-037** [B] sheet: title, body and chips share one left edge (248 bold / 256 quiet) → app: title inset ~5px and body ~8px further right than the chips/breadcrumb · files: qml/TaskDocument.qml, qml/MdBlockEditor.qml
- **R3-038** [B] sheet: body 15px, line-height 1.65, #d7dde5 → app: ~14px, line-height ~1.2, #e9edf2; paragraphs read dense · files: qml/MdBlockEditor.qml
- **R3-039** [C] sheet: slash hint "Пишите прямо здесь…" in #8f99a6 → app: #c4ccd6, almost as bright as the body · files: qml/TaskDocument.qml
- **R3-040** [C] sheet Q: meta column values 13px, ~22px row pitch → app: 12px, tight rows · files: qml/TaskDocument.qml

### Task menu (N-Menus-Task, X-Menus-Task)

captures: bold-taskmenu, bold-x-m-task, quiet-x-m-task, bold-x-m-priority, quiet-x-m-priority, bold-x-m-status, bold-multiselect (bold-m-task / -m-priority / -taskmenu-status: harness artifacts, menu at 0,0 or absent)

- **R3-041** [B] sheet: item labels start on the header's left edge → app: every AppMenuItem reserves an empty check/glyph column, labels sit ~21px right of the header (all menus: task, column, stage, person, saved view) · files: qml/AppMenuItem.qml
- **R3-042** [B] sheet: submenu header "‹ Приоритет" / "‹ Колонка" is the small grey header line → app: a normal white row, same size as the items · files: qml/TaskMenuHost.qml, qml/AppMenuItem.qml
- **R3-043** [B] sheet N: "P0 · срочно" red 600, P1 amber in the priority list → app: all rows plain · files: qml/TaskMenuHost.qml
- **R3-044** [B] sheet: column list has no number keys, separator before "Готово" with key d → app: 1–7 on every row, no separator, Готово without d · files: qml/TaskMenuHost.qml
- **R3-045** [B] sheet X: danger items ("Удалить", "Скрыть из lowkey", "Удалить колонку…") in muted #d8a09c → app quiet: same bright #ef6b63 as bold (also X-Menus-Column, X-Menus-Other) · files: qml/AppMenuItem.qml, qml/Theme.qml
- **R3-046** [B] (code) sheet tracker menu: Открыть, Открыть в GitHub, Готово / Мой приоритет, Мой срок, Запланировать / Копировать ссылку, Обновить из GitHub / Скрыть из lowkey, disabled "Удалить · из трекера не удаляем" → app: "Обновить из GitHub" and the disabled Удалить row missing, "Открыть в …" sits after the timer, Copy ID / branch rows kept, "Копировать ссылку на тикет" · files: qml/TaskMenuHost.qml, qml/I18n.qml
- **R3-047** [C] sheet: menu 280–293px, header "APP-109 · Рефакторинг обработчика вебхуков" fits → app: ~243px, header elided "…внутреннего логир…" · files: qml/AppMenu.qml

### Column & calendar menus (N-Menus-Column, X-Menus-Column)

captures: bold-m-column, quiet-m-column, bold-confirm-column, quiet-confirm-column

- **R3-048** [A] (code) sheet: calendar task block menu = Открыть, Готово, Перенести… s, Длительность… Ctrl Shift J/K, "Убрать из календаря · останется задачей" → app: the full generic task menu (TaskMenuHost) on a block; no duration or unplan row · files: qml/WeekView.qml, qml/TaskMenuHost.qml

### Multi-select & drag (N-Oth-Select-Drag, X-Oth-Select-Drag)

captures: bold-multiselect, quiet-multiselect, bold-drag, bold-x-drag, quiet-drag, quiet-x-drag

- **R3-049** [B] sheet N: target column framed 1.5px blue #7aa7ff, insertion line orange #f2a65a; X: frame 1px #4a525d, line #c4ccd6 → app: lavender accent frame 2px and lavender line in both styles · files: qml/KanbanBoard.qml
- **R3-050** [B] sheet: target frame hugs the column's cards → app: frame runs to the bottom of the window · files: qml/KanbanBoard.qml
- **R3-051** [B] sheet: the card's origin keeps a dashed, 35%-opacity placeholder → app: an empty gap · files: qml/KanbanBoard.qml
- **R3-052** [C] sheet: drag ghost opaque #1b2027 with a deep shadow, no accent border → app: translucent ghost with accent outline, cards show through · files: qml/KanbanBoard.qml
- **R3-053** [B] (code) sheet: folded Done under the pointer becomes a tall framed strip, ring + "Готово" + "отпустите" centred → app: only the top label swaps "Показать" → "отпустите" with a ring outline round the 88px column · files: qml/KanbanBoard.qml
- **R3-054** [A] (code) sheet: undated task dragged onto the calendar shows a dashed block sized by the estimate, "14:00–15:00 · по оценке 1 ч" → app: a 2px accent line at the pointer and a small title ghost · files: qml/WeekView.qml, qml/UndatedTray.qml

### Archive & people (N-Oth-Archive-People, X-Oth-Archive-People)

captures: bold-archive, quiet-archive, bold-archive-empty, quiet-archive-empty, bold-people, bold-r3-people, quiet-r3-people, bold-r3-personmenu (menu at 0,0 = harness), bold-m-person

- **R3-055** [B] sheet: archive row = ring, title, then "APP-111 · 6 окт" muted at the right → app: the plain list row (key column on the left, no date) · files: qml/TaskListView.qml
- **R3-056** [B] sheet: month group header carries the count ("Октябрь 6") → app: month groups have no count; a hand-archived task with no status change lands in "Без даты" under "по месяцу" · files: qml/TaskListView.qml
- **R3-057** [B] sheet: state on the right "• ждёт", "написал вчера", "ответила" → app: "написать", "написал" (no when), "ответил" · files: qml/PeopleDialog.qml, qml/I18n.qml
- **R3-058** [C] sheet: list ends after "+ человек · Ctrl Shift U" → app: fixed-height dialog, ~150px of empty list space above the footer · files: qml/PeopleDialog.qml

### Calendar week (H2-Calendar, Q-Calendar)

captures: bold-calendar, quiet-calendar, bold-week, quiet-week

- **R3-059** [C] sheet: hour labels fully visible under the day header (Q: "09" at the top of the grid) → app: in quiet, the first hour label is cut in half under the header/deadline row (also quiet day view "09:00") · files: qml/WeekView.qml
- **R3-060** [C] sheet: timed task blocks show only ring/time + title → app: an extra flag icon inside the block when the task also has a deadline (week and day zoom, both styles) · files: qml/WeekView.qml (Icon name "flag" in wkBlock)

### Calendar day & month (N-Oth-DayMonth, X-Oth-DayMonth)

captures: bold-day, quiet-day, bold-month, quiet-month, bold-m-slot, quiet-m-slot, bold-m-event, quiet-m-event

- **R3-061** [C] sheet: quiet day grid starts with a readable "09:00" → app: first label clipped under the header (same root cause as the week) · files: qml/WeekView.qml
- **R3-062** [D] note: bold-m-event / quiet-m-event show the empty-slot menu, not the meeting menu (harness); meeting menu items exist in code and match N-Menus-Column (code) · files: qml/WeekView.qml

### Meeting panel (N-Dlg-Event, X-Dlg-Event)

captures: bold-event-open, quiet-event-open, bold-event-new, quiet-event-new

- **R3-063** [B] sheet: bold title "1:1 с Олегом" 22px/600 → app: title at Medium (fwTitle) in bold style · files: qml/EventEditor.qml (titleField font.weight)
- **R3-064** [B] sheet: one-line input "Ретро спринта" plain + parsed words "пт 16:00 на 1 ч", "каждые 2 недели" tinted (#a9c3dd), regular weight → app: whole line one colour, Medium weight, no tint on recognised words · files: qml/EventCapture.qml
- **R3-065** [C] sheet: quiet "Удалить…" muted rose (#d8a09c) → app: full danger red in quiet · files: qml/EventEditor.qml

### Schedule / deadline field (N-Dlg-Schedule, X-Dlg-Schedule)

captures: bold-schedule, bold-schedule-due, bold-schedule-overlap, bold-schedule-picker, bold-schedule-unknown, quiet-schedule*

- **R3-066** [A] sheet: "Маленькое поле у карточки" — the popup sits right under the card it was opened from (card title visible above it) → app: popup centred on the window at 1/4 height, covering the card and neighbours; nothing says which task is being scheduled for a single task · files: qml/Main.qml (SchedulePopup x/y), qml/SchedulePopup.qml
- **R3-067** [A] sheet: overlap state hint "↵ всё равно поставить · ↓ ближайшее окно 12:00" (offers the next free slot) → app: same hint as the normal state "↵ поставить · Tab календарь · Esc отмена"; no nearest-free-window line or ↓ action · files: qml/SchedulePopup.qml
- **R3-068** [A] sheet: Tab picker = month grid + right column "пт, 9 окт · свободно" with hour slots (busy hour "занято"), "без времени · весь день" → app: generic DatePickerPopup with no time column, extra 6th week row and a "Сегодня" button; picks a date only · files: qml/Main.qml (schedDatePicker), qml/DatePickerPopup.qml
- **R3-069** [B] sheet (bold): overlap result line orange (#f2a65a), unknown-date line red (#ef6b63) → app: overlap in normal text colour, unknown in muted grey (quiet grey is correct) · files: qml/SchedulePopup.qml (schedule-result color)
- **R3-070** [B] sheet picker: today = orange underline, chosen day = outlined box, title "Октябрь 2026" left with ‹ › at right → app: chosen day filled lavender, today filled grey, lowercase centred "октябрь 2026" between arrows · files: qml/DatePickerPopup.qml
- **R3-071** [C] sheet: input clearly outlined (#4a525d), 14px regular → app: barely visible border while focused, Medium weight · files: qml/SchedulePopup.qml

### Recap, end of day, standup (N-Dlg-Recap, X-Dlg-Recap)

captures: bold-recap, quiet-recap, bold-endofday, quiet-endofday, bold-standup, quiet-standup

- **R3-072** [B] sheet: standup is prose lines "Вчера: закрыл APP-111, APP-112." / "Сегодня: …" / "Блокеры: …" → app: headings with "- " bullet lists, and an empty day reads "- —" · files: qml/StandupDraftDialog.qml (+ draft builder in src/)
- **R3-073** [B] sheet (bold): one filled white main button per dialog — "Копировать" (standup), "Перенести" (series question), "Восстановить эту версию…" (time machine), "Импортировать" (import) → app: all outlined (PillButton primary is outline only; `solid` exists but is not used here) · files: qml/StandupDraftDialog.qml, qml/SeriesScopeDialog.qml, qml/TimeMachineDialog.qml, qml/VaultImportDialog.qml, qml/PillButton.qml
- **R3-074** [C] sheet: end-of-day action chips small (26px, 12px text, dimmer #aeb7c2) → app: full-size 30px buttons, 13px · files: qml/EndOfDayDialog.qml

### Small dialogs & confirmations (N-Dlg-Small, X-Dlg-Small)

captures: bold/quiet-profile-new, -person-new, -confirm-column, -confirm-example, -confirm-link, -confirm-push, -r3-profiledelete, (bold-savedview)

- **R3-075** [B] sheet: "Новый профиль" 8 muted swatches (#8aa4c2, #7fae9a, #b49cc8, #c2a27a, #c48e8a, #9aa4b1, #6f8fa8, #a3a86e) → app: saturated cyan/blue/purple/red/orange/yellow/green · files: qml/ProfileEditor.qml (Theme.swatches / ThemePresets.js SWATCHES)
- **R3-076** [B] sheet: "Открыть ссылку в браузере?" + "Ссылка из задачи ведёт на внешний сайт." + labelled "Адрес" field (mono) + Копировать / Открыть, asked for external web links → app: "Открыть ссылку?" "Это не веб-страница…", bare URL text, Отмена / red "Всё равно открыть"; http(s) links open with no dialog (code; confirm-link capture shows no dialog) · files: qml/LinkConfirmDialog.qml
- **R3-077** [B] sheet: "Сохранить как вид" name prefilled as readable "Заблокировано · P0" → app: name prefilled with the raw query "статус:заблокировано p0" · files: qml/SavedViewNameDialog.qml
- **R3-078** [C] sheet: "Перенести задачи в" a compact dropdown "К выполнению ▾" → app: full-width combobox, defaults to "Бэклог" · files: qml/KanbanBoard.qml

### Time machine (N-Dlg-TimeMachine, X-Dlg-TimeMachine)

captures: bold-timemachine, quiet-timemachine

- **R3-079** [B] sheet (bold): selected snapshot row filled (#262d37) with a 2px light bar on the left; quiet filled #1b2027 → app: filled + lavender focus-ring outline round the whole row, no left bar · files: qml/TimeMachineDialog.qml (snapRow border = focusRing)

### Log & import (N-Dlg-Log-Import, X-Dlg-Log-Import)

captures: bold-log, quiet-log, bold-r3-import, quiet-r3-import

- **R3-080** [A] sheet: "Импорт профиля (JSON)" preview card — file · version · counts, radio "Новым профилем «work»" / "Слить с «Example» — совпадающие ID не затираются…", Импортировать → app: picking a file in the OS dialog imports straight away, no preview and no new/merge choice (code) · files: qml/Main.qml (importJsonDialog)
- **R3-081** [B] sheet: — → app: the JSON file dialog filter reads "heap. profile (*.json)", the old brand (code) · files: qml/Main.qml (importJsonDialog nameFilters)
- **R3-082** [C] sheet (bold): an error entry's source has a warning mark "GitHub ⚠" → app: error rows look the same as the others ("Синк") · files: qml/EventLogDialog.qml

### Knowledge (H2-Knowledge, Q-Knowledge)

captures: bold-knowledge, quiet-knowledge, bold-r3-knowledge, quiet-r3-knowledge, bold-m-note

- **R3-083** [B] sheet: body paragraphs and lists start flush with the title/heading x (512 bold / 496 quiet), line-height ~1.7 so a paragraph wraps to 2 airy lines, ~16px gap between blocks → app: paragraph text indented ~8px right of the heading, tight single line-height, blocks packed (whole note ~40% shorter) · files: qml/MdView.qml (paragraphRow, sideMargin), qml/MdBlockEditor.qml
- **R3-084** [B] sheet: heading scale per style — note title 30 bold (H2) / 28 semibold (Q); "##" 17 bold (H2) / 15 semibold (Q) → app: one fixed scale [24,20,17…] in both styles: title ~24, "##" 20 bold, so section headings are louder than the sheet and the title smaller; quiet gets bold-weight headings · files: qml/MdView.qml:344 (headingRow)
- **R3-085** [B] sheet Q-Knowledge: task refs inline read as underlined text "◑ APP-101" (no pill); RFC 6585 plain, not underlined → app quiet: task refs are filled pills (same as bold) and the external link is underlined · files: qml/MdView.qml, qml/NotesView.qml
- **R3-086** [B] sheet Q-Knowledge: inline code is a hairline-stroked pill (R2-020 says quiet strokes) → app quiet: inline code drawn as a fill, no stroke · files: qml/MdView.qml (InlineCodeFrames), Style.chipFill
- **R3-087** [C] sheet: list bullets are solid round text-colour dots → app: tiny grey dots, list indented further than the sheet · files: qml/MdView.qml (bulletLabel)
- **R3-088** [B] sheet H2: links column headers semibold 12, entries 13 medium with the ID bold and "· В работе" dimmed → app: headers regular-weight look, entries fsSm (~12) regular, ID not bold, status barely dimmer · files: qml/NotesView.qml (LinksHeader/LinksItem ~1097)
- **R3-089** [B] sheet: pinned "OpenAPI нашего бэкенда" tagged API → app: tag is the first word cut to 4 chars → "Open" (any ref whose first word is not a short code gets a broken tag) · files: qml/NotesListPane.qml:61 (_splitRef), :530
- **R3-090** [C] sheet: list rows 13–14px medium; "Знания" header ~18 bold; "+" a small stroked square → app: rows fsSm (~12) regular, header smaller, "+" a filled square; search field shows an accent focus outline at rest · files: qml/NotesListPane.qml
- **R3-091** [C] sheet Q-Knowledge: links column shows only "Ссылаются сюда" + "Задачи в заметке" → app quiet also draws "Внешние ссылки" · files: qml/NotesView.qml (DG-072 lists the quiet order only)

### Knowledge — inserts and "/" menu (N-Oth-Knowledge, X-Oth-Knowledge)

captures: bold-r3-knowledge, quiet-r3-knowledge, bold-r3-slash, quiet-r3-slash

- **R3-092** [B] sheet: "one editor, no modes": typing "/" on a new line shows just "/|" in place, block keeps its rendered position → app: the edited block turns into a bordered panel-filled text box showing raw markdown (`Retry-After` backticks), the paragraph and the new "/" line merged in one box, and the block jumps ~50px down when edit starts · files: qml/MdBlockEditor.qml (field TextArea background, _contentY)
- **R3-093** [B] sheet "/" menu: labels start ~16px from the panel edge, menu ~290px wide → app: an empty ~20px check/glyph column before every label (same in all AppMenu menus, see Menus), menu ~205px · files: qml/AppMenuItem.qml (contentItem check column), qml/MdBlockEditor.qml (slashMenu)
- **R3-094** [B] (code) sheet: image block with a caption line under it ("Повторы с экспоненциальной паузой") → app: image rows render no caption/alt line · files: qml/MdView.qml (imageRow/localImage)
- **R3-095** [B] (code) sheet Git line: "работаю над APP-101 · fix/login-throttle · PR #482 · CI прошёл ×", note "(выключена по умолчанию)" → app: copy "В работе %1", and `git.workingOnLine` defaults to on · files: qml/I18n.qml:2705 (topbar.git.workingOn), qml/Theme.qml:35, qml/SettingsView.qml:3325

### Quick capture over other windows (N-Oth-Capture, X-Oth-Capture)

captures: bold/quiet-capture-empty, bold/quiet-capture-typed, bold/quiet-r3-quicknote, bold-x-quicknote

- **R3-096** [B] sheet: task capture header "lowkey  новая задача" (wordmark + label, like the quick note) → app: only "новая задача", no wordmark · files: qml/QuickCapturePopup.qml:486
- **R3-097** [B] (code) sheet: footer right "из ветки fix/APP-105 — связать?" (offer to link the branch's task) → app: no branch hint in the task capture at all · files: qml/QuickCapturePopup.qml
- **R3-098** [B] sheet: input 16px medium white, tokens "завтра 11:00 p1" all in accent; chips ~26px tall, 13px ("когда пт, 9 окт · 11:00") → app: input ~14px light, p1 coloured as priority (orange in bold) not accent; chips ~22px, 11px, value "завтра, вс, 11 окт, 11:00 ×" (relative word + comma format + ×) · files: qml/QuickCapturePopup.qml (~700, PropertyChip)
- **R3-099** [C] sheet: footer hints spaced as separate items "↵ создать   Shift ↵ строка   Esc закрыть" / "Ctrl ↵ сохранить   Esc — черновик сохранится" → app: one string joined with " · " · files: qml/I18n.qml:3550 (capture.hints), quickNote footer
- **R3-100** [C] sheet quick note body 14px → app ~13px · files: qml/QuickCaptureNotesPopup.qml

### Other menus (N-Menus-Other, X-Menus-Other)

captures: bold/quiet-x-m-savedview, bold/quiet-m-profile, bold/quiet-x-m-profile, bold/quiet-r3-notemenu, bold/quiet-x-m-note, bold-r3-personmenu, bold/quiet-m-textfield (menu not open), m-savedview/m-note/m-person (menu not open)

- **R3-101** [B] sheet: menu labels start at the row's left padding (~16px) → app: every AppMenuItem reserves an always-on check/glyph column (fsMd + spMd ≈ 22px) so labels sit ~38px in, a blank gutter on menus with no checks (saved view, profile, note, person, text field, "/") · files: qml/AppMenuItem.qml:105 (labelRow check column)
- **R3-102** [B] sheet X-Menus-Other (quiet): highlighted row is a plain fill with no edge marker; danger items in a muted salmon → app quiet: same 3px accent marker and bright red danger as bold · files: qml/AppMenuItem.qml:186 (menu-row-marker), :142 (Theme.danger)
- **R3-103** [A] (code) sheet tray menu: header "lowkey", Новая задача… Ctrl Shift Space, Быстрая заметка… Ctrl Shift N, Остановить … timer line, "Далее: 11:00 1:1 с Олегом", Открыть lowkey, Не беспокоить 1 ч, Выход → app: native QMenu with two hard-coded English items "Show lowkey" / "Quit" · files: src/notify/NotificationCenter_tray.cpp:52
- **R3-104** [C] sheet profile switcher on the Example profile: danger row "Удалить профиль…" → app: "Убрать пример" replaces it there · files: qml/ProfileSwitcher.qml:320
- **R3-105** [C] sheet: menus ~283px wide, first row shown highlighted → app: ~200px, "Копировать ссылку [[...]]" label runs into its hint; saved view menu opens with no row highlighted · files: qml/AppMenu.qml, qml/AppMenuItem.qml

### Command line (H2-Command, Q-Command)

captures: bold/quiet-palette, bold/quiet-palette-query, bold/quiet-palette-empty

- **R3-106** [B] sheet H2: "Снять блокировку → В работу" → app: "Снять блокировку → В работе" (status name dropped in raw, not the accusative) · files: qml/I18n.qml:3527 (cmd.unblock)
- **R3-107** [C] sheet: query chips have no close glyph → app: every chip carries "×" (both styles) · files: qml/CommandPalette.qml
- **R3-108** [C] sheet: an extra hit outside tasks would sit in its own group → app: an event ("Focus · Оформление заказа…", "событие") listed under "Заметки, доки, люди" · files: qml/CommandPalette.qml
- **R3-109** [C] sheet: typed query 16px medium, row titles medium weight, side-card syntax column bold mono → app: query ~15px regular, rows regular, syntax cells regular mono · files: qml/CommandPalette.qml
- **R3-110** [C] (empty state, not drawn on the sheet) list offers "Перейти к докам" and "Перейти к заметкам" beside "Перейти в «Знания»" though Docs is gone (DG-070); last row cut by the footer · files: qml/CommandPalette.qml, src/AppController.cpp (command catalogue)

### Key cheat sheet (N-Keys, X-Keys)

captures: bold-cheatsheet, quiet-cheatsheet

- **R3-111** [B] sheet: key caps are filled chips (panel fill, bright medium mono) → app: hairline-outlined caps with dim light mono · files: qml/KeyCheatSheet.qml, qml/KeyHint.qml
- **R3-112** [B] sheet: areas in a fixed 4-column grid by rows (Движение | Перейти | Задача | Переместить, then Скопировать | Выделение | Вид | Поиск, then Изменилось в 0.8.0) → app: areas packed masonry-style into 4 columns (Скопировать under Движение, Выделение under Перейти, Вид under Задача, Поиск under Переместить) · files: qml/KeyCheatSheet.qml
- **R3-113** [C] sheet: secondary notes ("повтор — вернуть", "было O") set off by a gap in a dimmer colour; labels medium weight → app: notes run straight after the label, nearly the same colour; labels regular · files: qml/KeyCheatSheet.qml
- **R3-114** [C] sheet: Open key "↵"; title 22 bold; footer "Изменить сочетание — Настройки → Клавиши · Ctrl / тоже открывает этот экран", intro "менять в Настройках → Клавиши" → app: "Enter"; title ~18; footer link "Изменить сочетания…", intro "менять в «Изменить сочетания…»" · files: qml/KeyCheatSheet.qml, qml/I18n.qml

### Settings overview (H2-Settings, Q-Settings)

captures: bold-settings, quiet-settings, bold-light-settings, quiet-light-settings, bold-set-appearance, quiet-set-appearance

- **R3-115** [C] sheet: section heading 16px/600 (H2 dc: font-size 16px) → app: Theme.fsLg = 15px, reads smaller/lighter next to the 24px title · files: qml/SettingsView.qml (block heading, ~l.829)
- **R3-116** [C] sheet Q-Settings: quiet rows carry no section subline and only data hints ("цвет выделения", "10:00 – 19:00", "не подключена"), no dividers → app quiet: same sublines/sentence-case hints/dividers as bold (X boards do show sublines and hints, so the sources conflict; follows X) · files: qml/SettingsView.qml, qml/SettingsRow.qml
- **R3-117** [C] sheet N-Set-StyleKeys: switch "on" track #7aa7ff (blue) → app bold: switch "on" in the lavender accent · files: qml/AppSwitch.qml

### Style & keys (N-Set-StyleKeys, X-Set-StyleKeys)

captures: bold-set-shortcuts, quiet-set-shortcuts, bold-set-keys-conflict, quiet-set-keys-conflict, bold-settings, quiet-settings

- **R3-118** [B] sheet: block heading "Изменить сочетания", sub "Отдельный режим; шпаргалка «?» остаётся только для чтения" → app: heading "Клавиши", sub "Щёлкните по клавише, чтобы сменить; шпаргалка «?» остаётся только для чтения" · files: qml/I18n.qml (settings.section.shortcuts.*), qml/SettingsView.qml
- **R3-119** [C] sheet: key rows 45px, key cap border #262c34 with dim text #c4ccd6, unassigned cap dashed "—" → app: rows ~54px, cap border Theme.fieldBorder (brighter) with Theme.text, unassigned cap solid at 0.6 opacity · files: qml/SettingsView.qml (keyCap ~l.2380)
- **R3-120** [C] sheet: conflict box — rest of sentence in dim #8f99a6, "Заменить" is the primary (white outline) beside a plain "Другое сочетание" → app: whole sentence one colour, both buttons identical · files: qml/SettingsView.qml (settings-keys-conflict ~l.2445)

### Calendar, notifications, safety (N-Set-CalNotif, X-Set-CalNotif)

captures: bold-set-calendar, quiet-set-calendar, bold-set-notifications, quiet-set-notifications, bold-set-safety, quiet-set-safety

- **R3-121** [C] sheet: "Хранить снимков", immersion hint "Ctrl Shift F — одна задача, уведомления ждут" → app: "Хранить снимков, дней", "Ctrl+Shift+F — …" (plus notation, unlike "Ctrl Shift ↑↓" elsewhere on the page) · files: qml/I18n.qml
- **R3-122** [D] sheet: "Начало запланированной задачи" hint is short (one line) → app: long two-clause hint "когда начинается задача, запланированная на час; таймер не запускается" · files: qml/I18n.qml

### Columns (N-Set-Columns, X-Set-Columns)

captures: bold-set-tasks, quiet-set-tasks

- **R3-123** [C] sheet: stage dropdown is a subtle field (border #262c34-ish, small grey caret, ~170px), counts "3 задач" in dim body size → app: AppComboBox with bright border and large white caret (~180px), counts smaller and brighter; stage rings larger · files: qml/SettingsView.qml (columns table), qml/AppComboBox.qml
- **R3-124** [D] sheet: "+ Колонка" (capital, also in X) → app quiet: "+ колонка" · files: qml/SettingsView.qml

### Git, language, help, about (N-Set-GitLangAbout, X-Set-GitLangAbout)

captures: bold-set-git, quiet-set-git, bold-set-language, quiet-set-language, bold-set-help, quiet-set-help, bold-set-about, quiet-set-about, bold-set-data, quiet-set-data

- **R3-125** [C] sheet: "Помощь" has no subline (dc: sub '') → app: extra subline "Клавиши, гид, сообщение о проблеме" · files: qml/I18n.qml (settings.section.help.sub), qml/SettingsView.qml
- **R3-126** [C] sheet: Обновления hint lowercase fact "проверено сегодня 09:00" → app: "У вас последняя версия" (sentence case among lowercase hints); quiet "Проверить сейчас" and "Синхронизировать" (trackers) stay capitalised among lowercase options · files: qml/I18n.qml, qml/SettingsView.qml

### Trackers (N-Set-Trackers, X-Set-Trackers)

captures: bold-set-integrations, quiet-set-integrations, bold-set-trackers-jira, quiet-set-trackers-jira, t-bold-trk-settings, t-quiet-trk-settings

- **R3-127** [B] sheet: status-mapping dropdown is a compact pill with the column's stage ring + name + small caret, note "не распознан — выбрано по умолчанию" in full → app: wide plain AppComboBox without the stage ring; the note is elided "не распознан — выбрано по…" · files: qml/SettingsView.qml (Статусы → колонки), qml/AppComboBox.qml
- **R3-128** [B] sheet: detail column starts at one fixed x beside a fixed-width list → app: detail x jumps between trackers (GitHub detail at ~728px, Jira at ~657px) because the list column (preferredWidth 170) grows/shrinks with the state text · files: qml/SettingsView.qml (int-list ~l.2600)
- **R3-129** [C] sheet: "Запись в Jira" is a single value button "выключено" → app: two-option segment Выключено/Включено · files: qml/SettingsView.qml
- **R3-130** [C] sheet: not-connected copy «Войти через браузер» → app: "Подключить через браузер" · files: qml/I18n.qml

### Пустые состояния и особые случаи (N-Err-Empty, X-Err-Empty)

captures: bold-e-board, bold-e-list, bold-e-filter, bold-e-week, bold-e-today, bold-e-knowledge, bold-e-palette, bold-empty-filter-list, bold-archive-empty, bold-today-empty, bold-palette-empty (quiet-e-* captures did not reach the empty profile, so they could not be judged)

- **R3-131** [A] sheet: empty board = one plain centred line "Задач пока нет" + "Ctrl N — новая · или подключите трекер" → app: the old card (bordered panel, board icon, "Пока нет задач", two-line hint "Нажмите Ctrl+N, чтобы добавить первую задачу, или откройте быстрый ввод (Ctrl+Shift+Space).") · files: qml/KanbanBoard.qml (board.empty.*, the panel Rectangle about line 1925), qml/I18n.qml
- **R3-132** [B] sheet: empty list "Задач пока нет" + dim line "Ctrl N — новая · или подключите трекер" → app: title only, no second line · files: qml/TaskListView.qml:497, qml/I18n.qml (list.empty)
- **R3-133** [B] sheet: empty week "На этой неделе ничего не запланировано" / "S на задаче — поставить на день" → app (code): icon + "На этой неделе пусто" + long hint "Здесь появляются задачи с датой и события. Кликните…"; same old pattern in month ("В этом месяце пусто" + long hint) · files: qml/WeekView.qml:2414, qml/MonthView.qml:951, qml/I18n.qml (week.empty.*, month.empty.*)
- **R3-134** [B] sheet: empty Knowledge "Заметок пока нет" / "Ctrl Alt N — первая · импорт Markdown" → app: no notes section and no empty message at all (pinned links and snippets are listed, the right pane shows a blank "Заметка" editor with a placeholder); notes.empty copy is "Заметок пока нет. Нажмите +, чтобы написать." plus the notes icon · files: qml/NotesListPane.qml:413, qml/I18n.qml (notes.empty)
- **R3-135** [B] sheet: palette with nothing found = centred "Ничего не нашлось по «релиз пятн»" + dim "↵ — создать задачу «релиз пятн»" → app: one selectable row "Ничего · создать задачу «релиз пятн»" with ↵ on the right · files: qml/CommandPalette.qml, qml/I18n.qml (cmd.create)
- **R3-136** [B] sheet: "Ничего под «заблокировано · p0»" → app: a key typed in Russian ("статус:заблокировано") is read as an unknown key and shows as "где заблокировано · p0 · zzz" · files: qml/QueryWords.js (clause: keys map is English only)
- **R3-137** [A] sheet: D with no Done-stage column opens a card "Некуда отметить готовой" / "Ни у одной колонки нет этапа «Готово»." with [Создать колонку «Готово»] (primary) and [Выбрать этап у колонки…] → app (code): a toast "Нет колонки этапа «Готово» — создать?" with a single "Создать" action and no way to pick a stage · files: qml/Main.qml:953, qml/I18n.qml (done.noColumn)
- **R3-138** [B] sheet: a task whose column was deleted shows a dashed "?" ring + "колонка «На паузе» удалена · перенести…" (underlined link) → app (code): StatusRing has the "orphan" look, but nothing ever sets that category and there is no "удалена · перенести…" line · files: qml/StatusRing.qml, qml/TaskCard.qml, qml/TaskListView.qml
- **R3-139** [C] sheet: the free-day Today shows "Ничего не запланировано" / "в «Задачах» 12 без даты" as one centred pair → app: "Ничего не запланировано" sits in the header, "в «Задачах» N без даты" sits as a line under "День" above the free-time rows, and the right column repeats the same fact as "3 задачи без даты — посмотреть и решить" · files: qml/TodayView.qml

### Сохранение, восстановление, сбой (N-Err-Storage, X-Err-Storage)

captures: t-bold-storage, t-quiet-storage, bold-damaged, bold-damaged-start, bold-damaged-sidebar, t-bold-keychain, t-bold-report

- **R3-140** [B] sheet: keychain card has the dim eyebrow "Хранилище ключей ОС недоступно" above the title → app: no eyebrow (the keychain.eyebrow key exists but nothing uses it) · files: qml/KeychainDialog.qml, qml/I18n.qml
- **R3-141** [C] sheet: damaged-file fact opens with where it broke: "state.json не читается с позиции 18 230. Ничего не удалено: …" → app: only "Ничего не удалено: повреждённый файл сохранён рядом как …" · files: qml/I18n.qml (storage.damaged.fact), src/ (load error offset)
- **R3-142** [C] sheet: strip and card body text 13px → app: the storage strip, damaged card and keychain card body use the smaller fsSm, so they read a step smaller than the sheet · files: qml/StorageBanner.qml, qml/KeychainDialog.qml
- **R3-143** [D] bold-damaged-sidebar: blank Today, no card or other sign of the damaged file (could be the harness; unclear which state this capture was meant to show) · files: qml/Main.qml

### Ошибки трекеров (N-Err-Tracker, X-Err-Tracker)

captures: t-bold-strip, t-quiet-strip, t-bold-board, t-quiet-board, t-bold-trk-board, t-quiet-trk-board, t-bold-trk-list, t-bold-trk-today, t-bold-trk-task-conflict

- **R3-144** [B] sheet: tracker marks ("ждёт отправки статуса", "вне фильтра Jira — только у вас", "удалён в Jira · оставить у себя / убрать", "изменён и у вас, и в Jira · решить") → app: they appear on board cards only; list rows show the same tasks with no mark, no edge and no strike-through · files: qml/TaskListView.qml (marks live in qml/TaskCard.qml only)
- **R3-145** [C] sheet: strip fact, consequence and action at 13px → app: all three at fsSm (about 12px), so the strip reads a step smaller · files: qml/TrackerStrip.qml:123-144
- **R3-146** [C] app (code): the open task panel of a conflicted or gone tracker task (t-bold-trk-task-conflict) has no mark or "решить" link, so the conflict can only be reached from the card · files: qml/TaskPanel*.qml / qml/TaskDocView.qml

### Конфликт синка и запись в трекер (N-Dlg-Conflict, X-Dlg-Conflict)

captures: t-bold-conflict, t-quiet-conflict, t-bold-push-confirm, t-quiet-push-confirm, bold-confirm-push, quiet-confirm-push

- **R3-147** [A] sheet: with tracker writes on, a pre-send card "Отправить статус в Jira?" / "APP-101 · <title>" / "В работе → Done" / checkbox "Больше не спрашивать для Jira" / [Только у меня] [Отправить] → app (code): no such dialog and no "don't ask again" setting; only the not-yours card (TrackerPushConfirmDialog) exists · files: qml/TrackerPushConfirmDialog.qml, qml/Main.qml:890, src/AppController.cpp:3074
- **R3-148** [B] sheet: row label "Название" → app: "Заголовок" · files: qml/I18n.qml (ticket.conflict.title), qml/SyncConflictDialog.qml
- **R3-149** [B] sheet: "Тикет вне вашего фильтра Jira." / "…в Jira от вашего имени" → app (bold-confirm-push): "Тикет вне вашего фильтра jira." / "в jira": the raw provider id leaks when the provider descriptor is missing · files: src/AppController.cpp:3074 (d ? d->displayName : providerId), qml/TrackerPushConfirmDialog.qml
- **R3-150** [C] sheet: the picked cell is only an outline (transparent fill, bright text) → app: picked cell filled with the panel colour plus the border · files: qml/SyncConflictDialog.qml

### Landing, ru + en, desktop + mobile (heap-site-2 index / ru)

Layout, typography, colours, hero, scenes, demo, slider, tool cards, marquee and FAQ match the prototype at 1440 and 390; the copy differences below are deliberate `site/PROMISES.md` honesty edits, listed for the record. No console errors, failed requests or horizontal scroll on any page.

captures: sites/proto-{en,ru}-{d,m}.png vs ship-{en,ru}-{d,m}.png, cmp_rud_00..08, cmp_rum_00..07

- **R3-151** [B] sheet: Git heading «нужная задача уже подсвечена» / "the task is already marked" → app: the heading is kept, but the reworked scene no longer highlights the card (the top bar names the task; the card is not marked). PROMISES #14 is still an open **gap** (reword to "is already at the top" or highlight the card in 0.8.0) · files: site/src/data/i18n.ts (git.h), site/PROMISES.md
- **R3-152** [C] sheet: Git scene = terminal `git switch -c …` "Switched to a new branch" + card with a branch line (⎇ APP-112-flaky-sync-test) → app: `git switch APP-112-…` (existing branch), plus an extra "В работе APP-112 · PR #57 · на ревью" bar, a card with "PR #57 · на ревью" instead of the branch line, and an extra caption under it; body copy rewritten (Settings → Git, .git/HEAD, gh/glab). Deliberate (PROMISES #12–18, cards show no branch) · files: site/src/components/Landing.astro, site/src/data/i18n.ts (git.*)
- **R3-153** [C] sheet: Keyboard grid of 6 cards (3×2) → app: 9 cards (3×3; adds Разделы Ctrl 1–3, Скопировать номер y y, Шпаргалка ?; Перейти gains g l; Готово says "вернуть / Ctrl Z") + an extra footnote paragraph about single letters and the site's own keys; the intro paragraph is reworded (physical key). The section is ~260 px taller on desktop and ~3 cards longer on mobile · files: site/src/data/i18n.ts (keys.*), site/src/components/Landing.astro
- **R3-154** [C] sheet: Download block on the landing ends with a "Через Scoop" code box (`scoop bucket add heap …`) → app: no Scoop box on the landing; it moved to /download/ and shows only while the bucket installs the latest release (hidden in this build); a "Все способы установки" link is added under the file table · files: site/src/components/Landing.astro, site/src/components/Download.astro, site/src/lib/scoop.ts
- **R3-155** [D] sheet: file sizes "≈ 40 МБ" and "Размеры — по последнему релизу." → app: exact "39.7 МБ" (no ≈) and "Размеры файлов версии 0.7.2." (from the Releases API) · files: site/src/components/Landing.astro, site/src/data/i18n.ts (get.filesNote)
- **R3-156** [D] sheet: "Ваши данные" cards are short (3–4 lines) → app: «Трекеры — только чтение» and «Ничего не теряется» are much longer (6–7 lines), so the four cards are taller and uneven; whereP is 4 paragraphs instead of 1 (adds the heap 0.7 migration and the secrets.json lines); extra note under the state.json example; the example is schema 12 with `statuses` (proto: schema 11) · files: site/src/data/i18n.ts (trust.*), site/src/data/state-example.json
- **R3-157** [D] sheet: "Что приложение отправляет само" has 5 items → app: 7 (adds «Состояние PR», «Картинки в заметках»); extra sign-in caption paragraph under the tracker marquee · files: site/src/data/i18n.ts (trust.net, trust.signIn)
- **R3-158** [D] sheet: FAQ has 6 questions → app: 7 (adds «У меня heap 0.7. Что будет с данными?»); answers for offline / several machines / team / Obsidian reworded · files: site/src/data/i18n.ts (faq.items)
- **R3-159** [D] sheet: demo placeholder «Например: ревью PR завтра 15:00 #api» → app: «… #api p1»; 17:30 moment copy «Ссылка на задачу показывает её статус» → «#APP-112 в тексте заметки становится ссылкой с названием задачи» · files: site/src/data/i18n.ts (demo.placeholder, day.moments)
- **R3-160** [D] sheet: footer = logo · English · GitHub → app: logo · Скачать · English · MIT · GitHub (at 390 the four links fill the row to the 16 px gutter) · files: site/src/layouts/Page.astro

### Download page (/download/, /ru/download/) — ship only, no prototype page

captures: sites/ship-download-{d,m}.png, ship-download-ru-{d,m}.png, cmp_dl_00 (proto side = 404, the prototype has no download page)

- **R3-161** [C] sheet: (none) → app: on mobile (390) the "Из исходников" code box wraps commands mid-flag (`-B build -` / `DCMAKE_BUILD_TYPE=Release`) and the clone URL drops to its own line, so a copied-by-eye command reads as broken (`pre-wrap` + `overflow-wrap:anywhere`; the Copy button still copies it correctly) · files: site/src/styles/site.css (.way pre, line 396)
- **R3-162** [C] sheet: (none) → app: the Scoop way is missing in this build (hidden by the bucket-version gate), so the page offers only AppImage + source as "other ways" while the landing link says «Все способы установки» · files: site/src/components/Download.astro (line 25–27), site/src/lib/scoop.ts

### 404 — ship only, no prototype page

captures: g7/ship-404-{d,m}.png (re-shot at /heap/404.html; sites/ship-404-* and proto-404-* show the python http.server default page because the test server does not route 404s, so they are not evidence)

- **R3-163** [C] sheet: (none; the prototype has no 404) → app: one bilingual page: English h1 + subtitle + Home/Download buttons, then the Russian line «Возможно, она переехала… На главную» as plain body text at the same size as the subtitle, without the Russian heading «Такой страницы нет.» that i18n.ts defines; reads as a leftover rather than a designed second language block · files: site/src/pages/404.astro, site/src/data/i18n.ts (notFound)

### Global: nav, links, console

captures: probe run (g7/probe.cjs) over all ship and proto pages at 1440 and 390

- **R3-164** [C] sheet: links to github.com/sectapunterx/heap → app: the built site also links sectapunterx/heap everywhere (releases, LICENSE, GitHub, `git clone …/heap.git`, `scoop bucket add heap`), because the local fallback in repo.mjs is still `'sectapunterx/heap'` after the repository was renamed to lowkey. On Actions GITHUB_REPOSITORY fixes it; local/preview builds and the base path `/heap/` keep the old name · files: site/repo.mjs (line 5)
