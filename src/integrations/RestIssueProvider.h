#pragma once

#include "integrations/IntegrationProvider.h"
#include "integrations/IntegrationTypes.h"
#include "integrations/ProviderDescriptor.h"

#include <QString>
#include <QVariantMap>
#include <QVector>

class QNetworkAccessManager;
class QNetworkRequest;

namespace heap::integrations {

// One IntegrationProvider implementation that drives every generic REST tracker
// from its ProviderDescriptor — auth, list endpoint, response parsing and
// optional status write-back are all data. Adding a token+REST+JSON provider is
// a descriptor entry, no new networking code. Bespoke providers (Jira, Trello)
// stay as their own subclasses.
class RestIssueProvider : public IntegrationProvider {
  Q_OBJECT

 public:
  explicit RestIssueProvider(ProviderDescriptor desc, QObject* parent = nullptr);
  ~RestIssueProvider() override;

  // Config keys correspond to the descriptor's uiFields (non-secret from
  // settings, secret from the keychain). Values are trimmed.
  void setConfig(const QVariantMap& cfg);
  bool isConfigured() const;

  QString id() const override {
    return m_desc.id;
  }

  QString displayName() const override {
    return m_desc.displayName;
  }

  void testConnection() override;
  void pullTasks() override;
  void pushStatusChange(const QString& externalId, const QString& newStatus) override;

 private:
  // Expand "{key}" / "{key:enc}" placeholders from the config (plus any `extra`
  // overrides such as {externalId} / {state}). ":enc" percent-encodes the value;
  // host/baseUrl values have trailing slashes trimmed.
  QString expand(const QString& tmpl, const QVariantMap& extra = {}) const;
  QNetworkRequest buildRequest(const QString& url) const;
  // Resolved base URL (descriptor template, falling back to baseUrlFallback when
  // {host} is blank). Trailing slash trimmed.
  QString resolvedBaseUrl() const;
  // The list endpoint: the zero-config "assigned to me" path when the scoping
  // field is blank and a self endpoint exists, else the scoped list path.
  QString listPath() const;
  // True when the descriptor has a self endpoint and the scoping field is blank.
  bool inSelfScope() const;

  ProviderDescriptor m_desc;
  QVariantMap m_cfg;
  QNetworkAccessManager* m_nam = nullptr;
};

// Pure, unit-tested extraction of a list response into ExternalTasks using a
// declarative FieldMap. `baseUrl` feeds FieldMap::urlTemplate. No network.
QVector<ExternalTask> parseWithFieldMap(const QByteArray& json, const FieldMap& map, const QString& providerId, const QString& baseUrl);

}  // namespace heap::integrations
