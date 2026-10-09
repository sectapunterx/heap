// heap staying around: start at login (APP-154) and reminders with buttons
// that put them off or open what they are about (APP-155).
#include "AppController.h"

#include "notify/NotificationCenter.h"
#include "platform/Autostart.h"
#include "platform/Paths.h"
#include "text/LocaleFormat.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>

QVariantMap AppController::autostartState() const {
  namespace as = heap::platform::autostart;
  const as::Entry entry = as::read();
  const QVariantMap sys = settingsMap().value(QStringLiteral("system")).toMap();
  QVariantMap out;
  out[QStringLiteral("supported")] = as::supported();
  out[QStringLiteral("enabled")] = entry.enabled;
  out[QStringLiteral("minimized")] = entry.enabled ? entry.minimized : sys.value(QStringLiteral("startMinimized"), false).toBool();
  return out;
}

bool AppController::setAutostart(bool enabled, bool minimized) {
  namespace as = heap::platform::autostart;
  const bool ok = as::write(enabled, minimized);
  if(!ok) {
    emit toast(tr_("settings.system.startAtLogin.failed"), QStringLiteral("error"));
  }

  QJsonObject root = QJsonDocument::fromJson(m_appSettingsJson.toUtf8()).object();
  QJsonObject sys = root.value(QStringLiteral("system")).toObject();
  sys[QStringLiteral("startAtLogin")] = as::read().enabled;
  sys[QStringLiteral("startMinimized")] = minimized;
  // A login start is pointless if the first close quits heap again; only an
  // unanswered question is answered here, never the user's own "quit".
  if(enabled && ok && !sys.contains(QStringLiteral("closeToTray"))) {
    sys[QStringLiteral("closeToTray")] = true;
  }
  root[QStringLiteral("system")] = sys;
  setAppSettingsJson(QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Compact)));
  return ok;
}

// ── Reminder buttons (APP-155) ──────────────────────────────────────

namespace {

// A meeting or the standup is an appointment: it has a day to open, not a task.
bool isAppointment(const QString& kind) {
  return kind == QStringLiteral("meeting") || kind == QStringLiteral("standup");
}

}  // namespace

QVector<heap::notify::NotificationAction> AppController::reminderActions(const QString& kind) const {
  namespace hn = heap::notify;
  const QVariantMap notif = settingsMap().value(QStringLiteral("notifications")).toMap();
  const bool ru = m_language == QStringLiteral("ru");
  const int shortMin = notif.value(QStringLiteral("snoozeShortMin"), hn::kDefaultSnoozeShortMin).toInt();
  const int longMin = notif.value(QStringLiteral("snoozeLongMin"), hn::kDefaultSnoozeLongMin).toInt();
  const QString snoozeShort = QString::fromLatin1(hn::kSnoozeShort);
  const QString snoozeLong = QString::fromLatin1(hn::kSnoozeLong);
  QVector<hn::NotificationAction> out{{snoozeShort, hn::snoozeLabel(hn::snoozeMinutesFor(snoozeShort, shortMin, longMin), ru)},
                                      {snoozeLong, hn::snoozeLabel(hn::snoozeMinutesFor(snoozeLong, shortMin, longMin), ru)},
                                      {QString::fromLatin1(hn::kOpen), tr_(QStringLiteral("notify.action.open"))}};
  // A task's reminder can also close it, as the Linux toasts always could.
  if(!isAppointment(kind) && kind != QStringLiteral("test")) {
    out.append({QString::fromLatin1(hn::kDone), tr_(QStringLiteral("notify.action.done"))});
  }
  return out;
}

bool AppController::handleNotificationUri(const QString& uri) {
  return m_notifier && m_notifier->handleActivationUri(uri);
}

void AppController::sendTestNotification() {
  if(!m_notifier) {
    return;
  }
  heap::notify::Notification n;
  n.id = heap::notify::routingId(QStringLiteral("test"), QStringLiteral("heap"));
  n.title = tr_(QStringLiteral("notify.test.title"));
  n.body = tr_(QStringLiteral("notify.test.body"));
  n.iconPath = QStringLiteral(":/brand/lowkey/lowkey-icon.svg");
  n.category = QStringLiteral("test");
  if(m_notifier->supportsActions()) {
    n.actions = reminderActions(n.category);
  }
  m_shownReminders.insert(n.id, {n.title, n.body, n.category, QDate()});
  m_notifier->post(n);
}

void AppController::snoozeReminderAt(const QString& notificationId, int minutes, const QDateTime& now) {
  const auto [kind, ref] = heap::notify::parseRoutingId(notificationId);
  if(ref.isEmpty()) {
    return;
  }
  ShownReminder shown = m_shownReminders.value(notificationId);
  // Shown before a restart: the words are gone, the task's title is not.
  if(shown.title.isEmpty()) {
    shown.title = tr_(QStringLiteral("notify.reminderTitle"));
    shown.body = reminderTask(ref).task.title;
  }
  heap::notify::SnoozedReminder s;
  s.id = notificationId;
  s.title = shown.title;
  s.body = shown.body;
  s.kind = shown.kind.isEmpty() ? kind : shown.kind;
  s.fireAt = heap::notify::snoozeUntil(now, minutes);
  heap::notify::upsertSnooze(m_snoozed, s);
  saveSnoozes();
  if(m_notifier) {
    m_notifier->dismiss(notificationId);
  }
  emit toast(tr_(QStringLiteral("notify.snoozedUntil")).arg(heap::text::formatTime(s.fireAt.time(), twelveHourClock())));
}

