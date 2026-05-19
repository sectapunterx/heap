#include "AppController.h"
#include "SampleData.h"

#include <cmath>

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

namespace {
constexpr int kBackupIntervalSeconds = 5 * 60;
constexpr int kBackupRetentionCount  = 20;
}

AppController::AppController(QObject *parent)
    : QObject(parent)
{
    m_today = QDate::currentDate();
    m_selectedDate = m_today;

    m_saveTimer = new QTimer(this);
    m_saveTimer->setSingleShot(true);
    m_saveTimer->setInterval(300);
    connect(m_saveTimer, &QTimer::timeout, this, &AppController::saveStateNow);

    m_undoTimer = new QTimer(this);
    m_undoTimer->setSingleShot(true);
    connect(m_undoTimer, &QTimer::timeout, this, &AppController::clearPendingUndo);

    m_automationTimer = new QTimer(this);
    m_automationTimer->setInterval(60 * 1000);
    connect(m_automationTimer, &QTimer::timeout, this, &AppController::runAutomation);

    if (QSystemTrayIcon::isSystemTrayAvailable()) {
        QIcon icon(QStringLiteral(":/brand/icon/heap-icon.svg"));
        if (icon.isNull()) icon = QGuiApplication::windowIcon();
        if (icon.isNull()) icon = QIcon::fromTheme(QStringLiteral("application-x-executable"));
        m_tray = new QSystemTrayIcon(icon, this);
        m_tray->setToolTip(QStringLiteral("todocpp"));
        if (!icon.isNull()) m_tray->show();
    }

    // Route notification(...) → tray balloon + in-app toast, respecting quiet hours.
    connect(this, &AppController::notification, this,
            [this](const QString &title, const QString &body, const QString & /*kind*/) {
        if (inQuietHours(QDateTime::currentDateTime())) return;
        if (m_tray) m_tray->showMessage(title, body, QSystemTrayIcon::Information, 5000);
        emit toast(body);
    });

    seedShortcutCatalog();

    loadStateOnStart();
    m_automationTimer->start();

    // Fresh install or unreadable state — seed a single "Default" profile
    // from SampleData so the app boots with something sensible.
    if (m_profiles.isEmpty()) {
        Profile p;
        p.id        = "default";
        p.name      = "Default";
        p.color     = "#5cc2dd";
        p.createdAt = QDateTime::currentDateTime();
        p.tasks     = SampleData::tasks();
        p.people    = SampleData::people();
        QVariantList st;
        for (const auto &m : SampleData::statuses()) st.push_back(m);
        p.statuses  = st;
        p.docsState.clear();
        m_profiles.push_back(p);
        m_activeProfileId = p.id;

        // Events are global; tag the sample events with this default profile.
        QVector<CalEvent> sampleEvents = SampleData::events(m_today);
        for (CalEvent &e : sampleEvents) e.profileId = p.id;
        m_events.reset(sampleEvents);

        applyProfileToModels(p);
        emit profilesChanged();
        emit activeProfileChanged();
        scheduleSave();
    }
}

AppController::~AppController() {
    flushSave();
}

void AppController::flushSave() {
    if (m_saveTimer && m_saveTimer->isActive()) {
        m_saveTimer->stop();
        saveStateNow();
    }
}

void AppController::setSelectedDate(const QDate &d) {
    if (d == m_selectedDate) return;
    m_selectedDate = d;
    emit selectedDateChanged();
}

void AppController::setTheme(const QString &t) {
    if (t == m_theme) return;
    m_theme = t;
    emit themeChanged();
    scheduleSave();
}

void AppController::setDensity(const QString &d) {
    if (d == m_density) return;
    m_density = d;
    emit densityChanged();
    scheduleSave();
}

void AppController::setCurrentView(const QString &v) {
    if (v == m_currentView) return;
    m_currentView = v;
    emit currentViewChanged();
    scheduleSave();
}

void AppController::setWorkdayStart(int v) {
    v = qBound(0, v, 23);
    if (v >= m_workdayEnd) v = m_workdayEnd - 1;
    if (v == m_workdayStart) return;
    m_workdayStart = v;
    emit workdayChanged();
    scheduleSave();
}

void AppController::setWorkdayEnd(int v) {
    v = qBound(1, v, 24);
    if (v <= m_workdayStart) v = m_workdayStart + 1;
    if (v == m_workdayEnd) return;
    m_workdayEnd = v;
    emit workdayChanged();
    scheduleSave();
}

void AppController::setCrumbProject(const QString &v) {
    if (v == m_crumbProject) return;
    m_crumbProject = v;
    emit crumbProjectChanged();
    scheduleSave();
}

void AppController::setCrumbUser(const QString &v) {
    if (v == m_crumbUser) return;
    m_crumbUser = v;
    emit crumbUserChanged();
    scheduleSave();
}

void AppController::setDocsState(const QString &v) {
    if (v == m_docsState) return;
    m_docsState = v;
    emit docsStateChanged();
    scheduleSave();
}

void AppController::setNotesState(const QString &v) {
    if (v == m_notesState) return;
    m_notesState = v;
    emit notesStateChanged();
    scheduleSave();
}

void AppController::setAppSettingsJson(const QString &v) {
    if (v == m_appSettingsJson) return;
    m_appSettingsJson = v;
    emit appSettingsJsonChanged();
    scheduleSave();
}

void AppController::moveTask(const QString &id, const QString &newStatus) {
    const int row = m_tasks.indexOfId(id);
    if (row < 0) return;
    const Task &t = m_tasks.items().at(row);
    if (t.status == newStatus) return;
    if (!canTransitionStatus(id, newStatus)) return;
    QString statusName = newStatus;
    for (const auto &v : m_statuses) {
        const QVariantMap m = v.toMap();
        if (m.value("id").toString() == newStatus) {
            statusName = m.value("name").toString();
            break;
        }
    }
    const QString taskId = t.id;
    m_tasks.setStatus(id, newStatus);

    // Re-evaluate blocked-stuck set (the task may have left "blocked").
    if (m_blockedStuckIds.remove(id)) {
        m_tasks.setBlockedStuckIds(m_blockedStuckIds);
        emit blockedStuckChanged();
    }

    // Auto focus-block when moving into "prog", if setting on.
    if (newStatus == QStringLiteral("prog")) {
        const QVariantMap s = settingsMap();
        const QVariantMap cal = s.value("calendar").toMap();
        if (cal.value("autoFocusBlock", true).toBool()) {
            scheduleFocusBlockFor(taskId);
        }
    }

    emit toast(QString("%1 → %2").arg(taskId, statusName));
    scheduleSave();
}

QVariantMap AppController::newTaskDraft(const QString &statusId) const {
    const int nextNum = 2700 + m_tasks.rowCount();
    QVariantMap m;
    m["_isNew"] = true;
    m["id"] = QString("LTE-%1").arg(nextNum);
    m["title"] = QString();
    m["desc"] = QString();
    m["priority"] = "P2";
    m["status"] = statusId.isEmpty() ? QString("todo") : statusId;
    m["deadline"] = QDate();
    m["branch"] = QString();
    return m;
}

void AppController::saveTask(const QVariantMap &draft) {
    Task t;
    t.id       = draft.value("id").toString();
    t.title    = draft.value("title").toString();
    t.desc     = draft.value("desc").toString();
    t.priority = draft.value("priority").toString();
    t.status   = draft.value("status").toString();
    t.deadline = draft.value("deadline").toDate();
    t.branch   = draft.value("branch").toString();
    const bool isNew = draft.value("_isNew").toBool();
    if (isNew && t.title.trimmed().isEmpty()) return;
    m_tasks.upsert(t);
    if (isNew) emit toast(QString("Создано: %1").arg(t.id));
    scheduleSave();
}

void AppController::deleteTask(const QString &id) {
    const int row = m_tasks.indexOfId(id);
    if (row < 0) return;
    cancelUndo();
    m_pendingUndo = {};
    m_pendingUndo.kind = PendingUndo::Task;
    m_pendingUndo.task = m_tasks.items().at(row);
    m_pendingUndo.row  = row;
    for (const auto &e : m_events.items()) {
        if (e.taskId == id) m_pendingUndo.detachedEventIds.append({ e.id, e.taskId });
    }
    m_events.detachTask(id);
    m_tasks.removeById(id);
    armUndo(5);
    emit undoableToast(QString("Удалена: %1").arg(id), 5);
    scheduleSave();
}

