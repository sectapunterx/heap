#pragma once

#include <QSyntaxHighlighter>
#include <QTextCharFormat>
#include <QVariantMap>
#include <QVector>
#include <QRegularExpression>
#include <QQuickTextDocument>
#include <qqmlregistration.h>

// Inline-markdown highlighter for the Notes view: headings, bold,
// italic, inline code, lists, quotes, strike-through and the
// @mention / #TICKET-id tokens. Colors come from QML via the
// `palette` property so the panel matches the active Theme.
class NotesHighlighter : public QSyntaxHighlighter {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QQuickTextDocument* target READ target WRITE setTarget NOTIFY targetChanged)
    Q_PROPERTY(QVariantMap palette READ palette WRITE setPalette NOTIFY paletteChanged)

public:
    explicit NotesHighlighter(QObject *parent = nullptr);

    QQuickTextDocument* target() const { return m_target; }
    void setTarget(QQuickTextDocument *t);

    QVariantMap palette() const { return m_palette; }
    void        setPalette(const QVariantMap &p);

signals:
    void targetChanged();
    void paletteChanged();

protected:
    void highlightBlock(const QString &text) override;

private:
    enum BlockState {
        BS_Normal     = 0,
        BS_FencedCode = 1,
        BS_LatexBlock = 2,
    };

    struct Rule {
        QRegularExpression pattern;
        QTextCharFormat    format;
        int                captureGroup = 0;
    };

    QQuickTextDocument *m_target = nullptr;
    QVariantMap         m_palette;
    QVector<Rule>       m_rules;
    QTextCharFormat     m_codeBlockFmt;
    QTextCharFormat     m_latexFmt;

    void rebuildRules();
    QTextCharFormat fmt(const char *key, bool bold = false, bool italic = false) const;
};
