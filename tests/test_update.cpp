// Unit tests for heap::update — the semver comparison behind the GitHub-Releases
// update check (HEAP-63) and the in-app update (APP-125): which package this
// copy is, SHA256SUMS, a download against a local fake GitHub, and
// heap-updater's folder swap.

#include "FakeHttpServer.h"

#include "update/UpdateInstall.h"
#include "update/Updater.h"
#include "updater/BundleSwap.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>

#include <gtest/gtest.h>

#include <filesystem>
#include <fstream>
#include <iterator>
#include <memory>
#include <string>

using heap::update::isNewerVersion;

TEST(UpdateVersionCompare, DetectsNewer) {
  EXPECT_TRUE(isNewerVersion("0.4.2", "0.5.0"));
  EXPECT_TRUE(isNewerVersion("0.4.2", "v0.4.3"));
  EXPECT_TRUE(isNewerVersion("v0.4.2", "0.10.0"));  // 10 > 4, not lexicographic
  EXPECT_TRUE(isNewerVersion("1.0.0", "1.0.1"));
}

TEST(UpdateVersionCompare, RejectsSameOrOlder) {
  EXPECT_FALSE(isNewerVersion("0.4.2", "0.4.2"));
  EXPECT_FALSE(isNewerVersion("0.5.0", "0.4.9"));
  EXPECT_FALSE(isNewerVersion("v1.2.3", "v1.2.3"));
  EXPECT_FALSE(isNewerVersion("0.4.2", "v0.4.1"));
}

TEST(UpdateVersionCompare, HandlesPrerelease) {
  // Equal numeric core: a plain release outranks its pre-release.
  EXPECT_TRUE(isNewerVersion("1.0.0-rc1", "1.0.0"));
  EXPECT_FALSE(isNewerVersion("1.0.0", "1.0.0-rc1"));
  // A higher numeric core still wins regardless of pre-release suffix.
  EXPECT_TRUE(isNewerVersion("1.0.0", "1.0.1-rc1"));
}

TEST(UpdateVersionCompare, HandlesDifferentComponentCounts) {
  EXPECT_TRUE(isNewerVersion("1.0", "1.0.1"));
  EXPECT_FALSE(isNewerVersion("1.0.0", "1.0"));
  EXPECT_FALSE(isNewerVersion("1", "1.0.0"));
}

TEST(UpdateVersionCompare, DevBuildRanksBelowMatchingRelease) {
  // The Release workflow names manual test builds vX.Y.Z-dev.<sha> — a SemVer
  // pre-release of the same numeric core. A user on that dev build must be
  // offered the matching real release, and a user already on the release must
  // NOT be offered a dev build of the same version. This is the contract the CI
  // naming scheme relies on (see .github/workflows/release.yml meta job).
  EXPECT_TRUE(isNewerVersion("1.0.0-dev.abc1234", "v1.0.0"));
  EXPECT_FALSE(isNewerVersion("1.0.0", "v1.0.0-dev.abc1234"));
  // A newer real release still outranks an older dev build.
  EXPECT_TRUE(isNewerVersion("1.0.0-dev.abc1234", "v1.1.0"));
}

// ── APP-125: in-app update ──

namespace {

using heap::update::PackageEnv;
using heap::update::PackageKind;

PackageEnv windowsEnv() {
  PackageEnv env;
  env.os = QStringLiteral("windows");
  env.appDir = QStringLiteral("C:/Users/me/Apps/heap");
  env.writable = true;
  return env;
}

QString hexSha256(const QByteArray& data) {
  return QString::fromLatin1(QCryptographicHash::hash(data, QCryptographicHash::Sha256).toHex());
}

void ensureApp() {
  // QNetworkAccessManager needs an application object; it outlives the suite.
  if(QCoreApplication::instance() == nullptr) {
    static int argc = 1;
    static char arg0[] = "heap_update_tests";
    static char* argv[] = {arg0, nullptr};
    new QCoreApplication(argc, argv);
  }
}

}  // namespace