QVariantMap AppController::newEventDraft(double startHour, const QDate &date) const {
    QVariantMap m;
    m["id"] = QString("ev-") + QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    m["title"] = QString("Новое событие");
    m["type"] = "sync";
    m["start"] = startHour;
    m["end"] = startHour + 1.0;
    m["attendees"] = QString();
    m["date"] = date.isValid() ? date : m_selectedDate;
    m["taskId"] = QString();
    m["profileId"] = m_activeProfileId;   // default attribution: active profile
    m["_isNew"] = true;
    return m;
}

void AppController::saveEvent(const QVariantMap &draft) {
    CalEvent e;
    e.id        = draft.value("id").toString();
    e.title     = draft.value("title").toString();
    e.type      = draft.value("type").toString();
    e.start     = draft.value("start").toDouble();
    e.end       = draft.value("end").toDouble();
    e.attendees = draft.value("attendees").toString();
    e.date      = draft.value("date").toDate();
    e.taskId    = draft.value("taskId").toString();
    e.profileId = draft.value("profileId").toString();
    if (e.end <= e.start) e.end = e.start + 0.25;
    m_events.upsert(e);
    scheduleSave();
}

void AppController::updateEvent(const QString &id, double start, double end, const QDate &date) {
    const int row = m_events.indexOfId(id);
    if (row < 0) return;
    auto snap15 = [](double h) { return std::round(h * 4.0) / 4.0; };
    CalEvent e = m_events.items().at(row);
    e.start = snap15(qBound(0.0, start, 24.0));
    e.end   = snap15(qBound(e.start + 0.25, end, 24.0));
    if (e.end < e.start + 0.25) e.end = e.start + 0.25;
    if (date.isValid()) e.date = date;
    m_events.upsert(e);
    scheduleSave();
}

QString AppController::scheduledLabelFor(const QString &taskId, const QDate &date) const {
    if (taskId.isEmpty() || !date.isValid()) return QString();
    double earliest = -1.0;
    for (const CalEvent &e : m_events.items()) {
        if (e.taskId != taskId || e.date != date) continue;
        if (earliest < 0.0 || e.start < earliest) earliest = e.start;
    }
    if (earliest < 0.0) return QString();
    return eventHourLabel(earliest);
}

void AppController::deleteEvent(const QString &id) {
    const int row = m_events.indexOfId(id);
    if (row < 0) return;
    cancelUndo();
    m_pendingUndo = {};
    m_pendingUndo.kind  = PendingUndo::Event;
    m_pendingUndo.event = m_events.items().at(row);
    m_pendingUndo.row   = row;
    m_events.removeById(id);
    armUndo(5);
    emit undoableToast(QString("Удалено событие: %1").arg(m_pendingUndo.event.title), 5);
    scheduleSave();
}

void AppController::scheduleTask(const QString &taskId, double startHour, const QDate &date) {
    const int row = m_tasks.indexOfId(taskId);
    if (row < 0) return;
    const Task &t = m_tasks.items().at(row);
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
    emit toast(QString("%1 запланировано на %2").arg(t.id, eventHourLabel(startHour)));
    scheduleSave();
}

void AppController::cyclePerson(const QString &id) {
    m_people.cycleState(id);
    scheduleSave();
}

void AppController::setPersonState(const QString &id, const QString &state) {
    m_people.setState(id, state);
    scheduleSave();
}

QVariantMap AppController::newPersonDraft() const {
    static const QColor palette[] = {
        QColor("#d97a6c"), QColor("#c87fc7"), QColor("#6cc4b8"),
        QColor("#7da8d9"), QColor("#dcc06a"), QColor("#7cc492"),
        QColor("#e69854"), QColor("#a4a4d6"),
    };
    const int n = static_cast<int>(sizeof(palette) / sizeof(palette[0]));
    const QColor c = palette[m_people.rowCount() % n];
    QVariantMap m;
    m["_isNew"] = true;
    m["id"]       = QString("p-") + QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    m["name"]     = QString();
    m["role"]     = QString();
    m["question"] = QString();
    m["state"]    = "todo";
    m["color"]    = c;
    return m;
}

QVariantMap AppController::personById(const QString &id) const {
    const int row = m_people.indexOfId(id);
    if (row < 0) return {};
    const QModelIndex mi = m_people.index(row, 0);
    QVariantMap m;
    m["_isNew"]   = false;
    m["id"]       = m_people.data(mi, PersonModel::IdRole);
    m["name"]     = m_people.data(mi, PersonModel::NameRole);
    m["role"]     = m_people.data(mi, PersonModel::RoleRole);
    m["question"] = m_people.data(mi, PersonModel::QuestionRole);
    m["state"]    = m_people.data(mi, PersonModel::StateRole);
    m["color"]    = m_people.data(mi, PersonModel::ColorRole);
    return m;
}

void AppController::savePerson(const QVariantMap &draft) {
    Person p;
    p.id       = draft.value("id").toString();
    p.name     = draft.value("name").toString();
    p.role     = draft.value("role").toString();
    p.question = draft.value("question").toString();
    p.state    = draft.value("state").toString();
    p.color    = draft.value("color").value<QColor>();
    if (!p.color.isValid()) p.color = QColor("#7da8d9");
    if (p.state.isEmpty()) p.state = "todo";
    if (p.id.isEmpty()) p.id = QString("p-") + QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    const bool isNew = draft.value("_isNew").toBool();
    if (isNew && p.name.trimmed().isEmpty()) return;
    m_people.upsert(p);
    if (isNew) emit toast(QString("Добавлен: %1").arg(p.name));
    scheduleSave();
}

void AppController::deletePerson(const QString &id) {
    const int row = m_people.indexOfId(id);
    if (row < 0) return;
    cancelUndo();
    m_pendingUndo = {};
    m_pendingUndo.kind   = PendingUndo::Person;
    m_pendingUndo.person = m_people.items().at(row);
    m_pendingUndo.row    = row;
    m_people.removeById(id);
    armUndo(5);
    emit undoableToast(QString("Удалён: %1").arg(m_pendingUndo.person.name), 5);
    scheduleSave();
}

int AppController::countByStatus(const QString &statusId) const {
    int n = 0;
    for (const auto &t : m_tasks.items()) if (t.status == statusId) ++n;
    return n;
}

int AppController::statusIndexOf(const QString &id) const {
    for (int i = 0; i < m_statuses.size(); ++i)
        if (m_statuses[i].toMap().value("id").toString() == id) return i;
    return -1;
}

void AppController::addStatus(const QString &name, const QString &color) {
    if (name.trimmed().isEmpty()) return;
    QString base = name.toLower();
    QString slug;
    for (QChar c : base) slug.append(c.isLetterOrNumber() ? c : QChar('-'));
    while (slug.contains("--")) slug.replace("--", "-");
    if (slug.startsWith('-')) slug = slug.mid(1);
    while (slug.endsWith('-')) slug.chop(1);
    if (slug.isEmpty()) slug = "status";
    QString id = slug;
    int n = 2;
    while (statusIndexOf(id) >= 0) { id = slug + "-" + QString::number(n++); }
    QVariantMap m;
    m["id"]    = id;
    m["name"]  = name;
    m["color"] = QColor(color.isEmpty() ? QStringLiteral("#5cc2dd") : color);
    m_statuses.append(m);
    emit statusesChanged();
    emit toast(QString("Колонка добавлена: %1").arg(name));
    scheduleSave();
}

void AppController::renameStatus(const QString &id, const QString &name) {
    const int i = statusIndexOf(id);
    if (i < 0 || name.trimmed().isEmpty()) return;
    QVariantMap m = m_statuses[i].toMap();
    if (m.value("name").toString() == name) return;
    m["name"] = name;
    m_statuses[i] = m;
    emit statusesChanged();
    scheduleSave();
}

void AppController::setStatusColor(const QString &id, const QString &color) {
    const int i = statusIndexOf(id);
    if (i < 0) return;
    const QColor c(color);
    if (!c.isValid()) return;
    QVariantMap m = m_statuses[i].toMap();
    m["color"] = c;
    m_statuses[i] = m;
    emit statusesChanged();
    scheduleSave();
}

