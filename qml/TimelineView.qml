import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp
import "Search.js" as Search
import "PlainText.js" as MdPlain

Item {
    id: root

    property string searchText: ""
    property var prioritiesFilter: ({})
    property var scheduleMap: ({})
    property bool showDone: false
    property bool showArchived: false
    // Something is narrowing what the timeline shows.
    readonly property bool _filtering: searchText.trim().length > 0
        || Object.keys(prioritiesFilter || {}).some(function (k) { return prioritiesFilter[k] === true; })

    signal taskClicked(string id)
    signal toggleShowDone()

    // ── Keyboard (TASKS-30) ──────────────────────────────────────────
    // J/K or the arrows walk the rows, Enter opens, Space selects; "O" (the
    // app-wide open-in-tracker key) acts on the row the cursor is on.
    property string cursorTaskId: ""
    property string _hoverId: ""
    readonly property string hoveredTaskId: cursorTaskId.length > 0 ? cursorTaskId : _hoverId
    function _taskRowIndexes() {
        const out = [];
        for (let i = 0; i < root.flatRows.length; i++) if (root.flatRows[i].kind === "task") out.push(i);
        return out;
    }
    function moveCursor(dy) {
        const rows = _taskRowIndexes();
        if (rows.length === 0) return;
        let at = -1;
        for (let k = 0; k < rows.length; k++)
            if (root.flatRows[rows[k]].task.id === root.cursorTaskId) { at = k; break; }
        at = at < 0 ? 0 : Math.max(0, Math.min(rows.length - 1, at + dy));
        root.cursorTaskId = root.flatRows[rows[at]].task.id;
        rowList.positionViewAtIndex(rows[at], ListView.Contain);
    }
    function openCursor() {
        if (root.cursorTaskId) root.taskClicked(root.cursorTaskId);
        else root.moveCursor(0);
    }
    onVisibleChanged: if (visible) rowList.forceActiveFocus()
    Component.onCompleted: rowList.forceActiveFocus()

    // Selection plumbing — flat across buckets (reading order).
    property string shiftAnchorId: ""
    Connections {
        target: AppController

        function onSelectedTaskIdsChanged() {
            if (AppController.selectionCount === 0) root.shiftAnchorId = "";
        }
    }

    function _flatVisibleIds() {
        const out = [];
        for (const b of root.bucketOrder) {
            const list = root.groups[b] || [];
            for (let i = 0; i < list.length; i++) out.push(list[i].id);
        }
        return out;
    }

    function selectAllVisible() {
        AppController.setSelectedTaskIds(_flatVisibleIds());
    }

    function _rangeSelect(targetId) {
        const ordered = _flatVisibleIds();
        if (ordered.length === 0) return;
        const haveAnchor = root.shiftAnchorId && ordered.indexOf(root.shiftAnchorId) >= 0;
        if (!haveAnchor) {
            root.shiftAnchorId = targetId;
            AppController.toggleTaskSelection(targetId);
            return;
        }
        const ai = ordered.indexOf(root.shiftAnchorId);
        const ti = ordered.indexOf(targetId);
        const lo = Math.min(ai, ti);
        const hi = Math.max(ai, ti);
        const merged = AppController.selectedTaskIds.slice();
        for (let i = lo; i <= hi; i++) {
            if (merged.indexOf(ordered[i]) < 0) merged.push(ordered[i]);
        }
        AppController.setSelectedTaskIds(merged);
    }

    readonly property var bucketOrder: ["overdue", "today", "tomorrow", "thisweek", "nextweek", "later", "nodl"]
    readonly property var bucketMeta: ({
        overdue:  ({ name: I18n.t("timeline.bucket.overdue"),  icon: "!", color: Theme.danger,        tone: "danger"  }),
        today:    ({ name: I18n.t("timeline.bucket.today"),    icon: "●", color: Theme.accent,    tone: "today"   }),
        tomorrow: ({ name: I18n.t("timeline.bucket.tomorrow"), icon: "○", color: Theme.warning,        tone: "soon"    }),
        thisweek: ({ name: I18n.t("timeline.bucket.thisweek"), icon: "▷", color: Theme.stProg,    tone: "normal"  }),
        nextweek: ({ name: I18n.t("timeline.bucket.nextweek"), icon: "›", color: Theme.textMuted, tone: "normal"  }),
        later:    ({ name: I18n.t("timeline.bucket.later"),    icon: "…", color: Theme.textDim,   tone: "normal"  }),
        nodl:     ({ name: I18n.t("timeline.bucket.nodl"),     icon: "—", color: Theme.textDim,   tone: "normal"  })
    })

    function passesFilter(t) {
        if (!root.showDone && t.status === "done") return false;
        // Clauses (`status:blocked`) filter structurally, the leftover words
        // stay a substring test. Compiled once per (text, modelRev), not once
        // per row.
        if (!Search.accepts(AppController, root.searchText, root.modelRev, t)) return false;
        let anyPri = false;
        for (const k in root.prioritiesFilter) if (root.prioritiesFilter[k]) { anyPri = true; break; }
        if (anyPri && !root.prioritiesFilter[t.priority]) return false;
        return true;
    }

    function statusInfo(id) {
        const list = AppController.statuses;
        for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
        return { id: id, name: id, color: Theme.textDim };
    }

    // Snapshot tasks into a JS array grouped by bucket. We rebuild on
    // changes via the modelRev tick so QML bindings re-evaluate.
    property int modelRev: 0
    Connections {
        target: AppController.tasks
        function onDataChanged(topLeft, bottomRight) {
            root._forgetRows(topLeft.row, bottomRight.row);
            root.modelRev++;
        }
        function onRowsInserted() { root.modelRev++ }
        function onRowsRemoved()  { root.modelRev++ }
        function onModelReset()   { root._rowCache = ({}); root.modelRev++ }
    }

    // One snapshot row per task id, kept between rebuilds. A rebuild used to
    // read ten roles and ask C++ for the bucket of every task — 3k tasks,
    // ~85 ms — for every change anywhere, a single card's move included. Now
    // only the rows the model says changed are read again. Rows are keyed by
    // id, not position, so an insert or a removal leaves the rest valid; the
    // entries of removed tasks are simply never looked up again. The bucket
    // depends on today, so a new day starts a new cache.
    property var _rowCache: ({})
    property string _rowCacheDay: ""
    function _forgetRows(first, last) {
        const m = AppController.tasks;
        for (let i = first; i <= last; i++) delete root._rowCache[m.data(m.index(i, 0), Qt.UserRole + 1)];
    }
    function _rowAt(m, idx) {
        const t = {
            id:       m.data(idx, Qt.UserRole + 1),
            title:    m.data(idx, Qt.UserRole + 2),
            desc:     m.data(idx, Qt.UserRole + 3),
            priority: m.data(idx, Qt.UserRole + 4),
            status:   m.data(idx, Qt.UserRole + 5),
            deadline: m.data(idx, Qt.UserRole + 6),
            branch:   m.data(idx, Qt.UserRole + 7),
            archived: m.data(idx, Qt.UserRole + 9),
            // The one haystack passesFilter() searches (HEAP-117).
            searchText: m.data(idx, Qt.UserRole + 32),
            ticket:     m.data(idx, Qt.UserRole + 31),
            dueAt:      m.data(idx, m.roleOf("dueAt")),
            dueHasTime: !!m.data(idx, m.roleOf("dueHasTime")),
            scheduledAt: m.data(idx, m.roleOf("scheduledAt")),
            scheduledHasTime: !!m.data(idx, m.roleOf("scheduledHasTime")),
        };
        // A task with only a schedule is not "No deadline" work: it goes
        // under the day it is planned for (TASKS-12).
        const valid = (d) => d && d.getTime && !isNaN(d.getTime());
        t.scheduledOnly = !valid(t.deadline) && valid(t.scheduledAt);
        t.when = valid(t.deadline) ? t.deadline
               : (t.scheduledOnly ? new Date(t.scheduledAt.getFullYear(), t.scheduledAt.getMonth(), t.scheduledAt.getDate()) : t.deadline);
        t.bucket = AppController.deadlineBucket(t.when);
        t.dueMs = valid(t.when) ? t.when.getTime() : 9e15;
        return t;
    }

    function buildGroups() {
        const _rev = root.modelRev; // dependency
        const groups = { overdue: [], today: [], tomorrow: [], thisweek: [], nextweek: [], later: [], nodl: [] };
        const m = AppController.tasks;
        const day = String(AppController.today);
        if (root._rowCacheDay !== day) {
            root._rowCache = ({});
            root._rowCacheDay = day;
        }
        const cache = root._rowCache;
        for (let i = 0; i < m.rowCount(); i++) {
            const idx = m.index(i, 0);
            const id = m.data(idx, Qt.UserRole + 1);
            let t = cache[id];
            if (!t) {
                t = root._rowAt(m, idx);
                cache[id] = t;
            }
            if (t.archived && !root.showArchived) continue;
            if (!root.passesFilter(t)) continue;
            groups[t.bucket].push(t);
        }
        const priRank = { P0: 0, P1: 1, P2: 2, P3: 3 };
        for (const k in groups) {
            groups[k].sort((a, b) => {
                if (a.dueMs !== b.dueMs) return a.dueMs - b.dueMs;
                return (priRank[a.priority] ?? 9) - (priRank[b.priority] ?? 9);
            });
        }
        return groups;
    }
    // Rebuilt once per event-loop pass, not once per signal. One status change
    // emits several model signals (the move, its timestamp, the focus block it
    // books), and each used to rebuild the whole timeline — 3k tasks, ~100 ms a
    // pass. It was also a binding on top of the handlers, so the first change
    // rebuilt twice. A zero-interval timer folds repeated requests into one
    // (and, unlike Qt.callLater, dies with the view instead of calling into a
    // destroyed one after a view switch).
    property var groups: ({})
    function _rebuild() { root.groups = root.buildGroups(); }
    function _scheduleRebuild() { rebuildTimer.restart(); }
    Timer {
        id: rebuildTimer
        interval: 0
        onTriggered: root._rebuild()
    }
    Component.onCompleted: root._rebuild()
    onModelRevChanged: _scheduleRebuild()
    onSearchTextChanged: _scheduleRebuild()
    onPrioritiesFilterChanged: _scheduleRebuild()
    onShowDoneChanged: _scheduleRebuild()
    onShowArchivedChanged: _scheduleRebuild()

    // Expand a bucket's flat task list into a mixed array of
    // {kind:"header", label, date} / {kind:"task", task} rows. Buckets that
    // span multiple distinct dates (thisweek/nextweek/later) get one header
    // per date so the timeline reads like a sub-grouped agenda.
    function bucketRows(bucketId, list) {
        const out = [];
        const grouped = (bucketId === "thisweek" || bucketId === "nextweek" || bucketId === "later");
        if (!grouped) {
            for (let i = 0; i < list.length; i++) out.push({ kind: "task", task: list[i] });
            return out;
        }
        let lastKey = "__none__";
        for (let i = 0; i < list.length; i++) {
            const t = list[i];
            const dl = t.when;
            const key = (dl && dl.getFullYear) ? (dl.getFullYear() + "-" + (dl.getMonth()+1) + "-" + dl.getDate()) : "";
            if (key !== lastKey) {
                const label = (dl && dl.getFullYear) ? AppController.shortDate(dl) : I18n.t("timeline.noDate");
                out.push({ kind: "header", label: label, date: dl });
                lastKey = key;
            }
            out.push({ kind: "task", task: t });
        }
        return out;
    }

    // Every bucket's rows in display order, flat, for the virtualised list.
    // `first` marks the row that carries its bucket's label.
    readonly property var flatRows: {
        const out = [];
        for (const k of root.bucketOrder) {
            const list = root.groups[k] || [];
            if (list.length === 0) continue;
            const rows = root.bucketRows(k, list);
            for (let i = 0; i < rows.length; i++) {
                const r = rows[i];
                r.bucketId = k;
                r.first = i === 0;
                out.push(r);
            }
        }
        return out;
    }

    function totalShown() {
        let n = 0;
        for (const k of root.bucketOrder) n += (groups[k] || []).length;
        return n;
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Head
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 50
            color: Theme.panel
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 1; color: Theme.border
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.inset; anchors.rightMargin: Theme.inset
                spacing: Theme.spXl
                Column {
                    spacing: 1
                    Text {
                        text: I18n.t("timeline.title"); color: Theme.text; font.pixelSize: Theme.fsLg; font.weight: Font.DemiBold
                    }
                    Text {
                        text: I18n.t("timeline.subtitle")
                                .arg(I18n.tasks(root.totalShown()))
                                .arg(AppController.today.toLocaleDateString(I18n.locale, "yyyy-MM-dd"))
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsSm
                    }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    radius: Theme.radiusPill
                    color: root.showDone ? Theme.accentSoft : Theme.panel2
                    border.color: root.showDone ? Theme.accent : Theme.border
                    border.width: 1
                    implicitWidth: showDoneRow.implicitWidth + 16
                    implicitHeight: 24
                    RowLayout {
                        id: showDoneRow
                        anchors.centerIn: parent
                        spacing: Theme.spSm
                        Rectangle { width: 8; height: 8; radius: Theme.radiusXs; color: Theme.stDone }
                        Text { text: I18n.t("timeline.showDone"); color: root.showDone ? Theme.accentStrong : Theme.textMuted; font.pixelSize: Theme.fsMd }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleShowDone()
                    }
                }
            }
        }

        // Body — one virtualised list of rows. Buckets used to be a Repeater of
        // Repeaters inside a ScrollView, which built every card up front: 2000
        // tasks cost 1.24 GB. A ListView only builds what is on screen. The
        // bucket label sits beside the first row of its bucket, as before.
        ListView {
            id: rowList
            objectName: "timeline-rows"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ThinScrollBar {}
            // A row count, not the array. Every rebuild makes a new array, and
            // an array model is reset whenever it is replaced: all rows torn
            // down and laid out again for a single card's move. With a count
            // the list stays put while it is unchanged, and each row on screen
            // just re-reads its entry below.
            model: root.flatRows.length
            cacheBuffer: 400
            reuseItems: true
            focus: true
            activeFocusOnTab: true
            Keys.onPressed: (e) => {
                if (e.modifiers & (Qt.ControlModifier | Qt.AltModifier)) return;
                if (e.key === Qt.Key_J || e.key === Qt.Key_Down) { root.moveCursor(1); e.accepted = true; }
                else if (e.key === Qt.Key_K || e.key === Qt.Key_Up) { root.moveCursor(-1); e.accepted = true; }
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.openCursor(); e.accepted = true; }
                else if (e.key === Qt.Key_Space && root.cursorTaskId) {
                    AppController.toggleTaskSelection(root.cursorTaskId); e.accepted = true;
                }
            }
            footer: Item { width: rowList.width; height: 24 }

            delegate: Item {
                id: rowItem
                required property int index
                readonly property var rd: root.flatRows[index] ?? null
                readonly property bool first: !!(rd && rd.first)
                readonly property var meta: rd ? root.bucketMeta[rd.bucketId] : null
                readonly property var list: rd ? (root.groups[rd.bucketId] || []) : []
                width: rowList.width
                height: Math.max(first ? labelCol.implicitHeight : 0, rowLoader.item ? rowLoader.item.implicitHeight : 0)
                        + (first ? 14 : 0) + 6

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.inset; anchors.rightMargin: Theme.inset
                    anchors.topMargin: rowItem.first ? 14 : 0
                    anchors.bottomMargin: Theme.spSm
                    spacing: Theme.sp2xl

                    // Left side — label / marker, on the bucket's first row only
                    ColumnLayout {
                        id: labelCol
                        Layout.preferredWidth: 160
                        Layout.alignment: Qt.AlignTop
                        spacing: Theme.spXs
                        opacity: rowItem.first ? 1 : 0
                        RowLayout {
                            spacing: Theme.spMd
                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: rowItem.meta ? rowItem.meta.color : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: rowItem.meta ? rowItem.meta.icon : ""
                                    color: Theme.textOnAccent
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Theme.fsMd
                                }
                            }
                            Text {
                                text: rowItem.meta ? rowItem.meta.name : ""
                                color: rowItem.rd.bucketId === "overdue" ? Theme.danger
                                     : rowItem.rd.bucketId === "today" ? Theme.accentStrong
                                     : Theme.text
                                font.pixelSize: Theme.fsLg
                                font.weight: Font.DemiBold
                            }
                        }
                        Text {
                            visible: rowItem.first
                                     && (rowItem.rd.bucketId === "overdue" || rowItem.rd.bucketId === "today" || rowItem.rd.bucketId === "tomorrow")
                                     && rowItem.list.length > 0 && rowItem.list[0].when && rowItem.list[0].when.getTime
                            text: rowItem.list.length > 0 && rowItem.list[0].when && rowItem.list[0].when.getTime
                                  ? I18n.relang(AppController.shortDate(rowItem.list[0].when)) : ""
                            color: Theme.textMuted
                            font.pixelSize: Theme.fsSm
                            leftPadding: 34
                        }
                        Text {
                            visible: rowItem.first
                            text: I18n.tasks(rowItem.list.length)
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsSm
                            leftPadding: 34
                        }
                    }

                    Loader {
                        id: rowLoader
                        property var rowData: rowItem.rd
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        sourceComponent: (rowItem.rd && rowItem.rd.kind === "header") ? subHeaderComp : taskRowComp
                    }
                }
            }

            Item {
                visible: root.totalShown() === 0
                anchors.left: parent.left; anchors.right: parent.right
                anchors.top: parent.top; anchors.topMargin: Theme.sp2xl
                height: 200
                Column {
                    anchors.centerIn: parent
                    spacing: Theme.spSm
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "✓"; color: Theme.stDone; font.pixelSize: Theme.fs2xl }
                    // "No tasks match the filters" only when something is
                    // filtering; an empty timeline is not a filter's fault.
                    Text {
                        objectName: "timeline-empty-title"
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.t(root._filtering ? "timeline.empty.title" : "timeline.empty.none.title")
                        color: Theme.text; font.pixelSize: Theme.fsMd
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: I18n.t(root._filtering ? "timeline.empty.hint" : "timeline.empty.none.hint")
                        color: Theme.textDim; font.pixelSize: Theme.fsMd
                    }
                }
            }
        }
    }

            Component {
                id: subHeaderComp
                RowLayout {
                    id: hdr
                    readonly property var rd: parent && parent.rowData ? parent.rowData : null
                    width: parent ? parent.width : 0
                    spacing: Theme.spMd
                    Rectangle {
                        Layout.preferredWidth: 3
                        Layout.preferredHeight: 12
                        radius: 1
                        color: Theme.border
                    }
                    Text {
                        text: hdr.rd ? hdr.rd.label : ""
                        color: Theme.textMuted
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsSm
                        font.weight: Font.DemiBold
                        font.capitalization: Font.MixedCase
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Theme.border
                        opacity: 0.4
                    }
                }
            }

            Component {
                id: taskRowComp
                Rectangle {
                    id: tlRow
                    objectName: "tl-row"
                    readonly property var rd: parent && parent.rowData ? parent.rowData : null
                    readonly property var t: rd ? rd.task : null
                    readonly property var st: t ? root.statusInfo(t.status) : null
                    readonly property bool _selected: t && AppController.selectionCount >= 0
                        && AppController.isTaskSelected(t.id)
                    readonly property bool _cursored: !!t && root.cursorTaskId === t.id
                    width: parent ? parent.width : 0
                    radius: Theme.radius
                    color: _selected ? Theme.withAlpha(Theme.accent, 0.10)
                        : rowMA.containsMouse ? Theme.panel2 : Theme.panel
                    border.color: _selected ? Theme.accent
                        : _cursored ? Theme.accentStrong
                        : rowMA.containsMouse ? Theme.borderStrong : Theme.border
                    border.width: _selected || _cursored ? 2 : 1
                    implicitHeight: rowContent.implicitHeight + 16

                    // Left accent stripe
                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        anchors.leftMargin: 0
                        width: 3
                        color: (tlRow.rd ? tlRow.rd.bucketId : "") === "overdue" ? Theme.withAlpha(Theme.danger, 0.6)
                             : (tlRow.rd ? tlRow.rd.bucketId : "") === "today" ? Theme.accent
                             : (tlRow.rd ? tlRow.rd.bucketId : "") === "tomorrow" ? Theme.withAlpha(Theme.warning, 0.6)
                             : "transparent"
                        radius: 1
                    }

                    RowLayout {
                        id: rowContent
                        anchors.fill: parent
                        anchors.leftMargin: Theme.sp2xl
                        anchors.rightMargin: Theme.spXl
                        anchors.topMargin: Theme.spMd
                        anchors.bottomMargin: Theme.spMd
                        spacing: Theme.spLg

                        Rectangle { width: 10; height: 10; radius: Theme.radiusXs; color: tlRow.st.color }
                        Rectangle {
                            radius: Theme.radiusSm
                            color: Theme.withAlpha(Theme.priorityColor(tlRow.t.priority), 0.14)
                            implicitWidth: priT.implicitWidth + 10; implicitHeight: 18
                            Text {
                                id: priT
                                anchors.centerIn: parent
                                text: tlRow.t.priority
                                color: Theme.priorityColor(tlRow.t.priority)
                                font.pixelSize: Theme.fsXs
                                font.weight: Font.DemiBold
                            }
                        }
                        Text {
                            // A mirrored issue reads by its
                            // tracker key (HEAP-117).
                            text: (tlRow.t.ticket && tlRow.t.ticket.key)
                                  ? tlRow.t.ticket.key : tlRow.t.id
                            textFormat: Text.PlainText
                            color: Theme.accentStrong
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsSm
                            font.weight: Font.Medium
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                text: tlRow.t.title
                                textFormat: Text.PlainText
                                color: Theme.text
                                font.pixelSize: Theme.fsMd
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: tlRow.t.desc && String(tlRow.t.desc).length > 0
                                // Markdown read as prose, not as "**Steps:** - [ ]".
                                text: MdPlain.plain(tlRow.t.desc, 120)
                                color: Theme.textMuted
                                font.pixelSize: Theme.fsSm
                                elide: Text.ElideRight
                            }
                        }
                        Rectangle {
                            radius: Theme.radiusPill
                            color: "transparent"
                            border.color: Theme.withAlpha(tlRow.st.color, 0.4)
                            border.width: 1
                            implicitWidth: stT.implicitWidth + 14; implicitHeight: 20
                            Text {
                                id: stT
                                anchors.centerIn: parent
                                text: tlRow.st.name
                                color: tlRow.st.color
                                font.pixelSize: Theme.fsXs
                                font.weight: Font.DemiBold
                            }
                        }
                        Text {
                            visible: tlRow.t.branch && String(tlRow.t.branch).length > 0
                            text: tlRow.t.branch ? "⎇ " + String(tlRow.t.branch).split("/").pop() : ""
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsXs
                        }
                        Rectangle {
                            visible: root.scheduleMap[tlRow.t.id] !== undefined && String(root.scheduleMap[tlRow.t.id]).length > 0
                            radius: Theme.radiusSm
                            color: Theme.accentSoft
                            implicitWidth: schT.implicitWidth + 10; implicitHeight: 18
                            Text {
                                id: schT
                                anchors.centerIn: parent
                                text: "▸ " + (root.scheduleMap[tlRow.t.id] || "")
                                color: Theme.accentStrong
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fsXs
                            }
                        }
                        // The clock time of a timed deadline, and the day of a
                        // task that only has a schedule.
                        Text {
                            objectName: "tl-when"
                            readonly property var at: tlRow.t.scheduledOnly ? tlRow.t.scheduledAt : tlRow.t.dueAt
                            readonly property bool timed: tlRow.t.scheduledOnly ? tlRow.t.scheduledHasTime : tlRow.t.dueHasTime
                            visible: text.length > 0
                            text: (tlRow.t.scheduledOnly ? "▸ " : "")
                                  + (timed && at && at.getHours
                                     ? String(at.getHours()).padStart(2, "0") + ":" + String(at.getMinutes()).padStart(2, "0")
                                     : "")
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsSm
                        }
                        Text {
                            text: I18n.relang(AppController.deadlineDiffLabel(tlRow.t.when))
                            color: (tlRow.rd ? tlRow.rd.bucketId : "") === "overdue" ? Theme.danger
                                 : (tlRow.rd ? tlRow.rd.bucketId : "") === "today" ? Theme.accentStrong
                                 : (tlRow.rd ? tlRow.rd.bucketId : "") === "tomorrow" ? Theme.warning
                                 : Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsSm
                            font.weight: (tlRow.rd ? tlRow.rd.bucketId : "") === "overdue" || (tlRow.rd ? tlRow.rd.bucketId : "") === "today" ? Font.DemiBold : Font.Normal
                        }
                    }

                    MouseArea {
                        id: rowMA
                        anchors.fill: parent
                        hoverEnabled: true
                        onContainsMouseChanged: {
                            if (containsMouse) root._hoverId = tlRow.t.id;
                            else if (root._hoverId === tlRow.t.id) root._hoverId = "";
                        }
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton
                        onClicked: (mouse) => {
                            const ctrl = (mouse.modifiers & Qt.ControlModifier) !== 0;
                            const shift = (mouse.modifiers & Qt.ShiftModifier) !== 0;
                            if (ctrl) {
                                AppController.toggleTaskSelection(tlRow.t.id);
                            } else if (shift) {
                                root._rangeSelect(tlRow.t.id);
                            } else {
                                if (AppController.selectionCount > 0) AppController.clearSelection();
                                root.cursorTaskId = tlRow.t.id;
                                root.taskClicked(tlRow.t.id);
                            }
                            rowList.forceActiveFocus();
                        }
                    }
                }
            }
}
