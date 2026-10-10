#include "integrations/ProviderDescriptor.h"
#include "integrations/TrackerMerge.h"

#include <QCryptographicHash>
#include <QSet>

namespace heap::integrations {

FieldMerge mergeField(const QString& local, const QString& base, const QString& remote, bool hasBase, bool legacyKeepsLocal) {
  if(!hasBase) {
    if(legacyKeepsLocal && local != remote) {
      return FieldMerge::KeepLocal;
    }
    return FieldMerge::TakeRemote;
  }
  if(local == base) {
    return FieldMerge::TakeRemote;
  }
  if(local == remote) {
    return FieldMerge::Converged;
  }
  return remote == base ? FieldMerge::KeepLocal : FieldMerge::Conflict;
}

QVector<Label> mergeLabels(const QVector<Label>& local,
                           const QStringList& base,
                           const QStringList& remote,
                           const QHash<QString, QString>& remoteColors) {
  const QSet<QString> baseSet(base.cbegin(), base.cend());
  const QSet<QString> remoteSet(remote.cbegin(), remote.cend());
  QVector<Label> out;
  out.reserve(local.size() + remote.size());
  QSet<QString> present;
  for(const Label& l : local) {
    // In the base and gone from the tracker: removed upstream. A label that
    // was never in the base is the user's own and stays.
    if(baseSet.contains(l.id) && !remoteSet.contains(l.id)) {
      continue;
    }
    if(present.contains(l.id)) {
      continue;
    }
    present.insert(l.id);
    Label kept = l;
    if(kept.color.isEmpty()) {
      kept.color = remoteColors.value(l.id);
    }
    out.append(kept);
  }
  for(const QString& name : remote) {
    // Already there, or in the base but not here: the user took it off.
    if(name.isEmpty() || present.contains(name) || baseSet.contains(name)) {
      continue;
    }
    present.insert(name);
    out.append(Label{name, remoteColors.value(name)});
  }
  return out;
}

QString scopeFingerprint(const ProviderDescriptor& d, const QVariantMap& cfg) {
  // How heap signs in, or names branches, does not change which issues exist.
  static const QSet<QString> kNotScope = {
      QStringLiteral("clientId"),
      QStringLiteral("clientSecret"),
      QStringLiteral("branchTemplate"),
  };
  QStringList parts;
  for(const FieldSpec& f : d.uiFields) {
    if(f.secret || kNotScope.contains(f.key) || d.secretKeys.contains(f.key)) {
      continue;
    }
    // Whitespace and case in a repo slug or a JQL keyword do not change the
    // answer; collapsing them keeps a cosmetic edit from reading as a new
    // filter.
    parts.append(f.key + QChar('=') + cfg.value(f.key).toString().simplified().toLower());
  }
  // Which merge / pull requests come along (APP-242) is part of the filter,
  // but only once the user set it: a card pulled before stays in scope.
  for(const QString& key : {d.reviewEnabledKey, d.reviewRolesKey}) {
    if(!key.isEmpty() && cfg.contains(key)) {
      parts.append(key + QChar('=') + cfg.value(key).toString().simplified().toLower());
    }
  }
  // A browser-signed-in Jira names its site through the cloud id, not a field.
  const QString cloudId = cfg.value(QStringLiteral("cloudId")).toString();
  if(!cloudId.isEmpty()) {
    parts.append(QStringLiteral("cloudId=") + cloudId);
  }
  if(parts.isEmpty()) {
    parts.append(QStringLiteral("all"));
  }
  const QByteArray digest = QCryptographicHash::hash((d.id + QChar('\n') + parts.join(QChar('\n'))).toUtf8(), QCryptographicHash::Sha1);
  return QString::fromLatin1(digest.toHex().left(12));
}

void setConflict(QStringList& conflicts, const QString& field, bool on) {
  if(on) {
    if(!conflicts.contains(field)) {
      conflicts.append(field);
    }
  } else {
    conflicts.removeAll(field);
  }
}

}  // namespace heap::integrations