void AppController::moveStatus(const QString &id, int newIndex) {
    const int from = statusIndexOf(id);
    if (from < 0) return;
    newIndex = qBound(0, newIndex, m_statuses.size() - 1);
    if (from == newIndex) return;
    QVariant v = m_statuses.takeAt(from);
    m_statuses.insert(newIndex, v);
    emit statusesChanged();
    scheduleSave();
}

void AppController::deleteStatus(const QString &id) {
    const int i = statusIndexOf(id);
    if (i < 0 || m_statuses.size() <= 1) return; // never let the board run out of columns
    cancelUndo();
    m_pendingUndo = {};
    m_pendingUndo.kind   = PendingUndo::Status;
    m_pendingUndo.status = m_statuses[i].toMap();
    m_pendingUndo.row    = i;

    // re-home any tasks with this status to the first remaining one
    QString fallback;
    for (int k = 0; k < m_statuses.size(); ++k) {
        if (k == i) continue;
        fallback = m_statuses[k].toMap().value("id").toString();
        break;
    }
    for (const auto &t : m_tasks.items()) {
        if (t.status == id) {
            m_pendingUndo.reHomedTasks.append({ t.id, id });
        }
    }
    for (const auto &pair : m_pendingUndo.reHomedTasks) {
        m_tasks.setStatus(pair.first, fallback);
    }

    const QString name = m_pendingUndo.status.value("name").toString();
    m_statuses.removeAt(i);
    emit statusesChanged();
    armUndo(5);
    emit undoableToast(QString("Удалена колонка: %1").arg(name), 5);
    scheduleSave();
}

QVariantMap AppController::taskById(const QString &id) const {
    const int row = m_tasks.indexOfId(id);
    if (row < 0) return {};
    const Task &t = m_tasks.items().at(row);
    QVariantMap m;
    m["id"] = t.id; m["title"] = t.title; m["desc"] = t.desc;
    m["priority"] = t.priority; m["status"] = t.status;
    m["deadline"] = t.deadline; m["branch"] = t.branch;
    return m;
}

QString AppController::eventHourLabel(double hour) const {
    const int hh = int(hour);
    const int mm = int((hour - hh) * 60 + 0.5);
    return QString("%1:%2")
        .arg(hh, 2, 10, QLatin1Char('0'))
        .arg(mm, 2, 10, QLatin1Char('0'));
}

QString AppController::sprintLabel() const {
    const int n = int((m_today.month()) * 2.1);
    return QString("sprint-%1").arg(n);
}

QString AppController::humanDate(const QDate &date) const {
    if (!date.isValid()) return {};
    QLocale ru(QLocale::Russian, QLocale::Russia);
    return ru.toString(date, "dddd, d MMMM");
}

QString AppController::deadlineBucket(const QDate &deadline) const {
    if (!deadline.isValid()) return "nodl";
    const int d = m_today.daysTo(deadline);
    if (d < 0)  return "overdue";
    if (d == 0) return "today";
    if (d == 1) return "tomorrow";
    if (d <= 6)  return "thisweek";
    if (d <= 13) return "nextweek";
    return "later";
}

QString AppController::deadlineDiffLabel(const QDate &deadline) const {
    if (!deadline.isValid()) return QStringLiteral("—");
    const int d = m_today.daysTo(deadline);
    if (d < 0)  return QString("%1d overdue").arg(-d);
    if (d == 0) return QStringLiteral("today");
    if (d == 1) return QStringLiteral("+1 day");
    if (d < 7)  return QString("+%1 days").arg(d);
    return QString("+%1d").arg(d);
}

QString AppController::shortDate(const QDate &d) const {
    if (!d.isValid()) return {};
    QLocale ru(QLocale::Russian, QLocale::Russia);
    return ru.toString(d, "ddd, d MMM");
}

int AppController::isoWeekNumber(const QDate &d) const {
    if (!d.isValid()) return 0;
    return d.weekNumber();
}

void AppController::copyToClipboard(const QString &text) {
    if (auto *cb = QGuiApplication::clipboard()) cb->setText(text);
}

// ───────────────────────────────────────────────────────── Undo ──

void AppController::armUndo(int seconds) {
    m_undoTimer->start(seconds * 1000);
    emit pendingUndoChanged();
}

void AppController::cancelUndo() {
    if (m_undoTimer) m_undoTimer->stop();
    if (m_pendingUndo.kind != PendingUndo::None) {
        m_pendingUndo = {};
        emit pendingUndoChanged();
    }
}

void AppController::clearPendingUndo() {
    cancelUndo();
}

void AppController::undoLastDeletion() {
    if (m_pendingUndo.kind == PendingUndo::None) return;
    switch (m_pendingUndo.kind) {
        case PendingUndo::Task: {
            m_tasks.insertAt(m_pendingUndo.row, m_pendingUndo.task);
            for (const auto &pair : m_pendingUndo.detachedEventIds)
                m_events.setTaskId(pair.first, pair.second);
            emit toast(QString("Восстановлена: %1").arg(m_pendingUndo.task.id));
            break;
        }
        case PendingUndo::Event: {
            m_events.insertAt(m_pendingUndo.row, m_pendingUndo.event);
            emit toast(QString("Восстановлено: %1").arg(m_pendingUndo.event.title));
            break;
        }
        case PendingUndo::Person: {
            m_people.insertAt(m_pendingUndo.row, m_pendingUndo.person);
            emit toast(QString("Восстановлён: %1").arg(m_pendingUndo.person.name));
            break;
        }
        case PendingUndo::Status: {
            const int idx = qBound(0, m_pendingUndo.row, m_statuses.size());
            m_statuses.insert(idx, m_pendingUndo.status);
            for (const auto &pair : m_pendingUndo.reHomedTasks)
                m_tasks.setStatus(pair.first, pair.second);
            emit statusesChanged();
            emit toast(QString("Восстановлена колонка: %1")
                       .arg(m_pendingUndo.status.value("name").toString()));
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
            emit toast(QString("Восстановлен профиль: %1")
                       .arg(m_pendingUndo.profile.name));
            break;
        }
        default: break;
    }
    m_pendingUndo = {};
    if (m_undoTimer) m_undoTimer->stop();
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
    if (m_loading || !m_saveTimer) return;
    m_saveTimer->start();
}

