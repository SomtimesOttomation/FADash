// App state and data loading. Views subscribe to topics and re-render. Same API shape as NBADash's store.js
// (state.days, events with sides, favSet, orderedTeams, weeksWithData, sync, update, ...), with one addition: FADash is
// ONE dash for all English league football, so almost everything is per league (state.league is the pill that is open).
//
// Design decisions for the league pills (also in CHANGELOG.md):
//   - Data keys carry the league: score:<lg>:<date>, week:<lg>:<monday>, standings:<lg>, team:<club id>. The host keeps one
//     cache folder per league, so one league can be refreshed or deleted alone.
//   - Clubs are keyed by the data source's team id (ESPN's numeric ids). Favourites are club ids and work across leagues.
//   - Banner: favourites from every league first (each with its league tag), then the clubs of the open league. Cups show every club.
//   - Week bar: calendar weeks (Monday to Sunday) that have saved matches for the open league. Rounds and matchweeks come later.
//   - Traffic is counted per data source (host), not per league; the traffic page lists keys, which carry the league.
//   - Changing league asks for nothing by itself except what that league's page shows (like opening any other page).
import * as bridge from './bridge.js';
import { etKey, addDaysKey, asArray, fmtKey } from './util.js';
import { leagueOf, isLeague, DEFAULT_LEAGUE } from './leagues.js';

const LEAGUE_STORE = 'fadash.league';
function savedLeague() {
  try { const v = localStorage.getItem(LEAGUE_STORE); if (isLeague(v)) return v; } catch (e) { /* storage can be unavailable */ }
  return DEFAULT_LEAGUE;
}

export const state = {
  ready: false,
  source: 'espn',
  crests: new Map(),        // club id -> crest picture address (a file in the person's cache); only with the real source
  clubsLoading: false,
  host: bridge.isHost,
  version: '',
  league: savedLeague(),    // the open league pill: pl, ch, l1, l2 or cup
  teams: [],                // clubs from the host: { id, abbr, name, color, league }
  byId: new Map(),
  settings: { favorites: [], theme: 'system', updateCheck: false, autoRefresh: false, autoAck: false, refreshSeconds: 60 },
  days: new Map(),          // 'pl:yyyymmdd' -> { key, league, events, allFinal, source, at }
  cachedDays: new Map(),    // league -> Set of 'yyyymmdd' that came from a saved week
  standings: new Map(),     // league -> { teams: [{ id, abbr, gp, w, d, l, gf, ga, pts, form }] }
  teamFiles: new Map(),     // club id -> { players } | null
  live: { ok: true, at: 0, error: '' },
  sync: { running: false, lastRun: null, text: '', pct: 0, exitCode: null, summary: '', finishedAt: 0 },
  flash: new Map(),         // 'eventId:side' -> time of the last score change
  watch: new Set(),
  seasonStart: '',          // iso date of the season's first Monday
  seasonWeeks: [],          // [{ monday, leagues: [slugs with a saved copy] }]
  clubsError: '',
  update: { phase: 'idle', info: null, pct: 0, text: '', error: '', quiet: false, note: null },
  halted: false,
};

// ---- requests and the failed-request rule --------------------------------------------------------------
// Every key the open page asked for is remembered, so Refresh (F5) can ask again. A key that failed is NOT asked for
// again when the page redraws: it waits for Refresh. (Without this, a source that is down gets hammered on every redraw.)
const req = new Map();            // key -> { loading, error }
let routeKeys = new Set();
export const newRoute = () => { routeKeys = new Set(); };
export const keyError = (key) => req.get(key)?.error || '';
async function want(key, { force = false, cacheOnly = false } = {}) {
  routeKeys.add(key);
  const r = req.get(key);
  if (!force && r && (r.loading || r.error || r.done)) return;
  req.set(key, { loading: true, error: '', done: false });
  try {
    const answer = await bridge.request('data.get', { key, force, cacheOnly });
    if (answer === 'missing') req.set(key, { loading: false, error: '', done: true });
  } catch (e) { req.set(key, { loading: false, error: e.message, done: false }); state.live = { ...state.live, error: e.message }; notify('live', 'days'); }
}
// Refresh: everything the open page shows, failed keys included.
export async function refresh() {
  if (state.halted) throw new Error('Data traffic is paused. Resume first.');
  const keys = [...routeKeys];
  if (!keys.length) keys.push(`score:${state.league}:${isoOf(todayKey())}`);
  await Promise.all(keys.map((k) => want(k, { force: true })));
}
export const loading = () => [...routeKeys].some((k) => req.get(k)?.loading);

