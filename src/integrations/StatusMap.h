#pragma once

#include <QHash>
#include <QString>

namespace heap::integrations {

// Pure translation between external-tracker vocabularies and heap.'s own
// kanban columns / priority tiers. No network, no QObject — the deterministic
// core of the (post-release) tracker-sync feature, unit-tested on its own.
//
// heap. column ids: "backlog" | "todo" | "prog" | "review" | "blocked" | "done".
// heap. priority ids: "P0" | "P1" | "P2" | "P3".
class StatusMap {
 public:
  // Built-in mapping for common Jira/GitHub/GitLab status names → heap column.
  // Matching is case-insensitive and whitespace-trimmed. Unrecognized input
  // returns an empty string (callers pass it through map() with a fallback).
  static QString defaultColumn(const QString& providerStatus);

  // Resolve a provider status to a heap column: user \p overrides win (also
  // matched case-insensitively), then the built-in table, then \p fallback.
  static QString column(const QString& providerStatus,
                        const QHash<QString, QString>& overrides = {},
                        const QString& fallback = QStringLiteral("todo"));

  // Jira-style priority name → heap tier. Highest→P0, High→P1, Medium→P2,
  // Low/Lowest→P3. Unknown → \p fallback (default "P2").
  static QString priority(const QString& providerPriority,
                          const QString& fallback = QStringLiteral("P2"));
};

}  // namespace heap::integrations
