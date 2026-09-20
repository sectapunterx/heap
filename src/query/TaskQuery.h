#pragma once

#include "Models.h"

#include "query/QueryParser.h"

#include <QDate>
#include <QString>
#include <QStringList>

namespace heap::query {

// A ParsedQuery with its date literals resolved and its free text separated
// out, ready to test rows against.
//
// QueryParser has been in the tree, finished and unit-tested, without a single
// production caller: it turns `status:blocked priority:P0,P1 deadline:<friday`
// into clauses but never says whether a given task satisfies them. This is that
// half, plus the two things a search box needs that the grammar does not model:
//
//  - Date values are resolved ONCE, here, not per row. `deadline:<friday` costs
//    one chrono parse for the whole filter pass rather than one per task.
//  - Tokens that are not clauses are kept as free text, so `status:blocked
//    login` narrows by status *and* by the word "login". Typing a query and
//    typing a search are the same act.
class TaskQuery {
 public:
  // `today` anchors relative dates ("friday", "3d"); pass the app's notion of
  // today rather than the system clock so a test can pin it.
  static TaskQuery compile(const QString& text, const QDate& today);

  // True when at least one clause was recognised. False means the text was
  // ordinary search terms and `freeText()` is all of it.
  bool isQuery() const {
    return m_isQuery;
  }

  // The tokens that were not clauses, lowercased and space-joined. Empty when
  // the whole input was clauses.
  QString freeText() const {
    return m_freeText;
  }

  // Does this task satisfy every clause? A query with no clauses matches
  // everything, so free-text-only input leaves the caller to do its own
  // substring test.
  bool matches(const Task& t) const;

 private:
  struct Clause {
    QString field;
    Op op = Op::Eq;
    QStringList values;        // lowercased
    QDate date;                // resolved for `deadline`; invalid otherwise
    bool wantsNoDate = false;  // `deadline:none`
  };

  QVector<Clause> m_clauses;
  QString m_freeText;
  bool m_isQuery = false;
};

// The fields a clause may name, for the UI to hint with. Sorted.
QStringList queryFields();

}  // namespace heap::query
