// Switching the language repaints what is on screen, without a restart
// (audit UX-12). Dates formatted in C++ were bound as
// `(I18n.lang, AppController.humanDate(…))`; the compiled binding dropped the
// unused left operand and with it the dependency, so the day header stayed
// "Tuesday, September 29" in Russian. The people badge was assigned from
// Connections handlers, which broke its binding to I18n.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "LangSwitch"
    when: windowShown
    visible: true
    width: 1200
    height: 800

    Item { id: host; anchors.fill: parent }

    property string savedLang: ""
    function initTestCase() { tc.savedLang = AppController.language; }
    function cleanupTestCase() { AppController.language = tc.savedLang; }

    function texts(root) {
        const out = [];
        const walk = function (it) {
            if (!it) return;
            if (typeof it.text === "string" && it.contentWidth !== undefined) out.push(it);
            const kids = it.children || [];
            for (let i = 0; i < kids.length; i++) walk(kids[i]);
        };
        walk(root);
        return out;
    }
    function hasText(root, s) {
        const ts = texts(root);
        for (let i = 0; i < ts.length; i++) if (ts[i].text === s) return true;
        return false;
    }

    function test_day_header_follows_language() {
        AppController.language = "en";
        const cal = createTemporaryQmlObject('import TodoCpp; DayCalendar { anchors.fill: parent }', host);
        wait(0);
        const en = AppController.humanDate(AppController.selectedDate);
        verify(hasText(cal, en), "header shows " + en);
        AppController.language = "ru";
        const ru = AppController.humanDate(AppController.selectedDate);
        verify(en !== ru);
        tryVerify(function () { return hasText(cal, ru); }, 1000, "header did not switch to " + ru);
    }

    function test_week_range_follows_language() {
        AppController.language = "en";
        const wv = createTemporaryQmlObject('import TodoCpp; WeekView { anchors.fill: parent }', host);
        wait(0);
        const ws = wv.weekStart;
        const en = AppController.shortDate(ws);
        verify(texts(wv).some(function (t) { return t.text.indexOf(en) === 0; }), "range starts " + en);
        AppController.language = "ru";
        const ru = AppController.shortDate(ws);
        verify(en !== ru);
        tryVerify(function () { return texts(wv).some(function (t) { return t.text.indexOf(ru) === 0; }); },
                  1000, "range did not switch to " + ru);
    }

    function test_people_badge_follows_language() {
        AppController.language = "en";
        // The badge counts the people waiting for a message and hides at
        // none (APP-197), so there has to be one.
        let made = "";
        if (AppController.pendingPeopleCount() === 0) {
            const d = AppController.newPersonDraft();
            d.name = "Lang Badge Probe";
            d.id = AppController.suggestPersonId(d.name);
            d.state = "todo";
            verify(AppController.savePerson(d));
            made = d.id;
        }
        verify(AppController.pendingPeopleCount() > 0);
        const pl = createTemporaryQmlObject('import TodoCpp; PeopleList { width: 400; height: 300 }', host);
        wait(0);
        const en = I18n.t("people.badge.pending").arg(AppController.pendingPeopleCount());
        verify(hasText(pl, en), en);
        // A model signal first: the handlers used to overwrite the binding.
        AppController.activePeople.dataChanged(AppController.activePeople.index(0, 0), AppController.activePeople.index(0, 0));
        AppController.language = "ru";
        const ru = I18n.t("people.badge.pending").arg(AppController.pendingPeopleCount());
        verify(en !== ru);
        tryVerify(function () { return hasText(pl, ru); }, 1000, "badge did not switch to " + ru);
        if (made) AppController.deletePerson(made);
    }

    function test_sprint_crumb_is_the_iso_week_in_the_ui_language() {
        AppController.language = "en";
        compare(AppController.sprintLabel(), "wk " + tc.isoWeek(AppController.today));
        AppController.language = "ru";
        compare(AppController.sprintLabel(), "нед. " + tc.isoWeek(AppController.today));
    }
    function isoWeek(d) {
        const t = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        t.setDate(t.getDate() + 3 - (t.getDay() + 6) % 7);
        const w1 = new Date(t.getFullYear(), 0, 4);
        return 1 + Math.round(((t - w1) / 86400000 - 3 + (w1.getDay() + 6) % 7) / 7);
    }
}
