// Start at login (APP-154): the text of each OS's entry, and the system
// read/write going to a scratch folder instead of the real login items.
#include "platform/Autostart.h"

#include <QTemporaryDir>

#include <gtest/gtest.h>

namespace as = heap::platform::autostart;

TEST(AutostartWindows, CommandQuotesTheExeAndAddsTheFlag) {
  EXPECT_EQ(as::windowsRunCommand(QStringLiteral("C:/Program Files/heap/heap.exe"), true),
            QStringLiteral("\"C:\\Program Files\\heap\\heap.exe\" --minimized"));
  EXPECT_EQ(as::windowsRunCommand(QStringLiteral("C:/heap/heap.exe"), false), QStringLiteral("\"C:\\heap\\heap.exe\""));
}

TEST(AutostartWindows, ParseRoundTrips) {
  for(const bool minimized : {false, true}) {
    const as::Entry e = as::parseWindowsRunCommand(as::windowsRunCommand(QStringLiteral("C:/x/heap.exe"), minimized));
    EXPECT_TRUE(e.enabled);
    EXPECT_EQ(e.minimized, minimized);
  }
}

TEST(AutostartWindows, ParseNeedsTheFlagAfterTheProgram) {
  EXPECT_FALSE(as::parseWindowsRunCommand(QString()).enabled);
  // A folder named like the flag is part of the path, not an argument.
  EXPECT_FALSE(as::parseWindowsRunCommand(QStringLiteral("\"C:\\--minimized\\heap.exe\"")).minimized);
  EXPECT_TRUE(as::parseWindowsRunCommand(QStringLiteral("C:\\heap\\heap.exe --minimized")).minimized);
}

TEST(AutostartMac, PlistRunsAtLoadWithTheFlag) {
  const QString plist =
      as::macLaunchAgentPlist(QStringLiteral("local.heap.app"), QStringLiteral("/Applications/heap.app/Contents/MacOS/heap"), true);
  EXPECT_TRUE(plist.contains(QStringLiteral("<string>local.heap.app</string>")));
  EXPECT_TRUE(plist.contains(QStringLiteral("<string>/Applications/heap.app/Contents/MacOS/heap</string>")));
  EXPECT_TRUE(plist.contains(QStringLiteral("<key>RunAtLoad</key>")));
  const as::Entry e = as::parseMacLaunchAgent(plist);
  EXPECT_TRUE(e.enabled);
  EXPECT_TRUE(e.minimized);
  EXPECT_FALSE(as::parseMacLaunchAgent(as::macLaunchAgentPlist(QStringLiteral("l"), QStringLiteral("/a"), false)).minimized);
}

TEST(AutostartMac, PathsAreXmlEscaped) {
  const QString plist = as::macLaunchAgentPlist(QStringLiteral("l"), QStringLiteral("/Users/a&b/heap"), false);
  EXPECT_TRUE(plist.contains(QStringLiteral("/Users/a&amp;b/heap")));
}

TEST(AutostartLinux, PrefersTheAppImage) {
  EXPECT_EQ(as::linuxExecPath(QStringLiteral("/home/u/heap.AppImage"), QStringLiteral("/tmp/.mount_x/usr/bin/heap")),
            QStringLiteral("/home/u/heap.AppImage"));
  EXPECT_EQ(as::linuxExecPath(QString(), QStringLiteral("/usr/bin/heap")), QStringLiteral("/usr/bin/heap"));
}

TEST(AutostartLinux, DesktopEntryQuotesPathsWithSpaces) {
  const QString text = as::linuxDesktopEntry(QStringLiteral("/home/u/My Apps/heap.AppImage"), true);
  EXPECT_TRUE(text.contains(QStringLiteral("Exec=\"/home/u/My Apps/heap.AppImage\" --minimized\n")));
  EXPECT_TRUE(text.startsWith(QStringLiteral("[Desktop Entry]\n")));
  const as::Entry e = as::parseLinuxDesktopEntry(text);
  EXPECT_TRUE(e.enabled);
  EXPECT_TRUE(e.minimized);
}

TEST(AutostartLinux, SwitchedOffEntryIsDisabled) {
  QString text = as::linuxDesktopEntry(QStringLiteral("/usr/bin/heap"), false);
  EXPECT_TRUE(as::parseLinuxDesktopEntry(text).enabled);
  text.replace(QStringLiteral("X-GNOME-Autostart-enabled=true"), QStringLiteral("X-GNOME-Autostart-enabled=false"));
  EXPECT_FALSE(as::parseLinuxDesktopEntry(text).enabled);
  EXPECT_FALSE(as::parseLinuxDesktopEntry(QStringLiteral("[Desktop Entry]\nExec=/usr/bin/heap\nHidden=true\n")).enabled);
}

// The system half, pointed at a temporary folder: write, read back, remove.
TEST(AutostartSystem, WriteReadRemoveUnderTestRoot) {
  const QTemporaryDir dir;
  ASSERT_TRUE(dir.isValid());
  as::setRootForTesting(dir.path());
  ASSERT_EQ(as::testRoot(), dir.path());
  EXPECT_FALSE(as::read().enabled);

  ASSERT_TRUE(as::write(true, true));
  as::Entry e = as::read();
  EXPECT_TRUE(e.enabled);
  EXPECT_TRUE(e.minimized);

  ASSERT_TRUE(as::write(true, false));
  e = as::read();
  EXPECT_TRUE(e.enabled);
  EXPECT_FALSE(e.minimized);

  ASSERT_TRUE(as::write(false, false));
  EXPECT_FALSE(as::read().enabled);
  // Removing what is not there is not an error.
  EXPECT_TRUE(as::write(false, false));
  as::setRootForTesting(QString());
}
