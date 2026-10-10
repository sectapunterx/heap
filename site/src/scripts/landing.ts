// The home page: live screens, scroll scenes, the capture demo, the git scene, the key cards,
// the style divider and the dock. Shared behaviour (smooth scroll, search, downloads) is in site.ts.
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import { $, $$, EN, esc, reduce, scrollToEl, typing } from './site';

// [one, few, many] in Russian; English only uses one / many
const plural = (n: number, f: [string, string, string]) =>
  EN
    ? f[n === 1 ? 0 : 2]
    : f[n % 10 === 1 && n % 100 !== 11 ? 0 : n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20) ? 1 : 2];

/* runtime strings of the demo; page copy lives in src/data/i18n.ts */
const T = EN
  ? {
      seed: [['Reply to review #482', 'GitHub', 'today'], ['Login rate limit', 'Jira', 'P1'], ['Update dependencies', '#infra', 'Fri']],
      chip: { date: 'date', time: 'time', tag: 'label', pri: 'priority' },
      task: ['task', 'tasks', 'tasks'] as [string, string, string],
      done: 'done',
      allDone: 'all done',
      closed: ['task closed', 'tasks closed', 'tasks closed'] as [string, string, string],
      secs: ['second', 'seconds', 'seconds'] as [string, string, string],
      in: 'in',
      tick: ['Done', 'Undo'],
    }
  : {
      seed: [['Ответить на ревью #482', 'GitHub', 'сегодня'], ['Rate limit для логина', 'Jira', 'P1'], ['Обновить зависимости', '#infra', 'пт']],
      chip: { date: 'дата', time: 'время', tag: 'тег', pri: 'приоритет' },
      task: ['задача', 'задачи', 'задач'] as [string, string, string],
      done: 'готово',
      allDone: 'всё сделано',
      closed: ['задача закрыта', 'задачи закрыты', 'задач закрыто'] as [string, string, string],
      secs: ['секунду', 'секунды', 'секунд'] as [string, string, string],
      in: 'за',
      tick: ['Готово', 'Вернуть'],
    };

/* ---------- live screens: scale the 1440×900 canvas to cover its frame ---------- */
const fit = new ResizeObserver((entries) => {
  for (const e of entries) {
    const { width, height } = e.contentRect;
    if (!width) continue;
    const el = e.target as HTMLElement;
    const crop = el.dataset.crop?.split(' ').map(Number);
    if (crop) {
      const k = width / crop[2];
      el.style.setProperty('--k', String(k));
      el.style.setProperty('--tx', -crop[0] * k + 'px');
      el.style.setProperty('--ty', -crop[1] * k + 'px');
    } else el.style.setProperty('--k', String(Math.max(width / 1440, height / 900)));
  }
});
$$('.screen').forEach((s) => fit.observe(s));

/* ---------- hero ---------- */
if (!reduce) {
  gsap
    .timeline({ defaults: { ease: 'expo.out' } })
    .from('.hero .lines > span > span', { yPercent: 105, duration: 1.4, stagger: 0.12 }, 0.1)
    .from('.hero .fade', { y: 18, opacity: 0, duration: 1.2, stagger: 0.1 }, 0.5)
    .from('.hero-shot', { y: 80, opacity: 0, duration: 1.6 }, 0.7);
  gsap.fromTo(
    '.hero-shot .screen',
    { rotateX: 20, scale: 0.9 },
    { rotateX: 0, scale: 1, ease: 'none', scrollTrigger: { trigger: '.hero-shot', start: 'top 92%', end: 'top 20%', scrub: true } },
  );
}

/* ---------- reveals ---------- */
if (!reduce) {
  $$('.reveal').forEach((el) => gsap.from(el, { y: 32, opacity: 0, duration: 1.1, ease: 'expo.out', scrollTrigger: { trigger: el, start: 'top 88%' } }));
}

