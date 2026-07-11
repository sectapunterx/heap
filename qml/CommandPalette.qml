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

    // Dimmed backdrop so the underlying app stays visible behind the popup.
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.55) }

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
        // A late single-char match can push score below 0; clamp so a real match
        // never collides with the -1 no-match sentinel the caller filters on.
        return Math.max(0, score);
    }

    function _escapeHtml(s) {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    // Build a StyledText snippet: ~30 chars of context on each side of the first
    // occurrence of `q` in `body`, with the match emphasised. "" if not present.
    function _snippetFor(body, q) {
        if (!body || q.length < 2) return "";
        const idx = body.toLowerCase().indexOf(q.toLowerCase());
        if (idx < 0) return "";
        const start = Math.max(0, idx - 30);
        const end = Math.min(body.length, idx + q.length + 40);
        const frag = body.substring(start, end).replace(/\s+/g, " ").trim();
        const mi = frag.toLowerCase().indexOf(q.toLowerCase());
        const lead = start > 0 ? "…" : "";
        const tail = end < body.length ? "…" : "";
        if (mi < 0) return lead + _escapeHtml(frag) + tail;
        return lead + _escapeHtml(frag.substring(0, mi))
             + "<b>" + _escapeHtml(frag.substring(mi, mi + q.length)) + "</b>"
             + _escapeHtml(frag.substring(mi + q.length)) + tail;
    }

    function _filterAndScore(q) {
        const out = [];
        const trimmed = (q || "").trim();
        const ql = trimmed.toLowerCase();
        for (let i = 0; i < _entries.length; i++) {
            const e = _entries[i];
            let score = _fuzzyScore(trimmed, e.label + " " + (e.sub || ""));
            let snippet = "";
            // Full-text (HEAP-80): match the body too, with a context snippet.
            if (trimmed.length >= 2 && e.body && e.body.toLowerCase().indexOf(ql) >= 0) {
                snippet = _snippetFor(e.body, trimmed);
                // Body hit floors the entry at tier 5 (below head matches). Use
                // max, not `if (score < 0)`, so a weak-label match that _fuzzyScore
                // now clamps to 0 still gets the body tier and isn't ranked below
                // a pure body-only hit.
                score = Math.max(score, 5);
            }
            if (score < 0) continue;
            // tiny boost so an entry in the active profile floats up
            const profBonus = (e.profileId === AppController.activeProfileId) ? 1 : 0;
            out.push({ entry: e, score: score + profBonus, snippet: snippet });
        }
        out.sort(function (a, b) { return b.score - a.score; });
        return out.slice(0, 80).map(function (x) {
            const c = Object.assign({}, x.entry);
            c._snippet = x.snippet;
            return c;
        });
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
            } else if (entry.kind === "note") {
                AppController.currentView = "notes";
            } else if (entry.kind === "template") {
                AppController.currentView = "board";
                AppController.createTaskFromTemplate(entry.templateName);
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
                    placeholderText: I18n.t("palette.placeholderLong")
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
                height: (modelData._snippet && modelData._snippet.length > 0) ? 58 : 42
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
                                    case "note":    return "N";
                                    case "template": return "✚";
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
                            visible: !(modelData._snippet && modelData._snippet.length > 0)
                            text: modelData.sub
                            color: Theme.textMuted
                            font.family: Theme.fontMono
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        // Full-text context snippet with the match emphasised
                        // (HEAP-80). Shown in place of `sub` when the hit is in
                        // the body rather than the title.
                        Text {
                            visible: modelData._snippet && modelData._snippet.length > 0
                            text: modelData._snippet || ""
                            textFormat: Text.StyledText
                            color: Theme.textMuted
                            font.pixelSize: 11
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
                text: searchField.text.length === 0 ? I18n.t("palette.empty.start") : I18n.t("palette.empty.miss")
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
                text: I18n.t("palette.kbdHint")
                color: Theme.textDim
                font.family: Theme.fontMono
                font.pixelSize: 10
            }
        }
    }
}
