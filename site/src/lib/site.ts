// The GitHub repository, from repo.mjs (GITHUB_REPOSITORY on Actions): every download link, the
// releases API and the source links follow it, and so does the Pages base in astro.config.mjs.
import { REPO as REPO_FULL } from '../../repo.mjs';
export const REPO: string = REPO_FULL;
export const GITHUB_URL = `https://github.com/${REPO}`;
export const RELEASES_URL = `${GITHUB_URL}/releases`;
export const LATEST_URL = `${RELEASES_URL}/latest`;
export const LICENSE_URL = `${GITHUB_URL}/blob/master/LICENSE`;

/** Prefix a site-relative path with the deploy base (`/<repository>/`), keeping the trailing slash policy. */
export function url(path = ''): string {
  const base = import.meta.env.BASE_URL.replace(/\/+$/, '');
  const clean = path.replace(/^\/+/, '');
  if (!clean) return `${base}/`;
  const [pathname, hash = ''] = clean.split('#');
  const needsSlash = pathname !== '' && !pathname.endsWith('/') && !/\.[a-z0-9]+$/i.test(pathname);
  return `${base}/${pathname}${needsSlash ? '/' : ''}${hash ? `#${hash}` : ''}`;
}
