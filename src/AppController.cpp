#include "AppController.h"
#include "SampleData.h"

#include "chrono/ChronoParser.h"
#include "git/BranchTaskMatcher.h"
#include "git/GitWatcher.h"
#include "notify/NotificationCenter.h"
#include "platform/GlobalHotkey.h"
#include "text/TaskTextUtils.h"

#include <QApplication>
#include <QClipboard>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QIcon>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeySequence>
#include <QLocale>
#include <QSaveFile>
#include <QStandardPaths>
#include <QSystemTrayIcon>
#include <QTime>
#include <QUuid>

#include <cmath>

namespace {
constexpr int kBackupIntervalSeconds = 5 * 60;
constexpr int kBackupRetentionCount = 20;

// EN/RU string table for toast / system messages emitted from C++. QML chrome
// lives in qml/I18n.qml — this map only covers text produced by AppController
// itself. Keep keys stable: they are referenced from rewrite sites below.
struct I18nEntry {
  const char* en;
  const char* ru;
};

const QHash<QString, I18nEntry>& i18nTable() {
  static const QHash<QString, I18nEntry> table = {
      {"task.created", {"Created: %1", "Создано: %1"}},
      {"task.deleted", {"Deleted: %1", "Удалена: %1"}},
      {"task.restored", {"Restored: %1", "Восстановлена: %1"}},
      {"event.deleted", {"Deleted event: %1", "Удалено событие: %1"}},
      {"event.restored", {"Restored: %1", "Восстановлено: %1"}},
      {"event.scheduled", {"%1 scheduled for %2", "%1 запланировано на %2"}},
      {"person.added", {"Added: %1", "Добавлен: %1"}},
      {"person.deleted", {"Removed: %1", "Удалён: %1"}},
      {"person.restored", {"Restored: %1", "Восстановлён: %1"}},
      {"status.added", {"Column added: %1", "Колонка добавлена: %1"}},
      {"status.deleted", {"Column removed: %1", "Удалена колонка: %1"}},
      {"status.restored", {"Column restored: %1", "Восстановлена колонка: %1"}},
      {"profile.created", {"Profile created: %1", "Профиль создан: %1"}},
      {"profile.deleted", {"Profile removed: %1", "Удалён профиль: %1"}},
      {"profile.restored", {"Profile restored: %1", "Восстановлен профиль: %1"}},
      {"profile.duplicated", {"Profile duplicated: %1", "Дублирован профиль: %1"}},
      {"profile.exported", {"Profile exported: %1", "Профиль экспортирован: %1"}},
      {"profile.imported", {"Profile imported: %1", "Импортирован профиль: %1"}},
      {"tasks.renamed", {"Tasks renamed: %1", "Переименовано задач: %1"}},
      {"backup.restored", {"Restored from %1", "Восстановлено из %1"}},
      {"hotkeys.reset", {"Hotkeys reset to defaults", "Хоткеи сброшены к дефолту"}},
      {"branch.required", {"Set a branch — required by Settings", "Заполни branch — этого требует Settings"}},
      {"deadline.snoozed", {"%1: deadline snoozed", "%1: дедлайн отложен"}},
      {"slot.freed", {"Freed: %1", "Освобождено: %1"}},
      {"import.emptyJson", {"Empty JSON", "Пустой JSON"}},
      {"import.invalidJson", {"Invalid JSON", "Невалидный JSON"}},
      {"import.missingProfile", {"JSON has no 'profile' block or expected fields", "В JSON нет блока 'profile' или ожидаемых полей"}},
      {"import.emptyPath", {"Empty path", "Пустой путь"}},
      {"import.openFail", {"Cannot open: ", "Не открывается: "}},
      {"event.newDefault", {"New event", "Новое событие"}},
      // ---- Shortcuts catalog (labels + descriptions) ----
      {"shortcut.palette.open.label", {"Open Command Palette", "Открыть Command Palette"}},
      {"shortcut.palette.open.desc",
       {"Global fuzzy search across tasks, docs, profiles.", "Глобальный fuzzy-поиск задач, доков, профилей."}},
      {"shortcut.task.new.label", {"New task", "Новая задача"}},
      {"shortcut.task.new.desc", {"Create a ticket in the active profile.", "Создать тикет в активном профиле."}},
      {"shortcut.view.board.label", {"Go to Board", "Перейти в Board"}},
      {"shortcut.view.board.desc", {"Kanban of the active profile.", "Канбан активного профиля."}},
      {"shortcut.view.timeline.label", {"Go to Timeline", "Перейти в Timeline"}},
      {"shortcut.view.timeline.desc", {"Feed by deadlines.", "Лента по дедлайнам."}},
      {"shortcut.view.week.label", {"Go to Week", "Перейти в Week"}},
      {"shortcut.view.week.desc", {"Seven-day planner.", "Семидневный планировщик."}},
      {"shortcut.view.docs.label", {"Go to Docs", "Перейти в Docs"}},
      {"shortcut.view.docs.desc", {"Specs, links, snippets, contacts.", "Спеки, ссылки, сниппеты, контакты."}},
      {"shortcut.view.notes.label", {"Go to Notes", "Перейти в Notes"}},
      {"shortcut.view.notes.desc", {"Markdown canvas of the active profile.", "Markdown-канвас активного профиля."}},
      {"shortcut.view.settings.label", {"Go to Settings", "Перейти в Settings"}},
      {"shortcut.view.settings.desc",
       {"Full settings panel: profile, appearance, integrations.", "Полная панель настроек: профиль, внешний вид, интеграции."}},
      {"shortcut.profile.next.label", {"Next profile", "Следующий профиль"}},
      {"shortcut.profile.next.desc", {"Cycle forward through profiles.", "Циклит по списку профилей вперёд."}},
      {"shortcut.profile.prev.label", {"Previous profile", "Предыдущий профиль"}},
      {"shortcut.profile.prev.desc", {"Cycle backward through profiles.", "Циклит по списку профилей назад."}},
      {"shortcut.profile.exportMd.label", {"Export profile to Markdown", "Экспорт профиля в Markdown"}},
      {"shortcut.profile.exportMd.desc",
       {"Puts a markdown summary of the active profile into the clipboard.", "Кладёт markdown-выжимку активного профиля в буфер."}},
      {"shortcut.tweaks.open.label", {"Open Tweaks", "Открыть Tweaks"}},
      {"shortcut.tweaks.open.desc", {"Theme, density, workday.", "Тема, плотность, рабочий день."}},
      {"shortcut.hotkeys.open.label", {"Open Hotkeys", "Открыть Hotkeys"}},
      {"shortcut.hotkeys.open.desc", {"This panel.", "Эта панель."}},
      {"shortcut.undo.label", {"Undo deletion", "Отменить удаление"}},
      {"shortcut.undo.desc",
       {"Restore the last deleted task / event / profile.", "Восстановить последнюю удалённую задачу/событие/профиль."}},
      {"shortcut.search.focus.label", {"Focus search", "Фокус в поиск"}},
      {"shortcut.search.focus.desc", {"Move the cursor to the header search field.", "Перевести курсор в строку поиска в шапке."}},
      {"shortcut.quick-capture.label", {"Quick-capture task", "Быстрое создание задачи"}},
      {"shortcut.quick-capture.desc",
       {"Open Quick-capture with on-the-fly date parsing.", "Открыть Quick-capture с разбором даты на лету."}},
      {"shortcut.quick-capture-notes.label", {"Quick-capture note", "Быстрая заметка"}},
      {"shortcut.quick-capture-notes.desc",
       {"Open Quick-capture for Notes (appends to the Notes block).", "Открыть Quick-capture для Заметок (дописывает в блок Notes)."}},
      {"shortcut.selection.selectAll.label", {"Select all visible", "Выделить все видимые"}},
      {"shortcut.selection.selectAll.desc",
       {"Select every ticket visible in the current view.", "Выделить все тикеты, видимые в текущем виде."}},
      {"shortcut.selection.clearSel.label", {"Clear selection", "Снять выделение"}},
      {"shortcut.selection.clearSel.desc", {"Drop the current multi-selection.", "Сбросить текущее множественное выделение."}},
      {"shortcut.selection.deleteSel.label", {"Delete selection", "Удалить выделенные"}},
      {"shortcut.selection.deleteSel.desc",
       {"Delete every selected ticket (undoable for 5s).", "Удалить все выделенные тикеты (отменимо 5 с)."}},
      // ---- Selection action bar ----
      {"selection.bar.count", {"%1 selected", "Выделено: %1"}},
      {"selection.bar.move", {"Move to…", "Переместить…"}},
      {"selection.bar.archive", {"Archive", "Архивировать"}},
      {"selection.bar.unarchive", {"Unarchive", "Из архива"}},
      {"selection.bar.delete", {"Delete", "Удалить"}},
      {"selection.bar.clear", {"Clear", "Снять"}},
      {"selection.toast.deleted", {"Deleted %1 tasks", "Удалено задач: %1"}},
      {"selection.toast.restored", {"Restored %1 tasks", "Восстановлено задач: %1"}},
      {"selection.toast.moved", {"Moved %1 tasks", "Перемещено задач: %1"}},
      {"selection.toast.archived", {"Archived %1 tasks", "В архив: %1"}},
      {"selection.toast.unarchived", {"Unarchived %1 tasks", "Из архива: %1"}},
      // ---- Notification copy ----
      {"notify.deadlineTitle", {"Deadline %1", "Дедлайн %1"}},
      {"notify.deadlineWhen.h1", {"in 1 hour", "через час"}},
      {"notify.deadlineWhen.hN", {"in %1 h", "через %1 ч"}},
      {"notify.standupTitle", {"Standup soon", "Standup скоро"}},
      {"notify.standupBody", {"In %1 min", "Через %1 мин"}},
  };
  return table;
}

// Localized month/weekday names used by humanDate() / shortDate(). Kept
// inline so we don't depend on the host system locale being available.
const QStringList& monthNamesLong(const QString& lang) {
  static const QStringList en = {
      "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"};
  static const QStringList ru = {
      "января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"};
  return (lang == "ru") ? ru : en;
}

const QStringList& monthNamesShort(const QString& lang) {
  static const QStringList en = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};
  static const QStringList ru = {"янв", "фев", "мар", "апр", "май", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"};
  return (lang == "ru") ? ru : en;
}

const QStringList& weekdayNamesLong(const QString& lang) {
  static const QStringList en = {"Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"};
  static const QStringList ru = {"понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье"};
  return (lang == "ru") ? ru : en;
}

const QStringList& weekdayNamesShort(const QString& lang) {
  static const QStringList en = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
  static const QStringList ru = {"Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"};
  return (lang == "ru") ? ru : en;
}
}  // namespace

