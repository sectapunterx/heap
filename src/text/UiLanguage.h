#pragma once

#include <QString>
#include <QStringList>

namespace heap::text {

// The UI language a fresh install starts in, from the system's preferred UI
// languages (QLocale::system().uiLanguages(), most preferred first). heap
// speaks English and Russian; the first of those the system lists wins, and
// anything else falls back to English. A ru-RU Windows used to get an
// English welcome.
inline QString uiLanguageFor(const QStringList& uiLanguages) {
  for(const QString& raw : uiLanguages) {
    const QString l = raw.trimmed().toLower();
    if(l == QStringLiteral("ru") || l.startsWith(QStringLiteral("ru-")) || l.startsWith(QStringLiteral("ru_"))) {
      return QStringLiteral("ru");
    }
    if(l == QStringLiteral("en") || l.startsWith(QStringLiteral("en-")) || l.startsWith(QStringLiteral("en_"))) {
      return QStringLiteral("en");
    }
  }
  return QStringLiteral("en");
}

}  // namespace heap::text
