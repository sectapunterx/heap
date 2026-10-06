// "Whose move" on a task card (APP-156). The card only renders what the PR
// watcher worked out; these drive it with a hand-made task object, so no gh,
// no repo and no model are involved.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "WhoseMoveChip"
    when: windowShown
    visible: true
    width: 420
    height: 400

    Item { id: host; anchors.fill: parent }

    Component {
        id: cardComp
        TaskCard { width: 360 }
    }

    function make(fields) {
        const task = Object.assign({
            id: "LTE-1", title: "Ship it", priority: "P2", status: "review",
            labels: [], ticket: ({}), prState: "open", prNumber: 42
        }, fields);
        const o = cardComp.createObject(host, { task: task });
        verify(o !== null);
        return o;
    }

    function test_mine_shows_a_chip_with_the_reason() {
        const card = make({ prMove: "mine", prMoveReason: "ciFailing" });
        const chip = findChild(card, "tc-move");
        verify(chip !== null);
        verify(chip.visible, "my move is not shown");
        compare(findChild(card, "tc-move-text").text, I18n.t("taskcard.move.mine"));
        compare(chip.tip, I18n.t("taskcard.move.ciFailing"));
        card.destroy();
    }

    function test_theirs_reads_as_waiting() {
        const card = make({ prMove: "theirs", prMoveReason: "awaitingReview" });
        const chip = findChild(card, "tc-move");
        verify(chip.visible);
        compare(findChild(card, "tc-move-text").text, I18n.t("taskcard.move.theirs"));
        card.destroy();
    }

    function test_no_verdict_no_chip() {
        const card = make({ prMove: "", prMoveReason: "" });
        verify(!findChild(card, "tc-move").visible, "a chip with nothing to say");
        card.destroy();
    }

    function test_no_pr_no_chip() {
        const card = make({ prState: "", prMove: "mine", prMoveReason: "readyToMerge" });
        verify(!findChild(card, "tc-move").visible, "a move without a PR");
        card.destroy();
    }

    function test_every_reason_has_text_in_both_languages() {
        const reasons = ["reviewRequested", "ciFailing", "changesRequested", "conflicts",
                         "readyToMerge", "ciRunning", "awaitingReview"];
        for (let i = 0; i < reasons.length; ++i) {
            const key = "taskcard.move." + reasons[i];
            verify(I18n.dict.en[key] !== undefined, key + " missing in en");
            verify(I18n.dict.ru[key] !== undefined, key + " missing in ru");
        }
    }
}
