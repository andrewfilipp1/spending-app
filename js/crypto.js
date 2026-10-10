// At-rest encryption with the Web Crypto API.
// Key: PBKDF2-SHA-256 (600k iterations) from the passcode. Cipher: AES-256-GCM,
// whose authentication tag also detects a wrong passcode or tampered data.

export const PBKDF2_ITERATIONS = 600_000;

const enc = new TextEncoder();
const dec = new TextDecoder();

const toB64 = (buf) => {
  const bytes = new Uint8Array(buf);
  let bin = '';
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(bin);
};
const fromB64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

export const randomSalt = () => toB64(crypto.getRandomValues(new Uint8Array(16)));

export async function deriveKey(passcode, saltB64, iterations = PBKDF2_ITERATIONS) {
  const base = await crypto.subtle.importKey('raw', enc.encode(passcode), 'PBKDF2', false, ['deriveKey']);
  return crypto.subtle.deriveKey(
    { name: 'PBKDF2', salt: fromB64(saltB64), iterations, hash: 'SHA-256' },
    base,
    { name: 'AES-GCM', length: 256 },
    false, // not extractable
    ['encrypt', 'decrypt'],
  );
}

export async function encryptJSON(key, value) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, enc.encode(JSON.stringify(value)));
  return { iv: toB64(iv), ct: toB64(ct) };
}

// Throws if the key is wrong or the data was modified.
export async function decryptJSON(key, { iv, ct }) {
  const pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: fromB64(iv) }, key, fromB64(ct));
  return JSON.parse(dec.decode(pt));
}
