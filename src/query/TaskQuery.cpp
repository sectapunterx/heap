#include "chrono/ChronoParser.h"
#include "query/TaskQuery.h"

#include <QDateTime>
#include <QRegularExpression>
#include <QSet>

namespace heap::query {

namespace {

const QSet<QString>& knownFields() {
  static const QSet<QString> f = {QStringLiteral("status"),
                                  QStringLiteral("priority"),
                                  QStringLiteral("deadline"),
                                  QStringLiteral("profile"),
                                  QStringLiteral("mention"),
                                  QStringLiteral("tag"),
                                  QStringLiteral("sort"),
                                  QStringLiteral("limit")};
  return f;
}

// Is this token a clause the parser would recognise, as opposed to a search
// word that happens to contain a colon? Mirrors QueryParser's own test so the
// two never disagree about what counts as free text.
bool looksLikeClause(const QString& token) {
  const int sep = token.indexOf(QLatin1Char(':'));
  if(sep <= 0 || sep == token.size() - 1) {
    return false;
  }
  return knownFields().contains(token.left(sep).toLower());
}

// Resolve a `deadline:` value to a date. Accepts what the app's own date
// parser accepts ("friday", "tomorrow", "in 2 days", "2026-09-24") plus the
// bare "3d" shorthand a query language is expected to have.
QDate resolveDate(const QString& raw, const QDate& today, bool& ok) {
  ok = false;
  const QString v = raw.trimmed();
  if(v.isEmpty()) {
    return {};
  }
  // "7d" / "2w" — offsets from today, which chrono does not read on their own.
  static const QRegularExpression offset(QStringLiteral("^(\\d+)\\s*([dwm])$"), QRegularExpression::CaseInsensitiveOption);
  const QRegularExpressionMatch m = offset.match(v);
  if(m.hasMatch()) {
    const int n = m.captured(1).toInt();
    const QChar unit = m.captured(2).at(0).toLower();
    ok = true;
    if(unit == QLatin1Char('d')) {
      return today.addDays(n);
    }
    if(unit == QLatin1Char('w')) {
      return today.addDays(n * 7);
    }
    return today.addMonths(n);
  }
  // Everything else goes through the parser the rest of the app uses, so a
  // query understands exactly the dates the task editor does.
  const heap::chrono::ChronoParser parser;
  const heap::chrono::ParseResult r = parser.parse(v, QDateTime(today, QTime(0, 0)));
  if(r.ok && r.start.isValid()) {
    ok = true;
    return r.start.date();
  }
  return {};
}

bool compareDate(const QDate& lhs, Op op, const QDate& rhs) {
  switch(op) {
    case Op::Lt:
      return lhs < rhs;
    case Op::Le:
      return lhs <= rhs;
    case Op::Gt:
      return lhs > rhs;
    case Op::Ge:
      return lhs >= rhs;
    case Op::Eq:
    case Op::In:
      return lhs == rhs;
  }
  return false;
}

}  // namespace

QStringList queryFields() {
  QStringList out(knownFields().cbegin(), knownFields().cend());
  out.sort();
  return out;
}

TaskQuery TaskQuery::compile(const QString& text, const QDate& today) {
  TaskQuery q;
  const ParsedQuery parsed = QueryParser::parse(text);

  QStringList free;
  for(const QString& token : text.split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts)) {
    if(looksLikeClause(token)) {
      // Recognised as a clause, so it is never also matched as a search word —
      // otherwise "status:blocked" would have to appear in the task's text too.
      q.m_isQuery = true;
    } else {
      free << token.toLower();
    }
  }
  q.m_freeText = free.join(QChar(' '));

  for(const Condition& c : parsed.conditions) {
    Clause cl;
    cl.field = c.field;
    cl.op = c.op;
    for(const QString& v : c.values) {
      cl.values << v.toLower();
    }
    if(c.field == QLatin1String("deadline")) {
      // "none" is the one value that is about the absence of a date.
      if(cl.values.size() == 1 && cl.values.first() == QLatin1String("none")) {
        cl.wantsNoDate = true;
      } else {
        bool ok = false;
        cl.date = resolveDate(c.values.first(), today, ok);
        if(!ok) {
          continue;  // an unreadable date is a clause that cannot mean anything
        }
      }
    }
    q.m_clauses.append(cl);
  }
  // `sort:` and `limit:` parse but steer nothing here — they belong to a saved
  // view rather than to a filter, so they are recognised (and thus not
  // substring-matched) without adding a clause.
  return q;
}

bool TaskQuery::matches(const Task& t) const {
  for(const Clause& c : m_clauses) {
    if(c.field == QLatin1String("status")) {
      if(!c.values.contains(t.status.toLower())) {
        return false;
      }
      continue;
    }
    if(c.field == QLatin1String("priority")) {
      if(!c.values.contains(t.priority.toLower())) {
        return false;
      }
      continue;
    }
    if(c.field == QLatin1String("tag")) {
      bool hit = false;
      for(const Label& l : t.labels) {
        if(c.values.contains(l.id.toLower())) {
          hit = true;
          break;
        }
      }
      if(!hit) {
        return false;
      }
      continue;
    }
    if(c.field == QLatin1String("mention")) {
      // Who it is about: the tracker's assignee, or an @name in the text.
      bool hit = false;
      for(const QString& v : c.values) {
        if(t.assignee.toLower() == v || t.desc.toLower().contains(QChar('@') + v) || t.title.toLower().contains(QChar('@') + v)) {
          hit = true;
          break;
        }
      }
      if(!hit) {
        return false;
      }
      continue;
    }
    if(c.field == QLatin1String("deadline")) {
      const QDate due = t.dueAt.isValid() ? t.dueAt.date() : QDate();
      if(c.wantsNoDate) {
        if(due.isValid()) {
          return false;
        }
        continue;
      }
      // An undated task satisfies no comparison — it is not "before Friday",
      // it is simply not scheduled.
      if(!due.isValid() || !compareDate(due, c.op, c.date)) {
        return false;
      }
      continue;
    }
    // `profile` is meaningful across profiles, which a single board is not;
    // it parses and is ignored here rather than silently matching nothing.
  }
  return true;
}

}  // namespace heap::query
