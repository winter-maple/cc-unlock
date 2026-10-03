'use strict';
const { api, real, $, $$, log, tile, page } = window.CCUI;
let running = false;

$$('.nav__item').forEach((button) => button.addEventListener('click', () => page(button.dataset.page)));

const out = () => $('#console2');
const logLine = (kind, text) => log(out(), kind, text);

async function overview() {
  const env = await api.detect();
  if (!real) {
    ['#tOmpDir', '#tAgents', '#tRules', '#tSkills', '#tSystem'].forEach((id) => tile(id, '预览'));
    $('#hdrMeta').textContent = 'v3.0.1-stable · 界面预览（不执行操作）';
    return;
  }
  const carriers = env.carriers || {};
  tile('#tOmpDir', env.ompDirExists ? '已检测' : '缺失', env.ompDirExists ? 'ok' : 'warn', env.ompDir || '');
  tile('#tAgents', carriers['AGENTS.md'] ? '已注入' : '不一致', carriers['AGENTS.md'] ? 'ok' : 'warn');
  tile('#tRules', carriers['RULES.md'] ? '已注入' : '不一致', carriers['RULES.md'] ? 'ok' : 'warn');
  tile('#tSkills', String(env.skillFiles || 0), (env.skillFiles ? 'ok' : 'warn'), 'sec-forge');
  tile('#tSystem', env.systemMdPresent ? '存在' : '无', env.systemMdPresent ? 'warn' : 'ok');
}

async function paths() {
  const value = await api.paths();
  $('#pBundle').value = value.bundle || '';
  $('#pOmpDir').value = value.ompDir || '';
  $('#pAgents').value = value.agents || '';
  $('#pRules').value = value.rules || '';
}

async function run(kind, label) {
  if (running) return;
  running = true;
  const controls = $$('#page-deploy button');
  controls.forEach((node) => { node.disabled = true; });
  out().replaceChildren();
  try {
    const result = kind === 'deploy'
      ? await api.deploy({ force: $('#chkForce')?.checked === true }, logLine)
      : kind === 'verify'
        ? await api.verify(logLine)
        : await api.uninstall(logLine);
    if (result && result.ok === false) logLine('fail', result.error || `${label}未通过，详情见日志。`);
    await Promise.all([overview(), paths()]);
  } catch (error) {
    logLine('fail', error && error.message || String(error));
  } finally {
    running = false;
    controls.forEach((node) => { node.disabled = false; });
  }
}

$('#btnDeploy').addEventListener('click', () => run('deploy', '部署'));
$('#btnVerify').addEventListener('click', () => run('verify', '验证'));
$('#btnUninstall').addEventListener('click', () => {
  if (!confirm('卸载 ~/.omp/agent 中本工具管理的内容？')) return;
  run('uninstall', '卸载');
});
$('#btnRefresh').addEventListener('click', async () => {
  if (running) return;
  $('#btnRefresh').disabled = true;
  try { await Promise.all([overview(), paths()]); logLine('info', '状态已刷新。'); }
  catch (error) { logLine('fail', error.message); }
  finally { $('#btnRefresh').disabled = false; }
});

Promise.all([overview(), paths()]).catch((error) => logLine('fail', '读取部署状态失败：' + error.message));
