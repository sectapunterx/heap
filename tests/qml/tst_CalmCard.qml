// The two-line task card (APP-179): at rest a card is its title and one line
// of key, date and priority; under the cursor it opens the first line of its
// description, its checklist and the quieter facts. It never shows people
// or a branch: heap shows the tasks assigned to me.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "CalmCard"
    when: windowShown
    visible: true
    width: 420
    height: 500

    Item { id: host; anchors.fill: parent }

    Component {
        id: cardComp
        TaskCard { width: 300 }
    }

    function dayFromToday(n) {
        const t = AppController.today;
        return new Date(t.getFullYear(), t.getMonth(), t.getDate() + n);
    }

    function make(fields, props) {
        const task = Object.assign({
            id: "CALM-1", title: "Calm card probe", desc: "First line of the description.\nSecond line.",
            priority: "P2", status: "todo", labels: [], ticket: ({}),
            checklist: ({ total: 4, done: 1 })
        }, fields || {});
        const o = cardComp.createObject(host, Object.assign({ task: task }, props || {}));
        verify(o !== null);
        return o;
    }

    function texts(item, out) {
        if (!item) return out;
        if (item.text !== undefined && typeof item.text === "string" && item.visible) out.push(item.text);
        const kids = item.children || [];
        for (let i = 0; i < kids.length; i++) texts(kids[i], out);
        return out;
    }

    function test_no_people_and_no_branch_even_under_the_cursor() {
        const card = make({
            branch: "feat/calm-secret-branch",
            prState: "open", prNumber: 7,
            ticket: ({ provider: "github", key: "#77", url: "https://example.invalid/77",
                       assignee: "Calm Assignee Person", assignees: ["Calm Assignee Person"],
                       reporter: "Calm Reporter Person", commentCount: 3 })
        }, { cursored: true });
        tryVerify(function () { return findChild(card, "tc-details").height > 0; }, 2000);
        const all = texts(card, []).join("\n");
        verify(all.indexOf("calm-secret-branch") < 0, "the card shows the branch:\n" + all);
        verify(all.indexOf("Calm Assignee Person") < 0, "the card shows the assignee:\n" + all);
        verify(all.indexOf("Calm Reporter Person") < 0, "the card shows a person:\n" + all);
        card.destroy();
    }

    function test_the_date_is_red_only_when_overdue() {
        const cases = [
            { days: -3, red: true },
            { days: 0, red: false },
            { days: 1, red: false },
            { days: 2, red: false }
        ];
        for (let i = 0; i < cases.length; i++) {
            const c = cases[i];
            const card = make({ deadline: dayFromToday(c.days) });
            const due = findChild(card, "tc-due");
            verify(due.visible, "no date for " + c.days);
            compare(Qt.colorEqual(due.color, Theme.danger), c.red,
                    "due in " + c.days + " day(s): " + due.text + " " + due.color);
            card.destroy();
        }
        // Done work is never overdue.
        const done = make({ status: "done", deadline: dayFromToday(-3) });
        verify(!findChild(done, "tc-due").visible);
        done.destroy();
    }

    function test_priority_has_colour_only_for_p0_and_p1() {
        const p = ["P0", "P1", "P2", "P3"];
        for (let i = 0; i < p.length; i++) {
            const card = make({ priority: p[i] });
            const pri = findChild(card, "tc-priority");
            verify(pri.visible);
            if (i < 2) verify(Qt.colorEqual(pri.color, Theme.priorityColor(p[i])), p[i] + " " + pri.color);
            else verify(Qt.colorEqual(pri.color, Theme.textDim), p[i] + " is not dim: " + pri.color);
            card.destroy();
        }
    }

    function test_at_rest_the_card_is_title_and_one_line() {
        const card = make({ deadline: dayFromToday(4) });
        const details = findChild(card, "tc-details");
        wait(Theme.durPop + 50);
        compare(details.visible, false, "details open at rest");
        verify(findChild(card, "tc-title").visible);
        verify(findChild(card, "tc-meta").visible);
        verify(findChild(card, "tc-key").visible);
        compare(findChild(card, "tc-title").maximumLineCount, 2);
        compare(findChild(card, "tc-alerts").visible, false, "an alerts row with nothing to say");
        card.destroy();
    }

    function test_details_open_under_the_keyboard_cursor() {
        // The pointer well away: a card under it opens too.
        mouseMove(host, host.width - 1, host.height - 1);
        const card = make({});
        const details = findChild(card, "tc-details");
        const excerpt = findChild(card, "tc-excerpt");
        const check = findChild(card, "tc-checklist");
        const rest = card.height;
        card.cursored = true;
        tryVerify(function () { return details.visible && details.height > 0; }, 2000, "details did not open");
        tryVerify(function () { return excerpt.visible && check.visible; }, 2000);
        compare(excerpt.text.indexOf("Second line"), -1, "only the first line of the description");
        compare(check.text, "1/4");
        tryVerify(function () { return card.height > rest; }, 2000, "the card did not grow");
        card.cursored = false;
        tryVerify(function () { return !details.visible; }, 2000, "details did not close");
        card.destroy();
    }

    function test_details_open_on_tab_focus_and_under_the_pointer() {
        const card = make({});
        const details = findChild(card, "tc-details");
        card.forceActiveFocus();
        tryVerify(function () { return details.visible && details.height > 0; }, 2000, "Tab focus did not open the details");
        card.focus = false;
        host.forceActiveFocus();
        tryVerify(function () { return !details.visible; }, 2000);
        // The pointer: the card opens for whatever reports it is hovered.
        mouseMove(card, card.width / 2, card.height / 2);
        if (!card.hovered) skip("no synthetic hover on this platform");
        tryVerify(function () { return details.visible && details.height > 0; }, 2000, "hover did not open the details");
        mouseMove(host, host.width - 1, host.height - 1);
        tryVerify(function () { return !details.visible; }, 2000, "leaving did not close the details");
        card.destroy();
    }

    function test_nothing_to_open_stays_closed() {
        const card = make({ desc: "", checklist: ({}) }, { cursored: true });
        wait(Theme.durPop + 50);
        compare(findChild(card, "tc-details").visible, false, "an empty details block opened");
        card.destroy();
    }
}
