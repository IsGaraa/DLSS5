const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('dlss5', {
  invoke: (cmd, ...args) => ipcRenderer.invoke(cmd, ...args),
  getIcon: (exePath) => ipcRenderer.invoke('get-icon', exePath),
  checkUpdate: () => ipcRenderer.invoke('check-update'),
  applyUpdate: () => ipcRenderer.invoke('apply-update'),
  reportBug: (payload) => ipcRenderer.invoke('report-bug', payload),
  onLog: (cb) => ipcRenderer.on('log', (e, line) => cb(line))
});