#include "integrations/MattermostClient.h"
#include "integrations/ReplyError.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>

namespace heap::integrations {

namespace {

// Mattermost pages at 200 by default and a channel can have thousands of
// members; importing a whole company as contacts helps nobody, so stop after
// five pages of any one channel.
constexpr int kPageSize = 200;
constexpr int kMaxPages = 5;
// /users/ids takes a batch of ids and answers with the user objects.
constexpr int kUserBatch = 200;

QString contactRole(const QJsonObject& user, const QString& channelRoles) {
  const QString position = user.value(QStringLiteral("position")).toString().trimmed();
  if(!position.isEmpty()) {
    return position;
  }
  return mattermostRoleLabel(user.value(QStringLiteral("roles")).toString(), channelRoles);
}

}  // namespace

// ───────────────────────── pure helpers ─────────────────────────

QString mattermostDisplayName(const QByteArray& userJson) {
  const QJsonObject user = QJsonDocument::fromJson(userJson).object();
  const QString first = user.value(QStringLiteral("first_name")).toString().trimmed();
  const QString last = user.value(QStringLiteral("last_name")).toString().trimmed();
  const QString full = QStringLiteral("%1 %2").arg(first, last).trimmed();
  if(!full.isEmpty()) {
    return full;
  }
  const QString nickname = user.value(QStringLiteral("nickname")).toString().trimmed();
  if(!nickname.isEmpty()) {
    return nickname;
  }
  return user.value(QStringLiteral("username")).toString();
}

QString mattermostRoleLabel(const QString& userRoles, const QString& channelRoles) {
  // Roles arrive as a space-separated list ("system_user system_admin").
  const QStringList system = userRoles.split(QChar(' '), Qt::SkipEmptyParts);
  if(system.contains(QStringLiteral("system_admin"))) {
    return QStringLiteral("System admin");
  }
  if(channelRoles.split(QChar(' '), Qt::SkipEmptyParts).contains(QStringLiteral("channel_admin"))) {
    return QStringLiteral("Channel admin");
  }
  if(system.contains(QStringLiteral("system_guest"))) {
    return QStringLiteral("Guest");
  }
  return QStringLiteral("Member");
}

ExternalContact parseMattermostUser(const QByteArray& userJson) {
  const QJsonObject user = QJsonDocument::fromJson(userJson).object();
  ExternalContact c;
  c.providerId = QStringLiteral("mattermost");
  c.externalId = user.value(QStringLiteral("id")).toString();
  c.username = user.value(QStringLiteral("username")).toString();
  c.displayName = mattermostDisplayName(userJson);
  c.position = user.value(QStringLiteral("position")).toString().trimmed();
  c.role = contactRole(user, QString());
  c.email = user.value(QStringLiteral("email")).toString();
  c.isBot = user.value(QStringLiteral("is_bot")).toBool();
  // Mattermost never deletes a user; deactivating stamps delete_at instead.
  c.deactivated = user.value(QStringLiteral("delete_at")).toDouble() > 0;
  return c;
}

QVector<ExternalContact> parseMattermostUsers(const QByteArray& usersJson) {
  QVector<ExternalContact> out;
  const QJsonArray users = QJsonDocument::fromJson(usersJson).array();
  out.reserve(static_cast<int>(users.size()));
  for(const auto& v : users) {
    const ExternalContact c = parseMattermostUser(QJsonDocument(v.toObject()).toJson(QJsonDocument::Compact));
    if(!c.externalId.isEmpty()) {
      out.append(c);
    }
  }
  return out;
}

QString dmPeerId(const QString& channelName, const QString& myId) {
  const QStringList halves = channelName.split(QStringLiteral("__"));
  if(halves.size() != 2 || myId.isEmpty()) {
    return {};
  }
  if(halves.at(0) == myId && halves.at(1) == myId) {
    return {};  // the self-DM every account has
  }
  if(halves.at(0) == myId) {
    return halves.at(1);
  }
  if(halves.at(1) == myId) {
    return halves.at(0);
  }
  return {};  // not my conversation
}

// ───────────────────────── client ─────────────────────────

MattermostClient::MattermostClient(QObject* parent) : QObject(parent), m_nam(new QNetworkAccessManager(this)) {
}

MattermostClient::~MattermostClient() = default;

QString MattermostClient::normalizeHost(const QString& raw) {
  QString host = raw.trimmed();
  while(host.endsWith(QLatin1Char('/'))) {
    host.chop(1);
  }
  return host;
}

bool MattermostClient::hostIsAcceptable(const QString& host) {
  const QUrl url(normalizeHost(host));
  if(!url.isValid() || url.host().isEmpty()) {
    return false;
  }
  if(url.scheme() == QLatin1String("https")) {
    return true;
  }
  // A password and a session token both go over this connection. Plain http is
  // only tolerable when it cannot leave the machine.
  return url.scheme() == QLatin1String("http") &&
         (url.host() == QLatin1String("127.0.0.1") || url.host() == QLatin1String("localhost") || url.host() == QLatin1String("::1"));
}

void MattermostClient::setConfig(const QString& host, const QString& token, const QStringList& extraChannels) {
  m_host = normalizeHost(host);
  m_token = token.trimmed();
  m_extraChannels = extraChannels;
}

bool MattermostClient::isConfigured() const {
  return !m_host.isEmpty() && !m_token.isEmpty() && hostIsAcceptable(m_host);
}

void MattermostClient::send(const QByteArray& method, const QString& path, const QByteArray& body, const ApiCallback& done) {
  QNetworkRequest req{QUrl(m_host + QStringLiteral("/api/v4") + path)};
  // Qt's default redirect policy allows a redirect to another host, and a 307
  // keeps the method and body — so a server could bounce POST /users/login,
  // password and all, to somewhere else, or collect the Bearer token from any
  // other call. hostIsAcceptable() only ever saw the first URL.
  req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::SameOriginRedirectPolicy);
  req.setRawHeader("Accept", "application/json");
  req.setRawHeader("User-Agent", "heap-sync");
  if(!m_token.isEmpty()) {
    req.setRawHeader("Authorization", QByteArrayLiteral("Bearer ") + m_token.toUtf8());
  }
  if(!body.isEmpty()) {
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
  }

