/// Public entry point of the extraction library.
library;

import 'classifier.dart';
import 'detector.dart';
import 'merchant.dart';
import 'normalizer.dart';
import 'tier1.dart';
import 'validator.dart';

/// One incoming message as the app sees it (SMS or app notification).
class RawMessage {
  const RawMessage({
    required this.text,
    required this.sender,
    required this.receivedAt,
  });

  /// Message body. Never stored or returned by the extractor.
  final String text;

  /// SMS sender ID, or the app name for notifications.
  final String sender;

  /// When the phone received it (UTC).
  final DateTime receivedAt;
}

/// Runs the whole pipeline: sender filter, normalize, classify, Tier 1,
/// validate.
///
/// PRIVACY: with [requireKnownSender] on (the default) a message from a sender
/// that is not a supported bank or wallet is dropped before its text is read.
/// The raw text is never kept: the result carries only extracted fields.
class BeazaExtractor {
  BeazaExtractor({
    this.requireKnownSender = true,
    SenderFamilyDetector? senders,
    Normalizer? normalizer,
    MessageClassifier? classifier,
    Tier1Extractor? tier1,
    Validator? validator,
    MerchantNormalizer? merchants,
  })  : _senders = senders ?? SenderFamilyDetector(),
        _normalizer = normalizer ?? const Normalizer(),
        _classifier = classifier ?? const MessageClassifier(),
        _tier1 = tier1 ?? const Tier1Extractor(),
        _validator = validator ?? const Validator(),
        _merchants = merchants ?? const MerchantNormalizer();

  /// Turn off only for evaluation runs on labelled data.
  final bool requireKnownSender;

  final SenderFamilyDetector _senders;
  final Normalizer _normalizer;
  final MessageClassifier _classifier;
  final Tier1Extractor _tier1;
  final Validator _validator;
  final MerchantNormalizer _merchants;

  ExtractionResult process(RawMessage message) {
    final family = _senders.detect(message.sender);
    if (requireKnownSender && family == SenderFamily.unknown) {
      // Filtered: not a supported sender. kind stays null.
      return const ExtractionResult(status: ExtractionStatus.nonTransaction);
    }

    final text = _normalizer.normalize(message.text);
    final classification = _classifier.classify(text);
    final tier1 = classification.isTransaction
        ? _tier1.extract(
            text,
            family: family,
            receivedAt: message.receivedAt,
          )
        : null;

    final result = _validator.assemble(
      classification: classification,
      tier1: tier1,
      receivedAt: message.receivedAt,
    );
    final shop = _merchants.normalize(result.merchantRaw);
    if (shop == null) return result;
    return result.withMerchant(
        merchantNorm: shop.name, category: shop.category);
  }
}
