// The safety net (APP-157…): quiet, opt-in heads-ups.
//
// Each one is off until switched on under settings.safety, says what it
// noticed once, and leaves the data alone — no timer stopped, no card moved,
// no status changed. The rules themselves are pure and live in src/safety/;
// this file is the part that reads the workspace and delivers the notice.

#include "AppController.h"

#include "cal/Reminders.h"
#include "git/GitWatcher.h"
#include "notify/NotificationCenter.h"
#include "safety/SafetyText.h"

#include <QApplication>
#include <QFileInfo>
#include <QGuiApplication>

#include <utility>

using heap::safety::EndOfDayFacts;
using heap::safety::RepoDirt;

QVariantMap AppController::safetySettings() const {
  return settingsMap().value(QStringLiteral("safety")).toMap();
}

void AppController::safetyNotify(
    const QString& kind, const QString& title, const QString& body, const QStringList& taskIds, const QDateTime& now) {
  // Quiet hours hold it like any other notification; it arrives when they end,
  // as a plain one.
  if(inQuietHours(now)) {
    holdNotification({.title = title, .body = body, .kind = kind, .taskId = QString()});
    return;
  }
  const QVariantMap notif = settingsMap().value(QStringLiteral("notifications")).toMap();
  const bool appActive = QGuiApplication::applicationState() == Qt::ApplicationActive;
  if(notif.value(QStringLiteral("desktopNotif"), true).toBool() && m_notifier && !appActive) {
    heap::notify::Notification n;
    n.id = heap::notify::routingId(kind, taskIds.isEmpty() ? QStringLiteral("-") : taskIds.join(QLatin1Char(',')));
    n.title = title;
    n.body = body;
    n.iconPath = QStringLiteral(":/brand/icon/heap-icon.svg");
    n.category = kind;
    m_notifier->post(n);
  }
  if(notif.value(QStringLiteral("soundOnPing"), false).toBool()) {
    QApplication::beep();
  }
  emit safetyNotice(kind, title, body, taskIds);
}

// ── APP-157: end of day ──

EndOfDayFacts AppController::endOfDayFacts() const {
  EndOfDayFacts f;
  for(const Task& t : m_tasks.items()) {
    if(t.timerStartedAt.isValid()) {
      f.runningTimerTaskIds << t.id;
    }
    if(t.archived || !isDoingStatus(t.status)) {
      continue;
    }
    f.inProgress.append(
        {.taskId = t.id, .lastActivity = heap::safety::newest({t.statusChangedAt, t.timerStartedAt, m_lastCommitAt.value(t.id)})});
  }
  // A timer left running in another workspace runs all the same.
  for(const Profile& p : m_profiles) {
    if(p.id == m_activeProfileId) {
      continue;
    }
    for(const Task& t : p.tasks) {
      if(t.timerStartedAt.isValid()) {
        f.runningTimerTaskIds << t.id;
      }
    }
  }
  return f;
}

void AppController::checkEndOfDayAt(const QDateTime& now) {
  const QVariantMap s = safetySettings();
  if(!s.value(QStringLiteral("endOfDay"), false).toBool()) {
    return;
  }
  if(m_eodPendingAt.isValid()) {
    // Waiting on git. A repository that does not answer within a couple of
    // ticks is left out rather than holding the rest of the notice back.
    if(m_eodPendingAt.secsTo(now) >= 120) {
      const QDateTime at = std::exchange(m_eodPendingAt, {});
      m_eodPendingRepo.clear();
      finishEndOfDay(at, {});
    }
    return;
  }
  const QString key = QStringLiteral("eod:") + now.date().toString(Qt::ISODate);
  const QDate lastFired = reminderSent(key) ? now.date() : QDate();
  const QTime at = heap::cal::clockTime(s.value(QStringLiteral("endOfDayTime"), QStringLiteral("18:00")).toString());
  if(!heap::safety::shouldFireToday(lastFired, now, at.isValid() ? at : QTime(18, 0))) {
    return;
  }
  markReminderSent(key, now);
  // The repository of the task the current branch is for, when there is one.
  if(m_gitWatcher && !m_focusedRepo.isEmpty() && !m_focusedTaskId.isEmpty()) {
    m_eodPendingAt = now;
    m_eodPendingRepo = m_focusedRepo;
    m_gitWatcher->checkWorkingTree(m_focusedRepo);
    return;
  }
  finishEndOfDay(now, {});
}

void AppController::onWorkingTreeChecked(const QString& repo, int changedFiles, int stashes, bool ok) {
  if(!m_eodPendingAt.isValid() || repo != m_eodPendingRepo) {
    return;
  }
  const QDateTime at = std::exchange(m_eodPendingAt, {});
  m_eodPendingRepo.clear();
  RepoDirt dirt;
  if(ok) {
    dirt.repo = QFileInfo(repo).fileName();
    dirt.changedFiles = changedFiles;
    dirt.stashes = stashes;
  }
  finishEndOfDay(at, dirt);
}

void AppController::finishEndOfDay(const QDateTime& now, const RepoDirt& dirt) {
  const QVariantMap s = safetySettings();
  EndOfDayFacts facts = endOfDayFacts();
  facts.dirt = dirt;
  heap::safety::EndOfDaySettings settings;
  settings.staleDays = qMax(1, s.value(QStringLiteral("staleDays"), 3).toInt());
  const heap::safety::EndOfDayFindings f = heap::safety::endOfDayFindings(facts, now, settings);
  if(!f.any()) {
    return;
  }
  const bool ru = m_language == QStringLiteral("ru");
  safetyNotify(QStringLiteral("endOfDay"),
               tr_(QStringLiteral("safety.eod.title")),
               heap::safety::endOfDaySummary(f, settings.staleDays, ru),
               f.taskIds(),
               now);
}
