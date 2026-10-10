// Saved views: named snapshots of the task filters, per profile. The views
// themselves are plain data (views/SavedView.h); this is the part that owns the
// active profile's list — undo, toasts, the count badges. Applying a view is
// Main.qml's business: the filters it restores live on the window.

#include "AppController.h"

#include "views/SavedViewMatch.h"

using heap::savedviews::SavedView;

void AppController::wireSavedViews() {
  // The badges follow whatever changes what a view would show: the tasks
  // (statusCountsChanged is already raised from every task model signal), the
  // columns a `status:` clause resolves against, and the day `due:today` means.
  m_savedViewCountsTimer.setSingleShot(true);
  m_savedViewCountsTimer.setInterval(0);
  connect(&m_savedViewCountsTimer, &QTimer::timeout, this, &AppController::savedViewCountsChanged);
  connect(this, &AppController::statusCountsChanged, this, &AppController::dropSavedViewCounts);
  connect(this, &AppController::todayChanged, this, &AppController::dropSavedViewCounts);
  // A column renamed or deleted changes what a view's query means, and which
  // of its clauses the problem badge names.
  connect(this, &AppController::statusesChanged, this, [this]() {
    dropSavedViewCounts();
    emit savedViewsChanged();
  });
}

void AppController::dropSavedViewCounts() {
  m_savedViewCountsDirty = true;
  // A bulk edit raises the model's signals row by row; the badges are read
  // once, after it.
  m_savedViewCountsTimer.start();
}

void AppController::setSavedViews(const QVector<SavedView>& views) {
  if(views == m_savedViews) {
    return;
  }
  m_savedViews = views;
  emit savedViewsChanged();
  dropSavedViewCounts();
}

QVariantList AppController::savedViews() const {
  QVariantList out;
  out.reserve(m_savedViews.size());
  for(const SavedView& v : m_savedViews) {
    QVariantMap m = heap::savedviews::toVariant(v);
    m[QStringLiteral("name")] = heap::savedviews::displayName(v, m_language == QStringLiteral("ru"));
    m[QStringLiteral("problems")] = heap::query::TaskQuery::compile(v.query, m_today, m_statuses).unknownClauses();
    out.append(m);
  }
  return out;
}

QVariantMap AppController::savedViewCounts() const {
  if(!m_savedViewCountsDirty) {
    return m_savedViewCounts;
  }
  m_savedViewCounts.clear();
  const QHash<QString, int> counts = heap::savedviews::countMatches(m_savedViews, m_tasks, m_today, m_statuses);
  for(auto it = counts.constBegin(); it != counts.constEnd(); ++it) {
    m_savedViewCounts.insert(it.key(), it.value());
  }
  m_savedViewCountsDirty = false;
  return m_savedViewCounts;
}

QString AppController::saveView(const QString& name, const QVariantMap& state) {
  if(profileIndexOf(m_activeProfileId) < 0) {
    return {};
  }
  SavedView v = heap::savedviews::fromState(state);
  QString wanted = name.simplified();
  if(wanted.isEmpty()) {
    wanted = tr_(QStringLiteral("savedview.defaultName")).arg(m_savedViews.size() + 1);
  }
  v.id = heap::savedviews::makeId(m_savedViews);
  v.name = heap::savedviews::uniqueName(m_savedViews, wanted);
  {
    const UndoScope scope(this, tr_(QStringLiteral("savedview.undo.create")).arg(v.name));
    QVector<SavedView> next = m_savedViews;
    next.append(v);
    setSavedViews(next);
  }
  scheduleSave();
  emit undoableToast(tr_(QStringLiteral("savedview.saved")).arg(v.name), 5);
  return v.id;
}

