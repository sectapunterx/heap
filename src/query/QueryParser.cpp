#include "query/QueryParser.h"

#include <QRegularExpression>
#include <QSet>

namespace heap::query {

namespace {

const QSet<QString>& filterFields() {
  static const QSet<QString> f = {QStringLiteral("status"),  QStringLiteral("priority"), QStringLiteral("deadline"),
                                  QStringLiteral("profile"), QStringLiteral("mention"),  QStringLiteral("tag")};
  return f;
}

// Strip a leading comparison operator from `spec`, returning the matching Op and
// mutating `spec` to the remainder. Defaults to Eq (no prefix).
Op takeOp(QString& spec) {
  if(spec.startsWith(QLatin1String("<="))) {
    spec = spec.mid(2);
    return Op::Le;
  }
  if(spec.startsWith(QLatin1String(">="))) {
    spec = spec.mid(2);
    return Op::Ge;
  }
  if(spec.startsWith(QLatin1Char('<'))) {
    spec = spec.mid(1);
    return Op::Lt;
  }
  if(spec.startsWith(QLatin1Char('>'))) {
    spec = spec.mid(1);
    return Op::Gt;
  }
  return Op::Eq;
}

}  // namespace

ParsedQuery QueryParser::parse(const QString& text) {
  ParsedQuery q;
  const QStringList tokens = text.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
  for(const QString& tok : tokens) {
    const int sep = tok.indexOf(QLatin1Char(':'));
    if(sep <= 0 || sep == tok.size() - 1) {
      continue;  // no field or no spec
    }
    const QString field = tok.left(sep).toLower();
    QString spec = tok.mid(sep + 1);

    if(field == QLatin1String("sort")) {
      if(spec.startsWith(QLatin1Char('-'))) {
        q.orderDesc = true;
        spec = spec.mid(1);
      }
      if(!spec.isEmpty()) {
        q.orderBy = spec;
        q.ok = true;
      }
      continue;
    }
    if(field == QLatin1String("limit")) {
      bool okNum = false;
      const int n = spec.toInt(&okNum);
      if(okNum && n > 0) {
        q.limit = n;
        q.ok = true;
      }
      continue;
    }
    if(!filterFields().contains(field)) {
      continue;  // unknown field
    }

    Condition c;
    c.field = field;
    c.op = takeOp(spec);
    QStringList vals;
    for(const QString& raw : spec.split(QLatin1Char(','), Qt::SkipEmptyParts)) {
      QString v = raw.trimmed();
      if(field == QLatin1String("mention") && v.startsWith(QLatin1Char('@'))) {
        v = v.mid(1);
      }
      if(!v.isEmpty()) {
        vals << v;
      }
    }
    if(vals.isEmpty()) {
      continue;  // e.g. "status:" or "status:@" → nothing usable
    }
    // A comma list under the default operator is set membership.
    if(c.op == Op::Eq && vals.size() > 1) {
      c.op = Op::In;
    }
    c.values = vals;
    q.conditions.append(c);
    q.ok = true;
  }
  return q;
}

}  // namespace heap::query
