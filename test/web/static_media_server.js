// Eir Web E2E — static + same-origin media server.
//
// Serves the compiled product Web build and exposes loopback media fixtures at
// same-origin URLs so the product's HTMLMediaElement can decode H.264/AAC
// without CORS. Implements HTTP Range (206/416) so seeking works.
//
// Env:
//   EIR_WEB_BUILD_DIR  build dir to serve        (default /tmp/eir-web-final-build)
//   EIR_WEB_PORT       listen port               (default 8730)
//   EIR_WEB_HOST       listen host               (default 127.0.0.1)
//   EIR_MEDIA_FIXTURE  file for /sample.mp4      (default /tmp/eir-media-fixture.mp4)
//   EIR_MEDIA_LARGE    file for /sample-large.mp4(default /tmp/eir-streaming-large.mp4)
//
// No secrets. No external network. Loopback only.
const http = require('http');
const fs = require('fs');
const path = require('path');

const BUILD_DIR = path.resolve(process.env.EIR_WEB_BUILD_DIR || '/tmp/eir-web-final-build');
const PORT = Number(process.env.EIR_WEB_PORT || 8730);
const HOST = process.env.EIR_WEB_HOST || '127.0.0.1';

const MEDIA_ROUTES = {
  '/sample.mp4': path.resolve(process.env.EIR_MEDIA_FIXTURE || '/tmp/eir-media-fixture.mp4'),
  '/sample-large.mp4': path.resolve(process.env.EIR_MEDIA_LARGE || '/tmp/eir-streaming-large.mp4'),
};

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.mp4': 'video/mp4',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.wasm': 'application/wasm',
  '.map': 'application/json',
  '.bin': 'application/octet-stream',
  '.ico': 'image/x-icon',
};

function sendFile(filePath, req, res) {
  fs.stat(filePath, (err, stat) => {
    if (err || !stat.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not found');
      return;
    }
    const total = stat.size;
    const range = req.headers.range;
    const contentType = MIME[path.extname(filePath).toLowerCase()] || 'application/octet-stream';
    const headers = {
      'Accept-Ranges': 'bytes',
      'Content-Type': contentType,
      'Cache-Control': 'no-cache',
    };
    if (range) {
      const m = /bytes=(\d*)-(\d*)/.exec(range);
      let start = m && m[1] ? parseInt(m[1], 10) : 0;
      let end = m && m[2] ? parseInt(m[2], 10) : total - 1;
      if (isNaN(start) || isNaN(end) || start > end || end >= total) {
        res.writeHead(416, { 'Content-Range': `bytes */${total}` });
        res.end();
        return;
      }
      headers['Content-Range'] = `bytes ${start}-${end}/${total}`;
      headers['Content-Length'] = end - start + 1;
      res.writeHead(206, headers);
      fs.createReadStream(filePath, { start, end }).pipe(res);
    } else {
      headers['Content-Length'] = total;
      res.writeHead(200, headers);
      fs.createReadStream(filePath).pipe(res);
    }
  });
}

const server = http.createServer((req, res) => {
  let urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
  if (urlPath === '/') urlPath = '/index.html';

  if (MEDIA_ROUTES[urlPath]) {
    sendFile(MEDIA_ROUTES[urlPath], req, res);
    return;
  }

  // Prevent path traversal.
  const safe = path.normalize(urlPath).replace(/^(\.\.[/\\])+/, '');
  const filePath = path.join(BUILD_DIR, safe);
  if (!filePath.startsWith(BUILD_DIR)) {
    res.writeHead(403);
    res.end('forbidden');
    return;
  }
  sendFile(filePath, req, res);
});

server.listen(PORT, HOST, () => {
  console.log(`eir-web-test static server on http://${HOST}:${PORT} (build ${BUILD_DIR})`);
});
