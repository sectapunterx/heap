#include "safety/SafetyText.h"
#include "safety/Standup.h"

#include <QSet>
#include <QStringList>

#include <algorithm>
#include <cmath>

namespace heap::safety {

namespace {

QString taskLine(const StandupTask* t, const QString& id) {
  if(t == nullptr || t->title.isEmpty()) {
    return id;
  }
  return id + QLatin1Char(' ') + t->title;
}

QString hhmm(double hour) {
  const int total = static_cast<int>(std::lround(hour * 60.0));
  return QStringLiteral("%1:%2").arg(total / 60, 2, 10, QLatin1Char('0')).arg(total % 60, 2, 10, QLatin1Char('0'));
}

// One prose line per section (N-Dlg-Recap, R3-072): "Yesterday: a, b." An
// empty section keeps its place with a dash.
QString section(const QString& heading, const QStringList& lines) {
  if(lines.isEmpty()) {
    return heading + QStringLiteral(" \u2014");
  }
  return heading + QLatin1Char(' ') + lines.join(QStringLiteral(", ")) + QLatin1Char('.');
}

}  // namespace

QString buildStandup(const StandupFacts& facts, bool ru) {
  QHash<QString, const StandupTask*> byId;
  for(const StandupTask& t : facts.tasks) {
    byId.insert(t.id, &t);
  }
  const auto statusName = [&facts](const QString& id) {
    const QString n = facts.statusNames.value(id);
    return n.isEmpty() ? id : n;
  };

  // ── Yesterday: what happened to each task, in the order it first moved ──
  struct Activity {
    QDateTime first;
    QString from;
    QString to;
    int commits = 0;
    bool timer = false;
  };

  QHash<QString, Activity> act;
  QStringList order;
  const auto touch = [&](const QString& id, const QDateTime& at) -> Activity& {
    if(!act.contains(id)) {
      order << id;
      act.insert(id, Activity{.first = at, .from = {}, .to = {}, .commits = 0, .timer = false});
    }
    Activity& a = act[id];
    if(at.isValid() && (!a.first.isValid() || at < a.first)) {
      a.first = at;
    }
    return a;
  };
  QVector<StandupMove> moves = facts.moves;
  std::ranges::sort(moves, [](const StandupMove& a, const StandupMove& b) {
    return a.at < b.at;
  });
  for(const StandupMove& m : moves) {
    if(m.at.date() != facts.previousDay || m.from == m.to) {
      continue;
    }
    Activity& a = touch(m.taskId, m.at);
    if(a.from.isEmpty()) {
      a.from = m.from;
    }
    a.to = m.to;
  }
  for(const StandupCommit& c : facts.commits) {
    if(c.at.date() == facts.previousDay) {
      ++touch(c.taskId, c.at).commits;
    }
  }
  for(const StandupTask& t : facts.tasks) {
    if(t.timerStartedAt.isValid() && t.timerStartedAt.date() == facts.previousDay) {
      touch(t.id, t.timerStartedAt).timer = true;
    }
  }
  std::ranges::stable_sort(order, [&act](const QString& a, const QString& b) {
    return act.value(a).first < act.value(b).first;
  });

  QStringList yesterday;
  for(const QString& id : order) {
    const Activity& a = act[id];
    QStringList facts2;
    // A task that went somewhere and came back did not move.
    if(!a.from.isEmpty() && a.from != a.to) {
      facts2 << statusName(a.from) + QStringLiteral(" → ") + statusName(a.to);
    }
    if(a.commits > 0) {
      facts2 << QStringLiteral("%1 %2").arg(a.commits).arg(plural(a.commits, text(QStringLiteral("safety.standup.commitForms"), ru)));
    }
    if(a.timer && facts2.isEmpty()) {
      facts2 << text(QStringLiteral("safety.standup.timer"), ru);
    }
    if(facts2.isEmpty()) {
      continue;
    }
    yesterday << taskLine(byId.value(id), id) + QStringLiteral(" (") + facts2.join(QStringLiteral(" · ")) + QLatin1Char(')');
  }
  QSet<QString> seenMeetings;
  for(const StandupMeeting& m : facts.meetings) {
    if(m.date != facts.previousDay || m.title.isEmpty() || seenMeetings.contains(m.title)) {
      continue;
    }
    seenMeetings.insert(m.title);
    yesterday << text(QStringLiteral("safety.standup.meeting"), ru).arg(m.title);
  }

  // ── Today: what is in progress or planned for today, and today's meetings ──
  QStringList today;
  for(const StandupTask& t : facts.tasks) {
    if(t.archived || t.done || t.blocked) {
      continue;
    }
    const bool planned = t.scheduledAt.isValid() && t.scheduledAt.date() == facts.today;
    if(t.doing || planned) {
      today << taskLine(&t, t.id);
    }
  }
  QVector<StandupMeeting> todays;
  for(const StandupMeeting& m : facts.meetings) {
    if(m.date == facts.today && !m.title.isEmpty()) {
      todays.append(m);
    }
  }
  std::ranges::stable_sort(todays, [](const StandupMeeting& a, const StandupMeeting& b) {
    return a.start < b.start;
  });
  for(const StandupMeeting& m : todays) {
    today << (m.allDay ? m.title : text(QStringLiteral("safety.standup.at"), ru).arg(m.title, hhmm(m.start)));
  }

  // ── Blockers ──
  QStringList blockers;
  for(const StandupTask& t : facts.tasks) {
    if(t.blocked && !t.archived) {
      blockers << taskLine(&t, t.id);
    }
  }

  return section(text(QStringLiteral("safety.standup.yesterday"), ru), yesterday) + QLatin1Char('\n') +
         section(text(QStringLiteral("safety.standup.today"), ru), today) + QLatin1Char('\n') +
         section(text(QStringLiteral("safety.standup.blockers"), ru), blockers);
}

}  // namespace heap::safety
