import QtQuick
import QtQuick.Layouts
import TodoCpp

Item {
    id: root

    signal anchorRequested(string objectName)

    implicitHeight: col.implicitHeight
    implicitWidth: col.implicitWidth

    readonly property var tocModel: [
        {anchor: "help-views", label: "Views — Kanban, Timeline, Week, Day, Docs, Notes"},
        {anchor: "help-tasks", label: "Tasks — statuses, priorities, deadlines"},
        {anchor: "help-capture", label: "Quick Capture — text parsing, @-mentions"},
        {anchor: "help-calendar", label: "Calendar — events, drag-create, focus blocks"},
        {anchor: "help-people", label: "People — contacts, mentions, state cycle"},
        {anchor: "help-profiles", label: "Profiles — workspaces, JSON"},
        {anchor: "help-search", label: "Search & Command Palette"},
        {anchor: "help-filter", label: "Filters — priorities, archived, show-done"},
        {anchor: "help-tweaks", label: "Tweaks — theme, density, accent"},
        {anchor: "help-hotkeys", label: "Hotkeys — rebinding and conflicts"},
        {anchor: "help-automation", label: "Automation & Notifications"},
        {anchor: "help-git", label: "Git Watcher — branch focus, PR"},
        {anchor: "help-undo", label: "Undo & Backups"},
        {anchor: "help-data", label: "Data — JSON import/export, reset"},
        {anchor: "help-tips", label: "Tips & non-obvious things"}
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
                        text: "heap. help."
                    }
                    Text {
                        text: "Everything the app can do, in one place."
                        color: Theme.textMuted
                        font.pixelSize: 11
                    }
                }
            }
            Body {
                text: "heap. — a C++ developer's workday laid out across widgets: kanban, timeline, "
                    + "weekly and daily calendar, notes, documentation. Everything stays local in JSON; "
                    + "nothing goes to the cloud. Below — a tour of the sections. Click an item in the table "
                    + "of contents to jump to the topic you need."
            }
        }

        // ─────────────────────────────────────────── TOC
        HelpCard {
            H2 {
                text: "Table of Contents"
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
                text: "Views — main screens"
            }
            Body {
                text: "On the left in the sidebar — buttons for switching between views. What is shown in "
                    + "the center is the current view. Kanban, Timeline, and Week all work with the same set "
                    + "of tasks, they just display them differently."
            }

            H3 {
                text: "Kanban Board"
            }
            Body {
                text: "Columns are statuses (To Do, In Progress, Review, Done, and any of your own). Cards "
                    + "are dragged between columns and reordered within them. A card shows: ID, priority "
                    + "(P0–P3), title, git branch (if set), and a time badge if the task is placed on the "
                    + "calendar. The mouse wheel scrolls the board horizontally."
            }
            Hint {
                text: "Columns are configured in Settings → Tasks: rename, color, order, delete."
            }

            H3 {
                text: "Timeline"
            }
            Body {
                text: "Tasks are grouped into buckets: overdue / today / tomorrow / this week / next / "
                    + "later / no deadline. Within a bucket — subgroups by date. Completed tasks are hidden; "
                    + "you can turn them on with the 'Show done' toggle."
            }

            H3 {
                text: "Week View"
            }
            Body {
                text: "7 days as columns. At the top — deadline chips (all-day), below — an hourly grid with "
                    + "events. An event can be dragged between days and hours; drag the top/bottom edge to "
                    + "change its duration."
            }

            H3 {
                text: "Day Calendar (right panel)"
            }
            Body {
                text: "An hourly grid for the selected day. The current time is highlighted with a live "
                    + "line. Clicking an empty spot creates an hour-long event; a vertical drag — an event of "
                    + "the duration you need. Dropping a task card on the grid schedules a focus block for "
                    + "that hour."
            }
            Hint {
                text: "Workday bounds (9–19 by default) are changed in Settings → Calendar."
            }

            H3 {
                text: "Docs"
            }
            Body {
                text: "A reference across 4 sections: 3GPP, internal, C++, tools. Inside — sections with "
                    + "tips, code snippets with syntax highlighting, and contact cards. The command palette "
                    + "searches across all sections and snippets at once."
            }

            H3 {
                text: "Notes"
            }
            Body {
                text: "One markdown canvas per profile. Three modes: editor only, split (preview alongside), "
                    + "preview only. Autocomplete for @user and #ticket pulls in the people and tasks of the "
                    + "active profile."
            }
        }

        // ─────────────────────────────────────────── TASKS
        HelpCard {
            objectName: "help-tasks"
            H2 {
                text: "Tasks — tasks and the editor"
            }

            H3 {
                text: "Creating"
            }
            Body {
                text: "Press the '+' button in the TopBar, or the hotkey "
            }
            RowLayout {
                spacing: 6; Kbd {
                    keys: "Ctrl+N"
                }
                Body {
                    text: "— the Task Editor opens with an empty draft."
                }
            }

            H3 {
                text: "Task Editor — fields"
            }
            Body {
                text: "The ID is assigned on save (format — a prefix from Settings → Tasks). Title — a short "
                    + "name. Description — a long description with support for @-mentions. Status — the "
                    + "current kanban column. Priority — P0..P3 (affects the chip color and sorting). "
                    + "Branch — the git branch the task lives on (needed for Git Watcher). Deadline — a date, "
                    + "which you can type naturally: 'tomorrow 17:00', 'friday 5pm', 'friday evening'; the "
                    + "parser extracts the date and (if present) the time."
            }

            H3 {
                text: "Statuses (kanban columns)"
            }
            Body {
                text: "Statuses are created and edited in Settings → Tasks. Dragging in Settings changes the "
                    + "column order. Deleting a status offers to move its tasks to another one; the operation "
                    + "itself can be undone with "
            }
            RowLayout {
                spacing: 6; Kbd {
                    keys: "Ctrl+Z"
                }
                Body {
                    text: "while the undo timer is active."
                }
            }

            H3 {
                text: "Priorities P0–P3"
            }
            Body {
                text: "P0 — on fire, P1 — important, P2 — normal, P3 — background. Each has its own color in "
                    + "the card chip. The default priority for new tasks is set in Settings → Tasks."
            }

            H3 {
                text: "Deadlines"
            }
            Body {
                text: "The date parser accepts natural language. Time is stored separately from the date — "
                    + "if you typed 'tomorrow 17:00', the task keeps deadline=tomorrow, while the time is used "
                    + "for reminders and for auto-scheduling a focus block."
            }

            H3 {
                text: "PR chip"
            }
            Body {
                text: "If the task's branch matches a PR in a tracked repository, a state chip "
                    + "(pending / approved / changes requested) and a list of reviewers appear on the card."
            }
        }

        // ─────────────────────────────────────────── QUICK CAPTURE
        HelpCard {
            objectName: "help-capture"
            H2 {
                text: "Quick Capture — fast capture"
            }
            Body {
                text: "When you need to dump a thought without breaking away from what you're doing — open "
                    + "Quick Capture (assign a hotkey in Settings → Shortcuts). You type one line or a "
                    + "paragraph — the popup parses it into title, description, @-mentions, and deadline on "
                    + "its own."
            }

            H3 {
                text: "What gets parsed automatically"
            }
            Body {
                text: "The first line → title. The rest → description. @username → creates a link to a "
                    + "person (or offers to create one if they don't exist yet). A date in any form "
                    + "('tomorrow', 'through tuesday', 'wednesday at noon') is extracted and highlighted as a "
                    + "separate chip — on the right you can immediately see which date was recognized."
            }

            H3 {
                text: "Auto-classification"
            }
            Body {
                text: "From the wording of the text, Quick Capture guesses the task type: focus (solo deep "
                    + "work), sync (a meeting/call), ticket (something with an ID or a PR/Jira link), generic. "
                    + "The type affects the color coding of the event if the task becomes a focus block."
            }
            Hint {
                text: "The placeholder id will look like TODO-N until you save — then a real ID with the profile prefix is generated."
            }
        }

        // ─────────────────────────────────────────── CALENDAR
        HelpCard {
            objectName: "help-calendar"
            H2 {
                text: "Calendar — events and focus blocks"
            }

            H3 {
                text: "Creating events"
            }
            Body {
                text: "In Day Calendar and Week View, clicking an empty spot makes an hour-long event. If "
                    + "you hold and drag — the duration equals the height you dragged across. The snap step "
                    + "(15 min by default) is set in Settings → Calendar → Snap."
            }

            H3 {
                text: "Event Editor"
            }
            Body {
                text: "Fields: title, type (focus / sync / standup / 1-on-1), start/end, date, attendees, "
                    + "an optional link to a task (taskId). A linked event is highlighted with a link to the "
                    + "kanban card."
            }

            H3 {
                text: "Focus block — auto-scheduling"
            }
            Body {
                text: "Drag a task from the kanban onto the Day Calendar — a focus block appears for that "
                    + "hour. The default length comes from Settings → Calendar → Focus duration (90 minutes). "
                    + "You can enable the 'Auto focus block' option — then the block is created as soon as "
                    + "you switch the git branch to the one linked to the task."
            }

            H3 {
                text: "Workday and time format"
            }
            Body {
                text: "The workday is 9–19 by default — this is the visible area of the Day Calendar. Change "
                    + "it in Settings → Calendar. The time format switches between 12h and 24h. The week "
                    + "starts on Mon or Sun — also from settings. Snaps are 5/10/15/30 min."
            }
        }

        // ─────────────────────────────────────────── PEOPLE
        HelpCard {
            objectName: "help-people"
            H2 {
                text: "People — contacts and mentions"
            }
            Body {
                text: "The list of people in the bottom-right panel — who you need to reply to or write to. "
                    + "Each has: a name, a handle (unique), a role, an avatar color, a current question."
            }

            H3 {
                text: "State cycle"
            }
            Body {
                text: "The state cycles on click: todo → pinged → replied → (hidden until you bring it "
                    + "back). The badge at the top shows how many are still todo + how many are active in "
                    + "total."
            }

            H3 {
                text: "Person Editor"
            }
            Body {
                text: "Creating/editing. The handle is auto-picked; if it's taken — a suffix is added. "
                    + "The color is taken from the palette; this exact color is used in @-mentions."
            }

            H3 {
                text: "@-mentions"
            }
            Body {
                text: "Type @ + the start of a name or handle in Quick Capture, Task Editor, or Notes — a "
                    + "fuzzy list of the active profile's people drops down. Selecting one inserts the handle "
                    + "and links the entry to that person."
            }
        }

        // ─────────────────────────────────────────── PROFILES
        HelpCard {
            objectName: "help-profiles"
            H2 {
                text: "Profiles — workspaces"
            }
            Body {
                text: "A profile is an isolated set of tasks, people, notes, and docs. It's handy to keep "
                    + "different projects or contexts ('work', 'pet', 'study') separate — nothing gets mixed up."
            }

            H3 {
                text: "Switching"
            }
            RowLayout {
                spacing: 6
                Kbd {
                    keys: "Ctrl+Tab"
                }
                Body {
                    text: "— next profile, "
                }
                Kbd {
                    keys: "Ctrl+Shift+Tab"
                }
                Body {
                    text: "— previous. The pill in the TopBar — clicking it opens the dropdown."
                }
            }

            H3 {
                text: "Create / rename / duplicate / delete"
            }
            Body {
                text: "Profile dropdown → 'New…'. Rename and change color — through the same dropdown or the "
                    + "editor. Duplicate copies all data into a new profile with the same content. Deletion is "
                    + "reversible with "
            }
            RowLayout {
                spacing: 6; Kbd {
                    keys: "Ctrl+Z"
                }
                Body {
                    text: "while the undo timer is active."
                }
            }

            H3 {
                text: "JSON import / export"
            }
            Body {
                text: "Export the active profile → a .json file with all its content (tasks, people, "
                    + "statuses, notes, docs). Import — the other way around. Useful for backups and moving "
                    + "between machines."
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
                    text: "— opens a fuzzy search over everything: tasks in all profiles, doc sections, "
                }
            }
            Body {
                text: "snippets, contacts, people. Selecting a task from another profile automatically "
                    + "switches the profile. The search is fuzzy — typos are found too."
            }

            H3 {
                text: "Inline search"
            }
            RowLayout {
                spacing: 6
                Body {
                    text: "The "
                }
                Kbd {
                    keys: "/"
                }
                Body {
                    text: "key moves focus to the TopBar search field. Filters Kanban / Timeline / Week by "
                }
            }
            Body {
                text: "title, ID, description. The text persists within the session — switching views does "
                    + "not reset it."
            }
        }

        // ─────────────────────────────────────────── FILTERS
        HelpCard {
            objectName: "help-filter"
            H2 {
                text: "Filters — priority, archived, show-done"
            }

            H3 {
                text: "Priority chips"
            }
            Body {
                text: "A strip under the TopBar: P0/P1/P2/P3 chips. Multi-select — you can enable several. "
                    + "'Clear' resets them. The filter persists across view switches."
            }

            H3 {
                text: "Archived"
            }
            Body {
                text: "The checkbox shows archived tasks. Archive is a separate state, not the same thing "
                    + "as Done."
            }

            H3 {
                text: "Show Done (Timeline only)"
            }
            Body {
                text: "In the timeline, completed tasks are hidden by default. The toggle shows them as a "
                    + "dashed card."
            }

            H3 {
                text: "Blocked / Review badges"
            }
            Body {
                text: "In the SideRail on the left, counters of tasks in the blocked and review statuses are "
                    + "highlighted. Clicking takes you to Kanban with the filter for that status enabled."
            }
        }

        // ─────────────────────────────────────────── TWEAKS
        HelpCard {
            objectName: "help-tweaks"
            H2 {
                text: "Tweaks — appearance"
            }
            RowLayout {
                spacing: 6
                Kbd {
                    keys: "Ctrl+T"
                }
                Body {
                    text: "— a floating panel with quick toggles."
                }
            }

            H3 {
                text: "Theme"
            }
            Body {
                text: "Dark / Light. Changes instantly, no restart."
            }

            H3 {
                text: "Density"
            }
            Body {
                text: "Compact (tighter, smaller fonts) or Comfy (roomier)."
            }

            H3 {
                text: "Accent"
            }
            Body {
                text: "7 preset swatches — the accent color (selection highlight, chips, links). "
                    + "The brand palette lives in Brand.qml."
            }

            H3 {
                text: "Reduced motion"
            }
            Body {
                text: "Fully disables animations — for weak machines and for accessibility."
            }

            H3 {
                text: "High contrast"
            }
            Body {
                text: "Boosts the contrast of borders and text — for better readability."
            }
        }

        // ─────────────────────────────────────────── HOTKEYS
        HelpCard {
            objectName: "help-hotkeys"
            H2 {
                text: "Hotkeys — keyboard"
            }
            RowLayout {
                spacing: 6
                Kbd {
                    keys: "Ctrl+Shift+K"
                }
                Body {
                    text: "— opens the hotkey catalog."
                }
            }
            Body {
                text: "Every action can be rebound inline: you click the shortcut field, then press a new "
                    + "combination. If it's already taken by another action — a conflict warning appears. "
                    + "Reset restores the default (a separate button for each, and a Reset all button for all "
                    + "at once)."
            }

            H3 {
                text: "Defaults"
            }
            Body {
                text: "Ctrl+K — palette, Ctrl+N — new task, Ctrl+1/2/3/4/5 — Kanban / Timeline / Week / "
                    + "Docs / Notes, Ctrl+, — Settings, Ctrl+Tab / Ctrl+Shift+Tab — next/previous profile, "
                    + "Ctrl+Z — undo, Ctrl+T — Tweaks, Ctrl+Shift+K — hotkey catalog, '/' — focus search."
            }
        }

        // ─────────────────────────────────────────── AUTOMATION / NOTIFICATIONS
        HelpCard {
            objectName: "help-automation"
            H2 {
                text: "Automation & Notifications"
            }
            Body {
                text: "Once a minute a background ticker checks: whether deadlines are approaching, whether "
                    + "tasks have been stuck in blocked too long, whether it's time to archive done. "
                    + "Notifications go to the system toast (on Linux — via org.freedesktop.Notifications with "
                    + "real action buttons, on Windows/macOS — a fallback via a tray balloon)."
            }

            H3 {
                text: "Deadline reminders"
            }
            Body {
                text: "N hours before a deadline (24 by default, configurable in Settings → Notifications) — "
                    + "it pushes a notification. The notification has a 'Snooze 1h' action."
            }

            H3 {
                text: "Standup reminder"
            }
            Body {
                text: "Daily at standup-time (default 10:00). The time is changed in Settings → Notifications."
            }

            H3 {
                text: "Blocked stuck warning"
            }
            Body {
                text: "If a task sits in blocked for more than N days (default 3) — a warning badge appears "
                    + "on the card, and the SideRail counter jumps. You can configure an auto-move to another "
                    + "status after N days."
            }

            H3 {
                text: "Auto-archive done"
            }
            Body {
                text: "Tasks in done older than N days (default 7) automatically go to the archive. They are "
                    + "visible only when the 'Archived' toggle is on."
            }

            H3 {
                text: "Quiet hours"
            }
            Body {
                text: "The quiet window (default 19:00–09:00) suppresses desktop notifications, but not the "
                    + "reminders themselves — inside the app the toast still appears."
            }

            H3 {
                text: "Toasts"
            }
            Body {
                text: "Transient messages at the bottom of the screen. For reversible actions (deletion) "
                    + "they show an 'Undo' button for a few seconds."
            }
        }

        // ─────────────────────────────────────────── GIT
        HelpCard {
            objectName: "help-git"
            H2 {
                text: "Git Watcher — branch focus"
            }
            Body {
                text: "The watcher monitors the list of repositories from Settings → Git Watcher. When you "
                    + "switch a branch in one of them — heap. checks whether there's a task with the same "
                    + "branch. If there is — a focus banner with the task ID, branch name, and PR state "
                    + "appears in the TopBar."
            }

            H3 {
                text: "Auto move to in-progress"
            }
            Body {
                text: "An option: automatically moves the task to the 'In Progress' status when you switch "
                    + "to its branch."
            }

            H3 {
                text: "Auto focus block"
            }
            Body {
                text: "An option: automatically books a focus block in the Day Calendar at the nearest free "
                    + "hour when you switch to the task's branch. The block length — from Settings → Calendar."
            }

            H3 {
                text: "PR state chips"
            }
            Body {
                text: "The watcher periodically reads the PR state (pending / approved / changes requested) "
                    + "and shows a chip on the task card and in the editor. The list of reviewers is pulled "
                    + "in too."
            }

            H3 {
                text: "Dismiss banner"
            }
            Body {
                text: "Don't need the banner? Click '×' — it hides until the next branch switch. "
                    + "To disable it completely — untrack the repo in Settings → Git Watcher."
            }
        }

        // ─────────────────────────────────────────── UNDO & BACKUPS
        HelpCard {
            objectName: "help-undo"
            H2 {
                text: "Undo & Backups"
            }

            H3 {
                text: "Undo the last deletion"
            }
            RowLayout {
                spacing: 6
                Kbd {
                    keys: "Ctrl+Z"
                }
                Body {
                    text: "restores the object you just deleted: a task, an event, a person, "
                }
            }
            Body {
                text: "a status (bringing back all of its tasks), or an entire profile. The window of "
                    + "action — a few seconds after deletion (shown by the toast with the 'Undo' button). "
                    + "Once the timer runs out — the operation is considered final."
            }

            H3 {
                text: "Auto-backups"
            }
            Body {
                text: "Once a day (once every N minutes really, checked on save) heap. writes a snapshot of "
                    + "the current state to AppDataLocation/backups/. The last N are kept (default 7), older "
                    + "ones are deleted."
            }

            H3 {
                text: "Restore"
            }
            Body {
                text: "Settings → Data → the list of backups. Restoring overwrites the current state, but "
                    + "before that it creates one more backup itself — in case you change your mind."
            }
        }

        // ─────────────────────────────────────────── DATA
        HelpCard {
            objectName: "help-data"
            H2 {
                text: "Data — export, import, reset"
            }

            H3 {
                text: "Export JSON"
            }
            Body {
                text: "Saves the entire active profile (tasks, people, statuses, notes, docs, events) into a "
                    + "single .json file. The file is human-readable — you can open it in an editor, edit it "
                    + "by hand, and import it back."
            }

            H3 {
                text: "Import JSON"
            }
            Body {
                text: "Loads a .json into a new profile or over an existing one (with confirmation). "
                    + "Useful for migrating between machines or restoring from a backup."
            }

            H3 {
                text: "Reset app"
            }
            Body {
                text: "Wipes all profiles, settings, and history. Makes a backup before resetting, just in "
                    + "case — the path to the backup is shown in a toast."
            }
        }

        // ─────────────────────────────────────────── TIPS
        HelpCard {
            objectName: "help-tips"
            H2 {
                text: "Tips — small things that aren't obvious"
            }

            H3 {
                text: "Day Calendar — drag empty area"
            }
            Body {
                text: "Not just a click — hold and drag vertically, and the duration of the new event will "
                    + "be exactly as far as you stretched it."
            }

            H3 {
                text: "Drag TaskCard onto the calendar"
            }
            Body {
                text: "From the kanban/timeline you can drop a card straight into the Day Calendar — a "
                    + "focus block appears at the hour where you released it."
            }

            H3 {
                text: "MiniWeek dots"
            }
            Body {
                text: "The small dots under a date in the top panel are a marker that this day has at least "
                    + "one event. Handy for a quick scan of the week."
            }

            H3 {
                text: "Now-line in Day Calendar"
            }
            Body {
                text: "The horizontal line — the current time. Updates once a minute. Visible only if today "
                    + "is selected and the time falls within the workday."
            }

            H3 {
                text: "Breadcrumbs in TopBar"
            }
            Body {
                text: "'Project / sprint / user' can be edited in place — click the breadcrumb you need. "
                    + "It's saved in settings."
            }

            H3 {
                text: "Event resize handles"
            }
            Body {
                text: "The top and bottom edges of an event are resize handles (visible on hover). Drag the "
                    + "middle — move the whole thing, drag an edge — change the duration."
            }

            H3 {
                text: "Profile pill color"
            }
            Body {
                text: "The color of the dot next to the profile name in the TopBar is its accent. This same "
                    + "color is used to mark the events that belong to this specific profile."
            }

            H3 {
                text: "Sound on ping"
            }
            Body {
                text: "A separate option in Settings → Notifications — a sound when a notification fires. "
                    + "It respects quiet hours."
            }

            H3 {
                text: "Hotkey conflicts"
            }
            Body {
                text: "When rebinding, it shows who else holds that combination. You can either back out or "
                    + "overwrite it."
            }
        }

        // ─────────────────────────────────────────── Outro
        HelpCard {
            Hint {
                text: "Something missing or found strange behavior? Logs and state live in "
                    + "AppDataLocation. The version and exact paths — on the About page."
            }
        }
    }
}
