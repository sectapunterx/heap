import { expect, test, type Page } from '@playwright/test';

const PAGES = [
  '',
  'features/',
  'features/plan/',
  'features/time/',
  'features/know/',
  'features/connect/',
  'features/flow/',
  'demo/',
  'compare/',
  'privacy/',
  'download/',
  'docs/',
  'docs/tutorial/',
  'docs/hotkeys/',
  'docs/integrations/',
  'docs/oauth-setup/',
  'docs/data/',
  'docs/distribution/',
  'docs/packaging/',
  'changelog/',
  'brand/',
];

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
}

test('unknown pages get the 404 page', async ({ page }) => {
  const res = await page.goto('does-not-exist/');
  expect(res?.status()).toBe(404);
  await expect(page.getByRole('heading', { name: 'This page isn’t on the board.' })).toBeVisible();
});

test('internal links all resolve', async ({ page, request }) => {
  const seen = new Set<string>();
  for (const path of ['', 'features/', 'docs/', 'download/', 'changelog/']) {
    await page.goto(path);
    const hrefs = await page.$$eval('a[href]', (as) => as.map((a) => (a as HTMLAnchorElement).href));
    for (const h of hrefs) {
      const u = new URL(h);
      if (u.hostname !== 'localhost') continue;
      u.hash = '';
      seen.add(u.toString());
    }
  }
  for (const u of seen) {
    const res = await request.get(u);
    expect(res.status(), u).toBe(200);
  }
});

test('the theme toggle sticks across pages', async ({ page, isMobile }) => {
  await page.goto('');
  const before = await page.evaluate(() => document.documentElement.dataset.theme);
  await page.locator('[data-theme-toggle]').first().click();
  const after = await page.evaluate(() => document.documentElement.dataset.theme);
  expect(after).not.toBe(before);
  await page.goto(isMobile ? 'privacy/' : 'compare/');
  expect(await page.evaluate(() => document.documentElement.dataset.theme)).toBe(after);
});

test('the site palette finds a doc section', async ({ page, isMobile }) => {
  test.skip(isMobile, 'keyboard shortcut');
  await page.goto('');
  await page.waitForLoadState('networkidle');
  await page.keyboard.press('/');
  const input = page.getByRole('combobox', { name: 'Search the site' });
  await expect(input).toBeFocused();
  await input.fill('quick-capture syntax');
  await page.keyboard.press('Enter');
  await expect(page).toHaveURL(/docs\/tutorial\/#quick-capture-syntax/);
});

test('the download button points at this platform’s file', async ({ page, isMobile }) => {
  await page.goto('');
  await page.waitForLoadState('networkidle');
  const cta = page.locator('[data-os-cta]');
  if (isMobile) {
    await expect(cta).toHaveText(/Download/);
    await page.goto('download/');
    await expect(page.locator('[data-mobile-note]')).toBeVisible();
  } else {
    // Desktop Chrome in Playwright reports Linux on Linux, Windows on Windows…
    await expect(cta).toHaveText(/Download for (Linux|Windows|macOS)/);
    await expect(cta).toHaveAttribute('href', /github\.com\/sectapunterx\/heap\/releases\/download\//);
  }
});

test('home tour tabs switch panels', async ({ page }) => {
  await page.goto('');
  await page.getByRole('tab', { name: /Know/ }).click();
  await expect(page.locator('[data-tour-panel="know"]')).toBeVisible();
  await expect(page.locator('[data-tour-panel="plan"]')).toBeHidden();
});
