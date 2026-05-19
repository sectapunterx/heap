import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp

Item {
    id: root

    property string searchText: ""
    property var prioritiesFilter: ({})
    property var scheduleMap: ({})
    property bool showDone: false
    property bool showArchived: false

    signal taskClicked(string id)
    signal toggleShowDone()

    readonly property var bucketOrder: ["overdue", "today", "tomorrow", "thisweek", "nextweek", "later", "nodl"]
    readonly property var bucketMeta: ({
        overdue:  ({ name: "Overdue",     icon: "!", color: Theme.p0,           tone: "danger"  }),
        today:    ({ name: "Today",       icon: "●", color: Theme.accent,       tone: "today"   }),
        tomorrow: ({ name: "Tomorrow",    icon: "○", color: Theme.p1,           tone: "soon"    }),
        thisweek: ({ name: "This week",   icon: "▷", color: Theme.stProg,       tone: "normal"  }),
        nextweek: ({ name: "Next week",   icon: "›", color: Theme.textMuted,    tone: "normal"  }),
        later:    ({ name: "Later",       icon: "…", color: Theme.textDim,      tone: "normal"  }),
        nodl:     ({ name: "No deadline", icon: "—", color: Theme.textDim,      tone: "normal"  })
    })

    function passesFilter(t) {
        if (!root.showDone && t.status === "done") return false;
        const q = (root.searchText || "").toLowerCase();
        if (q && q.length > 0) {
            const hay = ((t.title || "") + " " + (t.id || "") + " " + (t.desc || "")).toLowerCase();
            if (hay.indexOf(q) < 0) return false;
        }
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
        function onDataChanged()  { root.modelRev++ }
        function onRowsInserted() { root.modelRev++ }
        function onRowsRemoved()  { root.modelRev++ }
        function onModelReset()   { root.modelRev++ }
    }

    function buildGroups() {
        const _rev = root.modelRev; // dependency
        const groups = { overdue: [], today: [], tomorrow: [], thisweek: [], nextweek: [], later: [], nodl: [] };
        const m = AppController.tasks;
        for (let i = 0; i < m.rowCount(); i++) {
            const idx = m.index(i, 0);
            const archived = m.data(idx, Qt.UserRole + 9);
            if (archived && !root.showArchived) continue;
            const t = {
                id:       m.data(idx, Qt.UserRole + 1),
                title:    m.data(idx, Qt.UserRole + 2),
                desc:     m.data(idx, Qt.UserRole + 3),
                priority: m.data(idx, Qt.UserRole + 4),
                status:   m.data(idx, Qt.UserRole + 5),
                deadline: m.data(idx, Qt.UserRole + 6),
                branch:   m.data(idx, Qt.UserRole + 7),
            };
            if (!root.passesFilter(t)) continue;
            const b = AppController.deadlineBucket(t.deadline);
            groups[b].push(t);
        }
        const priRank = { P0: 0, P1: 1, P2: 2, P3: 3 };
        for (const k in groups) {
            groups[k].sort((a, b) => {
                const ad = a.deadline && a.deadline.getTime ? a.deadline.getTime() : 9e15;
                const bd = b.deadline && b.deadline.getTime ? b.deadline.getTime() : 9e15;
                if (ad !== bd) return ad - bd;
                return (priRank[a.priority] || 9) - (priRank[b.priority] || 9);
            });
        }
        return groups;
    }
    property var groups: buildGroups()
    onModelRevChanged: groups = buildGroups()
    onSearchTextChanged: groups = buildGroups()
    onPrioritiesFilterChanged: groups = buildGroups()
    onShowDoneChanged: groups = buildGroups()
    onShowArchivedChanged: groups = buildGroups()

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
            const dl = t.deadline;
            const key = (dl && dl.getFullYear) ? (dl.getFullYear() + "-" + (dl.getMonth()+1) + "-" + dl.getDate()) : "";
            if (key !== lastKey) {
                const label = (dl && dl.getFullYear) ? AppController.shortDate(dl) : "Без даты";
                out.push({ kind: "header", label: label, date: dl });
                lastKey = key;
            }
            out.push({ kind: "task", task: t });
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
                anchors.leftMargin: 18; anchors.rightMargin: 18
                spacing: 12
                Column {
                    spacing: 1
                    Text { text: "Timeline · по дедлайнам"; color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold }
                    Text {
                        text: root.totalShown() + " task" + (root.totalShown() === 1 ? "" : "s") + " · today is " + AppController.today.toLocaleDateString(Qt.locale("en_US"), "yyyy-MM-dd")
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: 11
                    }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    radius: 999
                    color: root.showDone ? Theme.accentSoft : Theme.panel2
                    border.color: root.showDone ? Theme.accent : Theme.border
                    border.width: 1
                    implicitWidth: showDoneRow.implicitWidth + 16
                    implicitHeight: 24
                    RowLayout {
                        id: showDoneRow
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle { width: 8; height: 8; radius: 2; color: Theme.stDone }
                        Text { text: "Show done"; color: root.showDone ? Theme.accentStrong : Theme.textMuted; font.pixelSize: 12 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleShowDone()
                    }
                }
            }
        }

        // Body — scrollable list of bucket groups
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: root.width
                spacing: 0

                Repeater {
                    model: root.bucketOrder
                    delegate: Item {
                        id: groupItem
                        required property string modelData
                        readonly property string bucketId: modelData
                        readonly property var meta: root.bucketMeta[modelData]
                        readonly property var list: root.groups[modelData] || []
                        visible: list.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: visible ? (rowsCol.implicitHeight + 20) : 0
                        Layout.leftMargin: 18; Layout.rightMargin: 18; Layout.topMargin: 14

                        RowLayout {
                            anchors.fill: parent
                            spacing: 14

                            // Left side — label / marker
                            ColumnLayout {
                                Layout.preferredWidth: 160
                                Layout.alignment: Qt.AlignTop
                                spacing: 4
                                RowLayout {
                                    spacing: 8
                                    Rectangle {
                                        width: 26; height: 26; radius: 13
                                        color: groupItem.meta.color
                                        Text {
                                            anchors.centerIn: parent
                                            text: groupItem.meta.icon
                                            color: "#06121a"
                                            font.weight: Font.DemiBold
                                            font.pixelSize: 13
                                        }
                                    }
                                    Text {
                                        text: groupItem.meta.name
                                        color: groupItem.bucketId === "overdue" ? Theme.p0
                                             : groupItem.bucketId === "today" ? Theme.accentStrong
                                             : Theme.text
                                        font.pixelSize: 14
                                        font.weight: Font.DemiBold
                                    }
                                }
                                Text {
                                    visible: (groupItem.bucketId === "overdue" || groupItem.bucketId === "today" || groupItem.bucketId === "tomorrow")
                                             && groupItem.list.length > 0 && groupItem.list[0].deadline && groupItem.list[0].deadline.getTime
                                    text: groupItem.list.length > 0 && groupItem.list[0].deadline && groupItem.list[0].deadline.getTime
                                          ? AppController.shortDate(groupItem.list[0].deadline) : ""
                                    color: Theme.textMuted
                                    font.pixelSize: 11
                                    leftPadding: 34
                                }
                                Text {
                                    text: groupItem.list.length + " task" + (groupItem.list.length === 1 ? "" : "s")
                                    color: Theme.textDim
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                    leftPadding: 34
                                }
                            }

                            // Rows
                            ColumnLayout {
                                id: rowsCol
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: root.bucketRows(groupItem.bucketId, groupItem.list)
                                    delegate: Loader {
                                        required property var modelData
                                        property var rowData: modelData
                                        Layout.fillWidth: true
                                        sourceComponent: (modelData && modelData.kind === "header") ? subHeaderComp : taskRowComp
                                    }
                                }

                                Component {
                                    id: subHeaderComp
                                    RowLayout {
                                        id: hdr
                                        readonly property var rd: parent && parent.rowData ? parent.rowData : null
                                        width: parent ? parent.width : 0
                                        spacing: 8
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
                                            font.pixelSize: 11
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
                                        readonly property var rd: parent && parent.rowData ? parent.rowData : null
                                        readonly property var t: rd ? rd.task : null
                                        readonly property var st: t ? root.statusInfo(t.status) : null
                                        width: parent ? parent.width : 0
                                        radius: 8
                                        color: rowMA.containsMouse ? Theme.panel2 : Theme.panel
                                        border.color: rowMA.containsMouse ? Theme.borderStrong : Theme.border
                                        border.width: 1
                                        implicitHeight: rowContent.implicitHeight + 16

                                        // Left accent stripe
                                        Rectangle {
                                            anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                            anchors.leftMargin: 0
                                            width: 3
                                            color: groupItem.bucketId === "overdue" ? Theme.withAlpha(Theme.p0, 0.6)
                                                 : groupItem.bucketId === "today" ? Theme.accent
                                                 : groupItem.bucketId === "tomorrow" ? Theme.withAlpha(Theme.p1, 0.6)
                                                 : "transparent"
                                            radius: 1
                                        }

                                        RowLayout {
                                            id: rowContent
                                            anchors.fill: parent
                                            anchors.leftMargin: 14
                                            anchors.rightMargin: 12
                                            anchors.topMargin: 8
                                            anchors.bottomMargin: 8
                                            spacing: 10

                                            Rectangle { width: 10; height: 10; radius: 3; color: tlRow.st.color }
                                            Rectangle {
                                                radius: 4
                                                color: Theme.withAlpha(Theme.priorityColor(tlRow.t.priority), 0.14)
                                                implicitWidth: priT.implicitWidth + 10; implicitHeight: 18
                                                Text {
                                                    id: priT
                                                    anchors.centerIn: parent
                                                    text: tlRow.t.priority
                                                    color: Theme.priorityColor(tlRow.t.priority)
                                                    font.pixelSize: 10
                                                    font.weight: Font.DemiBold
                                                }
                                            }
                                            Text {
                                                text: tlRow.t.id
                                                color: Theme.accentStrong
                                                font.family: Theme.fontMono
                                                font.pixelSize: 11
                                                font.weight: Font.Medium
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: tlRow.t.title
                                                    color: Theme.text
                                                    font.pixelSize: 13
                                                    font.weight: Font.Medium
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    visible: tlRow.t.desc && String(tlRow.t.desc).length > 0
                                                    text: String(tlRow.t.desc || "").substring(0, 90) + (String(tlRow.t.desc || "").length > 90 ? "…" : "")
                                                    color: Theme.textMuted
                                                    font.pixelSize: 11
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            Rectangle {
                                                radius: 999
                                                color: "transparent"
                                                border.color: Theme.withAlpha(tlRow.st.color, 0.4)
                                                border.width: 1
                                                implicitWidth: stT.implicitWidth + 14; implicitHeight: 20
                                                Text {
                                                    id: stT
                                                    anchors.centerIn: parent
                                                    text: tlRow.st.name
                                                    color: tlRow.st.color
                                                    font.pixelSize: 10
                                                    font.weight: Font.DemiBold
                                                }
                                            }
                                            Text {
                                                visible: tlRow.t.branch && String(tlRow.t.branch).length > 0
                                                text: tlRow.t.branch ? "⎇ " + String(tlRow.t.branch).split("/").pop() : ""
                                                color: Theme.textDim
                                                font.family: Theme.fontMono
                                                font.pixelSize: 10
                                            }
                                            Rectangle {
                                                visible: root.scheduleMap[tlRow.t.id] !== undefined && String(root.scheduleMap[tlRow.t.id]).length > 0
                                                radius: 4
                                                color: Theme.accentSoft
                                                implicitWidth: schT.implicitWidth + 10; implicitHeight: 18
                                                Text {
                                                    id: schT
                                                    anchors.centerIn: parent
                                                    text: "⏰ " + (root.scheduleMap[tlRow.t.id] || "")
                                                    color: Theme.accentStrong
                                                    font.family: Theme.fontMono
                                                    font.pixelSize: 10
                                                }
                                            }
                                            Text {
                                                text: AppController.deadlineDiffLabel(tlRow.t.deadline)
                                                color: groupItem.bucketId === "overdue" ? Theme.p0
                                                     : groupItem.bucketId === "today" ? Theme.accentStrong
                                                     : groupItem.bucketId === "tomorrow" ? Theme.p1
                                                     : Theme.textMuted
                                                font.family: Theme.fontMono
                                                font.pixelSize: 11
                                                font.weight: groupItem.bucketId === "overdue" || groupItem.bucketId === "today" ? Font.DemiBold : Font.Normal
                                            }
                                        }

                                        MouseArea {
                                            id: rowMA
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.taskClicked(tlRow.t.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    visible: root.totalShown() === 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 200
                    Column {
                        anchors.centerIn: parent
                        spacing: 6
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "✓"; color: Theme.stDone; font.pixelSize: 26 }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Нет задач по фильтрам."; color: Theme.text; font.pixelSize: 13 }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Сбрось фильтры или добавь задачу."; color: Theme.textDim; font.pixelSize: 12 }
                    }
                }

                Item { Layout.fillWidth: true; Layout.preferredHeight: 24 }
            }
        }
    }
}