// ───────────────── (de)serialisation helpers ─────────────────
namespace {

QJsonArray tasksToJson(const QVector<Task> &xs) {
    QJsonArray a;
    for (const Task &t : xs) {
        QJsonObject o;
        o["id"]              = t.id;
        o["title"]           = t.title;
        o["desc"]            = t.desc;
        o["priority"]        = t.priority;
        o["status"]          = t.status;
        o["deadline"]        = t.deadline.isValid() ? t.deadline.toString(Qt::ISODate) : QString();
        o["branch"]          = t.branch;
        o["statusChangedAt"] = t.statusChangedAt.isValid() ? t.statusChangedAt.toString(Qt::ISODate) : QString();
        o["archived"]        = t.archived;
        a.append(o);
    }
    return a;
}

QVector<Task> tasksFromJson(const QJsonArray &a) {
    QVector<Task> v;
    v.reserve(a.size());
    for (const auto &it : a) {
        const QJsonObject o = it.toObject();
        Task t;
        t.id       = o["id"].toString();
        t.title    = o["title"].toString();
        t.desc     = o["desc"].toString();
        t.priority = o["priority"].toString();
        t.status   = o["status"].toString();
        t.deadline = QDate::fromString(o["deadline"].toString(), Qt::ISODate);
        t.branch   = o["branch"].toString();
        t.statusChangedAt = QDateTime::fromString(o["statusChangedAt"].toString(), Qt::ISODate);
        if (!t.statusChangedAt.isValid()) t.statusChangedAt = QDateTime::currentDateTime();
        t.archived = o["archived"].toBool(false);
        v.append(t);
    }
    return v;
}

QJsonArray eventsToJson(const QVector<CalEvent> &xs) {
    QJsonArray a;
    for (const CalEvent &e : xs) {
        QJsonObject o;
        o["id"]        = e.id;
        o["title"]     = e.title;
        o["type"]      = e.type;
        o["start"]     = e.start;
        o["end"]       = e.end;
        o["attendees"] = e.attendees;
        o["date"]      = e.date.isValid() ? e.date.toString(Qt::ISODate) : QString();
        o["taskId"]    = e.taskId;
        o["profileId"] = e.profileId;
        a.append(o);
    }
    return a;
}

QVector<CalEvent> eventsFromJson(const QJsonArray &a, const QString &fallbackProfileId = QString()) {
    QVector<CalEvent> v;
    v.reserve(a.size());
    for (const auto &it : a) {
        const QJsonObject o = it.toObject();
        CalEvent e;
        e.id        = o["id"].toString();
        e.title     = o["title"].toString();
        e.type      = o["type"].toString();
        e.start     = o["start"].toDouble();
        e.end       = o["end"].toDouble();
        e.attendees = o["attendees"].toString();
        e.date      = QDate::fromString(o["date"].toString(), Qt::ISODate);
        e.taskId    = o["taskId"].toString();
        e.profileId = o.contains("profileId") ? o["profileId"].toString() : fallbackProfileId;
        v.append(e);
    }
    return v;
}

QJsonArray peopleToJson(const QVector<Person> &xs) {
    QJsonArray a;
    for (const Person &p : xs) {
        QJsonObject o;
        o["id"]       = p.id;
        o["name"]     = p.name;
        o["role"]     = p.role;
        o["question"] = p.question;
        o["state"]    = p.state;
        o["color"]    = p.color.name();
        a.append(o);
    }
    return a;
}

QVector<Person> peopleFromJson(const QJsonArray &a) {
    QVector<Person> v;
    v.reserve(a.size());
    for (const auto &it : a) {
        const QJsonObject o = it.toObject();
        Person p;
        p.id       = o["id"].toString();
        p.name     = o["name"].toString();
        p.role     = o["role"].toString();
        p.question = o["question"].toString();
        p.state    = o["state"].toString();
        p.color    = QColor(o["color"].toString());
        v.append(p);
    }
    return v;
}

QJsonArray statusesToJson(const QVariantList &xs) {
    QJsonArray a;
    for (const QVariant &v : xs) {
        const QVariantMap m = v.toMap();
        QJsonObject o;
        o["id"]    = m.value("id").toString();
        o["name"]  = m.value("name").toString();
        const QVariant col = m.value("color");
        o["color"] = col.canConvert<QColor>() ? col.value<QColor>().name()
                                              : col.toString();
        a.append(o);
    }
    return a;
}

QVariantList statusesFromJson(const QJsonArray &a) {
    QVariantList v;
    for (const auto &it : a) {
        const QJsonObject o = it.toObject();
        QVariantMap m;
        m["id"]    = o["id"].toString();
        m["name"]  = o["name"].toString();
        m["color"] = QColor(o["color"].toString());
        v.append(m);
    }
    return v;
}

QJsonObject profileToJson(const Profile &p) {
    QJsonObject o;
    o["id"]        = p.id;
    o["name"]      = p.name;
    o["color"]     = p.color;
    o["createdAt"] = p.createdAt.isValid() ? p.createdAt.toString(Qt::ISODate) : QString();
    o["tasks"]     = tasksToJson(p.tasks);
    o["people"]    = peopleToJson(p.people);
    o["statuses"]  = statusesToJson(p.statuses);
    if (!p.docsState.isEmpty()) {
        const QJsonDocument d = QJsonDocument::fromJson(p.docsState.toUtf8());
        if (!d.isNull() && d.isObject()) o["docs"] = d.object();
    }
    if (!p.notesState.isEmpty()) o["notes"] = p.notesState;
    return o;
}

// Returns the parsed Profile and pulls out any nested "events" array (legacy
// schema v2) so the caller can hoist them into the global event pool with
// fallback profileId = p.id.
Profile profileFromJson(const QJsonObject &o, QVector<CalEvent> *outLegacyEvents = nullptr) {
    Profile p;
    p.id        = o["id"].toString();
    p.name      = o["name"].toString();
    p.color     = o["color"].toString();
    p.createdAt = QDateTime::fromString(o["createdAt"].toString(), Qt::ISODate);
    p.tasks     = tasksFromJson(o["tasks"].toArray());
    p.people    = peopleFromJson(o["people"].toArray());
    p.statuses  = statusesFromJson(o["statuses"].toArray());
    if (o.contains("docs"))
        p.docsState = QJsonDocument(o["docs"].toObject()).toJson(QJsonDocument::Compact);
    if (o.contains("notes"))
        p.notesState = o["notes"].toString();
    if (outLegacyEvents && o.contains("events")) {
        const QVector<CalEvent> v = eventsFromJson(o["events"].toArray(), p.id);
        outLegacyEvents->append(v);
    }
    return p;
}

} // namespace

// ───────────────── Profile helpers (private) ─────────────────

int AppController::profileIndexOf(const QString &id) const {
    for (int i = 0; i < m_profiles.size(); ++i)
        if (m_profiles[i].id == id) return i;
    return -1;
}

QString AppController::makeProfileId(const QString &name) const {
    QString slug;
    for (QChar c : name.toLower())
        slug.append(c.isLetterOrNumber() ? c : QChar('-'));
    while (slug.contains("--")) slug.replace("--", "-");
    if (slug.startsWith('-')) slug = slug.mid(1);
    while (slug.endsWith('-')) slug.chop(1);
    if (slug.isEmpty()) slug = "profile";
    QString id = slug;
    int n = 2;
    while (profileIndexOf(id) >= 0) { id = slug + "-" + QString::number(n++); }
    return id;
}

void AppController::snapshotActiveProfile() {
    const int i = profileIndexOf(m_activeProfileId);
    if (i < 0) return;
    Profile &p = m_profiles[i];
    p.tasks      = m_tasks.items();
    p.people     = m_people.items();
    p.statuses   = m_statuses;
    p.docsState  = m_docsState;
    p.notesState = m_notesState;
    // Events are global — not snapshotted into the profile.
}

