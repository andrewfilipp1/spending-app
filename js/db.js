// Minimal IndexedDB key/value store. Everything stays on this device.

const DB_NAME = 'spending-app';
const STORE = 'kv';
let dbPromise;

function open() {
  dbPromise ??= new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => {
      if (!req.result.objectStoreNames.contains(STORE)) req.result.createObjectStore(STORE);
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbPromise;
}

async function run(mode, fn) {
  const db = await open();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, mode);
    const req = fn(tx.objectStore(STORE));
    tx.oncomplete = () => resolve(req?.result);
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error);
  });
}

export const db = {
  get: (key) => run('readonly', (s) => s.get(key)),
  set: (key, value) => run('readwrite', (s) => s.put(value, key)),
  del: (key) => run('readwrite', (s) => s.delete(key)),
  // Several keys in one transaction: all are written or none.
  setMany: (entries) => run('readwrite', (s) => {
    for (const [k, v] of Object.entries(entries)) s.put(v, k);
  }),
  clear: () => run('readwrite', (s) => s.clear()),
};
