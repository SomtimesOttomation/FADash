// Week pages: NBADash's week view, built from the saved season (the week bar only links weeks that have data).
// A week is a calendar week, Monday to Sunday, named by its Monday: #/week/2026-11-02.
import * as S from '../store.js';
import { h, fmtKey } from '../util.js';
import { gameCard, sortEvents, sectionHead, emptyState } from '../components.js';

let monday = '';
export function mount(ctx) { monday = /^\d{4}-\d{2}-\d{2}$/.test(ctx.arg) ? ctx.arg : (S.weeksWithData().slice(-1)[0] || ''); S.loadStandings(); draw(ctx); }
export function update(topics, ctx) { if (['days', 'favorites', 'teams', 'standings', 'league'].some((t) => topics.has(t))) draw(ctx); }

function draw({ el }) {
  const lg = S.state.league;
  if (!monday) { el.replaceChildren(sectionHead('Weeks', S.league().name), emptyState('No weeks saved yet', 'Use "Sync the season" in settings to download them.')); return; }
  const saved = S.state.cachedDays.get(lg) || new Set();
  const keys = S.weekDayKeys(monday).slice().reverse().filter((k) => saved.has(k) || S.dayOf(lg, k));
  const out = [sectionHead(`Week of ${S.fmtIso(monday)}`, `${S.weekRangeLabel(monday)} · ${S.league().name}`)];
  let games = 0;
  for (const k of keys) {
    const d = S.dayOf(lg, k);
    if (!d) continue;
    const events = sortEvents(d.events);
    if (!events.length) continue;
    games += events.length;
    out.push(sectionHead(fmtKey(k), `${events.length} match${events.length === 1 ? '' : 'es'}`), h('div', { class: 'grid' }, events.map((e) => gameCard(e))));
  }
  if (!games) out.push(emptyState(`No ${S.league().name} matches saved for this week`, 'Use "Sync the season" in settings to download them.'));
  el.replaceChildren(...out);
}
