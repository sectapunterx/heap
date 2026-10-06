#include "platform/BundledFonts.h"

#include <QDebug>
#include <QDir>
#include <QFont>
#include <QFontDatabase>
#include <QFontInfo>
#include <QGuiApplication>
#include <QString>

namespace heap::platform {

namespace {

struct BundledFamily {
  const char* family;
  QList<int> weights;
};

QList<BundledFamily> bundledFamilies() {
  return {
      {kUiFontFamily, {QFont::Normal, QFont::Medium, QFont::DemiBold}},
      {kMonoFontFamily, {QFont::Normal, QFont::Medium}},
  };
}

}  // namespace

int registerBundledFonts() {
  int failed = 0;
  const QDir dir(QStringLiteral(":/fonts"));
  const QStringList files = dir.entryList({QStringLiteral("*.ttf")}, QDir::Files, QDir::Name);
  if(files.isEmpty()) {
    qWarning("fonts: no bundled fonts under :/fonts");
    return 1;
  }
  for(const QString& file : files) {
    if(QFontDatabase::addApplicationFont(dir.filePath(file)) < 0) {
      qWarning("fonts: could not register bundled font %s", qUtf8Printable(file));
      ++failed;
    }
  }
  return failed;
}

void useBundledUiFontByDefault() {
  const QString family = QString::fromLatin1(kUiFontFamily);
  if(!QFontDatabase::families().contains(family)) {
    return;
  }
  QFont font = QGuiApplication::font();
  font.setFamilies({family});
  QGuiApplication::setFont(font);
}

QStringList missingBundledFonts() {
  QStringList missing;
  const QStringList families = QFontDatabase::families();
  for(const BundledFamily& bundled : bundledFamilies()) {
    const QString family = QString::fromLatin1(bundled.family);
    if(!families.contains(family)) {
      missing << family;
      continue;
    }
    for(const int weight : bundled.weights) {
      QFont font(family);
      font.setWeight(static_cast<QFont::Weight>(weight));
      const QFontInfo info(font);
      if(info.family() != family || info.weight() != weight) {
        missing << family + QLatin1Char(' ') + QString::number(weight);
      }
    }
  }
  return missing;
}

}  // namespace heap::platform
