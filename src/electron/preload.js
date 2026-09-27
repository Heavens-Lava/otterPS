// preload.js - The only code that runs in both worlds.
//
// It exposes a fixed, narrow set of functions to the compiled Otter page as
// window.otterNative. Nothing else crosses: no ipcRenderer, no Node modules,
// no way to reach a channel that is not listed here. The page's own runtime
// (from Otter's web compiler) prefers window.otterNative when it exists.

'use strict';

const { contextBridge, ipcRenderer } = require('electron');

// The main process answers { value } or { __otterError }; turn the latter
// back into an ordinary Error so Otter's try / otherwise sees it.
async function call(channel, ...args) {
  const result = await ipcRenderer.invoke(channel, ...args);
  if (result && result.__otterError) throw new Error(result.__otterError);
  return result ? result.value : undefined;
}

contextBridge.exposeInMainWorld('otterNative', {
  isElectron: true,
  platform: process.platform,

  files: {
    read: (filePath) => call('otter:fs:read', filePath).then((r) => r.content),
    write: (filePath, content) => call('otter:fs:write', filePath, content),
    download: (url, filePath) => call('otter:fs:download', url, filePath),
    list: (folderPath, includeSubfolders) => call('otter:fs:files', folderPath, Boolean(includeSubfolders)),
    operate: (operation, payload) => call('otter:fs:operate', operation, payload || {})
  },

  folders: {
    list: (folderPath, includeSubfolders) => call('otter:fs:folders', folderPath, Boolean(includeSubfolders))
  },

  commands: {
    exec: (command) => call('otter:terminal:exec', command)
  },

  clipboard: {
    write: (text) => call('otter:system:clipboard-write', text),
    read: () => call('otter:system:clipboard-read')
  },

  system: {
    notification: (title, message) => call('otter:system:notify', title, message),
    env: (name) => call('otter:system:env', name).then((r) => r.value),
    paths: () => call('otter:system:env', null)
  },

  dialogs: {
    openFile: () => call('otter:dialog:open-file').then((r) => r.path || ''),
    openFolder: () => call('otter:dialog:folder').then((r) => r.path || ''),
    save: () => call('otter:dialog:save-file').then((r) => r.path || '')
  }
});
