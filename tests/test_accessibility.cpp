// A new profile's motion and contrast defaults follow the system (design audit
// DES-23): heap's own "Reduce motion" and "High contrast" started off whatever
// the user had asked the OS for.

#include "platform/Accessibility.h"

#include <QJsonDocument>
#include <QJsonObject>

#include <gtest/gtest.h>

namespace {

QJsonObject appearanceOf(const QString& json) {
  return QJsonDocument::fromJson(json.toUtf8()).object().value(QStringLiteral("appearance")).toObject();
}

}  // namespace

TEST(FirstRunAppearance, DefaultsToSoftContrastWithMotion) {
  const QJsonObject a = appearanceOf(heap::platform::firstRunAppearanceJson({}));
  EXPECT_EQ(a.value(QStringLiteral("darkPreset")).toString(), QStringLiteral("minimal-dark"));
  EXPECT_EQ(a.value(QStringLiteral("lightPreset")).toString(), QStringLiteral("heap-light"));
  EXPECT_EQ(a.value(QStringLiteral("contrast")).toString(), QStringLiteral("soft"));
  EXPECT_FALSE(a.contains(QStringLiteral("reducedMotion")));
  EXPECT_FALSE(a.contains(QStringLiteral("highContrast")));
}

TEST(FirstRunAppearance, FollowsTheSystemsHighContrastAndReducedMotion) {
  heap::platform::AccessibilityPrefs prefs;
  prefs.reduce_motion = true;
  prefs.high_contrast = true;
  const QJsonObject a = appearanceOf(heap::platform::firstRunAppearanceJson(prefs));
  EXPECT_EQ(a.value(QStringLiteral("contrast")).toString(), QStringLiteral("high"));
  EXPECT_TRUE(a.value(QStringLiteral("highContrast")).toBool());
  EXPECT_TRUE(a.value(QStringLiteral("reducedMotion")).toBool());
}

TEST(FirstRunAppearance, ReadingTheSystemDoesNotThrow) {
  // Whatever the machine says; the call itself must be safe everywhere.
  const heap::platform::AccessibilityPrefs prefs = heap::platform::systemAccessibilityPrefs();
  (void)prefs;
  SUCCEED();
}
