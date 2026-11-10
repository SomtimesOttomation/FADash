// Shared building blocks: logos, status pills, match cards, the league bar, the club banner and week bar. Copied from
// NBADash's components.js (the gold standard) and turned into football: three-way results (draws are not dimmed),
// football clocks (HT, 45+2', FT, AET, pens), goal lines and league pills.
import { h, asArray, fmtTime, fmtDayShort, etKey, num } from './util.js';
import * as S from './store.js';
import { LEAGUES, leagueOf } from './leagues.js';

export const teamColor = (t) => (t && t.color ? `#${t.color}` : '#6b7280');

// ---- logo ------------------------------------------------------------------------------------
// NBADash loads each team's logo from the dash's cache host (https://<id>.cache/logos/...), saved there by its sync, and
// falls back to initials in the team colour. FADash draws a crest with the club's letters for now, so it downloads nothing.
//
// Wide logos: NBADash's logos are square, so they fill their box. Some leagues' artwork is wider than tall with built-in
// margins (the NHL's SVGs are 3:2), so it draws about a third smaller in the same box. Scale such logos up inside their
// box (NHLDash uses `transform: scale(1.32)` on the img) and keep `pointer-events: none` on the img and a higher z-index
// on the favourite star (.tile-star), or the enlarged logo covers the star and it can no longer be clicked.
function shield(abbr, color) {
  // A drawn crest with the club's letters. The real source's crest images replace it when there is one
  // (fetched to the person's cache on first use, never bundled in the repo).
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><path d="M32 4 56 12v20c0 14-10 23-24 28C18 55 8 46 8 32V12z" fill="${color}"/><path d="M32 10 50 16v16c0 10-7 17-18 21-11-4-18-11-18-21V16z" fill="none" stroke="#fff" stroke-width="2.5" opacity=".85"/><text x="32" y="37" text-anchor="middle" font-family="Segoe UI,Arial,sans-serif" font-size="14" font-weight="700" fill="#fff">${String(abbr).slice(0, 3)}</text></svg>`;
  return `data:image/svg+xml,${encodeURIComponent(svg)}`;
}
export function teamLogo(id, size = 40) {
  const t = S.team(id);
  const abbr = t ? t.abbr : id;
  const wrap = h('span', { class: 'logo', style: { '--s': `${size}px`, '--tc': teamColor(t) }, 'data-abbr': abbr, 'data-id': id });
  const drawn = shield(abbr, teamColor(t));
  const crest = S.crestUrl(id);
  const img = h('img', { src: crest || drawn, alt: '', width: size, height: size, loading: 'lazy', decoding: 'async' });
  if (!crest) S.wantCrest(id);
  img.addEventListener('error', () => {
    if (img.src !== drawn && S.crestUrl(id)) { img.src = drawn; return; }       // a crest file that will not load: back to the drawn shield
    img.remove();
    wrap.classList.add('logo-fallback');
    wrap.append(String(abbr).slice(0, 3));
  });
  wrap.append(img);
  return wrap;
}

export function teamName(id) {
  const t = S.team(id);
  return t ? t.name : id;
}

// ---- status ------------------------------------------------------------------------------------------
// ev.phase is the host's word for where a match is: pre, 1H, HT, 2H, FT, AET, PENS. ev.clock is "67'" or "45+2'" or "HT".
export function statusInfo(ev) {
  const today = S.todayKey();
  if (ev.state === 'in') return { kind: 'live', text: ev.phase === 'HT' ? 'HT' : ev.clock || (ev.phase === '2H' ? '2H' : '1H'), label: 'LIVE' };
  if (ev.state === 'post') {
    const t = ev.phase === 'PENS' ? 'FT · pens' : ev.phase === 'AET' ? 'AET' : 'FT';
    return { kind: 'final', text: t, label: '' };
  }
  const dayKey = etKey(new Date(ev.date));
  const when = dayKey === today ? fmtTime(ev.date) : `${fmtDayShort(ev.date)} ${fmtTime(ev.date)}`;
  const detail = String(ev.detail || '');
  if (/postponed|canceled|cancelled|delayed|abandoned/i.test(detail)) return { kind: 'pre', text: detail.toUpperCase(), label: '' };
  return { kind: 'pre', text: when, label: '' };
}

export function statusPill(ev) {
  const s = statusInfo(ev);
  return h('span', { class: `pill pill-${s.kind}` },
    s.kind === 'live' ? h('i', { class: 'dot', 'aria-hidden': 'true' }) : null,
    s.kind === 'live' ? h('b', null, 'LIVE') : null,
    h('span', null, s.text));
}

// ---- star ------------------------------------------------------------------------------------------
export function starButton(id, cls = '') {
  const on = S.isFav(id);
  return h('button', {
    class: `star ${on ? 'on' : ''} ${cls}`, type: 'button',
    title: on ? 'Remove from favorites' : 'Add to favorites', 'aria-pressed': on ? 'true' : 'false',
    onclick: (e) => { e.preventDefault(); e.stopPropagation(); S.toggleFavorite(id); },
  }, on ? '★' : '☆');
}

// ---- ordering -----------------------------------------------------------------------------------------
export function sortEvents(events) {
  const fav = S.favSet();
  const rank = (e) => (e.sides.some((s) => fav.has(s.id)) ? 0 : 1);
  const st = (e) => (e.state === 'in' ? 0 : e.state === 'pre' ? 1 : 2);
  return [...events].sort((a, b) => rank(a) - rank(b) || st(a) - st(b) || Date.parse(a.date) - Date.parse(b.date));
}

// ---- match card ------------------------------------------------------------------------------------------
// Football results are three-way: only a side that actually beat the other is "won"/"lost"; a draw dims nobody.
// After a penalty shoot-out the shoot-out winner counts as the winner.
function outcome(ev, sd) {
  if (ev.state !== 'post') return '';
  const other = ev.sides.find((x) => x !== sd);
  const a = num(sd.score), b = other ? num(other.score) : NaN;
  if (!Number.isFinite(a) || !Number.isFinite(b)) return '';
  if (a !== b) return a > b ? 'win' : 'lose';
  const pa = num(sd.pens), pb = other ? num(other.pens) : NaN;
  if (Number.isFinite(pa) && Number.isFinite(pb) && pa !== pb) return pa > pb ? 'win' : 'lose';
  return 'draw';
}

function sideRow(ev, sd, opts) {
  const t = S.team(sd.id);
  const flash = S.state.flash.get(`${ev.id}:${sd.side}`);
  const justScored = flash && Date.now() - flash < 4000;
  const oc = outcome(ev, sd);
  const focus = opts.focus === sd.id;
  const record = sd.record || S.recordOf(sd.id);
  const showLg = t && ev.league === 'cup' && t.league !== 'cup' ? leagueOf(t.league).short : '';
  return h('div', { class: `side ${oc} ${focus ? 'focus' : ''}`, style: { '--tc': teamColor(t) } },
    h('a', { class: 'side-team', href: `#/team/${sd.id}`, onclick: (e) => e.stopPropagation(), title: teamName(sd.id) },
      teamLogo(sd.id, opts.wide ? 88 : 68),
      h('span', { class: 'side-names' },
        h('b', null, opts.wide ? teamName(sd.id) : sd.abbr),
        h('small', null, [opts.wide ? sd.abbr : '', showLg, record].filter(Boolean).join(' · ')))),
    ev.state === 'pre' ? h('span', { class: 'score muted' }, '–')
      : h('span', { class: `score ${justScored ? 'bump' : ''}` }, sd.score ?? '–',
        sd.pens != null ? h('small', { class: 'fa-pens', title: 'Penalty shoot-out' }, `(${sd.pens})`) : null));
}

