// The one place the GitHub repository is named. The repository is still sectapunterx/heap until
// the owner renames it (APP-280); change REPO here and every download link, the releases API and
// the source links follow. The Pages base (/heap/) lives in astro.config.mjs.
export const REPO = 'sectapunterx/heap';
export const GITHUB_URL = `https://github.com/${REPO}`;
export const RELEASES_URL = `${GITHUB_URL}/releases`;
export const LATEST_URL = `${RELEASES_URL}/latest`;
export const LICENSE_URL = `${GITHUB_URL}/blob/master/LICENSE`;

/** Prefix a site-relative path with the deploy base (`/heap/`), keeping the trailing slash policy. */
export function url(path = ''): string {
  const base = import.meta.env.BASE_URL.replace(/\/+$/, '');
  const clean = path.replace(/^\/+/, '');
  if (!clean) return `${base}/`;
  const [pathname, hash = ''] = clean.split('#');
  const needsSlash = pathname !== '' && !pathname.endsWith('/') && !/\.[a-z0-9]+$/i.test(pathname);
  return `${base}/${pathname}${needsSlash ? '/' : ''}${hash ? `#${hash}` : ''}`;
}