TEST(UpdatePackage, KnowsHowItWasInstalled) {
  using heap::update::detectPackageKind;
  PackageEnv env = windowsEnv();
  EXPECT_EQ(detectPackageKind(env), PackageKind::None) << "a build folder is not a release";
  env.hasPortableMarker = true;
  EXPECT_EQ(detectPackageKind(env), PackageKind::WindowsPortable);
  env.hasUninstaller = true;
  EXPECT_EQ(detectPackageKind(env), PackageKind::WindowsSetup) << "the installer's uninstaller decides first";
  env.writable = false;
  EXPECT_EQ(detectPackageKind(env), PackageKind::WindowsSetup) << "Program Files is fine: setup elevates";
  env.hasUninstaller = false;
  EXPECT_EQ(detectPackageKind(env), PackageKind::None) << "a portable folder heap cannot write";

  env = windowsEnv();
  env.hasPortableMarker = true;
  env.appDir = QStringLiteral("C:/Users/me/scoop/apps/heap/current");
  EXPECT_EQ(detectPackageKind(env), PackageKind::None) << "Scoop updates its own copy";

  PackageEnv mac;
  mac.os = QStringLiteral("macos");
  mac.writable = true;
  mac.appDir = QStringLiteral("/Applications/heap.app/Contents/MacOS");
  EXPECT_EQ(detectPackageKind(mac), PackageKind::MacApp);
  mac.appDir = QStringLiteral("/Users/me/src/heap/build");
  EXPECT_EQ(detectPackageKind(mac), PackageKind::None);

  PackageEnv lnx;
  lnx.os = QStringLiteral("linux");
  lnx.writable = true;
  EXPECT_EQ(detectPackageKind(lnx), PackageKind::None) << "a distro or source build";
  lnx.appImage = QStringLiteral("/home/me/Apps/heap.AppImage");
  EXPECT_EQ(detectPackageKind(lnx), PackageKind::LinuxAppImage);
  lnx.sandboxed = true;
  EXPECT_EQ(detectPackageKind(lnx), PackageKind::None) << "Flatpak updates through its store";
}

TEST(UpdatePackage, AssetNamesMatchTheReleaseWorkflow) {
  using heap::update::assetNameFor;
  const QString tag = QStringLiteral("v0.5.7");
  // lowkey since 0.8.0 (APP-280); a release that only has heap-… files is
  // still found (Updater::downloadAsset falls back to the old name).
  EXPECT_EQ(assetNameFor(PackageKind::WindowsSetup, tag), QStringLiteral("lowkey-v0.5.7-windows-setup.exe"));
  EXPECT_EQ(assetNameFor(PackageKind::WindowsPortable, tag), QStringLiteral("lowkey-v0.5.7-windows-portable.zip"));
  EXPECT_EQ(assetNameFor(PackageKind::MacApp, tag), QStringLiteral("lowkey-v0.5.7-macos.dmg"));
  EXPECT_EQ(assetNameFor(PackageKind::LinuxAppImage, tag), QStringLiteral("lowkey-v0.5.7-linux-x86_64.AppImage"));
  EXPECT_TRUE(assetNameFor(PackageKind::None, tag).isEmpty());
}

TEST(UpdatePackage, ReadsSha256Sums) {
  using heap::update::sha256FromSums;
  // The v0.5.6 file as published, plus the binary-mode '*' form.
  const QByteArray sums =
      "8dbc26ff4a88caab5470dbca86001fde283db8534acd5f4455065c07d6d1474f  heap-v0.5.6-linux-x86_64.AppImage\n"
      "7d4a22a8f0237175397dd5fa282dd195fcfdfc1b62d7c974be3638108c855438  heap-v0.5.6-windows-portable.zip\n"
      "7F05DBE29A0782EAC84CB04ED6CBB4DE26C9AE57F667A5B7E6E374DC3BB4951C *heap-v0.5.6-windows-setup.exe\r\n";
  EXPECT_EQ(sha256FromSums(sums, QStringLiteral("heap-v0.5.6-windows-portable.zip")),
            QStringLiteral("7d4a22a8f0237175397dd5fa282dd195fcfdfc1b62d7c974be3638108c855438"));
  EXPECT_EQ(sha256FromSums(sums, QStringLiteral("heap-v0.5.6-windows-setup.exe")),
            QStringLiteral("7f05dbe29a0782eac84cb04ed6cbb4de26c9ae57f667a5b7e6e374dc3bb4951c"))
      << "binary-mode '*' and upper case are read too";
  EXPECT_TRUE(sha256FromSums(sums, QStringLiteral("heap-v0.5.6-macos.dmg")).isEmpty());
  EXPECT_TRUE(sha256FromSums(sums, QStringLiteral("heap-v0.5.6-windows")).isEmpty()) << "no prefix match";
  EXPECT_TRUE(sha256FromSums("zz4a22a8f0237175397dd5fa282dd195fcfdfc1b62d7c974be3638108c855438  a.zip", QStringLiteral("a.zip")).isEmpty());
}

