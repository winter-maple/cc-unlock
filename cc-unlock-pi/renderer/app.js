'use strict';
const { api, real, $, $$, log, tile, page } = window.CCUI;
let running = false;

$$('.nav__item').forEach((button) => button.addEventListener('click', () => page(button.dataset.page)));

const out = () => $('#console2');
const logLine = (kind, text) => log(out(), kind, text);

async function overview() {
  const env = await api.detect();
  if (!real) {
    ['#tPiDir', '#tAgents', '#tSkills', '#tSystem'].forEach((id) => tile(id, '预览'));
    $('#hdrMeta').textContent = 'v3.0.1-stable · 界面预览（不执行操作）';
    return;
  }
  tile('#tPiDir', env.piDirExists ? '已检测' : '缺失', env.piDirExists ? 'ok' : 'warn', env.piDir || '');
  tile('#tAgents', env.agentsDeployed ? '已注入' : env.agentsExists ? '不一致' : '缺失',
    env.agentsDeployed ? 'ok' : env.agentsExists ? 'warn' : 'warn');
  tile('#tSkills', String(env.skillFiles || 0), (env.skillFiles ? 'ok' : 'warn'), 'sec-forge');
  tile('#tSystem', env.systemMdPresent ? '存在' : '无', env.systemMdPresent ? 'warn' : 'ok');
}

async function paths() {
  const value = await api.paths();
  $('#pBundle').value = value.bundle || '';
  $('#pPiDir').value = value.piDir || '';
  $('#pAgents').value = value.agents || '';
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
  if (!confirm('卸载 ~/.pi/agent 中本工具管理的内容？')) return;
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
