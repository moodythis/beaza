import 'dart:async';

import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/seen_message_store.dart';
import 'package:beaza/data/services/sms_source.dart';
import 'package:beaza/domain/use_cases/message_intake.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter_test/flutter_test.dart';

/// Formats follow real Bahraini bank messages; all values are invented.
const bisbCard =
    'Dear CLIENT, thank you for using your Debit card 7744 for BHD 0.300 at SAMPLE BAKERY - MAL BAH BH-000001 on 02/11 @16:31. Avail Bal BHD 9.999. Tel 17515151';
const ilaCard =
    'Success! Purchase at SAMPLE TRADING CO W using card ****8855 for BHD 1.500 on 02/11/2026 15:42 debited from BHD Ac Balance BHD 9.999 Enquiry 17123456';
/// A bank format with no template yet (invented values).
const unknownFormat =
    'Dear Client, your account was debited with BHD 3.000 for service charges on 02/11/2026.';
const otp = 'Your OTP is 123456. Do not share it with anyone.';
const personal = 'Hi, are we still meeting at 5? I owe you BHD 3.000';

class FakeSms implements SmsSource {
  FakeSms(this.inbox);

  final List<(String id, String sender, DateTime at, String body)> inbox;
  final List<String> bodiesRead = [];
  bool granted = true;
  final arrivalsController = StreamController<void>.broadcast();

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<List<InboxMessage>> listInbox({required DateTime since}) async => [
        for (final m in inbox)
          if (m.$3.isAfter(since))
            InboxMessage(id: m.$1, sender: m.$2, receivedAt: m.$3),
      ];

  @override
  Future<Map<String, String>> readBodies(List<String> ids) async {
    bodiesRead.addAll(ids);
    return {
      for (final m in inbox)
        if (ids.contains(m.$1)) m.$1: m.$4,
    };
  }

  @override
  Stream<void> get arrivals => arrivalsController.stream;
}

class MessageIntakeTestHelper {
  static ExtractionResult extract(FakeSms sms, String id) {
    final m = sms.inbox.firstWhere((m) => m.$1 == id);
    return BeazaExtractor().process(
        RawMessage(text: m.$4, sender: m.$2, receivedAt: m.$3));
  }
}

DateTime bh(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 11, day, hour, minute).subtract(kBahrainOffset);

