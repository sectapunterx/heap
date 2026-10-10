#pragma once

#include "Models.h"

namespace SampleData {
// Seed-content language. Selects between the EN and RU sample profile
// shipped on first launch. The default mirrors AppController's default
// language ("en") so a fresh user without a state file lands in English.
enum class Lang { En, Ru };

QVector<Task> tasks(Lang lang = Lang::En);
// The example's area labels (payments, auth, ui…), as H2-List shows them
// before the priority (DG-031). Same in both languages.
void addExampleLabels(QVector<Task>& tasks);
QVector<CalEvent> events(const QDate& today, Lang lang = Lang::En);
QVector<Person> people(Lang lang = Lang::En);
// Column names follow the seed language; the ids never change, so a column
// renamed or translated still means the same thing to sync and automation.
QVector<QVariantMap> statuses(Lang lang = Lang::En);
// A first note, so the Notes view does not open on nothing in the demo.
QVector<Note> notes(Lang lang = Lang::En);
}  // namespace SampleData
