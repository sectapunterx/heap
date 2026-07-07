#include "integrations/GithubProvider.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace heap::integrations {

QString githubStateForColumn(const QString& column) {
  return column == QStringLiteral("done") ? QStringLiteral("closed") : QStringLiteral("open");
}

QVector<ExternalTask> parseGithubIssues(const QByteArray& json) {
  QVector<ExternalTask> out;
  const QJsonDocument doc = QJsonDocument::fromJson(json);
  if(!doc.isArray()) {
    return out;
  }
  const QJsonArray arr = doc.array();
  out.reserve(arr.size());
  for(const auto& v : arr) {
    const QJsonObject o = v.toObject();
    // The issues endpoint also lists pull requests; skip them.
    if(o.contains(QStringLiteral("pull_request"))) {
      continue;
    }
    ExternalTask t;
    t.providerId = QStringLiteral("github");
    t.externalId = QString::number(static_cast<qlonglong>(o.value(QStringLiteral("number")).toDouble()));
    t.url = o.value(QStringLiteral("html_url")).toString();
    t.title = o.value(QStringLiteral("title")).toString();
    t.body = o.value(QStringLiteral("body")).toString();
    t.status = o.value(QStringLiteral("state")).toString();  // "open" | "closed"
    t.updatedAt = QDateTime::fromString(o.value(QStringLiteral("updated_at")).toString(), Qt::ISODate);
    for(const auto& lv : o.value(QStringLiteral("labels")).toArray()) {
      const QString name = lv.toObject().value(QStringLiteral("name")).toString();
      if(name.isEmpty()) {
        continue;
      }
      t.labels.append(name);
      // A "priority: high" style label feeds the priority column via StatusMap.
      if(name.startsWith(QStringLiteral("priority:"), Qt::CaseInsensitive)) {
        t.priority = name.mid(name.indexOf(':') + 1).trimmed();
      }
    }
    out.append(t);
  }
  return out;
}

}  // namespace heap::integrations
