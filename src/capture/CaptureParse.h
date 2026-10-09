#pragma once

#include <QDateTime>
#include <QString>
#include <QStringList>
#include <QStringView>
#include <QVector>

namespace heap::chrono {
class ChronoParser;
}

// What one line of task input means (APP-245/246/266): the dates, split into
// "when I do it" and "the deadline", and an estimate — each with where it sat
// in the line, so the input can mark it and a chip can give the words back.
// A pure function of the text, the parser and `now`.
namespace heap::capture {

// A recognised part of the line, as offsets into the text that was parsed.
struct Span {
  int start = -1;
  int end = -1;  // one past the last character
  QString kind;  // "when", "due", "estimate"
  QString text;  // the words, as typed (the deadline word included)

  bool operator==(const Span& o) const = default;
};

struct Parsed {
  // The line with the recognised parts cut out, whitespace collapsed.
  QString title;
  // A date with no deadline word: when the task is to be done.
  QDateTime when;
  bool whenHasTime = false;
  // The end of a time range said with it ("16:00-16:45"): a meeting's length.
  QDateTime whenEnd;
  // A date after a deadline word ("до пятницы", "к 15:00", "due fri", "by
  // monday"): the deadline.
  QDateTime due;
  bool dueHasTime = false;
  // "~30m", "~1.5h", "~2ч"; 0 when none.
  int estimateMinutes = 0;
  QString recurrence;
  QVector<Span> spans;
};

// The words that turn the date right after them into a deadline.
const QStringList& deadlineWords();

// Minutes in an estimate token ("~30m", "~1,5h", "~2ч", "~90мин", "~1h30m");
// 0 when `token` is not one.
int estimateMinutes(QStringView token);

// Parses `text`. The first date of each kind wins; any further dates stay in
// the title as words, so nothing is guessed from them. `rejected` lists
// recognised phrases (Span::text) the person took back with the chip's ×:
// they stay words in the title.
Parsed parse(const QString& text, const heap::chrono::ChronoParser& chrono, const QDateTime& now, const QStringList& rejected = {});

}  // namespace heap::capture
