#include "integrations/GitlabProvider.h"
#include "integrations/TrackerFields.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace heap::integrations {

namespace {

// "acme/web#42" → "acme/web". references.full is the only field that names the
// project in both the scoped and the assigned-to-me pull; web_url works as a
// fallback for an older GitLab that omits it.
QString projectFromIssue(const QJsonObject& o) {
  const QString full = o.value(QStringLiteral("references")).toObject().value(QStringLiteral("full")).toString();
  const int hash = full.indexOf(QChar('#'));
  if(hash > 0) {
    return full.left(hash);
  }
  const QString web = o.value(QStringLiteral("web_url")).toString();
  const int issues = web.indexOf(QStringLiteral("/-/issues"));
  if(issues < 0) {
    return {};
  }
  // Drop the scheme+host, keep the namespace path.
  const int slashAfterHost = web.indexOf(QChar('/'), web.indexOf(QStringLiteral("//")) + 2);
  if(slashAfterHost < 0 || slashAfterHost >= issues) {
    return {};
  }
  return web.mid(slashAfterHost + 1, issues - slashAfterHost - 1);
}

}  // namespace

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
    t.updatedAt = parseTrackerTimestamp(o.value(QStringLiteral("updated_at")));
    t.createdAt = parseTrackerTimestamp(o.value(QStringLiteral("created_at")));
    t.dueAt = parseTrackerTimestamp(o.value(QStringLiteral("due_date")), &t.dueHasTime);
    t.assignee = joinObjectField(o.value(QStringLiteral("assignees")), QStringLiteral("username"));
    if(t.assignee.isEmpty()) {
      t.assignee = o.value(QStringLiteral("assignee")).toObject().value(QStringLiteral("username")).toString();
    }
    t.author = o.value(QStringLiteral("author")).toObject().value(QStringLiteral("username")).toString();
    t.commentCount = o.value(QStringLiteral("user_notes_count")).isDouble() ? o.value(QStringLiteral("user_notes_count")).toInt(-1) : -1;
    t.issueType = o.value(QStringLiteral("issue_type")).toString();
    t.project = sanitizeProject(projectFromIssue(o));
    t.milestone = o.value(QStringLiteral("milestone")).toObject().value(QStringLiteral("title")).toString();
    // GitLab labels are plain strings, or {name, color} objects when the list
    // was requested with_labels_details. A "priority::high" (scoped) or
    // "priority: high" label feeds the priority column via StatusMap.
    for(const auto& lv : o.value(QStringLiteral("labels")).toArray()) {
      QString name = lv.toString();
      if(lv.isObject()) {
        const QJsonObject lo = lv.toObject();
        name = lo.value(QStringLiteral("name")).toString();
        const QString color = normalizeHexColor(lo.value(QStringLiteral("color")).toString());
        if(!name.isEmpty() && !color.isEmpty()) {
          t.labelColors.insert(name, color);
        }
      }
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
