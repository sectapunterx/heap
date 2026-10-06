#include "platform/Autostart.h"

#include <QRegularExpression>
#include <QStandardPaths>
#include <QStringList>

namespace heap::platform::autostart {

namespace {

QString& rootOverride() {
  static QString root;
  return root;
}

QString xmlEscape(const QString& s) {
  return s.toHtmlEscaped();
}

// An argument of a desktop entry's Exec key: quoted when it has to be, with
// the characters the spec reserves inside quotes escaped.
QString desktopExecArg(const QString& arg) {
  static const QRegularExpression plain(QStringLiteral("^[A-Za-z0-9_@%+=:,./-]+$"));
  if(plain.match(arg).hasMatch()) {
    return arg;
  }
  QString out = arg;
  out.replace(QLatin1Char('\\'), QStringLiteral("\\\\"));
  out.replace(QLatin1Char('"'), QStringLiteral("\\\""));
  out.replace(QLatin1Char('`'), QStringLiteral("\\`"));
  out.replace(QLatin1Char('$'), QStringLiteral("\\$"));
  return QLatin1Char('"') + out + QLatin1Char('"');
}

bool hasMinimizedArg(const QString& text) {
  static const QRegularExpression flag(QStringLiteral("(^|[\\s>\"])--minimized($|[\\s<\"])"));
  return flag.match(text).hasMatch();
}

}  // namespace

QString windowsRunCommand(const QString& exePath, bool minimized) {
  // Backslashes on every platform: the text is for the Windows registry, and
  // toNativeSeparators would leave slashes when the tests run on Linux/macOS.
  QString cmd = QLatin1Char('"') + QString(exePath).replace(QLatin1Char('/'), QLatin1Char('\\')) + QLatin1Char('"');
  if(minimized) {
    cmd += QLatin1Char(' ') + QLatin1String(kMinimizedFlag);
  }
  return cmd;
}

Entry parseWindowsRunCommand(const QString& value) {
  Entry e;
  const QString v = value.trimmed();
  e.enabled = !v.isEmpty();
  if(e.enabled) {
    // Only what follows the program counts: a folder called --minimized is
    // still a folder.
    const qsizetype afterExe = v.startsWith(QLatin1Char('"')) ? v.indexOf(QLatin1Char('"'), 1) + 1 : v.indexOf(QLatin1Char(' '));
    e.minimized = afterExe > 0 && hasMinimizedArg(v.mid(afterExe));
  }
  return e;
}

QString macLaunchAgentPlist(const QString& label, const QString& program, bool minimized) {
  QStringList args{QStringLiteral("        <string>%1</string>").arg(xmlEscape(program))};
  if(minimized) {
    args << QStringLiteral("        <string>%1</string>").arg(QLatin1String(kMinimizedFlag));
  }
  return QStringLiteral(
             "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
             "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
             "<plist version=\"1.0\">\n"
             "<dict>\n"
             "    <key>Label</key>\n"
             "    <string>%1</string>\n"
             "    <key>ProgramArguments</key>\n"
             "    <array>\n"
             "%2\n"
             "    </array>\n"
             "    <key>RunAtLoad</key>\n"
             "    <true/>\n"
             "    <key>ProcessType</key>\n"
             "    <string>Interactive</string>\n"
             "</dict>\n"
             "</plist>\n")
      .arg(xmlEscape(label))
      .arg(args.join(QLatin1Char('\n')));
}

Entry parseMacLaunchAgent(const QString& plist) {
  Entry e;
  static const QRegularExpression runAtLoad(QStringLiteral("<key>\\s*RunAtLoad\\s*</key>\\s*<true\\s*/>"));
  e.enabled = runAtLoad.match(plist).hasMatch();
  if(e.enabled) {
    static const QRegularExpression flag(QStringLiteral("<string>\\s*--minimized\\s*</string>"));
    e.minimized = flag.match(plist).hasMatch();
  }
  return e;
}

QString linuxDesktopEntry(const QString& execPath, bool minimized) {
  QString exec = desktopExecArg(execPath);
  if(minimized) {
    exec += QLatin1Char(' ') + QLatin1String(kMinimizedFlag);
  }
  return QStringLiteral(
             "[Desktop Entry]\n"
             "Type=Application\n"
             "Name=heap.\n"
             "Comment=Tickets, planning and notes for engineers\n"
             "Exec=%1\n"
             "Icon=heap\n"
             "Terminal=false\n"
             "X-GNOME-Autostart-enabled=true\n")
      .arg(exec);
}

Entry parseLinuxDesktopEntry(const QString& text) {
  Entry e;
  QString exec;
  bool hidden = false;
  for(const QString& raw : text.split(QLatin1Char('\n'))) {
    const QString line = raw.trimmed();
    if(line.startsWith(QLatin1String("Exec="))) {
      exec = line.mid(5);
    } else if(line == QLatin1String("Hidden=true") || line == QLatin1String("X-GNOME-Autostart-enabled=false")) {
      // How desktop environments switch an entry off without deleting it.
      hidden = true;
    }
  }
  e.enabled = !exec.trimmed().isEmpty() && !hidden;
  e.minimized = e.enabled && hasMinimizedArg(exec);
  return e;
}

QString linuxExecPath(const QString& appImageEnv, const QString& applicationPath) {
  return appImageEnv.trimmed().isEmpty() ? applicationPath : appImageEnv.trimmed();
}

void setRootForTesting(const QString& dir) {
  rootOverride() = dir;
}

QString testRoot() {
  if(!rootOverride().isEmpty()) {
    return rootOverride();
  }
  if(QStandardPaths::isTestModeEnabled()) {
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/heap-autostart-test");
  }
  return {};
}

bool supported() {
#if defined(Q_OS_WIN) || defined(Q_OS_MACOS) || defined(Q_OS_LINUX)
  return true;
#else
  return false;
#endif
}

Entry read() {
  if(!supported()) {
    return {};
  }
  return detail::readSystem(testRoot());
}

bool write(bool enabled, bool minimized) {
  if(!supported()) {
    return false;
  }
  return detail::writeSystem(testRoot(), enabled, minimized);
}

}  // namespace heap::platform::autostart