  QNetworkReply* reply = m_nam->sendCustomRequest(req, method, body);
  connect(reply, &QNetworkReply::finished, this, [reply, done]() {
    reply->deleteLater();
    ApiResult r;
    r.status = replyHttpStatus(reply);
    r.body = reply->readAll();
    r.tokenHeader = reply->rawHeader("Token");
    r.ok = reply->error() == QNetworkReply::NoError;
    if(!r.ok) {
      r.error = describeHttpError(r.status, r.body, reply->errorString());
    }
    done(r);
  });
}

void MattermostClient::testConnection() {
  if(!isConfigured()) {
    emit connectionTested(false,
                          hostIsAcceptable(m_host) ? QStringLiteral("Mattermost server URL or token is missing")
                                                   : QStringLiteral("Mattermost server URL must be https"));
    return;
  }
  send("GET", QStringLiteral("/users/me"), {}, [this](const ApiResult& r) {
    emit connectionTested(r.ok, r.error);
  });
}

void MattermostClient::login(const QString& loginId, const QString& password, const QString& mfaToken) {
  if(m_host.isEmpty() || !hostIsAcceptable(m_host)) {
    emit loggedIn(false, QString(), QStringLiteral("Mattermost server URL must be https"));
    return;
  }
  QJsonObject payload{{QStringLiteral("login_id"), loginId}, {QStringLiteral("password"), password}};
  if(!mfaToken.trimmed().isEmpty()) {
    payload.insert(QStringLiteral("token"), mfaToken.trimmed());
  }
  const QByteArray body = QJsonDocument(payload).toJson(QJsonDocument::Compact);

  send("POST", QStringLiteral("/users/login"), body, [this](const ApiResult& r) {
    if(!r.ok) {
      emit loggedIn(false, QString(), r.error);
      return;
    }
    // The session token is a response header; the body is the user object.
    const QString token = QString::fromUtf8(r.tokenHeader);
    if(token.isEmpty()) {
      emit loggedIn(false, QString(), QStringLiteral("the server accepted the sign-in but returned no session token"));
      return;
    }
    emit loggedIn(true, token, QString());
  });
  // No wiping here, deliberately. QByteArray is implicitly shared, so
  // fill('\0') would detach and zero a fresh copy while the one Qt is still
  // uploading stays intact — and the password also exists in the QString
  // argument, in `payload`, and inside Qt's own HTTP buffers, none of which are
  // reachable from here. A wipe would only look reassuring. The guarantees
  // worth making are the ones that hold: it is never persisted and never
  // logged, and it only ever leaves over https (see hostIsAcceptable).
}

