// Browser preview host, like NBADash's ui/dev/mock.js: open ui/index.html from a local web server (for example
// `python -m http.server` in the ui folder) and the page runs without PowerShell or WebView2. It answers the same
// commands as the backend, with PRETEND clubs and fixtures (ui/data/pretend-clubs.json). Dev only: the real host never loads this file.
//
// Keep this in step with modules/FADash.Host.psm1: same keys, same shapes. Keys:
//   score:<league>:<yyyy-mm-dd>   one day of matches        week:<league>:<monday>   seven days   standings:<league>   team:<club id>
let emit = () => {};
export function attach(fn) { emit = fn; }

const CLUBS = (await (await fetch(new URL('../data/pretend-clubs.json', import.meta.url))).json()).clubs;
const LEAGUE_NAMES = { pl: 'Premier League', ch: 'Championship', l1: 'League One', l2: 'League Two', cup: 'Cups' };
const SLUGS = Object.keys(LEAGUE_NAMES);
const clubsOf = (lg) => (lg === 'cup' ? CLUBS : CLUBS.filter((c) => c.league === lg));
const clubById = Object.fromEntries(CLUBS.map((c) => [c.id, c]));

// ?source=espn previews the REAL-source behaviour of the page (hidden switch in the host): no clubs until they are downloaded,
// crests fetched one by one, squads without appearance numbers. The data is still made up.
const ESPN = new URLSearchParams(location.search).get('source') === 'espn';
const known = new Set(ESPN ? [] : CLUBS.map((c) => c.id));
const settings = { theme: new URLSearchParams(location.search).get('theme') || 'system', autoRefresh: false, autoAck: false, refreshSeconds: 60, favorites: [], updateCheck: false };
const pretend = { live: 0, update: false, problem: false, fail: false };
const traffic = { requests: 0, bytes: 0, errors: 0, byKind: {}, byHost: {}, last: [] };
const saved = new Set();     // 'pl:2026-10-26'
let halted = false;

const seed = (s) => { let x = 17; for (const c of s) x = (x * 31 + c.charCodeAt(0)) % 2147483647; return () => (x = (x * 48271) % 2147483647) / 2147483647; };
const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const monday = (d) => { const x = new Date(d); x.setHours(12, 0, 0, 0); while (x.getDay() !== 1) x.setDate(x.getDate() - 1); return x; };
const seasonStart = () => { const d = new Date(); d.setDate(d.getDate() - 42); return monday(d); };

// ---- pretend squads --------------------------------------------------------------------------------------
const FIRST = ['Alex', 'Sam', 'Jordan', 'Riley', 'Casey', 'Morgan', 'Jamie', 'Taylor', 'Drew', 'Quinn', 'Avery', 'Rowan', 'Emery', 'Parker'];
const LAST = ['Hale', 'Moreau', 'Lindqvist', 'Okafor', 'Brandt', 'Castell', 'Rook', 'Vance', 'Pike', 'Ferro', 'Holm', 'Sato', 'Weller', 'Dunmore'];
const POS = ['GK', 'GK', 'DF', 'DF', 'DF', 'DF', 'DF', 'MF', 'MF', 'MF', 'MF', 'MF', 'FW', 'FW', 'FW', 'FW'];
function squad(id) {
  const rnd = seed(id);
  return POS.map((pos, i) => {
    const apps = 6 + Math.floor(rnd() * 5);
    const g = pos === 'FW' ? Math.floor(rnd() * 8) : pos === 'MF' ? Math.floor(rnd() * 4) : pos === 'DF' ? Math.floor(rnd() * 2) : 0;
    const a = pos === 'GK' ? 0 : Math.floor(rnd() * 5);
    return { id: `${id}${String(i).padStart(2, '0')}`, name: `${FIRST[Math.floor(rnd() * FIRST.length)]} ${LAST[Math.floor(rnd() * LAST.length)]}`, pos, apps, g, a, yc: Math.floor(rnd() * 4), rc: rnd() < 0.08 ? 1 : 0 };
  });
}
const surname = (n) => n.split(' ').slice(1).join(' ');

