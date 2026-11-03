/// Validator and public result of the extraction pipeline.
library;

import 'classifier.dart';
import 'tier1.dart';

/// Version of the template set. Recorded in every result so that evaluation
/// runs can be reproduced.
const String kTemplateSetVersion = '2026-11-04';

enum ExtractionStatus { transaction, nonTransaction, unparsed }

enum TxnType { purchase, transferOut, transferIn, atmWithdrawal, refund, bill }

enum Channel { card, wallet, transfer, atm }

/// Hard problems: the result cannot be used automatically (status unparsed).
enum ValidationIssue {
  unclassified,
  noTemplate,
  amountMissing,
  amountNotPositive,
  currencyMissing,
  directionUnknown,
  dateInFuture,
  dateTooOld,
}

/// Soft warnings: the result stays a transaction but the user should look.
enum ExtractionFlag { foreignCurrency, timestampFromReceipt, dateMissing }

/// Public result of the extraction pipeline (the library contract).
///
/// Extra fields compared with the minimal contract: [direction] (an account
/// debit has a direction but no known type), [kind] (why a message is not a
/// transaction), [issues] and [flags].
///
/// [amountFils] is only meaningful as BHD when [currency] is 'BHD'. Never add
/// amounts of a flagged foreign currency to a BHD limit.
class ExtractionResult {
  const ExtractionResult({
    required this.status,
    this.kind,
    this.amountFils,
    this.currency,
    this.type,
    this.direction = TxDirection.unknown,
    this.merchantRaw,
    this.merchantNorm,
    this.category,
    this.channel,
    this.last4,
    this.counterpartyLast4,
    this.reference,
    this.timestamp,
    this.confidence = 0.0,
    this.templateVersion = '',
    this.issues = const [],
    this.flags = const [],
  });

  final ExtractionStatus status;
  final MessageKind? kind;
  final int? amountFils;
  final String? currency;
  final TxnType? type;
  final TxDirection direction;
  final String? merchantRaw;

  /// Filled later by the merchant normalizer.
  final String? merchantNorm;

  /// Filled later by the categorizer.
  final String? category;
  final Channel? channel;
  final String? last4;

  /// Last digits of the other party's account. Never a name.
  final String? counterpartyLast4;

  /// Canonical reference, shared by duplicates and by both legs of a
  /// transfer between the user's own accounts.
  final String? reference;

  /// UTC instant.
  final DateTime? timestamp;
  final double confidence;
  final String templateVersion;
  final List<ValidationIssue> issues;
  final List<ExtractionFlag> flags;

  /// True when the user should check it: unusable, or usable with a warning.
  bool get needsReview =>
      status == ExtractionStatus.unparsed || flags.isNotEmpty;

  @override
  String toString() =>
      'ExtractionResult($status, fils: $amountFils, $currency, $type, '
      '$channel, at: $timestamp, conf: $confidence, issues: $issues, '
      'flags: $flags)';
}

/// Joins the classifier and Tier 1 outputs into an [ExtractionResult] and
/// applies the safety checks (Design 3.1, step 5).
class Validator {
  const Validator({
    this.maxAge = const Duration(days: 30),
    this.maxFutureSkew = const Duration(hours: 1),
  });

  /// A transaction time older than this (before the receive time) is rejected.
  final Duration maxAge;

  /// Small clock differences between the bank and the phone are tolerated.
  final Duration maxFutureSkew;

  ExtractionResult assemble({
    required ClassificationResult classification,
    Tier1Result? tier1,
    DateTime? receivedAt,
  }) {
    if (classification.kind == MessageKind.unknown) {
      // From a bank sender but not recognised: review it, do not drop it.
      return const ExtractionResult(
        status: ExtractionStatus.unparsed,
        kind: MessageKind.unknown,
        issues: [ValidationIssue.unclassified],
      );
    }
    if (!classification.isTransaction) {
      return ExtractionResult(
        status: ExtractionStatus.nonTransaction,
        kind: classification.kind,
        confidence: classification.confidence,
      );
    }
    if (tier1 == null) {
      return const ExtractionResult(
        status: ExtractionStatus.unparsed,
        kind: MessageKind.transaction,
        issues: [ValidationIssue.noTemplate],
      );
    }

    final issues = <ValidationIssue>[];
    final flags = <ExtractionFlag>[];

    final amount = tier1.amountFils;
    if (amount == null) {
      issues.add(ValidationIssue.amountMissing);
    } else if (amount <= 0) {
      issues.add(ValidationIssue.amountNotPositive);
    }

    final currency = tier1.currency.trim().toUpperCase();
    if (currency.isEmpty) {
      issues.add(ValidationIssue.currencyMissing);
    } else if (currency != 'BHD') {
      flags.add(ExtractionFlag.foreignCurrency);
    }

    final type = _typeOf(tier1);
    if (type == null && tier1.direction == TxDirection.unknown) {
      issues.add(ValidationIssue.directionUnknown);
    }

    var timestamp = tier1.occurredAt;
    final received = receivedAt?.toUtc();
    if (timestamp != null) {
      if (received != null) {
        if (timestamp.isAfter(received.add(maxFutureSkew))) {
          issues.add(ValidationIssue.dateInFuture);
        } else if (timestamp.isBefore(received.subtract(maxAge))) {
          issues.add(ValidationIssue.dateTooOld);
        }
      }
    } else if (received != null) {
      timestamp = received;
      flags.add(ExtractionFlag.timestampFromReceipt);
    } else {
      flags.add(ExtractionFlag.dateMissing);
    }

    return ExtractionResult(
      status: issues.isEmpty
          ? ExtractionStatus.transaction
          : ExtractionStatus.unparsed,
      kind: MessageKind.transaction,
      amountFils: amount,
      currency: currency.isEmpty ? null : currency,
      type: type,
      direction: tier1.direction,
      merchantRaw: tier1.merchant,
      channel: _channelOf(tier1.channel),
      last4: tier1.accountLast4,
      counterpartyLast4: tier1.counterpartyLast4,
      reference: tier1.reference,
      timestamp: timestamp,
      confidence: tier1.confidence,
      templateVersion: '${tier1.templateId}@$kTemplateSetVersion',
      issues: issues,
      flags: flags,
    );
  }

  static TxnType? _typeOf(Tier1Result t) {
    if (t.channel == TxChannel.card && t.direction == TxDirection.outgoing) {
      return TxnType.purchase;
    }
    if (t.channel == TxChannel.fawri) {
      if (t.direction == TxDirection.outgoing) return TxnType.transferOut;
      if (t.direction == TxDirection.incoming) return TxnType.transferIn;
    }
    // Account debits and credits do not say what they were: type stays null.
    return null;
  }

  static Channel? _channelOf(TxChannel c) {
    switch (c) {
      case TxChannel.card:
        return Channel.card;
      case TxChannel.fawri:
        return Channel.transfer;
      case TxChannel.account:
        return null;
    }
  }
}