// ---- calendar weeks: Monday to Sunday, labelled by the Monday ---------------------------------------------
const isoOf = (key) => `${key.slice(0, 4)}-${key.slice(4, 6)}-${key.slice(6, 8)}`;
const keyOf = (iso) => iso.replaceAll('-', '');
const keyToUtc = (k) => Date.UTC(+k.slice(0, 4), +k.slice(4, 6) - 1, +k.slice(6, 8));
export { isoOf, keyOf };
export const mondayOfKey = (k) => { const dow = (new Date(keyToUtc(k)).getUTCDay() + 6) % 7; return addDaysKey(k, -dow); };       // yyyymmdd -> yyyymmdd of that week's Monday
export const weekDayKeys = (mondayIso) => Array.from({ length: 7 }, (_, i) => addDaysKey(keyOf(mondayIso), i));
export const weekRangeLabel = (mondayIso) => { const d = weekDayKeys(mondayIso); const f = (k) => fmtKey(k, { weekday: undefined }); return `${f(d[0])} - ${f(d[6])}`; };
export const weekLabel = (mondayIso) => `w/c ${fmtKey(keyOf(mondayIso), { weekday: undefined })}`;
// Mondays (iso) of the weeks that have saved matches for a league.
export const weeksWithData = (lg = state.league) => [...new Set([...(state.cachedDays.get(lg) || [])].map((k) => isoOf(mondayOfKey(k))))].sort();
export const fmtIso = (iso) => fmtKey(keyOf(iso), { weekday: undefined });
export const todayKey = () => etKey(new Date());
export const yesterdayKey = () => addDaysKey(todayKey(), -1);
export const dayOf = (lg, key) => state.days.get(`${lg}:${key}`);

// ---- change notification (NBADash's) ----------------------------------------------------------------------
const subs = new Set();
let queued = new Set();
let raf = 0;
export function subscribe(fn) { subs.add(fn); return () => subs.delete(fn); }
export function notify(...topics) {
  topics.forEach((t) => queued.add(t));
  if (raf) return;
  raf = requestAnimationFrame(() => {
    const t = queued; queued = new Set(); raf = 0;
    subs.forEach((fn) => { try { fn(t); } catch (e) { console.error(e); } });
  });
}

// ---- helpers --------------------------------------------------------------------------------------------------
function normEvent(ev) {
  const e = { ...ev };
  e.id = String(e.id);
  e.sides = asArray(e.sides).map((s) => ({ ...s, scorers: asArray(s.scorers), leaders: asArray(s.leaders) }));
  return e;
}
export const side = (ev, which) => ev.sides.find((s) => s.side === which);
export const favSet = () => new Set(state.settings.favorites);
export const isFav = (id) => favSet().has(id);
export const team = (id) => state.byId.get(id);
export const league = (slug = state.league) => leagueOf(slug);
export const standingsOf = (lg = state.league) => state.standings.get(lg) || null;
// "W-D-L" from the club's league table, or '' while the table is not loaded.
export function recordOf(id) {
  const c = team(id);
  const t = c && (state.standings.get(c.league)?.teams || []).find((x) => x.id === id);
  return t ? `${t.w}-${t.d}-${t.l}` : '';
}
// Position in the club's league table (1-based), or 0.
export function positionOf(id) {
  const c = team(id);
  const i = c ? (state.standings.get(c.league)?.teams || []).findIndex((x) => x.id === id) : -1;
  return i + 1;
}
export function allEvents() {
  const out = [];
  state.days.forEach((d) => out.push(...d.events));
  return out;
}
// Banner order: favourites from every league first, then the clubs of the open league (Cups: every club, by league).
export function orderedTeams() {
  const fav = favSet();
  const byName = (a, b) => a.name.localeCompare(b.name);
  const byTier = (a, b) => leagueOf(a.league).tier - leagueOf(b.league).tier || byName(a, b);
  const f = state.teams.filter((t) => fav.has(t.id)).sort(byTier);
  const pool = state.league === 'cup' ? state.teams : state.teams.filter((t) => t.league === state.league);
  const rest = pool.filter((t) => !fav.has(t.id)).sort(state.league === 'cup' ? byTier : byName);
  return { favorites: f, others: rest, all: [...f, ...rest] };
}

