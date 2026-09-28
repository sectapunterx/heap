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

export interface ClassifiedAsset extends Asset {
  os: DesktopOS;
  /** Human label, e.g. "AppImage" or "Installer". */
  label: string;
  /** What the file is for, one line. */
  note: string;
  /** Lower comes first within an OS. */
  rank: number;
}

// Releases up to 0.5.1 also carried a .deb and a tarball built against Qt 6.4,
// on which the UI does not run; they are deliberately not offered.
const KINDS: Array<{ test: RegExp; os: DesktopOS; label: string; note: string; rank: number }> = [
  { test: /windows-setup\.exe$/i, os: 'windows', label: 'Installer', note: 'Start-menu entry and uninstaller', rank: 0 },
  { test: /windows-portable\.zip$/i, os: 'windows', label: 'Portable', note: 'Unzip and run from anywhere', rank: 1 },
  { test: /\.dmg$/i, os: 'macos', label: 'Disk image', note: 'Drag heap. into Applications', rank: 0 },
  { test: /\.appimage$/i, os: 'linux', label: 'AppImage', note: 'Qt inside — runs on any distro', rank: 0 },
];

export function classifyAsset(asset: Asset): ClassifiedAsset | null {
  const kind = KINDS.find((k) => k.test.test(asset.name));
  if (!kind) return null;
  return { ...asset, os: kind.os, label: kind.label, note: kind.note, rank: kind.rank };
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

export function formatSize(bytes: number): string {
  if (bytes < 1_000_000) return `${Math.max(1, Math.round(bytes / 1000))} KB`;
  return `${(bytes / 1_000_000).toFixed(1)} MB`;
}

export function versionOf(tag: string): string {
  return tag.replace(/^v/i, '');
}

export function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });
}

export interface NoteItem {
  scope: string;
  text: string;
  pr?: number;
  prUrl?: string;
}

export interface NoteGroup {
  title: string;
  items: NoteItem[];
}

const GROUP_TITLES: Record<string, string> = {
  feat: 'Features',
  fix: 'Fixes',
  perf: 'Performance',
  docs: 'Docs',
  build: 'Build & CI',
  ci: 'Build & CI',
  test: 'Tests',
  refactor: 'Internals',
  chore: 'Internals',
};
const GROUP_ORDER = ['Features', 'Fixes', 'Performance', 'Changes', 'Docs', 'Tests', 'Build & CI', 'Internals'];

/**
 * Turn GitHub's generated release notes ("* feat(scope): text by @x in <pr url>")
 * into groups by conventional-commit type. Lines that don't follow the
 * convention land under "Changes".
 */
export function parseNotes(body: string): NoteGroup[] {
  const groups = new Map<string, NoteItem[]>();
  for (const raw of body.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line.startsWith('* ') && !line.startsWith('- ')) continue;
    let text = line.slice(2).trim();
    let pr: number | undefined;
    let prUrl: string | undefined;
    const tail = text.match(/\s+by @[\w-]+ in (https:\/\/github\.com\/\S+\/pull\/(\d+))\s*$/);
    if (tail) {
      prUrl = tail[1];
      pr = Number(tail[2]);
      text = text.slice(0, tail.index).trim();
    }
    const cc = text.match(/^(\w+)(?:\(([^)]+)\))?!?:\s*(.+)$/);
    let title = 'Changes';
    let scope = '';
    if (cc && GROUP_TITLES[cc[1].toLowerCase()]) {
      title = GROUP_TITLES[cc[1].toLowerCase()];
      scope = cc[2] ?? '';
      text = cc[3];
    }
    text = text.charAt(0).toUpperCase() + text.slice(1);
    if (!groups.has(title)) groups.set(title, []);
    groups.get(title)!.push({ scope, text, pr, prUrl });
  }
  return [...groups.entries()]
    .sort(([a], [b]) => GROUP_ORDER.indexOf(a) - GROUP_ORDER.indexOf(b))
    .map(([title, items]) => ({ title, items }));
}

export function summarize(groups: NoteGroup[]): string {
  const parts = groups.map((g) => `${g.items.length} ${g.title.toLowerCase()}`);
  return parts.length ? parts.join(' · ') : 'Maintenance release';
}
