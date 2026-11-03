# Privacy compliance: GDPR and Bahrain PDPL

How Beaza meets the EU General Data Protection Regulation (GDPR) and
Bahrain's Personal Data Protection Law (Law No. 30 of 2018, "PDPL"), where
in the code each part lives, and what is still missing.

> Written for a graduation project. It is not legal advice; a lawyer should
> review it before a public release.

## Does each law apply?

- **Bahrain PDPL** applies: the users and the person running the service are
  in Bahrain.
- **GDPR** applies to services offered to people in the EU. Beaza targets
  Bahrain, so GDPR may not strictly apply, but it is followed as the stricter
  reference standard, and the server's database is kept in the EU.

## Personal data processed

| Data | Where | Readable by the server? |
|---|---|---|
| Bank message text | Phone memory only, never stored or sent | — |
| Transactions, limits, settings | Phone (encrypted database); server only as encrypted records if the user has an account | No |
| Email address | Server | Yes (needed to log in) |
| Password / recovery key | Never leave the phone; the server stores hashes of keys derived from them | No |
| Consent record (versions, time) | Server | Yes |
| IP address | Cloudflare edge for delivery and attack protection; not stored by Beaza | Not stored |

## Requirement → implementation

| Requirement | Source | How Beaza meets it | Code |
|---|---|---|---|
| Lawful basis | GDPR Art. 6(1)(a); PDPL consent rule | Consent is the only basis used | `server/src/app.ts` `checkConsent` |
| Consent freely given, specific, unambiguous | GDPR Art. 4(11), 7 | Three separate, unticked boxes; the button stays off until all are ticked | `app/.../sign_up_view.dart` |
| Consent not bundled with terms | GDPR Art. 7(2) | Privacy notice and terms of use are separate documents and separate boxes | `server/src/legal.ts`, sign-up screen |
| Able to show consent | GDPR Art. 7(1) | Server records privacy version, terms version and server time | `migrations/0002_consent.sql` |
| Withdraw consent as easily as given | GDPR Art. 7(3) | "Delete account" on the Account screen | `account_view.dart`, `POST /v1/account/delete` |
| Information to the person | GDPR Art. 13; PDPL | Privacy notice in Arabic and English, in the app before sign-up (works offline) and at `/privacy` | `legal.ts`, `legal_text.dart` (generated) |
| Same text everywhere | Accountability | The app's text is generated from the server's; a test fails if they differ | `server/scripts/legal-dart.ts`, `test/legal-sync.test.ts` |
| Changed notice → new consent | GDPR Art. 7, 13 | Versions; the server refuses sign-up with an old version (`documents_outdated`) | `checkConsent` |
| Children | GDPR Art. 8 (16, or 13 to 16 by state) | Accounts for 18 or over, stated separately at sign-up | consent `adult` |
| Data minimisation | GDPR Art. 5(1)(c) | No message text kept; server gets only email, hashes, locked key, encrypted blobs; no IP addresses or request bodies logged | `server/README.md` "What the server stores" |
| Purpose limitation | GDPR Art. 5(1)(b) | Sync only; no ads, analytics, sharing, profiling or automated decisions | privacy notice |
| Storage limitation | GDPR Art. 5(1)(e) | Kept until account deletion; sessions 60 days; attempt counters reset within an hour | `app.ts` |
| Right of access | GDPR Art. 15; PDPL | Account screen shows what the server holds | `GET /v1/account` |
| Right to erasure | GDPR Art. 17; PDPL | Delete account removes the user, sessions and records in one transaction | `deleteAccount` |
| Portability | GDPR Art. 20 | The data stays on the phone. **Gap:** no export file yet | — |
| Rectification | GDPR Art. 16 | **Gap:** email cannot be changed in the app yet | — |
| Privacy by design and default | GDPR Art. 25 | Works fully without an account; sync is off until the user signs up; end-to-end encryption | `beaza_crypto` |
| Security of processing | GDPR Art. 32; PDPL | XChaCha20-Poly1305, Argon2id with a floor the phone enforces, hashed tokens, rate limits, encrypted phone database, no cloud backup | `beaza_crypto/README.md`, `server/README.md` |
| Processor | GDPR Art. 28 | Cloudflare processes data on our behalf under its Data Processing Addendum | — |
| Transfer outside Bahrain | PDPL transfer rules | The EU is on Bahrain's list of countries with adequate protection; the D1 database is created with the EU jurisdiction | `server/wrangler.jsonc` |
| Breach notification | GDPR Art. 33-34; PDPL (72 hours) | Stated in the notice. End-to-end encryption limits a breach to email addresses | — |
| Complaint | GDPR Art. 77; PDPL | The notice names Bahrain's Personal Data Protection Authority (duties currently with the Ministry of Justice, Islamic Affairs and Endowments) | privacy notice |

## Before a public release

1. Notify Bahrain's Personal Data Protection Authority before processing
   (PDPL notification duty).
2. Add a privacy contact to the notice (Worker variable `PRIVACY_CONTACT`).
3. Keep a record of processing (GDPR Art. 30) and a short data protection
   impact assessment (financial data, SMS access).
4. Write a breach response procedure (who checks, who notifies, within 72
   hours).
5. Fill in Google Play's Data safety form to match this document, and link
   `/privacy`.
6. Add data export and email change (closes the two gaps above).
7. Have a lawyer review the notice and the terms.

## Sources

- DLA Piper, *Data Protection Laws of the World: Bahrain*.
- Cloudflare, *D1 data location* (jurisdictions).
- Regulation (EU) 2016/679 (GDPR).