export function setLeague(slug) {
  if (!isLeague(slug) || slug === state.league) return;
  state.league = slug;
  try { localStorage.setItem(LEAGUE_STORE, slug); } catch (e) { /* ignore */ }
  notify('league', 'teams', 'days');
}

function setDay(d, source, at) {
  const lg = d.league || state.league;
  const key = String(d.date);
  const id = `${lg}:${key}`;
  const prev = state.days.get(id);
  const next = { key, league: lg, events: asArray(d.events).map(normEvent), allFinal: asArray(d.events).every((e) => e.state === 'post'), source, at };
  if (prev) {     // goals flash for a few seconds, as score changes do in NBADash
    const old = new Map();
    prev.events.forEach((e) => e.sides.forEach((s) => old.set(`${e.id}:${s.side}`, s.score)));
    next.events.forEach((e) => e.sides.forEach((s) => { const k = `${e.id}:${s.side}`; if (old.has(k) && old.get(k) !== s.score && e.state === 'in') state.flash.set(k, Date.now()); }));
  }
  state.days.set(id, next);
}

// ---- data from the host ---------------------------------------------------------------------------------------
function onData(d) {
  if (d.key.startsWith('crest:')) { onCrest(d); return; }
  if (d.key.startsWith('clubs:')) { onClubs(d); return; }
  const r = req.get(d.key);
  if (!d.ok) {
    req.set(d.key, { loading: false, error: d.error, done: false });
    state.live = { ...state.live, error: d.error };
    notify('live', 'days', 'standings', 'team');
    return;
  }
  req.set(d.key, { loading: false, error: '', done: true });
  const at = Date.parse(d.at) || Date.now();
  const [kind, a, b] = d.key.split(':');
  if (kind === 'score') {
    setDay({ ...d.body, league: a }, 'live', at);
    if (b === isoOf(todayKey())) state.live = { ok: true, at, error: '' };
    notify('days', 'live');
  } else if (kind === 'week') {
    for (const day of asArray(d.body.days)) {
      if (day.date > todayKey()) continue;
      setDay({ ...day, league: a }, 'saved', at);
      if (!state.cachedDays.has(a)) state.cachedDays.set(a, new Set());
      state.cachedDays.get(a).add(day.date);
    }
    notify('days');
  } else if (kind === 'standings') {
    state.standings.set(a, d.body); notify('standings', 'days');
  } else if (kind === 'team') {
    state.teamFiles.set(a, d.body); notify('team');
  }
  void r;
}

