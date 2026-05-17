#include "CodeHighlighter.h"

#include <QQuickTextDocument>
#include <QTextDocument>
#include <QColor>

CodeHighlighter::CodeHighlighter(QObject *parent)
    : QSyntaxHighlighter(parent)
{
    rebuildRules();
}

void CodeHighlighter::setTarget(QQuickTextDocument *t) {
    if (m_target == t) return;
    m_target = t;
    setDocument(t ? t->textDocument() : nullptr);
    emit targetChanged();
    if (document()) rehighlight();
}

void CodeHighlighter::setLanguage(const QString &lang) {
    if (m_language == lang) return;
    m_language = lang;
    emit languageChanged();
    rebuildRules();
    if (document()) rehighlight();
}

void CodeHighlighter::setPalette(const QVariantMap &p) {
    if (m_palette == p) return;
    m_palette = p;
    emit paletteChanged();
    rebuildRules();
    if (document()) rehighlight();
}

QTextCharFormat CodeHighlighter::fmt(const char *key, bool bold, bool italic) const {
    QTextCharFormat f;
    const QVariant v = m_palette.value(QString::fromLatin1(key));
    QColor c = v.value<QColor>();
    if (!c.isValid()) {
        // Sensible dark-mode fallbacks if palette isn't supplied yet.
        if (QByteArray(key) == "keyword") c = QColor("#5cc2dd");
        else if (QByteArray(key) == "string") c = QColor("#d8c277");
        else if (QByteArray(key) == "comment") c = QColor("#5f6878");
        else if (QByteArray(key) == "number") c = QColor("#7cc492");
        else if (QByteArray(key) == "type") c = QColor("#6cc4b8");
        else if (QByteArray(key) == "builtin") c = QColor("#c07acf");
        else c = QColor("#e5ecf3");
    }
    f.setForeground(c);
    if (bold) f.setFontWeight(QFont::DemiBold);
    if (italic) f.setFontItalic(true);
    return f;
}

void CodeHighlighter::appendKeywordRule(QVector<Rule> &out, const QStringList &words, const QTextCharFormat &f) {
    if (words.isEmpty()) return;
    QString p = QStringLiteral("\\b(?:");
    for (int i = 0; i < words.size(); ++i) {
        if (i) p += '|';
        p += QRegularExpression::escape(words.at(i));
    }
    p += QStringLiteral(")\\b");
    Rule r;
    r.pattern = QRegularExpression(p);
    r.format = f;
    out.push_back(r);
}

