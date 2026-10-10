#pragma once

#include <QDateTime>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVector>

namespace heap::chrono {
class ChronoParser;
}

// The command line's input (APP-267): what the person typed in the language
// quick capture speaks — "заблок p0 до пт оформ" — read as query clauses
// for the task search plus the words left over. A pure function of the text,
// the board's columns, the date parser and `now`.
namespace heap::query {

struct CommandToken {
  QString words;   // as typed ("заблок", "до пт", "p0")
  QString kind;    // "status" | "priority" | "tag" | "due" | "when" | "ticket" | "clause"
  QString clause;  // the search clause it stands for ("status:blocked", "due:<=2026-10-16")
  QString value;   // what a chip shows after its key ("Заблокировано", "P0", "до пт")

  bool operator==(const CommandToken& o) const = default;
};

struct CommandQuery {
  // ">" first: commands only, `text` is what to look them up by.
  bool commandsOnly = false;
  QVector<CommandToken> tokens;
  // The words that are no clause, whitespace collapsed.
  QString text;
  // Clauses then words: what the task search runs.
  QString query() const;
};

// A column named by the start of one of its words, three letters at least:
// "заблок" → the column called "Заблокировано", "rev" → "In review". The
// column's id; empty when no column, or more than one, starts so.
QString statusByPrefix(const QString& word, const QVariantList& statuses);

// `scheduledField`: the search knows a `scheduled:` clause, so a date with no
// deadline word ("завтра") is a filter too; without it such words stay words.
CommandQuery parseCommandLine(
    const QString& text, const QVariantList& statuses, const heap::chrono::ChronoParser* chrono, const QDateTime& now, bool scheduledField);

}  // namespace heap::query