void AppController::applyProfileToModels(const Profile &p) {
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

Profile AppController::makeStartingProfile(const QString &name, const QString &color) const {
    Profile p;
    p.name      = name;
    p.color     = color.isEmpty() ? "#5cc2dd" : color;
    p.createdAt = QDateTime::currentDateTime();
    // Copy status template from the currently active profile (or sample).
    const int activeIdx = profileIndexOf(m_activeProfileId);
    if (activeIdx >= 0) {
        for (const QVariant &v : m_profiles[activeIdx].statuses) {
            QVariantMap m = v.toMap();
            // copy color reference as-is
            p.statuses.append(m);
        }
    } else {
        for (const auto &m : SampleData::statuses()) p.statuses.append(m);
    }
    // tasks / events / people / docs — empty
    return p;
}

// ───────────────── Save / load (schema v2) ─────────────────

void AppController::rotateBackupIfDue() {
    const QString path = stateFilePath();
    if (!QFile::exists(path)) return;
    const QDateTime now = QDateTime::currentDateTime();
    if (m_lastBackupAt.isValid()
        && m_lastBackupAt.secsTo(now) < kBackupIntervalSeconds) return;
    const QString dir = backupDirPath();
    const QString stamp = now.toString("yyyyMMdd-HHmmss");
    QFile::copy(path, dir + "/state-" + stamp + ".json");
    pruneBackups(kBackupRetentionCount);
    m_lastBackupAt = now;
}

void AppController::pruneBackups(int keep) {
    QDir d(backupDirPath());
    const QStringList all = d.entryList({"state-*.json"},
                                        QDir::Files | QDir::NoSymLinks,
                                        QDir::Time);
    for (int i = keep; i < all.size(); ++i) d.remove(all[i]);
}

void AppController::saveStateNow() {
    if (m_loading) return;

    // Push live model state back into the active profile.
    snapshotActiveProfile();

    QJsonObject root;
    root["schemaVersion"]   = 3;
    root["activeProfileId"] = m_activeProfileId;

    QJsonArray profilesArr;
    for (const Profile &p : m_profiles) profilesArr.append(profileToJson(p));
    root["profiles"] = profilesArr;

    // Events are global (shown across profiles in the calendar).
    root["events"] = eventsToJson(m_events.items());

    QJsonObject s;
    s["theme"]        = m_theme;
    s["density"]      = m_density;
    s["currentView"]  = m_currentView;
    s["workdayStart"] = m_workdayStart;
    s["workdayEnd"]   = m_workdayEnd;
    s["crumbProject"] = m_crumbProject;
    s["crumbUser"]    = m_crumbUser;

    // Keyboard shortcut overrides — store every entry (so a user-cleared
    // binding survives a restart even if the default is non-empty).
    QJsonObject shortcutsObj;
    for (const QVariant &v : m_shortcuts) {
        const QVariantMap m = v.toMap();
        shortcutsObj[m.value("id").toString()] = m.value("sequence").toString();
    }
    s["shortcuts"]    = shortcutsObj;

    if (!m_appSettingsJson.isEmpty()) {
        const QJsonDocument d = QJsonDocument::fromJson(m_appSettingsJson.toUtf8());
        if (!d.isNull() && d.isObject()) s["app"] = d.object();
    }

    root["settings"]  = s;

    rotateBackupIfDue();

    QSaveFile f(stateFilePath());
    if (!f.open(QIODevice::WriteOnly)) {
        qWarning("todocpp: cannot open state.json for writing: %s",
                 qUtf8Printable(f.errorString()));
        return;
    }
    f.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    if (!f.commit()) {
        qWarning("todocpp: state.json commit failed: %s", qUtf8Printable(f.errorString()));
    }
}

void AppController::loadStateOnStart() {
    QFile f(stateFilePath());
    if (!f.exists() || !f.open(QFile::ReadOnly)) return;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    if (doc.isNull() || !doc.isObject()) return;
    const QJsonObject root = doc.object();

    m_loading = true;

    // ----- settings (global) -----
    if (root.contains("settings")) {
        const QJsonObject s = root["settings"].toObject();
        if (s.contains("theme"))        { m_theme = s["theme"].toString(); emit themeChanged(); }
        if (s.contains("density"))      { m_density = s["density"].toString(); emit densityChanged(); }
        if (s.contains("currentView"))  { m_currentView = s["currentView"].toString(); emit currentViewChanged(); }
        if (s.contains("workdayStart") || s.contains("workdayEnd")) {
            if (s.contains("workdayStart")) m_workdayStart = s["workdayStart"].toInt(m_workdayStart);
            if (s.contains("workdayEnd"))   m_workdayEnd   = s["workdayEnd"].toInt(m_workdayEnd);
            emit workdayChanged();
        }
        if (s.contains("crumbProject")) { m_crumbProject = s["crumbProject"].toString(); emit crumbProjectChanged(); }
        if (s.contains("crumbUser"))    { m_crumbUser    = s["crumbUser"].toString();    emit crumbUserChanged(); }
        if (s.contains("shortcuts")) {
            QVariantMap overrides;
            const QJsonObject shortcutsObj = s["shortcuts"].toObject();
            for (auto it = shortcutsObj.constBegin(); it != shortcutsObj.constEnd(); ++it)
                overrides.insert(it.key(), it.value().toString());
            applyShortcutOverrides(overrides);
        }
        if (s.contains("app") && s["app"].isObject()) {
            m_appSettingsJson = QJsonDocument(s["app"].toObject()).toJson(QJsonDocument::Compact);
            emit appSettingsJsonChanged();
        }
    }

    const int schema = root.value("schemaVersion").toInt(1);
    QVector<CalEvent> globalEvents;

    if (schema >= 2 && root.contains("profiles")) {
        // ----- schema v2 / v3: profiles array -----
        for (const auto &it : root["profiles"].toArray()) {
            // For v2, profiles still carried their own events — hoist them
            // into the global pool tagged with the source profile id.
            QVector<CalEvent> legacy;
            m_profiles.push_back(profileFromJson(it.toObject(),
                                                 schema < 3 ? &legacy : nullptr));
            if (!legacy.isEmpty()) globalEvents.append(legacy);
        }
        m_activeProfileId = root.value("activeProfileId").toString();
        if (profileIndexOf(m_activeProfileId) < 0 && !m_profiles.isEmpty())
            m_activeProfileId = m_profiles.first().id;
        // schema v3 keeps events at top level.
        if (schema >= 3 && root.contains("events"))
            globalEvents = eventsFromJson(root["events"].toArray());
    } else {
        // ----- schema v1: flat fields → wrap into one "Default" profile -----
        Profile p;
        p.id        = "default";
        p.name      = "Default";
        p.color     = "#5cc2dd";
        p.createdAt = QDateTime::currentDateTime();
        if (root.contains("tasks"))    p.tasks    = tasksFromJson(root["tasks"].toArray());
        if (root.contains("people"))   p.people   = peopleFromJson(root["people"].toArray());
        if (root.contains("statuses")) p.statuses = statusesFromJson(root["statuses"].toArray());
        if (root.contains("docs"))
            p.docsState = QJsonDocument(root["docs"].toObject()).toJson(QJsonDocument::Compact);
        // Hoist any legacy top-level events into the global pool.
        if (root.contains("events"))
            globalEvents = eventsFromJson(root["events"].toArray(), p.id);
        m_profiles.push_back(p);
        m_activeProfileId = p.id;
    }

    m_events.reset(globalEvents);

    if (!m_profiles.isEmpty()) {
        const int ai = qMax(0, profileIndexOf(m_activeProfileId));
        applyProfileToModels(m_profiles[ai]);
    }

    m_loading = false;

    emit profilesChanged();
    emit activeProfileChanged();

    // Force a rewrite to upgrade the on-disk file to v3 if we just migrated.
    if (schema < 3) scheduleSave();
}

// ───────────────────────────────────────────────────── Profiles API ──

QVariantList AppController::profiles() const {
    QVariantList out;
    for (const Profile &p : m_profiles) {
        QVariantMap m;
        m["id"]        = p.id;
        m["name"]      = p.name;
        m["color"]     = p.color;
        m["tasks"]     = p.tasks.size();
        m["docs"]      = p.docsState.size() > 2 ? 1 : 0;
        m["createdAt"] = p.createdAt.isValid() ? p.createdAt.toString(Qt::ISODate) : QString();
        out.append(m);
    }
    return out;
}

void AppController::setActiveProfileId(const QString &id) {
    if (id == m_activeProfileId) return;
    const int next = profileIndexOf(id);
    if (next < 0) return;
    snapshotActiveProfile();
    m_activeProfileId = id;
    applyProfileToModels(m_profiles[next]);
    emit activeProfileChanged();
    scheduleSave();
}

QString AppController::createProfile(const QString &name, const QString &color) {
    if (name.trimmed().isEmpty()) return QString();
    // Snapshot current active before creating so we don't lose unsaved edits.
    snapshotActiveProfile();
    Profile p = makeStartingProfile(name.trimmed(), color);
    p.id = makeProfileId(name.trimmed());
    m_profiles.push_back(p);
    m_activeProfileId = p.id;
    applyProfileToModels(p);
    emit profilesChanged();
    emit activeProfileChanged();
    emit toast(QString("Профиль создан: %1").arg(p.name));
    scheduleSave();
    return p.id;
}

void AppController::renameProfile(const QString &id, const QString &newName) {
    const int i = profileIndexOf(id);
    if (i < 0 || newName.trimmed().isEmpty()) return;
    if (m_profiles[i].name == newName) return;
    m_profiles[i].name = newName.trimmed();
    emit profilesChanged();
    if (id == m_activeProfileId) emit activeProfileChanged();
    scheduleSave();
}

void AppController::setProfileColor(const QString &id, const QString &color) {
    const int i = profileIndexOf(id);
    if (i < 0) return;
    const QColor c(color);
    if (!c.isValid()) return;
    m_profiles[i].color = c.name();
    emit profilesChanged();
    if (id == m_activeProfileId) emit activeProfileChanged();
    scheduleSave();
}

void AppController::deleteProfile(const QString &id) {
    const int i = profileIndexOf(id);
    if (i < 0 || m_profiles.size() <= 1) return;  // never let the app run out of profiles
    cancelUndo();
    snapshotActiveProfile();
    m_pendingUndo = {};
    m_pendingUndo.kind    = PendingUndo::Profile;
    m_pendingUndo.profile = m_profiles[i];
    m_pendingUndo.row     = i;
    const QString name = m_profiles[i].name;
    m_profiles.removeAt(i);

    // Events that were attributed to this profile become "unassigned"
    // (still visible in the calendar, but with no feature dot).
    for (int r = 0; r < m_events.rowCount(); ++r) {
        const QModelIndex mi = m_events.index(r, 0);
        if (m_events.data(mi, EventModel::ProfileIdRole).toString() == id) {
            const CalEvent &e = m_events.items().at(r);
            CalEvent copy = e;
            copy.profileId.clear();
            m_events.upsert(copy);
        }
    }

    // If we deleted the active one, fall back to its neighbour.
    if (id == m_activeProfileId) {
        const int fallback = qMin(i, m_profiles.size() - 1);
        m_activeProfileId = m_profiles[fallback].id;
        applyProfileToModels(m_profiles[fallback]);
        emit activeProfileChanged();
    }
    emit profilesChanged();
    armUndo(5);
    emit undoableToast(QString("Удалён профиль: %1").arg(name), 5);
    scheduleSave();
}

QVariantMap AppController::profileById(const QString &id) const {
    const int i = profileIndexOf(id);
    if (i < 0) return {};
    const Profile &p = m_profiles[i];
    QVariantMap m;
    m["id"]    = p.id;
    m["name"]  = p.name;
    m["color"] = p.color;
    return m;
}

QString AppController::duplicateProfile(const QString &id, const QString &newName) {
    const int i = profileIndexOf(id);
    if (i < 0) return QString();
    if (id == m_activeProfileId) snapshotActiveProfile();
    Profile copy   = m_profiles[i];
    copy.name      = newName.trimmed().isEmpty()
                     ? (m_profiles[i].name + " copy")
                     : newName.trimmed();
    copy.id        = makeProfileId(copy.name);
    copy.createdAt = QDateTime::currentDateTime();
    m_profiles.push_back(copy);
    m_activeProfileId = copy.id;
    applyProfileToModels(copy);
    emit profilesChanged();
    emit activeProfileChanged();
    emit toast(QString("Дублирован профиль: %1").arg(copy.name));
    scheduleSave();
    return copy.id;
}

// ───────────────────────────────────────────────────── Backups API ──

QVariantList AppController::listBackups() const {
    QVariantList out;
    QDir d(backupDirPath());
    const QStringList files = d.entryList({"state-*.json"},
                                          QDir::Files | QDir::NoSymLinks,
                                          QDir::Time);
    for (const QString &name : files) {
        QFileInfo fi(d.filePath(name));
        QVariantMap m;
        m["fileName"] = name;
        m["sizeKb"]   = qint64(fi.size() / 1024);
        m["mtime"]    = fi.lastModified().toString(Qt::ISODate);
        out.append(m);
    }
    return out;
}

bool AppController::restoreFromBackup(const QString &fileName) {
    const QString src = backupDirPath() + "/" + fileName;
    if (!QFile::exists(src)) return false;
    // Snapshot current state alongside backups before overwriting.
    rotateBackupIfDue();
    flushSave();
    QFile target(stateFilePath());
    if (target.exists()) target.remove();
    if (!QFile::copy(src, stateFilePath())) return false;

    // Reload from disk.
    m_profiles.clear();
    m_activeProfileId.clear();
    loadStateOnStart();
    emit toast(QString("Восстановлено из %1").arg(fileName));
    return true;
}

// ───────────────────────────────────────────── Command palette source ──

QVariantList AppController::commandPaletteEntries() const {
    QVariantList out;

    // Profiles themselves.
    for (const Profile &p : m_profiles) {
        QVariantMap m;
        m["kind"]      = "profile";
        m["label"]     = p.name;
        m["sub"]       = QString("%1 tasks").arg(p.tasks.size());
        m["profileId"] = p.id;
        m["color"]     = p.color;
        out.append(m);
    }

    auto statusName = [](const QVariantList &statuses, const QString &id) {
        for (const QVariant &v : statuses) {
            const QVariantMap m = v.toMap();
            if (m.value("id").toString() == id) return m.value("name").toString();
        }
        return id;
    };

    for (const Profile &p : m_profiles) {
        // Tasks
        for (const Task &t : p.tasks) {
            QVariantMap m;
            m["kind"]      = "task";
            m["label"]     = QString("%1 · %2").arg(t.id, t.title);
            m["sub"]       = QString("%1 · %2").arg(p.name, statusName(p.statuses, t.status).toUpper());
            m["profileId"] = p.id;
            m["taskId"]    = t.id;
            m["color"]     = p.color;
            out.append(m);
        }
        // Docs / snippets / contacts (parsed from docsState JSON blob)
        if (!p.docsState.isEmpty()) {
            const QJsonDocument d = QJsonDocument::fromJson(p.docsState.toUtf8());
            if (!d.isNull() && d.isObject()) {
                const QJsonObject root = d.object();
                for (const auto &sIt : root["sections"].toArray()) {
                    const QJsonObject sec = sIt.toObject();
                    const QString secId    = sec["id"].toString();
                    const QString secTitle = sec["title"].toString();
                    for (const auto &iIt : sec["items"].toArray()) {
                        const QJsonObject it = iIt.toObject();
                        QVariantMap m;
                        m["kind"]      = "doc";
                        m["label"]     = QString("%1 · %2").arg(it["ref"].toString(),
                                                                 it["title"].toString());
                        m["sub"]       = QString("%1 · %2").arg(p.name, secTitle);
                        m["profileId"] = p.id;
                        m["sectionId"] = secId;
                        m["color"]     = p.color;
                        out.append(m);
                    }
                }
                int snipIdx = 0;
                for (const auto &snIt : root["snippets"].toArray()) {
                    const QJsonObject sn = snIt.toObject();
                    QVariantMap m;
                    m["kind"]      = "snippet";
                    m["label"]     = sn["title"].toString();
                    m["sub"]       = QString("%1 · %2").arg(p.name, sn["lang"].toString());
                    m["profileId"] = p.id;
                    m["idx"]       = snipIdx++;
                    m["color"]     = p.color;
                    out.append(m);
                }
                int contactIdx = 0;
                for (const auto &cIt : root["contacts"].toArray()) {
                    const QJsonObject c = cIt.toObject();
                    QVariantMap m;
                    m["kind"]      = "contact";
                    m["label"]     = c["name"].toString();
                    m["sub"]       = QString("%1 · %2").arg(p.name, c["role"].toString());
                    m["profileId"] = p.id;
                    m["idx"]       = contactIdx++;
                    m["color"]     = p.color;
                    out.append(m);
                }
            }
        }
        // People (pending contacts list)
        for (const Person &person : p.people) {
            QVariantMap m;
            m["kind"]      = "person";
            m["label"]     = person.name;
            m["sub"]       = QString("%1 · %2").arg(p.name, person.role);
            m["profileId"] = p.id;
            m["personId"]  = person.id;
            m["color"]     = p.color;
            out.append(m);
        }
    }

    return out;
}

// ───────────────────────────────────── JSON import / export of profile ──

QString AppController::exportActiveProfileJson() const {
    const int i = profileIndexOf(m_activeProfileId);
    if (i < 0) return QString();
    // Snapshot the live models into the profile copy we serialise, so
    // unsaved edits in tasks/people/statuses/docs/notes round-trip.
    Profile p = m_profiles[i];
    p.tasks      = m_tasks.items();
    p.people     = m_people.items();
    p.statuses   = m_statuses;
    p.docsState  = m_docsState;
    p.notesState = m_notesState;
    QJsonObject root;
    root["schemaVersion"] = 3;
    root["kind"]          = "todocpp.profile";
    root["exportedAt"]    = QDateTime::currentDateTime().toString(Qt::ISODate);
    root["profile"]       = profileToJson(p);
    return QString::fromUtf8(QJsonDocument(root).toJson(QJsonDocument::Indented));
}

bool AppController::exportActiveProfileToFile(const QUrl &fileUrl) const {
    const QString path = fileUrl.isLocalFile() ? fileUrl.toLocalFile() : fileUrl.toString();
    if (path.isEmpty()) return false;
    const QString json = exportActiveProfileJson();
    if (json.isEmpty()) return false;
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly)) {
        qWarning("todocpp: cannot open %s for writing: %s",
                 qUtf8Printable(path), qUtf8Printable(f.errorString()));
        return false;
    }
    f.write(json.toUtf8());
    if (!f.commit()) return false;
    const_cast<AppController*>(this)->emit toast(
        QStringLiteral("Профиль экспортирован: %1").arg(QFileInfo(path).fileName()));
    return true;
}

