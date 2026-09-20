// DocsView search.
//
// The search box used to filter only the reference sections. Snippets and
// contacts were exempt, so typing a query left both panels showing everything
// and a hit inside a snippet was unfindable — the one thing an engineer is
// most likely to be looking for in there.
//
// Also covers focusSearch(), which the global Ctrl+F now calls when Docs is
// the active view instead of focusing the task search in the top bar.
import QtQuick
import QtQuick.Controls
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "DocsView"
    when: windowShown
    visible: true
    width: 1000
    height: 700

    Item { id: host; anchors.fill: parent }

    function make() {
        const dv = createTemporaryQmlObject(
            'import TodoCpp; DocsView { anchors.fill: parent }', host);
        verify(dv !== null);
        return dv;
    }

    function test_smoke_load() {
        const dv = make();
        compare(dv.searchText, "");
        verify(dv.snippets !== undefined);
        verify(dv.contacts !== undefined);
    }

    // The regression: a query that matches a snippet's body must select it.
    function test_snippet_search_matches_title_lang_code_and_tags() {
        const dv = make();
        dv.snippets = [
            ({ title: "Rebase onto main", lang: "bash", code: "git rebase origin/main", tags: ["git"] }),
            ({ title: "Parse ISO date",   lang: "python", code: "datetime.fromisoformat(s)", tags: ["dates"] })
        ];

        dv.searchText = "rebase";
        verify(dv.snippetPassesSearch(dv.snippets[0]), "title must match");
        verify(!dv.snippetPassesSearch(dv.snippets[1]));

        dv.searchText = "fromisoformat";
        verify(dv.snippetPassesSearch(dv.snippets[1]), "the code body must be searchable");

        dv.searchText = "python";
        verify(dv.snippetPassesSearch(dv.snippets[1]), "the language must be searchable");

        dv.searchText = "git";
        verify(dv.snippetPassesSearch(dv.snippets[0]), "tags must be searchable");
    }

    function test_contact_search_matches_name_role_handle_and_team() {
        const dv = make();
        dv.contacts = [
            ({ name: "Ada Lovelace", role: "Analytical Engine", handle: "@ada", team: "core", note: "" }),
            ({ name: "Grace Hopper", role: "Compilers", handle: "@grace", team: "tools", note: "" })
        ];

        dv.searchText = "ada";
        verify(dv.contactPassesSearch(dv.contacts[0]));
        verify(!dv.contactPassesSearch(dv.contacts[1]));

        dv.searchText = "compilers";
        verify(dv.contactPassesSearch(dv.contacts[1]), "the role must be searchable");

        dv.searchText = "tools";
        verify(dv.contactPassesSearch(dv.contacts[1]), "the team must be searchable");
    }

    function test_empty_query_passes_everything() {
        const dv = make();
        dv.snippets = [({ title: "x", lang: "sh", code: "y", tags: [] })];
        dv.contacts = [({ name: "z", role: "", handle: "", team: "", note: "" })];

        dv.searchText = "";
        verify(dv.snippetPassesSearch(dv.snippets[0]));
        verify(dv.contactPassesSearch(dv.contacts[0]));

        dv.searchText = "   ";
        verify(dv.snippetPassesSearch(dv.snippets[0]), "whitespace is not a query");
    }

    function test_search_is_case_insensitive() {
        const dv = make();
        dv.snippets = [({ title: "Rebase onto main", lang: "bash", code: "", tags: [] })];
        dv.searchText = "REBASE";
        verify(dv.snippetPassesSearch(dv.snippets[0]));
    }

    // The section headers show a count; it has to follow the filter, or the
    // header claims nine snippets above a single visible card.
    function test_counts_follow_the_filter() {
        const dv = make();
        dv.snippets = [
            ({ title: "one", lang: "sh", code: "", tags: [] }),
            ({ title: "two", lang: "sh", code: "", tags: [] })
        ];
        dv.contacts = [
            ({ name: "Ada", role: "", handle: "", team: "", note: "" }),
            ({ name: "Grace", role: "", handle: "", team: "", note: "" })
        ];

        dv.searchText = "";
        compare(dv.matchingSnippetCount, 2);
        compare(dv.matchingContactCount, 2);

        dv.searchText = "one";
        compare(dv.matchingSnippetCount, 1);
        compare(dv.matchingContactCount, 0);
    }

    // Ctrl+F in Docs calls this instead of focusing the task search box, so it
    // has to actually land focus on the field — not merely exist.
    function test_focus_search_focuses_the_field() {
        const dv = make();
        verify(typeof dv.focusSearch === "function",
               "Main.qml duck-types on this to route the search shortcut");

        const field = findChild(dv, "docsSearchField");
        verify(field !== null, "docsSearchField not found — objectName renamed?");
        verify(!field.activeFocus, "precondition: the field does not start focused");

        dv.focusSearch();
        tryVerify(function () { return field.activeFocus; }, 2000,
                  "focusSearch() must put the caret in the search field");
    }
}
