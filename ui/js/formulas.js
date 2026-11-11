// Formula hover cards: every calculated number in the app can explain itself. Copied from NBADash's formulas.js.
// Mark any element with data-calc="<key>" (and optionally data-calc-scope="team"|"player"); hovering or focusing it shows
// the card. Add your own terms to DEFS: a title, the formula, and why it matters (NBADash has ~40, for every rating).
import { h } from './util.js';

// key -> (scope) => { title, formula, why, note? }
const DEFS = {
  gp: () => ({ title: 'Played', formula: 'P = matches played so far', why: 'How many matches the numbers next to it are based on. Early in the season small samples swing a lot, and clubs can have games in hand.' }),
  pts: () => ({ title: 'Points', formula: 'PTS = 3 \u00d7 W + 1 \u00d7 D', why: 'League points: three for a win, one for a draw, none for a defeat. Ties on points are split by goal difference, then goals scored.' }),
  ppg: () => ({ title: 'Points per game', formula: 'PPG = PTS / P', why: 'Points earned per match played, so clubs with games in hand compare fairly.' }),
  gf: () => ({ title: 'Goals for', formula: 'GF = goals scored in league matches', why: 'The second tie-breaker after goal difference.' }),
  ga: () => ({ title: 'Goals against', formula: 'GA = goals conceded in league matches', why: 'Half of goal difference; the cleaner a defence, the smaller it is.' }),
  gd: () => ({ title: 'Goal difference', formula: 'GD = Goals for \u2212 Goals against', why: 'How much a club outscores its opponents. It splits clubs level on points, and is a better sign of strength than the points total when the table is close.' }),
  form: () => ({ title: 'Form', formula: 'Last 5 league results, oldest on the left (W win, D draw, L defeat)', why: 'Recent form, which the season total can hide.' }),
  apps: () => ({ title: 'Appearances', formula: 'Apps = matches the player was in the matchday squad and played', why: 'Playing time context for goals and assists.' }),
  goals: () => ({ title: 'Goals', formula: 'G = goals scored (penalties count, own goals do not)', why: 'Straight from the match reports.' }),
  assists: () => ({ title: 'Assists', formula: 'A = final pass before a goal, as credited by the data source', why: 'Credited by the source, so definitions can differ between sources.' }),
  cards: () => ({ title: 'Cards', formula: 'YC = yellow cards, RC = red cards (a second yellow counts as a red)', why: 'Three or more bookings in a short spell can mean a suspension; check the league rules.' }),
};

export const hasFormula = (key) => !!DEFS[key];

// Attributes to mark an element: h('span', { ...calc('drtg', 'team') }, 'DRtg')
export const calc = (key, scope = 'team') => (DEFS[key] ? { 'data-calc': key, 'data-calc-scope': scope, tabindex: 0, class: 'calc' } : {});

let tip = null;
function show(el) {
  const d = DEFS[el.dataset.calc]; if (!d) return;
  const c = d(el.dataset.calcScope || 'team');
  if (!tip) { tip = h('div', { class: 'calc-tip', role: 'tooltip' }); document.body.append(tip); }
  tip.replaceChildren(h('b', null, c.title), h('pre', null, c.formula), h('p', null, c.why), c.note ? h('small', null, c.note) : null);
  tip.style.display = 'block';
  const r = el.getBoundingClientRect(), tw = tip.offsetWidth, th = tip.offsetHeight;
  let x = Math.min(window.innerWidth - tw - 10, Math.max(10, r.left + r.width / 2 - tw / 2));
  let y = r.bottom + 8; if (y + th > window.innerHeight - 10) y = Math.max(10, r.top - th - 8);
  tip.style.left = `${x}px`; tip.style.top = `${y}px`;
}
const hide = () => { if (tip) tip.style.display = 'none'; };

export function installCalcTips() {
  document.addEventListener('mouseover', (e) => { const el = e.target.closest && e.target.closest('[data-calc]'); if (el) show(el); else hide(); });
  document.addEventListener('focusin', (e) => { const el = e.target.closest && e.target.closest('[data-calc]'); if (el) show(el); });
  document.addEventListener('focusout', hide);
  window.addEventListener('scroll', hide, true);
  window.addEventListener('hashchange', hide);
}
