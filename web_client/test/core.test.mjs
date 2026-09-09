import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';
import { DeviceRegistry, parseRemoteUrl, runtimeSource } from '../src/device-registry.mjs';
import { SessionPool } from '../src/session-pool.mjs';
import { assetPath, entryAssets, cssAssets } from '../scripts/official-assets.mjs';
import { injectRuntime } from '../scripts/dev-server.mjs';

// Deliberately synthetic pairing fields; never use a real remote link here.
const url = (sid, proof = 'synthetic-proof', mid = 'synthetic-machine') => `https://zcode.z.ai/remote/v4?sid=${sid}&hash=${proof}&t=1&mid=${mid}&name=Example`;
test('remote links reject insecure origins, unexpected paths and duplicate pairing keys', () => {
  for (const raw of ['http://zcode.z.ai/remote/v4?sid=test&hash=test&t=1', url('a').replace('zcode.z.ai', 'example.org'), url('a').replace('/remote/v4', '/web-remote'), url('a') + '&sid=other', url('a').replace('t=1', 't=bad')]) assert.throws(() => parseRemoteUrl(raw));
});
test('normalized URLs strip unrelated parameters and fragments', () => {
  const parsed = parseRemoteUrl(url('a') + '&untrusted=value#fragment');
  assert.equal(new URL(parsed.url).searchParams.has('untrusted'), false);
  assert.equal(new URL(parsed.url).hash, '');
});
test('rotated pairing keeps local device identity and replaces credentials', () => {
  const store = new DeviceRegistry(() => 'device-0001');
  const first = store.upsert(url('old'), '工作电脑');
  const next = store.upsert(url('new', 'rotated'));
  assert.equal(next.id, first.id); assert.equal(next.label, '工作电脑');
  assert.equal(next.revision, 2);
  assert.equal(new URL(next.url).searchParams.get('sid'), 'new');
  assert.equal(store.devices.length, 1);
});
test('reimporting an unchanged link does not force a reconnect', () => {
  const store = new DeviceRegistry(() => 'device-0001');
  const first = store.upsert(url('same'));
  assert.equal(store.upsert(url('same')).revision, first.revision);
  const copy = store.get(first.id); copy.url = '';
  assert.notEqual(store.get(first.id).url, '');
});
test('iframe navigation transmits no pairing query to the local asset server', () => {
  const source = new URL(runtimeSource({ id: 'device-0001', url: url('a') }), 'http://127.0.0.1:4173');
  assert.equal(source.search, ''); assert.equal(source.pathname, '/runtime/device-0001');
  assert.equal(decodeURIComponent(source.hash.slice(1)), url('a'));
});
function poolFixture() {
  const creations = [], disposals = [], visibility = new Map();
  const pool = new SessionPool(device => {
    const token = `${device.id}/${device.revision}`; creations.push(token);
    return { token, setVisible: visible => visibility.set(token, visible), dispose: () => disposals.push(token) };
  });
  return { pool, creations, disposals, visibility };
}
test('A → B → A retains both runtimes and only switches visibility', () => {
  const { pool, creations, disposals, visibility } = poolFixture();
  const first = pool.activate({ id: 'a', revision: 1 });
  pool.activate({ id: 'b', revision: 1 });
  assert.equal(pool.activate({ id: 'a', revision: 1 }), first);
  assert.deepEqual(creations, ['a/1', 'b/1']); assert.deepEqual(disposals, []);
  assert.equal(visibility.get('a/1'), true); assert.equal(visibility.get('b/1'), false);
});
test('credential replacement and removal dispose only the affected runtime', () => {
  const { pool, disposals } = poolFixture();
  pool.activate({ id: 'a', revision: 1 });
  const b = pool.activate({ id: 'b', revision: 1 });
  pool.activate({ id: 'a', revision: 2 });
  assert.equal(pool.get('b'), b); assert.deepEqual(disposals, ['a/1']);
  pool.remove('a'); assert.equal(pool.get('a'), undefined); assert.equal(pool.get('b'), b);
  pool.dispose(); assert.deepEqual(disposals, ['a/1', 'a/2', 'b/1']);
});
class MemoryStorage {
  data = new Map();
  get length() { return this.data.size; }
  key(index) { return [...this.data.keys()][index] ?? null; }
  getItem(key) { return this.data.get(key) ?? null; }
  setItem(key, value) { this.data.set(key, String(value)); }
  removeItem(key) { this.data.delete(key); }
}
const storageContext = {};
runInNewContext(await readFile(new URL('../public/scoped-storage.js', import.meta.url), 'utf8'), storageContext);
const { createScopedStorage, unprefixEventKey } = storageContext.ZRStorage;
test('same draft and model keys do not cross device namespaces', () => {
  const raw = new MemoryStorage(), a = createScopedStorage(raw, 'a:'), b = createScopedStorage(raw, 'b:');
  a.setItem('draft/same-session', 'A draft'); b.setItem('draft/same-session', 'B draft');
  a.model = 'model-A'; b.model = 'model-B';
  assert.equal(a.getItem('draft/same-session'), 'A draft'); assert.equal(b.getItem('draft/same-session'), 'B draft');
  assert.equal(a.model, 'model-A'); assert.equal(b.model, 'model-B'); assert.equal(a.length, 2);
  assert.deepEqual(Object.keys(a), ['draft/same-session', 'model']);
});
test('clear, remove, property deletion and enumeration cannot clear a peer device', () => {
  const raw = new MemoryStorage(), a = createScopedStorage(raw, 'a:'), b = createScopedStorage(raw, 'b:');
  raw.setItem('host-preference', 'keep'); a.one = '1'; a.two = '2'; b.one = 'B'; delete a.one;
  assert.equal(a.getItem('one'), null); assert.equal(b.one, 'B');
  assert.equal(a.key(0), 'two'); assert.equal(a.key(1), null);
  a.clear(); assert.equal(a.length, 0); assert.equal(b.one, 'B'); assert.equal(raw.getItem('host-preference'), 'keep');
});
test('storage events only translate keys belonging to the device', () => {
  assert.equal(unprefixEventKey('a:theme', 'a:'), 'theme');
  assert.equal(unprefixEventKey('b:theme', 'a:'), undefined);
  assert.equal(unprefixEventKey(null, 'a:'), null);
});
test('asset allowlist rejects traversal, credential parameters and external paths', () => {
  for (const path of ['/remote/v4/assets/../../secrets.js', '/remote/v4?sid=secret', '//example.org/a.js', '/remote/v4/assets/a.js?token=x', '/remote/v4/assets/%2e%2e/a.js']) assert.throws(() => assetPath(path));
  assert.match(assetPath('/remote/v4/assets/index-test.js'), /index-test\.js$/);
});
test('baseline extraction includes entry modules, CSS and local fonts without external requests', () => {
  assert.deepEqual(entryAssets('<script src="/remote/v4/assets/a.js"></script><link href="/remote/v4/assets/a.js"><link href="https://example.org/x.css">'), ['/remote/v4/assets/a.js']);
  assert.deepEqual(cssAssets('url(./font.woff2) url(data:test) url(https://example.org/a.woff2)'), ['/remote/v4/assets/font.woff2']);
});
test('runtime bootstrap gates the original entry behind scoped storage without changing its source', () => {
  const html = '<html><head></head><body><script type="module" crossorigin src="/remote/v4/assets/main.js"></script></body></html>';
  const injected = injectRuntime(html);
  assert.match(injected, /data-zr-official-entry="\/remote\/v4\/assets\/main.js"/);
  assert.ok(injected.indexOf('scoped-storage.js') < injected.indexOf('runtime-prelude.js'));
  assert.doesNotMatch(injected, /<script type="module"/);
  assert.throws(() => injectRuntime('<html></html>'));
});

