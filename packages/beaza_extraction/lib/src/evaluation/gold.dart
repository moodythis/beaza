/// Gold-labelled messages for the evaluation harness (SRS FR-6.2, FR-6.3).
///
/// One message per line in a JSONL file. The schema is described in
/// `eval/SCHEMA.md`. Text in a gold file must already be masked (FR-6.1).
library;

import 'dart:convert';

import '../merchant.dart' show kCategories;

/// What a human annotator says is true about one message.
class GoldLabel {
  const GoldLabel({
    required this.isTransaction,
    this.amountFils,
    this.currency,
    this.direction,
    this.type,
    this.merchant,
    this.merchantNorm,
    this.category,
    this.last4,
    this.time,
  });

  final bool isTransaction;
  final int? amountFils;
  final String? currency;

  /// 'outgoing' or 'incoming' (names of TxDirection).
  final String? direction;

  /// A TxnType name, or null when the message does not say.
  final String? type;
  final String? merchant;

  /// Short display name of the shop, as a person would write it.
  final String? merchantNorm;

  /// One of kCategories.
  final String? category;
  final String? last4;

  /// UTC time written in the message, or null when it has none.
  final DateTime? time;

  static const directions = {'outgoing', 'incoming'};
  static const types = {
    'purchase',
    'transferOut',
    'transferIn',
    'atmWithdrawal',
    'refund',
    'bill',
  };

  factory GoldLabel.fromJson(Map<String, dynamic> j, {String where = ''}) {
    final isTx = j['is_transaction'];
    if (isTx is! bool) {
      throw FormatException('$where: label.is_transaction must be true or false');
    }
    final amount = j['amount_fils'];
    if (amount != null && amount is! int) {
      throw FormatException('$where: label.amount_fils must be an integer (fils)');
    }
    final direction = j['direction'] as String?;
    if (direction != null && !directions.contains(direction)) {
      throw FormatException('$where: label.direction "$direction" is not one of $directions');
    }
    final type = j['type'] as String?;
    if (type != null && !types.contains(type)) {
      throw FormatException('$where: label.type "$type" is not one of $types');
    }
    final timeRaw = j['time'] as String?;
    final time = timeRaw == null ? null : DateTime.tryParse(timeRaw)?.toUtc();
    if (timeRaw != null && time == null) {
      throw FormatException('$where: label.time "$timeRaw" is not an ISO 8601 time');
    }
    final label = GoldLabel(
      isTransaction: isTx,
      amountFils: amount as int?,
      currency: (j['currency'] as String?)?.toUpperCase(),
      direction: direction,
      type: type,
      merchant: j['merchant'] as String?,
      merchantNorm: j['merchant_norm'] as String?,
      category: j['category'] as String?,
      last4: j['last4'] as String?,
      time: time,
    );
    if (label.category != null && !kCategories.contains(label.category)) {
      throw FormatException(
          '$where: label.category "${label.category}" is not one of $kCategories');
    }
    if (!isTx && label.hasAnyField) {
      throw FormatException('$where: a non-transaction must not have transaction fields');
    }
    return label;
  }

  bool get hasAnyField =>
      amountFils != null ||
      currency != null ||
      direction != null ||
      type != null ||
      merchant != null ||
      merchantNorm != null ||
      category != null ||
      last4 != null ||
      time != null;

  Map<String, dynamic> toJson() => {
        'is_transaction': isTransaction,
        if (amountFils != null) 'amount_fils': amountFils,
        if (currency != null) 'currency': currency,
        if (direction != null) 'direction': direction,
        if (type != null) 'type': type,
        if (merchant != null) 'merchant': merchant,
        if (merchantNorm != null) 'merchant_norm': merchantNorm,
        if (category != null) 'category': category,
        if (last4 != null) 'last4': last4,
        if (time != null) 'time': time!.toIso8601String(),
      };
}

/// One labelled message.
class GoldMessage {
  const GoldMessage({
    required this.id,
    required this.sender,
    required this.receivedAt,
    required this.text,
    required this.label,
    this.source = '',
    this.annotator = '',
  });

  final String id;
  final String sender;
  final DateTime receivedAt;

  /// Masked message text.
  final String text;
  final GoldLabel label;

  /// Where the sample came from, e.g. 'seed', 'synthetic-ar', 'volunteer'.
  final String source;
  final String annotator;

  factory GoldMessage.fromJson(Map<String, dynamic> j, {String where = ''}) {
    String need(String key) {
      final v = j[key];
      if (v is! String || v.isEmpty) {
        throw FormatException('$where: "$key" is required');
      }
      return v;
    }

    final id = need('id');
    final at = DateTime.tryParse(need('received_at'));
    if (at == null) {
      throw FormatException('$where: received_at is not an ISO 8601 time');
    }
    final label = j['label'];
    if (label is! Map<String, dynamic>) {
      throw FormatException('$where ($id): "label" is required');
    }
    return GoldMessage(
      id: id,
      sender: need('sender'),
      receivedAt: at.toUtc(),
      text: need('text'),
      label: GoldLabel.fromJson(label, where: '$where ($id)'),
      source: (j['source'] as String?) ?? '',
      annotator: (j['annotator'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sender': sender,
        'received_at': receivedAt.toIso8601String(),
        'text': text,
        if (source.isNotEmpty) 'source': source,
        if (annotator.isNotEmpty) 'annotator': annotator,
        'label': label.toJson(),
      };
}

/// Reads a JSONL gold file. Blank lines and lines starting with // are
/// skipped. Duplicate ids are an error.
List<GoldMessage> parseGold(String content, {String name = 'gold'}) {
  final out = <GoldMessage>[];
  final seen = <String>{};
  final lines = const LineSplitter().convert(content);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty || line.startsWith('//')) continue;
    final where = '$name:${i + 1}';
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException catch (e) {
      throw FormatException('$where: not valid JSON (${e.message})');
    }
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('$where: each line must be a JSON object');
    }
    final m = GoldMessage.fromJson(decoded, where: where);
    if (!seen.add(m.id)) {
      throw FormatException('$where: duplicate id "${m.id}"');
    }
    out.add(m);
  }
  return out;
}

/// 32-bit FNV-1a over UTF-8 bytes, as 8 hex digits. Used for reproducible
/// splits and to fingerprint a data file in a report (NFR-10).
String fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final b in utf8.encode(s)) {
    h ^= b;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}
