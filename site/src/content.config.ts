import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { DOCS } from './data/docs';
import { docSlug } from './lib/remark-doc-links.mjs';

// The markdown in the repository's docs/ folder is the single source; the site
// renders it as-is (links are rewritten by remark-doc-links).
const docs = defineCollection({
  loader: glob({
    pattern: DOCS.map((d) => d.file),
    base: '../docs',
    generateId: ({ entry }) => docSlug(entry),
  }),
});

export const collections = { docs };
