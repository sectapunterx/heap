#include "markdown/MdHtml.h"

#include <QRegularExpression>
#include <QUrl>

namespace heap::md {

namespace {

// ── Inline decorations ──────────────────────────────────────────────
// These are heap's own conventions, not CommonMark, and they change nothing
// about the document's structure — which is why they are applied here, on the
// way to rich text, rather than in the AST. The patterns match what the editor
// highlighter has always used, so the two views agree on what is a mention.

const QRegularExpression& decorationRx() {
  // One pass, alternatives ordered so the longer match wins: a ticket
  // reference must be tried before a bare tag, or "#HEAP-1" reads as the tag
  // "HEAP".
  static const QRegularExpression rx(
      QStringLiteral("(==(?!\\s)([^=\\n]+)==)"                         // 1,2: ==highlight==
                     "|(\\[\\^([^\\]\\s]+)\\])"                        // 3,4: [^footnote]
                     "|(?<![A-Za-z0-9_])(#([A-Z][A-Z0-9]*-\\d+))"      // 5,6: #TICKET-123
                     "|(?<![A-Za-z0-9_])(#([A-Za-z][A-Za-z0-9_/-]*))"  // 7,8: #tag
                     "|(?<![A-Za-z0-9_])(@([A-Za-z0-9_.-]+))"));       // 9,10: @mention
  return rx;
}

QString colorOr(const QString& color, const QString& fallback) {
  return color.isEmpty() ? fallback : color;
}

QString span(const QString& color, const QString& body) {
  if(color.isEmpty()) {
    return body;
  }
  return QStringLiteral("<span style=\"color:%1;\">%2</span>").arg(color, body);
}

// A link heap resolves itself rather than handing to the browser. The UI
// routes these; nothing is fetched.
QString internalLink(const QString& scheme, const QString& target, const QString& label, const QString& color) {
  return QStringLiteral("<a href=\"heap://%1/%2\" style=\"color:%3;text-decoration:none;\">%4</a>")
      .arg(scheme, QString::fromUtf8(QUrl::toPercentEncoding(target)), colorOr(color, QStringLiteral("inherit")), label);
}

bool isRemote(const QString& href) {
  const QString lower = href.trimmed().toLower();
  return lower.startsWith(QStringLiteral("http://")) || lower.startsWith(QStringLiteral("https://")) ||
         lower.startsWith(QStringLiteral("//"));
}

// Text with heap's decorations applied. The input is raw document text; every
// piece of it is escaped here, including the parts that end up inside a tag.
QString decorate(const QString& text, const MdHtmlOptions& options) {
  QString out;
  int last = 0;
  auto it = decorationRx().globalMatch(text);
  while(it.hasNext()) {
    const auto match = it.next();
    out += escapeHtml(text.mid(last, match.capturedStart() - last));

    if(match.capturedStart(1) >= 0) {
      const QString body = escapeHtml(match.captured(2));
      out += options.palette.highlightBackground.isEmpty()
                 ? body
                 : QStringLiteral("<span style=\"background-color:%1;\">%2</span>").arg(options.palette.highlightBackground, body);
    } else if(match.capturedStart(3) >= 0) {
      const QString id = match.captured(4);
      const int number = options.footnoteNumbers.value(id, 0);
      // An unnumbered reference has no definition anywhere in the document.
      // Showing the id keeps the text honest rather than inventing a number.
      const QString label = number > 0 ? QString::number(number) : escapeHtml(id);
      out += QStringLiteral("<sup>%1</sup>").arg(internalLink(QStringLiteral("fn"), id, label, options.palette.link));
    } else if(match.capturedStart(5) >= 0) {
      out += internalLink(QStringLiteral("task"), match.captured(6), escapeHtml(match.captured(5)), options.palette.ticket);
    } else if(match.capturedStart(7) >= 0) {
      out += internalLink(QStringLiteral("tag"), match.captured(8), escapeHtml(match.captured(7)), options.palette.tag);
    } else if(match.capturedStart(9) >= 0) {
      out += internalLink(QStringLiteral("person"), match.captured(10), escapeHtml(match.captured(9)), options.palette.mention);
    }
    last = match.capturedEnd();
  }
  out += escapeHtml(text.mid(last));
  return out;
}

void appendInline(const MdAst& ast, int index, const MdHtmlOptions& options, QString* out);

// Render a list of sibling inlines, coalescing consecutive plain-text nodes
// before decorating them.
//
// md4c hands text back in runs that break at characters it had to inspect, so
// "[^ref]" commonly arrives as "[", "^ref", "]". Decorating each node on its
// own would never see a whole pattern. Joining the run first is also what
// makes "==a **b** c==" behave: the highlight simply does not match across the
// bold, which is the same answer every other editor gives.
void appendSiblings(const MdAst& ast, const QVector<int>& indices, const MdHtmlOptions& options, QString* out) {
  QString run;
  for(const int index : indices) {
    if(index >= 0 && index < ast.inlines.size() && ast.inlines.at(index).type == InlineType::Text) {
      run += ast.inlines.at(index).text;
      continue;
    }
    if(!run.isEmpty()) {
      *out += decorate(run, options);
      run.clear();
    }
    appendInline(ast, index, options, out);
  }
  if(!run.isEmpty()) {
    *out += decorate(run, options);
  }
}

void appendChildren(const MdAst& ast, const MdInline& node, const MdHtmlOptions& options, QString* out) {
  appendSiblings(ast, node.children, options, out);
}

void appendInline(const MdAst& ast, int index, const MdHtmlOptions& options, QString* out) {
  if(index < 0 || index >= ast.inlines.size()) {
    return;
  }
  const MdInline& node = ast.inlines.at(index);

  switch(node.type) {
    case InlineType::Text:
      // Reached only when a text node stands alone; a run of them is joined by
      // appendSiblings before it gets here.
      *out += decorate(node.text, options);
      break;

    case InlineType::HtmlInline:
      // Raw HTML from the document is shown, never interpreted: a note is not
      // a web page, and a stray "<script>" must read as text.
      *out += escapeHtml(node.text);
      break;

    case InlineType::SoftBreak:
      *out += QLatin1Char('\n');
      break;
    case InlineType::HardBreak:
      *out += QStringLiteral("<br/>");
      break;

    case InlineType::Emphasis:
      *out += QStringLiteral("<i>");
      appendChildren(ast, node, options, out);
      *out += QStringLiteral("</i>");
      break;
    case InlineType::Strong:
      *out += QStringLiteral("<b>");
      appendChildren(ast, node, options, out);
      *out += QStringLiteral("</b>");
      break;
    case InlineType::Strikethrough:
      *out += QStringLiteral("<s>");
      appendChildren(ast, node, options, out);
      *out += QStringLiteral("</s>");
      break;
    case InlineType::Underline:
      *out += QStringLiteral("<u>");
      appendChildren(ast, node, options, out);
      *out += QStringLiteral("</u>");
      break;

    case InlineType::Code: {
      // Code is never decorated: "#tag" inside backticks is a shell comment,
      // not a tag, and an @ in a snippet is not a mention.
      QString body;
      for(const int child : node.children) {
        body += ast.inlines.at(child).text;
      }
      body += node.text;
      QString styled = QStringLiteral("<code>%1</code>").arg(escapeHtml(body));
      if(!options.palette.codeBackground.isEmpty() || !options.palette.code.isEmpty()) {
        styled = QStringLiteral("<span style=\"background-color:%1;color:%2;\">%3</span>")
                     .arg(colorOr(options.palette.codeBackground, QStringLiteral("transparent")),
                          colorOr(options.palette.code, QStringLiteral("inherit")),
                          styled);
      }
      *out += styled;
      break;
    }

    case InlineType::LatexMath:
    case InlineType::LatexMathDisplay: {
      // Nothing typesets maths in this build, so the source is shown in a
      // distinct colour rather than silently dropped or rendered wrongly.
      QString body;
      for(const int child : node.children) {
        body += ast.inlines.at(child).text;
      }
      body += node.text;
      *out += span(options.palette.math, QStringLiteral("<code>%1</code>").arg(escapeHtml(body)));
      break;
    }

    case InlineType::Link: {
      QString label;
      for(const int child : node.children) {
        appendInline(ast, child, options, &label);
      }
      if(label.isEmpty()) {
        label = escapeHtml(node.href);
      }
      *out += QStringLiteral("<a href=\"%1\" style=\"color:%2;\">%3</a>")
                  .arg(escapeHtml(node.href), colorOr(options.palette.link, QStringLiteral("inherit")), label);
      break;
    }

    case InlineType::WikiLink: {
      QString label;
      appendChildren(ast, node, options, &label);
      if(label.isEmpty()) {
        label = escapeHtml(node.href);
      }
      *out += internalLink(QStringLiteral("note"), node.href, label, options.palette.link);
      break;
    }

    case InlineType::Image: {
      QString alt;
      appendChildren(ast, node, options, &alt);
      if(alt.isEmpty()) {
        alt = escapeHtml(node.href);
      }
      if(isRemote(node.href) && !options.allowRemoteImages) {
        // Emitting <img> here would make Qt fetch the URL as soon as the note
        // is opened, on behalf of whoever wrote it. Offer it as a link and let
        // the reader decide.
        *out += QStringLiteral("<a href=\"%1\" style=\"color:%2;\">%3</a>")
                    .arg(escapeHtml(node.href), colorOr(options.palette.link, QStringLiteral("inherit")), alt);
      } else {
        *out += QStringLiteral("<img src=\"%1\" alt=\"%2\"/>").arg(escapeHtml(node.href), alt);
      }
      break;
    }

    default:
      *out += escapeHtml(node.text);
      appendChildren(ast, node, options, out);
      break;
  }
}

void appendPlain(const MdAst& ast, int index, QString* out) {
  if(index < 0 || index >= ast.inlines.size()) {
    return;
  }
  const MdInline& node = ast.inlines.at(index);
  if(node.type == InlineType::SoftBreak || node.type == InlineType::HardBreak) {
    *out += QLatin1Char(' ');
  } else {
    *out += node.text;
  }
  for(const int child : node.children) {
    appendPlain(ast, child, out);
  }
}

}  // namespace

QString escapeHtml(const QString& text) {
  QString out;
  out.reserve(text.size());
  for(const QChar ch : text) {
    switch(ch.unicode()) {
      case u'&':
        out += QStringLiteral("&amp;");
        break;
      case u'<':
        out += QStringLiteral("&lt;");
        break;
      case u'>':
        out += QStringLiteral("&gt;");
        break;
      case u'"':
        out += QStringLiteral("&quot;");
        break;
      case u'\'':
        out += QStringLiteral("&#39;");
        break;
      default:
        out += ch;
        break;
    }
  }
  return out;
}

QString inlineHtml(const MdAst& ast, const MdBlock& block, const MdHtmlOptions& options) {
  QString out;
  appendSiblings(ast, block.inlines, options, &out);
  return out;
}

QString inlinePlainText(const MdAst& ast, const MdBlock& block) {
  QString out;
  for(const int index : block.inlines) {
    appendPlain(ast, index, &out);
  }
  return out;
}

QHash<QString, int> footnoteNumbers(const MdAst& ast) {
  // Numbered by first reference, the way a reader meets them, rather than by
  // where the definitions happen to sit.
  static const QRegularExpression refRx(QStringLiteral("\\[\\^([^\\]\\s]+)\\]"));

  QHash<QString, int> numbers;
  int next = 1;
  for(const MdBlock& block : ast.blocks) {
    if(block.type == BlockType::CodeBlock) {
      continue;
    }
    // The whole block at once: md4c splits "[^id]" across text nodes, so a
    // per-node scan would never match one.
    QString text;
    for(const int index : block.inlines) {
      appendPlain(ast, index, &text);
    }
    auto it = refRx.globalMatch(text);
    while(it.hasNext()) {
      const QString id = it.next().captured(1);
      if(!numbers.contains(id)) {
        numbers.insert(id, next++);
      }
    }
  }
  return numbers;
}

}  // namespace heap::md