void CodeHighlighter::rebuildRules() {
    m_comments.clear();
    m_strings.clear();
    m_others.clear();

    const QTextCharFormat fComment = fmt("comment", false, true);
    const QTextCharFormat fString  = fmt("string");
    const QTextCharFormat fKeyword = fmt("keyword", true);
    const QTextCharFormat fNumber  = fmt("number");
    const QTextCharFormat fType    = fmt("type", true);
    const QTextCharFormat fBuiltin = fmt("builtin");

    Rule numRule;
    numRule.pattern = QRegularExpression(QStringLiteral("\\b\\d+(?:\\.\\d+)?\\b"));
    numRule.format = fNumber;

    if (m_language == "sh" || m_language == "bash") {
        Rule c; c.pattern = QRegularExpression("#[^\n]*"); c.format = fComment;
        m_comments.push_back(c);

        Rule s1; s1.pattern = QRegularExpression("\"[^\"\\n]*\""); s1.format = fString;
        Rule s2; s2.pattern = QRegularExpression("'[^'\\n]*'");     s2.format = fString;
        m_strings.push_back(s1);
        m_strings.push_back(s2);

        appendKeywordRule(m_others, {
            "if","then","else","elif","fi","case","esac","for","in","while","do","done",
            "function","return","break","continue","exit","local","export","readonly",
            "unset","set","shift","source","trap","echo","printf","read","cd","pushd","popd"
        }, fKeyword);
        appendKeywordRule(m_others, {
            "bazel","cmake","make","gdb","tcpdump","pgrep","perf","valgrind","sudo",
            "git","grep","awk","sed","cat","ls","mkdir","rm","mv","cp","ssh","scp",
            "curl","wget","docker","kubectl","systemctl","journalctl"
        }, fBuiltin);

        Rule var; var.pattern = QRegularExpression("\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?"); var.format = fType;
        m_others.push_back(var);
        m_others.push_back(numRule);
    }
    else if (m_language == "cpp" || m_language == "c" || m_language == "h" || m_language == "hpp") {
        Rule lc; lc.pattern = QRegularExpression("//[^\n]*"); lc.format = fComment;
        Rule bc; bc.pattern = QRegularExpression("/\\*.*?\\*/"); bc.format = fComment;
        bc.pattern.setPatternOptions(QRegularExpression::DotMatchesEverythingOption);
        m_comments.push_back(lc);
        m_comments.push_back(bc);

        Rule s1; s1.pattern = QRegularExpression("\"(?:\\\\.|[^\"\\\\\\n])*\""); s1.format = fString;
        Rule s2; s2.pattern = QRegularExpression("'(?:\\\\.|[^'\\\\\\n])'");      s2.format = fString;
        Rule s3; s3.pattern = QRegularExpression("R\"\\(.*?\\)\"");                s3.format = fString;
        s3.pattern.setPatternOptions(QRegularExpression::DotMatchesEverythingOption);
        m_strings.push_back(s1);
        m_strings.push_back(s2);
        m_strings.push_back(s3);

        appendKeywordRule(m_others, {
            "alignas","alignof","asm","auto","break","case","catch","class","co_await",
            "co_return","co_yield","concept","const","consteval","constexpr","constinit",
            "const_cast","continue","decltype","default","delete","do","dynamic_cast",
            "else","enum","explicit","export","extern","false","final","for","friend",
            "goto","if","inline","mutable","namespace","new","noexcept","nullptr",
            "operator","override","private","protected","public","register",
            "reinterpret_cast","requires","return","sizeof","static","static_assert",
            "static_cast","struct","switch","template","this","thread_local","throw",
            "true","try","typedef","typeid","typename","union","using","virtual","void",
            "volatile","while","#include","#define","#ifdef","#ifndef","#endif","#pragma"
        }, fKeyword);
        appendKeywordRule(m_others, {
            "bool","char","char8_t","char16_t","char32_t","double","float","int","long",
            "short","signed","unsigned","wchar_t","int8_t","int16_t","int32_t","int64_t",
            "uint8_t","uint16_t","uint32_t","uint64_t","size_t","ptrdiff_t",
            "std","string","string_view","vector","array","map","unordered_map","set",
            "unordered_set","optional","variant","tuple","pair","shared_ptr","unique_ptr",
            "weak_ptr","function","span","chrono","filesystem","atomic","mutex","thread"
        }, fType);
        appendKeywordRule(m_others, {
            "LOG_BIN","LOG_WARN","LOG_INFO","LOG_ERROR","Q_OBJECT","Q_PROPERTY","Q_INVOKABLE","QML_ELEMENT","QML_SINGLETON",
            "emit","slots","signals","Q_SLOTS","Q_SIGNALS"
        }, fBuiltin);
        m_others.push_back(numRule);
    }
    else if (m_language == "py" || m_language == "python") {
        Rule c; c.pattern = QRegularExpression("#[^\n]*"); c.format = fComment;
        m_comments.push_back(c);

        Rule s1; s1.pattern = QRegularExpression("\"\"\".*?\"\"\""); s1.format = fString;
        s1.pattern.setPatternOptions(QRegularExpression::DotMatchesEverythingOption);
        Rule s2; s2.pattern = QRegularExpression("'''.*?'''"); s2.format = fString;
        s2.pattern.setPatternOptions(QRegularExpression::DotMatchesEverythingOption);
        Rule s3; s3.pattern = QRegularExpression("\"(?:\\\\.|[^\"\\\\\\n])*\""); s3.format = fString;
        Rule s4; s4.pattern = QRegularExpression("'(?:\\\\.|[^'\\\\\\n])*'");      s4.format = fString;
        m_strings.push_back(s1);
        m_strings.push_back(s2);
        m_strings.push_back(s3);
        m_strings.push_back(s4);

        appendKeywordRule(m_others, {
            "and","as","assert","async","await","break","class","continue","def","del",
            "elif","else","except","False","finally","for","from","global","if","import",
            "in","is","lambda","None","nonlocal","not","or","pass","raise","return",
            "True","try","while","with","yield","match","case"
        }, fKeyword);
        appendKeywordRule(m_others, {
            "print","len","range","int","str","float","bool","list","dict","set","tuple",
            "self","cls","open","map","filter","zip","enumerate","sorted","sum","min","max",
            "abs","any","all","type","isinstance","getattr","setattr","hasattr","super"
        }, fBuiltin);
        m_others.push_back(numRule);
    }
    else if (m_language == "js" || m_language == "ts" || m_language == "javascript" || m_language == "typescript") {
        Rule lc; lc.pattern = QRegularExpression("//[^\n]*"); lc.format = fComment;
        Rule bc; bc.pattern = QRegularExpression("/\\*.*?\\*/"); bc.format = fComment;
        bc.pattern.setPatternOptions(QRegularExpression::DotMatchesEverythingOption);
        m_comments.push_back(lc);
        m_comments.push_back(bc);

        Rule s1; s1.pattern = QRegularExpression("\"(?:\\\\.|[^\"\\\\\\n])*\""); s1.format = fString;
        Rule s2; s2.pattern = QRegularExpression("'(?:\\\\.|[^'\\\\\\n])*'");      s2.format = fString;
        Rule s3; s3.pattern = QRegularExpression("`(?:\\\\.|[^`\\\\])*`");          s3.format = fString;
        s3.pattern.setPatternOptions(QRegularExpression::DotMatchesEverythingOption);
        m_strings.push_back(s1);
        m_strings.push_back(s2);
        m_strings.push_back(s3);

        appendKeywordRule(m_others, {
            "async","await","break","case","catch","class","const","continue","debugger",
            "default","delete","do","else","enum","export","extends","false","finally",
            "for","from","function","if","implements","import","in","instanceof","interface",
            "let","new","null","of","package","private","protected","public","return",
            "static","super","switch","this","throw","true","try","typeof","var","void",
            "while","with","yield"
        }, fKeyword);
        appendKeywordRule(m_others, {
            "console","window","document","Math","JSON","Object","Array","String","Number",
            "Boolean","Promise","Map","Set","Symbol","undefined","NaN","Infinity"
        }, fBuiltin);
        m_others.push_back(numRule);
    }
    else if (m_language == "yaml" || m_language == "yml") {
        Rule c; c.pattern = QRegularExpression("#[^\n]*"); c.format = fComment;
        m_comments.push_back(c);

        Rule s1; s1.pattern = QRegularExpression("\"[^\"\\n]*\""); s1.format = fString;
        Rule s2; s2.pattern = QRegularExpression("'[^'\\n]*'");     s2.format = fString;
        m_strings.push_back(s1);
        m_strings.push_back(s2);

        Rule key; key.pattern = QRegularExpression("^\\s*([A-Za-z_][A-Za-z0-9_-]*)\\s*:"); key.format = fKeyword;
        key.captureGroup = 1;
        m_others.push_back(key);

        appendKeywordRule(m_others, {"true","false","null","yes","no","on","off"}, fBuiltin);
        m_others.push_back(numRule);
    }
    // unknown language → leave all rule lists empty so the text renders plain
}

void CodeHighlighter::highlightBlock(const QString &text) {
    auto apply = [&](const QVector<Rule> &rules) {
        for (const Rule &r : rules) {
            auto it = r.pattern.globalMatch(text);
            while (it.hasNext()) {
                const auto m = it.next();
                const int start = m.capturedStart(r.captureGroup);
                const int len   = m.capturedLength(r.captureGroup);
                if (len > 0) setFormat(start, len, r.format);
            }
        }
    };
    apply(m_others);
    apply(m_strings);
    apply(m_comments);
}
