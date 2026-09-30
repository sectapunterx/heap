import QtQuick
import QtQuick.Layouts
import TodoCpp

Item {
    id: root

    signal anchorRequested(string objectName)

    implicitHeight: col.implicitHeight
    implicitWidth: col.implicitWidth

    // The guide is written in both languages side by side; the one shown
    // follows I18n.lang, and switching repaints it (it was English only).
    function tr2(en, ru) { return I18n.lang === "ru" ? ru : en; }
    // A key chip shows the live binding, so a rebind (or a changed default)
    // cannot leave the guide naming the wrong keys.
    function kbd(id) {
        const list = AppController.shortcuts;
        for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i].sequence;
        return "";
    }

    readonly property var tocModel: [
        {anchor: "help-views", label: root.tr2("Views — Board, Timeline, Week, Month, Archive, Docs, Notes, day panel", "Виды — доска, лента, неделя, месяц, архив, доки, заметки, панель дня")},
        {anchor: "help-tasks", label: root.tr2("Tasks — statuses, priorities, deadlines", "Задачи — статусы, приоритеты, сроки")},
        {anchor: "help-capture", label: root.tr2("Quick Capture — text parsing, @-mentions", "Быстрый ввод — разбор текста, @-упоминания")},
        {anchor: "help-calendar", label: root.tr2("Calendar — events, drag-create, focus blocks", "Календарь — события, создание перетаскиванием, фокус-блоки")},
        {anchor: "help-people", label: root.tr2("People — contacts, mentions, state cycle", "Люди — контакты, упоминания, цикл состояний")},
        {anchor: "help-profiles", label: root.tr2("Profiles — workspaces, JSON", "Профили — рабочие пространства, JSON")},
        {anchor: "help-search", label: root.tr2("Search & Command Palette", "Поиск и палитра команд")},
        {anchor: "help-filter", label: root.tr2("Filters — priorities, archived, show-done", "Фильтры — приоритеты, архив, выполненные")},
        {anchor: "help-tweaks", label: root.tr2("Tweaks — theme, density, contrast", "Твики — тема, плотность, контраст")},
        {anchor: "help-hotkeys", label: root.tr2("Hotkeys — rebinding and conflicts", "Горячие клавиши — переназначение и конфликты")},
        {anchor: "help-automation", label: root.tr2("Automation & Notifications", "Автоматизация и уведомления")},
        {anchor: "help-git", label: root.tr2("Git Watcher — branch focus, PR", "Git Watcher — фокус по ветке, PR")},
        {anchor: "help-integrations", label: root.tr2("Integrations — trackers, tokens, OAuth, JQL", "Интеграции — трекеры, токены, OAuth, JQL")},
        {anchor: "help-undo", label: root.tr2("Undo & Backups", "Отмена и бэкапы")},
        {anchor: "help-data", label: root.tr2("Data — JSON import/export, reset", "Данные — импорт/экспорт JSON, сброс")},
        {anchor: "help-tips", label: root.tr2("Tips & non-obvious things", "Советы и неочевидные вещи")}
    ]

    component HelpCard: Rectangle {
        Layout.fillWidth: true
        radius: Theme.radiusLg
        color: Theme.panel
        border.color: Theme.border
        border.width: 1
        default property alias content: inner.data
        implicitHeight: inner.implicitHeight + 24
        ColumnLayout {
            id: inner
            anchors.fill: parent
            anchors.margins: Theme.sp2xl
            spacing: Theme.spLg
        }
    }

    component H2: Text {
        color: Theme.text
        font.pixelSize: Theme.fsLg
        font.weight: Font.DemiBold
        font.family: Theme.fontMono
        Layout.fillWidth: true
    }

    component H3: Text {
        color: Theme.accentStrong
        font.pixelSize: Theme.fsMd
        font.family: Theme.fontMono
        font.weight: Font.DemiBold
        font.letterSpacing: 0.5
        Layout.fillWidth: true
        Layout.topMargin: Theme.spSm
    }

    component Body: Text {
        color: Theme.text
        font.pixelSize: Theme.fsMd
        wrapMode: Text.WordWrap
        lineHeight: 1.35
        Layout.fillWidth: true
    }

    component Hint: Text {
        color: Theme.textMuted
        font.pixelSize: Theme.fsSm
        wrapMode: Text.WordWrap
        font.italic: true
        Layout.fillWidth: true
    }

    component Kbd: Text {
        property string keys: ""
        text: keys
        color: Theme.accentStrong
        font.family: Theme.fontMono
        font.pixelSize: Theme.fsSm
        font.weight: Font.DemiBold
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.sp2xl

        // ─────────────────────────────────────────── Intro
        HelpCard {
            RowLayout {
                spacing: Theme.spXl
                Layout.fillWidth: true
                Rectangle {
                    width: 36; height: 36; radius: Theme.radius
                    color: Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: "?"
                        color: Theme.textOnAccent
                        font.pixelSize: Theme.fsXl
                        font.weight: Font.Bold
                    }
                }
                ColumnLayout {
                    spacing: Theme.sp2xs
                    Layout.fillWidth: true
                    H2 {
                        text: root.tr2("heap. help.",
                                      "Справка heap.")
                    }
                    Text {
                        text: root.tr2("Everything the app can do, in one place.",
                                      "Всё, что умеет приложение, в одном месте.")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fsSm
                    }
                }
            }
            Body {
                text: root.tr2("heap. — a developer's workday laid out across widgets: board, timeline, week and month calendars, a day panel, notes and documentation. Everything stays local in JSON; nothing goes to the cloud unless you connect a tracker. Below — a tour of the sections. Click an item in the table of contents to jump to the topic you need.",
                              "heap. — рабочий день разработчика, разложенный по виджетам: доска, лента, календари недели и месяца, панель дня, заметки и документация. Всё хранится локально в JSON; в облако ничего не уходит, пока вы сами не подключите трекер. Ниже — обзор разделов. Нажмите пункт оглавления, чтобы перейти к нужной теме.")
            }
            PillButton {
                Layout.topMargin: Theme.sp2xs
                text: I18n.t("welcome.replay")
                onClicked: AppController.replayWelcome()
            }
        }

        // ─────────────────────────────────────────── TOC
        HelpCard {
            H2 {
                text: root.tr2("Table of Contents",
                              "Оглавление")
            }
            Repeater {
                model: root.tocModel
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    radius: Theme.radiusMd
                    color: tocMa.containsMouse ? Theme.panel2 : "transparent"
                    border.color: tocMa.containsMouse ? Theme.border : "transparent"
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.spLg
                        anchors.rightMargin: Theme.spLg
                        spacing: Theme.spMd
                        Text {
                            text: "›"
                            color: Theme.accentStrong
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsMd
                        }
                        Text {
                            text: modelData.label
                            color: tocMa.containsMouse ? Theme.accentStrong : Theme.text
                            font.pixelSize: Theme.fsMd
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        id: tocMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.anchorRequested(modelData.anchor)
                    }
                }
            }
        }

        // ─────────────────────────────────────────── VIEWS
        HelpCard {
            objectName: "help-views"
            H2 {
                text: root.tr2("Views — main screens",
                              "Виды — основные экраны")
            }
            Body {
                text: root.tr2("On the left in the sidebar — buttons for switching between views (Ctrl+1…8, in the sidebar's order). What is shown in the center is the current view. Board, Timeline, Week and Month all work with the same set of tasks, they just display them differently.",
                              "Слева на боковой панели — кнопки переключения видов (Ctrl+1…8, в порядке панели). В центре показан текущий вид. Доска, лента, неделя и месяц работают с одним и тем же набором задач — просто показывают его по-разному.")
            }

            H3 {
                text: root.tr2("Kanban Board",
                              "Доска (канбан)")
            }
            Body {
                text: root.tr2("Columns are statuses (To Do, In Progress, Review, Done, and any of your own). Cards are dragged between columns and reordered within them — a line shows where the card will land. A card shows: ID, priority (P0–P3), title, git branch (if set), and a time badge if the task is placed on the calendar. The mouse wheel scrolls the board horizontally.",
                              "Колонки — это статусы (К выполнению, В работе, Ревью, Готово и любые ваши). Карточки перетаскиваются между колонками и переставляются внутри них — линия показывает, куда карточка встанет. На карточке: ID, приоритет (P0–P3), название, git-ветка (если задана) и бейдж времени, если задача стоит в календаре. Колесо мыши прокручивает доску по горизонтали.")
            }
            Hint {
                text: root.tr2("Columns are configured in Settings → Tasks: rename, color, order, delete.",
                              "Колонки настраиваются в Настройки → Задачи: переименование, цвет, порядок, удаление.")
            }

            H3 {
                text: root.tr2("Timeline",
                              "Лента")
            }
            Body {
                text: root.tr2("Tasks are grouped into buckets: overdue / today / tomorrow / this week / next / later / no deadline. Within a bucket — subgroups by date. Completed tasks are hidden; you can turn them on with the 'Show done' toggle.",
                              "Задачи разложены по корзинам: просрочено / сегодня / завтра / на этой неделе / дальше / позже / без срока. Внутри корзины — подгруппы по датам. Выполненные скрыты; их можно показать переключателем «Показать выполненные».")
            }

            H3 {
                text: root.tr2("Week View",
                              "Неделя")
            }
            Body {
                text: root.tr2("7 days as columns. At the top — deadline chips (all-day), below — an hourly grid with events. An event can be dragged between days and hours; drag the top/bottom edge to change its duration.",
                              "7 дней колонками. Сверху — чипы сроков (на весь день), ниже — почасовая сетка с событиями. Событие можно перетащить между днями и часами; потяните за верхний или нижний край, чтобы изменить длительность.")
            }

            H3 {
                text: root.tr2("Month View", "Месяц")
            }
            Body {
                text: root.tr2("A month grid of deadlines and events, the week start from settings. Clicking a day selects it for the day panel; the arrows step a month, T goes to today, G picks any date.",
                              "Сетка месяца: сроки и события, начало недели — из настроек. Клик по дню выбирает его для панели дня; стрелки листают месяцы, T — к сегодняшнему дню, G — к любой дате.")
            }

            H3 {
                text: root.tr2("Archive", "Архив")
            }
            Body {
                text: root.tr2("Archived tasks of the active profile, newest first. Select several (Ctrl+A selects all visible) to restore or delete them at once.",
                              "Архивные задачи активного профиля, новые сверху. Выделите несколько (Ctrl+A — все видимые), чтобы вернуть или удалить их разом.")
            }

            H3 {
                text: root.tr2("Day Calendar (right panel)",
                              "Календарь дня (правая панель)")
            }
            Body {
                text: root.tr2("An hourly grid for the selected day. The current time is highlighted with a live line. Clicking an empty spot creates an hour-long event; a vertical drag — an event of the duration you need. Dropping a task card on the grid schedules a focus block for that hour.",
                              "Почасовая сетка выбранного дня. Текущее время отмечено живой линией. Клик по пустому месту создаёт событие на час; вертикальное перетаскивание — событие нужной длительности. Карточка задачи, брошенная на сетку, ставит фокус-блок на этот час.")
            }
            Hint {
                text: root.tr2("Workday bounds (9–19 by default) are changed in Settings → Calendar.",
                              "Границы рабочего дня (по умолчанию 9–19) меняются в Настройки → Календарь.")
            }

            H3 {
                text: root.tr2("Docs",
                              "Доки")
            }
            Body {
                text: root.tr2("Two halves. Pages is a tree of long-form markdown documents — the place for the paragraph explaining why something matters. Deleting a page takes everything under it, and that is undoable like anything else.",
                              "Две половины. Страницы — дерево длинных markdown-документов: место для абзаца, объясняющего, почему что-то важно. Удаление страницы забирает всё, что под ней, и отменяется, как любое другое действие.")
            }
            Body {
                text: root.tr2("References is the catalog: sections with tips, code snippets with syntax highlighting, and contact cards. The command palette searches across all of it at once.",
                              "Справочник — каталог: разделы с подсказками, сниппеты кода с подсветкой синтаксиса и карточки контактов. Палитра команд ищет по всему этому сразу.")
            }

            H3 {
                text: root.tr2("Notes",
                              "Заметки")
            }
            Body {
                text: root.tr2("As many notes as you like, with folders, pinning and a daily note. Three modes — editor only, split, preview — cycled with Ctrl+Shift+M. Autocomplete for @user and #ticket pulls in the people and tasks of the active profile.",
                              "Сколько угодно заметок, с папками, закреплением и заметкой дня. Три режима — только редактор, разделённый, просмотр — переключаются Ctrl+Shift+M. Автодополнение @пользователя и #тикета подтягивает людей и задачи активного профиля.")
            }
            Body {
                text: root.tr2("[[Double brackets]] link to another note by its title ([[Note#Heading]] to a section of it), falling back to a heading in the note you are in; renaming a note rewrites the links to it. Clicking one that points nowhere offers to write it. The Links pane shows which notes link here and where this note points. Clicking a #TICKET opens the task, an @person opens the person, a #tag filters the list. Ctrl+Alt+N makes a note, Ctrl+PgUp/PgDn steps through them, F2 renames, Ctrl+Alt+L folds the list away. Notes import and export as a folder of .md files with YAML frontmatter, which is what Obsidian and friends already read. Export writes into a new folder and never over existing files; import shows what will change first, keeps a note you edited here when the file did not change, keeps both versions when both did, and is undone with one Ctrl+Z.",
                              "[[Двойные скобки]] ссылаются на другую заметку по её названию ([[Заметка#Заголовок]] — на раздел в ней), а если такой нет — на заголовок в текущей; при переименовании заметки ссылки на неё переписываются. Клик по ссылке в никуда предлагает её написать. Панель «Ссылки» показывает, какие заметки ссылаются сюда и куда ссылается эта. Клик по #TICKET открывает задачу, по @человеку — карточку человека, по #тегу — фильтрует список. Ctrl+Alt+N создаёт заметку, Ctrl+PgUp/PgDn листают заметки, F2 переименовывает, Ctrl+Alt+L сворачивает список. Заметки импортируются и экспортируются папкой .md-файлов с YAML frontmatter — это то, что уже читают Obsidian и подобные. Экспорт пишет в новую папку и никогда не перезаписывает существующие файлы; импорт сначала показывает, что изменится, сохраняет заметку, отредактированную здесь, если файл не менялся, оставляет обе версии, если менялись оба, и отменяется одним Ctrl+Z.")
            }
            Body {
                text: root.tr2("Full markdown: headings, nested and task lists, tables, fenced code with syntax highlighting, quotes, footnotes and callouts like \"> [!WARNING] title\". In split mode the panes scroll together, clicking a rendered block moves the cursor to the line that produced it, and ticking a checkbox in the preview edits one character of the source — undoable like anything else.",
                              "Полный markdown: заголовки, вложенные списки и списки задач, таблицы, блоки кода с подсветкой, цитаты, сноски и выноски вида «> [!WARNING] заголовок». В разделённом режиме панели прокручиваются вместе, клик по отрисованному блоку ставит курсор на строку, из которой он получился, а галочка в просмотре правит один символ исходника — и отменяется, как всё остальное.")
            }
            Body {
                text: root.tr2("Formatting keys work while the cursor is in a note or a Docs page: Ctrl+B bold, Ctrl+I italic, Ctrl+E code, Ctrl+K link, Ctrl+Shift+X strikethrough, Ctrl+Shift+H highlight, Ctrl+Shift+L heading level, Tab and Shift+Tab to indent a list, Ctrl+Enter to tick a checkbox. With text selected they wrap the selection and act on every selected line. Enter continues the list or quote you are in.",
                              "Клавиши форматирования работают, пока курсор в заметке или на странице Docs: Ctrl+B — жирный, Ctrl+I — курсив, Ctrl+E — код, Ctrl+K — ссылка, Ctrl+Shift+X — зачёркивание, Ctrl+Shift+H — выделение, Ctrl+Shift+L — уровень заголовка, Tab и Shift+Tab — отступ в списке, Ctrl+Enter — отметить чекбокс. Если выделен текст, они оборачивают выделение и действуют на каждую выделенную строку. Enter продолжает список или цитату, в которой вы находитесь.")
            }
            Body {
                text: root.tr2("Images render from disk: an absolute path (C:\shots\x.png, file:///…) anywhere, a relative one from the attachments folder in heap's data folder. A remote image is shown as a link, with Load images to fetch it on request — heap makes no network requests you did not ask for, and network shares are never opened.",
                              "Изображения с диска отрисовываются: абсолютный путь (C:\shots\x.png, file:///…) — откуда угодно, относительный — из папки attachments в папке данных heap. Удалённое изображение показывается ссылкой, а кнопка «Загрузить изображения» скачивает его по запросу — heap не делает сетевых запросов, о которых вы не просили, и никогда не открывает сетевые папки.")
            }
        }

        // ─────────────────────────────────────────── TASKS
        HelpCard {
            objectName: "help-tasks"
            H2 {
                text: root.tr2("Tasks — tasks and the editor",
                              "Задачи — задачи и редактор")
            }

            H3 {
                text: root.tr2("Creating",
                              "Создание")
            }
            Body {
                text: root.tr2("Press the '+' button in the TopBar, or the hotkey ",
                              "Нажмите «+ Задача» в верхней панели или клавишу")
            }
            RowLayout {
                spacing: Theme.spSm; Kbd {
                    keys: root.kbd("task.new")
                }
                Body {
                    text: root.tr2("— the Task Editor opens with an empty draft and the cursor in the title.",
                                  "— откроется редактор задачи с пустым черновиком, курсор уже в названии.")
                }
            }

            H3 {
                text: root.tr2("Task Editor — fields",
                              "Редактор задачи — поля")
            }
            Body {
                text: root.tr2("The ID is assigned on save (format — a prefix from Settings → Tasks). Title — a short name. Description — a long description with support for @-mentions. Status — the current kanban column. Priority — P0..P3 (affects the chip color and sorting). Branch — the git branch the task lives on (needed for Git Watcher). Deadline — a date, which you can type naturally: 'tomorrow 17:00', 'friday 5pm', 'friday evening'; the parser extracts the date and (if present) the time.",
                              "ID назначается при сохранении (формат — префикс из Настройки → Задачи). Название — коротко о задаче. Описание — развёрнутый текст с @-упоминаниями. Статус — текущая колонка доски. Приоритет — P0..P3 (влияет на цвет чипа и сортировку). Ветка — git-ветка, в которой живёт задача (нужна для Git Watcher). Срок — дата, которую можно написать обычными словами: «завтра 17:00», «пятница 17:00», «в пятницу вечером»; разборщик вытащит дату и (если есть) время. Tab уходит из описания к следующему полю, Ctrl+Enter сохраняет.")
            }

            H3 {
                text: root.tr2("Statuses (kanban columns)",
                              "Статусы (колонки доски)")
            }
            Body {
                text: root.tr2("Statuses are created and edited in Settings → Tasks. Dragging in Settings changes the column order. Deleting a status offers to move its tasks to another one; the operation itself can be undone with ",
                              "Статусы создаются и редактируются в Настройки → Задачи. Перетаскивание в настройках меняет порядок колонок. Удаление статуса предлагает перенести его задачи в другой; саму операцию можно отменить клавишей")
            }
            RowLayout {
                spacing: Theme.spSm; Kbd {
                    keys: root.kbd("undo")
                }
                Body {
                    text: root.tr2("while the undo timer is active.",
                                  "пока идёт таймер отмены.")
                }
            }

            H3 {
                text: root.tr2("Priorities P0–P3",
                              "Приоритеты P0–P3")
            }
            Body {
                text: root.tr2("P0 — on fire, P1 — important, P2 — normal, P3 — background. Each has its own color in the card chip. The default priority for new tasks is set in Settings → Tasks.",
                              "P0 — горит, P1 — важно, P2 — обычно, P3 — фоном. У каждого свой цвет на чипе карточки. Приоритет новых задач по умолчанию задаётся в Настройки → Задачи.")
            }

            H3 {
                text: root.tr2("Deadlines",
                              "Сроки")
            }
            Body {
                text: root.tr2("The date parser accepts natural language. Time is stored separately from the date — if you typed 'tomorrow 17:00', the task keeps deadline=tomorrow, while the time is used for reminders and for auto-scheduling a focus block.",
                              "Разборщик дат понимает обычную речь. Время хранится отдельно от даты — если вы написали «завтра 17:00», у задачи срок завтра, а время используется для напоминаний и автопостановки фокус-блока.")
            }

            H3 {
                text: root.tr2("PR chip",
                              "Чип PR")
            }
            Body {
                text: root.tr2("If the task's branch matches a PR in a tracked repository, a state chip (pending / approved / changes requested) and a list of reviewers appear on the card.",
                              "Если ветка задачи совпадает с PR в отслеживаемом репозитории, на карточке появляется чип состояния (ожидает / одобрен / нужны правки) и список ревьюеров.")
            }
        }

        // ─────────────────────────────────────────── QUICK CAPTURE
        HelpCard {
            objectName: "help-capture"
            H2 {
                text: root.tr2("Quick Capture — fast capture",
                              "Быстрый ввод")
            }
            Body {
                text: root.tr2("When you need to dump a thought without breaking away from what you're doing — open Quick Capture (Ctrl+Shift+Space; rebind it in the Hotkeys panel). You type one line or a paragraph — the popup parses it into title, description, @-mentions, and deadline on its own.",
                              "Когда нужно выгрузить мысль, не отрываясь от дела, — откройте быстрый ввод (Ctrl+Shift+Space; переназначается в панели «Горячие клавиши»). Пишете строку или абзац — окно само разберёт их на название, описание, @-упоминания и срок.")
            }

            H3 {
                text: root.tr2("What gets parsed automatically",
                              "Что разбирается автоматически")
            }
            Body {
                text: root.tr2("The first line → title. The rest → description. @username → creates a link to a person (or offers to create one if they don't exist yet). A date in any form ('tomorrow', 'through tuesday', 'wednesday at noon') is extracted and highlighted as a separate chip — on the right you can immediately see which date was recognized.",
                              "Первая строка → название. Остальное → описание. @имя → связь с человеком (или предложение создать его, если такого ещё нет). Дата в любой форме («завтра», «до вторника», «в среду в полдень») извлекается и показывается отдельным чипом — справа сразу видно, какая дата распознана.")
            }

            H3 {
                text: root.tr2("Auto-classification",
                              "Автоклассификация")
            }
            Body {
                text: root.tr2("From the wording of the text, Quick Capture guesses the task type: focus (solo deep work), sync (a meeting/call), ticket (something with an ID or a PR/Jira link), generic. The type affects the color coding of the event if the task becomes a focus block.",
                              "По формулировке быстрый ввод угадывает тип задачи: focus (одиночная глубокая работа), sync (встреча или созвон), ticket (что-то с ID или ссылкой на PR/Jira), generic. Тип влияет на цвет события, если задача станет фокус-блоком.")
            }
            Hint {
                text: root.tr2("A captured task gets the profile's id prefix, or the ticket key when the text names one (\"LTE-2398 fix login\").",
                              "Задача из быстрого ввода получает префикс ID профиля или ключ тикета, если он есть в тексте («LTE-2398 починить вход»).")
            }
        }

        // ─────────────────────────────────────────── CALENDAR
        HelpCard {
            objectName: "help-calendar"
            H2 {
                text: root.tr2("Calendar — events and focus blocks",
                              "Календарь — события и фокус-блоки")
            }

            H3 {
                text: root.tr2("Creating events",
                              "Создание событий")
            }
            Body {
                text: root.tr2("In Day Calendar and Week View, clicking an empty spot makes an hour-long event. If you hold and drag — the duration equals the height you dragged across. The snap step (15 min by default) is set in Settings → Calendar → Snap.",
                              "В календаре дня и на неделе клик по пустому месту создаёт событие на час. Если зажать и потянуть — длительность равна протянутой высоте. Шаг привязки (по умолчанию 15 мин) задаётся в Настройки → Календарь → Привязка.")
            }

            H3 {
                text: root.tr2("Event Editor",
                              "Редактор события")
            }
            Body {
                text: root.tr2("Fields: title, type (focus / sync / standup / 1-on-1), start/end, date, attendees, an optional link to a task (taskId). A linked event is highlighted with a link to the kanban card.",
                              "Поля: название, тип (фокус / синк / стендап / 1-на-1), начало и конец, дата, участники, необязательная связь с задачей. Связанное событие подсвечивается и ведёт к карточке на доске.")
            }

            H3 {
                text: root.tr2("Focus block — auto-scheduling",
                              "Фокус-блок — автопостановка")
            }
            Body {
                text: root.tr2("Drag a task from the kanban onto the Day Calendar — a focus block appears for that hour. The default length comes from Settings → Calendar → Focus duration (90 minutes). You can enable the 'Auto focus block' option — then the block is created as soon as you switch the git branch to the one linked to the task.",
                              "Перетащите задачу с доски на календарь дня — на этот час появится фокус-блок. Длина по умолчанию — из Настройки → Календарь → Длительность фокуса (90 минут). Можно включить «Авто фокус-блок» — тогда блок создаётся, как только вы переключаетесь на git-ветку задачи.")
            }

            H3 {
                text: root.tr2("Workday and time format",
                              "Рабочий день и формат времени")
            }
            Body {
                text: root.tr2("The workday is 9–19 by default — it is shaded on the Day Calendar, whose grid covers the whole day. Change it in Settings → Calendar. The time format switches between 12h and 24h. The week starts on Mon or Sun — also from settings. Snaps are 5/10/15/30 min.",
                              "Рабочий день по умолчанию 9–19 — он затенён в календаре дня, сетка которого покрывает все сутки. Меняется в Настройки → Календарь. Формат времени переключается между 12 и 24 часами. Неделя начинается с понедельника или воскресенья — тоже в настройках. Привязка — 5/10/15/30 мин.")
            }
        }

        // ─────────────────────────────────────────── PEOPLE
        HelpCard {
            objectName: "help-people"
            H2 {
                text: root.tr2("People — contacts and mentions",
                              "Люди — контакты и упоминания")
            }
            Body {
                text: root.tr2("The list of people in the bottom-right panel — who you need to reply to or write to. Each has: a name, a handle (unique), a role, an avatar color, a current question.",
                              "Список людей в правой нижней панели — кому нужно ответить или написать. У каждого: имя, уникальный ник, роль, цвет аватара и текущий вопрос.")
            }

            H3 {
                text: root.tr2("State cycle",
                              "Цикл состояний")
            }
            Body {
                text: root.tr2("The state cycles on click: todo → pinged → replied → (hidden until you bring it back). The badge at the top shows how many are still todo + how many are active in total.",
                              "Состояние меняется по клику: нужно написать → написали → ответили → (скрыт, пока не вернёте). Бейдж сверху показывает, сколько ещё ждут, и сколько активных всего. С клавиатуры: Tab на список, ↑/↓, Enter — редактировать, клавиша меню — действия.")
            }

            H3 {
                text: root.tr2("Person Editor",
                              "Редактор человека")
            }
            Body {
                text: root.tr2("Creating/editing. The handle is auto-picked; if it's taken — a suffix is added. The color is taken from the palette; this exact color is used in @-mentions.",
                              "Создание и правка. Ник подбирается сам; если занят — добавляется суффикс. Цвет берётся из палитры; этот же цвет используется в @-упоминаниях.")
            }

            H3 {
                text: root.tr2("@-mentions",
                              "@-упоминания")
            }
            Body {
                text: root.tr2("Type @ + the start of a name or handle in Quick Capture, Task Editor, or Notes — a fuzzy list of the active profile's people drops down. Selecting one inserts the handle and links the entry to that person.",
                              "Наберите @ и начало имени или ника в быстром вводе, редакторе задачи или заметках — выпадет нечёткий список людей активного профиля. Выбор вставляет ник и связывает запись с человеком.")
            }
        }

        // ─────────────────────────────────────────── PROFILES
        HelpCard {
            objectName: "help-profiles"
            H2 {
                text: root.tr2("Profiles — workspaces",
                              "Профили — рабочие пространства")
            }
            Body {
                text: root.tr2("A profile is an isolated set of tasks, people, notes, and docs. It's handy to keep different projects or contexts ('work', 'pet', 'study') separate — nothing gets mixed up.",
                              "Профиль — изолированный набор задач, людей, заметок и доков. Удобно держать разные проекты или контексты («работа», «пет», «учёба») порознь — ничего не смешивается.")
            }

            H3 {
                text: root.tr2("Switching",
                              "Переключение")
            }
            RowLayout {
                spacing: Theme.spSm
                Kbd {
                    keys: root.kbd("profile.next")
                }
                Body {
                    text: root.tr2("— next profile, ",
                                  "— следующий профиль,")
                }
                Kbd {
                    keys: root.kbd("profile.prev")
                }
                Body {
                    text: root.tr2("— previous. The pill in the TopBar — clicking it opens the dropdown.",
                                  "— предыдущий. Плашка профиля в верхней панели открывает список по клику (или с клавиатуры: Tab, затем Enter).")
                }
            }

            H3 {
                text: root.tr2("Create / rename / duplicate / delete",
                              "Создание / переименование / дублирование / удаление")
            }
            Body {
                text: root.tr2("Profile dropdown → 'New…'. Rename and change color — through the same dropdown or the editor. Duplicate copies all data into a new profile with the same content. Deletion is reversible with ",
                              "Список профиля → «Новый…». Переименовать и сменить цвет — там же или в редакторе. Дублирование копирует все данные в новый профиль. Удаление отменяется клавишей")
            }
            RowLayout {
                spacing: Theme.spSm; Kbd {
                    keys: root.kbd("undo")
                }
                Body {
                    text: root.tr2("while the undo timer is active.",
                                  "пока идёт таймер отмены.")
                }
            }

            H3 {
                text: root.tr2("JSON import / export",
                              "Импорт и экспорт JSON")
            }
            Body {
                text: root.tr2("Export the active profile → a .json file with all its content (tasks, people, statuses, notes, docs). Import — the other way around. Useful for backups and moving between machines.",
                              "Экспорт активного профиля → .json-файл со всем содержимым (задачи, люди, статусы, заметки, доки). Импорт — наоборот. Пригодится для бэкапов и переезда между машинами.")
            }
        }

        // ─────────────────────────────────────────── SEARCH / PALETTE
        HelpCard {
            objectName: "help-search"
            H2 {
                text: root.tr2("Search & Command Palette",
                              "Поиск и палитра команд")
            }

            H3 {
                text: root.tr2("Command Palette",
                              "Палитра команд")
            }
            RowLayout {
                spacing: Theme.spSm
                Kbd {
                    keys: root.kbd("palette.open")
                }
                Body {
                    text: root.tr2("— opens the command palette: commands (switch view, toggle theme, open a Settings section, new task / note / event…), tasks in all profiles, doc sections, ",
                                  "— открывает палитру: команды (сменить вид, переключить тему, открыть раздел настроек, новая задача / заметка / событие…), задачи всех профилей, разделы доков, ")
                }
            }
            Body {
                text: root.tr2("snippets, contacts, people and notes. An empty query shows what you opened last. Words match in any order and a typo or two is forgiven. Selecting a task from another profile switches the profile.",
                              "сниппеты, контакты, люди и заметки. Пустой запрос показывает то, что вы открывали последним. Слова ищутся в любом порядке, опечатка-другая прощается. Выбор задачи из другого профиля переключает профиль.")
            }

            H3 {
                text: root.tr2("Inline search",
                              "Поиск в шапке")
            }
            RowLayout {
                spacing: Theme.spSm
                Body {
                    text: root.tr2("The ",
                                  "Клавиша")
                }
                Kbd {
                    keys: root.kbd("search.focus")
                }
                Body {
                    text: root.tr2("moves focus to the top bar's search field. Filters Board / Timeline / Week / Month by ",
                                  "переводит фокус в поле поиска верхней панели. Фильтрует доску / ленту / неделю / месяц по ")
                }
            }
            Body {
                text: root.tr2("title, ID, description. Esc clears it, a second Esc (or Return) hands the keyboard back to the view. In Notes the same key opens the palette, which searches every note.",
                              "названию, ID и описанию. Esc очищает поле, второй Esc (или Enter) возвращает клавиатуру виду. В заметках та же клавиша открывает палитру — она ищет по всем заметкам.")
            }
        }

        // ─────────────────────────────────────────── FILTERS
        HelpCard {
            objectName: "help-filter"
            H2 {
                text: root.tr2("Filters — priority, archived, show-done",
                              "Фильтры — приоритет, архив, выполненные")
            }

            H3 {
                text: root.tr2("Priority chips",
                              "Чипы приоритетов")
            }
            Body {
                text: root.tr2("A strip under the TopBar: P0/P1/P2/P3 chips. Multi-select — you can enable several. 'Clear' resets them. The filter persists across view switches.",
                              "Полоса под верхней панелью: чипы P0/P1/P2/P3. Можно включить несколько. «Сбросить» снимает все. Фильтр сохраняется при смене вида. С клавиатуры: Tab на чип, Space.")
            }

            H3 {
                text: root.tr2("Archived",
                              "Архив")
            }
            Body {
                text: root.tr2("The toggle shows archived tasks. Archive is a separate state, not the same thing as Done; the Archive view (Ctrl+5) lists them all.",
                              "Переключатель показывает архивные задачи. Архив — отдельное состояние, не то же самое, что «Готово»; вид «Архив» (Ctrl+5) показывает их все.")
            }

            H3 {
                text: root.tr2("Show Done (Timeline only)",
                              "Выполненные (только лента)")
            }
            Body {
                text: root.tr2("In the timeline, completed tasks are hidden by default. The toggle shows them as a dashed card.",
                              "В ленте выполненные задачи по умолчанию скрыты. Переключатель показывает их пунктирной карточкой.")
            }

            H3 {
                text: root.tr2("Blocked / Review badges",
                              "Бейджи «Заблокированные» и «На ревью»")
            }
            Body {
                text: root.tr2("In the SideRail on the left, counters of tasks in the blocked and review statuses are highlighted. Clicking takes you to Kanban with the filter for that status enabled.",
                              "На боковой панели слева подсвечены счётчики задач в статусах «Заблокировано» и «Ревью». Клик ведёт на доску с фильтром по этому статусу.")
            }
        }

        // ─────────────────────────────────────────── TWEAKS
        HelpCard {
            objectName: "help-tweaks"
            H2 {
                text: root.tr2("Tweaks — appearance",
                              "Твики — внешний вид")
            }
            RowLayout {
                spacing: Theme.spSm
                Kbd {
                    keys: root.kbd("tweaks.open")
                }
                Body {
                    text: root.tr2("— a floating panel with quick toggles.",
                                  "— плавающая панель с быстрыми переключателями.")
                }
            }

            H3 {
                text: root.tr2("Theme",
                              "Тема")
            }
            Body {
                text: root.tr2("Dark / Light. Changes instantly, no restart.",
                              "Тёмная / светлая. Меняется сразу, без перезапуска.")
            }

            H3 {
                text: root.tr2("Density",
                              "Плотность")
            }
            Body {
                text: root.tr2("Compact (tighter, smaller fonts) or Comfy (roomier).",
                              "Компактная (плотнее, мельче шрифты) или просторная.")
            }

            H3 {
                text: root.tr2("Theme presets",
                              "Темы")
            }
            Body {
                text: root.tr2("One dot per theme — heap., Minimal and the kaneo family, plus any of your own. A click puts it in the slot on screen (dark or light); hovering or focusing a dot names it.",
                              "По точке на тему — heap., Minimal и семейство kaneo, плюс ваши собственные. Клик ставит тему в показанный слот (тёмный или светлый); при наведении или фокусе точка называет тему.")
            }

            H3 {
                text: root.tr2("Reduced motion",
                              "Меньше движения")
            }
            Body {
                text: root.tr2("Fully disables animations — for weak machines and for accessibility.",
                              "Полностью отключает анимации — для слабых машин и для доступности.")
            }

            H3 {
                text: root.tr2("Contrast",
                              "Контраст")
            }
            Body {
                text: root.tr2("Soft fades lines and colour, Normal is the theme as designed, High strengthens lines and text for readability.",
                              "Мягкий приглушает линии и цвет, обычный — тема как задумана, высокий усиливает линии и текст для читаемости.")
            }
        }

        // ─────────────────────────────────────────── HOTKEYS
        HelpCard {
            objectName: "help-hotkeys"
            H2 {
                text: root.tr2("Hotkeys — keyboard",
                              "Горячие клавиши")
            }
            RowLayout {
                spacing: Theme.spSm
                Kbd {
                    keys: root.kbd("hotkeys.open")
                }
                Body {
                    text: root.tr2("— opens the hotkey catalog.",
                                  "— открывает каталог горячих клавиш.")
                }
            }
            Body {
                text: root.tr2("Every action can be rebound inline: click a shortcut (or Tab to it and press Enter), then press the new combination and Enter to save; Esc cancels. If it's already taken by another action — the conflict is named, and saving frees the other one. ↺ restores one default; ↺ all asks once more before resetting everything.",
                              "Любое действие переназначается на месте: нажмите сочетание (или дойдите до него Tab и нажмите Enter), затем новую комбинацию и Enter, чтобы сохранить; Esc отменяет. Если сочетание уже занято — конфликт будет назван, и при сохранении другое действие освобождается. ↺ возвращает одно значение по умолчанию; «↺ всё» переспрашивает, прежде чем сбросить всё.")
            }

            H3 {
                text: root.tr2("Defaults",
                              "По умолчанию")
            }
            Body {
                text: root.tr2("Ctrl+K — palette, Ctrl+N — new task, Ctrl+1…8 — the views in side-rail order (Board, Timeline, Week, Month, Archive, Docs, Notes, Settings), Ctrl+] / Ctrl+[ — next/previous profile, Ctrl+Z / Ctrl+Shift+Z — undo / redo, Ctrl+, — Tweaks, Ctrl+/ — hotkey catalog, Ctrl+F — focus search. docs/HOTKEYS.md has the full list.",
                              "Ctrl+K — палитра, Ctrl+N — новая задача, Ctrl+1…8 — виды в порядке боковой панели (доска, лента, неделя, месяц, архив, доки, заметки, настройки), Ctrl+] / Ctrl+[ — следующий/предыдущий профиль, Ctrl+Z / Ctrl+Shift+Z — отменить / повторить, Ctrl+, — твики, Ctrl+/ — каталог клавиш, Ctrl+F — фокус в поиск. Полный список — в docs/HOTKEYS.md.")
            }
            Body {
                text: root.tr2("On the board, J/K/H/L (or the arrows) move a cursor between cards and Shift with them moves the card itself; Return opens it, Space adds it to the selection. On the week and month views T goes to today, the arrows step a period, and G opens a date picker. Esc closes the innermost thing first — a menu, a dialog, the editor — and lets go of the selection last.",
                              "На доске J/K/H/L (или стрелки) двигают курсор между карточками, а с Shift — саму карточку; Enter открывает её, Space добавляет в выделение. На неделе и месяце T — к сегодняшнему дню, стрелки листают период, G открывает выбор даты. Esc сначала закрывает самое внутреннее — меню, диалог, редактор — и только потом снимает выделение.")
            }
        }

        // ─────────────────────────────────────────── AUTOMATION / NOTIFICATIONS
        HelpCard {
            objectName: "help-automation"
            H2 {
                text: root.tr2("Automation & Notifications",
                              "Автоматизация и уведомления")
            }
            Body {
                text: root.tr2("Once a minute a background ticker checks: whether deadlines are approaching, whether tasks have been stuck in blocked too long, whether it's time to archive done. Notifications go to the system toast (on Linux — via org.freedesktop.Notifications with real action buttons, on Windows/macOS — a fallback via a tray balloon).",
                              "Раз в минуту фоновый таймер проверяет: не подходят ли сроки, не застряли ли задачи в «Заблокировано», не пора ли архивировать выполненные. Уведомления уходят в системные (в Linux — через org.freedesktop.Notifications с настоящими кнопками, в Windows/macOS — запасной вариант через всплывающее окно трея).")
            }

            H3 {
                text: root.tr2("Deadline reminders",
                              "Напоминания о сроках")
            }
            Body {
                text: root.tr2("N hours before a deadline (24 by default, configurable in Settings → Notifications) — it pushes a notification. The notification has a 'Snooze 1h' action.",
                              "За N часов до срока (по умолчанию 24, настраивается в Настройки → Уведомления) приходит уведомление. У него есть действие «Отложить на 1 ч».")
            }

            H3 {
                text: root.tr2("Standup reminder",
                              "Напоминание о стендапе")
            }
            Body {
                text: root.tr2("Daily at standup-time (default 10:00). The time is changed in Settings → Notifications.",
                              "Каждый день во время стендапа (по умолчанию 10:00). Время меняется в Настройки → Уведомления.")
            }

            H3 {
                text: root.tr2("Blocked stuck warning",
                              "Предупреждение о застрявших")
            }
            Body {
                text: root.tr2("If a task sits in blocked for more than N days (default 3) — a warning badge appears on the card, and the SideRail counter jumps. You can configure an auto-move to another status after N days.",
                              "Если задача сидит в «Заблокировано» дольше N дней (по умолчанию 3), на карточке появляется бейдж, а счётчик на боковой панели подскакивает. Можно настроить автоперенос в другой статус через N дней.")
            }

            H3 {
                text: root.tr2("Auto-archive done",
                              "Автоархивация выполненных")
            }
            Body {
                text: root.tr2("Tasks in done older than N days (default 7) automatically go to the archive. They are visible only when the 'Archived' toggle is on.",
                              "Задачи в «Готово» старше N дней (по умолчанию 7) сами уходят в архив. Они видны только при включённом «Архив».")
            }

            H3 {
                text: root.tr2("Quiet hours",
                              "Тихие часы")
            }
            Body {
                text: root.tr2("The quiet window (default 19:00–09:00) suppresses desktop notifications, but not the reminders themselves — inside the app the toast still appears.",
                              "Тихое окно (по умолчанию 19:00–09:00) глушит системные уведомления, но не сами напоминания — внутри приложения тост всё равно появится. Время пишется как ЧЧ:ММ.")
            }

            H3 {
                text: root.tr2("Toasts",
                              "Тосты")
            }
            Body {
                text: root.tr2("Transient messages at the bottom of the screen. For reversible actions (deletion) they show an 'Undo' button for a few seconds.",
                              "Короткие сообщения внизу экрана. Для обратимых действий (удаление) несколько секунд показывают кнопку «Отменить»; новые сообщения встают рядом, а не заменяют её. Ошибки отмечены красным и держатся дольше.")
            }
        }

        // ─────────────────────────────────────────── GIT
        HelpCard {
            objectName: "help-git"
            H2 {
                text: root.tr2("Git Watcher — branch focus",
                              "Git Watcher — фокус по ветке")
            }
            Body {
                text: root.tr2("The watcher monitors the list of repositories from Settings → Git Watcher. When you switch a branch in one of them — heap. checks whether there's a task with the same branch. If there is — a focus banner with the task ID, branch name, and PR state appears in the TopBar.",
                              "Наблюдатель следит за репозиториями из Настройки → Git. Когда вы переключаете ветку в одном из них, heap. проверяет, есть ли задача с такой веткой. Если есть — в верхней панели появляется баннер фокуса с ID задачи, веткой и состоянием PR.")
            }

            H3 {
                text: root.tr2("Auto move to in-progress",
                              "Автоперевод «В работу»")
            }
            Body {
                text: root.tr2("An option: automatically moves the task to the 'In Progress' status when you switch to its branch.",
                              "Опция: задача сама переходит в статус «В работе», когда вы переключаетесь на её ветку.")
            }

            H3 {
                text: root.tr2("Auto focus block",
                              "Авто фокус-блок")
            }
            Body {
                text: root.tr2("An option: automatically books a focus block in the Day Calendar at the nearest free hour when you switch to the task's branch. The block length — from Settings → Calendar.",
                              "Опция: при переключении на ветку задачи в календаре дня бронируется фокус-блок на ближайший свободный час. Длина блока — из Настройки → Календарь.")
            }

            H3 {
                text: root.tr2("PR state chips",
                              "Чипы состояния PR")
            }
            Body {
                text: root.tr2("The watcher periodically reads the PR state (pending / approved / changes requested) and shows a chip on the task card and in the editor. The list of reviewers is pulled in too.",
                              "Наблюдатель периодически читает состояние PR (ожидает / одобрен / нужны правки) и показывает чип на карточке и в редакторе. Список ревьюеров тоже подтягивается.")
            }

            H3 {
                text: root.tr2("Dismiss banner",
                              "Скрыть баннер")
            }
            Body {
                text: root.tr2("Don't need the banner? Click '×' — it hides until the next branch switch. To disable it completely — untrack the repo in Settings → Git Watcher.",
                              "Баннер не нужен? Нажмите «×» — он скроется до следующего переключения ветки. Чтобы отключить совсем — уберите репозиторий в Настройки → Git.")
            }
        }

        // ─────────────────────────────────────────── INTEGRATIONS
        HelpCard {
            objectName: "help-integrations"
            H2 {
                text: root.tr2("Integrations — connecting a tracker",
                              "Интеграции — подключение трекера")
            }
            Body {
                text: root.tr2("Settings → Integrations lists every tracker heap. can pull issues from. Each card is collapsed; click it to expand. Issues arrive as cards in the active profile, and moving one between columns writes the status back where the tracker allows it.",
                              "Настройки → Интеграции перечисляют все трекеры, из которых heap. умеет забирать задачи. Каждая карточка свёрнута; нажмите, чтобы развернуть. Задачи приходят карточками в активный профиль, а перенос между колонками записывает статус обратно, где трекер это позволяет.")
            }

            H3 {
                text: root.tr2("Three ways to sign in",
                              "Три способа войти")
            }
            Body {
                text: root.tr2("Connect with browser — opens your browser, you authorize, nothing to fill in. Device code (GitHub) — the card shows a short code you type on the page that opens. Access token — open Advanced, fill in the fields and press Connect. The token path works for every provider, including the ones that also offer the browser button, and is never a degraded mode: it is exactly what the browser flow ends up storing. It is also the only way into a self-hosted instance the vendor’s OAuth service has never heard of — a Jira Server or Data Center of your own, for one.",
                              "Войти через браузер — открывается браузер, вы даёте доступ, заполнять ничего не нужно. Код устройства (GitHub) — карточка показывает короткий код, который вы вводите на открывшейся странице. Токен доступа — откройте «Дополнительно», заполните поля и нажмите «Подключить». Токен работает для всех провайдеров, в том числе с кнопкой браузера, и это не урезанный режим: браузерный вход в итоге хранит ровно такой же токен. Это ещё и единственный путь к собственному серверу, о котором OAuth-сервис вендора ничего не знает, — например, к своему Jira Server или Data Center.")
            }

            H3 {
                text: root.tr2("No 'Connect with browser' button?",
                              "Нет кнопки «Войти через браузер»?")
            }
            Body {
                text: root.tr2("The button only appears when this build can run the flow with no help from you. If you built heap. yourself, that is expected for most providers. Paste a token under Advanced and everything works.",
                              "Кнопка появляется, только когда эта сборка может пройти вход без вашей помощи. Если вы собрали heap. сами, для большинства провайдеров это ожидаемо. Вставьте токен в «Дополнительно» — и всё заработает.")
            }
            Body {
                text: root.tr2("Why it is missing, in order of likelihood:\n1.  You built heap. yourself. Jira, Todoist, ClickUp, Bitbucket and Sentry all refuse an app that has no client secret, and the official builds get theirs from CI. A source build has none, so those buttons stay hidden.\n2.  Your provider is self-hosted — Gitea, Forgejo, a GitLab of your own. There is no single app anyone could ship for every instance, so you register one on your server and paste its client ID under Advanced.\n3.  The provider has no OAuth at all. Redmine is the only one here: its API only takes an API key. That is not a gap in heap. and will not change until Redmine changes.\n4.  GitHub on a Qt older than 6.9 (some Linux packages). The device grant needs that version; the token path is unaffected.",
                              "Почему её нет, от самого вероятного:\n1.  Вы собрали heap. сами. Jira, Todoist, ClickUp, Bitbucket и Sentry не принимают приложение без client secret, а официальные сборки получают его из CI. В сборке из исходников его нет, поэтому эти кнопки скрыты.\n2.  Ваш провайдер на своём сервере — Gitea, Forgejo, собственный GitLab. Одного приложения на все инсталляции не бывает, поэтому вы регистрируете его на своём сервере и вставляете client ID в «Дополнительно».\n3.  У провайдера вообще нет OAuth. Здесь это только Redmine: его API принимает лишь API-ключ. Это не пробел в heap., и он не закроется, пока не изменится Redmine.\n4.  GitHub на Qt старше 6.9 (некоторые пакеты Linux). Для кода устройства нужна эта версия; вход по токену не затронут.")
            }
            Hint {
                text: root.tr2("Want one-click in your own build? Register an OAuth app with the provider, set the redirect URI to http://127.0.0.1:51789/ and pass HEAP_OAUTH_<PROVIDER>_CLIENT_ID and _CLIENT_SECRET in the environment when you run cmake. docs/INTEGRATIONS.md has the per-provider registration steps.",
                              "Хотите вход в один клик в своей сборке? Зарегистрируйте OAuth-приложение у провайдера, укажите redirect URI http://127.0.0.1:51789/ и передайте HEAP_OAUTH_<PROVIDER>_CLIENT_ID и _CLIENT_SECRET в окружении при запуске cmake. Шаги регистрации для каждого провайдера — в docs/INTEGRATIONS.md.")
            }

            H3 {
                text: root.tr2("Where to get a token",
                              "Где взять токен")
            }
            Body {
                text: root.tr2("GitHub — Settings → Developer settings → Personal access tokens. A classic token needs the 'repo' scope; a fine-grained one needs read/write on Issues for the repos you care about.\nGitLab — User settings → Access tokens, scope 'api'. Self-hosted: the same page on your instance, and fill in Host.\nJira Cloud — id.atlassian.com → Security → Create and manage API tokens. You also need the Email of the same Atlassian account: Cloud authenticates the pair, not the token alone.\nJira Server / Data Center — your avatar → Profile → Personal Access Tokens. Leave the Email field empty; a PAT authenticates on its own. heap. works out which of the two you have from the server itself, so there is nothing to pick.\nGitea / Forgejo — Settings → Applications → Generate token.\nRedmine — My account → API access key (an admin has to enable the REST API first).\nTodoist — Settings → Integrations → Developer → API token.\nAsana — My settings → Apps → Manage developer apps → Personal access token.\nClickUp — Settings → Apps → API token.\nSentry — Settings → Account → API → Auth tokens, scopes org:read, project:read, event:read.\nBitbucket — Personal settings → App passwords, with the Issues: Read permission.\nTrello — trello.com/power-ups/admin → your Power-Up → API key, then the 'Token' link next to it to generate the token.",
                              "GitHub — Settings → Developer settings → Personal access tokens. Классическому токену нужен scope «repo»; детализированному — чтение и запись Issues для нужных репозиториев.\nGitLab — User settings → Access tokens, scope «api». Свой сервер: та же страница на вашей инсталляции, и заполните Host.\nJira Cloud — id.atlassian.com → Security → Create and manage API tokens. Нужен ещё Email той же учётной записи Atlassian: Cloud проверяет пару, а не один токен.\nJira Server / Data Center — ваш аватар → Profile → Personal Access Tokens. Поле Email оставьте пустым: PAT работает сам по себе. heap. сам узнаёт у сервера, какой у вас вариант, так что выбирать ничего не нужно.\nGitea / Forgejo — Settings → Applications → Generate token.\nRedmine — My account → API access key (сначала администратор должен включить REST API).\nTodoist — Settings → Integrations → Developer → API token.\nAsana — My settings → Apps → Manage developer apps → Personal access token.\nClickUp — Settings → Apps → API token.\nSentry — Settings → Account → API → Auth tokens, scopes org:read, project:read, event:read.\nBitbucket — Personal settings → App passwords, с правом Issues: Read.\nTrello — trello.com/power-ups/admin → ваш Power-Up → API key, затем ссылка «Token» рядом, чтобы создать токен.")
            }
            Hint {
                text: root.tr2("Tokens go straight into the OS keychain — never into state.json, its backups or a profile export. A build without a keychain keeps them in a private secrets.json instead.",
                              "Токены сразу уходят в системное хранилище ключей — никогда в state.json, его бэкапы или экспорт профиля. Сборка без хранилища ключей держит их в закрытом secrets.json.")
            }

            H3 {
                text: root.tr2("Signing in is not the same as choosing what to sync",
                              "Войти — ещё не значит выбрать, что синхронизировать")
            }
            Body {
                text: root.tr2("GitHub, GitLab and Jira need nothing else: leave Repo / Project / JQL empty and they pull the issues assigned to you. Asana, ClickUp, Sentry and Bitbucket cannot — they have no 'my issues' endpoint — so they need a workspace, a list, an org and project, or a repo. The card names what is missing and opens Advanced at it.",
                              "GitHub, GitLab и Jira больше ничего не требуют: оставьте Repo / Project / JQL пустыми — и они заберут задачи, назначенные на вас. Asana, ClickUp, Sentry и Bitbucket так не умеют — у них нет «моих задач», — поэтому им нужны рабочее пространство, список, организация и проект или репозиторий. Карточка называет, чего не хватает, и открывает «Дополнительно» на нужном поле.")
            }
            Hint {
                text: root.tr2("In that 'my issues' mode there is no single repo to write to, so moving a card between columns does not push the status back.",
                              "В режиме «мои задачи» нет одного репозитория, куда писать, поэтому перенос карточки между колонками не отправляет статус обратно.")
            }

            H3 {
                text: root.tr2("Jira — writing a JQL that works",
                              "Jira — как написать работающий JQL")
            }
            Body {
                text: root.tr2("Leave the JQL field empty and heap. uses 'assignee = currentUser() ORDER BY updated DESC'. If you write your own, it has to narrow the search somehow — a bare 'ORDER BY updated DESC' is rejected with 'Unbounded JQL queries are not allowed here', which looks exactly like a sync that found nothing.",
                              "Оставьте поле JQL пустым — и heap. возьмёт «assignee = currentUser() ORDER BY updated DESC». Если пишете свой, он должен как-то сужать поиск: голый «ORDER BY updated DESC» отклоняется с «Unbounded JQL queries are not allowed here», а это выглядит в точности как синхронизация, которая ничего не нашла.")
            }
            Body {
                text: root.tr2("Useful starting points:\nassignee = currentUser() AND resolution = Unresolved ORDER BY priority DESC\nproject = APP AND status IN (\"In Progress\", \"In Review\") ORDER BY updated DESC\nassignee = currentUser() AND sprint IN openSprints() ORDER BY rank\nreporter = currentUser() AND created >= -14d ORDER BY created DESC\nproject = APP AND labels = backend AND updated >= -7d ORDER BY updated DESC",
                              "С чего можно начать:\nassignee = currentUser() AND resolution = Unresolved ORDER BY priority DESC\nproject = APP AND status IN (\"In Progress\", \"In Review\") ORDER BY updated DESC\nassignee = currentUser() AND sprint IN openSprints() ORDER BY rank\nreporter = currentUser() AND created >= -14d ORDER BY created DESC\nproject = APP AND labels = backend AND updated >= -7d ORDER BY updated DESC")
            }
            Hint {
                text: root.tr2("Try a query in Jira's own issue search first — heap. sends it verbatim, so anything Jira accepts there works here. Cloud and Server/Data Center are both supported; the unbounded-query rule is Cloud's, so a bare ORDER BY may work on Server and is still worth avoiding.",
                              "Сначала проверьте запрос в поиске задач самой Jira — heap. отправляет его как есть, так что всё, что Jira принимает там, работает и здесь. Поддерживаются и Cloud, и Server/Data Center; правило про неограниченные запросы — у Cloud, так что голый ORDER BY может сработать на Server, но его всё равно лучше избегать.")
            }

            H3 {
                text: root.tr2("Sessions expire, tokens mostly don't",
                              "Сессии истекают, токены — почти никогда")
            }
            Body {
                text: root.tr2("A browser sign-in hands out a short-lived token — two hours on GitLab and Bitbucket, one on Jira and Asana — and heap. renews it in the background, so you stay signed in. The card shows when the current session runs out. If the tracker revokes the grant, the card drops back to disconnected and asks you to sign in again rather than failing silently. Being offline is not that: the card says 'offline', keeps you signed in and retries, and moves you make meanwhile are sent after the next sync.",
                              "Вход через браузер выдаёт короткоживущий токен — два часа у GitLab и Bitbucket, час у Jira и Asana, — и heap. обновляет его в фоне, так что вы остаётесь в системе. Карточка показывает, когда закончится текущая сессия. Если трекер отзывает доступ, карточка возвращается в «не подключено» и просит войти заново, а не молча ломается. Отсутствие сети — другое дело: карточка пишет «офлайн», вход сохраняется, heap. повторяет попытки, а перемещения, сделанные за это время, отправляются после следующей синхронизации.")
            }
            Body {
                text: root.tr2("Disconnecting a browser session discards its tokens. A token you pasted yourself is left alone — it is your credential, not one heap. obtained — so reconnecting does not mean finding it again. Pasting a token over a live browser session ends that session.",
                              "Отключение браузерной сессии удаляет её токены. Токен, который вы вставили сами, остаётся — это ваш ключ, а не полученный heap., — так что при повторном подключении его не придётся искать. Вставка токена поверх живой браузерной сессии завершает эту сессию.")
            }

            H3 {
                text: root.tr2("Auto-sync",
                              "Автосинхронизация")
            }
            Body {
                text: root.tr2("Off by default. The chips at the top of the section run every connected tracker every 15, 30 or 60 minutes; 'Sync now' on a card pulls just that one. Nothing is deleted by a sync — an issue that disappears upstream stays as a card, and labels you added locally survive. Changing a card's filter (repo, JQL) marks the cards it no longer covers 'outside filter', not 'not in tracker'. A title, description or priority changed both here and in the tracker keeps yours and shows a 'conflict' chip; the editor offers the tracker's version.",
                              "По умолчанию выключена. Чипы вверху раздела запускают все подключённые трекеры раз в 15, 30 или 60 минут; «Синхронизировать сейчас» на карточке забирает только её. Синхронизация ничего не удаляет: задача, пропавшая в трекере, остаётся карточкой, а метки, добавленные локально, сохраняются. Если сменить фильтр карточки (репозиторий, JQL), задачи, которые он больше не покрывает, помечаются «вне фильтра», а не «нет в трекере». Если заголовок, описание или приоритет изменены и здесь, и в трекере, остаётся ваша версия с чипом «конфликт»; редактор предлагает версию трекера.")
            }
        }

        // ─────────────────────────────────────────── UNDO & BACKUPS
        HelpCard {
            objectName: "help-undo"
            H2 {
                text: root.tr2("Undo & Backups",
                              "Отмена и бэкапы")
            }

            H3 {
                text: root.tr2("Undo the last deletion",
                              "Отменить последнее удаление")
            }
            RowLayout {
                spacing: Theme.spSm
                Kbd {
                    keys: root.kbd("undo")
                }
                Body {
                    text: root.tr2("restores the object you just deleted: a task, an event, a person, ",
                                  "восстанавливает то, что вы только что удалили: задачу, событие, человека, ")
                }
            }
            Body {
                text: root.tr2("a status (bringing back all of its tasks), or an entire profile. The window of action — a few seconds after deletion (shown by the toast with the 'Undo' button). Once the timer runs out — the operation is considered final.",
                              "статус (вместе со всеми его задачами) или целый профиль. Окно действия — несколько секунд после удаления (его показывает тост с кнопкой «Отменить»). Когда таймер истёк, операция считается окончательной.")
            }

            H3 {
                text: root.tr2("Auto-backups",
                              "Автобэкапы")
            }
            Body {
                text: root.tr2("At most once per interval (hourly, daily — the default — or weekly; Settings → Data), checked on save, heap. copies state.json into the backups folder next to it. The newest 20 copies are kept, older ones are deleted.",
                              "Не чаще раза за интервал (час, день — по умолчанию — или неделя; Настройки → Данные), с проверкой при сохранении, heap. копирует state.json в папку backups рядом с ним. Хранятся 20 последних копий, более старые удаляются.")
            }

            H3 {
                text: root.tr2("Restore",
                              "Восстановление")
            }
            Body {
                text: root.tr2("Settings → Data → the list of backups. Restoring overwrites the current state, but before that it always snapshots the current state (a -prerestore copy) — in case you change your mind. Undo history does not carry across a restore or a profile switch.",
                              "Настройки → Данные → список бэкапов. Восстановление перезаписывает текущее состояние, но перед этим всегда сохраняет его снимок (копия -prerestore) — на случай, если вы передумаете. История отмены не переносится через восстановление и переключение профиля.")
            }
        }

        // ─────────────────────────────────────────── DATA
        HelpCard {
            objectName: "help-data"
            H2 {
                text: root.tr2("Data — export, import, reset",
                              "Данные — экспорт, импорт, сброс")
            }

            H3 {
                text: root.tr2("Export JSON",
                              "Экспорт JSON")
            }
            Body {
                text: root.tr2("Saves the entire active profile (tasks, people, statuses, notes, docs, events) into a single .json file. The file is human-readable — you can open it in an editor, edit it by hand, and import it back.",
                              "Сохраняет весь активный профиль (задачи, люди, статусы, заметки, доки, события) в один .json-файл. Файл читается человеком — его можно открыть в редакторе, поправить руками и импортировать обратно.")
            }

            H3 {
                text: root.tr2("Import JSON",
                              "Импорт JSON")
            }
            Body {
                text: root.tr2("Loads a .json into a new profile or over an existing one (with confirmation). Useful for migrating between machines or restoring from a backup.",
                              "Загружает .json в новый профиль или поверх существующего (с подтверждением). Пригодится для переезда между машинами или восстановления из бэкапа.")
            }

            H3 {
                text: root.tr2("Reset app",
                              "Сброс приложения")
            }
            Body {
                text: root.tr2("Wipes all profiles, settings, and history. Makes a backup before resetting, just in case — the path to the backup is shown in a toast.",
                              "Стирает все профили, настройки и историю. Перед сбросом на всякий случай делает бэкап — путь к нему показывается в тосте.")
            }
        }

        // ─────────────────────────────────────────── TIPS
        HelpCard {
            objectName: "help-tips"
            H2 {
                text: root.tr2("Tips — small things that aren't obvious",
                              "Советы — мелочи, которые не очевидны")
            }

            H3 {
                text: root.tr2("Day Calendar — drag empty area",
                              "Календарь дня — перетаскивание по пустому месту")
            }
            Body {
                text: root.tr2("Not just a click — hold and drag vertically, and the duration of the new event will be exactly as far as you stretched it.",
                              "Не только клик — зажмите и потяните по вертикали, и новое событие будет ровно такой длины, какую вы протянули.")
            }

            H3 {
                text: root.tr2("Drag TaskCard onto the calendar",
                              "Карточка задачи на календарь")
            }
            Body {
                text: root.tr2("From the kanban/timeline you can drop a card straight into the Day Calendar — a focus block appears at the hour where you released it.",
                              "С доски или ленты карточку можно бросить прямо в календарь дня — фокус-блок появится на часе, где вы её отпустили.")
            }

            H3 {
                text: root.tr2("MiniWeek dots",
                              "Точки в мини-неделе")
            }
            Body {
                text: root.tr2("The small dots under a date in the top panel are a marker that this day has at least one event. Handy for a quick scan of the week.",
                              "Маленькие точки под датой на верхней панели — знак, что в этот день есть хотя бы одно событие. Удобно, чтобы быстро окинуть неделю взглядом. С клавиатуры: Tab на полосу дней, ←/→ — день, PgUp/PgDn — неделя.")
            }

            H3 {
                text: root.tr2("Now-line in Day Calendar",
                              "Линия «сейчас» в календаре дня")
            }
            Body {
                text: root.tr2("The horizontal line — the current time. Updates once a minute. Visible only when today is selected.",
                              "Горизонтальная линия — текущее время. Обновляется раз в минуту. Видна, только если выбран сегодняшний день.")
            }

            H3 {
                text: root.tr2("Breadcrumbs in TopBar",
                              "Хлебные крошки в верхней панели")
            }
            Body {
                text: root.tr2("'Project / sprint / user' can be edited in place — click the breadcrumb you need. It's saved in settings.",
                              "«Проект / неделя / пользователь» правятся на месте — нажмите нужную крошку (или Tab и Enter). Сохраняется в настройках.")
            }

            H3 {
                text: root.tr2("Event resize handles",
                              "Ручки изменения размера события")
            }
            Body {
                text: root.tr2("The top and bottom edges of an event are resize handles (visible on hover). Drag the middle — move the whole thing, drag an edge — change the duration.",
                              "Верхний и нижний края события — ручки изменения размера (видны при наведении). Тянете середину — двигаете событие, тянете край — меняете длительность.")
            }

            H3 {
                text: root.tr2("Profile pill color",
                              "Цвет плашки профиля")
            }
            Body {
                text: root.tr2("The color of the dot next to the profile name in the TopBar is its accent. This same color is used to mark the events that belong to this specific profile.",
                              "Цвет точки рядом с именем профиля в верхней панели — его акцент. Этим же цветом отмечены события, принадлежащие именно этому профилю.")
            }

            H3 {
                text: root.tr2("Sound on ping",
                              "Звук при уведомлении")
            }
            Body {
                text: root.tr2("A separate option in Settings → Notifications — a sound when a notification fires. It respects quiet hours.",
                              "Отдельная опция в Настройки → Уведомления — звук, когда срабатывает уведомление. Тихие часы он уважает.")
            }

            H3 {
                text: root.tr2("Hotkey conflicts",
                              "Конфликты горячих клавиш")
            }
            Body {
                text: root.tr2("When rebinding, it shows who else holds that combination. You can either back out or overwrite it.",
                              "При переназначении показывается, кто ещё держит эту комбинацию. Можно отступить или перезаписать — тогда другое действие освободится.")
            }
        }

        // ─────────────────────────────────────────── Outro
        HelpCard {
            Hint {
                text: root.tr2("Something missing or found strange behavior? Logs and state live in AppDataLocation. The version and exact paths — on the About page.",
                              "Чего-то не хватает или что-то ведёт себя странно? Логи и состояние лежат в AppDataLocation. Версия и точные пути — на странице «О программе».")
            }
        }
    }
}
