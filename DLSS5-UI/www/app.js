const $ = (s) => document.querySelector(s);
const $$ = (s) => Array.from(document.querySelectorAll(s));
const api = window.dlss5;

window.onerror = (msg, src, line) => {
  try {
    const pre = document.getElementById('console-pre');
    if (pre) pre.innerHTML += '<span class="err">[RENDERER] ' + esc(msg) + ' (' + (src || '') + ':' + line + ')</span>\n';
  } catch (e) {}
  return false;
};

const state = {
  folders: [],
  library: [],
  selected: null,
  savedAt: null
};

const TITLES = {
  lib: ['Games library', 'Folders you added, scanned for executables and renderer.'],
  install: ['Install options', 'Provider, passes and tuning for the selected game.'],
  backups: ['Backups & history', 'Original files saved before an install - restore them anytime.'],
  console: ['Console', 'Live output from the DLSS5 backend.']
};

function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }
function ts() { return new Date().toTimeString().slice(0, 8); }

function toast(msg, ms) {
  const t = $('#toast');
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(toast.to);
  toast.to = setTimeout(() => t.classList.remove('show'), ms || 3400);
}
function setBusy(b) { document.body.classList.toggle('busy', b); }

function logLine(text, cls) {
  const s = '<span class="ts">[' + ts() + ']</span> ' + (cls ? '<span class="' + cls + '">' + esc(text) + '</span>' : esc(text));
  const pre = $('#console-pre');
  pre.innerHTML += s + '\n';
  while (pre.childNodes.length > 600) pre.removeChild(pre.firstChild);
  pre.scrollTop = pre.scrollHeight;
}
function logCls(l) {
  if (/!!|error|err\b|failed|fail\b|missing|refuse|not found|reject/i.test(l)) return 'err';
  if (/ok\b|installed|restored|done|built|ready|complete/i.test(l)) return 'ok';
  return '';
}

// ---------------------------------------------------------------- nav
let page = 'lib';
function showPage(p) {
  page = p;
  $$('.nav-btn').forEach(b => b.classList.toggle('active', b.dataset.page === p));
  $$('.page').forEach(pp => pp.classList.toggle('hidden', pp.id !== 'page-' + p));
  $('#page-title').textContent = TITLES[p][0];
  $('#page-sub').textContent = TITLES[p][1];
  if (p === 'backups') loadBackups();
  if (p === 'install') renderInstall();
}

// ---------------------------------------------------------------- library
function apiClass(a) {
  a = (a || '').toLowerCase();
  if (a.indexOf('d3d12') !== -1) return 'accent';
  if (a.indexOf('d3d11') !== -1) return 'cyan';
  if (a.indexOf('dxgi') !== -1) return 'blue';
  if (a.indexOf('vulkan') !== -1) return 'purple';
  if (a.indexOf('d3d9') !== -1 || a.indexOf('d3d8') !== -1) return 'amber';
  if (a.indexOf('opengl') !== -1) return 'cyan';
  return 'red';
}

function mkBtn(cls, txt, onClick) {
  const b = document.createElement('button');
  b.className = 'btn ' + cls;
  b.textContent = txt;
  b.onclick = onClick;
  return b;
}

