// Picks the visitor's platform for download buttons and OS tabs. The server
// render shows Windows; this swaps in the detected OS once the page loads.
import { detectCurrentOS, OS_LABEL, type DesktopOS } from '../lib/os';

interface PrimaryAsset {
  url: string;
  name: string;
}

function selectTab(group: HTMLElement, os: string) {
  group.querySelectorAll<HTMLButtonElement>('[data-os-tab]').forEach((b) => {
    b.setAttribute('aria-selected', String(b.dataset.osTab === os));
    b.tabIndex = b.dataset.osTab === os ? 0 : -1;
  });
  group.querySelectorAll<HTMLElement>('[data-os-panel]').forEach((p) => {
    p.hidden = p.dataset.osPanel !== os;
  });
}

function init() {
  const detected = detectCurrentOS();
  const desktop: DesktopOS | null = detected && detected !== 'mobile' ? detected : null;

  document.querySelectorAll<HTMLAnchorElement>('[data-os-cta]').forEach((a) => {
    if (!desktop) return;
    const primary = JSON.parse(a.dataset.osCta || '{}') as Partial<Record<DesktopOS, PrimaryAsset>>;
    const asset = primary[desktop];
    if (!asset) return;
    a.href = asset.url;
    const label = a.querySelector('[data-os-label]');
    if (label) label.textContent = `Download for ${OS_LABEL[desktop]}`;
    a.title = asset.name;
  });

  document.querySelectorAll<HTMLElement>('[data-os-tabs]').forEach((group) => {
    if (desktop) selectTab(group, desktop);
    const tabs = [...group.querySelectorAll<HTMLButtonElement>('[data-os-tab]')];
    tabs.forEach((b, i) => {
      b.addEventListener('click', () => selectTab(group, b.dataset.osTab!));
      b.addEventListener('keydown', (e) => {
        if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return;
        e.preventDefault();
        const next = tabs[(i + (e.key === 'ArrowRight' ? 1 : tabs.length - 1)) % tabs.length];
        next.focus();
        selectTab(group, next.dataset.osTab!);
      });
    });
  });

  if (detected === 'mobile') {
    document.querySelectorAll<HTMLElement>('[data-mobile-note]').forEach((n) => (n.hidden = false));
    document.querySelectorAll<HTMLElement>('[data-desktop-only]').forEach((n) => (n.hidden = true));
  }

  document.querySelectorAll<HTMLButtonElement>('[data-share-link]').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const link = btn.dataset.shareLink || location.href;
      try {
        if (navigator.share) {
          await navigator.share({ title: 'heap. — download for your computer', url: link });
          return;
        }
        await navigator.clipboard.writeText(link);
        btn.textContent = 'Link copied';
      } catch {
        /* share sheet dismissed or clipboard blocked */
      }
    });
  });
}

init();
