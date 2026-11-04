-- How many AI savings plans were asked for each UTC day, for everyone
-- together (no user, device or IP). Only to stay inside the free Workers AI
-- allowance. IF NOT EXISTS: this table may be created by hand first.
CREATE TABLE IF NOT EXISTS coach_usage (
  day   TEXT PRIMARY KEY,
  count INTEGER NOT NULL
) STRICT;