function gameCard(g) {
  const card = document.createElement('div');
  card.className = 'card card-hover game-card';
  if (state.selected && state.selected.path === g.path) card.classList.add('selected');

  const thumb = document.createElement('div');
  thumb.className = 'cover-thumb';
  const iconImg = document.createElement('img');
  iconImg.alt = '';
  iconImg.draggable = false;
  const letter = document.createElement('span');
  letter.className = 'cover-letter';
  letter.textContent = (g.name || '?').trim().charAt(0).toUpperCase();
  thumb.appendChild(iconImg);
  thumb.appendChild(letter);
  api.getIcon(g.path).then(url => {
    if (url) { iconImg.src = url; letter.classList.add('has-icon'); }
  }).catch(() => {});

  const body = document.createElement('div');
  body.className = 'cover-body';

  const nm = document.createElement('div');
  nm.className = 'cover-name';
  nm.textContent = g.name;

  const chips = document.createElement('div');
  chips.className = 'chips cover-meta';
  const badge = document.createElement('span');
  badge.className = 'pill ' + (g.api ? apiClass(g.api) : 'amber');
  badge.textContent = g.api ? (g.label || g.api) : 'undetected';
  chips.appendChild(badge);
  if (g.native) chips.appendChild(chip('accent', 'Native DLSS'));
  if (g.reshade) chips.appendChild(chip('blue', 'ReShade ' + g.reshade.ver));
  if (g.bit) chips.appendChild(chip('dim', g.bit + '-bit'));
  if (g.via) chips.appendChild(chip('dim', g.via));

  const pth = document.createElement('div');
  pth.className = 'gc-path';
  pth.textContent = g.path;

  const btns = document.createElement('div');
  btns.className = 'gc-btns';
  const install = mkBtn('accent', 'Install', () => { state.selected = g; showPage('install'); });
  const verify = mkBtn('ghost', 'Verify', () => verifyGame(g));
  const open = mkBtn('ghost icon', '\u{1F4C2}', () => api.invoke('open-folder', g.dir));
  const un = mkBtn('danger', 'Restore', () => uninstallGame(g));
  if (!g.reshade && !g.native && g.api) un.textContent = 'Uninstall';
  un.style.marginLeft = 'auto';
  btns.appendChild(install);
  btns.appendChild(verify);
  btns.appendChild(open);
  btns.appendChild(un);

  body.appendChild(nm);
  body.appendChild(chips);
  body.appendChild(pth);
  body.appendChild(btns);

  card.appendChild(thumb);
  card.appendChild(body);
  return card;
}

function chip(cls, txt) {
  const c = document.createElement('span');
  c.className = 'chip ' + cls;
  c.textContent = txt;
  return c;
}

