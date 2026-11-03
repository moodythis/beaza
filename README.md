# Beaza (بيزة)

Localized bilingual transaction extraction pipeline and daily spending guardrail
for cashless micro-expenses in Bahrain. Flutter and Dart, Android first.

## Layout

| Path | Purpose |
|---|---|
| `packages/beaza_extraction` | Pure Dart core: extraction pipeline, reconciler and daily guardrail, shared by the app and the evaluation tool |
| `packages/beaza_crypto` | Pure Dart end-to-end encryption for sync (keys, recovery key, record encryption) |
| `app` | Flutter app (Arabic and English), MVVM: `data/` repositories and services, `domain/use_cases`, `ui/core`, `ui/features/<feature>/{view_models,views}`; Kotlin SMS intake and alerts in `android/` |
| `server` | Optional sync server: Cloudflare Worker with a D1 database in the EU; stores only encrypted records |
| `docs` | Privacy compliance notes (GDPR, Bahrain PDPL) and the app icon |
| `dartpad` | Old single-file snapshots of early stages; not maintained |
| `.github/workflows/ci.yml` | Tests every part (extraction, crypto, server, phone-server contract, app, a two-phone sync test) and builds the APK |

## Status

| Part | State |
|---|---|
| Normalizer, detector, classifier, Tier 1 templates (BisB, ila, Al Salam, BenefitPay), validator, extractor | Done, tested |
| Reconciler (duplicates, own accounts, spending total) | Done, tested |
| Daily guardrail (limit, 50/80/100% alerts, cap, snooze, micro-expenses, rollover) | Done, tested |
| App: home, manual expense, daily limit, review of unread messages, Arabic/English | Done, tested |
| Encrypted database (drift + SQLite3 Multiple Ciphers, key in Android Keystore) | Done, tested |
| SMS intake (Kotlin receiver, background run) and local alerts | Done; battery saving can delay background alerts (the app shows a card) |
| Optional account, end-to-end encrypted sync, merge protection | Done, tested (including a two-phone test against the real server code) |
| Data export to a JSON file | Done, tested |
| Notification intake (wallet apps), merchant normalizer and categorizer | Later |
| Evaluation harness | B1 (rules) built: `packages/beaza_extraction/eval` |
| Tier 2 model (B2, B3) | Later |
| Changing the account email | Later |

## Without a laptop

- **Tests:** push, open the **Actions** tab, read the latest run.
- **Try the app:** open the latest green run, download the `beaza-apk` artifact
  (a zip), extract it on an Android phone and install `app-release.apk`.
  Google Play Protect may block it because it reads SMS; pause scanning while
  installing. It is signed with a test key (`app/android/keystore`), not for
  release.
