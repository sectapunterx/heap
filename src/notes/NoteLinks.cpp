#include "notes/NoteLinks.h"

#include <QHash>
#include <QRegularExpression>
#include <QSet>
#include <QVariantMap>

namespace heap::notes {

namespace {

const QRegularExpression& headingRx() {
  static const QRegularExpression rx(QStringLiteral("^#{1,6}\\s+(.+?)\\s*$"));
  return rx;
}

const QRegularExpression& wikiRx() {
  static const QRegularExpression rx(QStringLiteral("\\[\\[([^\\]\\n]+)\\]\\]"));
  return rx;
}

}  // namespace

QStringList collectHeadings(const QString& markdown) {
  QStringList out;
  QSet<QString> seen;
  const auto lines = markdown.split(QChar('\n'));
  for(const QString& line : lines) {
    const auto m = headingRx().match(line);
    if(!m.hasMatch()) {
      continue;
    }
    const QString text = m.captured(1).trimmed();
    if(text.isEmpty() || seen.contains(text)) {
      continue;
    }
    seen.insert(text);
    out.append(text);
  }
  return out;
}

QVariantList collectBacklinks(const QString& markdown) {
  const QStringList headingList = collectHeadings(markdown);
  const QSet<QString> headings(headingList.cbegin(), headingList.cend());

  // Preserve first-seen target order, accumulate refs per target.
  QStringList order;
  QHash<QString, QVariantList> refsByTarget;

  const auto lines = markdown.split(QChar('\n'));
  for(int i = 0; i < lines.size(); ++i) {
    const QString& line = lines.at(i);
    auto it = wikiRx().globalMatch(line);
    while(it.hasNext()) {
      const QString target = it.next().captured(1).trimmed();
      if(target.isEmpty()) {
        continue;
      }
      if(!refsByTarget.contains(target)) {
        order.append(target);
      }
      QVariantMap ref;
      ref.insert(QStringLiteral("line"), i + 1);  // 1-based
      ref.insert(QStringLiteral("text"), line.trimmed());
      refsByTarget[target].append(ref);
    }
  }

  QVariantList out;
  order.sort(Qt::CaseInsensitive);
  for(const QString& target : order) {
    QVariantMap entry;
    entry.insert(QStringLiteral("target"), target);
    entry.insert(QStringLiteral("resolved"), headings.contains(target));
    entry.insert(QStringLiteral("refs"), refsByTarget.value(target));
    out.append(entry);
  }
  return out;
}

int headingOffset(const QString& markdown, const QString& heading) {
  const QString needle = heading.trimmed();
  if(needle.isEmpty()) {
    return -1;
  }
  int offset = 0;
  const auto lines = markdown.split(QChar('\n'));
  for(const QString& line : lines) {
    const auto m = headingRx().match(line);
    if(m.hasMatch() && m.captured(1).trimmed().compare(needle, Qt::CaseInsensitive) == 0) {
      return offset;
    }
    offset += line.size() + 1;  // +1 for the '\n' consumed by split
  }
  return -1;
}

}  // namespace heap::notes
