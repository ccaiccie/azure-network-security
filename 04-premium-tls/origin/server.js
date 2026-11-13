'use strict';
// Azure App Service terminates public TLS before forwarding platform HTTP here.
// Socket/XFF fields are observations, not authenticated original-client identity.
const http = require('node:http');
function makeServer() {
  const server = http.createServer({ maxHeaderSize: 8192 }, (req, res) => {
    let path;
    try { path = new URL(req.url, 'http://fixture.invalid').pathname; }
    catch { res.writeHead(400); res.end(); return; }
    if (req.url.length > 256) { res.writeHead(414); res.end(); return; }
    if (req.method !== 'GET') { res.writeHead(405, { Allow: 'GET' }); res.end(); return; }
    if (!['/allowed', '/blocked', '/health'].includes(path) || req.url !== path) {
      res.writeHead(404, { 'Content-Type': 'application/json' }); res.end('{"error":"not-found"}\n'); return;
    }
    const caseId = req.headers['x-lab-case-id'] || 'readiness';
    if (!/^[A-Za-z0-9_.-]{1,128}$/.test(caseId)) { res.writeHead(400); res.end(); return; }
    const observation = {
      time_utc: new Date().toISOString(), fixture: 'azure-tls-origin-v1',
      path, case_id: caseId, host: req.headers.host || '',
      socket_peer: req.socket.remoteAddress, socket_peer_port: req.socket.remotePort,
      forwarded_for_untrusted: String(req.headers['x-forwarded-for'] || '').slice(0, 512),
      forwarded_proto_untrusted: String(req.headers['x-forwarded-proto'] || '').slice(0, 32)
    };
    console.log(JSON.stringify(observation));
    const body = JSON.stringify(observation) + '\n';
    res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body),
      'Cache-Control': 'no-store', Connection: 'close' });
    res.end(body);
  });
  server.requestTimeout = 10000;
  server.headersTimeout = 10000;
  server.keepAliveTimeout = 1000;
  return server;
}
if (require.main === module) {
  const server = makeServer();
  // BIND is only overridden for local tests. App Service needs its container interface.
  server.listen(Number(process.env.PORT || 8080), process.env.BIND || '0.0.0.0', () => {
    console.log(JSON.stringify({ event: 'listening', address: server.address() }));
  });
  const stop = () => server.close(() => process.exit(0));
  process.on('SIGTERM', stop); process.on('SIGINT', stop);
}
module.exports = { makeServer };
