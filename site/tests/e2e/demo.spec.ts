import { expect, test, type Page } from '@playwright/test';

async function dragTo(page: Page, from: string, to: string) {
  const a = await page.locator(from).boundingBox();
  const b = await page.locator(to).boundingBox();
  if (!a || !b) throw new Error('missing element');
  await page.mouse.move(a.x + a.width / 2, a.y + a.height / 2);
  await page.mouse.down();
  await page.mouse.move(a.x + a.width / 2 + 10, a.y + a.height / 2 + 10, { steps: 4 });
  await page.mouse.move(b.x + b.width / 2, b.y + 40, { steps: 12 });
  await page.mouse.up();
}

test.describe('hero board', () => {
  test('a click moves a card one column right', async ({ page }) => {
    await page.goto('');
    const card = page.locator('.hb [data-card="APP-108"]');
    await card.scrollIntoViewIfNeeded();
    await expect(card).toBeVisible();
    await card.click();
    await expect(page.locator('.hb section[aria-label^="In progress"] [data-card="APP-108"]')).toBeVisible();
  });
});

test.describe('sandbox', () => {
  test.skip(({ isMobile }) => isMobile, 'pointer drag and shortcuts are desktop checks');

  test.beforeEach(async ({ page }) => {
    await page.goto('demo/');
    await page.evaluate(() => localStorage.removeItem('heap-demo-v1'));
    await page.reload();
    await expect(page.locator('[data-card="APP-108"]')).toBeVisible();
  });

  test('drag a card to another column, and it survives a reload', async ({ page }) => {
    await dragTo(page, '[data-card="APP-108"]', 'section[aria-label^="Review"]');
    await expect(page.locator('section[aria-label^="Review"] [data-card="APP-108"]')).toBeVisible();
    await page.reload();
    await expect(page.locator('section[aria-label^="Review"] [data-card="APP-108"]')).toBeVisible();
  });

  test('keyboard: select a card and move it with Shift+L', async ({ page }) => {
    await page.locator('[data-card="APP-110"]').click();
    await page.keyboard.press('Shift+L');
    await expect(page.locator('section[aria-label^="In progress"] [data-card="APP-110"]')).toBeVisible();
  });

  test('Ctrl+K opens the palette and jumps to a note', async ({ page }) => {
    await page.keyboard.press('Control+k');
    const input = page.getByRole('combobox', { name: 'Search tasks, notes and commands' });
    await expect(input).toBeFocused();
    await input.fill('rate limiter');
    await page.keyboard.press('Enter');
    await expect(page.getByRole('textbox', { name: /Markdown for Rate limiter design/ })).toBeVisible();
  });

  test('the terminal matches a branch to its card', async ({ page }) => {
    await page.keyboard.press('`');
    const cmd = page.getByRole('textbox', { name: 'Command' });
    await cmd.fill('git switch -c APP-112-flaky-sync-test');
    await cmd.press('Enter');
    await expect(page.locator('[data-card="APP-112"]')).toHaveClass(/d-card--matched/);
    await expect(page.locator('.d-banner--live')).toContainText('APP-112');
  });

  test('quick capture books a focus block on the week', async ({ page }) => {
    await page.keyboard.press('n');
    const box = page.getByRole('textbox', { name: 'Quick capture' });
    await box.fill('focus refactor parser 16:00');
    await expect(page.locator('.d-parse')).toContainText('focus block');
    await box.press('Enter');
    await expect(page.locator('.d-event', { hasText: 'Focus: Refactor parser' })).toBeVisible();
  });

  test('notes: a missing [[link]] creates the note', async ({ page }) => {
    await page.keyboard.press('3');
    await page.locator('.md-wiki--missing', { hasText: 'Retry budget' }).click();
    await expect(page.getByRole('button', { name: 'Retry budget' })).toHaveAttribute('aria-current', 'true');
  });

  test('week: drag an event to a later time', async ({ page }) => {
    await page.keyboard.press('2');
    const ev = page.locator('.d-event', { hasText: 'Sprint planning' });
    await ev.scrollIntoViewIfNeeded();
    const box = (await ev.boundingBox())!;
    await page.mouse.move(box.x + box.width / 2, box.y + 8);
    await page.mouse.down();
    await page.mouse.move(box.x + box.width / 2, box.y + 8 + 48, { steps: 8 });
    await page.mouse.up();
    await expect(ev).toContainText('15:00–16:30');
  });
});

test('feature widgets load on every area page', async ({ page }) => {
  for (const [area, probe] of [
    ['plan', '[data-card="APP-101"]'],
    ['time', '.d-week'],
    ['know', '.d-notes'],
    ['connect', '.cw__panel'],
    ['flow', '.d-term'],
  ] as const) {
    await page.goto(`features/${area}/`);
    await expect(page.locator(probe).first()).toBeVisible();
  }
});

test('connect widget: connecting GitHub brings issues, Done closes one', async ({ page, isMobile }) => {
  test.skip(isMobile, 'pointer drag');
  await page.goto('features/connect/');
  await page.getByRole('button', { name: 'Connect with browser' }).click();
  await expect(page.locator('[data-card="WEB-231"]')).toBeVisible({ timeout: 5000 });
  await dragTo(page, '[data-card="WEB-231"]', '.cw__panel section[aria-label^="Done"]');
  await expect(page.locator('.d-toast')).toContainText('closed on GitHub');
});
