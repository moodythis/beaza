import 'package:beaza/data/repositories/account_repository.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/features/account/view_models/account_view_model.dart';
import 'package:beaza/ui/features/account/views/account_widgets.dart';
import 'package:beaza/ui/features/account/views/log_in_view.dart';
import 'package:beaza/ui/features/account/views/sign_up_view.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Signed out: what an account is for, and how to make one or log in.
/// Signed in: what the server holds (right of access), log out, and delete
/// the account (right to erasure, withdrawal of consent).
class AccountView extends StatefulWidget {
  const AccountView({super.key, required this.repository});

  final AccountRepository repository;

  @override
  State<AccountView> createState() => _AccountViewState();
}

class _AccountViewState extends State<AccountView> {
  late final AccountViewModel vm = AccountViewModel(widget.repository);

  bool _loadScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_maybeLoadInfo);
    vm.addListener(_maybeLoadInfo);
    _maybeLoadInfo();
  }

  @override
  void dispose() {
    widget.repository.removeListener(_maybeLoadInfo);
    vm.removeListener(_maybeLoadInfo);
    vm.dispose();
    super.dispose();
  }

  bool get _needsInfo =>
      widget.repository.signedIn &&
      vm.info == null &&
      !vm.busy &&
      vm.failure == null;

  /// Loads what the server holds once signed in: on opening the screen, and
  /// right after sign-up or log-in finish (the view model is busy during
  /// those, so this waits for it to be free).
  void _maybeLoadInfo() {
    if (_loadScheduled || !_needsInfo) return;
    _loadScheduled = true;
    Future.microtask(() {
      _loadScheduled = false;
      if (mounted && _needsInfo) vm.loadInfo();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountTitle)),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.repository, vm]),
        builder: (context, _) => widget.repository.signedIn
            ? _signedIn(context, l10n)
            : _signedOut(context, l10n),
      ),
    );
  }

  Widget _signedOut(BuildContext context, AppLocalizations l10n) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Icon(Icons.lock_outline,
              size: 40, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(l10n.accountIntro, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('createAccountButton'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => SignUpView(viewModel: vm),
            )),
            child: Text(l10n.createAccount),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('logInButton'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<bool>(
              builder: (_) => LogInView(viewModel: vm),
            )),
            child: Text(l10n.logIn),
          ),
          const SizedBox(height: 16),
          const LegalLinks(),
        ],
      );

  Widget _signedIn(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final info = vm.info;
    final dates = DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.account_circle_outlined),
          title: Text(l10n.signedInAs(widget.repository.current!.email)),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              key: const Key('serverHolds'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.serverHoldsTitle, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (info != null) ...[
                  Text(l10n.memberSince(dates.format(info.createdAt.toLocal()))),
                  if (info.consentAt != null)
                    Text(l10n.consentGiven(
                      info.privacyVersion ?? '-',
                      info.termsVersion ?? '-',
                      dates.format(info.consentAt!.toLocal()),
                    )),
                  Text(l10n.encryptedRecords(info.encryptedRecords)),
                ] else
                  AccountStatus(viewModel: vm),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.syncNext, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        const LegalLinks(),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('logOutButton'),
          onPressed: vm.busy ? null : vm.logOut,
          child: Text(l10n.logOut),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('deleteAccountButton'),
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          onPressed: vm.busy ? null : () => _delete(context, l10n),
          child: Text(l10n.deleteAccount),
        ),
        if (info != null) AccountStatus(viewModel: vm),
      ],
    );
  }

  Future<void> _delete(BuildContext context, AppLocalizations l10n) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteDialog(),
    );
    if (password == null || password.isEmpty) return;
    final ok = await vm.deleteAccount(password);
    if (ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.accountDeleted)));
    }
  }
}

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog();

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = Theme.of(context).colorScheme.error;
    return AlertDialog(
      title: Text(l10n.deleteAccount),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.deleteAccountBody),
          const SizedBox(height: 12),
          PasswordField(
            key: const Key('deletePasswordField'),
            controller: _password,
            label: l10n.passwordLabel,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const Key('confirmDelete'),
          style: TextButton.styleFrom(foregroundColor: error),
          onPressed: () => Navigator.of(context).pop(_password.text),
          child: Text(l10n.deleteAccount),
        ),
      ],
    );
  }
}
