#pragma once

#include <QByteArray>
#include <QDate>
#include <QDateTime>
#include <QString>
#include <QStringList>
#include <QTime>
#include <QVector>

#include <initializer_list>

// The end-of-day safety net (APP-157): at a time the user picks, once a day,
// one quiet notice about what is easy to leave behind — a timer still running,
// work not committed in the repository of the current branch's task, tasks
// sitting in progress without a sign of life. It says what it noticed and
// nothing else: it stops no timer and moves no card.
//
// Everything here is pure and takes `now`, so the rules are tested without a
// clock, a repository or a window.
namespace heap::safety {

// The working tree of one repository, as `git status --porcelain` and
// `git stash list` reported it.
struct RepoDirt {
  QString repo;  // display name ("heap"), not the path
  int changedFiles = 0;
  int stashes = 0;
};

// A task in an in-progress column and the newest thing known to have happened
// to it: a status move, a timer started on it, a commit naming it.
struct InProgressTask {
  QString taskId;
  QDateTime lastActivity;  // invalid = nothing known
};

struct EndOfDayFacts {
  QStringList runningTimerTaskIds;
  RepoDirt dirt;
  QVector<InProgressTask> inProgress;
};

struct EndOfDaySettings {
  QTime at = QTime(18, 0);
  int staleDays = 3;
};

struct EndOfDayFindings {
  QStringList timerTaskIds;
  int changedFiles = 0;
  int stashes = 0;
  QString repo;
  QStringList staleTaskIds;

  bool any() const {
    return !timerTaskIds.isEmpty() || changedFiles > 0 || stashes > 0 || !staleTaskIds.isEmpty();
  }

  // The tasks the notice is about, for opening the board on them.
  QStringList taskIds() const {
    QStringList out = timerTaskIds;
    for(const QString& id : staleTaskIds) {
      if(!out.contains(id)) {
        out << id;
      }
    }
    return out;
  }

  bool operator==(const EndOfDayFindings&) const = default;
};

// The newest of the given instants; invalid ones are ignored.
inline QDateTime newest(std::initializer_list<QDateTime> times) {
  QDateTime out;
  for(const QDateTime& t : times) {
    if(t.isValid() && (!out.isValid() || t > out)) {
      out = t;
    }
  }
  return out;
}

// What the notice would say at `now`. A task whose last activity is unknown is
// never called stale: heap cannot tell "untouched for a week" from "imported a
// minute ago with no history".
inline EndOfDayFindings endOfDayFindings(const EndOfDayFacts& facts, const QDateTime& now, const EndOfDaySettings& settings) {
  EndOfDayFindings f;
  f.timerTaskIds = facts.runningTimerTaskIds;
  f.changedFiles = qMax(0, facts.dirt.changedFiles);
  f.stashes = qMax(0, facts.dirt.stashes);
  if(f.changedFiles > 0 || f.stashes > 0) {
    f.repo = facts.dirt.repo;
  }
  const int days = qMax(1, settings.staleDays);
  for(const InProgressTask& t : facts.inProgress) {
    if(!t.lastActivity.isValid() || f.timerTaskIds.contains(t.taskId)) {
      continue;  // a running timer is activity, and is already said
    }
    if(t.lastActivity.addDays(days) <= now) {
      f.staleTaskIds << t.taskId;
    }
  }
  return f;
}

// Whether the check is due at `now`: the set time has come today and it has
// not run today yet. A day the app was closed at the set time is not made up
// for the next morning — once `now` is past midnight, it is a new day whose
// time has not come yet.
inline bool shouldFireToday(const QDate& lastFired, const QDateTime& now, const QTime& at) {
  if(!now.isValid() || !at.isValid()) {
    return false;
  }
  if(lastFired.isValid() && lastFired >= now.date()) {
    return false;
  }
  return now.time() >= at;
}

// Entries in `git status --porcelain` output: one per changed or untracked
// path. A rename is one line and one file.
inline int countPorcelainEntries(const QByteArray& out) {
  int n = 0;
  for(const QByteArray& line : out.split('\n')) {
    if(line.trimmed().size() >= 2) {
      ++n;
    }
  }
  return n;
}

// Entries in `git stash list` output.
inline int countStashEntries(const QByteArray& out) {
  int n = 0;
  for(const QByteArray& line : out.split('\n')) {
    if(line.trimmed().startsWith("stash@{")) {
      ++n;
    }
  }
  return n;
}

}  // namespace heap::safety
