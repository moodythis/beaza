# Beaza (بيزة)

Localized bilingual transaction extraction pipeline and daily spending guardrail
for cashless micro-expenses in Bahrain. Flutter and Dart, Android first.

## Layout

| Path | Purpose |
|---|---|
| `packages/beaza_extraction` | Pure Dart extraction core, shared by the app and the evaluation tool |
| `.github/workflows/ci.yml` | Runs `dart analyze` and `dart test` on every push |

The Flutter app and the Kotlin intake plugin will be added later (see the Design chapter).

## Tests without a laptop

Push to GitHub, open the **Actions** tab, and read the result of the latest run.