QString AppController::importProfileFromJson(const QString &jsonText, bool activate) {
    if (jsonText.trimmed().isEmpty()) return QStringLiteral("Пустой JSON");
    const QJsonDocument doc = QJsonDocument::fromJson(jsonText.toUtf8());
    if (doc.isNull() || !doc.isObject())
        return QStringLiteral("Невалидный JSON");
    const QJsonObject root = doc.object();

    // Accept either { "profile": {...} } wrapper or a bare profile object.
    QJsonObject profileObj;
    if (root.contains("profile") && root["profile"].isObject())
        profileObj = root["profile"].toObject();
    else if (root.contains("id") && root.contains("name"))
        profileObj = root;
    else
        return QStringLiteral("В JSON нет блока 'profile' или ожидаемых полей");

    Profile imported = profileFromJson(profileObj);
    if (imported.name.trimmed().isEmpty())
        imported.name = QStringLiteral("Imported");

    // Resolve id collisions — re-slug so we never overwrite an existing profile.
    if (imported.id.isEmpty() || profileIndexOf(imported.id) >= 0)
        imported.id = makeProfileId(imported.name);
    imported.createdAt = QDateTime::currentDateTime();
    if (imported.color.isEmpty()) imported.color = QStringLiteral("#5cc2dd");
    if (imported.statuses.isEmpty()) {
        for (const auto &m : SampleData::statuses()) imported.statuses.append(m);
    }

    if (activate) snapshotActiveProfile();
    m_profiles.push_back(imported);
    if (activate) {
        m_activeProfileId = imported.id;
        applyProfileToModels(imported);
        emit activeProfileChanged();
    }
    emit profilesChanged();
    emit toast(QStringLiteral("Импортирован профиль: %1").arg(imported.name));
    scheduleSave();
    return QString();
}

