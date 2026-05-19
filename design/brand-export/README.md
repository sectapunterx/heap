# heap. — brand export for Qt 6 / QML

Этот пакет переносит брендбук **heap.** в твой проект `sectapunterx/todolist` (Qt 6 + QML + CMake).

## Что внутри

```
brand-export/
├─ logo/
│  ├─ heap-mark.svg          ← мини-логотип (heap-дерево), тёмный фон
│  ├─ heap-mark-light.svg    ← тот же, для светлого фона
│  ├─ heap-mark-mono.svg     ← одноцветный (использует currentColor)
│  ├─ heap-lockup.svg        ← горизонтальный lockup: mark + "heap."
│  ├─ heap-lockup-light.svg
│  └─ heap-wordmark.svg      ← только "heap." словесный знак
├─ icon/
│  └─ heap-icon.svg          ← мастер 1024×1024 со squircle, для иконки приложения
├─ qml/
│  ├─ Brand.qml              ← singleton: цвета, шрифты, токены, пути к ассетам
│  └─ BrandLogo.qml          ← компонент <BrandLogo variant="lockup" />
├─ fonts/
│  └─ README.md              ← где скачать IBM Plex Sans + JetBrains Mono
├─ brand.qrc                 ← готовый .qrc на все ассеты
└─ README.md                 ← этот файл
```

## Шаги интеграции

### 1 · Скопировать в репозиторий

Скопируй папку `brand-export/` в корень репо. Структуру дальше можно держать как есть либо разнести по `src/`, `qml/`, `assets/` — `brand.qrc` ниже подстроим по факту.

### 2 · Подключить .qrc в CMake

В `CMakeLists.txt` добавь `brand-export/brand.qrc` к ресурсам исполняемого таргета:

```cmake
qt_add_executable(todocpp
    src/main.cpp
    src/AppController.cpp
    # ...
)

# ── Brand assets ──
qt_add_resources(todocpp "brand"
    PREFIX "/"
    BASE "brand-export"
    FILES
        brand-export/logo/heap-mark.svg
        brand-export/logo/heap-mark-light.svg
        brand-export/logo/heap-mark-mono.svg
        brand-export/logo/heap-lockup.svg
        brand-export/logo/heap-lockup-light.svg
        brand-export/logo/heap-wordmark.svg
        brand-export/icon/heap-icon.svg
)
```

(вариант со старым стилем — просто добавь `brand-export/brand.qrc` в список исходников через `qt6_add_resources`).

После сборки ассеты будут доступны по `qrc:/brand/logo/heap-mark.svg` и т. д. — пути уже зашиты в `Brand.qml`.

### 3 · Зарегистрировать `Brand` как QML singleton

В `qt_add_qml_module(...)` у тебя уже идёт `Theme.qml` — добавь рядом `Brand.qml` и `BrandLogo.qml`:

```cmake
qt_add_qml_module(todocpp
    URI todocpp
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/Theme.qml
        qml/TopBar.qml
        # ...
        brand-export/qml/Brand.qml
        brand-export/qml/BrandLogo.qml
)
```

И добавь в `Brand.qml` пометку singleton (она уже там: `pragma Singleton` в первой строке).
Тогда в любом `.qml`:

```qml
import todocpp

Rectangle {
    color: Brand.bg
    Text {
        text: Brand.tagline           // "heap.push(task)"
        color: Brand.accent
        font.family: Brand.fontMono
        font.pixelSize: Brand.sizeBody
    }
}
```

### 4 · Шрифты

См. `fonts/README.md` — нужно положить 6 `.ttf` (IBM Plex Sans 400/500/600 + JetBrains Mono 400/500/600), раскомментить блок шрифтов в `brand.qrc` и вызвать `QFontDatabase::addApplicationFont` в `main.cpp` до старта движка QML.

### 5 · Иконка приложения

Из `icon/heap-icon.svg` нужно сгенерить платформенные форматы. Самый простой путь:

**Linux / любой:** оставь `.svg` — Qt и большинство DE его понимают:
```cpp
// main.cpp
app.setWindowIcon(QIcon(":/brand/icon/heap-icon.svg"));
```

