#include "NotesHighlighter.h"

#include <QQuickTextDocument>
#include <QTextDocument>
#include <QColor>

NotesHighlighter::NotesHighlighter(QObject *parent)
    : QSyntaxHighlighter(parent)
{
    rebuildRules();
}

void NotesHighlighter::setTarget(QQuickTextDocument *t) {
    if (m_target == t) return;
    m_target = t;
    setDocument(t ? t->textDocument() : nullptr);
    emit targetChanged();
    if (document()) rehighlight();
}

void NotesHighlighter::setPalette(const QVariantMap &p) {
    if (m_palette == p) return;
    m_palette = p;
    emit paletteChanged();
    rebuildRules();
    if (document()) rehighlight();
}

QTextCharFormat NotesHighlighter::fmt(const char *key, bool bold, bool italic) const {
    QTextCharFormat f;
    const QVariant v = m_palette.value(QString::fromLatin1(key));
    QColor c = v.value<QColor>();
    if (!c.isValid()) {
        // Sensible dark-mode fallbacks.
        const QByteArray k(key);
        if (k == "heading")     c = QColor("#8ad7ec");
        else if (k == "bold")   c = QColor("#e5ecf3");
        else if (k == "italic") c = QColor("#e5ecf3");
        else if (k == "code")   c = QColor("#d8c277");
        else if (k == "quote")  c = QColor("#8a94a3");
        else if (k == "mention")c = QColor("#5aa3e6");
        else if (k == "ticket") c = QColor("#d8c277");
        else if (k == "link")   c = QColor("#5cc2dd");
        else if (k == "list")   c = QColor("#8a94a3");
        else                    c = QColor("#e5ecf3");
    }
    f.setForeground(c);
    if (bold)   f.setFontWeight(QFont::DemiBold);
    if (italic) f.setFontItalic(true);
    return f;
}

void NotesHighlighter::rebuildRules() {
    m_rules.clear();

    // --- Headings: # / ## / ### ---
    {
        Rule r;
        r.pattern = QRegularExpression(QStringLiteral("^#{1,3}\\s.+$"));
        r.format = fmt("heading", true);
        m_rules.push_back(r);
    }

    // --- List markers (the dash, not the whole line) ---
    {
        Rule r;
        r.pattern = QRegularExpression(QStringLiteral("^\\s*([-*+])\\s"));
        r.format = fmt("list", true);
        r.captureGroup = 1;
        m_rules.push_back(r);
    }

    // --- Quote block ">" ---
    {
        Rule r;
        r.pattern = QRegularExpression(QStringLiteral("^>\\s.*$"));
        r.format = fmt("quote", false, true);
        m_rules.push_back(r);
    }

    // --- Markdown link [text](url) — color the whole match ---
    {
        Rule r;
        r.pattern = QRegularExpression(QStringLiteral("\\[[^\\]\\n]+\\]\\([^)\\n]+\\)"));
        QTextCharFormat f = fmt("link");
        f.setFontUnderline(true);
        r.format = f;
        m_rules.push_back(r);
    }

    // --- Strike-through ~~text~~ ---
    {
        Rule r;
        r.pattern = QRegularExpression(QStringLiteral("~~[^~\\n]+~~"));
        QTextCharFormat f = fmt("quote");
        f.setFontStrikeOut(true);
        r.format = f;
        m_rules.push_back(r);
    }

    // --- Bold **text** ---
    {
        Rule r;
        r.pattern = QRegularExpression(QStringLiteral("\\*\\*[^*\\n]+\\*\\*"));
        r.format = fmt("bold", true);
        m_rules.push_back(r);
    }

    // --- Italic *text* (avoid eating the inside of **bold**) ---
    {
        Rule r;
        r.pattern = QRegularExpression(QStringLiteral("(?<![*\\w])\\*(?!\\s)[^*\\n]+\\*(?!\\w)"));
        r.format = fmt("italic", false, true);
        m_rules.push_back(r);
    }

    // --- Inline code `code` ---
    {
        Rule r;
        r.pattern = QRegularExpression(QStringLiteral("`[^`\\n]+`"));
        QTextCharFormat f = fmt("code");
        f.setFontFamilies({ QStringLiteral("JetBrains Mono"),
                            QStringLiteral("Fira Code"),
                            QStringLiteral("DejaVu Sans Mono") });
        // Subtle background — derived from "codeBg" if present, otherwise leave bare.
        const QVariant bgv = m_palette.value(QStringLiteral("codeBg"));
        QColor bg = bgv.value<QColor>();
        if (bg.isValid()) f.setBackground(bg);
        r.format = f;
        m_rules.push_back(r);
    }

    // --- @mention ---
    {
        Rule r;
        r.pattern = QRegularExpression(QStringLiteral("(?<![A-Za-z0-9_])@[A-Za-z0-9_.\\-]+"));
        r.format = fmt("mention", true);
        m_rules.push_back(r);
    }

    // --- #TICKET-id (e.g. LTE-2401) ---
    {
        Rule r;
        r.pattern = QRegularExpression(QStringLiteral("(?<![A-Za-z0-9_])#[A-Z][A-Z0-9]*-\\d+"));
        r.format = fmt("ticket", true);
        m_rules.push_back(r);
    }
}

void NotesHighlighter::highlightBlock(const QString &text) {
    for (const Rule &r : m_rules) {
        auto it = r.pattern.globalMatch(text);
        while (it.hasNext()) {
            const auto m = it.next();
            const int start = m.capturedStart(r.captureGroup);
            const int len   = m.capturedLength(r.captureGroup);
            if (len > 0) setFormat(start, len, r.format);
        }
    }
}
