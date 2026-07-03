#include "git/BranchTaskMatcher.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>

#include <gtest/gtest.h>

using heap::git::BranchTaskMatcher;

TEST(Parse, BranchFromRefHeadText) {
  auto b = BranchTaskMatcher::branchFromHeadText(QStringLiteral("ref: refs/heads/feature/x\n"));
  EXPECT_EQ(b, QString("feature/x"));
}

TEST(Parse, BranchFromDetachedSha) {
  auto b = BranchTaskMatcher::branchFromHeadText(QStringLiteral("a3f9b1c8d2e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8\n"));
  EXPECT_EQ(b, QString("(detached HEAD)"));
}

TEST(Parse, BranchFromGarbageEmpty) {
  EXPECT_TRUE(BranchTaskMatcher::branchFromHeadText(QStringLiteral("garbage")).isEmpty());
}

TEST(Parse, ResolveGitDirNormal) {
  const QTemporaryDir td;
  ASSERT_TRUE(td.isValid());
  ASSERT_TRUE(QDir(td.path()).mkdir(".git"));
  const QString gd = BranchTaskMatcher::resolveGitDir(td.path());
  EXPECT_TRUE(gd.endsWith("/.git"));
  EXPECT_TRUE(QFileInfo(gd).isDir());
}

TEST(Parse, ResolveGitDirWorktreeFile) {
  const QTemporaryDir td;
  ASSERT_TRUE(td.isValid());
  const QString realGit = td.path() + "/realgit";
  ASSERT_TRUE(QDir().mkpath(realGit));
  QFile f(td.path() + "/.git");
  ASSERT_TRUE(f.open(QIODevice::WriteOnly));
  f.write(("gitdir: " + realGit + "\n").toUtf8());
  f.close();
  const QString gd = BranchTaskMatcher::resolveGitDir(td.path());
  EXPECT_EQ(QDir::cleanPath(gd), QDir::cleanPath(realGit));
}

TEST(Parse, ResolveGitDirWorktreeFileRelative) {
  const QTemporaryDir td;
  ASSERT_TRUE(td.isValid());
  const QString rel = "subdir/realgit";
  ASSERT_TRUE(QDir(td.path()).mkpath(rel));
  QFile f(td.path() + "/.git");
  ASSERT_TRUE(f.open(QIODevice::WriteOnly));
  f.write(("gitdir: " + rel + "\n").toUtf8());
  f.close();
  const QString gd = BranchTaskMatcher::resolveGitDir(td.path());
  EXPECT_EQ(QDir::cleanPath(gd), QDir::cleanPath(td.path() + "/" + rel));
}

TEST(Parse, ResolveGitDirMissing) {
  const QTemporaryDir td;
  ASSERT_TRUE(td.isValid());
  EXPECT_TRUE(BranchTaskMatcher::resolveGitDir(td.path()).isEmpty());
}

// ── HEAP-76: branch-name derivation ──

TEST(Slug, LowercasesAndHyphenates) {
  EXPECT_EQ(BranchTaskMatcher::slugifyTitle("Fix the Login Bug"), QString("fix-the-login-bug"));
}

TEST(Slug, CollapsesAndTrimsSeparators) {
  EXPECT_EQ(BranchTaskMatcher::slugifyTitle("  Hello,   World!!  "), QString("hello-world"));
}

TEST(Slug, EmptyForPunctuationOnly) {
  EXPECT_EQ(BranchTaskMatcher::slugifyTitle("!!! ??? ..."), QString());
}

TEST(Slug, CapsLength) {
  const QString slug = BranchTaskMatcher::slugifyTitle(QString("word ").repeated(30).trimmed());
  EXPECT_LE(slug.size(), 40);
  EXPECT_FALSE(slug.endsWith('-'));
}

TEST(BranchName, DefaultTemplate) {
  EXPECT_EQ(BranchTaskMatcher::branchNameForTask("HEAP-76", "Git write actions", QString()), QString("feature/heap-76-git-write-actions"));
}

TEST(BranchName, CustomTemplatePlaceholders) {
  EXPECT_EQ(BranchTaskMatcher::branchNameForTask("HEAP-76", "Do Thing", "{type}/{id}/{slug}"), QString("feature/heap-76/do-thing"));
}

TEST(BranchName, EmptyTitleDropsDanglingSeparator) {
  EXPECT_EQ(BranchTaskMatcher::branchNameForTask("HEAP-76", "  ", QString()), QString("feature/heap-76"));
}

// ── HEAP-76: commit ↔ task grouping ──

TEST(Commits, GroupsBySubjectTaskId) {
  BranchTaskMatcher m({"HEAP"});
  QByteArray log;
  log +=
      "aaaaaaa1111111111111111111111111111bbbb\x1f"
      "HEAP-76 add branch action\n";
  log +=
      "bbbbbbb2222222222222222222222222222cccc\x1f"
      "HEAP-76: linking commits\n";
  log +=
      "ccccccc3333333333333333333333333333dddd\x1f"
      "HEAP-40 unrelated older work\n";
  log +=
      "ddddddd4444444444444444444444444444eeee\x1f"
      "chore: no task id here\n";
  const QVariantMap byTask = m.groupCommitsByTask(log);
  ASSERT_TRUE(byTask.contains("HEAP-76"));
  ASSERT_TRUE(byTask.contains("HEAP-40"));
  EXPECT_FALSE(byTask.contains(""));  // subjects without an id are dropped
  const QVariantList h76 = byTask.value("HEAP-76").toList();
  EXPECT_EQ(h76.size(), 2);
  // sha is abbreviated to 7 chars; subject preserved verbatim.
  EXPECT_EQ(h76.first().toMap().value("sha").toString(), QString("aaaaaaa"));
  EXPECT_EQ(h76.first().toMap().value("subject").toString(), QString("HEAP-76 add branch action"));
}

TEST(Commits, EmptyLogYieldsEmptyMap) {
  BranchTaskMatcher m({"HEAP"});
  EXPECT_TRUE(m.groupCommitsByTask(QByteArray()).isEmpty());
}
