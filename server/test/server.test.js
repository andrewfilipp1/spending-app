// Runs against `npm run dev` (wrangler dev on :8787 with a local D1 database).
import { test } from 'node:test';
import assert from 'node:assert/strict';

const BASE = process.env.SYNC_URL || 'http://localhost:8787';
const rnd = () => Math.random().toString(36).slice(2, 10);
const key = () => Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('base64');
const call = (method, path, { body, user, auth, origin } = {}) => fetch(BASE + path, {
  method,
  headers: {
    ...(body ? { 'Content-Type': 'application/json' } : {}),
    ...(user ? { Authorization: `Sync ${user}:${auth}` } : {}),
    ...(origin ? { Origin: origin } : {}),
  },
  body: body ? JSON.stringify(body) : undefined,
});
const blob = { iv: 'AAAAAAAAAAAAAAAA', ct: 'Y2lwaGVydGV4dA==' };

test('register, read, write with versions, delete', async () => {
  const user = `t-${rnd()}`;
  const auth = key();
  assert.equal((await call('POST', '/v1/register', { body: { username: user, auth } })).status, 201);
  assert.equal((await call('POST', '/v1/register', { body: { username: user, auth: key() } })).status, 409);
  assert.deepEqual(await (await call('GET', '/v1/data', { user, auth })).json(), { version: 0, blob: null });

  const put1 = await call('PUT', '/v1/data', { user, auth, body: { version: 0, blob } });
  assert.deepEqual(await put1.json(), { version: 1 });
  const stale = await call('PUT', '/v1/data', { user, auth, body: { version: 0, blob: { ...blob, ct: 'b3RoZXI=' } } });
  assert.equal(stale.status, 409);
  assert.deepEqual(await stale.json(), { error: 'conflict', version: 1, blob });

  assert.equal((await call('DELETE', '/v1/account', { user, auth })).status, 204);
  assert.equal((await call('GET', '/v1/data', { user, auth })).status, 401);
});

test('rejects bad input and wrong keys, locks after repeated failures', async () => {
  assert.equal((await call('POST', '/v1/register', { body: { username: 'Κεφαλαία', auth: key() } })).status, 400);
  assert.equal((await call('POST', '/v1/register', { body: { username: `t-${rnd()}`, auth: 'c2hvcnQ=' } })).status, 400);
  const user = `t-${rnd()}`;
  const auth = key();
  await call('POST', '/v1/register', { body: { username: user, auth } });
  assert.equal((await call('PUT', '/v1/data', { user, auth, body: { version: 0, blob: { iv: '<script>', ct: 'x' } } })).status, 400);
  for (let i = 0; i < 10; i++) assert.equal((await call('GET', '/v1/data', { user, auth: key() })).status, 401);
  // now locked, even with the right key
  assert.equal((await call('GET', '/v1/data', { user, auth })).status, 429);
  assert.equal((await call('GET', '/v1/data', { user: 'nobody-here', auth })).status, 401);
});

test('CORS only for allowed origins', async () => {
  const ok = await call('OPTIONS', '/v1/data', { origin: 'https://andrewfilipp1.github.io' });
  assert.equal(ok.headers.get('access-control-allow-origin'), 'https://andrewfilipp1.github.io');
  const bad = await call('OPTIONS', '/v1/data', { origin: 'https://evil.example' });
  assert.equal(bad.headers.get('access-control-allow-origin'), null);
  assert.equal((await call('GET', '/v1/health')).headers.get('cache-control'), 'no-store');
});
