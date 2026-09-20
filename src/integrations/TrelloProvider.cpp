#include "integrations/ReplyError.h"
#include "integrations/TrackerFields.h"
#include "integrations/TrelloProvider.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QUrlQuery>

namespace heap::integrations {

namespace {

// A Trello object id starts with the creation time: the first eight hex digits
// are epoch seconds. It is the only creation timestamp the card carries.
QDateTime trelloCreatedFromId(const QString& id) {
  if(id.size() < 8) {
    return {};
  }
  bool ok = false;
  const qlonglong secs = id.left(8).toLongLong(&ok, 16);
  if(!ok || secs <= 0) {
    return {};
  }
  return QDateTime::fromSecsSinceEpoch(secs).toLocalTime();
}

// Trello names its label colours ("green", "red_dark") rather than sending hex.
QString trelloLabelColor(const QString& name) {
  static const QHash<QString, QString> kPalette = {{QStringLiteral("green"), QStringLiteral("#61bd4f")},
                                                   {QStringLiteral("yellow"), QStringLiteral("#f2d600")},
                                                   {QStringLiteral("orange"), QStringLiteral("#ff9f1a")},
                                                   {QStringLiteral("red"), QStringLiteral("#eb5a46")},
                                                   {QStringLiteral("purple"), QStringLiteral("#c377e0")},
                                                   {QStringLiteral("blue"), QStringLiteral("#0079bf")},
                                                   {QStringLiteral("sky"), QStringLiteral("#00c2e0")},
                                                   {QStringLiteral("lime"), QStringLiteral("#51e898")},
                                                   {QStringLiteral("pink"), QStringLiteral("#ff78cb")},
                                                   {QStringLiteral("black"), QStringLiteral("#344563")}};
  // The shade suffixes ("_dark", "_light") map onto the base hue.
  const QString base = name.section(QChar('_'), 0, 0).toLower();
  return kPalette.value(base);
}

}  // namespace

QHash<QString, QString> parseTrelloLists(const QByteArray& json) {
  QHash<QString, QString> out;
  const QJsonDocument doc = QJsonDocument::fromJson(json);
  if(!doc.isArray()) {
    return out;
  }
  for(const auto& v : doc.array()) {
    const QJsonObject o = v.toObject();
    const QString id = o.value(QStringLiteral("id")).toString();
    const QString name = o.value(QStringLiteral("name")).toString();
    if(!id.isEmpty()) {
      out.insert(id, name);
    }
  }
  return out;
}

QVector<ExternalTask> parseTrelloCards(const QByteArray& json, const QHash<QString, QString>& listNames) {
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
    t.providerId = QStringLiteral("trello");
    t.externalId = o.value(QStringLiteral("id")).toString();
    t.title = o.value(QStringLiteral("name")).toString();
    t.body = o.value(QStringLiteral("desc")).toString();
    t.url = o.value(QStringLiteral("url")).toString();
    // A card's status is the name of the list it lives in.
    t.status = listNames.value(o.value(QStringLiteral("idList")).toString());
    t.updatedAt = parseTrackerTimestamp(o.value(QStringLiteral("dateLastActivity")));
    t.createdAt = trelloCreatedFromId(t.externalId);
    t.dueAt = parseTrackerTimestamp(o.value(QStringLiteral("due")), &t.dueHasTime);
    const QJsonObject badges = o.value(QStringLiteral("badges")).toObject();
    t.commentCount = badges.value(QStringLiteral("comments")).isDouble() ? badges.value(QStringLiteral("comments")).toInt(-1) : -1;
    // /members/me/cards can be asked for the card's members; a board pull is
    // already scoped, and either way the field is absent unless requested.
    t.assignee = joinObjectField(o.value(QStringLiteral("members")), QStringLiteral("fullName"));
    for(const auto& lv : o.value(QStringLiteral("labels")).toArray()) {
      const QJsonObject lo = lv.toObject();
      const QString name = lo.value(QStringLiteral("name")).toString();
      if(!name.isEmpty()) {
        t.labels.append(name);
        const QString color = trelloLabelColor(lo.value(QStringLiteral("color")).toString());
        if(!color.isEmpty()) {
          t.labelColors.insert(name, color);
        }
      }
    }
    out.append(t);
  }
  return out;
}

