# beaza_assistant

Beaza's spending assistant, in pure Dart (tested with `dart test`).

It answers three kinds of request, in Gulf Arabic or English:

| Intent | Example | What happens |
|---|---|---|
| `spendingQuery` | «كم صرفت على القهوة هالأسبوع؟», «وين راحت فلوسي هالشهر؟», «جم باقي لي من حدي؟» | Totals, shares and the day's limit are computed on the phone in integer fils |
| `logExpense` | «شريت شاورما بـ 800 فلس وكرك بـ 200 فلس», «دفعت دينار ونص في البرادة» | Draft transactions, shown to the person to confirm; nothing is saved by itself |
| `guardrailAdvice` | «عطني نصيحة» | Short advice from the guardrail level (50/80/100%), small purchases and the week's biggest discretionary category |

## Rules

- **No arithmetic by a model.** Every amount, total and percentage comes from
  `SpendingSummaryBuilder` (integer fils). The reply is written by the rules
  first.
- **The model is optional and only rewords.** With an `AiLlmClient` and the
  person's separate consent (`llmAllowed`), the computed reply and its numbers
  are sent to be reworded. `NumberGuard` rejects any reply with a number that
  was not in what was sent, and the offline reply is used instead. Drafts and
  not-understood requests never go to the model. Errors and timeouts fall back
  to the offline reply.
- **Only computed numbers leave the phone.** `AiContextSanitizer.context`
  holds the intent, the language, the person's question with phone numbers,
  IBANs, e-mail addresses and card or account numbers masked, the metrics, and
  the draft reply. Single transactions, message text, merchant names, last
  four digits and references are never sent. `AiContextSanitizer.entry` (for
  later use) keeps only amount, category, a known chain's name, type and date.
  Names typed by the person cannot be detected reliably, which is one more
  reason the model is opt-in.

## Bahraini money words (`BahrainiMoneyParser`)

| Words | Fils |
|---|---|
| ربية / ربيه | 100 |
| ربيتين | 200 |
| خمس ربيات، نص دينار | 500 |
| دينار وربع | 1250 |
| دينار ونص | 1500 |
| دينارين إلا ربع | 1750 |
| 800 فلس، 2.500 د.ب، BD 2.5، ٢٫٥٠٠ د.ب | 800, 2500, 2500, 2500 |
| 4 دنانير و5 ربيات | 4500 |

A number with no unit ("كرك 200") is guessed (under 100 is dinars, 100 or
more is fils, a decimal is dinars) and marked `guessed`, so the app asks the
person to check it.

## Files

```
lib/src/text.dart        normalise Arabic, tokenise
lib/src/money.dart       BahrainiMoneyParser
lib/src/expense.dart     ExpenseParser -> DraftTransaction
lib/src/analytics.dart   SpendingSummaryBuilder, Period (fils only)
lib/src/intent.dart      IntentDetector (word lists)
lib/src/sanitizer.dart   AiContextSanitizer
lib/src/llm.dart         AiLlmClient, MockLlmClient, NumberGuard
lib/src/assistant.dart   BeazaAiAssistant (offline replies + optional rewording)
lib/src/response.dart    AssistantResponse, DraftTransaction, Metric
```

Not built yet: the chat screen in the app, and a real model client (it would
call Beaza's server, so no API key is on the phone).
