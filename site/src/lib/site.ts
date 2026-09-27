export const REPO = 'sectapunterx/heap';
export const GITHUB_URL = `https://github.com/${REPO}`;
export const RELEASES_URL = `${GITHUB_URL}/releases`;
export const ISSUES_URL = `${GITHUB_URL}/issues`;

/** Prefix a site-relative path with the deploy base (`/heap/`), keeping the trailing slash policy. */
export function url(path = ''): string {
  const base = import.meta.env.BASE_URL.replace(/\/+$/, '');
  const clean = path.replace(/^\/+/, '');
  if (!clean) return `${base}/`;
  const [pathname, hash = ''] = clean.split('#');
  const needsSlash = pathname !== '' && !pathname.endsWith('/') && !/\.[a-z0-9]+$/i.test(pathname);
  return `${base}/${pathname}${needsSlash ? '/' : ''}${hash ? `#${hash}` : ''}`;
}

export interface NavItem {
  id: string;
  label: string;
  href: string;
}

export const NAV: NavItem[] = [
  { id: 'features', label: 'Features', href: 'features' },
  { id: 'demo', label: 'Try it', href: 'demo' },
  { id: 'compare', label: 'Compare', href: 'compare' },
  { id: 'privacy', label: 'Privacy', href: 'privacy' },
  { id: 'docs', label: 'Docs', href: 'docs' },
  { id: 'changelog', label: 'Changelog', href: 'changelog' },
];
