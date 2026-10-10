#include "views/TaskListGroups.h"

#include <QHash>
#include <QMap>
#include <QStringList>

#include <algorithm>

namespace heap::tasklist {

namespace {

int priorityRank(const QString& p) {
  if(p.size() == 2 && p.at(0) == QLatin1Char('P') && p.at(1) >= QLatin1Char('0') && p.at(1) <= QLatin1Char('3')) {
    return p.at(1).digitValue();
  }
  return 9;
}

// Monday of the week `d` is in.
QDate weekStart(const QDate& d) {
  return d.addDays(1 - d.dayOfWeek());
}

const QStringList& dateOrder() {
  static const QStringList order = {QStringLiteral("overdue"),
                                    QStringLiteral("today"),
                                    QStringLiteral("tomorrow"),
                                    QStringLiteral("week"),
                                    QStringLiteral("nextWeek"),
                                    QStringLiteral("later"),
                                    QStringLiteral("past"),
                                    QStringLiteral("none")};
  return order;
}

// Earlier date first, undated last; then the higher priority; then the order
// the tasks came in (stable).
void sortMembers(QVector<int>& members, const QVector<Item>& items) {
  std::stable_sort(members.begin(), members.end(), [&items](int a, int b) {
    const QDate da = groupDate(items.at(a));
    const QDate db = groupDate(items.at(b));
    if(da.isValid() != db.isValid()) {
      return da.isValid();
    }
    if(da.isValid() && da != db) {
      return da < db;
    }
    return priorityRank(items.at(a).priority) < priorityRank(items.at(b).priority);
  });
}

}  // namespace

QDate groupDate(const Item& t) {
  return t.when.isValid() ? t.when : t.due;
}

QString dateGroupOf(const Item& t, const QDate& today) {
  const QDate d = groupDate(t);
  if(!d.isValid()) {
    return QStringLiteral("none");
  }
  if(d < today) {
    return t.done ? QStringLiteral("past") : QStringLiteral("overdue");
  }
  if(d == today) {
    return QStringLiteral("today");
  }
  if(d == today.addDays(1)) {
    return QStringLiteral("tomorrow");
  }
  const QDate nextMonday = weekStart(today).addDays(7);
  if(d < nextMonday) {
    return QStringLiteral("week");
  }
  if(d < nextMonday.addDays(7)) {
    return QStringLiteral("nextWeek");
  }
  return QStringLiteral("later");
}

QVector<Group> group(const QVector<Item>& items, const QString& by, const QDate& today) {
  QVector<Group> out;
  if(by == QStringLiteral("month")) {
    QMap<QString, QVector<int>> byMonth;  // "yyyy-MM" sorts as the calendar does
    for(int i = 0; i < items.size(); ++i) {
      const QDate d = items.at(i).changed;
      byMonth[d.isValid() ? d.toString(QStringLiteral("yyyy-MM")) : QString()].append(i);
    }
    for(auto it = byMonth.constEnd(); it != byMonth.constBegin();) {
      --it;
      Group g;
      g.key = QStringLiteral("month");
      g.value = it.key();
      const QDate first = QDate::fromString(it.key() + QStringLiteral("-01"), QStringLiteral("yyyy-MM-dd"));
      if(first.isValid()) {
        g.from = first;
        g.to = first.addMonths(1).addDays(-1);
      }
      g.members = it.value();
      std::stable_sort(g.members.begin(), g.members.end(), [&items](int a, int b) {
        return items.at(a).changed > items.at(b).changed;
      });
      // Newest first; "" (no date) sorts first in the map, so it ends last.
      out.append(g);
    }
    return out;
  }
  if(by == QStringLiteral("status") || by == QStringLiteral("priority") || by == QStringLiteral("profile")) {
    // key → (sort key, group)
    QHash<QString, int> at;
    QVector<QPair<int, Group>> made;
    for(int i = 0; i < items.size(); ++i) {
      const Item& t = items.at(i);
      QString value;
      int order = 0;
      if(by == QStringLiteral("status")) {
        value = t.status;
        order = t.statusIndex;
      } else if(by == QStringLiteral("priority")) {
        const int r = priorityRank(t.priority);
        value = r < 9 ? t.priority : QString();
        order = r;
      } else {
        value = t.profile;
        order = t.profileIndex;
      }
      auto it = at.find(value);
      if(it == at.end()) {
        Group g;
        g.key = by;
        g.value = value;
        made.append({order, g});
        it = at.insert(value, made.size() - 1);
      }
      made[it.value()].second.members.append(i);
    }
    std::stable_sort(made.begin(), made.end(), [](const auto& a, const auto& b) {
      return a.first < b.first;
    });
    for(auto& m : made) {
      sortMembers(m.second.members, items);
      out.append(m.second);
    }
    return out;
  }

  QHash<QString, QVector<int>> byKey;
  for(int i = 0; i < items.size(); ++i) {
    byKey[dateGroupOf(items.at(i), today)].append(i);
  }
  const QDate nextMonday = weekStart(today).addDays(7);
  for(const QString& key : dateOrder()) {
    auto it = byKey.find(key);
    if(it == byKey.end() || it->isEmpty()) {
      continue;
    }
    Group g;
    g.key = key;
    if(key == QStringLiteral("today")) {
      g.from = g.to = today;
    } else if(key == QStringLiteral("tomorrow")) {
      g.from = g.to = today.addDays(1);
    } else if(key == QStringLiteral("week")) {
      g.from = today.addDays(2);
      g.to = nextMonday.addDays(-1);
    } else if(key == QStringLiteral("nextWeek")) {
      g.from = nextMonday;
      g.to = nextMonday.addDays(6);
    }
    g.members = *it;
    sortMembers(g.members, items);
    out.append(g);
  }
  return out;
}

}  // namespace heap::tasklist
