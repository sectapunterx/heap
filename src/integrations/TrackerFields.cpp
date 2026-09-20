#include "integrations/TrackerFields.h"

#include <QJsonArray>
#include <QRegularExpression>
#include <QStringList>

#include <cstdlib>

namespace heap::integrations {

namespace {

// Walk one dot-path ("status.name") through nested JSON. A segment that is all
// digits indexes an array; QJsonArray::at answers Undefined when the index is
// out of range, so no bounds check is needed.
QJsonValue valueAtSinglePath(const QJsonObject& obj, const QString& path) {
  if(path.isEmpty()) {
    return {};
  }
  const QStringList parts = path.split('.');
  QJsonValue cur = obj;
  for(const QString& part : parts) {
    bool isIndex = false;
    const int idx = part.toInt(&isIndex);
    if(isIndex && idx >= 0 && cur.isArray()) {
      cur = cur.toArray().at(idx);
      continue;
    }
    if(!cur.isObject()) {
      return {};
    }
    cur = cur.toObject().value(part);
  }
  return cur;
}

QString leafToString(const QJsonValue& v) {
  if(v.isString()) {
    return v.toString();
  }
  if(v.isBool()) {
    return v.toBool() ? QStringLiteral("true") : QStringLiteral("false");
  }
  if(v.isDouble()) {
    const double d = v.toDouble();
    const auto asLong = static_cast<qlonglong>(d);
    if(static_cast<double>(asLong) == d) {
      return QString::number(asLong);
    }
    return QString::number(d);
  }
  return {};
}

}  // namespace

QJsonValue valueAtPath(const QJsonObject& obj, const QString& path) {
  // "a|b" = the first alternative that resolves to something non-empty. Asana
  // carries a due date in either due_at or due_on; GitHub puts the owner in
  // assignees[] or the singular assignee.
  if(!path.contains(QChar('|'))) {
    return valueAtSinglePath(obj, path);
  }
  for(const QString& alt : path.split(QChar('|'))) {
    const QJsonValue v = valueAtSinglePath(obj, alt.trimmed());
    if(!v.isUndefined() && !v.isNull() && !leafToString(v).isEmpty()) {
      return v;
    }
  }
  return {};
}

QString fieldStr(const QJsonObject& obj, const QString& path) {
  return leafToString(valueAtPath(obj, path));
}

QDateTime parseTrackerTimestamp(const QJsonValue& v, bool* hasTime) {
  const auto answer = [hasTime](const QDateTime& dt, bool withClock) {
    if(hasTime) {
      *hasTime = dt.isValid() && withClock;
    }
    return dt;
  };
  const QString s = leafToString(v).trimmed();
  if(s.isEmpty()) {
    return answer({}, false);
  }
  // Epoch milliseconds, as a number (Trello) or as a string (ClickUp). A value
  // below 1e11 is a count or a year, not an instant.
  bool numeric = false;
  const qlonglong ms = s.toLongLong(&numeric);
  if(numeric && std::llabs(ms) >= 100000000000LL) {
    return answer(QDateTime::fromMSecsSinceEpoch(ms).toLocalTime(), true);
  }
  // A bare "2026-09-20" is a day, not an instant: keep it at local midnight so
  // it compares equal to a deadline the user typed by hand.
  if(s.size() == 10) {
    const QDate d = QDate::fromString(s, Qt::ISODate);
    if(d.isValid()) {
      return answer(QDateTime(d, QTime(0, 0)), false);
    }
  }
  QDateTime dt = QDateTime::fromString(s, Qt::ISODate);
  if(!dt.isValid()) {
    dt = QDateTime::fromString(s, Qt::ISODateWithMs);
  }
  if(!dt.isValid()) {
    // Jira sends "+0000" with no colon, which Qt::ISODate rejects outright.
    static const QRegularExpression bareOffset(QStringLiteral(R"(([+-]\d{2})(\d{2})$)"));
    const QRegularExpressionMatch m = bareOffset.match(s);
    if(m.hasMatch()) {
      QString fixed = s;
      fixed.replace(m.capturedStart(), m.capturedLength(), m.captured(1) + QChar(':') + m.captured(2));
      dt = QDateTime::fromString(fixed, Qt::ISODateWithMs);
      if(!dt.isValid()) {
        dt = QDateTime::fromString(fixed, Qt::ISODate);
      }
    }
  }
  if(!dt.isValid()) {
    return answer({}, false);
  }
  return answer(dt.toLocalTime(), true);
}

QString normalizeHexColor(const QString& raw) {
  QString c = raw.trimmed();
  if(c.isEmpty()) {
    return {};
  }
  // GitHub and Gitea send "d73a4a"; everyone else sends "#d73a4a".
  if(!c.startsWith(QChar('#'))) {
    c.prepend(QChar('#'));
  }
  static const QRegularExpression hex(QStringLiteral("^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"));
  return hex.match(c).hasMatch() ? c : QString();
}

QString sanitizeProject(const QString& raw) {
  const QString p = raw.trimmed();
  if(p.isEmpty()) {
    return {};
  }
  // The project is interpolated into a URL path (comments) and into a task id.
  // Anything that is not a plain path segment is dropped rather than escaped.
  // A segment of "." or ".." would climb out of the path it is spliced into, so
  // the shape check alone is not enough — dots are legal inside a repo name.
  static const QRegularExpression shape(QStringLiteral(R"(^[\w.~-]+(?:/[\w.~-]+)*$)"));
  if(!shape.match(p).hasMatch()) {
    return {};
  }
  for(const QString& segment : p.split(QChar('/'))) {
    if(segment == QStringLiteral(".") || segment == QStringLiteral("..")) {
      return {};
    }
  }
  return p;
}

QString joinObjectField(const QJsonValue& array, const QString& key) {
  QStringList names;
  for(const auto& v : array.toArray()) {
    const QString name = v.toObject().value(key).toString();
    if(!name.isEmpty()) {
      names.append(name);
    }
  }
  return names.join(QStringLiteral(", "));
}

}  // namespace heap::integrations
