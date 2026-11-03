import 'package:beaza/app.dart';
import 'package:beaza/data/repositories/account_repository.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/data/services/account_store.dart';
import 'package:beaza/data/services/sync_api.dart';
import 'package:beaza/ui/features/account/legal_text.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:beaza_crypto/beaza_crypto.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Account without a server or real crypto, for the screens.
class FakeAccounts extends AccountRepository {
  SavedAccount? _current;
  Consent? lastConsent;
  final recoveryKey = RecoveryKey.fromSecret(List.generate(18, (i) => i * 7));
  String? deletedWith;

  @override
  SavedAccount? get current => _current;

  void signIn(String email) {
    _current = SavedAccount(
        email: email, token: 't', dataKey: DataKey.fromBytes(List.filled(32, 1)));
    notifyListeners();
  }

  @override
  Future<void> load() async {}

  @override
  Future<RecoveryKey> signUp({
    required String email,
    required String password,
    required Consent consent,
  }) async {
    lastConsent = consent;
    signIn(email);
    return recoveryKey;
  }

  @override
  Future<void> logIn({required String email, required String password}) async {
    if (password != 'right password') {
      throw const AccountFailure(AccountProblem.wrongCredentials);
    }
    signIn(email);
  }

  @override
  Future<void> recover({
    required String email,
    required String recoveryKey,
    required String newPassword,
  }) async =>
      signIn(email);

  @override
  Future<AccountInfo> info() async => AccountInfo(
        email: _current!.email,
        createdAt: DateTime.utc(2026, 11, 3),
        privacyVersion: privacyNotice.version,
        termsVersion: termsOfUse.version,
        consentAt: DateTime.utc(2026, 11, 3),
        encryptedRecords: 0,
        activeSessions: 1,
      );

  @override
  Future<void> deleteAccount(String password) async {
    deletedWith = password;
    _current = null;
    notifyListeners();
  }

  @override
  Future<void> logOut() async {
    _current = null;
    notifyListeners();
  }
}

Future<FakeAccounts> pumpApp(WidgetTester tester,
    {Locale locale = const Locale('en'), FakeAccounts? accounts}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final account = accounts ?? FakeAccounts();
  final vm = HomeViewModel(
    ledger: InMemoryLedgerRepository(),
    settings: InMemorySettingsRepository(const GuardrailSettings(dailyLimitFils: 10000)),
  );
  await vm.load();
  await tester.pumpWidget(
      BeazaApp(homeViewModel: vm, locale: locale, account: account));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('accountButton')));
  await tester.pumpAndSettle();
  return account;
}

Finder checkbox(String key) => find.descendant(
    of: find.byKey(Key(key)), matching: find.byType(Checkbox));

