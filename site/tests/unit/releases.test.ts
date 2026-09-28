import { describe, expect, it } from 'vitest';
import { assetsByOS, classifyAsset, formatSize, parseNotes, summarize, versionOf, type Release } from '../../src/lib/releases';
import fallback from '../../src/data/releases.fallback.json';

const asset = (name: string, size = 1_000_000) => ({ name, size, url: `https://example.test/${name}` });

describe('classifyAsset', () => {
  it('recognises every file a heap. release ships', () => {
    expect(classifyAsset(asset('heap-v0.5.1-windows-setup.exe'))).toMatchObject({ os: 'windows', label: 'Installer', rank: 0 });
    expect(classifyAsset(asset('heap-v0.5.1-windows-portable.zip'))).toMatchObject({ os: 'windows', label: 'Portable' });
    expect(classifyAsset(asset('heap-v0.5.1-macos.dmg'))).toMatchObject({ os: 'macos' });
    expect(classifyAsset(asset('heap-v0.5.1-linux-x86_64.AppImage'))).toMatchObject({ os: 'linux', label: 'AppImage', rank: 0 });
  });

  it('ignores files it does not know', () => {
    expect(classifyAsset(asset('checksums.txt'))).toBeNull();
    // Qt 6.4 builds shipped up to 0.5.1; the UI does not run on them.
    expect(classifyAsset(asset('heap-v0.5.1-linux-amd64.deb'))).toBeNull();
    expect(classifyAsset(asset('heap-v0.5.1-linux-x86_64.tar.gz'))).toBeNull();
    expect(classifyAsset(asset('source.tar.gz'))).toBeNull();
  });
});

describe('assetsByOS', () => {
  it('groups the committed snapshot and puts the recommended file first', () => {
    const latest = (fallback as Release[])[0];
    const by = assetsByOS(latest);
    expect(by.windows[0].label).toBe('Installer');
    expect(by.macos).toHaveLength(1);
    expect(by.linux.map((a) => a.label)).toEqual(['AppImage']);
  });
});

describe('formatSize / versionOf', () => {
  it('formats like the download page shows it', () => {
    expect(formatSize(1_741_202)).toBe('1.7 MB');
    expect(formatSize(40_851_960)).toBe('40.9 MB');
    expect(formatSize(12_400)).toBe('12 KB');
    expect(versionOf('v0.5.1')).toBe('0.5.1');
  });
});

describe('parseNotes', () => {
  const body = [
    "## What's Changed",
    '* feat(undo): a real undo/redo stack by @sectapunterx in https://github.com/sectapunterx/heap/pull/131',
    '* fix(calendar): clamp every event write into the day by @sectapunterx in https://github.com/sectapunterx/heap/pull/124',
    '* Ticket enrichment: make a mirrored issue look like one by @sectapunterx in https://github.com/sectapunterx/heap/pull/108',
    '* ci: bump actions by @sectapunterx in https://github.com/sectapunterx/heap/pull/73',
    '',
    '**Full Changelog**: https://github.com/sectapunterx/heap/compare/v0.4.9...v0.5.0',
  ].join('\n');

  it('groups conventional commits and keeps the PR link', () => {
    const groups = parseNotes(body);
    expect(groups.map((g) => g.title)).toEqual(['Features', 'Fixes', 'Changes', 'Build & CI']);
    expect(groups[0].items[0]).toEqual({ scope: 'undo', text: 'A real undo/redo stack', pr: 131, prUrl: 'https://github.com/sectapunterx/heap/pull/131' });
    expect(groups[2].items[0].text).toBe('Ticket enrichment: make a mirrored issue look like one');
  });

  it('summarizes counts and handles empty notes', () => {
    expect(summarize(parseNotes(body))).toBe('1 features · 1 fixes · 1 changes · 1 build & ci');
    expect(parseNotes('**Full Changelog**: …')).toEqual([]);
    expect(summarize([])).toBe('Maintenance release');
  });
});
