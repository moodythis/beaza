# beaza_crypto

End-to-end encryption for Beaza sync. Pure Dart (`package:cryptography`), no
Flutter dependency, so it is tested in CI like `beaza_extraction`.

**Goal:** the user can see the same ledger on several phones, and the sync
server — or anyone who steals its database — cannot read any of it.

## Keys

| Key | Made where | Kept where | Purpose |
|---|---|---|---|
| Data key (32 random bytes) | First phone | Each phone's secure storage (Android Keystore) | Root of all record encryption |
| Record key | HKDF from the data key | Memory only | Encrypts records |
| Recovery key (144 random bits + 16-bit checksum) | First phone | Written down by the user; never stored by the app or sent | Opens the data key when the password is lost; the only lock for Google accounts |
| Password keys | Argon2id(password, salt) then HKDF | Memory only | `authKey` is sent to log in; `wrapKey` opens the data key and never leaves the phone |

The server stores a **key bundle**: the data key locked twice (once with
`wrapKey`, once with the recovery key), plus the salt and Argon2id setting.
It also stores a hash of `authKey`, never the password.

## Algorithms

- **XChaCha20-Poly1305** for everything encrypted. 24-byte random nonces are
  safe for any number of messages under one key.
- **Argon2id**, 19 MiB, 2 passes, 1 lane (OWASP's setting), for the
  password. The setting is stored per account so it can be raised later.
- **HKDF-SHA256** to split one secret into keys with different labels.
- Every ciphertext is bound to a context string (`beaza/v1/record/<list>/<id>`,
  `beaza/v1/data-key/<lock>/<keyId>`), so the server cannot move a record to
  another id, swap locked keys between accounts, or replay one record as
  another.
- Record plaintext is padded to 64-byte blocks so the blob size does not
  reveal amounts or merchant-name lengths.

## Flows

- **Sign up (email):** make data key + recovery key → lock the data key with
  both → send email, `authKey`, bundle → show the recovery key once.
- **Sign up (Google):** same without a password; Google proves identity, the
  recovery key is the only lock.
- **Log in on another phone:** get salt and setting for the email → refuse a
  setting below the minimum → derive keys → send `authKey` → receive the
  bundle → open the data key with `wrapKey`.
- **Forgot password:** open the data key with the recovery key → set a new
  password (new salt). Records stay as they are because the data key does
  not change.
- **Lost recovery key:** any phone still logged in can make a new one.
- **Lost everything** (all phones, password and recovery key): the server
  copy cannot be opened by anyone, including us. The app rebuilds what it
  can from the bank messages still on the phone.

## What the server can still learn

Account email (or Google id), how many records exist and in which list,
when they change, rough record size (in 64-byte steps), and IP addresses.
It cannot learn amounts, merchants, times of purchase, limits or anything
else inside a record.

## Why not WhatsApp's approach

WhatsApp's password-protected backups keep the key in hardware security
modules that erase it after a few wrong guesses. That needs dedicated
hardware a student project cannot run. Beaza uses a recovery key instead,
which gives the same protection; the cost is that the user must keep it.

## Defences tested (`test/`)

- Wrong password / wrong recovery key / other account's key → `DecryptionFailed`.
- One changed byte anywhere → `DecryptionFailed`.
- Record moved to another id or list → `DecryptionFailed`.
- A server asking a new phone for a cheap Argon2id setting → refused
  (`WeakKdfParams`), because the phone would then send an `authKey` that is
  cheap to guess from.
- Typing mistakes in the recovery key are caught by the checksum before any
  network call.
- Everything uploaded (bundle, auth key, records) contains no amount,
  merchant, field name, password, recovery key or data key.
