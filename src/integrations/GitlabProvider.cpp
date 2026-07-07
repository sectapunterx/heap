#include "integrations/GitlabProvider.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace heap::integrations {

QString gitlabStateEventForColumn(const QString& column) {
  return column == QStringLiteral("done") ? QStringLiteral("close") : QStringLiteral("reopen");
}

QVector<ExternalTask> parseGitlabIssues(const QByteArray& json) {
  QVector<ExternalTask> out;
  const QJsonDocument doc = QJsonDocument::fromJson(json);
  if(!doc.isArray()) {
    return out;
  }
  const QJsonArray arr = doc.array();
  out.reserve(arr.size());
  for(const auto& v : arr) {
    const QJsonObject o = v.toObject();
    ExternalTask t;
    t.providerId = QStringLiteral("gitlab");
    t.externalId = QString::number(static_cast<qlonglong>(o.value(QStringLiteral("iid")).toDouble()));
    t.url = o.value(QStringLiteral("web_url")).toString();
    t.title = o.value(QStringLiteral("title")).toString();
    t.body = o.value(QStringLiteral("description")).toString();
    // GitLab state is "opened" | "closed"; StatusMap folds both onto columns.
    t.status = o.value(QStringLiteral("state")).toString();
    t.updatedAt = QDateTime::fromString(o.value(QStringLiteral("updated_at")).toString(), Qt::ISODate);
    // GitLab labels are plain strings. A "priority::high" (scoped) or
    // "priority: high" label feeds the priority column via StatusMap.
    for(const auto& lv : o.value(QStringLiteral("labels")).toArray()) {
      const QString name = lv.toString();
      if(name.isEmpty()) {
        continue;
      }
      t.labels.append(name);
      if(name.startsWith(QStringLiteral("priority"), Qt::CaseInsensitive)) {
        const int sep = name.lastIndexOf(':');
        if(sep >= 0) {
          t.priority = name.mid(sep + 1).trimmed();
        }
      }
    }
    out.append(t);
  }
  return out;
}

}  // namespace heap::integrations
