-- Google accounts: the stable Google account id ("sub" in the ID token).
-- NULL for email and password accounts; SQLite allows many NULLs in a
-- UNIQUE index.
ALTER TABLE users ADD COLUMN google_sub TEXT;
CREATE UNIQUE INDEX users_google_sub ON users (google_sub);
