import { Marked, type TokenizerAndRendererExtension } from 'marked';

// Markdown for demo notes: GitHub-flavoured, plus heap.'s own inline syntax —
// [[Wiki links]], @people and #TASK-ids. Raw HTML in notes is escaped.

function esc(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
}

export function wikiTargets(body: string): string[] {
  return [...body.matchAll(/\[\[([^\]\n]+)\]\]/g)].map((m) => m[1].trim());
}

export function renderNote(body: string, noteTitles: string[], taskIds: string[]): string {
  const known = new Set(noteTitles.map((t) => t.toLowerCase()));
  const tasks = new Set(taskIds);

  const wiki: TokenizerAndRendererExtension = {
    name: 'wiki',
    level: 'inline',
    start: (src) => src.indexOf('[['),
    tokenizer(src) {
      const m = /^\[\[([^\]\n]+)\]\]/.exec(src);
      if (m) return { type: 'wiki', raw: m[0], target: m[1].trim() };
      return undefined;
    },
    renderer(token) {
      const target = String(token.target);
      const exists = known.has(target.toLowerCase());
      return `<a href="#" class="md-wiki${exists ? '' : ' md-wiki--missing'}" data-note="${esc(target)}"${
        exists ? '' : ' title="No such note yet — click to create it"'
      }>${esc(target)}</a>`;
    },
  };

  const mention: TokenizerAndRendererExtension = {
    name: 'mention',
    level: 'inline',
    start: (src) => {
      const m = /(^|[\s(])@[\w]/.exec(src);
      return m ? m.index + m[1].length : undefined;
    },
    tokenizer(src) {
      const m = /^@([\w.-]*\w)/.exec(src);
      if (m) return { type: 'mention', raw: m[0], name: m[1] };
      return undefined;
    },
    renderer: (token) => `<span class="md-mention">@${esc(String(token.name))}</span>`,
  };

  const ticket: TokenizerAndRendererExtension = {
    name: 'ticket',
    level: 'inline',
    start: (src) => {
      const m = /(^|[\s(])#[A-Z]/.exec(src);
      return m ? m.index + m[1].length : undefined;
    },
    tokenizer(src) {
      const m = /^#([A-Z][A-Z0-9]{1,9}-\d{1,6})\b/.exec(src);
      if (m) return { type: 'ticket', raw: m[0], id: m[1] };
      return undefined;
    },
    renderer(token) {
      const id = String(token.id);
      return tasks.has(id)
        ? `<a href="#" class="md-ticket" data-task="${id}">${id}</a>`
        : `<span class="md-ticket md-ticket--unknown">${id}</span>`;
    },
  };

  const md = new Marked({ gfm: true, breaks: true, async: false });
  md.use({
    extensions: [wiki, mention, ticket],
    renderer: {
      html: ({ text }) => esc(text),
    },
  });
  return md.parse(body) as string;
}
