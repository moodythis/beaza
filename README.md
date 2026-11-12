# Beaza (بيزة)

An Android app that helps students in Bahrain keep to a daily spending limit.
It reads the bank's SMS messages on the phone, works out what was spent, and
warns before the limit is passed. Arabic and English.

Graduation project, College of Information Technology, University of Bahrain.

## Try it

Download the APK from the [latest release](https://github.com/moodythis/beaza/releases/latest)
and install it on an Android phone.

Google Play Protect may block the install because the app reads SMS and is not
on the Play Store. Pause Play Protect scanning while installing, then turn it
back on. The APK is signed with a test key and is meant for evaluation only.

## What it does

- **Reads bank messages on the phone.** Templates for NBB, BBK, BisB, ila,
  Al Salam, KFH and BenefitPay. A message with no template goes to review
  instead of being guessed.
- **Daily limit.** Set by hand or worked out from income, with alerts at 50%,
  80% and 100%, a forecast of where today ends, and "Can I buy it?".
- **Saving.** A goal, a 24-hour wait before a purchase, subscriptions, a daily
  close that moves unspent money to the goal, a streak and a leaderboard.
- **Questions.** "How much did I spend this week?", "Where did my money go?",
  answered on the phone in Gulf Arabic or English.
- **Optional AI** (Google Gemini, through the project's server): a savings
  plan, sorting of shop names, receipt and voice reading. Each needs its own
  consent, and each has a fallback on the phone.
- **Optional sync** between a person's phones, end-to-end encrypted.

The deals and coupons in the Saving tab are a demo: the shops are made up.

## Privacy

Everything works without an account, and bank messages never leave the phone.
The local database is encrypted with a key in the Android Keystore. Sync
stores only records the server cannot read. The savings plan sends totals and
shop names, never message text, account numbers or people's names. A receipt
photo or a voice recording is sent only when the person turns that on. Details
are in [docs/privacy-compliance.md](docs/privacy-compliance.md).

## How it is built

| Path | What is there |
|---|---|
| `app` | The Flutter app (MVVM), with Kotlin for SMS intake and reminders |
| `packages/beaza_extraction` | Pure Dart: reading messages, removing duplicates, the daily limit, and the evaluation tool |
| `packages/beaza_assistant` | Pure Dart: the questions screen and Bahraini money words |
| `packages/beaza_crypto` | Pure Dart: encryption for sync |
| `server` | A Cloudflare Worker with a D1 database: sync, the AI routes and the leaderboard |

All money is kept as whole fils (1 BHD = 1000 fils), and days follow Bahrain
time.

## Accuracy

The rules-only reader (B1) was measured on two sets made by the team:

| Set | Messages | Field precision | Field recall | Exact match |
|---|---|---|---|---|
| Formats (wording of real NBB, KFH and BBK messages, digits made up) | 37 | 1.000 | 1.000 | 100% |
| Seed (real English formats and invented Arabic ones) | 30 | 1.000 | 0.776 | 80% |

The templates were written from the formats set, so its score shows they match
those messages, not how they handle new ones. No messages from other users
were collected, and only one person labelled the sets, so there is no
agreement score. The data and the tool are in
[`packages/beaza_extraction/eval`](packages/beaza_extraction/eval).

## Tests

Every push runs the tests for each package, the server and the app, a
two-phone sync test against the real server code, and builds the APK. Results
are in the [Actions](https://github.com/moodythis/beaza/actions) tab.

## Known limits

- No template reads Arabic; every real transaction alert collected so far is
  in English (ila Bank's Arabic marketing is discarded as promotion). AUB has no template.
- Wallet notifications are not read, only SMS.
- Leaderboard scores are reported by each phone and not checked.
- Sign-up by email does not verify the address.
- The AI runs on Google's free tier, whose terms the project does not control.
