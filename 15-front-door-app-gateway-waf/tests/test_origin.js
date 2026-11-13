'use strict';
// Offline fixture contract tests. No server is started and no request is sent.
// This does not test TLS, App Service, Azure routing, access rules or WAF policy.
// Run: node tests/test_origin.js
const assert = require('node:assert/strict');
const http = require('node:http');
const https = require('node:https');
const net = require('node:net');
const tls = require('node:tls');
const dns = require('node:dns');
const dgram = require('node:dgram');
const childProcess = require('node:child_process');

function denied() {
  throw new Error('Offline fixture test attempted a real network or child-process operation');
}
const restored = [];
function deny(object, key) {
  const old = object[key];
  object[key] = denied;
  restored.push(() => { object[key] = old; });
}
for (const key of ['createServer', 'request', 'get']) { deny(http, key); deny(https, key); }
for (const key of ['createServer', 'connect', 'createConnection']) deny(net, key);
deny(net.Server.prototype, 'listen');
deny(net.Socket.prototype, 'connect');
for (const key of ['connect', 'createServer']) deny(tls, key);
for (const key of Object.keys(dns)) {
  if (typeof dns[key] === 'function') deny(dns, key);
}
for (const key of Object.keys(dns.promises)) {
  if (typeof dns.promises[key] === 'function') deny(dns.promises, key);
}
deny(dgram, 'createSocket');
for (const key of ['exec', 'execFile', 'execSync', 'execFileSync', 'fork', 'spawn', 'spawnSync']) deny(childProcess, key);
if (typeof global.fetch === 'function') deny(global, 'fetch');

let assertions = 0;
function test(name, fn) {
  try { fn(); assertions += 1; }
  catch (error) { error.message = name + ': ' + error.message; throw error; }
}

