import QtQuick

// A revision counter for a view that rebuilds a snapshot when a model changes
// (APP-203). Bumping `rev` re-runs every binding that reads it, so a sync that
// changed forty cards used to rebuild the week forty times in a row, ~170 ms
// each on a 2k-task profile, while whatever was moving on screen waited.
//
// The first change still bumps at once, so a single edit shows in the frame it
// was made in. Any more before the next turn of the event loop are folded into
// one bump then. A Timer rather than Qt.callLater: it goes away with the view,
// where a deferred call outlived a view closed mid-burst and ran on nothing.
QtObject {
    id: tick

    property int rev: 0

    property bool _pending: false

    readonly property Timer _settle: Timer {
        interval: 0
        onTriggered: {
            if (tick._pending) {
                tick._pending = false;
                tick.rev++;
                tick._settle.restart();
            }
        }
    }

    function bump() {
        if (tick._settle.running) {
            tick._pending = true;
            return;
        }
        tick.rev++;
        tick._settle.start();
    }
}