TEST(UpdatePackage, ReadsTheOutcomeAHelperLeft) {
  using heap::update::parseInstallOutcome;
  EXPECT_FALSE(parseInstallOutcome("").present);
  const auto ok = parseInstallOutcome("ok\n");
  EXPECT_TRUE(ok.present && ok.ok);
  const auto bad = parseInstallOutcome("error\nthe administrator prompt was declined\n");
  EXPECT_TRUE(bad.present);
  EXPECT_FALSE(bad.ok);
  EXPECT_EQ(bad.error, QStringLiteral("the administrator prompt was declined"));
}

class UpdateDownload : public ::testing::Test {
 protected:
  void SetUp() override {
    ensureApp();
    m_server = std::make_unique<heap::testing::FakeHttpServer>();
    ASSERT_TRUE(m_dir.isValid());
  }

  // A fake GitHub: the release JSON points at assets on the same server.
  void publish(const QByteArray& package, const QByteArray& sums) {
    const QString base = m_server->base();
    const QByteArray release = QStringLiteral(
                                   "{\"tag_name\":\"v9.0.0\",\"html_url\":\"%1/r\",\"assets\":["
                                   "{\"name\":\"heap-v9.0.0-windows-portable.zip\",\"browser_download_url\":\"%1/dl/pkg\"},"
                                   "{\"name\":\"SHA256SUMS\",\"browser_download_url\":\"%1/dl/sums\"}]}")
                                   .arg(base)
                                   .toUtf8();
    m_server->route("GET /latest", {200, release});
    m_server->route("GET /dl/pkg", {200, package});
    m_server->route("GET /dl/sums", {200, sums});
  }

  // Check, then download the portable zip; returns the signal that ended it.
  QString run(heap::update::Updater& u, QString& path, QString& sha, int& failure) {
    u.setLatestReleaseUrl(m_server->base() + QStringLiteral("/latest"));
    bool checked = false;
    QObject::connect(&u, &heap::update::Updater::updateAvailable, [&checked]() {
      checked = true;
    });
    u.checkForUpdates();
    if(!heap::testing::waitFor(checked)) {
      return QStringLiteral("no check");
    }
    QString ended;
    QObject::connect(&u, &heap::update::Updater::downloadVerified, [&](const QString& p, const QString& s) {
      path = p;
      sha = s;
      ended = QStringLiteral("verified");
    });
    QObject::connect(&u, &heap::update::Updater::downloadFailed, [&](int kind, const QString&) {
      failure = kind;
      ended = QStringLiteral("failed");
    });
    u.downloadAsset(QStringLiteral("heap-v9.0.0-windows-portable.zip"), m_dir.path());
    heap::testing::waitUntil([&ended]() {
      return !ended.isEmpty();
    });
    return ended;
  }

  std::unique_ptr<heap::testing::FakeHttpServer> m_server;
  QTemporaryDir m_dir;
};

