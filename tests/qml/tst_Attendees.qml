// Attendee-field helpers (qml/Attendees.js) behind the event editor's contact
// suggestions: which comma-separated entry the caret is in, who is offered for
// it, and how a pick is spliced back into the field.
import QtQuick
import QtTest
import "../../qml/Attendees.js" as Attendees

TestCase {
    name: "Attendees"

    readonly property var people: [
        { name: "Oleg Titov", role: "backend", handle: "@oleg" },
        { name: "Viktor Sokolov", role: "PM", handle: "vik" },
        { name: "Masha", role: "", handle: "" },
        { name: "Oleg Titov", role: "", handle: "@oleg" },   // contact + Person of one human
        { name: "Anatoly", role: "", handle: "tolik" }
    ]
    function names(list) { return list.map(c => c.name); }

    function test_token_at_caret() {
        compare(Attendees.tokenAt("", 0).query, "");
        const t = Attendees.tokenAt("Oleg, vi", 8);
        compare(t.start, 5);
        compare(t.end, 8);
        compare(t.query, "vi");
        // Only what is left of the caret is the query; the entry spans to the comma.
        const m = Attendees.tokenAt("Oleg, Viktor, Masha", 8);
        compare(m.query, "Vi");
        compare(m.end, 12);
    }

    function test_suggest_ranks_prefix_first_and_dedupes() {
        // "ol": Oleg by first name; Sokolov and Anatoly only contain it — after.
        compare(names(Attendees.suggest(people, "ol", [], 6)), ["Oleg Titov", "Viktor Sokolov", "Anatoly"]);
        // Surname and handle prefixes count as prefixes too.
        compare(names(Attendees.suggest(people, "sok", [], 6)), ["Viktor Sokolov"]);
        compare(names(Attendees.suggest(people, "tol", [], 6)), ["Anatoly"]);   // by handle
        // Empty query offers everyone, once each.
        compare(names(Attendees.suggest(people, "", [], 6)),
                ["Oleg Titov", "Viktor Sokolov", "Masha", "Anatoly"]);
        compare(Attendees.suggest(people, "", [], 2).length, 2);
    }

    function test_suggest_skips_already_listed() {
        const text = "Oleg Titov, ";
        const tok = Attendees.tokenAt(text, text.length);
        compare(names(Attendees.suggest(people, tok.query, Attendees.listed(text, tok.start), 6)),
                ["Viktor Sokolov", "Masha", "Anatoly"]);
        // The entry being edited does not exclude itself.
        compare(Attendees.listed("Masha", 0), []);
    }

    function test_apply_replaces_entry() {
        let text = "ol";
        let r = Attendees.apply(text, Attendees.tokenAt(text, 2), "Oleg Titov");
        compare(r.text, "Oleg Titov, ");
        compare(r.caret, r.text.length);

        text = "Oleg Titov, vi";
        r = Attendees.apply(text, Attendees.tokenAt(text, text.length), "Viktor Sokolov");
        compare(r.text, "Oleg Titov, Viktor Sokolov, ");

        // Editing a middle entry keeps what follows it.
        text = "Oleg Titov, ma, Anatoly";
        r = Attendees.apply(text, Attendees.tokenAt(text, 14), "Masha");
        compare(r.text, "Oleg Titov, Masha, Anatoly");
        compare(r.caret, "Oleg Titov, Masha, ".length);
    }
}
