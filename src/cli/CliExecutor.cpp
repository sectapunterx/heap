#include "AppController.h"

#include "cli/CliExecutor.h"
#include "cli/CliQuery.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QStringList>

namespace heap::cli {

namespace {

Snapshot snapshotOf(const AppController& c) {
  return snapshotFromProfiles(c.profilesSnapshot(), c.activeProfileId(), c.taskIdPrefix(), c.language());
}

Response failure(int code, const QString& message) {
  Response r;
  r.exitCode = code;
  r.err = QStringLiteral("lowkey: ") + message + QChar('\n');
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

// `key` is a cliText line taking the id and the title.
Response taskResult(const AppController& c, const QString& taskId, const QString& key, bool json, const QDateTime& now) {
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
    r.out = cliText(key, after.language).arg(t.id, t.title) + QChar('\n');
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
        r.out = cliText(QStringLiteral("added"), after.language).arg(t.id, t.title) + QChar('\n');
      }
      return r;
    }
  }
  return failure(kExitData, QStringLiteral("the task was not saved: %1").arg(reasons(toasts, QStringLiteral("unknown reason"))));
}

Response done(AppController& c, const Request& req, const QDateTime& now) {
  const Snapshot before = snapshotOf(c);
  QString why;
  const TaskRef ref = resolveTaskArg(before, req.taskId, req.branch, &why);
  if(!ref.found()) {
    return failure(kExitNotFound, why);
  }
  const ProfileData& p = before.profiles.at(ref.profile);
  const Task& t = p.tasks.at(ref.task);
  const QString target = doneStatus(p.statuses);
  if(t.status == target) {
    return taskResult(c, t.id, QStringLiteral("alreadyDone"), req.json, now);
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
    // Not the user's click in the window: no sound (APP-177).
    c.setSoundMuted(true);
    c.moveTask(id, target);
    c.setSoundMuted(false);
    const Snapshot after = snapshotOf(c);
    const TaskRef moved_ref = findTask(after, id, findProfile(after, QString()));
    moved = moved_ref.found() && after.profiles.at(moved_ref.profile).tasks.at(moved_ref.task).status == target;
  }
  if(!moved) {
    return failure(
        kExitData,
        QStringLiteral("could not move %1 to %2: %3").arg(id, statusName(p.statuses, target), reasons(toasts, QStringLiteral("refused"))));
  }
  return taskResult(c, id, QStringLiteral("done"), req.json, now);
}

Response open(AppController& c, const Request& req) {
  const Snapshot s = snapshotOf(c);
  QString why;
  const TaskRef ref = resolveTaskArg(s, req.taskId, req.branch, &why);
  if(!ref.found()) {
    return failure(kExitNotFound, why);
  }
  const ProfileData& p = s.profiles.at(ref.profile);
  const QString id = p.tasks.at(ref.task).id;
  // Opening a task of another profile is going there.
  const ProfileScope scope(c, p.id, /*restore=*/false);
  emit c.openTaskRequested(id, p.id);
  Response r;
  r.out = req.json ? QString::fromUtf8(QJsonDocument(QJsonObject{{QStringLiteral("id"), id}}).toJson(QJsonDocument::Compact)) + QChar('\n')
                   : cliText(QStringLiteral("opened"), s.language).arg(id) + QChar('\n');
  return r;
}

// One line of fact about the change, or the task as JSON with `changed`.
Response changeResult(const AppController& c, const QString& taskId, const QString& line, bool changed, bool json, const QDateTime& now) {
  Response r;
  if(!json) {
    r.out = line + QChar('\n');
    return r;
  }
  const Snapshot after = snapshotOf(c);
  const TaskRef ref = findTask(after, taskId, findProfile(after, QString()));
  if(!ref.found()) {
    return r;
  }
  QJsonObject o = taskJson(after.profiles.at(ref.profile), after.profiles.at(ref.profile).tasks.at(ref.task), now);
  o.insert(QStringLiteral("changed"), changed);
  o.insert(QStringLiteral("estimateMinutes"), after.profiles.at(ref.profile).tasks.at(ref.task).estimateMinutes);
  o.insert(QStringLiteral("someday"), after.profiles.at(ref.profile).tasks.at(ref.task).someday);
  r.out = QString::fromUtf8(QJsonDocument(o).toJson(QJsonDocument::Indented));
  return r;
}

// The date words of `sched`/`due` read the way quick capture reads them
// ("tomorrow 14:00", "пт", "next monday 9:30"), or an ISO date. Nothing else
// may be left over: "sched X tomorrow or friday" is refused rather than half
// read.
bool readWhen(const AppController& c, const QString& text, const QDateTime& now, QDateTime* when, bool* hasTime) {
  const QDate iso = QDate::fromString(text.trimmed(), Qt::ISODate);
  if(iso.isValid()) {
    *when = QDateTime(iso, QTime(0, 0));
    *hasTime = false;
    return true;
  }
  const QDateTime isoTime = QDateTime::fromString(text.trimmed(), Qt::ISODate);
  if(isoTime.isValid()) {
    *when = isoTime;
    *hasTime = true;
    return true;
  }
  const QVariantMap p = c.captureParse(text, now, {});
  const QString rest = p.value(QStringLiteral("title")).toString().trimmed();
  QDateTime at = p.value(QStringLiteral("when")).toDateTime();
  bool timed = p.value(QStringLiteral("whenHasTime")).toBool();
  if(!at.isValid()) {
    at = p.value(QStringLiteral("due")).toDateTime();
    timed = p.value(QStringLiteral("dueHasTime")).toBool();
  }
  if(!at.isValid() || !rest.isEmpty()) {
    return false;
  }
  *when = at;
  *hasTime = timed;
  return true;
}

