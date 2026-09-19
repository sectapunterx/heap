#pragma once

#include "integrations/IntegrationTypes.h"

#include <QByteArray>
#include <QHash>
#include <QObject>
#include <QPair>
#include <QString>
#include <QStringList>
#include <QVector>

#include <functional>

class QNetworkAccessManager;

namespace heap::integrations {

// ── Pure helpers, unit-tested against canned JSON ──

// One user object from /api/v4/users → ExternalContact. `myId` marks the signed
// in user so the caller can drop them.
ExternalContact parseMattermostUser(const QByteArray& userJson);
QVector<ExternalContact> parseMattermostUsers(const QByteArray& usersJson);

// A direct-message channel's `name` is "<userIdA>__<userIdB>" — the peer is
// whichever half is not me. Empty when the name is malformed, or for the
// self-DM every Mattermost user has. Group DMs have an opaque name instead and
// have to go through the members endpoint.
QString dmPeerId(const QString& channelName, const QString& myId);

// What to show as the person's name: their full name, else their nickname,
// else the username. Mattermost lets every one of those be blank.
QString mattermostDisplayName(const QByteArray& userJson);

// What to show when the person set no job title. Derived from their roles —
// "system_admin" in the user's roles, "channel_admin" in the membership.
QString mattermostRoleLabel(const QString& userRoles, const QString& channelRoles);

// Talks to a Mattermost server's REST API v4. Not an IntegrationProvider:
// nothing here is issue-shaped — there are no tasks to pull, no status to map
// to a column and nothing to push back, only people to import.
//
// Authentication is a token in an Authorization: Bearer header, which is the
// same header for all three ways of getting one:
//   * a personal access token, if the admin enabled them;
//   * a session token from POST /users/login, for a server where they are not;
//   * an OAuth access token, when the admin enabled the OAuth provider.
class MattermostClient : public QObject {
  Q_OBJECT

 public:
  explicit MattermostClient(QObject* parent = nullptr);
  ~MattermostClient() override;

  // `host` is the server root ("https://mm.acme.com"). A plain-http host is
  // refused unless it is loopback — see hostIsAcceptable().
  void setConfig(const QString& host, const QString& token, const QStringList& extraChannels);
  bool isConfigured() const;

  // A password is only ever sent over https, so a typo in the host cannot ship
  // it in clear text to whatever answers. Loopback is allowed for the tests.
  static bool hostIsAcceptable(const QString& host);
  // Trailing slashes off, so "{host}/api/v4" never becomes "//api/v4".
  static QString normalizeHost(const QString& raw);

  // GET /users/me. Emits connectionTested.
  void testConnection();
  // POST /users/login. The session token comes back in the response's `Token`
  // header, not in the body. `mfaToken` is optional. Emits loggedIn.
  void login(const QString& loginId, const QString& password, const QString& mfaToken);
  // POST /users/logout, so disconnecting actually ends the server-side session
  // rather than leaving it alive for its full 30 days.
  void logout();
  // Walk my teams → channels → members → users. Emits contactsFetched.
  void fetchContacts();

 signals:
  void connectionTested(bool ok, const QString& error);
  void loggedIn(bool ok, const QString& token, const QString& error);
  void contactsFetched(const QVector<heap::integrations::ExternalContact>& contacts);
  void failed(int httpStatus, const QString& error);

 private:
  struct ApiResult {
    bool ok = false;
    int status = 0;
    QByteArray body;
    QByteArray tokenHeader;  // login's session token
    QString error;
  };

  using ApiCallback = std::function<void(const ApiResult&)>;

  void send(const QByteArray& method, const QString& path, const QByteArray& body, const ApiCallback& done);
  // The choreography of fetchContacts, one step per method so each one reads as
  // a single request rather than a pyramid of callbacks.
  void fetchTeams(const QString& myId);
  void fetchChannels(const QString& myId, const QStringList& teamIds, int teamIndex);
  void fetchMemberChannels(
      const QString& myId, const QStringList& teamIds, int teamIndex, const QVector<QPair<QString, QString>>& channels, int channelIndex);
  void fetchChannelMembers(const QString& channelId, const QString& label, int page, const std::function<void()>& next);
  void resolveUsers();
  void resolveUserBatch(const QStringList& ids, int offset, const QVector<ExternalContact>& collected);

  QNetworkAccessManager* m_nam = nullptr;
  QString m_host;
  QString m_token;
  QStringList m_extraChannels;  // channel names whose members to import too

  // fetchContacts scratch state. One fetch at a time: a second call while one
  // is in flight is ignored rather than interleaved.
  bool m_fetching = false;
  QString m_myId;
  QHash<QString, QString> m_wanted;       // user id → where we met them
  QHash<QString, QString> m_channelRole;  // user id → their roles in that channel
};

}  // namespace heap::integrations