/* ---------- noise turns into one calm list ---------- */
const field = $('.noise-field');
const pings = $$('.ping', field);
if (reduce) {
  gsap.set(pings, { opacity: 0 });
  gsap.set(['.n-a'], { opacity: 0 });
  gsap.set(['.n-b', '.calm'], { opacity: 1 });
} else {
  const toCentre = (axis: 'x' | 'y') => (_: number, el: HTMLElement) => {
    const f = field.getBoundingClientRect(),
      r = el.getBoundingClientRect();
    return axis === 'x' ? f.left + f.width / 2 - (r.left + r.width / 2) : f.top + f.height / 2 - (r.top + r.height / 2);
  };
  gsap
    .timeline({ scrollTrigger: { trigger: '.noise-stage', start: 'top top', end: '+=170%', pin: true, scrub: 0.8, invalidateOnRefresh: true } })
    .from(pings, { opacity: 0, y: 40, scale: 0.92, stagger: 0.04, duration: 0.25, ease: 'power2.out' }, 0)
    .to(pings, { rotate: (i) => (i % 2 ? 2.5 : -2.5), duration: 0.2, ease: 'sine.inOut' }, 0.3)
    .to(pings, { x: toCentre('x'), y: toCentre('y'), scale: 0.35, opacity: 0, rotate: 0, stagger: 0.015, duration: 0.3, ease: 'power3.in' }, 0.55)
    .to('.n-a', { opacity: 0, y: -16, duration: 0.15 }, 0.58)
    .fromTo('.n-b', { opacity: 0, y: 16 }, { opacity: 1, y: 0, duration: 0.2 }, 0.72)
    .fromTo('.calm', { opacity: 0, scale: 0.94 }, { opacity: 1, scale: 1, duration: 0.25, ease: 'expo.out' }, 0.78)
    .from('.calm .row', { opacity: 0, x: -12, stagger: 0.04, duration: 0.15 }, 0.86)
    .to({}, { duration: 0.15 });
}

/* ---------- live demo: quick capture with the words parsed into chips ---------- */
type Task = { title: string; meta: string[]; done: boolean };
const demo = $('.demo');
const input = $<HTMLInputElement>('.cap-in', demo);
const chipsEl = $('.chips', demo);
const listEl = $('.list', demo);
const emptyEl = $('.empty', demo);
const factsEl = $('.demo-facts', demo);
const tasks: Task[] = T.seed.map(([title, ...meta]) => ({ title, meta, done: false }));
let cursor = 0;
let firstTouch = 0;
let closed = 0;
let lastDone = { i: -1, at: 0 };

