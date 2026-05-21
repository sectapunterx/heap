import QtQuick
import QtQuick.Layouts
import TodoCpp

Item {
    id: root

    signal anchorRequested(string objectName)

    implicitHeight: col.implicitHeight
    implicitWidth: col.implicitWidth

    readonly property var tocModel: [
        {anchor: "help-views", label: "Views — Канбан, Timeline, Week, Day, Docs, Notes"},
        {anchor: "help-tasks", label: "Tasks — статусы, приоритеты, дедлайны"},
        {anchor: "help-capture", label: "Quick Capture — разбор текста, @-упоминания"},
        {anchor: "help-calendar", label: "Calendar — события, drag-create, focus blocks"},
        {anchor: "help-people", label: "People — контакты, упоминания, цикл состояний"},
        {anchor: "help-profiles", label: "Profiles — рабочие пространства, JSON"},
        {anchor: "help-search", label: "Search & Command Palette"},
        {anchor: "help-filter", label: "Filters — приоритеты, archived, show-done"},
        {anchor: "help-tweaks", label: "Tweaks — тема, плотность, акцент"},
        {anchor: "help-hotkeys", label: "Hotkeys — перебиндинг и конфликты"},
        {anchor: "help-automation", label: "Automation & Notifications"},
        {anchor: "help-git", label: "Git Watcher — фокус по ветке, PR"},
        {anchor: "help-undo", label: "Undo & Backups"},
        {anchor: "help-data", label: "Data — JSON import/export, reset"},
        {anchor: "help-tips", label: "Tips & неочевидности"}
    ]

    component HelpCard: Rectangle {
        Layout.fillWidth: true
        radius: 10
        color: Theme.panel
        border.color: Theme.border
        border.width: 1
        default property alias content: inner.data
        implicitHeight: inner.implicitHeight + 24
        ColumnLayout {
            id: inner
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10
        }
    }

    component H2: Text {
        color: Theme.text
        font.pixelSize: 16
        font.weight: Font.DemiBold
        font.family: Theme.fontMono
        Layout.fillWidth: true
    }

    component H3: Text {
        color: Theme.accentStrong
        font.pixelSize: 13
        font.family: Theme.fontMono
        font.weight: Font.DemiBold
        font.letterSpacing: 0.5
        Layout.fillWidth: true
        Layout.topMargin: 6
    }

    component Body: Text {
        color: Theme.text
        font.pixelSize: 12
        wrapMode: Text.WordWrap
        lineHeight: 1.35
        Layout.fillWidth: true
    }

    component Hint: Text {
        color: Theme.textMuted
        font.pixelSize: 11
        wrapMode: Text.WordWrap
        font.italic: true
        Layout.fillWidth: true
    }

    component Kbd: Text {
        property string keys: ""
        text: keys
        color: Theme.accentStrong
        font.family: Theme.fontMono
        font.pixelSize: 11
        font.weight: Font.DemiBold
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 14

        // ─────────────────────────────────────────── Intro
        HelpCard {
            RowLayout {
                spacing: 12
                Layout.fillWidth: true
                Rectangle {
                    width: 36; height: 36; radius: 8
                    color: Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: "?"
                        color: "#06121a"
                        font.pixelSize: 20
                        font.weight: Font.Bold
                    }
                }
                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    H2 {
                        text: "Справка по heap."
                    }
                    Text {
                        text: "Всё, что умеет программа, в одном месте."
                        color: Theme.textMuted
                        font.pixelSize: 11
                    }
                }
            }
            Body {
                text: "heap. — это рабочий день C++-разработчика, разложенный по виджетам: канбан, таймлайн, "
                    + "недельный и дневной календарь, заметки, документация. Всё держится локально в JSON; "
                    + "ничего в облако не уходит. Ниже — экскурсия по разделам. Кликни пункт в оглавлении, "
                    + "чтобы прыгнуть к нужной теме."
            }
        }

        // ─────────────────────────────────────────── TOC
        HelpCard {
            H2 {
                text: "Оглавление"
            }
            Repeater {
                model: root.tocModel
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    radius: 6
                    color: tocMa.containsMouse ? Theme.panel2 : "transparent"
                    border.color: tocMa.containsMouse ? Theme.border : "transparent"
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 8
                        Text {
                            text: "›"
                            color: Theme.accentStrong
                            font.family: Theme.fontMono
                            font.pixelSize: 13
                        }
                        Text {
                            text: modelData.label
                            color: tocMa.containsMouse ? Theme.accentStrong : Theme.text
                            font.pixelSize: 12
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
                text: "Views — основные экраны"
            }
            Body {
                text: "Слева в боковой панели — кнопки переключения между видами. То, что показано в центре, "
                    + "и есть текущий вид. Канбан, Timeline и Week работают с одним набором задач, просто "
                    + "показывают их по-разному."
            }

            H3 {
                text: "Kanban Board"
            }
            Body {
                text: "Колонки — это статусы (To Do, In Progress, Review, Done и любые твои свои). Карточки "
                    + "тащатся между колонками и переупорядочиваются внутри. На карточке видны: ID, приоритет "
                    + "(P0–P3), название, ветка git (если задана), плашка времени, если задача поставлена в "
                    + "календарь. Колесо мыши горизонтально скроллит доску."
            }
            Hint {
                text: "Колонки настраиваются в Settings → Tasks: переименование, цвет, порядок, удаление."
            }

            H3 {
                text: "Timeline"
            }
            Body {
                text: "Задачи сгруппированы по бакетам: просрочено / сегодня / завтра / эта неделя / "
                    + "следующая / позже / без дедлайна. Внутри бакета — подгруппы по дате. Готовые задачи "
                    + "скрыты, можно включить переключателем «Показать выполненные»."
            }

            H3 {
                text: "Week View"
            }
            Body {
                text: "7 дней в виде колонок. Сверху — чипы дедлайнов (all-day), ниже — часовая сетка с "
                    + "событиями. Событие можно перетаскивать между днями и часами, тянуть верхний/нижний край "
                    + "для изменения длительности."
            }

            H3 {
                text: "Day Calendar (правая панель)"
            }
            Body {
                text: "Часовая сетка выбранного дня. Текущее время подсвечено живой линией. Клик по пустому "
                    + "месту создаёт часовое событие, drag по вертикали — событие нужной длительности. Drop "
                    + "карточки задачи на сетку планирует focus-блок на этот час."
            }
            Hint {
                text: "Границы рабочего дня (по умолчанию 9–19) меняются в Settings → Calendar."
            }

            H3 {
                text: "Docs"
            }
            Body {
                text: "Справочник по 4 разделам: 3GPP, internal, C++, tools. Внутри — секции с подсказками, "
                    + "сниппетами кода с подсветкой синтаксиса, и карточками контактов. Команд-палитра ищет "
                    + "сразу по всем секциям и сниппетам."
            }

            H3 {
                text: "Notes"
            }
            Body {
                text: "Один markdown-холст на профиль. Три режима: только редактор, split (превью рядом), только "
                    + "превью. Автокомплит @user и #ticket подтягивает людей и задачи активного профиля."
            }
        }

        // ─────────────────────────────────────────── TASKS
        HelpCard {
            objectName: "help-tasks"
            H2 {
                text: "Tasks — задачи и редактор"
            }

            H3 {
                text: "Создание"
            }
            Body {
                text: "Нажми кнопку «+» в TopBar, или хоткей "
            }
            RowLayout {
                spacing: 6; Kbd {
                    keys: "Ctrl+N"
                }
                Body {
                    text: "— откроется Task Editor с пустым черновиком."
                }
            }

            H3 {
                text: "Task Editor — поля"
            }
            Body {
                text: "ID присваивается на сохранении (формат — префикс из Settings → Tasks). Title — короткое "
                    + "название. Description — длинное описание с поддержкой @-упоминаний. Status — текущая "
                    + "колонка канбана. Priority — P0..P3 (влияет на цвет чипа и сортировку). Branch — ветка "
                    + "git, на которой висит задача (нужна для Git Watcher). Deadline — дата, можно вписать "
                    + "по-русски/по-английски естественно: «завтра 17:00», «friday 5pm», «в пятницу к вечеру»; "
                    + "парсер вытащит дату и (если есть) время."
            }

            H3 {
                text: "Статусы (колонки канбана)"
            }
            Body {
                text: "Статусы создаются и редактируются в Settings → Tasks. Drag в Settings меняет порядок "
                    + "колонок. Удаление статуса предлагает перенести задачи в другой; саму операцию можно "
                    + "откатить через "
            }
            RowLayout {
                spacing: 6; Kbd {
                    keys: "Ctrl+Z"
                }
                Body {
                    text: "пока активен undo-таймер."
                }
            }

            H3 {
                text: "Приоритеты P0–P3"
            }
            Body {
                text: "P0 — горит, P1 — важное, P2 — обычное, P3 — фоновое. Каждый имеет свой цвет в чипе "
                    + "карточки. Дефолтный приоритет новых задач задаётся в Settings → Tasks."
            }

            H3 {
                text: "Дедлайны"
            }
            Body {
                text: "Парсер дат принимает естественный язык. Время сохраняется отдельно от даты — если "
                    + "вписал «завтра 17:00», задача останется с deadline=завтра, а время используется для "
                    + "напоминаний и для авто-планирования focus-блока."
            }

            H3 {
                text: "PR-чип"
            }
            Body {
                text: "Если ветка задачи матчится с PR в отслеживаемом репозитории, на карточке появится "
                    + "чип состояния (pending / approved / changes requested) и список ревьюеров."
            }
        }

        // ─────────────────────────────────────────── QUICK CAPTURE
        HelpCard {
            objectName: "help-capture"
            H2 {
                text: "Quick Capture — быстрая фиксация"
            }
            Body {
                text: "Когда нужно скинуть мысль и не отвлекаться от текущего — открой Quick Capture "
                    + "(назначь хоткей в Settings → Shortcuts). Вписываешь одну строку или абзац — попап "
                    + "сам разберёт его на title, description, @-упоминания и дедлайн."
            }

            H3 {
                text: "Что разбирается автоматически"
            }
            Body {
                text: "Первая строка → title. Остальное → description. @username → создаст связь с человеком "
                    + "(или предложит создать, если такого ещё нет). Дата в любой форме («завтра», «through "
                    + "tuesday», «в среду к полудню») вытащится и подсветится отдельным чипом — справа сразу "
                    + "видно, какая дата распознана."
            }

            H3 {
                text: "Авто-классификация"
            }
            Body {
                text: "По формулировке текста Quick Capture угадывает тип задачи: focus (одиночная глубокая "
                    + "работа), sync (встреча/созвон), ticket (что-то с ID или связкой PR/Jira), generic. "
                    + "Тип влияет на цветовую маркировку события, если задача станет focus-блоком."
            }
            Hint {
                text: "Список placeholder-id будет вида TODO-N, пока ты не сохранишь — тогда сгенерится настоящий ID с префиксом профиля."
            }
        }

        // ─────────────────────────────────────────── CALENDAR
        HelpCard {
            objectName: "help-calendar"
            H2 {
                text: "Calendar — события и focus-блоки"
            }

            H3 {
                text: "Создание событий"
            }
            Body {
                text: "В Day Calendar и Week View клик по пустому месту делает часовое событие. Если зажать "
                    + "и потащить — длительность будет равна высоте, на которую ты протянул. Шаг привязки "
                    + "(по умолчанию 15 мин) задаётся в Settings → Calendar → Snap."
            }

            H3 {
                text: "Event Editor"
            }
            Body {
                text: "Поля: название, тип (focus / sync / standup / 1-on-1), start/end, дата, attendees, "
                    + "опциональная привязка к задаче (taskId). Привязанное событие подсвечивается ссылкой "
                    + "на канбан-карточку."
            }

            H3 {
                text: "Focus block — автопланирование"
            }
            Body {
                text: "Перетащи задачу из канбана на Day Calendar — появится focus-блок на этот час. Длина "
                    + "по умолчанию из Settings → Calendar → Focus duration (90 минут). Можно включить "
                    + "опцию «Auto focus block» — тогда блок будет создаваться сразу при переключении "
                    + "ветки git на ту, что привязана к задаче."
            }

            H3 {
                text: "Workday и формат времени"
            }
            Body {
                text: "Workday по умолчанию 9–19 — это видимая область Day Calendar. Меняй в Settings → "
                    + "Calendar. Формат времени переключается между 12h и 24h. Неделя стартует с пн или вс — "
                    + "тоже из настроек. Снепы 5/10/15/30 мин."
            }
        }

        // ─────────────────────────────────────────── PEOPLE
        HelpCard {
            objectName: "help-people"
            H2 {
                text: "People — контакты и упоминания"
            }
            Body {
                text: "Список людей в правой нижней панели — кому надо что-то ответить или написать. У "
                    + "каждого: имя, handle (уникальный), роль, цвет аватара, текущий вопрос."
            }

            H3 {
                text: "Цикл состояний"
            }
            Body {
                text: "Состояние крутится по клику: todo → pinged → replied → (скрыт, пока не вернёшь). "
                    + "Badge сверху показывает сколько ещё todo + сколько всего активных."
            }

            H3 {
                text: "Person Editor"
            }
            Body {
                text: "Создание/редактирование. Handle автоподбирается, если занят — добавит суффикс. "
                    + "Цвет берётся из палитры; именно этот цвет используется в @-упоминаниях."
            }

            H3 {
                text: "@-упоминания"
            }
            Body {
                text: "Введи @ + начало имени или handle в Quick Capture, Task Editor или Notes — выпадет "
                    + "fuzzy-список людей активного профиля. Выбор подставляет handle и связывает запись с "
                    + "человеком."
            }
        }

        // ─────────────────────────────────────────── PROFILES
        HelpCard {
            objectName: "help-profiles"
            H2 {
                text: "Profiles — рабочие пространства"
            }
            Body {
                text: "Профиль — это изолированный набор задач, людей, заметок и доки. Удобно держать "
                    + "разные проекты или контексты («работа», «pet», «учёба») раздельно — ничего не путается."
            }

            H3 {
                text: "Переключение"
            }
            RowLayout {
                spacing: 6
                Kbd {
                    keys: "Ctrl+Tab"
                }
                Body {
                    text: "— следующий профиль, "
                }
                Kbd {
                    keys: "Ctrl+Shift+Tab"
                }
                Body {
                    text: "— предыдущий. Pill в TopBar — клик открывает дропдаун."
                }
            }

            H3 {
                text: "Создание / переименование / дубликат / удаление"
            }
            Body {
                text: "Дропдаун профиля → «Новый…». Переименовать и сменить цвет — через тот же дропдаун или "
                    + "редактор. Дубликат копирует все данные в новый профиль с тем же содержимым. Удаление "
                    + "обратимо через "
            }
            RowLayout {
                spacing: 6; Kbd {
                    keys: "Ctrl+Z"
                }
                Body {
                    text: "пока активен undo-таймер."
                }
            }

            H3 {
                text: "JSON import / export"
            }
            Body {
                text: "Экспорт активного профиля → .json файл со всем содержимым (задачи, люди, статусы, "
                    + "заметки, доки). Импорт — обратно. Полезно для бэкапа и переноса между машинами."
            }
        }

        // ─────────────────────────────────────────── SEARCH / PALETTE
        HelpCard {
            objectName: "help-search"
            H2 {
                text: "Search & Command Palette"
            }

            H3 {
                text: "Command Palette"
            }
            RowLayout {
                spacing: 6
                Kbd {
                    keys: "Ctrl+K"
                }
                Body {
                    text: "— открывает fuzzy-поиск по всему: задачам всех профилей, секциям доки, "
                }
            }
            Body {
                text: "сниппетам, контактам, людям. Выбор задачи из другого профиля автоматически "
                    + "переключает профиль. Поиск нечеткий — опечатки тоже находятся."
            }

            H3 {
                text: "Inline-поиск"
            }
            RowLayout {
                spacing: 6
                Body {
                    text: "Клавиша "
                }
                Kbd {
                    keys: "/"
                }
                Body {
                    text: "переводит фокус в строку поиска TopBar. Фильтрует Kanban / Timeline / Week по "
                }
            }
            Body {
                text: "title, ID, description. Текст сохраняется в рамках сессии — переключения видов его "
                    + "не сбрасывают."
            }
        }

        // ─────────────────────────────────────────── FILTERS
        HelpCard {
            objectName: "help-filter"
            H2 {
                text: "Filters — приоритет, archived, show-done"
            }

            H3 {
                text: "Priority chips"
            }
            Body {
                text: "Полоса под TopBar: чипы P0/P1/P2/P3. Multi-select — можно включить несколько. "
                    + "«Clear» сбрасывает. Фильтр сохраняется между переключениями видов."
            }

            H3 {
                text: "Archived"
            }
            Body {
                text: "Чекбокс показывает заархивированные задачи. Архив — это отдельное состояние, не "
                    + "то же самое, что Done."
            }

            H3 {
                text: "Show Done (только Timeline)"
            }
            Body {
                text: "В таймлайне завершённые задачи скрыты по умолчанию. Тогл показывает их пунктирной "
                    + "карточкой."
            }

            H3 {
                text: "Blocked / Review badges"
            }
            Body {
                text: "В SideRail слева подсвечиваются счётчики задач в статусах blocked и review. Клик "
                    + "переводит в Kanban с включённым фильтром по этому статусу."
            }
        }

        // ─────────────────────────────────────────── TWEAKS
        HelpCard {
            objectName: "help-tweaks"
            H2 {
                text: "Tweaks — внешний вид"
            }
            RowLayout {
                spacing: 6
                Kbd {
                    keys: "Ctrl+T"
                }
                Body {
                    text: "— плавающая панель с быстрыми переключателями."
                }
            }

            H3 {
                text: "Theme"
            }
            Body {
                text: "Dark / Light. Меняется мгновенно, без рестарта."
            }

            H3 {
                text: "Density"
            }
            Body {
                text: "Compact (плотнее, меньше шрифты) или Comfy (просторнее)."
            }

            H3 {
                text: "Accent"
            }
            Body {
                text: "7 предустановленных свотчей — цвет акцента (выделение выбранного, чипы, ссылки). "
                    + "Брэнд-палитра в Brand.qml."
            }

            H3 {
                text: "Reduced motion"
            }
            Body {
                text: "Полностью выключает анимации — для слабых машин и для accessibility."
            }

            H3 {
                text: "High contrast"
            }
            Body {
                text: "Усиливает контраст границ и текста — для лучшей читаемости."
            }
        }

        // ─────────────────────────────────────────── HOTKEYS
        HelpCard {
            objectName: "help-hotkeys"
            H2 {
                text: "Hotkeys — клавиатура"
            }
            RowLayout {
                spacing: 6
                Kbd {
                    keys: "Ctrl+Shift+K"
                }
                Body {
                    text: "— открывает каталог хоткеев."
                }
            }
            Body {
                text: "Каждое действие можно перебиндить inline: кликаешь по shortcut-полю, нажимаешь "
                    + "новую комбинацию. Если такая уже занята другим действием — появится предупреждение о "
                    + "конфликте. Reset возвращает дефолт (отдельной кнопкой для каждого, и кнопкой Reset all "
                    + "для всех сразу)."
            }

            H3 {
                text: "Defaults"
            }
            Body {
                text: "Ctrl+K — палитра, Ctrl+N — новая задача, Ctrl+1/2/3/4/5 — Kanban / Timeline / Week / "
                    + "Docs / Notes, Ctrl+, — Settings, Ctrl+Tab / Ctrl+Shift+Tab — следующий/предыдущий "
                    + "профиль, Ctrl+Z — undo, Ctrl+T — Tweaks, Ctrl+Shift+K — каталог хоткеев, «/» — фокус "
                    + "на поиск."
            }
        }

        // ─────────────────────────────────────────── AUTOMATION / NOTIFICATIONS
        HelpCard {
            objectName: "help-automation"
            H2 {
                text: "Automation & Notifications"
            }
            Body {
                text: "Раз в минуту фоновый тикер проверяет: подходят ли дедлайны, висят ли задачи в "
                    + "blocked слишком долго, не пора ли заархивировать done. Уведомления уходят системному "
                    + "тосту (на Linux — через org.freedesktop.Notifications с реальными action-кнопками, на "
                    + "Windows/macOS — fallback через tray-балун)."
            }

            H3 {
                text: "Deadline reminders"
            }
            Body {
                text: "За N часов до дедлайна (по умолчанию 24, настраивается в Settings → Notifications) — "
                    + "толкнёт уведомление. В уведомлении есть action «Snooze 1h»."
            }

            H3 {
                text: "Standup reminder"
            }
            Body {
                text: "Ежедневно в standup-time (default 10:00). Время меняется в Settings → Notifications."
            }

            H3 {
                text: "Blocked stuck warning"
            }
            Body {
                text: "Если задача висит в blocked больше N дней (default 3) — на карточке появится "
                    + "warning-badge, а в SideRail счётчик подскочит. Можно настроить автоперевод в другой "
                    + "статус через N дней."
            }

            H3 {
                text: "Auto-archive done"
            }
            Body {
                text: "Задачи в done старше N дней (default 7) автоматически уходят в архив. Видны только "
                    + "при включённом тогле «Archived»."
            }

            H3 {
                text: "Quiet hours"
            }
            Body {
                text: "Окно тишины (default 19:00–09:00) подавляет десктопные уведомления, но не сами "
                    + "напоминания — внутри приложения тост всё равно появится."
            }

            H3 {
                text: "Toasts"
            }
            Body {
                text: "Транзиентные сообщения внизу экрана. На обратимых действиях (удаление) показывают "
                    + "кнопку «Отменить» в течение нескольких секунд."
            }
        }

        // ─────────────────────────────────────────── GIT
        HelpCard {
            objectName: "help-git"
            H2 {
                text: "Git Watcher — фокус по ветке"
            }
            Body {
                text: "Watcher следит за списком репозиториев из Settings → Git Watcher. Когда ты "
                    + "переключаешь ветку в одном из них — heap. смотрит, есть ли задача с такой же branch. "
                    + "Если есть — в TopBar появляется фокус-баннер с ID задачи, именем ветки и состоянием PR."
            }

            H3 {
                text: "Auto move to in-progress"
            }
            Body {
                text: "Опция: автоматически переводит задачу в статус «In Progress», когда ты переключился "
                    + "на её ветку."
            }

            H3 {
                text: "Auto focus block"
            }
            Body {
                text: "Опция: автоматически бронирует focus-блок в Day Calendar на ближайший свободный час "
                    + "при переключении на ветку задачи. Длина блока — из Settings → Calendar."
            }

            H3 {
                text: "PR state chips"
            }
            Body {
                text: "Watcher периодически читает состояние PR (pending / approved / changes requested) и "
                    + "отображает чип на карточке задачи и в редакторе. Список ревьюеров тоже подтягивается."
            }

            H3 {
                text: "Dismiss banner"
            }
            Body {
                text: "Не нужен баннер? Кликни «×» — он скроется до следующего переключения ветки. "
                    + "Полностью отключить — снять отслеживание репо в Settings → Git Watcher."
            }
        }

        // ─────────────────────────────────────────── UNDO & BACKUPS
        HelpCard {
            objectName: "help-undo"
            H2 {
                text: "Undo & Backups"
            }

            H3 {
                text: "Undo последнего удаления"
            }
            RowLayout {
                spacing: 6
                Kbd {
                    keys: "Ctrl+Z"
                }
                Body {
                    text: "восстанавливает только что удалённый объект: задачу, событие, человека, "
                }
            }
            Body {
                text: "статус (с возвратом всех его задач) или целый профиль. Окно действия — несколько "
                    + "секунд после удаления (видно по тосту с кнопкой «Отменить»). После того как таймер "
                    + "выйдет — операция считается финальной."
            }

            H3 {
                text: "Auto-backups"
            }
            Body {
                text: "Раз в день (раз в N минут на самом деле, проверяется при сохранении) heap. кладёт "
                    + "снапшот текущего состояния в AppDataLocation/backups/. Хранится последние N штук "
                    + "(default 7), старые удаляются."
            }

            H3 {
                text: "Restore"
            }
            Body {
                text: "Settings → Data → список бэкапов. Восстановление перезаписывает текущее состояние, "
                    + "но перед этим само создаёт ещё один бэкап — на случай, если ты передумал."
            }
        }

        // ─────────────────────────────────────────── DATA
        HelpCard {
            objectName: "help-data"
            H2 {
                text: "Data — экспорт, импорт, сброс"
            }

            H3 {
                text: "Export JSON"
            }
            Body {
                text: "Сохраняет активный профиль целиком (задачи, люди, статусы, заметки, доки, события) "
                    + "в один .json файл. Файл человекочитаемый — можно открыть редактором, поправить "
                    + "руками, импортнуть обратно."
            }

            H3 {
                text: "Import JSON"
            }
            Body {
                text: "Загружает .json в новый профиль или поверх существующего (с подтверждением). "
                    + "Полезно для миграции между машинами или восстановления из бэкапа."
            }

            H3 {
                text: "Reset app"
            }
            Body {
                text: "Стирает все профили, настройки и историю. Делает бэкап перед сбросом, на всякий "
                    + "случай — путь к бэкапу выводится в тосте."
            }
        }

        // ─────────────────────────────────────────── TIPS
        HelpCard {
            objectName: "help-tips"
            H2 {
                text: "Tips — мелочи, которые не очевидны"
            }

            H3 {
                text: "Day Calendar — drag empty area"
            }
            Body {
                text: "Не просто клик, а зажми и протяни вертикально — длительность нового события будет "
                    + "ровно такой, на сколько ты его растянул."
            }

            H3 {
                text: "Drag TaskCard на календарь"
            }
            Body {
                text: "Из канбана/таймлайна можно дропнуть карточку прямо в Day Calendar — focus-блок "
                    + "появится на том часу, куда отпустил."
            }

            H3 {
                text: "MiniWeek dots"
            }
            Body {
                text: "Маленькие точки под датой в верхней панели — это маркер того, что в этот день есть "
                    + "хотя бы одно событие. Полезно для быстрого скана недели."
            }

            H3 {
                text: "Now-line в Day Calendar"
            }
            Body {
                text: "Горизонтальная линия — текущее время. Обновляется раз в минуту. Видна только если "
                    + "выбран сегодняшний день и время попадает в workday."
            }

            H3 {
                text: "Breadcrumbs в TopBar"
            }
            Body {
                text: "«Проект / спринт / пользователь» можно редактировать на месте — кликни по нужной "
                    + "хлебной крошке. Сохраняется в настройках."
            }

            H3 {
                text: "Resize handles событий"
            }
            Body {
                text: "Верхний и нижний край события — это resize-хэндлы (видны при ховере). Тащить "
                    + "середину — двигать целиком, тащить край — менять длительность."
            }

            H3 {
                text: "Profile pill цвет"
            }
            Body {
                text: "Цвет точки рядом с именем профиля в TopBar — это его accent. Это же цвет "
                    + "используется для маркировки событий, которые принадлежат именно этому профилю."
            }

            H3 {
                text: "Sound on ping"
            }
            Body {
                text: "Отдельная опция в Settings → Notifications — звук при срабатывании уведомления. "
                    + "Уважает quiet hours."
            }

            H3 {
                text: "Hotkey конфликты"
            }
            Body {
                text: "При перебиндинге показывает кто ещё держит эту комбинацию. Можно либо отказаться, "
                    + "либо перетереть."
            }
        }

        // ─────────────────────────────────────────── Outro
        HelpCard {
            Hint {
                text: "Чего-то не хватает или нашёл странное поведение? Логи и состояние лежат в "
                    + "AppDataLocation. Версия и точные пути — на странице About."
            }
        }
    }
}
