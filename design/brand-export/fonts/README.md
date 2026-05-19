# Fonts — heap. brand

Both font families are free, open source, and ship with weights 400 / 500 / 600 which is everything the brand needs.

## IBM Plex Sans (UI / body)
- License: OFL 1.1
- Download: https://github.com/IBM/plex/releases  (grab the `OpenType` or `TrueType` archive)
- Files needed:
  - `IBMPlexSans-Regular.ttf` (400)
  - `IBMPlexSans-Medium.ttf` (500)
  - `IBMPlexSans-SemiBold.ttf` (600)

## JetBrains Mono (mono / wordmark / code)
- License: OFL 1.1
- Download: https://www.jetbrains.com/lp/mono/  or  https://github.com/JetBrains/JetBrainsMono/releases
- Files needed:
  - `JetBrainsMono-Regular.ttf` (400)
  - `JetBrainsMono-Medium.ttf` (500)
  - `JetBrainsMono-SemiBold.ttf` (600)

## How to load them in Qt

1. Put the 6 `.ttf` files into this `fonts/` directory.
2. Uncomment the corresponding `<file>` entries in `brand.qrc`.
3. Load them on app startup (before `QQmlApplicationEngine` shows any window):

```cpp
// main.cpp — after QGuiApplication app(argc, argv);
#include <QFontDatabase>

static void loadBrandFonts() {
    const QStringList files = {
        ":/fonts/IBMPlexSans-Regular.ttf",
        ":/fonts/IBMPlexSans-Medium.ttf",
        ":/fonts/IBMPlexSans-SemiBold.ttf",
        ":/fonts/JetBrainsMono-Regular.ttf",
        ":/fonts/JetBrainsMono-Medium.ttf",
        ":/fonts/JetBrainsMono-SemiBold.ttf",
    };
    for (const auto &f : files) {
        if (QFontDatabase::addApplicationFont(f) == -1)
            qWarning() << "failed to load font" << f;
    }
}
```

After that you can use `Brand.fontSans` ("IBM Plex Sans") and `Brand.fontMono`
("JetBrains Mono") anywhere in QML and Qt will resolve them to the embedded fonts.
