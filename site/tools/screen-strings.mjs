// Lists the visible Russian strings of every screen as JSON, to extend tools/screens.en.json.
// Strings the dictionary already has keep their translation; new ones come out empty.
//   node tools/screen-strings.mjs strings.json
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { russianStrings } from './screens-i18n.mjs';

const dir = new URL('../src/screens/', import.meta.url);
const dict = JSON.parse(readFileSync(new URL('./screens.en.json', import.meta.url), 'utf8'));
const seen = new Set();
for (const f of readdirSync(dir).filter((f) => f.endsWith('.html') && !f.endsWith('.en.html'))) {
  for (const s of russianStrings(readFileSync(new URL(f, dir), 'utf8'))) seen.add(s);
}
writeFileSync(process.argv[2] ?? 'strings.json', JSON.stringify(Object.fromEntries([...seen].sort().map((s) => [s, dict[s] ?? ''])), null, 1));
console.log(seen.size, 'strings,', [...seen].filter((s) => !dict[s]).length, 'without a translation');
