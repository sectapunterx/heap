// The "there is a key for that" counter (APP-166): the third mouse use of an
// action shows its shortcut once, and never again.
#include "hints/ShortcutHints.h"

#include <QJsonDocument>

#include <gtest/gtest.h>

using heap::hints::kMouseUsesBeforeHint;
using heap::hints::recordMouseUse;

TEST(ShortcutHints, ThirdMouseUseShowsTheHint) {
  QJsonObject uses;
  EXPECT_FALSE(recordMouseUse(uses, "palette.open", true, true).showHint);
  EXPECT_FALSE(recordMouseUse(uses, "palette.open", true, true).showHint);
  const auto third = recordMouseUse(uses, "palette.open", true, true);
  EXPECT_TRUE(third.changed);
  EXPECT_TRUE(third.showHint);
  EXPECT_EQ(uses.value("palette.open").toInt(), kMouseUsesBeforeHint);
}

TEST(ShortcutHints, NeverAgainAfterTheHint) {
  QJsonObject uses;
  for(int i = 0; i < kMouseUsesBeforeHint; ++i) {
    recordMouseUse(uses, "view.week", true, true);
  }
  for(int i = 0; i < 10; ++i) {
    const auto r = recordMouseUse(uses, "view.week", true, true);
    EXPECT_FALSE(r.showHint);
    EXPECT_FALSE(r.changed) << "a hinted action is not counted any more";
  }
  EXPECT_EQ(uses.value("view.week").toInt(), kMouseUsesBeforeHint);
}

TEST(ShortcutHints, CountsEachActionOnItsOwn) {
  QJsonObject uses;
  recordMouseUse(uses, "view.week", true, true);
  recordMouseUse(uses, "view.week", true, true);
  EXPECT_FALSE(recordMouseUse(uses, "view.month", true, true).showHint);
  EXPECT_TRUE(recordMouseUse(uses, "view.week", true, true).showHint);
  EXPECT_EQ(uses.value("view.month").toInt(), 1);
}

TEST(ShortcutHints, NothingCountedWithoutAKeyOrWhenOff) {
  QJsonObject uses;
  EXPECT_FALSE(recordMouseUse(uses, "task.new", false, true).changed) << "no key bound: nothing to suggest";
  EXPECT_FALSE(recordMouseUse(uses, "task.new", true, false).changed) << "hints switched off";
  EXPECT_FALSE(recordMouseUse(uses, "", true, true).changed);
  EXPECT_TRUE(uses.isEmpty());
}

TEST(ShortcutHints, SurvivesARoundTripThroughJson) {
  QJsonObject uses;
  recordMouseUse(uses, "notes.new", true, true);
  recordMouseUse(uses, "notes.new", true, true);
  QJsonObject back = QJsonDocument::fromJson(QJsonDocument(uses).toJson()).object();
  EXPECT_TRUE(recordMouseUse(back, "notes.new", true, true).showHint);
}

TEST(ShortcutHints, EnabledUnlessSwitchedOff) {
  EXPECT_TRUE(heap::hints::hintsEnabled(QJsonObject{}));
  EXPECT_TRUE(heap::hints::hintsEnabled(QJsonDocument::fromJson(R"({"shortcuts":{}})").object()));
  EXPECT_TRUE(heap::hints::hintsEnabled(QJsonDocument::fromJson(R"({"shortcuts":{"mouseHints":true}})").object()));
  EXPECT_FALSE(heap::hints::hintsEnabled(QJsonDocument::fromJson(R"({"shortcuts":{"mouseHints":false}})").object()));
}
