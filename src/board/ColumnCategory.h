#pragma once

#include <QSet>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

// A column's stage (APP-259): what kind of work sits in it, independent of
// its name and colour. It decides the shape of the status mark (StatusRing)
// and where "Done" (d) sends a task. The seven stages are the seven built-in
// columns; a column of the user's own picks one (by default "todo") and is
// never guessed from its name.
namespace heap::board {

inline const QStringList& columnCategories() {
  static const QStringList kCategories = {QStringLiteral("backlog"),
                                          QStringLiteral("todo"),
                                          QStringLiteral("prog"),
                                          QStringLiteral("half"),
                                          QStringLiteral("blocked"),
                                          QStringLiteral("review"),
                                          QStringLiteral("done")};
  return kCategories;
}

inline bool isColumnCategory(const QString& category) {
  return columnCategories().contains(category);
}

// A built-in column's own stage; any other column starts at "todo".
inline QString defaultCategoryFor(const QString& column_id) {
  return isColumnCategory(column_id) ? column_id : QStringLiteral("todo");
}

// The ids of a board's columns of the Done kind ([{id, category}]). "done"
// counts unless the board gives that id another stage, so a task left on a
// deleted Done column, or a board that names no columns, still reads as
// finished. A user's "Shipped" column of the Done kind counts too
// (IDIOT-CAL-4): "done" was a literal column id in too many places.
inline QSet<QString> doneColumnIds(const QVariantList& statuses) {
  QSet<QString> out{QStringLiteral("done")};
  for(const QVariant& v : statuses) {
    const QVariantMap m = v.toMap();
    const QString id = m.value(QStringLiteral("id")).toString();
    const QString c = m.value(QStringLiteral("category")).toString();
    if((isColumnCategory(c) ? c : defaultCategoryFor(id)) == QStringLiteral("done")) {
      out.insert(id);
    } else {
      out.remove(id);
    }
  }
  return out;
}

}  // namespace heap::board
