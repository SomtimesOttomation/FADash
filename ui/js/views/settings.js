// Settings: NBADash's overlay with tabs (General, Data, Sync), plus a Pretend data tab for trying the launcher while the
// data is made up. Copied from NBADash's views/settings.js; the NBA-only panels (ratings, nightly task, timing) are left out.
import * as S from '../store.js';
import * as bridge from '../bridge.js';
import { h, ago } from '../util.js';
import { teamLogo } from '../components.js';
import { openUpdate } from './update.js';
import { openTraffic } from './traffic.js';

function overlay(content) {
  const root = document.getElementById('overlay-root');
  const close = () => { root.replaceChildren(); document.removeEventListener('keydown', esc); };
  const esc = (e) => { if (e.key === 'Escape') close(); };
  document.addEventListener('keydown', esc);
  const o = h('div', { class: 'overlay', onclick: (e) => { if (e.target === o) close(); } }, h('div', { class: 'card modal' }, content(close)));
  root.replaceChildren(o);
  return close;
}
export { overlay };

const TAB_KEY = 'fadash.settingsTab';
let settingsTab = 'general';
try { const v = localStorage.getItem(TAB_KEY); if (['general', 'data', 'sync'].includes(v)) settingsTab = v; } catch (e) { /* ignore */ }

const hr = () => h('hr', { style: { border: 0, borderTop: '1px solid var(--line)' } });

function generalTab(close, repaint) {
  const s = S.state.settings;
  const favs = S.favSet();
  return [
    S.inLauncher()
      ? h('p', null, h('b', null, 'Theme '), h('small', null, 'Follows DashLauncher.'))
      : h('p', null, h('b', null, 'Theme '),
        [['system', 'System'], ['light', 'Light'], ['dark', 'Dark']].map(([t, label]) => h('button', { class: `btn ${s.theme === t ? 'primary' : ''}`, type: 'button', style: { marginRight: '6px' }, onclick: () => { S.saveSettings({ theme: t }); repaint(); } }, label))),
    hr(),
    h('p', null, h('b', null, 'Check for Updates')),
    h('p', null, h('label', null, h('input', { type: 'checkbox', checked: s.updateCheck ? true : null, onchange: (e) => S.saveSettings({ updateCheck: e.target.checked }) }),
      ' Check GitHub for a new version when the app starts '), h('button', { class: 'btn', type: 'button', style: { marginLeft: '8px' }, onclick: () => { close(); openUpdate(); } }, `v${S.state.version || '?'} - Check for updates`)),
    h('p', null, h('small', null, 'Off by default, so it contacts nothing on its own. It only ever talks to GitHub.')),
    hr(),
    h('p', null, h('b', null, 'Favorites '), favs.size ? [...favs].map((a) => h('span', { style: { marginRight: '6px' }, title: S.team(a)?.name || a }, teamLogo(a, 26))) : h('small', null, 'none yet \u2013 star a club in the banner')),
  ];
}

// Automatic refresh: off by default; turning it on needs the risk acknowledged (NBADash's wording, for your source).
let confirming = false;
function refreshPanel() {
  const box = h('div');
  const paint = () => {
    const s = S.state.settings;
    if (!s.autoRefresh) {
      const ack = h('input', { type: 'checkbox' });
      const go = h('button', { class: 'btn primary', type: 'button', disabled: true, onclick: () => { S.saveSettings({ autoRefresh: true }, true).catch(() => {}); confirming = false; paint(); } }, 'Turn on automatic refresh');
      ack.addEventListener('change', () => { go.disabled = !ack.checked; });
      box.replaceChildren(
        h('p', null, h('b', null, 'Data refresh: manual '), h('small', null, 'The dash only contacts its source when you press the refresh button (or F5), open a page, or run a sync.')),
        confirming
          ? h('div', { class: 'card pad warn' },
              h('b', null, 'Before you turn this on'),
              h('p', null, 'Automatic refresh polls the data source repeatedly while the app is open. Polling too often can get your connection rate-limited or blocked. You are responsible for the cadence you choose; the default is deliberately gentle.'),
              h('label', null, ack, ' I understand and accept this risk'),
              h('div', { style: { marginTop: '8px', display: 'flex', gap: '8px' } }, go, h('button', { class: 'btn', type: 'button', onclick: () => { confirming = false; paint(); } }, 'Cancel')))
          : h('button', { class: 'btn', type: 'button', onclick: () => { confirming = true; paint(); } }, 'Enable automatic refresh…'));
      return;
    }
    const secs = h('input', { type: 'number', min: 20, max: 600, step: 10, value: s.refreshSeconds, class: 'tune-input', onchange: (e) => S.saveSettings({ refreshSeconds: Number(e.target.value) }) });
    box.replaceChildren(
      h('p', null, h('b', null, 'Data refresh: automatic '), h('button', { class: 'btn', type: 'button', style: { marginLeft: '8px' }, onclick: () => { S.saveSettings({ autoRefresh: false }); paint(); } }, 'Switch back to manual')),
      h('p', null, h('small', { class: 'warn-text' }, 'Automatic refresh can get you rate-limited or blocked if set too aggressively.')),
      h('p', null, 'Today’s matches of the open league every ', secs, ' seconds while this tab is visible.'));
  };
  paint();
  return box;
}

