// Build-time index for the site-wide Ctrl+K palette: every page, every
// feature area, every doc and the h2 sections inside each doc.
import { getCollection, render } from 'astro:content';
import { DOCS } from '../data/docs';
import { FEATURE_AREAS } from '../data/features';
import { url } from './site';

export interface PaletteItem {
  id: string;
  title: string;
  keywords?: string;
  group: 'Pages' | 'Features' | 'Docs' | 'Sections';
  href: string;
}

let cache: Promise<PaletteItem[]> | undefined;

async function build(): Promise<PaletteItem[]> {
  const items: PaletteItem[] = [
    { id: 'home', title: 'Home', group: 'Pages', href: url() },
    { id: 'demo', title: 'Try it in the browser', keywords: 'demo sandbox playground', group: 'Pages', href: url('demo') },
    { id: 'download', title: 'Download', keywords: 'install windows macos linux appimage deb dmg scoop', group: 'Pages', href: url('download') },
    { id: 'compare', title: 'Compare', keywords: 'jira trello notion obsidian alternative', group: 'Pages', href: url('compare') },
    { id: 'privacy', title: 'Privacy & local data', keywords: 'telemetry network data state.json', group: 'Pages', href: url('privacy') },
    { id: 'changelog', title: 'Changelog', keywords: 'releases what is new version', group: 'Pages', href: url('changelog') },
    { id: 'docs', title: 'Documentation', group: 'Pages', href: url('docs') },
  ];
  for (const a of FEATURE_AREAS) {
    items.push({ id: `f-${a.slug}`, title: `${a.label} — ${a.title.split('— ')[1] ?? a.title}`, keywords: a.summary, group: 'Features', href: url(`features/${a.slug}`) });
  }
  const entries = await getCollection('docs');
  for (const meta of DOCS) {
    const entry = entries.find((e) => e.id === meta.slug);
    items.push({ id: `d-${meta.slug}`, title: meta.label, keywords: meta.blurb, group: 'Docs', href: url(`docs/${meta.slug}`) });
    if (!entry) continue;
    const { headings } = await render(entry);
    for (const h of headings.filter((x) => x.depth === 2 || x.depth === 3)) {
      items.push({ id: `s-${meta.slug}-${h.slug}`, title: `${meta.label} › ${h.text}`, group: 'Sections', href: url(`docs/${meta.slug}#${h.slug}`) });
    }
  }
  return items;
}

export function getPaletteItems(): Promise<PaletteItem[]> {
  cache ??= build();
  return cache;
}
