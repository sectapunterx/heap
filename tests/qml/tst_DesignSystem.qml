// heap 2 design system (APP-259) and the two interface styles (APP-275).
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "DesignSystem"
    when: windowShown
    visible: true
    width: 600
    height: 400

    Item { id: host; anchors.fill: parent }

    property string savedSettings: ""
    function init() { savedSettings = AppController.appSettingsJson; }
    function cleanup() { AppController.appSettingsJson = savedSettings; }

    function make(qml) {
        const o = createTemporaryQmlObject(qml, host);
        verify(o !== null);
        return o;
    }

    // ── Style: two sets of switches, "custom" in between ──

    function test_bold_is_the_default() {
        AppController.appSettingsJson = "{}";
        compare(Style.name, "bold");
        verify(Style.urgency && Style.counters && Style.keyHints && Style.chipFill && Style.factsLine);
        compare(Style.todayExtras, "open");
    }

    function test_quiet_turns_the_noise_off() {
        AppController.appSettingsJson = "{}";
        Style.apply("quiet");
        compare(Style.name, "quiet");
        verify(!Style.urgency && !Style.counters && !Style.keyHints && !Style.chipFill);
        verify(Style.factsLine, "the muted facts line stays in the quiet style");
        compare(Style.todayExtras, "collapsed");
    }

    function test_one_switch_makes_it_custom_and_back() {
        AppController.appSettingsJson = "{}";
        Style.apply("bold");
        Style.setFlag("counters", false);
        compare(Style.name, "custom");
        verify(!Style.counters);
        verify(Style.urgency, "the other switches keep the set's values");
        Style.setFlag("counters", true);
        compare(Style.name, "bold", "a switch flipped back is the set again");
        compare(JSON.parse(AppController.appSettingsJson).appearance.styleFlags.counters, undefined);
    }

    function test_applying_a_style_drops_the_overrides() {
        AppController.appSettingsJson = "{}";
        Style.setFlag("keyHints", false);
        compare(Style.name, "custom");
        Style.apply("quiet");
        compare(Style.name, "quiet");
        Style.toggle();
        compare(Style.name, "bold");
    }

    function test_style_drives_the_theme_tokens() {
        AppController.appSettingsJson = "{}";
        Style.apply("bold");
        verify(Qt.colorEqual(Theme.priorityInk("P0"), Theme.danger));
        verify(Qt.colorEqual(Theme.signalNow, Theme.warning));
        verify(Theme.chipBg !== "transparent");
        Style.apply("quiet");
        verify(Qt.colorEqual(Theme.priorityInk("P0"), Theme.textMuted), "no red in the quiet style");
        verify(Qt.colorEqual(Theme.signalNow, Theme.textMuted));
        verify(Qt.colorEqual(Theme.chipBg, "transparent"), "quiet chips are an outline");
        verify(Theme.priorityShown("P0") && Theme.priorityShown("P1"));
        verify(!Theme.priorityShown("P2") && !Theme.priorityShown("P3"));
    }

    // ── Components ──

    function test_status_ring_draws_every_stage() {
        for (const c of ["backlog", "todo", "half", "prog", "review", "done", "blocked", "orphan"]) {
            const r = make('import TodoCpp; StatusRing { category: "' + c + '" }');
            compare(r.width, Theme.statusRingSize);
            verify(r.Accessible.name.length > 0, c + " has a spoken name");
        }
        const rep = make('import TodoCpp; StatusRing { category: "todo"; repeats: true }');
        verify(rep.implicitWidth > Theme.statusRingSize, "the repeat mark sits beside the shape");
    }

    function test_blocked_takes_the_urgent_signal_only_in_bold() {
        AppController.appSettingsJson = "{}";
        Style.apply("bold");
        const r = make('import TodoCpp; StatusRing { category: "blocked" }');
        verify(Qt.colorEqual(r.ink, Theme.danger));
        Style.apply("quiet");
        verify(Qt.colorEqual(r.ink, Theme.text));
    }

    function test_chips_have_a_fixed_height() {
        const a = make('import TodoCpp; PropertyChip { key: "status"; value: "in progress" }');
        const b = make('import TodoCpp; PropertyChip { key: "priority"; value: "P0" }');
        compare(a.height, Theme.chipH);
        compare(b.height, Theme.chipH);
        const s = make('import TodoCpp; PropertyChip { small: true; key: "status"; value: "open" }');
        compare(s.height, Theme.chipHSmall);
        const long = make('import TodoCpp; PropertyChip { key: "title"; value: "' + "x".repeat(400) + '" }');
        verify(long.width <= Theme.chipMaxW, "a long value is cut, not the row widened");
    }

    function test_key_hints_follow_the_style_except_in_menus() {
        AppController.appSettingsJson = "{}";
        Style.apply("bold");
        const h = make('import TodoCpp; KeyHint { keys: "g b" }');
        const m = make('import TodoCpp; KeyHint { keys: "d"; always: true }');
        verify(h.visible && m.visible);
        Style.apply("quiet");
        verify(!h.visible, "no on-screen hints in the quiet style");
        verify(m.visible, "a menu keeps its keys");
    }

    function test_lens_tabs_select() {
        const t = make('import TodoCpp; LensTabs { model: [{id:"board",label:"Board",keys:"g b"},{id:"list",label:"List",keys:"g l"}]; current: "board" }');
        let picked = "";
        t.selected.connect(function (id) { picked = id; });
        const list = (function find(it) {
            if (it.objectName === "lens-list") return it;
            for (let i = 0; i < it.children.length; i++) { const r = find(it.children[i]); if (r) return r; }
            return null;
        })(t);
        verify(list !== null);
        mouseClick(list);
        compare(picked, "list");
    }

    function test_query_bar_backspace_takes_the_last_condition() {
        const q = make('import TodoCpp; QueryBar { conditions: [{key:"status",value:"open"},{key:"profile",value:"Example"}] }');
        let removed = -1;
        q.conditionRemoved.connect(function (i) { removed = i; });
        q.focusInput();
        keyClick(Qt.Key_Backspace);
        compare(removed, 1);
    }

    // ── Density: three steps that move the spacing ──

    function test_density_has_three_steps() {
        const saved = AppController.density;
        AppController.density = "compact";
        const c = Theme.sp2xl;
        AppController.density = "comfy";
        const n = Theme.sp2xl;
        AppController.density = "spacious";
        const s = Theme.sp2xl;
        AppController.density = saved;
        verify(c < n && n < s, c + " < " + n + " < " + s);
    }
}
