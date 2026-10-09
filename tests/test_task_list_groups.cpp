// The groups of the Tasks → List lens (APP-263).

#include "views/TaskListGroups.h"

#include <gtest/gtest.h>

using heap::tasklist::Group;
using heap::tasklist::Item;

namespace {

// Thursday 8 October 2026, as in the mockup sheet H2-List.
const QDate kToday(2026, 10, 8);

Item task(const QString& id, QDate when = {}, QDate due = {}) {
  Item t;
  t.id = id;
  t.when = when;
  t.due = due;
  return t;
}

QStringList keys(const QVector<Group>& groups) {
  QStringList out;
  for(const Group& g : groups) {
    out << g.key + (g.value.isEmpty() ? QString() : QLatin1Char(':') + g.value);
  }
  return out;
}

QStringList ids(const QVector<Item>& items, const Group& g) {
  QStringList out;
  for(int i : g.members) {
    out << items.at(i).id;
  }
  return out;
}

}  // namespace

TEST(TaskListGroups, DateGroupsFollowTheWeek) {
  const QVector<Item> items = {
      task("A", kToday),
      task("B", kToday.addDays(1)),
      task("C", QDate(2026, 10, 10)),  // Saturday: this week
      task("D", QDate(2026, 10, 11)),  // Sunday: this week
      task("E", QDate(2026, 10, 12)),  // Monday: next week
      task("F", QDate(2026, 10, 18)),  // Sunday: next week
      task("G", QDate(2026, 10, 19)),  // later
      task("H"),                       // no date
  };
  const auto groups = heap::tasklist::group(items, "date", kToday);
  EXPECT_EQ(keys(groups), QStringList({"today", "tomorrow", "week", "nextWeek", "later", "none"}));
  EXPECT_EQ(ids(items, groups.at(2)), QStringList({"C", "D"}));
  EXPECT_EQ(groups.at(2).from, QDate(2026, 10, 10));
  EXPECT_EQ(groups.at(2).to, QDate(2026, 10, 11));
  EXPECT_EQ(groups.at(3).from, QDate(2026, 10, 12));
  EXPECT_EQ(groups.at(3).to, QDate(2026, 10, 18));
  EXPECT_EQ(ids(items, groups.at(5)), QStringList({"H"}));
}

TEST(TaskListGroups, WhenWinsOverTheDeadline) {
  // Planned tomorrow, due next week: it is tomorrow's.
  const Item t = task("A", kToday.addDays(1), QDate(2026, 10, 14));
  EXPECT_EQ(heap::tasklist::dateGroupOf(t, kToday), "tomorrow");
  // Only a deadline: the deadline decides.
  EXPECT_EQ(heap::tasklist::dateGroupOf(task("B", {}, QDate(2026, 10, 14)), kToday), "nextWeek");
}

TEST(TaskListGroups, OverdueOnlyWhenOpenAndOnlyWhenThere) {
  Item late = task("A", kToday.addDays(-2));
  EXPECT_EQ(heap::tasklist::dateGroupOf(late, kToday), "overdue");
  late.done = true;
  EXPECT_EQ(heap::tasklist::dateGroupOf(late, kToday), "past");

  const QVector<Item> none = {task("B", kToday)};
  EXPECT_EQ(keys(heap::tasklist::group(none, "date", kToday)), QStringList({"today"}));
  const QVector<Item> some = {task("B", kToday), task("C", kToday.addDays(-1))};
  EXPECT_EQ(keys(heap::tasklist::group(some, "date", kToday)).first(), "overdue");
}

TEST(TaskListGroups, SortsByDateThenPriority) {
  QVector<Item> items = {task("A", QDate(2026, 10, 14)), task("B", QDate(2026, 10, 13)), task("C", QDate(2026, 10, 13))};
  items[2].priority = "P0";
  const auto groups = heap::tasklist::group(items, "date", kToday);
  ASSERT_EQ(groups.size(), 1);
  EXPECT_EQ(ids(items, groups.first()), QStringList({"C", "B", "A"}));
}

TEST(TaskListGroups, ByStatusFollowsTheColumns) {
  QVector<Item> items = {task("A"), task("B"), task("C")};
  items[0].status = "review";
  items[0].statusIndex = 4;
  items[1].status = "todo";
  items[1].statusIndex = 1;
  items[2].status = "review";
  items[2].statusIndex = 4;
  const auto groups = heap::tasklist::group(items, "status", kToday);
  EXPECT_EQ(keys(groups), QStringList({"status:todo", "status:review"}));
  EXPECT_EQ(ids(items, groups.at(1)), QStringList({"A", "C"}));
}

TEST(TaskListGroups, ByPriorityThenNone) {
  QVector<Item> items = {task("A"), task("B"), task("C")};
  items[0].priority = "P2";
  items[2].priority = "P0";
  const auto groups = heap::tasklist::group(items, "priority", kToday);
  EXPECT_EQ(keys(groups), QStringList({"priority:P0", "priority:P2", "priority"}));
}

TEST(TaskListGroups, ByProfileActiveFirst) {
  QVector<Item> items = {task("A"), task("B")};
  items[0].profile = "Work";
  items[0].profileIndex = 2;
  items[1].profile = "Home";
  items[1].profileIndex = 0;
  EXPECT_EQ(keys(heap::tasklist::group(items, "profile", kToday)), QStringList({"profile:Home", "profile:Work"}));
}

TEST(TaskListGroups, EmptyInNothingOut) {
  EXPECT_TRUE(heap::tasklist::group({}, "date", kToday).isEmpty());
  EXPECT_TRUE(heap::tasklist::group({}, "status", kToday).isEmpty());
}
