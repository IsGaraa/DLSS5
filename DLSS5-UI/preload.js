const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('dlss5', {
  invoke: (cmd, ...args) => ipcRenderer.invoke(cmd, ...args),
  getIcon: (exePath) => ipcRenderer.invoke('get-icon', exePath),
  onLog: (cb) => ipcRenderer.on('log', (e, line) => cb(line))
});