AppController::AppController(QObject* parent) :
    QObject(parent),
    m_today(QDate::currentDate()),
    m_selectedDate(m_today),
    m_saveTimer(new QTimer(this)),
    m_undoTimer(new QTimer(this)),
    m_automationTimer(new QTimer(this)),
    m_chrono(std::make_unique<heap::chrono::ChronoParser>(QLocale())) {
  m_saveTimer->setSingleShot(true);
  m_saveTimer->setInterval(300);
  connect(m_saveTimer, &QTimer::timeout, this, &AppController::saveStateNow);

  m_undoTimer->setSingleShot(true);
  connect(m_undoTimer, &QTimer::timeout, this, &AppController::clearPendingUndo);

  m_automationTimer->setInterval(60 * 1000);
  connect(m_automationTimer, &QTimer::timeout, this, &AppController::runAutomation);

  // (Legacy QSystemTrayIcon creation removed — the notification backend
  // owns its own tray icon on Windows/macOS via the tray fallback. Having
  // two would show duplicate icons in the system tray.)

  // Native notification backend — Linux uses org.freedesktop.Notifications
  // (with real action buttons); Windows/macOS fall back to the legacy tray
  // balloon path. See src/notify/NotificationCenter.h for the contract.
  m_notifier = heap::notify::NotificationCenter::create(this);
  connect(m_notifier.get(), &heap::notify::NotificationCenter::actionInvoked, this, &AppController::onNotifierAction);
  connect(m_notifier.get(), &heap::notify::NotificationCenter::activated, this, &AppController::onNotifierActivated);
  // The tray backend (Windows/macOS) doubles as the app's presence when the
  // window is hidden: clicking the icon or its "Show" entry restores the
  // window, and "Quit" exits for real. Forwarded to QML / the event loop.
  connect(m_notifier.get(), &heap::notify::NotificationCenter::showWindowRequested, this,
          &AppController::showWindowRequested);
  connect(m_notifier.get(), &heap::notify::NotificationCenter::quitRequested, this, []() { QCoreApplication::quit(); });

  // Route notification(...) → native toast + in-app toast bar, respecting
  // quiet hours and the user's `notifications.desktopNotif` / `soundOnPing`
  // opt-outs. Kept as a signal so existing call-sites (`emit
  // notification(...)`) keep working — the lambda just forwards to the
  // NotificationCenter without action buttons (it carries no task id).
  connect(this, &AppController::notification, this, [this](const QString& title, const QString& body, const QString& kind) {
    if(inQuietHours(QDateTime::currentDateTime())) {
      return;
    }
    const QVariantMap notif = settingsMap().value("notifications").toMap();
    if(notif.value("desktopNotif", true).toBool() && m_notifier) {
      heap::notify::Notification n;
      n.id = QStringLiteral("info:") + QString::number(QDateTime::currentMSecsSinceEpoch());
      n.title = title;
      n.body = body;
      n.iconPath = QStringLiteral(":/brand/icon/heap-icon.svg");
      n.category = kind;
      m_notifier->post(n);
    }
    if(notif.value("soundOnPing", false).toBool()) {
      QApplication::beep();
    }
    emit toast(body);
  });

  seedShortcutCatalog();

  // Re-localize shortcut catalog when language flips so the Settings →
  // Shortcuts list and HotkeysPanel labels update in place.
  connect(this, &AppController::languageChanged, this, [this]() {
    seedShortcutCatalog();
  });

  loadStateOnStart();
  m_automationTimer->start();

  // ---- Global hotkeys (OS-level Quick-capture) ----
  // Registered after loadStateOnStart() so any user rebind of the capture
  // sequences is already applied. On non-Windows platforms this is a no-op and
  // the app relies on the in-app QML shortcuts instead.
  m_globalHotkey = heap::platform::GlobalHotkey::create(this);
  connect(m_globalHotkey.get(), &heap::platform::GlobalHotkey::activated, this, &AppController::onGlobalHotkey);
  registerGlobalHotkeys();

  // ---- Git watcher ----
  m_gitWatcher = std::make_unique<heap::git::GitWatcher>(this);
  connect(m_gitWatcher.get(), &heap::git::GitWatcher::branchChanged, this, &AppController::onGitBranchChanged);
  connect(m_gitWatcher.get(), &heap::git::GitWatcher::repoStateUpdated, this, &AppController::onGitRepoState);
  connect(
      m_gitWatcher.get(), &heap::git::GitWatcher::prInfoUpdated, this, [this](const QString&, const QString& br, const QVariantMap& pr) {
        const heap::git::BranchTaskMatcher m(collectPrefixes());
        const auto mr = m.extract(br);
        if(!mr.matched) {
          return;
        }
        QVariantMap entry;
        entry["prState"] = pr.value("state");
        entry["prNumber"] = pr.value("number");
        entry["prUrl"] = pr.value("url");
        m_tasks.setGitInfoForId(mr.taskId, entry);
      });
  applyGitSettingsFromMap(settingsMap().value("git").toMap());
  connect(this, &AppController::appSettingsJsonChanged, this, [this]() {
    applyGitSettingsFromMap(settingsMap().value("git").toMap());
  });
  connect(this, &AppController::activeProfileChanged, this, [this]() {
    if(m_gitWatcher) {
      m_gitWatcher->setPrefixes(collectPrefixes());
    }
  });

  // Fresh install or unreadable state — seed a single "Example" profile
  // from SampleData so the app boots with something sensible.
  if(m_profiles.isEmpty()) {
    Profile p;
    p.id = "default";
    p.name = "Example";
    p.color = "#5cc2dd";
    p.createdAt = QDateTime::currentDateTime();
    const SampleData::Lang seedLang = (m_language == "ru") ? SampleData::Lang::Ru : SampleData::Lang::En;
    p.tasks = SampleData::tasks(seedLang);
    p.people = SampleData::people(seedLang);
    QVariantList st;
    for(const auto& m : SampleData::statuses()) {
      st.push_back(m);
    }
    p.statuses = st;
    p.docsState.clear();
    m_profiles.push_back(p);
    m_activeProfileId = p.id;

    // Events are global; tag the sample events with this default profile.
    QVector<CalEvent> sampleEvents = SampleData::events(m_today, seedLang);
    for(CalEvent& e : sampleEvents) {
      e.profileId = p.id;
    }
    m_events.reset(sampleEvents);

    applyProfileToModels(p);
    emit profilesChanged();
    emit activeProfileChanged();
    scheduleSave();
  }

  // ── Person-id migration ──
  // Upgrade legacy "p-XXXXXXXX" ids (UUID-short, pre-slug scheme) AND the
  // sample-data ids ("p1".."p6") to slug form ("e.zaharov"). CalEvent.
  // attendees is a freeform string of names — no cross-references to fix.
  {
    static const QRegularExpression kLegacyId(QStringLiteral("^p-?[0-9a-fA-F]+$"));
    bool changed = false;
    for(Profile& pr : m_profiles) {
      QSet<QString> taken;
      for(const Person& pe : pr.people) {
        taken.insert(pe.id);
      }
      for(Person& pe : pr.people) {
        if(!kLegacyId.match(pe.id).hasMatch() && !pe.id.isEmpty()) {
          continue;
        }
        const QString slug = heap::text::slugifyPersonName(pe.name);
        if(slug.isEmpty()) {
          continue;
        }
        QString candidate = slug;
        for(int i = 2; taken.contains(candidate) && i < 1000; ++i) {
          candidate = slug + QChar('-') + QString::number(i);
        }
        taken.remove(pe.id);
        taken.insert(candidate);
        pe.id = candidate;
        changed = true;
      }
    }
    if(changed) {
      for(const Profile& pr : m_profiles) {
        if(pr.id == m_activeProfileId) {
          applyProfileToModels(pr);
          break;
        }
      }
      scheduleSave();
    }
  }
}

AppController::~AppController() {
  flushSave();
}

void AppController::flushSave() {
  if(m_saveTimer && m_saveTimer->isActive()) {
    m_saveTimer->stop();
    saveStateNow();
  }
}

void AppController::setSelectedDate(const QDate& d) {
  if(d == m_selectedDate) {
    return;
  }
  m_selectedDate = d;
  emit selectedDateChanged();
}

void AppController::setTheme(const QString& t) {
  if(t == m_theme) {
    return;
  }
  m_theme = t;
  emit themeChanged();
  scheduleSave();
}

void AppController::setDensity(const QString& d) {
  if(d == m_density) {
    return;
  }
  m_density = d;
  emit densityChanged();
  scheduleSave();
}

void AppController::setLanguage(const QString& v) {
  const QString norm = (v == "ru") ? QStringLiteral("ru") : QStringLiteral("en");
  if(norm == m_language) {
    return;
  }
  m_language = norm;
  emit languageChanged();
  // Date helpers (shortDate, humanDate) depend on m_language — nudge any
  // bindings that read them by re-emitting selectedDateChanged. Cheap, and
  // keeps QML chrome that references AppController.shortDate(selectedDate)
  // in sync without per-binding wiring.
  emit selectedDateChanged();
  scheduleSave();
}

QString AppController::tr_(const QString& key) const {
  const auto& table = i18nTable();
  const auto it = table.constFind(key);
  if(it == table.constEnd()) {
    return key;
  }
  return QString::fromUtf8((m_language == "ru") ? it->ru : it->en);
}

void AppController::setCurrentView(const QString& v) {
  if(v == m_currentView) {
    return;
  }
  m_currentView = v;
  clearSelection();
  emit currentViewChanged();
  scheduleSave();
}

void AppController::setWorkdayStart(int v) {
  v = qBound(0, v, 23);
  if(v >= m_workdayEnd) {
    v = m_workdayEnd - 1;
  }
  if(v == m_workdayStart) {
    return;
  }
  m_workdayStart = v;
  emit workdayChanged();
  scheduleSave();
}

void AppController::setWorkdayEnd(int v) {
  v = qBound(1, v, 24);
  if(v <= m_workdayStart) {
    v = m_workdayStart + 1;
  }
  if(v == m_workdayEnd) {
    return;
  }
  m_workdayEnd = v;
  emit workdayChanged();
  scheduleSave();
}

void AppController::setCrumbProject(const QString& v) {
  if(v == m_crumbProject) {
    return;
  }
  m_crumbProject = v;
  emit crumbProjectChanged();
  scheduleSave();
}

void AppController::setCrumbUser(const QString& v) {
  if(v == m_crumbUser) {
    return;
  }
  m_crumbUser = v;
  emit crumbUserChanged();
  scheduleSave();
}

void AppController::setDocsState(const QString& v) {
  if(v == m_docsState) {
    return;
  }
  m_docsState = v;
  emit docsStateChanged();
  scheduleSave();
}

void AppController::setNotesState(const QString& v) {
  if(v == m_notesState) {
    return;
  }
  m_notesState = v;
  emit notesStateChanged();
  scheduleSave();
}

void AppController::appendNoteEntry(const QString& text) {
  const QString body = text.trimmed();
  if(body.isEmpty()) {
    return;
  }
  const QString stamp = QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm");
  QString next;
  if(m_notesState.trimmed().isEmpty()) {
    next = QStringLiteral("### %1\n\n%2").arg(stamp, body);
  } else {
    next = m_notesState;
    while(next.endsWith(QLatin1Char('\n'))) {
      next.chop(1);
    }
    next += QStringLiteral("\n\n----\n### %1\n\n%2").arg(stamp, body);
  }
  setNotesState(next);
}

void AppController::setAppSettingsJson(const QString& v) {
  if(v == m_appSettingsJson) {
    return;
  }
  m_appSettingsJson = v;
  emit appSettingsJsonChanged();
  scheduleSave();
}

void AppController::moveTask(const QString& id, const QString& newStatus) {
  const int row = m_tasks.indexOfId(id);
  if(row < 0) {
    return;
  }
  const Task& t = m_tasks.items().at(row);
  if(t.status == newStatus) {
    return;
  }
  if(!canTransitionStatus(id, newStatus)) {
    return;
  }
  QString statusName = newStatus;
  for(const auto& v : m_statuses) {
    const QVariantMap m = v.toMap();
    if(m.value("id").toString() == newStatus) {
      statusName = m.value("name").toString();
      break;
    }
  }
  const QString taskId = t.id;
  m_tasks.setStatus(id, newStatus);

  // Re-evaluate blocked-stuck set (the task may have left "blocked").
  if(m_blockedStuckIds.remove(id)) {
    m_tasks.setBlockedStuckIds(m_blockedStuckIds);
    emit blockedStuckChanged();
  }

  // Auto focus-block when moving into "prog", if setting on.
  if(newStatus == QStringLiteral("prog")) {
    const QVariantMap s = settingsMap();
    const QVariantMap cal = s.value("calendar").toMap();
    if(cal.value("autoFocusBlock", true).toBool()) {
      scheduleFocusBlockFor(taskId);
    }
  }

  emit toast(QString("%1 → %2").arg(taskId, statusName));
  scheduleSave();
}

QVariantMap AppController::newTaskDraft(const QString& statusId) const {
  const QVariantMap tasksCfg = settingsMap().value("tasks").toMap();
  const QString prefix = tasksCfg.value("idPrefix", QStringLiteral("LTE")).toString().trimmed();
  const QString priorityDefault = tasksCfg.value("defaultPriority", QStringLiteral("P2")).toString();
  const QString statusDefault = tasksCfg.value("defaultStatus", QStringLiteral("todo")).toString();

  const int nextNum = 2700 + m_tasks.rowCount();
  QVariantMap m;
  m["_isNew"] = true;
  m["id"] = QString("%1-%2").arg(prefix.isEmpty() ? QStringLiteral("TASK") : prefix).arg(nextNum);
  m["title"] = QString();
  m["desc"] = QString();
  m["priority"] = priorityDefault.isEmpty() ? QStringLiteral("P2") : priorityDefault;
  m["status"] = statusId.isEmpty() ? (statusDefault.isEmpty() ? QStringLiteral("todo") : statusDefault) : statusId;
  m["deadline"] = QDate();
  m["branch"] = QString();
  return m;
}

QVariantMap AppController::newQuickTaskDraft() const {
  QVariantMap m = newTaskDraft(QStringLiteral("todo"));
  // Replace the project-prefixed auto-id with a placeholder. The user can
  // rename it later via TaskEditor — saveTask handles the rename safely.
  int n = 1;
  QString candidate;
  do {
    candidate = QStringLiteral("TODO-") + QString::number(n++);
  } while(m_tasks.indexOfId(candidate) >= 0);
  m["id"] = candidate;
  return m;
}

void AppController::saveTask(const QVariantMap& draft) {
  Task t;
  t.id = draft.value("id").toString().trimmed();
  t.title = draft.value("title").toString();
  t.desc = draft.value("desc").toString();
  t.priority = draft.value("priority").toString();
  t.status = draft.value("status").toString();
  t.deadline = draft.value("deadline").toDate();
  t.branch = draft.value("branch").toString();
  const bool isNew = draft.value("_isNew").toBool();
  if(isNew && t.title.trimmed().isEmpty()) {
    return;
  }

  // Preserve fields the editor doesn't expose. Without this, opening an
  // archived ticket and hitting Save silently unarchives it (struct
  // defaults to archived=false), and any edit wipes statusChangedAt,
  // breaking auto-archive-after-N-days. If the draft explicitly carries
  // the flag (round-tripped through taskById), honour it.
  if(!isNew) {
    const QString originalForLookup = draft.value("_originalId").toString().trimmed();
    const QString priorId = originalForLookup.isEmpty() ? t.id : originalForLookup;
    const int existing = m_tasks.indexOfId(priorId);
    if(existing >= 0) {
      const Task& prev = m_tasks.items().at(existing);
      t.archived = draft.contains("archived") ? draft.value("archived").toBool() : prev.archived;
      t.statusChangedAt = prev.statusChangedAt;
    }
  }

  // ── Rename path ──
  // If the editor captured an _originalId that differs from the new id,
  // this is an id-change on an existing row. Drop the old row, fix up
  // CalEvent.taskId backlinks, and upsert under the new id. This prevents
  // the previous "duplicate appears after edit" symptom (which used to
  // happen whenever idField text drifted from the stored id).
  const QString originalId = draft.value("_originalId").toString().trimmed();
  if(!isNew && !originalId.isEmpty() && originalId != t.id) {
    const int row = m_tasks.indexOfId(originalId);
    if(row >= 0) {
      // Re-key dependent events first so live bindings update once.
      for(const auto& e : m_events.items()) {
        if(e.taskId == originalId) {
          m_events.setTaskId(e.id, t.id);
        }
      }
      m_tasks.removeById(originalId);
    }
  }

  m_tasks.upsert(t);
  if(isNew) {
    emit toast(tr_("task.created").arg(t.id));
  }
  scheduleSave();
}

void AppController::deleteTask(const QString& id) {
  const int row = m_tasks.indexOfId(id);
  if(row < 0) {
    return;
  }
  cancelUndo();
  m_pendingUndo = {};
  m_pendingUndo.kind = PendingUndo::Task;
  m_pendingUndo.task = m_tasks.items().at(row);
  m_pendingUndo.row = row;
  for(const auto& e : m_events.items()) {
    if(e.taskId == id) {
      m_pendingUndo.detachedEventIds.append({e.id, e.taskId});
    }
  }
  m_events.detachTask(id);
  m_tasks.removeById(id);
  armUndo(5);
  emit undoableToast(tr_("task.deleted").arg(id), 5);
  scheduleSave();
}

