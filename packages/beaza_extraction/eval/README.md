# Evaluation harness (SRS FR-6.2 to FR-6.4, NFR-5, NFR-10)

Scores an extraction system against gold labels and writes `report.md` and
`results.json`.

```
cd packages/beaza_extraction
dart run bin/evaluate.dart --data eval/seed.jsonl
```

CI runs this on every push and shows the report on the run's summary page.

## Data

`seed.jsonl` (30 messages) is a development set, **not** the evaluation set
for the report:

- 24 English messages (`source: seed`) follow real Bahraini formats from
  BisB, ila, Al Salam and BenefitPay. Names, balances and numbers are
  invented.
- 6 Arabic messages (`source: synthetic-ar`) use invented wording, because no
  real Arabic bank samples have been collected yet. They show what happens
  to Arabic messages today.

The held-out evaluation set will be real, consented, masked messages labelled
by two annotators (SRS section 8). Label format: [SCHEMA.md](SCHEMA.md).

## Metrics

| Metric | Meaning |
|---|---|
| Transaction F1 | Transaction or not. A message the system flags as a transaction but cannot read still counts as detected. |
| Field precision, recall, F1 | Per field: amount, currency, direction, type, merchant, last4, time. A wrong value counts as one false positive and one false negative. Spacing and letter case are ignored; time is compared to the minute. |
| Amount exact | Share of gold transactions with amount and currency both right (NFR-5 target 98%). |
| Message exact | Share of messages with the decision and every field right. |
| Accepted without review | Share of gold transactions the app would count at once, without asking the user. |

Results are also given by sender family and by language.

A time the app copies from the receive time is not counted as a predicted
time.

## Splits (NFR-10)

| `--split` | Test part |
|---|---|
| `all` (default) | Every message |
| `random` | Fixed by message id and `--seed` (default 42), `--test-fraction` (default 0.3) |
| `time` | The latest messages by receive time |
| `template` | Senders in `--holdout`, for example `--holdout ila,bisb`: formats unseen in development |

The report header records the data file's fingerprint, the split, the
template set version and the exact command.

## Systems (FR-6.4)

| Id | System | Status |
|---|---|---|
| B1 | Rules only (Tier 1 templates) | Built |
| B2 | LLM only | Needs the Tier 2 model |
| B3 | Hybrid: Tier 1, then Tier 2 | Needs the Tier 2 model |