// ---- pretend matches --------------------------------------------------------------------------------------
const KICKOFFS = [[12, 30], [15, 0], [15, 0], [17, 30], [20, 0]];
function day(lg, dateIso) {
  const rnd = seed(lg + dateIso);
  const clubs = [...clubsOf(lg)].sort(() => rnd() - 0.5);
  const now = new Date(), isToday = dateIso === iso(now);
  // Match days: Saturday, Sunday and Tuesday, plus today whatever day it is (so the preview always has something live).
  if (!isToday && ![0, 2, 6].includes(new Date(`${dateIso}T12:00:00`).getDay())) return { league: lg, date: dateIso.replaceAll('-', ''), events: [] };
  const n = lg === 'cup' ? 2 : 3 + Math.floor(rnd() * 3);
  const events = [];
  for (let i = 0; i < n; i++) {
    const home = clubs[2 * i + 1], away = clubs[2 * i];
    let start;
    if (isToday) start = new Date(now.getTime() + [-130, -25, -70, 40, 150][i % 5] * 60000);
    else { const [hh, mm] = KICKOFFS[i % 5]; start = new Date(`${dateIso}T${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}:00`); }
    const e = (now - start) / 60000;                      // minutes since kick-off
    const fin = { home: Math.floor(rnd() * rnd() * 5.2), away: Math.floor(rnd() * rnd() * 4.6) };
    const goals = ['home', 'away'].flatMap((s) => Array.from({ length: fin[s] }, () => ({ side: s, min: 1 + Math.floor(rnd() * 90), who: surname(squad(s === 'home' ? home.id : away.id)[8 + Math.floor(rnd() * 8)].name) }))).sort((x, y) => x.min - y.min);
    let state = 'pre', phase = 'pre', clock = '', p = 0;
    if (dateIso < iso(now) || e >= 111) { state = 'post'; phase = 'FT'; p = 120; }
    else if (e >= 0) {
      state = 'in';
      if (e < 45) { phase = '1H'; p = Math.max(1, Math.floor(e) + 1); clock = `${p}'`; }
      else if (e < 47) { phase = '1H'; p = 45; clock = `45+${Math.floor(e - 44)}'`; }
      else if (e < 62) { phase = 'HT'; p = 45; clock = 'HT'; }
      else { phase = '2H'; p = 46 + Math.floor(e - 62); clock = p > 90 ? `90+${p - 90}'` : `${p}'`; }
    }
    const shown = state === 'pre' ? [] : goals.filter((g) => g.min <= p);
    const side = (s, c) => {
      const mine = shown.filter((g) => g.side === s);
      return { side: s, id: c.id, abbr: c.abbr, score: state === 'pre' ? null : String(mine.length), pens: null,
        scorers: mine.map((g) => ({ min: g.min, name: g.who })) };
    };
    const sides = [side('away', away), side('home', home)];
    if (lg === 'cup' && state === 'post' && fin.home === fin.away) {       // cup ties cannot end level: penalties
      phase = 'PENS'; const w = rnd() < 0.5 ? 'home' : 'away', hi = 3 + Math.floor(rnd() * 3);
      sides.forEach((s) => { s.pens = String(s.side === w ? hi : hi - 1 - Math.floor(rnd() * 2)); });
    }
    events.push({ id: `${lg}${dateIso.replaceAll('-', '')}${i}`, league: lg, comp: lg === 'cup' ? (rnd() < 0.5 ? 'FA Cup' : 'EFL Cup') : LEAGUE_NAMES[lg],
      state, phase, date: start.toISOString(), clock, detail: '', venue: `${home.name} ground (pretend)`, sides });
  }
  return { league: lg, date: dateIso.replaceAll('-', ''), events };
}

