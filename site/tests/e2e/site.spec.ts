import { readFileSync, readdirSync, statSync } from 'node:fs';
import { BASE, REPO } from '../../repo.mjs';
import { join } from 'node:path';
import { expect, test, type Page } from '@playwright/test';

const PAGES = ['', 'ru/', 'download/', 'ru/download/'];

function collectErrors(page: Page): string[] {
  const errors: string[] = [];
  page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
  page.on('console', (m) => m.type() === 'error' && errors.push(`console: ${m.text()}`));
  page.on('requestfailed', (r) => errors.push(`requestfailed: ${r.url()}`));
  page.on('request', (r) => {
    const u = new URL(r.url());
    if (u.hostname !== 'localhost') errors.push(`third-party request: ${r.url()}`);
  });
  return errors;
}

for (const path of PAGES) {
  test(`/${path} renders cleanly`, async ({ page }) => {
    const errors = collectErrors(page);
    const res = await page.goto(path);
    expect(res?.status()).toBe(200);
    await page.waitForLoadState('networkidle');
    await expect(page.locator('h1').first()).toBeVisible();
    expect(errors).toEqual([]);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    expect(overflow, 'no horizontal page scroll').toBeLessThanOrEqual(0);
  });

  test(`/${path} never starts a sentence with the product name`, async ({ page }) => {
    await page.goto(path);
    const text = await page.locator('body').innerText();
    expect(text).not.toMatch(/(?:^|[.!?]\s+|\n\s*)lowkey\b/);
  });
}

test('the product name is never capitalised in the built HTML', () => {
  // Legal text (the LICENSE) is not part of the site; nothing here is exempt.
  const files: string[] = [];
  const walk = (dir: string) => {
    for (const f of readdirSync(dir)) {
      const p = join(dir, f);
      if (statSync(p).isDirectory()) walk(p);
      else if (p.endsWith('.html')) files.push(p);
    }
  };
  walk('dist');
  expect(files.length).toBeGreaterThanOrEqual(5);
  // MOVED-TO-LOWKEY.txt is the real name of the marker file the app leaves in the old heap folder
  for (const f of files) expect(readFileSync(f, 'utf8').replaceAll('MOVED-TO-LOWKEY.txt', ''), f).not.toMatch(/Lowkey|LOWKEY/);
});

test('unknown pages get the 404 page', async ({ page }) => {
  const res = await page.goto('does-not-exist/');
  expect(res?.status()).toBe(404);
  await expect(page.getByRole('heading', { name: 'This page is not here.' })).toBeVisible();
});

test('internal links all resolve', async ({ page, request }) => {
  const seen = new Set<string>();
  for (const path of PAGES) {
    await page.goto(path);
    const hrefs = await page.$$eval('a[href]', (as) => as.map((a) => (a as HTMLAnchorElement).href));
    for (const h of hrefs) {
      const u = new URL(h);
      if (u.hostname !== 'localhost') continue;
      u.hash = '';
      seen.add(u.toString());
    }
  }
  expect(seen.size).toBeGreaterThan(3);
  for (const u of seen) expect((await request.get(u)).status(), u).toBe(200);
});

test('links to pages of the old site still lead somewhere', async ({ request }) => {
  for (const [path, to] of [['demo/', `${BASE}/#try`], ['privacy/', `${BASE}/#trust`], ['docs/hotkeys/', `github.com/${REPO}/tree/master/docs`], ['changelog/', `github.com/${REPO}/releases`]]) {
    const res = await request.get(path);
    expect(res.status(), path).toBe(200);
    expect(await res.text(), path).toContain(`url=${to.startsWith('/') ? to : 'https://' + to}`);
  }
});

test('the language switch leads to the same page in the other language', async ({ page }) => {
  await page.goto('download/');
  await page.locator('header .lang-switch').click();
  await expect(page).toHaveURL(new RegExp(`${BASE}/ru/download/$`));
  await expect(page.locator('html')).toHaveAttribute('lang', 'ru');
  await page.locator('header .lang-switch').click();
  await expect(page).toHaveURL(new RegExp(`${BASE}/download/$`));
});