TEST_F(UpdateDownload, AFileThatMatchesTheChecksumIsHandedOn) {
  const QByteArray package(200000, 'x');
  publish(package, hexSha256(package).toLatin1() + "  heap-v9.0.0-windows-portable.zip\n");
  heap::update::Updater u(QStringLiteral("0.5.7"));
  QString path;
  QString sha;
  int failure = -1;
  ASSERT_EQ(run(u, path, sha, failure), QStringLiteral("verified"));
  EXPECT_EQ(sha, hexSha256(package));
  QFile f(path);
  ASSERT_TRUE(f.open(QIODevice::ReadOnly));
  EXPECT_EQ(f.readAll(), package);
}

TEST_F(UpdateDownload, AFileThatDoesNotMatchIsDeleted) {
  const QByteArray package(5000, 'x');
  publish(package, hexSha256("something else").toLatin1() + "  heap-v9.0.0-windows-portable.zip\n");
  heap::update::Updater u(QStringLiteral("0.5.7"));
  QString path;
  QString sha;
  int failure = -1;
  ASSERT_EQ(run(u, path, sha, failure), QStringLiteral("failed"));
  EXPECT_EQ(failure, static_cast<int>(heap::update::DownloadFailure::ChecksumMismatch));
  EXPECT_FALSE(QFileInfo::exists(QDir(m_dir.path()).filePath(QStringLiteral("heap-v9.0.0-windows-portable.zip"))))
      << "a file the release did not publish stayed on disk";
}

TEST_F(UpdateDownload, NoChecksumNoInstall) {
  const QByteArray package(5000, 'x');
  publish(package, "0000000000000000000000000000000000000000000000000000000000000000  another-file.zip\n");
  heap::update::Updater u(QStringLiteral("0.5.7"));
  QString path;
  QString sha;
  int failure = -1;
  ASSERT_EQ(run(u, path, sha, failure), QStringLiteral("failed"));
  EXPECT_EQ(failure, static_cast<int>(heap::update::DownloadFailure::NoChecksum));
  EXPECT_FALSE(QFileInfo::exists(QDir(m_dir.path()).filePath(QStringLiteral("heap-v9.0.0-windows-portable.zip"))));
}

// ── heap-updater's folder swap ──

namespace {

namespace fs = std::filesystem;

void writeFile(const fs::path& p, const std::string& text) {
  fs::create_directories(p.parent_path());
  std::ofstream(p, std::ios::binary) << text;
}

std::string readFile(const fs::path& p) {
  std::ifstream in(p, std::ios::binary);
  return {std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>()};
}

}  // namespace

TEST(UpdateBundleSwap, ReplacesWhatTheNewVersionShipsAndKeepsTheRest) {
  QTemporaryDir tmp;
  const fs::path root = fs::path(tmp.path().toStdWString());
  const fs::path target = root / "heap";
  const fs::path staging = root / "staging";
  writeFile(target / "heap.exe", "old exe");
  writeFile(target / "qml" / "Old.qml", "old qml");
  writeFile(target / "notes-i-keep-here.txt", "mine");
  writeFile(staging / "heap.exe", "new exe");
  writeFile(staging / "qml" / "New.qml", "new qml");

  std::string error;
  ASSERT_TRUE(heap::updater::swapBundle(staging, target, error)) << error;
  EXPECT_EQ(readFile(target / "heap.exe"), "new exe");
  EXPECT_TRUE(fs::exists(target / "qml" / "New.qml"));
  EXPECT_FALSE(fs::exists(target / "qml" / "Old.qml")) << "a shipped folder is replaced whole";
  EXPECT_EQ(readFile(target / "notes-i-keep-here.txt"), "mine");
  EXPECT_FALSE(fs::exists(target / ".heap-update-old")) << "the moved-aside copy is cleaned up";
}

TEST(UpdateBundleSwap, AFailedSwapLeavesTheOldVersion) {
  QTemporaryDir tmp;
  const fs::path root = fs::path(tmp.path().toStdWString());
  const fs::path target = root / "heap";
  writeFile(target / "heap.exe", "old exe");
  std::string error;
  EXPECT_FALSE(heap::updater::swapBundle(root / "nothing-here", target, error));
  EXPECT_FALSE(error.empty());
  EXPECT_EQ(readFile(target / "heap.exe"), "old exe");
}
