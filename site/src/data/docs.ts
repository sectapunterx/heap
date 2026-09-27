// Which files from the repository's docs/ folder the site publishes, in what
// order and under which heading. ANNOUNCEMENT.md is a press draft, not docs.
export interface DocMeta {
  slug: string;
  file: string;
  label: string;
  blurb: string;
}

export interface DocGroup {
  title: string;
  docs: DocMeta[];
}

export const DOC_GROUPS: DocGroup[] = [
  {
    title: 'Start',
    docs: [
      { slug: 'tutorial', file: 'TUTORIAL.md', label: 'Your first day', blurb: 'A guided walk through the board, calendar, notes and search.' },
      { slug: 'data', file: 'DATA.md', label: 'Data & backups', blurb: 'Where your data lives, how backups work, moving between machines.' },
    ],
  },
  {
    title: 'Reference',
    docs: [
      { slug: 'hotkeys', file: 'HOTKEYS.md', label: 'Keyboard reference', blurb: 'Every default shortcut — all of them rebindable.' },
      { slug: 'integrations', file: 'INTEGRATIONS.md', label: 'Integrations', blurb: 'Connecting GitHub, GitLab, Jira, Trello and the rest.' },
      { slug: 'oauth-setup', file: 'OAUTH-SETUP.md', label: 'OAuth setup', blurb: 'Registering the one-click browser sign-in for each tracker.' },
    ],
  },
  {
    title: 'Shipping',
    docs: [
      { slug: 'distribution', file: 'DISTRIBUTION.md', label: 'Distribution', blurb: 'Scoop, winget and Flathub manifests.' },
      { slug: 'packaging', file: 'PACKAGING.md', label: 'Packaging & release', blurb: 'How the release workflow builds every installer.' },
    ],
  },
];

export const DOCS: DocMeta[] = DOC_GROUPS.flatMap((g) => g.docs);

export function docBySlug(slug: string): DocMeta | undefined {
  return DOCS.find((d) => d.slug === slug);
}
