// Table (the Standings page of the other dashes; football calls it the table): NBADash's table layout (crest, code, numbers; favourites highlighted; click a row for the club), one table per
// league. Zone stripes (promotion, play-offs, relegation, European places) come from the league config in leagues.js, never
// from this file, so a rule change is a config change.
import * as S from '../store.js';
import { h } from '../util.js';
import { teamLogo, emptyState, failNote, sectionHead } from '../components.js';
import { calc } from '../formulas.js';
import { zoneAt, zoneLegend } from '../leagues.js';

export function mount(ctx) { S.loadStandings(); draw(ctx); }
export function update(topics, ctx) { if (['standings', 'favorites', 'league', 'teams'].some((t) => topics.has(t))) draw(ctx); }

const COLS = [['P', 'gp', 'gp'], ['W', 'w'], ['D', 'd'], ['L', 'l'], ['GF', 'gf', 'gf'], ['GA', 'ga', 'ga'], ['GD', 'gd', 'gd'], ['PTS', 'pts', 'pts'], ['PPG', 'ppg', 'ppg']];
const gd = (t) => t.gf - t.ga;
const val = (t, k) => (k === 'gd' ? `${gd(t) > 0 ? '+' : ''}${gd(t)}` : k === 'ppg' ? (t.gp ? (t.pts / t.gp).toFixed(2) : '–') : t[k]);
export const formChips = (form) => h('span', { class: 'form' }, (form || []).map((r) => h('i', { class: `fc fc-${r}`, title: r === 'W' ? 'Win' : r === 'D' ? 'Draw' : 'Defeat' }, r)));

function draw({ el }) {
  const lg = S.league();
  if (!lg.table) {
    el.replaceChildren(sectionHead('Table', lg.name), emptyState('Cups have no table', 'Knock-out ties are on the Matches page. Pick a league above for its table.'));
    return;
  }
  const st = S.standingsOf(lg.slug);
  const err = S.keyError(`standings:${lg.slug}`);
  if (!st) { el.replaceChildren(sectionHead('Table', lg.name), err ? failNote(err) : emptyState('Loading table...', '')); return; }
  const fav = S.favSet();
  const n = st.teams.length;
  const legend = zoneLegend(lg);
  el.replaceChildren(
    sectionHead('Table', lg.name),
    h('div', { class: 'card scroll-x' }, h('table', { class: 'tbl standings' },
      h('thead', null, h('tr', null, h('th', null, 'Club'), COLS.map(([l, , c]) => h('th', null, c ? h('span', calc(c), l) : l)), h('th', null, h('span', calc('form'), 'Form')))),
      h('tbody', null, st.teams.map((t, i) => {
        const z = zoneAt(lg, i + 1, n);
        return h('tr', { class: `${fav.has(t.id) ? 'me' : ''} ${z ? `zone zone-${z.kind}` : ''}`, title: z ? z.label : '', style: { cursor: 'pointer' }, onclick: () => { location.hash = `#/team/${t.id}`; } },
          h('td', null, h('span', { class: 'club-cell' }, h('small', { class: 'pos' }, i + 1), teamLogo(t.id, 24), h('b', null, (S.team(t.id) || t).abbr), h('small', { class: 'club-name' }, S.team(t.id)?.name || ''))),
          COLS.map(([, k]) => h('td', { class: k === 'pts' ? 'pts' : '' }, val(t, k))),
          h('td', null, formChips(t.form)));
      })))),
    legend.length ? h('div', { class: 'zone-legend', 'aria-label': 'Table zones' }, legend.map((z) => h('span', null, h('i', { class: `zone-key zone-${z.kind}` }), z.label))) : null);
}
