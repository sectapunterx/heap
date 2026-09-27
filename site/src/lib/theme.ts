/** Flip the site theme — the same switch as the one in the header. */
export function toggleTheme(): 'light' | 'dark' {
  const root = document.documentElement;
  const next = root.dataset.theme === 'light' ? 'dark' : 'light';
  root.dataset.theme = next;
  try {
    localStorage.setItem('heap-theme', next);
  } catch {
    /* storage blocked — the choice lasts for this page only */
  }
  window.dispatchEvent(new CustomEvent('heap:theme', { detail: next }));
  return next;
}
