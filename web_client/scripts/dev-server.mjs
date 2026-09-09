import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, resolve } from 'node:path';
import { obtainAsset, projectRoot } from './official-assets.mjs';

const port = Number(process.env.ZCODE_WEB_PORT || 4173);
const offline = process.argv.includes('--offline');
const publicRoot = resolve(projectRoot, 'web_client/public');
const sourceRoot = resolve(projectRoot, 'web_client/src');
const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8' };

export function injectRuntime(html) {
  const bootstrap = '<meta name="referrer" content="no-referrer"><script src="/host/scoped-storage.js"></script><script src="/host/runtime-prelude.js"></script><script defer src="/host/runtime-adapter.js"></script>';
  const entryPattern = /<script type="module" crossorigin src="([^"]+)"><\/script>/;
  if (!entryPattern.test(html) || !html.includes('<head>')) throw new Error('Official entry contract changed');
  return html.replace('<head>', '<head>' + bootstrap).replace(entryPattern, '<script type="application/octet-stream" data-zr-official-entry="$1"></script>');
}

export function createDevServer() {
  return createServer(async (request, response) => {
    // Never log request URLs: a reload of the vendor runtime can contain pairing parameters.
    response.setHeader('Referrer-Policy', 'no-referrer');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    response.setHeader('Cache-Control', 'no-store');
    if (!/^(127\.0\.0\.1|localhost)(:\d+)?$/.test(request.headers.host || '')) {
      response.writeHead(403).end('Loopback host required'); return;
    }
    const path = new URL(request.url, 'http://127.0.0.1').pathname;
    try {
      if (request.method !== 'GET' && request.method !== 'HEAD') { response.writeHead(405).end(); return; }
      let body, contentType;
      if (path === '/') {
        body = await readFile(resolve(publicRoot, 'index.html')); contentType = mime['.html'];
      } else if (/^\/runtime\/[a-z0-9-]{8,64}$/i.test(path) || path === '/remote/v4') {
        const entry = await obtainAsset('/remote/v4', { offline });
        body = injectRuntime(entry.bytes.toString('utf8')); contentType = mime['.html'];
      } else if (path.startsWith('/remote/v4/assets/')) {
        const asset = await obtainAsset(path, { offline }); body = asset.bytes; contentType = asset.contentType;
      } else if (/^\/(host|src)\/[a-zA-Z0-9_.-]+\.(css|js|mjs)$/.test(path)) {
        body = await readFile(resolve(path.startsWith('/src/') ? sourceRoot : publicRoot, path.split('/').at(-1)));
        contentType = mime[extname(path)];
      } else { response.writeHead(404).end('Not found'); return; }
      response.setHeader('Content-Type', contentType);
      response.writeHead(200).end(request.method === 'HEAD' ? undefined : body);
    } catch {
      response.writeHead(503, { 'Content-Type': 'text/plain; charset=utf-8' }).end('资源暂不可用。请先运行 npm run sync:official，或检查控制台资源请求。');
    }
  });
}

if (process.argv[1] && resolve(process.argv[1]) === resolve(projectRoot, 'web_client/scripts/dev-server.mjs')) {
  createDevServer().listen(port, '127.0.0.1', () => console.log(`ZcodeRemote: http://127.0.0.1:${port}`));
}