bool isNone(const QString& v) {
  return v.compare(QLatin1String("none"), Qt::CaseInsensitive) == 0 || v == QStringLiteral("нет");
}

Response setDate(AppController& c, const Request& req, const QString& id, const QDateTime& now) {
  const bool due = req.verb == Verb::Due;
  const QString field = due ? QStringLiteral("due") : QStringLiteral("scheduled");
  QDateTime when;
  bool hasTime = false;
  if(!isNone(req.value) && !readWhen(c, req.value, now, &when, &hasTime)) {
    return failure(kExitUsage,
                   QStringLiteral("could not read a date in '%1'; e.g. tomorrow 14:00, fri, 2026-10-12 or none").arg(req.value));
  }
  const QVariantMap before = c.taskById(id);
  const bool tracker = !before.value(QStringLiteral("externalProvider")).toString().isEmpty();
  const QString language = c.language();
  // Not the user's hand in the window: no sound.
  c.setSoundMuted(true);
  const bool changed = c.rescheduleTask(id, field, when, hasTime);
  c.setSoundMuted(false);
  QString line;
  if(!changed) {
    line = cliText(QStringLiteral("unchanged"), language).arg(id);
  } else if(!when.isValid()) {
    line = cliText(due ? QStringLiteral("dueCleared") : QStringLiteral("schedCleared"), language).arg(id);
  } else {
    line = cliText(due ? QStringLiteral("due") : QStringLiteral("sched"), language).arg(id, humanDate(when, hasTime, language, now.date()));
  }
  if(changed && due && tracker) {
    line += QStringLiteral(" (") + cliText(QStringLiteral("dueMine"), language) + QChar(')');
  }
  return changeResult(c, id, line, changed, req.json, now);
}

// Estimate and someday go through saveTask with the task's own draft, as the
// editor saves them: same undo step, same "someday files it under Backlog".
Response saveField(AppController& c, const Request& req, const QString& id, const QDateTime& now) {
  QVariantMap draft = c.taskById(id);
  const QString language = c.language();
  QString line;
  bool changed = false;
  if(req.verb == Verb::Est) {
    const int minutes = parseEstimate(req.value);
    if(minutes < 0) {
      return failure(kExitUsage, QStringLiteral("'%1' is not an estimate; e.g. 2h, 90m, 1h30m or none").arg(req.value));
    }
    changed = draft.value(QStringLiteral("estimateMinutes")).toInt() != minutes;
    draft.insert(QStringLiteral("estimateMinutes"), minutes);
    line = minutes == 0 ? cliText(QStringLiteral("estCleared"), language).arg(id)
                        : cliText(QStringLiteral("est"), language).arg(id, humanMinutes(minutes, language));
  } else {
    const bool on = req.value != QLatin1String("off");
    changed = draft.value(QStringLiteral("someday")).toBool() != on;
    draft.insert(QStringLiteral("someday"), on);
    line = cliText(on ? QStringLiteral("someday") : QStringLiteral("somedayOff"), language).arg(id);
  }
  if(!changed) {
    return changeResult(c, id, cliText(QStringLiteral("unchanged"), language).arg(id), false, req.json, now);
  }
  draft.insert(QStringLiteral("_originalId"), id);
  QStringList toasts;
  const QObject guard;
  QObject::connect(&c, &AppController::toast, &guard, [&toasts](const QString& message, const QString&) {
    toasts << message;
  });
  c.setSoundMuted(true);
  const bool saved = c.saveTask(draft);
  c.setSoundMuted(false);
  if(!saved) {
    return failure(kExitData, QStringLiteral("could not change %1: %2").arg(id, reasons(toasts, QStringLiteral("refused"))));
  }
  return changeResult(c, id, line, true, req.json, now);
}

// sched / due / est / someday: the task the argument names (any profile; "."
// the branch's), changed in its own profile.
Response plan(AppController& c, const Request& req, const QDateTime& now) {
  const Snapshot before = snapshotOf(c);
  QString why;
  const TaskRef ref = resolveTaskArg(before, req.taskId, req.branch, &why);
  if(!ref.found()) {
    return failure(kExitNotFound, why);
  }
  const ProfileData& p = before.profiles.at(ref.profile);
  const QString id = p.tasks.at(ref.task).id;
  const ProfileScope scope(c, p.id, /*restore=*/true);
  if(req.verb == Verb::Sched || req.verb == Verb::Due) {
    return setDate(c, req, id, now);
  }
  return saveField(c, req, id, now);
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
    case Verb::Sched:
    case Verb::Due:
    case Verb::Est:
    case Verb::Someday:
      return plan(controller, request, now);
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

Response applyHeadless(const Request& request, const QDateTime& now) {
  if(const QString unusable = unusableState(); !unusable.isEmpty()) {
    return failure(kExitData, QStringLiteral("nothing changed: ") + unusable);
  }
  Response r;
  AppController controller;
  if(controller.storageState() != QLatin1String("ok")) {
    r.exitCode = kExitData;
    r.err = QStringLiteral("lowkey: nothing changed: %1\n").arg(controller.storageMessage());
    return r;
  }
  r = execute(controller, request, now);
  controller.flushSave();
  if(controller.storageState() != QLatin1String("ok")) {
    r.exitCode = kExitData;
    r.err += QStringLiteral("lowkey: the change was not saved: %1\n").arg(controller.storageMessage());
  }
  return r;
}

}  // namespace heap::cli
