#include "platform/Accessibility.h"

#include <QJsonDocument>
#include <QJsonObject>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

namespace heap::platform {

AccessibilityPrefs systemAccessibilityPrefs() {
  AccessibilityPrefs prefs;
#ifdef Q_OS_WIN
  BOOL animations = TRUE;
  if(SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &animations, 0) != FALSE) {
    prefs.reduce_motion = animations == FALSE;
  }
  HIGHCONTRASTW hc{};
  hc.cbSize = sizeof(hc);
  if(SystemParametersInfoW(SPI_GETHIGHCONTRAST, hc.cbSize, &hc, 0) != FALSE) {
    prefs.high_contrast = (hc.dwFlags & HCF_HIGHCONTRASTON) != 0;
  }
#endif
  return prefs;
}

QString firstRunAppearanceJson(const AccessibilityPrefs& prefs) {
  QJsonObject appearance{
      {QStringLiteral("darkPreset"), QStringLiteral("heap-ink")},
      {QStringLiteral("lightPreset"), QStringLiteral("heap-light")},
      {QStringLiteral("contrast"), prefs.high_contrast ? QStringLiteral("high") : QStringLiteral("soft")},
  };
  if(prefs.high_contrast) {
    appearance.insert(QStringLiteral("highContrast"), true);
  }
  if(prefs.reduce_motion) {
    appearance.insert(QStringLiteral("reducedMotion"), true);
  }
  return QString::fromUtf8(QJsonDocument(QJsonObject{{QStringLiteral("appearance"), appearance}}).toJson(QJsonDocument::Compact));
}

}  // namespace heap::platform
