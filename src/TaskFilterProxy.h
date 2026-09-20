#pragma once

#include "Models.h"

#include <QQmlEngine>
#include <QSortFilterProxyModel>
#include <QString>
#include <QStringList>

// One board column's view of the task model.
//
// The board used to give every status column the whole task model and let each
// card hide itself with `visible:` — so a profile with N tasks and C columns
// built N×C card delegates, each one a full component tree, and every card
// re-ran the filter in JS. Measured at 300 tasks and 7 columns: 3416 delegates.
//
// A proxy per column instantiates only the cards that belong to it. Roles pass
// through untouched, so the delegate keeps its named `required property`
// bindings and its live updates.
class TaskFilterProxy : public QSortFilterProxyModel {
  Q_OBJECT
  QML_ELEMENT

  // The column this proxy belongs to. Empty shows every status.
  Q_PROPERTY(QString status READ status WRITE setStatus NOTIFY filterChanged)
  Q_PROPERTY(bool showArchived READ showArchived WRITE setShowArchived NOTIFY filterChanged)
  // Matched against the model's prebuilt lowercase haystack.
  Q_PROPERTY(QString searchText READ searchText WRITE setSearchText NOTIFY filterChanged)
  // The priorities the filter bar has switched on ("P0", "P1", …). Empty means
  // no priority filter, which is not the same as "none pass".
  Q_PROPERTY(QStringList priorities READ priorities WRITE setPriorities NOTIFY filterChanged)
  // Row count after filtering — what the column header badge shows.
  Q_PROPERTY(int count READ count NOTIFY countChanged)

 public:
  explicit TaskFilterProxy(QObject* parent = nullptr);

  QString status() const {
    return m_status;
  }

  void setStatus(const QString& v);

  bool showArchived() const {
    return m_showArchived;
  }

  void setShowArchived(bool v);

  QString searchText() const {
    return m_searchText;
  }

  void setSearchText(const QString& v);

  QStringList priorities() const {
    return m_priorities;
  }

  void setPriorities(const QStringList& v);

  int count() const {
    return rowCount();
  }

 signals:
  void filterChanged();
  void countChanged();

 protected:
  bool filterAcceptsRow(int sourceRow, const QModelIndex& sourceParent) const override;

 private:
  QString m_status;
  bool m_showArchived = false;
  QString m_searchText;  // kept lowercased
  QStringList m_priorities;
};
