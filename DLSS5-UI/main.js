const { app, BrowserWindow, ipcMain, dialog, shell, Menu } = require('electron');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const SWAPPER = path.join(__dirname, '..', 'DLSS5-Swapper.ps1');
const LIB_FILE = path.join(__dirname, 'library.json');

let win = null;

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

ipcMain.handle('scan', (e, folder) => runSwapper(['-Scan', '-Json', '-GamePath', folder]));
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