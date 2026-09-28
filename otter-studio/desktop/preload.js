// Gives the Studio page its native window controls, and nothing else.
'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('otterStudioWindow', {
  minimize: () => ipcRenderer.invoke('otter-studio:window', 'minimize'),
  toggleMaximize: () => ipcRenderer.invoke('otter-studio:window', 'maximize'),
  close: () => ipcRenderer.invoke('otter-studio:window', 'close'),
  onStateChange: (callback) => {
    ipcRenderer.on('otter-studio:window-state', (_event, state) => callback(state));
  }
});
