#include "integrations/StatusMap.h"

namespace heap::integrations {

namespace {

QString norm(const QString& s) {
  return s.trimmed().toLower();
}

}  // namespace

QString StatusMap::defaultColumn(const QString& providerStatus) {
  static const QHash<QString, QString> kTable = {
      // backlog
      {QStringLiteral("backlog"), QStringLiteral("backlog")},
      // todo
      {QStringLiteral("to do"), QStringLiteral("todo")},
      {QStringLiteral("todo"), QStringLiteral("todo")},
      {QStringLiteral("open"), QStringLiteral("todo")},
      {QStringLiteral("reopened"), QStringLiteral("todo")},
      {QStringLiteral("selected for development"), QStringLiteral("todo")},
      // in progress
      {QStringLiteral("in progress"), QStringLiteral("prog")},
      {QStringLiteral("in development"), QStringLiteral("prog")},
      {QStringLiteral("doing"), QStringLiteral("prog")},
      {QStringLiteral("started"), QStringLiteral("prog")},
      // review
      {QStringLiteral("in review"), QStringLiteral("review")},
      {QStringLiteral("review"), QStringLiteral("review")},
      {QStringLiteral("code review"), QStringLiteral("review")},
      {QStringLiteral("in code review"), QStringLiteral("review")},
      // blocked
      {QStringLiteral("blocked"), QStringLiteral("blocked")},
      {QStringLiteral("impediment"), QStringLiteral("blocked")},
      {QStringLiteral("on hold"), QStringLiteral("blocked")},
      // done
      {QStringLiteral("done"), QStringLiteral("done")},
      {QStringLiteral("closed"), QStringLiteral("done")},
      {QStringLiteral("resolved"), QStringLiteral("done")},
      {QStringLiteral("complete"), QStringLiteral("done")},
      {QStringLiteral("completed"), QStringLiteral("done")},
      {QStringLiteral("merged"), QStringLiteral("done")},
  };
  return kTable.value(norm(providerStatus));
}

QString StatusMap::column(const QString& providerStatus, const QHash<QString, QString>& overrides, const QString& fallback) {
  const QString key = norm(providerStatus);
  // User overrides win. Match case-insensitively against normalized keys.
  for(auto it = overrides.constBegin(); it != overrides.constEnd(); ++it) {
    if(norm(it.key()) == key) {
      return it.value();
    }
  }
  const QString built = defaultColumn(providerStatus);
  return built.isEmpty() ? fallback : built;
}

QString StatusMap::priority(const QString& providerPriority, const QString& fallback) {
  static const QHash<QString, QString> kTable = {
      {QStringLiteral("highest"), QStringLiteral("P0")},
      {QStringLiteral("critical"), QStringLiteral("P0")},
      {QStringLiteral("blocker"), QStringLiteral("P0")},
      {QStringLiteral("high"), QStringLiteral("P1")},
      {QStringLiteral("major"), QStringLiteral("P1")},
      {QStringLiteral("medium"), QStringLiteral("P2")},
      {QStringLiteral("normal"), QStringLiteral("P2")},
      {QStringLiteral("low"), QStringLiteral("P3")},
      {QStringLiteral("lowest"), QStringLiteral("P3")},
      {QStringLiteral("minor"), QStringLiteral("P3")},
      {QStringLiteral("trivial"), QStringLiteral("P3")},
  };
  return kTable.value(norm(providerPriority), fallback);
}

}  // namespace heap::integrations