function renderLibrary() {
  const grid = $('#grid');
  grid.innerHTML = '';
  $('#lib-empty').classList.toggle('hidden', state.library.length > 0);
  for (const g of state.library) grid.appendChild(gameCard(g));
  let status = state.library.length + ' game' + (state.library.length === 1 ? '' : 's');
  if (state.savedAt) status += '\u00B7 last scan ' + new Date(state.savedAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  $('#lib-status').textContent = status;
}

function scanToEntries(r, dir, via) {
  const lib = [];
  const cands = r.candidates || [];
  const mainPath = (r.chosen && r.chosen.Path) || null;
  let main = cands.find(c => c.Main || (mainPath && c.Path === mainPath)) || cands[0];
  if (!main) return lib;
  const alternates = [];
  for (const c of cands) {
    if (c === main || c.Path === main.Path) continue;
    alternates.push({ path: c.Path, name: c.Name, bit: c.Bitness, api: c.Api || '', label: c.Label || '', via: c.Via || '' });
  }
  lib.push({
    dir: dir,
    path: main.Path,
    name: main.Name,
    bit: main.Bitness,
    api: main.Api || '',
    label: main.Label || '',
    via: via || main.Via || '',
    native: !!r.hasNativeDlss,
    reshade: (r.reshade && r.reshade.present) ? { ver: r.reshade.version || '?' } : null,
    alternates: alternates
  });
  return lib;
}

async function scanFolder(f) {
  const r = await api.invoke('scan', f);
  const entries = scanToEntries(r, f, '');
  logLine('scan ok: ' + f + ' (' + (r.candidates || []).length + ' exe, ' + entries.length + ' main)', 'ok');
  return entries;
}

async function rescan() {
  setBusy(true);
  try {
    const lib = [];
    for (let i = 0; i < state.folders.length; i++) {
      const f = state.folders[i];
      if (f) $('#lib-status').textContent = 'Scanning ' + f.split(/[\\/]/).pop() + ' (' + (i + 1) + '/' + state.folders.length + ')...';
      try {
        const entries = await scanFolder(f);
        lib.push.apply(lib, entries);
      } catch (e) {
        logLine('scan failed: ' + f + ' - ' + e.message, 'err');
      }
    }
    state.library = lib;
    state.selected = null;
    state.savedAt = Date.now();
    renderLibrary();
    renderInstall();
    try { await api.invoke('library-cache-save', { savedAt: state.savedAt, games: lib }); } catch (e) {}
  } finally {
    setBusy(false);
  }
}

// ---------------------------------------------------------------- auto-scan
function mergeFolders(list) {
  for (const f of list) {
    const hit = state.folders.find(x => x.toLowerCase() === String(f).toLowerCase());
    if (!hit) state.folders.push(f);
  }
}

async function runDiscover(root, depth) {
  setBusy(true);
  try {
    $('#lib-status').textContent = root ? 'Auto-scanning ' + root + ' (depth ' + depth + ')...' : 'Auto-scanning launchers...';
    logLine('discover: ' + (root ? 'deep scan of ' + root + ' ' : 'launcher roots'), '');
    const r = await api.invoke('discover', root, depth);
    const scans = (r && r.scans) || [];
    for (const s of scans) mergeFolders([s.gameDir]);
    await api.invoke('library-save', state.folders);
    const was = state.library.length;
    logLine('discover: ' + scans.length + ' playable folder(s) found, ' + state.folders.length + ' saved to library', 'ok');
    if (scans.length) await rescan();
    toast('Auto-scan done \u2014 ' + scans.length + ' game folder(s) found' + (was ? ' (library updated)' : ''));
  } catch (e) {
    toast('Auto-scan failed: ' + e.message);
    logLine('auto-scan failed: ' + e.message, 'err');
  } finally {
    setBusy(false);
  }
}

function autoScan() {
  const body = '<div class="m-intro">Auto-discovery scans your installed launchers or a whole drive for playable executables, identifies the renderer, and adds each found folder to the library. Found folders are saved, so a plain rescan later picks up newly installed games.</div>' +
    '<div class="m-opts"><button class="opt" id="d-launchers">Launchers \u00B7 Steam, GOG, Epic, EA, Ubisoft</button>' +
    '<button class="opt" id="d-deep">Deep scan \u00B7 a drive or folder</button></div>';
  showModal('Auto-scan games', body, [{ label: 'Close', cls: 'ghost', action: closeModal }]);
  $('#d-launchers').onclick = () => { closeModal(); runDiscover(null, 0); };
  $('#d-deep').onclick = () => {
    $('#m-body').innerHTML =
      '<div class="m-intro">Choose a drive or folder to deep-scan (up to 6 sub-folders deep, capped at 600 game folders). Folders without a top-level executable are skipped fast.</div>' +
      '<div class="d-root"><strong>Root:</strong> <input id="d-input" type="text" value="C:\\" spellcheck="false">' +
      '<button class="btn ghost" id="d-browse" type="button">Browse\u2026</button></div>' +
      '<div class="m-btns2"><span class="spacer"></span></div>';
    const btnBox = $('#m-btns');
    btnBox.innerHTML = '';
    btnBox.appendChild(mkBtn('ghost', 'Close', closeModal));
    btnBox.appendChild(mkBtn('accent', 'Scan', () => {
      const root = $('#d-input').value.trim();
      closeModal();
      if (root) runDiscover(root, 6);
    }));
    $('#d-browse').onclick = async () => {
      const f = await api.invoke('pick-folder');
      if (f) $('#d-input').value = f;
    };
  };
}

// ---------------------------------------------------------------- install
function renderInstall() {
  const g = state.selected;
  const gd = $('#inst-game');
  const eng = $('#inst-engine');
  const btn = $('#btn-install');
  const note = $('#inst-note');
  const exeWrap = $('#inst-exe-wrap');
  const exeSel = $('#o-exe');
  if (!g) {
    gd.innerHTML = '<b>No game selected</b>';
    eng.textContent = 'pick one in the library';
    eng.className = 'pill dim';
    btn.disabled = true;
    note.classList.add('hidden');
    exeWrap.classList.add('hidden');
    return;
  }
  gd.innerHTML = '<b>' + esc(g.name) + '</b><div class="gc-path" style="margin:4px 0 0">' + esc(g.path) + '</div>';
  eng.textContent = g.api ? (g.label || g.api) : 'undetected';
  eng.className = 'pill ' + (g.api ? apiClass(g.api) : 'amber');
  btn.disabled = false;
  exeWrap.classList.remove('hidden');
  exeSel.innerHTML = '';
  const opts = [{ name: g.name, api: g.label || '' }].concat(g.alternates || []);
  for (const o of opts) {
    const opt = document.createElement('option');
    opt.value = o.name;
    opt.textContent = o.name + (o.api ? '  (' + o.api + ')' : '');
    exeSel.appendChild(opt);
  }
  if (!g.api) {
    note.textContent = 'Renderer not detected for this executable. Default DXGI hook will be used - pick the exact API above if the game does not hook.';
    note.classList.remove('hidden');
  } else {
    note.classList.add('hidden');
  }
}

function readInstallOptions() {
  const exe = $('#o-exe').value || (state.selected ? state.selected.name : '');
  return {
    provider: state.provider,
    passes: parseInt($('#o-passes').value, 10),
    api: $('#o-api').value,
    res: parseInt($('#o-res').value, 10),
    style: $('#o-style').value,
    preset: parseInt($('#o-preset').value, 10) || 0,
    intensity: parseFloat($('#o-intensity').value) || 1,
    mv: $('#o-mv').value,
    feeder: $('#o-feeder').value,
    cleanFry: $('#o-cleanfry').checked,
    texBoost: $('#o-texboost').checked,
    uplift: $('#o-uplift').checked,
    force: $('#o-force').checked,
    launch: $('#o-launch').checked,
    exe: exe
  };
}

async function doInstall() {
  const g = state.selected;
  if (!g) return;
  setBusy(true);
  try {
    const r = await api.invoke('install', g.dir, readInstallOptions());
    const bits = [r.provider];
    if (r.passes) bits.push(r.passes + ' pass' + (r.passes === 1 ? '' : 'es'));
    if (r.api) bits.push(r.api);
    const msg = 'Installed into ' + r.exe + '  \u00B7  ' + bits.join('  \u00B7  ');
    toast('OK  \u2014  ' + msg);
    logLine('install OK: ' + msg, 'ok');
    logLine('manifest: ' + (r.manifestPath || ''), 'ok');
  } catch (e) {
    toast('Install failed: ' + e.message);
    logLine('install failed: ' + e.message, 'err');
  } finally {
    setBusy(false);
  }
}

// ---------------------------------------------------------------- verify / restore
async function verifyGame(g) {
  setBusy(true);
  try {
    const r = await api.invoke('verify', g.dir);
    if (!r) { toast('Nothing to verify - no DLSS5 install in that folder'); return; }
    const checks = (r.checks || []).map(c =>
      '<div class="vrow"><span class="ic ' + (c.Ok ? 'ok' : 'fail') + '">' + (c.Ok ? '\u2713' : '\u2717') + '</span>' +
      '<span>' + esc(c.Item) + '</span><span class="note2">' + esc(String(c.Note || '')) + '</span></div>').join('');
    showModal('Verify \u00B7 ' + r.exe,
      '<div class="m-intro">Loaded as <samp>' + esc(r.api || '?') + '</samp>' +
      (r.installed ? '  \u00B7  manifest found (provider <samp>' + esc(r.provider || '?') + '</samp>)' : '  \u00B7  not installed') + '</div>' +
      '<div class="vert">' + checks + '</div>',
      [{ label: 'Close', cls: 'ghost', action: closeModal }]);
  } catch (e) {
    toast(e.message);
  } finally {
    setBusy(false);
  }
}

function uninstallGame(g) {
  showModal('Restore originals', '<div class="m-intro">Remove the DLSS5 stack and restore the original files for <b>' + esc(g.name) + '</b>?</div>', [
    { label: 'Cancel', cls: 'ghost', action: closeModal },
    {
      label: 'Restore', cls: 'danger', action: async () => {
        closeModal();
        setBusy(true);
        try {
          const r = await api.invoke('uninstall', g.dir);
          toast('Restored ' + (r.restored || []).length + ' original(s), removed ' + (r.removed || []).length + ' file(s).');
          logLine('uninstall ok: ' + g.dir, 'ok');
        } catch (e) {
          toast('Restore failed: ' + e.message);
          logLine('uninstall failed: ' + e.message, 'err');
        } finally {
          setBusy(false);
        }
      }
    }
  ]);
}

// ---------------------------------------------------------------- backups
async function loadBackups() {
  $('#bk-status').textContent = 'Scanning folders...';
  const list = await api.invoke('backups', state.folders);
  const wrap = $('#bk-list');
  wrap.innerHTML = '';
  $('#bk-empty').classList.toggle('hidden', list.length > 0);
  for (const b of list) {
    const card = document.createElement('div');
    card.className = 'card card-hover';
    const name = document.createElement('div');
    name.className = 'gc-name';
    name.textContent = b.dir.split(/[\\/]/).pop();
    const pth = document.createElement('div');
    pth.className = 'gc-path';
    pth.textContent = b.dir;
    const chips = document.createElement('div');
    chips.className = 'chips';
    chips.appendChild(chip('accent', b.count + ' file' + (b.count === 1 ? '' : 's') + ' backed up'));
    if (b.provider) chips.appendChild(chip('dim', 'provider ' + b.provider));
    const btns = document.createElement('div');
    btns.className = 'gc-btns';
    btns.appendChild(mkBtn('danger', 'Restore originals', () => restoreBackup(b.dir)));
    btns.appendChild(mkBtn('ghost icon', '\u{1F4C2}', () => api.invoke('open-folder', b.dir)));
    card.appendChild(name);
    card.appendChild(pth);
    card.appendChild(chips);
    card.appendChild(btns);
    wrap.appendChild(card);
  }
  $('#bk-status').textContent = list.length + ' backup' + (list.length === 1 ? '' : 's') + ' found.';
}

function restoreBackup(dir) {
  showModal('Restore originals', '<div class="m-intro">Restore the original files for this game from its backup?</div>', [
    { label: 'Cancel', cls: 'ghost', action: closeModal },
    {
      label: 'Restore', cls: 'danger', action: async () => {
        closeModal();
        setBusy(true);
        try {
          const r = await api.invoke('uninstall', dir);
          toast('Restored ' + (r.restored || []).length + ' original(s).');
          logLine('restore ok: ' + dir, 'ok');
        } catch (e) {
          toast(e.message);
        } finally {
          setBusy(false);
          loadBackups();
        }
      }
    }
  ]);
}

// ---------------------------------------------------------------- modal
function showModal(title, bodyHtml, buttons) {
  $('#m-title').textContent = title;
  $('#m-body').innerHTML = bodyHtml;
  const wrap = $('#m-btns');
  wrap.innerHTML = '';
  for (const b of buttons) wrap.appendChild(mkBtn(b.cls, b.label, b.action));
  $('#modal').classList.remove('hidden');
}
function closeModal() { $('#modal').classList.add('hidden'); }

// ---------------------------------------------------------------- bindings
function bind() {
  $('#w-min').onclick = () => api.invoke('win-min');
  $('#w-max').onclick = () => api.invoke('win-max');
  $('#w-close').onclick = () => api.invoke('win-close');

  $$('.nav-btn').forEach(b => b.onclick = () => showPage(b.dataset.page));

  $('#btn-add').onclick = onAddFolder;
  $('#btn-add2').onclick = onAddFolder;
  $('#btn-scan2').onclick = () => rescan();
  $('#btn-rescan').onclick = () => rescan();
  $('#btn-autoscan').onclick = () => autoScan();
  $('#btn-refresh-bk').onclick = () => loadBackups();
  $('#btn-clear-log').onclick = () => {
    $('#console-pre').innerHTML = '';
  };

  $('#modal').onclick = (e) => { if (e.target.id === 'modal') closeModal(); };

  state.provider = 'chicken';
  $$('.seg').forEach(b => b.onclick = () => {
    state.provider = b.dataset.prov;
    $$('.seg').forEach(x => x.classList.toggle('on', x === b));
    $('#opt-chicken').classList.toggle('hidden', state.provider !== 'chicken');
    $('#opt-renodx').classList.toggle('hidden', state.provider !== 'renodx');
    $('#o-uplift').disabled = state.provider !== 'renodx';
    $('#o-passes').disabled = state.provider !== 'chicken';
  });

  const tgt = (id) => $('#o-' + id);
  $('#o-passes').oninput = () => $('#v-passes').textContent = tgt('passes').value + 'x';
  $('#o-res').oninput = () => $('#v-res').textContent = tgt('res').value + '%';
  $('#v-passes').textContent = tgt('passes').value + 'x';
  $('#v-res').textContent = tgt('res').value + '%';
  tgt('uplift').disabled = true;

  $$('.stepper button').forEach(b => b.onclick = () => {
    const inp = document.getElementById(b.dataset.tgt);
    let v = parseFloat(inp.value) || 0;
    v += b.dataset.add ? parseFloat(b.dataset.add) : -(parseFloat(b.dataset.step || 1));
    const min = parseFloat(b.dataset.min), max = parseFloat(b.dataset.max);
    if (v < min) v = min;
    if (v > max) v = max;
    inp.value = v;
  });

  $('#btn-install').onclick = doInstall;
}

async function onAddFolder() {
  const f = await api.invoke('pick-folder');
  if (!f) return;
  const isNew = state.folders.findIndex(x => x.toLowerCase() === f.toLowerCase()) === -1;
  if (isNew) {
    state.folders.push(f);
    await api.invoke('library-save', state.folders);
  }
  setBusy(true);
  try {
    $('#lib-status').textContent = 'Scanning ' + f.split(/[\\/]/).pop() + '...';
    const entries = await scanFolder(f);
    if (entries.length) {
      const byDir = new Map(state.library.map(g => [String(g.dir).toLowerCase(), g]));
      byDir.set(f.toLowerCase(), entries[0]);
      state.library = Array.from(byDir.values());
      logLine('added to library: ' + entries[0].name + ' (' + f + ')', 'ok');
    } else {
      logLine('no detectable executable in ' + f + ' - folder saved but no game card', 'warn');
    }
    state.savedAt = Date.now();
    renderLibrary();
    renderInstall();
    try { await api.invoke('library-cache-save', { savedAt: state.savedAt, games: state.library }); } catch (e) {}
  } catch (e) {
    logLine('scan failed: ' + f + ' - ' + e.message, 'err');
    toast('Scan failed: ' + e.message);
  } finally {
    setBusy(false);
  }
}

// ---------------------------------------------------------------- boot
(async function boot() {
  bind();
  api.onLog(line => logLine(line, logCls(line)));
  state.folders = await api.invoke('library-load');
  if (!Array.isArray(state.folders)) state.folders = [];
  logLine('DLSS 5 Swapper UI ready \u00B7 backend DLSS5-Swapper.ps1', 'ok');
  logLine('folders: ' + (state.folders.length ? state.folders.join('  \u00B7  ') : 'empty - add a game folder'), '');

  const cache = await api.invoke('library-cache-load');
  if (cache && Array.isArray(cache.games) && cache.games.length) {
    state.library = cache.games;
    state.savedAt = cache.savedAt || null;
    logLine('library loaded from saved scan (' + cache.games.length + ' games) - rescan to refresh', 'ok');
  } else {
    logLine(state.folders.length
      ? 'no saved scan yet - click Rescan to scan your folders'
      : 'no folders configured yet - add a game folder', '');
  }
  renderLibrary();
  setBusy(false);
  showPage('lib');
})();