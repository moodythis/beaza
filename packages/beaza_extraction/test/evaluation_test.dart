import 'dart:io';

import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:beaza_extraction/evaluation.dart';
import 'package:test/test.dart';

/// Returns fixed predictions by message id.
class FakeSystem implements EvalSystem {
  FakeSystem(this.answers);
  final Map<String, Prediction> answers;

  @override
  String get id => 'FAKE';

  @override
  String get description => 'fixed answers';

  @override
  Prediction predict(GoldMessage m) => answers[m.id]!;
}

GoldMessage msg(String id, GoldLabel label,
        {String sender = 'BisB',
        String text = 'x',
        DateTime? at}) =>
    GoldMessage(
      id: id,
      sender: sender,
      receivedAt: at ?? DateTime.utc(2026, 11, 1),
      text: text,
      label: label,
    );

final buy = GoldLabel(
  isTransaction: true,
  amountFils: 1500,
  currency: 'BHD',
  direction: 'outgoing',
  type: 'purchase',
  merchant: 'SAMPLE SHOP',
  last4: '7744',
  time: DateTime.utc(2026, 11, 1, 10, 5),
);

Prediction right() => Prediction(
      isTransaction: true,
      accepted: true,
      amountFils: 1500,
      currency: 'BHD',
      direction: 'outgoing',
      type: 'purchase',
      merchant: 'sample  shop ',
      last4: '7744',
      time: DateTime.utc(2026, 11, 1, 10, 5, 30),
    );

