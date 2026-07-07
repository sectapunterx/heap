#pragma once

#include "integrations/IntegrationProvider.h"
#include "integrations/IntegrationTypes.h"

#include <QByteArray>
#include <QHash>
#include <QString>
#include <QVector>

class QNetworkAccessManager;

namespace heap::integrations {

// Map a Trello "board lists" JSON array to { listId → listName }. A card's
// status is the name of the list it sits in, so this resolves the id the card
// carries into a human status StatusMap can fold onto a column. Pure, no
// network — unit-tested with canned JSON.
QHash<QString, QString> parseTrelloLists(const QByteArray& json);

// Parse a Trello "cards" JSON array into ExternalTasks. `listNames` (from
// parseTrelloLists) turns each card's idList into a status name; an unknown id
// leaves the status empty (StatusMap then falls back to todo). Pure, no network.
QVector<ExternalTask> parseTrelloCards(const QByteArray& json, const QHash<QString, QString>& listNames);

// Bespoke provider for Trello: auth is an API key + token in the query string,
// and a card's status lives in a separate "lists" resource, so it needs a second
// request the generic RestIssueProvider can't express. Pull-only for v1.
class TrelloProvider : public IntegrationProvider {
  Q_OBJECT

 public:
  explicit TrelloProvider(QObject* parent = nullptr);
  ~TrelloProvider() override;

  // `board` is optional: blank pulls the member's cards across all boards
  // (statuses unresolved); a board id scopes to it and resolves list names.
  void setConfig(const QString& key, const QString& token, const QString& board);
  bool isConfigured() const;

  QString id() const override {
    return QStringLiteral("trello");
  }

  QString displayName() const override {
    return QStringLiteral("Trello");
  }

  void testConnection() override;
  void pullTasks() override;
  void pushStatusChange(const QString& externalId, const QString& newStatus) override;

 private:
  void fetchCards(const QHash<QString, QString>& listNames);

  QNetworkAccessManager* m_nam = nullptr;
  QString m_key;
  QString m_token;
  QString m_board;
};

}  // namespace heap::integrations
