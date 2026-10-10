// Merge / pull requests in Settings → Integrations (APP-242): GitHub's are off
// until switched on, which ones come in is the person's pick, and whether
// their cards may be moved here is a switch of its own, off by default.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "ReviewSettings"
    when: windowShown
    visible: true
    width: 900
    height: 1400

    Item { id: host; anchors.fill: parent }

    property string savedSettings: ""
    function init() {
        savedSettings = AppController.appSettingsJson;
        AppController.appSettingsJson = "{}";
    }
    function cleanup() {
        AppController.appSettingsJson = savedSettings;
    }

    function find(root, name) {
        if (root.objectName === name) return root;
        const kids = root.children || [];
        for (let i = 0; i < kids.length; i++) {
            const r = find(kids[i], name);
            if (r) return r;
        }
        return null;
    }

    // Mark trackers connected: their settings rows show only then (DG-093).
    function connect(ids) {
        const s = JSON.parse(AppController.appSettingsJson || "{}");
        s.integrations = s.integrations || ({});
        for (const id of ids) s.integrations[id] = Object.assign({}, s.integrations[id], { connected: true });
        AppController.appSettingsJson = JSON.stringify(s);
    }
    // The tracker's detail, connected and picked in the list.
    function openCard(id) {
        connect([id]);
        const sv = createTemporaryQmlObject('import TodoCpp; SettingsView { anchors.fill: parent }', host);
        sv.activeSection = "integrations";
        let card = null;
        tryVerify(function () { card = find(sv, "int-card-" + id); return card !== null; }, 2000, id + " card");
        sv.pickedTracker = id;
        tryVerify(function () { return card.visible; }, 1000);
        return card;
    }

    function conf(id) {
        const s = JSON.parse(AppController.appSettingsJson || "{}");
        return (s.integrations && s.integrations[id]) || {};
    }

    function test_github_pull_requests_are_off_until_switched_on() {
        const card = openCard("github");
        const pull = find(card, "int-review-pull-github");
        const roles = find(card, "int-review-roles-github");
        const movable = find(card, "int-review-movable-github");
        verify(pull && roles && movable);
        verify(pull.visible);
        verify(!pull.checked, "pull requests start switched on");
        verify(!roles.visible && !movable.visible, "nothing to pick while they do not come in");
        pull.toggled(true);
        tryVerify(function () { return conf("github").pullRequests === true; }, 1000);
        tryVerify(function () { return roles.visible && movable.visible; }, 1000);
        // The default: assigned to me and to review, not my own.
        verify(find(card, "int-review-role-github-assignee").on);
        verify(find(card, "int-review-role-github-reviewer").on);
        verify(!find(card, "int-review-role-github-author").on);
    }

    function test_gitlab_roles_and_movable_are_written_to_its_config() {
        const card = openCard("gitlab");
        verify(!find(card, "int-review-pull-gitlab").visible, "GitLab has no on/off key: its requests come by roles");
        const movable = find(card, "int-review-movable-gitlab");
        verify(movable.visible && !movable.checked, "cards are not movable by default");
        verify(!find(card, "int-review-role-gitlab-author").on);
        find(card, "int-review-role-gitlab-author-click").activated();
        tryVerify(function () { return conf("gitlab").mrRoles === "assignee,reviewer,author"; }, 1000, JSON.stringify(conf("gitlab")));
        find(card, "int-review-role-gitlab-reviewer-click").activated();
        tryVerify(function () { return conf("gitlab").mrRoles === "assignee,author"; }, 1000, JSON.stringify(conf("gitlab")));
        movable.toggled(true);
        tryVerify(function () { return conf("gitlab").reviewMovable === true; }, 1000);
        tryVerify(function () { return movable.checked; }, 1000);
    }

    function test_a_tracker_without_requests_shows_none_of_it() {
        const card = openCard("jira");
        verify(!find(card, "int-review-pull-jira").visible);
        verify(!find(card, "int-review-roles-jira").visible);
        verify(!find(card, "int-review-movable-jira").visible);
    }

    function test_strings_exist_in_both_languages() {
        const keys = ["settings.int.review.pull", "settings.int.review.roles", "settings.int.review.movable",
                      "settings.int.review.movable.hint", "settings.int.review.role.author",
                      "settings.int.review.role.assignee", "settings.int.review.role.reviewer"];
        for (let i = 0; i < keys.length; ++i) {
            verify(I18n.dict.en[keys[i]] !== undefined, keys[i] + " missing in en");
            verify(I18n.dict.ru[keys[i]] !== undefined, keys[i] + " missing in ru");
        }
    }
}
