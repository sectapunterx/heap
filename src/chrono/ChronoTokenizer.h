#pragma once

#include "ChronoTypes.h"

#include <QString>
#include <QVector>

namespace heap::chrono {

class ChronoTokenizer {
public:
    /// Splits the input into tokens. Whitespace separates; punctuation that
    /// can carry semantic weight (':', '.', '-', '/') is emitted as its own
    /// token kind so the parser can distinguish "5.6" from "5 6".
    QVector<Token> tokenize(const QString &input) const;
};

} // namespace heap::chrono
