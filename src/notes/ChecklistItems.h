#pragma once

#include <QRegularExpression>
#include <QString>
#include <QStringList>

namespace heap::notes {

// The open "- [ ] …" items of a markdown note, their text trimmed, in order
// (R2-070: "Пункты «- [ ]» превращать в задачи" on a folder import). Ticked
// items, empty items and anything inside a ``` fence are left out.
inline QStringList openChecklistItems(const QString& markdown) {
  static const QRegularExpression item(QStringLiteral("^\\s*[-*+]\\s+\\[ \\]\\s+(.*\\S)\\s*$"));
  QStringList out;
  bool fence = false;
  for(const QString& line : markdown.split(QLatin1Char('\n'))) {
    const QString t = line.trimmed();
    if(t.startsWith(QStringLiteral("```")) || t.startsWith(QStringLiteral("~~~"))) {
      fence = !fence;
      continue;
    }
    if(fence) {
      continue;
    }
    const QRegularExpressionMatch m = item.match(line);
    if(m.hasMatch()) {
      out << m.captured(1);
    }
  }
  return out;
}

}  // namespace heap::notes
