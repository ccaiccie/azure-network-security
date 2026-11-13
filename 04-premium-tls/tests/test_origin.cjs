'use strict';
// Loopback HTTP only. No Azure, TLS keys, dependencies or public listeners.
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { makeServer } = require('../origin/server.js');
let server, base;
before(async () => {
  server = makeServer();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});
after(async () => { await new Promise(resolve => server.close(resolve)); });
for (const path of ['allowed', 'blocked', 'health']) {
  test(`${path} returns identifiable HTTP200`, async () => {
    const response = await fetch(`${base}/${path}`, { headers: { 'X-Lab-Case-ID': `local-${path}` } });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    const value = await response.json();
    assert.equal(value.fixture, 'azure-tls-origin-v1');
    assert.equal(value.path, `/${path}`);
    assert.equal(value.case_id, `local-${path}`);
    assert.ok(value.socket_peer.includes('127.0.0.1'));
  });
}
for (const path of ['/unknown', '/blocked/', '/allowed?q=1', '/Allowed']) {
  test(`exact path contract rejects ${path}`, async () => {
    assert.equal((await fetch(base + path)).status, 404);
  });
}
test('non-GET rejected', async () => {
  assert.equal((await fetch(base + '/allowed', { method: 'POST' })).status, 405);
});
test('unsafe case header rejected', async () => {
  assert.equal((await fetch(base + '/allowed', { headers: { 'X-Lab-Case-ID': 'not valid' } })).status, 400);
});
test('forwarded headers explicitly untrusted', async () => {
  const v = await (await fetch(base + '/allowed', { headers: { 'X-Forwarded-For': 'arbitrary-string', 'X-Forwarded-Proto': 'not-authenticated' } })).json();
  assert.equal(v.forwarded_for_untrusted, 'arbitrary-string');
  assert.equal(v.forwarded_proto_untrusted, 'not-authenticated');
});
