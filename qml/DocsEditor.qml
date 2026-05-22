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

    // Dimmed backdrop so the underlying app stays visible behind the popup.
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.55) }

    property string kind: "doc"          // doc | snippet | contact | section
    property bool   isNew: false
    property string sectionId: ""        // for doc / section (=original id)
    property string originalRef: ""      // for doc rename / move
    property int    idx: -1              // for snippet / contact
    property var    sections: []
    property var    contactPalette: []
    property var    accentPalette: []    // for section
    property var    docCustomFields: [] // for doc — schema from the section
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
                text: root.kind === "doc" ? I18n.t(root.isNew ? "docs.editor.title.new.doc" : "docs.editor.title.edit.doc")
                    : root.kind === "snippet" ? I18n.t(root.isNew ? "docs.editor.title.new.snip" : "docs.editor.title.edit.snip")
                        : root.kind === "section" ? I18n.t(root.isNew ? "docs.editor.title.new.section" : "docs.editor.title.edit.section")
                            : I18n.t(root.isNew ? "docs.editor.title.new.contact" : "docs.editor.title.edit.contact")
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
            FormField {
                id: docUrl; mono: true; placeholderText: I18n.t("docs.editor.url.ph")
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

            // Custom fields defined on the section
            ColumnLayout {
                visible: root.docCustomFields && root.docCustomFields.length > 0
                Layout.fillWidth: true
                spacing: 4
                FieldLabel { text: "CUSTOM FIELDS" }
                Repeater {
                    model: root.docCustomFields
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 6
                        Text {
                            Layout.preferredWidth: 110
                            text: modelData.label || modelData.key
                            color: Theme.textMuted
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                        FormField {
                            placeholderText: modelData.key
                            text: (root.draft.extra && root.draft.extra[modelData.key]) ? root.draft.extra[modelData.key] : ""
                            onTextChanged: {
                                if (!root.draft.extra) root.draft.extra = ({});
                                root.draft.extra[modelData.key] = text;
                            }
                        }
                    }
                }
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
                    placeholderText: I18n.t("docs.editor.build.ph")
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
                    id: codeArea
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
            CodeHighlighter {
                target: codeArea.textDocument
                language: root.draft.lang || "text"
                palette: ({
                    keyword: Theme.accent,
                    string:  Theme.p2,
                    comment: Theme.textDim,
                    number:  Theme.mFocus,
                    type:    Theme.mSync,
                    builtin: Theme.mOneone
                })
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

            // ── Custom fields list ──────────────────────────────────────
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border; Layout.topMargin: 10 }
            FieldLabel {
                text: I18n.t("docs.editor.fields.label")
            }

            ColumnLayout {
                id: fieldsList
                Layout.fillWidth: true
                spacing: 6
                property int rev: 0
                function notify() { rev++; root.draft.customFields = (root.draft.customFields || []).slice() }
                Repeater {
                    model: (root.draft.customFields || []).length
                    delegate: RowLayout {
                        required property int index
                        Layout.fillWidth: true
                        spacing: 6
                        property var fld: (root.draft.customFields || [])[index] || ({ key: "", label: "" })
                        FormField {
                            Layout.fillWidth: true
                            placeholderText: "label"
                            text: parent.fld.label || ""
                            onTextChanged: {
                                if (!root.draft.customFields) return;
                                const list = root.draft.customFields.slice();
                                if (!list[parent.index]) return;
                                list[parent.index] = Object.assign({}, list[parent.index], { label: text });
                                root.draft.customFields = list;
                            }
                        }
                        FormField {
                            mono: true
                            Layout.preferredWidth: 140
                            placeholderText: "key"
                            text: parent.fld.key || ""
                            onTextChanged: {
                                if (!root.draft.customFields) return;
                                const list = root.draft.customFields.slice();
                                if (!list[parent.index]) return;
                                list[parent.index] = Object.assign({}, list[parent.index], { key: text.toLowerCase().replace(/[^a-z0-9_]+/g, "_") });
                                root.draft.customFields = list;
                            }
                        }
                        Rectangle {
                            width: 26; height: 26; radius: 5
                            color: upMA.containsMouse ? Theme.panel3 : Theme.panel2
                            border.color: Theme.border; border.width: 1
                            Text { anchors.centerIn: parent; text: "↑"; color: Theme.textMuted; font.pixelSize: 12 }
                            MouseArea {
                                id: upMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const i = parent.parent.index;
                                    if (i <= 0) return;
                                    const list = root.draft.customFields.slice();
                                    const t = list[i]; list[i] = list[i-1]; list[i-1] = t;
                                    root.draft.customFields = list;
                                }
                            }
                        }
                        Rectangle {
                            width: 26; height: 26; radius: 5
                            color: dnMA.containsMouse ? Theme.panel3 : Theme.panel2
                            border.color: Theme.border; border.width: 1
                            Text { anchors.centerIn: parent; text: "↓"; color: Theme.textMuted; font.pixelSize: 12 }
                            MouseArea {
                                id: dnMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const i = parent.parent.index;
                                    const cur = root.draft.customFields || [];
                                    if (i >= cur.length - 1) return;
                                    const list = cur.slice();
                                    const t = list[i]; list[i] = list[i+1]; list[i+1] = t;
                                    root.draft.customFields = list;
                                }
                            }
                        }
                        Rectangle {
                            width: 26; height: 26; radius: 5
                            color: delFMA.containsMouse ? Theme.withAlpha(Theme.p0, 0.16) : Theme.panel2
                            border.color: delFMA.containsMouse ? Theme.p0 : Theme.border; border.width: 1
                            Text { anchors.centerIn: parent; text: "×"; color: delFMA.containsMouse ? Theme.p0 : Theme.textMuted; font.pixelSize: 13 }
                            MouseArea {
                                id: delFMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const i = parent.parent.index;
                                    const list = (root.draft.customFields || []).slice();
                                    list.splice(i, 1);
                                    root.draft.customFields = list;
                                }
                            }
                        }
                    }
                }
            }

            PillButton {
                text: I18n.t("docs.editor.addField")
                onClicked: {
                    const list = (root.draft.customFields || []).slice();
                    let base = "field"; let key = base; let n = 2;
                    while (list.some(function (f) { return f.key === key; })) { key = base + "_" + n; n++; }
                    list.push({ key: key, label: "Field " + list.length });
                    root.draft.customFields = list;
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
                FormField {
                    placeholderText: I18n.t("docs.editor.ph.fullName")
                            text: root.draft.name || ""; onTextChanged: root.draft.name = text }
                FormField { placeholderText: "Tech Lead / QA / PHY team…"
                            text: root.draft.role || ""; onTextChanged: root.draft.role = text }
                FieldLabel { text: "MATTERMOST CHANNEL" }
                FieldLabel { text: "MATTERMOST HANDLE" }
                FormField { mono: true; placeholderText: "#lte-core"
                            text: root.draft.channel || ""; onTextChanged: root.draft.channel = text }
                FormField { mono: true; placeholderText: "@name.surname"
                            text: root.draft.mattermost || ""; onTextChanged: root.draft.mattermost = text }
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
                text: I18n.t("common.delete"); danger: true
                onClicked: {
                    if (root.kind === "doc")          root.deletedDoc();
                    else if (root.kind === "snippet") root.deletedSnippet();
                    else if (root.kind === "contact") root.deletedContact();
                    else if (root.kind === "section") root.deletedSection();
                    root.close();
                }
            }
            Item { Layout.fillWidth: true }
            PillButton {
                text: I18n.t("common.cancel"); onClicked: root.close()
            }
            PillButton {
                text: root.isNew ? I18n.t("editor.btn.create") : I18n.t("editor.btn.save")
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
