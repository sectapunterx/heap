// APP-177 / APP-178: Settings → Appearance → Sound. One switch, off by
// default, and under it the volume and the meeting chimes (on, at 15, 10 and
// 5 minutes). What the rows write is what AppController reads: sound.enabled,
// sound.volume, sound.meetingChimes, sound.meetingChimeMinutes (latest first).
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "SoundSettings"
    when: windowShown
    visible: true
    width: 900
    height: 700

    Item { id: host; anchors.fill: parent }

    property string savedSettings: ""

    function initTestCase() { tc.savedSettings = AppController.appSettingsJson; }
    function cleanup() { AppController.appSettingsJson = tc.savedSettings; }

    function stored() {
        try { return (JSON.parse(AppController.appSettingsJson || "{}") || {}).sound || {}; } catch (e) { return {}; }
    }

    function clearSound() {
        let s = {};
        try { s = JSON.parse(AppController.appSettingsJson || "{}") || {}; } catch (e) { s = {}; }
        delete s.sound;
        if (s.appearance) delete s.appearance.completionSound;
        AppController.appSettingsJson = JSON.stringify(s);
    }

    function openAppearance() {
        const sv = createTemporaryQmlObject('import TodoCpp; SettingsView { anchors.fill: parent }', host);
        verify(sv !== null);
        sv.activeSection = "appearance";
        tryVerify(function () { return findChild(sv, "settings-sound-enabled") !== null; }, 2000);
        return sv;
    }

    function test_off_by_default_with_nothing_under_it() {
        clearSound();
        const sv = openAppearance();
        const row = findChild(sv, "settings-sound-enabled");
        verify(!row.checked, "sound is on for a profile that never chose it");
        verify(!findChild(sv, "settings-sound-volume").visible);
        verify(!findChild(sv, "settings-sound-meeting").visible);
        compare(sv.defaults.sound.enabled, false);
        compare(sv.defaults.sound.meetingChimes, true);
        compare(JSON.stringify(sv.defaults.sound.meetingChimeMinutes), "[15,10,5]");
    }

    function test_switching_on_stores_it_and_shows_the_rest() {
        clearSound();
        const sv = openAppearance();
        const row = findChild(sv, "settings-sound-enabled");
        row.toggled(true);
        compare(stored().enabled, true);
        tryVerify(function () { return findChild(sv, "settings-sound-volume").visible; }, 1000);
        const vol = findChild(sv, "settings-sound-volume");
        compare(Math.round(vol.value), 55);
        vol.moved(30);
        compare(stored().volume, 30);
        const chimes = findChild(sv, "settings-sound-meeting");
        verify(chimes.visible && chimes.checked);
        verify(findChild(sv, "settings-sound-meeting-minutes").visible);
        chimes.toggled(false);
        compare(stored().meetingChimes, false);
        tryVerify(function () { return !findChild(sv, "settings-sound-meeting-minutes").visible; }, 1000);
    }

    function test_chime_minutes_are_read_latest_first() {
        const sv = openAppearance();
        compare(JSON.stringify(sv.parseChimeMinutes("5, 15, 10")), "[15,10,5]");
        compare(JSON.stringify(sv.parseChimeMinutes(" 3,3, 0, 200, 7 ")), "[7,3]");
        compare(JSON.stringify(sv.parseChimeMinutes("30, 20, 10, 5")), "[30,20,10]");
        compare(sv.parseChimeMinutes("x").length, 0);
        compare(sv.chimeMinutesText([20, 5]), "20, 5");
        compare(sv.chimeMinutesText(undefined), "15, 10, 5");
    }
}