const DAYS: Record<string, string> = {
  пн: 'пн', понедельник: 'пн', вт: 'вт', вторник: 'вт', ср: 'ср', среда: 'ср', среду: 'ср', чт: 'чт', четверг: 'чт',
  пт: 'пт', пятница: 'пт', пятницу: 'пт', сб: 'сб', суббота: 'сб', субботу: 'сб', вс: 'вс', воскресенье: 'вс',
  mon: 'Mon', monday: 'Mon', tue: 'Tue', tuesday: 'Tue', wed: 'Wed', wednesday: 'Wed', thu: 'Thu', thursday: 'Thu',
  fri: 'Fri', friday: 'Fri', sat: 'Sat', saturday: 'Sat', sun: 'Sun', sunday: 'Sun',
};
function parse(raw: string) {
  const words = raw.trim().split(/\s+/).filter(Boolean);
  const r = { title: [] as string[], date: '', time: '', tags: [] as string[], pri: '' };
  for (let i = 0; i < words.length; i++) {
    const w = words[i],
      lw = w.toLowerCase().replace(/[.,]$/, ''),
      next = (words[i + 1] ?? '').toLowerCase();
    if (['сегодня', 'завтра', 'послезавтра', 'today', 'tomorrow'].includes(lw)) r.date = lw;
    else if (DAYS[lw]) r.date = DAYS[lw];
    else if ((lw === 'в' || lw === 'at') && /^\d{1,2}([:.]\d{2})?(am|pm)?$/.test(next)) continue;
    else if (/^\d{1,2}(am|pm)$/.test(lw)) {
      const h = (Number(lw.slice(0, -2)) % 12) + (lw.endsWith('pm') ? 12 : 0);
      r.time = String(h).padStart(2, '0') + ':00';
    } else if (/^\d{1,2}[:.]\d{2}$/.test(lw)) r.time = lw.replace('.', ':').padStart(5, '0');
    else if (/^\d{1,2}$/.test(lw) && ['в', 'at'].includes(words[i - 1]?.toLowerCase()) && Number(lw) < 24) r.time = lw.padStart(2, '0') + ':00';
    else if (lw === 'in' && /^\d+$/.test(next) && /^days?$/.test((words[i + 2] ?? '').toLowerCase())) {
      r.date = `in ${next} d`;
      i += 2;
    } else if (lw === 'next' && next === 'week') {
      r.date = 'next week';
      i++;
    } else if (lw === 'через' && /^\d+$/.test(next) && /^д(н|ен|ня)/.test((words[i + 2] ?? '').toLowerCase())) {
      r.date = `через ${next} дн.`;
      i += 2;
    } else if (lw === 'через' && next === 'неделю') {
      r.date = 'через неделю';
      i++;
    } else if (/^#[\p{L}\d_-]+$/u.test(w)) r.tags.push(w);
    else if (/^p[0-3]$/i.test(lw)) r.pri = 'P' + lw[1];
    else r.title.push(w);
  }
  return { ...r, title: r.title.join(' ') };
}
const metaOf = (p: ReturnType<typeof parse>) => [p.date, p.time, ...p.tags, p.pri].filter(Boolean);

function renderChips() {
  const p = parse(input.value);
  const parts: [string, string][] = [];
  if (p.date) parts.push([T.chip.date, p.date]);
  if (p.time) parts.push([T.chip.time, p.time]);
  p.tags.forEach((t) => parts.push([T.chip.tag, t]));
  if (p.pri) parts.push([T.chip.pri, p.pri]);
  const before = chipsEl.children.length;
  chipsEl.innerHTML = parts.map(([k, v]) => `<span class="chip"><i>${k}</i>${esc(v)}</span>`).join('');
  if (!reduce && parts.length > before) gsap.from(chipsEl.lastElementChild, { y: 6, opacity: 0, duration: 0.4, ease: 'expo.out' });
}
function renderFacts() {
  const open = tasks.filter((t) => !t.done).length;
  factsEl.textContent = open ? `${open} ${plural(open, T.task)} · ${closed} ${T.done}` : T.allDone;
}
function render() {
  listEl.innerHTML = tasks
    .map(
      (t, i) => `
    <li class="task${t.done ? ' done' : ''}${i === cursor ? ' cur' : ''}" data-i="${i}">
      <button class="tick" aria-label="${t.done ? T.tick[1] : T.tick[0]}: ${esc(t.title)}"></button>
      <span class="tt">${esc(t.title)}</span>
      <span class="tm">${t.meta.map((m) => `<span class="chip">${esc(m)}</span>`).join('')}</span>
    </li>`,
    )
    .join('');
  renderFacts();
  const allDone = tasks.length > 0 && tasks.every((t) => t.done);
  if (allDone && emptyEl.hidden) {
    const secs = Math.max(1, Math.round((Date.now() - firstTouch) / 1000));
    $('.empty-s', emptyEl).textContent = `${closed} ${plural(closed, T.closed)} ${T.in} ${secs} ${plural(secs, T.secs)}.`;
    emptyEl.hidden = false;
    gsap.to(listEl, { height: 0, opacity: 0, duration: reduce ? 0 : 0.6, ease: 'expo.inOut', delay: reduce ? 0 : 0.5 });
    if (!reduce) gsap.from(emptyEl.children, { y: 16, opacity: 0, stagger: 0.1, duration: 0.9, ease: 'expo.out', delay: 0.8 });
  } else if (!allDone && !emptyEl.hidden) {
    emptyEl.hidden = true;
    gsap.to(listEl, { height: 'auto', opacity: 1, duration: reduce ? 0 : 0.5, ease: 'expo.out' });
  }
}
function toggle(i: number, fromKey = false) {
  const t = tasks[i];
  if (!t) return;
  // as in the app: a second d on the same task within half a second is a Vim "dd", not an undo
  if (fromKey && lastDone.i === i && Date.now() - lastDone.at < 500) return;
  if (!firstTouch) firstTouch = Date.now();
  t.done = !t.done;
  if (t.done) lastDone = { i, at: Date.now() };
  closed += t.done ? 1 : -1;
  cursor = i;
  render();
  const li = listEl.children[i];
  if (li && !reduce) gsap.fromTo($('.tick', li), { scale: 0.6 }, { scale: 1, duration: 0.5, ease: 'back.out(3)' });
}
function add() {
  const p = parse(input.value);
  if (!p.title) return;
  if (!firstTouch) firstTouch = Date.now();
  tasks.unshift({ title: p.title, meta: metaOf(p), done: false });
  cursor = 0;
  input.value = '';
  renderChips();
  render();
  if (!reduce) gsap.from(listEl.firstElementChild, { height: 0, opacity: 0, y: -8, duration: 0.6, ease: 'expo.out' });
}
input.addEventListener('input', renderChips);
input.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    e.preventDefault();
    add();
  }
  if (e.key === 'Escape') {
    input.blur();
    demo.focus({ preventScroll: true });
  }
});
listEl.addEventListener('click', (e) => {
  const li = (e.target as HTMLElement).closest<HTMLElement>('.task');
  if (!li) return;
  const i = Number(li.dataset.i);
  if ((e.target as HTMLElement).closest('.tick')) toggle(i);
  else {
    cursor = i;
    render();
  }
});
let demoActive = false;
ScrollTrigger.create({
  trigger: demo,
  start: 'top 75%',
  end: 'bottom 25%',
  onToggle: (s) => {
    demoActive = s.isActive;
    demo.classList.toggle('active', s.isActive);
  },
});
render();

