import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const officialOrigin = 'https://zcode.z.ai';
export const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
export const cacheRoot = resolve(projectRoot, 'build/official-web');
export const manifestPath = resolve(cacheRoot, 'manifest.json');
const activeDownloads = new Map();
let manifestPromise;
let manifestWrites = Promise.resolve();

export function assetPath(pathname) {
  if (pathname === '/remote/v4') return resolve(cacheRoot, 'index.html');
  if (!/^\/remote\/v4\/assets\/[A-Za-z0-9_.-]+\.(?:js|css|woff2?|ttf|otf|png|svg|webp|jpg|jpeg|wasm)$/.test(pathname)) {
    throw new Error('Unsupported official asset path');
  }
  return resolve(cacheRoot, 'assets', pathname.split('/').at(-1));
}

export function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

export async function readManifest() {
  manifestPromise ??= (async () => {
    try { return JSON.parse(await readFile(manifestPath, 'utf8')); }
    catch (error) {
      if (error.code !== 'ENOENT') throw error;
      return { source: officialOrigin + '/remote/v4', createdAt: new Date().toISOString(), assets: {} };
    }
  })();
  return manifestPromise;
}

async function record(pathname, bytes, contentType) {
  const data = await readManifest();
  data.assets[pathname] = { bytes: bytes.length, sha256: sha256(bytes), contentType };
  manifestWrites = manifestWrites.then(async () => {
    await mkdir(cacheRoot, { recursive: true });
    await writeFile(manifestPath, JSON.stringify(data, null, 2) + '\n');
  });
  await manifestWrites;
}

// Only fetch credential-free resources from the exact public vendor origin.
// Redirects are rejected, including the vendor's trailing-slash HTTP redirect.
export async function obtainAsset(pathname, { offline = false } = {}) {
  const target = assetPath(pathname);
  const data = await readManifest();
  try {
    const bytes = await readFile(target);
    const entry = data.assets[pathname];
    if (!entry || entry.sha256 !== sha256(bytes)) throw new Error('Official asset integrity mismatch');
    return { bytes, contentType: entry.contentType, cached: true };
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  if (offline) throw new Error('Official resource is not cached');
  if (activeDownloads.has(pathname)) return activeDownloads.get(pathname);
  const download = (async () => {
    const response = await fetch(officialOrigin + pathname, { redirect: 'error', signal: AbortSignal.timeout(30_000) });
    if (!response.ok) throw new Error(`Official resource request failed (${response.status})`);
    const bytes = Buffer.from(await response.arrayBuffer());
    if (bytes.length > 32 * 1024 * 1024) throw new Error('Official resource exceeds cache limit');
    const contentType = response.headers.get('content-type') || 'application/octet-stream';
    if (pathname.endsWith('.js') && !/javascript/.test(contentType)) throw new Error('Official module returned non-JavaScript content');
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, bytes);
    await record(pathname, bytes, contentType);
    return { bytes, contentType, cached: false };
  })();
  activeDownloads.set(pathname, download);
  try { return await download; } finally { activeDownloads.delete(pathname); }
}

export function entryAssets(html) {
  return [...new Set([...html.matchAll(/(?:src|href)="(\/remote\/v4\/assets\/[A-Za-z0-9_.-]+\.(?:js|css))"/g)].map(match => match[1]))];
}

export function cssAssets(css) {
  return [...new Set([...css.matchAll(/url\(["']?(?:\.\/)?([^"')]+)["']?\)/g)]
    .map(match => match[1])
    .filter(name => /^[A-Za-z0-9_.-]+\.(?:woff2?|ttf|otf|png|svg|webp)$/.test(name))
    .map(name => '/remote/v4/assets/' + name))];
}
