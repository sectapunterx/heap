export interface Searchable {
  id: string;
  title: string;
  /** Extra text that can match but ranks lower than the title. */
  keywords?: string;
  group: string;
}

/**
 * Score a query against a string: contiguous substring matches beat
 * scattered subsequence matches, earlier and word-start matches beat later
 * ones. Returns -1 when the query does not match at all.
 */
export function score(query: string, text: string): number {
  const q = query.trim().toLowerCase();
  const t = text.toLowerCase();
  if (!q) return 0;
  const idx = t.indexOf(q);
  if (idx >= 0) {
    const wordStart = idx === 0 || /[\s\-_/.(#@[]/.test(t[idx - 1]);
    return 1000 - idx + (wordStart ? 200 : 0) - (t.length - q.length) * 0.1;
  }
  // every word of the query somewhere in the text
  const words = q.split(/\s+/).filter(Boolean);
  if (words.length > 1 && words.every((w) => t.includes(w))) {
    return 500 - t.indexOf(words[0]);
  }
  // subsequence
  let ti = 0;
  let gaps = 0;
  for (const ch of q) {
    const found = t.indexOf(ch, ti);
    if (found < 0) return -1;
    gaps += found - ti;
    ti = found + 1;
  }
  return 100 - gaps;
}

export function search<T extends Searchable>(items: T[], query: string, limit = 12): T[] {
  if (!query.trim()) return items.slice(0, limit);
  return items
    .map((item) => {
      const s = Math.max(score(query, item.title), item.keywords ? score(query, item.keywords) - 300 : -1);
      return { item, s };
    })
    .filter((r) => r.s >= 0)
    .sort((a, b) => b.s - a.s)
    .slice(0, limit)
    .map((r) => r.item);
}

/** Split `text` into plain and highlighted runs for the first match of `query`. */
export function highlight(text: string, query: string): Array<{ text: string; hit: boolean }> {
  const q = query.trim();
  if (!q) return [{ text, hit: false }];
  const i = text.toLowerCase().indexOf(q.toLowerCase());
  if (i < 0) return [{ text, hit: false }];
  return [
    { text: text.slice(0, i), hit: false },
    { text: text.slice(i, i + q.length), hit: true },
    { text: text.slice(i + q.length), hit: false },
  ].filter((r) => r.text);
}
