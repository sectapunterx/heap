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
    anchors.centerIn: Overlay.overlay

    property string kind: "doc"          // doc | snippet | contact | section
    property bool   isNew: false
    property string sectionId: ""        // for doc / section (=original id)
    property string originalRef: ""      // for doc rename / move
    property int    idx: -1              // for snippet / contact
    property var    sections: []
    property var    contactPalette: []
    property var    accentPalette: []    // for section
    property var    draft: ({})

    signal savedDoc(var draft)
    signal deletedDoc()
    signal savedSnippet(var draft)
    signal deletedSnippet()
    signal savedContact(var draft)
    signal deletedContact()
    signal savedSection(var draft)
    signal deletedSection()

    width: kind === "snippet" ? 700 : 500

    background: Rectangle {
        radius: 12
        color: Theme.panel
        border.color: Theme.borderStrong
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: 12
        Item { Layout.preferredHeight: 4 }

        RowLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18
            spacing: 8
            Text {
                text: root.kind === "doc"     ? (root.isNew ? "Новая запись"  : "Редактировать запись")
                    : root.kind === "snippet" ? (root.isNew ? "Новый snippet" : "Редактировать snippet")
                    : root.kind === "section" ? (root.isNew ? "Новая секция"  : "Редактировать секцию")
                                              : (root.isNew ? "Новый контакт" : "Редактировать контакт")
                color: Theme.text; font.pixelSize: 14; font.weight: Font.DemiBold
            }
            Text {
                visible: !root.isNew && root.kind === "doc" && (root.draft.ref || "").length > 0
                text: root.draft.ref || ""
                color: Theme.accentStrong
                font.family: Theme.fontMono
                font.pixelSize: 12
                font.weight: Font.Medium
            }
            Item { Layout.fillWidth: true }
        }

        // ── Doc form ─────────────────────────────────────────────────────
        ColumnLayout {
            visible: root.kind === "doc"
            Layout.fillWidth: true
            Layout.leftMargin: 18; Layout.rightMargin: 18
            spacing: 10

            GridLayout {
                columns: 2; columnSpacing: 10; rowSpacing: 4; Layout.fillWidth: true
                FieldLabel { text: "REF / CODE" }
                FieldLabel { text: "VERSION" }
                FormField { id: docRef     ; mono: true; placeholderText: "TS 36.331"
                            text: root.draft.ref || ""    ; onTextChanged: root.draft.ref = text }
                FormField { id: docVersion ; mono: true; placeholderText: "v17.5.0"
                            text: root.draft.version || ""; onTextChanged: root.draft.version = text }
            }

            FieldLabel { text: "TITLE" }
            FormField { id: docTitle; placeholderText: "Title"
                        text: root.draft.title || ""; onTextChanged: root.draft.title = text
                        Layout.fillWidth: true }

            FieldLabel { text: "DESCRIPTION" }
            ScrollView {
                Layout.fillWidth: true; Layout.preferredHeight: 78
                TextArea {
                    id: docDesc
                    text: root.draft.desc || ""
                    onTextChanged: root.draft.desc = text
                    wrapMode: TextEdit.Wrap
                    color: Theme.text
                    placeholderText: "…"
                    placeholderTextColor: Theme.textDim
                    background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                }
            }

            FieldLabel { text: "URL" }
            FormField { id: docUrl; mono: true; placeholderText: "https://… или #/wiki/…"
                        text: root.draft.url || ""; onTextChanged: root.draft.url = text
                        Layout.fillWidth: true }

            GridLayout {
                columns: 2; columnSpacing: 10; rowSpacing: 4; Layout.fillWidth: true
                FieldLabel { text: "SOURCE" }
                FieldLabel { text: "UPDATED" }
                FormField { placeholderText: "ETSI, wiki.internal…"
                            text: root.draft.source || ""; onTextChanged: root.draft.source = text }
                FormField { placeholderText: "today, 2 weeks ago…"
                            text: root.draft.updated || ""; onTextChanged: root.draft.updated = text }
            }

            ColumnLayout {
                visible: root.isNew
                spacing: 4
                Layout.fillWidth: true
                FieldLabel { text: "SECTION" }
                ComboBox {
                    id: docSection
                    Layout.fillWidth: true
                    model: root.sections.map(s => s.title)
                    background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                    contentItem: Text { text: docSection.displayText; color: Theme.text; leftPadding: 10; verticalAlignment: Text.AlignVCenter }
                    onCurrentIndexChanged: {
                        if (currentIndex >= 0 && currentIndex < root.sections.length)
                            root.draft._sectionId = root.sections[currentIndex].id;
                    }
                    Component.onCompleted: {
                        const cur = root.draft._sectionId || root.sectionId;
                        for (let i = 0; i < root.sections.length; i++)
                            if (root.sections[i].id === cur) { currentIndex = i; break; }
                    }
                }
            }
        }

        // ── Snippet form ─────────────────────────────────────────────────
        ColumnLayout {
            visible: root.kind === "snippet"
            Layout.fillWidth: true
            Layout.leftMargin: 18; Layout.rightMargin: 18
            spacing: 10

            GridLayout {
                columns: 2; columnSpacing: 10; rowSpacing: 4; Layout.fillWidth: true
                FieldLabel { text: "TITLE" }
                FieldLabel { text: "LANGUAGE" }
                FormField {
                    placeholderText: "Build с sanitizers"
                    text: root.draft.title || ""
                    onTextChanged: root.draft.title = text
                }
                ComboBox {
                    Layout.fillWidth: true
                    model: ["sh", "cpp", "py", "js", "yaml", "text"]
                    background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
                    contentItem: Text { text: parent.displayText; color: Theme.text; leftPadding: 10; verticalAlignment: Text.AlignVCenter }
                    currentIndex: {
                        const idx = ["sh","cpp","py","js","yaml","text"].indexOf(root.draft.lang || "sh");
                        return Math.max(0, idx);
                    }
                    onCurrentTextChanged: root.draft.lang = currentText
                }
            }

            FieldLabel { text: "CODE" }
            ScrollView {
                Layout.fillWidth: true; Layout.preferredHeight: 240
                TextArea {
                    text: root.draft.code || ""
                    onTextChanged: root.draft.code = text
                    wrapMode: TextEdit.NoWrap
                    color: Theme.text
                    placeholderText: "// your snippet…"
                    placeholderTextColor: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                    background: Rectangle { radius: 6; color: Theme.bg2; border.color: Theme.border; border.width: 1 }
                }
            }
        }

        // ── Section form ─────────────────────────────────────────────────
        ColumnLayout {
            visible: root.kind === "section"
            Layout.fillWidth: true
            Layout.leftMargin: 18; Layout.rightMargin: 18
            spacing: 10

            FieldLabel { text: "TITLE" }
            FormField {
                placeholderText: "3GPP / ETSI Standards"
                text: root.draft.title || ""
                onTextChanged: root.draft.title = text
            }

            FieldLabel { text: "SUBTITLE" }
            FormField {
                placeholderText: "External — LTE / E-UTRAN protocol specifications"
                text: root.draft.subtitle || ""
                onTextChanged: root.draft.subtitle = text
            }

            FieldLabel { text: "ACCENT COLOR" }
            Row {
                spacing: 6
                Repeater {
                    model: root.accentPalette
                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        width: 24; height: 24; radius: 12
                        color: modelData
                        border.color: String(root.draft.accent || "").toLowerCase() === modelData.toLowerCase()
                                      ? Theme.text : Theme.border
                        border.width: 2
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.draft.accent = modelData
                        }
                    }
                }
            }
        }

        // ── Contact form ─────────────────────────────────────────────────
        ColumnLayout {
            visible: root.kind === "contact"
            Layout.fillWidth: true
            Layout.leftMargin: 18; Layout.rightMargin: 18
            spacing: 10

            GridLayout {
                columns: 2; columnSpacing: 10; rowSpacing: 4; Layout.fillWidth: true
                FieldLabel { text: "NAME" }
                FieldLabel { text: "ROLE" }
                FormField { placeholderText: "Иван Иванов"
                            text: root.draft.name || ""; onTextChanged: root.draft.name = text }
                FormField { placeholderText: "Tech Lead / QA / PHY team…"
                            text: root.draft.role || ""; onTextChanged: root.draft.role = text }
                FieldLabel { text: "SLACK CHANNEL" }
                FieldLabel { text: "SLACK HANDLE" }
                FormField { mono: true; placeholderText: "#lte-core"
                            text: root.draft.channel || ""; onTextChanged: root.draft.channel = text }
                FormField { mono: true; placeholderText: "@name.surname"
                            text: root.draft.slack || ""; onTextChanged: root.draft.slack = text }
            }

            FieldLabel { text: "AVATAR COLOR" }
            Row {
                spacing: 6
                Repeater {
                    model: root.contactPalette
                    delegate: Rectangle {
                        required property string modelData
                        required property int index
                        width: 24; height: 24; radius: 12
                        color: modelData
                        border.color: root.draft.color === modelData ? Theme.text : Theme.border
                        border.width: 2
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.draft.color = modelData
                        }
                    }
                }
            }
        }

        // ── Actions ──────────────────────────────────────────────────────
        RowLayout {
            Layout.leftMargin: 18; Layout.rightMargin: 18
            Layout.topMargin: 6; Layout.bottomMargin: 16
            Layout.fillWidth: true
            spacing: 8
            PillButton {
                visible: !root.isNew
                text: "Удалить"; danger: true
                onClicked: {
                    if (root.kind === "doc")          root.deletedDoc();
                    else if (root.kind === "snippet") root.deletedSnippet();
                    else if (root.kind === "contact") root.deletedContact();
                    else if (root.kind === "section") root.deletedSection();
                    root.close();
                }
            }
            Item { Layout.fillWidth: true }
            PillButton { text: "Отмена"; onClicked: root.close() }
            PillButton {
                text: root.isNew ? "Создать" : "Сохранить"
                primary: true
                onClicked: {
                    // Validation
                    if (root.kind === "doc" && (!root.draft.title || !String(root.draft.title).trim().length)) return;
                    if (root.kind === "snippet" && (!root.draft.title || !String(root.draft.title).trim().length)) return;
                    if (root.kind === "contact" && (!root.draft.name || !String(root.draft.name).trim().length)) return;
                    if (root.kind === "section" && (!root.draft.title || !String(root.draft.title).trim().length)) return;

                    const out = Object.assign({}, root.draft);
                    if (root.kind === "doc")          root.savedDoc(out);
                    else if (root.kind === "snippet") root.savedSnippet(out);
                    else if (root.kind === "contact") root.savedContact(out);
                    else if (root.kind === "section") root.savedSection(out);
                    root.close();
                }
            }
        }
    }

    component FieldLabel: Text {
        color: Theme.textMuted
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 1
        topPadding: 2
    }

    component FormField: TextField {
        property bool mono: false
        Layout.fillWidth: true
        color: Theme.text
        placeholderTextColor: Theme.textDim
        font.family: mono ? Theme.fontMono : Theme.fontUi
        background: Rectangle { radius: 6; color: Theme.panel2; border.color: Theme.border; border.width: 1 }
    }
}
