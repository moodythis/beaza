import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/data/services/voice_input.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeVoice implements VoiceInput {
  FakeVoice(this.said, {this.fail = false});
  final String? said;
  final bool fail;
  final List<String> languages = [];

  @override
  Future<String?> listen({required String language}) async {
    languages.add(language);
    if (fail) throw PlatformException(code: 'no_speech');
    return said;
  }
}

final DateTime now = DateTime.utc(2026, 11, 4, 9); // 12:00 in Bahrain

Future<(HomeViewModel, InMemoryLedgerRepository)> pump(
  WidgetTester tester, {
  VoiceInput? voice,
  Locale locale = const Locale('en'),
}) async {
  final ledger = InMemoryLedgerRepository();
  final vm = HomeViewModel(
    ledger: ledger,
    settings: InMemorySettingsRepository(
        const GuardrailSettings(dailyLimitFils: 10000)),
    voice: voice,
    clock: () => now,
  );
  await vm.load();
  await tester.pumpWidget(BeazaApp(homeViewModel: vm, locale: locale));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('quickAdd')));
  await tester.pumpAndSettle();
  return (vm, ledger);
}

void main() {
  testWidgets('typed Gulf Arabic becomes two drafts, saved on Add',
      (tester) async {
    final (_, ledger) = await pump(tester);
    expect(find.byKey(const Key('quickAddSpeak')), findsNothing);
    await tester.enterText(find.byKey(const Key('quickAddText')),
        'شريت كرك بربيتين وشاورما بـ 800 فلس');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('draft_0')), findsOneWidget);
    expect(find.byKey(const Key('draft_1')), findsOneWidget);
    expect(find.text('Total BHD 1.000'), findsOneWidget);

    await tester.tap(find.byKey(const Key('quickAddSave')));
    await tester.pumpAndSettle();
    final saved = (await ledger.entries()).map((e) => e.result).toList();
    expect(saved.map((r) => r.amountFils), containsAll([200, 800]));
    // The local word list gives the category the shop dictionary lacks.
    expect(saved.every((r) => r.category == 'food'), isTrue);
    expect(saved.every((r) => r.timestamp == now), isTrue);
    expect(find.byKey(const Key('quickAddText')), findsNothing);
  });

  testWidgets('no amount: nothing to add', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('quickAddText')), 'مرحبا');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quickAddNone')), findsOneWidget);
    final save = tester.widget<FilledButton>(find.byKey(const Key('quickAddSave')));
    expect(save.onPressed, isNull);
  });

  testWidgets('a guessed unit asks to check the amount', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('quickAddText')), 'كرك 200');
    await tester.pumpAndSettle();
    expect(find.text('No unit written: check the amount'), findsOneWidget);
  });

  testWidgets('speaking fills the text in Bahraini Arabic', (tester) async {
    final voice = FakeVoice('دفعت دينار ونص في البرادة');
    await pump(tester, voice: voice, locale: const Locale('ar'));
    await tester.tap(find.byKey(const Key('quickAddSpeak')));
    await tester.pumpAndSettle();
    expect(voice.languages, ['ar-BH']);
    expect(find.byKey(const Key('draft_0')), findsOneWidget);
    expect(find.text('البراده'), findsOneWidget);
  });

  testWidgets('an English screen still listens in Arabic, unless switched',
      (tester) async {
    final voice = FakeVoice('كرك بربيتين');
    await pump(tester, voice: voice);
    await tester.tap(find.byKey(const Key('quickAddSpeak')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('speechEnglish')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quickAddSpeak')));
    await tester.pumpAndSettle();
    expect(voice.languages, ['ar-BH', 'en-US']);
    // Each recording is its own line, so its own item.
    expect(find.byKey(const Key('draft_0')), findsOneWidget);
    expect(find.byKey(const Key('draft_1')), findsOneWidget);
  });

  testWidgets('no speech service on the phone is explained', (tester) async {
    await pump(tester, voice: FakeVoice(null, fail: true));
    await tester.tap(find.byKey(const Key('quickAddSpeak')));
    await tester.pumpAndSettle();
    expect(find.text('Voice input is not available on this phone'),
        findsOneWidget);
  });

  test('a manual add keeps a given category', () async {
    final ledger = InMemoryLedgerRepository();
    await ledger.addManual(
        amountFils: 200, merchant: 'كرك', at: now, category: 'food');
    await ledger.addManual(amountFils: 900, merchant: 'TALABAT', at: now);
    final rs = (await ledger.entries()).map((e) => e.result).toList();
    expect(rs.map((r) => r.category), ['food', 'food']);
  });

  test('speech language follows the app language', () {
    expect(speechLanguage('ar'), 'ar-BH');
    expect(speechLanguage('en'), 'en-US');
  });
}
