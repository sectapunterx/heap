#include "Logger.h"
#include "RecoveryLog.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>

namespace heap::recovery {

QString recoveryLogPath() {
  return heap::logging::logDirPath() + "/recovery.log";
}

void append(const QString& kind, const QVariantMap& details) {
  QVariantMap record = details;
  record.insert(QStringLiteral("at"), QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs));
  record.insert(QStringLiteral("kind"), kind);
  record.insert(QStringLiteral("version"), QCoreApplication::applicationVersion());

  QFile f(recoveryLogPath());
  if(!f.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
    return;
  }
  f.write(QJsonDocument(QJsonObject::fromVariantMap(record)).toJson(QJsonDocument::Compact));
  f.write("\n");
}

QVariantList entries() {
  QFile f(recoveryLogPath());
  if(!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
    return {};
  }
  QVariantList out;
  while(!f.atEnd()) {
    const QByteArray line = f.readLine().trimmed();
    if(line.isEmpty()) {
      continue;
    }
    const QJsonDocument doc = QJsonDocument::fromJson(line);
    if(doc.isObject()) {
      out.append(doc.object().toVariantMap());
    }
  }
  return out;
}

bool exportTo(const QString& destPath) {
  QFile src(recoveryLogPath());
  if(!src.exists() || destPath.isEmpty()) {
    return false;
  }
  QFile::remove(destPath);  // QFile::copy refuses to overwrite
  return src.copy(destPath);
}

QString tail(int maxBytes) {
  QFile f(recoveryLogPath());
  if(!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
    return {};
  }
  const qint64 size = f.size();
  const bool truncated = size > maxBytes;
  if(truncated) {
    f.seek(size - maxBytes);
  }
  QString out = QString::fromUtf8(f.readAll());
  if(truncated) {
    const int nl = out.indexOf('\n');
    out = nl >= 0 ? out.mid(nl + 1) : out;
  }
  return out;
}

}  // namespace heap::recovery