void main() {
  group('gold file', () {
    const line =
        '{"id":"a","sender":"BisB","received_at":"2026-11-01T10:00:00Z","text":"t",'
        '"label":{"is_transaction":true,"amount_fils":300,"currency":"bhd",'
        '"direction":"outgoing","time":"2026-11-01T09:59:00Z"}}';

    test('parses a line, skips blanks and comments', () {
      final g = parseGold('// header\n\n$line\n');
      expect(g, hasLength(1));
      expect(g.single.label.amountFils, 300);
      expect(g.single.label.currency, 'BHD');
      expect(g.single.label.time, DateTime.utc(2026, 11, 1, 9, 59));
    });

    test('round trip through JSON', () {
      final g = parseGold(line).single;
      final again = GoldMessage.fromJson(g.toJson());
      expect(again.toJson(), g.toJson());
    });

    test('duplicate id is an error', () {
      expect(() => parseGold('$line\n$line'),
          throwsA(isA<FormatException>()
              .having((e) => e.message, 'message', contains('duplicate'))));
    });

    test('a non-transaction with fields is an error', () {
      expect(
          () => parseGold('{"id":"b","sender":"BisB","received_at":"2026-11-01T10:00:00Z",'
              '"text":"t","label":{"is_transaction":false,"amount_fils":5}}'),
          throwsFormatException);
    });

    test('an unknown type is an error', () {
      expect(
          () => parseGold('{"id":"b","sender":"BisB","received_at":"2026-11-01T10:00:00Z",'
              '"text":"t","label":{"is_transaction":true,"type":"gift"}}'),
          throwsFormatException);
    });

    test('amount must be whole fils', () {
      expect(
          () => parseGold('{"id":"b","sender":"BisB","received_at":"2026-11-01T10:00:00Z",'
              '"text":"t","label":{"is_transaction":true,"amount_fils":1.5}}'),
          throwsFormatException);
    });

    test('fingerprint is stable', () {
      expect(fnv1a(''), '811c9dc5');
      expect(fnv1a('a'), 'e40c292c');
    });
  });

  group('metrics', () {
    test('perfect answer: every score is 1, case and spacing ignored', () {
      final ev = evaluate(FakeSystem({'1': right()}), [msg('1', buy)]);
      final o = ev.overall;
      expect(o.detection.f1, 1.0);
      expect(o.micro.f1, 1.0);
      expect(o.amountExactRate, 1.0);
      expect(o.exactMatchRate, 1.0);
      expect(o.acceptedRate, 1.0);
      expect(ev.errors, isEmpty);
    });

    test('a wrong amount is one false positive and one false negative', () {
      final p = right();
      final wrong = Prediction(
        isTransaction: true,
        amountFils: 1600,
        currency: p.currency,
        direction: p.direction,
        type: p.type,
        merchant: p.merchant,
        last4: p.last4,
        time: p.time,
      );
      final ev = evaluate(FakeSystem({'1': wrong}), [msg('1', buy)]);
      final a = ev.overall.fields['amount']!;
      expect([a.tp, a.fp, a.fn], [0, 1, 1]);
      expect(ev.overall.amountExactRate, 0.0);
      expect(ev.overall.exactMatchRate, 0.0);
      expect(ev.overall.acceptedRate, 0.0);
      expect(ev.errors.single.field, 'amount');
      expect(ev.errors.single.gold, '1500');
      expect(ev.errors.single.predicted, '1600');
    });

    test('missed transaction and false alarm', () {
      const none = GoldLabel(isTransaction: false);
      final ev = evaluate(
        FakeSystem({
          'miss': const Prediction(isTransaction: false),
          'alarm': const Prediction(isTransaction: true, amountFils: 5),
          'ok': const Prediction(isTransaction: false),
        }),
        [msg('miss', buy), msg('alarm', none), msg('ok', none)],
      );
      final d = ev.overall.detection;
      expect([d.tp, d.fp, d.fn], [0, 1, 1]);
      expect(d.f1, 0.0);
      // The false alarm's amount is a false positive; the miss loses 7 fields.
      expect(ev.overall.fields['amount']!.fp, 1);
      expect(ev.overall.micro.fn, 7);
      expect(ev.overall.exactMatch, 1);
    });

    test('nothing predicted for an expected field gives F1 0, not undefined',
        () {
      final c = Counts()..fn = 3;
      expect(c.precision.isNaN, isTrue);
      expect(c.f1, 0.0);
      expect(Counts().f1.isNaN, isTrue);
    });

    test('groups by sender family and language', () {
      final ev = evaluate(FakeSystem({'1': right(), '2': right()}), [
        msg('1', buy, sender: 'ilabank', text: 'Purchase BHD 1.500'),
        msg('2', buy, sender: 'NBB', text: 'تم خصم 1.500 د.ب من بطاقتك'),
      ]);
      expect(ev.bySender.keys, containsAll(['ila', 'nbb']));
      expect(ev.byLanguage.keys, containsAll(['english', 'arabic']));
    });

    test('a time copied from the receive time is not a prediction', () {
      final p = Prediction.fromResult(ExtractionResult(
        status: ExtractionStatus.transaction,
        kind: MessageKind.transaction,
        timestamp: DateTime.utc(2026, 11, 1),
        flags: const [ExtractionFlag.timestampFromReceipt],
      ));
      expect(p.time, isNull);
      expect(p.isTransaction, isTrue);
      expect(p.accepted, isTrue);
    });

    test('an unreadable bank transaction counts as detected, not accepted', () {
      const p = ExtractionResult(
        status: ExtractionStatus.unparsed,
        kind: MessageKind.transaction,
        issues: [ValidationIssue.noTemplate],
      );
      final pred = Prediction.fromResult(p);
      expect(pred.isTransaction, isTrue);
      expect(pred.accepted, isFalse);
    });
  });

  group('splits', () {
    final many = [
      for (var i = 0; i < 100; i++)
        msg('m$i', buy,
            sender: i.isEven ? 'BisB' : 'ilabank',
            at: DateTime.utc(2026, 1, 1).add(Duration(hours: i))),
    ];

    test('random split is repeatable and near the fraction', () {
      final a = splitMessages(many, kind: SplitKind.random, seed: 7);
      final b = splitMessages(many, kind: SplitKind.random, seed: 7);
      expect(a.test.map((m) => m.id), b.test.map((m) => m.id));
      expect(a.test.length + a.dev.length, 100);
      expect(a.test.length, inInclusiveRange(15, 45));
      final c = splitMessages(many, kind: SplitKind.random, seed: 8);
      expect(c.test.map((m) => m.id), isNot(a.test.map((m) => m.id)));
    });

    test('time split puts the latest messages in test', () {
      final s = splitMessages(many.reversed.toList(),
          kind: SplitKind.time, testFraction: 0.2);
      expect(s.test, hasLength(20));
      final lastDev = s.dev.map((m) => m.receivedAt).reduce(
          (a, b) => a.isAfter(b) ? a : b);
      expect(s.test.every((m) => m.receivedAt.isAfter(lastDev)), isTrue);
    });

    test('template split holds out whole sender families', () {
      final s = splitMessages(many,
          kind: SplitKind.template, holdout: {SenderFamily.ila});
      expect(s.test, hasLength(50));
      expect(s.test.every((m) => m.sender == 'ilabank'), isTrue);
      expect(() => splitMessages(many, kind: SplitKind.template),
          throwsArgumentError);
    });
  });

  group('agreement', () {
    test("Cohen's kappa on a known table", () {
      // 10 messages: both yes 4, both no 4, A yes B no 1, A no B yes 1.
      // observed 0.8, expected 0.5, kappa 0.6.
      const yes = GoldLabel(isTransaction: true, amountFils: 100);
      const no = GoldLabel(isTransaction: false);
      final a = <GoldMessage>[];
      final b = <GoldMessage>[];
      final pairs = [
        ...List.filled(4, (yes, yes)),
        ...List.filled(4, (no, no)),
        (yes, no),
        (no, yes),
      ];
      for (var i = 0; i < pairs.length; i++) {
        a.add(msg('$i', pairs[i].$1));
        b.add(msg('$i', pairs[i].$2));
      }
      b.add(msg('extra', no));
      final ag = agreement(a, b);
      expect(ag.shared, 10);
      expect(ag.onlyB, 1);
      expect(ag.observed, closeTo(0.8, 1e-9));
      expect(ag.kappa, closeTo(0.6, 1e-9));
      expect(ag.fieldAgreement['amount'], 1.0);
      expect(ag.disagreements.where((d) => d.field == 'is_transaction'),
          hasLength(2));
    });
  });

  group('seed data with B1', () {
    final seed = parseGold(File('eval/seed.jsonl').readAsStringSync(),
        name: 'seed.jsonl');

    test('seed file is valid', () {
      expect(seed, hasLength(30));
      expect(seed.where((m) => m.label.isTransaction), hasLength(21));
    });

    test('B1 reads the supported formats exactly', () {
      final ev = evaluate(RulesSystem(), seed);
      final wrongIds = ev.errors.map((e) => e.id).toSet();
      for (final id in [
        's-bisb-01', 's-bisb-02', 's-bisb-03', 's-bisb-04',
        's-ila-01', 's-ila-02', 's-ila-03', 's-ila-04',
        's-als-01', 's-als-02', 's-als-04', 's-als-05', 's-bp-01',
      ]) {
        expect(wrongIds, isNot(contains(id)), reason: id);
      }
      expect(ev.overall.messages, 30);
    });

    // The 33 NBB, 1 KFH and 3 BBK formats taken from real messages, with
    // every account, card, reference and balance made up (eval/formats.jsonl).
    test('B1 reads every message format exactly', () {
      final formats = parseGold(File('eval/formats.jsonl').readAsStringSync(),
          name: 'formats.jsonl');
      expect(formats, hasLength(37));
      expect(formats.where((m) => m.id.startsWith('f-bbk-')), hasLength(3));
      expect(formats.where((m) => m.id.startsWith('f-nbb-')), hasLength(33));
      final ev = evaluate(RulesSystem(), formats);
      expect(ev.errors.map((e) => '${e.id} ${e.field}'), isEmpty);
      expect(ev.overall.acceptedRate, 1.0);
    });

    test('report has the summary and every section', () {
      final ev = evaluate(RulesSystem(), seed);
      final md = markdownReport(
        const RunInfo(
          dataName: 'eval/seed.jsonl',
          dataFingerprint: '00000000',
          split: 'all messages',
          devCount: 0,
          testCount: 30,
          templateVersion: kTemplateSetVersion,
          command: 'test',
        ),
        [('B1', 'rules', ev)],
      );
      for (final s in [
        '## Summary', '### Fields', '### By sender family', '### By language',
        '### Errors',
      ]) {
        expect(md, contains(s));
      }
    });
  });
}