void MattermostClient::logout() {
  if(!isConfigured()) {
    return;
  }
  send("POST", QStringLiteral("/users/logout"), {}, [](const ApiResult&) {
    // Best effort: the local token is dropped either way.
  });
}

void MattermostClient::fetchContacts() {
  if(!isConfigured()) {
    emit failed(0, QStringLiteral("Mattermost is not configured"));
    return;
  }
  if(m_fetching) {
    return;  // a second sync while one is in flight would interleave the state
  }
  m_fetching = true;
  m_wanted.clear();
  m_channelRole.clear();

  send("GET", QStringLiteral("/users/me"), {}, [this](const ApiResult& r) {
    if(!r.ok) {
      m_fetching = false;
      emit failed(r.status, r.error);
      return;
    }
    m_myId = QJsonDocument::fromJson(r.body).object().value(QStringLiteral("id")).toString();
    fetchTeams(m_myId);
  });
}

void MattermostClient::fetchTeams(const QString& myId) {
  send("GET", QStringLiteral("/users/me/teams"), {}, [this, myId](const ApiResult& r) {
    if(!r.ok) {
      m_fetching = false;
      emit failed(r.status, r.error);
      return;
    }
    QStringList teamIds;
    const QJsonArray teams = QJsonDocument::fromJson(r.body).array();
    for(const auto& v : teams) {
      const QString id = v.toObject().value(QStringLiteral("id")).toString();
      if(!id.isEmpty()) {
        teamIds.append(id);
      }
    }
    fetchChannels(myId, teamIds, 0);
  });
}

void MattermostClient::fetchChannels(const QString& myId, const QStringList& teamIds, int teamIndex) {
  if(teamIndex >= teamIds.size()) {
    resolveUsers();
    return;
  }
  const QString path = QStringLiteral("/users/me/teams/%1/channels").arg(teamIds.at(teamIndex));
  send("GET", path, {}, [this, myId, teamIds, teamIndex](const ApiResult& r) {
    if(!r.ok) {
      m_fetching = false;
      emit failed(r.status, r.error);
      return;
    }
    // Channels needing a members call, walked after this team's list is read.
    QVector<QPair<QString, QString>> memberChannels;  // id, label
    const QJsonArray channels = QJsonDocument::fromJson(r.body).array();
    for(const auto& v : channels) {
      const QJsonObject ch = v.toObject();
      const QString type = ch.value(QStringLiteral("type")).toString();
      const QString name = ch.value(QStringLiteral("name")).toString();
      const QString id = ch.value(QStringLiteral("id")).toString();

      if(type == QLatin1String("D")) {
        // A one-to-one conversation: the peer is in the channel name, so no
        // extra request. An empty one has never been used — importing it would
        // add a stranger the server happened to pre-create a channel for.
        if(ch.value(QStringLiteral("total_msg_count")).toDouble() <= 0) {
          continue;
        }
        const QString peer = dmPeerId(name, myId);
        if(!peer.isEmpty() && !m_wanted.contains(peer)) {
          m_wanted.insert(peer, QStringLiteral("direct message"));
        }
        continue;
      }
      if(type == QLatin1String("G")) {
        memberChannels.append({id, ch.value(QStringLiteral("display_name")).toString()});
        continue;
      }
      // Ordinary channels only when the user asked for them by name: a company
      // -wide channel would otherwise import everyone.
      if(m_extraChannels.contains(name, Qt::CaseInsensitive)) {
        memberChannels.append({id, QLatin1Char('#') + name});
      }
    }

    // Walk them one at a time, then move on to the next team. Explicit indices
    // rather than a self-referential std::function: that idiom makes the
    // functor own itself, so the closure and everything it captured leak on
    // every sync.
    fetchMemberChannels(myId, teamIds, teamIndex, memberChannels, 0);
  });
}