function standings(lg) {
  const r = Object.fromEntries(clubsOf(lg).map((c) => [c.id, { id: c.id, abbr: c.abbr, gp: 0, w: 0, d: 0, l: 0, gf: 0, ga: 0, pts: 0, form: [] }]));
  for (let d = seasonStart(); iso(d) < iso(new Date()); d.setDate(d.getDate() + 1)) {
    for (const e of day(lg, iso(d)).events) {
      const [aw, hm] = e.sides;
      for (const [me, op] of [[aw, hm], [hm, aw]]) {
        const t = r[me.id]; if (!t) continue;
        t.gp++; t.gf += +me.score; t.ga += +op.score;
        if (+me.score > +op.score) { t.w++; t.pts += 3; t.form.push('W'); } else if (+me.score === +op.score) { t.d++; t.pts++; t.form.push('D'); } else { t.l++; t.form.push('L'); }
      }
    }
  }
  const rows = Object.values(r).map((t) => ({ ...t, form: t.form.slice(-5) }));
  rows.sort((x, y) => y.pts - x.pts || (y.gf - y.ga) - (x.gf - x.ga) || y.gf - x.gf || x.abbr.localeCompare(y.abbr));
  return { league: lg, teams: rows };
}
function body(key) {
  const [kind, a, b] = key.split(':');
  if (kind === 'score') return day(a, b);
  if (kind === 'week') { const m = new Date(`${b}T12:00:00`); return { league: a, monday: b, days: Array.from({ length: 7 }, (_, i) => { const d = new Date(m); d.setDate(d.getDate() + i); return day(a, iso(d)); }) }; }
  if (kind === 'team') return { id: a, players: squad(a).map((p, i) => (ESPN ? { ...p, no: String(i + 1), age: 18 + (i % 15), apps: null, g: null, a: null, yc: null, rc: null } : p)) };
  if (kind === 'clubs') return { league: a, clubs: clubsOf(a).map((c) => ({ id: c.id, abbr: c.abbr, name: c.name, color: c.color, league: a })) };
  if (kind === 'crest') return { id: a, file: `espn/crests/${a}.png` };
  return standings(a);
}
function valid(key) {
  const [kind, a, b] = key.split(':');
  if ((kind === 'score' || kind === 'week') && SLUGS.includes(a) && /^\d{4}-\d{2}-\d{2}$/.test(b || '')) return kind !== 'week' || new Date(`${b}T12:00:00`).getDay() === 1;
  if (kind === 'standings') return SLUGS.includes(a) && a !== 'cup';
  if (kind === 'team') return !!clubById[a] && known.has(a);
  if (ESPN && kind === 'clubs') return ['pl', 'ch', 'l1', 'l2'].includes(a);
  if (ESPN && kind === 'crest') return known.has(a);
  return false;
}
function fetchKey(key) {
  setTimeout(() => {
    const kind = key.split(':')[0];
    traffic.requests++;
    const host = ESPN ? 'site.api.espn.com' : kind === 'team' ? 'teams.pretend.invalid' : 'scores.pretend.invalid';
    traffic.byHost[host] ||= { requests: 0, bytes: 0, errors: 0 }; traffic.byHost[host].requests++;
    traffic.byKind[kind] ||= { requests: 0, bytes: 0 }; traffic.byKind[kind].requests++;
    if (pretend.fail) {
      traffic.errors++; traffic.byHost[host].errors++;
      traffic.last.unshift({ at: new Date().toISOString(), key, bytes: 0, ms: 0, ok: false });
      emit('data', { key, ok: false, error: 'Pretend download failure (Pretend data tools).' }); return;
    }
    const b = body(key); const n = JSON.stringify(b).length;
    traffic.bytes += n; traffic.byHost[host].bytes += n; traffic.byKind[kind].bytes += n;
    traffic.last.unshift({ at: new Date().toISOString(), key, bytes: n, ms: 180, ok: true }); traffic.last.length = Math.min(traffic.last.length, 40);
    if (kind === 'week') saved.add(key.slice(5));
    if (kind === 'clubs') for (const c of b.clubs) known.add(c.id);
    emit('data', { key, ok: true, cached: false, at: new Date().toISOString(), body: b });
  }, 150);
}
const snap = () => ({ source: ESPN ? 'espn' : 'pretend', mode: 'standalone', version: '0.1.0', theme: '', settings, pretend, halted, live: pretend.live, today: iso(new Date()), seasonStart: iso(seasonStart()),
  teams: CLUBS.filter((c) => known.has(c.id)).map((c) => ({ id: c.id, abbr: c.abbr, name: c.name, color: c.color, league: c.league })), traffic: { requests: traffic.requests, bytes: traffic.bytes, errors: traffic.errors } });
function weeks() {
  const out = [];
  for (let d = seasonStart(); d <= new Date(); d.setDate(d.getDate() + 7)) { const m = iso(d); out.push({ monday: m, leagues: SLUGS.filter((lg) => saved.has(`${lg}:${m}`)) }); }
  return out;
}

export async function request(cmd, args = {}) {
  await new Promise((r) => setTimeout(r, 20));
  switch (cmd) {
    case 'init': return snap();
    case 'season.weeks': return weeks();
    case 'watch.set': return true;
    case 'data.get':
      if (!valid(args.key)) throw new Error('unknown data key');
      if (halted) throw new Error('Data traffic is paused.');
      if (args.cacheOnly) {
        if (args.key.startsWith('week:') && saved.has(args.key.slice(5))) { emit('data', { key: args.key, ok: true, cached: true, at: new Date().toISOString(), body: body(args.key) }); return 'cached'; }
        return 'missing';
      }
      fetchKey(args.key); return 'queued';
    case 'settings.set': settings[args.key] = args.value; return snap();
    case 'pretend.set': pretend[args.key] = args.key === 'live' ? Math.max(0, args.value) : args.value; return snap();
    case 'traffic.get': return { uptimeSec: Math.round(performance.now() / 1000), ...traffic, last: traffic.last[0] ? traffic.last[0].key : '', lastList: traffic.last };
    case 'traffic.stop': halted = true; emit('traffic', { stopped: true }); return snap();
    case 'traffic.resume': halted = false; emit('traffic', { stopped: false }); return snap();
    case 'sync.run': {
      const keys = [];
      for (const w of weeks()) for (const lg of SLUGS) if (!w.leagues.includes(lg)) keys.push(`week:${lg}:${w.monday}`);
      for (const lg of SLUGS.filter((x) => x !== 'cup')) keys.push(`standings:${lg}`);
      let i = 0;
      const step = () => { if (i >= keys.length) { emit('sync', { running: false, pct: 100, exitCode: 0, summary: `${keys.length} requests`, lastRun: new Date().toISOString() }); return; }
        fetchKey(keys[i]); i++; emit('sync', { running: true, pct: Math.round(100 * i / keys.length), text: `Downloading ${i} of ${keys.length}` }); setTimeout(step, 120); };
      setTimeout(step, 50); return { started: true, requests: keys.length };
    }
    case 'sync.cancel': return true;
    case 'cache.clear': saved.clear(); return true;
    case 'update.check': setTimeout(() => emit('update', { running: false, action: 'Check', result: { status: 'none' } }), 300); return true;
    default: throw new Error(`mock: unknown command ${cmd}`);
  }
}
