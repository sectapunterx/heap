// The first run (APP-271): the input line on Today makes a task with its
// date read from the line, and the example is a profile of its own that
// comes and goes without touching the person's tasks.
import QtQuick
import QtTest
import TodoCpp

TestCase {
    id: tc
    name: "FirstRun"
    when: windowShown
    visible: true
    width: 1000
    height: 700

    Item { id: host; anchors.fill: parent }

    function test_the_line_makes_a_task_with_its_date() {
        const hero = createTemporaryQmlObject('import TodoCpp; FirstRunHero { width: 800 }', host);
        const input = findChild(hero, "first-run-input");
        verify(input !== null);
        const before = AppController.tasks.rowCount();
        input.text = "first run demo tomorrow 12:00 p1";
        const id = hero.submit();
        verify(id.length > 0, "no task made");
        compare(AppController.tasks.rowCount(), before + 1);
        const t = AppController.taskById(id);
        compare(t.title, "first run demo");
        compare(t.priority, "P1");
        verify(AppController.welcomeSeen, "the first task did not end the first run");
        compare(input.text, "");
        AppController.deleteTask(id);
    }

    function test_three_keys_and_the_ways_in() {
        const hero = createTemporaryQmlObject('import TodoCpp; FirstRunHero { width: 800 }', host);
        verify(findChild(hero, "first-run-connect") !== null);
        verify(findChild(hero, "first-run-import") !== null);
        verify(findChild(hero, "first-run-example") !== null);
    }

    function test_example_is_its_own_profile() {
        const own = AppController.activeProfileId;
        const ownTasks = AppController.tasks.rowCount();
        AppController.openExample();
        compare(AppController.activeProfileId, "lowkey-example");
        verify(AppController.tasks.rowCount() > 0);
        const profiles = AppController.profiles.length;
        AppController.activeProfileId = own;
        AppController.openExample();
        compare(AppController.profiles.length, profiles, "a second example was made");
        AppController.removeExample();
        verify(!AppController.hasExample());
        compare(AppController.activeProfileId === "lowkey-example", false);
        AppController.activeProfileId = own;
        compare(AppController.tasks.rowCount(), ownTasks, "the person's tasks changed");
    }
}
