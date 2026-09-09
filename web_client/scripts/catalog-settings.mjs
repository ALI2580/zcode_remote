import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { cacheRoot, projectRoot, sha256 } from './official-assets.mjs';
const main = await readFile(resolve(cacheRoot, 'assets/index-nOVzQNKW.js'), 'utf8');
const intl = await readFile(resolve(cacheRoot, 'assets/IntlProvider-BDZANi-i.js'), 'utf8');
const list = main.match(/pQt=\[(.*?)\];pQt\.filter/s)?.[1];
if (!list) throw new Error('Pinned settings catalog structure changed');
function labels(key) {
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const values = [...intl.matchAll(new RegExp('"' + escaped + '":`([^`]+)`', 'g'))].map(match => match[1]);
  return { zh: values[0] || key, en: values[1] || key };
}
const sections = [...list.matchAll(/\{id:`([^`]+)`,icon:[^,]+,titleId:`([^`]+)`(?:,titleBadgeId:`[^`]+`)?(?:,groupId:`([^`]+)`)/g)].map(match => ({
  id: match[1], titleId: match[2], ...labels(match[2]), group: match[3],
  webDefaultVisible: !['automations', 'computerUse'].includes(match[1]),
  gate: match[1] === 'computerUse' ? 'desktop && cuaGrayEnabled' : match[1] === 'automations' ? 'excluded by cb() in this build' : null,
}));
if (sections.length !== 15) throw new Error('Unexpected official settings count');
const catalog = {
  source: 'https://zcode.z.ai/remote/v4', mainSha256: sha256(main),
  mode: 'source-derived; runtime capability gates remain authoritative',
  groups: ['basics', 'agentCapabilities', 'dataAndStats'].map(id => ({ id, ...labels('settings.sidebar.group.' + id) })), sections,
  avatarMenu: ['language submenu', 'theme submenu', 'usage and upgrade (account-dependent)', 'login/logout (account-dependent)', 'interface zoom (desktop only)'],
  extensionPolicy: 'Keep vendor avatar and settings components; add client-specific settings separately.',
};
await writeFile(resolve(projectRoot, 'references/official-settings-catalog.json'), JSON.stringify(catalog, null, 2) + '\n');
console.log(`Official settings: ${sections.length} defined, ${sections.filter(section => section.webDefaultVisible).length} visible under base Web gates`);
