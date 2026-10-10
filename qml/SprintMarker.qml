import QtQuick
import QtQuick.Controls
import TodoCpp

// The end of a Jira sprint (APP-255), drawn where a day is: on the week and
// the month at the sprint's last day, and as a heading in the list. A fact
// from the last pull and nothing more — it moves nothing, plans nothing and
// writes nothing to the sprint.
//
//   SprintMarker { sprint: AppController.sprintMarkers(from, to)[0] }
//
// `sprint` is one entry of AppController.sprintMarkers(): {name, state,
// start, end, endDay, tasks}. `rule` draws a hairline down the left edge for
// the full height the parent gives the marker (a day column); without it the
// marker is a single chip.
Item {
    id: root

    property var sprint: ({})
    property bool rule: false
    // The chip only, no rule and no name: for a cell too small for text.
    property bool compact: false

    readonly property string sprintName: sprint && sprint.name ? String(sprint.name) : ""
    readonly property string tipText: {
        if (sprintName.length === 0) return "";
        const end = sprint.end ? I18n.fmtDate(new Date(sprint.end), "weekdayDay") : "";
        let s = I18n.t("sprint.tip").replace("%1", sprintName).replace("%2", end);
        if (sprint.tasks > 0) s += " · " + I18n.count(sprint.tasks, "sprint.cards");
        return s;
    }

    visible: sprintName.length > 0
    implicitWidth: compact ? Theme.spSm : chip.implicitWidth
    implicitHeight: compact ? Theme.spSm : Theme.chipHSmall

    Accessible.role: Accessible.StaticText
    Accessible.name: tipText

    Rectangle {
        id: line
        visible: root.rule && !root.compact
        x: 0
        y: 0
        width: 2
        height: root.height
        color: Theme.accent
        opacity: 0.7
    }

    Rectangle {
        id: chip
        visible: !root.compact
        x: root.rule ? line.width : 0
        height: Theme.chipHSmall
        radius: Theme.radiusSm
        color: Theme.accentSoft
        implicitWidth: label.implicitWidth + Theme.spMd * 2
        width: Math.min(implicitWidth, root.width > 0 ? root.width - x : implicitWidth)

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            x: Theme.spMd
            width: parent.width - Theme.spMd * 2
            text: I18n.t("sprint.marker").replace("%1", root.sprintName)
            color: Theme.text
            font.pixelSize: Theme.fsXs
            elide: Text.ElideRight
        }
    }

    Rectangle {
        visible: root.compact
        anchors.centerIn: parent
        width: Theme.spSm
        height: Theme.spSm
        radius: width / 2
        color: Theme.accent
    }

    HoverHandler { id: hover }

    ToolTip.visible: hover.hovered && root.tipText.length > 0
    ToolTip.delay: 400
    ToolTip.text: root.tipText
}
