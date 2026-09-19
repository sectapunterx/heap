import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Controls as QQC
import TodoCpp

Rectangle {
    id: root
    color: Theme.panel2

    signal personRequested(string id)
    signal newPersonRequested()

    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        height: 1; color: Theme.border
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text {
                text: I18n.t("people.label.title")
                color: Theme.textMuted
                font.pixelSize: 11
                font.letterSpacing: 1
                font.weight: Font.DemiBold
            }
            Rectangle {
                radius: 999
                color: Theme.panel3
                implicitWidth: badge.implicitWidth + 12
                implicitHeight: 18
                Text {
                    id: badge
                    anchors.centerIn: parent
                    text: I18n.t("people.badge").arg(AppController.pendingPeopleCount()).arg(AppController.people.rowCount())
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                }
                Connections {
                    target: AppController.people
                    function onDataChanged()    { badge.text = I18n.t("people.badge").arg(AppController.pendingPeopleCount()).arg(AppController.people.rowCount()) }
                    function onRowsInserted()   { badge.text = I18n.t("people.badge").arg(AppController.pendingPeopleCount()).arg(AppController.people.rowCount()) }
                    function onRowsRemoved()    { badge.text = I18n.t("people.badge").arg(AppController.pendingPeopleCount()).arg(AppController.people.rowCount()) }
                    function onModelReset()     { badge.text = I18n.t("people.badge").arg(AppController.pendingPeopleCount()).arg(AppController.people.rowCount()) }
                }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                width: 22; height: 22; radius: 5
                color: addMA.containsMouse ? Theme.panel3 : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: addMA.containsMouse ? Theme.text : Theme.textDim
                    font.pixelSize: 14
                }
                MouseArea {
                    id: addMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.newPersonRequested()
                    ToolTip.visible: containsMouse
                    ToolTip.delay: 400
                    ToolTip.text: I18n.t("people.tip.add")
                }
            }
        }

        ListView {
            id: peopleView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: AppController.people
            boundsBehavior: Flickable.StopAtBounds

            // Empty state — the string existed in I18n but was never rendered.
            Text {
                anchors.centerIn: parent
                width: parent.width - 32
                visible: peopleView.count === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: I18n.t("people.empty")
                color: Theme.textDim
                font.pixelSize: 11
            }

            delegate: Item {
                id: prow
                required property string id
                required property string name
                required property string role
                required property string question
                required property string state
                required property var color
                width: ListView.view ? ListView.view.width : 0
                height: layout.implicitHeight + 12

                // Row hover drives the highlight and the ✎ affordance. It has to
                // be a HoverHandler: hover delivery stops at the first item that
                // accepts it, so a MouseArea here lost hover the moment the
                // pointer reached the ✎ on top of it — the row un-highlighted and
                // the button faded out from under the cursor.
                property bool rowHovered: false
                HoverHandler { onHoveredChanged: prow.rowHovered = hovered }

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

                QQC.Menu {
                    id: personMenu
                    QQC.MenuItem { text: I18n.t("people.menu.edit"); onTriggered: root.personRequested(prow.id) }
                    QQC.MenuItem { text: I18n.t("people.menu.cycle"); onTriggered: AppController.cyclePerson(prow.id) }
                    QQC.MenuSeparator {}
                    QQC.MenuItem { text: I18n.t("people.menu.delete"); onTriggered: AppController.deletePerson(prow.id) }
                }

                // 2) Hover indicator — a real Rectangle whose visibility is
                //    toggled by border.width / a separate fill Rectangle.
                //    Using opacity instead of swapping color literals avoids
                //    the "transparent string" rendering quirk on Windows.
                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: Theme.panel3
                    border.color: Theme.border
                    border.width: 1
                    opacity: prow.rowHovered ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: Theme.scaledMs(80) } }
                }

                RowLayout {
                    id: layout
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 8; anchors.rightMargin: 8
                    spacing: 10

                    Rectangle {
                        width: 28; height: 28; radius: 14
                        color: prow.color
                        Text {
                            anchors.centerIn: parent
                            text: {
                                const parts = prow.name.split(/\s+/);
                                return (parts[0] ? parts[0][0] : "") + (parts[1] ? parts[1][0] : "");
                            }
                            color: "#06121a"
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }
                    Column {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1
                        Text {
                            width: parent.width
                            text: prow.name + (prow.role.length ? "  · " + prow.role : "")
                            color: (prow.state === "todo") ? Theme.text : Theme.textMuted
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: prow.question
                            color: Theme.textMuted
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            font.strikeout: prow.state === "replied"
                            opacity: prow.state === "replied" ? 0.6 : 1.0
                        }
                    }

                    Item {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        opacity: prow.rowHovered ? 1.0 : 0.0
                        enabled: prow.rowHovered
                        Behavior on opacity { NumberAnimation { duration: Theme.scaledMs(80) } }
                        Rectangle {
                            anchors.fill: parent
                            radius: 5
                            color: editMA.containsMouse ? Theme.panel : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "✎"
                                color: Theme.textMuted
                                font.pixelSize: 12
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
                        radius: 999
                        color: prow.state === "pinged" ? Theme.withAlpha(Theme.p1, 0.10)
                             : prow.state === "replied" ? Theme.withAlpha(Theme.stDone, 0.10)
                             : Theme.bg2
                        border.color: prow.state === "pinged" ? Theme.withAlpha(Theme.p1, 0.4)
                                    : prow.state === "replied" ? Theme.withAlpha(Theme.stDone, 0.4)
                                    : Theme.border
                        border.width: 1
                        implicitWidth: stT.implicitWidth + 14
                        implicitHeight: 22
                        Text {
                            id: stT
                            anchors.centerIn: parent
                            text: prow.state === "todo" ? I18n.t("people.state.todo.tag")
                                : prow.state === "pinged" ? I18n.t("people.state.pinged.tag")
                                    : prow.state === "replied" ? I18n.t("people.state.replied.tag")
                                        : I18n.t("people.state.idle.tag")
                            color: prow.state === "pinged" ? Theme.p1
                                 : prow.state === "replied" ? Theme.stDone
                                 : Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            font.letterSpacing: 1
                            font.weight: Font.DemiBold
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
