#pragma once

// Generated profiles for the wall-clock suites (heap_save_bench_tests,
// heap_perf_tests). Deterministic: the same n gives the same data on every run
// and every machine, so the numbers they print are comparable over time.

#include "Models.h"

#include <QDate>
#include <QDateTime>
#include <QString>
#include <QTime>
#include <QVector>

namespace heap::bench {

// Tasks shaped like a heavy real profile: dates on most, labels, tracker links
// on every fifth, a recurrence on every tenth.
inline QVector<Task> makeTasks(int n) {
  QVector<Task> out;
  out.reserve(n);
  const QDateTime base(QDate(2026, 7, 9), QTime(9, 0));
  for(int i = 0; i < n; ++i) {
    Task t;
    t.id = QStringLiteral("BENCH-") + QString::number(i);
    t.title = QStringLiteral("Task number %1 with a realistic title length").arg(i);
    t.desc = QStringLiteral("Several lines of description text, of the sort a real ticket carries.\nSecond line.");
    t.priority = QStringLiteral("P%1").arg(i % 4);
    t.status = (i % 3 == 0) ? QStringLiteral("todo") : QStringLiteral("prog");
    t.scheduledAt = base.addDays(i % 90);
    t.dueAt = base.addDays((i % 90) + 1);
    t.scheduledHasTime = (i % 2) == 0;
    t.dueHasTime = (i % 2) == 0;
    t.branch = QStringLiteral("feature/bench-") + QString::number(i);
    t.statusChangedAt = base;
    t.trackedSeconds = i;
    t.recurrence = (i % 10 == 0) ? QStringLiteral("every:weekday") : QString();
    if(i % 5 == 0) {
      t.externalId = QString::number(i);
      t.externalUrl = QStringLiteral("https://example.invalid/") + t.externalId;
      t.externalProvider = QStringLiteral("github");
    }
    t.labels = {Label{.id = QStringLiteral("bench"), .color = QStringLiteral("#5cc2dd")},
                Label{.id = QStringLiteral("p") + QString::number(i % 4), .color = QString()}};
    t.estimateMinutes = 30 + (i % 240);
    out.append(t);
  }
  return out;
}

// A note body of roughly `approximateChars`, with the mix a real note has —
// headings (full-text search splits on them), prose, lists, a table, code.
inline QString makeNoteBody(int seed, int approximateChars) {
  QString out;
  out.reserve(approximateChars + 512);
  for(int section = 0; out.size() < approximateChars; ++section) {
    out += QStringLiteral("## Section %1 of note %2\n\n").arg(section).arg(seed);
    out += QStringLiteral(
        "A paragraph with **strong** text, _emphasis_, `inline code`, a [link](https://example.com), "
        "a [[wiki link]], a #tag and some Cyrillic: текст заметки.\n\n"
        "- [ ] an open task\n"
        "- [x] a finished one\n"
        "  - a nested item\n\n"
        "| column | other |\n"
        "|--------|------:|\n"
        "| value  |    42 |\n\n"
        "```cpp\n"
        "int answer() { return 42; }\n"
        "```\n\n");
  }
  return out;
}

inline QVector<Note> makeNotes(int n, int approximateChars) {
  QVector<Note> out;
  out.reserve(n);
  const QDateTime base(QDate(2026, 7, 9), QTime(9, 0));
  for(int i = 0; i < n; ++i) {
    Note note;
    note.id = QStringLiteral("note-") + QString::number(i);
    note.title = QStringLiteral("Bench note %1").arg(i);
    note.folder = QStringLiteral("folder-%1").arg(i % 8);
    note.body = makeNoteBody(i, approximateChars);
    note.created = base;
    note.updated = base.addSecs(i);
    out.append(note);
  }
  return out;
}

}  // namespace heap::bench