QVariantMap AppController::newEventDraft(double startHour, const QDate& date) const {
  QVariantMap m;
  m["id"] = QString("ev-") + QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
  m["title"] = tr_("event.newDefault");
  m["type"] = "sync";
  m["start"] = startHour;
  m["end"] = startHour + 1.0;
  m["attendees"] = QString();
  m["date"] = date.isValid() ? date : m_selectedDate;
  m["taskId"] = QString();
  m["profileId"] = m_activeProfileId;  // default attribution: active profile
  m["context"] = QString();
  m["_isNew"] = true;
  return m;
}

void AppController::saveEvent(const QVariantMap& draft) {
  CalEvent e;
  e.id = draft.value("id").toString();
  e.title = draft.value("title").toString();
  e.type = draft.value("type").toString();
  e.start = draft.value("start").toDouble();
  e.end = draft.value("end").toDouble();
  e.attendees = draft.value("attendees").toString();
  e.date = draft.value("date").toDate();
  e.taskId = draft.value("taskId").toString();
  // EventEditor no longer exposes profileId — preserve the prior value
  // (round-tripped through showForId) when the draft omits the key, so
  // existing saved attribution survives an edit.
  if(draft.contains("profileId")) {
    e.profileId = draft.value("profileId").toString();
  } else {
    const int prev = m_events.indexOfId(e.id);
    e.profileId = (prev >= 0) ? m_events.items().at(prev).profileId : QString();
  }
  e.context = draft.value("context").toString();
  if(e.end <= e.start) {
    e.end = e.start + 0.25;
  }
  m_events.upsert(e);
  scheduleSave();
}

void AppController::updateEvent(const QString& id, double start, double end, const QDate& date) {
  const int row = m_events.indexOfId(id);
  if(row < 0) {
    return;
  }
  const int snapMin = qMax(1, settingsMap().value("calendar").toMap().value("snapMinutes", 15).toInt());
  const double step = snapMin / 60.0;
  const double minDur = step;
  auto snap = [step](double h) {
    return std::round(h / step) * step;
  };
  CalEvent e = m_events.items().at(row);
  e.start = snap(qBound(0.0, start, 24.0));
  e.end = snap(qBound(e.start + minDur, end, 24.0));
  if(e.end < e.start + minDur) {
    e.end = e.start + minDur;
  }
  if(date.isValid()) {
    e.date = date;
  }
  m_events.upsert(e);
  scheduleSave();
}

QString AppController::scheduledLabelFor(const QString& taskId, const QDate& date) const {
  if(taskId.isEmpty() || !date.isValid()) {
    return QString();
  }
  double earliest = -1.0;
  for(const CalEvent& e : m_events.items()) {
    if(e.taskId != taskId || e.date != date) {
      continue;
    }
    if(earliest < 0.0 || e.start < earliest) {
      earliest = e.start;
    }
  }
  if(earliest < 0.0) {
    return QString();
  }
  return eventHourLabel(earliest);
}

void AppController::deleteEvent(const QString& id) {
  const int row = m_events.indexOfId(id);
  if(row < 0) {
    return;
  }
  cancelUndo();
  m_pendingUndo = {};
  m_pendingUndo.kind = PendingUndo::Event;
  m_pendingUndo.event = m_events.items().at(row);
  m_pendingUndo.row = row;
  m_events.removeById(id);
  armUndo(5);
  emit undoableToast(tr_("event.deleted").arg(m_pendingUndo.event.title), 5);
  scheduleSave();
}

void AppController::scheduleTask(const QString& taskId, double startHour, const QDate& date) {
  const int row = m_tasks.indexOfId(taskId);
  if(row < 0) {
    return;
  }
  const Task& t = m_tasks.items().at(row);
  CalEvent e;
  e.id = QString("ev-") + QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
  e.title = QString("Focus · %1").arg(t.title.left(36));
  e.type = "focus";
  e.start = startHour;
  e.end = startHour + 1.0;
  e.attendees = "🔒 deep work";
  e.date = date;
  e.taskId = t.id;
  e.profileId = m_activeProfileId;
  m_events.upsert(e);
  emit toast(tr_("event.scheduled").arg(t.id, eventHourLabel(startHour)));
  scheduleSave();
}

void AppController::cyclePerson(const QString& id) {
  m_people.cycleState(id);
  scheduleSave();
}

void AppController::setPersonState(const QString& id, const QString& state) {
  m_people.setState(id, state);
  scheduleSave();
}

QVariantMap AppController::newPersonDraft() const {
  static const QColor palette[] = {
      QColor("#d97a6c"),
      QColor("#c87fc7"),
      QColor("#6cc4b8"),
      QColor("#7da8d9"),
      QColor("#dcc06a"),
      QColor("#7cc492"),
      QColor("#e69854"),
      QColor("#a4a4d6"),
  };
  const int n = static_cast<int>(sizeof(palette) / sizeof(palette[0]));
  const QColor c = palette[m_people.rowCount() % n];
  QVariantMap m;
  m["_isNew"] = true;
  // Empty id signals "auto-derive from name on save" — see savePerson().
  m["id"] = QString();
  m["name"] = QString();
  m["role"] = QString();
  m["question"] = QString();
  m["state"] = "todo";
  m["color"] = c;
  return m;
}

QVariantMap AppController::personById(const QString& id) const {
  const int row = m_people.indexOfId(id);
  if(row < 0) {
    return {};
  }
  const QModelIndex mi = m_people.index(row, 0);
  QVariantMap m;
  m["_isNew"] = false;
  m["id"] = m_people.data(mi, PersonModel::IdRole);
  m["name"] = m_people.data(mi, PersonModel::NameRole);
  m["role"] = m_people.data(mi, PersonModel::RoleRole);
  m["question"] = m_people.data(mi, PersonModel::QuestionRole);
  m["state"] = m_people.data(mi, PersonModel::StateRole);
  m["color"] = m_people.data(mi, PersonModel::ColorRole);
  return m;
}

void AppController::savePerson(const QVariantMap& draft) {
  Person p;
  p.id = draft.value("id").toString();
  p.name = draft.value("name").toString();
  p.role = draft.value("role").toString();
  p.question = draft.value("question").toString();
  p.state = draft.value("state").toString();
  p.color = draft.value("color").value<QColor>();
  if(!p.color.isValid()) {
    p.color = QColor("#7da8d9");
  }
  if(p.state.isEmpty()) {
    p.state = "todo";
  }
  // Derive a slug id ("e.zaharov") from the name when the caller did not
  // supply one. Old UUID-style ids ("p-XXXXXXXX") are upgraded too — they
  // were created before the slug scheme was in place.
  static const QRegularExpression kLegacyId(QStringLiteral("^p-[0-9a-fA-F]+$"));
  if(p.id.isEmpty() || kLegacyId.match(p.id).hasMatch()) {
    p.id = suggestPersonId(p.name, /*exceptId=*/draft.value("id").toString());
  }
  if(p.id.isEmpty()) {
    // Names with no transliterable letters at all — fall back to UUID
    // so we never end up with an empty key.
    p.id = QString("p-") + QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
  }
  const bool isNew = draft.value("_isNew").toBool();
  if(isNew && p.name.trimmed().isEmpty()) {
    return;
  }
  m_people.upsert(p);
  if(isNew) {
    emit toast(tr_("person.added").arg(p.name));
  }
  scheduleSave();
}

QString AppController::suggestPersonId(const QString& name, const QString& exceptId) const {
  QString base = heap::text::slugifyPersonName(name);
  if(base.isEmpty()) {
    return QString();
  }
  // Collision check against every Person across every profile so that ids
  // remain globally unique (even though models are per-profile).
  auto inUse = [this, &exceptId](const QString& candidate) {
    if(candidate == exceptId) {
      return false;
    }
    for(const Profile& pr : m_profiles) {
      for(const Person& pe : pr.people) {
        if(pe.id == candidate) {
          return true;
        }
      }
    }
    return false;
  };
  if(!inUse(base)) {
    return base;
  }
  for(int i = 2; i < 1000; ++i) {
    const QString c = base + QChar('-') + QString::number(i);
    if(!inUse(c)) {
      return c;
    }
  }
  return base;  // last-resort, caller already guarded against empty
}

void AppController::deletePerson(const QString& id) {
  const int row = m_people.indexOfId(id);
  if(row < 0) {
    return;
  }
  cancelUndo();
  m_pendingUndo = {};
  m_pendingUndo.kind = PendingUndo::Person;
  m_pendingUndo.person = m_people.items().at(row);
  m_pendingUndo.row = row;
  m_people.removeById(id);
  armUndo(5);
  emit undoableToast(tr_("person.deleted").arg(m_pendingUndo.person.name), 5);
  scheduleSave();
}

int AppController::countByStatus(const QString& statusId) const {
  int n = 0;
  for(const auto& t : m_tasks.items()) {
    if(t.status == statusId) {
      ++n;
    }
  }
  return n;
}

int AppController::statusIndexOf(const QString& id) const {
  for(int i = 0; i < m_statuses.size(); ++i) {
    if(m_statuses[i].toMap().value("id").toString() == id) {
      return i;
    }
  }
  return -1;
}

void AppController::addStatus(const QString& name, const QString& color) {
  if(name.trimmed().isEmpty()) {
    return;
  }
  const QString base = name.toLower();
  QString slug;
  for(const QChar c : base) {
    slug.append(c.isLetterOrNumber() ? c : QChar('-'));
  }
  while(slug.contains("--")) {
    slug.replace("--", "-");
  }
  if(slug.startsWith('-')) {
    slug = slug.mid(1);
  }
  while(slug.endsWith('-')) {
    slug.chop(1);
  }
  if(slug.isEmpty()) {
    slug = "status";
  }
  QString id = slug;
  int n = 2;
  while(statusIndexOf(id) >= 0) {
    id = slug + "-" + QString::number(n++);
  }
  QVariantMap m;
  m["id"] = id;
  m["name"] = name;
  m["color"] = QColor(color.isEmpty() ? QStringLiteral("#5cc2dd") : color);
  m_statuses.append(m);
  emit statusesChanged();
  emit toast(tr_("status.added").arg(name));
  scheduleSave();
}

void AppController::renameStatus(const QString& id, const QString& name) {
  const int i = statusIndexOf(id);
  if(i < 0 || name.trimmed().isEmpty()) {
    return;
  }
  QVariantMap m = m_statuses[i].toMap();
  if(m.value("name").toString() == name) {
    return;
  }
  m["name"] = name;
  m_statuses[i] = m;
  emit statusesChanged();
  scheduleSave();
}

void AppController::setStatusColor(const QString& id, const QString& color) {
  const int i = statusIndexOf(id);
  if(i < 0) {
    return;
  }
  const QColor c(color);
  if(!c.isValid()) {
    return;
  }
  QVariantMap m = m_statuses[i].toMap();
  m["color"] = c;
  m_statuses[i] = m;
  emit statusesChanged();
  scheduleSave();
}

void AppController::moveStatus(const QString& id, int newIndex) {
  const int from = statusIndexOf(id);
  if(from < 0) {
    return;
  }
  newIndex = qBound(0, newIndex, m_statuses.size() - 1);
  if(from == newIndex) {
    return;
  }
  const QVariant v = m_statuses.takeAt(from);
  m_statuses.insert(newIndex, v);
  emit statusesChanged();
  scheduleSave();
}

void AppController::deleteStatus(const QString& id) {
  const int i = statusIndexOf(id);
  if(i < 0 || m_statuses.size() <= 1) {
    return;  // never let the board run out of columns
  }
  cancelUndo();
  m_pendingUndo = {};
  m_pendingUndo.kind = PendingUndo::Status;
  m_pendingUndo.status = m_statuses[i].toMap();
  m_pendingUndo.row = i;

  // re-home any tasks with this status to the first remaining one
  QString fallback;
  for(int k = 0; k < m_statuses.size(); ++k) {
    if(k == i) {
      continue;
    }
    fallback = m_statuses[k].toMap().value("id").toString();
    break;
  }
  for(const auto& t : m_tasks.items()) {
    if(t.status == id) {
      m_pendingUndo.reHomedTasks.append({t.id, id});
    }
  }
  for(const auto& pair : m_pendingUndo.reHomedTasks) {
    m_tasks.setStatus(pair.first, fallback);
  }

  const QString name = m_pendingUndo.status.value("name").toString();
  m_statuses.removeAt(i);
  emit statusesChanged();
  armUndo(5);
  emit undoableToast(tr_("status.deleted").arg(name), 5);
  scheduleSave();
}

QVariantMap AppController::taskById(const QString& id) const {
  const int row = m_tasks.indexOfId(id);
  if(row < 0) {
    return {};
  }
  const Task& t = m_tasks.items().at(row);
  QVariantMap m;
  m["id"] = t.id;
  m["title"] = t.title;
  m["desc"] = t.desc;
  m["priority"] = t.priority;
  m["status"] = t.status;
  m["deadline"] = t.deadline;
  m["branch"] = t.branch;
  m["archived"] = t.archived;
  return m;
}

QString AppController::eventHourLabel(double hour) const {
  const int hh = static_cast<int>(hour);
  const int mm = static_cast<int>((hour - hh) * 60 + 0.5);
  const QString fmt = settingsMap().value("calendar").toMap().value("timeFormat", QStringLiteral("24h")).toString();
  const QString mmS = QString("%1").arg(mm, 2, 10, QLatin1Char('0'));
  if(fmt == QLatin1String("12h")) {
    const int h12 = ((hh + 11) % 12) + 1;
    const QString ampm = hh < 12 ? QStringLiteral("am") : QStringLiteral("pm");
    return QString("%1:%2%3").arg(h12).arg(mmS).arg(ampm);
  }
  return QString("%1:%2").arg(hh, 2, 10, QLatin1Char('0')).arg(mmS);
}

