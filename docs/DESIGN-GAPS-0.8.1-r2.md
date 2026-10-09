# Design gaps 0.8.1 — re-inventory r2

Branch `heap2/0.8.1` at 406d188. Fresh pass: every sheet in `New heap design/screens` (H2-/N- bold, Q-/X- quiet) compared side by side with offscreen captures of the real `Main.qml` (QuickTest harness, isolated profiles, 1440×900 and 1280×720, both styles, dark and light). The previous report was not used as a source.

Not gaps (accepted): everything in `docs/DESIGN-DECISIONS.md`, the one detail line on bold cards, the sort chip, the weekly recap line on Today, the lavender accent options, "только здесь", Ctrl F = filter, tone.

Severity: **S** wrong structure / legacy component visible · **A** clearly off from the sheet · **B** visible detail · **C** minor · **D** cosmetic nit.

## Summary

| S | A | B | C | D | total |
|---|---|---|---|---|---|
| 3 | 6 | 23 | 27 | 13 | 72 |


### S — structure / legacy

- **R2-032** (Sync conflict (X-/N-Dlg-Conflict)) — sheet: one table: field rows × "У вас" / "В Jira" columns, picked cell outlined → app: legacy stacked form: "Конфликт: APP-109", per field "Здесь / В трекере" lines with two buttons each ("Оставить моё (отправить)" / "Взять из трекера"),
- **R2-037** (Storage (X-/N-Err-Storage)) — sheet: write failure: full-width strip "ⓘ Не сохраняется: на диске C: нет места." + "Изменения пока в памяти, пробуем → app: legacy StorageBanner: red-outlined strip flush to the window top, red dot, one long sentence, "Открыть папку данных" + "Скрыть" (dismissable)
- **R2-041** (Small dialogs (X-/N-Dlg-Small)) — sheet: "Удалить колонку «На паузе»?" in the SmallDialog template: fact "В ней 2 задачи. Колонку можно вернуть через C → app: legacy QQC.Dialog: small title, big empty band, "Карточек переедет в первую колонку: 2. Действие можно отменить.", no target-column picker, odd dark n

### A — clearly off

- **R2-001** (Today (H2-Today / H2-Today-Calm)) — sheet: bold screen title 30px/600 ("Четверг, 8 октября") → app: ~22px (fsXl) - same on Задачи/Настройки headers
- **R2-016** (Archive (X-Oth-Archive-People, left)) — sheet: chip "статус в архиве ×" → app: chip "это archived ×" - raw English token, wrong key word
- **R2-034** (Tracker errors (X-/N-Err-Tracker)) — sheet: card marks inline in the meta line in the sheet's words: "ждёт отправки статуса" → app: coloured tag pills above the title: "не отправлено" (amber fill), "вне фильтра" (grey text), "нет в трекере" (amber fill), "⇄ конфликт" (amber outline
- **R2-035** (Tracker errors (X-/N-Err-Tracker)) — sheet: strip above Задачи per tracker problem (ⓘ/◌ icon, bold fact, consequence, underlined action, ×): "GitHub: вход → app: no such strip exists (no strings, no component)
- **R2-038** (Storage (X-/N-Err-Storage)) — sheet: (lowkey brand everywhere) → app: the empty workspace after a damaged file names its profile "heap" (old brand) in the sidebar
- **R2-048** (Toasts & sync indicator (X-/N-Ntf-Toasts)) — sheet: sync indicator at the profile name: green dot = synced (tip "2 мин назад"), "◔ синк…" while running, "○ 1 ошиб → app: the dot is the profile colour (accent blue) at rest, only turns "live" while a sync runs

### B — visible detail

