// Rewrites links inside docs/*.md so they work on the site as well as on GitHub:
//   HOTKEYS.md#notes-editor  -> /heap/docs/hotkeys/#notes-editor
//   ../src/foo.cpp           -> https://github.com/sectapunterx/heap/blob/master/src/foo.cpp
//   ../packaging/linux/      -> https://github.com/sectapunterx/heap/tree/master/packaging/linux/
import { visit } from 'unist-util-visit';

const REPO_URL = 'https://github.com/sectapunterx/heap';

export function docSlug(file) {
  return file.replace(/\.md$/i, '').toLowerCase().replace(/_/g, '-');
}

export function rewriteDocHref(href, base = '') {
  if (!href || /^[a-z]+:/i.test(href) || href.startsWith('#') || href.startsWith('/')) return href;
  const [path, hash] = href.split('#');
  const anchor = hash ? `#${hash}` : '';
  if (/^[A-Za-z0-9_-]+\.md$/.test(path)) {
    return `${base}/docs/${docSlug(path)}/${anchor}`;
  }
  if (path.startsWith('../')) {
    const repoPath = path.replace(/^(\.\.\/)+/, '');
    const kind = repoPath.endsWith('/') ? 'tree' : 'blob';
    return `${REPO_URL}/${kind}/master/${repoPath}${anchor}`;
  }
  return href;
}

export default function remarkDocLinks(options = {}) {
  const base = (options.base ?? '').replace(/\/+$/, '');
  return (tree) => {
    visit(tree, ['link', 'definition'], (node) => {
      node.url = rewriteDocHref(node.url, base);
    });
  };
}
