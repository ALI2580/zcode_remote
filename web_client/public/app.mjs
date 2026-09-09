import { DeviceRegistry, runtimeSource } from '/src/device-registry.mjs';
import { SessionPool } from '/src/session-pool.mjs';

const registry = new DeviceRegistry();
const runtimeContainer = document.querySelector('#runtimes');
const statusById = new Map();
let toastTimer;
function notify(text) {
  document.querySelector('#status').textContent = text;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { document.querySelector('#status').textContent = ''; }, 3500);
}
const pool = new SessionPool(device => {
  const frame = document.createElement('iframe');
  frame.className = 'runtime-frame';
  frame.title = device.label;
  frame.referrerPolicy = 'no-referrer';
  frame.src = runtimeSource(device);
  runtimeContainer.append(frame);
  statusById.set(device.id, '正在连接');
  return {
    frame,
    setVisible(visible) { frame.hidden = !visible; frame.inert = !visible; },
    dispose() { frame.remove(); statusById.delete(device.id); },
  };
});
function activate(device) {
  pool.activate(device);
  runtimeContainer.hidden = false;
  document.querySelector('#devices-page').hidden = true;
  document.querySelector('#switch-dialog').close();
  document.querySelector('#connecting-devices').hidden = statusById.get(device.id) === '工作区已加载';
  sendDeviceLabel(device.id);
  renderLists();
}
function sendDeviceLabel(id) {
  const runtime = pool.get(id), device = registry.get(id);
  if (runtime && device) runtime.frame.contentWindow.postMessage({ type: 'zr:device-label', deviceId: id, label: device.label }, location.origin);
}
function renderLists() {
  for (const selector of ['#device-list', '#switch-list']) {
    const list = document.querySelector(selector);
    list.replaceChildren();
    for (const device of registry.devices) {
      const row = document.createElement('button');
      row.className = 'device-row';
      const label = document.createElement('strong');
      label.textContent = device.label;
      const state = document.createElement('span');
      state.textContent = device.id === pool.activeId ? '当前设备' : statusById.get(device.id) || '未连接';
      row.append(label, state);
      row.onclick = () => activate(device);
      list.append(row);
    }
  }
  document.querySelector('#empty-state').hidden = registry.devices.length > 0;
}
function showAdd() { document.querySelector('#add-error').textContent = ''; document.querySelector('#add-dialog').showModal(); }
document.querySelector('#add-device').onclick = showAdd;
document.querySelector('#connecting-devices').onclick = () => { renderLists(); document.querySelector('#switch-dialog').showModal(); };
document.querySelector('#switch-add').onclick = () => { document.querySelector('#switch-dialog').close(); showAdd(); };
document.querySelectorAll('[data-close]').forEach(button => { button.onclick = () => document.getElementById(button.dataset.close).close(); });
document.querySelector('#add-form').addEventListener('submit', event => {
  event.preventDefault();
  const form = event.currentTarget;
  try {
    const device = registry.upsert(form.elements.remoteUrl.value, form.elements.label.value);
    form.reset();
    document.querySelector('#add-dialog').close();
    activate(device);
  } catch (error) { document.querySelector('#add-error').textContent = error.message; }
});
window.addEventListener('message', event => {
  if (event.origin !== location.origin || !event.data || typeof event.data.deviceId !== 'string') return;
  const runtime = pool.get(event.data.deviceId);
  if (!runtime || event.source !== runtime.frame.contentWindow) return;
  if (event.data.type === 'zr:workspace-ready') {
    statusById.set(event.data.deviceId, '工作区已加载');
    sendDeviceLabel(event.data.deviceId);
    if (event.data.deviceId === pool.activeId) document.querySelector('#connecting-devices').hidden = true;
    renderLists();
    notify('工作区已加载');
  }
  if (event.data.type === 'zr:show-devices') {
    renderLists();
    document.querySelector('#switch-dialog').showModal();
  }
});
window.addEventListener('pagehide', event => { if (!event.persisted) pool.dispose(); });
renderLists();
