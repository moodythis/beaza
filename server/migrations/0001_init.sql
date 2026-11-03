-- Beaza sync server, first schema.
--
-- Nothing here can be read without the user's keys: records.blob is an
-- encrypted blob made on the phone, users.bundle holds the data key only in
-- locked form, and the two *_hash columns hold hashes of keys the phone
-- derives from the password and the recovery key (never the secrets).

CREATE TABLE users (
  id                 TEXT PRIMARY KEY,
  email              TEXT NOT NULL UNIQUE,
  auth_hash          TEXT NOT NULL,
  recovery_auth_hash TEXT NOT NULL,
  bundle             TEXT NOT NULL,
  seq                INTEGER NOT NULL DEFAULT 0,
  created_at         INTEGER NOT NULL
) STRICT;

-- Only a hash of each session token is stored.
CREATE TABLE sessions (
  token_hash TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
) STRICT;
CREATE INDEX sessions_user ON sessions (user_id, created_at);

-- seq grows by one for every change of a user's records, so a phone asks
-- for "everything after seq N".
CREATE TABLE records (
  user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  collection TEXT NOT NULL,
  id         TEXT NOT NULL,
  blob       TEXT NOT NULL,
  seq        INTEGER NOT NULL,
  PRIMARY KEY (user_id, collection, id)
) STRICT;
CREATE INDEX records_seq ON records (user_id, seq);

-- Wrong-password counters. Keys are keyed hashes of the email or address,
-- so this table holds no emails and no IP addresses.
CREATE TABLE attempts (
  key          TEXT PRIMARY KEY,
  count        INTEGER NOT NULL,
  window_start INTEGER NOT NULL
) STRICT;

CREATE TABLE meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
) STRICT;