QString AppController::sprintLabel() const {
  const int n = static_cast<int>((m_today.month()) * 2.1);
  return QString("sprint-%1").arg(n);
}

QString AppController::humanDate(const QDate& date) const {
  if(!date.isValid()) {
    return {};
  }
  const int dow = date.dayOfWeek();  // 1=Mon..7=Sun
  const int mon = date.month();      // 1..12
  if(dow < 1 || dow > 7 || mon < 1 || mon > 12) {
    return {};
  }
  const QString day = weekdayNamesLong(m_language).at(dow - 1);
  const QString month = monthNamesLong(m_language).at(mon - 1);
  if(m_language == "ru") {
    return QString("%1, %2 %3").arg(day).arg(date.day()).arg(month);
  }
  // EN: "Friday, May 15"
  return QString("%1, %2 %3").arg(day, month).arg(date.day());
}

QString AppController::deadlineBucket(const QDate& deadline) const {
  if(!deadline.isValid()) {
    return "nodl";
  }
  const int d = m_today.daysTo(deadline);
  if(d < 0) {
    return "overdue";
  }
  if(d == 0) {
    return "today";
  }
  if(d == 1) {
    return "tomorrow";
  }
  if(d <= 6) {
    return "thisweek";
  }
  if(d <= 13) {
    return "nextweek";
  }
  return "later";
}

QString AppController::deadlineDiffLabel(const QDate& deadline) const {
  if(!deadline.isValid()) {
    return QStringLiteral("—");
  }
  const int d = m_today.daysTo(deadline);
  if(d < 0) {
    return QString("%1d overdue").arg(-d);
  }
  if(d == 0) {
    return QStringLiteral("today");
  }
  if(d == 1) {
    return QStringLiteral("+1 day");
  }
  if(d < 7) {
    return QString("+%1 days").arg(d);
  }
  return QString("+%1d").arg(d);
}

QString AppController::shortDate(const QDate& d) const {
  if(!d.isValid()) {
    return {};
  }
  const int dow = d.dayOfWeek();
  const int mon = d.month();
  if(dow < 1 || dow > 7 || mon < 1 || mon > 12) {
    return {};
  }
  const QString day = weekdayNamesShort(m_language).at(dow - 1);
  const QString month = monthNamesShort(m_language).at(mon - 1);
  if(m_language == "ru") {
    return QString("%1, %2 %3").arg(day).arg(d.day()).arg(month);
  }
  // EN: "Fri, 15 May"
  return QString("%1, %2 %3").arg(day).arg(d.day()).arg(month);
}

int AppController::isoWeekNumber(const QDate& d) const {
  if(!d.isValid()) {
    return 0;
  }
  return d.weekNumber();
}

QVariantMap AppController::parseDateTime(const QString& input, const QDateTime& reference) const {
  QVariantMap m;
  if(!m_chrono) {
    m.insert("ok", false);
    return m;
  }
  const auto r = m_chrono->parse(input, reference);
  m.insert("ok", r.ok);
  m.insert("start", r.start);
  m.insert("end", r.end);
  m.insert("hasTime", r.hasTime);
  m.insert("recurrence", r.recurrence);
  m.insert("consumed", r.consumed);
  m.insert("startOffset", r.startOffset);
  m.insert("endOffset", r.endOffset);
  return m;
}

QVariantList AppController::parseAllDateTimes(const QString& input, const QDateTime& reference) const {
  QVariantList out;
  if(!m_chrono) {
    return out;
  }
  const auto all = m_chrono->parseAll(input, reference);
  for(const auto& r : all) {
    QVariantMap m;
    m.insert("ok", r.ok);
    m.insert("start", r.start);
    m.insert("end", r.end);
    m.insert("hasTime", r.hasTime);
    m.insert("recurrence", r.recurrence);
    m.insert("consumed", r.consumed);
    m.insert("startOffset", r.startOffset);
    m.insert("endOffset", r.endOffset);
    out.append(m);
  }
  return out;
}

void AppController::copyToClipboard(const QString& text) {
  if(auto* cb = QGuiApplication::clipboard()) {
    cb->setText(text);
  }
}

QString AppController::classifyTaskKind(const QString& text) const {
  using heap::text::TaskKind;
  switch(heap::text::classifyKind(text)) {
    case TaskKind::Focus:
      return QStringLiteral("focus");
    case TaskKind::Sync:
      return QStringLiteral("sync");
    case TaskKind::Ticket:
      return QStringLiteral("ticket");
    case TaskKind::Contact:
      return QStringLiteral("contact");
    case TaskKind::None:
      break;
  }
  return QStringLiteral("none");
}

QVariantMap AppController::extractTaskMeta(const QString& text) const {
  const auto m = heap::text::extractMeta(text);
  QVariantMap out;
  out["title"] = m.title;
  out["desc"] = m.desc;
  out["handles"] = QVariant::fromValue(m.handles);
  return out;
}

// ───────────────────────────────────────────────────────── Undo ──

void AppController::armUndo(int seconds) {
  m_undoTimer->start(seconds * 1000);
  emit pendingUndoChanged();
}

void AppController::cancelUndo() {
  if(m_undoTimer) {
    m_undoTimer->stop();
  }
  if(m_pendingUndo.kind != PendingUndo::None) {
    m_pendingUndo = {};
    emit pendingUndoChanged();
  }
}

void AppController::clearPendingUndo() {
  cancelUndo();
}

void AppController::undoLastDeletion() {
  if(m_pendingUndo.kind == PendingUndo::None) {
    return;
  }
  switch(m_pendingUndo.kind) {
    case PendingUndo::Task: {
      m_tasks.insertAt(m_pendingUndo.row, m_pendingUndo.task);
      for(const auto& pair : m_pendingUndo.detachedEventIds) {
        m_events.setTaskId(pair.first, pair.second);
      }
      emit toast(tr_("task.restored").arg(m_pendingUndo.task.id));
      break;
    }
    case PendingUndo::BulkTasks: {
      // m_pendingUndo.tasks/rows captured in ascending row order; re-insert
      // in that same order so earlier indices stay valid.
      for(int i = 0; i < m_pendingUndo.tasks.size(); ++i) {
        const int row = qBound(0, m_pendingUndo.rows.value(i, m_tasks.rowCount()), m_tasks.rowCount());
        m_tasks.insertAt(row, m_pendingUndo.tasks.at(i));
      }
      for(const auto& pair : m_pendingUndo.detachedEventIds) {
        m_events.setTaskId(pair.first, pair.second);
      }
      emit toast(tr_("selection.toast.restored").arg(m_pendingUndo.tasks.size()));
      break;
    }
    case PendingUndo::Event: {
      m_events.insertAt(m_pendingUndo.row, m_pendingUndo.event);
      emit toast(tr_("event.restored").arg(m_pendingUndo.event.title));
      break;
    }
    case PendingUndo::Person: {
      m_people.insertAt(m_pendingUndo.row, m_pendingUndo.person);
      emit toast(tr_("person.restored").arg(m_pendingUndo.person.name));
      break;
    }
    case PendingUndo::Status: {
      const int idx = qBound(0, m_pendingUndo.row, m_statuses.size());
      m_statuses.insert(idx, m_pendingUndo.status);
      for(const auto& pair : m_pendingUndo.reHomedTasks) {
        m_tasks.setStatus(pair.first, pair.second);
      }
      emit statusesChanged();
      emit toast(tr_("status.restored").arg(m_pendingUndo.status.value("name").toString()));
      break;
    }
    case PendingUndo::Profile: {
      const int idx = qBound(0, m_pendingUndo.row, m_profiles.size());
      // Snapshot whatever is live now so we don't lose post-delete edits
      // in whichever profile became active after the deletion.
      snapshotActiveProfile();
      m_profiles.insert(idx, m_pendingUndo.profile);
      m_activeProfileId = m_pendingUndo.profile.id;
      applyProfileToModels(m_pendingUndo.profile);
      emit profilesChanged();
      emit activeProfileChanged();
      emit toast(tr_("profile.restored").arg(m_pendingUndo.profile.name));
      break;
    }
    default:
      break;
  }
  m_pendingUndo = {};
  if(m_undoTimer) {
    m_undoTimer->stop();
  }
  emit pendingUndoChanged();
  scheduleSave();
}

// ─────────────────────────────────────────────────── Persistence ──

QString AppController::stateFilePath() const {
  const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
  QDir().mkpath(dir);
  return dir + "/state.json";
}

QString AppController::backupDirPath() const {
  const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/backups";
  QDir().mkpath(dir);
  return dir;
}

void AppController::scheduleSave() {
  if(m_loading || !m_saveTimer) {
    return;
  }
  m_saveTimer->start();
}

// ───────────────── (de)serialisation helpers ─────────────────
namespace {

QJsonArray tasksToJson(const QVector<Task>& xs) {
  QJsonArray a;
  for(const Task& t : xs) {
    QJsonObject o;
    o["id"] = t.id;
    o["title"] = t.title;
    o["desc"] = t.desc;
    o["priority"] = t.priority;
    o["status"] = t.status;
    o["deadline"] = t.deadline.isValid() ? t.deadline.toString(Qt::ISODate) : QString();
    o["branch"] = t.branch;
    o["statusChangedAt"] = t.statusChangedAt.isValid() ? t.statusChangedAt.toString(Qt::ISODate) : QString();
    o["archived"] = t.archived;
    a.append(o);
  }
  return a;
}

QVector<Task> tasksFromJson(const QJsonArray& a) {
  QVector<Task> v;
  v.reserve(a.size());
  for(const auto& it : a) {
    const QJsonObject o = it.toObject();
    Task t;
    t.id = o["id"].toString();
    t.title = o["title"].toString();
    t.desc = o["desc"].toString();
    t.priority = o["priority"].toString();
    t.status = o["status"].toString();
    t.deadline = QDate::fromString(o["deadline"].toString(), Qt::ISODate);
    t.branch = o["branch"].toString();
    t.statusChangedAt = QDateTime::fromString(o["statusChangedAt"].toString(), Qt::ISODate);
    if(!t.statusChangedAt.isValid()) {
      t.statusChangedAt = QDateTime::currentDateTime();
    }
    t.archived = o["archived"].toBool(false);
    v.append(t);
  }
  return v;
}

QJsonArray eventsToJson(const QVector<CalEvent>& xs) {
  QJsonArray a;
  for(const CalEvent& e : xs) {
    QJsonObject o;
    o["id"] = e.id;
    o["title"] = e.title;
    o["type"] = e.type;
    o["start"] = e.start;
    o["end"] = e.end;
    o["attendees"] = e.attendees;
    o["date"] = e.date.isValid() ? e.date.toString(Qt::ISODate) : QString();
    o["taskId"] = e.taskId;
    o["profileId"] = e.profileId;
    o["context"] = e.context;
    a.append(o);
  }
  return a;
}

QVector<CalEvent> eventsFromJson(const QJsonArray& a, const QString& fallbackProfileId = QString()) {
  QVector<CalEvent> v;
  v.reserve(a.size());
  for(const auto& it : a) {
    const QJsonObject o = it.toObject();
    CalEvent e;
    e.id = o["id"].toString();
    e.title = o["title"].toString();
    e.type = o["type"].toString();
    e.start = o["start"].toDouble();
    e.end = o["end"].toDouble();
    e.attendees = o["attendees"].toString();
    e.date = QDate::fromString(o["date"].toString(), Qt::ISODate);
    e.taskId = o["taskId"].toString();
    e.profileId = o.contains("profileId") ? o["profileId"].toString() : fallbackProfileId;
    e.context = o["context"].toString();
    v.append(e);
  }
  return v;
}

QJsonArray peopleToJson(const QVector<Person>& xs) {
  QJsonArray a;
  for(const Person& p : xs) {
    QJsonObject o;
    o["id"] = p.id;
    o["name"] = p.name;
    o["role"] = p.role;
    o["question"] = p.question;
    o["state"] = p.state;
    o["color"] = p.color.name();
    a.append(o);
  }
  return a;
}

QVector<Person> peopleFromJson(const QJsonArray& a) {
  QVector<Person> v;
  v.reserve(a.size());
  for(const auto& it : a) {
    const QJsonObject o = it.toObject();
    Person p;
    p.id = o["id"].toString();
    p.name = o["name"].toString();
    p.role = o["role"].toString();
    p.question = o["question"].toString();
    p.state = o["state"].toString();
    p.color = QColor(o["color"].toString());
    v.append(p);
  }
  return v;
}

QJsonArray statusesToJson(const QVariantList& xs) {
  QJsonArray a;
  for(const QVariant& v : xs) {
    const QVariantMap m = v.toMap();
    QJsonObject o;
    o["id"] = m.value("id").toString();
    o["name"] = m.value("name").toString();
    const QVariant col = m.value("color");
    o["color"] = col.canConvert<QColor>() ? col.value<QColor>().name() : col.toString();
    a.append(o);
  }
  return a;
}

QVariantList statusesFromJson(const QJsonArray& a) {
  QVariantList v;
  for(const auto& it : a) {
    const QJsonObject o = it.toObject();
    QVariantMap m;
    m["id"] = o["id"].toString();
    m["name"] = o["name"].toString();
    m["color"] = QColor(o["color"].toString());
    v.append(m);
  }
  return v;
}

QJsonObject profileToJson(const Profile& p) {
  QJsonObject o;
  o["id"] = p.id;
  o["name"] = p.name;
  o["color"] = p.color;
  o["createdAt"] = p.createdAt.isValid() ? p.createdAt.toString(Qt::ISODate) : QString();
  o["tasks"] = tasksToJson(p.tasks);
  o["people"] = peopleToJson(p.people);
  o["statuses"] = statusesToJson(p.statuses);
  if(!p.docsState.isEmpty()) {
    const QJsonDocument d = QJsonDocument::fromJson(p.docsState.toUtf8());
    if(!d.isNull() && d.isObject()) {
      o["docs"] = d.object();
    }
  }
  if(!p.notesState.isEmpty()) {
    o["notes"] = p.notesState;
  }
  return o;
}

// Returns the parsed Profile and pulls out any nested "events" array (legacy
// schema v2) so the caller can hoist them into the global event pool with
// fallback profileId = p.id.
Profile profileFromJson(const QJsonObject& o, QVector<CalEvent>* outLegacyEvents = nullptr) {
  Profile p;
  p.id = o["id"].toString();
  p.name = o["name"].toString();
  p.color = o["color"].toString();
  p.createdAt = QDateTime::fromString(o["createdAt"].toString(), Qt::ISODate);
  p.tasks = tasksFromJson(o["tasks"].toArray());
  p.people = peopleFromJson(o["people"].toArray());
  p.statuses = statusesFromJson(o["statuses"].toArray());
  if(o.contains("docs")) {
    p.docsState = QJsonDocument(o["docs"].toObject()).toJson(QJsonDocument::Compact);
  }
  if(o.contains("notes")) {
    p.notesState = o["notes"].toString();
  }
  if(outLegacyEvents && o.contains("events")) {
    const QVector<CalEvent> v = eventsFromJson(o["events"].toArray(), p.id);
    outLegacyEvents->append(v);
  }
  return p;
}

}  // namespace

