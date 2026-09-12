const { app, BrowserWindow, ipcMain, dialog, shell, Menu } = require('electron');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const os = require('os');

const SWAPPER = path.join(__dirname, '..', 'DLSS5-Swapper.ps1');
const REPO_ROOT = path.join(__dirname, '..');
const LIB_FILE = path.join(__dirname, 'library.json');
const CACHE_FILE = path.join(__dirname, 'library-cache.json');
const ICONS_DIR = path.join(__dirname, 'www', 'icons');
const ICONS_SCRIPT = path.join(__dirname, 'icons-extract.ps1');

let win = null;

const iconCache = new Map();
const iconPending = new Map();
let iconBatch = [];
let iconBatchTimer = null;

const FOLDER_LABELS = { '0': '0', '1': '1', '2': '2', '3': '3 (Lumenite Kernel)', '4': '4' };

function runSwapper(args) {
  return new Promise((resolve, reject) => {
    const ps = spawn('powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', SWAPPER].concat(args),
      { windowsHide: true });
    let out = '', err = '';
    ps.stdout.setEncoding('utf8');
    ps.stderr.setEncoding('utf8');
    ps.stdout.on('data', d => {
      out += d;
      const t = d.replace(/^\uFEFF/, '').trim();
      if (!t) return;
      if (t.startsWith('{') || t.startsWith('[')) return; // final JSON payload - parsed, not console noise
      if (win) win.webContents.send('log', t);
    });
    ps.stderr.on('data', d => {
      err += d;
      const t = d.trim();
      if (t && win) win.webContents.send('log', t);
    });
    ps.on('error', reject);
    ps.on('close', code => {
      if (code !== 0) return reject(new Error(err.trim() || ('swapper exited with code ' + code)));
      try {
        const json = out.replace(/^\uFEFF/, '').trim();
        resolve(json ? JSON.parse(json) : null);
      } catch (e) {
        reject(new Error('Bad JSON from swapper:\n' + out.slice(0, 800)));
      }
    });
  });
}

function buildInstallArgs(folder, o) {
  const a = ['-Install', '-Json', '-GamePath', folder];
  a.push('-Provider', o.provider);
  if (o.provider === 'chicken') a.push('-Passes', String(o.passes));
  if (o.api) a.push('-Api', o.api);
  a.push('-WorkResolution', String(o.res));
  a.push('-Style', o.style);
  a.push('-Preset', String(o.preset));
  a.push('-Intensity', String(o.intensity));
  a.push('-MVProvider', String(o.mv));
  if (o.cleanFry) a.push('-CleanFry');
  if (o.texBoost) a.push('-TextureBoost');
  if (o.uplift) a.push('-NeuralUplift');
  a.push('-Feeder', o.feeder);
  if (o.mfgAddon) a.push('-MFGAddon');
  if (o.exe) a.push('-Exe', o.exe);
  if (o.force) a.push('-Force');
  if (o.launch) a.push('-Launch');
  return a;
}

function loadLibrary() {
  try { return JSON.parse(fs.readFileSync(LIB_FILE, 'utf8')); }
  catch (e) { return []; }
}
function saveLibrary(list) {
  fs.writeFileSync(LIB_FILE, JSON.stringify(list, null, 2), 'utf8');
}
function loadLibraryCache() {
  try { return JSON.parse(fs.readFileSync(CACHE_FILE, 'utf8')); }
  catch (e) { return null; }
}
function saveLibraryCache(data) {
  fs.writeFileSync(CACHE_FILE, JSON.stringify(data, null, 2), 'utf8');
}

function runGit(args) {
  return new Promise((resolve, reject) => {
    const env = Object.assign({}, process.env, { GIT_TERMINAL_PROMPT: '0', GCM_INTERACTIVE: 'never' });
    const g = spawn('git', ['-C', REPO_ROOT].concat(args), { windowsHide: true, env });
    let out = '', err = '';
    g.stdout.setEncoding('utf8');
    g.stderr.setEncoding('utf8');
    g.stdout.on('data', d => out += d);
    g.stderr.on('data', d => err += d);
    g.on('error', reject);
    g.on('close', code => {
      if (code !== 0) return reject(new Error(err.trim() || out.trim() || ('git exited with code ' + code)));
      resolve(out.trim());
    });
  });
}

async function checkForUpdate() {
  try {
    const inRepo = await runGit(['rev-parse', '--is-inside-work-tree']).then(() => true, () => false);
    if (!inRepo) return { status: 'not-git' };
    const from = await runGit(['rev-parse', 'HEAD']);
    await runGit(['fetch', 'origin', 'main']);
    const to = await runGit(['rev-parse', 'origin/main']);
    const count = parseInt(await runGit(['rev-list', '--count', 'HEAD..origin/main']), 10) || 0;
    // Only a *behind* HEAD is an update. A local HEAD that is ahead of origin
    // (e.g. unpushed commits) must NOT fetch/nmerge/relaunch - previously this
    // reported "update-available" for from != to, then `merge --ff-only` was a
    // no-op and relaunched into an infinite update/restart loop.
    if (count <= 0) return { status: 'current', from: from, to: to, behind: 0 };
    return { status: 'update-available', from: from, to: to, behind: count };
  } catch (e) {
    return { status: 'error', message: e.message };
  }
}

