// TaskCard, ticket half (HEAP-117). A mirrored issue has to look like one:
// provider badge, tracker key in place of the synthetic heap id, the upstream
// assignee, and open-in-browser. A locally-created task shows none of it.
//
// The card is instantiated directly with a `task` object rather than driven
// through a sync, so nothing here touches a provider or the task model.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "TaskCardTicket"
    when: windowShown
    visible: true
    width: 420
    height: 400

    Item { id: host; anchors.fill: parent }

    Component {
        id: cardComp
        TaskCard { width: 360 }
    }

    function make(taskObj) {
        const o = cardComp.createObject(host, { task: taskObj });
        verify(o !== null);
        return o;
    }

    function ghTicket() {
        return {
            id: "github-1234",
            title: "Fix the crash",
            desc: "steps",
            priority: "P1",
            status: "todo",
            labels: [],
            ticket: {
                provider: "github",
                key: "#1234",
                url: "https://github.com/acme/web/issues/1234",
                assignee: "ada",
                author: "grace",
                project: "acme/web",
                commentCount: 4
            }
        };
    }

    function localTask() {
        return {
            id: "LTE-2700",
            title: "Write the thing",
            priority: "P2",
            status: "todo",
            labels: [],
            ticket: ({})
        };
    }

    function find(card, name) {
        return findChild(card, name);
    }

    // HEAP-117's headline: a GitHub-synced card shows a GitHub badge and #1234.
    function test_github_card_shows_badge_and_hash_key() {
        const card = make(ghTicket());
        const badge = find(card, "tc-badge");
        verify(badge !== null, "no provider badge");
        verify(badge.visible, "the badge is hidden on a synced card");

        const key = find(card, "tc-key");
        verify(key !== null);
        compare(key.text, "#1234", "the card shows the heap id instead of the tracker key");

        const assignee = find(card, "tc-assignee");
        verify(assignee !== null && assignee.visible, "no assignee chip");

        const comments = find(card, "tc-comments");
        verify(comments !== null && comments.visible, "no comment count");
        card.destroy();
    }

    // …and a purely local card shows no provider badge and no ticket chips.
    function test_local_card_shows_no_ticket_chrome() {
        const card = make(localTask());
        verify(!find(card, "tc-badge").visible, "a local card grew a provider badge");
        verify(!find(card, "tc-assignee").visible);
        verify(!find(card, "tc-comments").visible);
        // The heap id is what a local card is known by.
        compare(find(card, "tc-key").text, "LTE-2700");
        card.destroy();
    }

    // -1 is "the provider did not say", which is not "no comments"; neither is
    // worth a chip, and neither may render as "💬 -1".
    function test_comment_chip_hidden_when_unknown_or_zero() {
        const unknown = ghTicket();
        unknown.ticket.commentCount = -1;
        const a = make(unknown);
        verify(!find(a, "tc-comments").visible, "rendered an unknown comment count");
        a.destroy();

        const none = ghTicket();
        none.ticket.commentCount = 0;
        const b = make(none);
        verify(!find(b, "tc-comments").visible);
        b.destroy();
    }

    function test_assignee_chip_hidden_when_unassigned() {
        const t = ghTicket();
        t.ticket.assignee = "";
        const card = make(t);
        verify(!find(card, "tc-assignee").visible);
        card.destroy();
    }

    // Open-in-browser and copy-link belong to a ticket, not to a local task.
    // A Menu builds its items lazily, so it has to be opened before they exist.
    function menuItem(card, name) {
        const menu = findChild(card, "tc-menu");
        verify(menu !== null, "the card has no context menu");
        menu.open();
        const item = findChild(menu, name);
        verify(item !== null, "no menu item named " + name);
        return item;
    }

    function test_menu_offers_open_only_for_a_ticket() {
        const ticketCard = make(ghTicket());
        verify(menuItem(ticketCard, "tc-menu-open").visible, "a ticket has no open-in-tracker item");
        verify(menuItem(ticketCard, "tc-menu-copylink").visible);
        ticketCard.destroy();

        const local = make(localTask());
        verify(!menuItem(local, "tc-menu-open").visible, "a local task was offered open-in-tracker");
        verify(!menuItem(local, "tc-menu-copylink").visible);
        local.destroy();
    }

    // An issue title is written by whoever filed it. Text defaults to AutoText,
    // which renders HTML — and an <img> in it fetches from the network.
    function test_tracker_text_is_never_rendered_as_markup() {
        const t = ghTicket();
        t.title = "<img src='http://example.invalid/x.png'> title";
        t.desc = "<b>bold</b>";
        const card = make(t);
        let checked = 0;
        for (let i = 0; i < card.children.length; i++) {
            const col = card.children[i];
            for (let j = 0; j < (col.children ? col.children.length : 0); j++) {
                const it = col.children[j];
                if (it instanceof Text && (it.text === t.title || it.text === t.desc)) {
                    compare(it.textFormat, Text.PlainText, "tracker text is rendered as markup");
                    checked++;
                }
            }
        }
        verify(checked >= 2, "did not find the title and description to check");
        card.destroy();
    }
}