void MattermostClient::fetchMemberChannels(
    const QString& myId, const QStringList& teamIds, int teamIndex, const QVector<QPair<QString, QString>>& channels, int channelIndex) {
  if(channelIndex >= channels.size()) {
    fetchChannels(myId, teamIds, teamIndex + 1);
    return;
  }
  const auto& entry = channels.at(channelIndex);
  fetchChannelMembers(entry.first, entry.second, 0, [this, myId, teamIds, teamIndex, channels, channelIndex]() {
    fetchMemberChannels(myId, teamIds, teamIndex, channels, channelIndex + 1);
  });
}

void MattermostClient::fetchChannelMembers(const QString& channelId, const QString& label, int page, const std::function<void()>& next) {
  if(page >= kMaxPages) {
    next();
    return;
  }
  const QString path = QStringLiteral("/channels/%1/members?page=%2&per_page=%3").arg(channelId).arg(page).arg(kPageSize);
  send("GET", path, {}, [this, channelId, label, page, next](const ApiResult& r) {
    if(!r.ok) {
      // One unreadable channel is not worth abandoning the whole import.
      next();
      return;
    }
    const QJsonArray members = QJsonDocument::fromJson(r.body).array();
    for(const auto& v : members) {
      const QJsonObject m = v.toObject();
      const QString userId = m.value(QStringLiteral("user_id")).toString();
      if(userId.isEmpty() || userId == m_myId) {
        continue;
      }
      // A DM label is more informative than a channel one, so it wins.
      if(!m_wanted.contains(userId)) {
        m_wanted.insert(userId, label);
      }
      m_channelRole.insert(userId, m.value(QStringLiteral("roles")).toString());
    }
    if(members.size() < kPageSize) {
      next();
      return;
    }
    fetchChannelMembers(channelId, label, page + 1, next);
  });
}

void MattermostClient::resolveUsers() {
  const QStringList ids = m_wanted.keys();
  if(ids.isEmpty()) {
    m_fetching = false;
    emit contactsFetched({});
    return;
  }
  resolveUserBatch(ids, 0, {});
}

void MattermostClient::resolveUserBatch(const QStringList& ids, int offset, const QVector<ExternalContact>& collected) {
  if(offset >= ids.size()) {
    m_fetching = false;
    emit contactsFetched(collected);
    return;
  }
  QJsonArray batch;
  const int end = qMin(offset + kUserBatch, static_cast<int>(ids.size()));
  for(int i = offset; i < end; ++i) {
    batch.append(ids.at(i));
  }

  send("POST",
       QStringLiteral("/users/ids"),
       QJsonDocument(batch).toJson(QJsonDocument::Compact),
       [this, ids, end, collected](const ApiResult& r) {
         if(!r.ok) {
           m_fetching = false;
           emit failed(r.status, r.error);
           return;
         }
         QVector<ExternalContact> all = collected;
         const QJsonArray users = QJsonDocument::fromJson(r.body).array();
         for(const auto& v : users) {
           const QJsonObject user = v.toObject();
           ExternalContact c = parseMattermostUser(QJsonDocument(user).toJson(QJsonDocument::Compact));
           // Bots are integrations, not colleagues; deactivated accounts are
           // people who left; and importing yourself is noise.
           if(c.externalId.isEmpty() || c.isBot || c.deactivated || c.externalId == m_myId) {
             continue;
           }
           c.channelLabel = m_wanted.value(c.externalId);
           c.role = contactRole(user, m_channelRole.value(c.externalId));
           all.append(c);
         }
         resolveUserBatch(ids, end, all);
       });
}

}  // namespace heap::integrations
