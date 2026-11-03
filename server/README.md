# Beaza sync server

A small Cloudflare Worker with a D1 database. It lets one person see the same
ledger on several phones. **It stores only data it cannot read**: every record
is encrypted on the phone (see `packages/beaza_crypto`) before it is sent.

No runtime dependencies. Tests run on Node's built-in SQLite
(`npm test`, Node 22.18 or newer), against the same SQL that runs on D1.

## What the server stores

| Table | Holds |
|---|---|
| `users` | email, a hash of the password key, a hash of the recovery proof, the key bundle (data key, locked), and a change counter |
| `sessions` | a hash of each session token and its expiry |
| `records` | per user: list name, random id, the encrypted blob, a change number |
| `attempts` | wrong-guess counters under keyed hashes (no emails, no addresses) |
| `meta` | a random secret that keys those hashes |

Not stored: passwords, recovery keys, data keys, amounts, merchants, times,
limits, IP addresses, request bodies. The request log has the route and the
status code only.

## API

All bodies are JSON. Keys are 32 bytes in base64url.

| Call | Purpose |
|---|---|
| `GET /v1/health` | Is the server up |
| `POST /v1/register` | `{email, authKey, recoveryAuthKey, bundle}` → `{token}` |
| `POST /v1/kdf` | `{email}` → `{salt, kdf}` for this email. An email with no account gets a steady made-up answer, so the call does not reveal who has an account |
| `POST /v1/login` | `{email, authKey}` → `{token, bundle}` |
| `POST /v1/recover` | `{email, recoveryAuthKey}` → `{token, bundle}` (forgot the password) |
| `POST /v1/password` | New password: `{authKey, bundle}`; other phones are logged out |
| `POST /v1/recovery-key` | New recovery key: `{recoveryAuthKey, bundle}` |
| `POST /v1/records` | Push up to 100 records `{collection, id, blob}` → `{seq}` |
| `GET /v1/records?since=N&limit=M` | Records changed after number N → `{records, nextSince, more, latest}`. `latest` is the account's newest change number; a phone that already pulled past it knows the server lost changes and sends everything again |
| `POST /v1/logout` | End this session |
| `POST /v1/account/delete` | `{authKey}` → deletes the account and every record |

Everything except register, kdf, login, recover and health needs
`Authorization: Bearer <token>`.

## Protections (all covered by tests)

- **Wrong guesses:** login allows 10 wrong tries per email and 40 per address
  in 15 minutes; recovery allows 5 and 20 per hour; sign-up 20 per address per
  hour. A right log-in clears the email's count. Trade-off: someone who knows
  an email can lock that person out for 15 minutes. Accepted, because the
  alternative is unlimited guessing.
- **Same answer for wrong password and unknown email**, with the same amount
  of work, so neither the answer nor the timing shows who has an account.
  (Sign-up itself says "email taken"; that cannot be avoided without email
  verification.)
- **Hashes include the user id** and use their own label per purpose, so a
  password key cannot be used as a recovery proof or the reverse.
- **Sessions:** random 256-bit tokens, only hashes stored, 60 days, at most
  20 per account, and a password change ends all other sessions.
- **No orphaned data:** a password or recovery-key change must keep the same
  data key id, otherwise every stored record would become unreadable.
- **Change numbers are given inside the database transaction** that stores
  the records, so a phone that asks "after N" can never miss a record that
  was committed later with a smaller number.
- **Size limits:** 256 KB body, 100 records per push, 16 KB per record.
- **No CORS headers** (the app is not a web page) and `Cache-Control: no-store`.

## Known limits (for the report)

- A signed-in user can still store a lot of records; there is no per-user
  quota yet.
- The server sees the email, how many records exist, when they change, and
  their size to the nearest 64 bytes.
- Google sign-in is not built yet. It needs a Google client id, and Google
  accounts have only the recovery key (no password).
- Conflicts (two phones changing one record) are settled on the phones by
  the changed-time inside the encrypted record; the server only keeps the
  last pushed version.

## Run and deploy

```
cd server
npm test                 # needs Node 22.18+, no install step
npx wrangler deploy      # done automatically by Workers Builds
```

The D1 schema is in `migrations/`. Apply new files with
`npx wrangler d1 migrations apply beaza-sync-eu --remote`. The database
was created with the EU jurisdiction, which can only be set at creation.
