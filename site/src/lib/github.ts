// Build-time only: pulls releases from the GitHub API so the download page and
// changelog follow each release. Falls back to a committed snapshot when the
// API is unreachable or rate-limited, so a flaky network never breaks a deploy.
import fallback from '../data/releases.fallback.json';
import { REPO } from './site';
import type { Release } from './releases';

interface ApiRelease {
  tag_name: string;
  name: string | null;
  published_at: string;
  body: string | null;
  html_url: string;
  prerelease: boolean;
  draft: boolean;
  assets: Array<{ name: string; size: number; browser_download_url: string }>;
}

let cache: Promise<Release[]> | undefined;

async function fetchReleases(): Promise<Release[]> {
  const headers: Record<string, string> = {
    Accept: 'application/vnd.github+json',
    'User-Agent': 'heap-site-build',
  };
  const token = process.env.GITHUB_TOKEN;
  if (token) headers.Authorization = `Bearer ${token}`;
  try {
    const res = await fetch(`https://api.github.com/repos/${REPO}/releases?per_page=30`, { headers });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = (await res.json()) as ApiRelease[];
    const releases = data
      .filter((r) => !r.draft)
      .map((r) => ({
        tag: r.tag_name,
        name: r.name ?? r.tag_name,
        date: r.published_at,
        body: r.body ?? '',
        url: r.html_url,
        prerelease: r.prerelease,
        assets: r.assets.map((a) => ({ name: a.name, size: a.size, url: a.browser_download_url })),
      }));
    if (!releases.length) throw new Error('no releases');
    return releases;
  } catch (err) {
    console.warn(`[heap-site] GitHub releases unavailable (${(err as Error).message}); using the committed snapshot.`);
    return fallback as Release[];
  }
}

export function getReleases(): Promise<Release[]> {
  cache ??= fetchReleases();
  return cache;
}

export async function getLatestRelease(): Promise<Release> {
  const all = await getReleases();
  return all.find((r) => !r.prerelease) ?? all[0];
}
