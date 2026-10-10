// Sync server for "Τα Οικονομικά μου" — stores one end-to-end encrypted blob per account.
// Platform-independent: runs on Cloudflare Workers (src/index.js) or Node.js (src/node.js).
// `env` provides DB (D1-style API), ALLOWED_ORIGINS and clientIP(req).
//
// Auth: every request carries `Authorization: Sync <username>:<base64 auth key>`. The auth key is
// derived on the device from the password (PBKDF2) and is unrelated to the encryption key, which
// never leaves the device. Only SHA-256(auth key) is stored.
//
//   POST   /v1/register  { username, auth }      → 201 | 409 taken
//   GET    /v1/data                               → { version, blob | null }
//   PUT    /v1/data      { version, blob }        → { version } | 409 { version, blob }
//   DELETE /v1/account                            → 204

const USER_RE = /^[a-z0-9._-]{3,32}$/;
const MAX_BODY = 5 * 1024 * 1024;
const MAX_FAILS = 10;
const LOCK_MS = 15 * 60 * 1000;
const SIGNUPS_PER_IP_PER_DAY = 10;

export async function handle(req, env) {
  {
    const cors = corsHeaders(req.headers.get('Origin'), env);
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    let res;
    try {
      res = await route(req, env);
    } catch (err) {
      console.error(err);
      res = json({ error: 'server' }, 500);
    }
    for (const [k, v] of Object.entries(cors)) res.headers.set(k, v);
    res.headers.set('Cache-Control', 'no-store');
    res.headers.set('X-Content-Type-Options', 'nosniff');
    res.headers.set('Referrer-Policy', 'no-referrer');
    return res;
  }
}

function corsHeaders(origin, env) {
  const allowed = (env.ALLOWED_ORIGINS || '').split(',').map((s) => s.trim()).filter(Boolean);
  if (!origin || !allowed.includes(origin)) return { Vary: 'Origin' };
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'GET, PUT, POST, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

const json = (obj, status = 200) => new Response(JSON.stringify(obj), {
  status,
  headers: { 'Content-Type': 'application/json; charset=utf-8' },
});

async function route(req, env) {
  const { pathname } = new URL(req.url);
  if (pathname === '/v1/health') return json({ ok: true });
  if (pathname === '/v1/register' && req.method === 'POST') return register(req, env);

  const auth = await authenticate(req, env);
  if (auth.error) return json({ error: auth.error }, auth.status);
  const user = auth.user;

  if (pathname === '/v1/data' && req.method === 'GET') {
    const row = await env.DB.prepare('SELECT version, data FROM blobs WHERE username = ?').bind(user).first();
    return json({ version: row?.version ?? 0, blob: row?.data ? JSON.parse(row.data) : null });
  }
  if (pathname === '/v1/data' && req.method === 'PUT') {
    const body = await readJSON(req);
    if (!body || !Number.isInteger(body.version) || !isBlob(body.blob)) return json({ error: 'bad_request' }, 400);
    const data = JSON.stringify({ iv: body.blob.iv, ct: body.blob.ct });
    const now = Date.now();
    // Optimistic concurrency: only the holder of the latest version may write.
    const r = await env.DB.prepare('UPDATE blobs SET version = version + 1, data = ?, updated = ? WHERE username = ? AND version = ?')
      .bind(data, now, user, body.version).run();
    if (r.meta.changes === 1) return json({ version: body.version + 1 });
    const row = await env.DB.prepare('SELECT version, data FROM blobs WHERE username = ?').bind(user).first();
    return json({ error: 'conflict', version: row.version, blob: row.data ? JSON.parse(row.data) : null }, 409);
  }
  if (pathname === '/v1/account' && req.method === 'DELETE') {
    await env.DB.batch([
      env.DB.prepare('DELETE FROM blobs WHERE username = ?').bind(user),
      env.DB.prepare('DELETE FROM users WHERE username = ?').bind(user),
    ]);
    return new Response(null, { status: 204 });
  }
  return json({ error: 'not_found' }, 404);
}

async function register(req, env) {
  const body = await readJSON(req);
  const username = body?.username;
  const authBytes = decodeAuth(body?.auth);
  if (typeof username !== 'string' || !USER_RE.test(username) || !authBytes) return json({ error: 'bad_request' }, 400);

  const ip = env.clientIP?.(req) || 'unknown';
  const dayAgo = Date.now() - 86400000;
  const recent = await env.DB.prepare('SELECT COUNT(*) AS n FROM signups WHERE ip = ? AND at > ?').bind(ip, dayAgo).first();
  if (recent.n >= SIGNUPS_PER_IP_PER_DAY) return json({ error: 'rate_limited' }, 429);

  const now = Date.now();
  try {
    await env.DB.batch([
      env.DB.prepare('INSERT INTO users (username, auth_hash, created) VALUES (?, ?, ?)').bind(username, await sha256hex(authBytes), now),
      env.DB.prepare('INSERT INTO blobs (username, version, data, updated) VALUES (?, 0, NULL, ?)').bind(username, now),
      env.DB.prepare('INSERT INTO signups (ip, at) VALUES (?, ?)').bind(ip, now),
      env.DB.prepare('DELETE FROM signups WHERE at < ?').bind(dayAgo),
    ]);
  } catch (err) {
    if (String(err).includes('UNIQUE')) return json({ error: 'taken' }, 409);
    throw err;
  }
  return json({ ok: true }, 201);
}

async function authenticate(req, env) {
  const m = /^Sync ([^:\s]+):([A-Za-z0-9+/=]+)$/.exec(req.headers.get('Authorization') || '');
  const authBytes = m && decodeAuth(m[2]);
  if (!m || !USER_RE.test(m[1]) || !authBytes) return { error: 'unauthorized', status: 401 };
  const user = m[1];
  const row = await env.DB.prepare('SELECT auth_hash, fails, locked_until FROM users WHERE username = ?').bind(user).first();
  const hash = await sha256hex(authBytes);
  if (!row) return { error: 'unauthorized', status: 401 };
  const now = Date.now();
  if (row.locked_until > now) return { error: 'locked', status: 429 };
  if (!constantTimeEqual(hash, row.auth_hash)) {
    const fails = row.fails + 1;
    await env.DB.prepare('UPDATE users SET fails = ?, locked_until = ? WHERE username = ?')
      .bind(fails >= MAX_FAILS ? 0 : fails, fails >= MAX_FAILS ? now + LOCK_MS : 0, user).run();
    return { error: 'unauthorized', status: 401 };
  }
  if (row.fails) await env.DB.prepare('UPDATE users SET fails = 0 WHERE username = ?').bind(user).run();
  return { user };
}

async function readJSON(req) {
  const len = Number(req.headers.get('Content-Length') || 0);
  if (len > MAX_BODY) return null;
  const text = await req.text();
  if (text.length > MAX_BODY) return null;
  try { return JSON.parse(text); } catch { return null; }
}

function decodeAuth(b64) {
  if (typeof b64 !== 'string' || b64.length > 64) return null;
  try {
    const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
    return bytes.length === 32 ? bytes : null;
  } catch { return null; }
}

const isB64 = (s, max) => typeof s === 'string' && s.length <= max && /^[A-Za-z0-9+/=]+$/.test(s);
const isBlob = (b) => b && isB64(b.iv, 32) && isB64(b.ct, MAX_BODY);

async function sha256hex(bytes) {
  const d = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  return [...d].map((x) => x.toString(16).padStart(2, '0')).join('');
}

// Compares two hex strings without leaking where they differ through timing.
function constantTimeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
