# Gold label schema and annotation guide (SRS FR-6.2)

A gold file is JSONL: one JSON object per line. Blank lines and lines that
start with `//` are skipped. Ids must be unique within a file.

```json
{"id": "v-0001", "sender": "BisB", "received_at": "2026-10-15T13:40:00Z",
 "text": "Dear CLIENT, thank you for using your Debit card 7744 for BHD 0.300 at SAMPLE BAKERY on 15/10 @16:31 ...",
 "source": "volunteer", "annotator": "A1",
 "label": {"is_transaction": true, "amount_fils": 300, "currency": "BHD",
           "direction": "outgoing", "type": "purchase",
           "merchant": "SAMPLE BAKERY", "last4": "7744",
           "time": "2026-10-15T13:31:00Z"}}
```

## Message fields

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Unique id. Use the same id in both annotators' files. |
| `sender` | yes | SMS sender id or app name, as the phone shows it. |
| `received_at` | yes | When the phone received it, ISO 8601 in UTC (Bahrain time minus 3 hours). |
| `text` | yes | The message after masking (below). |
| `source` | no | `seed`, `synthetic-ar`, `volunteer`, `team`. |
| `annotator` | no | Annotator code, for example `A1`. |
| `label` | yes | The gold label. |

## Label fields

Leave a field out (or `null`) when the message does not say it. Do not guess
from other messages, except `last4` and `direction` as explained below.

| Field | Values | Rule |
|---|---|---|
| `is_transaction` | true / false | True when money moved: purchase, transfer, deposit, withdrawal, refund, fee. False for OTP, declined, promotion, balance, statement, notices. A non-transaction has no other fields. |
| `amount_fils` | integer | Amount in fils: BHD 1.500 is 1500. A foreign amount keeps its own 3-decimal scale: USD 22.00 is 22000. |
| `currency` | ISO code | `BD` and `د.ب` are `BHD`. |
| `direction` | `outgoing` / `incoming` | From the user's point of view. When the text is unclear, use the account numbers: money to one of the user's accounts is incoming. |
| `type` | `purchase`, `transferOut`, `transferIn`, `atmWithdrawal`, `refund`, `bill` | Only when the message says what it was. A plain "account debited" has no type. |
| `merchant` | text | Copied as written (not cleaned up). Only for card or wallet purchases. |
| `merchant_norm` | text | The shop's short name. A chain gets its brand name ("Day To Day"). Any other shop gets the printed name without the city, store or branch codes and legal suffix (WLL, CO), in Title Case. Do not complete cut-off words. |
| `category` | `food`, `groceries`, `shopping`, `transport`, `bills`, `health`, `entertainment`, `education`, `other` | The annotator's judgement. Leave out when the shop cannot be told from its name. |
| `last4` | 4 digits | The user's own card or account. Not the other party's. |
| `time` | ISO 8601 UTC | The time written in the message, converted from Bahrain time. Leave out when the message has no time (a date alone is not enough). If the printed date is provably wrong (for example the balances show the order), label the real time. |

## Masking (FR-6.1)

The one team member who receives a volunteer's messages masks them within 24
hours and then deletes the originals (the consent form promises this).
Replace, with made-up values of the same shape:

- personal names with `[NAME]`
- phone numbers of people with `[PHONE]` (bank hotline numbers may stay)
- account numbers, card numbers and IBANs: keep the shape, make up every
  digit. Use one made-up last-4 per real account of a volunteer, the same in
  all of that volunteer's messages, so `last4` can still be checked
- reference numbers: keep the bank's prefix and the date part, make up the rest
- balances: made-up amounts

Keep amounts, dates, times, merchant names and the bank's wording exactly as
they are, because those are what is being measured. Masked messages are kept
in a private folder, never in this repository. `eval/formats.jsonl` shows the
result on the team's own messages.

## Two annotators

Each annotator labels the same ids in a separate file without looking at the
other's. Then run:

```
dart run bin/evaluate.dart --agreement gold_A1.jsonl gold_A2.jsonl
```

The report gives Cohen's kappa for transaction or not, agreement per field
and a list of disagreements. The two annotators settle each disagreement and
the settled labels become the gold file.
