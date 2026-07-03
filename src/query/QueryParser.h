#pragma once

#include <QString>
#include <QStringList>
#include <QVector>

namespace heap::query {

enum class Op { Eq, In, Lt, Le, Gt, Ge };

// One `field:spec` clause. `values` holds one entry for Eq/comparison ops and
// several for In (comma-separated).
struct Condition {
  QString field;  // "status" | "priority" | "deadline" | "profile" | "mention" | "tag"
  Op op = Op::Eq;
  QStringList values;
};

// A parsed Notes query, e.g. `status:blocked priority:P0,P1 deadline:<7d sort:-deadline limit:20`.
struct ParsedQuery {
  QVector<Condition> conditions;  // AND-joined
  QString orderBy;
  bool orderDesc = false;
  int limit = 50;
  bool ok = false;  // true when at least one recognized clause was parsed
};

// Pure parser for the mini query language embedded in Notes. Tokenizes on
// whitespace; each token is `field:spec`. Comparison prefixes on the spec
// (`<`, `<=`, `>`, `>=`) select the operator; a comma-separated spec becomes an
// In. `sort:field` / `sort:-field` and `limit:N` are recognized specially.
// Unknown fields and malformed tokens are skipped.
class QueryParser {
 public:
  static ParsedQuery parse(const QString& text);
};

}  // namespace heap::query