bool AppController::renameSavedView(const QString& id, const QString& name) {
  const int i = heap::savedviews::indexOf(m_savedViews, id);
  const QString wanted = name.simplified();
  if(i < 0 || wanted.isEmpty()) {
    return false;
  }
  const QString unique = heap::savedviews::uniqueName(m_savedViews, wanted, id);
  if(unique == m_savedViews.at(i).name) {
    return false;
  }
  const QString before = m_savedViews.at(i).name;
  {
    const UndoScope scope(this, tr_(QStringLiteral("savedview.undo.rename")).arg(before));
    QVector<SavedView> next = m_savedViews;
    next[i].name = unique;
    setSavedViews(next);
  }
  scheduleSave();
  emit undoableToast(tr_(QStringLiteral("savedview.renamed")).arg(unique), 5);
  return true;
}

bool AppController::updateSavedView(const QString& id, const QVariantMap& state) {
  const int i = heap::savedviews::indexOf(m_savedViews, id);
  if(i < 0) {
    return false;
  }
  SavedView v = heap::savedviews::fromState(state);
  v.id = m_savedViews.at(i).id;
  v.name = m_savedViews.at(i).name;
  if(v == m_savedViews.at(i)) {
    return false;
  }
  {
    const UndoScope scope(this, tr_(QStringLiteral("savedview.undo.update")).arg(v.name));
    QVector<SavedView> next = m_savedViews;
    next[i] = v;
    setSavedViews(next);
  }
  scheduleSave();
  emit undoableToast(tr_(QStringLiteral("savedview.updated")).arg(v.name), 5);
  return true;
}

QString AppController::duplicateSavedView(const QString& id) {
  const int i = heap::savedviews::indexOf(m_savedViews, id);
  if(i < 0) {
    return {};
  }
  SavedView copy = m_savedViews.at(i);
  copy.id = heap::savedviews::makeId(m_savedViews);
  copy.name = heap::savedviews::uniqueName(m_savedViews, tr_(QStringLiteral("savedview.copySuffix")).arg(copy.name));
  {
    const UndoScope scope(this, tr_(QStringLiteral("savedview.undo.duplicate")).arg(copy.name));
    QVector<SavedView> next = m_savedViews;
    next.insert(i + 1, copy);  // next to the original, where the eye is
    setSavedViews(next);
  }
  scheduleSave();
  emit undoableToast(tr_(QStringLiteral("savedview.duplicated")).arg(copy.name), 5);
  return copy.id;
}

bool AppController::deleteSavedView(const QString& id) {
  const int i = heap::savedviews::indexOf(m_savedViews, id);
  if(i < 0) {
    return false;
  }
  const QString name = m_savedViews.at(i).name;
  {
    const UndoScope scope(this, tr_(QStringLiteral("savedview.undo.delete")).arg(name));
    QVector<SavedView> next = m_savedViews;
    next.removeAt(i);
    setSavedViews(next);
  }
  scheduleSave();
  emit undoableToast(tr_(QStringLiteral("savedview.deleted")).arg(name), 8);
  return true;
}

bool AppController::moveSavedView(const QString& id, int delta) {
  // Any distance: a drag in the sidebar lands a view several rows away in
  // one move, and one undo (APP-258). Clamped to the list.
  const int i = heap::savedviews::indexOf(m_savedViews, id);
  const int to = qBound(0, i + delta, static_cast<int>(m_savedViews.size()) - 1);
  if(i < 0 || delta == 0 || to == i) {
    return false;
  }
  const QString name = m_savedViews.at(i).name;
  {
    const UndoScope scope(this, tr_(QStringLiteral("savedview.undo.move")).arg(name));
    QVector<SavedView> next = m_savedViews;
    next.move(i, to);
    setSavedViews(next);
  }
  scheduleSave();
  emit undoableToast(tr_(QStringLiteral("savedview.moved")).arg(name), 5);
  return true;
}

QVariantMap AppController::savedView(const QString& id) const {
  const int i = heap::savedviews::indexOf(m_savedViews, id);
  return i < 0 ? QVariantMap{} : heap::savedviews::toVariant(m_savedViews.at(i));
}

bool AppController::savedViewDiffers(const QString& id, const QVariantMap& state) const {
  const int i = heap::savedviews::indexOf(m_savedViews, id);
  if(i < 0) {
    return true;
  }
  return !heap::savedviews::sameFilters(m_savedViews.at(i), heap::savedviews::fromState(state));
}