**Windows (.ico):**
```bash
# через ImageMagick
magick brand-export/icon/heap-icon.svg -define icon:auto-resize=256,128,64,48,32,16 heap.ico
```
Положи `heap.ico` рядом с `.rc` и пропиши:
```rc
IDI_ICON1 ICON "heap.ico"
```
И добавь `.rc` в исходники CMake.

**macOS (.icns):**
```bash
# 1) экспортнуть SVG в PNG 1024×1024 (Inkscape / rsvg-convert)
rsvg-convert -w 1024 -h 1024 brand-export/icon/heap-icon.svg -o heap-1024.png
# 2) собрать .icns
mkdir heap.iconset
sips -z 16 16     heap-1024.png --out heap.iconset/icon_16x16.png
sips -z 32 32     heap-1024.png --out heap.iconset/icon_16x16@2x.png
sips -z 32 32     heap-1024.png --out heap.iconset/icon_32x32.png
sips -z 64 64     heap-1024.png --out heap.iconset/icon_32x32@2x.png
sips -z 128 128   heap-1024.png --out heap.iconset/icon_128x128.png
sips -z 256 256   heap-1024.png --out heap.iconset/icon_128x128@2x.png
sips -z 256 256   heap-1024.png --out heap.iconset/icon_256x256.png
sips -z 512 512   heap-1024.png --out heap.iconset/icon_256x256@2x.png
sips -z 512 512   heap-1024.png --out heap.iconset/icon_512x512.png
cp heap-1024.png  heap.iconset/icon_512x512@2x.png
iconutil -c icns heap.iconset
```

### 6 · Заменить старый брендинг в QML

В `qml/TopBar.qml` сейчас, скорее всего, нарисован текстовый `todo·cpp`. Замени на компонент логотипа:

```qml
import todocpp

Item {
    // было:
    // Text { text: "todo·cpp"; font.family: Theme.fontMono; ... }

    // стало:
    BrandLogo {
        variant: "lockup"          // или "mark" если мало места
        height: 28
        anchors.verticalCenter: parent.verticalCenter
    }
}
```

### 7 · Перенести цвета в `Theme.qml` (опционально)

Если хочешь, чтобы старый `Theme.qml` был источником истины — пусть он импортирует из `Brand`:

```qml
// Theme.qml
pragma Singleton
import QtQuick
import todocpp

QtObject {
    property color accent:   Brand.accent
    property color bg:       Brand.bg
    property color panel:    Brand.panel
    property color text:     Brand.text
    property string fontUi:  Brand.fontSans
    property string fontMon: Brand.fontMono
    // ...а dark/light/density-логику оставляешь как была
}
```

Тогда весь существующий код продолжит работать через `Theme.*`, а изменение в `Brand.qml` пробросится автоматически.

## Палитра (на всякий — без QML)

| token     | hex       | роль                       |
| --------- | --------- | -------------------------- |
| `bg`      | `#0b0e13` | app background             |
| `bg2`     | `#11151c` | secondary surface          |
| `panel`   | `#14181f` | cards / panels             |
| `panel2`  | `#1a1f29` | nested cards               |
| `border`  | `#262d39` | dividers, hairlines        |
| `text`    | `#e5ecf3` | primary text               |
| `text2`   | `#b8c2cc` | secondary text             |
| `text3`   | `#8a94a3` | muted / labels             |
| `text4`   | `#5f6878` | very muted / meta          |
| `accent`  | `#3bccdd` | brand cyan (`heap.` dot)   |
| `accent2` | `#5fdaea` | hover / highlight          |

Семантические:

| status      | hex       |
| ----------- | --------- |
| todo        | `#86a0bd` |
| in-progress | `#32b2e7` |
| review      | `#bf94ec` |
| done        | `#78be7a` |
| warn        | `#fe9c3a` |

## Слоган

> **`heap.push(task)`**

Используется в брендбуке как mono-tagline (см. артборд 01 · Identity и 06 · Splash).
