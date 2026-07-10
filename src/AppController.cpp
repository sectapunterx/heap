#include "AppController.h"
#include "Logger.h"
#include "RecoveryLog.h"
#include "SampleData.h"
#include "StateSerializer.h"
#include "TaskDefer.h"

#include "chrono/ChronoParser.h"
#include "git/BranchTaskMatcher.h"
#include "git/GitWatcher.h"
#include "integrations/OAuthManager.h"
#include "integrations/ProviderDescriptor.h"
#include "integrations/ProviderRegistry.h"
#include "integrations/RestIssueProvider.h"
#include "integrations/SecretStore.h"
#include "integrations/StatusMap.h"
#include "notes/NoteLinks.h"
#include "notify/NotificationCenter.h"
#include "platform/GlobalHotkey.h"
#include "recur/RecurrenceEngine.h"
#include "text/TaskTextUtils.h"
#include "update/Updater.h"

#include <QApplication>
#include <QClipboard>
#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QDesktopServices>
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
#include <QPair>
#include <QSaveFile>
#include <QStandardPaths>
#include <QSysInfo>
#include <QSystemTrayIcon>
#include <QTime>
#include <QUrl>
#include <QUrlQuery>
#include <QUuid>

#include <algorithm>
#include <cmath>

// Version is injected by CMake (PROJECT_VERSION); this fallback keeps standalone
// test targets that compile AppController.cpp directly building without it.
#ifndef HEAP_VERSION
#define HEAP_VERSION "0.0.0-dev"
#endif

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
      {"task.moved", {"%1 → %2", "%1 → %2"}},
      {"task.moveUndone", {"Move undone: %1", "Перемещение отменено: %1"}},
      {"task.archived", {"Archived: %1", "В архиве: %1"}},
      {"task.unarchived", {"Unarchived: %1", "Из архива: %1"}},
      {"task.archiveUndone", {"Restored: %1", "Восстановлено: %1"}},
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
      {"profile.mdCopied", {"Profile Markdown copied to clipboard", "Markdown профиля скопирован в буфер"}},
      {"profile.weeklyCopied", {"Weekly report copied to clipboard", "Недельный отчёт скопирован в буфер"}},
      {"profile.imported", {"Profile imported: %1", "Импортирован профиль: %1"}},
      {"tasks.renamed", {"Tasks renamed: %1", "Переименовано задач: %1"}},
      {"backup.restored", {"Restored from %1", "Восстановлено из %1"}},
      {"data.recovered",
       {"Your data file was unreadable — recovered from backup %1", "Файл данных был нечитаем — восстановлено из бэкапа %1"}},
      {"data.corruptKept",
       {"Your data file was unreadable and no backup was found. The damaged file was "
        "kept as state.corrupt-*.json.",
        "Файл данных был нечитаем, бэкап не найден. Повреждённый файл сохранён как "
        "state.corrupt-*.json."}},
      {"hotkeys.reset", {"Hotkeys reset to defaults", "Хоткеи сброшены к дефолту"}},
      {"onboarding.startedFresh", {"Demo cleared — your workspace is empty", "Демо очищено — рабочее пространство пустое"}},
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
      {"shortcut.profile.weeklyReport.label", {"Weekly shipped report", "Недельный отчёт"}},
      {"shortcut.profile.weeklyReport.desc",
       {"Copies a Markdown report of tasks marked done in the last 7 days, with tracked time.",
        "Копирует Markdown-отчёт задач, завершённых за последние 7 дней, с учётом времени."}},
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
      {"shortcut.view.archive.label", {"Go to Archive", "Перейти в Архив"}},
      {"shortcut.view.archive.desc", {"Archived tickets of the active profile.", "Архивные тикеты активного профиля."}},
      {"shortcut.theme.toggle.label", {"Toggle light / dark", "Переключить светлую/тёмную"}},
      {"shortcut.theme.toggle.desc", {"Flip the app theme between dark and light.", "Переключить тему приложения между тёмной и светлой."}},
      {"shortcut.person.new.label", {"New contact", "Новый контакт"}},
      {"shortcut.person.new.desc", {"Add a person to the active profile.", "Добавить человека в активный профиль."}},
      {"shortcut.profile.new.label", {"New profile", "Новый профиль"}},
      {"shortcut.profile.new.desc", {"Create a new profile.", "Создать новый профиль."}},
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
  connect(m_notifier.get(), &heap::notify::NotificationCenter::showWindowRequested, this, &AppController::showWindowRequested);
  connect(m_notifier.get(), &heap::notify::NotificationCenter::quitRequested, this, []() {
    QCoreApplication::quit();
  });

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
    // Only raise an OS toast when the window is NOT focused. When the app is
    // active the in-app Toast bar (emitted below) already surfaces the message;
    // showing both is the "notification appears twice on Windows" bug (HEAP-47)
    // — one styled in-app toast plus one plain system balloon.
    const bool appActive = QGuiApplication::applicationState() == Qt::ApplicationActive;
    if(notif.value("desktopNotif", true).toBool() && m_notifier && !appActive) {
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

  // If loadStateOnStart() had to recover from a backup or quarantine a corrupt
  // file, surface it once the QML toast bar exists (singleShot fires after the
  // engine has loaded Main.qml and this event loop starts).
  if(!m_recoveryNotice.isEmpty()) {
    QTimer::singleShot(0, this, [this]() {
      emit toast(m_recoveryNotice);
      m_recoveryNotice.clear();
    });
  }

  // ---- Git watcher ----
  m_gitWatcher = std::make_unique<heap::git::GitWatcher>(this);
  connect(m_gitWatcher.get(), &heap::git::GitWatcher::branchChanged, this, &AppController::onGitBranchChanged);
  connect(m_gitWatcher.get(), &heap::git::GitWatcher::repoStateUpdated, this, &AppController::onGitRepoState);
  connect(m_gitWatcher.get(), &heap::git::GitWatcher::commitsUpdated, this, &AppController::onGitCommits);
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

  // ---- Auto-update (HEAP-63) ----
  m_updater = std::make_unique<heap::update::Updater>(appVersion(), this);
  connect(m_updater.get(), &heap::update::Updater::updateAvailable, this, [this](const QString& version, const QString& url) {
    m_latestReleaseUrl = url;
    m_updateStatus = tr("Update available: %1").arg(version);
    emit updateStatusChanged();
    emit updateAvailable(version, url);
  });
  connect(m_updater.get(), &heap::update::Updater::upToDate, this, [this](const QString&) {
    m_updateStatus = tr("You're up to date");
    emit updateStatusChanged();
  });
  connect(m_updater.get(), &heap::update::Updater::checkFailed, this, [this](const QString& error) {
    qWarning() << "update check failed:" << error;
    m_updateStatus = tr("Update check failed");
    emit updateStatusChanged();
  });
  // Opt-out background check shortly after startup (never auto-downloads). The
  // delay lets settings load and the QML toast bar come up first.
  QTimer::singleShot(3000, this, [this]() {
    if(settingsMap().value("updates").toMap().value("autoCheck", true).toBool()) {
      checkForUpdates();
    }
  });

  // ---- Tracker sync (HEAP-74/75) ----
  m_secretStore = new heap::integrations::SecretStore(this);
  m_syncTimer = new QTimer(this);
  m_syncTimer->setSingleShot(false);
  connect(m_syncTimer, &QTimer::timeout, this, &AppController::syncNow);
  // Move any legacy plaintext tokens out of state.json, then load the keychain.
  migrateLegacySecrets();
  QVector<QPair<QString, QString>> secretKeys;
  for(const heap::integrations::ProviderDescriptor& d : heap::integrations::providerCatalog()) {
    for(const QString& f : d.secretKeys) {
      secretKeys.append({d.id, f});
    }
  }
  // Providers that need a secret build after the async keychain read completes.
  m_secretStore->load(secretKeys, [this]() {
    applyIntegrationSettings();
  });
  applyIntegrationSettings();
  connect(this, &AppController::appSettingsJsonChanged, this, [this]() {
    applyIntegrationSettings();
  });
  connect(this, &AppController::activeProfileChanged, this, [this]() {
    if(m_gitWatcher) {
      m_gitWatcher->setPrefixes(collectPrefixes());
      refreshFocusedTaskId();
    }
  });

  // Fresh install or unreadable state — seed a single "Example" profile
  // from SampleData so the app boots with something sensible.
  if(m_profiles.isEmpty()) {
    seedExampleProfile();
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

void AppController::focusStatusColumn(const QString& statusId) {
  // Sidebar Blocked / Code Review entry point: make sure the Board is the
  // active view, then flag the target status column so KanbanBoard can scroll
  // to and briefly highlight it. focusedStatus is transient UI state (not
  // persisted). Emitted unconditionally so a repeat click re-triggers the
  // scroll/pulse even when the same column is already focused.
  setCurrentView(QStringLiteral("board"));
  m_focusedStatus = statusId;
  emit focusedStatusChanged();
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

QStringList AppController::noteHeadings(const QString& markdown) const {
  return heap::notes::collectHeadings(markdown);
}

QVariantList AppController::noteBacklinks(const QString& markdown) const {
  return heap::notes::collectBacklinks(markdown);
}

int AppController::noteHeadingOffset(const QString& markdown, const QString& heading) const {
  return heap::notes::headingOffset(markdown, heading);
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
  const QString prevStatus = t.status;
  // Capture before any upsert can invalidate the `t` reference (HEAP-77).
  const QString recurrence = t.recurrence;
  const QDate recurBase = t.dueAt.isValid() ? t.dueAt.date() : t.scheduledAt.date();
  m_tasks.setStatus(id, newStatus);

  // Mirror the change back to the linked tracker issue (e.g. moving to Done
  // closes the GitHub issue / transitions the Jira issue). Routed to whichever
  // provider owns the task. No-op for locally-created, unlinked tasks.
  if(!t.externalId.isEmpty() && !t.externalProvider.isEmpty()) {
    for(const auto& provider : m_syncProviders) {
      if(provider->id() == t.externalProvider) {
        provider->pushStatusChange(t.externalId, newStatus);
        break;
      }
    }
  }

  // Arm undo so a mis-drag to the wrong column is reversible (previously
  // moveTask had no undo at all).
  cancelUndo();
  m_pendingUndo = {};
  m_pendingUndo.kind = PendingUndo::TaskMove;
  m_pendingUndo.taskId = taskId;
  m_pendingUndo.prevStatus = prevStatus;
  armUndo(5);

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

  // Recurring task completed → spawn the next occurrence (HEAP-77).
  if(newStatus == QStringLiteral("done") && !recurrence.isEmpty()) {
    const QDate base = recurBase.isValid() ? recurBase : QDate::currentDate();
    const QDate next = heap::recur::nextOccurrence(recurrence, base);
    const int srcRow = m_tasks.indexOfId(taskId);
    if(next.isValid() && srcRow >= 0) {
      Task copy = m_tasks.items().at(srcRow);  // clone title/desc/priority/branch
      // Fresh unique id (strip any prior "-rN" suffix) so upsert inserts a new
      // row rather than overwriting the just-completed one.
      QString stem = taskId;
      static const QRegularExpression kRSuffix(QStringLiteral("-r\\d+$"));
      stem.remove(kRSuffix);
      QString newId;
      int n = 1;
      do {
        newId = stem + QStringLiteral("-r") + QString::number(n++);
      } while(m_tasks.indexOfId(newId) >= 0);
      copy.id = newId;
      copy.status = QStringLiteral("todo");
      // Roll each datetime onto the next occurrence, keeping the clock time the
      // user set (a 09:00 standup recurs at 09:00, not at midnight). A field the
      // task never carried stays invalid — rebuilding it would manufacture a
      // phantom midnight deadline/schedule and fire spurious reminders.
      if(copy.dueAt.isValid()) {
        copy.dueAt = QDateTime(next, copy.dueAt.time());
      }
      if(copy.scheduledAt.isValid()) {
        copy.scheduledAt = QDateTime(next, copy.scheduledAt.time());
      }
      copy.statusChangedAt = QDateTime::currentDateTime();
      copy.trackedSeconds = 0;
      copy.timerStartedAt = QDateTime();
      copy.recurrence = recurrence;  // stays recurring
      copy.externalId.clear();       // a new local occurrence, not the synced issue
      copy.externalUrl.clear();
      copy.externalProvider.clear();
      m_tasks.upsert(copy);
      emit toast(tr("Recurs: %1 due %2").arg(newId, next.toString(Qt::ISODate)));
    }
  }

  emit undoableToast(tr_("task.moved").arg(taskId, statusName), 5);
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
  m["scheduledAt"] = QDateTime();
  m["dueAt"] = QDateTime();
  m["hasTime"] = false;
  m["branch"] = QString();
  m["labels"] = QVariantList();
  m["estimateMinutes"] = 0;
  m["someday"] = false;
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

namespace {
// Built-in task/checklist templates (HEAP-77). Checklists are markdown
// `- [ ]` lines in the description — they render as checkboxes in the notes
// preview and stay plain, editable text everywhere else.
struct TaskTemplate {
  QString name;
  QString title;
  QString desc;
  QString priority;
};

const QVector<TaskTemplate>& builtinTemplates() {
  static const QVector<TaskTemplate> kTemplates = {
      {QStringLiteral("PR review"),
       QStringLiteral("Review PR: "),
       QStringLiteral("- [ ] Pull the branch and build\n- [ ] Tests pass locally\n- [ ] Logic + edge cases\n- [ ] Naming / style\n- [ ] "
                      "No leftover debug code\n- [ ] Approve or request changes"),
       QStringLiteral("P2")},
      {QStringLiteral("Release checklist"),
       QStringLiteral("Release "),
       QStringLiteral("- [ ] Version bumped\n- [ ] Changelog updated\n- [ ] CI green on main\n- [ ] Tag pushed\n- [ ] Artifacts signed\n- "
                      "[ ] Release notes published\n- [ ] Announce"),
       QStringLiteral("P1")},
      {QStringLiteral("Bug report"),
       QStringLiteral("Bug: "),
       QStringLiteral(
           "**Steps to reproduce:**\n1. \n\n**Expected:**\n\n**Actual:**\n\n- [ ] Repro confirmed\n- [ ] Root cause\n- [ ] Fix + "
           "test"),
       QStringLiteral("P1")},
  };
  return kTemplates;
}
}  // namespace

QVariantList AppController::taskTemplates() const {
  QVariantList out;
  for(const auto& t : builtinTemplates()) {
    QVariantMap m;
    m["name"] = t.name;
    m["title"] = t.title;
    m["desc"] = t.desc;
    out.append(m);
  }
  return out;
}

void AppController::createTaskFromTemplate(const QString& name) {
  const auto& templates = builtinTemplates();
  const auto it = std::find_if(templates.cbegin(), templates.cend(), [&](const TaskTemplate& t) {
    return t.name == name;
  });
  if(it == templates.cend()) {
    return;
  }
  const QVariantMap draft = newTaskDraft(QStringLiteral("todo"));
  Task t;
  t.id = draft.value("id").toString();
  t.title = it->title;
  t.desc = it->desc;
  t.priority = it->priority;
  t.status = QStringLiteral("todo");
  t.statusChangedAt = QDateTime::currentDateTime();
  m_tasks.upsert(t);
  scheduleSave();
  emit toast(tr("Created from template: %1").arg(it->name));
  emit openTaskRequested(t.id);  // open the editor so the user fills in the blank
}

void AppController::saveTask(const QVariantMap& draft) {
  Task t;
  t.id = draft.value("id").toString().trimmed();
  t.title = draft.value("title").toString();
  t.desc = draft.value("desc").toString();
  t.priority = draft.value("priority").toString();
  t.status = draft.value("status").toString();
  t.branch = draft.value("branch").toString();
  t.recurrence = draft.value("recurrence").toString();
  // Scheduling (HEAP-115). The editors hand over full datetimes and say whether
  // the clock component is real; a caller that only knows a date may still send
  // the legacy `deadline` key, which lands at midnight on both fields.
  t.scheduledAt = draft.value("scheduledAt").toDateTime();
  t.dueAt = draft.value("dueAt").toDateTime();
  t.hasTime = draft.value("hasTime").toBool();
  if(!t.scheduledAt.isValid() && !t.dueAt.isValid() && draft.contains("deadline")) {
    const QDate legacy = draft.value("deadline").toDate();
    if(legacy.isValid()) {
      t.scheduledAt = QDateTime(legacy, QTime(0, 0));
      t.dueAt = t.scheduledAt;
      t.hasTime = false;
    }
  }
  t.estimateMinutes = draft.value("estimateMinutes").toInt();
  t.someday = draft.value("someday").toBool();
  t.labels = labelsFromVariant(draft.value("labels").toList());
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
      // The editor exposes neither the tracker link nor the timer — carry both.
      t.trackedSeconds = prev.trackedSeconds;
      t.timerStartedAt = prev.timerStartedAt;
      // Recurrence: honour the draft when it carries the key, else preserve.
      t.recurrence = draft.contains("recurrence") ? draft.value("recurrence").toString() : prev.recurrence;
      t.externalId = prev.externalId;
      t.externalUrl = prev.externalUrl;
      t.externalProvider = prev.externalProvider;
      // The editor never shows the tracker-supplied assignee, and the planning
      // fields are honoured only when the draft actually carries them.
      t.assignee = prev.assignee;
      if(!draft.contains("labels")) {
        t.labels = prev.labels;
      }
      if(!draft.contains("estimateMinutes")) {
        t.estimateMinutes = prev.estimateMinutes;
      }
      if(!draft.contains("someday")) {
        t.someday = prev.someday;
      }
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
  m["scheduledAt"] = t.scheduledAt;
  m["dueAt"] = t.dueAt;
  m["hasTime"] = t.hasTime;
  m["branch"] = t.branch;
  m["archived"] = t.archived;
  m["trackedSeconds"] = t.trackedSeconds;
  m["isTiming"] = t.timerStartedAt.isValid();
  m["recurrence"] = t.recurrence;
  m["labels"] = labelsToVariant(t.labels);
  m["estimateMinutes"] = t.estimateMinutes;
  m["someday"] = t.someday;
  m["assignee"] = t.assignee;
  m["externalKey"] = externalKeyOf(t);
  m["externalUrl"] = t.externalUrl;
  m["externalProvider"] = t.externalProvider;
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

void AppController::copyActiveProfileMarkdownToClipboard() {
  snapshotActiveProfile();  // flush live models into the active Profile first
  const int pi = profileIndexOf(m_activeProfileId);
  if(pi < 0) {
    return;
  }
  const Profile& p = m_profiles[pi];

  const auto renderTask = [](const Task& t) {
    QString line = QStringLiteral("- ");
    if(!t.priority.isEmpty()) {
      line += QStringLiteral("**[") + t.priority + QStringLiteral("]** ");
    }
    if(!t.id.isEmpty()) {
      line += QStringLiteral("`") + t.id + QStringLiteral("` ");
    }
    line += t.title;
    QStringList meta;
    if(t.dueAt.isValid()) {
      meta << QStringLiteral("deadline: ") + (t.hasTime ? t.dueAt.toString(Qt::ISODate) : t.dueAt.date().toString(Qt::ISODate));
    }
    if(!t.branch.isEmpty()) {
      meta << QStringLiteral("branch: ") + t.branch;
    }
    if(!meta.isEmpty()) {
      line += QStringLiteral("  — ") + meta.join(QStringLiteral(" · "));
    }
    return line;
  };

  QString md;
  md += QStringLiteral("# ") + p.name + QStringLiteral("\n\n");
  md += QStringLiteral("_Exported ") + QDate::currentDate().toString(Qt::ISODate) + QStringLiteral("_\n");

  // Tasks grouped by column, in the profile's status order; archived hidden.
  md += QStringLiteral("\n## Tasks\n");
  QSet<QString> knownStatus;
  for(const QVariant& sv : p.statuses) {
    const QVariantMap sm = sv.toMap();
    const QString sid = sm.value(QStringLiteral("id")).toString();
    knownStatus.insert(sid);
    QStringList lines;
    for(const Task& t : p.tasks) {
      if(!t.archived && t.status == sid) {
        lines << renderTask(t);
      }
    }
    if(lines.isEmpty()) {
      continue;
    }
    md += QStringLiteral("\n### ") + sm.value(QStringLiteral("name")).toString() + QStringLiteral(" (") + QString::number(lines.size()) +
          QStringLiteral(")\n");
    md += lines.join(QStringLiteral("\n")) + QStringLiteral("\n");
  }
  // Tasks whose status is not one of the profile's columns.
  QStringList orphan;
  for(const Task& t : p.tasks) {
    if(!t.archived && !knownStatus.contains(t.status)) {
      orphan << renderTask(t);
    }
  }
  if(!orphan.isEmpty()) {
    md += QStringLiteral("\n### Other (") + QString::number(orphan.size()) + QStringLiteral(")\n");
    md += orphan.join(QStringLiteral("\n")) + QStringLiteral("\n");
  }

  // People.
  if(!p.people.isEmpty()) {
    md += QStringLiteral("\n## People\n");
    for(const Person& pe : p.people) {
      QString line = QStringLiteral("- **") + pe.name + QStringLiteral("**");
      QStringList meta;
      if(!pe.role.isEmpty()) {
        meta << pe.role;
      }
      if(!pe.question.isEmpty()) {
        meta << QStringLiteral("Q: ") + pe.question;
      }
      if(!meta.isEmpty()) {
        line += QStringLiteral(" — ") + meta.join(QStringLiteral(" · "));
      }
      md += line + QStringLiteral("\n");
    }
  }

  // Notes (raw markdown of the active profile).
  const QString notes = p.notesState.trimmed();
  if(!notes.isEmpty()) {
    md += QStringLiteral("\n## Notes\n\n") + notes + QStringLiteral("\n");
  }

  copyToClipboard(md);
  emit toast(tr_("profile.mdCopied"));
}

namespace {
QString formatTrackedDuration(int secs) {
  const int h = secs / 3600;
  const int m = (secs % 3600) / 60;
  return h > 0 ? QStringLiteral("%1h %2m").arg(h).arg(m) : QStringLiteral("%1m").arg(m);
}
}  // namespace

void AppController::copyWeeklyReportToClipboard() {
  snapshotActiveProfile();
  const int pi = profileIndexOf(m_activeProfileId);
  if(pi < 0) {
    return;
  }
  const Profile& p = m_profiles[pi];
  const QDate since = QDate::currentDate().addDays(-7);

  QVector<const Task*> shipped;
  int totalSecs = 0;
  for(const Task& t : p.tasks) {
    if(t.status == QStringLiteral("done") && t.statusChangedAt.isValid() && t.statusChangedAt.date() >= since) {
      shipped.push_back(&t);
      totalSecs += t.trackedSeconds;
    }
  }

  QString md;
  md += QStringLiteral("# What I shipped — ") + p.name + QStringLiteral("\n\n");
  md += QStringLiteral("_") + since.toString(Qt::ISODate) + QStringLiteral(" → ") + QDate::currentDate().toString(Qt::ISODate) +
        QStringLiteral("_\n\n");
  if(shipped.isEmpty()) {
    md += QStringLiteral("_Nothing marked done in the last 7 days._\n");
  } else {
    md += QStringLiteral("**") + QString::number(shipped.size()) + QStringLiteral(" task(s) shipped");
    if(totalSecs > 0) {
      md += QStringLiteral(" · ") + formatTrackedDuration(totalSecs) + QStringLiteral(" tracked");
    }
    md += QStringLiteral("**\n\n");
    for(const Task* t : shipped) {
      QString line = QStringLiteral("- ");
      if(!t->id.isEmpty()) {
        line += QStringLiteral("`") + t->id + QStringLiteral("` ");
      }
      line += t->title;
      QStringList meta;
      meta << QStringLiteral("done ") + t->statusChangedAt.date().toString(Qt::ISODate);
      if(t->trackedSeconds > 0) {
        meta << formatTrackedDuration(t->trackedSeconds);
      }
      line += QStringLiteral("  — ") + meta.join(QStringLiteral(" · "));
      md += line + QStringLiteral("\n");
    }
  }

  copyToClipboard(md);
  emit toast(tr_("profile.weeklyCopied"));
}

void AppController::startTaskTimer(const QString& id) {
  if(m_tasks.indexOfId(id) < 0) {
    return;
  }
  m_tasks.startTiming(id);
  scheduleSave();
}

void AppController::stopTaskTimer(const QString& id) {
  if(m_tasks.indexOfId(id) < 0) {
    return;
  }
  m_tasks.stopTiming(id);
  scheduleSave();
}

int AppController::elapsedSecondsFor(const QString& id) const {
  const int row = m_tasks.indexOfId(id);
  if(row < 0) {
    return 0;
  }
  const Task& t = m_tasks.items().at(row);
  int secs = t.trackedSeconds;
  if(t.timerStartedAt.isValid()) {
    secs += static_cast<int>(t.timerStartedAt.secsTo(QDateTime::currentDateTime()));
  }
  return secs;
}

void AppController::markWelcomeSeen() {
  if(m_welcomeSeen) {
    return;
  }
  m_welcomeSeen = true;
  emit onboardingChanged();
  scheduleSave();
}

void AppController::dismissDemo() {
  if(!m_demoActive) {
    return;
  }
  m_demoActive = false;
  emit onboardingChanged();
  scheduleSave();
}

void AppController::replayWelcome() {
  // UI-only request: ask Main.qml to re-open the welcome guide. Deliberately
  // leaves m_welcomeSeen / m_demoActive untouched so replaying the tour never
  // resurrects the demo banner or changes what persists.
  emit welcomeReplayRequested();
}

void AppController::seedExampleProfile() {
  // Seed a single "Example" profile from SampleData + turn on the first-run
  // onboarding. Called on a genuine fresh install and by resetToFirstRun().
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

  // Fresh install: show the welcome dialog and flag the seeded demo so the
  // board can offer "start fresh". (welcomeSeen stays false from its default.)
  m_demoActive = true;
  emit onboardingChanged();
  scheduleSave();
}

void AppController::resetToFirstRun() {
  // Destructive: erase every trace of user data — on disk and in memory — and
  // re-seed the app exactly as a fresh install (Example profile + onboarding).
  // m_loading gates the debounced writer so nothing persists a half-torn state
  // while we tear it down.
  m_loading = true;

  // 1. Remove persisted state so a crash mid-reset can't half-recover and the
  //    next launch sees a genuine first run. Backups + quarantined corrupt
  //    snapshots must go too, or loadStateOnStart would resurrect old data.
  QFile::remove(stateFilePath());
  QDir(backupDirPath()).removeRecursively();
  {
    const QDir dir(dataDir());
    const QStringList corrupt = dir.entryList(QStringList{"state.corrupt-*.json"}, QDir::Files);
    for(const QString& f : corrupt) {
      QFile::remove(dir.filePath(f));
    }
  }

  // 2. Drop transient UI state that points at rows we're about to delete.
  if(m_undoTimer) {
    m_undoTimer->stop();
  }
  m_pendingUndo = PendingUndo{};
  emit pendingUndoChanged();
  clearSelection();
  m_focusedStatus.clear();
  emit focusedStatusChanged();

  // 3. Reset preferences to their defaults. Language is preserved so the
  //    reseeded demo + UI stay in the user's tongue.
  m_theme = "dark";
  m_density = "comfy";
  m_currentView = "board";
  m_workdayStart = 9;
  m_workdayEnd = 19;
  m_crumbProject = "eNB-core";
  m_crumbUser = "You";
  m_selectedDate = m_today;
  m_appSettingsJson.clear();
  resetAllShortcuts();
  emit themeChanged();
  emit densityChanged();
  emit currentViewChanged();
  emit workdayChanged();
  emit crumbProjectChanged();
  emit crumbUserChanged();
  emit selectedDateChanged();
  emit appSettingsJsonChanged();

  // 4. Clear every profile + model, then re-seed like a fresh install.
  m_profiles.clear();
  m_activeProfileId.clear();
  m_events.reset({});
  m_tasks.reset({});
  m_people.reset({});
  m_notesState.clear();
  emit notesStateChanged();
  m_docsState.clear();
  emit docsStateChanged();

  m_welcomeSeen = false;
  m_demoActive = false;  // seedExampleProfile flips this back on
  seedExampleProfile();

  // 5. Persist the fresh state immediately and let the UI re-onboard.
  m_loading = false;
  saveStateNow();
  emit firstRunReset();
}

void AppController::startFresh() {
  // Wipe the active profile's seeded demo content, leaving an empty but usable
  // workspace: keep the profile and its kanban columns, drop tasks / people /
  // this profile's events / notes / docs.
  m_tasks.reset({});
  m_people.reset({});

  QVector<CalEvent> kept;
  for(const CalEvent& e : m_events.items()) {
    if(e.profileId != m_activeProfileId) {
      kept.append(e);
    }
  }
  m_events.reset(kept);

  m_notesState.clear();
  emit notesStateChanged();
  m_docsState.clear();
  emit docsStateChanged();

  m_demoActive = false;
  emit onboardingChanged();

  snapshotActiveProfile();
  scheduleSave();
  emit toast(tr_("onboarding.startedFresh"));
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
    case PendingUndo::TaskMove: {
      if(m_tasks.indexOfId(m_pendingUndo.taskId) >= 0) {
        m_tasks.setStatus(m_pendingUndo.taskId, m_pendingUndo.prevStatus);
        emit toast(tr_("task.moveUndone").arg(m_pendingUndo.taskId));
      }
      break;
    }
    case PendingUndo::TaskArchive: {
      if(m_tasks.indexOfId(m_pendingUndo.taskId) >= 0) {
        m_tasks.setArchived(m_pendingUndo.taskId, m_pendingUndo.prevArchived);
        emit toast(tr_("task.archiveUndone").arg(m_pendingUndo.taskId));
      }
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

QString AppController::dataDir() const {
  return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
}

QString AppController::qtVersion() const {
  return QString::fromLatin1(qVersion());
}

QString AppController::appVersion() const {
  return QString::fromLatin1(HEAP_VERSION);
}

void AppController::openLogsFolder() const {
  QDesktopServices::openUrl(QUrl::fromLocalFile(heap::logging::logDirPath()));
}

QString AppController::issueReportBody() const {
  QString body = QStringLiteral(
                     "<!-- Describe the problem above this line. The diagnostics below are "
                     "filled in automatically — please keep them. -->\n\n"
                     "---\n"
                     "**Diagnostics**\n"
                     "- heap version: %1\n"
                     "- OS: %2 (%3)\n"
                     "- Qt: %4\n\n"
                     "<details><summary>Recent log tail</summary>\n\n"
                     "```\n%5\n```\n</details>\n")
                     .arg(QCoreApplication::applicationVersion(),
                          QSysInfo::prettyProductName(),
                          QSysInfo::currentCpuArchitecture(),
                          QString::fromLatin1(qVersion()),
                          heap::logging::logTail());

  // Corruption recoveries are the failures nobody reports because nobody sees
  // them. Attach them to the report the user is already writing (HEAP-156).
  const QString recovery = heap::recovery::tail();
  if(!recovery.isEmpty()) {
    body += QStringLiteral("\n<details><summary>Recovery log</summary>\n\n```\n%1\n```\n</details>\n").arg(recovery);
  }
  return body;
}

QVariantList AppController::recoveryLog() const {
  return heap::recovery::entries();
}

bool AppController::exportRecoveryLog(const QUrl& fileUrl) {
  const QString path = fileUrl.isLocalFile() ? fileUrl.toLocalFile() : fileUrl.toString();
  const bool ok = heap::recovery::exportTo(path);
  emit toast(ok ? tr("Recovery log saved") : tr("No recovery log to export"));
  return ok;
}

void AppController::reportAnIssue() const {
  const QString body = issueReportBody();

  QUrl url(QStringLiteral("https://github.com/sectapunterx/heap/issues/new"));
  QUrlQuery query;
  query.addQueryItem(QStringLiteral("title"), QStringLiteral("[bug] "));
  query.addQueryItem(QStringLiteral("body"), body);
  url.setQuery(query);
  QDesktopServices::openUrl(url);
}

void AppController::checkForUpdates() {
  if(!m_updater || m_updater->isChecking()) {
    return;
  }
  m_updateStatus = tr("Checking for updates…");
  emit updateStatusChanged();
  m_updater->checkForUpdates();
}

void AppController::openLatestRelease() const {
  if(!m_latestReleaseUrl.isEmpty()) {
    QDesktopServices::openUrl(QUrl(m_latestReleaseUrl));
  }
}

void AppController::syncNow() {
  if(m_syncProviders.empty()) {
    emit toast(tr("Connect a tracker in Settings → Integrations first"));
    return;
  }
  emit toast(tr("Syncing…"));
  for(const auto& provider : m_syncProviders) {
    provider->pullTasks();
  }
}

void AppController::mergeExternalTasks(const QString& providerId,
                                       const QString& idPrefix,
                                       const QVector<heap::integrations::ExternalTask>& issues) {
  using heap::integrations::StatusMap;
  for(const heap::integrations::ExternalTask& ext : issues) {
    // Match an existing task by its stored external id; else create one.
    QString existingId;
    for(const Task& cur : m_tasks.items()) {
      if(cur.externalProvider == providerId && cur.externalId == ext.externalId) {
        existingId = cur.id;
        break;
      }
    }
    const int row = existingId.isEmpty() ? -1 : m_tasks.indexOfId(existingId);
    Task t;
    if(row >= 0) {
      t = m_tasks.items().at(row);
    } else {
      t.id = idPrefix + ext.externalId;
      t.statusChangedAt = QDateTime::currentDateTime();
    }
    t.title = ext.title;
    t.desc = ext.body;
    t.status = StatusMap::column(ext.status, {}, QStringLiteral("todo"));
    if(!ext.priority.isEmpty()) {
      t.priority = StatusMap::priority(ext.priority);
    } else if(t.priority.isEmpty()) {
      t.priority = QStringLiteral("P2");
    }
    t.externalId = ext.externalId;
    t.externalUrl = ext.url;
    t.externalProvider = providerId;
    // Pulled labels used to be parsed and thrown away (HEAP-124). Trackers hand
    // us names only (chip colour stays empty). Merge rather than clobber: a
    // label the user added locally and the tracker doesn't know must survive the
    // pull, and an existing chip keeps whatever colour it already had.
    QSet<QString> present;
    for(const Label& l : t.labels) {
      present.insert(l.id);
    }
    for(const QString& name : ext.labels) {
      if(!present.contains(name)) {
        t.labels.append(Label{name, {}});
        present.insert(name);
      }
    }
    m_tasks.upsert(t);
  }
  if(!issues.isEmpty()) {
    scheduleSave();
  }
}

void AppController::applyIntegrationSettings() {
  m_syncProviders.clear();
  const QVariantMap integrations = settingsMap().value("integrations").toMap();

  // Wire one provider's signals into the shared merge/push/toast handlers.
  const auto wire = [this](heap::integrations::IntegrationProvider* provider, const QString& idPrefix, const QString& label) {
    const QString providerId = provider->id();
    connect(provider,
            &heap::integrations::IntegrationProvider::tasksFetched,
            this,
            [this, providerId, idPrefix, label](const QVector<heap::integrations::ExternalTask>& issues) {
              mergeExternalTasks(providerId, idPrefix, issues);
              emit toast(tr("Synced %1 issue(s) from %2").arg(issues.size()).arg(label));
            });
    connect(provider,
            &heap::integrations::IntegrationProvider::taskPushed,
            this,
            [providerId](const QString& externalId, bool ok, const QString& error) {
              if(!ok) {
                qWarning() << providerId << "push failed for" << externalId << ":" << error;
              }
            });
    connect(provider, &heap::integrations::IntegrationProvider::connectionTested, this, [this, label](bool ok, const QString& error) {
      emit toast(ok ? tr("%1 connected").arg(label) : tr("%1 connection failed: %2").arg(label, error));
    });
  };

  // Build every connected + configured provider from the registry. Generic
  // trackers run on RestIssueProvider; the awkward few (Jira, Trello) are
  // bespoke. Adding a provider is a registry entry — no change here.
  for(const heap::integrations::ProviderDescriptor& d : heap::integrations::providerCatalog()) {
    const QVariantMap cfg = integrationConfig(d.id);
    if(!cfg.value(QStringLiteral("connected"), false).toBool()) {
      continue;
    }
    std::unique_ptr<heap::integrations::IntegrationProvider> provider;
    if(d.bespoke) {
      provider = heap::integrations::makeBespokeProvider(d.id, cfg, this);
    } else {
      auto rest = std::make_unique<heap::integrations::RestIssueProvider>(d, this);
      rest->setConfig(cfg);
      if(rest->isConfigured()) {
        provider = std::move(rest);
      }
    }
    if(provider) {
      wire(provider.get(), d.id + QStringLiteral("-"), d.displayName);
      m_syncProviders.push_back(std::move(provider));
    }
  }

  // Optional periodic auto-sync (integrations.autoSyncMinutes: 0 = off).
  const int mins = integrations.value(QStringLiteral("autoSyncMinutes")).toInt();
  if(m_syncTimer) {
    if(mins > 0 && !m_syncProviders.empty()) {
      m_syncTimer->start(mins * 60 * 1000);
    } else {
      m_syncTimer->stop();
    }
  }
}

QVariantMap AppController::integrationConfig(const QString& providerId) const {
  QVariantMap cfg = settingsMap().value("integrations").toMap().value(providerId).toMap();
  const heap::integrations::ProviderDescriptor* d = heap::integrations::findDescriptor(providerId);
  if(d && m_secretStore) {
    for(const QString& field : d->secretKeys) {
      cfg.insert(field, m_secretStore->value(providerId, field));
    }
  }
  return cfg;
}

void AppController::migrateLegacySecrets() {
  if(!m_secretStore) {
    return;
  }
  QVariantMap settings = settingsMap();
  QVariantMap integrations = settings.value("integrations").toMap();
  bool changed = false;
  for(const heap::integrations::ProviderDescriptor& d : heap::integrations::providerCatalog()) {
    if(!integrations.contains(d.id)) {
      continue;
    }
    QVariantMap cfg = integrations.value(d.id).toMap();
    for(const QString& field : d.secretKeys) {
      const QString existing = cfg.value(field).toString();
      if(!existing.isEmpty()) {
        m_secretStore->setValue(d.id, field, existing);
        cfg.remove(field);
        changed = true;
      }
    }
    integrations.insert(d.id, cfg);
  }
  if(changed) {
    settings.insert(QStringLiteral("integrations"), integrations);
    m_appSettingsJson = QJsonDocument(QJsonObject::fromVariantMap(settings)).toJson(QJsonDocument::Compact);
    emit appSettingsJsonChanged();
    scheduleSave();
  }
}

void AppController::syncProvider(const QString& providerId) {
  for(const auto& provider : m_syncProviders) {
    if(provider->id() == providerId) {
      emit toast(tr("Syncing…"));
      provider->pullTasks();
      return;
    }
  }
  emit toast(tr("Connect a tracker in Settings → Integrations first"));
}

void AppController::testIntegration(const QString& providerId) {
  const heap::integrations::ProviderDescriptor* d = heap::integrations::findDescriptor(providerId);
  if(!d) {
    emit toast(tr("Unknown integration"));
    return;
  }
  const QVariantMap cfg = integrationConfig(providerId);
  heap::integrations::IntegrationProvider* provider = nullptr;
  if(d->bespoke) {
    provider = heap::integrations::makeBespokeProvider(providerId, cfg, this).release();
  } else {
    auto* rest = new heap::integrations::RestIssueProvider(*d, this);
    rest->setConfig(cfg);
    provider = rest;
  }
  if(!provider) {
    emit toast(tr("%1 is not fully configured").arg(d->displayName));
    return;
  }
  const QString label = d->displayName;
  connect(
      provider, &heap::integrations::IntegrationProvider::connectionTested, this, [this, provider, label](bool ok, const QString& error) {
        emit toast(ok ? tr("%1 connected").arg(label) : tr("%1 connection failed: %2").arg(label, error));
        provider->deleteLater();
      });
  provider->testConnection();
}

QVariantList AppController::integrationCatalog() const {
  QVariantList out;
  for(const heap::integrations::ProviderDescriptor& d : heap::integrations::providerCatalog()) {
    QVariantMap m;
    m.insert(QStringLiteral("id"), d.id);
    m.insert(QStringLiteral("name"), d.displayName);
    m.insert(QStringLiteral("color"), d.color);
    m.insert(QStringLiteral("icon"), d.icon);
    m.insert(QStringLiteral("descKey"), d.descKey);
    m.insert(QStringLiteral("oauth"), d.oauth.supported);
    // oauthReady = a client ID is baked in, so "Connect with browser" is truly
    // one-click; otherwise the user must add one under Advanced first.
    m.insert(QStringLiteral("oauthReady"), d.oauth.supported && !d.oauth.clientId.isEmpty());
    QVariantList fields;
    for(const heap::integrations::FieldSpec& f : d.uiFields) {
      QVariantMap fm;
      fm.insert(QStringLiteral("key"), f.key);
      fm.insert(QStringLiteral("label"), f.label);
      fm.insert(QStringLiteral("placeholder"), f.placeholder);
      fm.insert(QStringLiteral("mono"), f.mono);
      fm.insert(QStringLiteral("secret"), f.secret);
      fields.append(fm);
    }
    m.insert(QStringLiteral("fields"), fields);
    out.append(m);
  }
  return out;
}

QString AppController::integrationSecret(const QString& providerId, const QString& field) const {
  return m_secretStore ? m_secretStore->value(providerId, field) : QString();
}

bool AppController::hasIntegrationSecret(const QString& providerId, const QString& field) const {
  return m_secretStore && m_secretStore->has(providerId, field);
}

void AppController::setIntegrationSecret(const QString& providerId, const QString& field, const QString& value) {
  if(m_secretStore) {
    m_secretStore->setValue(providerId, field, value);
  }
  applyIntegrationSettings();
}

void AppController::setIntegrationField(const QString& providerId, const QString& field, const QVariant& value) {
  QVariantMap settings = settingsMap();
  QVariantMap integrations = settings.value(QStringLiteral("integrations")).toMap();
  QVariantMap cfg = integrations.value(providerId).toMap();
  cfg.insert(field, value);
  integrations.insert(providerId, cfg);
  settings.insert(QStringLiteral("integrations"), integrations);
  m_appSettingsJson = QJsonDocument(QJsonObject::fromVariantMap(settings)).toJson(QJsonDocument::Compact);
  emit appSettingsJsonChanged();  // rebuilds providers + refreshes the QML settings copy
  scheduleSave();
}

void AppController::connectOAuth(const QString& providerId) {
  const heap::integrations::ProviderDescriptor* d = heap::integrations::findDescriptor(providerId);
  if(!d || !d->oauth.supported) {
    emit toast(tr("Browser sign-in is not available for this integration"));
    return;
  }
  const QVariantMap cfg = integrationConfig(providerId);
  // Prefer a user-entered client ID (self-hosted / Advanced), else the app's
  // baked-in registered client ID. Only if both are empty is there nothing to do.
  QString clientId = cfg.value(QStringLiteral("clientId")).toString().trimmed();
  if(clientId.isEmpty()) {
    clientId = d->oauth.clientId;
  }
  if(clientId.isEmpty()) {
    emit toast(tr("No OAuth app configured — add a client ID under Advanced first"));
    return;
  }
  QString clientSecret = cfg.value(QStringLiteral("clientSecret")).toString();
  if(clientSecret.isEmpty()) {
    clientSecret = d->oauth.clientSecret;
  }
  // {host} defaults to the descriptor fallback (e.g. gitlab.com) so gitlab.com
  // users never type a host; self-hosted users enter one under Advanced.
  QString host = cfg.value(QStringLiteral("host")).toString().trimmed();
  if(host.isEmpty()) {
    host = d->baseUrlFallback;
  }
  const QString base = cfg.value(QStringLiteral("baseUrl")).toString().trimmed();
  const auto expandHost = [host, base](QString url) {
    QString h = host;
    QString b = base;
    while(h.endsWith('/')) {
      h.chop(1);
    }
    while(b.endsWith('/')) {
      b.chop(1);
    }
    url.replace(QStringLiteral("{host}"), h);
    url.replace(QStringLiteral("{baseUrl}"), b);
    return url;
  };

  auto* mgr = new heap::integrations::OAuthManager(this);
  heap::integrations::OAuthManager::Params p;
  p.tokenUrl = expandHost(d->oauth.tokenUrl);
  p.clientId = clientId;
  p.clientSecret = clientSecret;
  p.scope = d->oauth.scope;
  p.usePkce = d->oauth.usePkce;
  p.deviceFlow = d->oauth.deviceFlow;
  // Device flow: authUrl is the device authorization endpoint (no loopback).
  p.authUrl = expandHost(p.deviceFlow ? d->oauth.deviceAuthUrl : d->oauth.authUrl);

  const QString label = d->displayName;
  // Device flow surfaces a user code the person types in the browser — relay it
  // to the Integrations card as a banner.
  connect(mgr, &heap::integrations::OAuthManager::userCode, this, [this, providerId, label](const QString& code, const QString& uri) {
    emit oauthDeviceCode(providerId, code, uri);
    emit toast(tr("%1: open %2 and enter code %3").arg(label, uri, code));
  });
  connect(mgr, &heap::integrations::OAuthManager::finished, this, [this, providerId, label, mgr](const heap::integrations::OAuthResult& r) {
    mgr->deleteLater();
    emit oauthDeviceCode(providerId, QString(), QString());  // clear the banner
    if(!r.ok) {
      emit toast(tr("%1 sign-in failed: %2").arg(label, r.error));
      return;
    }
    if(m_secretStore) {
      m_secretStore->setValue(providerId, QStringLiteral("token"), r.accessToken);
      if(!r.refreshToken.isEmpty()) {
        m_secretStore->setValue(providerId, QStringLiteral("refreshToken"), r.refreshToken);
      }
    }
    setIntegrationField(providerId, QStringLiteral("authMode"), QStringLiteral("oauth"));
    setIntegrationField(providerId, QStringLiteral("connected"), true);
    emit toast(tr("%1 connected via browser").arg(label));
  });
  if(p.deviceFlow) {
    emit toast(tr("Starting %1 browser sign-in…").arg(label));
  } else {
    emit toast(tr("Opening browser for %1 — OAuth redirect: %2").arg(label, heap::integrations::OAuthManager::redirectUri()));
  }
  mgr->start(p);
}

void AppController::scheduleSave() {
  if(m_loading || !m_saveTimer) {
    return;
  }
  m_saveTimer->start();
}

// ───────────────── (de)serialisation helpers ─────────────────
// Live state.json (de)serialisation now lives in src/StateSerializer.cpp
// (namespace heap::state) so the round-trip + field-count guards can exercise
// the real save path instead of a look-alike (HEAP-131).

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

// ───────────────── Save / load ─────────────────

// The writer seam (HEAP-156). saveStateNow() never touches the filesystem
// directly; it hands the serialized bytes to whatever is installed here. The
// default is an atomic QSaveFile write; the fault-injection harness swaps in a
// writer that truncates, corrupts or drops the rename.
namespace {
AppController::StateWriter g_stateWriter;

bool defaultStateWriter(const QString& path, const QByteArray& bytes) {
  QSaveFile f(path);
  if(!f.open(QIODevice::WriteOnly)) {
    qWarning("todocpp: cannot open state.json for writing: %s", qUtf8Printable(f.errorString()));
    return false;
  }
  f.write(bytes);
  if(!f.commit()) {
    qWarning("todocpp: state.json commit failed: %s", qUtf8Printable(f.errorString()));
    return false;
  }
  return true;
}
}  // namespace

void AppController::setStateWriterForTesting(StateWriter writer) {
  g_stateWriter = std::move(writer);
}

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
  // Rotational snapshots only. The pre-migration copy retained by
  // loadStateOnStart must survive retention: it is the only pre-v4 image of the
  // user's data.
  const QStringList all = d.entryList({"state-*.json"}, QDir::Files | QDir::NoSymLinks, QDir::Time);
  int kept = 0;
  for(const QString& name : all) {
    if(name.contains(QLatin1String("premigration"))) {
      continue;
    }
    if(++kept > keep) {
      d.remove(name);
    }
  }
}

bool AppController::recoverFromNewestBackup(QJsonObject& out, QString& fromPath) {
  const QDir d(backupDirPath());
  // Newest first — return the most recent backup that still parses as an object.
  const QFileInfoList backups = d.entryInfoList({"state-*.json"}, QDir::Files | QDir::NoSymLinks, QDir::Time);
  for(const QFileInfo& fi : backups) {
    QFile bf(fi.absoluteFilePath());
    if(!bf.open(QFile::ReadOnly)) {
      continue;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(bf.readAll());
    bf.close();
    if(!doc.isNull() && doc.isObject()) {
      out = doc.object();
      fromPath = fi.absoluteFilePath();
      return true;
    }
  }
  return false;
}

void AppController::quarantineCorruptState(const QString& path) {
  if(!QFile::exists(path)) {
    return;
  }
  const QFileInfo fi(path);
  const QString stamp = QDateTime::currentDateTime().toString("yyyyMMdd-HHmmss");
  QString target = fi.absolutePath() + "/state.corrupt-" + stamp + ".json";
  // Avoid clobbering an earlier quarantine from the same second.
  int n = 1;
  while(QFile::exists(target)) {
    target = fi.absolutePath() + "/state.corrupt-" + stamp + "-" + QString::number(n++) + ".json";
  }
  if(!QFile::rename(path, target)) {
    qWarning("todocpp: could not quarantine corrupt state.json to %s", qUtf8Printable(target));
    return;
  }
  heap::recovery::append(QString::fromLatin1(heap::recovery::kQuarantined),
                         {{QStringLiteral("from"), path}, {QStringLiteral("to"), target}});
}

void AppController::saveStateNow() {
  if(m_loading) {
    return;
  }

  // Push live model state back into the active profile.
  snapshotActiveProfile();

  QJsonObject root;
  root["schemaVersion"] = heap::state::kSchemaVersion;
  root["activeProfileId"] = m_activeProfileId;

  QJsonArray profilesArr;
  for(const Profile& p : m_profiles) {
    profilesArr.append(heap::state::profileToJson(p));
  }
  root["profiles"] = profilesArr;

  // Events are global (shown across profiles in the calendar).
  root["events"] = heap::state::eventsToJson(m_events.items());

  QJsonObject s;
  s["theme"] = m_theme;
  s["density"] = m_density;
  s["language"] = m_language;
  s["currentView"] = m_currentView;
  s["workdayStart"] = m_workdayStart;
  s["workdayEnd"] = m_workdayEnd;
  s["crumbProject"] = m_crumbProject;
  s["crumbUser"] = m_crumbUser;
  s["welcomeSeen"] = m_welcomeSeen;
  s["demoActive"] = m_demoActive;

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

  const QByteArray bytes = QJsonDocument(root).toJson(QJsonDocument::Indented);
  const bool ok = g_stateWriter ? g_stateWriter(stateFilePath(), bytes) : defaultStateWriter(stateFilePath(), bytes);
  if(!ok) {
    // A failed write is the fault the user never sees. Leave a local record so
    // "heap lost my edit" has evidence attached to the next bug report.
    heap::recovery::append(QString::fromLatin1(heap::recovery::kWriteFailed),
                           {{QStringLiteral("path"), stateFilePath()}, {QStringLiteral("bytes"), bytes.size()}});
  }
}

void AppController::loadStateOnStart() {
  const QString path = stateFilePath();
  QFile f(path);
  if(!f.exists()) {
    return;  // genuine first run — nothing to load, seed demo silently
  }

  // The file exists, so from here on any failure is corruption / an unreadable
  // file, NOT a first run. We must never let the caller silently seed demo data
  // and overwrite it: try to recover from the newest valid backup, otherwise
  // quarantine the damaged file so the subsequent save cannot destroy it.
  QJsonDocument doc;
  bool ok = false;
  if(f.open(QFile::ReadOnly)) {
    doc = QJsonDocument::fromJson(f.readAll());
    f.close();
    ok = !doc.isNull() && doc.isObject();
  }

  if(!ok) {
    QJsonObject recovered;
    QString recoveredFrom;
    if(recoverFromNewestBackup(recovered, recoveredFrom)) {
      // Quarantine the corrupt original, then promote the recovered backup to
      // be the live state so future debounced saves continue from good data.
      quarantineCorruptState(path);
      QFile::copy(recoveredFrom, path);
      doc = QJsonDocument(recovered);
      m_recoveryNotice = tr_("data.recovered").arg(QFileInfo(recoveredFrom).fileName());
      heap::recovery::append(QString::fromLatin1(heap::recovery::kRecovered), {{QStringLiteral("from"), recoveredFrom}});
    } else {
      // No usable backup. Preserve the damaged file under a distinct name and
      // fall through to a fresh seed — the user keeps a recoverable copy and a
      // visible warning instead of a silent wipe.
      quarantineCorruptState(path);
      m_recoveryNotice = tr_("data.corruptKept");
      heap::recovery::append(QString::fromLatin1(heap::recovery::kUnrecovered), {{QStringLiteral("path"), path}});
      return;
    }
  }

  QJsonObject root = doc.object();

  // ----- schema ladder: field-level upgrades, before anything parses a task ---
  // Version-gated and idempotent: a v4 document walks straight past this, so
  // reopening the app never re-migrates. The original file is copied aside first
  // — that copy is what a mid-migration failure reopens to, since it is the
  // newest valid state-*.json in the backup dir.
  const int onDiskSchema = root.value("schemaVersion").toInt(1);
  if(onDiskSchema < heap::state::kSchemaVersion) {
    retainPreMigrationBackup(path, onDiskSchema);
    heap::state::migrateState(root, onDiskSchema);
    heap::recovery::append(QString::fromLatin1(heap::recovery::kMigrated),
                           {{QStringLiteral("from"), onDiskSchema}, {QStringLiteral("to"), heap::state::kSchemaVersion}});
  }

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
    // Onboarding flags. An existing state.json that predates them means a
    // returning user — don't show the welcome again (default welcomeSeen=true),
    // and there is no seeded demo to offer clearing (demoActive=false).
    m_welcomeSeen = s.contains("welcomeSeen") ? s["welcomeSeen"].toBool() : true;
    m_demoActive = s.contains("demoActive") ? s["demoActive"].toBool() : false;
    emit onboardingChanged();
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

  // Structural decisions below key off what was on disk, not the migrated value.
  const int schema = onDiskSchema;
  QVector<CalEvent> globalEvents;

  if(schema >= 2 && root.contains("profiles")) {
    // ----- schema v2 / v3: profiles array -----
    for(const auto& it : root["profiles"].toArray()) {
      // For v2, profiles still carried their own events — hoist them
      // into the global pool tagged with the source profile id.
      QVector<CalEvent> legacy;
      m_profiles.push_back(heap::state::profileFromJson(it.toObject(), schema < 3 ? &legacy : nullptr));
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
      globalEvents = heap::state::eventsFromJson(root["events"].toArray());
    }
  } else {
    // ----- schema v1: flat fields → wrap into one "Example" profile -----
    Profile p;
    p.id = "default";
    p.name = "Example";
    p.color = "#5cc2dd";
    p.createdAt = QDateTime::currentDateTime();
    if(root.contains("tasks")) {
      p.tasks = heap::state::tasksFromJson(root["tasks"].toArray());
    }
    if(root.contains("people")) {
      p.people = heap::state::peopleFromJson(root["people"].toArray());
    }
    if(root.contains("statuses")) {
      p.statuses = heap::state::statusesFromJson(root["statuses"].toArray());
    }
    if(root.contains("docs")) {
      p.docsState = QJsonDocument(root["docs"].toObject()).toJson(QJsonDocument::Compact);
    }
    // Hoist any legacy top-level events into the global pool.
    if(root.contains("events")) {
      globalEvents = heap::state::eventsFromJson(root["events"].toArray(), p.id);
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

  // Force a rewrite so the on-disk file lands at the current schema version.
  if(schema < heap::state::kSchemaVersion) {
    scheduleSave();
  }
}

void AppController::retainPreMigrationBackup(const QString& path, int fromVersion) {
  const QString dir = backupDirPath();
  const QString stamp = QDateTime::currentDateTime().toString("yyyyMMdd-HHmmss");
  const QString target = dir + "/state-premigration-v" + QString::number(fromVersion) + "-" + stamp + ".json";
  if(QFile::exists(target) || !QFile::copy(path, target)) {
    return;
  }
  heap::recovery::append(QString::fromLatin1(heap::recovery::kPreMigration),
                         {{QStringLiteral("from"), path}, {QStringLiteral("to"), target}, {QStringLiteral("schema"), fromVersion}});
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

  // Task templates (HEAP-77) — "New from template: …" actions.
  for(const auto& t : builtinTemplates()) {
    QVariantMap m;
    m["kind"] = "template";
    m["label"] = QStringLiteral("New from template: ") + t.name;
    m["sub"] = QStringLiteral("template");
    m["templateName"] = t.name;
    m["color"] = QStringLiteral("#b58ad7");
    out.append(m);
  }

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

  // Full-text search (HEAP-80): each entry carries a `body` of the searchable
  // text that is NOT already in label/sub (task descriptions, note/doc/snippet
  // bodies, …). The palette scores over label+sub+body and shows a snippet when
  // the hit is in the body. Kept bounded so rebuilding the list stays cheap.
  constexpr int kBodyCap = 8000;
  const auto cap = [](QString s) {
    if(s.size() > kBodyCap) {
      s.truncate(kBodyCap);
    }
    return s;
  };

  for(const Profile& p : m_profiles) {
    // Notes — the whole per-profile markdown blob is one searchable entry.
    if(!p.notesState.trimmed().isEmpty()) {
      QVariantMap m;
      m["kind"] = "note";
      m["label"] = QString("%1 · Notes").arg(p.name);
      m["sub"] = p.name;
      m["body"] = cap(p.notesState);
      m["profileId"] = p.id;
      m["color"] = p.color;
      out.append(m);
    }
    // Tasks
    for(const Task& t : p.tasks) {
      QVariantMap m;
      m["kind"] = "task";
      m["label"] = QString("%1 · %2").arg(t.id, t.title);
      m["sub"] = QString("%1 · %2").arg(p.name, statusName(p.statuses, t.status).toUpper());
      m["body"] = cap(t.desc);
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
            m["body"] = cap(it["desc"].toString() + QChar(' ') + it["source"].toString());
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
          // Full-text (HEAP-79): language + tags + code so the palette can find
          // a snippet by tag or language, not just its title.
          QStringList tagList;
          for(const auto& tg : sn["tags"].toArray()) {
            const QString s = tg.toString().trimmed();
            if(!s.isEmpty()) {
              tagList << s;
            }
          }
          m["body"] = cap(sn["lang"].toString() + QChar(' ') + tagList.join(QChar(' ')) + QChar(' ') + sn["code"].toString());
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
          m["body"] = cap(c["channel"].toString() + QChar(' ') + c["mattermost"].toString());
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
      m["body"] = cap(person.question);
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
  QJsonObject profObj = heap::state::profileToJson(p);

  // Events live in the global pool, so profileToJson() cannot see them — a
  // profile export used to silently drop the whole calendar. Include the
  // events attributed to this profile so the export is a complete snapshot;
  // import re-attributes them to the (possibly re-slugged) imported profile.
  QVector<CalEvent> profileEvents;
  for(const CalEvent& e : m_events.items()) {
    if(e.profileId == m_activeProfileId) {
      profileEvents.append(e);
    }
  }
  profObj["events"] = heap::state::eventsToJson(profileEvents);

  QJsonObject root;
  root["schemaVersion"] = heap::state::kSchemaVersion;
  root["kind"] = "todocpp.profile";
  root["exportedAt"] = QDateTime::currentDateTime().toString(Qt::ISODate);
  root["profile"] = profObj;
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

  QVector<CalEvent> importedEvents;
  Profile imported = heap::state::profileFromJson(profileObj, &importedEvents);
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

  // Hoist the imported calendar events into the global pool, re-attributed to
  // the (possibly re-slugged) imported profile and given fresh ids so they can
  // never collide with existing events — including on a same-instance
  // round-trip where the source ids are already present.
  for(CalEvent& e : importedEvents) {
    e.profileId = imported.id;
    e.id = QStringLiteral("ev-") + QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    m_events.upsert(e);
  }

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
  add("profile.weeklyReport", "Ctrl+Shift+W");
  add("tweaks.open", "Ctrl+,");
  add("hotkeys.open", "Ctrl+/");
  add("undo", "Ctrl+Z");
  add("search.focus", "Ctrl+F");
  add("quick-capture", "Ctrl+Shift+Space");
  add("quick-capture-notes", "Ctrl+Shift+N");
  add("view.archive", "Ctrl+7");
  add("theme.toggle", "Ctrl+Shift+T");
  add("person.new", "Ctrl+Shift+U");
  add("profile.new", "Ctrl+Shift+P");
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
  const int row = m_tasks.indexOfId(taskId);
  if(row < 0) {
    return;
  }
  const bool prev = m_tasks.items().at(row).archived;
  if(prev == archived) {
    return;
  }
  m_tasks.setArchived(taskId, archived);

  // Arm undo so an accidental (un)archive is reversible.
  cancelUndo();
  m_pendingUndo = {};
  m_pendingUndo.kind = PendingUndo::TaskArchive;
  m_pendingUndo.taskId = taskId;
  m_pendingUndo.prevArchived = prev;
  armUndo(5);

  emit undoableToast(tr_(archived ? "task.archived" : "task.unarchived").arg(taskId), 5);
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
      if(!t.dueAt.isValid()) {
        continue;
      }
      if(t.status == QStringLiteral("done")) {
        continue;
      }
      // A task due at a parsed clock time fires then; a bare due date keeps the
      // old end-of-day horizon.
      const QDateTime deadlineAt = t.hasTime ? t.dueAt : QDateTime(t.dueAt.date(), QTime(23, 59));
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
  // A prefix edit lands here (idPrefix lives in app settings) but leaves HEAD
  // untouched, so re-match the branch we're already on for the banner.
  refreshFocusedTaskId();
}

void AppController::refreshFocusedTaskId() {
  if(m_focusedBranch.isEmpty() || m_focusedBranch == QStringLiteral("(detached HEAD)")) {
    return;
  }
  const heap::git::BranchTaskMatcher m(collectPrefixes());
  const auto mr = m.extract(m_focusedBranch);
  const QString newId = mr.matched ? mr.taskId : QString();
  if(newId == m_focusedTaskId) {
    return;
  }
  m_focusedTaskId = newId;
  m_dismissedBranches.remove(m_focusedBranch);  // re-arm banner for a now-matching branch
  emit focusedGitChanged();
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

void AppController::createBranchForTask(const QString& taskId) {
  if(!m_gitWatcher) {
    return;
  }
  const int row = m_tasks.indexOfId(taskId);
  if(row < 0) {
    return;
  }
  Task t = m_tasks.items().at(row);  // copy — mutated below on success

  // Prefer the currently focused repo; otherwise the first watched repo.
  QString repo = m_focusedRepo;
  const QStringList repos = m_gitWatcher->snapshot().keys();
  if(repo.isEmpty() && !repos.isEmpty()) {
    repo = repos.first();
  }
  if(repo.isEmpty()) {
    emit toast(tr("No git repository configured — add one in Settings › Git"));
    return;
  }

  const QString templ = settingsMap().value("integrations").toMap().value("github").toMap().value("branchTemplate").toString();
  const QString branch = heap::git::BranchTaskMatcher::branchNameForTask(t.id, t.title, templ);
  if(branch.isEmpty()) {
    emit toast(tr("Could not derive a branch name for %1").arg(t.id));
    return;
  }

  QString err;
  if(!m_gitWatcher->createBranch(repo, branch, &err)) {
    emit toast(tr("Branch create failed: %1").arg(err));
    return;
  }
  // Record the branch on the task so the card shows it and copy-branch works.
  t.branch = branch;
  m_tasks.upsert(t);
  scheduleSave();
  emit toast(tr("Created branch %1").arg(branch));
}

void AppController::onGitCommits(const QString& repo, const QVariantMap& commitsByTask) {
  Q_UNUSED(repo);
  for(auto it = commitsByTask.constBegin(); it != commitsByTask.constEnd(); ++it) {
    if(m_tasks.indexOfId(it.key()) < 0) {
      continue;
    }
    QVariantMap entry;
    entry["recentCommits"] = it.value();
    m_tasks.setGitInfoForId(it.key(), entry);
  }
}

// ── Native notifications with action buttons ─────────────────────

void AppController::notifyTask(const QString& taskId, const QString& title, const QString& body, const QString& kind) {
  if(inQuietHours(QDateTime::currentDateTime())) {
    return;
  }
  const QVariantMap notif = settingsMap().value("notifications").toMap();
  // Suppress the OS toast when notifications are disabled, unavailable, or the
  // window is currently focused. In the focused case the in-app Toast bar below
  // already shows the message — emitting both is the double-notification bug on
  // Windows (HEAP-47): one styled in-app toast and one plain system balloon.
  const bool appActive = QGuiApplication::applicationState() == Qt::ApplicationActive;
  if(!notif.value("desktopNotif", true).toBool() || !m_notifier || appActive) {
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
  if(!t.dueAt.isValid()) {
    return;
  }
  // Reminders are date-grained — bump to the next day so the dl: sentinel
  // for "today" stops firing. The clock time rides along.
  const int days = (seconds + 86399) / 86400;
  t.dueAt = t.dueAt.addDays(days);
  if(t.scheduledAt.isValid()) {
    t.scheduledAt = t.scheduledAt.addDays(days);
  }
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
