pragma Singleton
import QtQuick
import TodoCpp

// What each integration card's actions are doing, by integration id (design
// audit DES-5): which requests are waiting on the provider, the last error it
// answered with, and when the last sync came back. "Sync now" and "Test
// connection" used to stay clickable while the request ran, and a failure
// lived only in a toast that was gone in three seconds.
//
// A singleton, not state on the Settings view: the view and its cards are
// rebuilt whenever the user moves around, and an answer that arrives in
// between (or from an auto-sync) should still be on the card afterwards.
// Filled from AppController.integrationActionFinished.
QtObject {
    id: activity

    // id -> { busy: { sync|test|oauth|signin: started ms }, error, errorAt, syncedAt }
    property var states: ({})

    // Longest a button stays busy with no answer. The browser sign-in has its
    // own timeouts (3 min, 14 for a device code) that do answer; this is only
    // a backstop so a lost reply can't leave a card stuck.
    readonly property var busyLimitMs: ({ sync: 120000, test: 120000, signin: 120000, oauth: 900000 })

    readonly property bool anyBusy: {
        const keys = Object.keys(activity.states)
        for (let i = 0; i < keys.length; ++i)
            if (Object.keys(activity.states[keys[i]].busy || {}).length > 0) return true
        return false
    }

    function patch(key, fields) {
        const m = Object.assign({}, activity.states)
        m[key] = Object.assign({}, m[key] || {}, fields)
        activity.states = m
    }
    // Call before the request: some answers arrive synchronously.
    function start(key: string, action: string) {
        const busy = Object.assign({}, (activity.states[key] || {}).busy || {})
        busy[action] = Date.now()
        activity.patch(key, { busy: busy })
    }
    function finish(key: string, action: string, ok: bool, message: string) {
        const busy = Object.assign({}, (activity.states[key] || {}).busy || {})
        delete busy[action]
        const fields = { busy: busy }
        if (ok) {
            fields.error = ""
            if (action === "sync") fields.syncedAt = new Date()
        } else if (message.length > 0) {
            fields.error = message
            fields.errorAt = new Date()
        }
        activity.patch(key, fields)
    }
    // A deliberate disconnect starts the card over.
    function clear(key: string) {
        const m = Object.assign({}, activity.states)
        delete m[key]
        activity.states = m
    }
    // Frees whatever has been busy longer than its limit. Not an answer, so
    // it leaves no error behind.
    function expire(now: double) {
        const keys = Object.keys(activity.states)
        for (let i = 0; i < keys.length; ++i) {
            const busy = activity.states[keys[i]].busy || {}
            const acts = Object.keys(busy)
            for (let j = 0; j < acts.length; ++j) {
                if (now - busy[acts[j]] > (activity.busyLimitMs[acts[j]] || 120000))
                    activity.finish(keys[i], acts[j], false, "")
            }
        }
    }

    property Connections _results: Connections {
        target: AppController
        function onIntegrationActionFinished(provider, action, ok, message) {
            activity.finish(provider, action, ok, message)
        }
    }
    property Timer _backstop: Timer {
        interval: 5000
        repeat: true
        running: activity.anyBusy
        onTriggered: activity.expire(Date.now())
    }
}
