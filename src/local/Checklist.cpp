#include "local/Checklist.h"

#include <QStringList>
#include <QUuid>

#include <algorithm>

namespace heap::local::checklist {

namespace {

bool isBlank(QChar c) {
  return c == QLatin1Char(' ') || c == QLatin1Char('\t');
}

// The direct children of items[i] (or the roots for i == -1), as start
// indices of their subtrees.
QVector<int> childStarts(const QVector<LocalCheckItem>& items, int i) {
  QVector<int> out;
  const int begin = i + 1;
  const int end = i < 0 ? static_cast<int>(items.size()) : subtreeEnd(items, i);
  for(int j = begin; j < end; j = subtreeEnd(items, j)) {
    out.append(j);
  }
  return out;
}

int parentOf(const QVector<LocalCheckItem>& items, int i) {
  for(int k = i - 1; k >= 0; --k) {
    if(items.at(k).level < items.at(i).level) {
      return k;
    }
  }
  return -1;
}

}  // namespace

QString newId() {
  return QUuid::createUuid().toString(QUuid::WithoutBraces).left(8);
}

Line parseLine(const QString& raw) {
  Line out;
  QString s = raw;
  // Trailing whitespace (and a \r from a pasted Windows text) is noise.
  while(!s.isEmpty() && s.back().isSpace()) {
    s.chop(1);
  }
  const bool indented = !s.isEmpty() && s.front().isSpace();
  qsizetype pos = 0;
  while(pos < s.size() && s.at(pos).isSpace()) {
    ++pos;
  }
  // The longest run of dashes and blanks that ends in a dash followed by a
  // blank (or by the end of the line). "-5 degrees" has none, so it is text.
  int dashes = 0;
  int validDashes = 0;
  qsizetype validEnd = -1;
  for(qsizetype k = pos; k < s.size(); ++k) {
    const QChar c = s.at(k);
    if(c == QLatin1Char('-')) {
      ++dashes;
      if(k + 1 == s.size() || isBlank(s.at(k + 1))) {
        validDashes = dashes;
        validEnd = k + 1;
      }
    } else if(!isBlank(c)) {
      break;
    }
  }
  if(validEnd >= 0) {
    pos = validEnd;
    // Spaces before the first dash: not nested, whatever the dashes say.
    out.level = indented ? 1 : validDashes;
  }
  while(pos < s.size() && isBlank(s.at(pos))) {
    ++pos;
  }
  // "[x]" / "[ ]" (a Cyrillic х too: same key on a Russian layout).
  if(pos + 2 < s.size() &&s.at(pos) == QLatin1Char('[') && s.at(pos + 2) == QLatin1Char(']') &&
     (pos + 3 == s.size() || isBlank(s.at(pos + 3)))) {
    const QChar m = s.at(pos + 1);
    const bool tick = m == QLatin1Char('x') || m == QLatin1Char('X') || m == QChar(0x0445) || m == QChar(0x0425);
    if(tick || m == QLatin1Char(' ')) {
      out.done = tick;
      pos += 3;
    }
  }
  out.text = s.mid(pos).trimmed();
  return out;
}

QVector<LocalCheckItem> parse(const QString& text, const QVector<LocalCheckItem>& previous) {
  QVector<LocalCheckItem> out;
  QVector<bool> used(previous.size(), false);
  const QStringList lines = text.split(QLatin1Char('\n'));
  for(const QString& raw : lines) {
    const Line l = parseLine(raw);
    if(l.text.isEmpty()) {
      continue;
    }
    LocalCheckItem c;
    c.text = l.text;
    c.level = std::max(1, l.level);
    c.done = l.done;
    // The same text keeps its id: the same row at the same place first,
    // then the first unused one with that text.
    int match = -1;
    const int here = static_cast<int>(out.size());
    if(here < previous.size() && !used.at(here) && previous.at(here).text == c.text) {
      match = here;
    } else {
      for(int k = 0; k < previous.size(); ++k) {
        if(!used.at(k) && previous.at(k).text == c.text) {
          match = k;
          break;
        }
      }
    }
    if(match >= 0) {
      used[match] = true;
      c.id = previous.at(match).id;
      c.cardId = previous.at(match).cardId;
      c.autoDone = c.done && previous.at(match).done && previous.at(match).autoDone;
    } else {
      c.id = newId();
    }
    out.append(c);
  }
  settle(out);
  return out;
}

QString serialize(const QVector<LocalCheckItem>& items) {
  QStringList lines;
  lines.reserve(items.size());
  for(const LocalCheckItem& c : items) {
    lines.append(QString(std::max(1, c.level), QLatin1Char('-')) + QLatin1Char(' ') + (c.done ? QStringLiteral("[x] ") : QString()) +
                 c.text);
  }
  return lines.join(QLatin1Char('\n'));
}

int subtreeEnd(const QVector<LocalCheckItem>& items, int i) {
  const int n = static_cast<int>(items.size());
  if(i < 0 || i >= n) {
    return n;
  }
  const int level = items.at(i).level;
  int j = i + 1;
  while(j < n && items.at(j).level > level) {
    ++j;
  }
  return j;
}

bool hasChildren(const QVector<LocalCheckItem>& items, int i) {
  return subtreeEnd(items, i) > i + 1;
}

void settle(QVector<LocalCheckItem>& items) {
  for(int i = static_cast<int>(items.size()) - 1; i >= 0; --i) {
    if(!hasChildren(items, i)) {
      items[i].autoDone = false;
      continue;
    }
    bool all = true;
    for(int c : childStarts(items, i)) {
      all = all && items.at(c).done;
    }
    if(all && !items.at(i).done) {
      items[i].done = true;
      items[i].autoDone = true;
    } else if(!all && items.at(i).done) {
      items[i].done = false;
      items[i].autoDone = false;
    }
  }
}

void setDone(QVector<LocalCheckItem>& items, int i, bool done) {
  if(i < 0 || i >= items.size()) {
    return;
  }
  const int end = subtreeEnd(items, i);
  for(int j = i; j < end; ++j) {
    items[j].done = done;
    items[j].autoDone = false;
  }
  settle(items);
}

void indent(QVector<LocalCheckItem>& items, int i, int delta) {
  if(i < 0 || i >= items.size() || delta == 0) {
    return;
  }
  if(delta < 0 && items.at(i).level + delta < 1) {
    return;
  }
  const int end = subtreeEnd(items, i);
  for(int j = i; j < end; ++j) {
    items[j].level = std::max(1, items.at(j).level + delta);
  }
  settle(items);
}

int move(QVector<LocalCheckItem>& items, int i, int dir) {
  if(i < 0 || i >= items.size() || dir == 0) {
    return -1;
  }
  const QVector<int> sibs = childStarts(items, parentOf(items, i));
  const int at = static_cast<int>(sibs.indexOf(i));
  const int other = at + (dir < 0 ? -1 : 1);
  if(at < 0 || other < 0 || other >= sibs.size()) {
    return -1;
  }
  const int first = std::min(sibs.at(at), sibs.at(other));
  const int second = std::max(sibs.at(at), sibs.at(other));
  const int secondEnd = subtreeEnd(items, second);
  // [first, second) and [second, secondEnd) swap places.
  QVector<LocalCheckItem> out = items.mid(0, first);
  out += items.mid(second, secondEnd - second);
  out += items.mid(first, second - first);
  out += items.mid(secondEnd);
  items = out;
  return dir < 0 ? first : first + (secondEnd - second);
}

void remove(QVector<LocalCheckItem>& items, int i) {
  if(i < 0 || i >= items.size()) {
    return;
  }
  items.remove(i, subtreeEnd(items, i) - i);
  settle(items);
}

Progress progress(const QVector<LocalCheckItem>& items) {
  Progress p;
  for(const LocalCheckItem& c : items) {
    ++p.total;
    p.done += c.done ? 1 : 0;
  }
  return p;
}

int nextStep(const QVector<LocalCheckItem>& items) {
  int i = -1;
  for(int k = 0; k < items.size(); ++k) {
    if(!items.at(k).done) {
      i = k;
      break;
    }
  }
  while(i >= 0) {
    int deeper = -1;
    for(int c : childStarts(items, i)) {
      if(!items.at(c).done) {
        deeper = c;
        break;
      }
    }
    if(deeper < 0) {
      break;
    }
    i = deeper;
  }
  return i;
}

}  // namespace heap::local::checklist
