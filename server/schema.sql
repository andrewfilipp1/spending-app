-- Accounts and their encrypted data. The server never sees passwords, keys or plaintext:
-- `auth_hash` is SHA-256 of a key derived on the device, `data` is AES-256-GCM ciphertext.
CREATE TABLE IF NOT EXISTS users (
  username     TEXT PRIMARY KEY,
  auth_hash    TEXT    NOT NULL,
  created      INTEGER NOT NULL,
  fails        INTEGER NOT NULL DEFAULT 0,
  locked_until INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS blobs (
  username TEXT PRIMARY KEY,
  version  INTEGER NOT NULL,
  data     TEXT,
  updated  INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS signups (
  ip    TEXT    NOT NULL,
  at    INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS signups_ip ON signups (ip, at);
-- Photo estimates per user, for the daily limit (no photos or results are kept).
CREATE TABLE IF NOT EXISTS estimates (
  username TEXT    NOT NULL,
  at       INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS estimates_user ON estimates (username, at);