/* ---------- a day with lowkey ---------- */
const moments = $$('.moments li');
const dayImgs = $$('.day-right .screen');
const clock = $('.clock');
let dayIdx = 0;
const setMoment = (i: number) => {
  if (i === dayIdx) return;
  dayIdx = i;
  moments.forEach((m, j) => m.classList.toggle('on', j === i));
  dayImgs.forEach((m, j) => m.classList.toggle('on', j === i));
  const t = $('.t', moments[i]).textContent!;
  if (reduce) {
    clock.textContent = t;
    return;
  }
  gsap
    .timeline()
    .to(clock, { y: -12, opacity: 0, duration: 0.18, ease: 'power2.in' })
    .add(() => {
      clock.textContent = t;
    })
    .fromTo(clock, { y: 12 }, { y: 0, opacity: 1, duration: 0.5, ease: 'expo.out' });
};
gsap.matchMedia().add('(min-width: 901px)', () => {
  ScrollTrigger.create({
    trigger: '.day-pin',
    start: 'top top',
    end: () => '+=' + innerHeight * moments.length * 0.7,
    pin: true,
    onUpdate: (s) => setMoment(Math.min(moments.length - 1, Math.floor(s.progress * moments.length))),
  });
});

/* ---------- key cards light up as you press their keys ---------- */
const keyCards = $$('.keycard');
const hit = (c: HTMLElement) => {
  c.classList.remove('hit');
  void c.offsetWidth;
  c.classList.add('hit');
  setTimeout(() => c.classList.remove('hit'), 260);
};
keyCards.forEach((c) => c.addEventListener('click', () => hit(c)));
addEventListener('keydown', (e) => {
  const code = (e.ctrlKey || e.metaKey ? 'ctrl+' : '') + (e.shiftKey ? 'shift+' : '') + e.code;
  if (!typing(e) || code === 'ctrl+KeyK') {
    const card = keyCards.find((c) => (c.dataset.codes ?? '').split(' ').includes(code));
    if (card) hit(card);
  }
  if (typing(e) || !demoActive || e.ctrlKey || e.metaKey || e.altKey) return;
  if (e.code === 'KeyJ') {
    cursor = Math.min(tasks.length - 1, cursor + 1);
    render();
  } else if (e.code === 'KeyK') {
    cursor = Math.max(0, cursor - 1);
    render();
  } else if (e.code === 'KeyD') toggle(cursor, true);
});

