pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp
import "KeyRules.js" as KeyRules

// The keyboard cheat sheet (APP-272, sheet X-Keys / N-Keys): "?" or Ctrl+/
// anywhere. Every key of the catalogue by area, in columns, with a search
// by action or by key; read only — "Change shortcuts…" opens the panel that
// rebinds. The keys come from the one catalogue (AppController.shortcuts),
// so a rebinding changes them here, in the menus and in the hints alike.
Popup {
    id: root
    objectName: "key-cheat-sheet"
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    anchors.centerIn: Overlay.overlay
    width: Math.min(Overlay.overlay ? Overlay.overlay.width - 2 * Theme.sp2xl : 1240, 1240)
    height: Math.min(Overlay.overlay ? Overlay.overlay.height - 2 * Theme.spXl : 960, 960)
    padding: 0
    Overlay.modal: ModalScrim {}
    background: ModalSurface {}

    // "Change shortcuts…": Main opens the rebinding panel.
    signal editRequested()

    property alias query: search.text

    // The sheet's areas and rows. A row names its catalogue ids; its keys are
    // read from the catalogue each time. `label` is an I18n key; without one
    // the row is called what the catalogue calls its first id. `range` writes
    // a run of keys as "1…4".
    // The sheet's areas and rows, in X-Keys order. `col` is the column the
    // area stands in (four columns, read top to bottom).
    readonly property var groups: [
        { id: "move", col: 0, rows: [
            { label: "keys.row.upDown", ids: ["board.cursorDown", "board.cursorUp"] },
            { label: "keys.row.leftRight", ids: ["board.cursorLeft", "board.cursorRight"] },
            { label: "keys.row.firstLast", ids: ["cursor.first", "cursor.last"] },
            { label: "keys.row.halfPage", ids: ["cursor.pageDown", "cursor.pageUp"] },
            { label: "keys.row.period", ids: ["cal.prev", "cal.next"] },
            { label: "keys.row.today", ids: ["cal.today"] },
            { label: "keys.row.jumps", ids: ["nav.back", "nav.forward"] },
            { label: "keys.row.regionNext", ids: ["region.next"] }
        ] },
        { id: "go", col: 1, rows: [
            { label: "keys.row.goToday", ids: ["section.today.alt", "section.today"] },
            { label: "keys.row.goBoard", ids: ["view.board"] },
            { label: "keys.row.goList", ids: ["view.timeline"] },
            { label: "keys.row.goCalendar", ids: ["view.calendar"] },
            { label: "keys.row.goKnowledge", ids: ["section.knowledge.alt", "section.knowledge"] },
            { label: "keys.row.goView", range: true, ids: ["savedView.1.alt", "savedView.2.alt", "savedView.3.alt",
                "savedView.4.alt", "savedView.5.alt", "savedView.6.alt", "savedView.7.alt", "savedView.8.alt",
                "savedView.9.alt"] },
            { label: "keys.row.goTracker", ids: ["task.openExternal"] }
        ] },
        { id: "task", col: 2, rows: [
            { label: "keys.row.open", ids: ["board.open"] },
            { label: "keys.row.done", note: "keys.row.done.note", ids: ["task.done"] },
            { label: "keys.row.newBelowAbove", ids: ["task.newBelow", "task.newAbove"] },
            { label: "keys.row.rename", ids: ["task.rename", "notes.rename"] },
            { label: "keys.row.schedule", ids: ["task.schedule"] },
            { label: "keys.row.due", ids: ["task.due"] },
            { label: "keys.row.priority", range: true, ids: ["task.priority0", "task.priority1", "task.priority2", "task.priority3"] },
            { label: "keys.row.timer", ids: ["task.timer"] },
            { label: "keys.row.archive", ids: ["board.archive"] },
            { label: "keys.row.menu", ids: ["board.cardMenu"] },
            { label: "keys.row.delete", ids: ["selection.deleteSel"] }
        ] },
        { id: "moveTask", col: 3, rows: [
            { label: "keys.row.moveColumn", ids: ["board.moveLeft", "board.moveRight"] },
            { label: "keys.row.moveUpDown", ids: ["board.moveDown", "board.moveUp"] },
            { label: "keys.row.blockLength", ids: ["cal.longer", "cal.shorter"] },
            { label: "keys.row.columnMove", ids: ["board.columnLeft", "board.columnRight"] }
        ] },
        { id: "copy", col: 0, rows: [
            { label: "keys.row.copyId", ids: ["task.copyId"] },
            { label: "keys.row.copyBranch", ids: ["task.copyBranch"] },
            { label: "keys.row.copyLink", ids: ["task.copyLink"] },
            { label: "keys.row.createBranch", ids: ["task.createBranch"] }
        ] },
        { id: "select", col: 1, rows: [
            { label: "keys.row.select", ids: ["selection.toggle", "board.toggleSelect"] },
            { label: "keys.row.range", ids: ["selection.range"] },
            { label: "keys.row.selectAll", ids: ["selection.selectAll"] },
            { label: "keys.row.clear", ids: ["selection.clearSel"] }
        ] },
        { id: "view", col: 2, rows: [
            { label: "keys.row.zoom", ids: ["cal.zoomDay", "view.week", "view.month"] },
            { label: "keys.row.fold", ids: ["board.collapseColumn"] },
            { label: "keys.row.sidebar", ids: ["rail.toggle"] }
        ] },
        { id: "find", col: 3, rows: [
            { label: "keys.row.filter", ids: ["search.focus.alt"] },
            { label: "keys.row.command", ids: ["palette.commands"] },
            { label: "keys.row.commandLine", ids: ["palette.open"] },
            { label: "keys.row.newTask", ids: ["task.new"] },
            { label: "keys.row.anywhere", ids: ["quick-capture"] },
            { label: "keys.row.undoRedo", ids: ["undo.alt", "redo.alt"] },
            { label: "keys.row.goSettings", ids: ["view.settings"] }
        ] }
    ]
    // What the old keys do now (APP-281 A4).
    readonly property var changedRows: [
        { label: "keys.changed.views", was: "keys.changed.views.was", ids: ["view.board", "view.timeline", "view.calendar"] },
        { label: "keys.changed.tracker", was: "keys.changed.tracker.was", ids: ["task.openExternal"] },
        { label: "keys.changed.fold", was: "keys.changed.fold.was", ids: ["board.collapseColumn"] },
        { label: "keys.changed.today", was: "keys.changed.today.was", ids: ["cal.today"] },
        { label: "keys.changed.date", was: "keys.changed.date.was", ids: ["palette.commands"] }
    ]

    // Every catalogue id the areas do not show. Not an area of its own (the
    // sheet has none): these rows come up only under a search, so a key
    // that exists can always be found.
    readonly property var otherRows: {
        const shown = {};
        for (const g of root.groups)
            for (const r of g.rows)
                for (const id of r.ids) shown[id] = true;
        const out = [];
        const list = AppController.shortcuts;
        for (let i = 0; i < list.length; i++)
            if (!shown[list[i].id]) out.push({ ids: [list[i].id] });
        return out;
    }

    // Every id the sheet shows (a test compares it with the catalogue).
    function allIds() {
        const out = [];
        for (const g of root.groups) for (const r of g.rows) for (const id of r.ids) out.push(id);
        for (const r of root.otherRows) out.push(r.ids[0]);
        return out;
    }

    function _seq(id) {
        const list = AppController.shortcuts;
        for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i].sequence;
        return "";
    }
    function _label(row) {
        if (row.label) return I18n.t(row.label);
        const list = AppController.shortcuts;
        for (let i = 0; i < list.length; i++) if (list[i].id === row.ids[0]) return list[i].label;
        return row.ids[0];
    }
    // The keys of a row as written beside it: each bound id, or a run.
    function keysOf(row) {
        const keys = [];
        for (const id of row.ids) {
            const seq = root._seq(id);
            if (seq.length > 0) keys.push(AppController.keyText(seq));
        }
        if (row.range && keys.length > 2) {
            const a = keys[0], z = keys[keys.length - 1];
            let n = 0;
            while (n < a.length && n < z.length && a[n] === z[n]) n++;
            return [a + "…" + z.slice(n)];
        }
        return keys;
    }
    // A row is found by its words, or by a key in either layout: "ctrl k"
    // and "л" (the K key of ЙЦУКЕН) both find the command line.
    function matches(row, q) {
        const query = String(q || "").trim().toLowerCase();
        if (query.length === 0) return true;
        if (root._label(row).toLowerCase().indexOf(query) >= 0) return true;
        const keys = root.keysOf(row).join("  ").toLowerCase();
        const variants = [query, KeyRules.latinOf(query), KeyRules.translit(query)];
        for (const v of variants)
            if (v.length > 0 && keys.indexOf(v) >= 0) return true;
        return false;
    }
    function _filtered(rows, q) { return rows.filter(r => root.keysOf(r).length > 0 && root.matches(r, q)); }
    readonly property var _shownGroups: {
        const q = search.text.trim();
        const out = root.groups.map(g => Object.assign({}, g));
        out.push({ id: "changed", col: 0, rows: root.changedRows });
        if (q.length > 0) out.push({ id: "other", col: 3, rows: root.otherRows });
        return out;
    }

    onAboutToShow: search.text = ""
    onOpened: search.forceActiveFocus()

    contentItem: ColumnLayout {
        spacing: Theme.spLg

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.sp2xl
            Layout.rightMargin: Theme.sp2xl
            Layout.topMargin: Theme.sp2xl
            spacing: Theme.spMd
            Text {
                text: I18n.t("keys.sheet.title")
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXl
                font.weight: Theme.fwHeading
            }
            Text {
                Layout.fillWidth: true
                // The sheet wraps it at ~900px, not the panel's width (R4-082).
                Layout.maximumWidth: Theme.px(900)
                text: I18n.t("keys.sheet.intro")
                wrapMode: Text.WordWrap
                color: Theme.textMuted
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsSm
            }
            RowLayout {
                spacing: Theme.spLg
                TextField {
                    id: search
                    objectName: "key-sheet-search"
                    Layout.preferredWidth: Theme.px(420)
                    placeholderText: I18n.t("keys.sheet.search")
                    color: Theme.text
                    placeholderTextColor: Theme.textDim
                    font.pixelSize: Theme.fsMd
                    background: FieldFrame {}
                    ContextMenu.menu: TextEditMenu { editor: search }
                }
                Text {
                    text: I18n.t("keys.sheet.searchHint")
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsXs
                }
            }
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: Theme.sp2xl
            Layout.rightMargin: Theme.sp2xl
            clip: true
            contentWidth: width
            contentHeight: cols.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ThinScrollBar {}

            // A grid of four columns read row by row (N/X-Keys, R3-112):
            // Движение | Перейти | Задача | Переместить, then Скопировать |
            // Выделение | Вид | Поиск, then "Изменилось". Fewer columns on a
            // narrow window; an area with nothing found takes no cell.
            GridLayout {
                id: cols
                width: flick.width
                columnSpacing: Theme.sp2xl
                rowSpacing: Theme.sp2xl
                readonly property int n: Math.max(1, Math.min(4, Math.floor((flick.width + Theme.sp2xl) / Theme.px(260))))
                columns: cols.n
                        Repeater {
                            model: root._shownGroups
                            delegate: ColumnLayout {
                                id: group
                                required property var modelData
                                readonly property var shownRows: root._filtered(group.modelData.rows, search.text)
                                objectName: "key-sheet-group-" + group.modelData.id
                                visible: group.shownRows.length > 0
                                Layout.alignment: Qt.AlignTop
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                spacing: 0
                                Text {
                                    Layout.bottomMargin: Theme.spSm
                                    text: I18n.t("keys.group." + group.modelData.id)
                                    color: Theme.textMuted
                                    font.family: Theme.fontUi
                                    font.pixelSize: Theme.fsSm
                                }
                                Repeater {
                                    model: group.shownRows
                                    delegate: Item {
                                        id: row
                                        required property var modelData
                                        readonly property var keys: AppController.shortcuts.length >= 0 ? root.keysOf(row.modelData) : []
                                        objectName: "key-sheet-row-" + row.modelData.ids[0]
                                        Layout.fillWidth: true
                                        implicitHeight: Math.max(rowLabel.implicitHeight, keyRow.implicitHeight) + 2 * Theme.spXs
                                        Text {
                                            id: rowLabel
                                            anchors.left: parent.left
                                            anchors.right: keyRow.left
                                            anchors.rightMargin: Theme.spMd
                                            anchors.verticalCenter: parent.verticalCenter
                                            // A label and its "было …" are each one unit, so the line
                                            // breaks between them, never inside (sheet N-Keys, R4-083).
                                            readonly property string _nb: row.modelData.was ? "&nbsp;" : " "
                                            text: root._label(row.modelData).replace(/ /g, rowLabel._nb)
                                                  + (row.modelData.note ? "&nbsp;&nbsp;<font color=\"" + Theme.textDim + "\">" + I18n.t(row.modelData.note) + "</font>" : "")
                                                  + (row.modelData.was ? "&nbsp; <font color=\"" + Theme.textDim + "\">"
                                                                         + I18n.t(row.modelData.was).replace(/ /g, "&nbsp;") + "</font>" : "")
                                            textFormat: Text.StyledText
                                            wrapMode: Text.WordWrap
                                            color: Theme.text
                                            font.family: Theme.fontUi
                                            font.pixelSize: Theme.fsMd
                                        }
                                        Row {
                                            id: keyRow
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: Theme.spXs
                                            Repeater {
                                                model: row.keys
                                                delegate: Rectangle {
                                                    id: cap
                                                    required property string modelData
                                                    implicitWidth: capText.implicitWidth + 2 * Theme.spSm
                                                    implicitHeight: Theme.chipHSmall
                                                    radius: Theme.radiusSm
                                                    // Filled caps in bold, outlined in
                                                    // quiet, bright mono (R3-111).
                                                    color: Style.fills ? Theme.chipBg : "transparent"
                                                    border.color: Theme.borderStrong
                                                    border.width: 1
                                                    Text {
                                                        id: capText
                                                        anchors.centerIn: parent
                                                        text: cap.modelData
                                                        color: Theme.text
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: Theme.fsXs
                                                        font.weight: Theme.fwTitle
                                                    }
                                                }
                                            }
                                        }
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: 1
                                            color: Theme.border
                                        }
                                    }
                                }
                            }
                        }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.sp2xl
            Layout.rightMargin: Theme.sp2xl
            Layout.bottomMargin: Theme.spXl
            spacing: Theme.spXl
            Text {
                objectName: "key-sheet-edit"
                text: I18n.t("keys.sheet.edit")
                color: editCA.hovered ? Theme.text : Theme.accentStrong
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsSm
                ClickArea {
                    id: editCA
                    label: parent.text
                    onActivated: {
                        root.close();
                        root.editRequested();
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: I18n.t("keys.sheet.footer").arg(AppController.shortcuts.length >= 0 ? AppController.shortcutText("hotkeys.open") : "")
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: Theme.fsXs
                elide: Text.ElideRight
            }
        }
    }
}