// ───────────────── Profile helpers (private) ─────────────────

int AppController::profileIndexOf(const QString& id) const {
  for(int i = 0; i < m_profiles.size(); ++i) {
    if(m_profiles[i].id == id) {
      return i;
    }
  }
  return -1;
}

QString AppController::makeProfileId(const QString& name) const {
  QString slug;
  for(const QChar c : name.toLower()) {
    slug.append(c.isLetterOrNumber() ? c : QChar('-'));
  }
  while(slug.contains("--")) {
    slug.replace("--", "-");
  }
  if(slug.startsWith('-')) {
    slug = slug.mid(1);
  }
  while(slug.endsWith('-')) {
    slug.chop(1);
  }
  if(slug.isEmpty()) {
    slug = "profile";
  }
  QString id = slug;
  int n = 2;
  while(profileIndexOf(id) >= 0) {
    id = slug + "-" + QString::number(n++);
  }
  return id;
}

void AppController::snapshotActiveProfile() {
  const int i = profileIndexOf(m_activeProfileId);
  if(i < 0) {
    return;
  }
  Profile& p = m_profiles[i];
  p.tasks = m_tasks.items();
  p.people = m_people.items();
  p.statuses = m_statuses;
  p.docsState = m_docsState;
  p.notesState = m_notesState;
  // Events are global — not snapshotted into the profile.
}

void AppController::applyProfileToModels(const Profile& p) {
  m_tasks.reset(p.tasks);
  m_people.reset(p.people);
  m_statuses = p.statuses;
  emit statusesChanged();
  m_docsState = p.docsState;
  emit docsStateChanged();
  m_notesState = p.notesState;
  emit notesStateChanged();
  // Events are global — not reset on profile switch.
}

Profile AppController::makeStartingProfile(const QString& name, const QString& color) const {
  Profile p;
  p.name = name;
  p.color = color.isEmpty() ? "#5cc2dd" : color;
  p.createdAt = QDateTime::currentDateTime();
  // Copy status template from the currently active profile (or sample).
  const int activeIdx = profileIndexOf(m_activeProfileId);
  if(activeIdx >= 0) {
    for(const QVariant& v : m_profiles[activeIdx].statuses) {
      const QVariantMap m = v.toMap();
      // copy color reference as-is
      p.statuses.append(m);
    }
  } else {
    for(const auto& m : SampleData::statuses()) {
      p.statuses.append(m);
    }
  }
  // tasks / events / people / docs — empty
  return p;
}

// ───────────────── Save / load (schema v2) ─────────────────

void AppController::rotateBackupIfDue() {
  const QVariantMap d = settingsMap().value("data").toMap();
  if(!d.value("autoBackup", true).toBool()) {
    return;
  }
  const QString path = stateFilePath();
  if(!QFile::exists(path)) {
    return;
  }
  const QDateTime now = QDateTime::currentDateTime();
  qint64 intervalSecs = kBackupIntervalSeconds;
  const QString interval = d.value("backupInterval", QStringLiteral("daily")).toString();
  if(interval == QLatin1String("hourly")) {
    intervalSecs = 3600;
  } else if(interval == QLatin1String("daily")) {
    intervalSecs = 24 * 3600;
  } else if(interval == QLatin1String("weekly")) {
    intervalSecs = 7 * 24 * 3600;
  }
  if(m_lastBackupAt.isValid() && m_lastBackupAt.secsTo(now) < intervalSecs) {
    return;
  }
  const QString dir = backupDirPath();
  const QString stamp = now.toString("yyyyMMdd-HHmmss");
  QFile::copy(path, dir + "/state-" + stamp + ".json");
  pruneBackups(kBackupRetentionCount);
  m_lastBackupAt = now;
}

void AppController::pruneBackups(int keep) {
  QDir d(backupDirPath());
  const QStringList all = d.entryList({"state-*.json"}, QDir::Files | QDir::NoSymLinks, QDir::Time);
  for(int i = keep; i < all.size(); ++i) {
    d.remove(all[i]);
  }
}

void AppController::saveStateNow() {
  if(m_loading) {
    return;
  }

  // Push live model state back into the active profile.
  snapshotActiveProfile();

  QJsonObject root;
  root["schemaVersion"] = 3;
  root["activeProfileId"] = m_activeProfileId;

  QJsonArray profilesArr;
  for(const Profile& p : m_profiles) {
    profilesArr.append(profileToJson(p));
  }
  root["profiles"] = profilesArr;

  // Events are global (shown across profiles in the calendar).
  root["events"] = eventsToJson(m_events.items());

  QJsonObject s;
  s["theme"] = m_theme;
  s["density"] = m_density;
  s["language"] = m_language;
  s["currentView"] = m_currentView;
  s["workdayStart"] = m_workdayStart;
  s["workdayEnd"] = m_workdayEnd;
  s["crumbProject"] = m_crumbProject;
  s["crumbUser"] = m_crumbUser;

  // Keyboard shortcut overrides — store every entry (so a user-cleared
  // binding survives a restart even if the default is non-empty).
  QJsonObject shortcutsObj;
  for(const QVariant& v : m_shortcuts) {
    const QVariantMap m = v.toMap();
    shortcutsObj[m.value("id").toString()] = m.value("sequence").toString();
  }
  s["shortcuts"] = shortcutsObj;

  if(!m_appSettingsJson.isEmpty()) {
    const QJsonDocument d = QJsonDocument::fromJson(m_appSettingsJson.toUtf8());
    if(!d.isNull() && d.isObject()) {
      s["app"] = d.object();
    }
  }

  root["settings"] = s;

  rotateBackupIfDue();

  QSaveFile f(stateFilePath());
  if(!f.open(QIODevice::WriteOnly)) {
    qWarning("todocpp: cannot open state.json for writing: %s", qUtf8Printable(f.errorString()));
    return;
  }
  f.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
  if(!f.commit()) {
    qWarning("todocpp: state.json commit failed: %s", qUtf8Printable(f.errorString()));
  }
}

void AppController::loadStateOnStart() {
  QFile f(stateFilePath());
  if(!f.exists() || !f.open(QFile::ReadOnly)) {
    return;
  }
  const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
  if(doc.isNull() || !doc.isObject()) {
    return;
  }
  const QJsonObject root = doc.object();

  m_loading = true;

  // ----- settings (global) -----
  if(root.contains("settings")) {
    const QJsonObject s = root["settings"].toObject();
    if(s.contains("theme")) {
      m_theme = s["theme"].toString();
      emit themeChanged();
    }
    if(s.contains("density")) {
      m_density = s["density"].toString();
      emit densityChanged();
    }
    if(s.contains("language")) {
      const QString v = s["language"].toString();
      m_language = (v == "ru") ? QStringLiteral("ru") : QStringLiteral("en");
      emit languageChanged();
    }
    if(s.contains("currentView")) {
      m_currentView = s["currentView"].toString();
      emit currentViewChanged();
    }
    if(s.contains("workdayStart") || s.contains("workdayEnd")) {
      if(s.contains("workdayStart")) {
        m_workdayStart = s["workdayStart"].toInt(m_workdayStart);
      }
      if(s.contains("workdayEnd")) {
        m_workdayEnd = s["workdayEnd"].toInt(m_workdayEnd);
      }
      emit workdayChanged();
    }
    if(s.contains("crumbProject")) {
      m_crumbProject = s["crumbProject"].toString();
      emit crumbProjectChanged();
    }
    if(s.contains("crumbUser")) {
      m_crumbUser = s["crumbUser"].toString();
      emit crumbUserChanged();
    }
    if(s.contains("shortcuts")) {
      QVariantMap overrides;
      const QJsonObject shortcutsObj = s["shortcuts"].toObject();
      for(auto it = shortcutsObj.constBegin(); it != shortcutsObj.constEnd(); ++it) {
        overrides.insert(it.key(), it.value().toString());
      }
      applyShortcutOverrides(overrides);
    }
    if(s.contains("app") && s["app"].isObject()) {
      m_appSettingsJson = QJsonDocument(s["app"].toObject()).toJson(QJsonDocument::Compact);
      emit appSettingsJsonChanged();
    }
  }

  const int schema = root.value("schemaVersion").toInt(1);
  QVector<CalEvent> globalEvents;

  if(schema >= 2 && root.contains("profiles")) {
    // ----- schema v2 / v3: profiles array -----
    for(const auto& it : root["profiles"].toArray()) {
      // For v2, profiles still carried their own events — hoist them
      // into the global pool tagged with the source profile id.
      QVector<CalEvent> legacy;
      m_profiles.push_back(profileFromJson(it.toObject(), schema < 3 ? &legacy : nullptr));
      if(!legacy.isEmpty()) {
        globalEvents.append(legacy);
      }
    }
    m_activeProfileId = root.value("activeProfileId").toString();
    if(profileIndexOf(m_activeProfileId) < 0 && !m_profiles.isEmpty()) {
      m_activeProfileId = m_profiles.first().id;
    }
    // schema v3 keeps events at top level.
    if(schema >= 3 && root.contains("events")) {
      globalEvents = eventsFromJson(root["events"].toArray());
    }
  } else {
    // ----- schema v1: flat fields → wrap into one "Example" profile -----
    Profile p;
    p.id = "default";
    p.name = "Example";
    p.color = "#5cc2dd";
    p.createdAt = QDateTime::currentDateTime();
    if(root.contains("tasks")) {
      p.tasks = tasksFromJson(root["tasks"].toArray());
    }
    if(root.contains("people")) {
      p.people = peopleFromJson(root["people"].toArray());
    }
    if(root.contains("statuses")) {
      p.statuses = statusesFromJson(root["statuses"].toArray());
    }
    if(root.contains("docs")) {
      p.docsState = QJsonDocument(root["docs"].toObject()).toJson(QJsonDocument::Compact);
    }
    // Hoist any legacy top-level events into the global pool.
    if(root.contains("events")) {
      globalEvents = eventsFromJson(root["events"].toArray(), p.id);
    }
    m_profiles.push_back(p);
    m_activeProfileId = p.id;
  }

  m_events.reset(globalEvents);

  if(!m_profiles.isEmpty()) {
    const int ai = qMax(0, profileIndexOf(m_activeProfileId));
    applyProfileToModels(m_profiles[ai]);
  }

  m_loading = false;

  emit profilesChanged();
  emit activeProfileChanged();

  // Force a rewrite to upgrade the on-disk file to v3 if we just migrated.
  if(schema < 3) {
    scheduleSave();
  }
}

// ───────────────────────────────────────────────────── Profiles API ──

QVariantList AppController::profiles() const {
  QVariantList out;
  for(const Profile& p : m_profiles) {
    QVariantMap m;
    m["id"] = p.id;
    m["name"] = p.name;
    m["color"] = p.color;
    m["tasks"] = p.tasks.size();
    m["docs"] = p.docsState.size() > 2 ? 1 : 0;
    m["createdAt"] = p.createdAt.isValid() ? p.createdAt.toString(Qt::ISODate) : QString();
    out.append(m);
  }
  return out;
}

void AppController::setActiveProfileId(const QString& id) {
  if(id == m_activeProfileId) {
    return;
  }
  const int next = profileIndexOf(id);
  if(next < 0) {
    return;
  }
  clearSelection();
  snapshotActiveProfile();
  m_activeProfileId = id;
  applyProfileToModels(m_profiles[next]);
  emit activeProfileChanged();
  scheduleSave();
}

QString AppController::createProfile(const QString& name, const QString& color) {
  if(name.trimmed().isEmpty()) {
    return QString();
  }
  // Snapshot current active before creating so we don't lose unsaved edits.
  snapshotActiveProfile();
  Profile p = makeStartingProfile(name.trimmed(), color);
  p.id = makeProfileId(name.trimmed());
  m_profiles.push_back(p);
  m_activeProfileId = p.id;
  applyProfileToModels(p);
  emit profilesChanged();
  emit activeProfileChanged();
  emit toast(tr_("profile.created").arg(p.name));
  scheduleSave();
  return p.id;
}

void AppController::renameProfile(const QString& id, const QString& newName) {
  const int i = profileIndexOf(id);
  if(i < 0 || newName.trimmed().isEmpty()) {
    return;
  }
  if(m_profiles[i].name == newName) {
    return;
  }
  m_profiles[i].name = newName.trimmed();
  emit profilesChanged();
  if(id == m_activeProfileId) {
    emit activeProfileChanged();
  }
  scheduleSave();
}

void AppController::setProfileColor(const QString& id, const QString& color) {
  const int i = profileIndexOf(id);
  if(i < 0) {
    return;
  }
  const QColor c(color);
  if(!c.isValid()) {
    return;
  }
  m_profiles[i].color = c.name();
  emit profilesChanged();
  if(id == m_activeProfileId) {
    emit activeProfileChanged();
  }
  scheduleSave();
}

