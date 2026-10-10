// Turns a Russian screen fragment (src/screens/<name>.html) into its English copy with the
// dictionary in tools/screens.en.json. Every visible Russian string must have a translation:
// a string the dictionary lacks throws, so an English page can never show Russian text.
// Used by tools/translate-screens.mjs, tools/screen-strings.mjs and tests/unit/screens.test.ts.

const CYRILLIC = /[А-Яа-яЁё]/;

/** Throws `untranslated: <string>` for a Russian string the dictionary has no entry for. */
export function translateString(s, dict) {
  const t = s.trim();
  if (!CYRILLIC.test(t)) return s;
  if (!dict[t]) throw new Error('untranslated: ' + t);
  return s.replace(t, dict[t]);
}

/** The English copy of one screen; styles pass through untouched. */
export function translateScreen(html, dict) {
  const parts = html.split(/(<style>[\s\S]*?<\/style>)/);
  return parts
    .map((p) =>
      p.startsWith('<style>')
        ? p
        : p
            .replace(/>([^<]+)</g, (_, t) => '>' + translateString(t, dict) + '<')
            .replace(/(aria-label|title|placeholder)="([^"]+)"/g, (_, a, v) => `${a}="${translateString(v, dict)}"`),
    )
    .join('')
    .replace(/lang="ru"/g, 'lang="en"');
}

/** Every visible Russian string of a screen: text nodes and aria-label/title/placeholder values. */
export function russianStrings(html) {
  const seen = new Set();
  const body = html.replace(/<style>[\s\S]*?<\/style>/g, '');
  for (const m of body.matchAll(/>([^<]+)</g)) {
    const t = m[1].trim();
    if (CYRILLIC.test(t)) seen.add(t);
  }
  for (const m of body.matchAll(/(?:aria-label|title|placeholder)="([^"]+)"/g)) if (CYRILLIC.test(m[1])) seen.add(m[1].trim());
  return seen;
}
