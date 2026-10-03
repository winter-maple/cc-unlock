// Pi deployment: <agent-dir>/AGENTS.md persona overlay + skills/sec-forge.
// pi = @earendil-works/pi-coding-agent; agent dir defaults to ~/.pi/agent.
// SYSTEM.md is deliberately never written — it replaces Pi's default system prompt.
'use strict';

const os = require('os');
const fs = require('fs');
const path = require('path');

const HOME = os.homedir();
const PI_DIR = process.env.PI_CODING_AGENT_DIR || path.join(HOME, '.pi', 'agent');
const CCF = path.resolve(__dirname, '..', 'cc-unlock-files');
// Electron also defines resourcesPath in development; only an app inside it is packaged.
const resourceRelative = process.resourcesPath ? path.relative(path.resolve(process.resourcesPath), __dirname) : null;
const PACKAGED = resourceRelative !== null && !path.isAbsolute(resourceRelative) &&
  resourceRelative !== '..' && !resourceRelative.startsWith('..' + path.sep);
const PI_BUNDLE = path.join(PACKAGED ? process.resourcesPath : path.resolve(__dirname, '..', 'pi-files'), 'pi-config-bundle');
const SKILL_BUNDLE = path.join(PACKAGED ? process.resourcesPath : CCF, 'skill-bundle');
const AGENTS_SRC = path.join(PI_BUNDLE, 'AGENTS.md');
const AGENTS_DST = path.join(PI_DIR, 'AGENTS.md');
const SYSTEM_MD = path.join(PI_DIR, 'SYSTEM.md');
const SKILL_DIRS = ['sec-forge'];
const PATHS = { HOME, PI_DIR, PI_BUNDLE, SKILL_BUNDLE, AGENTS_SRC, AGENTS_DST, SYSTEM_MD, CCF };

const exists = (p) => { try { return fs.existsSync(p); } catch { return false; } };
const logger = (log) => typeof log === 'function' ? log : () => {};
const readBytes = (file) => fs.readFileSync(file);
const sameBytes = (a, b) => a.length === b.length && a.equals(b);

function assertNoLinks(file) {
  let current = path.resolve(file);
  while (true) {
    let st = null;
    try { st = fs.lstatSync(current); } catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (st && st.isSymbolicLink()) throw new Error(`Refusing linked/junction target: ${current}`);
    const parent = path.dirname(current);
    if (parent === current) break;
    current = parent;
  }
}