void AppController::deleteProfile(const QString& id) {
  const int i = profileIndexOf(id);
  if(i < 0 || m_profiles.size() <= 1) {
    return;  // never let the app run out of profiles
  }
  cancelUndo();
  snapshotActiveProfile();
  m_pendingUndo = {};
  m_pendingUndo.kind = PendingUndo::Profile;
  m_pendingUndo.profile = m_profiles[i];
  m_pendingUndo.row = i;
  const QString name = m_profiles[i].name;
  m_profiles.removeAt(i);

  // Events that were attributed to this profile become "unassigned"
  // (still visible in the calendar, but with no feature dot).
  for(int r = 0; r < m_events.rowCount(); ++r) {
    const QModelIndex mi = m_events.index(r, 0);
    if(m_events.data(mi, EventModel::ProfileIdRole).toString() == id) {
      const CalEvent& e = m_events.items().at(r);
      CalEvent copy = e;
      copy.profileId.clear();
      m_events.upsert(copy);
    }
  }

  // If we deleted the active one, fall back to its neighbour.
  if(id == m_activeProfileId) {
    const int fallback = qMin(i, m_profiles.size() - 1);
    m_activeProfileId = m_profiles[fallback].id;
    applyProfileToModels(m_profiles[fallback]);
    emit activeProfileChanged();
  }
  emit profilesChanged();
  armUndo(5);
  emit undoableToast(tr_("profile.deleted").arg(name), 5);
  scheduleSave();
}

QVariantMap AppController::profileById(const QString& id) const {
  const int i = profileIndexOf(id);
  if(i < 0) {
    return {};
  }
  const Profile& p = m_profiles[i];
  QVariantMap m;
  m["id"] = p.id;
  m["name"] = p.name;
  m["color"] = p.color;
  return m;
}

QString AppController::duplicateProfile(const QString& id, const QString& newName) {
  const int i = profileIndexOf(id);
  if(i < 0) {
    return QString();
  }
  if(id == m_activeProfileId) {
    snapshotActiveProfile();
  }
  Profile copy = m_profiles[i];
  copy.name = newName.trimmed().isEmpty() ? (m_profiles[i].name + " copy") : newName.trimmed();
  copy.id = makeProfileId(copy.name);
  copy.createdAt = QDateTime::currentDateTime();
  m_profiles.push_back(copy);
  m_activeProfileId = copy.id;
  applyProfileToModels(copy);
  emit profilesChanged();
  emit activeProfileChanged();
  emit toast(tr_("profile.duplicated").arg(copy.name));
  scheduleSave();
  return copy.id;
}

int AppController::renameTaskIdPrefix(const QString& oldPrefix, const QString& newPrefix) {
  const QString from = oldPrefix.trimmed().toUpper();
  const QString to = newPrefix.trimmed().toUpper();
  if(from.isEmpty() || to.isEmpty() || from == to) {
    return 0;
  }

  // Persist the live model back into the active profile so we walk a
  // single source of truth — m_profiles holds the canonical list while
  // m_tasks mirrors only the active one.
  snapshotActiveProfile();

  const QRegularExpression rx(QStringLiteral("^") + QRegularExpression::escape(from) + QStringLiteral("-(\\d+)$"),
                              QRegularExpression::CaseInsensitiveOption);

  QHash<QString, QString> remap;  // old id → new id, for CalEvent.taskId fix-up
  int renamed = 0;

  for(Profile& pr : m_profiles) {
    for(Task& t : pr.tasks) {
      const auto m = rx.match(t.id);
      if(!m.hasMatch()) {
        continue;
      }
      const QString next = to + QChar('-') + m.captured(1);
      remap.insert(t.id, next);
      t.id = next;
      ++renamed;
    }
  }

  if(!remap.isEmpty()) {
    const auto& events = m_events.items();
    for(const auto& event : events) {
      const QString& tid = event.taskId;
      auto it = remap.find(tid);
      if(it == remap.end()) {
        continue;
      }
      CalEvent copy = event;
      copy.taskId = it.value();
      m_events.upsert(copy);
    }

    const int ai = profileIndexOf(m_activeProfileId);
    if(ai >= 0) {
      applyProfileToModels(m_profiles[ai]);
    }
    scheduleSave();
    emit toast(tr_("tasks.renamed").arg(renamed));
  }

  return renamed;
}

// ───────────────────────────────────────────────────── Backups API ──

QVariantList AppController::listBackups() const {
  QVariantList out;
  const QDir d(backupDirPath());
  const QStringList files = d.entryList({"state-*.json"}, QDir::Files | QDir::NoSymLinks, QDir::Time);
  for(const QString& name : files) {
    const QFileInfo fi(d.filePath(name));
    QVariantMap m;
    m["fileName"] = name;
    m["sizeKb"] = (fi.size() / 1024);
    m["mtime"] = fi.lastModified().toString(Qt::ISODate);
    out.append(m);
  }
  return out;
}

bool AppController::restoreFromBackup(const QString& fileName) {
  const QString src = backupDirPath() + "/" + fileName;
  if(!QFile::exists(src)) {
    return false;
  }
  // Snapshot current state alongside backups before overwriting.
  rotateBackupIfDue();
  flushSave();
  QFile target(stateFilePath());
  if(target.exists()) {
    target.remove();
  }
  if(!QFile::copy(src, stateFilePath())) {
    return false;
  }

  // Reload from disk.
  m_profiles.clear();
  m_activeProfileId.clear();
  loadStateOnStart();
  emit toast(tr_("backup.restored").arg(fileName));
  return true;
}

// ───────────────────────────────────────────── Command palette source ──

QVariantList AppController::commandPaletteEntries() const {
  QVariantList out;

  // Profiles themselves.
  for(const Profile& p : m_profiles) {
    QVariantMap m;
    m["kind"] = "profile";
    m["label"] = p.name;
    m["sub"] = QString("%1 tasks").arg(p.tasks.size());
    m["profileId"] = p.id;
    m["color"] = p.color;
    out.append(m);
  }

  auto statusName = [](const QVariantList& statuses, const QString& id) {
    for(const QVariant& v : statuses) {
      const QVariantMap m = v.toMap();
      if(m.value("id").toString() == id) {
        return m.value("name").toString();
      }
    }
    return id;
  };

  for(const Profile& p : m_profiles) {
    // Tasks
    for(const Task& t : p.tasks) {
      QVariantMap m;
      m["kind"] = "task";
      m["label"] = QString("%1 · %2").arg(t.id, t.title);
      m["sub"] = QString("%1 · %2").arg(p.name, statusName(p.statuses, t.status).toUpper());
      m["profileId"] = p.id;
      m["taskId"] = t.id;
      m["color"] = p.color;
      out.append(m);
    }
    // Docs / snippets / contacts (parsed from docsState JSON blob)
    if(!p.docsState.isEmpty()) {
      const QJsonDocument d = QJsonDocument::fromJson(p.docsState.toUtf8());
      if(!d.isNull() && d.isObject()) {
        const QJsonObject root = d.object();
        for(const auto& sIt : root["sections"].toArray()) {
          const QJsonObject sec = sIt.toObject();
          const QString secId = sec["id"].toString();
          const QString secTitle = sec["title"].toString();
          for(const auto& iIt : sec["items"].toArray()) {
            const QJsonObject it = iIt.toObject();
            QVariantMap m;
            m["kind"] = "doc";
            m["label"] = QString("%1 · %2").arg(it["ref"].toString(), it["title"].toString());
            m["sub"] = QString("%1 · %2").arg(p.name, secTitle);
            m["profileId"] = p.id;
            m["sectionId"] = secId;
            m["color"] = p.color;
            out.append(m);
          }
        }
        int snipIdx = 0;
        for(const auto& snIt : root["snippets"].toArray()) {
          const QJsonObject sn = snIt.toObject();
          QVariantMap m;
          m["kind"] = "snippet";
          m["label"] = sn["title"].toString();
          m["sub"] = QString("%1 · %2").arg(p.name, sn["lang"].toString());
          m["profileId"] = p.id;
          m["idx"] = snipIdx++;
          m["color"] = p.color;
          out.append(m);
        }
        int contactIdx = 0;
        for(const auto& cIt : root["contacts"].toArray()) {
          const QJsonObject c = cIt.toObject();
          QVariantMap m;
          m["kind"] = "contact";
          m["label"] = c["name"].toString();
          m["sub"] = QString("%1 · %2").arg(p.name, c["role"].toString());
          m["profileId"] = p.id;
          m["idx"] = contactIdx++;
          m["color"] = p.color;
          out.append(m);
        }
      }
    }
    // People (pending contacts list)
    for(const Person& person : p.people) {
      QVariantMap m;
      m["kind"] = "person";
      m["label"] = person.name;
      m["sub"] = QString("%1 · %2").arg(p.name, person.role);
      m["profileId"] = p.id;
      m["personId"] = person.id;
      m["color"] = p.color;
      out.append(m);
    }
  }

  return out;
}

// ───────────────────────────────────── JSON import / export of profile ──

QString AppController::exportActiveProfileJson() const {
  const int i = profileIndexOf(m_activeProfileId);
  if(i < 0) {
    return QString();
  }
  // Snapshot the live models into the profile copy we serialise, so
  // unsaved edits in tasks/people/statuses/docs/notes round-trip.
  Profile p = m_profiles[i];
  p.tasks = m_tasks.items();
  p.people = m_people.items();
  p.statuses = m_statuses;
  p.docsState = m_docsState;
  p.notesState = m_notesState;
  QJsonObject root;
  root["schemaVersion"] = 3;
  root["kind"] = "todocpp.profile";
  root["exportedAt"] = QDateTime::currentDateTime().toString(Qt::ISODate);
  root["profile"] = profileToJson(p);
  return QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Indented));
}

bool AppController::exportActiveProfileToFile(const QUrl& fileUrl) const {
  const QString path = fileUrl.isLocalFile() ? fileUrl.toLocalFile() : fileUrl.toString();
  if(path.isEmpty()) {
    return false;
  }
  const QString json = exportActiveProfileJson();
  if(json.isEmpty()) {
    return false;
  }
  QSaveFile f(path);
  if(!f.open(QIODevice::WriteOnly)) {
    qWarning("todocpp: cannot open %s for writing: %s", qUtf8Printable(path), qUtf8Printable(f.errorString()));
    return false;
  }
  f.write(json.toUtf8());
  if(!f.commit()) {
    return false;
  }
  const_cast<AppController*>(this)->emit toast(tr_("profile.exported").arg(QFileInfo(path).fileName()));
  return true;
}

QString AppController::importProfileFromJson(const QString& jsonText, bool activate) {
  if(jsonText.trimmed().isEmpty()) {
    return tr_("import.emptyJson");
  }
  const QJsonDocument doc = QJsonDocument::fromJson(jsonText.toUtf8());
  if(doc.isNull() || !doc.isObject()) {
    return tr_("import.invalidJson");
  }
  const QJsonObject root = doc.object();

  // Accept either { "profile": {...} } wrapper or a bare profile object.
  QJsonObject profileObj;
  if(root.contains("profile") && root["profile"].isObject()) {
    profileObj = root["profile"].toObject();
  } else if(root.contains("id") && root.contains("name")) {
    profileObj = root;
  } else {
    return tr_("import.missingProfile");
  }

  Profile imported = profileFromJson(profileObj);
  if(imported.name.trimmed().isEmpty()) {
    imported.name = QStringLiteral("Imported");
  }

  // Resolve id collisions — re-slug so we never overwrite an existing profile.
  if(imported.id.isEmpty() || profileIndexOf(imported.id) >= 0) {
    imported.id = makeProfileId(imported.name);
  }
  imported.createdAt = QDateTime::currentDateTime();
  if(imported.color.isEmpty()) {
    imported.color = QStringLiteral("#5cc2dd");
  }
  if(imported.statuses.isEmpty()) {
    for(const auto& m : SampleData::statuses()) {
      imported.statuses.append(m);
    }
  }

  if(activate) {
    snapshotActiveProfile();
  }
  m_profiles.push_back(imported);
  if(activate) {
    m_activeProfileId = imported.id;
    applyProfileToModels(imported);
    emit activeProfileChanged();
  }
  emit profilesChanged();
  emit toast(tr_("profile.imported").arg(imported.name));
  scheduleSave();
  return QString();
}

QString AppController::importProfileFromFile(const QUrl& fileUrl, bool activate) {
  const QString path = fileUrl.isLocalFile() ? fileUrl.toLocalFile() : fileUrl.toString();
  if(path.isEmpty()) {
    return tr_("import.emptyPath");
  }
  QFile f(path);
  if(!f.open(QIODevice::ReadOnly)) {
    return tr_("import.openFail") + f.errorString();
  }
  const QString text = QString::fromUtf8(f.readAll());
  return importProfileFromJson(text, activate);
}

// ─────────────────────────────────────────────── Shortcuts catalog ──

