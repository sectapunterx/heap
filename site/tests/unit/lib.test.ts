import { describe, expect, it } from 'vitest';
import { detectOS } from '../../src/lib/os';
import { highlight, score, search } from '../../src/lib/search';
import { docSlug, rewriteDocHref } from '../../src/lib/remark-doc-links.mjs';

describe('detectOS', () => {
  it('tells desktop platforms apart', () => {
    expect(detectOS('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36')).toBe('windows');
    expect(detectOS('Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15')).toBe('macos');
    expect(detectOS('Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0')).toBe('linux');
    expect(detectOS('anything', 'Windows')).toBe('windows');
  });

  it('treats phones as mobile, not Linux or macOS', () => {
    expect(detectOS('Mozilla/5.0 (Linux; Android 14; Pixel 8) Mobile Safari/537.36')).toBe('mobile');
    expect(detectOS('Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X)')).toBe('mobile');
  });

  it('gives up on unknown agents', () => {
    expect(detectOS('curl/8.9')).toBeNull();
  });
});

describe('search', () => {
  const items = [
    { id: 'a', title: 'Keyboard reference', group: 'Docs' },
    { id: 'b', title: 'APP-101 Login rate-limit bypass', group: 'Tasks' },
    { id: 'c', title: 'Data & backups', keywords: 'state.json export import', group: 'Docs' },
  ];

  it('prefers substring and word-start matches', () => {
    expect(score('key', 'Keyboard reference')).toBeGreaterThan(score('key', 'hotkeys'));
    expect(search(items, 'keyboard')[0].id).toBe('a');
  });

  it('matches several words and keywords', () => {
    expect(search(items, 'rate lim')[0].id).toBe('b');
    expect(search(items, 'state.json')[0].id).toBe('c');
  });

  it('matches subsequences and drops misses', () => {
    expect(search(items, 'kbrf').map((i) => i.id)).toContain('a');
    expect(search(items, 'zzz')).toEqual([]);
  });

  it('highlights the first hit', () => {
    expect(highlight('Login rate-limit', 'rate')).toEqual([
      { text: 'Login ', hit: false },
      { text: 'rate', hit: true },
      { text: '-limit', hit: false },
    ]);
  });
});

describe('rewriteDocHref', () => {
  it('turns sibling markdown into site pages, keeping anchors', () => {
    expect(rewriteDocHref('HOTKEYS.md', '/heap')).toBe('/heap/docs/hotkeys/');
    expect(rewriteDocHref('TUTORIAL.md#quick-capture-syntax', '/heap')).toBe('/heap/docs/tutorial/#quick-capture-syntax');
    expect(rewriteDocHref('OAUTH-SETUP.md', '/heap')).toBe('/heap/docs/oauth-setup/');
  });

  it('sends repository paths to GitHub', () => {
    expect(rewriteDocHref('../src/integrations/OAuthClients.h')).toBe('https://github.com/sectapunterx/heap/blob/master/src/integrations/OAuthClients.h');
    expect(rewriteDocHref('../packaging/linux/')).toBe('https://github.com/sectapunterx/heap/tree/master/packaging/linux/');
  });

  it('leaves absolute, anchor and image links alone', () => {
    expect(rewriteDocHref('https://example.com/x.md')).toBe('https://example.com/x.md');
    expect(rewriteDocHref('#section')).toBe('#section');
    expect(rewriteDocHref('assets/img/screens/board-kanban.png')).toBe('assets/img/screens/board-kanban.png');
    expect(docSlug('OAUTH-SETUP.md')).toBe('oauth-setup');
  });
});
