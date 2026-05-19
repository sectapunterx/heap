# Product surfaces · heap.

Готовые ассеты для трёх product surface'ов из брендбука: splash screen, README banner и marketing hero. Используются на GitHub, в Qt-приложении и на лендинге.

## Файлы

| Surface           | SVG                                  | QML                              | Размер     |
| ----------------- | ------------------------------------ | -------------------------------- | ---------- |
| 06 · Splash       | `surfaces/heap-splash.svg`           | `qml/SplashScreen.qml`           | 1280 × 800 |
| 07 · README banner| `surfaces/heap-readme-banner.svg`    | —                                | 1280 × 640 |
| 08 · Marketing hero | `surfaces/heap-marketing-hero.svg` | —                                | 1440 × 900 |

Все SVG — self-contained, без `<link>` к внешним шрифтам. Если шрифт `IBM Plex Sans` / `JetBrains Mono` не установлен в системе, текст отрендерится системным fallback'ом, остальная геометрия не изменится. Для постоянного pixel-perfect рендера на GitHub лучше использовать готовый PNG (см. ниже).

## GitHub README · как вставить

```markdown
<p align="center">
  <img src="brand-export/surfaces/heap-readme-banner.svg" width="100%" alt="heap.">
</p>
```

SVG на github.com рендерится корректно почти всегда — но если хочется гарантированно одинаковый вид у всех (включая social-preview / og:image), сгенери `.png`:

```bash
# через rsvg-convert
rsvg-convert -w 1280 -h 640 brand-export/surfaces/heap-readme-banner.svg \
    -o brand-export/surfaces/heap-readme-banner.png

# или через ImageMagick (нужен установленный шрифт)
magick -density 144 brand-export/surfaces/heap-readme-banner.svg \
    -resize 1280x640 brand-export/surfaces/heap-readme-banner.png
```

И положи в repo-settings → Social preview, или в `<meta property="og:image">` на лендинге.

## Qt splash screen

`qml/SplashScreen.qml` — рабочий компонент, использует `Brand.qml` singleton и `BrandLogo.qml` (см. главный `brand-export/README.md`).

**Минимальное использование** в `main.qml`:

```qml
import QtQuick
import todocpp

Window {
    visible: true
    width: 1280; height: 800
    color: Brand.bg

    SplashScreen {
        anchors.fill: parent
        progress: appLoader.progress     // bind к своему loader'у
        status: appLoader.statusText
        autoAnimate: false               // выключи демо-анимацию
        onFinished: mainScene.start()
    }
}
```

**Frameless-окно** (отдельный сплеш до основного окна):

```qml
import QtQuick.Window

Window {
    flags: Qt.SplashScreen
    visible: true
    width: 1280; height: 800
    color: "transparent"

    SplashScreen {
        anchors.fill: parent
        autoDuration: 1500
        onFinished: { mainWindow.show(); Qt.quit() }
    }
}
```

Зарегистрируй `SplashScreen.qml` в том же `qt_add_qml_module(...)`:

```cmake
qt_add_qml_module(todocpp
    URI todocpp  VERSION 1.0
    QML_FILES
        brand-export/qml/Brand.qml
        brand-export/qml/BrandLogo.qml
        brand-export/qml/SplashScreen.qml
        # ...
)
```

## Marketing hero · для лендинга

Если делаешь отдельный сайт-визитку — `heap-marketing-hero.svg` встаёт прямо в `<img>` (1440×900). Внутри уже миниатюра приложения с kanban и сегодняшним расписанием.

Слоган в герое — **`Your day, allocated.`** Если хочется поменять только текстовые слои (заголовок, абзац, чеклист) — открой SVG в Figma / Illustrator / любом редакторе текста: всё лежит в `<text>` элементах, geometry трогать не надо.
