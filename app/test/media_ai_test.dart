import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/data/services/media_ai_api.dart';
import 'package:beaza/data/services/receipt_scanner.dart';
import 'package:beaza/data/services/voice_input.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza/ui/features/receipt/view_models/receipt_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime now = DateTime.utc(2026, 11, 4, 9); // 12:00 in Bahrain

class ImageScanner extends ReceiptScanner {
  ImageScanner(this.text);
  final String text;
  int withImage = 0;

  @override
  Future<String?> scan(ReceiptSource source) async => text;

  @override
  Future<({String text, String? jpeg})?> scanWithImage(ReceiptSource source) async {
    withImage++;
    return (text: text, jpeg: 'AAAA');
  }
}

class FakeMediaAi implements MediaAiApi {
  AiReceipt? receipt;
  bool fail = false;
  final List<String> sentImages = [];
  final List<String> sentAudio = [];
  final List<String> sentText = [];

  @override
  Future<AiReceipt?> readReceipt(String jpegBase64, String language) async {
    sentImages.add(jpegBase64);
    if (fail) throw Exception('offline');
    return receipt;
  }

  @override
  Future<({String text, List<AiDraft> drafts})> readVoice(
      String audioBase64, String language) async {
    sentAudio.add(audioBase64);
    if (fail) throw Exception('offline');
    return (
      text: 'شريت كرك بربيتين وعبيت بترول بدينار ونص',
      drafts: const [
        AiDraft(item: 'كرك', fils: 200, category: 'food'),
        AiDraft(item: 'بترول', fils: 1500, category: 'transport'),
      ],
    );
  }

  @override
  Future<List<AiDraft>> readExpenses(String text, String language) async {
    sentText.add(text);
    return const [AiDraft(item: 'غدا', fils: 2500, category: 'food')];
  }
}

class FakeRecorder implements VoiceRecorder {
  int started = 0;
  @override
  Future<void> start() async => started++;
  @override
  Future<String?> stop() async => 'AUDIO';
  @override
  Future<void> cancel() async {}
}

void main() {
  group('receipt photo with AI', () {
    test('without consent nothing is sent: the phone reads it', () async {
      final ai = FakeMediaAi();
      final scanner = ImageScanner('SHOP\nTOTAL 3.300');
      final vm = ReceiptViewModel(
        scanner: scanner,
        ledger: InMemoryLedgerRepository(),
        clock: () => now,
        ai: ai,
        consent: MediaAiConsent(MemoryPreferencesStore()),
      );
      await vm.scan(ReceiptSource.camera);
      expect(scanner.withImage, 0);
      expect(ai.sentImages, isEmpty);
      expect(vm.result!.amountFils, 3300);
      expect(vm.fromAi, isFalse);
    });

    test('with consent the AI reading wins, and failures fall back', () async {
      final prefs = MemoryPreferencesStore();
      final consent = MediaAiConsent(prefs);
      await consent.turnOn();
      final ai = FakeMediaAi()
        ..receipt = const AiReceipt(
          fils: 1100,
          currency: 'BHD',
          kind: 'purchase',
          shop: 'Kids Port Games',
          date: '2026-11-03',
          time: '22:56',
          category: 'entertainment',
        );
      final vm = ReceiptViewModel(
        scanner: ImageScanner('garbled text 8.000 x 0.100'),
        ledger: InMemoryLedgerRepository(),
        clock: () => now,
        ai: ai,
        consent: consent,
      );
      await vm.scan(ReceiptSource.gallery);
      expect(ai.sentImages, ['AAAA']);
      expect(vm.fromAi, isTrue);
      expect(vm.result!.amountFils, 1100);
      expect(vm.result!.merchantRaw, 'Kids Port Games');
      expect(vm.result!.category, 'entertainment'); // chosen by the AI
      // 3 Nov 22:56 in Bahrain = 19:56 UTC.
      expect(vm.result!.timestamp, DateTime.utc(2026, 11, 3, 19, 56));

      ai.fail = true;
      vm.startOver();
      await vm.scan(ReceiptSource.gallery);
      expect(vm.fromAi, isFalse);
      expect(vm.aiFailed, isTrue);
      expect(vm.aiDetail, contains('offline'));
      expect(vm.step, ReceiptStep.review);

      // Try again with the same photo: now it works.
      ai.fail = false;
      await vm.retryAi();
      expect(vm.fromAi, isTrue);
      expect(vm.aiFailed, isFalse);
      expect(vm.result!.amountFils, 1100);
      expect(ai.sentImages, ['AAAA', 'AAAA', 'AAAA']);
    });

    test('the AI answers but cannot read it: shown as a failure', () async {
      final consent = MediaAiConsent(MemoryPreferencesStore());
      await consent.turnOn();
      final vm = ReceiptViewModel(
        scanner: ImageScanner('SHOP\nTOTAL 3.300'),
        ledger: InMemoryLedgerRepository(),
        clock: () => now,
        ai: FakeMediaAi(), // receipt stays null
        consent: consent,
      );
      await vm.scan(ReceiptSource.camera);
      expect(vm.aiTried, isTrue);
      expect(vm.aiFailed, isTrue);
      expect(vm.result!.amountFils, 3300);
    });

    test('a declined screen read by AI is not a purchase', () {
      final r = resultFromAi(
        const AiReceipt(fils: 5000, currency: 'BHD', kind: 'declined'),
        const ExtractionResult(status: ExtractionStatus.unparsed),
        now,
      );
      expect(r.status, ExtractionStatus.nonTransaction);
      expect(r.kind, MessageKind.declined);
    });
  });

  testWidgets('voice with AI: record, then check the drafts and add',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final prefs = MemoryPreferencesStore();
    final consent = MediaAiConsent(prefs);
    await consent.turnOn();
    final ai = FakeMediaAi();
    final recorder = FakeRecorder();
    final ledger = InMemoryLedgerRepository();
    final vm = HomeViewModel(
      ledger: ledger,
      settings: InMemorySettingsRepository(
          const GuardrailSettings(dailyLimitFils: 10000)),
      mediaAi: ai,
      mediaConsent: consent,
      recorder: recorder,
      clock: () => now,
    );
    await vm.load();
    await tester.pumpWidget(BeazaApp(homeViewModel: vm, locale: const Locale('en')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quickAdd')));
    await tester.pumpAndSettle();

    // Typed text can be understood by the AI too.
    await tester.enterText(find.byKey(const Key('quickAddText')), 'غدا بدينارين ونص');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quickAddAi')));
    await tester.pumpAndSettle();
    expect(ai.sentText, ['غدا بدينارين ونص']);
    expect(find.byKey(const Key('aiDraftsNote')), findsOneWidget);
    expect(find.text('BHD 2.500'), findsWidgets);
    expect(recorder.started, 0); // no voice object: no automatic recording
  });
}
