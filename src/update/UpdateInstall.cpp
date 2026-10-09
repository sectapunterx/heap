#include "update/UpdateInstall.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QStringList>

#include <cstdio>

namespace heap::update {

namespace {

constexpr auto kOutcomeFile = "outcome.txt";
constexpr int kToolTimeoutMs = 2 * 60 * 1000;

QString outcomePath() {
  return QDir(updateWorkDir()).filePath(QLatin1String(kOutcomeFile));
}

bool writeOutcome(const QByteArray& text) {
  QFile f(outcomePath());
  return f.open(QIODevice::WriteOnly | QIODevice::Truncate) && f.write(text) == text.size();
}

// Whether heap could write into `dir`: a real write, since on Windows the
// permission bits QFileInfo reads say little about the folder's ACL.
bool canWriteInto(const QString& dir) {
  QFile probe(QDir(dir).filePath(QStringLiteral(".heap-write-probe-%1").arg(QCoreApplication::applicationPid())));
  if(!probe.open(QIODevice::WriteOnly)) {
    return false;
  }
  probe.close();
  probe.remove();
  return true;
}

// Run a tool to the end. False, and why, if it did not exit cleanly.
bool runTool(const QString& program, const QStringList& args, QString& error) {
  QProcess p;
  p.setProcessChannelMode(QProcess::MergedChannels);
  p.start(program, args);
  if(!p.waitForStarted() || !p.waitForFinished(kToolTimeoutMs)) {
    error = QStringLiteral("%1: %2").arg(program, p.errorString());
    p.kill();
    return false;
  }
  if(p.exitStatus() != QProcess::NormalExit || p.exitCode() != 0) {
    error = QStringLiteral("%1 failed: %2").arg(program, QString::fromUtf8(p.readAll()).trimmed());
    return false;
  }
  return true;
}

// A shell that waits for heap to quit, then runs `then` with "$1"/"$2"
// standing for `a`/`b` — arguments, so no path ever needs quoting.
bool startAfterQuit(const QString& then, const QString& a, const QString& b) {
  const QString script =
      QStringLiteral("while kill -0 %1 2>/dev/null; do sleep 0.2; done; %2").arg(QCoreApplication::applicationPid()).arg(then);
  return QProcess::startDetached(QStringLiteral("/bin/sh"), {QStringLiteral("-c"), script, QStringLiteral("sh"), a, b});
}

bool installWindows(PackageKind kind, const QString& package, QString& error) {
  const QString appDir = QCoreApplication::applicationDirPath();
  const QString helper = QDir(appDir).filePath(QStringLiteral("lowkey-updater.exe"));
  if(!QFileInfo::exists(helper)) {
    error = QStringLiteral("lowkey-updater.exe is missing next to lowkey.exe");
    return false;
  }
  // It must not run from the folder it is about to replace.
  const QString copy = QDir(updateWorkDir()).filePath(QStringLiteral("lowkey-updater.exe"));
  QFile::remove(copy);
  if(!QFile::copy(helper, copy)) {
    error = QStringLiteral("could not copy lowkey-updater.exe to %1").arg(updateWorkDir());
    return false;
  }
  QFile::remove(outcomePath());
  const QStringList args = {
      QStringLiteral("--pid"),
      QString::number(QCoreApplication::applicationPid()),
      QStringLiteral("--mode"),
      kind == PackageKind::WindowsSetup ? QStringLiteral("setup") : QStringLiteral("portable"),
      QStringLiteral("--package"),
      QDir::toNativeSeparators(package),
      QStringLiteral("--target"),
      QDir::toNativeSeparators(appDir),
      QStringLiteral("--exe"),
      QDir::toNativeSeparators(QCoreApplication::applicationFilePath()),
      QStringLiteral("--result"),
      QDir::toNativeSeparators(outcomePath()),
  };
  if(!QProcess::startDetached(copy, args, updateWorkDir())) {
    error = QStringLiteral("could not start lowkey-updater.exe");
    return false;
  }
  return true;
}

bool installMac(const QString& package, QString& error) {
  // .../heap.app/Contents/MacOS → .../heap.app
  const QString bundle = QDir::cleanPath(QCoreApplication::applicationDirPath() + QStringLiteral("/../.."));
  const QString parent = QFileInfo(bundle).absolutePath();
  const QString mount = QDir(updateWorkDir()).filePath(QStringLiteral("mnt"));
  QDir().mkpath(mount);
  if(!runTool(QStringLiteral("hdiutil"),
              {QStringLiteral("attach"),
               QStringLiteral("-nobrowse"),
               QStringLiteral("-readonly"),
               QStringLiteral("-noautoopen"),
               QStringLiteral("-mountpoint"),
               mount,
               package},
              error)) {
    return false;
  }
  const QStringList apps = QDir(mount).entryList({QStringLiteral("*.app")}, QDir::Dirs);
  const QString fresh = QDir(parent).filePath(QStringLiteral(".heap-update-new.app"));
  const QString aside = QDir(parent).filePath(QStringLiteral(".heap-update-old.app"));
  QDir(fresh).removeRecursively();
  QDir(aside).removeRecursively();
  bool copied = false;
  if(apps.isEmpty()) {
    error = QStringLiteral("the disk image holds no app");
  } else {
    // ditto keeps the bundle's signature, symlinks and attributes intact.
    copied = runTool(QStringLiteral("ditto"), {QDir(mount).filePath(apps.first()), fresh}, error);
  }
  QString ignored;
  runTool(QStringLiteral("hdiutil"), {QStringLiteral("detach"), mount, QStringLiteral("-quiet")}, ignored);
  if(!copied) {
    QDir(fresh).removeRecursively();
    return false;
  }
  // The running bundle can be renamed: the process keeps its open files.
  if(!QDir().rename(bundle, aside)) {
    error = QStringLiteral("could not move %1 aside").arg(bundle);
    QDir(fresh).removeRecursively();
    return false;
  }
  if(!QDir().rename(fresh, bundle)) {
    error = QStringLiteral("could not put the new heap.app in place");
    QDir().rename(aside, bundle);
    QDir(fresh).removeRecursively();
    return false;
  }
  writeOutcome("ok\n");
  if(!startAfterQuit(QStringLiteral("rm -rf \"$1\"; open \"$2\""), aside, bundle)) {
    error = QStringLiteral("could not schedule the restart");
    return false;
  }
  return true;
}

bool installAppImage(const QString& package, QString& error) {
  const QString target = qEnvironmentVariable("APPIMAGE");
  const QString part = QFileInfo(target).absolutePath() + QStringLiteral("/.heap-update.AppImage.part");
  QFile::remove(part);
  if(!QFile::copy(package, part)) {
    error = QStringLiteral("could not write next to %1").arg(target);
    return false;
  }
  QFile::setPermissions(part,
                        QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner | QFileDevice::ReadGroup |
                            QFileDevice::ExeGroup | QFileDevice::ReadOther | QFileDevice::ExeOther);
  // rename(2) replaces the file in one step; the running AppImage keeps its
  // mounted copy of the old one.
  if(std::rename(QFile::encodeName(part).constData(), QFile::encodeName(target).constData()) != 0) {
    error = QStringLiteral("could not replace %1").arg(target);
    QFile::remove(part);
    return false;
  }
  writeOutcome("ok\n");
  if(!startAfterQuit(QStringLiteral("exec \"$1\""), target, QString())) {
    error = QStringLiteral("could not schedule the restart");
    return false;
  }
  return true;
}

}  // namespace

QString updateWorkDir() {
  const QString dir = QDir(QStandardPaths::writableLocation(QStandardPaths::TempLocation)).filePath(QStringLiteral("heap-update"));
  QDir().mkpath(dir);
  return dir;
}

PackageEnv currentPackageEnv() {
  PackageEnv env;
  env.appDir = QCoreApplication::applicationDirPath();
#if defined(Q_OS_WIN)
  env.os = QStringLiteral("windows");
  env.hasUninstaller = QFileInfo::exists(QDir(env.appDir).filePath(QStringLiteral("unins000.exe")));
  // heap-portable.txt is what a 0.7.x zip unpacked; an update keeps it.
  env.hasPortableMarker = QFileInfo::exists(QDir(env.appDir).filePath(QStringLiteral("lowkey-portable.txt"))) ||
                          QFileInfo::exists(QDir(env.appDir).filePath(QStringLiteral("heap-portable.txt")));
  env.writable = canWriteInto(env.appDir);
#elif defined(Q_OS_MACOS)
  env.os = QStringLiteral("macos");
  env.writable = canWriteInto(QDir::cleanPath(env.appDir + QStringLiteral("/../../..")));
#else
  env.os = QStringLiteral("linux");
  env.appImage = qEnvironmentVariable("APPIMAGE");
  env.sandboxed = qEnvironmentVariableIsSet("FLATPAK_ID") || qEnvironmentVariableIsSet("SNAP");
  env.writable = !env.appImage.isEmpty() && canWriteInto(QFileInfo(env.appImage).absolutePath());
#endif
  return env;
}

bool startInstall(PackageKind kind, const QString& package, QString& error) {
  switch(kind) {
    case PackageKind::WindowsSetup:
    case PackageKind::WindowsPortable:
      return installWindows(kind, package, error);
    case PackageKind::MacApp:
      return installMac(package, error);
    case PackageKind::LinuxAppImage:
      return installAppImage(package, error);
    case PackageKind::None:
      break;
  }
  error = QStringLiteral("this copy of heap is not updated from inside the app");
  return false;
}

InstallOutcome parseInstallOutcome(const QByteArray& text) {
  InstallOutcome out;
  const QByteArray t = text.trimmed();
  if(t.isEmpty()) {
    return out;
  }
  out.present = true;
  out.ok = t == "ok";
  if(!out.ok) {
    const qsizetype nl = t.indexOf('\n');
    out.error = nl >= 0 ? QString::fromUtf8(t.mid(nl + 1)).trimmed() : QString::fromUtf8(t);
  }
  return out;
}

InstallOutcome takeInstallOutcome() {
  QFile f(outcomePath());
  if(!f.open(QIODevice::ReadOnly)) {
    return {};
  }
  const InstallOutcome out = parseInstallOutcome(f.readAll());
  f.close();
  f.remove();
  // The package and the helper's copy are spent once heap has restarted.
  const QDir dir(updateWorkDir());
  for(const QFileInfo& fi : dir.entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot)) {
    if(fi.isDir()) {
      QDir(fi.absoluteFilePath()).removeRecursively();
    } else {
      QFile::remove(fi.absoluteFilePath());
    }
  }
  return out;
}

}  // namespace heap::update
