import 'dart:async';

import 'package:beaza/data/repositories/ledger_repository.dart';
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
}
