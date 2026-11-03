# Graph Report - beaza  (2026-11-03)

## Corpus Check
- 138 files · ~66,758 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 24 file(s) not represented in the graph (top: .xml 15, (none) 3, .properties 2)

## Summary
- 2151 nodes · 2992 edges · 105 communities (98 shown, 7 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 23 edges (avg confidence: 0.92)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- DartPad validator copy
- Daily guardrail engine
- Android native intake (Kotlin)
- DartPad Tier 1 copy
- Encrypted database schema
- Sync repository
- Tier 1 bank templates
- CI pipeline
- Sync tests
- DartPad detector copy
- App dependencies
- Validator and result types
- Live two-phone and storage tests
- Account key derivation
- Home view model
- Secure key and account stores
- Language and sender detector
- Server HTTP routes
- Sync API client
- Legal texts and server scripts
- Local stores on AppDatabase
- DartPad classifier copy
- Account repository
- Package entry points and README
- D1 adapter and test harness
- Drift ledger repository
- Test-account workflow
- Account view tests
- Message intake use case
- Sign-up screen
- Guardrail alerts use case
- Account repository tests
- Reconciler (duplicates, transfers)
- Recovery key
- Server test helpers
- Account screen
- Home screen
- Extractor facade
- Syncable interface
- Message classifier
- Record cipher
- Account form widgets
- Message intake tests
- Password key derivation
- Account view model
- Log-in screen
- DartPad normalizer copy
- Smoke-test workflow
- Validator tests
- App entry and background run
- App wiring (BeazaApp)
- Storage bootstrap
- Review screen and alert text
- Request validation and consent
- Android bootstrap workflow
- Drift settings repository
- Ledger repository contract
- SMS source
- Text normalizer
- Amount input dialog
- Money and time formatting
- App widget tests
- Privacy law and legal sync
- Crypto response checker tool
- Envelope (XChaCha20-Poly1305)
- Stateless widgets
- Stateful dialogs and screens
- Bundled legal text
- Crypto tests
- Tier 1 template tests
- Background key work
- Byte helpers
- End-to-end encryption design
- Crypto package manifest
- Server package manifest
- Language controller
- Extraction package tests
- Server TypeScript config
- Review view model
- Recovery key screen
- Home view model tests
- Extraction package manifest
- Encrypted database opener
- Classifier tests
- Guardrail tests
- Server database schema
- App icon set
- Settings repository
- Alert notifier channel
- Drift table definitions
- Sample account tool
- Weak KDF refusal test
- Reconciler tests
- New account tool
- Account and network errors
- App theme
- Recovery key tests
- Server design notes
- Analyzer options
- Extraction roadmap notes
- Day value type

## God Nodes (most connected - your core abstractions)
1. `HttpError` - 16 edges
2. `register()` - 15 edges
3. `with` - 14 edges
4. `handle()` - 14 edges
5. `MainActivity` - 13 edges
6. `AppDatabase` - 13 edges
7. `dependencies` - 13 edges
8. `dispatch()` - 13 edges
9. `login()` - 13 edges
10. `authenticate()` - 12 edges

## Surprising Connections (you probably didn't know these)
- `Status table` --references--> `AppDatabase`  [AMBIGUOUS]
  README.md → app/lib/data/services/database.dart
- `App icon (mipmap-hdpi/ic_launcher.png)` --semantically_similar_to--> `Beaza app icon: gold coin with the letter ب inside a spending gauge`  [INFERRED] [semantically similar]
  app/android/app/src/main/res/mipmap-hdpi/ic_launcher.png → docs/icon/beaza-icon-512.png
- `App icon (mipmap-mdpi/ic_launcher.png)` --semantically_similar_to--> `Beaza app icon: gold coin with the letter ب inside a spending gauge`  [INFERRED] [semantically similar]
  app/android/app/src/main/res/mipmap-mdpi/ic_launcher.png → docs/icon/beaza-icon-512.png
- `App icon (mipmap-xhdpi/ic_launcher.png)` --semantically_similar_to--> `Beaza app icon: gold coin with the letter ب inside a spending gauge`  [INFERRED] [semantically similar]
  app/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png → docs/icon/beaza-icon-512.png
- `App icon (mipmap-xxhdpi/ic_launcher.png)` --semantically_similar_to--> `Beaza app icon: gold coin with the letter ب inside a spending gauge`  [INFERRED] [semantically similar]
  app/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png → docs/icon/beaza-icon-512.png

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Bilingual extraction pipeline** — packages_beaza_extraction_lib_src_normalizer, packages_beaza_extraction_lib_src_detector, packages_beaza_extraction_lib_src_classifier, packages_beaza_extraction_lib_src_tier1, packages_beaza_extraction_lib_src_validator, packages_beaza_extraction_lib_src_extractor, packages_beaza_extraction_lib_src_reconciler [EXTRACTED 1.00]
- **Privacy by design across app, crypto and server** — docs_privacy_compliance_separate_consent, docs_privacy_compliance_right_to_erasure, docs_privacy_compliance_eu_residency, packages_beaza_crypto_readme_server_cannot_read, server_readme_sync_server [INFERRED 0.85]

## Communities (105 total, 7 thin omitted)

### Community 0 - "DartPad validator copy"
Cohesion: 0.03
Nodes (64): accountLast4, acct, amountFils, assemble, card, category, Channel, _channelOf (+56 more)

### Community 1 - "Daily guardrail engine"
Cohesion: 0.03
Nodes (62): addDays, alert, alertCap, AlertDecision, AlertLevel, AlertLog, AlertPlanner, baseLimitFils (+54 more)

### Community 2 - "Android native intake (Kotlin)"
Cohesion: 0.05
Nodes (8): Alerts, Channels, PermissionRequester, MainActivity, StreamHandler, BroadcastReceiver, SmsInbox, SmsReceiver

### Community 3 - "DartPad Tier 1 copy"
Cohesion: 0.04
Nodes (51): accountLast4, amountFils, _amt, _bahrain, bisbCard, bisbIn, bisbOut, bpCredited (+43 more)

### Community 4 - "Encrypted database schema"
Cohesion: 0.04
Nodes (42): alertCap, amountFils, category, channel, confidence, counterpartyLast4, currency, dailyLimitFils (+34 more)

### Community 5 - "Sync repository"
Cohesion: 0.04
Nodes (43): _account, accountChanged, accountPref, _again, _api, _applying, approveMerge, _cipher (+35 more)

### Community 6 - "Tier 1 bank templates"
Cohesion: 0.05
Nodes (37): accountLast4, amountFils, _amt, _bahrain, _build, canonicalRef, channel, _cleanMerchant (+29 more)

### Community 7 - "CI pipeline"
Cohesion: 0.07
Nodes (41): defaults, name, runs-on, steps, name, runs-on, steps, defaults (+33 more)

### Community 8 - "Sync tests"
Cohesion: 0.05
Nodes (37): a, account, addAccount, amounts, b, client, close, _current (+29 more)

### Community 9 - "DartPad detector copy"
Cohesion: 0.05
Nodes (37): _aliases, arabicRatio, arabicThreshold, _buildLookup, _buildPhrases, check, _currencyToken, custom (+29 more)

### Community 10 - "App dependencies"
Cohesion: 0.05
Nodes (36): path, path, dependencies, beaza_crypto, beaza_extraction, crypto, drift, flutter (+28 more)

### Community 11 - "Validator and result types"
Cohesion: 0.05
Nodes (32): amountFils, assemble, category, Channel, _channelOf, confidence, counterpartyLast4, currency (+24 more)

### Community 12 - "Live two-phone and storage tests"
Cohesion: 0.07
Nodes (23): DriftLedgerRepository, DriftSettingsRepository, Syncable, main, account, close, consent, db (+15 more)

### Community 13 - "Account key derivation"
Cohesion: 0.06
Nodes (32): AccountKeys, authKey, bundle, byPassword, byRecovery, _bytes, _context, _copyWith (+24 more)

### Community 14 - "Home view model"
Cohesion: 0.06
Nodes (26): addExpense, arrivalDelay, _arrivals, checkMessages, dispose, _disposed, _duplicates, enableMessages (+18 more)

### Community 15 - "Secure key and account stores"
Cohesion: 0.07
Nodes (28): AccountStore, clear, dataKey, email, MemoryAccountStore, read, saved, SavedAccount (+20 more)

### Community 16 - "Language and sender detector"
Cohesion: 0.06
Nodes (28): _aliases, arabicRatio, arabicThreshold, _buildLookup, _buildPhrases, _currencyToken, defaultAliases, details (+20 more)

### Community 17 - "Server HTTP routes"
Cohesion: 0.20
Nodes (31): accountInfo(), assertNotLimited(), authenticate(), changePassword(), changeRecoveryKey(), createSession(), Ctx, DEFAULT_KDF (+23 more)

### Community 18 - "Sync API client"
Cohesion: 0.06
Nodes (30): activeSessions, adult, _base, _client, code, consentAt, createdAt, deleteAccount (+22 more)

### Community 19 - "Legal texts and server scripts"
Cohesion: 0.08
Nodes (25): consent, s, sample, stored, token, a, body, [url, file] (+17 more)

### Community 20 - "Local stores on AppDatabase"
Cohesion: 0.09
Nodes (23): AlertLogStore, _db, DriftAlertLogStore, load, logs, MemoryAlertLogStore, save, _db (+15 more)

### Community 21 - "DartPad classifier copy"
Cohesion: 0.06
Nodes (30): _amount, _balance, c, check, ClassificationResult, classify, confidence, _declined (+22 more)

### Community 22 - "Account repository"
Cohesion: 0.07
Nodes (28): AccountProblem, AccountRepository, _api, code, current, deleteAccount, _forget, info (+20 more)

### Community 23 - "Package entry points and README"
Cohesion: 0.07
Nodes (10): name, on, pull_request, push, workflow_dispatch, beaza_crypto, beaza_extraction, Beaza (بيزة) project overview (+2 more)

### Community 24 - "D1 adapter and test harness"
Cohesion: 0.08
Nodes (10): env, port, loadPepper(), D1Like, D1Statement, Env, Value, fetch() (+2 more)

### Community 25 - "Drift ledger repository"
Cohesion: 0.07
Nodes (27): _accounts, addExtracted, addManual, applyRemote, collection, countDuplicates, countFromOtherPhones, _db (+19 more)

### Community 26 - "Test-account workflow"
Cohesion: 0.07
Nodes (27): description, required, EMAIL, PUBLIC_KEY, email, public_key, url, jobs (+19 more)

### Community 27 - "Account view tests"
Cohesion: 0.08
Nodes (23): Consent, account, checkbox, _current, deleteAccount, deletedWith, enabled, goBack (+15 more)

### Community 28 - "Message intake use case"
Cohesion: 0.08
Nodes (24): added, arrivals, _extractor, found, hasPermission, IntakeReport, keyFor, _ledger (+16 more)

### Community 29 - "Sign-up screen"
Cohesion: 0.08
Nodes (21): _adult, build, createState, dispose, _email, _form, initState, onChanged (+13 more)

### Community 30 - "Guardrail alerts use case"
Cohesion: 0.09
Nodes (17): InMemoryLedgerRepository, LedgerRepository, AlertPresenter, evaluate, GuardrailAlerts, _ledger, _logs, _present (+9 more)

### Community 31 - "Account repository tests"
Cohesion: 0.08
Nodes (20): bodies, calls, client, consent, _error, failRegisterWith, FakeServer, fast (+12 more)

### Community 32 - "Reconciler (duplicates, transfers)"
Cohesion: 0.08
Nodes (22): _compatible, confirm, _confirmed, countsTowardSpending, duplicateOf, _earlier, EntryRole, index (+14 more)

### Community 33 - "Recovery key"
Cohesion: 0.08
Nodes (21): alphabet, authKey, characters, _checksum, checksumLength, _decode, _encode, format (+13 more)

### Community 34 - "Server test helpers"
Cohesion: 0.21
Nodes (14): handle(), json(), concat(), encoder, randomBytes(), toB64(), Account, newAccountFields() (+6 more)

### Community 35 - "Account screen"
Cohesion: 0.09
Nodes (19): _askMerge, build, _count, createState, _delete, dispose, initState, _loadScheduled (+11 more)

### Community 36 - "Home screen"
Cohesion: 0.09
Nodes (18): account, _addExpense, build, denied, _editLimit, entry, language, levelColor (+10 more)

### Community 37 - "Extractor facade"
Cohesion: 0.09
Nodes (12): BeazaExtractor, _classifier, _normalizer, process, RawMessage, receivedAt, requireKnownSender, sender (+4 more)

### Community 38 - "Syncable interface"
Cohesion: 0.09
Nodes (21): applyRemote, boolField, collection, countFromOtherPhones, doubleField, fields, id, intField (+13 more)

### Community 39 - "Message classifier"
Cohesion: 0.09
Nodes (20): _amount, _anyAmount, _balance, ClassificationResult, classify, confidence, _declined, isTransaction (+12 more)

### Community 40 - "Record cipher"
Cohesion: 0.10
Nodes (17): blob, block, _check, collection, _collectionPattern, _context, create, decrypt (+9 more)

### Community 41 - "Account form widgets"
Cohesion: 0.10
Nodes (17): accountProblemText, autofillHint, build, busyText, controller, createState, document, _emailPattern (+9 more)

### Community 42 - "Message intake tests"
Cohesion: 0.10
Nodes (19): arrivals, arrivalsController, bh, bisbCard, bodiesRead, granted, hasPermission, ilaCard (+11 more)

### Community 43 - "Password key derivation"
Cohesion: 0.10
Nodes (17): authKey, derive, fromJson, hashCode, isAtLeast, iterations, memoryKiB, minimum (+9 more)

### Community 44 - "Account view model"
Cohesion: 0.10
Nodes (16): AccountInfo, _busy, deleteAccount, dispose, _disposed, _failure, forgetFailure, _info (+8 more)

### Community 45 - "Log-in screen"
Cohesion: 0.11
Nodes (15): build, createState, dispose, _email, _forgot, _form, initState, _key (+7 more)

### Community 46 - "DartPad normalizer copy"
Cohesion: 0.10
Nodes (19): bhd, _bhdArabicAfterNumber, _bhdArabicBeforeNumber, _bhdArabicDotted, _bhdArabicWord, _bhdLatin, _bidiMarks, check (+11 more)

### Community 47 - "Smoke-test workflow"
Cohesion: 0.10
Nodes (19): run, url, jobs, smoke, name, on, workflow_dispatch, working-directory (+11 more)

### Community 48 - "Validator tests"
Cohesion: 0.10
Nodes (19): acct, card, check, fromReceipt, main, names, noCur, noDir (+11 more)

### Community 49 - "App entry and background run"
Cohesion: 0.11
Nodes (13): account, appLifecycle, backgroundMain, buildAlerts, buildIntake, done, load, main (+5 more)

### Community 50 - "App wiring (BeazaApp)"
Cohesion: 0.12
Nodes (12): account, _app, build, homeViewModel, language, locale, sync, SyncRepository (+4 more)

### Community 51 - "Storage bootstrap"
Cohesion: 0.11
Nodes (15): alertLogs, background, create, database, db, deviceId, file, key (+7 more)

### Community 52 - "Review screen and alert text"
Cohesion: 0.12
Nodes (13): alertId, alertText, bhd, micro, s, showMicro, status, build (+5 more)

### Community 53 - "Request validation and consent"
Cohesion: 0.18
Nodes (15): checkConsent(), fromB64(), bad(), Bundle, checkB64(), checkBundle(), checkInt(), checkRecords() (+7 more)

### Community 54 - "Android bootstrap workflow"
Cohesion: 0.11
Nodes (17): defaults, runs-on, steps, run, jobs, bootstrap, name, on (+9 more)

### Community 55 - "Drift settings repository"
Cohesion: 0.12
Nodes (15): applyRemote, collection, countFromOtherPhones, _db, load, localCount, markAllPending, markSynced (+7 more)

### Community 56 - "Ledger repository contract"
Cohesion: 0.12
Nodes (14): _accounts, addExtracted, addManual, checkCompleteTransaction, countDuplicates, duplicateGap, entries, manualTemplate (+6 more)

### Community 57 - "SMS source"
Cohesion: 0.12
Nodes (14): arrivals, _events, hasPermission, id, InboxMessage, listInbox, _methods, PlatformSmsSource (+6 more)

### Community 58 - "Text normalizer"
Cohesion: 0.12
Nodes (14): bhd, _bhdArabicAfterNumber, _bhdArabicBeforeNumber, _bhdArabicDotted, _bhdArabicWord, _bhdLatin, _bidiMarks, _diacriticsAndTatweel (+6 more)

### Community 59 - "Amount input dialog"
Cohesion: 0.12
Nodes (13): _amount, AmountInput, build, createState, dispose, fils, initialFils, _invalid (+5 more)

### Community 60 - "Money and time formatting"
Cohesion: 0.12
Nodes (15): abs, _amount, b, fils, formatBahrainTime, formatFils, frac, fracText (+7 more)

### Community 61 - "App widget tests"
Cohesion: 0.12
Nodes (11): bh, limit, load, locale, main, pumpAndSettle, pumpHome, pumpWidget (+3 more)

### Community 62 - "Privacy law and legal sync"
Cohesion: 0.20
Nodes (9): Bahrain PDPL (Law No. 30 of 2018), Before a public release (notify Authority, privacy contact, DPIA, breach plan), EU GDPR (reference standard), Open gaps: data export and email change, Right to erasure (delete account), DART_FILE, dartSource(), sections() (+1 more)

### Community 63 - "Crypto response checker tool"
Cohesion: 0.12
Nodes (15): bundle, _check, expectedKey, _failed, fields, kdf, keys, login (+7 more)

### Community 64 - "Envelope (XChaCha20-Poly1305)"
Cohesion: 0.13
Nodes (10): _aead, Envelope, nonceLength, open, overhead, seal, tagLength, toString (+2 more)

### Community 65 - "Stateless widgets"
Cohesion: 0.14
Nodes (13): BeazaApp, StartupErrorApp, SyncSection, AccountStatus, EmailField, LegalLinks, LegalView, _Agreement (+5 more)

### Community 66 - "Stateful dialogs and screens"
Cohesion: 0.20
Nodes (12): AmountDialog, _AmountDialogState, AccountView, _AccountViewState, _DeleteDialog, _DeleteDialogState, OtherPhonesCard, _OtherPhonesCardState (+4 more)

### Community 67 - "Bundled legal text"
Cohesion: 0.14
Nodes (12): ar, en, LegalDocument, LegalSection, paragraphs, privacyNotice, sections, termsOfUse (+4 more)

### Community 68 - "Crypto tests"
Cohesion: 0.15
Nodes (11): DecryptionFailed, emailAccount, keys, logIn, main, openWithPassword, viaServer, cipher (+3 more)

### Community 69 - "Tier 1 template tests"
Cohesion: 0.14
Nodes (13): bisbCard, bisbIn, bisbOut, bpCredited, bpReceived, check, conf, ex (+5 more)

### Community 70 - "Background key work"
Cohesion: 0.15
Nodes (9): createAccount, derive, forTests, inBackground, KeyWork, minimum, params, setPassword (+1 more)

### Community 71 - "Byte helpers"
Cohesion: 0.15
Nodes (8): diff, fromBase64, out, randomBytes, randomId, sameBytes, _secure, toBase64

### Community 72 - "End-to-end encryption design"
Cohesion: 0.23
Nodes (9): DataKey, PasswordKeys, RecordCipher, RecoveryKey, Data key (32 random bytes), Key bundle (data key locked twice), Password keys (Argon2id then HKDF), Record key (HKDF from data key) (+1 more)

### Community 73 - "Crypto package manifest"
Cohesion: 0.15
Nodes (12): dependencies, crypto, cryptography, description, dev_dependencies, lints, test, environment (+4 more)

### Community 74 - "Server package manifest"
Cohesion: 0.17
Nodes (12): wrangler, description, devDependencies, wrangler@^4.0.0, engines, node, name, private (+4 more)

### Community 75 - "Language controller"
Cohesion: 0.17
Nodes (7): choose, _code, effectiveLanguage, load, locale, prefName, _prefs

### Community 76 - "Extraction package tests"
Cohesion: 0.20
Nodes (7): main, main, run, sum, x, main, n

### Community 77 - "Server TypeScript config"
Cohesion: 0.17
Nodes (11): compilerOptions, allowImportingTsExtensions, erasableSyntaxOnly, lib, module, moduleResolution, noEmit, skipLibCheck (+3 more)

### Community 78 - "Review view model"
Cohesion: 0.20
Nodes (7): MessageIntake, dispose, _disposed, _failed, _intake, _items, load

### Community 79 - "Recovery key screen"
Cohesion: 0.22
Nodes (9): build, _confirm, createState, dispose, _lastGroup, recoveryKey, RecoveryKeyView, _RecoveryKeyViewState (+1 more)

### Community 80 - "Home view model tests"
Cohesion: 0.20
Nodes (7): bh, ledger, main, purchase, settings, settle, vm

### Community 81 - "Extraction package manifest"
Cohesion: 0.20
Nodes (9): description, dev_dependencies, lints, test, environment, sdk, name, publish_to (+1 more)

### Community 82 - "Encrypted database opener"
Cohesion: 0.22
Nodes (5): background, _hexKey, openEncryptedDatabase, openMemoryDatabase, setup

### Community 83 - "Classifier tests"
Cohesion: 0.22
Nodes (8): c, fawri, kindOf, main, none, otp, single, tx

### Community 84 - "Guardrail tests"
Cohesion: 0.22
Nodes (8): bh, g, main, _next, planner, settings, spend, today

### Community 85 - "Server database schema"
Cohesion: 0.33
Nodes (8): attempts, meta, records, records_seq, sessions, sessions_user, users, What the server stores (users, sessions, records, attempts, meta)

### Community 86 - "App icon set"
Cohesion: 0.25
Nodes (8): App icon (mipmap-hdpi/ic_launcher.png), App icon (mipmap-mdpi/ic_launcher.png), App icon (mipmap-xhdpi/ic_launcher.png), App icon (mipmap-xxhdpi/ic_launcher.png), App icon (mipmap-xxxhdpi/ic_launcher.png), Beaza app icon: gold coin with the letter ب inside a spending gauge, App icon (icon/beaza-icon.svg), App icon (icon/beaza-icon-mono.svg)

### Community 87 - "Settings repository"
Cohesion: 0.29
Nodes (6): InMemorySettingsRepository, load, save, _settings, SettingsRepository, GuardrailSettings

### Community 88 - "Alert notifier channel"
Cohesion: 0.29
Nodes (5): AlertNotifier, _channel, PlatformAlertNotifier, requestPermission, show

### Community 89 - "Drift table definitions"
Cohesion: 0.48
Nodes (5): AlertDayRows, LedgerRows, PreferenceRows, SeenMessageRows, SettingsRows

### Community 90 - "Sample account tool"
Cohesion: 0.29
Nodes (5): account, cipher, main, password, record

### Community 91 - "Weak KDF refusal test"
Cohesion: 0.29
Nodes (5): WeakKdfParams, derive, fast, main, salt

### Community 92 - "Reconciler tests"
Cohesion: 0.29
Nodes (6): main, rec, roles, t0, transfer, tx

### Community 93 - "New account tool"
Cohesion: 0.33
Nodes (4): account, email, main, password

### Community 94 - "Account and network errors"
Cohesion: 0.40
Nodes (4): AccountFailure, ApiException, NetworkException, RecoveryKeyException

### Community 96 - "Recovery key tests"
Cohesion: 0.40
Nodes (3): fixed, main, problemOf

### Community 98 - "Analyzer options"
Cohesion: 0.50
Nodes (3): analyzer, exclude, include

### Community 99 - "Extraction roadmap notes"
Cohesion: 0.50
Nodes (3): Merchant normalizer and categorizer (needs data), Extraction pipeline stages (Design 3.1), Tier 2 model (not built)

## Ambiguous Edges - Review These
- `AppDatabase` → `Status table`  [AMBIGUOUS]
  README.md · relation: references

## Knowledge Gaps
- **1322 isolated node(s):** `homeViewModel`, `account`, `sync`, `language`, `locale` (+1317 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1589 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Three separate, unticked consent boxes` connect `Request validation and consent` to `Sign-up screen`, `Privacy law and legal sync`?**
  _High betweenness centrality (0.071) - this node is a cross-community bridge._
- **What connects `homeViewModel`, `account`, `sync` to the rest of the system?**
  _1322 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `DartPad validator copy` be split into smaller, more focused modules?**
  _Cohesion score 0.03076923076923077 - nodes in this community are weakly interconnected._
- **Why does `checkConsent()` connect `Request validation and consent` to `Server HTTP routes`?**
  _High betweenness centrality (0.060) - this node is a cross-community bridge._
- **Should `Daily guardrail engine` be split into smaller, more focused modules?**
  _Cohesion score 0.03076923076923077 - nodes in this community are weakly interconnected._
- **Why does `AppDatabase` connect `Local stores on AppDatabase` to `Encrypted database schema`, `Sync tests`, `Live two-phone and storage tests`, `Storage bootstrap`, `Package entry points and README`, `Drift settings repository`, `Drift ledger repository`?**
  _High betweenness centrality (0.042) - this node is a cross-community bridge._

### Low-confidence Hints
_AMBIGUOUS edges — the extractor was unsure. Verify before acting on these._

- **What is the exact relationship between `AppDatabase` and `Status table`?**
  _Edge tagged AMBIGUOUS (relation: references) - confidence is low._