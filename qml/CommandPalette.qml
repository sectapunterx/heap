// Ctrl+K fuzzy palette across profiles: tasks, docs, snippets, contacts, people.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import TodoCpp

Popup {
    id: root
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    padding: 0
    width: 600
    height: 480
    anchors.centerIn: Overlay.overlay

    signal navigateToDoc(string sectionId)
    signal navigateToSnippets()
    signal navigateToContacts()
    signal openTask(string taskId)
    signal openPerson(string personId)

    property var _entries: []           // cached full list
    property var _matches: []           // filtered + scored
    property int _selectedIdx: 0

    function _refresh() {
        _entries = AppController.commandPaletteEntries();
        _matches = _filterAndScore("");
        _selectedIdx = 0;
    }

    function _fuzzyScore(q, s) {
        // subsequence match with proximity bonus; returns -1 if no match
        if (q.length === 0) return 0;
        const ql = q.toLowerCase();
        const sl = s.toLowerCase();
        let i = 0, j = 0, score = 0, lastPos = -2;
        while (i < ql.length && j < sl.length) {
            if (ql[i] === sl[j]) {
                score += (lastPos + 1 === j ? 10 : 2);
                lastPos = j;
                i++;
            }
            j++;
        }
        if (i < ql.length) return -1;
        score -= lastPos * 0.05;  // prefer early matches
        return score;
    }

    function _filterAndScore(q) {
        const out = [];
        const trimmed = (q || "").trim();
        for (let i = 0; i < _entries.length; i++) {
            const e = _entries[i];
            const sc = _fuzzyScore(trimmed, e.label + " " + (e.sub || ""));
            if (sc < 0) continue;
            // tiny boost so a task in the active profile floats up
            const profBonus = (e.profileId === AppController.activeProfileId) ? 1 : 0;
            out.push({ entry: e, score: sc + profBonus });
        }
        out.sort(function (a, b) { return b.score - a.score; });
        return out.slice(0, 80).map(function (x) { return x.entry; });
    }

    function _activate(entry) {
        if (!entry) return;
        const switchProfile = (entry.profileId && entry.profileId !== AppController.activeProfileId);
        if (switchProfile) AppController.activeProfileId = entry.profileId;
        Qt.callLater(function () {
            if (entry.kind === "profile") {
                // already switched above
            } else if (entry.kind === "task") {
                AppController.currentView = "board";
                root.openTask(entry.taskId);
            } else if (entry.kind === "doc") {
                AppController.currentView = "docs";
                root.navigateToDoc(entry.sectionId);
            } else if (entry.kind === "snippet") {
                AppController.currentView = "docs";
                root.navigateToSnippets();
            } else if (entry.kind === "contact") {
                AppController.currentView = "docs";
                root.navigateToContacts();
            } else if (entry.kind === "person") {
                root.openPerson(entry.personId);
            }
            root.close();
        });
    }

    onAboutToShow: {
        _refresh();
        searchField.text = "";
        Qt.callLater(searchField.forceActiveFocus);
    }

    background: Rectangle {
        radius: 12; color: Theme.panel
        border.color: Theme.borderStrong; border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: 0

        // Search row
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            color: "transparent"
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                height: 1; color: Theme.border
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16; anchors.rightMargin: 16
                spacing: 10
                Text { text: "⌕"; color: Theme.textMuted; font.pixelSize: 18 }
                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: "Поиск задач, доков, сниппетов, контактов…"
                    background: Item {}
                    color: Theme.text
                    placeholderTextColor: Theme.textDim
                    font.pixelSize: 14
                    selectByMouse: true
                    onTextChanged: {
                        root._matches = root._filterAndScore(text);
                        root._selectedIdx = 0;
                    }
                    Keys.onDownPressed:  if (root._matches.length > 0) root._selectedIdx = Math.min(root._matches.length - 1, root._selectedIdx + 1)
                    Keys.onUpPressed:    if (root._matches.length > 0) root._selectedIdx = Math.max(0, root._selectedIdx - 1)
                    Keys.onReturnPressed: root._activate(root._matches[root._selectedIdx])
                    Keys.onEnterPressed:  root._activate(root._matches[root._selectedIdx])
                }
                Text {
                    visible: root._matches.length > 0
                    text: (root._selectedIdx + 1) + " / " + root._matches.length
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }
            }
        }

        // Results
        ListView {
            id: resultsView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            currentIndex: root._selectedIdx
            highlightFollowsCurrentItem: true
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            model: root._matches
            spacing: 2

            delegate: Rectangle {
                required property var modelData
                required property int index
                width: ListView.view.width
                height: 42
                color: index === root._selectedIdx ? Theme.panel2 : "transparent"
                radius: 4

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    spacing: 10

                    Rectangle {
                        width: 18; height: 18; radius: 4
                        color: "transparent"
                        border.color: modelData.color || Theme.accent
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: {
                                switch (modelData.kind) {
                                    case "task":    return "T";
                                    case "doc":     return "D";
                                    case "snippet": return "S";
                                    case "contact": return "C";
                                    case "profile": return "●";
                                    case "person":  return "P";
                                }
                                return "?";
                            }
                            color: modelData.color || Theme.accent
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: modelData.label
                            color: Theme.text
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: modelData.sub
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Text {
                        text: modelData.kind
                        color: Theme.textDim
                        font.family: Theme.fontMono
                        font.pixelSize: 10
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root._selectedIdx = index
                    onClicked: root._activate(modelData)
                }
            }

            // Empty state
            Text {
                visible: root._matches.length === 0
                anchors.centerIn: parent
                text: searchField.text.length === 0 ? "введите запрос…" : "ничего не найдено"
                color: Theme.textDim
                font.pixelSize: 12
            }
        }

        // Hints
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            color: Theme.panel2
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 1; color: Theme.border }
            Text {
                anchors.centerIn: parent
                text: "↑↓ выбор · Enter переход · Esc закрыть"
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: 10
            }
        }
    }
}
