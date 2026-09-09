import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { request } from 'node:http';
import { createDevServer } from '../scripts/dev-server.mjs';

test('local server exposes the application and source modules without exposing the repository', async t => {
  const server = createDevServer();
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); server.close(); });
  const origin = `http://127.0.0.1:${server.address().port}`;
  const home = await fetch(origin);
  assert.equal(home.status, 200);
  assert.match(await home.text(), /ZcodeRemote/);
  assert.equal(home.headers.get('referrer-policy'), 'no-referrer');
  const module = await fetch(origin + '/src/session-pool.mjs');
  assert.equal(module.status, 200);
  assert.match(module.headers.get('content-type'), /javascript/);
  assert.equal((await fetch(origin + '/pubspec.yaml')).status, 404);
  assert.equal((await fetch(origin + '/.git/config')).status, 404);
  assert.equal((await fetch(origin + '/src/device-registry.mjs', { method: 'POST', body: 'synthetic' })).status, 405);
  const rejectedHostStatus = await new Promise((resolve, reject) => {
    const call = request(origin, { headers: { Host: 'other.example' } }, response => {
      response.resume(); resolve(response.statusCode);
    });
    call.on('error', reject); call.end();
  });
  assert.equal(rejectedHostStatus, 403);
});
