#pragma once

#include <QRegularExpression>
#include <QString>
#include <QStringList>

namespace heap::people {

// Whether a meeting's free-form attendees line ("Олег Т.", "Андрей, Виктор",
// "@o.t") names a person (DG-002: "Встречи" in the people dialog). A fact
// read off what the user typed, nothing guessed past it: a name in full, the
// person's handle, or the first name alone when the line gives no surname
// ("Андрей" names "Андрей Б."). A different surname initial is someone else.
inline bool attendeesName(const QString& attendees, const QString& name, const QString& handle) {
  const QString full = name.simplified().toLower();
  if(full.isEmpty() && handle.isEmpty()) {
    return false;
  }
  const QStringList nameWords = full.split(QLatin1Char(' '), Qt::SkipEmptyParts);
  static const QRegularExpression sep(QStringLiteral("[,;/\\n]"));
  const QStringList tokens = attendees.split(sep, Qt::SkipEmptyParts);
  for(const QString& raw : tokens) {
    const QString token = raw.simplified().toLower();
    if(token.isEmpty()) {
      continue;
    }
    if(!handle.isEmpty() && (token == handle.toLower() || token == QLatin1Char('@') + handle.toLower())) {
      return true;
    }
    if(full.isEmpty()) {
      continue;
    }
    if(token == full) {
      return true;
    }
    const QStringList words = token.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    if(words.isEmpty() || nameWords.isEmpty() || words.first() != nameWords.first() || nameWords.first().size() < 2) {
      continue;
    }
    if(words.size() == 1) {
      return true;
    }
    if(nameWords.size() > 1 && words.at(1).at(0) == nameWords.at(1).at(0)) {
      return true;
    }
  }
  return false;
}

}  // namespace heap::people
