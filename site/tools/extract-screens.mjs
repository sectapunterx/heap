// Renders screens of the lowkey (heap 2) mockups, <name>.dc.html, into the HTML fragments in
// src/screens/ that Screen.astro puts on the page inside a declarative shadow root.
//   MOCKUPS="C:/Users/Fin/Desktop/Code/New heap design/screens" node tools/extract-screens.mjs H2-Board H2-Today …
// Then run tools/translate-screens.mjs for the English copies. Uses Playwright's Chromium
// (npx playwright install chromium once).
import { chromium } from '@playwright/test';
import { writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const from = process.env.MOCKUPS;
const names = process.argv.slice(2);
if (!from || !names.length) {
  console.error('usage: MOCKUPS=<dir with *.dc.html> node tools/extract-screens.mjs <name> [<name>…]');
  process.exit(2);
}
const out = new URL('../src/screens/', import.meta.url);
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
for (const n of names) {
  await p.goto(pathToFileURL(`${from}/${n}.dc.html`).href);
  await p.waitForTimeout(300);
  const html = await p.evaluate(() => {
    const root = [...document.body.children].find((e) => e.tagName === 'DIV');
    root.querySelectorAll('script').forEach((s) => s.remove());
    // links inside a picture must not navigate anywhere
    root.querySelectorAll('a[href]').forEach((a) => a.removeAttribute('href'));
    root.querySelectorAll('[id]').forEach((e) => e.removeAttribute('id'));
    // the page's own styles (moved to <head> from <helmet>) travel with the screen into its shadow root
    const css = [...document.head.querySelectorAll('style')].map((s) => s.textContent)
      .filter((t) => !t.includes('x-dc{display:none}')).join('\n').replace(/\bbody\b/g, ':host');
    return '<style>' + css + '</style>' + root.innerHTML.replace(/\n\s+/g, '\n');
  });
  writeFileSync(new URL(`${n}.html`, out), html);
  console.log(n, html.length);
}
await b.close();
