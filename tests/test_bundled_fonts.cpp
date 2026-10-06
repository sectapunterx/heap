// The fonts heap ships inside the binary (platform/BundledFonts, qrc :/fonts):
// every face registers, the families come back under their plain names, and
// each weight the UI asks for (Golos Text 400/500/600, JetBrains Mono 400/500)
// resolves to that face rather than a synthesised or system one. Static faces
// with legacy naming are what makes this hold on every font backend — a
// variable font or "Golos Text Medium" as its own family would fail here.

#include "platform/BundledFonts.h"

#include <QDir>
#include <QFont>
#include <QFontDatabase>
#include <QFontInfo>
#include <QGuiApplication>
#include <QRawFont>

#include <gtest/gtest.h>

using heap::platform::kMonoFontFamily;
using heap::platform::kUiFontFamily;

namespace {

QString ui() {
  return QString::fromLatin1(kUiFontFamily);
}

QString mono() {
  return QString::fromLatin1(kMonoFontFamily);
}

// What registerBundledFonts() returned in main(), before any test ran.
int g_failedFaces = -1;

}  // namespace

TEST(BundledFonts, AllFacesAreCompiledIn) {
  const QStringList files = QDir(QStringLiteral(":/fonts")).entryList({QStringLiteral("*.ttf")}, QDir::Files, QDir::Name);
  EXPECT_EQ(files,
            QStringList({QStringLiteral("GolosText-Medium.ttf"),
                         QStringLiteral("GolosText-Regular.ttf"),
                         QStringLiteral("GolosText-SemiBold.ttf"),
                         QStringLiteral("JetBrainsMono-Medium.ttf"),
                         QStringLiteral("JetBrainsMono-Regular.ttf")}));
}

TEST(BundledFonts, EveryFaceRegisters) {
  EXPECT_EQ(g_failedFaces, 0);
}

TEST(BundledFonts, FamiliesAreRegistered) {
  const QStringList families = QFontDatabase::families();
  EXPECT_TRUE(families.contains(ui())) << qPrintable(families.join(QStringLiteral(", ")));
  EXPECT_TRUE(families.contains(mono()));
  // One family per font: a weight never shows up as a family of its own.
  EXPECT_FALSE(families.contains(QStringLiteral("Golos Text Medium")));
  EXPECT_FALSE(families.contains(QStringLiteral("Golos Text SemiBold")));
  EXPECT_FALSE(families.contains(QStringLiteral("JetBrains Mono Medium")));
}

TEST(BundledFonts, StylesAreTheShippedWeights) {
  const QStringList uiStyles = QFontDatabase::styles(ui());
  EXPECT_TRUE(uiStyles.contains(QStringLiteral("Regular"))) << qPrintable(uiStyles.join(QStringLiteral(", ")));
  EXPECT_TRUE(uiStyles.contains(QStringLiteral("Medium")));
  EXPECT_TRUE(uiStyles.contains(QStringLiteral("SemiBold")));
  const QStringList monoStyles = QFontDatabase::styles(mono());
  EXPECT_TRUE(monoStyles.contains(QStringLiteral("Regular"))) << qPrintable(monoStyles.join(QStringLiteral(", ")));
  EXPECT_TRUE(monoStyles.contains(QStringLiteral("Medium")));
  EXPECT_TRUE(QFontDatabase::isFixedPitch(mono()));
}

TEST(BundledFonts, EachWeightResolvesToItsFace) {
  const QList<QPair<QString, QFont::Weight>> wanted = {
      {ui(), QFont::Normal},
      {ui(), QFont::Medium},
      {ui(), QFont::DemiBold},
      {mono(), QFont::Normal},
      {mono(), QFont::Medium},
  };
  for(const auto& [family, weight] : wanted) {
    QFont font(family);
    font.setWeight(weight);
    const QFontInfo info(font);
    EXPECT_EQ(info.family(), family) << weight;
    EXPECT_EQ(info.weight(), weight) << qPrintable(family);
  }
  EXPECT_TRUE(heap::platform::missingBundledFonts().isEmpty())
      << qPrintable(heap::platform::missingBundledFonts().join(QStringLiteral(", ")));
}

TEST(BundledFonts, CoverCyrillic) {
  // The interface is Russian as well as English.
  for(const QString& family : {ui(), mono()}) {
    const QRawFont raw = QRawFont::fromFont(QFont(family));
    ASSERT_TRUE(raw.isValid()) << qPrintable(family);
    EXPECT_TRUE(raw.supportsCharacter(QChar(0x0416))) << qPrintable(family);  // Ж
    EXPECT_TRUE(raw.supportsCharacter(QChar(0x0451))) << qPrintable(family);  // ё
  }
}

int main(int argc, char** argv) {
  qputenv("QT_QPA_PLATFORM", "offscreen");
  const QGuiApplication app(argc, argv);
  g_failedFaces = heap::platform::registerBundledFonts();
  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
