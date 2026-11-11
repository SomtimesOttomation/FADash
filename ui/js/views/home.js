// Matches: NBADash's home view, per league. A left-aligned heading per day ("Today · date · N matches · N live"), then the
// match grid; "Coming up" lists the next days' fixtures. The open league is the pill in the league bar (state.league).
import * as S from '../store.js';
import { addDaysKey, h, fmtKey } from '../util.js';
import { gameCard, sortEvents, sectionHead, emptyState, skeletonCards, failNote } from '../components.js';

const COMING_DAYS = 2;
export function mount(ctx) {
  draw(ctx);
  const t = S.todayKey();
  S.loadDay(t); S.loadDay(S.yesterdayKey());
  for (let i = 1; i <= COMING_DAYS; i++) S.loadDay(addDaysKey(t, i));
  S.loadStandings();
}
export function update(topics, ctx) {
  if (['days', 'favorites', 'teams', 'sync', 'standings', 'settings', 'live', 'league'].some((t) => topics.has(t))) draw(ctx);
}

function section(key, title) {
  const d = S.dayOf(S.state.league, key);
  if (!d) return null;
  return { key, title, events: sortEvents(d.events) };
}

function comingUp() {
  const t = S.todayKey();
  const events = [];
  for (let i = 1; i <= COMING_DAYS; i++) { const d = S.dayOf(S.state.league, addDaysKey(t, i)); if (d) events.push(...d.events.filter((e) => e.state === 'pre')); }
  return sortEvents(events).sort((a, b) => Date.parse(a.date) - Date.parse(b.date));
}

function draw({ el }) {
  const lg = S.state.league;
  const today = S.todayKey(), yest = S.yesterdayKey();
  const sections = [section(today, 'Today'), section(yest, 'Last night')].filter(Boolean);
  const out = [];
  const fav = S.favSet();
  // Real source only: the club list is downloaded once, on a click (about 4 requests; crests follow one at a time as clubs are drawn).
  if (S.state.source === 'espn' && S.state.teams.length === 0) {
    out.push(h('div', { class: 'card pad fa-notice' },
      h('span', null, h('b', null, 'No clubs yet. '), 'FADash downloads the clubs of the four leagues once (four requests). Their crests are saved to your computer as each club first appears.'),
      h('button', { class: 'btn', type: 'button', disabled: S.state.clubsLoading || S.state.halted ? true : null, onclick: () => S.downloadClubs() }, S.state.clubsLoading ? 'Downloading...' : 'Download clubs'),
      S.state.clubsError ? h('small', { class: 'muted' }, S.state.clubsError) : null));
  } else if (fav.size === 0) out.push(h('div', { class: 'card pad fa-notice' },
    h('b', null, 'Pick your teams. '), 'Click the ☆ on any crest above: favorites move to the front, across every league, and their matches are shown first.'));
  if (!S.state.settings.autoRefresh && S.state.host) {
    out.push(h('div', { class: 'card pad fa-notice' },
      h('span', null, h('b', null, 'Automatic refresh is off. '), 'Scores only update when you ask. Use the ', h('b', null, '↻'), ' button (or F5) for the latest, or '),
      h('button', { class: 'btn', type: 'button', onclick: () => S.runSync().catch(() => {}) }, 'Sync the season'),
      h('button', { class: 'btn', type: 'button', onclick: () => import('./settings.js').then((m) => m.openSettings()) }, 'Automatic refresh options')));
  }
  for (const s of sections) {
    const live = s.events.filter((e) => e.state === 'in').length;
    out.push(sectionHead(s.title, `${fmtKey(s.key)} · ${s.events.length} match${s.events.length === 1 ? '' : 'es'}${live ? ` · ${live} live` : ''}`));
    out.push(s.events.length
      ? h('div', { class: 'grid' }, s.events.map((e) => gameCard(e)))
      : emptyState('No matches', `No ${S.league().name} matches on this day.`));
  }
  const next = comingUp();
  if (next.length) {
    out.push(sectionHead('Coming up', `next ${COMING_DAYS} days · ${next.length} match${next.length === 1 ? '' : 'es'}`));
    out.push(h('div', { class: 'grid' }, next.slice(0, 9).map((e) => gameCard(e))));
  }
  const err = S.keyError(`score:${lg}:${S.isoOf(today)}`);
  if (!sections.length) out.push(err ? failNote(err) : S.state.ready ? emptyState('Nothing loaded yet', 'Press the refresh button or F5.') : skeletonCards(6));
  el.replaceChildren(...out);
}
