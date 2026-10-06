// A new profile's motion and contrast defaults follow the system (design audit
// DES-23): heap's own "Reduce motion" and "High contrast" started off whatever
// the user had asked the OS for.

#include "platform/Accessibility.h"
#include "views/UiScale.h"

#include <QJsonDocument>
#include <QJsonObject>

#include <gtest/gtest.h>

#include <cmath>

namespace {

QJsonObject appearanceOf(const QString& json) {
  return QJsonDocument::fromJson(json.toUtf8()).object().value(QStringLiteral("appearance")).toObject();
}

}  // namespace

TEST(FirstRunAppearance, DefaultsToSoftContrastWithMotion) {
  const QJsonObject a = appearanceOf(heap::platform::firstRunAppearanceJson({}));
  EXPECT_EQ(a.value(QStringLiteral("darkPreset")).toString(), QStringLiteral("heap-ink"));
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

// The system's text size starts heap's interface scale (APP-183).
TEST(SystemTextScale, ParsesFactorsAndPercentages) {
  using heap::platform::parseTextScale;
  EXPECT_DOUBLE_EQ(parseTextScale(QStringLiteral("1.5")), 1.5);
  EXPECT_DOUBLE_EQ(parseTextScale(QStringLiteral("150")), 1.5);
  EXPECT_DOUBLE_EQ(parseTextScale(QStringLiteral(" 125% ")), 1.25);
  EXPECT_DOUBLE_EQ(parseTextScale(QStringLiteral("2")), 2.0);
  // gsettings prints the double with a newline.
  EXPECT_DOUBLE_EQ(parseTextScale(QStringLiteral("1.25\n")), 1.25);
  EXPECT_DOUBLE_EQ(parseTextScale(QString()), 0);
  EXPECT_DOUBLE_EQ(parseTextScale(QStringLiteral("big")), 0);
  EXPECT_DOUBLE_EQ(parseTextScale(QStringLiteral("-1.5")), 0);
}

TEST(SystemTextScale, MapsToTheNearestInterfaceStep) {
  using heap::ui::uiScaleForTextScale;
  const QList<double> steps{0.9, 1, 1.1, 1.25, 1.5};
  EXPECT_DOUBLE_EQ(uiScaleForTextScale(1.0, steps), 1.0);
  EXPECT_DOUBLE_EQ(uiScaleForTextScale(1.1, steps), 1.1);
  EXPECT_DOUBLE_EQ(uiScaleForTextScale(1.2, steps), 1.25);
  EXPECT_DOUBLE_EQ(uiScaleForTextScale(1.25, steps), 1.25);
  EXPECT_DOUBLE_EQ(uiScaleForTextScale(1.4, steps), 1.5);
  EXPECT_DOUBLE_EQ(uiScaleForTextScale(1.5, steps), 1.5);
  // Windows goes to 225 %; heap's top step is as far as it goes.
  EXPECT_DOUBLE_EQ(uiScaleForTextScale(2.25, steps), 1.5);
  // Never smaller than 100 %, and nothing unreadable moves it.
  EXPECT_DOUBLE_EQ(uiScaleForTextScale(0.8, steps), 1.0);
  EXPECT_DOUBLE_EQ(uiScaleForTextScale(std::nan(""), steps), 1.0);
  EXPECT_DOUBLE_EQ(uiScaleForTextScale(1.5, {}), 1.0);
  // A tie goes up; unsorted steps are fine.
  EXPECT_DOUBLE_EQ(uiScaleForTextScale(1.375, {1.5, 1, 1.25}), 1.5);
}

TEST(SystemTextScale, ReadingTheSystemIsAtLeastOne) {
  EXPECT_GE(heap::platform::systemTextScale(), 1.0);
}
