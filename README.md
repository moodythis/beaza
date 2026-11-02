# Beaza (بيزة)

Localized bilingual transaction extraction pipeline and daily spending guardrail
for cashless micro-expenses in Bahrain. Flutter and Dart, Android first.

## Layout

| Path | Purpose |
|---|---|
| `packages/beaza_extraction` | Pure Dart core: extraction pipeline, reconciler and daily guardrail, shared by the app and the evaluation tool |
| `app` | Flutter app (Arabic and English), layered: `data/` repositories, `ui/core`, `ui/features/<feature>/{view_models,views}` |
| `.github/workflows/ci.yml` | Analyzes and tests both, then builds an installable APK |

## Status

| Part | State |
|---|---|
| Normalizer, detector, classifier, Tier 1 templates, validator, extractor facade | Done, tested |
| Reconciler (duplicates, own accounts, spending total) | Done, tested |
| Daily guardrail (limit, 50/80/100% alerts, cap, snooze, micro-expenses, rollover) | Done, tested |
| App: home screen, manual expense, daily limit, Arabic/English | Done, tested; data kept in memory for now |
| Encrypted database (drift + SQLCipher) | Next |
| SMS and notification intake (Kotlin), local alerts, settings, review queue | Later |
| Merchant normalizer and categorizer, Tier 2 model, evaluation harness | Later |

## Without a laptop

- **Tests:** push, open the **Actions** tab, read the latest run.
- **Try the app:** open the latest green run, download the `beaza-apk` artifact
  (a zip), extract it on an Android phone and install `app-release.apk`
  (allow installing from this source when asked). It is signed with a debug
  key, for testing only.
