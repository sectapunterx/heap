#pragma once

#include "ChronoTypes.h"

#include <QDateTime>
#include <QLocale>
#include <QString>
#include <QVector>

#include <memory>

namespace heap::chrono {

class ChronoParser {
public:
    explicit ChronoParser(const QLocale &userLocale = QLocale());
    ~ChronoParser();

    /// Parse the first datetime expression found in \p text.
    /// \param now Reference moment for relatives ("tomorrow"/"in 2 days"/…).
    ///            When invalid, QDateTime::currentDateTime() is used.
    ParseResult parse(const QString &text, const QDateTime &now = QDateTime()) const;

    /// Parse every datetime expression found in \p text. Each result has the
    /// `consumed`/`startOffset`/`endOffset` populated so the caller can carve
    /// the remaining text into "title" / "date".
    QVector<ParseResult> parseAll(const QString &text, const QDateTime &now = QDateTime()) const;

private:
    class Impl;
    std::unique_ptr<Impl> m_impl;
};

} // namespace heap::chrono