const preludeSource = await readFile(new URL('../public/runtime-prelude.js', import.meta.url), 'utf8');
function preludeFixture(remoteUrl) {
  const domReady = [], modules = [], rewrites = [], raw = new MemoryStorage();
  const context = {
    URL, URLSearchParams, Object, WeakSet,
    location: new URL('http://127.0.0.1:4173/runtime/device-0001#' + encodeURIComponent(remoteUrl)),
    history: { replaceState(_state, _title, value) { rewrites.push(value); } },
    localStorage: raw, sessionStorage: new MemoryStorage(),
    addEventListener() {},
    document: {
      addEventListener(_type, callback) { domReady.push(callback); },
      querySelector() { return { getAttribute() { return '/remote/v4/assets/main.js'; } }; },
      createElement() { return {}; },
      head: { append(module) { modules.push(module); } },
      body: { replaceChildren() {} },
    },
  };
  context.window = context;
  runInNewContext(awaitStorageSource, context);
  runInNewContext(preludeSource, context);
  return { context, domReady, modules, rewrites, raw };
}
const awaitStorageSource = await readFile(new URL('../public/scoped-storage.js', import.meta.url), 'utf8');
test('document-start prelude scopes storage before starting the official module', () => {
  const { context, domReady, modules, rewrites, raw } = preludeFixture(url('a'));
  assert.equal(context.ZRRuntime.deviceId, 'device-0001');
  context.localStorage.setItem('draft', 'A');
  assert.equal(raw.getItem('zr:device:device-0001:draft'), 'A');
  assert.equal(raw.getItem('draft'), null);
  assert.equal(modules.length, 0);
  assert.match(rewrites[0], /zrDevice=device-0001/);
  domReady.forEach(callback => callback());
  assert.equal(modules.length, 1);
  assert.equal(modules[0].type, 'module');
  assert.equal(modules[0].src, '/remote/v4/assets/main.js');
});
test('invalid bootstrap origin never launches the official connection module', () => {
  const { context, domReady, modules, rewrites } = preludeFixture(url('a').replace('zcode.z.ai', 'other.example'));
  domReady.forEach(callback => callback());
  assert.equal(context.ZRRuntime, undefined);
  assert.equal(modules.length, 0);
  assert.equal(rewrites.length, 0);
});
