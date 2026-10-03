// cc-unlock for omp — Electron main process (window + IPC).
// All deploy logic lives in deploy-core.js (pure Node, testable / CLI-reusable).
'use strict';

const { app, BrowserWindow, ipcMain, shell } = require('electron');
const path = require('path');
const core = require('./deploy-core');

const APP = __dirname;

function wireIpc() {
  ipcMain.handle('detect', () => core.detect());
  ipcMain.handle('paths', () => ({
    bundle: core.PATHS.OMP_BUNDLE,
    ompDir: core.PATHS.OMP_DIR,
    agents: path.join(core.PATHS.OMP_DIR, 'AGENTS.md'),
    rules: path.join(core.PATHS.OMP_DIR, 'RULES.md'),
  }));

  const actions = {
    deploy: { label: '部署', run: (opts, log) => core.deploy(opts, log) },
    uninstall: { label: '卸载', run: (_opts, log) => core.uninstall(log) },
    verify: { label: '验证', run: (_opts, log) => core.verify(log) },
  };
  for (const [channel, action] of Object.entries(actions)) {
    ipcMain.handle(channel, (ev, payload = {}) => {
      const log = (kind, text) => ev.sender.send(`${channel}-log`, { kind, text });
      try {
        const result = action.run(payload.opts || {}, log) || {};
        const ok = result.ok === true;
        if (!ok) log('fail', result.error || `${action.label}未通过。`);
        return { ok, result, ...(ok ? {} : { error: result.error || `${action.label}未通过。` }) };
      } catch (error) {
        const message = String(error && error.message || error);
        log('fail', message);
        return { ok: false, error: message };
      }
    });
  }

  ipcMain.handle('openExternal', (_e, url) => { if (/^https?:\/\//.test(url)) shell.openExternal(url); });
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1040, height: 720, minWidth: 860, minHeight: 560,
    backgroundColor: '#f5f5f2',
    title: 'cc-unlock for omp',
    webPreferences: { preload: path.join(APP, 'preload.js'), contextIsolation: true, nodeIntegration: false },
  });
  win.setMenuBarVisibility(false);
  win.loadFile(path.join(APP, 'renderer', 'index.html'));
}

app.whenReady().then(() => {
  wireIpc();
  createWindow();
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
