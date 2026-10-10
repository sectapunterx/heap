import type { DesktopOS } from './os';

export interface Asset {
  name: string;
  size: number;
  url: string;
}

export interface Release {
  tag: string;
  name: string;
  date: string;
  body: string;
  url: string;
  prerelease: boolean;
  assets: Asset[];
}

/** Which kind of download a release file is; the page names it in its own language. */
export type AssetKind = 'installer' | 'portable' | 'dmg' | 'appimage';

export interface ClassifiedAsset extends Asset {
  os: DesktopOS;
  kind: AssetKind;
  /** Lower comes first within an OS. */
  rank: number;
}

// By suffix, so both the heap-* files of 0.7.x and the lowkey-* files from 0.8.0 on are found.
// Releases up to 0.5.1 also carried a .deb and a tarball built against Qt 6.4, on which the UI
// does not run; they are deliberately not offered. Checksums and the SBOM are not downloads.
const KINDS: Array<{ test: RegExp; os: DesktopOS; kind: AssetKind; rank: number }> = [
  { test: /windows-setup\.exe$/i, os: 'windows', kind: 'installer', rank: 0 },
  { test: /windows-portable\.zip$/i, os: 'windows', kind: 'portable', rank: 1 },
  { test: /\.dmg$/i, os: 'macos', kind: 'dmg', rank: 0 },
  { test: /\.appimage$/i, os: 'linux', kind: 'appimage', rank: 0 },
];

export function classifyAsset(asset: Asset): ClassifiedAsset | null {
  const k = KINDS.find((x) => x.test.test(asset.name));
  return k ? { ...asset, os: k.os, kind: k.kind, rank: k.rank } : null;
}

export function assetsByOS(release: Release): Record<DesktopOS, ClassifiedAsset[]> {
  const out: Record<DesktopOS, ClassifiedAsset[]> = { windows: [], macos: [], linux: [] };
  for (const a of release.assets) {
    const c = classifyAsset(a);
    if (c) out[c.os].push(c);
  }
  for (const list of Object.values(out)) list.sort((a, b) => a.rank - b.rank);
  return out;
}

/** Megabytes the way the page prints them: 39 715 428 bytes → "39.7". */
export function megabytes(bytes: number): string {
  return (bytes / 1_000_000).toFixed(1);
}

export function versionOf(tag: string): string {
  return tag.replace(/^v/i, '');
}

export function formatDate(iso: string, lang: 'ru' | 'en'): string {
  return new Date(iso).toLocaleDateString(lang === 'ru' ? 'ru-RU' : 'en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });
}

/** The file the big download button offers on each platform. */
export function primaryAssets(release: Release): Partial<Record<DesktopOS, { url: string; name: string }>> {
  const by = assetsByOS(release);
  const out: Partial<Record<DesktopOS, { url: string; name: string }>> = {};
  for (const os of ['windows', 'macos', 'linux'] as const) {
    const a = by[os][0];
    if (a) out[os] = { url: a.url, name: a.name };
  }
  return out;
}