void main() {
  late FakeSms sms;
  late InMemoryLedgerRepository ledger;
  late MemorySeenMessageStore seen;
  late MessageIntake intake;

  setUp(() {
    sms = FakeSms([
      ('1', 'BisB', bh(2, 16, 32), bisbCard),
      ('2', 'ilabank', bh(2, 15, 43), ilaCard),
      ('3', 'BisB', bh(2, 17), otp),
      ('4', '+97333000000', bh(2, 18), personal),
      ('5', 'ilabank', DateTime.utc(2026, 9, 1), ilaCard), // too old
    ]);
    ledger = InMemoryLedgerRepository();
    seen = MemorySeenMessageStore();
    intake = MessageIntake(
      sms: sms,
      ledger: ledger,
      seen: seen,
      clock: () => bh(2, 20),
    );
  });

  test('stores bank transactions and skips the rest', () async {
    final report = await intake.scan();
    expect(report.added, 2);
    expect(report.notTransactions, 1);
    expect(report.notUnderstood, 0);

    final amounts = (await ledger.entries()).map((e) => e.result.amountFils);
    expect(amounts, unorderedEquals([300, 1500]));
  });

  test('never reads the text of an unknown sender', () async {
    await intake.scan();
    expect(sms.bodiesRead, isNot(contains('4')));
    expect(sms.bodiesRead, unorderedEquals(['1', '2', '3']));
  });

  test('messages older than the window are not even listed', () async {
    await intake.scan();
    expect(sms.bodiesRead, isNot(contains('5')));
  });

  test('a second scan adds nothing and reads no bodies', () async {
    await intake.scan();
    sms.bodiesRead.clear();
    final again = await intake.scan();
    expect(again.added, 0);
    expect(sms.bodiesRead, isEmpty);
    expect(await ledger.entries(), hasLength(2));
  });

  test('reading the same messages again after the seen list is lost adds '
      'nothing (data cleared and restored from an account)', () async {
    await intake.scan();
    // The seen list is local and is lost with the data; the ledger is not
    // (it came back from the account), and the inbox still has the SMS.
    final restored = MessageIntake(
      sms: sms,
      ledger: ledger,
      seen: MemorySeenMessageStore(),
      clock: () => bh(2, 20),
    );
    await restored.scan();
    expect(await ledger.entries(), hasLength(2));
  });

  test('a new template set reads messages an older one dropped', () async {
    // An older version saw message 6 and called it not a transaction.
    sms.inbox.add(('6', 'NBB', bh(2, 19),
        'Thank you for using NBB Debit Card at SAMPLE SHOP MANAMA for BHD2.050 on 02/11/2026 18:59, A/C ending 4810 balance BHD99.999.'));
    for (final id in ['1', '2', '3', '6']) {
      await seen.add('sms:$id', bh(2, 19, 30));
    }
    await seen.add('templates:old', bh(2, 19, 30));
    await ledger.addExtracted(
        MessageIntakeTestHelper.extract(sms, '1'),
        messageKey: 'sms:1');

    final report = await intake.scan();
    expect(sms.bodiesRead, containsAll(['1', '6']));
    final amounts = (await ledger.entries()).map((e) => e.result.amountFils);
    expect(amounts, unorderedEquals([300, 1500, 2050]));
    // Only the messages this scan saw for the first time are counted.
    expect(report.added, 0);
    expect(await seen.contains(MessageIntake.templateMarker), isTrue);

    sms.bodiesRead.clear();
    await intake.scan();
    expect(sms.bodiesRead, isEmpty);
  });

  test('overlapping scans share one run', () async {
    final a = intake.scan();
    final b = intake.scan();
    expect(identical(a, b), isTrue);
    await a;
    expect(await ledger.entries(), hasLength(2));
  });

  test('stored results carry no message text', () async {
    await intake.scan();
    for (final e in await ledger.entries()) {
      expect(e.result.toString(), isNot(contains('Avail Bal')));
      expect(e.result.toString(), isNot(contains('9.999')));
    }
  });

  group('run started by a new SMS', () {
    test('waits for the message to reach the inbox', () async {
      final late = FakeSms([]);
      final lateIntake = MessageIntake(
        sms: late,
        ledger: ledger,
        seen: seen,
        clock: () => bh(2, 20),
      );
      // The SMS app saves the message only after the first scan.
      Future<void>.delayed(const Duration(milliseconds: 5),
          () => late.inbox.add(('9', 'BisB', bh(2, 16, 32), bisbCard)));

      final r = await lateIntake.scanUntilFound(
          pause: const Duration(milliseconds: 20));
      expect(r.added, 1);
      expect(await ledger.entries(), hasLength(1));
    });

    test('a personal SMS gives up after the last attempt', () async {
      final only = FakeSms([('4', '+97333000000', bh(2, 18), personal)]);
      final r = await MessageIntake(
        sms: only,
        ledger: ledger,
        seen: seen,
        clock: () => bh(2, 20),
      ).scanUntilFound(attempts: 3, pause: Duration.zero);
      expect(r.found, 0);
      expect(only.bodiesRead, isEmpty);
    });
  });

  group('review screen source', () {
    test('lists only bank messages that were not understood, with reasons',
        () async {
      sms.inbox.add(('7', 'BisB', bh(2, 19), unknownFormat));
      final report = await intake.scan();
      expect(report.notUnderstood, 1);

      final unread = await intake.unreadable();
      expect(unread, hasLength(1));
      expect(unread.single.sender, 'BisB');
      expect(unread.single.text, unknownFormat);
      expect(unread.single.reasons, isNotEmpty);
    });

    test('never includes personal messages', () async {
      await intake.scan();
      final unread = await intake.unreadable();
      expect(unread.where((m) => m.text == personal), isEmpty);
    });
  });

  group('reading starts when messages are turned on', () {
    late MemoryPreferencesStore prefs;
    late DateTime now;
    late MessageIntake fresh;

    setUp(() {
      prefs = MemoryPreferencesStore();
      now = bh(2, 17); // between the BisB OTP (17:00) and later messages
      sms.inbox.add(('6', 'BisB', bh(2, 19), bisbCard.replaceAll('0.300', '0.700')));
      fresh = MessageIntake(
        sms: sms,
        ledger: ledger,
        seen: seen,
        preferences: prefs,
        clock: () => now,
      );
    });

    test('a new person: only messages after the permission are read',
        () async {
      expect(await fresh.requestPermission(), isTrue);
      expect(await fresh.offersEarlier(), isTrue);
      now = bh(2, 20);
      final report = await fresh.scan();
      expect(report.added, 1);
      expect((await ledger.entries()).single.result.amountFils, 700);
      // The bodies of the earlier messages were not even read.
      expect(sms.bodiesRead, ['6']);
    });

    test('earlier messages: a preview first, stored only when asked', () async {
      await fresh.requestPermission();
      now = bh(2, 20);
      await fresh.scan();

      final preview = await fresh.previewEarlier(7);
      expect(preview.purchases, 2);
      expect(preview.spentFils, 1800);
      expect(await ledger.entries(), hasLength(1)); // nothing stored yet

      final report = await fresh.addEarlier(7);
      expect(report.added, 2);
      expect((await ledger.entries()).map((e) => e.result.amountFils),
          unorderedEquals([300, 1500, 700]));
      expect(await fresh.offersEarlier(), isFalse);
      // Still never older than the window.
      expect(sms.bodiesRead, isNot(contains('5')));
    });

    test('saying no keeps the start and stops asking', () async {
      await fresh.requestPermission();
      await fresh.declineEarlier();
      expect(await fresh.offersEarlier(), isFalse);
      now = bh(2, 20);
      expect((await fresh.scan()).added, 1);
    });

    test('a phone that already read messages keeps the old window', () async {
      // Permission given before this version: no start saved, no question.
      now = bh(2, 20);
      final report = await fresh.scan();
      expect(report.added, 3);
      expect(await fresh.offersEarlier(), isFalse);
    });

    test('asking again later does not move the start', () async {
      await fresh.requestPermission();
      now = bh(2, 20);
      await fresh.requestPermission();
      expect((await fresh.scan()).added, 1);
    });
  });
}
