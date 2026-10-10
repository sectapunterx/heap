#include "integrations/Sprints.h"
#include "integrations/TrackerFields.h"

#include <QHash>
#include <QJsonObject>

#include <algorithm>

namespace heap::integrations {

namespace {

QDate localDate(const QJsonValue& v) {
  const QDateTime at = parseTrackerTimestamp(v);
  return at.isValid() ? at.toLocalTime().date() : QDate();
}

}  // namespace

SprintMarker sprintOf(const Task& t) {
  const QJsonObject s = t.externalMeta.details.value(QStringLiteral("sprint")).toObject();
  SprintMarker m;
  m.name = s.value(QStringLiteral("name")).toString();
  if(m.name.isEmpty()) {
    return {};
  }
  m.state = s.value(QStringLiteral("state")).toString();
  m.start = localDate(s.value(QStringLiteral("start")));
  m.end = localDate(s.value(QStringLiteral("end")));
  return m;
}

QVector<SprintMarker> sprintMarkers(const QVector<Task>& tasks, const QDate& from, const QDate& to) {
  QVector<SprintMarker> out;
  QHash<QString, qsizetype> at;
  for(const Task& t : tasks) {
    if(t.archived) {
      continue;
    }
    const SprintMarker m = sprintOf(t);
    if(m.name.isEmpty() || !m.end.isValid() || m.end < from || m.end > to) {
      continue;
    }
    const QString key = m.name + QChar('\n') + m.end.toString(Qt::ISODate);
    const auto it = at.constFind(key);
    if(it != at.constEnd()) {
      ++out[*it].tasks;
      continue;
    }
    at.insert(key, out.size());
    SprintMarker added = m;
    added.tasks = 1;
    out.append(added);
  }
  std::sort(out.begin(), out.end(), [](const SprintMarker& a, const SprintMarker& b) {
    return a.end != b.end ? a.end < b.end : a.name < b.name;
  });
  return out;
}

SprintMarker currentSprint(const QVector<Task>& tasks, const QDate& today) {
  SprintMarker best;
  for(const Task& t : tasks) {
    if(t.archived) {
      continue;
    }
    const SprintMarker m = sprintOf(t);
    if(m.name.isEmpty() || m.state != QLatin1String("active") || (m.end.isValid() && m.end < today)) {
      continue;
    }
    if(best.name.isEmpty() || (m.end.isValid() && (!best.end.isValid() || m.end < best.end))) {
      best = m;
    }
  }
  return best;
}

}  // namespace heap::integrations
