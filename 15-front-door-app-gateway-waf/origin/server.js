'use strict';
// Synthetic dependency-free App Service fixture. TLS terminates at its platform
// frontend; Node receives internal HTTP. No credentials or real customer data.
const http = require('node:http');
const MARKER = 'azure-waf-origin-v1';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
function publicValue(value, regex, limit) {
  return typeof value === 'string' && value.length <= limit && regex.test(value) ? value : null;
}
function handle(req, res, emit = line => process.stdout.write(line + '\n')) {
  let status = 404, body = Buffer.from('Not found\n'), caseId = null;
  const health = req.url === '/health';
  const path = typeof req.url === 'string' ? /^\/probe\/([^/?]{36})$/.exec(req.url) : null;
  if (path && UUID.test(path[1])) caseId = path[1];
  if (!['GET', 'HEAD'].includes(req.method)) { status = 405; body = Buffer.from('Method not allowed\n'); }
  else if (health) { status = 200; body = Buffer.from('azure-waf-health-v1\n'); }
  else if (caseId) { status = 200; body = Buffer.from(JSON.stringify({fixture:MARKER,case_id:caseId,message:'Layered WAF inspection proof.'}) + '\n'); }
  res.statusCode = status;
  res.setHeader('Content-Type', caseId && status === 200 ? 'application/json' : 'text/plain');
  res.setHeader('Content-Length', body.length);
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Lab-Fixture', MARKER);
  res.setHeader('X-Content-Type-Options', 'nosniff');
  // Only allowlisted, syntax-limited attribution fields. These are observations,
  // not proof of trusted client identity or the three proxy connections.
  emit(JSON.stringify({event:'fixture_request',utc:new Date().toISOString(),case_id:caseId,
    health,method:['GET','HEAD'].includes(req.method)?req.method:'OTHER',status,
    user_agent:publicValue(req.headers['user-agent'],/^azure-waf-lab\/[0-9a-f-]{36}$/,60),
    azure_ref:publicValue(req.headers['x-azure-ref'],/^[A-Za-z0-9_+=/:-]+$/,256),
    fdid:publicValue(req.headers['x-azure-fdid'],/^[0-9a-fA-F-]{36}$/,36)}));
  res.end(req.method === 'HEAD' ? undefined : body);
}
function start() {
  const raw = process.env.PORT || '8080';
  if (!/^\d{1,5}$/.test(raw) || Number(raw)<1 || Number(raw)>65535) throw new Error('Invalid platform port');
  const server=http.createServer(handle);
  server.maxHeadersCount=32; server.headersTimeout=10000; server.requestTimeout=15000; server.keepAliveTimeout=1000;
  server.listen(Number(raw),'0.0.0.0');
  return server;
}
module.exports={handle,MARKER};
if(require.main===module) start();
