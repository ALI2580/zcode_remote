(function () {
  'use strict';
  try {
    const current = new URL(location.href);
    const id = current.pathname.startsWith('/runtime/') ? current.pathname.split('/').at(-1) : current.searchParams.get('zrDevice');
    if (!id || !/^[a-z0-9-]{8,64}$/i.test(id)) throw new Error('设备作用域无效');
    const remote = current.hash ? new URL(decodeURIComponent(current.hash.slice(1))) : current;
    if (current.hash && (remote.origin !== 'https://zcode.z.ai' || remote.pathname !== '/remote/v4')) throw new Error('连接来源无效');
    if (!remote.searchParams.get('sid') || !remote.searchParams.get('hash') || !/^\d+$/.test(remote.searchParams.get('t') || '')) throw new Error('连接参数无效');
    const allowed = ['sid', 'hash', 't', 'mid', 'name', 'app_version', 'theme'];
    const query = new URLSearchParams();
    for (const key of allowed) if (remote.searchParams.get(key)) query.set(key, remote.searchParams.get(key));
    query.set('zrDevice', id);
    history.replaceState(null, '', '/remote/v4?' + query.toString());
    const prefix = 'zr:device:' + id + ':';
    const stores = ['localStorage', 'sessionStorage'].map(name => {
      const native = window[name], scoped = ZRStorage.createScopedStorage(native, prefix);
      Object.defineProperty(window, name, { configurable: true, get: () => scoped });
      return { native, scoped };
    });
    const forwarded = new WeakSet();
    window.addEventListener('storage', event => {
      if (forwarded.has(event)) return;
      const store = stores.find(candidate => candidate.native === event.storageArea);
      if (!store) return;
      event.stopImmediatePropagation();
      const key = ZRStorage.unprefixEventKey(event.key, prefix);
      if (key === undefined) return;
      const translated = new StorageEvent('storage', { key, oldValue: event.oldValue, newValue: event.newValue, url: event.url });
      Object.defineProperty(translated, 'storageArea', { value: store.scoped });
      forwarded.add(translated);
      window.dispatchEvent(translated);
    }, true);
    window.ZRRuntime = Object.freeze({ deviceId: id });
    document.addEventListener('DOMContentLoaded', () => {
      const entry = document.querySelector('[data-zr-official-entry]');
      if (!entry) throw new Error('官方入口缺失');
      const module = document.createElement('script');
      module.type = 'module';
      module.src = entry.getAttribute('data-zr-official-entry');
      module.crossOrigin = 'anonymous';
      document.head.append(module);
    }, { once: true });
  } catch {
    document.addEventListener('DOMContentLoaded', () => {
      document.body.replaceChildren(Object.assign(document.createElement('p'), { textContent: '连接初始化失败，请返回设备列表重新添加链接。' }));
    }, { once: true });
  }
})();
