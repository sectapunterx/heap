#include "capture/CaptureParse.h"
#include "chrono/ChronoParser.h"
#include "query/CommandQuery.h"

#include <QRegularExpression>
#include <QVariantMap>

#include <algorithm>

namespace heap::query {

namespace {

bool allLetters(const QString& w) {
  return !w.isEmpty() && std::all_of(w.cbegin(), w.cend(), [](QChar c) {
    return c.isLetter();
  });
}

}  // namespace

QString CommandQuery::query() const {
  QStringList parts;
  QStringList statusIds;
  for(const CommandToken& t : tokens) {
    if(t.kind == QLatin1String("status") && t.clause.startsWith(QLatin1String("status:"))) {
      const QString id = t.clause.mid(7);
      if(!statusIds.contains(id)) {
        statusIds << id;
      }
      continue;
    }
    parts << t.clause;
  }
  if(!statusIds.isEmpty()) {
    parts.prepend(QStringLiteral("status:") + statusIds.join(QLatin1Char(',')));
  }
  if(!text.isEmpty()) {
    parts << text;
  }
  return parts.join(QLatin1Char(' '));
}

QString statusByPrefix(const QString& word, const QVariantList& statuses) {
  const QString w = word.toLower();
  if(w.size() < 3 || !allLetters(w)) {
    return {};
  }
  static const QRegularExpression split(QStringLiteral("[^\\p{L}\\p{N}]+"));
  QString found;
  for(const QVariant& v : statuses) {
    const QVariantMap m = v.toMap();
    const QString id = m.value(QStringLiteral("id")).toString();
    const QString name = m.value(QStringLiteral("name")).toString().toLower();
    bool hit = id.toLower().startsWith(w);
    for(const QString& part : name.split(split, Qt::SkipEmptyParts)) {
      hit = hit || part.startsWith(w);
    }
    if(!hit) {
      continue;
    }
    if(!found.isEmpty() && found != id) {
      return {};  // two columns start so: the word stays a word
    }
    found = id;
  }
  return found;
}

CommandQuery parseCommandLine(const QString& text,
                              const QVariantList& statuses,
                              const heap::chrono::ChronoParser* chrono,
                              const QDateTime& now,
                              bool scheduledField) {
  CommandQuery out;
  QString input = text.trimmed();
  if(input.startsWith(QLatin1Char('>'))) {
    out.commandsOnly = true;
    out.text = input.mid(1).simplified();
    return out;
  }

  static const QRegularExpression clauseRx(QStringLiteral("^-?[A-Za-z]+:\\S+$"));
  static const QRegularExpression priorityRx(QStringLiteral("^[pP]([0-3])$"));
  static const QRegularExpression tagRx(QStringLiteral("^#(\\S+)$"));
  static const QRegularExpression ruKeyRx(QStringLiteral("^(статус|приоритет):(\\S+)$"),
                                          QRegularExpression::CaseInsensitiveOption | QRegularExpression::UseUnicodePropertiesOption);
  static const QRegularExpression ticketRx(QStringLiteral("^[A-Za-z][A-Za-z0-9]*-\\d+$"));

  // Where each recognised token sat, to give them back in typed order.
  QVector<QPair<int, CommandToken>> found;
  QStringList rest;
  int cursor = 0;
  for(const QString& word : input.split(QLatin1Char(' '), Qt::SkipEmptyParts)) {
    const int at = static_cast<int>(input.indexOf(word, cursor));
    cursor = at + static_cast<int>(word.size());
    QRegularExpressionMatch m;
    // The chips' own words typed back ("статус:заблок", "приоритет:p0"):
    // the Russian keys the line shows on its chips (DG-080).
    if((m = ruKeyRx.match(word)).hasMatch()) {
      const QString value = m.captured(2);
      if(m.captured(1).toLower() == QStringLiteral("статус")) {
        const QString id = statusByPrefix(value, statuses);
        if(!id.isEmpty()) {
          QString name = id;
          for(const QVariant& v : statuses) {
            if(v.toMap().value(QStringLiteral("id")).toString() == id) {
              name = v.toMap().value(QStringLiteral("name")).toString();
            }
          }
          found.append({at, {word, QStringLiteral("status"), QStringLiteral("status:") + id, name}});
          continue;
        }
      } else if(const QRegularExpressionMatch pm = priorityRx.match(value); pm.hasMatch()) {
        const QString p = QStringLiteral("P") + pm.captured(1);
        found.append({at, {word, QStringLiteral("priority"), QStringLiteral("priority:") + p, p}});
        continue;
      }
      rest << word;
      continue;
    }
    if(clauseRx.match(word).hasMatch() && !word.contains(QStringLiteral("//"))) {
      found.append({at, {word, QStringLiteral("clause"), word, word}});
    } else if((m = priorityRx.match(word)).hasMatch()) {
      const QString p = QStringLiteral("P") + m.captured(1);
      found.append({at, {word, QStringLiteral("priority"), QStringLiteral("priority:") + p, p}});
    } else if((m = tagRx.match(word)).hasMatch()) {
      found.append({at, {word, QStringLiteral("tag"), QStringLiteral("tag:") + m.captured(1).toLower(), word}});
    } else if(ticketRx.match(word).hasMatch()) {
      found.append({at, {word, QStringLiteral("ticket"), word.toUpper(), word.toUpper()}});
    } else {
      rest << word;
    }
  }

  // Dates, the way quick capture reads them: after a deadline word it is the
  // deadline, otherwise when the task is done.
  QString left = rest.join(QLatin1Char(' '));
  if(chrono != nullptr && !left.isEmpty()) {
    capture::Parsed p = capture::parse(left, *chrono, now);
    QStringList rejected;
    for(const capture::Span& s : p.spans) {
      if(s.kind == QLatin1String("estimate") || (s.kind == QLatin1String("when") && !scheduledField)) {
        rejected << s.text;
      }
    }
    if(!rejected.isEmpty()) {
      p = capture::parse(left, *chrono, now, rejected);
    }
    for(const capture::Span& s : p.spans) {
      const int at = static_cast<int>(input.indexOf(s.text, 0, Qt::CaseInsensitive));
      if(s.kind == QLatin1String("due") && p.due.isValid()) {
        found.append({at, {s.text, QStringLiteral("due"), QStringLiteral("due:<=") + p.due.date().toString(Qt::ISODate), s.text}});
      } else if(s.kind == QLatin1String("when") && p.when.isValid()) {
        found.append({at, {s.text, QStringLiteral("when"), QStringLiteral("scheduled:") + p.when.date().toString(Qt::ISODate), s.text}});
      }
    }
    left = p.title;
  }

  // A column by the start of a word: "заблок" is the Blocked column.
  QStringList words;
  for(const QString& word : left.split(QLatin1Char(' '), Qt::SkipEmptyParts)) {
    const QString id = statusByPrefix(word, statuses);
    if(id.isEmpty()) {
      words << word;
      continue;
    }
    QString name = id;
    for(const QVariant& v : statuses) {
      if(v.toMap().value(QStringLiteral("id")).toString() == id) {
        name = v.toMap().value(QStringLiteral("name")).toString();
      }
    }
    const int at = static_cast<int>(input.indexOf(word));
    found.append({at, {word, QStringLiteral("status"), QStringLiteral("status:") + id, name}});
  }

  std::stable_sort(found.begin(), found.end(), [](const auto& a, const auto& b) {
    return a.first < b.first;
  });
  for(const auto& f : found) {
    out.tokens.append(f.second);
  }
  out.text = words.join(QLatin1Char(' '));
  return out;
}

}  // namespace heap::query