function writeBytes(file, bytes) {
  assertNoLinks(file);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.tmp-${process.pid}`;
  fs.writeFileSync(tmp, bytes);
  fs.renameSync(tmp, file);
}

// Copy every file under src into dst, preserving relative layout, refusing linked targets.
function copyTree(src, dst) {
  assertNoLinks(dst);
  const base = path.resolve(src).replace(/[\\/]+$/, '') + path.sep;
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const from = path.join(dir, entry.name);
      if (entry.isDirectory()) { walk(from); continue; }
      if (!entry.isFile()) continue;
      const to = path.join(dst, from.slice(base.length));
      assertNoLinks(to);
      fs.mkdirSync(path.dirname(to), { recursive: true });
      fs.copyFileSync(from, to);
    }
  };
  walk(src);
}

// Remove only files that match the bundle byte-for-byte; leave containers alone.
function removeMatchingTree(src, dst, log) {
  if (!exists(src) || !exists(dst)) return 0;
  assertNoLinks(dst);
  const base = path.resolve(src).replace(/[\\/]+$/, '') + path.sep;
  let removed = 0;
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const from = path.join(dir, entry.name);
      if (entry.isDirectory()) { walk(from); continue; }
      if (!entry.isFile()) continue;
      const to = path.join(dst, from.slice(base.length));
      if (exists(to) && sameBytes(readBytes(from), readBytes(to))) { fs.rmSync(to, { force: true }); removed += 1; }
    }
  };
  walk(src);
  return removed;
}

function deploy(opts, log) {
  const say = logger(log);
  const force = Boolean(opts && opts.force);
  say('head', 'Pi 配置');
  if (!exists(AGENTS_SRC)) { say('fail', `缺少 Pi 人格包: ${AGENTS_SRC}`); return { ok: false, error: 'missing bundle' }; }
  fs.mkdirSync(PI_DIR, { recursive: true });
  const src = readBytes(AGENTS_SRC);
  if (exists(AGENTS_DST) && !sameBytes(readBytes(AGENTS_DST), src) && !force) {
    say('fail', `${AGENTS_DST} 已存在且内容不同。先核对，确认替换再勾选「强制覆盖」重试。`);
    return { ok: false, error: 'existing AGENTS.md differs' };
  }
  writeBytes(AGENTS_DST, src);
  say('ok', `AGENTS.md (${src.length} bytes) — persona overlay`);
  say('info', 'SYSTEM.md 未改动（替换它等于顶掉 Pi 内置系统提示）');
  let files = 0;
  for (const dir of SKILL_DIRS) {
    const s = path.join(SKILL_BUNDLE, dir);
    if (!exists(s)) continue;
    copyTree(s, path.join(PI_DIR, 'skills', dir));
    files += countFiles(path.join(PI_DIR, 'skills', dir));
    say('ok', `skills/${dir}/ (${files} files)`);
  }
  say('done', 'Pi 部署完成。重启 pi 生效。');
  return { ok: true, agents: AGENTS_DST, skillFiles: files };
}

function uninstall(log) {
  const say = logger(log);
  say('head', 'Pi 卸载');
  if (!exists(PI_DIR)) { say('warn', `${PI_DIR} 不存在`); return { ok: true, removed: 0 }; }
  let removed = 0;
  if (exists(AGENTS_DST) && sameBytes(readBytes(AGENTS_DST), readBytes(AGENTS_SRC))) {
    fs.rmSync(AGENTS_DST, { force: true });
    removed += 1;
    say('ok', 'AGENTS.md 已移除');
  } else {
    say('info', 'AGENTS.md 不存在或已被修改，保留');
  }
  for (const dir of SKILL_DIRS) {
    const n = removeMatchingTree(path.join(SKILL_BUNDLE, dir), path.join(PI_DIR, 'skills', dir), log);
    if (n) { removed += n; say('ok', `skills/${dir}/ 移除 ${n} 个文件`); }
  }
  say('info', 'SYSTEM.md 未改动');
  say('done', 'Pi 卸载完成。');
  return { ok: true, removed };
}

function verify(log) {
  const say = logger(log);
  say('head', 'Pi 验证');
  const agentsOk = exists(AGENTS_DST) && sameBytes(readBytes(AGENTS_DST), readBytes(AGENTS_SRC));
  say(agentsOk ? 'ok' : 'fail', `AGENTS.md ${agentsOk ? `(${readBytes(AGENTS_DST).length} bytes)` : '缺失或与包内容不一致'}`);
  let ok = agentsOk;
  for (const dir of SKILL_DIRS) {
    const s = path.join(SKILL_BUNDLE, dir);
    if (!exists(s)) continue;
    const base = path.resolve(s).replace(/[\\/]+$/, '') + path.sep;
    let miss = 0;
    const walk = (d) => {
      for (const entry of fs.readdirSync(d, { withFileTypes: true })) {
        const from = path.join(d, entry.name);
        if (entry.isDirectory()) { walk(from); continue; }
        if (!entry.isFile()) continue;
        const to = path.join(PI_DIR, 'skills', dir, from.slice(base.length));
        if (!exists(to) || !sameBytes(readBytes(from), readBytes(to))) miss += 1;
      }
    };
    walk(s);
    say(miss === 0 ? 'ok' : 'fail', `skills/${dir} ${miss === 0 ? '完整' : `缺少/不一致 ${miss} 个文件`}`);
    if (miss) ok = false;
  }
  if (exists(SYSTEM_MD)) say('warn', 'SYSTEM.md 存在 — 它会替换 Pi 内置系统提示');
  say(ok ? 'done' : 'fail', ok ? 'Pi 验证通过。' : 'Pi 验证未通过。');
  return { ok };
}

function countFiles(dir) {
  let n = 0;
  const walk = (d) => { for (const e of fs.readdirSync(d, { withFileTypes: true })) { if (e.isDirectory()) walk(path.join(d, e.name)); else if (e.isFile()) n += 1; } };
  if (exists(dir)) walk(dir);
  return n;
}

function detect() {
  return {
    piDir: PI_DIR,
    piDirExists: exists(PI_DIR),
    agentsSrc: AGENTS_SRC,
    agentsDeployed: exists(AGENTS_DST) && sameBytes(readBytes(AGENTS_DST), readBytes(AGENTS_SRC)),
    agentsExists: exists(AGENTS_DST),
    systemMdPresent: exists(SYSTEM_MD),
    skillDirs: SKILL_DIRS.length,
    skillFiles: countFiles(path.join(PI_DIR, 'skills', 'sec-forge')),
  };
}

module.exports = { PATHS, SKILL_DIRS, exists, deploy, uninstall, verify, detect };
