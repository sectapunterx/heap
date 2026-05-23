#pragma once

#include "Models.h"

namespace SampleData {
// Seed-content language. Selects between the EN and RU sample profile
// shipped on first launch. The default mirrors AppController's default
// language ("en") so a fresh user without a state file lands in English.
enum class Lang { En, Ru };

QVector<Task> tasks(Lang lang = Lang::En);
QVector<CalEvent> events(const QDate& today, Lang lang = Lang::En);
QVector<Person> people(Lang lang = Lang::En);
QVector<QVariantMap> statuses();
}  // namespace SampleData