// ---- real source only: the club list and the crests -------------------------------------------------------------
// The clubs are downloaded once, by the person's click (Home notice). Crests are downloaded one at a time to the person's
// cache the first time a club is drawn; until then, and if a download fails, the drawn shield stays. Nothing is retried.
const CREST_BASE = 'https://fadash.cache/espn/crests/';
const crestAsked = new Set();
export const crestUrl = (id) => state.crests.get(id) || '';
export function wantCrest(id) {
  if (state.source !== 'espn' || state.halted || state.crests.has(id) || crestAsked.has(id) || !state.byId.has(id)) return;
  crestAsked.add(id);
  bridge.request('data.get', { key: `crest:${id}` }).catch(() => {});
}
function onCrest(d) {
  const id = d.key.slice(6);
  if (!d.ok) return;                                  // a missing crest is not an error worth a banner: the shield stays
  state.crests.set(id, `${CREST_BASE}${id}.png?v=${Date.parse(d.at) || 1}`);
  document.querySelectorAll(`.logo[data-id="${CSS.escape(id)}"] img`).forEach((img) => { img.src = state.crests.get(id); });
}
function onClubs(d) {
  const lg = d.key.slice(6);
  const left = clubsPending; clubsPending = Math.max(0, left - 1);
  if (!d.ok) { state.clubsError = d.error || 'The club list did not download.'; } else {
    for (const c of asArray(d.body?.clubs)) {
      if (state.byId.has(c.id)) continue;
      const t = { id: String(c.id), abbr: c.abbr, name: c.name, color: c.color, league: lg };
      state.teams.push(t); state.byId.set(t.id, t);
    }
  }
  if (!clubsPending) state.clubsLoading = false;
  notify('teams', 'days', 'favorites');
}
let clubsPending = 0;
export function downloadClubs() {
  if (state.source !== 'espn' || state.clubsLoading || state.halted) return;
  state.clubsLoading = true; state.clubsError = ''; clubsPending = 4;
  notify('teams');
  for (const lg of ['pl', 'ch', 'l1', 'l2']) {
    bridge.request('data.get', { key: `clubs:${lg}`, force: true }).catch((e) => { clubsPending = Math.max(0, clubsPending - 1); state.clubsError = e.message; if (!clubsPending) state.clubsLoading = false; notify('teams'); });
  }
}

// ---- loading (each view asks for what it shows) ---------------------------------------------------------------
export const loadDay = (key, force, lg = state.league) => want(`score:${lg}:${isoOf(key)}`, { force });
export const loadStandings = (force, lg = state.league) => (leagueOf(lg).table ? want(`standings:${lg}`, { force }) : Promise.resolve());
export const loadTeamFile = (id, force) => want(`team:${id}`, { force });
export async function loadSeasonWeeks() {
  try {
    const weeks = asArray(await bridge.request('season.weeks'));
    state.seasonWeeks = weeks;
    for (const w of weeks) for (const lg of asArray(w.leagues)) bridge.request('data.get', { key: `week:${lg}:${w.monday}`, cacheOnly: true }).catch(() => {});
  } catch { state.seasonWeeks = []; }
  notify('days');
}

// ---- app updates (NBADash's) ------------------------------------------------------------------------------------
function onUpdate(d) {
  const u = state.update;
  if (d.running) {
    u.phase = d.action === 'Stage' ? 'downloading' : 'checking';
    u.pct = d.pct || 0; u.text = d.text || '';
  } else {
    const r = d.result || {};
    u.pct = 0; u.text = ''; u.error = '';
    if (r.status === 'error') { u.phase = 'error'; u.error = r.error || 'The update did not finish.'; }
    else { u.phase = r.status || 'idle'; u.info = r; }
  }
  notify('update');
}
export async function checkUpdate({ quiet = false } = {}) {
  const u = state.update;
  if (u.phase === 'checking' || u.phase === 'downloading') return;
  u.quiet = quiet; u.phase = 'checking'; u.error = ''; u.pct = 0; u.text = 'Asking GitHub for the latest release...';
  notify('update');
  try {
    const started = await bridge.request('update.check');
    if (started === false) { u.phase = u.info?.status === 'available' ? 'available' : 'idle'; notify('update'); }
  } catch (e) { u.phase = 'error'; u.error = e.message; notify('update'); }
}
export async function downloadUpdate() {
  const u = state.update;
  u.quiet = false; u.phase = 'downloading'; u.pct = 0; u.text = 'Starting...'; notify('update');
  try { await bridge.request('update.stage'); } catch (e) { u.phase = 'error'; u.error = e.message; notify('update'); }
}
export async function cancelUpdate() {
  try { await bridge.request('update.cancel'); } catch { /* ignore */ }
  state.update.phase = state.update.info?.status === 'available' ? 'available' : 'idle';
  notify('update');
}
export async function installUpdate() {
  try { await bridge.request('update.apply'); } catch (e) { state.update.phase = 'error'; state.update.error = e.message; notify('update'); }
}
export const updateReady = () => state.update.phase === 'available' || state.update.phase === 'staged';