void AppController::seedShortcutCatalog() {
  // Snapshot any user-set sequences before the labels are rebuilt so a
  // language flip preserves rebinds.
  QMap<QString, QString> existingOverrides;
  for(const QVariant& v : m_shortcuts) {
    const QVariantMap m = v.toMap();
    const QString id = m.value("id").toString();
    const QString def = m.value("defaultSequence").toString();
    const QString cur = m.value("sequence").toString();
    if(cur != def) {
      existingOverrides.insert(id, cur);
    }
  }

  auto add = [this](const char* id, const char* defaultSeq) {
    QVariantMap m;
    const QString sid = QString::fromUtf8(id);
    m["id"] = sid;
    m["label"] = tr_(QString("shortcut.%1.label").arg(sid));
    m["description"] = tr_(QString("shortcut.%1.desc").arg(sid));
    m["defaultSequence"] = QString::fromUtf8(defaultSeq);
    m["sequence"] = QString::fromUtf8(defaultSeq);
    m_shortcuts.append(m);
  };

  m_shortcuts.clear();
  add("palette.open", "Ctrl+K");
  add("task.new", "Ctrl+N");
  add("view.board", "Ctrl+1");
  add("view.timeline", "Ctrl+2");
  add("view.week", "Ctrl+3");
  add("view.docs", "Ctrl+4");
  add("view.notes", "Ctrl+5");
  add("view.settings", "Ctrl+6");
  add("profile.next", "Ctrl+]");
  add("profile.prev", "Ctrl+[");
  add("profile.exportMd", "Ctrl+Shift+E");
  add("tweaks.open", "Ctrl+,");
  add("hotkeys.open", "Ctrl+/");
  add("undo", "Ctrl+Z");
  add("search.focus", "Ctrl+F");
  add("quick-capture", "Ctrl+Shift+Space");
  add("quick-capture-notes", "Ctrl+Shift+N");
  add("selection.selectAll", "Ctrl+A");
  add("selection.clearSel", "Esc");
  add("selection.deleteSel", "Del");

  if(!existingOverrides.isEmpty()) {
    QVariantMap asMap;
    for(auto it = existingOverrides.constBegin(); it != existingOverrides.constEnd(); ++it) {
      asMap.insert(it.key(), it.value());
    }
    applyShortcutOverrides(asMap);
  }
  emit shortcutsChanged();
}

void AppController::registerGlobalHotkeys() {
  if(!m_globalHotkey) {
    return;
  }
  // Each global capture hotkey mirrors its in-app catalog binding, so one place
  // in Settings → Hotkeys controls both. RegisterHotKey intercepts the
  // combination even when the window is focused, so the in-app QML Shortcut
  // only fires as a fallback when the OS registration is refused.
  const auto arm = [this](int id, const QString& catalogId) {
    const QString seq = shortcutFor(catalogId);
    if(seq.isEmpty() || !m_globalHotkey->registerHotkey(id, seq)) {
      m_globalHotkey->unregister(id);
    }
  };
  arm(HotkeyQuickCapture, QStringLiteral("quick-capture"));
  arm(HotkeyQuickCaptureNotes, QStringLiteral("quick-capture-notes"));
}

void AppController::onGlobalHotkey(int id) {
  switch(id) {
    case HotkeyQuickCapture:
      emit quickCaptureRequested();
      break;
    case HotkeyQuickCaptureNotes:
      emit quickCaptureNotesRequested();
      break;
    default:
      break;
  }
}

int AppController::shortcutIndexOf(const QString& id) const {
  for(int i = 0; i < m_shortcuts.size(); ++i) {
    if(m_shortcuts[i].toMap().value("id").toString() == id) {
      return i;
    }
  }
  return -1;
}

QString AppController::normalizeSequence(const QString& raw) const {
  const QString trimmed = raw.trimmed();
  if(trimmed.isEmpty()) {
    return QString();
  }
  const QKeySequence ks(trimmed, QKeySequence::PortableText);
  if(ks.isEmpty()) {
    return QString();
  }
  return ks.toString(QKeySequence::PortableText);
}

void AppController::applyShortcutOverrides(const QVariantMap& overrides) {
  bool changed = false;
  for(auto& m_shortcut : m_shortcuts) {
    QVariantMap m = m_shortcut.toMap();
    const QString id = m.value("id").toString();
    if(!overrides.contains(id)) {
      continue;
    }
    const QString seq = normalizeSequence(overrides.value(id).toString());
    if(seq == m.value("sequence").toString()) {
      continue;
    }
    m["sequence"] = seq;
    m_shortcut = m;
    changed = true;
  }
  if(changed) {
    emit shortcutsChanged();
  }
}

QString AppController::shortcutFor(const QString& id) const {
  const int i = shortcutIndexOf(id);
  return i < 0 ? QString() : m_shortcuts[i].toMap().value("sequence").toString();
}

QString AppController::defaultShortcutFor(const QString& id) const {
  const int i = shortcutIndexOf(id);
  return i < 0 ? QString() : m_shortcuts[i].toMap().value("defaultSequence").toString();
}

QString AppController::shortcutDescription(const QString& id) const {
  const int i = shortcutIndexOf(id);
  return i < 0 ? QString() : m_shortcuts[i].toMap().value("description").toString();
}

QString AppController::shortcutLabel(const QString& id) const {
  const int i = shortcutIndexOf(id);
  return i < 0 ? QString() : m_shortcuts[i].toMap().value("label").toString();
}

QString AppController::findShortcutConflict(const QString& id, const QString& sequence) const {
  const QString want = normalizeSequence(sequence);
  if(want.isEmpty()) {
    return QString();
  }
  for(const auto& m_shortcut : m_shortcuts) {
    const QVariantMap m = m_shortcut.toMap();
    if(m.value("id").toString() == id) {
      continue;
    }
    if(m.value("sequence").toString() == want) {
      return m.value("id").toString();
    }
  }
  return QString();
}

bool AppController::setShortcut(const QString& id, const QString& sequence) {
  const int i = shortcutIndexOf(id);
  if(i < 0) {
    return false;
  }
  const QString seq = normalizeSequence(sequence);
  QVariantMap m = m_shortcuts[i].toMap();
  if(m.value("sequence").toString() == seq) {
    return true;
  }

  // VS-Code-style swap: clear the conflicting owner so the new binding wins.
  if(!seq.isEmpty()) {
    const QString conflictId = findShortcutConflict(id, seq);
    if(!conflictId.isEmpty()) {
      const int j = shortcutIndexOf(conflictId);
      if(j >= 0) {
        QVariantMap o = m_shortcuts[j].toMap();
        const QString freedLabel = o.value("label").toString();
        o["sequence"] = QString();
        m_shortcuts[j] = o;
        emit toast(tr_("slot.freed").arg(freedLabel));
      }
    }
  }

  m["sequence"] = seq;
  m_shortcuts[i] = m;
  emit shortcutsChanged();
  // Re-arm both capture hotkeys — the change may have retargeted a capture
  // binding or freed one via conflict resolution above.
  registerGlobalHotkeys();
  scheduleSave();
  return true;
}

void AppController::resetShortcut(const QString& id) {
  const int i = shortcutIndexOf(id);
  if(i < 0) {
    return;
  }
  QVariantMap m = m_shortcuts[i].toMap();
  const QString def = m.value("defaultSequence").toString();
  if(m.value("sequence").toString() == def) {
    return;
  }
  // If the default would conflict with another action, swap it out.
  const QString conflictId = findShortcutConflict(id, def);
  if(!conflictId.isEmpty()) {
    const int j = shortcutIndexOf(conflictId);
    if(j >= 0) {
      QVariantMap o = m_shortcuts[j].toMap();
      o["sequence"] = QString();
      m_shortcuts[j] = o;
    }
  }
  m["sequence"] = def;
  m_shortcuts[i] = m;
  emit shortcutsChanged();
  registerGlobalHotkeys();
  scheduleSave();
}

void AppController::resetAllShortcuts() {
  bool changed = false;
  for(auto& m_shortcut : m_shortcuts) {
    QVariantMap m = m_shortcut.toMap();
    const QString def = m.value("defaultSequence").toString();
    if(m.value("sequence").toString() != def) {
      m["sequence"] = def;
      m_shortcut = m;
      changed = true;
    }
  }
  if(changed) {
    emit shortcutsChanged();
    scheduleSave();
    registerGlobalHotkeys();
    emit toast(tr_("hotkeys.reset"));
  }
}

// ── Notifications, transitions, automation ─────────────────────────────

QVariantMap AppController::settingsMap() const {
  if(m_appSettingsJson.isEmpty()) {
    return {};
  }
  QJsonParseError err;
  const QJsonDocument doc = QJsonDocument::fromJson(m_appSettingsJson.toUtf8(), &err);
  if(err.error != QJsonParseError::NoError || !doc.isObject()) {
    return {};
  }
  return doc.object().toVariantMap();
}

bool AppController::canTransitionStatus(const QString& taskId, const QString& newStatus) {
  const int row = m_tasks.indexOfId(taskId);
  if(row < 0) {
    return false;
  }
  const Task& t = m_tasks.items().at(row);
  if(newStatus == QStringLiteral("review")) {
    const QVariantMap s = settingsMap();
    const QVariantMap tasks = s.value("tasks").toMap();
    if(tasks.value("requireBranchOnReview", true).toBool() && t.branch.trimmed().isEmpty()) {
      emit toast(tr_("branch.required"));
      return false;
    }
  }
  return true;
}

void AppController::setArchived(const QString& taskId, bool archived) {
  m_tasks.setArchived(taskId, archived);
  scheduleSave();
}

// ─────────────────────────────────────────────────── Multi-select ──

bool AppController::isTaskSelected(const QString& id) const {
  return m_selectedTaskIds.contains(id);
}

void AppController::rebuildSelectionList_() {
  // Stable order: by current row in m_tasks. Tasks no longer present (e.g.
  // deleted while selected) drop out of the list.
  QVector<QPair<int, QString>> rows;
  rows.reserve(m_selectedTaskIds.size());
  for(const QString& id : m_selectedTaskIds) {
    const int r = m_tasks.indexOfId(id);
    if(r >= 0) {
      rows.append({r, id});
    }
  }
  std::sort(rows.begin(), rows.end(), [](const auto& a, const auto& b) {
    return a.first < b.first;
  });
  QSet<QString> live;
  QStringList list;
  list.reserve(rows.size());
  for(const auto& p : rows) {
    list.append(p.second);
    live.insert(p.second);
  }
  m_selectedTaskIds = live;
  m_selectedTaskIdsList = list;
}

void AppController::toggleTaskSelection(const QString& id) {
  if(id.isEmpty()) {
    return;
  }
  if(m_selectedTaskIds.contains(id)) {
    m_selectedTaskIds.remove(id);
  } else {
    m_selectedTaskIds.insert(id);
  }
  rebuildSelectionList_();
  emit selectedTaskIdsChanged();
}

void AppController::setTaskSelected(const QString& id, bool selected) {
  if(id.isEmpty()) {
    return;
  }
  const bool had = m_selectedTaskIds.contains(id);
  if(selected == had) {
    return;
  }
  if(selected) {
    m_selectedTaskIds.insert(id);
  } else {
    m_selectedTaskIds.remove(id);
  }
  rebuildSelectionList_();
  emit selectedTaskIdsChanged();
}

void AppController::setSelectedTaskIds(const QStringList& ids) {
  const QSet<QString> next(ids.constBegin(), ids.constEnd());
  if(next == m_selectedTaskIds) {
    return;
  }
  m_selectedTaskIds = next;
  rebuildSelectionList_();
  emit selectedTaskIdsChanged();
}

void AppController::clearSelection() {
  if(m_selectedTaskIds.isEmpty() && m_selectedTaskIdsList.isEmpty()) {
    return;
  }
  m_selectedTaskIds.clear();
  m_selectedTaskIdsList.clear();
  emit selectedTaskIdsChanged();
}

void AppController::deleteSelectedTasks() {
  if(m_selectedTaskIdsList.isEmpty()) {
    return;
  }

  // Snapshot tasks + rows in ascending-row order for clean re-insertion.
  QVector<QPair<int, ::Task>> snap;
  snap.reserve(m_selectedTaskIdsList.size());
  for(const QString& id : m_selectedTaskIdsList) {
    const int row = m_tasks.indexOfId(id);
    if(row < 0) {
      continue;
    }
    snap.append({row, m_tasks.items().at(row)});
  }
  if(snap.isEmpty()) {
    clearSelection();
    return;
  }
  std::sort(snap.begin(), snap.end(), [](const auto& a, const auto& b) {
    return a.first < b.first;
  });

  cancelUndo();
  m_pendingUndo = {};
  m_pendingUndo.kind = PendingUndo::BulkTasks;
  m_pendingUndo.tasks.reserve(snap.size());
  m_pendingUndo.rows.reserve(snap.size());
  QSet<QString> ids;
  for(const auto& p : snap) {
    m_pendingUndo.rows.append(p.first);
    m_pendingUndo.tasks.append(p.second);
    ids.insert(p.second.id);
  }
  for(const auto& e : m_events.items()) {
    if(ids.contains(e.taskId)) {
      m_pendingUndo.detachedEventIds.append({e.id, e.taskId});
    }
  }
  // Detach events first, then remove tasks. Removal order doesn't matter
  // for removeById; we walk the snapshot in any direction.
  for(const QString& id : std::as_const(ids)) {
    m_events.detachTask(id);
  }
  for(const auto& p : snap) {
    m_tasks.removeById(p.second.id);
  }

  const int n = snap.size();
  armUndo(5);
  emit undoableToast(tr_("selection.toast.deleted").arg(n), 5);
  clearSelection();
  scheduleSave();
}

void AppController::moveSelectedTasksToStatus(const QString& statusId) {
  if(m_selectedTaskIdsList.isEmpty() || statusId.isEmpty()) {
    return;
  }
  if(statusIndexOf(statusId) < 0) {
    return;
  }
  int moved = 0;
  for(const QString& id : m_selectedTaskIdsList) {
    const int row = m_tasks.indexOfId(id);
    if(row < 0) {
      continue;
    }
    if(m_tasks.items().at(row).status == statusId) {
      continue;
    }
    m_tasks.setStatus(id, statusId);
    m_tasks.stampStatusChange(id);
    ++moved;
  }
  if(moved > 0) {
    emit toast(tr_("selection.toast.moved").arg(moved));
    scheduleSave();
  }
}

void AppController::setSelectedTasksArchived(bool archived) {
  if(m_selectedTaskIdsList.isEmpty()) {
    return;
  }
  int n = 0;
  for(const QString& id : m_selectedTaskIdsList) {
    if(m_tasks.indexOfId(id) < 0) {
      continue;
    }
    m_tasks.setArchived(id, archived);
    ++n;
  }
  if(n > 0) {
    emit toast(tr_(archived ? "selection.toast.archived" : "selection.toast.unarchived").arg(n));
    // Drop the selection after a bulk archive/restore. Tickets just left
    // the current view (archive view loses unarchived ones; board loses
    // archived ones), so keeping the prior selection is confusing.
    clearSelection();
    scheduleSave();
  }
}

