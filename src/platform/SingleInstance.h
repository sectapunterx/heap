#pragma once

#include <QByteArray>
#include <QObject>
#include <QString>

#include <memory>

class QLocalServer;
class QLockFile;

// One heap per data directory (PLAT-2).
//
// Close-to-tray makes a second launch the normal way to "open heap" again, and
// two processes on one state.json each save their own copy: whichever writes
// last silently erases the other's edits. The first process takes a QLockFile
// in the data dir and listens on a QLocalServer named after that dir; a second
// one finds the lock, hands its request ("activate", optionally a view) to the
// first over the socket, and exits.
//
// Keyed by data dir, not by user: `heap --data-dir /tmp/x` next to the real
// profile is a different workspace and may run alongside it.
namespace heap::platform {

class SingleInstance : public QObject {
  Q_OBJECT
 public:
  enum class Result {
    Primary,    // this process owns the data dir
    Forwarded,  // another heap owns it and got our message: exit now
    Busy,       // another heap owns it but did not answer
  };

  explicit SingleInstance(const QString& dataDir, QObject* parent = nullptr);
  ~SingleInstance() override;

  // Takes the lock, or forwards `message` to the process holding it.
  Result acquire(const QByteArray& message);

  // The local-socket name for a data dir (exposed for tests).
  static QString serverName(const QString& dataDir);

  // Hands `message` to a heap already running on `dataDir`, without taking
  // the lock or creating anything there. False when none answers. For a
  // notification click naming a throwaway profile (APP-155): it may reach a
  // heap that is running, never start one in a folder a URI chose.
  static bool forwardOnly(const QString& dataDir, const QByteArray& message);

 signals:
  // Another launch asked this one to come forward; `message` is what it sent.
  void messageReceived(const QByteArray& message);

 private:
  bool listen();
  static bool forward(const QString& name, const QByteArray& message);

  QString m_dataDir;
  std::unique_ptr<QLockFile> m_lock;
  QLocalServer* m_server = nullptr;
};

}  // namespace heap::platform
