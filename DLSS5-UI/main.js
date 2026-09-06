const { app, BrowserWindow, ipcMain, dialog, shell, Menu } = require('electron');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

const SWAPPER = path.join(__dirname, '..', 'DLSS5-Swapper.ps1');
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
      if (t && win) win.webContents.send('log', t);
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

function listBackups(folders) {
  const out = [];
  for (const dir of folders) {
    try {
      const mp = path.join(dir, '_DLSS5_Backup', 'manifest.json');
      if (!fs.existsSync(mp)) continue;
      const arr = JSON.parse(fs.readFileSync(mp, 'utf8'));
      const items = Array.isArray(arr) ? arr : (arr.entries || []);
      out.push({ dir, count: items.length, provider: arr && arr.provider, api: arr && arr.api });
    } catch (e) {}
  }
  return out;
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