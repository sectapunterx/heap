#include "chrono/ChronoParser.h"
#include "local/Effective.h"
#include "query/TaskQuery.h"

#include <QDateTime>
#include <QHash>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSet>

namespace heap::query {

namespace {

const QSet<QString>& knownFields() {
  static const QSet<QString> f = {QStringLiteral("status"),
                                  QStringLiteral("priority"),
                                  QStringLiteral("deadline"),
                                  QStringLiteral("due"),
                                  QStringLiteral("profile"),
                                  QStringLiteral("mention"),
                                  QStringLiteral("tag"),
                                  QStringLiteral("is"),
                                  QStringLiteral("scheduled"),
                                  QStringLiteral("estimate"),
                                  QStringLiteral("branch"),
                                  QStringLiteral("has"),
                                  QStringLiteral("sprint"),
                                  QStringLiteral("sort"),
                                  QStringLiteral("limit")};
  return f;
}

// Whitespace-separated tokens, except that a double-quoted run stays one token
// with its quotes removed: status:"code review".
QStringList tokenize(const QString& text) {
  QStringList out;
  QString cur;
  bool quoted = false;
  bool any = false;
  for(const QChar c : text) {
    if(c == QLatin1Char('"')) {
      quoted = !quoted;
      any = true;
      continue;
    }
    if(c.isSpace() && !quoted) {
      if(any) {
        out << cur;
      }
      cur.clear();
      any = false;
      continue;
    }
    cur.append(c);
    any = true;
  }
  if(any) {
    out << cur;
  }
  return out;
}

// "Code Review" → "code-review": how a column name is typed without quotes.
QString slug(const QString& s) {
  QString out;
  for(const QChar c : s.toLower()) {
    out.append(c.isLetterOrNumber() ? c : QChar('-'));
  }
  static const QRegularExpression dashes(QStringLiteral("-+"));
  out.replace(dashes, QStringLiteral("-"));
  while(out.startsWith(QLatin1Char('-'))) {
    out.remove(0, 1);
  }
  while(out.endsWith(QLatin1Char('-'))) {
    out.chop(1);
  }
  return out;
}

// A token of the shape `field:value` with a word for a field — as opposed to a
// URL ("https://…"), a time ("10:30") or a lone colon.
bool looksLikeFieldToken(const QString& token, QString* field, QString* value) {
  static const QRegularExpression rx(QStringLiteral("^([A-Za-z]+):(.+)$"));
  const QRegularExpressionMatch m = rx.match(token);
  if(!m.hasMatch() || m.captured(2).startsWith(QStringLiteral("//"))) {
    return false;
  }
  *field = m.captured(1).toLower();
  *value = m.captured(2);
  return true;
}

// Strip a leading comparison operator from `spec`.
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

// Resolve a `deadline:` value to a date. Accepts what the app's own date
// parser accepts ("friday", "tomorrow", "in 2 days", "2026-09-24") plus the
// bare "3d" shorthand a query language is expected to have.
// "@week", "@today", "@tomorrow" and their Russian words: the plan they name,
// as a scheduled: value; empty for any other token.
QString shorthandWhen(const QString& token) {
  if(token.size() < 2 || !token.startsWith(QLatin1Char('@'))) {
    return {};
  }
  static const QHash<QString, QString> kWhen = {
      {QStringLiteral("week"), QStringLiteral("week")},     {QStringLiteral("неделя"), QStringLiteral("week")},
      {QStringLiteral("неделе"), QStringLiteral("week")},   {QStringLiteral("today"), QStringLiteral("today")},
      {QStringLiteral("сегодня"), QStringLiteral("today")}, {QStringLiteral("tomorrow"), QStringLiteral("1d")},
      {QStringLiteral("завтра"), QStringLiteral("1d")}};
  return kWhen.value(token.mid(1).toLower());
}

QDate resolveDate(const QString& raw, const QDate& today, bool& ok) {
  ok = false;
  const QString v = raw.trimmed();
  if(v.isEmpty()) {
    return {};
  }
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
  if(v.compare(QStringLiteral("today"), Qt::CaseInsensitive) == 0) {
    ok = true;
    return today;
  }
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

// "30m", "1.5h", "2ч", "45м", "90" (minutes) → minutes; -1 when unreadable.
int parseMinutes(const QString& raw) {
  static const QRegularExpression rx(QStringLiteral("^(\\d+(?:[.,]\\d+)?)\\s*(m|min|h|ч|м|мин)?$"),
                                     QRegularExpression::CaseInsensitiveOption);
  const QRegularExpressionMatch m = rx.match(raw.trimmed());
  if(!m.hasMatch()) {
    return -1;
  }
  const double n = QString(m.captured(1)).replace(QLatin1Char(','), QLatin1Char('.')).toDouble();
  const QString unit = m.captured(2).toLower();
  const bool hours = unit == QLatin1String("h") || unit == QStringLiteral("ч");
  return static_cast<int>(hours ? n * 60.0 + 0.5 : n + 0.5);
}

bool compareInt(int lhs, Op op, int rhs) {
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

QString haystackOf(const Task& t) {
  QStringList parts{t.title, t.id, t.desc, t.assignee, t.externalMeta.project};
  for(const Label& l : t.labels) {
    parts << l.id;
  }
  for(const LocalTag& l : t.local.tags) {
    parts << l.id;
  }
  parts << t.local.notes << t.local.commentDraft;
  return parts.join(QChar(' ')).toLower();
}

}  // namespace

QStringList queryFields() {
  QStringList out(knownFields().cbegin(), knownFields().cend());
  out.sort();
  return out;
}

TaskQuery TaskQuery::compile(const QString& text, const QDate& today, const QVariantList& statuses, const QStringList& newIds) {
  TaskQuery q;
  q.m_today = today;
  q.m_newIds = QSet<QString>(newIds.cbegin(), newIds.cend());
  q.m_groups.append(QVector<Clause>());
  // The search words of each OR group, parallel to m_groups. Without an OR
  // they are the one free text the caller substring-matches; with one, each
  // group's words are a clause of that group, so "a OR b" means either word
  // rather than the phrase "a b" (TASKS-4).
  QVector<QStringList> groupWords(1);
  const auto addWord = [&groupWords](const QString& w) {
    groupWords.last() << w;
  };

  for(QString token : tokenize(text)) {
    if(token == QStringLiteral("OR") || token == QStringLiteral("|")) {
      if(!q.m_groups.constLast().isEmpty() || !groupWords.constLast().isEmpty()) {
        q.m_groups.append(QVector<Clause>());
        groupWords.append(QStringList());
      }
      q.m_isQuery = true;
      continue;
    }
    bool negate = false;
    if(token.size() > 1 && token.startsWith(QLatin1Char('-'))) {
      negate = true;
      token = token.mid(1);
    }
    QString field;
    QString spec;
    // The shorthands the filter's placeholder offers, as quick capture reads
    // them (PERSONA-14): "p1" is a priority, "@week" / "@неделя" a plan.
    static const QRegularExpression kPriority(QStringLiteral("^[pP][0-3]$"));
    const QString when = shorthandWhen(token);
    // "#infra" is a label; "#42" is an issue number, searched for as text.
    static const QRegularExpression kIssueNo(QStringLiteral("^#\\d+$"));
    if(kPriority.match(token).hasMatch()) {
      field = QStringLiteral("priority");
      spec = token.toLower();
    } else if(!when.isEmpty()) {
      field = QStringLiteral("scheduled");
      spec = when;
    } else if(token.size() > 1 && token.startsWith(QLatin1Char('#')) && !kIssueNo.match(token).hasMatch()) {
      field = QStringLiteral("tag");
      spec = token.mid(1);
    } else if(!looksLikeFieldToken(token, &field, &spec)) {
      if(negate) {
        q.m_negatedWords << token.toLower();
        q.m_isQuery = true;
      } else {
        addWord(token.toLower());
      }
      continue;
    }
    const QString typed = (negate ? QStringLiteral("-") : QString()) + token;
    if(!knownFields().contains(field)) {
      // Not a field: searched for as typed, and said so.
      q.m_unknown << typed;
      addWord((negate ? QStringLiteral("-") : QString()) + token.toLower());
      continue;
    }
    // Recognised as a clause, so it is never also matched as a search word.
    q.m_isQuery = true;
    if(field == QLatin1String("sort") || field == QLatin1String("limit") || field == QLatin1String("profile")) {
      // A saved view's business, or meaningful only across profiles: parsed so
      // it is not substring-matched, and steers nothing on one board.
      continue;
    }

    Clause cl;
    cl.field = field == QLatin1String("due") ? QStringLiteral("deadline") : field;
    cl.negate = negate;
    cl.op = takeOp(spec);
    for(const QString& raw : spec.split(QLatin1Char(','), Qt::SkipEmptyParts)) {
      QString v = raw.trimmed().toLower();
      if(cl.field == QLatin1String("mention") && v.startsWith(QLatin1Char('@'))) {
        v = v.mid(1);
      }
      if(!v.isEmpty()) {
        cl.values << v;
      }
    }
    if(cl.values.isEmpty()) {
      q.m_unknown << typed;
      continue;
    }
    if(cl.op == Op::Eq && cl.values.size() > 1) {
      cl.op = Op::In;
    }

    bool ok = true;
    if(cl.field == QLatin1String("status")) {
      for(const QString& v : cl.values) {
        const QString vs = slug(v);
        bool hit = false;
        for(const QVariant& sv : statuses) {
          const QVariantMap m = sv.toMap();
          const QString id = m.value(QStringLiteral("id")).toString();
          const QString name = m.value(QStringLiteral("name")).toString();
          if(id.toLower() == v || name.toLower() == v || slug(name) == vs || slug(id) == vs) {
            cl.statusIds.insert(id);
            hit = true;
          }
        }
        if(statuses.isEmpty()) {
          cl.statusIds.insert(v);  // no catalog: ids as typed
          hit = true;
        }
        ok = ok && hit;
      }
      ok = ok && !cl.statusIds.isEmpty();
    } else if(cl.field == QLatin1String("priority")) {
      QStringList norm;
      for(const QString& v : cl.values) {
        const QString p = v.startsWith(QLatin1Char('p')) ? v : QStringLiteral("p") + v;
        static const QRegularExpression kPri(QStringLiteral("^p[0-3]$"));
        if(!kPri.match(p).hasMatch()) {
          ok = false;
          continue;
        }
        norm << p;
      }
      cl.values = norm;
      ok = ok && !norm.isEmpty();
    } else if(cl.field == QLatin1String("is")) {
      static const QSet<QString> kIs = {QStringLiteral("open"),
                                        QStringLiteral("done"),
                                        QStringLiteral("closed"),
                                        QStringLiteral("archived"),
                                        QStringLiteral("overdue"),
                                        QStringLiteral("recurring"),
                                        QStringLiteral("undated"),
                                        QStringLiteral("new"),
                                        QStringLiteral("someday"),
                                        QStringLiteral("unscheduled"),
                                        QStringLiteral("blocked")};
      for(const QString& v : cl.values) {
        ok = ok && kIs.contains(v);
        q.m_usesBlocked = q.m_usesBlocked || v == QLatin1String("blocked");
      }
    } else if(cl.field == QLatin1String("has")) {
      static const QSet<QString> kHas = {
          QStringLiteral("notes"), QStringLiteral("draft"), QStringLiteral("checklist"), QStringLiteral("links"), QStringLiteral("tags")};
      for(const QString& v : cl.values) {
        ok = ok && kHas.contains(v);
      }
    } else if(cl.field == QLatin1String("estimate")) {
      if(cl.values.first() == QLatin1String("none")) {
        cl.special = QStringLiteral("none");
      } else {
        cl.minutes = parseMinutes(cl.values.first());
        ok = cl.minutes >= 0;
        if(cl.op == Op::In) {
          cl.op = Op::Eq;
        }
      }
    } else if(cl.field == QLatin1String("deadline") || cl.field == QLatin1String("scheduled")) {
      const QString v = cl.values.first();
      if(v == QLatin1String("none")) {
        cl.special = QStringLiteral("none");
      } else if(v == QLatin1String("overdue")) {
        cl.special = QStringLiteral("overdue");
      } else if(v == QLatin1String("week") || v == QLatin1String("thisweek") || v == QLatin1String("this week")) {
        cl.special = QStringLiteral("range");
        cl.date = today;
        cl.dateTo = today.addDays(7 - today.dayOfWeek());  // through Sunday
      } else {
        cl.date = resolveDate(v, today, ok);
      }
    }
    if(!ok) {
      // A clause that cannot mean anything is dropped rather than matching
      // nothing — "deadline:banana" is a typo, not a request for an empty
      // board — and reported.
      q.m_unknown << typed;
      continue;
    }
    q.m_groups.last().append(cl);
  }
  if(q.m_groups.size() > 1 && q.m_groups.constLast().isEmpty() && groupWords.constLast().isEmpty()) {
    q.m_groups.removeLast();  // a trailing OR
    groupWords.removeLast();
  }
  if(q.m_groups.size() == 1) {
    q.m_freeText = groupWords.constFirst().join(QChar(' '));
    return q;
  }
  for(int i = 0; i < q.m_groups.size(); ++i) {
    if(!groupWords.at(i).isEmpty()) {
      Clause words;
      words.field = QStringLiteral("text");
      words.values << groupWords.at(i).join(QChar(' '));
      q.m_groups[i].append(words);
    }
  }
  return q;
}

bool TaskQuery::clauseMatches(const Clause& c, const Task& t, const QString& haystack) const {
  if(c.field == QLatin1String("sprint")) {
    // A Jira sprint as the last pull saw it (APP-255): "current" is the
    // active one, "none" no sprint, anything else a part of its name.
    const QJsonObject sprint = t.externalMeta.details.value(QStringLiteral("sprint")).toObject();
    const QString name = sprint.value(QStringLiteral("name")).toString().toLower();
    for(const QString& v : c.values) {
      if(v == QLatin1String("current") || v == QLatin1String("active")) {
        if(sprint.value(QStringLiteral("state")).toString() == QLatin1String("active")) {
          return true;
        }
      } else if(v == QLatin1String("none")) {
        if(name.isEmpty()) {
          return true;
        }
      } else if(!name.isEmpty() && name.contains(v)) {
        return true;
      }
    }
    return false;
  }
  if(c.field == QLatin1String("text")) {
    return haystack.contains(c.values.constFirst());
  }
  if(c.field == QLatin1String("status")) {
    return c.statusIds.contains(t.status) || c.statusIds.contains(t.status.toLower());
  }
  if(c.field == QLatin1String("priority")) {
    return c.values.contains(heap::local::effectivePriority(t).toLower());
  }
  if(c.field == QLatin1String("tag")) {
    for(const Label& l : t.labels) {
      if(c.values.contains(l.id.toLower())) {
        return true;
      }
    }
    // My own tags answer the same #tag, whatever tracker the card is from.
    for(const LocalTag& l : t.local.tags) {
      if(c.values.contains(l.id.toLower())) {
        return true;
      }
    }
    return false;
  }
  if(c.field == QLatin1String("branch")) {
    const QString b = t.branch.toLower();
    for(const QString& v : c.values) {
      if(v == QLatin1String("none") ? b.isEmpty() : b.contains(v)) {
        return true;
      }
    }
    return false;
  }
  if(c.field == QLatin1String("has")) {
    for(const QString& v : c.values) {
      bool hit = false;
      if(v == QLatin1String("notes")) {
        hit = !t.local.notes.trimmed().isEmpty();
      } else if(v == QLatin1String("draft")) {
        hit = !t.local.commentDraft.trimmed().isEmpty();
      } else if(v == QLatin1String("checklist")) {
        hit = !t.local.checklist.isEmpty();
      } else if(v == QLatin1String("links")) {
        hit = !t.local.related.isEmpty() || !t.links.isEmpty();
      } else if(v == QLatin1String("tags")) {
        hit = !t.local.tags.isEmpty();
      }
      if(hit) {
        return true;
      }
    }
    return false;
  }
  if(c.field == QLatin1String("estimate")) {
    if(c.special == QLatin1String("none")) {
      return t.estimateMinutes <= 0;
    }
    // A task with no estimate satisfies no comparison, as with dates.
    return t.estimateMinutes > 0 && compareInt(t.estimateMinutes, c.op, c.minutes);
  }
  if(c.field == QLatin1String("mention")) {
    // Who it is about: the tracker's assignee, or an @name in the text.
    for(const QString& v : c.values) {
      if(t.assignee.toLower() == v || t.desc.toLower().contains(QChar('@') + v) || t.title.toLower().contains(QChar('@') + v)) {
        return true;
      }
    }
    return false;
  }
  if(c.field == QLatin1String("is")) {
    const bool done = t.status == QStringLiteral("done");
    for(const QString& v : c.values) {
      bool hit = false;
      if(v == QLatin1String("open")) {
        hit = !done && !t.archived;
      } else if(v == QLatin1String("done") || v == QLatin1String("closed")) {
        hit = done;
      } else if(v == QLatin1String("archived")) {
        hit = t.archived;
      } else if(v == QLatin1String("overdue")) {
        hit = !done && heap::local::effectiveDueAt(t).isValid() && heap::local::effectiveDueAt(t).date() < m_today;
      } else if(v == QLatin1String("recurring")) {
        hit = !t.recurrence.isEmpty();
      } else if(v == QLatin1String("undated")) {
        // No plan and no deadline, and not parked for "someday" (APP-260).
        hit = !done && !t.archived && !t.someday && !t.scheduledAt.isValid() && !heap::local::effectiveDueAt(t).isValid();
      } else if(v == QLatin1String("new")) {
        hit = m_newIds.contains(t.id);
      } else if(v == QLatin1String("someday")) {
        hit = t.someday && !done && !t.archived;
      } else if(v == QLatin1String("unscheduled")) {
        // Open, not parked, and no "when" (a deadline alone is not a plan).
        hit = !done && !t.archived && !t.someday && !t.scheduledAt.isValid();
      } else if(v == QLatin1String("blocked")) {
        hit = !done && m_blocked.contains(t.id);
      }
      if(hit) {
        return true;
      }
    }
    return false;
  }
  if(c.field == QLatin1String("deadline") || c.field == QLatin1String("scheduled")) {
    const QDateTime at = c.field == QLatin1String("scheduled") ? t.scheduledAt : heap::local::effectiveDueAt(t);
    const QDate due = at.isValid() ? at.date() : QDate();
    if(c.special == QLatin1String("none")) {
      return !due.isValid();
    }
    // An undated task satisfies no comparison — it is not "before Friday",
    // it is simply not scheduled.
    if(!due.isValid()) {
      return false;
    }
    if(c.special == QLatin1String("overdue")) {
      return due < m_today && t.status != QStringLiteral("done");
    }
    if(c.special == QLatin1String("range")) {
      return due >= c.date && due <= c.dateTo;
    }
    return compareDate(due, c.op, c.date);
  }
  return true;
}

bool TaskQuery::matches(const Task& t, const QString& haystack) const {
  // The caller's haystack when it has one (the model's cached search text,
  // which the free text is matched against too), else built here.
  QString built;
  const auto hay = [&]() -> const QString& {
    if(!haystack.isEmpty()) {
      return haystack;
    }
    if(built.isEmpty()) {
      built = haystackOf(t);
    }
    return built;
  };
  if(!m_negatedWords.isEmpty()) {
    for(const QString& w : m_negatedWords) {
      if(hay().contains(w)) {
        return false;
      }
    }
  }
  bool anyClauses = false;
  for(const QVector<Clause>& group : m_groups) {
    if(group.isEmpty()) {
      continue;
    }
    anyClauses = true;
    bool all = true;
    for(const Clause& c : group) {
      const bool hit = c.field == QLatin1String("text") ? clauseMatches(c, t, hay()) : clauseMatches(c, t, QString());
      if(hit == c.negate) {
        all = false;
        break;
      }
    }
    if(all) {
      return true;
    }
  }
  return !anyClauses;
}

QSet<QString> openlyBlockedIds(const QVector<Task>& tasks, const std::function<bool(const Task&)>& isDone) {
  QSet<QString> out;
  for(const Task& t : tasks) {
    if(t.links.isEmpty() || t.archived || isDone(t)) {
      continue;
    }
    for(const TaskLink& l : t.links) {
      if(l.type == QLatin1String("blocks")) {
        out.insert(l.targetId);
      }
    }
  }
  return out;
}

}  // namespace heap::query
