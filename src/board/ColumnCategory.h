#pragma once

#include <QString>
#include <QStringList>

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

}  // namespace heap::board
