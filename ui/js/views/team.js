// Club page: NBADash's hero (96 px crest, name, star, league position) above the club's matches and squad.
import * as S from '../store.js';
import { h, addDaysKey, ordinal } from '../util.js';
import { teamLogo, teamColor, starButton, gameCard, sectionHead, emptyState, failNote } from '../components.js';
import { calc } from '../formulas.js';
import { leagueOf } from '../leagues.js';
import { formChips } from './standings.js';

export function mount(ctx) {
  const c = S.team(ctx.arg);
  S.loadTeamFile(ctx.arg);
  if (c) {
    S.loadStandings(false, c.league);
    const t = S.todayKey();
    [S.yesterdayKey(), t, addDaysKey(t, 1)].forEach((k) => S.loadDay(k, false, c.league));
  }
  draw(ctx);
}
export function update(topics, ctx) { if (['team', 'standings', 'favorites', 'sync', 'days'].some((t) => topics.has(t))) draw(ctx); }

const dash = (v) => (v === null || v === undefined || v === '' ? '\u2013' : v);
const POS_ORDER = [['GK', 'Goalkeepers'], ['DF', 'Defenders'], ['MF', 'Midfielders'], ['FW', 'Forwards']];

function draw({ el, arg }) {
  const t = S.team(arg);
  if (!t) { el.replaceChildren(emptyState('Unknown club', arg)); return; }
  const lg = leagueOf(t.league);
  const file = S.state.teamFiles.get(arg);
  const st = (S.standingsOf(t.league)?.teams || []).find((x) => x.id === arg);
  const pos = S.positionOf(arg);
  const hero = h('section', { class: 'card hero', style: { '--tc': teamColor(t) } },
    teamLogo(arg, 96),
    h('div', null,
      h('h1', null, t.name, ' ', starButton(arg)),
      h('div', { class: 'meta' }, lg.name, st ? ` · ${ordinal(pos)} · ${st.pts} points · ${st.w}-${st.d}-${st.l}` : ''),
      st ? h('dl', { class: 'kv', style: { marginTop: '8px' } },
        h('dt', null, h('span', calc('ppg'), 'Points per game')), h('dd', null, st.gp ? (st.pts / st.gp).toFixed(2) : '–'),
        h('dt', null, h('span', calc('gd'), 'Goal difference')), h('dd', null, `${st.gf - st.ga > 0 ? '+' : ''}${st.gf - st.ga}`),
        h('dt', null, h('span', calc('form'), 'Form')), h('dd', null, formChips(st.form))) : null));

  // matches already on the page (loaded days of the club's league and any cup days)
  const mine = [];
  S.state.days.forEach((d) => d.events.forEach((e) => { if (e.sides.some((s) => s.id === arg)) mine.push(e); }));
  const byDate = (a, b) => Date.parse(a.date) - Date.parse(b.date);
  const next = mine.filter((e) => e.state !== 'post').sort(byDate);
  const results = mine.filter((e) => e.state === 'post').sort((a, b) => byDate(b, a)).slice(0, 6);
  const sections = [];
  if (next.length) sections.push(sectionHead('Next', 'live and upcoming'), h('div', { class: 'grid' }, next.map((e) => gameCard(e, { focus: arg, showLeague: true }))));
  if (results.length) sections.push(sectionHead('Results', 'latest first'), h('div', { class: 'grid' }, results.map((e) => gameCard(e, { focus: arg, showLeague: true }))));
  if (!mine.length) sections.push(h('p', { class: 'muted' }, 'No matches loaded for this club yet. Press refresh, or sync the season in settings.'));

  const err = S.keyError(`team:${arg}`);
  const head = (label, key) => h('th', null, key ? h('span', calc(key, 'player'), label) : label);
  const real = S.state.source === 'espn';
  const squad = file
    ? POS_ORDER.map(([code, label]) => {
      const rows = file.players.filter((p) => p.pos === code);
      if (!rows.length) return null;
      return h('div', { class: 'card scroll-x', style: { marginBottom: '14px' } }, h('table', { class: 'tbl roster' },
        h('thead', null, h('tr', null, h('th', null, label), real ? head('Age') : null, head('Apps', 'apps'), head('G', 'goals'), head('A', 'assists'), head('YC', 'cards'), head('RC', 'cards'))),
        // The real source's roster has no appearance, goal or card counts: those arrive as null and show as a dash.
        h('tbody', null, rows.map((p) => h('tr', null, h('td', null, p.no ? h('small', { class: 'muted' }, `${p.no} `) : null, h('b', null, p.name)), real ? h('td', null, dash(p.age)) : null, h('td', null, dash(p.apps)), h('td', null, dash(p.g)), h('td', null, dash(p.a)), h('td', null, dash(p.yc)), h('td', null, dash(p.rc)))))));
    })
    : [err ? failNote(err) : emptyState('Loading...', '')];
  el.replaceChildren(hero, ...sections, sectionHead('Squad', S.state.source === 'espn' ? 'from ESPN · appearances, goals and cards are not in this feed' : 'pretend players'), ...squad);
}
