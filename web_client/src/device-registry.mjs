const allowedKeys = ['sid', 'hash', 't', 'mid', 'name', 'app_version', 'theme'];

export function parseRemoteUrl(raw) {
  let url;
  try { url = new URL(raw.trim()); } catch { throw new Error('请粘贴有效的 ZCode 远程控制链接'); }
  if (url.origin !== 'https://zcode.z.ai' || !['/remote/v4', '/remote/v4/'].includes(url.pathname) || url.username || url.password) {
    throw new Error('此验证版仅支持 https://zcode.z.ai/remote/v4 链接');
  }
  for (const key of ['sid', 'hash', 't']) {
    if (url.searchParams.getAll(key).length !== 1 || !url.searchParams.get(key)?.trim()) throw new Error('连接链接缺少有效配对参数');
  }
  if (!/^\d+$/.test(url.searchParams.get('t'))) throw new Error('配对时间格式无效');
  const normalized = new URL('/remote/v4', url.origin);
  for (const key of allowedKeys) {
    const value = url.searchParams.get(key);
    if (value) normalized.searchParams.set(key, value);
  }
  return {
    url: normalized.toString(),
    identity: url.origin + ':' + (url.searchParams.get('mid') || url.searchParams.get('sid')),
    name: url.searchParams.get('name')?.trim() || '桌面设备',
  };
}

// The M0 registry is deliberately memory-only. No credentials reach disk,
// browser storage, logs, or the resource cache before a credential store exists.
export class DeviceRegistry {
  #devices = new Map();
  constructor(createId = () => crypto.randomUUID()) { this.createId = createId; }
  get devices() { return [...this.#devices.values()].map(device => ({ ...device })); }
  get(id) { const device = this.#devices.get(id); return device ? { ...device } : null; }
  upsert(raw, label = '') {
    const parsed = parseRemoteUrl(raw);
    const existing = [...this.#devices.values()].find(device => device.identity === parsed.identity);
    const device = {
      id: existing?.id || this.createId(),
      identity: parsed.identity,
      label: label.trim() || existing?.label || parsed.name,
      url: parsed.url,
      revision: existing ? existing.revision + (existing.url !== parsed.url ? 1 : 0) : 1,
    };
    this.#devices.set(device.id, device);
    return { ...device };
  }
  remove(id) { this.#devices.delete(id); }
}

export function runtimeSource(device) {
  if (!/^[a-z0-9-]{8,64}$/i.test(device.id)) throw new Error('Invalid local device id');
  // Fragments are not transmitted to the local HTTP asset server.
  return '/runtime/' + device.id + '#' + encodeURIComponent(device.url);
}
