// Rendered markdown — one delegate per drawn row.
//
// Replaces a read-only TextArea with textFormat: MarkdownText, which handed
// the whole document to Qt and gave nothing back: no say in how anything
// looked, and no way to ask which part of the source produced what. Here each
// row knows the lines it came from, so clicking one can move the caret, and a
// code block can be drawn as a code block rather than as indented text.
//
// Rows are flat. A quote holding a list holding a paragraph is one row that
// knows how deep it sits, which is what keeps the list virtualised: a note
// with two thousand task items draws the dozen on screen.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Basic
import TodoCpp

ListView {
    id: view

    // MdDocument instance. Its model drives this view.
    required property var document
    // The editor's QQuickTextDocument. A checkbox click writes through it, so
    // the change joins the editor's undo stack instead of arriving from the
    // side. Null in a preview with no editor: the boxes then do not toggle.
    property var editorDocument: null

    // Emitted when a row is activated (double-click, or Alt+click), with the
    // first source line it came from — the editor uses this to put the caret
    // where the reader was looking.
    signal sourceRequested(int line)
    // A checkbox was clicked and the source has been rewritten. The editor
    // listens so it can keep the caret where the reader left it.
    signal taskToggled()
    // A heap:// link, already split into kind ("note", "task", "person",
    // "tag", "fn") and target.
    signal internalLinkActivated(string kind, string target)

    model: document ? document.model : null
    clip: true
    spacing: 0
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ThinScrollBar {}

    // Row types, mirroring MdBlockModel::RowType. QML has no access to the
    // C++ enum without registering it, and these never change independently.
    readonly property int tParagraph: 0
    readonly property int tHeading: 1
    readonly property int tCode: 2
    readonly property int tTable: 3
    readonly property int tRule: 4
    readonly property int tImage: 5
    readonly property int tMath: 6
    readonly property int tHtml: 7
    readonly property int tFrontmatter: 8
    readonly property int tCalloutHeader: 9
    readonly property int tFootnoteHeading: 10
    readonly property int tFootnoteDef: 11
    readonly property int tBlank: 12

    // Indent per list level and per quote level, in pixels.
    readonly property int indentStep: 22
    readonly property int quoteStep: 14
    readonly property int sideMargin: 24

    function _handleLink(link, line) {
        if (link.startsWith("heap://")) {
            const rest = link.substring(7);
            const slash = rest.indexOf("/");
            if (slash > 0) {
                view.internalLinkActivated(rest.substring(0, slash),
                                           decodeURIComponent(rest.substring(slash + 1)));
                return;
            }
        }
        Qt.openUrlExternally(link);
    }

    // Colour for a callout kind. Unknown kinds fall back to the accent, so a
    // note using "[!SOMETHING]" still renders as a callout rather than losing
    // its frame.
    // Reuses the priority and status colours the rest of the app already
    // speaks, so a warning in a note is the same red as a blocked task.
    function _calloutColor(kind) {
        switch (kind) {
        case "warning": case "caution": case "attention": return Theme.p1;
        case "danger": case "error": case "bug": return Theme.stBlocked;
        case "tip": case "success": case "done": case "check": return Theme.stDone;
        default: return Theme.accent;
        }
    }

    delegate: Item {
        id: rowItem
        width: view.width
        implicitHeight: content.implicitHeight + content.anchors.topMargin + content.anchors.bottomMargin

        required property int index
        required property var model

        // Quote bars are drawn per row rather than around a group, so a quote
        // that contains several blocks shows one continuous bar.
        Row {
            anchors.left: parent.left
            anchors.leftMargin: view.sideMargin
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: view.quoteStep - 3
            Repeater {
                model: rowItem.model.quoteDepth
                Rectangle {
                    width: 3
                    height: rowItem.height
                    radius: 1.5
                    color: rowItem.model.calloutKind
                           ? view._calloutColor(rowItem.model.calloutKind)
                           : Theme.border
                }
            }
        }

        Loader {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: view.sideMargin
                                + rowItem.model.quoteDepth * view.quoteStep
                                + rowItem.model.indent * view.indentStep
            anchors.rightMargin: view.sideMargin
            anchors.topMargin: rowItem.model.rowType === view.tHeading
                               ? (rowItem.model.level <= 2 ? 18 : 12)
                               : (rowItem.model.loose ? 8 : 4)
            anchors.bottomMargin: rowItem.model.rowType === view.tHeading ? 6 : 4
            anchors.top: parent.top

            sourceComponent: {
                switch (rowItem.model.rowType) {
                case view.tHeading: return headingRow;
                case view.tCode: return codeRow;
                case view.tTable: return tableRow;
                case view.tRule: return ruleRow;
                case view.tImage: return imageRow;
                case view.tMath: return mathRow;
                case view.tHtml: return rawRow;
                case view.tFrontmatter: return frontmatterRow;
                case view.tCalloutHeader: return calloutHeaderRow;
                case view.tFootnoteHeading: return footnoteHeadingRow;
                case view.tFootnoteDef: return footnoteDefRow;
                case view.tBlank: return blankRow;
                default: return paragraphRow;
                }
            }
        }

        // Double-click anywhere on a row jumps the editor to its source.
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onDoubleTapped: view.sourceRequested(rowItem.model.firstLine)
        }

        // ── Row components ──────────────────────────────────────────────

        Component {
            id: paragraphRow
            RowLayout {
                spacing: 8
                // List marker or checkbox, drawn beside the text rather than in it
                // so wrapped lines line up under the first word.
                Loader {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 2
                    active: rowItem.model.marker !== "" || rowItem.model.taskState >= 0
                    sourceComponent: rowItem.model.taskState >= 0 ? taskBox : bulletLabel
                }
                TextEdit {
                    id: body
                    objectName: "mdParagraph"
                    Layout.fillWidth: true
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.RichText
                    text: rowItem.model.html
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.pixelSize: 14
                    onLinkActivated: (link) => view._handleLink(link, rowItem.model.firstLine)
                }
            }
        }

        Component {
            id: bulletLabel
            Text {
                objectName: "mdMarker"
                text: rowItem.model.marker
                color: Theme.textDim
                font.family: Theme.fontUi
                font.pixelSize: 14
            }
        }

        Component {
            id: taskBox
            Rectangle {
                objectName: "mdTaskBox"
                width: 14
                height: 14
                radius: 3
                border.width: 1.5
                border.color: rowItem.model.taskState === 1 ? Theme.stDone : Theme.border
                color: rowItem.model.taskState === 1 ? Theme.stDone : "transparent"
                Text {
                    anchors.centerIn: parent
                    visible: rowItem.model.taskState === 1
                    text: "✓"
                    color: Theme.bg
                    font.pixelSize: 10
                    font.bold: true
                }

                // Ticking a box here rewrites exactly one character of the
                // note. The edit goes through the editor's own cursor, so it
                // lands on the undo stack and the caret stays where the reader
                // left it.
                MouseArea {
                    objectName: "mdTaskClick"
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        // The write goes into the editor's own document, in one
                        // edit block, so Ctrl+Z takes the whole change back.
                        if (view.editorDocument && view.document.toggleTask(view.editorDocument, rowItem.index))
                            view.taskToggled();
                    }
                }
            }
        }

        Component {
            id: headingRow
            ColumnLayout {
                spacing: 4
                TextEdit {
                    objectName: "mdHeading"
                    Layout.fillWidth: true
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.RichText
                    text: rowItem.model.html
                    color: Theme.text
                    font.family: Theme.fontUi
                    font.bold: rowItem.model.level <= 3
                    // Relative sizes, so the hierarchy reads at a glance without
                    // any level becoming shouty.
                    font.pixelSize: [24, 20, 17, 15, 14, 13][Math.min(rowItem.model.level, 6) - 1]
                    onLinkActivated: (link) => view._handleLink(link, rowItem.model.firstLine)
                }
                // A rule under the top two levels, the way a document separates
                // its major sections.
                Rectangle {
                    visible: rowItem.model.level <= 2
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    height: 1
                    color: Theme.border
                }
            }
        }

        Component {
            id: codeRow
            Rectangle {
                objectName: "mdCode"
                implicitHeight: codeColumn.implicitHeight
                color: Theme.panel
                radius: 6
                border.width: 1
                border.color: Theme.border

                ColumnLayout {
                    id: codeColumn
                    anchors.fill: parent
                    spacing: 0

                    // Header appears only when there is something to say.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: 8
                        Layout.bottomMargin: 0
                        visible: rowItem.model.language !== "" || codeHover.hovered
                        spacing: 8
                        Text {
                            objectName: "mdCodeLanguage"
                            text: rowItem.model.isDiagram
                                  ? I18n.t("notes.code.diagram").arg(rowItem.model.language)
                                  : rowItem.model.language
                            color: Theme.textDim
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            objectName: "mdCodeCopy"
                            text: copyArea.copied ? I18n.t("notes.code.copied") : I18n.t("notes.code.copy")
                            color: copyArea.containsMouse ? Theme.accent : Theme.textDim
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                            MouseArea {
                                id: copyArea
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                property bool copied: false
                                onClicked: {
                                    clipboardHelper.text = rowItem.model.code;
                                    clipboardHelper.selectAll();
                                    clipboardHelper.copy();
                                    copied = true;
                                    resetTimer.restart();
                                }
                                Timer {
                                    id: resetTimer
                                    interval: 1200
                                    onTriggered: copyArea.copied = false
                                }
                            }
                        }
                    }

                    // Horizontal scroll rather than wrapping: wrapped code lies
                    // about its own indentation.
                    Flickable {
                        Layout.fillWidth: true
                        Layout.margins: 8
                        Layout.topMargin: 4
                        implicitHeight: codeText.implicitHeight
                        contentWidth: codeText.implicitWidth
                        contentHeight: codeText.implicitHeight
                        clip: true
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds

                        TextEdit {
                            id: codeText
                            objectName: "mdCodeBody"
                            readOnly: true
                            selectByMouse: true
                            textFormat: TextEdit.PlainText
                            text: rowItem.model.code
                            color: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: 13
                            CodeHighlighter {
                                target: codeText.textDocument
                                language: rowItem.model.language
                            }
                        }
                    }
                }

                HoverHandler { id: codeHover }
                // Off-screen, purely to reach the clipboard.
                TextEdit { id: clipboardHelper; visible: false }
            }
        }

        Component {
            id: tableRow
            Flickable {
                objectName: "mdTable"
                implicitHeight: grid.implicitHeight + 2
                contentWidth: Math.max(grid.implicitWidth, width)
                contentHeight: grid.implicitHeight
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds

                GridLayout {
                    id: grid
                    columns: Math.max(1, rowItem.model.tableColumns)
                    rowSpacing: 0
                    columnSpacing: 0

                    Repeater {
                        model: rowItem.model.tableCells
                        Rectangle {
                            required property int index
                            required property string modelData
                            readonly property bool isHeader: index < rowItem.model.tableHeaderCells
                            readonly property int column: index % Math.max(1, rowItem.model.tableColumns)

                            Layout.fillWidth: true
                            Layout.minimumWidth: cellText.implicitWidth + 24
                            implicitHeight: cellText.implicitHeight + 14
                            color: isHeader ? Theme.panel : "transparent"
                            border.width: 1
                            border.color: Theme.border

                            TextEdit {
                                id: cellText
                                anchors.fill: parent
                                anchors.margins: 7
                                readOnly: true
                                selectByMouse: true
                                textFormat: TextEdit.RichText
                                text: parent.modelData
                                color: Theme.text
                                font.family: Theme.fontUi
                                font.pixelSize: 13
                                font.bold: parent.isHeader
                                // 0 default, 1 left, 2 centre, 3 right.
                                horizontalAlignment: {
                                    const a = rowItem.model.tableAlign[parent.column];
                                    if (a === 2) return Text.AlignHCenter;
                                    if (a === 3) return Text.AlignRight;
                                    return Text.AlignLeft;
                                }
                                onLinkActivated: (link) => view._handleLink(link, rowItem.model.firstLine)
                            }
                        }
                    }
                }
            }
        }

        Component {
            id: ruleRow
            Item {
                objectName: "mdRule"
                implicitHeight: 17
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 1
                    color: Theme.border
                }
            }
        }

        Component {
            id: imageRow
            ColumnLayout {
                spacing: 4
                Loader {
                    Layout.fillWidth: true
                    // A remote image is not loaded until the reader asks. heap
                    // makes no network requests of its own, and an image in a note
                    // would make one to a host the note's author chose.
                    sourceComponent: (rowItem.model.imageIsRemote && !view.document.allowRemoteImages)
                                     ? remoteImagePlaceholder : localImage
                }
            }
        }

        Component {
            id: localImage
            Image {
                objectName: "mdImage"
                source: rowItem.model.imageSource
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignLeft
                // Never upscale past the natural size, never overflow the pane.
                sourceSize.width: Math.min(implicitWidth > 0 ? implicitWidth : width, width)
                Text {
                    anchors.centerIn: parent
                    visible: parent.status === Image.Error
                    text: I18n.t("notes.image.missing")
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                }
            }
        }

        Component {
            id: remoteImagePlaceholder
            Rectangle {
                objectName: "mdRemoteImage"
                implicitHeight: 44
                color: Theme.panel
                radius: 6
                border.width: 1
                border.color: Theme.border
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        text: I18n.t("notes.image.remote").arg(rowItem.model.imageSource)
                        color: Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                    }
                    Text {
                        text: I18n.t("notes.image.open")
                        color: openArea.containsMouse ? Theme.accent : Theme.textDim
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        MouseArea {
                            id: openArea
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            onClicked: Qt.openUrlExternally(rowItem.model.imageSource)
                        }
                    }
                }
            }
        }

        Component {
            id: mathRow
            Rectangle {
                objectName: "mdMath"
                implicitHeight: mathText.implicitHeight + 20
                color: Theme.panel
                radius: 6
                border.width: 1
                border.color: Theme.border
                Text {
                    id: mathText
                    anchors.fill: parent
                    anchors.margins: 10
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    // Nothing typesets maths in this build, so the source is shown
                    // rather than dropped or drawn wrongly.
                    text: rowItem.model.code
                    color: Theme.text
                    font.family: Theme.fontMono
                    font.pixelSize: 13
                }
            }
        }

        Component {
            id: rawRow
            Rectangle {
                objectName: "mdHtml"
                implicitHeight: rawText.implicitHeight + 16
                color: Theme.panel
                radius: 6
                border.width: 1
                border.color: Theme.border
                Text {
                    id: rawText
                    anchors.fill: parent
                    anchors.margins: 8
                    wrapMode: Text.Wrap
                    // Shown as source, never interpreted: a note is not a web page.
                    textFormat: Text.PlainText
                    text: rowItem.model.code
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                }
            }
        }

        Component {
            id: frontmatterRow
            Rectangle {
                objectName: "mdFrontmatter"
                implicitHeight: fmText.implicitHeight + 16
                color: "transparent"
                radius: 6
                border.width: 1
                border.color: Theme.border
                Text {
                    id: fmText
                    anchors.fill: parent
                    anchors.margins: 8
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: rowItem.model.code
                    color: Theme.textDim
                    font.family: Theme.fontMono
                    font.pixelSize: 12
                }
            }
        }

        Component {
            id: calloutHeaderRow
            RowLayout {
                objectName: "mdCallout"
                spacing: 8
                Text {
                    text: {
                        switch (rowItem.model.calloutKind) {
                        case "warning": case "caution": case "attention": return "⚠";
                        case "danger": case "error": case "bug": return "✕";
                        case "tip": case "success": case "done": case "check": return "✓";
                        case "question": case "help": case "faq": return "?";
                        default: return "ⓘ";
                        }
                    }
                    color: view._calloutColor(rowItem.model.calloutKind)
                    font.pixelSize: 14
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    text: rowItem.model.calloutTitle
                    color: view._calloutColor(rowItem.model.calloutKind)
                    font.family: Theme.fontUi
                    font.pixelSize: 14
                    font.bold: true
                    elide: Text.ElideRight
                }
            }
        }

        Component {
            id: footnoteHeadingRow
            ColumnLayout {
                spacing: 6
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.border }
                Text {
                    objectName: "mdFootnoteHeading"
                    text: I18n.t("notes.footnotes")
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    font.bold: true
                }
            }
        }

        Component {
            id: footnoteDefRow
            RowLayout {
                objectName: "mdFootnoteDef"
                spacing: 8
                Text {
                    Layout.alignment: Qt.AlignTop
                    text: rowItem.model.footnoteNumber > 0
                          ? rowItem.model.footnoteNumber + "."
                          : rowItem.model.footnoteId + "."
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                }
                TextEdit {
                    Layout.fillWidth: true
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.RichText
                    text: rowItem.model.html
                    color: Theme.textDim
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    onLinkActivated: (link) => view._handleLink(link, rowItem.model.firstLine)
                }
            }
        }

        Component {
            id: blankRow
            // Source that draws nothing — a link reference definition. The row
            // exists so every line still maps to something.
            Item { objectName: "mdBlank"; implicitHeight: 0 }
        }
    }

}
