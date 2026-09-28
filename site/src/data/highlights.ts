// Hand-written one-liners for releases. GitHub's generated notes list PRs;
// these say what the release means. Add one when you tag a release — the
// changelog falls back to counting the notes when a version has none.
export const HIGHLIGHTS: Record<string, { headline: string; badge?: string }> = {
  'v0.5.1': { headline: 'Closes the 0.5.0 audit list.' },
  'v0.5.0': { headline: 'Undo and redo, recurring events, and many notes with links between them.', badge: 'Undo/redo, recurring events, linked notes' },
  'v0.4.9': { headline: 'Tracker issues look and behave like the real thing.' },
  'v0.4.8': { headline: 'Lossless, time-aware task storage and a round of UI fixes.' },
  'v0.4.5': { headline: 'An interactive first-run guide you can skip and replay.' },
};
