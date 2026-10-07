#pragma once

#include "safety/EndOfDay.h"

#include <QString>

// The words the safety net (APP-157…) says from C++: notice titles and bodies.
// Kept out of AppController's own table the way the integrations' and saved
// views' strings are, and looked up through the same tr_() chain.
namespace heap::safety {

// `key` in the UI language, or a null QString when it is not a safety string.
QString text(const QString& key, bool ru);

// "1 file" / "2 files"; in Russian the three plural forms ("1 файл",
// "3 файла", "5 файлов"). `forms` is "one|few|many" (en: "one|many|many").
QString plural(int n, const QString& forms);

// The body of the end-of-day notice, its parts joined by " · ":
// "Timer still running · 3 uncommitted files in heap · 2 tasks in progress
// without a move for 3+ days". Empty when there is nothing to say.
QString endOfDaySummary(const EndOfDayFindings& f, int staleDays, bool ru);

// The day's summary in one line (APP-190): "3 closed today · 2 carry over to
// tomorrow". Running timers are said by endOfDaySummary. Empty when neither.
QString daySummaryLine(const DaySummary& s, bool ru);

}  // namespace heap::safety
