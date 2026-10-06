#pragma once

#include <QDate>
#include <QDateTime>
#include <QHash>
#include <QString>
#include <QVector>

// The standup draft (APP-170): "Yesterday / Today / Blockers", written from
// what heap already knows — column moves, commits naming a task, a timer
// started on it, meetings on the calendar, blocked cards. It is a draft the
// user edits and copies; heap sends it nowhere and plans nothing.
//
// Pure: the caller gathers the facts, this only words them, so the rules are
// tested without a clock or a workspace.
namespace heap::safety {

struct StandupTask {
  QString id;
  QString title;
  QString status;
  bool doing = false;  // an in-progress column
  bool blocked = false;
  bool done = false;
  bool archived = false;
  QDateTime scheduledAt;
  QDateTime timerStartedAt;
};

struct StandupMove {
  QString taskId;
  QString from;
  QString to;
  QDateTime at;
};

struct StandupCommit {
  QString taskId;
  QString subject;
  QDateTime at;
};

struct StandupMeeting {
  QString title;
  QDate date;
  double start = 0;  // hour, 0..24
  bool allDay = false;
};

struct StandupFacts {
  QDate previousDay;  // the last working day before today
  QDate today;
  QVector<StandupTask> tasks;
  QVector<StandupMove> moves;
  QVector<StandupCommit> commits;
  QVector<StandupMeeting> meetings;
  QHash<QString, QString> statusNames;  // id → column name
};

// The last working day before `today`; `isWorkDay` is Monday to Friday unless
// given. A week with no working day at all falls back to yesterday.
template<class IsWorkDay>
QDate previousWorkDay(const QDate& today, IsWorkDay isWorkDay) {
  for(int back = 1; back <= 7; ++back) {
    const QDate d = today.addDays(-back);
    if(isWorkDay(d)) {
      return d;
    }
  }
  return today.addDays(-1);
}

// The draft, in the UI language:
//
//   Yesterday:
//   - APP-12 Login rate limit: In progress → Review · 3 commits
//   - Meeting: Sync with the team
//   Today:
//   - APP-12 Login rate limit
//   - 15:00 1:1 with Oleg
//   Blockers:
//   - APP-20 Deploy pipeline
//
// An empty section says so ("—") rather than vanishing, so the shape the team
// expects is always there to fill in.
QString buildStandup(const StandupFacts& facts, bool ru);

}  // namespace heap::safety
