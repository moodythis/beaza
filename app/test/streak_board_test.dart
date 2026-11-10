import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/rewards_repository.dart';
import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/data/services/leaderboard_api.dart';
import 'package:beaza/domain/use_cases/daily_close.dart';
import 'package:beaza/domain/use_cases/leaderboard.dart';
import 'package:beaza/domain/use_cases/streak.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/features/account/legal_text.dart';
import 'package:beaza/ui/features/account/views/account_widgets.dart';
import 'package:beaza/ui/features/savings/view_models/leaderboard_sync.dart';
import 'package:beaza/ui/features/savings/view_models/savings_view_model.dart';
import 'package:beaza/ui/features/savings/views/leaderboard_card.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

int _n = 0;
ExtractionResult tx(int fils, DateTime at) => ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      merchantNorm: 'Cafe',
      reference: 'S${_n++}',
      timestamp: at,
    );

List<LedgerEntry> ledger(List<ExtractionResult> rs) =>
    const Reconciler().reconcile(rs, OwnAccounts());

/// Noon Bahrain time on [day] November 2026.
DateTime noon(int day) => DateTime.utc(2026, 11, day, 9);

const today = Day(2026, 11, 10);

/// 3.000 on each of [days], except [over] days which get 12.000.
List<LedgerEntry> month(Iterable<int> days, {Set<int> over = const {}}) => ledger([
      for (final d in days) tx(over.contains(d) ? 12000 : 3000, noon(d)),
    ]);

class FakeBoard implements LeaderboardApi {
  final List<Map<String, Object>> sent = [];
  final List<String> left = [];
  BoardException? fail;
  bool keepsMe = true;

  @override
  Future<OnlineBoard> post(Map<String, Object> request) async {
    sent.add(request);
    if (fail != null) throw fail!;
    return OnlineBoard(
      rows: [
        const BoardRow(points: 500, streak: 9, number: 111),
        if (keepsMe)
          BoardRow(
            points: request['points30d']! as int,
            streak: request['streakDays']! as int,
            number: 222,
            nickname: request['nickname'] as String?,
            me: true,
          ),
      ],
      rank: keepsMe ? 2 : null,
    );
  }

  @override
  Future<void> leave(String boardId) async => left.add(boardId);
}

Future<(SavingsViewModel, MemoryPreferencesStore, FakeBoard)> make(
  List<ExtractionResult> rs, {
  DateTime? now,
  bool withBoard = true,
}) async {
  final at = now ?? noon(10);
  final prefs = MemoryPreferencesStore();
  final api = FakeBoard();
  final vm = SavingsViewModel(
    repo: SavingsRepository(prefs, clock: () => at),
    ledger: InMemoryLedgerRepository(initial: rs),
    rewards: RewardsRepository(prefs, clock: () => at),
    board: withBoard ? LeaderboardSync(api: api, preferences: prefs) : null,
    settings: InMemorySettingsRepository(
        const GuardrailSettings(dailyLimitFils: 10000)),
    clock: () => at,
  );
  await vm.load();
  return (vm, prefs, api);
}

Widget host(SavingsViewModel vm, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ListenableBuilder(
          listenable: vm,
          builder: (context, _) => SingleChildScrollView(
            child: Column(children: [
              StreakRow(viewModel: vm),
              LeaderboardCard(viewModel: vm),
            ]),
          ),
        ),
      ),
    );