bool enabled(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed != null;

void main() {
  testWidgets('signed out: the account screen explains and offers both ways in',
      (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const Key('createAccountButton')), findsOneWidget);
    expect(find.byKey(const Key('logInButton')), findsOneWidget);
    expect(find.textContaining('nothing leaves this phone'), findsOneWidget);
  });

  testWidgets('sign-up needs three separate ticks, none ticked at first',
      (tester) async {
    final accounts = await pumpApp(tester);
    await tester.tap(find.byKey(const Key('createAccountButton')));
    await tester.pumpAndSettle();

    for (final key in ['consentPrivacy', 'consentTerms', 'consentAdult']) {
      expect(tester.widget<Checkbox>(checkbox(key)).value, false, reason: key);
    }
    await tester.enterText(find.byKey(const Key('emailField')), 'a@b.co');
    await tester.enterText(find.byKey(const Key('passwordField')), 'a long password');
    await tester.enterText(find.byKey(const Key('repeatField')), 'a long password');
    expect(enabled(tester, 'signUpSubmit'), false);

    await tester.tap(checkbox('consentPrivacy'));
    await tester.tap(checkbox('consentTerms'));
    await tester.pump();
    expect(enabled(tester, 'signUpSubmit'), false, reason: 'age not stated');

    await tester.tap(checkbox('consentAdult'));
    await tester.pump();
    expect(enabled(tester, 'signUpSubmit'), true);

    await tester.tap(find.byKey(const Key('signUpSubmit')));
    await tester.pumpAndSettle();
    expect(accounts.lastConsent!.privacyVersion, privacyNotice.version);
    expect(accounts.lastConsent!.termsVersion, termsOfUse.version);
    expect(accounts.lastConsent!.adult, true);
    expect(find.byKey(const Key('recoveryKeyText')), findsOneWidget);
  });

  testWidgets('wrong email and short password are shown, nothing is sent',
      (tester) async {
    final accounts = await pumpApp(tester);
    await tester.tap(find.byKey(const Key('createAccountButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('emailField')), 'not-an-email');
    await tester.enterText(find.byKey(const Key('passwordField')), 'short');
    await tester.enterText(find.byKey(const Key('repeatField')), 'other');
    for (final key in ['consentPrivacy', 'consentTerms', 'consentAdult']) {
      await tester.tap(checkbox(key));
    }
    await tester.pump();
    await tester.tap(find.byKey(const Key('signUpSubmit')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Use at least 10 characters'), findsOneWidget);
    expect(find.text('The passwords are not the same'), findsOneWidget);
    expect(accounts.lastConsent, isNull);
  });

  testWidgets('recovery key: Done only after typing the last group, then signed in',
      (tester) async {
    final accounts = await pumpApp(tester);
    await tester.tap(find.byKey(const Key('createAccountButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('emailField')), 'a@b.co');
    await tester.enterText(find.byKey(const Key('passwordField')), 'a long password');
    await tester.enterText(find.byKey(const Key('repeatField')), 'a long password');
    for (final key in ['consentPrivacy', 'consentTerms', 'consentAdult']) {
      await tester.tap(checkbox(key));
    }
    await tester.pump();
    await tester.tap(find.byKey(const Key('signUpSubmit')));
    await tester.pumpAndSettle();

    final last = accounts.recoveryKey.format().split('-').last;
    expect(enabled(tester, 'recoveryDone'), false);
    await tester.enterText(find.byKey(const Key('confirmKeyField')), 'ZZZZ');
    await tester.pump();
    expect(enabled(tester, 'recoveryDone'), false);
    await tester.enterText(find.byKey(const Key('confirmKeyField')), last.toLowerCase());
    await tester.pump();
    expect(enabled(tester, 'recoveryDone'), true);

    await tester.tap(find.byKey(const Key('recoveryDone')));
    await tester.pumpAndSettle();
    expect(find.text('Signed in as a@b.co'), findsOneWidget);
    expect(find.byKey(const Key('serverHolds')), findsOneWidget);
    expect(find.textContaining('Agreed to privacy notice ${privacyNotice.version}'),
        findsOneWidget);
  });

  testWidgets('log in: a wrong password is shown on the screen', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('logInButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('emailField')), 'a@b.co');
    await tester.enterText(find.byKey(const Key('passwordField')), 'wrong one');
    await tester.tap(find.byKey(const Key('logInSubmit')));
    await tester.pumpAndSettle();
    expect(find.text('Wrong email or password'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('passwordField')), 'right password');
    await tester.tap(find.byKey(const Key('logInSubmit')));
    await tester.pumpAndSettle();
    expect(find.text('Signed in as a@b.co'), findsOneWidget);
  });

  testWidgets('the privacy notice and terms open in Arabic', (tester) async {
    await pumpApp(tester, locale: const Locale('ar'));
    await tester.tap(find.byKey(const Key('openPrivacy')));
    await tester.pumpAndSettle();
    expect(find.text(privacyNotice.titleAr), findsOneWidget);
    expect(find.text(privacyNotice.ar.first.title), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('openTerms')));
    await tester.pumpAndSettle();
    expect(find.text(termsOfUse.titleAr), findsOneWidget);
  });

  testWidgets('delete account asks for the password, then signs out',
      (tester) async {
    final accounts = FakeAccounts()..signIn('a@b.co');
    await pumpApp(tester, accounts: accounts);
    await tester.tap(find.byKey(const Key('deleteAccountButton')));
    await tester.pumpAndSettle();
    expect(find.textContaining('withdraws your consent'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('deletePasswordField')), 'my password');
    await tester.tap(find.byKey(const Key('confirmDelete')));
    await tester.pumpAndSettle();
    expect(accounts.deletedWith, 'my password');
    expect(find.text('Account deleted'), findsOneWidget);
    expect(find.byKey(const Key('createAccountButton')), findsOneWidget);
  });

  testWidgets('the account icon shows when you are signed in', (tester) async {
    final accounts = FakeAccounts()..signIn('a@b.co');
    await pumpApp(tester, accounts: accounts);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
  });
}