function dataTab() {
  const t = S.state.sync;
  return [
    refreshPanel(),
    hr(),
    h('p', null, h('b', null, 'Data sources ')),
    h('div', { class: 'card pad fa-notice' }, h('b', null, 'ESPN DATA (unofficial). '), 'Scores, tables, clubs and squads come from ESPN\u2019s public JSON feeds. ESPN publishes no terms or limits for these feeds and they can change or stop at any time. FADash asks only when you ask (or when you turn automatic refresh on), at most one request per second, and never asks for betting data. Club crests are downloaded to your computer the first time each club is drawn.'),
    h('p', null, h('small', null, 'Every request is counted per server on the traffic page. Nothing from ESPN is stored in FADash\u2019s own files; the saved copies live in your cache folder and Clear saved data removes them (crest pictures stay, so they are not downloaded again).')),
    h('p', null, h('button', { class: 'btn', type: 'button', onclick: async () => { await bridge.request('cache.clear'); location.reload(); } }, 'Clear saved data'), ' ',
      h('button', { class: 'btn', type: 'button', onclick: () => openTraffic() }, 'Traffic details')),
    void t,
  ].filter(Boolean);
}

// Sync: NBADash's sync panel with one mode (the season so far, all leagues).
function syncPanel() {
  const box = h('div', { class: 'syncpanel' });
  const paint = () => {
    if (!box.isConnected && box.dataset.mounted) { unsub(); return; }
    box.dataset.mounted = '1';
    const sy = S.state.sync;
    const status = sy.running
      ? h('div', null, h('b', null, `${sy.pct ? sy.pct + '% · ' : ''}${sy.text || 'Starting...'}`), h('div', { class: 'bar' }, h('i', { style: { width: `${sy.pct || 3}%` } })), h('button', { class: 'btn', type: 'button', onclick: () => bridge.request('sync.cancel') }, 'Cancel update'))
      : h('small', null, sy.summary ? `Last result: ${sy.summary}` : `Last sync ${sy.lastRun ? ago(Date.parse(sy.lastRun)) : 'never'}`);
    box.replaceChildren(
      h('div', { style: { display: 'flex', gap: '8px', flexWrap: 'wrap' } },
        h('button', { class: 'btn', type: 'button', title: 'Every week of the season so far, for every league; weeks already saved are not downloaded again', disabled: sy.running || S.state.halted ? true : null, onclick: () => S.runSync().catch((e) => alert(e.message)) }, 'Sync the season')),
      h('div', { style: { marginTop: '10px', minHeight: '38px' } }, status));
  };
  const unsub = S.subscribe((t) => { if (t.has('sync')) paint(); });
  paint();
  return box;
}
function syncTab() {
  return [h('p', null, h('b', null, 'Season sync '), h('small', null, 'Downloads the season one week at a time. Progress also shows in the strip under the top bar and on the launcher’s tab.')), syncPanel()];
}

// Messages from the host (kept for debugging in the console: import { hostLog } from settings.js).
export const hostLog = [];

export function openSettings() {
  overlay((close) => {
    const body = h('div', { class: 'settings-body', role: 'tabpanel' });
    const tabs = h('div', { class: 'seg settings-tabs', role: 'tablist', 'aria-label': 'Settings sections' });
    const paint = () => {
      tabs.replaceChildren(...[['general', 'General'], ['data', 'Data'], ['sync', 'Sync']].map(([k, label]) => h('button', {
        type: 'button', role: 'tab', 'aria-selected': settingsTab === k ? 'true' : 'false', class: settingsTab === k ? 'active' : '',
        onclick: () => { settingsTab = k; try { localStorage.setItem(TAB_KEY, k); } catch (e) { /* ignore */ } paint(); } }, label)));
      body.replaceChildren(...(settingsTab === 'data' ? dataTab() : settingsTab === 'sync' ? syncTab() : generalTab(close, paint)));
    };
    paint();
    return h('div', null,
      h('h2', null, 'Settings'),
      tabs,
      body,
      h('p', { style: { textAlign: 'right' } }, h('button', { class: 'btn primary', type: 'button', onclick: close }, 'Done')));
  });
}
