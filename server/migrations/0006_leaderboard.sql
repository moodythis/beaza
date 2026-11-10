-- The optional leaderboard (FR-9.10). A row holds no account, e-mail, IP,
-- amount or shop: only the hash of a random id the phone made up, a persona
-- number, an optional nickname (letters and spaces only), the points of the
-- last 30 days and the streak. At most 50 rows are kept.
CREATE TABLE IF NOT EXISTS leaderboard (
  id_hash     TEXT PRIMARY KEY,
  number      INTEGER NOT NULL,
  nickname    TEXT,
  points      INTEGER NOT NULL,
  streak      INTEGER NOT NULL,
  updated_day TEXT NOT NULL
) STRICT;

-- How many board updates came in each UTC day, for everyone together, to
-- stay inside the free database allowance.
CREATE TABLE IF NOT EXISTS leaderboard_usage (
  day   TEXT PRIMARY KEY,
  count INTEGER NOT NULL
) STRICT;