void main() {
  group('streakWithFreeze', () {
    test('counts finished days in a row within the limit', () {
      final r = streakWithFreeze(month([5, 6, 7, 8, 9]), today, 10000, max: 5);
      expect(r.days, 5);
      expect(r.usedOn, isNull);
      // A day over the limit ends it.
      expect(
          streakWithFreeze(month([5, 6, 7, 8, 9], over: {7}), today, 10000).days,
          2);
      expect(streakWithFreeze(month([9]), today, 0).days, 0);
    });

    test('a held freeze covers one day over the limit, then it is gone', () {
      final entries = month([4, 5, 6, 7, 8, 9], over: {5, 8});
      final r = streakWithFreeze(entries, today, 10000,
          freezeBoughtOn: const Day(2026, 11, 7), max: 6);
      // The 9th counts, the 8th is frozen (not counted), the 7th and 6th
      // count, and the 5th ends it: the freeze was already used.
      expect(r.days, 3);
      expect(r.usedOn, const Day(2026, 11, 8));
      expect(r.frozen, {const Day(2026, 11, 8)});
      expect(r.freezeHeld, isFalse);
      // The next time, the frozen day is remembered and nothing is used.
      final again = streakWithFreeze(entries, today, 10000,
          frozen: r.frozen, max: 6);
      expect(again.days, 3);
      expect(again.usedOn, isNull);
    });

    test('a freeze bought later cannot repair an older break', () {
      final r = streakWithFreeze(month([6, 7, 8, 9], over: {7}), today, 10000,
          freezeBoughtOn: const Day(2026, 11, 9));
      expect(r.days, 2);
      expect(r.freezeHeld, isTrue);
      expect(r.usedOn, isNull);
    });

    test('each day is judged by the limit it had', () {
      // 12.000 on the 8th was within that day's limit of 15.000.
      final entries = month([7, 8, 9], over: {8});
      expect(streakWithFreeze(entries, today, 10000, max: 3).days, 1);
      expect(
          streakWithFreeze(entries, today, 10000,
              limitOn: {const Day(2026, 11, 8): 15000}, max: 3).days,
          3);
    });
  });

  group('the streak freeze in the app', () {
    test('costs 50 points, one at a time, and is used by itself', () async {
      // Six days within the limit: 60 points.
      final (vm, prefs, _) = await make([
        for (final d in [4, 5, 6, 7, 8, 9]) tx(3000, noon(d)),
      ], withBoard: false);
      expect(vm.pointsBalance, 60);
      expect(vm.streak, greaterThanOrEqualTo(6));
      expect(await vm.buyFreeze(), isTrue);
      expect(vm.freezeHeld, isTrue);
      expect(vm.pointsBalance, 10);
      expect(await vm.buyFreeze(), isFalse);
      expect(prefs.values[RewardsRepository.freezeKey], dayKey(today));

      // The next day goes over the limit; the day after, the freeze has
      // covered it and the streak is still there.
      final at = noon(12);
      final later = SavingsViewModel(
        repo: SavingsRepository(prefs, clock: () => at),
        ledger: InMemoryLedgerRepository(initial: [
          for (final d in [4, 5, 6, 7, 8, 9, 10]) tx(3000, noon(d)),
          tx(12000, noon(11)),
        ]),
        rewards: RewardsRepository(prefs, clock: () => at),
        settings: InMemorySettingsRepository(
            const GuardrailSettings(dailyLimitFils: 10000)),
        clock: () => at,
      );
      await later.load();
      expect(later.freezeUsedOn, const Day(2026, 11, 11));
      expect(later.freezeHeld, isFalse);
      expect(later.streak, greaterThanOrEqualTo(7));
      expect(prefs.values[RewardsRepository.freezeKey], isNull);
    });

    test('not enough points: no freeze', () async {
      final (vm, _, _) = await make([tx(3000, noon(9))], withBoard: false);
      expect(vm.pointsBalance, 10);
      expect(await vm.buyFreeze(), isFalse);
      expect(vm.freezeHeld, isFalse);
    });
  });

  group('names on the board', () {
    test('a nickname is 3 to 15 letters and spaces, nothing else', () {
      for (final ok in ['Abu Salman', 'أبو سلمان', 'Zoë', '  Ali   Reza ']) {
        expect(nicknameProblem(ok), isNull, reason: ok);
      }
      expect(tidyNickname('  Ali   Reza '), 'Ali Reza');
      for (final bad in [
        'ali99', 'علي٣٣', 'a@b', '39001234', 'ali.k', 'ali_k', 'ali-k', 'عمر 😀', '+973',
      ]) {
        expect(nicknameProblem(bad), NicknameProblem.notLetters, reason: bad);
      }
      expect(nicknameProblem('ab'), NicknameProblem.tooShort);
      expect(nicknameProblem(''), NicknameProblem.tooShort);
      expect(nicknameProblem('a' * 16), NicknameProblem.tooLong);
    });

    test('the persona number is the same here and on the server', () {
      // The same two values are pinned in server/test/leaderboard.test.ts.
      expect(fnv1a('abc'), 2921240957);
      expect(personaNumber('0123456789abcdef0123456789abcdef'), 413);
    });

    test('the title follows the points', () {
      expect(personaTitle(0), PersonaTitle.guardian);
      expect(personaTitle(100), PersonaTitle.filsMaster);
      expect(personaTitle(299), PersonaTitle.captain);
      expect(personaTitle(300), PersonaTitle.falcon);
    });

    test('the practice board: 15 made-up rows, the same for everyone that week',
        () {
      final a = practiceBoard(today);
      expect(a, hasLength(15));
      expect(a.every((r) => !r.me && r.nickname == null), isTrue);
      expect(a.every((r) => r.points % 10 == 0 && r.points >= 0), isTrue);
      expect(practiceBoard(today).map((r) => r.points),
          a.map((r) => r.points));
      final ranked = rankBoard([
        ...a,
        const BoardRow(points: 9999, streak: 1, number: 500, me: true),
      ]);
      expect(ranked.first.me, isTrue);
    });
  });

  group('the online board', () {
    test('nothing is sent before joining; then only five or six fields',
        () async {
      final (vm, prefs, api) = await make([tx(3000, noon(9))]);
      expect(api.sent, isEmpty);
      expect(vm.boardOnline, isFalse);
      expect(vm.boardRows.where((r) => r.me), hasLength(1));
      expect(vm.boardRows, hasLength(16));

      await vm.joinBoard();
      expect(prefs.values[LeaderboardSync.prefName], kBoardConsentVersion);
      final r = api.sent.single;
      expect(r.keys.toSet(),
          {'consent', 'boardId', 'displayMode', 'points30d', 'streakDays'});
      expect(r['displayMode'], 'persona');
      expect(r['points30d'], 10);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(r['boardId']! as String), isTrue);
      expect(vm.boardOnline, isTrue);
      expect(vm.board!.rank, 2);

      // The same score is not sent twice.
      await vm.load();
      expect(api.sent, hasLength(1));

      // A nickname is sent as one, and only then.
      expect(await vm.setNickname('ali99'), NicknameProblem.notLetters);
      expect(api.sent, hasLength(1));
      expect(await vm.setNickname(' Abu  Salman '), isNull);
      expect(api.sent.last['displayMode'], 'nickname');
      expect(api.sent.last['nickname'], 'Abu Salman');
    });

    test('leaving deletes the row and makes a new id for next time', () async {
      final (vm, prefs, api) = await make([tx(3000, noon(9))]);
      await vm.joinBoard();
      final id = api.sent.single['boardId']! as String;
      await vm.leaveBoard();
      expect(api.left, [id]);
      expect(prefs.values.containsKey(LeaderboardSync.prefName), isFalse);
      expect(vm.boardOnline, isFalse);
      expect(prefs.values[RewardsRepository.boardIdKey], isNot(id));
      await vm.load();
      expect(api.sent, hasLength(1));
    });

    test('outside the top 50 the own row is shown last; offline falls back',
        () async {
      final (vm, _, api) = await make([tx(3000, noon(9))]);
      api.keepsMe = false;
      await vm.joinBoard();
      expect(vm.board!.rank, isNull);
      expect(vm.boardRows.last.me, isTrue);

      final (off, _, down) = await make([tx(3000, noon(9))]);
      down.fail = const BoardException('network');
      await off.joinBoard();
      expect(off.boardOnline, isFalse);
      expect(off.board!.error, 'network');
      expect(off.boardRows, hasLength(16));
    });
  });

  group('the leaderboard card', () {
    testWidgets('practice board first, own row marked, a nickname with digits refused',
        (tester) async {
      final (vm, _, api) = await make([tx(3000, noon(9))]);
      await tester.pumpWidget(host(vm));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('boardMe')), findsOneWidget);
      expect(
          tester.widget<Text>(find.byKey(const Key('boardNote'))).data,
          contains('not people'));
      expect(find.textContaining('Beaza Guardian'), findsWidgets);

      await tester.ensureVisible(find.byKey(const Key('boardNickSwitch')));
      await tester.tap(find.byKey(const Key('boardNickSwitch')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('boardNickField')), '39001234');
      await tester.tap(find.byKey(const Key('boardNickSave')));
      await tester.pumpAndSettle();
      expect(find.textContaining('no digits'), findsOneWidget);
      expect(vm.nickname, isNull);
      await tester.enterText(find.byKey(const Key('boardNickField')), 'Abu Salman');
      await tester.tap(find.byKey(const Key('boardNickSave')));
      await tester.pumpAndSettle();
      expect(vm.nickname, 'Abu Salman');
      expect(find.text('Abu Salman · you'), findsOneWidget);
      expect(api.sent, isEmpty);
    });

    testWidgets('joining shows exactly what is sent, with the privacy notice',
        (tester) async {
      final (vm, _, api) = await make([tx(3000, noon(9))]);
      await tester.pumpWidget(host(vm));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('boardJoin')));
      await tester.tap(find.byKey(const Key('boardJoin')));
      await tester.pumpAndSettle();
      expect(
          tester.widget<Text>(find.byKey(const Key('boardJoinWhat'))).data,
          allOf(contains('No amounts'), contains('random id')));
      expect(find.byKey(const Key('boardPrivacy')), findsOneWidget);
      expect(api.sent, isEmpty);
      await tester.tap(find.byKey(const Key('boardJoinAgree')));
      await tester.pumpAndSettle();
      expect(api.sent, hasLength(1));
      expect(
          tester.widget<Text>(find.byKey(const Key('boardNote'))).data,
          contains('Online board'));
      expect(find.text('Your place online: 2'), findsOneWidget);
      expect(privacyNotice.en[kPrivacyBoardSection].title, contains('leaderboard'));
      expect(privacyNotice.ar[kPrivacyBoardSection].title, contains('لوحة الصدارة'));
    });

    testWidgets('the flame swells when the streak grows, not with reduced motion',
        (tester) async {
      double scale() => tester
          .widget<Transform>(find
              .ancestor(
                  of: find.byKey(const Key('streakFlame')),
                  matching: find.byType(Transform))
              .first)
          .transform
          .getMaxScaleOnAxis();
      Widget flame(int days, {bool still = false}) => MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: still),
              child: Center(child: StreakFlame(days: days)),
            ),
          );
      await tester.pumpWidget(flame(3));
      expect(scale(), closeTo(1, 0.001));
      await tester.pumpWidget(flame(4));
      await tester.pump(const Duration(milliseconds: 300));
      expect(scale(), greaterThan(1.2));
      await tester.pumpAndSettle();
      expect(scale(), closeTo(1, 0.001));

      await tester.pumpWidget(flame(4, still: true));
      await tester.pumpWidget(flame(5, still: true));
      await tester.pump(const Duration(milliseconds: 300));
      expect(scale(), closeTo(1, 0.001));
    });

    testWidgets('Arabic: titles and the practice note', (tester) async {
      final (vm, _, _) = await make([tx(3000, noon(9))]);
      await tester.pumpWidget(host(vm, locale: const Locale('ar')));
      await tester.pumpAndSettle();
      expect(find.text('لوحة الصدارة'), findsOneWidget);
      expect(find.textContaining('حارس البيزة'), findsWidgets);
      expect(
          tester.widget<Text>(find.byKey(const Key('boardNote'))).data,
          contains('مو ناس حقيقيين'));
    });
  });
}