test.describe('tracker writes are described as off by default', () => {
  test('en', async ({ page }) => {
    await page.goto('');
    const card = page.locator('[data-card="Trackers are read-only"]');
    await expect(card).toContainText('Nothing is written to your trackers.');
    await expect(card).toContainText('Status write-back is turned on per tracker');
    await expect(page.locator('#faq')).toContainText('by default nothing is written back');
    // the old site promised that closing a card closes the issue
    expect(await page.locator('body').innerText()).not.toMatch(/issue closes|closes the issue/i);
  });

  test('ru', async ({ page }) => {
    await page.goto('ru/');
    const card = page.locator('[data-card="Трекеры — только чтение"]');
    await expect(card).toContainText('В трекеры ничего не пишется.');
    await expect(card).toContainText('Запись статуса включается для каждого трекера отдельно');
    await expect(page.locator('#faq')).toContainText('обратно по умолчанию ничего не пишется');
  });
});

test('the state.json example is the current schema', async ({ page }) => {
  await page.goto('');
  const example = page.locator('[data-state-example]');
  await expect(example.locator('figcaption')).toContainText('schema 12');
  const code = await example.locator('pre').innerText();
  expect(code).toContain('"scheduledAt"');
  expect(code).not.toMatch(/"deadline"|"schemaVersion": 5/);
});

test('the copy keeps at most the allowed emotional lines', async ({ page }) => {
  for (const path of ['', 'ru/']) {
    await page.goto(path);
    const text = await page.locator('body').innerText();
    expect(text).not.toMatch(/не обидимся|won.t be offended|Попробуйте один день/i);
  }
});

test.describe('home page scenes', () => {
  test.skip(({ isMobile }) => isMobile, 'keyboard and pointer checks are desktop checks');

  test('the git scene names the branch’s task', async ({ page }) => {
    await page.goto('');
    await page.locator('[data-git-run]').scrollIntoViewIfNeeded();
    await page.locator('[data-git-run]').click();
    await expect(page.locator('[data-git-bar]')).toContainText('Working on APP-112', { timeout: 10_000 });
    await expect(page.locator('[data-git-card]')).toContainText('in progress');
    await expect(page.locator('[data-git-card]')).toContainText('PR #57');
  });

  test('capture: words become chips, d closes, the empty state shows', async ({ page }) => {
    await page.goto('ru/');
    const input = page.locator('.cap-in');
    await input.scrollIntoViewIfNeeded();
    await input.fill('ревью PR завтра 15:00 #api p1');
    await expect(page.locator('.chips .chip')).toHaveCount(4);
    await input.press('Enter');
    await expect(page.locator('.list .task').first()).toContainText('ревью PR');
    for (let i = 0; i < 4; i++) await page.locator('.list .task:not(.done) .tick').first().click();
    await expect(page.locator('.empty-h')).toHaveText('Пусто. Можно выдохнуть.');
  });

  test('Ctrl K searches the page and opens the answer', async ({ page }) => {
    await page.goto('');
    await page.waitForLoadState('networkidle');
    await page.keyboard.press('Control+k');
    const input = page.getByRole('combobox', { name: 'Search this site' });
    await expect(input).toBeFocused();
    await input.fill('obsidian');
    await page.keyboard.press('Enter');
    await expect(page.locator('#faq details', { hasText: 'Obsidian' })).toHaveAttribute('open', '');
  });

  test('"/" opens the search too, as the filter key does in the app', async ({ page }) => {
    await page.goto('ru/');
    await page.waitForLoadState('networkidle');
    await page.keyboard.press('/');
    await expect(page.getByRole('combobox', { name: 'Поиск по сайту' })).toBeFocused();
  });
});

test('the download buttons point at this platform’s file', async ({ page, isMobile }) => {
  await page.goto('');
  await page.waitForLoadState('networkidle');
  const cta = page.locator('.hero a[data-os-cta]');
  if (isMobile) {
    await expect(cta).toHaveText('Download lowkey');
    await page.goto('download/');
    await expect(page.locator('[data-mobile-note]')).toBeVisible();
  } else {
    await expect(cta).toHaveText(/Download for (Linux|Windows|macOS)/);
    await expect(cta).toHaveAttribute('href', /^https:\/\/github\.com\/sectapunterx\/heap\/releases\/download\//);
  }
});

test('the download page lists every file with its size', async ({ page }) => {
  for (const [path, mb] of [['download/', 'MB'], ['ru/download/', 'МБ']]) {
    await page.goto(path);
    const files = page.locator('[data-files] a');
    await expect(files).toHaveCount(4);
    for (const a of await files.all()) {
      await expect(a).toContainText(new RegExp(`\\d+\\.\\d ${mb}`));
      await expect(a).toHaveAttribute('href', /^https:\/\/github\.com\/sectapunterx\/heap\/releases\/download\//);
    }
  }
});
