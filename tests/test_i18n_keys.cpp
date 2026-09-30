// Every key the QML asks I18n.t() for must exist in both dictionaries.
//
// A missing key renders as the key itself: the audit found
// "docs.cat.snippets.sub" printed under a heading in the Docs view, in both
// languages, with the whole QML suite green. This reads the sources, so a key
// added to a view without a translation fails here instead of on screen.

#include <QDir>
#include <QFile>
#include <QRegularExpression>
#include <QSet>
#include <QString>
#include <QStringList>

#include <gtest/gtest.h>

namespace {

QString readFile(const QString& path) {
  QFile f(path);
  if(!f.open(QFile::ReadOnly | QFile::Text)) {
    return {};
  }
  return QString::fromUtf8(f.readAll());
}

QSet<QString> keysIn(const QString& block) {
  static const QRegularExpression rx(QStringLiteral(R"re(^\s*"([^"]+)"\s*:)re"), QRegularExpression::MultilineOption);
  QSet<QString> out;
  auto it = rx.globalMatch(block);
  while(it.hasNext()) {
    out.insert(it.next().captured(1));
  }
  return out;
}

struct Dictionaries {
  QSet<QString> en;
  QSet<QString> ru;
};

Dictionaries loadDictionaries() {
  const QString src = readFile(QStringLiteral(HEAP_QML_DIR "/I18n.qml"));
  const qsizetype en = src.indexOf(QStringLiteral("\n        en: {"));
  const qsizetype ru = src.indexOf(QStringLiteral("\n        ru: {"));
  if(en < 0 || ru < 0) {
    return {};
  }
  return {keysIn(src.mid(en, ru - en)), keysIn(src.mid(ru))};
}

}  // namespace

TEST(I18n, T_EveryKeyUsedInQml_ExistsInBothLanguages) {
  const Dictionaries dict = loadDictionaries();
  ASSERT_GT(dict.en.size(), 100) << "could not read qml/I18n.qml";
  static const QRegularExpression use(QStringLiteral(R"re(I18n\.t\("([^"]+)"\))re"));
  QStringList missing;
  const QDir dir(QStringLiteral(HEAP_QML_DIR));
  for(const QString& name : dir.entryList({QStringLiteral("*.qml"), QStringLiteral("*.js")}, QDir::Files)) {
    if(name == QStringLiteral("I18n.qml")) {
      continue;
    }
    auto it = use.globalMatch(readFile(dir.filePath(name)));
    while(it.hasNext()) {
      const QString key = it.next().captured(1);
      if(!dict.en.contains(key) || !dict.ru.contains(key)) {
        missing << name + QStringLiteral(": ") + key;
      }
    }
  }
  EXPECT_TRUE(missing.isEmpty()) << missing.join(QChar('\n')).toStdString();
}

TEST(I18n, Dict_EnglishAndRussian_HaveTheSameKeys) {
  const Dictionaries dict = loadDictionaries();
  ASSERT_GT(dict.en.size(), 100);
  QStringList onlyEn = (dict.en - dict.ru).values();
  QStringList onlyRu = (dict.ru - dict.en).values();
  onlyEn.sort();
  onlyRu.sort();
  EXPECT_TRUE(onlyEn.isEmpty()) << "missing in ru: " << onlyEn.join(QStringLiteral(", ")).toStdString();
  EXPECT_TRUE(onlyRu.isEmpty()) << "missing in en: " << onlyRu.join(QStringLiteral(", ")).toStdString();
}

// The C++ side has its own EN/RU table (AppController::tr_). A key missing
// there reaches the toast as the raw key, in both languages.
TEST(I18n, Tr_EveryKeyUsedInAppController_IsInTheTable) {
  const QString src = readFile(QStringLiteral(HEAP_SRC_DIR "/AppController.cpp"));
  ASSERT_FALSE(src.isEmpty());
  const qsizetype begin = src.indexOf(QStringLiteral("i18nTable() {"));
  const qsizetype end = src.indexOf(QStringLiteral("\n  };"), begin);
  ASSERT_GT(begin, 0);
  static const QRegularExpression entry(QStringLiteral(R"re(\{"([^"]+)",\s*\{)re"));
  QSet<QString> table;
  auto rows = entry.globalMatch(src.mid(begin, end - begin));
  while(rows.hasNext()) {
    table.insert(rows.next().captured(1));
  }
  // tr_ falls back to the integrations' own table (IntegrationI18n.cpp).
  static const QRegularExpression ownEntry(QStringLiteral(R"re(\{QStringLiteral\("([^"]+)"\),\s*\{)re"));
  auto own = ownEntry.globalMatch(readFile(QStringLiteral(HEAP_SRC_DIR "/integrations/IntegrationI18n.cpp")));
  while(own.hasNext()) {
    table.insert(own.next().captured(1));
  }
  static const QRegularExpression use(QStringLiteral(R"re(tr_\("([^"]+)"\))re"));
  QStringList missing;
  auto it = use.globalMatch(src);
  while(it.hasNext()) {
    const QString key = it.next().captured(1);
    if(!table.contains(key)) {
      missing << key;
    }
  }
  missing.removeDuplicates();
  EXPECT_TRUE(missing.isEmpty()) << missing.join(QStringLiteral(", ")).toStdString();
}
