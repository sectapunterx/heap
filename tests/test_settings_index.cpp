// The settings search index (qml/SettingsIndex.js, APP-207) against the rows
// it indexes (qml/SettingsView.qml).
//
// Settings search and the Tweaks panel find a setting through the index, so
// a row the index does not know about cannot be found at all. This reads the
// sources and fails when a SettingsRow's or a SettingsGroup's title key is
// missing from the index or filed under another section, and when an index
// entry no longer belongs to anything on the page.

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QRegularExpression>
#include <QSet>
#include <QString>
#include <QStringList>

#include <gtest/gtest.h>

#include <algorithm>

namespace {

QString readFile(const QString& path) {
  QFile f(path);
  if(!f.open(QFile::ReadOnly | QFile::Text)) {
    return {};
  }
  return QString::fromUtf8(f.readAll());
}

QString qmlPath(const QString& name) {
  return QDir(QStringLiteral(HEAP_QML_DIR)).filePath(name);
}

struct IndexEntry {
  QString section;
  QString kind;
  QString key;
};

QList<IndexEntry> loadIndex() {
  const QString src = readFile(qmlPath(QStringLiteral("SettingsIndex.js")));
  static const QRegularExpression rx(QStringLiteral(R"re(\[\s*"(\w+)"\s*,\s*"(\w+)"\s*,\s*"([^"]+)"\s*(?:,\s*"[^"]+"\s*)?\])re"));
  QList<IndexEntry> out;
  auto it = rx.globalMatch(src);
  while(it.hasNext()) {
    const auto m = it.next();
    out.append({m.captured(1), m.captured(2), m.captured(3)});
  }
  return out;
}

QStringList loadSectionIds() {
  const QString src = readFile(qmlPath(QStringLiteral("SettingsIndex.js")));
  static const QRegularExpression rx(QStringLiteral(R"re(\{\s*id:\s*"(\w+)"\s*,\s*icon:)re"));
  QStringList out;
  auto it = rx.globalMatch(src);
  while(it.hasNext()) {
    out << it.next().captured(1);
  }
  return out;
}

// What SettingsView.qml puts on each section's page.
struct Page {
  // (section, key) of every row and group title.
  QSet<QPair<QString, QString>> titles;
  // section → the element types it instantiates.
  QHash<QString, QSet<QString>> types;
};

QSet<QString> rowTypes(const QString& view) {
  QSet<QString> out{QStringLiteral("SettingsRow")};
  static const QRegularExpression inlineRow(QStringLiteral(R"re(^\s*component\s+(\w+)\s*:\s*SettingsRow\b)re"),
                                            QRegularExpression::MultilineOption);
  auto it = inlineRow.globalMatch(view);
  while(it.hasNext()) {
    out.insert(it.next().captured(1));
  }
  // Files whose root is a SettingsRow (CursorColorRow.qml).
  static const QRegularExpression fileRoot(QStringLiteral(R"re(^SettingsRow\s*\{)re"), QRegularExpression::MultilineOption);
  const QDir dir(QStringLiteral(HEAP_QML_DIR));
  for(const QString& name : dir.entryList({QStringLiteral("*.qml")}, QDir::Files)) {
    if(fileRoot.match(readFile(dir.filePath(name))).hasMatch()) {
      out.insert(QFileInfo(name).completeBaseName());
    }
  }
  return out;
}

Page readPage() {
  const QString view = readFile(qmlPath(QStringLiteral("SettingsView.qml")));
  const QSet<QString> rows = rowTypes(view);
  static const QRegularExpression strings(QStringLiteral(R"re("(?:[^"\\]|\\.)*")re"));
  static const QRegularExpression braces(QStringLiteral(R"re((?:\b([A-Z]\w*)\s*)?\{|\})re"));
  static const QRegularExpression sectionId(QStringLiteral(R"re(^\s*id:\s*section([A-Z]\w*)\s*$)re"));
  static const QRegularExpression titleProp(QStringLiteral(R"re(^\s*(label|title):\s*I18n\.t\("([^"]+)"\))re"));

  Page page;
  QStringList stack;  // element type per open brace, "" for a non-element block
  QString section;
  qsizetype sectionDepth = -1;
  for(const QString& line : view.split(QChar('\n'))) {
    const QString top = stack.isEmpty() ? QString() : stack.last();
    if(const auto m = sectionId.match(line); m.hasMatch() && top == QStringLiteral("Component")) {
      section = m.captured(1);
      section[0] = section[0].toLower();
      sectionDepth = stack.size() - 1;
    }
    if(const auto m = titleProp.match(line); m.hasMatch() && !section.isEmpty()) {
      const bool rowLabel = m.captured(1) == QStringLiteral("label") && rows.contains(top);
      const bool titled =
          m.captured(1) == QStringLiteral("title") && (top == QStringLiteral("SettingsGroup") || top == QStringLiteral("DangerRow"));
      if(rowLabel || titled) {
        page.titles.insert({section, m.captured(2)});
      }
    }
    QString code = line;
    code.replace(strings, QStringLiteral("\"\""));
    if(const qsizetype c = code.indexOf(QStringLiteral("//")); c >= 0) {
      code.truncate(c);
    }
    auto it = braces.globalMatch(code);
    while(it.hasNext()) {
      const auto b = it.next();
      if(b.captured(0) == QStringLiteral("}")) {
        if(!stack.isEmpty()) {
          stack.removeLast();
        }
        if(sectionDepth >= 0 && stack.size() <= sectionDepth) {
          section.clear();
          sectionDepth = -1;
        }
      } else {
        stack << b.captured(1);
        if(!section.isEmpty() && !b.captured(1).isEmpty()) {
          page.types[section].insert(b.captured(1));
        }
      }
    }
  }
  return page;
}

// The qml files (other than the view and I18n) that ask I18n for `key`.
QStringList filesUsing(const QString& key) {
  QStringList out;
  const QString needle = QStringLiteral("I18n.t(\"") + key + QStringLiteral("\")");
  const QDir dir(QStringLiteral(HEAP_QML_DIR));
  for(const QString& name : dir.entryList({QStringLiteral("*.qml")}, QDir::Files)) {
    if(name == QStringLiteral("I18n.qml") || name == QStringLiteral("SettingsView.qml")) {
      continue;
    }
    if(readFile(dir.filePath(name)).contains(needle)) {
      out << QFileInfo(name).completeBaseName();
    }
  }
  return out;
}

}  // namespace

TEST(SettingsIndex, ReadsTheSources) {
  EXPECT_GT(loadIndex().size(), 80) << "could not read qml/SettingsIndex.js";
  EXPECT_GT(readPage().titles.size(), 80) << "could not read the rows of qml/SettingsView.qml";
}

// Every row title and group heading in Settings is in the index, under the
// section it is on.
TEST(SettingsIndex, EveryRowTitleKey_IsIndexed) {
  const Page page = readPage();
  QSet<QPair<QString, QString>> indexed;
  QHash<QString, QString> sectionOf;
  for(const IndexEntry& e : loadIndex()) {
    indexed.insert({e.section, e.key});
    sectionOf.insert(e.key, e.section);
  }
  QStringList missing;
  for(const auto& t : page.titles) {
    if(!indexed.contains(t)) {
      missing << t.first + QStringLiteral(": ") + t.second +
                     (sectionOf.contains(t.second) ? QStringLiteral(" (indexed under ") + sectionOf.value(t.second) + ')' : QString());
    }
  }
  missing.sort();
  EXPECT_TRUE(missing.isEmpty()) << "settings rows the search cannot find — add them to qml/SettingsIndex.js:\n"
                                 << missing.join(QChar('\n')).toStdString();
}

// Nothing in the index points at a setting that is gone: an entry is either
// a row of its section in SettingsView.qml, or the title of a card that the
// section puts on its page (IntegrationHealthCard, AutoSyncCard…).
TEST(SettingsIndex, EveryEntry_BelongsToItsSectionPage) {
  const Page page = readPage();
  QStringList stale;
  for(const IndexEntry& e : loadIndex()) {
    if(page.titles.contains({e.section, e.key})) {
      continue;
    }
    const QSet<QString> onSectionPage = page.types.value(e.section);
    const QStringList users = filesUsing(e.key);
    if(std::ranges::none_of(users, [&](const QString& file) {
         return onSectionPage.contains(file);
       })) {
      stale << e.section + QStringLiteral(": ") + e.key;
    }
  }
  EXPECT_TRUE(stale.isEmpty()) << "index entries with no setting behind them:\n" << stale.join(QChar('\n')).toStdString();
}

TEST(SettingsIndex, Kinds_AreKnown) {
  const QSet<QString> kinds{QStringLiteral("row"), QStringLiteral("group"), QStringLiteral("card")};
  for(const IndexEntry& e : loadIndex()) {
    EXPECT_TRUE(kinds.contains(e.kind)) << e.key.toStdString() << ": " << e.kind.toStdString();
  }
}

// The section catalogue the nav is built from matches the pages there are.
TEST(SettingsIndex, EverySection_HasAPage) {
  const QStringList ids = loadSectionIds();
  ASSERT_GT(ids.size(), 10);
  const QString view = readFile(qmlPath(QStringLiteral("SettingsView.qml")));
  for(const QString& id : ids) {
    QString comp = id;
    comp[0] = comp[0].toUpper();
    EXPECT_TRUE(view.contains(QStringLiteral("id: section") + comp + QChar('\n')) ||
                view.contains(QStringLiteral("id: section") + comp + QStringLiteral("\r\n")))
        << "no page for section " << id.toStdString();
  }
  const QSet<QString> sectionSet(ids.cbegin(), ids.cend());
  for(const IndexEntry& e : loadIndex()) {
    EXPECT_TRUE(sectionSet.contains(e.section)) << e.key.toStdString() << " is under unknown section " << e.section.toStdString();
  }
}
