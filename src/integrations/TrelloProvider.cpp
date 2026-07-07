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
    t.updatedAt = QDateTime::fromString(o.value(QStringLiteral("dateLastActivity")).toString(), Qt::ISODate);
    for(const auto& lv : o.value(QStringLiteral("labels")).toArray()) {
      const QString name = lv.toObject().value(QStringLiteral("name")).toString();
      if(!name.isEmpty()) {
        t.labels.append(name);
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

}  // namespace

void TrelloProvider::testConnection() {
  if(!isConfigured()) {
    emit connectionTested(false, QStringLiteral("Trello key/token not configured"));
    return;
  }
  QNetworkReply* reply = m_nam->get(QNetworkRequest(trelloUrl(QStringLiteral("/members/me"), m_key, m_token)));
  connect(reply, &QNetworkReply::finished, this, [this, reply]() {
    reply->deleteLater();
    emit connectionTested(reply->error() == QNetworkReply::NoError, reply->errorString());
  });
}

void TrelloProvider::pullTasks() {
  if(!isConfigured()) {
    emit tasksFetched({});
    return;
  }
  // With a board id we can resolve list names (→ statuses) first; without one we
  // pull the member's cards across all boards and leave statuses unresolved.
  if(m_board.isEmpty()) {
    fetchCards({});
    return;
  }
  QNetworkReply* reply = m_nam->get(QNetworkRequest(trelloUrl(QStringLiteral("/boards/") + m_board + QStringLiteral("/lists"),
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
  const QUrl url =
      trelloUrl(path, m_key, m_token, {{QStringLiteral("fields"), QStringLiteral("name,desc,idList,url,dateLastActivity,labels")}});
  QNetworkReply* reply = m_nam->get(QNetworkRequest(url));
  connect(reply, &QNetworkReply::finished, this, [this, reply, listNames]() {
    reply->deleteLater();
    if(reply->error() != QNetworkReply::NoError) {
      emit tasksFetched({});
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
