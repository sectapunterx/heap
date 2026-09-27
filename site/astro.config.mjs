// @ts-check
import { defineConfig } from 'astro/config';
import react from '@astrojs/react';
import { unified } from '@astrojs/markdown-remark';
import remarkDocLinks from './src/lib/remark-doc-links.mjs';

// Served from GitHub Pages as a project site: https://sectapunterx.github.io/heap/
const base = '/heap';

export default defineConfig({
  site: 'https://sectapunterx.github.io',
  base,
  trailingSlash: 'always',
  integrations: [react()],
  prefetch: { prefetchAll: false, defaultStrategy: 'hover' },
  markdown: {
    processor: unified({ remarkPlugins: [[remarkDocLinks, { base }]] }),
    shikiConfig: { themes: { light: 'github-light', dark: 'github-dark' } },
  },
});
