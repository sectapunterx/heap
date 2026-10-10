// The live screens: the English copies are made from the Russian ones by tools/translate-screens.mjs,
// which must refuse a string it has no translation for.
import { readFileSync, readdirSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { russianStrings, translateScreen, translateString } from '../../tools/screens-i18n.mjs';

const dir = new URL('../../src/screens/', import.meta.url);
const dict = JSON.parse(readFileSync(new URL('../../tools/screens.en.json', import.meta.url), 'utf8')) as Record<string, string>;
const russian = readdirSync(dir).filter((f) => f.endsWith('.html') && !f.endsWith('.en.html'));

describe('translate-screens', () => {
  it('fails on an untranslated string', () => {
    expect(() => translateString('Совсем новая строка', dict)).toThrow('untranslated: Совсем новая строка');
    expect(() => translateScreen('<div title="Новая подсказка">x</div>', dict)).toThrow(/untranslated/);
    expect(() => translateScreen('<span>Строка без перевода</span>', dict)).toThrow(/untranslated/);
  });

  it('leaves styles and non-Russian text alone', () => {
    expect(translateScreen('<style>.a{content:"Привет"}</style><b>APP-112</b>', dict)).toBe('<style>.a{content:"Привет"}</style><b>APP-112</b>');
  });

  it('has a translation for every string on every screen', () => {
    const missing = russian.flatMap((f) => [...russianStrings(readFileSync(new URL(f, dir), 'utf8'))].filter((s: string) => !dict[s]));
    expect(missing).toEqual([]);
  });

  it('the committed English screens are what the translator makes now', () => {
    for (const f of russian) {
      const made = translateScreen(readFileSync(new URL(f, dir), 'utf8'), dict);
      expect(readFileSync(new URL(f.replace('.html', '.en.html'), dir), 'utf8'), `${f}: rerun npm run screens:en`).toBe(made);
      expect(made.replace(/<style>[\s\S]*?<\/style>/g, '')).not.toMatch(/[А-Яа-яЁё]/);
    }
  });

  it('no screen names the product with a capital letter', () => {
    for (const f of readdirSync(dir)) expect(readFileSync(new URL(f, dir), 'utf8')).not.toMatch(/Lowkey|LOWKEY/);
  });
});
