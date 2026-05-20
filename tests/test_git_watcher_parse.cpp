#include <gtest/gtest.h>

#include "git/BranchTaskMatcher.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>

using heap::git::BranchTaskMatcher;

TEST(Parse, BranchFromRefHeadText) {
    auto b = BranchTaskMatcher::branchFromHeadText(
        QStringLiteral("ref: refs/heads/feature/x\n"));
    EXPECT_EQ(b, QString("feature/x"));
}

TEST(Parse, BranchFromDetachedSha) {
    auto b = BranchTaskMatcher::branchFromHeadText(
        QStringLiteral("a3f9b1c8d2e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8\n"));
    EXPECT_EQ(b, QString("(detached HEAD)"));
}

TEST(Parse, BranchFromGarbageEmpty) {
    EXPECT_TRUE(BranchTaskMatcher::branchFromHeadText(
        QStringLiteral("garbage")).isEmpty());
}

TEST(Parse, ResolveGitDirNormal) {
    QTemporaryDir td;
    ASSERT_TRUE(td.isValid());
    ASSERT_TRUE(QDir(td.path()).mkdir(".git"));
    const QString gd = BranchTaskMatcher::resolveGitDir(td.path());
    EXPECT_TRUE(gd.endsWith("/.git"));
    EXPECT_TRUE(QFileInfo(gd).isDir());
}

TEST(Parse, ResolveGitDirWorktreeFile) {
    QTemporaryDir td;
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
    QTemporaryDir td;
    ASSERT_TRUE(td.isValid());
    const QString rel = "subdir/realgit";
    ASSERT_TRUE(QDir(td.path()).mkpath(rel));
    QFile f(td.path() + "/.git");
    ASSERT_TRUE(f.open(QIODevice::WriteOnly));
    f.write(("gitdir: " + rel + "\n").toUtf8());
    f.close();
    const QString gd = BranchTaskMatcher::resolveGitDir(td.path());
    EXPECT_EQ(QDir::cleanPath(gd),
              QDir::cleanPath(td.path() + "/" + rel));
}

TEST(Parse, ResolveGitDirMissing) {
    QTemporaryDir td;
    ASSERT_TRUE(td.isValid());
    EXPECT_TRUE(BranchTaskMatcher::resolveGitDir(td.path()).isEmpty());
}
