import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import TodoCpp

Rectangle {
    id: root
    color: Theme.panel2

    signal personRequested(string id)
    signal pickPersonRequested()

    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        height: 1; color: Theme.border
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Theme.spXl
        spacing: Theme.spMd

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spSm
            Text {
                text: I18n.t("people.label.title")
                color: Theme.textDim
                font.pixelSize: Theme.fsSm
                font.weight: Theme.fwTitle
            }
            // One count (APP-197): how many are waiting for a message from
            // me. The list itself shows how many people there are.
            Rectangle {
                visible: badge.pending > 0
                radius: Theme.radiusPill
                color: Theme.panel3
                implicitWidth: badge.implicitWidth + 12
                implicitHeight: 18
                // Counts come from calls the binding cannot watch, so the model
                // signals bump a revision it does watch. They used to assign
                // badge.text directly, which broke the binding to I18n: the
                // badge stayed English after switching to Russian.
                property int _rev: 0
                Text {
                    id: badge
                    anchors.centerIn: parent
                    readonly property int pending: parent._rev >= 0 ? AppController.pendingPeopleCount() : 0
                    text: I18n.t("people.badge.pending").arg(badge.pending)
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.features: Theme.tabularNums
                    font.pixelSize: Theme.fsXs
                }
                Connections {
                    target: AppController.activePeople
                    function onDataChanged()    { badge.parent._rev++ }
                    function onRowsInserted()   { badge.parent._rev++ }
                    function onRowsRemoved()    { badge.parent._rev++ }
                    function onModelReset()     { badge.parent._rev++ }
                }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                id: addBtn
                width: Theme.px(22); height: Theme.px(22); radius: Theme.radiusSm
                color: addMA.containsMouse ? Theme.panel3 : "transparent"
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: I18n.t("people.tip.add")
                Keys.onSpacePressed: root.pickPersonRequested()
                Keys.onReturnPressed: root.pickPersonRequested()
                FocusRing {}
                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: addMA.containsMouse ? Theme.text : Theme.textDim
                    font.pixelSize: Theme.fsLg
                }
                MouseArea {
                    id: addMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pickPersonRequested()
                    ToolTip.visible: containsMouse || addBtn.activeFocus
                    ToolTip.delay: 400
                    ToolTip.text: I18n.t("people.tip.add")
                }
            }
        }

        ListView {
            id: peopleView
            // Named for a screen reader: it is a Tab stop (APP-168).
            Accessible.name: I18n.t("people.title")
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.spSm
            // Not `people`: the rail carries the people something is pending
            // on, and a Mattermost sync imports every colleague ever DM'd as
            // "idle". See ActivePeopleModel.
            model: AppController.activePeople
            boundsBehavior: Flickable.StopAtBounds
            // Keyboard: Tab lands on the list, ↑/↓ walk it, Enter edits the
            // person, the menu key (or Shift+F10) opens their menu.
            activeFocusOnTab: true
            keyNavigationEnabled: true
            Accessible.role: Accessible.List
            Keys.onReturnPressed: if (currentItem) root.personRequested(currentItem.id)
            Keys.onEnterPressed: if (currentItem) root.personRequested(currentItem.id)
            Keys.onPressed: (event) => {
                if (currentItem && (event.key === Qt.Key_Menu
                                    || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier)))) {
                    currentItem.openMenu();
                    event.accepted = true;
                }
            }
            onActiveFocusChanged: if (activeFocus && currentIndex < 0 && count > 0) currentIndex = 0

            // Empty is the resting state now, not an unfinished setup: the rail
            // is only ever as long as what is actually outstanding.
            Text {
                anchors.centerIn: parent
                width: parent.width - 32
                visible: peopleView.count === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: I18n.t("people.empty")
                color: Theme.textDim
                font.pixelSize: Theme.fsSm
            }

            delegate: Item {
                id: prow
                required property string id
                required property string name
                required property string role
                required property string question
                required property var color
                // `state` is QQuickItem's own property — the name of the active
                // State — so a `required property string state` here shadows it
                // and puts a person's workflow state into the item's state
                // machine. Read the role off the model object instead.
                required property var model
                readonly property string personState: prow.model.state
                width: ListView.view ? ListView.view.width : 0
                height: layout.implicitHeight + 12
                function openMenu() { personMenu.popup(prow, 12, prow.height / 2); }
                FocusRing {
                    anchors.margins: 0
                    radius: Theme.radius
                    visible: prow.ListView.isCurrentItem && peopleView.activeFocus
                    z: 10
                }

                // Row hover drives the highlight and the ✎ affordance. It has to
                // be a HoverHandler: hover delivery stops at the first item that
                // accepts it, so a MouseArea here lost hover the moment the
                // pointer reached the ✎ on top of it — the row un-highlighted and
                // the button faded out from under the cursor.
                property bool rowHovered: false
                HoverHandler { onHoveredChanged: prow.rowHovered = hovered }
                // The list's keyboard row shows the ✎ as the pointer does
                // (APP-184); Enter edits, the menu key holds the rest.
                readonly property bool keyCurrent: prow.ListView.isCurrentItem && !!prow.ListView.view && prow.ListView.view.activeFocus
                readonly property bool revealed: prow.rowHovered || prow.keyCurrent
                Accessible.role: Accessible.ListItem
                Accessible.name: prow.name + (prow.role.length ? ", " + prow.role : "")
                Accessible.description: stT.text + (prow.question.length ? ". " + prow.question : "")

                // Declared before the RowLayout so it sits below it in paint /
                // event order (later siblings draw on top, events hit them first).
                MouseArea {
                    id: rowMA
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) personMenu.popup();
                        else root.personRequested(prow.id);
                    }
                }

                AppMenu {
                    id: personMenu
                    AppMenuItem { text: I18n.t("people.menu.edit"); onTriggered: root.personRequested(prow.id) }
                    AppMenuItem { text: I18n.t("people.menu.cycle"); onTriggered: AppController.cyclePerson(prow.id) }
                    // Off the rail without losing the person: they stay in
                    // contacts, @-autocomplete and the picker.
                    AppMenuItem { text: I18n.t("people.menu.dismiss"); onTriggered: AppController.setPersonState(prow.id, "idle") }
                    AppMenuSeparator {}
                    AppMenuItem { danger: true; text: I18n.t("people.menu.delete"); onTriggered: AppController.deletePerson(prow.id) }
                }

                // 2) Hover indicator — a real Rectangle whose visibility is
                //    toggled by border.width / a separate fill Rectangle.
                //    Using opacity instead of swapping color literals avoids
                //    the "transparent string" rendering quirk on Windows.
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius
                    color: Theme.panel3
                    border.color: Theme.border
                    border.width: 1
                    opacity: prow.rowHovered ? 1.0 : 0.0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: prow.rowHovered ? Theme.durTap : Theme.durTapOut
                            easing.type: prow.rowHovered ? Theme.easeEnter : Theme.easeExit
                        }
                    }
                }

                RowLayout {
                    id: layout
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Theme.spMd; anchors.rightMargin: Theme.spMd
                    spacing: Theme.spLg

                    // Sized with the type its initials are set in: a fixed
                    // 28 let "МК" run past the circle at 150 % (SCALE-4).
                    Rectangle {
                        objectName: "people-avatar"
                        width: Theme.px(28); height: width; radius: width / 2
                        color: prow.color
                        Text {
                            anchors.centerIn: parent
                            text: {
                                const parts = prow.name.split(/\s+/);
                                return (parts[0] ? parts[0][0] : "") + (parts[1] ? parts[1][0] : "");
                            }
                            color: Theme.textOnAccent
                            font.family: Theme.fontUi
                            font.features: Theme.tabularNums
                            font.pixelSize: Theme.fsSm
                            font.weight: Theme.fwTitle
                        }
                    }
                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1
                        // The name, and the role beside it in dim text
                        // rather than chained on with a "·" (APP-197).
                        Row {
                            width: parent.width
                            spacing: Theme.spMd
                            Text {
                                id: personName
                                width: Math.min(implicitWidth, parent.width - (roleT.visible ? Math.min(roleT.implicitWidth, parent.width / 2) + parent.spacing : 0))
                                text: prow.name
                                color: (prow.personState === "todo") ? Theme.text : Theme.textMuted
                                font.pixelSize: Theme.fsMd
                                font.weight: Theme.fwTitle
                                elide: Text.ElideRight
                            }
                            Text {
                                id: roleT
                                anchors.baseline: personName.baseline
                                visible: prow.role.length > 0
                                width: Math.max(0, parent.width - personName.width - parent.spacing)
                                text: prow.role
                                color: Theme.textDim
                                font.pixelSize: Theme.fsSm
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            width: parent.width
                            text: prow.question
                            color: Theme.textMuted
                            font.pixelSize: Theme.fsSm
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.strikeout: prow.personState === "replied"
                            opacity: prow.personState === "replied" ? 0.6 : 1.0
                        }
                    }

                    Item {
                        objectName: "people-edit"
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        opacity: prow.revealed ? 1.0 : 0.0
                        enabled: prow.revealed
                        Accessible.role: Accessible.Button
                        Accessible.name: I18n.t("people.tip.edit")
                        Behavior on opacity {
                            NumberAnimation {
                                duration: prow.revealed ? Theme.durTap : Theme.durTapOut
                                easing.type: prow.revealed ? Theme.easeEnter : Theme.easeExit
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusSm
                            color: editMA.containsMouse ? Theme.panel : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "✎"
                                color: Theme.textMuted
                                font.pixelSize: Theme.fsMd
                            }
                            MouseArea {
                                id: editMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.personRequested(prow.id)
                                ToolTip.visible: containsMouse
                                ToolTip.delay: 400
                                ToolTip.text: I18n.t("people.tip.edit")
                            }
                        }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        Accessible.role: Accessible.Button
                        Accessible.name: stT.text + ", " + I18n.t("people.tip.cycle")
                        Accessible.onPressAction: AppController.cyclePerson(prow.id)
                        radius: Theme.radiusPill
                        color: prow.personState === "pinged" ? Theme.withAlpha(Theme.warning, 0.10)
                             : prow.personState === "replied" ? Theme.withAlpha(Theme.stDone, 0.10)
                             : Theme.bg2
                        border.color: prow.personState === "pinged" ? Theme.withAlpha(Theme.warning, 0.4)
                                    : prow.personState === "replied" ? Theme.withAlpha(Theme.stDone, 0.4)
                                    : Theme.border
                        border.width: 1
                        implicitWidth: stT.implicitWidth + 14
                        implicitHeight: 22
                        Text {
                            id: stT
                            anchors.centerIn: parent
                            text: prow.personState === "todo" ? I18n.t("people.state.todo.tag")
                                : prow.personState === "pinged" ? I18n.t("people.state.pinged.tag")
                                    : prow.personState === "replied" ? I18n.t("people.state.replied.tag")
                                        : I18n.t("people.state.idle.tag")
                            color: prow.personState === "pinged" ? Theme.warning
                                 : prow.personState === "replied" ? Theme.stDone
                                 : Theme.textDim
                            font.family: Theme.fontUi
                            font.features: Theme.tabularNums
                            font.pixelSize: Theme.fsXs
                            font.weight: Theme.fwTitle
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: AppController.cyclePerson(prow.id)
                            ToolTip.visible: containsMouse
                            ToolTip.delay: 400
                            ToolTip.text: I18n.t("people.tip.cycle")
                        }
                    }
                }
            }
        }
    }
}
