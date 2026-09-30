#include "diag/IssueReport.h"

#include <QDir>
#include <QRegularExpression>
#include <QStringList>
#include <QtGlobal>

namespace heap::diag {

QString scrubPersonalPaths(const QString& text, const QString& homePath, const QString& userName) {
  QString out = text;
  QString home = QDir::fromNativeSeparators(homePath);
  while(home.endsWith(QChar('/'))) {
    home.chop(1);
  }
  if(home.size() > 1) {
    // Both spellings of the same folder: C:/Users/x and C:\Users\x.
    const QString native = QString(home).replace(QChar('/'), QChar('\\'));
    out.replace(home, QStringLiteral("~"), Qt::CaseInsensitive);
    out.replace(native, QStringLiteral("~"), Qt::CaseInsensitive);
  }
  if(userName.size() >= 3) {
    const QRegularExpression word(QStringLiteral("(?<![\\w.])") + QRegularExpression::escape(userName) + QStringLiteral("(?![\\w])"),
                                  QRegularExpression::CaseInsensitiveOption | QRegularExpression::UseUnicodePropertiesOption);
    out.replace(word, QStringLiteral("<user>"));
  }
  return out;
}

QString tailLines(const QString& text, int maxLines, int maxChars) {
  QStringList lines = text.split(QChar('\n'));
  while(!lines.isEmpty() && lines.constLast().trimmed().isEmpty()) {
    lines.removeLast();
  }
  if(maxLines >= 0 && lines.size() > maxLines) {
    lines = lines.mid(lines.size() - maxLines);
  }
  QString out = lines.join(QChar('\n'));
  if(maxChars >= 0 && out.size() > maxChars) {
    out = out.right(maxChars);
    const qsizetype nl = out.indexOf(QChar('\n'));
    if(nl >= 0 && nl + 1 < out.size()) {
      out = out.mid(nl + 1);
    }
  }
  return out;
}

QString currentUserName() {
  QString name = qEnvironmentVariable("USERNAME");
  if(name.isEmpty()) {
    name = qEnvironmentVariable("USER");
  }
  return name;
}

}  // namespace heap::diag