/* ---------- git: switch a branch, the matching card is marked ---------- */
const gitStage = $('[data-git]');
const gitCmd = $('[data-git-cmd]', gitStage);
let gitDone = false;
const runGit = () => {
  if (gitDone) return;
  gitDone = true;
  const text = gitCmd.dataset.text!;
  const finish = () => {
    gitCmd.textContent = text;
    $('[data-git-out]', gitStage).hidden = false;
    const head = $('[data-git-head]', gitStage);
    head.textContent = head.dataset.branch!;
    head.classList.add('on');
    $$('[data-git-on]', gitStage).forEach((el) => (el.hidden = false));
    $$('[data-git-off]', gitStage).forEach((el) => (el.hidden = true));
    const meta = $('[data-git-meta]', gitStage);
    meta.textContent = meta.dataset.after!;
    $('[data-git-card]', gitStage).classList.add('on');
    $('.term-caret', gitStage)?.remove();
  };
  if (reduce) return finish();
  let i = 0;
  const step = () => {
    gitCmd.textContent = text.slice(0, ++i);
    if (i < text.length) setTimeout(step, 28 + Math.random() * 40);
    else setTimeout(finish, 350);
  };
  step();
};
$('[data-git-run]').addEventListener('click', runGit);
ScrollTrigger.create({ trigger: gitStage, start: 'top 70%', once: true, onEnter: () => setTimeout(runGit, 400) });

/* ---------- quiet vs bold ---------- */
const cmp = $('.compare');
const handle = $('.handle', cmp);
const pos = { v: 50 };
const applyPos = () => {
  cmp.style.setProperty('--pos', pos.v + '%');
  handle.setAttribute('aria-valuenow', String(Math.round(pos.v)));
};
const setPos = (v: number, animate = false) => {
  v = Math.max(0, Math.min(100, v));
  if (animate && !reduce) gsap.to(pos, { v, duration: 0.9, ease: 'expo.inOut', onUpdate: applyPos, overwrite: true });
  else {
    gsap.killTweensOf(pos);
    pos.v = v;
    applyPos();
  }
};
const xOf = (e: PointerEvent) => {
  const r = cmp.getBoundingClientRect();
  return ((e.clientX - r.left) / r.width) * 100;
};
let drag = false;
cmp.addEventListener('pointerdown', (e) => {
  drag = true;
  cmp.setPointerCapture(e.pointerId);
  setPos(xOf(e), true);
});
cmp.addEventListener('pointermove', (e) => drag && setPos(xOf(e)));
cmp.addEventListener('pointerup', () => (drag = false));
handle.addEventListener('keydown', (e) => {
  const step = e.shiftKey ? 10 : 2;
  if (e.key === 'ArrowLeft') {
    setPos(pos.v - step);
    e.preventDefault();
  }
  if (e.key === 'ArrowRight') {
    setPos(pos.v + step);
    e.preventDefault();
  }
});
if (!reduce)
  ScrollTrigger.create({
    trigger: cmp,
    start: 'top 65%',
    once: true,
    onEnter: () => {
      setPos(75, true);
      setTimeout(() => setPos(50, true), 1000);
    },
  });

/* ---------- dock: which section you are in, and the way out ---------- */
const sections = $$<HTMLElement>('main section[data-name]');
const dock = $('.dock');
const dockN = $('.dock-n', dock);
const dockName = $('.dock-name', dock);
let secIdx = 0;
const setSection = (i: number) => {
  if (i === secIdx) return;
  secIdx = i;
  const apply = () => {
    dockN.textContent = String(i + 1).padStart(2, '0');
    dockName.textContent = sections[i].dataset.name!;
  };
  if (reduce) return apply();
  gsap
    .timeline()
    .to([dockN, dockName], { y: -8, opacity: 0, duration: 0.15 })
    .add(apply)
    .fromTo([dockN, dockName], { y: 8 }, { y: 0, opacity: 1, duration: 0.4, ease: 'expo.out' });
};
sections.forEach((s, i) => {
  ScrollTrigger.create({ trigger: s, start: 'top 50%', end: 'bottom 50%', onToggle: (st) => st.isActive && setSection(i) });
});
$('.dock-where', dock).addEventListener('click', () => scrollToEl(sections[Math.min(sections.length - 1, secIdx + 1)]));
gsap.to('.dock-progress i', { scaleX: 1, ease: 'none', scrollTrigger: { start: 0, end: 'max', scrub: 0.3 } });
let pastHero = false,
  atEnd = false;
const syncDock = () => dock.classList.toggle('show', pastHero && !atEnd);
ScrollTrigger.create({ trigger: '.hero .cta', start: 'bottom top', end: 'max', onToggle: (s) => { pastHero = s.isActive; syncDock(); } });
ScrollTrigger.create({ trigger: '#get .cta', start: 'top bottom', end: 'max', onToggle: (s) => { atEnd = s.isActive; syncDock(); } });
