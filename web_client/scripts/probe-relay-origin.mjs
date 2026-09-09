import { request } from 'node:https';
import { randomBytes } from 'node:crypto';

// Read-only transport check: no pairing credentials, authentication or RPC.
const result = await new Promise((resolve, reject) => {
  const call = request('https://zcode.z.ai/ws', {
    headers: {
      Connection: 'Upgrade', Upgrade: 'websocket',
      'Sec-WebSocket-Version': '13',
      'Sec-WebSocket-Key': randomBytes(16).toString('base64'),
      Origin: 'http://127.0.0.1:4173',
    },
  });
  call.setTimeout(15_000, () => call.destroy(new Error('Transport probe timed out')));
  call.on('upgrade', (response, socket) => { socket.destroy(); resolve(response.statusCode); });
  call.on('response', response => { response.resume(); resolve(response.statusCode); });
  call.on('error', reject);
  call.end();
});
console.log(`Relay HTTP upgrade with local origin: ${result}`);
console.log('No device pairing or conversation command was sent.');
if (result !== 101) process.exitCode = 1;
