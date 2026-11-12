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
- 6 Arabic or mixed-script messages (`source: synthetic-ar`) use invented
  wording. Every real bank message collected so far is in English and no bank
  has been seen sending Arabic alerts; these show that a message no template
  reads goes to review instead of the budget.

`formats.jsonl` (34 messages) keeps the NBB and KFH formats the templates
were written from: 33 NBB messages the team received from 24 October to
3 November 2026 (card purchases, Fawri+ out and Fawri+ in) and one KFH
Fawri+ message. Every account ending, reference, other party's account digits
and balance in it is made up, and so is the KFH amount; wording, shop names,
amounts and times are as received. The real messages are not kept in the
repository. They showed that NBB prints the previous day's date between 00:00
and 00:59; the label carries the real time, found from the order of the
balances. On this set B1 reads every message exactly and accepts all of them
without review (checked in `test/evaluation_test.dart`).

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
