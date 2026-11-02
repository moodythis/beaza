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
| Tier 1 templates (BisB, ila, Al Salam, BenefitPay) | Done, tests included. ATM and deposit templates need real samples |
| Validator and public ExtractionResult | Done, tests included |
| BeazaExtractor facade (sender filter, whole pipeline) | Written, tests run in CI |
| Deduplicator, own-account registry, merchant normalizer | Next |
| Tier 2 model | Later |
