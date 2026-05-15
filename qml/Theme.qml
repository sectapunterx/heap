pragma Singleton
import QtQuick
import TodoCpp

QtObject {
    readonly property bool dark: AppController.theme === "dark"
    readonly property bool compact: AppController.density === "compact"

    readonly property color bg:           dark ? "#0b0e13" : "#f4f6f9"
    readonly property color bg2:          dark ? "#0f131a" : "#ebeef3"
    readonly property color panel:        dark ? "#14181f" : "#ffffff"
    readonly property color panel2:       dark ? "#181d26" : "#f7f8fa"
    readonly property color panel3:       dark ? "#1d232d" : "#eef1f5"
    readonly property color border:       dark ? "#262d39" : "#dde2ea"
    readonly property color borderStrong: dark ? "#323a48" : "#c4ccd8"
    readonly property color text:         dark ? "#e5ecf3" : "#1a1f29"
    readonly property color textMuted:    dark ? "#8a94a3" : "#5a6371"
    readonly property color textDim:      dark ? "#5f6878" : "#8893a3"

    readonly property color accent:       dark ? "#5cc2dd" : "#1f7aa6"
    readonly property color accentStrong: dark ? "#8ad7ec" : "#155a80"
    readonly property color accentSoft:   dark ? Qt.rgba(0.36, 0.76, 0.87, 0.15) : Qt.rgba(0.12, 0.48, 0.65, 0.12)

    readonly property color p0: dark ? "#e6624c" : "#c34a36"
    readonly property color p1: dark ? "#e6984c" : "#bd7530"
    readonly property color p2: dark ? "#d8c277" : "#9a8237"
    readonly property color p3: dark ? "#7d9bc7" : "#496a91"

    readonly property color stBacklog: dark ? "#8a8e98" : "#7a808c"
    readonly property color stTodo:    dark ? "#9aa3b4" : "#5a6371"
    readonly property color stProg:    dark ? "#5aa9e6" : "#1f6fb0"
    readonly property color stHalf:    dark ? "#dcb86b" : "#9a7a2b"
    readonly property color stBlocked: dark ? "#e6624c" : "#c34a36"
    readonly property color stReview:  dark ? "#c07acf" : "#7a3e91"
    readonly property color stDone:    dark ? "#6ec18a" : "#3e8a5d"

    readonly property color mStandup: dark ? "#5aa3e6" : "#1f6fb0"
    readonly property color mOneone:  dark ? "#c07acf" : "#7a3e91"
    readonly property color mSync:    dark ? "#6cc4b8" : "#317e74"
    readonly property color mFocus:   dark ? "#7cc492" : "#3e8a5d"

    // Geometry tokens
    readonly property int rowH:   compact ? 32 : 44
    readonly property int pad:    compact ? 8  : 14
    readonly property int gap:    compact ? 8  : 12
    readonly property int radius: 10
    readonly property int hourH:  compact ? 44 : 56

    readonly property string fontUi:   "IBM Plex Sans, Inter, Segoe UI, Noto Sans, sans-serif"
    readonly property string fontMono: "JetBrains Mono, Fira Code, DejaVu Sans Mono, monospace"

    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a); }

    function statusColor(id) {
        switch (id) {
            case "backlog": return stBacklog;
            case "todo":    return stTodo;
            case "prog":    return stProg;
            case "half":    return stHalf;
            case "blocked": return stBlocked;
            case "review":  return stReview;
            case "done":    return stDone;
        }
        return textMuted;
    }
    function priorityColor(p) {
        switch (p) { case "P0": return p0; case "P1": return p1; case "P2": return p2; case "P3": return p3; }
        return textMuted;
    }
    function eventColor(type) {
        switch (type) {
            case "standup": return mStandup;
            case "oneone":  return mOneone;
            case "sync":    return mSync;
            case "focus":   return mFocus;
        }
        return accent;
    }
}
