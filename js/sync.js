// Account + end-to-end encrypted sync.
//
// From the account password the device derives (PBKDF2-SHA-256, 600k rounds) 64 bytes:
//   • the first 32 are the AES-256-GCM key that encrypts the data — they never leave the device;
//   • the last 32 are the login key sent to the server, which stores only its SHA-256.
// The server therefore holds nothing it can read, and knows neither the password nor the data.

import { encryptJSON, decryptJSON } from './crypto.js';

export const SYNC_URL = (self.SYNC_URL || '').replace(/\/$/, '');
export const enabled = () => !!SYNC_URL;
export const USER_RE = /^[a-z0-9._-]{3,32}$/;
export const normUser = (u) => String(u || '').trim().toLowerCase();

const enc = new TextEncoder();
const toB64 = (bytes) => btoa(String.fromCharCode(...bytes));
const fromB64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

export async function deriveAccountKeys(username, password) {
  const base = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = new Uint8Array(await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt: enc.encode(`spending-app/sync/v1/${username}`), iterations: 600_000, hash: 'SHA-256' },
    base, 512,
  ));
  return { username, encKey: toB64(bits.slice(0, 32)), auth: toB64(bits.slice(32)) };
}

const aesKey = (creds) => crypto.subtle.importKey('raw', fromB64(creds.encKey), 'AES-GCM', false, ['encrypt', 'decrypt']);

export class SyncError extends Error {
  constructor(code, status) {
    super(code);
    this.code = code;
    this.status = status;
  }
}

async function api(creds, method, path, body) {
  let res;
  try {
    res = await fetch(SYNC_URL + path, {
      method,
      headers: {
        ...(body ? { 'Content-Type': 'application/json' } : {}),
        ...(creds ? { Authorization: `Sync ${creds.username}:${creds.auth}` } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
      cache: 'no-store',
      credentials: 'omit',
      referrerPolicy: 'no-referrer',
    });
  } catch {
    throw new SyncError('offline', 0);
  }
  const data = res.status === 204 ? null : await res.json().catch(() => null);
  if (res.ok || res.status === 409) return { status: res.status, data };
  throw new SyncError(data?.error || 'server', res.status);
}

export async function register(creds) {
  await api(null, 'POST', '/v1/register', { username: creds.username, auth: creds.auth });
}

/** Checks the login and that the stored data opens with this password. */
export async function verify(creds) {
  const { data } = await api(creds, 'GET', '/v1/data');
  if (data.blob) await decryptJSON(await aesKey(creds), data.blob).catch(() => { throw new SyncError('decrypt', 0); });
}

export async function deleteAccount(creds) {
  await api(creds, 'DELETE', '/v1/account');
}

/**
 * One sync round. `merge(remoteData|null)` returns the data that should be on the server
 * (plus whether it differs from the remote copy); on a version conflict it is retried.
 */
export async function syncRound(creds, merge) {
  const key = await aesKey(creds);
  for (let attempt = 0; attempt < 4; attempt++) {
    const { data: remote } = await api(creds, 'GET', '/v1/data');
    let remoteData = null;
    if (remote.blob) {
      try {
        remoteData = await decryptJSON(key, remote.blob);
      } catch {
        throw new SyncError('decrypt', 0);
      }
    }
    const { result, changed } = merge(remoteData);
    if (!changed) return { result, version: remote.version };
    const put = await api(creds, 'PUT', '/v1/data', { version: remote.version, blob: await encryptJSON(key, result) });
    if (put.status === 200) return { result, version: put.data.version };
  }
  throw new SyncError('conflict', 409);
}