async function applyUpdate() {
  try {
    const branch = await runGit(['rev-parse', '--abbrev-ref', 'HEAD']);
    if (branch !== 'main') return { ok: false, message: 'Not on branch "' + branch + '" - switch to main to update.' };
    await runGit(['merge', '--ff-only', 'origin/main']);
    runGit(['lfs', 'pull']).catch(() => {});
    setTimeout(() => { app.relaunch({ args: process.argv.slice(1) }); app.exit(0); }, 900);
    return { ok: true };
  } catch (e) {
    return { ok: false, message: e.message };
  }
}

function listBackups(folders) {
  const out = [];
  for (const dir of folders) {
    try {
      const bdir = path.join(dir, '_DLSS5_Backup');
      const mp = path.join(bdir, 'manifest.json');
      if (!fs.existsSync(mp)) continue;
      const arr = JSON.parse(fs.readFileSync(mp, 'utf8').replace(/^\uFEFF/, ''));
      const added = Array.isArray(arr.added) ? arr.added.map(String) : [];
      let size = 0;
      for (const f of fs.readdirSync(bdir)) {
        try { size += fs.statSync(path.join(bdir, f)).size; } catch (e) {}
      }
      out.push({
        dir,
        count: added.length,
        provider: arr && arr.provider,
        api: arr && arr.api,
        apiLabel: arr && arr.apiLabel,
        exe: arr && arr.exe,
        feeder: arr && arr.feeder,
        mfgAddon: !!(arr && arr.mfgAddon),
        date: arr && arr.date,
        size,
        added: added,
        replaced: Array.isArray(arr.replaced) ? arr.replaced.map(r => (r && r.file) || String(r)) : []
      });
    } catch (e) {}
  }
  return out;
}

async function reportBug(payload) {
  try {
    const head = await runGit(['rev-parse', '--short', 'HEAD']).catch(() => 'unknown');
    const remote = await runGit(['rev-parse', '--short', 'origin/main']).catch(() => 'unknown');
    const logTail = String((payload && payload.logTail) || '').split('\n').slice(-120).join('\n');
    const body = [
      '**Describe the bug or feature request**',
      '',
      '',
      '**Environment**',
      '- **App:** v2 (Electron ' + process.versions.electron + ' / Chromium ' + process.versions.chrome + ' / Node ' + process.versions.node + ')',
      '- **OS:** ' + os.platform() + ' ' + os.release(),
      '- **Git:** local ' + head + ' / remote main ' + remote,
      '- **Game:** ' + ((payload && payload.game) || 'not selected'),
      '',
      '**Console log tail**',
      '',
      '```',
      logTail,
      '```'
    ].join('\n');
    const url = 'https://github.com/IsGaraa/DLSS5/issues/new?title=' +
      encodeURIComponent('[Bug] DLSS 5 Swapper') + '&body=' + encodeURIComponent(body);
    await shell.openExternal(url);
    return { ok: true };
  } catch (e) {
    return { ok: false, message: e.message };
  }
}

async function getAppInfo() {
  let pkg = {};
  try { pkg = JSON.parse(fs.readFileSync(path.join(__dirname, 'package.json'), 'utf8')); } catch (e) {}
  const info = {
    name: pkg.productName || 'DLSS 5 Swapper',
    version: pkg.version || '0.0.0',
    electron: process.versions.electron,
    chrome: process.versions.chrome,
    node: process.versions.node,
    platform: process.platform,
    arch: process.arch,
    os: String(os.version() || os.release())
  };
  try {
    const inRepo = await runGit(['rev-parse', '--is-inside-work-tree']).then(() => true, () => false);
    info.repo = inRepo ? { remote: await runGit(['remote', 'get-url', 'origin']).catch(() => null) } : null;
  } catch (e) {}
  return info;
}

function iconKey(exePath) {
  return crypto.createHash('sha1').update(String(exePath).toLowerCase()).digest('hex').slice(0, 16);
}

function runPs(script, args) {
  return new Promise((resolve, reject) => {
    const ps = spawn('powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script].concat(args),
      { windowsHide: true });
    let out = '', err = '';
    ps.stdout.setEncoding('utf8');
    ps.stderr.setEncoding('utf8');
    ps.stdout.on('data', d => out += d);
    ps.stderr.on('data', d => err += d);
    ps.on('error', reject);
    ps.on('close', code => {
      if (code !== 0) return reject(new Error(err.trim() || ('script exited with code ' + code)));
      resolve(out.replace(/^\uFEFF/, '').trim());
    });
  });
}

