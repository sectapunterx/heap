// Runs on every page: smooth scroll, the nav, the download buttons, copy buttons and the site
// search. Keys follow the app's keymap where the site has an equivalent: Ctrl K (and "/", the
// app's filter key) open the search, g g goes to the top and Shift G to the end of the page.
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import Lenis from 'lenis';
import { detectCurrentOS, OS_LABEL, type DesktopOS } from '../lib/os';

gsap.registerPlugin(ScrollTrigger);

export const $ = <T extends Element = HTMLElement>(s: string, r: ParentNode = document) => r.querySelector(s) as T;
export const $$ = <T extends Element = HTMLElement>(s: string, r: ParentNode = document) => [...r.querySelectorAll(s)] as T[];
export const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
export const typing = (e: Event) => !!(e.target as HTMLElement)?.closest?.('input, textarea, select, [contenteditable]');
export const EN = document.documentElement.lang === 'en';
export const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]!);

/* ---------- smooth scroll ---------- */
export const lenis = reduce ? null : new Lenis({ lerp: 0.085 });
if (lenis) {
  lenis.on('scroll', ScrollTrigger.update);
  gsap.ticker.add((t) => lenis.raf(t * 1000));
  gsap.ticker.lagSmoothing(0);
}
export const scrollToEl = (target: string | HTMLElement, offset = -40) => {
  const el = typeof target === 'string' ? $(target) : target;
  if (!el) return;
  if (lenis) lenis.scrollTo(el, { duration: 1.2, offset: target === '#top' ? 0 : offset });
  else el.scrollIntoView();
};
$$('[data-scroll]').forEach((a) =>
  a.addEventListener('click', (e) => {
    e.preventDefault();
    scrollToEl(a.dataset.scroll!);
  }),
);

/* ---------- nav ---------- */
const nav = $('.nav');
ScrollTrigger.create({ start: 24, end: 'max', onToggle: (s) => nav.classList.toggle('scrolled', s.isActive) });

/* ---------- download buttons: this platform's file, named in the button ---------- */
const downloadFor = EN ? 'Download for' : 'Скачать для';
const detected = detectCurrentOS();
const desktop: DesktopOS | null = detected && detected !== 'mobile' ? detected : null;
const primary = JSON.parse(document.body.dataset.primary || '{}') as Partial<Record<DesktopOS, { url: string; name: string }>>;
if (desktop && primary[desktop]) {
  const file = primary[desktop]!;
  $$<HTMLAnchorElement>('a[data-os-cta]').forEach((a) => {
    a.href = file.url;
    a.title = file.name;
    const label = $('[data-app]', a);
    if (label) label.textContent = `${downloadFor} ${OS_LABEL[desktop]}`;
  });
  $$(`[data-os="${desktop}"]`).forEach((el) => el.classList.add('mine'));
}
if (detected === 'mobile') $$('[data-mobile-note]').forEach((n) => (n.hidden = false));

/* ---------- copy buttons ---------- */
$$<HTMLButtonElement>('[data-copy]').forEach((b) =>
  b.addEventListener('click', async () => {
    const label = b.textContent;
    try {
      await navigator.clipboard.writeText(b.dataset.copy!);
      b.textContent = b.dataset.done!;
    } catch {
      /* the command stays selectable */
    }
    setTimeout(() => (b.textContent = label), 1600);
  }),
);

/* ---------- site search: headings, cards, questions ---------- */
const pal = $<HTMLDialogElement>('.palette');
const palIn = $<HTMLInputElement>('.pal-in', pal);
const palList = $('.pal-list', pal);
const norm = (v: string) => v.toLowerCase().replace(/ё/g, 'е').replace(/\s+/g, ' ').trim();
type Hit = { text: string; where: string; el: HTMLElement };
let index: Hit[] = [];
const buildIndex = () => {
  index = $$('main h1, main h2, main h3, main summary, .keycard .kt')
    .map((el) => {
      const sec = el.closest<HTMLElement>('section');
      return { text: (el.textContent ?? '').replace(/\s+/g, ' ').trim(), where: sec?.dataset.name ?? '', el };
    })
    .filter((h) => h.text && h.el.getClientRects().length > 0);
};
let hits: Hit[] = [];
let sel = 0;
const renderPal = () => {
  const words = norm(palIn.value).split(' ').filter(Boolean);
  hits = (
    words.length
      ? index.filter((h) => {
          const n = norm(h.text + ' ' + h.where);
          return words.every((w) => n.includes(w));
        })
      : index.filter((h) => h.el.tagName === 'H2')
  ).slice(0, 9);
  sel = Math.min(sel, Math.max(0, hits.length - 1));
  palList.innerHTML = hits.length
    ? hits.map((h, i) => `<li role="option" aria-selected="${i === sel}" data-i="${i}">${esc(h.text)}<small>${esc(h.where)}</small></li>`).join('')
    : `<li class="pal-empty">${esc(pal.dataset.empty!)}</li>`;
};
const go = (h?: Hit) => {
  if (!h) return;
  pal.close();
  const d = h.el.closest('details');
  if (d) d.open = true;
  scrollToEl((d ?? h.el) as HTMLElement, -120);
};
export function openPalette() {
  if (pal.open) return pal.close();
  buildIndex();
  palIn.value = '';
  sel = 0;
  renderPal();
  lenis?.stop();
  pal.showModal();
  palIn.focus();
}
pal.addEventListener('close', () => lenis?.start());
palIn.addEventListener('input', () => {
  sel = 0;
  renderPal();
});
palIn.addEventListener('keydown', (e) => {
  if (e.key === 'ArrowDown') {
    sel = Math.min(hits.length - 1, sel + 1);
    renderPal();
    e.preventDefault();
  } else if (e.key === 'ArrowUp') {
    sel = Math.max(0, sel - 1);
    renderPal();
    e.preventDefault();
  } else if (e.key === 'Enter') {
    e.preventDefault();
    go(hits[sel]);
  }
});
palList.addEventListener('click', (e) => {
  const li = (e.target as HTMLElement).closest<HTMLElement>('[data-i]');
  if (li) go(hits[Number(li.dataset.i)]);
});
pal.addEventListener('click', (e) => {
  if (e.target === pal) pal.close();
});
$('.search-btn').addEventListener('click', openPalette);

/* ---------- keys ---------- */
let gAt = 0;
addEventListener('keydown', (e) => {
  if ((e.ctrlKey || e.metaKey) && !e.shiftKey && !e.altKey && e.code === 'KeyK') {
    e.preventDefault();
    openPalette();
    return;
  }
  if (typing(e) || e.ctrlKey || e.metaKey || e.altKey || pal.open) return;
  if (e.code === 'Slash' && !e.shiftKey) {
    e.preventDefault();
    openPalette();
  } else if (e.code === 'KeyG' && e.shiftKey) {
    if (lenis) lenis.scrollTo('bottom', { duration: 1.2 });
    else scrollTo(0, document.body.scrollHeight);
  } else if (e.code === 'KeyG') {
    // g g: to the top; a single g waits a second for its pair, like the app's prefixes
    if (Date.now() - gAt < 1000) {
      gAt = 0;
      if (lenis) lenis.scrollTo(0, { duration: 1.2 });
      else scrollTo(0, 0);
    } else gAt = Date.now();
  }
});

addEventListener('load', () => ScrollTrigger.refresh());
