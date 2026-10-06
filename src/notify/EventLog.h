#pragma once

#include <QDateTime>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

#include <deque>

// The event log (APP-187): what the toasts said, kept for a while so a missed
// one can be read again. Syncs that brought news, refusals, errors, actions
// that can be undone, failed saves. Each entry can point at what it is about:
// the tasks it names, or a place in the app ("settings:integrations").
//
// This session only and capped at kCapacity entries, oldest dropped first:
// a short memory, not a history. Nothing of it is saved or synced.
namespace heap::notify {

struct LogEntry {
  int id = 0;
  QDateTime at;
  // "sync" | "error" | "warning" | "undo" | "info"
  QString kind;
  QString message;
  QStringList taskIds;
  QString route;
  // The same entry said again in a row ("Jira sync failed" on every
  // auto-sync) is one entry with a count, not a column of copies.
  int count = 1;
};

class EventLog {
 public:
  static constexpr int kCapacity = 100;

  // Appends an entry, or folds it into the newest one when that says the
  // same thing about the same objects. Returns the entry's id.
  int add(const QDateTime& at, const QString& kind, const QString& message, const QStringList& taskIds = {}, const QString& route = {}) {
    if(!m_entries.empty()) {
      LogEntry& last = m_entries.back();
      if(last.kind == kind && last.message == message && last.taskIds == taskIds && last.route == route) {
        last.at = at;
        ++last.count;
        return last.id;
      }
    }
    LogEntry e;
    e.id = ++m_lastId;
    e.at = at;
    e.kind = kind;
    e.message = message;
    e.taskIds = taskIds;
    e.route = route;
    m_entries.push_back(e);
    while(m_entries.size() > static_cast<size_t>(kCapacity)) {
      m_entries.pop_front();
    }
    return e.id;
  }

  // Oldest first.
  const std::deque<LogEntry>& entries() const {
    return m_entries;
  }

  int size() const {
    return static_cast<int>(m_entries.size());
  }

  void clear() {
    m_entries.clear();
  }

  // Newest first, for the panel: { id, at, kind, message, taskIds, route, count }.
  QVariantList toVariantList() const {
    QVariantList out;
    out.reserve(static_cast<qsizetype>(m_entries.size()));
    for(auto it = m_entries.rbegin(); it != m_entries.rend(); ++it) {
      out.append(QVariantMap{{QStringLiteral("id"), it->id},
                             {QStringLiteral("at"), it->at},
                             {QStringLiteral("kind"), it->kind},
                             {QStringLiteral("message"), it->message},
                             {QStringLiteral("taskIds"), it->taskIds},
                             {QStringLiteral("route"), it->route},
                             {QStringLiteral("count"), it->count}});
    }
    return out;
  }

 private:
  std::deque<LogEntry> m_entries;
  int m_lastId = 0;
};

}  // namespace heap::notify