QString AppController::importProfileFromFile(const QUrl &fileUrl, bool activate) {
    const QString path = fileUrl.isLocalFile() ? fileUrl.toLocalFile() : fileUrl.toString();
    if (path.isEmpty()) return QStringLiteral("Пустой путь");
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return QStringLiteral("Не открывается: ") + f.errorString();
    const QString text = QString::fromUtf8(f.readAll());
    return importProfileFromJson(text, activate);
}


// ─────────────────────────────────────────────── Shortcuts catalog ──

namespace {
QVariantMap makeShortcut(const char *id, const char *label, const char *desc,
                         const char *defaultSeq) {
    QVariantMap m;
    m["id"]              = QString::fromUtf8(id);
    m["label"]           = QString::fromUtf8(label);
    m["description"]     = QString::fromUtf8(desc);
    m["defaultSequence"] = QString::fromUtf8(defaultSeq);
    m["sequence"]        = QString::fromUtf8(defaultSeq);
    return m;
}
} // namespace

void AppController::seedShortcutCatalog() {
    m_shortcuts.clear();
    m_shortcuts.append(makeShortcut("palette.open",     "Открыть Command Palette",
        "Глобальный fuzzy-поиск задач, доков, профилей.",      "Ctrl+K"));
    m_shortcuts.append(makeShortcut("task.new",         "Новая задача",
        "Создать тикет в активном профиле.",                   "Ctrl+N"));
    m_shortcuts.append(makeShortcut("view.board",       "Перейти в Board",
        "Канбан активного профиля.",                           "Ctrl+1"));
    m_shortcuts.append(makeShortcut("view.timeline",    "Перейти в Timeline",
        "Лента по дедлайнам.",                                 "Ctrl+2"));
    m_shortcuts.append(makeShortcut("view.week",        "Перейти в Week",
        "Семидневный планировщик.",                            "Ctrl+3"));
    m_shortcuts.append(makeShortcut("view.docs",        "Перейти в Docs",
        "Спеки, ссылки, сниппеты, контакты.",                  "Ctrl+4"));
    m_shortcuts.append(makeShortcut("view.notes",       "Перейти в Notes",
        "Markdown-канвас активного профиля.",                  "Ctrl+5"));
    m_shortcuts.append(makeShortcut("view.settings",    "Перейти в Settings",
        "Полная панель настроек: профиль, внешний вид, интеграции.", "Ctrl+6"));
    m_shortcuts.append(makeShortcut("profile.next",     "Следующий профиль",
        "Циклит по списку профилей вперёд.",                   "Ctrl+]"));
    m_shortcuts.append(makeShortcut("profile.prev",     "Предыдущий профиль",
        "Циклит по списку профилей назад.",                    "Ctrl+["));
    m_shortcuts.append(makeShortcut("profile.exportMd", "Экспорт профиля в Markdown",
        "Кладёт markdown-выжимку активного профиля в буфер.",  "Ctrl+Shift+E"));
    m_shortcuts.append(makeShortcut("tweaks.open",      "Открыть Tweaks",
        "Тема, плотность, рабочий день.",                      "Ctrl+,"));
    m_shortcuts.append(makeShortcut("hotkeys.open",     "Открыть Hotkeys",
        "Эта панель.",                                         "Ctrl+/"));
    m_shortcuts.append(makeShortcut("undo",             "Отменить удаление",
        "Восстановить последнюю удалённую задачу/событие/профиль.", "Ctrl+Z"));
    m_shortcuts.append(makeShortcut("search.focus",     "Фокус в поиск",
        "Перевести курсор в строку поиска в шапке.",           "Ctrl+F"));
    emit shortcutsChanged();
}

int AppController::shortcutIndexOf(const QString &id) const {
    for (int i = 0; i < m_shortcuts.size(); ++i)
        if (m_shortcuts[i].toMap().value("id").toString() == id) return i;
    return -1;
}

QString AppController::normalizeSequence(const QString &raw) const {
    const QString trimmed = raw.trimmed();
    if (trimmed.isEmpty()) return QString();
    const QKeySequence ks(trimmed, QKeySequence::PortableText);
    if (ks.isEmpty()) return QString();
    return ks.toString(QKeySequence::PortableText);
}

void AppController::applyShortcutOverrides(const QVariantMap &overrides) {
    bool changed = false;
    for (int i = 0; i < m_shortcuts.size(); ++i) {
        QVariantMap m = m_shortcuts[i].toMap();
        const QString id = m.value("id").toString();
        if (!overrides.contains(id)) continue;
        const QString seq = normalizeSequence(overrides.value(id).toString());
        if (seq == m.value("sequence").toString()) continue;
        m["sequence"] = seq;
        m_shortcuts[i] = m;
        changed = true;
    }
    if (changed) emit shortcutsChanged();
}

QString AppController::shortcutFor(const QString &id) const {
    const int i = shortcutIndexOf(id);
    return i < 0 ? QString() : m_shortcuts[i].toMap().value("sequence").toString();
}

QString AppController::defaultShortcutFor(const QString &id) const {
    const int i = shortcutIndexOf(id);
    return i < 0 ? QString() : m_shortcuts[i].toMap().value("defaultSequence").toString();
}

QString AppController::shortcutDescription(const QString &id) const {
    const int i = shortcutIndexOf(id);
    return i < 0 ? QString() : m_shortcuts[i].toMap().value("description").toString();
}

QString AppController::shortcutLabel(const QString &id) const {
    const int i = shortcutIndexOf(id);
    return i < 0 ? QString() : m_shortcuts[i].toMap().value("label").toString();
}

QString AppController::findShortcutConflict(const QString &id, const QString &sequence) const {
    const QString want = normalizeSequence(sequence);
    if (want.isEmpty()) return QString();
    for (int i = 0; i < m_shortcuts.size(); ++i) {
        const QVariantMap m = m_shortcuts[i].toMap();
        if (m.value("id").toString() == id) continue;
        if (m.value("sequence").toString() == want)
            return m.value("id").toString();
    }
    return QString();
}

