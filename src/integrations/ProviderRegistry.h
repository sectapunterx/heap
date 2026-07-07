#pragma once

#include "integrations/IntegrationProvider.h"
#include "integrations/ProviderDescriptor.h"

#include <QVariantMap>
#include <QVector>

#include <memory>

class QObject;

namespace heap::integrations {

// The complete catalogue of tracker integrations — the single source of truth
// for both the C++ build loop (AppController::applyIntegrationSettings) and the
// QML Settings cards (AppController::integrationCatalog). Generic providers are
// driven by RestIssueProvider; entries with `bespoke = true` (Jira, Trello) are
// built via makeBespokeProvider.
const QVector<ProviderDescriptor>& providerCatalog();

// Look up one descriptor by id; returns nullptr if unknown.
const ProviderDescriptor* findDescriptor(const QString& id);

// Construct and configure a bespoke provider (Jira, Trello) from a merged config
// map (non-secret settings + keychain secrets). Returns nullptr for an unknown
// id or when required fields are missing.
std::unique_ptr<IntegrationProvider> makeBespokeProvider(const QString& id, const QVariantMap& cfg, QObject* parent);

}  // namespace heap::integrations
