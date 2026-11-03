-- Phones remembered for Google log-in. Each holds a random key (only its
-- hash is here) and keeps the data key itself, so these open no data.
CREATE TABLE devices (
  key_hash   TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL
) STRICT;
CREATE INDEX devices_user ON devices (user_id, created_at);
