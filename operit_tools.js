// Operit 自定义工具脚本（JS）。
// 作用：把 KSU AI Bridge 的本地端点包装成 Operit Agent 可直接调用的语义工具。
// 用法：填好 PORT 与 TOKEN 后，在 Operit 自定义工具里注册本文件导出的函数。
// 注意：所有工具只访问 127.0.0.1，不对外网暴露。

const HOST = 'http://127.0.0.1:38888';
const TOKEN = '在这里填入 SettingsActivity 里显示的 token';

async function call(path, method, body) {
  const res = await fetch(HOST + path, {
    method: method || 'GET',
    headers: {
      'X-Token': TOKEN,
      'Content-Type': 'application/json'
    },
    body: body ? JSON.stringify(body) : undefined
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error('bridge ' + res.status + ': ' + text);
  }
  const json = JSON.parse(text);
  if (!json.ok) {
    throw new Error(json.error || 'bridge error');
  }
  return json.data;
}

// L0 只读
export async function ksu_ping() {
  return await call('/ping');
}

export async function ksu_status() {
  return await call('/status');
}

export async function ksu_list_modules() {
  return await call('/modules');
}

export async function ksu_superuser() {
  return await call('/superuser');
}

export async function ksu_features() {
  return await call('/feature');
}

// L1 低危写
export async function ksu_toggle_module(id, enabled) {
  return await call('/module/' + (enabled ? 'enable' : 'disable'), 'POST', { id: id });
}

export async function ksu_module_action(id) {
  return await call('/module/action', 'POST', { id: id });
}

// L2 高危写（调用前必须用户二次确认）
export async function ksu_install_module(zipPath) {
  return await call('/module/install', 'POST', { path: zipPath });
}

export async function ksu_uninstall_module(id) {
  return await call('/module/uninstall', 'POST', { id: id });
}

export async function ksu_root_exec(cmd, timeout) {
  return await call('/root/exec', 'POST', { cmd: cmd, timeout: timeout || 30 });
}

export async function ksu_reboot(mode) {
  return await call('/reboot', 'POST', { mode: mode || 'normal' });
}
