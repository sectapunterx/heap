#pragma once

#include <QHash>
#include <QJsonArray>
#include <QJsonObject>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QUuid>
#include <QVariantMap>
#include <QVector>

// Saved views: a named snapshot of how the user is looking at tasks.
//
// A view holds exactly what the filter state in settings.app.filters holds
// (TASKS-22) — the search box text, the priority chips, the board's sort, the
// Archived toggle, the timeline's "Show done" — plus the view it opens in. It
// stores the query as typed, not a compiled form: a view that names a column
// keeps meaning the column by that name, and one whose column was deleted says
// so through the same problem list the search box shows.
//
// Views belong to a workspace, so they live on the profile (`savedViews` in the
// profile object, optional — a profile written before this simply has none)
// and travel with a profile export.
namespace heap::savedviews {

struct SavedView {
  QString id;
  QString name;
  QString query;           // the search box text, whitespace-collapsed
  QStringList priorities;  // the chips that are on, "P0".."P3", in order
  QString sort = QStringLiteral("manual");
  bool archived = false;  // the filter bar's Archived toggle
  bool showDone = false;  // the timeline's Show done
  QString view = QStringLiteral("board");

  bool operator==(const SavedView& o) const = default;
};

// ── Declarations with their docs; definitions follow. ──
// The views a saved view may open in: every one that shows tasks through the
// shared filters. Anything else read from a file becomes "board".
const QStringList& taskViews();
bool isTaskView(const QString& view);

// One spelling per filter state, so "is the view modified?" is not fooled by
// a trailing space, chips toggled in a different order or a sort mode that
// was never set.
QString normalizeQuery(const QString& q);
QStringList normalizePriorities(const QStringList& ps);
QString normalizeSort(const QString& s);
QString normalizeView(const QString& v);

// The filter state QML hands over ({query, priorities, sort, archived,
// showDone, view}) as a view with no id or name, normalized.
SavedView fromState(const QVariantMap& state);
// A view as QML reads it (every field, `priorities` as a list).
QVariantMap toVariant(const SavedView& v);

// Same filters, whatever the id and name.
bool sameFilters(const SavedView& a, const SavedView& b);

QJsonObject toJson(const SavedView& v);
SavedView fromJson(const QJsonObject& o);
QJsonArray listToJson(const QVector<SavedView>& views);
// Entries without an id or a name are dropped, as are repeated ids.
QVector<SavedView> listFromJson(const QJsonArray& a);

// `name`, or "name (2)", "name (3)"… — the first one no other view (other than
// `exceptId`) is called, compared case-insensitively.
QString uniqueName(const QVector<SavedView>& views, const QString& name, const QString& exceptId = {});
QString makeId(const QVector<SavedView>& views);
int indexOf(const QVector<SavedView>& views, const QString& id);

// The starter views a brand-new profile gets. Seeded once, when the profile is
// made, and never again: deleting them is a choice that sticks.
QVector<SavedView> starterViews(bool ru);

// This feature's own strings (toasts, undo labels, the shortcut catalog's
// "Apply saved view N"). AppController::tr_ falls back to it. Null when the
// key is not one of them.
QString text(const QString& key, bool ru);

// ── Definitions ──

inline const QStringList& taskViews() {
  static const QStringList v = {
      QStringLiteral("board"), QStringLiteral("timeline"), QStringLiteral("week"), QStringLiteral("month"), QStringLiteral("archive")};
  return v;
}

inline bool isTaskView(const QString& view) {
  return taskViews().contains(view);
}

inline QString normalizeQuery(const QString& q) {
  return q.simplified();
}

inline QStringList normalizePriorities(const QStringList& ps) {
  static const QStringList kOrder = {QStringLiteral("P0"), QStringLiteral("P1"), QStringLiteral("P2"), QStringLiteral("P3")};
  QStringList out;
  for(const QString& p : kOrder) {
    for(const QString& given : ps) {
      if(given.trimmed().compare(p, Qt::CaseInsensitive) == 0) {
        out << p;
        break;
      }
    }
  }
  return out;
}

inline QString normalizeSort(const QString& s) {
  static const QStringList kModes = {
      QStringLiteral("manual"), QStringLiteral("priority"), QStringLiteral("due"), QStringLiteral("updated"), QStringLiteral("title")};
  return kModes.contains(s) ? s : QStringLiteral("manual");
}

inline QString normalizeView(const QString& v) {
  return isTaskView(v) ? v : QStringLiteral("board");
}

inline SavedView fromState(const QVariantMap& state) {
  SavedView v;
  v.query = normalizeQuery(state.value(QStringLiteral("query")).toString());
  // Either a list of the chips that are on or the window's {P0: true} map.
  const QVariant pri = state.value(QStringLiteral("priorities"));
  QStringList ps;
  if(pri.typeId() == QMetaType::QVariantMap) {
    const QVariantMap m = pri.toMap();
    for(auto it = m.constBegin(); it != m.constEnd(); ++it) {
      if(it.value().toBool()) {
        ps << it.key();
      }
    }
  } else {
    ps = pri.toStringList();
  }
  v.priorities = normalizePriorities(ps);
  v.sort = normalizeSort(state.value(QStringLiteral("sort")).toString());
  v.archived = state.value(QStringLiteral("archived")).toBool();
  v.showDone = state.value(QStringLiteral("showDone")).toBool();
  v.view = normalizeView(state.value(QStringLiteral("view")).toString());
  return v;
}

inline QVariantMap toVariant(const SavedView& v) {
  return {{QStringLiteral("id"), v.id},
          {QStringLiteral("name"), v.name},
          {QStringLiteral("query"), v.query},
          {QStringLiteral("priorities"), v.priorities},
          {QStringLiteral("sort"), v.sort},
          {QStringLiteral("archived"), v.archived},
          {QStringLiteral("showDone"), v.showDone},
          {QStringLiteral("view"), v.view}};
}

inline bool sameFilters(const SavedView& a, const SavedView& b) {
  return normalizeQuery(a.query) == normalizeQuery(b.query) && normalizePriorities(a.priorities) == normalizePriorities(b.priorities) &&
         normalizeSort(a.sort) == normalizeSort(b.sort) && a.archived == b.archived && a.showDone == b.showDone &&
         normalizeView(a.view) == normalizeView(b.view);
}

inline QJsonObject toJson(const SavedView& v) {
  QJsonObject o;
  o[QStringLiteral("id")] = v.id;
  o[QStringLiteral("name")] = v.name;
  o[QStringLiteral("query")] = v.query;
  o[QStringLiteral("priorities")] = QJsonArray::fromStringList(v.priorities);
  o[QStringLiteral("sort")] = v.sort;
  o[QStringLiteral("archived")] = v.archived;
  o[QStringLiteral("showDone")] = v.showDone;
  o[QStringLiteral("view")] = v.view;
  return o;
}

inline SavedView fromJson(const QJsonObject& o) {
  SavedView v;
  v.id = o.value(QStringLiteral("id")).toString().trimmed();
  v.name = o.value(QStringLiteral("name")).toString().trimmed();
  v.query = normalizeQuery(o.value(QStringLiteral("query")).toString());
  QStringList ps;
  for(const QJsonValue& p : o.value(QStringLiteral("priorities")).toArray()) {
    ps << p.toString();
  }
  v.priorities = normalizePriorities(ps);
  v.sort = normalizeSort(o.value(QStringLiteral("sort")).toString());
  v.archived = o.value(QStringLiteral("archived")).toBool();
  v.showDone = o.value(QStringLiteral("showDone")).toBool();
  v.view = normalizeView(o.value(QStringLiteral("view")).toString());
  return v;
}

inline QJsonArray listToJson(const QVector<SavedView>& views) {
  QJsonArray a;
  for(const SavedView& v : views) {
    a.append(toJson(v));
  }
  return a;
}

inline QVector<SavedView> listFromJson(const QJsonArray& a) {
  QVector<SavedView> out;
  QSet<QString> seen;
  for(const QJsonValue& it : a) {
    if(!it.isObject()) {
      continue;
    }
    const SavedView v = fromJson(it.toObject());
    if(v.id.isEmpty() || v.name.isEmpty() || seen.contains(v.id)) {
      continue;
    }
    seen.insert(v.id);
    out.append(v);
  }
  return out;
}

namespace detail {
inline bool nameTaken(const QVector<SavedView>& views, const QString& name, const QString& exceptId) {
  for(const SavedView& v : views) {
    if(v.id != exceptId && v.name.compare(name, Qt::CaseInsensitive) == 0) {
      return true;
    }
  }
  return false;
}
}  // namespace detail

inline QString uniqueName(const QVector<SavedView>& views, const QString& name, const QString& exceptId) {
  const QString base = name.simplified();
  if(!detail::nameTaken(views, base, exceptId)) {
    return base;
  }
  for(int n = 2;; ++n) {
    const QString candidate = QStringLiteral("%1 (%2)").arg(base).arg(n);
    if(!detail::nameTaken(views, candidate, exceptId)) {
      return candidate;
    }
  }
}

inline int indexOf(const QVector<SavedView>& views, const QString& id) {
  for(int i = 0; i < views.size(); ++i) {
    if(views.at(i).id == id) {
      return i;
    }
  }
  return -1;
}

inline QString makeId(const QVector<SavedView>& views) {
  for(;;) {
    const QString id = QStringLiteral("view-") + QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
    if(indexOf(views, id) < 0) {
      return id;
    }
  }
}

inline QVector<SavedView> starterViews(bool ru) {
  // Three that answer a question a board alone does not: what is on fire,
  // what is due before the weekend, what slipped. "Blocked" is not one of
  // them — the sidebar's Focus section already jumps to that column.
  SavedView urgent;
  urgent.id = QStringLiteral("view-urgent");
  urgent.name = text(QStringLiteral("savedview.starter.urgent"), ru);
  urgent.query = QStringLiteral("priority:P0,P1 is:open");

  SavedView week;
  week.id = QStringLiteral("view-due-week");
  week.name = text(QStringLiteral("savedview.starter.dueWeek"), ru);
  week.query = QStringLiteral("due:week is:open");
  week.sort = QStringLiteral("due");

  SavedView overdue;
  overdue.id = QStringLiteral("view-overdue");
  overdue.name = text(QStringLiteral("savedview.starter.overdue"), ru);
  overdue.query = QStringLiteral("is:overdue");
  overdue.sort = QStringLiteral("due");
  return {urgent, week, overdue};
}

inline QString text(const QString& key, bool ru) {
  struct Pair {
    const char* en;
    const char* ru;
  };

  static const QHash<QString, Pair> kTable = {
      {QStringLiteral("savedview.defaultName"), {"View %1", "Вид %1"}},
      {QStringLiteral("savedview.starter.urgent"), {"Urgent", "Срочное"}},
      {QStringLiteral("savedview.starter.dueWeek"), {"Due this week", "Срок на этой неделе"}},
      {QStringLiteral("savedview.starter.overdue"), {"Overdue", "Просрочено"}},
      {QStringLiteral("savedview.saved"), {"View saved: %1", "Вид сохранён: %1"}},
      {QStringLiteral("savedview.updated"), {"View updated: %1", "Вид обновлён: %1"}},
      {QStringLiteral("savedview.renamed"), {"View renamed: %1", "Вид переименован: %1"}},
      {QStringLiteral("savedview.duplicated"), {"View copied: %1", "Вид скопирован: %1"}},
      {QStringLiteral("savedview.deleted"), {"View deleted: %1", "Вид удалён: %1"}},
      {QStringLiteral("savedview.moved"), {"View moved: %1", "Вид перемещён: %1"}},
      {QStringLiteral("savedview.undo.create"), {"Saving the view undone: %1", "Сохранение вида отменено: %1"}},
      {QStringLiteral("savedview.undo.update"), {"View update undone: %1", "Обновление вида отменено: %1"}},
      {QStringLiteral("savedview.undo.rename"), {"Rename undone: %1", "Переименование отменено: %1"}},
      {QStringLiteral("savedview.undo.duplicate"), {"Copy removed: %1", "Копия удалена: %1"}},
      {QStringLiteral("savedview.undo.delete"), {"View restored: %1", "Вид восстановлен: %1"}},
      {QStringLiteral("savedview.undo.move"), {"Move undone: %1", "Перемещение отменено: %1"}},
      {QStringLiteral("savedview.copySuffix"), {"%1 copy", "%1 — копия"}},
  };
  const auto it = kTable.constFind(key);
  if(it != kTable.constEnd()) {
    return QString::fromUtf8(ru ? it->ru : it->en);
  }
  // The shortcut catalog: shortcut.savedView.<n>.label / .desc.
  static const QString kPrefix = QStringLiteral("shortcut.savedView.");
  if(key.startsWith(kPrefix)) {
    const QStringList parts = key.mid(kPrefix.size()).split(QLatin1Char('.'));
    bool ok = false;
    const int n = parts.value(0).toInt(&ok);
    if(ok && n >= 1 && n <= 9 && parts.size() == 2) {
      if(parts.at(1) == QLatin1String("label")) {
        return (ru ? QStringLiteral("Сохранённый вид %1") : QStringLiteral("Saved view %1")).arg(n);
      }
      if(parts.at(1) == QLatin1String("desc")) {
        return (ru ? QStringLiteral("Применить %1-й вид из раздела «Виды» на боковой панели")
                   : QStringLiteral("Apply view number %1 in the sidebar's Saved views"))
            .arg(n);
      }
    }
  }
  return {};
}

}  // namespace heap::savedviews