try {
  // Requiring the module is also guarded against server startup side effects.
  const { handle, MARKER } = require('../origin/server.js');
  const CASE = '12345678-1234-4123-8123-123456789abc';
  const UUID = 'abcdefab-1234-4567-89ab-abcdefabcdef';
  const payload = { fixture: 'azure-waf-origin-v1', case_id: CASE, message: 'Layered WAF inspection proof.' };
  const expectedBody = JSON.stringify(payload) + '\n';

  test('network and process guards fail closed', () => {
    for (const action of [() => http.createServer(), () => https.request('https://never-connect.test'),
      () => net.connect(443, 'never-connect.test'), () => tls.connect(443),
      () => dns.lookup('never-resolve.test'), () => dgram.createSocket('udp4'),
      () => childProcess.spawn('never-execute')]) {
      assert.throws(action, /Offline fixture test attempted/);
    }
  });

  function invoke({ url = '/probe/' + CASE, method = 'GET', headers = {} } = {}) {
    const logs = [];
    const res = {
      headers: {}, ends: [], statusCode: null,
      setHeader(name, value) { assert.equal(Object.hasOwn(this.headers, name), false); this.headers[name] = value; },
      end(value) { this.ends.push(value); },
    };
    handle({ url, method, headers }, res, line => logs.push(line));
    assert.equal(res.ends.length, 1);
    assert.equal(logs.length, 1);
    const record = JSON.parse(logs[0]);
    assert.deepEqual(Object.keys(record).sort(), ['event', 'utc', 'case_id', 'health', 'method', 'status', 'user_agent', 'azure_ref', 'fdid'].sort());
    assert.equal(record.event, 'fixture_request');
    assert.match(record.utc, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
    assert.ok(Number.isFinite(Date.parse(record.utc)));
    assert.equal(record.status, res.statusCode);
    assert.equal(res.headers['Cache-Control'], 'no-store');
    assert.equal(res.headers['X-Lab-Fixture'], MARKER);
    assert.equal(res.headers['X-Content-Type-Options'], 'nosniff');
    assert.deepEqual(Object.keys(res.headers).sort(), ['Content-Type', 'Content-Length', 'Cache-Control', 'X-Lab-Fixture', 'X-Content-Type-Options'].sort());
    if (method === 'HEAD') assert.equal(res.ends[0], undefined);
    else {
      assert.ok(Buffer.isBuffer(res.ends[0]));
      assert.equal(res.ends[0].length, res.headers['Content-Length']);
    }
    return { res, record, log: logs[0], body: res.ends[0] === undefined ? undefined : res.ends[0].toString('utf8') };
  }

  test('exact synthetic JSON and non-cacheable response', () => {
    const { res, record, body } = invoke();
    assert.equal(MARKER, payload.fixture);
    assert.equal(res.statusCode, 200);
    assert.equal(res.headers['Content-Type'], 'application/json');
    assert.equal(res.headers['Content-Length'], Buffer.byteLength(expectedBody));
    assert.equal(body, expectedBody);
    assert.deepEqual(JSON.parse(body), payload);
    assert.equal(record.case_id, CASE);
    assert.equal(record.health, false);
    assert.equal(record.method, 'GET');
    assert.equal(record.user_agent, null);
    assert.equal(record.azure_ref, null);
    assert.equal(record.fdid, null);
  });

  test('HEAD fixture returns the same representation headers and no body', () => {
    const get = invoke();
    const head = invoke({ method: 'HEAD' });
    assert.equal(head.res.statusCode, 200);
    assert.deepEqual(head.res.headers, get.res.headers);
    assert.equal(head.record.method, 'HEAD');
    assert.equal(head.body, undefined);
  });

  test('GET and HEAD health are exact and separate from case evidence', () => {
    for (const method of ['GET', 'HEAD']) {
      const { res, record, body } = invoke({ url: '/health', method });
      assert.equal(res.statusCode, 200);
      assert.equal(res.headers['Content-Type'], 'text/plain');
      assert.equal(res.headers['Content-Length'], Buffer.byteLength('azure-waf-health-v1\n'));
      assert.equal(body, method === 'HEAD' ? undefined : 'azure-waf-health-v1\n');
      assert.equal(record.health, true);
      assert.equal(record.case_id, null);
    }
  });

  test('case path requires exactly one lower-case canonical UUIDv4', () => {
    const invalid = ['/probe/' + CASE.toUpperCase(), '/probe/' + CASE + '/',
      '/probe/' + CASE + '?secret=HIDDEN_QUERY', '/probe/' + CASE + '#fragment',
      '/probe/' + CASE.replace('-4123-', '-1123-'), '/probe/' + CASE.replace('-8123-', '-7123-'),
      '/probe/' + 'f'.repeat(36), '/probe/' + CASE.replace('12345678', '%31%32%33'),
      '/probe/', '/probe/' + CASE + '/other', '/Probe/' + CASE, '/health?x=1',
      '/health/', '/HEALTH', '/', undefined, null, 12];
    for (const url of invalid) {
      // Explicit undefined is passed through here rather than invoke's defaults.
      const actualUrl = url === undefined ? '' : url;
      const { res, record, body, log } = invoke({ url: actualUrl });
      assert.equal(res.statusCode, 404, String(url));
      assert.equal(body, 'Not found\n');
      assert.equal(record.case_id, null);
      assert.equal(record.health, false);
      assert.equal(res.headers['Content-Type'], 'text/plain');
      assert.equal(log.includes('HIDDEN_QUERY'), false);
    }
  });

  test('valid UUIDv4 variant digits are accepted', () => {
    for (const variant of ['8', '9', 'a', 'b']) {
      const caseId = CASE.replace('-8123-', '-' + variant + '123-');
      const { res, record, body } = invoke({ url: '/probe/' + caseId });
      assert.equal(res.statusCode, 200);
      assert.equal(record.case_id, caseId);
      assert.equal(JSON.parse(body).case_id, caseId);
    }
  });

  test('unsupported methods never produce successful fixture or health content', () => {
    for (const method of ['POST', 'PUT', 'DELETE', 'OPTIONS', 'TRACE', 'CONNECT', 'get', 'HEAD\r\nSECRET_METHOD', undefined]) {
      for (const url of ['/probe/' + CASE, '/health', '/missing']) {
        const { res, record, body, log } = invoke({ url, method: method === undefined ? null : method });
        assert.equal(res.statusCode, 405);
        assert.equal(res.headers['Content-Type'], 'text/plain');
        assert.equal(body, 'Method not allowed\n');
        assert.equal(record.method, 'OTHER');
        assert.equal(log.includes('SECRET_METHOD'), false);
      }
    }
  });

  test('HEAD unknown path still reports correct status and length without body', () => {
    const { res, record, body } = invoke({ url: '/missing', method: 'HEAD' });
    assert.equal(res.statusCode, 404);
    assert.equal(res.headers['Content-Length'], Buffer.byteLength('Not found\n'));
    assert.equal(record.case_id, null);
    assert.equal(body, undefined);
  });

  test('only bounded allowlisted attribution fields survive logging', () => {
    const headers = {
      'user-agent': 'azure-waf-lab/' + CASE,
      'x-azure-ref': 'A_123+/=:-',
      'x-azure-fdid': UUID.toUpperCase(),
      authorization: 'HIDDEN_AUTH', cookie: 'HIDDEN_COOKIE',
      'proxy-authorization': 'HIDDEN_PROXY_AUTH', 'x-forwarded-for': 'HIDDEN_IP',
      'x-azure-clientip': 'HIDDEN_CLIENT', 'x-azure-socketip': 'HIDDEN_SOCKET',
      'x-lab-case-id': 'HIDDEN_UNTRUSTED_CASE', 'x-secret': 'HIDDEN_HEADER',
    };
    const { record, log, body } = invoke({ headers });
    assert.equal(record.user_agent, headers['user-agent']);
    assert.equal(record.azure_ref, headers['x-azure-ref']);
    assert.equal(record.fdid, UUID.toUpperCase());
    assert.equal(log.includes('HIDDEN_'), false);
    assert.equal(body, expectedBody);
    assert.equal(record.case_id, CASE);
  });

  test('malformed, oversized, duplicate and non-string values are redacted', () => {
    const badValues = [null, undefined, 123, {}, ['one', 'two'], '', 'HIDDEN_VALUE\r\nother',
      'HIDDEN_VALUE\u0000', 'a'.repeat(257), 'one, two', 'é'];
    for (const value of badValues) {
      const { record, log } = invoke({ headers: { 'user-agent': value, 'x-azure-ref': value, 'x-azure-fdid': value } });
      assert.equal(record.user_agent, null);
      assert.equal(record.azure_ref, null);
      assert.equal(record.fdid, null);
      assert.equal(log.includes('HIDDEN_VALUE'), false);
    }
    for (const value of [UUID + ', ' + UUID, [UUID, UUID], UUID + ' ', UUID + '\n', 'z'.repeat(36)]) {
      assert.equal(invoke({ headers: { 'x-azure-fdid': value } }).record.fdid, null);
    }
  });

  test('azure-ref permits its exact 256-character upper bound only', () => {
    assert.equal(invoke({ headers: { 'x-azure-ref': 'a'.repeat(256) } }).record.azure_ref, 'a'.repeat(256));
    assert.equal(invoke({ headers: { 'x-azure-ref': 'a'.repeat(257) } }).record.azure_ref, null);
    for (const value of ['safe\n', 'safe\r', 'safe\r\n', 'safe\u2028', 'safe\u2029']) {
      assert.equal(invoke({ headers: { 'x-azure-ref': value } }).record.azure_ref, null);
    }
  });

  test('user-agent and FDID cannot smuggle arbitrary data past their formats', () => {
    for (const value of ['ordinary-browser', 'azure-waf-lab/' + CASE.toUpperCase(),
      'azure-waf-lab/' + CASE + 'x', 'azure-waf-lab/' + CASE + '\n']) {
      assert.equal(invoke({ headers: { 'user-agent': value } }).record.user_agent, null);
    }
    assert.equal(invoke({ headers: { 'x-azure-fdid': UUID } }).record.fdid, UUID);
    assert.equal(invoke({ headers: { 'x-azure-fdid': UUID.toUpperCase() } }).record.fdid, UUID.toUpperCase());
  });

  test('fake invocation does not read or echo request body, cookies or all headers', () => {
    const headers = { 'user-agent': 'azure-waf-lab/' + CASE };
    for (const key of ['cookie', 'authorization', 'x-forwarded-for']) {
      Object.defineProperty(headers, key, { get() { throw new Error('Forbidden header was read: ' + key); } });
    }
    const { body } = invoke({ headers });
    assert.equal(body, expectedBody);
  });

  process.stdout.write('Passed ' + assertions + ' offline fixture contract tests; no server, DNS, TLS or HTTP operation was performed.\n');
} finally {
  for (const restore of restored.reverse()) restore();
}
