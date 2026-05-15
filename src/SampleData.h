#pragma once

#include "Models.h"

namespace SampleData {
    QVector<Task>     tasks();
    QVector<CalEvent> events(const QDate &today);
    QVector<Person>   people();
    QVector<QVariantMap> statuses();
}