void AppController::fireDueSnoozes(const QDateTime& now) {
  const QVector<heap::notify::SnoozedReminder> due = heap::notify::takeDueSnoozes(m_snoozed, now);
  if(due.isEmpty()) {
    return;
  }
  saveSnoozes();
  // A task finished or deleted since the snooze has nothing left to say. Any
  // profile: reminders cover them all.
  const auto stillOpen = [this](const QString& ref) {
    const ReminderTask r = reminderTask(ref);
    return !r.profileId.isEmpty() && !r.task.archived && r.task.status != QStringLiteral("done");
  };
  for(const heap::notify::SnoozedReminder& s : due) {
    const auto [kind, ref] = heap::notify::parseRoutingId(s.id);
    if(isAppointment(kind) || kind == QStringLiteral("test")) {
      emit notification(s.title, s.body, s.kind, s.id);
    } else if(stillOpen(ref)) {
      notifyTaskAt(ref, s.title, s.body, kind, now);
    }
  }
}

void AppController::openReminder(const QString& notificationId) {
  const auto [kind, ref] = heap::notify::parseRoutingId(notificationId);
  if(isAppointment(kind)) {
    const QDate date = m_shownReminders.value(notificationId).date;
    emit openEventRequested(kind == QStringLiteral("meeting") ? ref : QString(), date.isValid() ? date : today());
    return;
  }
  // Reminders cover every profile; opening one goes to the workspace it is in.
  // The window switches there itself, once an open editor's edits are settled
  // (PRES-1): switching here came first and left that editor saving into the
  // other profile.
  const ReminderTask target = reminderTask(ref);
  if(!target.profileId.isEmpty()) {
    emit openTaskRequested(target.task.id, target.profileId);
  } else {
    emit showWindowRequested();
  }
}

AppController::ReminderTask AppController::reminderTask(const QString& ref) const {
  const auto inProfile = [this](const QString& profileId, const QString& taskId) -> ReminderTask {
    if(profileId == m_activeProfileId) {
      const int row = m_tasks.indexOfId(taskId);
      return row >= 0 ? ReminderTask{profileId, m_tasks.items().at(row)} : ReminderTask{};
    }
    const int p = profileIndexOf(profileId);
    if(p < 0) {
      return {};
    }
    for(const Task& t : m_profiles.at(p).tasks) {
      if(t.id == taskId) {
        return {profileId, t};
      }
    }
    return {};
  };
  if(ref.isEmpty()) {
    return {};
  }
  // The profile it names, and no other: a namesake elsewhere is another task
  // (PRES-2).
  const auto [profileId, taskId] = heap::notify::parseTaskRef(ref);
  if(!profileId.isEmpty() && profileIndexOf(profileId) >= 0) {
    return inProfile(profileId, taskId);
  }
  // A ref from before profiles were named: the active profile first.
  if(ReminderTask r = inProfile(m_activeProfileId, ref); !r.profileId.isEmpty()) {
    return r;
  }
  for(const Profile& p : m_profiles) {
    if(p.id != m_activeProfileId) {
      if(ReminderTask r = inProfile(p.id, ref); !r.profileId.isEmpty()) {
        return r;
      }
    }
  }
  return {};
}

QString AppController::snoozesFilePath() const {
  return heap::paths::dataDir() + QStringLiteral("/snoozes.json");
}

void AppController::loadSnoozes() {
  m_snoozed.clear();
  QFile f(snoozesFilePath());
  if(!f.open(QIODevice::ReadOnly)) {
    return;
  }
  const QJsonArray arr = QJsonDocument::fromJson(f.readAll()).array();
  for(const auto& v : arr) {
    const QJsonObject o = v.toObject();
    heap::notify::SnoozedReminder s;
    s.id = o.value(QStringLiteral("id")).toString();
    s.title = o.value(QStringLiteral("title")).toString();
    s.body = o.value(QStringLiteral("body")).toString();
    s.kind = o.value(QStringLiteral("kind")).toString();
    s.fireAt = QDateTime::fromString(o.value(QStringLiteral("fireAt")).toString(), Qt::ISODate);
    if(!s.id.isEmpty() && s.fireAt.isValid()) {
      m_snoozed.append(s);
    }
  }
}

void AppController::saveSnoozes() const {
  QJsonArray arr;
  for(const heap::notify::SnoozedReminder& s : m_snoozed) {
    arr.append(QJsonObject{{QStringLiteral("id"), s.id},
                           {QStringLiteral("title"), s.title},
                           {QStringLiteral("body"), s.body},
                           {QStringLiteral("kind"), s.kind},
                           {QStringLiteral("fireAt"), s.fireAt.toString(Qt::ISODate)}});
  }
  QDir().mkpath(heap::paths::dataDir());
  QSaveFile f(snoozesFilePath());
  if(f.open(QIODevice::WriteOnly)) {
    f.write(QJsonDocument(arr).toJson(QJsonDocument::Compact));
    f.commit();
  }
}
