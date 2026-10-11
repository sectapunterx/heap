// Tasks → List (APP-263): the rows of the list lens, groups and tasks in the
// order they are drawn. The grouping itself is views/TaskListGroups; this is
// the part that knows the profile, the query and the columns.

#include "AppController.h"

#include "board/ColumnCategory.h"
#include "local/Effective.h"
#include "views/SavedViewMatch.h"
#include "views/TaskListGroups.h"

namespace {

QVariant dateOrNull(const QDateTime& d) {
  return d.isValid() ? QVariant(d) : QVariant();
}

}  // namespace

QVariantList AppController::taskListRows(const QString& query,
                                         const QStringList& priorities,
                                         bool showArchived,
                                         const QString& groupBy) const {
  heap::savedviews::SavedView v;
  v.query = query;
  v.priorities = priorities;
  v.archived = showArchived;
  const QDate today = m_today.isValid() ? m_today : QDate::currentDate();
  heap::savedviews::CompiledView c = heap::savedviews::compile(v, today, m_statuses);
  // `is:blocked` is a fact about other rows, as on the board: without the set
  // the list showed nothing the board did (IDIOT-TASKS-13).
  if(c.query.usesBlocked()) {
    c.query.setBlockedIds(heap::query::openlyBlockedIds(m_tasks.items(), [&c](const Task& t) {
      return c.query.isDone(t);
    }));
  }

  QStringList order;
  for(const QVariant& s : m_statuses) {
    order << s.toMap().value(QStringLiteral("id")).toString();
  }

  struct Src {
    const Task* task;
    QString profile;
    bool own;
  };

  QVector<Src> src;
  const QVector<Task>& own = m_tasks.items();
  for(int row = 0; row < own.size(); ++row) {
    if(heap::savedviews::accepts(c, own.at(row), m_tasks.searchTextAt(row))) {
      src.append({&own.at(row), QString(), true});
    }
  }
  QString activeName;
  // "By profile" lists every profile's tasks through the same query, the
  // active one first.
  QVector<Profile> snapshot;
  if(groupBy == QStringLiteral("profile")) {
    snapshot = profilesSnapshot();
    for(const Profile& p : std::as_const(snapshot)) {
      if(p.id == m_activeProfileId) {
        activeName = p.name;
      }
    }
    for(Src& s : src) {
      s.profile = activeName;
    }
    for(const Profile& p : std::as_const(snapshot)) {
      if(p.id == m_activeProfileId) {
        continue;
      }
      for(const Task& t : p.tasks) {
        if(heap::savedviews::accepts(c, t, TaskModel::searchTextOf(t))) {
          src.append({&t, p.name, false});
        }
      }
    }
  }
  QHash<QString, int> profileIndex;
  profileIndex.insert(activeName, 0);
  for(int i = 0; i < snapshot.size(); ++i) {
    if(snapshot.at(i).id != m_activeProfileId) {
      profileIndex.insert(snapshot.at(i).name, i + 1);
    }
  }

  QVector<heap::tasklist::Item> items;
  items.reserve(src.size());
  QStringList categories;
  for(const Src& s : std::as_const(src)) {
    const Task& t = *s.task;
    const QString cat = s.own ? statusCategory(t.status) : heap::board::defaultCategoryFor(t.status);
    categories << cat;
    heap::tasklist::Item it;
    it.id = t.id;
    it.when = t.scheduledAt.isValid() ? t.scheduledAt.date() : QDate();
    const QDateTime due = heap::local::effectiveDueAt(t);
    it.due = due.isValid() ? due.date() : QDate();
    it.done = cat == QStringLiteral("done");
    it.status = t.status;
    it.statusIndex = s.own ? std::max(0, static_cast<int>(order.indexOf(t.status))) : order.size();
    it.priority = heap::local::effectivePriority(t);
    it.profile = s.profile;
    it.profileIndex = profileIndex.value(s.profile, 0);
    it.changed = t.statusChangedAt.isValid() ? t.statusChangedAt.date() : QDate();
    items.append(it);
  }

  const auto groups = heap::tasklist::group(items, groupBy, today);
  QVariantList rows;
  rows.reserve(items.size() + groups.size());
  for(const heap::tasklist::Group& g : groups) {
    QVariantMap head{{QStringLiteral("kind"), QStringLiteral("group")},
                     {QStringLiteral("key"), g.key},
                     {QStringLiteral("value"), g.value},
                     {QStringLiteral("count"), g.members.size()},
                     {QStringLiteral("from"), g.from.isValid() ? QVariant(g.from) : QVariant()},
                     {QStringLiteral("to"), g.to.isValid() ? QVariant(g.to) : QVariant()}};
    if(g.key == QStringLiteral("status")) {
      const int si = statusIndexOf(g.value);
      head[QStringLiteral("name")] = si >= 0 ? m_statuses.at(si).toMap().value(QStringLiteral("name")).toString() : g.value;
      head[QStringLiteral("category")] = si >= 0 ? statusCategory(g.value) : heap::board::defaultCategoryFor(g.value);
    }
    const QString groupId = g.key + QLatin1Char(':') + g.value;
    head[QStringLiteral("groupId")] = groupId;
    rows.append(head);
    for(int i : g.members) {
      const Task& t = *src.at(i).task;
      const QString key = externalKeyOf(t);
      QVariantMap r{{QStringLiteral("kind"), QStringLiteral("task")},
                    {QStringLiteral("groupId"), groupId},
                    {QStringLiteral("id"), t.id},
                    {QStringLiteral("key"), key.isEmpty() ? t.id : key},
                    {QStringLiteral("title"), t.title},
                    {QStringLiteral("status"), t.status},
                    {QStringLiteral("category"), categories.at(i)},
                    {QStringLiteral("priority"), items.at(i).priority},
                    {QStringLiteral("label"), t.labels.isEmpty() ? QString() : t.labels.first().id},
                    {QStringLiteral("when"), dateOrNull(t.scheduledAt)},
                    {QStringLiteral("whenHasTime"), t.scheduledHasTime},
                    {QStringLiteral("due"), dateOrNull(heap::local::effectiveDueAt(t))},
                    {QStringLiteral("dueHasTime"), heap::local::effectiveDueHasTime(t)},
                    {QStringLiteral("repeats"), !t.recurrence.isEmpty()},
                    {QStringLiteral("archived"), t.archived},
                    {QStringLiteral("changed"), dateOrNull(t.statusChangedAt)},
                    {QStringLiteral("own"), src.at(i).own},
                    {QStringLiteral("profile"), src.at(i).profile}};
      rows.append(r);
    }
  }
  return rows;
}
