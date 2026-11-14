# Spending chatbot (Gemini), design

Status: approved by the author on 14 Nov 2026 ("approach A", implement now).

## Intent

The "Ask" screen answers questions about the person's own spending by rules
on the phone. The author wants a chatbot: Gemini gets a fixed prompt, answers
anything about the person's spending, budget, daily limit and saving, and
refuses everything else. Answers must stay correct: Beaza's rule is that the
model explains numbers and never computes them.

## Goals

- Natural answers to spending questions the rules cannot parse ("why was this
  week more than last week?", "where do I waste money?").
- Off-topic questions are refused, in the person's language, and never reach
  Gemini when the phone can tell.
- Every number in an answer was computed on the phone and sent in the summary.
- Optional, behind its own consent that lists exactly what is sent; withdrawing
  it returns the screen to the rules-only behaviour.
- Works when Gemini is off, busy or over quota: the rules answer is shown.

## Non-goals

- No free conversation about anything else, no memory between sessions, no
  stored chats (server or phone), no tool use, no actions (adding expenses
  stays with the rules and the confirm button).
- No raw bank messages, no single transaction text, no account or card digits.

## Approaches considered

A. **Phone filter + computed summary + number guard (chosen).** The phone's
   scope rules turn off-topic questions away first. For the rest, the phone
   sends the question and a summary computed in integer fils; the server asks
   Gemini with the fixed prompt and drops any reply with a number not in the
   summary. Cost: cannot answer what the summary does not contain.
B. Prompt alone decides, every question goes to Gemini. Simpler, but anyone can
   talk the model into other topics, every question leaves the phone, and the
   numbers are not guaranteed.
C. Rules for numbers, Gemini for advice only. Most exact, but feels like two
   tools.

## Design (A)

Phone (`AskViewModel`):
1. `answerLocally` runs first (always).
2. `outOfScope` and `logExpense` stop here: never sent.
3. Otherwise, if the person agreed to chat and the server is reachable, send
   `chatRequest(...)`: question and previous question (digits runs masked), the
   coach summary (week totals, categories, shops, last purchases, limit), plus
   periods (today, yesterday, week, last week, month, last month: total and
   count), month categories and shops, today's spent/limit, and the numbers the
   rules computed for this question (`metrics`: key and display text only).
4. Show the reply; mark it as Gemini's. If there is no reply (consent off,
   network, busy, number guard, refusal) show the local reply; a refusal shows
   the scope message.

Server (`POST /v1/chat`, `server/src/chat.ts`):
- Strict field validation (reuses the coach validators), own consent version.
- Facts text is built on the server from the numbers (the model never sees raw
  JSON).
- Fixed system prompt (in code, not from the phone). The question sits inside
  `<question>` tags and is declared data, not instructions.
- The model answers or replies exactly `out_of_scope`.
- Reply is kept only if: not a refusal; at most 500 characters; no link, code
  fence or markdown list; every number is in the facts, the metrics or the
  question. Otherwise `answer: null` with a reason.
- Limits: the per-caller AI share (shared with the other AI calls) and its own
  daily cap (`CHAT_DAILY_CAP`), counted apart from the savings plan so chat
  cannot use up the plan's allowance. Nothing stored except counters.

Privacy: the privacy notice (server/src/legal.ts, then the generated Dart
copy) names the chat in the "Which AI models" and AI-consent sections; the
privacy version is bumped. The consent sheet shows the exact lines sent.

## Known limits (to state in the report)

- A caller who skips the app and posts straight to the server could try to
  steer Gemini off topic. The prompt, the output checks, the per-caller limit
  and the daily cap bound that; they do not make it impossible.
- Questions needing a number outside the summary get "I can't see that".
- The number guard allows a reply that repeats a given number in a
  wrong sense ("BHD 3.200 is your limit" when it is the spending). Metrics
  carry keys to reduce this; it is not eliminated.

- The phone judges "about spending" by words (a money word, a category with a
  period, an amount). A question such as "price of gold?" has a money word and
  is sent; Gemini is then asked to refuse it. The consent text says so.
- Review by a second model (14 Nov) found and fixed: unclear text with no money
  word was being sent; transfers sorted into a category leaked the recipient as
  a shop; `</question>` in a question; free text in a metric's display; the
  number guard rejecting "BHD 25" and "800 fils"; replies with no number, shop
  or spending word are dropped (a poem, a general-knowledge answer); chat has its
  own per-caller share. Not fixed on purpose: a cash expense typed inside a
  spending question is sent with the question (the person typed it as part of
  it, and the consent says the question is sent).

## Left to the builder

Wording of the consent text, example chips, exact fact lines.
