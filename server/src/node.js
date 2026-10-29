// Node.js entry point (≥ 22.13, no dependencies): `node src/node.js`.
// Listens on 127.0.0.1 only — a reverse proxy (Caddy, see deploy/) terminates HTTPS in front of it.
//
// Environment:
//   PORT             default 8787
//   DB_PATH          default ./data/sync.db
//   ALLOWED_ORIGINS  comma-separated, e.g. https://andrewfilipp1.github.io
//   TRUST_PROXY=1    take the client IP from X-Real-IP (set by Caddy)
//   ANTHROPIC_API_KEY  enables photo calorie estimates (POST /v1/estimate); ESTIMATE_MODEL, ESTIMATES_PER_DAY optional

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { handle } from './app.js';

const PORT = Number(process.env.PORT || 8787);
const HOST = process.env.HOST || '127.0.0.1';
const DB_PATH = process.env.DB_PATH || path.resolve('data/sync.db');
const MAX_BODY = 5 * 1024 * 1024 + 1024;

fs.mkdirSync(path.dirname(DB_PATH), { recursive: true, mode: 0o700 });
const sqlite = new DatabaseSync(DB_PATH);
sqlite.exec('PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA busy_timeout = 3000;');
sqlite.exec(fs.readFileSync(new URL('../schema.sql', import.meta.url), 'utf8'));
fs.chmodSync(DB_PATH, 0o600);

// The small subset of Cloudflare D1's API that app.js uses, on top of node:sqlite.
class Statement {
  constructor(sql, args = []) {
    this.sql = sql;
    this.args = args;
  }
  bind(...args) { return new Statement(this.sql, args); }
  async first() { return this.get(); }
  async run() { return this.exec(); }
  get() {
    const row = sqlite.prepare(this.sql).get(...this.args);
    return row ? { ...row } : null;
  }
  exec() {
    const r = sqlite.prepare(this.sql).run(...this.args);
    return { meta: { changes: Number(r.changes) } };
  }
}
const DB = {
  prepare: (sql) => new Statement(sql),
  async batch(statements) {
    sqlite.exec('BEGIN IMMEDIATE');
    try {
      const out = statements.map((s) => s.exec());
      sqlite.exec('COMMIT');
      return out;
    } catch (err) {
      sqlite.exec('ROLLBACK');
      throw err;
    }
  },
};

const env = {
  DB,
  ALLOWED_ORIGINS: process.env.ALLOWED_ORIGINS || '',
  ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY || '',
  ESTIMATE_MODEL: process.env.ESTIMATE_MODEL || '',
  ESTIMATES_PER_DAY: process.env.ESTIMATES_PER_DAY || '',
  clientIP: (req) => (process.env.TRUST_PROXY === '1' ? req.headers.get('X-Real-IP') : null) || req.clientAddress,
};

const server = http.createServer(async (nreq, nres) => {
  try {
    const chunks = [];
    let size = 0;
    for await (const c of nreq) {
      size += c.length;
      if (size > MAX_BODY) {
        nres.writeHead(413, { 'Content-Type': 'application/json' }).end('{"error":"too_large"}');
        return;
      }
      chunks.push(c);
    }
    const headers = new Headers();
    for (const [k, v] of Object.entries(nreq.headers)) if (typeof v === 'string') headers.set(k, v);
    const req = new Request(`http://${HOST}${nreq.url}`, {
      method: nreq.method,
      headers,
      body: ['GET', 'HEAD', 'OPTIONS'].includes(nreq.method) ? undefined : Buffer.concat(chunks),
    });
    req.clientAddress = nreq.socket.remoteAddress;
    const res = await handle(req, env);
    nres.writeHead(res.status, Object.fromEntries(res.headers));
    nres.end(Buffer.from(await res.arrayBuffer()));
  } catch (err) {
    console.error(err);
    if (!nres.headersSent) nres.writeHead(500, { 'Content-Type': 'application/json' });
    nres.end('{"error":"server"}');
  }
});
server.requestTimeout = 30_000;
server.headersTimeout = 15_000;
server.listen(PORT, HOST, () => console.log(`spending-sync listening on http://${HOST}:${PORT}`));

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => server.close(() => { sqlite.close(); process.exit(0); }));
}