function flushIconBatch() {
  iconBatchTimer = null;
  const requests = iconBatch;
  iconBatch = [];
  if (!requests.length) return;

  const miss = [];
  for (const r of requests) {
    if (iconCache.has(r.key)) continue;
    if (fs.existsSync(path.join(ICONS_DIR, r.key + '.png'))) {
      iconCache.set(r.key, 'icons/' + r.key + '.png');
    } else {
      miss.push(r);
    }
  }

  const settle = () => {
    for (const r of requests) {
      const pend = iconPending.get(r.key);
      if (pend) { iconPending.delete(r.key); pend.forEach(p => p(iconCache.get(r.key))); }
    }
  };

  if (!miss.length) return settle();

  const tmpJson = path.join(app.getPath('temp'), 'dlss5-icons-' + Date.now() + '.json');
  fs.writeFileSync(tmpJson, JSON.stringify({
    outDir: ICONS_DIR,
    icons: miss.map(r => ({ key: r.key, path: r.exe }))
  }));
  runPs(ICONS_SCRIPT, ['-JsonIn', tmpJson]).then(result => {
    let map = {};
    try { map = JSON.parse(result); } catch (e) {}
    for (const r of miss) {
      if (!iconCache.has(r.key)) iconCache.set(r.key, map[r.key] ? 'icons/' + r.key + '.png' : null);
    }
  }).catch(() => {
    for (const r of miss) if (!iconCache.has(r.key)) iconCache.set(r.key, null);
  }).finally(() => {
    try { fs.unlinkSync(tmpJson); } catch (e) {}
    settle();
  });
}

function getIconUrl(exePath) {
  return new Promise(resolve => {
    if (!exePath || !/\.exe$/i.test(exePath) || !fs.existsSync(exePath)) return resolve(null);
    const key = iconKey(exePath);
    if (iconCache.has(key)) return resolve(iconCache.get(key));
    if (!iconPending.has(key)) {
      iconPending.set(key, []);
      iconBatch.push({ key, exe: exePath });
      if (iconBatchTimer) clearTimeout(iconBatchTimer);
      iconBatchTimer = setTimeout(flushIconBatch, 120);
    }
    iconPending.get(key).push(resolve);
  });
}

function createWindow() {
  win = new BrowserWindow({
    width: 1240,
    height: 800,
    minWidth: 940,
    minHeight: 600,
    backgroundColor: '#0B0E13',
    title: 'DLSS 5 Swapper',
    titleBarStyle: 'hidden',
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      spellcheck: false
    }
  });
  win.loadFile(path.join(__dirname, 'www', 'index.html'));
  win.once('ready-to-show', () => win.show());
  win.on('closed', () => { win = null; });
}

Menu.setApplicationMenu(null);

ipcMain.handle('pick-folder', async () => {
  const r = await dialog.showOpenDialog(win, { properties: ['openDirectory'], title: 'Add a game folder' });
  if (r.canceled || !r.filePaths.length) return null;
  return r.filePaths[0];
});

ipcMain.handle('pick-exe', async () => {
  const r = await dialog.showOpenDialog(win, { properties: ['openFile'], filters: [{ name: 'Executables', extensions: ['exe'] }], title: 'Pick a specific executable' });
  if (r.canceled || !r.filePaths.length) return null;
  return r.filePaths[0];
});

ipcMain.handle('library-load', () => loadLibrary());
ipcMain.handle('library-save', (e, list) => { saveLibrary(list); return true; });
ipcMain.handle('library-cache-load', () => loadLibraryCache());
ipcMain.handle('library-cache-save', (e, data) => { saveLibraryCache(data); return true; });
ipcMain.handle('get-icon', (e, exePath) => getIconUrl(exePath));
ipcMain.handle('check-update', () => checkForUpdate());
ipcMain.handle('apply-update', () => applyUpdate());

ipcMain.handle('scan', (e, folder) => runSwapper(['-Scan', '-Json', '-GamePath', folder]));
ipcMain.handle('discover', (e, root, depth) => {
  const args = ['-Discover', '-Json'];
  if (root) { args.push('-Root', root, '-Depth', String(depth || 6)); }
  return runSwapper(args);
});
ipcMain.handle('install', (e, folder, opts) => runSwapper(buildInstallArgs(folder, opts)));
ipcMain.handle('verify', (e, folder) => runSwapper(['-Verify', '-Json', '-GamePath', folder]));
ipcMain.handle('uninstall', (e, folder) => runSwapper(['-Uninstall', '-Json', '-GamePath', folder]));
ipcMain.handle('backups', (e, folders) => listBackups(folders));
ipcMain.handle('report-bug', (e, payload) => reportBug(payload));
ipcMain.handle('app-info', () => getAppInfo());
ipcMain.handle('open-url', (e, url) => { if (url) shell.openExternal(String(url)); return true; });
ipcMain.handle('open-folder', (e, folder) => shell.openPath(folder));

ipcMain.handle('win-min', () => win.minimize());
ipcMain.handle('win-max', () => { if (win.isMaximized()) win.unmaximize(); else win.maximize(); return win.isMaximized(); });
ipcMain.handle('win-close', () => win.close());

app.whenReady().then(() => {
  createWindow();
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});