#include "platform/SingleInstance.h"

#include <QCryptographicHash>
#include <QDeadlineTimer>
#include <QDir>
#include <QLocalServer>
#include <QLocalSocket>
#include <QLockFile>
#include <QThread>

#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace heap::platform {

namespace {
// How long a second launch keeps trying to reach the first one. Covers the
// window between the first process taking the lock and its server listening.
constexpr int kForwardWindowMs = 3000;
}  // namespace

SingleInstance::SingleInstance(const QString& dataDir, QObject* parent) : QObject(parent), m_dataDir(QDir(dataDir).absolutePath()) {
}

SingleInstance::~SingleInstance() = default;

QString SingleInstance::serverName(const QString& dataDir) {
  QString key = QDir::cleanPath(QDir(dataDir).absolutePath());
#ifdef Q_OS_WIN
  key = key.toLower();  // C:\Users and c:\users are one folder
#endif
  const QByteArray hash = QCryptographicHash::hash(key.toUtf8(), QCryptographicHash::Sha1).toHex().left(16);
  return QStringLiteral("heap-") + QString::fromLatin1(hash);
}

SingleInstance::Result SingleInstance::acquire(const QByteArray& message) {
  QDir().mkpath(m_dataDir);
  m_lock = std::make_unique<QLockFile>(m_dataDir + QStringLiteral("/heap.lock"));
  // Never stale by age: a heap left open for a week still owns its data. A
  // lock whose process is gone (a crash) is still detected and taken over.
  m_lock->setStaleLockTime(0);
  if(m_lock->tryLock(0)) {
    listen();
    return Result::Primary;
  }
  if(m_lock->error() != QLockFile::LockFailedError) {
    // No permission to create the lock file (a read-only data dir): nothing to
    // coordinate with, and the storage banner reports the real problem.
    m_lock.reset();
    return Result::Primary;
  }
  m_lock.reset();

#ifdef Q_OS_WIN
  // The running instance may only take the foreground if the launching
  // process (which the user just started, so it owns the foreground) lets it.
  AllowSetForegroundWindow(ASFW_ANY);
#endif
  const QDeadlineTimer deadline(kForwardWindowMs);
  const QString name = serverName(m_dataDir);
  while(!deadline.hasExpired()) {
    if(forward(name, message)) {
      return Result::Forwarded;
    }
    QThread::msleep(100);
  }
  return Result::Busy;
}

bool SingleInstance::listen() {
  const QString name = serverName(m_dataDir);
  // A crashed owner can leave its socket file behind on Unix. We hold the
  // lock, so whatever is listening under this name is not a live heap.
  QLocalServer::removeServer(name);
  m_server = new QLocalServer(this);
  m_server->setSocketOptions(QLocalServer::UserAccessOption);
  if(!m_server->listen(name)) {
    qWarning("single instance: cannot listen on %s: %s", qUtf8Printable(name), qUtf8Printable(m_server->errorString()));
    return false;
  }
  connect(m_server, &QLocalServer::newConnection, this, [this]() {
    while(QLocalSocket* socket = m_server->nextPendingConnection()) {
      connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
      connect(socket, &QLocalSocket::readyRead, this, [this, socket]() {
        if(!socket->canReadLine()) {
          return;
        }
        const QByteArray line = socket->readLine().trimmed();
        socket->write("ok\n");
        socket->flush();
        socket->disconnectFromServer();
        emit messageReceived(line);
      });
    }
  });
  return true;
}

bool SingleInstance::forward(const QString& name, const QByteArray& message) {
  QLocalSocket socket;
  socket.connectToServer(name);
  if(!socket.waitForConnected(500)) {
    return false;
  }
  QByteArray line = message;
  line.replace('\n', ' ');
  socket.write(line + '\n');
  if(!socket.waitForBytesWritten(1000)) {
    return false;
  }
  // Wait for the acknowledgement, so "Forwarded" means the other side has it.
  return socket.waitForReadyRead(2000) && socket.readLine().trimmed() == "ok";
}

}  // namespace heap::platform
