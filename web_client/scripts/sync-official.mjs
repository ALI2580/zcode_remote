import { writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { obtainAsset, entryAssets, cssAssets, readManifest, projectRoot } from './official-assets.mjs';

const entry = await obtainAsset('/remote/v4');
const queue = entryAssets(entry.bytes.toString('utf8'));
const seen = new Set(queue);
let completed = 0;
async function worker() {
  for (;;) {
    const path = queue.shift();
    if (!path) return;
    const asset = await obtainAsset(path);
    if (path.endsWith('.css')) {
      for (const dependency of cssAssets(asset.bytes.toString('utf8'))) {
        if (!seen.has(dependency)) { seen.add(dependency); queue.push(dependency); }
      }
    }
    completed += 1;
    if (completed % 20 === 0) process.stdout.write(`Cached ${completed} public assets\n`);
  }
}
await Promise.all(Array.from({ length: 6 }, worker));
const manifest = await readManifest();
await writeFile(resolve(projectRoot, 'references/official-web-baseline.json'), JSON.stringify(manifest, null, 2) + '\n');
const entries = Object.values(manifest.assets);
console.log(`Baseline: ${entries.length} assets, ${entries.reduce((total, item) => total + item.bytes, 0)} bytes`);
