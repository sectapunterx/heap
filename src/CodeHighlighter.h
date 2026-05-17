#pragma once

#include <QSyntaxHighlighter>
#include <QTextCharFormat>
#include <QVariantMap>
#include <QVector>
#include <QRegularExpression>
#include <QQuickTextDocument>
#include <qqmlregistration.h>

class CodeHighlighter : public QSyntaxHighlighter {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QQuickTextDocument* target READ target WRITE setTarget NOTIFY targetChanged)
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY languageChanged)
    Q_PROPERTY(QVariantMap palette READ palette WRITE setPalette NOTIFY paletteChanged)

public:
    explicit CodeHighlighter(QObject *parent = nullptr);

    QQuickTextDocument* target() const { return m_target; }
    void setTarget(QQuickTextDocument *t);

    QString language() const { return m_language; }
    void    setLanguage(const QString &lang);

    QVariantMap palette() const { return m_palette; }
    void        setPalette(const QVariantMap &p);

signals:
    void targetChanged();
    void languageChanged();
    void paletteChanged();

protected:
    void highlightBlock(const QString &text) override;

private:
    struct Rule {
        QRegularExpression pattern;
        QTextCharFormat    format;
        int                captureGroup = 0;
    };

    QQuickTextDocument *m_target = nullptr;
    QString             m_language = "text";
    QVariantMap         m_palette;
    QVector<Rule>       m_comments;
    QVector<Rule>       m_strings;
    QVector<Rule>       m_others;

    void rebuildRules();
    QTextCharFormat fmt(const char *key, bool bold = false, bool italic = false) const;
    static void appendKeywordRule(QVector<Rule> &out, const QStringList &words, const QTextCharFormat &f);
};