// "Hale 8', 61'" per scorer, in minute order, one line per side that has scored.
function goalLines(ev) {
  const lines = [];
  for (const sd of ev.sides) {
    const g = asArray(sd.scorers);
    if (!g.length) continue;
    const by = new Map();
    g.forEach((x) => { if (!by.has(x.name)) by.set(x.name, []); by.get(x.name).push(`${x.min}'`); });
    lines.push(h('div', { class: 'fa-goal-line' }, h('b', null, sd.abbr), ' ', [...by].map(([n, m]) => `${n} ${m.join(', ')}`).join(' · ')));
  }
  return lines.length ? h('div', { class: 'fa-goals', 'aria-label': 'Goals' }, lines) : null;
}

export function gameCard(ev, opts = {}) {
  const away = S.side(ev, 'away') || ev.sides[0];
  const home = S.side(ev, 'home') || ev.sides[1];
  const fav = S.favSet();
  const isFavGame = [away, home].some((s) => s && fav.has(s.id));
  // NBADash opens the game page (#/game/<id>); FADash has no match centre yet, so the card opens the home club.
  const go = () => { location.hash = `#/team/${home?.id || ''}`; };
  // With automatic refresh off a live match does not move by itself: the card carries its own refresh.
  const manual = ev.state === 'in' && !S.state.settings.autoRefresh;
  const refreshBtn = manual ? h('button', { class: 'btn fa-mc-btn', type: 'button', title: 'Fetch the latest for this day (manual refresh)',
    onclick: (e) => { e.stopPropagation(); S.loadDay(etKey(new Date(ev.date)), true, ev.league).catch(() => {}); } }, '↻ Match centre') : null;
  return h('article', {
    class: `card game ${ev.state} ${opts.wide ? 'wide' : ''} ${isFavGame ? 'fav' : ''}`,
    tabindex: '0', role: 'link', 'aria-label': `${teamName(home?.id)} v ${teamName(away?.id)}`,
    onclick: go, onkeydown: (e) => { if (e.key === 'Enter') go(); },
  },
    h('header', { class: 'game-head' },
      statusPill(ev),
      h('span', { class: 'game-head-right' },
        opts.showLeague || ev.league === 'cup' ? h('span', { class: 'fa-comp-tag', title: ev.comp }, ev.comp) : null,
        isFavGame ? h('span', { class: 'fav-tag', title: 'Favorite club' }, '★') : null)),
    h('div', { class: 'sides' }, home ? sideRow(ev, home, opts) : null, away ? sideRow(ev, away, opts) : null),
    goalLines(ev),
    h('footer', { class: 'game-foot' }, h('span', { class: 'venue' }, ev.venue || ''), refreshBtn));
}

