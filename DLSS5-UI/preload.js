const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('dlss5', {
  invoke: (cmd, ...args) => ipcRenderer.invoke(cmd, ...args),
  onLog: (cb) => ipcRenderer.on('log', (e, line) => cb(line))
});