TrelloProvider::TrelloProvider(QObject* parent) : IntegrationProvider(parent), m_nam(new QNetworkAccessManager(this)) {
}

TrelloProvider::~TrelloProvider() = default;

void TrelloProvider::setConfig(const QString& key, const QString& token, const QString& board) {
  m_key = key.trimmed();
  m_token = token.trimmed();
  m_board = board.trimmed();
}

bool TrelloProvider::isConfigured() const {
  return !m_key.isEmpty() && !m_token.isEmpty();
}

namespace {

QUrl trelloUrl(const QString& path, const QString& key, const QString& token, const QList<QPair<QString, QString>>& extra = {}) {
  QUrl url(QStringLiteral("https://api.trello.com/1") + path);
  QUrlQuery q;
  q.addQueryItem(QStringLiteral("key"), key);
  q.addQueryItem(QStringLiteral("token"), token);
  for(const auto& kv : extra) {
    q.addQueryItem(kv.first, kv.second);
  }
  url.setQuery(q);
  return url;
}

// Trello carries the key and token in the query string, so a redirect to
// another host would hand them over. Qt's default policy permits that.
QNetworkRequest trelloRequest(const QUrl& url) {
  QNetworkRequest req{url};
  req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::SameOriginRedirectPolicy);
  return req;
}

}  // namespace

void TrelloProvider::testConnection() {
  if(!isConfigured()) {
    emit connectionTested(false, QStringLiteral("Trello key/token not configured"));
    return;
  }
  QNetworkReply* reply = m_nam->get(trelloRequest(trelloUrl(QStringLiteral("/members/me"), m_key, m_token)));
  connect(reply, &QNetworkReply::finished, this, [this, reply]() {
    reply->deleteLater();
    const bool ok = reply->error() == QNetworkReply::NoError;
    emit connectionTested(ok, ok ? QString() : describeReplyError(reply));
  });
}

void TrelloProvider::pullTasks() {
  if(!isConfigured()) {
    emit pullFailed(0, QStringLiteral("Trello key/token not configured"));
    return;
  }
  // With a board id we can resolve list names (→ statuses) first; without one we
  // pull the member's cards across all boards and leave statuses unresolved.
  if(m_board.isEmpty()) {
    fetchCards({});
    return;
  }
  QNetworkReply* reply = m_nam->get(trelloRequest(trelloUrl(QStringLiteral("/boards/") + m_board + QStringLiteral("/lists"),
                                                            m_key,
                                                            m_token,
                                                            {{QStringLiteral("fields"), QStringLiteral("name")}})));
  connect(reply, &QNetworkReply::finished, this, [this, reply]() {
    reply->deleteLater();
    QHash<QString, QString> listNames;
    if(reply->error() == QNetworkReply::NoError) {
      listNames = parseTrelloLists(reply->readAll());
    }
    fetchCards(listNames);
  });
}

void TrelloProvider::fetchCards(const QHash<QString, QString>& listNames) {
  const QString path =
      m_board.isEmpty() ? QStringLiteral("/members/me/cards") : QStringLiteral("/boards/") + m_board + QStringLiteral("/cards");
  const QUrl url = trelloUrl(path,
                             m_key,
                             m_token,
                             {{QStringLiteral("fields"), QStringLiteral("name,desc,idList,url,dateLastActivity,labels,due,badges")},
                              {QStringLiteral("members"), QStringLiteral("true")},
                              {QStringLiteral("member_fields"), QStringLiteral("fullName")}});
  QNetworkReply* reply = m_nam->get(trelloRequest(url));
  connect(reply, &QNetworkReply::finished, this, [this, reply, listNames]() {
    reply->deleteLater();
    if(reply->error() != QNetworkReply::NoError) {
      emit pullFailed(replyHttpStatus(reply), describeReplyError(reply));
      return;
    }
    emit tasksFetched(parseTrelloCards(reply->readAll(), listNames));
  });
}

void TrelloProvider::pushStatusChange(const QString& externalId, const QString& /*newStatus*/) {
  // Pull-only for v1: moving a card would require resolving the target column to
  // a list id on the card's board. Report success so linked-task moves stay quiet.
  emit taskPushed(externalId, true, QStringLiteral("pull-only"));
}

}  // namespace heap::integrations