bool AppController::setShortcut(const QString &id, const QString &sequence) {
    const int i = shortcutIndexOf(id);
    if (i < 0) return false;
    const QString seq = normalizeSequence(sequence);
    QVariantMap m = m_shortcuts[i].toMap();
    if (m.value("sequence").toString() == seq) return true;

    // VS-Code-style swap: clear the conflicting owner so the new binding wins.
    if (!seq.isEmpty()) {
        const QString conflictId = findShortcutConflict(id, seq);
        if (!conflictId.isEmpty()) {
            const int j = shortcutIndexOf(conflictId);
            if (j >= 0) {
                QVariantMap o = m_shortcuts[j].toMap();
                const QString freedLabel = o.value("label").toString();
                o["sequence"] = QString();
                m_shortcuts[j] = o;
                emit toast(QString("Освобождено: %1").arg(freedLabel));
            }
        }
    }

    m["sequence"] = seq;
    m_shortcuts[i] = m;
    emit shortcutsChanged();
    scheduleSave();
    return true;
}

void AppController::resetShortcut(const QString &id) {
    const int i = shortcutIndexOf(id);
    if (i < 0) return;
    QVariantMap m = m_shortcuts[i].toMap();
    const QString def = m.value("defaultSequence").toString();
    if (m.value("sequence").toString() == def) return;
    // If the default would conflict with another action, swap it out.
    const QString conflictId = findShortcutConflict(id, def);
    if (!conflictId.isEmpty()) {
        const int j = shortcutIndexOf(conflictId);
        if (j >= 0) {
            QVariantMap o = m_shortcuts[j].toMap();
            o["sequence"] = QString();
            m_shortcuts[j] = o;
        }
    }
    m["sequence"] = def;
    m_shortcuts[i] = m;
    emit shortcutsChanged();
    scheduleSave();
}

void AppController::resetAllShortcuts() {
    bool changed = false;
    for (int i = 0; i < m_shortcuts.size(); ++i) {
        QVariantMap m = m_shortcuts[i].toMap();
        const QString def = m.value("defaultSequence").toString();
        if (m.value("sequence").toString() != def) {
            m["sequence"] = def;
            m_shortcuts[i] = m;
            changed = true;
        }
    }
    if (changed) {
        emit shortcutsChanged();
        scheduleSave();
        emit toast("Хоткеи сброшены к дефолту");
    }
}

// ── Notifications, transitions, automation ─────────────────────────────

QVariantMap AppController::settingsMap() const {
    if (m_appSettingsJson.isEmpty()) return {};
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(m_appSettingsJson.toUtf8(), &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) return {};
    return doc.object().toVariantMap();
}

bool AppController::canTransitionStatus(const QString &taskId, const QString &newStatus) {
    const int row = m_tasks.indexOfId(taskId);
    if (row < 0) return false;
    const Task &t = m_tasks.items().at(row);
    if (newStatus == QStringLiteral("review")) {
        const QVariantMap s = settingsMap();
        const QVariantMap tasks = s.value("tasks").toMap();
        if (tasks.value("requireBranchOnReview", true).toBool() && t.branch.trimmed().isEmpty()) {
            emit toast(QStringLiteral("Заполни branch — этого требует Settings"));
            return false;
        }
    }
    return true;
}

void AppController::setArchived(const QString &taskId, bool archived) {
    m_tasks.setArchived(taskId, archived);
    scheduleSave();
}

void AppController::notify(const QString &title, const QString &body, const QString &kind) {
    emit notification(title, body, kind);
}

bool AppController::inQuietHours(const QDateTime &when) const {
    const QVariantMap s = settingsMap();
    const QVariantMap notif = s.value("notifications").toMap();
    if (!notif.value("quietHours", true).toBool()) return false;
    const QTime from = QTime::fromString(notif.value("quietFrom", "19:00").toString(), "HH:mm");
    const QTime to   = QTime::fromString(notif.value("quietTo",   "09:00").toString(), "HH:mm");
    if (!from.isValid() || !to.isValid()) return false;
    const QTime now = when.time();
    if (from <= to) {
        return now >= from && now < to;
    }
    // Window wraps midnight (e.g. 19:00..09:00).
    return now >= from || now < to;
}

double AppController::nextQuarterHour(const QDateTime &when) {
    const QTime t = when.time();
    const double cur = t.hour() + t.minute() / 60.0;
    const double q = std::ceil(cur * 4.0) / 4.0;
    return std::min(q, 24.0);
}

void AppController::scheduleFocusBlockFor(const QString &taskId) {
    const int row = m_tasks.indexOfId(taskId);
    if (row < 0) return;
    const Task &t = m_tasks.items().at(row);
    const QVariantMap s = settingsMap();
    const QVariantMap cal = s.value("calendar").toMap();
    const int durMin = cal.value("focusBlockDuration", 90).toInt();
    const double dur = std::max(0.25, durMin / 60.0);
    const QDateTime now = QDateTime::currentDateTime();
    const double start = nextQuarterHour(now);
    if (start >= 24.0) return; // No room left in today.
    const double end = std::min(24.0, start + dur);
    CalEvent e;
    e.id        = QStringLiteral("ev-") + QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    e.title     = QStringLiteral("Focus: %1").arg(t.title);
    e.type      = QStringLiteral("focus");
    e.start     = start;
    e.end       = end;
    e.date      = now.date();
    e.taskId    = taskId;
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
    for (const Task &t : m_tasks.items()) {
        if (t.archived) continue;
        if (t.status != QStringLiteral("blocked")) continue;
        if (!t.statusChangedAt.isValid()) continue;
        if (t.statusChangedAt.daysTo(now) >= stuckDays) {
            stuck.insert(t.id);
        }
    }
    if (stuck != m_blockedStuckIds) {
        m_blockedStuckIds = stuck;
        m_tasks.setBlockedStuckIds(m_blockedStuckIds);
        emit blockedStuckChanged();
    }

    // 2. Auto-archive done tasks past retention.
    const int archDays = qMax(0, tasksCfg.value("archiveDoneAfterDays", 7).toInt());
    bool persistedAny = false;
    if (archDays > 0) {
        QStringList toArchive;
        for (const Task &t : m_tasks.items()) {
            if (t.archived) continue;
            if (t.status != QStringLiteral("done")) continue;
            if (!t.statusChangedAt.isValid()) continue;
            if (t.statusChangedAt.daysTo(now) >= archDays) toArchive << t.id;
        }
        for (const QString &id : toArchive) {
            m_tasks.setArchived(id, true);
            persistedAny = true;
        }
    }
    if (persistedAny) scheduleSave();

    // 3. Deadline reminders — at most one per task per day.
    if (notif.value("deadlineReminders", true).toBool()) {
        const int leadHours = qMax(1, notif.value("deadlineLeadHours", 24).toInt());
        for (const Task &t : m_tasks.items()) {
            if (t.archived) continue;
            if (!t.deadline.isValid()) continue;
            if (t.status == QStringLiteral("done")) continue;
            const QDateTime deadlineAt(t.deadline, QTime(23, 59));
            const qint64 hoursLeft = now.secsTo(deadlineAt) / 3600;
            if (hoursLeft < 0 || hoursLeft > leadHours) continue;
            const QString sentinel = QStringLiteral("dl:") + t.id;
            if (m_lastReminderDay.value(sentinel) == today) continue;
            m_lastReminderDay[sentinel] = today;
            const QString when = (hoursLeft <= 1)
                ? QStringLiteral("через час")
                : QStringLiteral("через %1 ч").arg(hoursLeft);
            notify(QStringLiteral("Дедлайн %1").arg(when),
                   QStringLiteral("%1 (%2)").arg(t.title, t.priority),
                   QStringLiteral("deadline"));
        }
    }

    // 4. Standup reminder.
    if (notif.value("standupReminder", true).toBool()) {
        const QVariantMap cal = s.value("calendar").toMap();
        const QTime standup = QTime::fromString(cal.value("standupTime", "10:00").toString(), "HH:mm");
        const int lead = qMax(0, notif.value("meetingLead", 5).toInt());
        if (standup.isValid()) {
            const QDateTime atDt(today, standup);
            const qint64 minsLeft = now.secsTo(atDt) / 60;
            if (minsLeft >= 0 && minsLeft <= lead) {
                const QString sentinel = QStringLiteral("standup:%1").arg(today.toString(Qt::ISODate));
                if (m_lastReminderDay.value(sentinel) != today) {
                    m_lastReminderDay[sentinel] = today;
                    notify(QStringLiteral("Standup скоро"),
                           QStringLiteral("Через %1 мин").arg(minsLeft),
                           QStringLiteral("standup"));
                }
            }
        }
    }
}
