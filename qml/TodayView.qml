pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as QQC
import TodoCpp
import "Reschedule.js" as Resched

// Today (heap 2, APP-260): the start screen. The date and one line of facts;
// the day by the hours — meetings filled, tasks outlined with their status,
// the free windows as facts, the line of "now", the end of the working day;
// on the side what is in progress, what is due, whom to write, and how many
// tasks have no date. It shows; lowkey places nothing by itself.
//
// The day shown is AppController.selectedDate, so Alt+←/→ and the arrows in
// the header move it, and T (cal.today) brings it back.
FocusScope {
    id: root
    objectName: "today-view"

    signal eventClicked(string id, var occurrence)
    signal createRequested(real startHour, real endHour, var day)
    signal taskClicked(string id)
    // "N tasks without a date": Tasks · List with that condition.
    signal undatedRequested()
    signal recapRequested()
    // The first-run screen (APP-271): a task made from its line, and where
    // tasks from elsewhere come in.
    signal firstTaskCreated(string id)
    signal connectRequested()
    signal importRequested()
    signal exampleRequested()

    property bool allProfiles: false
    function focusView() {
        if (root.firstRun) firstRunHero.focusInput();
        else root.forceActiveFocus();
    }

    readonly property date day: AppController.selectedDate
    readonly property bool isToday: root._sameDay(root.day, AppController.today)
    function _sameDay(a: date, b: date): bool {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    // Rebuilt when tasks, meetings or people change; the minute ticks too.
    property int _rev: 0
    Connections { target: AppController.tasks; function onDataChanged() { root._rev++; } function onRowsInserted() { root._rev++; } function onRowsRemoved() { root._rev++; } function onModelReset() { root._rev++; } }
    Connections { target: AppController.events; function onDataChanged() { root._rev++; } function onRowsInserted() { root._rev++; } function onRowsRemoved() { root._rev++; } function onModelReset() { root._rev++; } }
    Connections { target: AppController.people; function onDataChanged() { root._rev++; } function onRowsInserted() { root._rev++; } function onRowsRemoved() { root._rev++; } function onModelReset() { root._rev++; } }
    Connections { target: AppController; function onTodayChanged() { root._rev++; } function onFocusedGitChanged() { root._rev++; } }
    Timer { interval: 60000; repeat: true; running: root.visible; onTriggered: root._rev++ }

    readonly property var dayData: root._rev >= 0 ? AppController.todayData(root.day, root.allProfiles) : ({})
    // Until the first task (APP-271): the input line, three keys, and the
    // way in for tasks that live elsewhere — instead of a tour. Closed
    // before a task was made, it is here again on the next start.
    readonly property bool firstRun: !AppController.welcomeSeen && root._rev >= 0 && AppController.tasks.rowCount() === 0
    readonly property real nowHour: {
        const n = root._rev >= 0 ? new Date() : new Date();
        return n.getHours() + n.getMinutes() / 60;
    }

    // ── text ──
    function _facts() {
        const f = root.dayData.facts || {};
        const parts = [];
        if (f.meetings > 0) parts.push(I18n.count(f.meetings, "today.n.meetings"));
        if (f.planned > 0) parts.push(I18n.count(f.planned, "today.n.planned"));
        if (f.dueToday > 0) parts.push(I18n.count(f.dueToday, "today.n.due"));
        return parts.join(" · ");
    }
    function _hm(h) {
        const hh = Math.floor(h + 1e-6), mm = Math.round((h - hh) * 60);
        return Theme.fmtHour(hh + mm / 60);
    }
    function _len(a, b) { return I18n.fmtMinutes(Math.round((b - a) * 60)); }

    // The day as rows: all-day above, then by time with the free windows,
    // "now" and the end of the working day put in their places.
    readonly property var rows: {
        const d = root.dayData;
        const out = [];
        if (!d.blocks) return out;
        for (const b of d.allDay || []) out.push({ kind: "allday", start: -1, block: b });
        for (const b of d.blocks) out.push({ kind: b.kind, start: b.start, block: b });
        for (const g of d.free || []) out.push({ kind: "free", start: g.start, end: g.end });
        if (root.isToday && root.nowHour >= d.fromHour && root.nowHour <= Math.max(d.toHour, d.workEnd))
            out.push({ kind: "now", start: root.nowHour });
        if (d.workday) out.push({ kind: "end", start: d.workEnd });
        const order = { allday: 0, free: 1, meeting: 2, task: 2, now: 3, end: 4 };
        out.sort((a, b) => a.start - b.start || order[a.kind] - order[b.kind]);
        return out;
    }

    Keys.onPressed: (e) => {
        if (e.modifiers & Qt.AltModifier && (e.key === Qt.Key_Left || e.key === Qt.Key_Right)) return;
    }

    // ── The keyboard cursor (APP-276) ────────────────────────────────
    // j / k walk the day's meetings and tasks, h / l the day before / after
    // (as [ ] do); the task keys act on the task under it. Held by key, so
    // a move or a sync leaves it on the same thing, or on its neighbour.
    property bool cursorVisible: false
    property string cursorKey: ""
    property int _cursorIdx: 0
    readonly property bool cardMenuOpen: menuHost.menuOpen
    function _rowKey(r) {
        if (!r || !r.block) return "";
        return (r.kind === "task" ? "task:" : "event:") + r.block.id;
    }
    function _items() {
        const out = [];
        for (let i = 0; i < root.rows.length; i++) {
            const r = root.rows[i];
            if (r.kind !== "meeting" && r.kind !== "task" && r.kind !== "allday") continue;
            out.push({ kind: r.kind === "task" ? "task" : "event", id: r.block.id, key: root._rowKey(r), row: i, block: r.block });
        }
        return out;
    }
    function _cursorIndex() {
        const items = root._items();
        for (let i = 0; i < items.length; i++)
            if (items[i].key === root.cursorKey) return i;
        return -1;
    }
    function _cursorItem() {
        if (!root.cursorVisible || root.cursorKey === "") return null;
        const items = root._items();
        for (let i = 0; i < items.length; i++)
            if (items[i].key === root.cursorKey) return items[i];
        return null;
    }
    readonly property string cursorTaskId: {
        const it = root._cursorItem();
        return it && it.kind === "task" ? it.id : "";
    }
    function clearCursor() {
        root.cursorVisible = false;
        root.cursorKey = "";
    }
    function _placeIdx(i) {
        root.cursorVisible = true;
        const items = root._items();
        if (items.length === 0) {
            root.cursorKey = "";
            root._cursorIdx = 0;
            return;
        }
        const at = Math.max(0, Math.min(items.length - 1, i));
        root.cursorKey = items[at].key;
        root._cursorIdx = at;
        dayList.positionViewAtIndex(items[at].row, ListView.Contain);
        if (items[at].kind === "task") AppController.markTaskSeen(items[at].id);
    }
    function moveCursor(dx, dy) {
        if (dx !== 0) {
            root._step(dx);
            Qt.callLater(root._placeIdx, 0);
            return;
        }
        const at = root._cursorIndex();
        if (!root.cursorVisible || at < 0) { root._placeIdx(at < 0 && root.cursorVisible ? root._cursorIdx : 0); return; }
        root._placeIdx(at + dy);
    }
    function _reconcile() {
        if (root.cursorVisible && root.cursorKey !== "" && root._cursorIndex() < 0) root._placeIdx(root._cursorIdx);
    }
    onRowsChanged: if (root.cursorVisible) Qt.callLater(root._reconcile)
    function _actionCardId() {
        const it = root._cursorItem();
        if (it) return it.kind === "task" ? it.id : "";
        if (AppController.selectionCount === 1) return AppController.selectedTaskIds[0];
        return "";
    }
    function openCursor() {
        const it = root._cursorItem();
        if (!it) { root.moveCursor(0, 0); return; }
        if (it.kind === "task") root.taskClicked(it.id);
        else root.eventClicked(it.id, null);
    }
    function toggleCursorSelection() {
        const it = root._cursorItem();
        if (it && it.kind === "task") AppController.toggleTaskSelection(it.id);
        else if (!it) root.moveCursor(0, 0);
    }
    function openCursorMenu() {
        const id = root._actionCardId();
        if (!id) return;
        menuHost.taskId = id;
        menuHost.releaseMenu();
        menuHost.popup();
    }
    // Shift H / L: the task a day earlier / later (the cursor follows);
    // Shift J / K: a grid step; Ctrl Shift J / K: its block longer / shorter.
    function moveSelectionOrCard(dx) {
        const it = root._cursorItem();
        if (!it || it.kind !== "task") return;
        const t = AppController.taskById(it.id);
        if (!t || !t.id) return;
        const r = Resched.shiftByDays(t.scheduledAt, t.scheduledHasTime, dx, root.day, AppController.today);
        if (AppController.rescheduleTask(it.id, "scheduled", r.when, r.timed)) root._step(dx);
    }
    function moveCursorCard(dx, dy) {
        const it = root._cursorItem();
        if (!it || it.kind !== "task" || dy === 0) return;
        const t = AppController.taskById(it.id);
        const r = t ? Resched.shiftByTime(t.scheduledAt, t.scheduledHasTime, dy, Theme.snapMinutes) : null;
        if (r) AppController.rescheduleTask(it.id, "scheduled", r.when, true);
    }
    function resizeCursor(steps) {
        const it = root._cursorItem();
        if (!it || it.kind !== "task" || it.block.fromPrevDay || it.block.toNextDay) return false;
        const step = Theme.snapMinutes / 60;
        const end = Math.min(24, it.block.end + steps * step);
        if (end - it.block.start < step - 1e-9) return false;
        return AppController.resizeTaskBlock(it.id, root.day, it.block.start, end);
    }
    TaskMenuHost {
        id: menuHost
        anchorItem: root
        onOpenRequested: root.taskClicked(menuHost.taskId)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.sp3xl
        anchors.rightMargin: Theme.sp3xl
        anchors.topMargin: Theme.sp2xl
        spacing: Theme.sp3xl

        // ── the day ──
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spXs

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spMd
                Text {
                    objectName: "today-label"
                    text: root.isToday ? I18n.t("sidebar.today")
                         : root.dayData.workday === false ? I18n.t("today.dayOff") : I18n.fmtDate(root.day, "longWeekday")
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                }
                Text {
                    objectName: "today-dayoff"
                    visible: root.isToday && root.dayData.workday === false
                    text: "· " + I18n.t("today.dayOff")
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                }
                Item { Layout.fillWidth: true }
                Text {
                    objectName: "today-back"
                    visible: !root.isToday
                    text: I18n.t("today.backToToday")
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                    font.underline: backCA.hovered
                    ClickArea { id: backCA; label: parent.text; shortcutId: "cal.today"; onActivated: AppController.selectedDate = AppController.today }
                }
                NavBtn { objectName: "today-prev"; glyph: "‹"; label: I18n.t("today.prevDay"); shortcutId: "cal.prevDay"; onActivated: root._step(-1) }
                NavBtn { objectName: "today-next"; glyph: "›"; label: I18n.t("today.nextDay"); shortcutId: "cal.nextDay"; onActivated: root._step(1) }
            }
            Text {
                objectName: "today-date"
                text: {
                    const s = I18n.fmtDate(root.day, "longWeekday");
                    return s.charAt(0).toUpperCase() + s.slice(1);
                }
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.fs2xl
                font.weight: Theme.fwHeading
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }
            // Only the parts that are not zero; nothing at all says so.
            Text {
                objectName: "today-facts"
                visible: !root.firstRun
                Layout.fillWidth: true
                text: root._facts().length > 0 ? root._facts() : I18n.t("today.nothing")
                color: Style.factsLine ? Theme.textMuted : Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsMd
                wrapMode: Text.WordWrap
            }
            // The load of the day (APP-247): facts, no advice.
            Text {
                objectName: "today-load"
                Layout.fillWidth: true
                Layout.bottomMargin: Theme.spXl
                readonly property var l: root.dayData.load || {}
                visible: !root.firstRun && root.dayData.workday === true && (l.meetings > 0 || l.tasks > 0)
                text: {
                    const parts = [];
                    if (l.meetings > 0) parts.push(I18n.t("load.meetings").arg(I18n.fmtMinutes(l.meetings)));
                    if (l.tasks > 0) parts.push(I18n.t("load.tasks").arg(I18n.fmtMinutes(l.tasks)));
                    parts.push(I18n.t("load.free").arg(I18n.fmtMinutes(l.free || 0)));
                    if (l.overWork > 0) parts.push(I18n.t("load.over").arg(I18n.fmtMinutes(l.overWork)));
                    return parts.join(" · ");
                }
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsSm
            }

            FirstRunHero {
                id: firstRunHero
                visible: root.firstRun
                Layout.fillWidth: true
                Layout.topMargin: Theme.sp3xl * 2
                onCreated: (id) => root.firstTaskCreated(id)
                onConnectRequested: root.connectRequested()
                onImportRequested: root.importRequested()
                onExampleRequested: root.exampleRequested()
            }
            Item { visible: root.firstRun; Layout.fillHeight: true }

            SectionHeader { visible: !root.firstRun; title: I18n.t("today.day") }

            ListView {
                id: dayList
                objectName: "today-day"
                visible: !root.firstRun
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: Theme.spSm
                clip: true
                spacing: Theme.spSm
                boundsBehavior: Flickable.StopAtBounds
                model: root.rows
                QQC.ScrollBar.vertical: ThinScrollBar {}
                delegate: DayRow {}
                // Opened, it shows "now", not 09:00.
                onCountChanged: Qt.callLater(root._revealNow)
                Text {
                    objectName: "today-empty"
                    visible: dayList.count === 0 || (root.dayData.blocks && root.dayData.blocks.length === 0 && (root.dayData.allDay || []).length === 0)
                    anchors.top: parent.top
                    anchors.topMargin: Theme.spSm
                    text: I18n.t("today.dayEmpty")
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsMd
                    z: -1
                }
            }
        }

        // ── the side ──
        Flickable {
            objectName: "today-side"
            visible: !root.firstRun
            Layout.preferredWidth: Math.min(Theme.px(470), root.width * 0.38)
            Layout.fillHeight: true
            contentHeight: side.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: side
                width: parent.width
                spacing: Theme.sp2xl

                // In progress; hidden when nothing is.
                ColumnLayout {
                    objectName: "today-inprogress"
                    Layout.fillWidth: true
                    visible: (root.dayData.inProgress || []).length > 0
                    spacing: Theme.spSm
                    SectionHeader { title: I18n.t("today.inProgress") }
                    Repeater {
                        model: root.dayData.inProgress || []
                        delegate: Rectangle {
                            id: ip
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: ipCol.implicitHeight + 2 * Theme.spLg
                            radius: Theme.radiusLg
                            color: Style.chipFill ? Theme.surfaceCard : "transparent"
                            border.color: Theme.border
                            border.width: Style.chipFill ? 0 : 1
                            ColumnLayout {
                                id: ipCol
                                anchors.fill: parent
                                anchors.margins: Theme.spLg
                                spacing: Theme.spXs
                                RowLayout {
                                    spacing: Theme.spMd
                                    StatusRing { category: ip.modelData.category }
                                    Text {
                                        Layout.fillWidth: true
                                        text: ip.modelData.title
                                        elide: Text.ElideRight
                                        color: Theme.text
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.fsMd
                                        font.weight: Theme.fwTitle
                                    }
                                }
                                RowLayout {
                                    spacing: Theme.spMd
                                    Text { text: ip.modelData.id; color: Theme.textDim; font.family: Theme.fontMono; font.pixelSize: Theme.fsXs }
                                    Text {
                                        visible: String(ip.modelData.branch || "").length > 0
                                        text: "⎇ " + ip.modelData.branch
                                        color: Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fsXs
                                    }
                                    Text {
                                        readonly property var pr: ip.modelData.repo && ip.modelData.repo.pr ? ip.modelData.repo.pr : null
                                        visible: !!pr && pr.number > 0
                                        text: pr ? "PR #" + pr.number + (pr.checks === "passing" ? " · CI ✓" : pr.checks === "failing" ? " · CI ✗" : "") : ""
                                        color: Theme.text
                                        font.family: Theme.fontUi
                                        font.pixelSize: Theme.fsXs
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        objectName: "today-timer"
                                        visible: !!ip.modelData.isTiming
                                        text: {
                                            const s = root._rev >= 0 ? AppController.elapsedSecondsFor(ip.modelData.id) : 0;
                                            const m = Math.floor(s / 60);
                                            return "● " + Math.floor(m / 60) + ":" + String(m % 60).padStart(2, "0");
                                        }
                                        color: Theme.signalNow
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fsSm
                                    }
                                }
                            }
                            ClickArea { label: ip.modelData.title; onActivated: root.taskClicked(ip.modelData.id) }
                        }
                    }
                }

                // Deadlines today / tomorrow; overdue apart, never in red.
                ColumnLayout {
                    objectName: "today-deadlines"
                    Layout.fillWidth: true
                    visible: (root.dayData.deadlines || []).length > 0 || (root.dayData.overdue || []).length > 0
                    spacing: Theme.spSm
                    SectionHeader { title: I18n.t("today.deadlines") }
                    Repeater {
                        model: root.dayData.deadlines || []
                        delegate: TaskLine {
                            required property var modelData
                            task: modelData
                            sub: modelData.id + (modelData.category === "blocked" ? " · " + I18n.t("today.blocked") : "")
                                 + (modelData.profileName ? " · " + modelData.profileName : "")
                            when: modelData.tomorrow ? I18n.t("quick.day.tomorrow") : I18n.t("quick.day.today")
                            whenSignal: !modelData.tomorrow
                        }
                    }
                    Text {
                        objectName: "today-overdue"
                        visible: (root.dayData.overdue || []).length > 0
                        text: Style.urgency ? I18n.count((root.dayData.overdue || []).length, "today.n.overdue")
                                            : I18n.t("today.overdueQuiet").arg((root.dayData.overdue || []).length)
                        color: Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsSm
                        font.underline: odCA.hovered
                        ClickArea { id: odCA; label: parent.text; onActivated: root.undatedRequested() }
                    }
                }

                // Whom to write; hidden when nobody. Folded in the quiet style.
                ColumnLayout {
                    objectName: "today-people"
                    Layout.fillWidth: true
                    visible: (root.dayData.people || []).length > 0
                    spacing: Theme.spSm
                    property bool open: Style.todayExtras === "open"
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: peopleHead.implicitHeight
                        SectionHeader {
                            id: peopleHead
                            width: parent.width
                            title: I18n.t("today.people") + (peopleBox.open ? "" : " · " + (root.dayData.people || []).length)
                        }
                        ClickArea {
                            label: I18n.t("today.people")
                            onActivated: peopleBox.open = !peopleBox.open
                        }
                    }
                    id: peopleBox
                    Repeater {
                        model: peopleBox.open ? (root.dayData.people || []) : []
                        delegate: RowLayout {
                            id: pr
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Theme.spMd
                            Rectangle {
                                implicitWidth: Theme.chipH; implicitHeight: Theme.chipH
                                radius: width / 2
                                color: Theme.panel3
                                Text {
                                    anchors.centerIn: parent
                                    text: String(pr.modelData.name).split(/\s+/).map(w => w.charAt(0)).join("").slice(0, 2).toUpperCase()
                                    color: Theme.text
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.fsXs
                                    font.weight: Theme.fwTitle
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: "<b>" + pr.modelData.name + "</b>" + (pr.modelData.question ? " — " + pr.modelData.question : "")
                                textFormat: Text.StyledText
                                elide: Text.ElideRight
                                color: Theme.textMuted
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fsSm
                            }
                            PillButton {
                                objectName: "today-wrote"
                                text: I18n.t("today.wrote")
                                onClicked: AppController.setPersonState(pr.modelData.id, "pinged")
                            }
                        }
                    }
                }

                // Tasks without a date: a fact and a way there.
                Text {
                    objectName: "today-undated"
                    Layout.fillWidth: true
                    visible: (root.dayData.undated || 0) > 0
                    text: I18n.count(root.dayData.undated || 0, "today.n.undated") + "  →"
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                    font.underline: undCA.hovered
                    ClickArea { id: undCA; label: parent.text; onActivated: root.undatedRequested() }
                }

                // The week's recap, on its last working day (APP-211).
                Text {
                    objectName: "today-recap"
                    Layout.fillWidth: true
                    visible: root.dayData.recapDay === true
                    text: I18n.t("today.recap") + "  →"
                    color: Theme.textMuted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsSm
                    font.underline: recapCA.hovered
                    ClickArea { id: recapCA; label: parent.text; onActivated: root.recapRequested() }
                }
                Item { Layout.fillHeight: true }
            }
        }
    }

    function _step(n) {
        const d = root.day;
        AppController.selectedDate = new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
    }
    function _revealNow() {
        for (let i = 0; i < root.rows.length; i++) {
            if (root.rows[i].kind === "now") { dayList.positionViewAtIndex(i, ListView.Center); return; }
        }
    }

    component NavBtn: Rectangle {
        id: nb
        property string glyph: ""
        property string label: ""
        property string shortcutId: ""
        signal activated()
        implicitWidth: Theme.chipH; implicitHeight: Theme.chipH
        radius: Theme.radiusMd
        color: nbCA.hovered ? Theme.panel2 : "transparent"
        border.color: Theme.border
        border.width: 1
        Text { anchors.centerIn: parent; text: nb.glyph; color: Theme.text; font.pixelSize: Theme.fsLg }
        ClickArea { id: nbCA; label: nb.label; shortcutId: nb.shortcutId; onActivated: nb.activated() }
    }

    // A task line on the side: its status mark (a click = Done), title,
    // the facts under it, when on the right.
    component TaskLine: RowLayout {
        id: tl
        property var task: ({})
        property string sub: ""
        property string when: ""
        property bool whenSignal: false
        Layout.fillWidth: true
        spacing: Theme.spMd
        Item {
            implicitWidth: Theme.statusRingSize; implicitHeight: Theme.statusRingSize
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: Theme.spXs
            StatusRing { category: tl.task.category || "todo" }
            ClickArea { label: I18n.t("taskmenu.done"); shortcutId: "task.done"; onActivated: AppController.toggleDone([tl.task.id]) }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                Layout.fillWidth: true
                text: tl.task.title || ""
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsMd
                font.weight: Theme.fwTitle
                ClickArea { label: parent.text; onActivated: root.taskClicked(tl.task.id) }
            }
            Text {
                text: tl.sub
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
            }
        }
        Text {
            Layout.alignment: Qt.AlignTop
            text: tl.when
            color: tl.whenSignal ? Theme.signalUrgent : Theme.signalNow
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
            font.weight: Theme.fwTitle
        }
    }

    // One row of the day.
    component DayRow: Item {
        id: dr
        required property var modelData
        required property int index
        width: ListView.view.width
        implicitHeight: dr.modelData.kind === "meeting" || dr.modelData.kind === "task" || dr.modelData.kind === "allday"
                        ? Math.max(Theme.px(48), body.implicitHeight + 2 * Theme.spMd)
                        : Theme.px(24)
        readonly property var b: dr.modelData.block || ({})
        opacity: dr.b.past ? 0.55 : 1

        Text {
            id: timeT
            width: Theme.px(56)
            anchors.top: parent.top
            anchors.topMargin: dr.modelData.kind === "meeting" || dr.modelData.kind === "task" ? Theme.spMd : 0
            text: dr.modelData.kind === "allday" ? I18n.t("today.allDay")
                : dr.b.fromPrevDay ? I18n.t("today.fromPrev")
                : root._hm(dr.modelData.start)
            color: dr.modelData.kind === "now" ? Theme.signalNow : Theme.textDim
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsXs
        }
        // Meetings and tasks.
        Rectangle {
            id: blockBox
            visible: dr.modelData.kind === "meeting" || dr.modelData.kind === "task" || dr.modelData.kind === "allday"
            anchors.left: timeT.right
            anchors.leftMargin: Theme.spMd
            anchors.right: parent.right
            height: parent.height
            radius: Theme.radiusLg
            readonly property bool meeting: dr.modelData.kind !== "task"
            color: blockBox.meeting ? (Style.chipFill ? Theme.meetingFill : "transparent") : "transparent"
            border.color: blockBox.meeting ? (Style.chipFill ? "transparent" : Theme.border) : Theme.border
            border.width: 1
            Rectangle {
                visible: blockBox.meeting
                anchors.left: parent.left; anchors.leftMargin: Theme.spMd
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.cursorBarH; height: parent.height - 2 * Theme.spMd
                radius: width / 2
                color: Theme.meeting
            }
            RowLayout {
                id: body
                anchors.left: parent.left
                anchors.leftMargin: blockBox.meeting ? Theme.spXl + Theme.spMd : Theme.spLg
                anchors.right: parent.right
                anchors.rightMargin: Theme.spLg
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spMd
                Item {
                    visible: !blockBox.meeting
                    implicitWidth: Theme.statusRingSize; implicitHeight: Theme.statusRingSize
                    StatusRing { category: dr.b.category || "todo" }
                    ClickArea { label: I18n.t("taskmenu.done"); onActivated: AppController.toggleDone([dr.b.id]) }
                }
                MeetingIcon { visible: blockBox.meeting && !Style.chipFill }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        Layout.fillWidth: true
                        text: dr.b.title || ""
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsMd
                        font.weight: Theme.fwTitle
                    }
                    Text {
                        Layout.fillWidth: true
                        text: {
                            const parts = [];
                            if (blockBox.meeting) parts.push(dr.b.eventType === "focus" ? I18n.t("today.withSelf") : I18n.t("event.kind.meeting"));
                            else parts.push(dr.b.id, I18n.t("today.plannedByYou"));
                            if (dr.b.attendees) parts.push(dr.b.attendees);
                            if (dr.b.profileName) parts.push(dr.b.profileName);
                            if (dr.b.toNextDay) parts.push(I18n.t("today.untilNext").arg(root._hm(dr.b.end % 24)));
                            if ((dr.b.overlapsWith || []).length > 0) parts.push(I18n.t("today.overlaps").arg(dr.b.overlapsWith.join(", ")));
                            return parts.join(" · ");
                        }
                        elide: Text.ElideRight
                        color: Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsXs
                    }
                }
                Text {
                    visible: dr.modelData.kind !== "allday"
                    text: root._len(dr.b.start || 0, dr.b.end || 0)
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsXs
                }
            }
            FocusRing {
                objectName: "today-cursor"
                visible: root.cursorVisible && root.cursorKey.length > 0 && root.cursorKey === root._rowKey(dr.modelData)
            }
            ClickArea {
                anchors.fill: undefined
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: blockBox.meeting ? 0 : Theme.spLg + Theme.statusRingSize + Theme.spMd
                label: dr.b.title || ""
                onActivated: blockBox.meeting ? root.eventClicked(dr.b.id, null) : root.taskClicked(dr.b.id)
            }
        }
        // A free window, a fact.
        Text {
            visible: dr.modelData.kind === "free"
            anchors.left: timeT.right
            anchors.leftMargin: Theme.spLg
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.t("today.free").arg(root._len(dr.modelData.start, dr.modelData.end || dr.modelData.start))
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
        }
        // Now.
        Rectangle {
            visible: dr.modelData.kind === "now"
            anchors.left: timeT.right
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Style.urgency ? 2 : 1
            color: Theme.nowLineColor
            Rectangle {
                width: Theme.spSm; height: Theme.spSm; radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.nowLineColor
            }
        }
        // The end of the working day.
        Text {
            visible: dr.modelData.kind === "end"
            anchors.left: timeT.right
            anchors.leftMargin: Theme.spLg
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.t("today.endOfDay").arg(root._hm(dr.modelData.start))
            color: Theme.textDim
            font.family: Theme.fontUi
            font.pixelSize: Theme.fsSm
        }
    }
}
