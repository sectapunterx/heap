#include "integrations/GithubProvider.h"
#include "integrations/TrackerFields.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace {

// GitHub only names the repo an issue belongs to in its API url
// ("https://api.github.com/repos/acme/web"), which is the one place that works
// in both the scoped and the cross-repo pull, and on GitHub Enterprise too.
QString repoFromApiUrl(const QString& apiUrl) {
  const int at = apiUrl.indexOf(QStringLiteral("/repos/"));
  if(at < 0) {
    return {};
  }
  return apiUrl.mid(at + 7);
}

}  // namespace

namespace heap::integrations {

QVector<ExternalTask> parseGithubPulls(const QByteArray& json) {
  QVector<ExternalTask> out;
  const QJsonDocument doc = QJsonDocument::fromJson(json);
  QJsonArray arr;
  if(doc.isArray()) {
    arr = doc.array();
  } else if(doc.isObject()) {
    arr = doc.object().value(QStringLiteral("items")).toArray();
  } else {
    return out;
  }
  out.reserve(arr.size());
  for(const auto& v : arr) {
    const QJsonObject o = v.toObject();
    // A search item is a PR when it has a pull_request node; a pulls-list
    // entry is one by definition and carries head/base instead.
    const bool fromSearch = o.contains(QStringLiteral("pull_request"));
    if(!fromSearch && !o.contains(QStringLiteral("head"))) {
      continue;
    }
    ExternalTask t;
    t.providerId = QStringLiteral("github");
    t.externalId = QString::number(static_cast<qlonglong>(o.value(QStringLiteral("number")).toDouble()));
    t.url = o.value(QStringLiteral("html_url")).toString();
    t.title = o.value(QStringLiteral("title")).toString();
    t.body = o.value(QStringLiteral("body")).toString();
    const QString state = o.value(QStringLiteral("state")).toString();  // "open" | "closed"
    const bool draft = o.value(QStringLiteral("draft")).toBool();
    const QJsonValue mergedAt = fromSearch ? o.value(QStringLiteral("pull_request")).toObject().value(QStringLiteral("merged_at"))
                                           : o.value(QStringLiteral("merged_at"));
    const bool merged = mergedAt.isString() && !mergedAt.toString().isEmpty();
    QString stage;
    if(merged) {
      stage = QStringLiteral("merged");
      t.status = QStringLiteral("PR merged");
    } else if(state == QLatin1String("closed")) {
      stage = QStringLiteral("closed");
      t.status = QStringLiteral("PR closed");
    } else {
      stage = QStringLiteral("open");
      t.status = draft ? QStringLiteral("PR draft") : QStringLiteral("PR open");
    }
    t.updatedAt = parseTrackerTimestamp(o.value(QStringLiteral("updated_at")));
    t.createdAt = parseTrackerTimestamp(o.value(QStringLiteral("created_at")));
    t.assignee = joinObjectField(o.value(QStringLiteral("assignees")), QStringLiteral("login"));
    if(t.assignee.isEmpty()) {
      t.assignee = o.value(QStringLiteral("assignee")).toObject().value(QStringLiteral("login")).toString();
    }
    t.author = o.value(QStringLiteral("user")).toObject().value(QStringLiteral("login")).toString();
    t.commentCount = o.value(QStringLiteral("comments")).isDouble() ? o.value(QStringLiteral("comments")).toInt(-1) : -1;
    t.issueType = QStringLiteral("PR");
    QString repo = repoFromApiUrl(o.value(QStringLiteral("repository_url")).toString());
    if(repo.isEmpty()) {
      repo =
          o.value(QStringLiteral("base")).toObject().value(QStringLiteral("repo")).toObject().value(QStringLiteral("full_name")).toString();
    }
    t.project = sanitizeProject(repo);
    t.milestone = o.value(QStringLiteral("milestone")).toObject().value(QStringLiteral("title")).toString();
    for(const auto& lv : o.value(QStringLiteral("labels")).toArray()) {
      const QJsonObject lo = lv.toObject();
      const QString name = lo.value(QStringLiteral("name")).toString();
      if(name.isEmpty()) {
        continue;
      }
      t.labels.append(name);
      const QString color = normalizeHexColor(lo.value(QStringLiteral("color")).toString());
      if(!color.isEmpty()) {
        t.labelColors.insert(name, color);
      }
    }

    QJsonObject d;
    d.insert(QStringLiteral("kind"), QStringLiteral("pr"));
    d.insert(QStringLiteral("state"), stage);
    d.insert(QStringLiteral("draft"), draft);
    const QString head = o.value(QStringLiteral("head")).toObject().value(QStringLiteral("ref")).toString();
    const QString base = o.value(QStringLiteral("base")).toObject().value(QStringLiteral("ref")).toString();
    if(!head.isEmpty()) {
      d.insert(QStringLiteral("sourceBranch"), head);
    }
    if(!base.isEmpty()) {
      d.insert(QStringLiteral("targetBranch"), base);
    }
    QStringList reviewers;
    for(const auto& rv : o.value(QStringLiteral("requested_reviewers")).toArray()) {
      const QString login = rv.toObject().value(QStringLiteral("login")).toString();
      if(!login.isEmpty()) {
        reviewers.append(login);
      }
    }
    if(!reviewers.isEmpty()) {
      d.insert(QStringLiteral("reviewers"), QJsonArray::fromStringList(reviewers));
    }
    if(o.value(QStringLiteral("mergeable_state")).isString()) {
      d.insert(QStringLiteral("mergeStatus"), o.value(QStringLiteral("mergeable_state")).toString());
    }
    const QStringList closes = closingReferences(t.body);
    if(!closes.isEmpty()) {
      d.insert(QStringLiteral("closes"), QJsonArray::fromStringList(closes));
    }
    t.details = d;
    out.append(t);
  }
  return out;
}

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
    t.updatedAt = parseTrackerTimestamp(o.value(QStringLiteral("updated_at")));
    t.createdAt = parseTrackerTimestamp(o.value(QStringLiteral("created_at")));
    // GitHub issues carry no due date of their own — a milestone's due_on
    // belongs to the milestone, not to each issue in it, so it is not one.
    t.assignee = joinObjectField(o.value(QStringLiteral("assignees")), QStringLiteral("login"));
    if(t.assignee.isEmpty()) {
      t.assignee = o.value(QStringLiteral("assignee")).toObject().value(QStringLiteral("login")).toString();
    }
    t.author = o.value(QStringLiteral("user")).toObject().value(QStringLiteral("login")).toString();
    t.commentCount = o.value(QStringLiteral("comments")).isDouble() ? o.value(QStringLiteral("comments")).toInt(-1) : -1;
    t.issueType = o.value(QStringLiteral("type")).toObject().value(QStringLiteral("name")).toString();
    t.project = sanitizeProject(repoFromApiUrl(o.value(QStringLiteral("repository_url")).toString()));
    t.milestone = o.value(QStringLiteral("milestone")).toObject().value(QStringLiteral("title")).toString();
    for(const auto& lv : o.value(QStringLiteral("labels")).toArray()) {
      const QJsonObject lo = lv.toObject();
      const QString name = lo.value(QStringLiteral("name")).toString();
      if(name.isEmpty()) {
        continue;
      }
      t.labels.append(name);
      // GitHub sends the chip colour as bare hex ("d73a4a").
      const QString color = normalizeHexColor(lo.value(QStringLiteral("color")).toString());
      if(!color.isEmpty()) {
        t.labelColors.insert(name, color);
      }
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