- **R2-002** (Today (H2-Today / H2-Today-Calm)) — sheet: quiet title 26px → app: ~22px
- **R2-003** (Today (H2-Today / H2-Today-Calm)) — sheet: quiet: no eyebrow above the date → app: "Сегодня · выходной" eyebrow in quiet
- **R2-005** (Board (H2-Board / Q-Board)) — sheet: bold card titles 600 (heavier than body) → app: 500 (fwTitle Medium)
- **R2-008** (List (H2-List / Q-List)) — sheet: bold row title 600 → app: regular 400 - rows read flat vs the sheet
- **R2-011** (Calendar (H2-Calendar / Q-Calendar / X-Oth-DayMonth)) — sheet: quiet "Без даты · 3" header only, no hint, no panel divider → app: bold "Без даты 3" + "Перетащите в нужный час…" hint + divider/bg in quiet
- **R2-013** (Task document (H2-Task / Q-Task)) — sheet: meta column reads top-down: Код, Упоминается в, Время, История, then (quiet) a small "Готово" right under Исто → app: История and quiet "Готово" are pinned to the bottom of the meta column - a 400-550px hole after Время in panel and full mode
- **R2-017** (Archive (X-Oth-Archive-People, left)) — sheet: (empty state follows DG-160 "Ничего под «…»" with the filter as typed) → app: "Ничего под «is:archived»" - raw query syntax in the empty state
- **R2-020** (Knowledge (H2-Knowledge / Q-Knowledge)) — sheet: inline code `login:<email>`, `Retry-After` in JetBrains Mono inside a hairline pill → app: Qt rich-text <code> default face (not the bundled "lowkey JetBrains Mono"
- **R2-024** (Knowledge inserts / slash (X-/N-Oth-Knowledge)) — sheet: "/" menu: Чек-лист [] · Код ``` · Ссылка на задачу [[ · Картинка или файл · Таблица · Справочник (RFC, ссылка) → app: Чек-лист · Блок кода · Ссылка на задачу · Заголовок · Таблица · Цитата · Просто /
- **R2-033** (Sync conflict (X-/N-Dlg-Conflict)) — sheet: not-yours write: "Тикет назначен Маше К." · "Изменить статус APP-117 в Jira от вашего имени? Обычно lowkey не  → app: "Всё равно отправить статус?" · "<key> «title» больше не в вашем фильтре <Tracker>. Сейчас там статус «…»
- **R2-036** (Tracker errors (X-/N-Err-Tracker)) — sheet: first-load panel "Jira: загружаем ваши тикеты 120 из ~400" with rows filling in + skeleton rows + "Можно работ → app: not present (no strings)
- **R2-039** (Storage (X-/N-Err-Storage)) — sheet: (copy in the UI language) → app: banner text in English in a Russian UI ("Your data file was damaged…") - composed at load before the language is known and never re-translated
- **R2-040** (Storage (X-/N-Err-Storage)) — sheet: keychain card "Не удаётся сохранить вход в Jira" (Хранить в файле / Повторить) and "Сообщить о проблеме" form  → app: no in-app keychain prompt (silent secrets.json fallback)
- **R2-042** (Small dialogs (X-/N-Dlg-Small)) — sheet: @-autocomplete: rows "Олег Т." + role right ("Tech Lead"), "+ Добавить «ол» как человека" last row → app: one row "@o.t · Олег Т." (handle first, mono, no role), no add-person row
- **R2-052** (Notifications, timer, update (X-/N-Ntf-OS, X-/N-Ntf-Focus)) — sheet: running timer line in the sidebar under "Новая задача…": "◑ Обход ограничения попыток  0:42  ⏸ T" → app: no sidebar line while a timer runs (both styles)
- **R2-053** (Notifications, timer, update (X-/N-Ntf-OS, X-/N-Ntf-Focus)) — sheet: quiet line at the sidebar bottom "0.8.1 готова · перезапустить · что нового" → app: an available/ready update is a 10-30 s toast with an action ("Доступно обновление: …" Скачать / Обновить / Перезапустить) and Settings → О программе
- **R2-054** (Notifications, timer, update (X-/N-Ntf-OS, X-/N-Ntf-Focus)) — sheet: "Что нового в 0.8.0" dialog once after an update (sections, "Что переехало", Понятно) → app: not implemented (no component/strings
- **R2-058** (First run (H2-First / Q-First)) — sheet: sidebar "Мои виды" + hint "Появятся, когда сохраните фильтр" (bold) → app: four starter views (Заблокировано, На ревью, Срочное, Эта неделя) already listed on an empty profile, both styles
- **R2-062** (Menus (X-/N-Menus-*)) — sheet: note menu: header "Заметка «Дизайн rate-limit»", Открыть ↵, Закрепить, Переименовать F2, Копировать ссылку [[… → app: no header, no Открыть / Копировать ссылку / Экспорт в .md, no keys
- **R2-063** (Menus (X-/N-Menus-*)) — sheet: person menu on "Кому написать": header "Олег Т. · Tech Lead", Написал — убрать из списка, Изменить вопрос…, (С → app: right-click on a person does nothing (no menu in TodayView or PeopleDialog
- **R2-067** (Today on another day (H2-Today)) — sheet: (H2-Today rows never overlap) → app: another day with nothing planned (bold, пт 9 окт): "в «Задачах» 3 без даты" is drawn on top of "Свободно 10 ч" on the same line - text collision
- **R2-069** (Quick note, import, scope, drag (X-Oth-Capture, X-Dlg-Log-Import, X-Dlg-Event, X-Oth-Select-Drag)) — sheet: quick note (Ctrl Shift N): compact card "lowkey быстрая заметка → «Входящие»", "прикрепить к APP-101 ▾", small → app: large dialog "Быстрая заметка → <active note>", tall text area, instructions inside the placeholder, footer hint + Отмена / Сохранить buttons
- **R2-070** (Quick note, import, scope, drag (X-Oth-Capture, X-Dlg-Log-Import, X-Dlg-Event, X-Oth-Select-Drag)) — sheet: "Импорт папки Markdown": path (mono), "42 файла · 38 станут заметками · из 4 чек-листов — 12 задач", skipped-f → app: "Импорт папки заметок": path, one dense sentence "Файлов: 2. Новых — 2, обновятся с диска — 0, …", no checkboxes, Отмена / Импортировать

### Close to the sheet (no gap above D)

Time Machine, event log, key cheat sheet, settings (style switches, key rebinding + conflict box, columns table,
calendar / notifications / safety, Git / language / help / about), multi-select + selection bar, meeting panel,
end of day, "Убрать пример?", new profile / person / saved-view template, undo toast with "+N", column / saved-view /
profile / task menus and their priority / status lists, the command line (both styles), month view.

## Capture notes

- Captures: `C:/Users/Fin/AppData/Local/Temp/claude/C--Users-Fin-CLionProjects-todolist/94cfdb4b-65f9-46d8-b85c-958b3a86d2cd/scratchpad/r2/app` (`<style>-<screen>.png`; `-x-` = extra states, `-trk-` = tracker flags fixture, `-err-` = damaged state file, `-first-` = empty profile).
- The run was on Saturday 10 Oct at ~02:00: Today was a weekend day with nothing planned (no task rows, free-time rows, now-line or end-of-day line to compare), and the week/day grids scrolled to night hours. Planned-task rows on Today could not be compared.
- Not verifiable offscreen: modal scrims (the dimmer is not grabbed — no scrim finding is made), light-theme text weight (transparent grabs darken antialiasing; only structure and colours were judged in light), menu position at the pointer (no cursor offscreen).
- Not captured: the Git "работаю над …" line (needs a watched repo), OS notifications and the tray menu (system surfaces), the global capture window over other apps, JSON profile import, the splash; tracker error strip / first-load / keychain card and sync popover are judged by code (they do not exist), marked "code read".
- One finding from the first pass was withdrawn after checking: the board losing "не готово" after the archive was the harness pressing Esc (DG-160 clears the filter), not a bug.


## Today (H2-Today / H2-Today-Calm)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-001 | A | bold screen title 30px/600 ("Четверг, 8 октября") | ~22px (fsXl) - same on Задачи/Настройки headers | qml/Theme.qml (fsXl), qml/TodayView.qml, qml/TopBar.qml |
| R2-002 | B | quiet title 26px | ~22px | same |
| R2-003 | B | quiet: no eyebrow above the date | "Сегодня · выходной" eyebrow in quiet | qml/TodayView.qml |
| R2-004 | D | quiet "▸ Кому написать · 2" filled triangle | ">" line chevron | qml/TodayView.qml |

## Board (H2-Board / Q-Board)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-005 | B | bold card titles 600 (heavier than body) | 500 (fwTitle Medium); reads lighter than the sheet | qml/TaskCard.qml, qml/Theme.qml fwTitle |
| R2-006 | C | priority mark only for P0/P1 (bold), only P0 (quiet) | P2/P3 grey on every bold card; P1 on quiet cards | qml/TaskCard.qml |
| R2-007 | D | quiet tabs 14px | 13px | qml/LensTabs.qml |

## List (H2-List / Q-List)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-008 | B | bold row title 600 | regular 400 - rows read flat vs the sheet | qml/TaskListView.qml |
| R2-009 | C | quiet shows only P0 | P1 marks in quiet rows | qml/TaskListView.qml |
| R2-010 | D | quiet "Без даты · 3" one grey line | "Без даты" bold label + grey "· 3" | qml/TaskListView.qml |

## Calendar (H2-Calendar / Q-Calendar / X-Oth-DayMonth)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-011 | B | quiet "Без даты · 3" header only, no hint, no panel divider | bold "Без даты 3" + "Перетащите в нужный час…" hint + divider/bg in quiet | qml/UndatedTray.qml / UnscheduledRail.qml |
| R2-012 | D | quiet: no today-column tint | faint tint on today's column in quiet | qml/WeekView.qml |

## Task document (H2-Task / Q-Task)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-013 | B | meta column reads top-down: Код, Упоминается в, Время, История, then (quiet) a small "Готово" right under История (DG-065) | История and quiet "Готово" are pinned to the bottom of the meta column - a 400-550px hole after Время in panel and full mode | qml/TaskDocument.qml |
| R2-014 | C | title, chips and body share one left edge (x=248 bold / 256 quiet) | title +5px, body +9px inset vs chips (editor padding) - three ragged edges | qml/TaskDocument.qml, qml/MdBlockEditor.qml |
| R2-015 | D | "+ свойство" on its own line under the chips | inline after the last chip | qml/TaskDocument.qml |

## Archive (X-Oth-Archive-People, left)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-016 | A | chip "статус в архиве ×" | chip "это archived ×" - raw English token, wrong key word | qml/QueryBar.qml / FilterBar.qml (is:archived chip label), qml/I18n.qml |
| R2-017 | B | (empty state follows DG-160 "Ничего под «…»" with the filter as typed) | "Ничего под «is:archived»" - raw query syntax in the empty state | qml/TaskListView.qml / EmptyState |

## People (X-Oth-Archive-People, right)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-018 | C | state words "ждёт" / "написал вчера" / "ответила" | "написать" / "написал" / "ответил" (no when, no gender agreement) | qml/PeopleDialog.qml, qml/I18n.qml |
| R2-019 | D | "+ человек · Ctrl Shift U" right under the last person | pinned to the dialog bottom, a big empty gap above | qml/PeopleDialog.qml |

## Knowledge (H2-Knowledge / Q-Knowledge)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-020 | B | inline code `login:<email>`, `Retry-After` in JetBrains Mono inside a hairline pill | Qt rich-text <code> default face (not the bundled "lowkey JetBrains Mono"; renders as a fallback bitmap-like face offscreen, Courier on Windows), grey fill, no border - same in task descriptions | src/markdown/MdHtml.cpp (InlineType::Code), qml/MdView.qml |
| R2-021 | C | paragraphs and headings share one left edge | paragraphs inset ~8px right of the headings (both styles) | src/markdown/MdHtml.cpp / qml/MdView.qml |
| R2-022 | C | pinned row tags "RFC" / "RFC" / "API" | third tag reads "Open" (first word of "OpenAPI"), title "Спецификация OpenAPI · 3.1" | qml/NotesListPane.qml, qml/DocsStarter.js |
| R2-023 | C | quiet inline task ref "◑ APP-101" as underlined text link | grey filled pill (bold treatment) in quiet | src/markdown/MdHtml.cpp / qml/MdView.qml (Style.textLinks) |

## Knowledge inserts / slash (X-/N-Oth-Knowledge)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-024 | B | "/" menu: Чек-лист [] · Код ``` · Ссылка на задачу [[ · Картинка или файл · Таблица · Справочник (RFC, ссылка); first row highlighted; keys right | Чек-лист · Блок кода · Ссылка на задачу · Заголовок · Таблица · Цитата · Просто /; no keys, no row preselected, empty left icon gutter; no "Картинка или файл" / "Справочник" entries | qml/MdBlockEditor.qml (slashMenu), qml/I18n.qml md.slash.* |

## Settings (H2-/Q-Settings, X-Set-*)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-025 | C | H2-Settings: sidebar without "Мои виды", keys and the bottom "Настройки" while in Settings | full sidebar (views, Ctrl keys, active "Настройки" at the bottom) - matches Q-Settings, not H2 | qml/Sidebar.qml |
| R2-026 | C | Q-Settings rows carry no hint (Тема, Плотность, Анимации) and sections no subtitle; only "Акцент · цвет выделения" | bold hints and section subtitles shown in quiet too | qml/SettingsView.qml, qml/SettingsRow.qml |
| R2-027 | C | X-Set-Trackers list: Jira, GitHub, GitLab, Linear, Trello, Todoist, state words right ("чтение", "вход истёк"), green dot when connected | 14 providers (no Linear; Gitea, Forgejo, Redmine, Asana, ClickUp, Sentry, Bitbucket, Mattermost…), connected dot neutral | qml/SettingsView.qml (integrations), src/integrations/ProviderRegistry.cpp |
| R2-028 | C | status mapping dropdown shows the column's status ring + name | name only | qml/SettingsView.qml |
| R2-029 | D | "+ Колонка" | "+ колонка"; stage dropdowns with a bright full-white border (sheet: hairline) | qml/SettingsView.qml, qml/AppComboBox.qml |

## Command line (H2-Command / Q-Command)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-030 | D | chips in the input have no × (bold & quiet) | each chip carries × | qml/CommandPalette.qml |
| R2-031 | D | ↵ glyph for Enter (row and footer) | a left-arrow-like glyph "←" at 11px; reads as "back" | qml/CommandPalette.qml, qml/KeyHint.qml / Icon.qml |

## Sync conflict (X-/N-Dlg-Conflict)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-032 | S | one table: field rows × "У вас" / "В Jira" columns, picked cell outlined; title "APP-101 изменили и у вас, и в Jira" + "Вы — сегодня 14:58, Jira (Олег Т.) — 15:20…"; "Не меняется: мои заметки, мой срок (пт), метки «auth», связи."; buttons Позже · Всё из Jira · Всё моё · Применить выбор ↵ | legacy stacked form: "Конфликт: APP-109", per field "Здесь / В трекере" lines with two buttons each ("Оставить моё (отправить)" / "Взять из трекера"), single "Закрыть"; no times, no "не меняется" line, no bulk actions | qml/SyncConflictDialog.qml |
| R2-033 | B | not-yours write: "Тикет назначен Маше К." · "Изменить статус APP-117 в Jira от вашего имени? Обычно lowkey не трогает чужие тикеты." · [Только у меня] (primary) [Всё равно отправить] | "Всё равно отправить статус?" · "<key> «title» больше не в вашем фильтре <Tracker>. Сейчас там статус «…»; отправка сменит его на «…»." · [Отмена] [Всё равно отправить] in danger red | qml/TrackerPushConfirmDialog.qml, qml/I18n.qml |

## Tracker errors (X-/N-Err-Tracker)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-034 | A | card marks inline in the meta line in the sheet's words: "ждёт отправки статуса"; dashed card "вне фильтра Jira — только у вас"; struck-through title + "удалён в Jira · оставить у себя / убрать"; "изменён и у вас, и в Jira · решить" | coloured tag pills above the title: "не отправлено" (amber fill), "вне фильтра" (grey text), "нет в трекере" (amber fill), "⇄ конфликт" (amber outline); no dashed border, no strike-through, no inline "оставить у себя / убрать" / "решить" actions | qml/TaskCard.qml, qml/I18n.qml taskcard.* |
| R2-035 | A | strip above Задачи per tracker problem (ⓘ/◌ icon, bold fact, consequence, underlined action, ×): "GitHub: вход истёк в 12:10…Войти снова", "Jira просит подождать (429)…Повторить сейчас", "загружено 38 из 41…Подробнее", "Нет сети…Журнал" | no such strip exists (no strings, no component); sync failures only reach the log and toasts | qml/Main.qml / TopBar.qml (missing), qml/I18n.qml |
| R2-036 | B | first-load panel "Jira: загружаем ваши тикеты 120 из ~400" with rows filling in + skeleton rows + "Можно работать дальше — загрузка идёт в фоне." | not present (no strings) | (missing) qml/KanbanBoard.qml / TaskListView.qml |

## Storage (X-/N-Err-Storage)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-037 | S | write failure: full-width strip "ⓘ Не сохраняется: на диске C: нет места." + "Изменения пока в памяти, пробуем каждые 30 с…" + one button "Сохранить копию в другое место…", never self-dismissing; damaged file: card "Файл данных повреждён" with snapshot choices (Последний снимок…, Снимок перед закрытием…, Начать с пустого профиля) + Показать файлы / Восстановить | legacy StorageBanner: red-outlined strip flush to the window top, red dot, one long sentence, "Открыть папку данных" + "Скрыть" (dismissable); no snapshot choice card | qml/StorageBanner.qml, src/AppController.cpp (data.corruptKept) |
| R2-038 | A | (lowkey brand everywhere) | the empty workspace after a damaged file names its profile "heap" (old brand) in the sidebar | src/AppController.cpp:12094, :12174 makeStartingProfile("heap") |
| R2-039 | B | (copy in the UI language) | banner text in English in a Russian UI ("Your data file was damaged…") - composed at load before the language is known and never re-translated | src/AppController.cpp setStorageState / tr_ |
| R2-040 | B | keychain card "Не удаётся сохранить вход в Jira" (Хранить в файле / Повторить) and "Сообщить о проблеме" form (checkboxes, log preview, Копировать / Открыть issue на GitHub) | no in-app keychain prompt (silent secrets.json fallback); "Сообщить о проблеме" opens GitHub directly, no preview form (code read) | qml/SettingsView.qml, src/SecretStore* |

## Small dialogs (X-/N-Dlg-Small)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-041 | S | "Удалить колонку «На паузе»?" in the SmallDialog template: fact "В ней 2 задачи. Колонку можно вернуть через Ctrl Z.", field "Перенести задачи в [К выполнению ▾]", Отмена / Удалить колонку | legacy QQC.Dialog: small title, big empty band, "Карточек переедет в первую колонку: 2. Действие можно отменить.", no target-column picker, odd dark notch at the top-right corner | qml/KanbanBoard.qml:1963 (confirmDelete) |
| R2-042 | B | @-autocomplete: rows "Олег Т." + role right ("Tech Lead"), "+ Добавить «ол» как человека" last row | one row "@o.t · Олег Т." (handle first, mono, no role), no add-person row; the popup covers the parsed-chips row | qml/MentionAutocomplete.qml |
| R2-043 | C | "Открыть ссылку в браузере?" for a link from a task to an external site (https), field "Адрес" (mono), Копировать / Открыть | https links open with no question; the dialog (non-web schemes only) is a QQC.Dialog with Отмена as the second button, no Копировать (code read, not drawn) | qml/LinkConfirmDialog.qml |
| R2-044 | C | new profile colour dots muted (slate, sage, lavender, tan, salmon, grey, steel, olive) | saturated set (cyan, blue, lavender, violet, red, orange, gold, green) | qml/ProfileEditor.qml / Theme swatches |
| R2-045 | C | "Сохранить как вид": Название prefilled readable ("Заблокировано · P0") | prefilled with the raw query ("статус:заблокировано p0") | qml/SavedViewNameDialog.qml |

## Capture (X-/N-Oth-Capture)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-046 | C | chip "когда пт, 9 окт · 11:00" | "когда завтра, вс, 11 окт, 11:00" (word + date, commas) with a × | qml/QuickCapturePopup.qml, qml/CaptureParse / TaskDates.js |
| R2-047 | D | typed "завтра 11:00 p1" highlighted one colour (accent) | date in accent, "p1" in amber | qml/QuickCapturePopup.qml (SpanHighlighter) |

## Toasts & sync indicator (X-/N-Ntf-Toasts)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-048 | A | sync indicator at the profile name: green dot = synced (tip "2 мин назад"), "◔ синк…" while running, "○ 1 ошибка", "◌ офлайн" in words; click opens a popover with each source (Jira 2 мин назад · 41 тикет / GitHub вход истёк · войти / Календарь ICS / GitLab ждёт сети) + "Синхронизировать всё · Ctrl Shift R" | the dot is the profile colour (accent blue) at rest, only turns "live" while a sync runs; no error/offline words; click jumps to Settings → Трекеры, no per-source popover | qml/ProfileSwitcher.qml (syncDot), qml/Main.qml:991 |

## Dialogs: standup, event, other (X-/N-Dlg-Recap, -Event)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-049 | C | draft as sentences: "Вчера: закрыл APP-111, APP-112." / "Сегодня: …" / "Блокеры: …"; Копировать is the primary (bright outline) | Markdown bullets with "- —" for an empty day; Копировать and Закрыть look the same | qml/StandupDraftDialog.qml, src (standup draft text) |
| R2-050 | C | day rows 26px apart with bars | rows ~19px apart, cramped against the 5-line block | qml/WeeklyRecapDialog.qml |
| R2-051 | C | one-line meeting input highlights what it understood ("пт 16:00", "на 1 ч", "каждые 2 недели" in accent) | typed text stays plain white; only the chips show the parse | qml/EventCapture.qml |

## Notifications, timer, update (X-/N-Ntf-OS, X-/N-Ntf-Focus)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-052 | B | running timer line in the sidebar under "Новая задача…": "◑ Обход ограничения попыток  0:42  ⏸ T" | no sidebar line while a timer runs (both styles); the timer shows only on the card | qml/Sidebar.qml |
| R2-053 | B | quiet line at the sidebar bottom "0.8.1 готова · перезапустить · что нового" | an available/ready update is a 10-30 s toast with an action ("Доступно обновление: …" Скачать / Обновить / Перезапустить) and Settings → О программе; no sidebar line (code read) | qml/Sidebar.qml, qml/Main.qml:959-970 |
| R2-054 | B | "Что нового в 0.8.0" dialog once after an update (sections, "Что переехало", Понятно) | not implemented (no component/strings; APP-120 planned); "Что нового" opens GitHub release notes | (missing) qml/Main.qml |
| R2-055 | C | card timer in m:ss ("0:42") | card shows "• 3s" (English unit) and in quiet pushes "P0" past the card edge (clipped) | qml/TaskCard.qml |
| R2-056 | C | splash "lowkey 0.8.0" and the launch card "Прошлый раз lowkey закрылся неожиданно … Посмотреть отчёт · Не отправлять" | no crash-on-last-run card (code read); splash exists (SplashScreen.qml, not captured) | (missing) qml/Main.qml |
| R2-057 | D | top-left "погружение · 3 события подождут" | "погружение" only (count part not drawn when 0 waiting — unverified with events) | qml/ImmersionView.qml |

## First run (H2-First / Q-First)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-058 | B | sidebar "Мои виды" + hint "Появятся, когда сохраните фильтр" (bold); quiet shows no views block at all | four starter views (Заблокировано, На ревью, Срочное, Эта неделя) already listed on an empty profile, both styles | qml/Sidebar.qml, src/AppController.cpp (starter views) |
| R2-059 | C | profile "Личное" | "Personal" in the Russian UI (the test seeds the profile before the language is set; check on a ru system) | src/AppController.cpp makeStartingProfile |

## Small window (X-/N-Oth-Small, 1280x720)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-060 | C | rail: mark at the top, 3 section icons, settings at the bottom; the three side facts in tight columns (84 / 336 / 557) | no mark at the top (only the profile dot), four extra saved-view icons (bookmark 1-4) in the rail; side facts spread in thirds (80 / 480 / 880) | qml/Sidebar.qml (compact), qml/TodayView.qml |
| R2-061 | C | (owner question) the sheet's rail mark is "h." - the old heap monogram; lowkey has no compact mark yet | app shows none | brand - owner |

## Menus (X-/N-Menus-*)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-062 | B | note menu: header "Заметка «Дизайн rate-limit»", Открыть ↵, Закрепить, Переименовать F2, Копировать ссылку [[…]], Экспорт в .md, Удалить | no header, no Открыть / Копировать ссылку / Экспорт в .md, no keys; extra "Слить с открытой" (code read + capture) | qml/NotesListPane.qml rowMenu |
| R2-063 | B | person menu on "Кому написать": header "Олег Т. · Tech Lead", Написал — убрать из списка, Изменить вопрос…, (Связанные задачи - DG-002), Удалить человека | right-click on a person does nothing (no menu in TodayView or PeopleDialog; people.menu.cycle/delete strings unused) | qml/TodayView.qml, qml/PeopleDialog.qml |
| R2-064 | C | items start on the header's left edge (one column, no icon gutter) | every AppMenu item is indented ~20px past its header (an empty icon column) - task, column, slot, slash menus | qml/AppMenuItem.qml / AppMenu.qml |
| R2-065 | D | "Переместить в колонку" list: no keys except Готово d | digits 1-7 on every column row | qml/TaskMenuHost.qml statusMenu |

## Board, cursor (Q-Board)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-066 | C | quiet cards never show a detail line | the card under the keyboard cursor grows the description line in quiet (owner's detail line is bold-only) | qml/TaskCard.qml |

## Today on another day (H2-Today)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-067 | B | (H2-Today rows never overlap) | another day with nothing planned (bold, пт 9 окт): "в «Задачах» 3 без даты" is drawn on top of "Свободно 10 ч" on the same line - text collision | qml/TodayView.qml |
| R2-068 | C | eyebrow "Сегодня" over the date (bold) | on another day the eyebrow repeats the date ("пятница, 9 октября" over "Пятница, 9 октября") | qml/TodayView.qml |

## Quick note, import, scope, drag (X-Oth-Capture, X-Dlg-Log-Import, X-Dlg-Event, X-Oth-Select-Drag)

| id | sev | sheet shows | app shows | likely files |
|---|---|---|---|---|
| R2-069 | B | quick note (Ctrl Shift N): compact card "lowkey быстрая заметка → «Входящие»", "прикрепить к APP-101 ▾", small text area, footer "Ctrl ↵ сохранить · Esc — черновик сохранится", no buttons | large dialog "Быстрая заметка → <active note>", tall text area, instructions inside the placeholder, footer hint + Отмена / Сохранить buttons | qml/QuickCaptureNotesPopup.qml |
| R2-070 | B | "Импорт папки Markdown": path (mono), "42 файла · 38 станут заметками · из 4 чек-листов — 12 задач", skipped-files line, checkboxes "Пункты «- [ ]» превращать в задачи" / "Следить за папкой…", Другая папка / Импортировать | "Импорт папки заметок": path, one dense sentence "Файлов: 2. Новых — 2, обновятся с диска — 0, …", no checkboxes, Отмена / Импортировать | qml/VaultImportDialog.qml |
| R2-071 | C | the dragged card leaves a dashed faded placeholder in its source column | the source slot collapses (no placeholder); target frame + ghost match | qml/KanbanBoard.qml |
| R2-072 | D | series scope: unchecked radios clearly visible, keys on buttons "Отмена Esc" / "Перенести ↵" | unchecked radios nearly invisible, no key hints on the buttons | qml/SeriesScopeDialog.qml |
