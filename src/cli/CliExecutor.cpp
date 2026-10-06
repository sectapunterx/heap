#include "AppController.h"

#include "cli/CliExecutor.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QStringList>

namespace heap::cli {

namespace {

Snapshot snapshotOf(const AppController& c) {
  return snapshotFromProfiles(c.profilesSnapshot(), c.activeProfileId(), c.taskIdPrefix());
}

Response failure(int code, const QString& message) {
  Response r;
  r.exitCode = code;
  r.err = QStringLiteral("heap: ") + message + QChar('\n');
  return r;
}

// What the controller said while refusing something: its toasts carry the
// reason ("ID is taken", "blocked by …").
QString reasons(const QStringList& toasts, const QString& fallback) {
  return toasts.isEmpty() ? fallback : toasts.join(QStringLiteral("; "));
}

// Makes `profileId` the active profile for the lifetime of the scope, and puts
// the one the user had back afterwards.
class ProfileScope {
 public:
  ProfileScope(AppController& c, const QString& profileId, bool restore) :
      m_controller(c), m_previous(c.activeProfileId()), m_restore(restore) {
    if(profileId != m_previous) {
      c.setActiveProfileId(profileId);
    } else {
      m_restore = false;
    }
  }

  ~ProfileScope() {
    if(m_restore) {
      m_controller.setActiveProfileId(m_previous);
    }
  }

  ProfileScope(const ProfileScope&) = delete;
  ProfileScope& operator=(const ProfileScope&) = delete;

 private:
  AppController& m_controller;
  QString m_previous;
  bool m_restore;
};

Response taskResult(const AppController& c, const QString& taskId, const QString& verb, bool json, const QDateTime& now) {
  const Snapshot after = snapshotOf(c);
  const TaskRef ref = findTask(after, taskId, findProfile(after, QString()));
  Response r;
  if(!ref.found()) {
    return r;  // nothing more to say than the exit code
  }
  const ProfileData& p = after.profiles.at(ref.profile);
  const Task& t = p.tasks.at(ref.task);
  if(json) {
    r.out = QString::fromUtf8(QJsonDocument(taskJson(p, t, now)).toJson(QJsonDocument::Indented));
  } else {
    r.out = QStringLiteral("%1 %2: %3\n").arg(verb, t.id, t.title);
  }
  return r;
}

Response add(AppController& c, const Request& req, const QDateTime& now) {
  const Snapshot before = snapshotOf(c);
  const int pi = findProfile(before, req.profile);
  if(pi < 0) {
    return failure(kExitNotFound, QStringLiteral("no profile '%1'").arg(req.profile));
  }
  QStringList toasts;
  const QObject guard;
  QObject::connect(&c, &AppController::toast, &guard, [&toasts](const QString& message, const QString&) {
    toasts << message;
  });
  QString id;
  {
    const ProfileScope scope(c, before.profiles.at(pi).id, /*restore=*/true);
    const QVariantMap draft = c.quickTaskDraft(req.text, now);
    if(draft.value(QStringLiteral("title")).toString().trimmed().isEmpty()) {
      return failure(kExitUsage, QStringLiteral("nothing to add: '%1' has no title besides the date").arg(req.text));
    }
    id = draft.value(QStringLiteral("id")).toString();
    if(!c.saveTask(draft)) {
      return failure(kExitData, QStringLiteral("could not add the task: %1").arg(reasons(toasts, QStringLiteral("refused"))));
    }
  }
  // The task lives in profile `pi`, whichever one is active now.
  const Snapshot after = snapshotOf(c);
  const int api = findProfile(after, before.profiles.at(pi).id);
  if(api >= 0) {
    const ProfileData& p = after.profiles.at(api);
    for(const Task& t : p.tasks) {
      if(t.id != id) {
        continue;
      }
      Response r;
      if(req.json) {
        r.out = QString::fromUtf8(QJsonDocument(taskJson(p, t, now)).toJson(QJsonDocument::Indented));
      } else {
        r.out = QStringLiteral("Added %1: %2\n").arg(t.id, t.title);
      }
      return r;
    }
  }
  return failure(kExitData, QStringLiteral("the task was not saved: %1").arg(reasons(toasts, QStringLiteral("unknown reason"))));
}

Response done(AppController& c, const Request& req, const QDateTime& now) {
  const Snapshot before = snapshotOf(c);
  const TaskRef ref = findTask(before, req.taskId, findProfile(before, QString()));
  if(!ref.found()) {
    return failure(kExitNotFound, QStringLiteral("no task '%1'").arg(req.taskId));
  }
  const ProfileData& p = before.profiles.at(ref.profile);
  const Task& t = p.tasks.at(ref.task);
  const QString target = doneStatus(p.statuses);
  if(t.status == target) {
    return taskResult(c, t.id, QStringLiteral("Already done"), req.json, now);
  }
  QStringList toasts;
  const QObject guard;
  QObject::connect(&c, &AppController::toast, &guard, [&toasts](const QString& message, const QString&) {
    toasts << message;
  });
  const QString id = t.id;
  bool moved = false;
  {
    const ProfileScope scope(c, p.id, /*restore=*/true);
    // Not the user's click in the window: no completion sound (APP-167).
    c.setCompletionSoundMuted(true);
    c.moveTask(id, target);
    c.setCompletionSoundMuted(false);
    const Snapshot after = snapshotOf(c);
    const TaskRef moved_ref = findTask(after, id, findProfile(after, QString()));
    moved = moved_ref.found() && after.profiles.at(moved_ref.profile).tasks.at(moved_ref.task).status == target;
  }
  if(!moved) {
    return failure(
        kExitData,
        QStringLiteral("could not move %1 to %2: %3").arg(id, statusName(p.statuses, target), reasons(toasts, QStringLiteral("refused"))));
  }
  return taskResult(c, id, QStringLiteral("Done"), req.json, now);
}

Response open(AppController& c, const Request& req) {
  const Snapshot s = snapshotOf(c);
  const TaskRef ref = findTask(s, req.taskId, findProfile(s, QString()));
  if(!ref.found()) {
    return failure(kExitNotFound, QStringLiteral("no task '%1'").arg(req.taskId));
  }
  const ProfileData& p = s.profiles.at(ref.profile);
  const QString id = p.tasks.at(ref.task).id;
  // Opening a task of another profile is going there.
  const ProfileScope scope(c, p.id, /*restore=*/false);
  emit c.openTaskRequested(id);
  Response r;
  r.out = req.json ? QString::fromUtf8(QJsonDocument(QJsonObject{{QStringLiteral("id"), id}}).toJson(QJsonDocument::Compact)) + QChar('\n')
                   : QStringLiteral("Opened %1\n").arg(id);
  return r;
}

}  // namespace

Response execute(AppController& controller, const Request& request, const QDateTime& now) {
  switch(request.verb) {
    case Verb::Add:
      return add(controller, request, now);
    case Verb::Done:
      return done(controller, request, now);
    case Verb::Open:
      return open(controller, request);
    case Verb::Now:
    case Verb::List:
    case Verb::Today:
      return answer(snapshotOf(controller), request, now);
    case Verb::Help:
    case Verb::Version:
      break;
  }
  Response r;
  r.out = helpText();
  return r;
}

}  // namespace heap::cli
