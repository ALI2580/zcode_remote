(function (root) {
  'use strict';
  function createScopedStorage(storage, prefix) {
    const keys = () => {
      const result = [];
      for (let index = 0; index < storage.length; index += 1) {
        const key = storage.key(index);
        if (key?.startsWith(prefix)) result.push(key.slice(prefix.length));
      }
      return result;
    };
    const api = {
      getItem(key) { return storage.getItem(prefix + String(key)); },
      setItem(key, value) { storage.setItem(prefix + String(key), String(value)); },
      removeItem(key) { storage.removeItem(prefix + String(key)); },
      clear() { for (const key of keys()) storage.removeItem(prefix + key); },
      key(index) { return keys()[Number(index)] ?? null; },
    };
    return new Proxy(Object.create(null), {
      get(_target, key) {
        if (key === 'length') return keys().length;
        if (key === Symbol.toStringTag) return 'Storage';
        if (Object.hasOwn(api, key)) return api[key];
        return typeof key === 'string' ? api.getItem(key) ?? undefined : undefined;
      },
      set(_target, key, value) { if (typeof key !== 'string') return false; api.setItem(key, value); return true; },
      deleteProperty(_target, key) { api.removeItem(key); return true; },
      ownKeys: keys,
      has(_target, key) { return key === 'length' || Object.hasOwn(api, key) || api.getItem(key) !== null; },
      getOwnPropertyDescriptor(_target, key) {
        const value = api.getItem(key);
        return value === null ? undefined : { enumerable: true, configurable: true, writable: true, value };
      },
    });
  }
  function unprefixEventKey(key, prefix) {
    return key === null ? null : key.startsWith(prefix) ? key.slice(prefix.length) : undefined;
  }
  root.ZRStorage = { createScopedStorage, unprefixEventKey };
})(globalThis);
