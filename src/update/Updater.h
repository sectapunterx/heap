#pragma once

#include <QObject>
#include <QString>

class QNetworkAccessManager;

// GitHub-Releases update checker (HEAP-63). Polls the public releases API for
// the latest published release and reports whether it is newer than the running
// build. It never downloads or installs anything — acting on an available
// update is left to the caller (open the release page). No auth/token needed for
// public repos.
namespace heap::update {

// Compare two version strings ("v0.5.0", "0.5.0", "0.5.0-rc1"). Returns true iff
// `latest` is strictly newer than `current`. A leading 'v'/'V' is ignored;
// dotted numeric components are compared left-to-right (missing = 0); with an
// equal numeric core, a pre-release ("-rc1") ranks below the plain release.
// Non-numeric components degrade to 0. Pure function — unit-tested directly.
// Build metadata ("+hotfix") is ignored; two pre-releases of one core compare
// identifier by identifier, "rc1" < "rc2" < "rc10" < the release.
bool isNewerVersion(const QString& current, const QString& latest);

// Why a check did not answer, so the UI can say "couldn't check" for the
// network's (or GitHub's rate limit's) fault rather than "failed".
enum class CheckFailure : int {
  Offline = 0,      // no connection, DNS, timeout
  RateLimited = 1,  // GitHub 403 / 429
  Other = 2,
};

// `networkError` is a QNetworkReply::NetworkError. Pure — unit-tested.
CheckFailure classifyCheckFailure(int httpStatus, int networkError);

class Updater : public QObject {
  Q_OBJECT

 public:
  explicit Updater(QString currentVersion, QObject* parent = nullptr);
  ~Updater() override;

  // Start an async check. Emits exactly one of updateAvailable / upToDate /
  // checkFailed. A no-op while a previous check is still in flight.
  void checkForUpdates();

  bool isChecking() const {
    return m_checking;
  }

 signals:
  void updateAvailable(const QString& latestVersion, const QString& releaseUrl);
  void upToDate(const QString& currentVersion);
  // `kind` is a CheckFailure.
  void checkFailed(int kind, const QString& error);

 private:
  QString m_currentVersion;
  QNetworkAccessManager* m_nam = nullptr;
  bool m_checking = false;
};

}  // namespace heap::update
