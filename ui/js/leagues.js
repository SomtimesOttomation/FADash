// The competitions FADash covers and the rules that colour their tables. Pure configuration: nothing here fetches.
//
// slug      short key used in data keys ("score:ch:2026-11-09") and in the page's league bar
// name/short  shown on the pills and in tags
// table     true when the competition has a league table (cups do not)
// zones     table stripes, counted from the top (from: 'top') or the bottom (from: 'bottom'); the page applies them to however
//           many clubs the feed returns, so a change in the rules is a change here, not in the table code
//           kind: promo (automatic promotion), playoff, europe (qualification places), rel (relegation)
//
// Rules as they stand for 2026-27 in the English pyramid (check the league sites if they change):
//   Premier League  top 4 Champions League, 5th Europa League, bottom 3 relegated
//   Championship    top 2 promoted, 3rd-6th play-offs, bottom 3 relegated
//   League One      top 2 promoted, 3rd-6th play-offs, bottom 4 relegated
//   League Two      top 3 promoted, 4th-7th play-offs, bottom 2 relegated (to the National League)
export const LEAGUES = [
  { slug: 'pl', name: 'Premier League', short: 'PL', tier: 1, table: true, zones: [
    { from: 'top', count: 4, kind: 'europe', label: 'Champions League' },
    { from: 'top', count: 1, kind: 'europe2', label: 'Europa League' },
    { from: 'bottom', count: 3, kind: 'rel', label: 'Relegation' }] },
  { slug: 'ch', name: 'Championship', short: 'CH', tier: 2, table: true, zones: [
    { from: 'top', count: 2, kind: 'promo', label: 'Promotion' },
    { from: 'top', count: 4, kind: 'playoff', label: 'Play-offs' },
    { from: 'bottom', count: 3, kind: 'rel', label: 'Relegation' }] },
  { slug: 'l1', name: 'League One', short: 'L1', tier: 3, table: true, zones: [
    { from: 'top', count: 2, kind: 'promo', label: 'Promotion' },
    { from: 'top', count: 4, kind: 'playoff', label: 'Play-offs' },
    { from: 'bottom', count: 4, kind: 'rel', label: 'Relegation' }] },
  { slug: 'l2', name: 'League Two', short: 'L2', tier: 4, table: true, zones: [
    { from: 'top', count: 3, kind: 'promo', label: 'Promotion' },
    { from: 'top', count: 4, kind: 'playoff', label: 'Play-offs' },
    { from: 'bottom', count: 2, kind: 'rel', label: 'Relegation' }] },
  { slug: 'cup', name: 'Cups', short: 'CUP', tier: 0, table: false, zones: [] },
];

export const leagueOf = (slug) => LEAGUES.find((l) => l.slug === slug) || LEAGUES[0];
export const isLeague = (slug) => LEAGUES.some((l) => l.slug === slug);
export const DEFAULT_LEAGUE = 'pl';

// Zone for a 1-based table position in a table of n clubs, or null. Top zones are stacked in the order listed
// (4 Champions League then 1 Europa League puts the Europa League place at 5th).
export function zoneAt(league, pos, n) {
  let top = 0;
  for (const z of league.zones) {
    if (z.from === 'top') { if (pos > top && pos <= top + z.count) return z; top += z.count; }
  }
  let bottom = 0;
  for (const z of league.zones.filter((x) => x.from === 'bottom')) {
    bottom += z.count;
    if (pos > n - bottom && pos <= n - bottom + z.count) return z;
  }
  return null;
}

// The legend shows each distinct zone once, top to bottom.
export function zoneLegend(league) {
  const seen = new Set();
  return league.zones.filter((z) => (seen.has(z.kind) ? false : seen.add(z.kind)));
}
