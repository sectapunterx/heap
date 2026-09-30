#include "update/Updater.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QStringList>
#include <QUrl>

#include <utility>

namespace heap::update {

namespace {

// GitHub REST endpoint for the newest *published* (non-draft, non-prerelease)
// release of the repo.
constexpr auto kLatestReleaseUrl = "https://api.github.com/repos/sectapunterx/heap/releases/latest";
// A check that has not answered by then is not going to; without a limit a
// dead network held "Checking for updates…" on screen for minutes.
constexpr int kCheckTimeoutMs = 15 * 1000;

struct ParsedVersion {
  QList<int> parts;
  QStringList preRelease;  // dot-separated identifiers after '-'; empty = a release
};

ParsedVersion parseVersion(QString v) {
  v = v.trimmed();
  if(v.startsWith('v') || v.startsWith('V')) {
    v.remove(0, 1);
  }
  // SemVer §10: build metadata ("+hotfix", "+20260930") takes no part in
  // precedence. It used to be read into the last number ("2+hotfix" → 0).
  const qsizetype plus = v.indexOf('+');
  if(plus >= 0) {
    v.truncate(plus);
  }
  const qsizetype dash = v.indexOf('-');
  ParsedVersion parsed;
  if(dash >= 0) {
    parsed.preRelease = v.mid(dash + 1).split('.', Qt::SkipEmptyParts);
    if(parsed.preRelease.isEmpty()) {
      parsed.preRelease.append(QStringLiteral("0"));  // "1.0.0-" is still a pre-release
    }
  }
  const QString core = dash >= 0 ? v.left(dash) : v;
  const QStringList comps = core.split('.', Qt::SkipEmptyParts);
  for(const QString& c : comps) {
    bool ok = false;
    const int n = c.toInt(&ok);
    parsed.parts.append(ok ? n : 0);
  }
  return parsed;
}

// One pre-release identifier against another. SemVer compares numeric ones
// numerically and the rest in ASCII order, numeric below alphanumeric. On top
// of that a letters-then-digits identifier ("rc2", "beta10") compares its
// digits as a number, so rc10 comes after rc9 the way people mean it.
int compareIdentifier(const QString& a, const QString& b) {
  bool aNum = false;
  bool bNum = false;
  const qlonglong an = a.toLongLong(&aNum);
  const qlonglong bn = b.toLongLong(&bNum);
  if(aNum && bNum) {
    return an < bn ? -1 : (an > bn ? 1 : 0);
  }
  if(aNum != bNum) {
    return aNum ? -1 : 1;
  }
  const auto split = [](const QString& s, QString& stem, qlonglong& num) {
    qsizetype i = s.size();
    while(i > 0 && s.at(i - 1).isDigit()) {
      --i;
    }
    stem = s.left(i);
    bool ok = false;
    num = i < s.size() ? s.mid(i).toLongLong(&ok) : -1;
    if(!ok) {
      num = -1;
    }
  };
  QString aStem;
  QString bStem;
  qlonglong aN = -1;
  qlonglong bN = -1;
  split(a, aStem, aN);
  split(b, bStem, bN);
  if(aStem == bStem && !aStem.isEmpty()) {
    return aN < bN ? -1 : (aN > bN ? 1 : 0);
  }
  return QString::compare(a, b, Qt::CaseSensitive) < 0 ? -1 : (a == b ? 0 : 1);
}

}  // namespace

bool isNewerVersion(const QString& current, const QString& latest) {
  const ParsedVersion a = parseVersion(current);
  const ParsedVersion b = parseVersion(latest);
  const qsizetype n = qMax(a.parts.size(), b.parts.size());
  for(qsizetype i = 0; i < n; ++i) {
    const int av = i < a.parts.size() ? a.parts.at(i) : 0;
    const int bv = i < b.parts.size() ? b.parts.at(i) : 0;
    if(bv != av) {
      return bv > av;
    }
  }
  // Equal numeric core: a plain release outranks a pre-release of the same core.
  const bool aPre = !a.preRelease.isEmpty();
  const bool bPre = !b.preRelease.isEmpty();
  if(aPre != bPre) {
    return aPre;
  }
  if(!aPre) {
    return false;
  }
  // Both pre-releases: identifier by identifier, then the longer list wins.
  const qsizetype m = qMin(a.preRelease.size(), b.preRelease.size());
  for(qsizetype i = 0; i < m; ++i) {
    const int c = compareIdentifier(a.preRelease.at(i), b.preRelease.at(i));
    if(c != 0) {
      return c < 0;
    }
  }
  return b.preRelease.size() > a.preRelease.size();
}

CheckFailure classifyCheckFailure(int httpStatus, int networkError) {
  // 403 with an exhausted X-RateLimit is how GitHub says "later" to an
  // unauthenticated client (60 requests an hour per IP — a shared office NAT
  // uses that up); 429 is the same thing said plainly. Neither is a failure of
  // the update check itself.
  if(httpStatus == 403 || httpStatus == 429) {
    return CheckFailure::RateLimited;
  }
  if(httpStatus == 0) {
    switch(static_cast<QNetworkReply::NetworkError>(networkError)) {
      case QNetworkReply::HostNotFoundError:
      case QNetworkReply::TimeoutError:
      case QNetworkReply::OperationCanceledError:
      case QNetworkReply::ConnectionRefusedError:
      case QNetworkReply::RemoteHostClosedError:
      case QNetworkReply::TemporaryNetworkFailureError:
      case QNetworkReply::NetworkSessionFailedError:
      case QNetworkReply::UnknownNetworkError:
      case QNetworkReply::ProxyConnectionRefusedError:
      case QNetworkReply::ProxyNotFoundError:
      case QNetworkReply::ProxyTimeoutError:
        return CheckFailure::Offline;
      default:
        break;
    }
  }
  return CheckFailure::Other;
}

Updater::Updater(QString currentVersion, QObject* parent) :
    QObject(parent), m_currentVersion(std::move(currentVersion)), m_nam(new QNetworkAccessManager(this)) {
}

Updater::~Updater() = default;

void Updater::checkForUpdates() {
  if(m_checking) {
    return;
  }
  m_checking = true;

  QNetworkRequest req{QUrl(QLatin1String(kLatestReleaseUrl))};
  req.setRawHeader("Accept", "application/vnd.github+json");
  req.setRawHeader("User-Agent", "heap-updater");
  req.setTransferTimeout(kCheckTimeoutMs);

  QNetworkReply* reply = m_nam->get(req);
  connect(reply, &QNetworkReply::finished, this, [this, reply]() {
    reply->deleteLater();
    m_checking = false;

    if(reply->error() != QNetworkReply::NoError) {
      const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
      emit checkFailed(static_cast<int>(classifyCheckFailure(status, reply->error())), reply->errorString());
      return;
    }

    const QJsonObject obj = QJsonDocument::fromJson(reply->readAll()).object();
    const QString tag = obj.value(QStringLiteral("tag_name")).toString();
    const QString url = obj.value(QStringLiteral("html_url")).toString();
    if(tag.isEmpty()) {
      emit checkFailed(static_cast<int>(CheckFailure::Other), QStringLiteral("no release tag in GitHub response"));
      return;
    }

    if(isNewerVersion(m_currentVersion, tag)) {
      emit updateAvailable(tag, url);
    } else {
      emit upToDate(m_currentVersion);
    }
  });
}

}  // namespace heap::update
