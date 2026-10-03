// omp deployment: <agent-dir>/AGENTS.md + RULES.md + skills/sec-forge.
// omp = oh-my-pi (fork of pi); agent dir defaults to ~/.omp/agent.
// SYSTEM.md is deliberately never written — it replaces omp's default system prompt.
'use strict';

const os = require('os');
const fs = require('fs');
const path = require('path');

const HOME = os.homedir();
const OMP_DIR = process.env.OMP_AGENT_DIR || path.join(HOME, '.omp', 'agent');
const CCF = path.resolve(__dirname, '..', 'cc-unlock-files');
// Electron also defines resourcesPath in development; only an app inside it is packaged.
const resourceRelative = process.resourcesPath ? path.relative(path.resolve(process.resourcesPath), __dirname) : null;
const PACKAGED = resourceRelative !== null && !path.isAbsolute(resourceRelative) &&
  resourceRelative !== '..' && !resourceRelative.startsWith('..' + path.sep);
const OMP_BUNDLE = path.join(PACKAGED ? process.resourcesPath : path.resolve(__dirname, '..', 'omp-files'), 'omp-config-bundle');
const SKILL_BUNDLE = path.join(PACKAGED ? process.resourcesPath : CCF, 'skill-bundle');
const CARRIERS = [
  { name: 'AGENTS.md', label: 'persona overlay' },
  { name: 'RULES.md', label: 'sticky rules' },
];
const SYSTEM_MD = path.join(OMP_DIR, 'SYSTEM.md');
const SKILL_DIRS = ['sec-forge'];
const PATHS = { HOME, OMP_DIR, OMP_BUNDLE, SKILL_BUNDLE, SYSTEM_MD, CCF };

const exists = (p) => { try { return fs.existsSync(p); } catch { return false; } };
const logger = (log) => typeof log === 'function' ? log : () => {};
const readBytes = (file) => fs.readFileSync(file);
const sameBytes = (a, b) => a.length === b.length && a.equals(b);
const carrierSrc = (name) => path.join(OMP_BUNDLE, name);
const carrierDst = (name) => path.join(OMP_DIR, name);

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

function removeMatchingTree(src, dst) {
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
  say('head', 'omp 配置');
  for (const { name } of CARRIERS) {
    if (!exists(carrierSrc(name))) { say('fail', `缺少 omp 包文件: ${carrierSrc(name)}`); return { ok: false, error: 'missing bundle' }; }
  }
  fs.mkdirSync(OMP_DIR, { recursive: true });
  for (const { name, label } of CARRIERS) {
    const src = readBytes(carrierSrc(name));
    const dst = carrierDst(name);
    if (exists(dst) && !sameBytes(readBytes(dst), src) && !force) {
      say('fail', `${dst} 已存在且内容不同。先核对，确认替换再勾选「强制覆盖」重试。`);
      return { ok: false, error: `existing ${name} differs` };
    }
    writeBytes(dst, src);
    say('ok', `${name} (${src.length} bytes) — ${label}`);
  }
  say('info', 'SYSTEM.md 未改动（替换它等于顶掉 omp 内置系统提示）');
  let files = 0;
  for (const dir of SKILL_DIRS) {
    const s = path.join(SKILL_BUNDLE, dir);
    if (!exists(s)) continue;
    copyTree(s, path.join(OMP_DIR, 'skills', dir));
    files += countFiles(path.join(OMP_DIR, 'skills', dir));
    say('ok', `skills/${dir}/ (${files} files)`);
  }
  say('done', 'omp 部署完成。重启 omp 生效。');
  return { ok: true, skillFiles: files };
}

function uninstall(log) {
  const say = logger(log);
  say('head', 'omp 卸载');
  if (!exists(OMP_DIR)) { say('warn', `${OMP_DIR} 不存在`); return { ok: true, removed: 0 }; }
  let removed = 0;
  for (const { name } of CARRIERS) {
    const dst = carrierDst(name);
    if (exists(dst) && sameBytes(readBytes(dst), readBytes(carrierSrc(name)))) {
      fs.rmSync(dst, { force: true });
      removed += 1;
      say('ok', `${name} 已移除`);
    } else {
      say('info', `${name} 不存在或已被修改，保留`);
    }
  }
  for (const dir of SKILL_DIRS) {
    const n = removeMatchingTree(path.join(SKILL_BUNDLE, dir), path.join(OMP_DIR, 'skills', dir));
    if (n) { removed += n; say('ok', `skills/${dir}/ 移除 ${n} 个文件`); }
  }
  say('info', 'SYSTEM.md 未改动');
  say('done', 'omp 卸载完成。');
  return { ok: true, removed };
}

function verify(log) {
  const say = logger(log);
  say('head', 'omp 验证');
  let ok = true;
  for (const { name } of CARRIERS) {
    const good = exists(carrierDst(name)) && sameBytes(readBytes(carrierDst(name)), readBytes(carrierSrc(name)));
    say(good ? 'ok' : 'fail', `${name} ${good ? `(${readBytes(carrierDst(name)).length} bytes)` : '缺失或与包内容不一致'}`);
    if (!good) ok = false;
  }
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
        const to = path.join(OMP_DIR, 'skills', dir, from.slice(base.length));
        if (!exists(to) || !sameBytes(readBytes(from), readBytes(to))) miss += 1;
      }
    };
    walk(s);
    say(miss === 0 ? 'ok' : 'fail', `skills/${dir} ${miss === 0 ? '完整' : `缺少/不一致 ${miss} 个文件`}`);
    if (miss) ok = false;
  }
  if (exists(SYSTEM_MD)) say('warn', 'SYSTEM.md 存在 — 它会替换 omp 内置系统提示');
  say(ok ? 'done' : 'fail', ok ? 'omp 验证通过。' : 'omp 验证未通过。');
  return { ok };
}

function countFiles(dir) {
  let n = 0;
  const walk = (d) => { for (const e of fs.readdirSync(d, { withFileTypes: true })) { if (e.isDirectory()) walk(path.join(d, e.name)); else if (e.isFile()) n += 1; } };
  if (exists(dir)) walk(dir);
  return n;
}

function detect() {
  const carriers = {};
  for (const { name } of CARRIERS) {
    carriers[name] = exists(carrierDst(name)) && sameBytes(readBytes(carrierDst(name)), readBytes(carrierSrc(name)));
  }
  return {
    ompDir: OMP_DIR,
    ompDirExists: exists(OMP_DIR),
    carriers,
    deployed: Object.values(carriers).every(Boolean),
    systemMdPresent: exists(SYSTEM_MD),
    skillFiles: countFiles(path.join(OMP_DIR, 'skills', 'sec-forge')),
  };
}

module.exports = { PATHS, CARRIERS, SKILL_DIRS, exists, deploy, uninstall, verify, detect };
