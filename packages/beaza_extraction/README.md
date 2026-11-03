# beaza_extraction

Pure Dart extraction core for Beaza. No Flutter dependency, so the app and the
evaluation tool run the same code (NFR-10).

## Run the tests

```
cd packages/beaza_extraction
dart pub get
dart test
```

## Status

| Stage (Design 3.1) | Status |
|---|---|
| Normalize | Done, tests included |
| Detect language and sender family | Done, tests included |
| Classify transaction or not | Done, tests included |
| Tier 1 templates (BisB, ila, Al Salam, NBB, BenefitPay) | Done, tests included. ATM and deposit templates need real samples |
| Validator and public ExtractionResult | Done, tests included |
| BeazaExtractor facade (sender filter, whole pipeline) | Written, tests run in CI |
| Reconciler: duplicates, own accounts, spending total | Done, tests included |
| Daily guardrail (limit, 50/80/100% alerts) | Done, tests included |
| Merchant normalizer and categorizer | First version (alias dictionary and keywords), tests included |
| Evaluation harness (FR-6.2 to 6.4) | Done for B1, see [eval/README.md](eval/README.md) |
| Tier 2 model | Later |