void AppController::notify(const QString& title, const QString& body, const QString& kind) {
  emit notification(title, body, kind);
}

bool AppController::inQuietHours(const QDateTime& when) const {
  const QVariantMap s = settingsMap();
  const QVariantMap notif = s.value("notifications").toMap();
  if(!notif.value("quietHours", true).toBool()) {
    return false;
  }
  const QTime from = QTime::fromString(notif.value("quietFrom", "19:00").toString(), "HH:mm");
  const QTime to = QTime::fromString(notif.value("quietTo", "09:00").toString(), "HH:mm");
  if(!from.isValid() || !to.isValid()) {
    return false;
  }
  const QTime now = when.time();
  if(from <= to) {
    return now >= from && now < to;
  }
  // Window wraps midnight (e.g. 19:00..09:00).
  return now >= from || now < to;
}

double AppController::nextQuarterHour(const QDateTime& when) {
  const QTime t = when.time();
  const double cur = t.hour() + t.minute() / 60.0;
  const double q = std::ceil(cur * 4.0) / 4.0;
  return std::min(q, 24.0);
}

void AppController::scheduleFocusBlockFor(const QString& taskId) {
  const int row = m_tasks.indexOfId(taskId);
  if(row < 0) {
    return;
  }
  const Task& t = m_tasks.items().at(row);
  const QVariantMap s = settingsMap();
  const QVariantMap cal = s.value("calendar").toMap();
  const int durMin = cal.value("focusBlockDuration", 90).toInt();
  const double dur = std::max(0.25, durMin / 60.0);
  const QDateTime now = QDateTime::currentDateTime();
  const double start = nextQuarterHour(now);
  if(start >= 24.0) {
    return;  // No room left in today.
  }
  const double end = std::min(24.0, start + dur);
  CalEvent e;
  e.id = QStringLiteral("ev-") + QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
  e.title = QStringLiteral("Focus: %1").arg(t.title);
  e.type = QStringLiteral("focus");
  e.start = start;
  e.end = end;
  e.date = now.date();
  e.taskId = taskId;
  e.profileId = m_activeProfileId;
  m_events.upsert(e);
  scheduleSave();
}

void AppController::runAutomation() {
  const QDateTime now = QDateTime::currentDateTime();
  const QDate today = now.date();
  const QVariantMap s = settingsMap();
  const QVariantMap tasksCfg = s.value("tasks").toMap();
  const QVariantMap notif = s.value("notifications").toMap();

  // 1. Re-compute blocked-stuck (status=blocked older than threshold).
  const int stuckDays = qMax(0, tasksCfg.value("autoMoveBlockedAfterDays", 3).toInt());
  QSet<QString> stuck;
  for(const Task& t : m_tasks.items()) {
    if(t.archived) {
      continue;
    }
    if(t.status != QStringLiteral("blocked")) {
      continue;
    }
    if(!t.statusChangedAt.isValid()) {
      continue;
    }
    if(t.statusChangedAt.daysTo(now) >= stuckDays) {
      stuck.insert(t.id);
    }
  }
  if(stuck != m_blockedStuckIds) {
    m_blockedStuckIds = stuck;
    m_tasks.setBlockedStuckIds(m_blockedStuckIds);
    emit blockedStuckChanged();
  }

  // 1b. Daily digest of blocked-stuck tasks — one notification per day.
  if(notif.value("blockedDailyDigest", false).toBool() && !m_blockedStuckIds.isEmpty()) {
    const QString sentinel = QStringLiteral("digest:") + today.toString(Qt::ISODate);
    if(m_lastReminderDay.value(sentinel) != today) {
      m_lastReminderDay[sentinel] = today;
      QStringList ids;
      ids.reserve(m_blockedStuckIds.size());
      for(const QString& id : m_blockedStuckIds) {
        ids << id;
      }
      std::sort(ids.begin(), ids.end());
      const QString body = QStringLiteral("Stuck: %1").arg(ids.join(QStringLiteral(", ")));
      notify(QStringLiteral("Blocked daily digest (%1)").arg(ids.size()), body, QStringLiteral("digest"));
    }
  }

  // 2. Auto-archive done tasks past retention.
  const int archDays = qMax(0, tasksCfg.value("archiveDoneAfterDays", 7).toInt());
  bool persistedAny = false;
  if(archDays > 0) {
    QStringList toArchive;
    for(const Task& t : m_tasks.items()) {
      if(t.archived) {
        continue;
      }
      if(t.status != QStringLiteral("done")) {
        continue;
      }
      if(!t.statusChangedAt.isValid()) {
        continue;
      }
      if(t.statusChangedAt.daysTo(now) >= archDays) {
        toArchive << t.id;
      }
    }
    for(const QString& id : toArchive) {
      m_tasks.setArchived(id, true);
      persistedAny = true;
    }
  }
  if(persistedAny) {
    scheduleSave();
  }

  // 3. Deadline reminders — at most one per task per day.
  if(notif.value("deadlineReminders", true).toBool()) {
    const int leadHours = qMax(1, notif.value("deadlineLeadHours", 24).toInt());
    for(const Task& t : m_tasks.items()) {
      if(t.archived) {
        continue;
      }
      if(!t.deadline.isValid()) {
        continue;
      }
      if(t.status == QStringLiteral("done")) {
        continue;
      }
      const QDateTime deadlineAt(t.deadline, QTime(23, 59));
      const qint64 hoursLeft = now.secsTo(deadlineAt) / 3600;
      if(hoursLeft < 0 || hoursLeft > leadHours) {
        continue;
      }
      const QString sentinel = QStringLiteral("dl:") + t.id;
      if(m_lastReminderDay.value(sentinel) == today) {
        continue;
      }
      m_lastReminderDay[sentinel] = today;
      const QString when = (hoursLeft <= 1) ? tr_("notify.deadlineWhen.h1") : tr_("notify.deadlineWhen.hN").arg(hoursLeft);
      notifyTask(
          t.id, tr_("notify.deadlineTitle").arg(when), QStringLiteral("%1 (%2)").arg(t.title, t.priority), QStringLiteral("deadline"));
    }
  }

  // 4. Standup reminder.
  if(notif.value("standupReminder", true).toBool()) {
    const QVariantMap cal = s.value("calendar").toMap();
    const QTime standup = QTime::fromString(cal.value("standupTime", "10:00").toString(), "HH:mm");
    const int lead = qMax(0, notif.value("meetingLead", 5).toInt());
    if(standup.isValid()) {
      const QDateTime atDt(today, standup);
      const qint64 minsLeft = now.secsTo(atDt) / 60;
      if(minsLeft >= 0 && minsLeft <= lead) {
        const QString sentinel = QStringLiteral("standup:%1").arg(today.toString(Qt::ISODate));
        if(m_lastReminderDay.value(sentinel) != today) {
          m_lastReminderDay[sentinel] = today;
          notify(tr_("notify.standupTitle"), tr_("notify.standupBody").arg(minsLeft), QStringLiteral("standup"));
        }
      }
    }
  }
}

// ---- Git watcher integration ----

QStringList AppController::collectPrefixes() const {
  const QString def = settingsMap().value("tasks").toMap().value("idPrefix", QStringLiteral("LTE")).toString().trimmed().toUpper();
  return def.isEmpty() ? QStringList{} : QStringList{def};
}

void AppController::applyGitSettingsFromMap(const QVariantMap& g) {
  if(!m_gitWatcher) {
    return;
  }
  QStringList repos;
  const QVariantList raw = g.value("watchedRepos").toList();
  for(const QVariant& v : raw) {
    const QString p = v.toString().trimmed();
    if(!p.isEmpty()) {
      repos << p;
    }
  }
  m_gitWatcher->setPrefixes(collectPrefixes());
  m_gitWatcher->setWatchedRepos(repos);
  m_gitWatcher->setPrFetchEnabled(g.value("watchPrState", true).toBool());
}

void AppController::onGitBranchChanged(const QString& repo, const QString& branch, const QString& taskId) {
  m_focusedRepo = repo;
  m_focusedBranch = branch;
  m_focusedTaskId = taskId;
  if(m_gitWatcher) {
    m_focusedRepoState = m_gitWatcher->snapshot().value(repo).toMap();
  }
  m_dismissedBranches.remove(branch);  // re-arm banner on every branch change
  emit focusedGitChanged();

  if(taskId.isEmpty() || branch == QStringLiteral("(detached HEAD)")) {
    return;
  }
  const QVariantMap g = settingsMap().value("git").toMap();
  const int row = m_tasks.indexOfId(taskId);
  if(row < 0) {
    return;
  }

  if(g.value("autoMoveToInProgress", true).toBool() && m_tasks.items().at(row).status != QStringLiteral("prog")) {
    moveTask(taskId, QStringLiteral("prog"));
  }
  if(g.value("autoCreateFocusBlock", false).toBool()) {
    scheduleFocusBlockFor(taskId);
  }
  emit notification(QStringLiteral("Working on ") + taskId, QStringLiteral("Branch ") + branch, QStringLiteral("git"));
}

void AppController::onGitRepoState(const QString& repo, const QVariantMap& state) {
  if(repo == m_focusedRepo) {
    m_focusedRepoState = state;
    emit focusedGitChanged();
  }
  const heap::git::BranchTaskMatcher m(collectPrefixes());
  const auto mr = m.extract(state.value("branch").toString());
  if(!mr.matched) {
    return;
  }
  const QVariantMap pr = state.value("pr").toMap();
  QVariantMap entry;
  entry["ahead"] = state.value("ahead");
  entry["behind"] = state.value("behind");
  entry["prState"] = pr.value("state");
  entry["prNumber"] = pr.value("number");
  entry["prUrl"] = pr.value("url");
  m_tasks.setGitInfoForId(mr.taskId, entry);
}

void AppController::dismissGitBanner() {
  if(m_focusedBranch.isEmpty()) {
    return;
  }
  m_dismissedBranches.insert(m_focusedBranch);
  emit focusedGitChanged();
}

void AppController::openFocusedTask() {
  if(!m_focusedTaskId.isEmpty()) {
    emit openTaskRequested(m_focusedTaskId);
  }
}

void AppController::refreshGitForTaskBranch(const QString& taskId) {
  if(!m_gitWatcher) {
    return;
  }
  const int row = m_tasks.indexOfId(taskId);
  if(row < 0) {
    return;
  }
  const QString br = m_tasks.items().at(row).branch;
  if(br.isEmpty()) {
    return;
  }
  const QStringList repos = m_gitWatcher->snapshot().keys();
  for(const QString& repo : repos) {
    m_gitWatcher->requestPrFetch(repo, br);
  }
}

// ── Native notifications with action buttons ─────────────────────

void AppController::notifyTask(const QString& taskId, const QString& title, const QString& body, const QString& kind) {
  if(inQuietHours(QDateTime::currentDateTime())) {
    return;
  }
  const QVariantMap notif = settingsMap().value("notifications").toMap();
  if(!notif.value("desktopNotif", true).toBool() || !m_notifier) {
    // Fallback path — still surface via in-app toast for visibility.
    emit toast(body);
    return;
  }

  heap::notify::Notification n;
  // The id encodes both kind and task id so the action handler can route
  // back without bookkeeping ("deadline:LTE-2398" → kind=deadline, task=LTE-2398).
  n.id = heap::notify::routingId(kind, taskId);
  n.title = title;
  n.body = body;
  n.iconPath = QStringLiteral(":/brand/icon/heap-icon.svg");
  n.category = kind;

  if(m_notifier->supportsActions()) {
    n.actions = {{QStringLiteral("snooze1h"), QStringLiteral("Snooze 1h")},
                 {QStringLiteral("done"), QStringLiteral("Mark done")},
                 {QStringLiteral("open"), QStringLiteral("Open")}};
  }
  m_notifier->post(n);

  if(notif.value("soundOnPing", false).toBool()) {
    QApplication::beep();
  }
  emit toast(body);
}

void AppController::snoozeDeadline(const QString& taskId, int seconds) {
  const int row = m_tasks.indexOfId(taskId);
  if(row < 0) {
    return;
  }
  Task t = m_tasks.items().at(row);
  if(!t.deadline.isValid()) {
    return;
  }
  // Reminders are date-grained — bump to the next day so the dl: sentinel
  // for "today" stops firing.
  t.deadline = t.deadline.addDays((seconds + 86399) / 86400);
  m_tasks.upsert(t);
  // Forget the "already notified today" memo so the new horizon is honoured.
  m_lastReminderDay.remove(QStringLiteral("dl:") + taskId);
  emit toast(tr_("deadline.snoozed").arg(taskId));
  scheduleSave();
}

void AppController::onNotifierAction(const QString& notificationId, const QString& actionId) {
  const auto [kind, taskId] = heap::notify::parseRoutingId(notificationId);
  Q_UNUSED(kind);
  if(taskId.isEmpty()) {
    return;
  }

  if(actionId == QStringLiteral("snooze1h")) {
    snoozeDeadline(taskId, 3600);
  } else if(actionId == QStringLiteral("done")) {
    if(m_tasks.indexOfId(taskId) >= 0) {
      moveTask(taskId, QStringLiteral("done"));
    }
  } else if(actionId == QStringLiteral("open")) {
    if(m_tasks.indexOfId(taskId) >= 0) {
      emit openTaskRequested(taskId);
    }
  }
}

void AppController::onNotifierActivated(const QString& notificationId) {
  const auto [kind, taskId] = heap::notify::parseRoutingId(notificationId);
  Q_UNUSED(kind);
  if(!taskId.isEmpty() && m_tasks.indexOfId(taskId) >= 0) {
    emit openTaskRequested(taskId);
  }
}
