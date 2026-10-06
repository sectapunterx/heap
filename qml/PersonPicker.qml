// The People rail's "+": pick who to ping.
//
// The rail is a to-do list, not a directory, so adding someone to it starts by
// finding them among the people already known — the profile's Docs contacts and
// its People, which AppController.pingCandidates() folds into one row per
// human. Anyone not there yet is created from the same box: the query doubles
// as the new contact's name, so a miss costs one keystroke instead of a
// detour through Docs.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0
    width: 460
    anchors.centerIn: Overlay.overlay

    Overlay.modal: Rectangle { color: Theme.scrim }

    // Emitted with a PersonEditor draft — Main hands it straight to the editor.
    signal draftRequested(var draft)
    // Pick mode (APP-158, "waiting on…"): choosing someone answers with their
    // Person id instead of opening the editor. A contact with no Person yet,
    // or a new name, becomes one first.
    property bool pickOnly: false
    property string title: I18n.t("people.pick.title")
    signal personPicked(string personId)

    // Every candidate, as pingCandidates() returned it. Re-read on each open:
    // a Mattermost sync or an edit in Docs may have changed the list since.
    property var candidates: []
    property string query: ""

    readonly property var matches: {
        const q = root.query.toLowerCase().trim();
        const out = [];
        for (let i = 0; i < root.candidates.length; i++) {
            const c = root.candidates[i];
            // Name and handle the way @-mentions find them: a login made of
            // the name ("r.losev"), the words in either script.
            const handle = String(c.handle || "").replace(/^@+/, "");
            let r = q.length === 0 ? 1 : AppController.personMatchRank(q, c.name || "", handle);
            if (q.length > 0 && c.personId && c.personId !== handle)
                r = Math.max(r, AppController.personMatchRank(q, c.name || "", c.personId));
            if (r === 0 && ((c.role || "").toLowerCase().indexOf(q) >= 0
                            || (c.channel || "").toLowerCase().indexOf(q) >= 0))
                r = 1;
            if (r > 0) out.push(Object.assign({}, c, { _rank: r }));
        }
        // People already on the rail sink to the bottom: the point of this box
        // is the ones who are not. Then the better match; name breaks the tie
        // — V4's sort is not stable, so without it the list reshuffles between
        // openings and the row under the cursor is never the same one twice.
        out.sort((a, b) => {
            if (!!a.active !== !!b.active) return a.active ? 1 : -1;
            if (a._rank !== b._rank) return b._rank - a._rank;
            return String(a.name || "").localeCompare(String(b.name || ""));
        });
        return out;
    }

    // "Create «query»" is a row of its own at the end of the list, so Down/Up
    // reach it and Enter on an empty list does the obvious thing.
    readonly property bool canCreate: root.query.trim().length > 0
    readonly property int rowCount: root.matches.length + (root.canCreate ? 1 : 0)
    property int current: 0

    function open_() {
        candidates = AppController.pingCandidates();
        query = "";
        current = 0;
        open();
        searchField.text = "";
        searchField.forceActiveFocus();
    }

    function _accept() {
        if (root.pickOnly) {
            let draft = null;
            if (root.current < root.matches.length) {
                const c = root.matches[root.current];
                if (c.personId && AppController.personById(c.personId).id) {
                    root.close();
                    root.personPicked(c.personId);
                    return;
                }
                draft = AppController.pingDraftFor(c);
            } else if (root.canCreate) {
                draft = AppController.newContactDraft(root.query.trim());
            }
            // Someone you are waiting on is someone you have asked.
            if (draft && draft._isNew) draft.state = "pinged";
            if (draft && AppController.savePerson(draft)) {
                root.close();
                root.personPicked(draft.id);
            }
            return;
        }
        if (root.current < root.matches.length) {
            root.draftRequested(AppController.pingDraftFor(root.matches[root.current]));
            root.close();
        } else if (root.canCreate) {
            root.draftRequested(AppController.newContactDraft(root.query.trim()));
            root.close();
        }
    }

    function _move(delta) {
        if (root.rowCount === 0) return;
        current = (current + delta + root.rowCount) % root.rowCount;
        list.positionViewAtIndex(Math.min(current, list.count - 1), ListView.Contain);
    }

    // A shorter query can leave `current` past the end of the list.
    onMatchesChanged: if (current >= rowCount) current = Math.max(0, rowCount - 1)

    background: Rectangle {
        radius: Theme.radiusXl
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: 0

        Text {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.topMargin: Theme.sp2xl
            text: root.title
            color: Theme.text
            font.pixelSize: Theme.fsLg
            font.weight: Theme.fwHeading
        }

        TextField {
            id: searchField
            ContextMenu.menu: TextEditMenu { editor: searchField }
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.topMargin: Theme.spXl
            Layout.fillWidth: true
            placeholderText: I18n.t("people.pick.ph")
            background: FieldFrame {}
            color: Theme.text
            placeholderTextColor: Theme.textDim
            onTextChanged: { root.query = text; root.current = 0; }
            // Keyboard-first: the field keeps focus and drives the list, the
            // way CommandPalette does.
            Keys.onDownPressed: root._move(1)
            Keys.onUpPressed: root._move(-1)
            Keys.onReturnPressed: root._accept()
            Keys.onEnterPressed: root._accept()
        }

        Text {
            Layout.leftMargin: Theme.inset; Layout.rightMargin: Theme.inset; Layout.topMargin: Theme.sp2xl
            visible: root.rowCount === 0
            text: I18n.t("people.pick.none")
            color: Theme.textDim
            font.pixelSize: Theme.fsMd
        }

        ListView {
            id: list
            Layout.leftMargin: Theme.spLg; Layout.rightMargin: Theme.spLg; Layout.topMargin: Theme.spLg
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 260)
            visible: count > 0
            clip: true
            model: root.matches
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: root.current

            delegate: Item {
                id: crow
                required property var modelData
                required property int index
                width: ListView.view ? ListView.view.width : 0
                height: 42

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: Theme.sp2xs
                    radius: Theme.radius
                    color: Theme.panel3
                    opacity: root.current === crow.index ? 1.0 : 0.0
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.current = crow.index
                    onClicked: { root.current = crow.index; root._accept(); }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spLg; anchors.rightMargin: Theme.spLg
                    spacing: Theme.spLg

                    Rectangle {
                        width: 26; height: 26; radius: 13
                        color: crow.modelData.color && crow.modelData.color.length ? crow.modelData.color : Theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: {
                                const parts = String(crow.modelData.name || "").split(/\s+/);
                                return (parts[0] ? parts[0][0] : "") + (parts[1] ? parts[1][0] : "");
                            }
                            color: Theme.textOnAccent
                            font.family: Theme.fontUi
                            font.features: Theme.tabularNums
                            font.pixelSize: Theme.fsXs
                            font.weight: Theme.fwTitle
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: crow.modelData.name || ""
                            color: Theme.text
                            font.pixelSize: Theme.fsMd
                            font.weight: Theme.fwTitle
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: {
                                const bits = [];
                                if (crow.modelData.role) bits.push(crow.modelData.role);
                                if (crow.modelData.handle) bits.push(crow.modelData.handle);
                                if (crow.modelData.channel) bits.push(crow.modelData.channel);
                                return bits.join(" · ");
                            }
                            color: Theme.textMuted
                            font.pixelSize: Theme.fsXs
                            elide: Text.ElideRight
                        }
                    }

                    // Someone already on the rail is still pickable — it just
                    // reopens their row rather than adding a second one.
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        visible: !!crow.modelData.active
                        radius: Theme.radiusPill
                        color: Theme.bg2
                        border.color: Theme.border
                        border.width: 1
                        implicitWidth: inRail.implicitWidth + 12
                        implicitHeight: 18
                        Text {
                            id: inRail
                            anchors.centerIn: parent
                            text: I18n.t("people.pick.inrail")
                            color: Theme.textDim
                            font.family: Theme.fontUi
                            font.features: Theme.tabularNums
                            font.pixelSize: Theme.fsXs
                            font.letterSpacing: 1
                        }
                    }
                }
            }
        }

        Item {
            Layout.leftMargin: Theme.spLg; Layout.rightMargin: Theme.spLg; Layout.topMargin: Theme.sp2xs
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            visible: root.canCreate

            readonly property bool selected: root.current === root.matches.length

            Rectangle {
                anchors.fill: parent
                anchors.margins: Theme.sp2xs
                radius: Theme.radius
                color: Theme.panel3
                opacity: parent.selected ? 1.0 : 0.0
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.current = root.matches.length
                onClicked: { root.current = root.matches.length; root._accept(); }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spLg; anchors.rightMargin: Theme.spLg
                spacing: Theme.spLg
                Rectangle {
                    width: 26; height: 26; radius: 13
                    color: "transparent"
                    border.color: Theme.border
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: Theme.textMuted
                        font.pixelSize: Theme.fsMd
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.t("people.pick.create").arg(root.query.trim())
                    color: Theme.text
                    font.pixelSize: Theme.fsMd
                    elide: Text.ElideRight
                }
            }
        }

        Item { Layout.preferredHeight: 12 }
    }
}