// ---- actions (NBADash's names) ------------------------------------------------------------------------------------
// In DashLauncher the launcher's theme wins; standalone, the dash's own setting.
export const inLauncher = () => state.hostMode === 'launcher';
export function applyTheme() {
  document.documentElement.dataset.theme = (inLauncher() && state.hostTheme) ? state.hostTheme : (state.settings.theme || 'system');
  notify('theme');
}
function takeSnapshot(snap) {
  if (!snap) return;
  state.settings = { ...state.settings, ...(snap.settings || {}) };
  state.halted = !!snap.halted;
  if (snap.source) state.source = snap.source;
}
// The live status button: same as the launcher's kill switch, started from inside the dash.
export async function stopTraffic() { takeSnapshot(await bridge.request('traffic.stop')); req.forEach((v) => { v.loading = false; }); notify('traffic'); }
export async function resumeTraffic() { takeSnapshot(await bridge.request('traffic.resume')); state.live = { ...state.live, error: '' }; notify('traffic'); }
export async function saveSettings(patch, ack = false) {
  Object.assign(state.settings, patch);
  if ('theme' in patch) applyTheme();
  notify('settings', 'favorites');
  for (const [key, value] of Object.entries(patch)) {
    try { takeSnapshot(await bridge.request('settings.set', { key, value, ack })); } catch (e) { console.warn(e.message); throw e; }
  }
  notify('settings', 'favorites');
}
export function toggleFavorite(abbr) {
  const list = [...state.settings.favorites];
  const i = list.indexOf(abbr);
  if (i >= 0) list.splice(i, 1); else list.push(abbr);
  saveSettings({ favorites: list }).catch(() => {});
}
// Start a sync and show it immediately; the host then streams progress ({running, pct, text}) as 'sync' events.
export async function runSync() {
  try {
    const r = await bridge.request('sync.run');
    if (r && r.started) { state.sync = { ...state.sync, running: true, pct: 0, text: 'Starting...' }; notify('sync'); }
  } catch (e) { throw e; }
}
function onSync(d) {
  const wasRunning = state.sync.running;
  state.sync = { ...state.sync, ...d };
  if (wasRunning && d.running === false) state.sync.finishedAt = Date.now();
  if (d.running === false && !d.cancelled) loadSeasonWeeks();
  notify('sync');
}

export async function init() {
  await bridge.ready();
  const info = await bridge.request('init');
  takeSnapshot(info);
  state.version = info.version || '';
  state.teams = asArray(info.teams);
  state.byId = new Map(state.teams.map((t) => [t.id, t]));
  for (const t of state.teams) if (t.crest) state.crests.set(t.id, `${CREST_BASE}${t.id}.png`);
  state.seasonStart = info.seasonStart || '';
  state.update.note = info.updateNote || null;
  state.hostMode = info.mode || 'standalone';
  state.hostTheme = info.theme || '';
  applyTheme();

  // host events (dash contract): launcher theme, tab shown again, kill switch
  bridge.on('host.theme', (d) => { state.hostTheme = (d && d.theme) || ''; applyTheme(); });
  bridge.on('host.visible', () => { if (state.settings.autoRefresh && !state.halted) refresh().catch(() => {}); notify('visible'); });
  bridge.on('host.hidden', () => notify('hidden'));
  bridge.on('traffic', (d) => { state.halted = !!(d && d.stopped); notify('traffic'); });
  bridge.on('data', onData);
  bridge.on('sync', onSync);
  bridge.on('update', onUpdate);

  state.ready = true;
  notify('teams', 'favorites');
  loadSeasonWeeks();
  if (state.host && state.settings.updateCheck && !state.update.note) setTimeout(() => checkUpdate({ quiet: true }), 4000);
  return state;
}
