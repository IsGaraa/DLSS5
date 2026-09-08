const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('dlss5', {
  invoke: (cmd, ...args) => ipcRenderer.invoke(cmd, ...args),
  getIcon: (exePath) => ipcRenderer.invoke('get-icon', exePath),
  checkUpdate: () => ipcRenderer.invoke('check-update'),
  applyUpdate: () => ipcRenderer.invoke('apply-update'),
  reportBug: (payload) => ipcRenderer.invoke('report-bug', payload),
  appInfo: () => ipcRenderer.invoke('app-info'),
  openUrl: (url) => ipcRenderer.invoke('open-url', url),
  onLog: (cb) => ipcRenderer.on('log', (e, line) => cb(line))
});