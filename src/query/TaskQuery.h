#pragma once

#include "Models.h"

#include "query/QueryParser.h"

#include <QDate>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVector>

namespace heap::query {

// A search-box query with its date literals resolved and its free text
// separated out, ready to test rows against.
//
// The grammar, as the board's search box reads it:
//
//   status:blocked            a column, by id, by name or by the name's slug —
//   status:"code review"      what the board shows, not only the internal id
//   status:in-progress
//   priority:P0,P1            comma = any of
//   tag:infra   #infra        a label
//   mention:@ada              the assignee, or an @name in the text
//   due:today  due:overdue    (deadline: is the same field) today, overdue,
//   due:week   due:<7d        this week, relative/absolute comparisons,
//   due:friday due:none       anything the date parser reads, or no date
//   is:open  is:done  is:archived  is:overdue  is:recurring
//   -clause   -#tag  -word    negation
//   a OR b    a | b           either side (clauses on each side are ANDed;
//                             a side's words are one of its clauses)
//
// Tokens that are not clauses stay free text, so `status:blocked login`
// narrows by status *and* by the word "login". A `word:word` token whose field
// is not one of the above is kept as text too (a URL, "note:foo"), but it is
// reported, as is a clause whose value cannot mean anything (an unknown column,
// P9, an unreadable date): unknownClauses() is what the search box shows, so a
// typo reads as a typo rather than as an empty board.
class TaskQuery {
 public:
  // `today` anchors relative dates ("friday", "3d"). `statuses` is the board's
  // column list ([{id, name}]) so a status can be named as the UI shows it;
  // without it only ids match.
  // `newIds` is what `is:new` matches: the cards the latest sync brought in
  // (APP-180). The caller owns that set; a CLI run has none.
  static TaskQuery compile(const QString& text, const QDate& today, const QVariantList& statuses = {}, const QStringList& newIds = {});

  // True when at least one clause (or a negated word) was recognised. False
  // means the text was ordinary search terms and `freeText()` is all of it.
  bool isQuery() const {
    return m_isQuery;
  }

  // The tokens that were not clauses, lowercased and space-joined. Empty when
  // the whole input was clauses.
  QString freeText() const {
    return m_freeText;
  }

  // What the user typed that looks like a clause but means nothing — each
  // entry is the token as typed. Empty for a clean query.
  QStringList unknownClauses() const {
    return m_unknown;
  }

  // Does this task satisfy the query? A query with no clauses matches
  // everything, so free-text-only input leaves the caller to do its own
  // substring test. `haystack` is the task's lowercased search text (the
  // model's cached one); empty = built from the task. Search words are only
  // matched here when an OR split them into groups — otherwise they are all
  // in freeText().
  bool matches(const Task& t, const QString& haystack = QString()) const;

 private:
  struct Clause {
    QString field;
    Op op = Op::Eq;
    QStringList values;       // lowercased
    QSet<QString> statusIds;  // `status`: the column ids the values named
    QDate date;               // resolved for `deadline`; invalid otherwise
    QDate dateTo;             // `deadline:week`: the end of the range
    QString special;          // `deadline`: "none" | "overdue" | "range"
    bool negate = false;
  };

  bool clauseMatches(const Clause& c, const Task& t, const QString& haystack) const;

  // OR of AND-groups.
  QVector<QVector<Clause>> m_groups;
  QStringList m_negatedWords;
  QString m_freeText;
  QStringList m_unknown;
  QDate m_today;
  QSet<QString> m_newIds;
  bool m_isQuery = false;
};

// The fields a clause may name, for the UI to hint with. Sorted.
QStringList queryFields();

}  // namespace heap::query
