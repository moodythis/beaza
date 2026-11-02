import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/seen_message_store.dart';
import 'package:beaza/data/services/sms_source.dart';
import 'package:beaza_extraction/beaza_extraction.dart';

/// What one scan did. Counts only, nothing about the messages themselves.
class IntakeReport {
  const IntakeReport({
    this.added = 0,
    this.notTransactions = 0,
    this.notUnderstood = 0,
  });

  /// New transactions stored.
  final int added;

  /// Bank messages that are not spending (OTP, promotion, declined...).
  final int notTransactions;

  /// Bank messages that look like transactions but could not be read
  /// safely. Kept unread until the review screen exists.
  final int notUnderstood;

  /// Bank messages handled in this scan, of any kind.
  int get found => added + notTransactions + notUnderstood;
}

/// A bank message the pipeline could not read safely, shown to the user on
/// the review screen. Held in memory only; never stored.
class UnreadMessage {
  const UnreadMessage({
    required this.sender,
    required this.receivedAt,
    required this.text,
    required this.reasons,
  });

  final String sender;
  final DateTime receivedAt;
  final String text;

  /// ValidationIssue names, for example "noTemplate".
  final List<String> reasons;
}

/// Reads new bank SMS from the inbox and stores the transactions found.
///
/// Privacy order: list (id, sender, date only) -> drop every sender that is
/// not a known bank -> drop ids already handled -> only then read bodies ->
/// extract -> keep the extracted fields, discard the text.
class MessageIntake {
  MessageIntake({
    required SmsSource sms,
    required LedgerRepository ledger,
    required SeenMessageStore seen,
    BeazaExtractor? extractor,
    SenderFamilyDetector? senders,
    DateTime Function()? clock,
    this.window = const Duration(days: 30),
  })  : _sms = sms,
        _ledger = ledger,
        _seen = seen,
        _extractor = extractor ?? BeazaExtractor(),
        _senders = senders ?? SenderFamilyDetector(),
        _clock = clock ?? DateTime.now;

  final SmsSource _sms;
  final LedgerRepository _ledger;
  final SeenMessageStore _seen;
  final BeazaExtractor _extractor;
  final SenderFamilyDetector _senders;
  final DateTime Function() _clock;

  /// How far back to look. Matches the validator's maximum message age.
  final Duration window;

  Future<IntakeReport>? _running;

  Future<bool> hasPermission() => _sms.hasPermission();

  Future<bool> requestPermission() => _sms.requestPermission();

  Stream<void> get arrivals => _sms.arrivals;

  static String keyFor(InboxMessage m) => 'sms:${m.id}';

  /// Safe to call often: overlapping calls share one scan.
  Future<IntakeReport> scan() =>
      _running ??= _scan().whenComplete(() => _running = null);

  /// The bank messages still not understood, newest first, read live from
  /// the inbox for the review screen. Nothing is stored.
  Future<List<UnreadMessage>> unreadable() async {
    final now = _clock();
    final listed = await _sms.listInbox(since: now.subtract(window));
    final wanted = <InboxMessage>[];
    for (final m in listed) {
      if (_senders.detect(m.sender) == SenderFamily.unknown) continue;
      if (await _seen.contains(keyFor(m))) continue;
      wanted.add(m);
    }
    if (wanted.isEmpty) return const [];
    final bodies = await _sms.readBodies([for (final m in wanted) m.id]);
    final out = <UnreadMessage>[];
    for (final m in wanted) {
      final text = bodies[m.id];
      if (text == null) continue;
      final r = _extractor.process(
        RawMessage(text: text, sender: m.sender, receivedAt: m.receivedAt),
      );
      if (r.status != ExtractionStatus.unparsed) continue;
      out.add(UnreadMessage(
        sender: m.sender,
        receivedAt: m.receivedAt,
        text: text,
        reasons: [for (final i in r.issues) i.name],
      ));
    }
    out.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    return out;
  }

  /// For a run started by a new SMS: the SMS app saves the message to the
  /// inbox a moment after Android announces it, so scan again a few times
  /// until a bank message shows up (or give up; a non-bank SMS never will).
  Future<IntakeReport> scanUntilFound({
    int attempts = 4,
    Duration pause = const Duration(milliseconds: 1500),
  }) async {
    var report = const IntakeReport();
    for (var i = 0; i < attempts; i++) {
      report = await scan();
      if (report.found > 0) return report;
      if (i < attempts - 1) await Future<void>.delayed(pause);
    }
    return report;
  }

  Future<IntakeReport> _scan() async {
    final now = _clock();
    final listed = await _sms.listInbox(since: now.subtract(window));

    final wanted = <InboxMessage>[];
    for (final m in listed) {
      if (_senders.detect(m.sender) == SenderFamily.unknown) continue;
      if (await _seen.contains(keyFor(m))) continue;
      wanted.add(m);
    }

    var added = 0;
    var other = 0;
    var unclear = 0;
    if (wanted.isNotEmpty) {
      final bodies = await _sms.readBodies([for (final m in wanted) m.id]);
      for (final m in wanted) {
        final text = bodies[m.id];
        if (text == null) continue;
        final result = _extractor.process(
          RawMessage(text: text, sender: m.sender, receivedAt: m.receivedAt),
        );
        switch (result.status) {
          case ExtractionStatus.transaction:
            await _ledger.addExtracted(result);
            await _seen.add(keyFor(m), now);
            added++;
          case ExtractionStatus.nonTransaction:
            await _seen.add(keyFor(m), now);
            other++;
          case ExtractionStatus.unparsed:
            unclear++;
        }
      }
    }

    await _seen.pruneBefore(now.subtract(window + const Duration(days: 1)));
    return IntakeReport(
      added: added,
      notTransactions: other,
      notUnderstood: unclear,
    );
  }
}
