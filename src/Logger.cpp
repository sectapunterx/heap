#include "Logger.h"

#include <QByteArray>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QIODevice>
#include <QMutex>
#include <QStandardPaths>
#include <QtGlobal>

#include <cstdio>
#include <cstdlib>

// Rotation policy: keep the live log under kMaxLogBytes; when it grows past
// that, roll it to a timestamped sibling and keep only the newest
// kKeepRotated rolled files. Mirrors the keep-last-N backup pruning in
// AppController::pruneBackups.
namespace {

constexpr qint64 kMaxLogBytes = 1 * 1024 * 1024;  // 1 MiB
constexpr int kKeepRotated = 5;

QMutex g_mutex;
QFile g_logFile;
QtMessageHandler g_previousHandler = nullptr;

const char* levelName(QtMsgType type) {
  switch(type) {
    case QtDebugMsg:
      return "DEBUG";
    case QtInfoMsg:
      return "INFO ";
    case QtWarningMsg:
      return "WARN ";
    case QtCriticalMsg:
      return "CRIT ";
    case QtFatalMsg:
      return "FATAL";
  }
  return "LOG  ";
}

// Caller must hold g_mutex and g_logFile must be open.
void rotateIfNeeded() {
  if(g_logFile.size() < kMaxLogBytes) {
    return;
  }
  const QString base = heap::logging::logFilePath();
  g_logFile.close();
  const QString rolled = base + '.' + QDateTime::currentDateTime().toString("yyyyMMdd-HHmmss");
  QFile::rename(base, rolled);

  QDir dir(heap::logging::logDirPath());
  const QStringList rolledLogs = dir.entryList({"heap.log.*"}, QDir::Files | QDir::NoSymLinks, QDir::Time);
  for(int i = kKeepRotated; i < rolledLogs.size(); ++i) {
    dir.remove(rolledLogs[i]);
  }

  g_logFile.setFileName(base);
  g_logFile.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text);
}

void messageHandler(QtMsgType type, const QMessageLogContext& ctx, const QString& msg) {
  QString line = QDateTime::currentDateTime().toString(Qt::ISODateWithMs);
  line += ' ';
  line += QLatin1String(levelName(type));
  line += ' ';
  if(ctx.category && qstrcmp(ctx.category, "default") != 0) {
    line += QLatin1String(ctx.category);
    line += QLatin1String(": ");
  }
  line += msg;
  line += '\n';

  {
    QMutexLocker lock(&g_mutex);
    if(g_logFile.isOpen()) {
      g_logFile.write(line.toUtf8());
      g_logFile.flush();
      rotateIfNeeded();
    }
  }

  // Forward to the original handler so stderr/console output is preserved.
  if(g_previousHandler) {
    g_previousHandler(type, ctx, msg);
  } else {
    fputs(line.toUtf8().constData(), stderr);
  }
  if(type == QtFatalMsg) {
    abort();
  }
}

}  // namespace

namespace heap::logging {

QString logDirPath() {
  const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/logs";
  QDir().mkpath(dir);
  return dir;
}

QString logFilePath() {
  return logDirPath() + "/heap.log";
}

void installFileLogger() {
  QMutexLocker lock(&g_mutex);
  if(g_logFile.isOpen()) {
    return;
  }
  g_logFile.setFileName(logFilePath());
  if(g_logFile.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
    g_previousHandler = qInstallMessageHandler(messageHandler);
  }
}

QString logTail(int maxBytes) {
  QFile file(logFilePath());
  if(!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
    return {};
  }
  const qint64 size = file.size();
  const bool truncated = size > maxBytes;
  if(truncated) {
    file.seek(size - maxBytes);
  }
  QString tail = QString::fromUtf8(file.readAll());
  // Drop the partial first line left by seeking into the middle of the file.
  if(truncated) {
    const int nl = tail.indexOf('\n');
    if(nl >= 0) {
      tail = tail.mid(nl + 1);
    }
  }
  return tail;
}

}  // namespace heap::logging