// ---- league bar ---------------------------------------------------------------------------------------------------
// One pill per competition, between the sync strip and the club banner. A dot marks a league with a match in play.
export function renderLeagueBar(el) {
  const live = new Set();
  S.state.days.forEach((d) => { if (d.events.some((e) => e.state === 'in')) live.add(d.league); });
  el.replaceChildren(h('div', { class: 'fa-leaguebar-in', role: 'tablist', 'aria-label': 'Competitions' },
    LEAGUES.map((l) => h('button', {
      class: `fa-lg-pill ${l.slug === S.state.league ? 'active' : ''}`, type: 'button', role: 'tab', 'aria-selected': l.slug === S.state.league ? 'true' : 'false',
      title: l.name, onclick: () => S.setLeague(l.slug),
    }, live.has(l.slug) ? h('i', { class: 'dot', 'aria-hidden': 'true' }) : null, l.name))));
}

// ---- week bar and banner ------------------------------------------------------------------------------------------
// "w/c 28 Sep | w/c 5 Oct | ..." under the club banner: calendar weeks (Monday to Sunday) of the open league; only weeks
// that have saved matches are linked.
export function renderWeekBar(el, activeMonday) {
  const weeks = S.weeksWithData();
  el.hidden = weeks.length === 0;
  const since = S.state.seasonStart ? ` from ${S.fmtIso(S.state.seasonStart)}` : '';
  el.replaceChildren(h('span', { class: 'weekbar-label', title: 'Calendar weeks, Monday to Sunday' }, `Season${since}`),
    ...weeks.map((m) => h('a', { class: `weeklink ${m === activeMonday ? 'active' : ''}`, href: `#/week/${m}`, title: S.weekRangeLabel(m) }, S.weekLabel(m))));
}

export function renderBanner(el, activeId) {
  const { favorites, others } = S.orderedTeams();
  el.replaceChildren();
  const strip = h('div', { class: 'banner-strip', role: 'list' });
  const tile = (t, isFav) => h('a', {
    class: `tile fa-tile ${isFav ? 'fav' : ''} ${t.id === activeId ? 'active' : ''}`, href: `#/team/${t.id}`, role: 'listitem',
    title: `${t.name} · ${leagueOf(t.league).name}`, style: { '--tc': teamColor(t) },
  }, starButton(t.id, 'tile-star'), teamLogo(t.id, 92),
  h('span', { class: 'tile-code' }, t.abbr),
  isFav && t.league !== S.state.league ? h('span', { class: 'fa-tile-lg' }, leagueOf(t.league).short) : null);
  favorites.forEach((t) => strip.append(tile(t, true)));
  if (favorites.length && others.length) strip.append(h('span', { class: 'banner-divider', 'aria-hidden': 'true' }));
  others.forEach((t) => strip.append(tile(t, false)));

  const scroll = (dir) => strip.scrollBy({ left: dir * Math.max(300, strip.clientWidth * 0.8), behavior: 'smooth' });
  const left = h('button', { class: 'banner-btn left', type: 'button', 'aria-label': 'Scroll clubs left', onclick: () => scroll(-1) }, '‹');
  const right = h('button', { class: 'banner-btn right', type: 'button', 'aria-label': 'Scroll clubs right', onclick: () => scroll(1) }, '›');
  strip.addEventListener('wheel', (e) => {
    if (Math.abs(e.deltaY) > Math.abs(e.deltaX)) { strip.scrollLeft += e.deltaY; e.preventDefault(); }
  }, { passive: false });
  const update = () => {
    left.classList.toggle('hide', strip.scrollLeft < 8);
    right.classList.toggle('hide', strip.scrollLeft + strip.clientWidth >= strip.scrollWidth - 8);
  };
  strip.addEventListener('scroll', update, { passive: true });
  el.append(left, strip, right);
  requestAnimationFrame(() => {
    const active = strip.querySelector('.tile.active');
    if (active) active.scrollIntoView({ inline: 'center', block: 'nearest' });
    update();
  });
}

// ---- small pieces ------------------------------------------------------------------------------------------------
export const emptyState = (title, body, action) =>
  h('div', { class: 'empty' }, h('h3', null, title), body ? h('p', null, body) : null, action || null);

export function skeletonCards(n = 3) {
  return h('div', { class: 'grid' }, Array.from({ length: n }, () => h('div', { class: 'card skeleton' })));
}

export function sectionHead(title, sub, right) {
  return h('div', { class: 'section-head' },
    h('h2', null, title, sub ? h('small', null, sub) : null),
    right || null);
}

// A failed request, as a note with the Refresh hint (the page never retries on its own).
export function failNote(err) {
  return emptyState('Could not load', `${err} Press Refresh (F5) to try again.`);
}

export { asArray };
