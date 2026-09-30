#pragma once

#include "Models.h"

#include <QHash>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QVector>

// The pure halves of AppController::mergeExternalTasks: how one field of a
// mirrored card reconciles the local value, the value the tracker sent last
// time (the base) and the value it sends now. Kept out of AppController so
// the rules can be tested without a controller, and so the merge reads as a
// list of fields rather than a list of special cases.

namespace heap::integrations {

struct ProviderDescriptor;

// Three-way outcome for one scalar field.
enum class FieldMerge {
  TakeRemote,  // the local value was untouched (or there is no base): follow the tracker
  KeepLocal,   // edited here, the tracker did not move: the local edit stands
  Converged,   // both sides now say the same thing
  Conflict,    // both sides changed, to different values: local kept, user told
};

// `hasBase` false means the card predates bases for this field.
// `legacyKeepsLocal` picks what a card without a base does: title and body
// were overwritten by every older pull, so the tracker's text is what the card
// expects (false); priority was too, but a value that differs from the
// tracker's now can only be an edit made since the last pull (true).
FieldMerge mergeField(const QString& local, const QString& base, const QString& remote, bool hasBase, bool legacyKeepsLocal = false);

// Labels, three-way by name. A label the tracker dropped since the last pull
// is dropped here too; one the user removed here stays removed while the
// tracker still has it; one added on either side is kept. A card without a
// base (an empty one reads the same) only gains labels, as it always did.
// Colours: a chip without one takes the tracker's.
QVector<Label> mergeLabels(const QVector<Label>& local,
                           const QStringList& base,
                           const QStringList& remote,
                           const QHash<QString, QString>& remoteColors);

// A digest of what decides which issues a pull returns: every non-secret field
// the user fills in on the card (repo, JQL, project, board, host, email…),
// minus the ones that only affect how heap signs in or names branches.
// Changing any of them changes the set of issues a complete pull can be
// expected to carry. Stable across launches; empty for an unknown provider.
QString scopeFingerprint(const ProviderDescriptor& d, const QVariantMap& cfg);

// Add or drop `field` from a conflict list, keeping the rest in order.
void setConflict(QStringList& conflicts, const QString& field, bool on);

}  // namespace heap::integrations
