// Writes src/screens/<name>.en.html from each Russian screen using tools/screens.en.json.
// Rerun after re-extracting screens; fails on any Russian string left untranslated.
//   node tools/translate-screens.mjs
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { translateScreen } from './screens-i18n.mjs';

const dir = new URL('../src/screens/', import.meta.url);
const dict = JSON.parse(readFileSync(new URL('./screens.en.json', import.meta.url), 'utf8'));
for (const f of readdirSync(dir).filter((f) => f.endsWith('.html') && !f.endsWith('.en.html'))) {
  writeFileSync(new URL(f.replace('.html', '.en.html'), dir), translateScreen(readFileSync(new URL(f, dir), 'utf8'), dict));
  console.log(f);
}
