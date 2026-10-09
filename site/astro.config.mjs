// @ts-check
import { defineConfig } from 'astro/config';
import { GITHUB_URL } from './src/lib/site.ts';

// Served from GitHub Pages as a project site: https://sectapunterx.github.io/heap/
// The path follows the repository name; when the repository is renamed, change `base` here and
// REPO in src/lib/site.ts (the one place the repository is named).
const base = '/heap';
const repo = GITHUB_URL;

// Pages of the heap 0.7 site that the one-page site replaced. Old links (the README, posts)
// land on the closest place instead of a 404.
const docs = ['tutorial', 'hotkeys', 'integrations', 'oauth-setup', 'data', 'distribution', 'packaging'];
const areas = ['plan', 'time', 'know', 'connect', 'flow'];
const redirects = {
  '/demo': `${base}/#try`,
  '/privacy': `${base}/#trust`,
  '/compare': `${base}/`,
  '/features': `${base}/`,
  ...Object.fromEntries(areas.map((a) => [`/features/${a}`, `${base}/`])),
  '/docs': `${repo}/tree/master/docs`,
  ...Object.fromEntries(docs.map((d) => [`/docs/${d}`, `${repo}/tree/master/docs`])),
  '/changelog': `${repo}/releases`,
  '/brand': `${base}/`,
};

export default defineConfig({
  site: 'https://sectapunterx.github.io',
  base,
  trailingSlash: 'always',
  devToolbar: { enabled: false },
  redirects,
});
