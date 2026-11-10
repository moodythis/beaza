# Beaza (بيزة)

Localized bilingual transaction extraction pipeline and daily spending guardrail
for cashless micro-expenses in Bahrain. Flutter and Dart, Android first.

## Layout

| Path | Purpose |
|---|---|
| `packages/beaza_extraction` | Pure Dart core: extraction pipeline, reconciler and daily guardrail, shared by the app and the evaluation tool |
| `packages/beaza_crypto` | Pure Dart end-to-end encryption for sync (keys, recovery key, record encryption) |
| `app` | Flutter app (Arabic and English), MVVM: `data/` repositories and services, `domain/use_cases`, `ui/core`, `ui/features/<feature>/{view_models,views}`; Kotlin SMS intake and alerts in `android/` |
| `server` | Cloudflare Worker (`beaza-sync`) with a D1 database in the EU: optional sync that stores only encrypted records, and the AI endpoints (`/v1/coach`, `/v1/alternatives`, `/v1/categorize`, `/v1/receipt`, `/v1/voice`, `/v1/expenses`) that keep no content |
| `docs` | Privacy compliance notes (GDPR, Bahrain PDPL) and the app icon. The SRS, Design, discussion guide and the Arabic user guide are kept as shared documents outside the repo |
| `dartpad` | Old single-file snapshots of early stages; not maintained |
| `.github/workflows/ci.yml` | Tests every part (extraction, crypto, server, phone-server contract, app, a two-phone sync test) and builds the APK |

## Status

| Part | State |
|---|---|
| Normalizer, detector, classifier, Tier 1 templates (BisB, ila, Al Salam, BenefitPay, NBB, KFH), validator, extractor | Done, tested; BBK and AUB are detected but have no template yet |
| Reconciler (duplicates, own accounts, spending total, money paid back within 30 days) | Done, tested |
| Daily guardrail (limit, 50/80/100% alerts, cap, snooze, micro-expenses, rollover) | Done, tested |
| App: four tabs (Today, History, Insights, Saving), light theme by default, short motion that turns off with reduced motion | Done, tested |
| Daily limit from income with no saving or one of six profiles (pay yourself first, 50/30/20, 70/20/10, weekend weighted, kakeibo, own amount) | Done, tested |
| Today: limit card, "Can I buy it?" with "Wait 24 hours", AI plan tile, challenge tile, weekly report card, small purchases | Done, tested |
| Today's pace: a forecast from the person's usual day (last 28 days, per Bahrain hour) that says before the limit is crossed whether a usual rest of the day fits or passes it, and when; drawn as a chart with the late-night hours shaded | Done, tested |
| History: day list, unsorted filter, change category (own categories too), edit, delete, swipe to delete, "money came back" switch | Done, tested |
| Insights: Ask (on the phone), category ring with percentages, rule tips, weekly challenge, AI plan, cheaper alternatives | Done, tested |
| Saving: goal, 24-hour holds with a "Did you decide?" notification, subscriptions, demo points and offers | Done, tested; a reminder is lost if the phone restarts |
| Weekly report (9 sections, week by week, Saturday 21:00 notification without amounts) and the privacy eye | Done, tested |
| Manual expense, quick add by text or voice, receipt photo read on the phone | Done, tested |
| Optional AI (Google Gemini through the Worker, key kept as a Worker secret): plan, cheaper ideas, sorting, receipt and voice reading, each with its own consent | Done, tested; falls back to rules or the phone when Gemini does not answer |
| Encrypted database (drift + SQLite3 Multiple Ciphers, key in Android Keystore) | Done, tested |
| SMS intake (Kotlin receiver, background run) and local alerts | Done; battery saving can delay background alerts (the app shows a card) |
| Optional account, end-to-end encrypted sync, merge protection | Done, tested (including a two-phone test against the real server code) |
| Data export to a JSON file | Done, tested |
| Merchant normalizer and categorizer | Done (names cleaned, nine categories plus the user's own) |
| Notification intake (wallet apps) | Later |
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
