(function () {
  'use strict';
  const runtime = window.ZRRuntime;
  if (!runtime || window.parent === window) return;
  let announced = false;
  let deviceLabel = '';
  const send = type => parent.postMessage({ type, deviceId: runtime.deviceId }, location.origin);
  function mountDeviceAction() {
    // Stable public test ids from the pinned vendor build. The original avatar
    // trigger, its menu, and the full settings page remain owned by ZCode.
    const profile = document.querySelector('[data-testid="login-trigger"]');
    const footer = profile?.closest('footer');
    if (!footer || footer.querySelector('[data-zr-device-action]')) return;
    const button = document.createElement('button');
    button.type = 'button';
    button.dataset.zrDeviceAction = '';
    button.className = 'zr-device-action';
    button.textContent = deviceLabel ? deviceLabel + ' · 切换设备' : '切换设备';
    button.setAttribute('aria-label', '切换设备');
    button.onclick = () => send('zr:show-devices');
    footer.prepend(button);
    if (!announced) { announced = true; send('zr:workspace-ready'); }
  }
  const style = document.createElement('style');
  style.textContent = '.zr-device-action{display:flex;width:100%;padding:8px 4px;border-top:1px solid var(--color-border);background:transparent;color:var(--color-foreground-subtle);font:inherit;font-size:12px;text-align:left;cursor:pointer}.zr-device-action:hover{color:var(--color-foreground)}';
  document.head.append(style);
  window.addEventListener('message', event => {
    if (event.source !== parent || event.origin !== location.origin || event.data?.type !== 'zr:device-label' || event.data.deviceId !== runtime.deviceId) return;
    if (typeof event.data.label !== 'string') return;
    deviceLabel = event.data.label;
    const button = document.querySelector('[data-zr-device-action]');
    if (button) button.textContent = deviceLabel + ' · 切换设备';
  });
  const observer = new MutationObserver(mountDeviceAction);
  observer.observe(document.documentElement, { childList: true, subtree: true });
  mountDeviceAction();
  window.addEventListener('pagehide', () => observer.disconnect(), { once: true });
})();
