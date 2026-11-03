import 'package:beaza/data/repositories/account_repository.dart';
import 'package:beaza/data/repositories/sync_repository.dart';
import 'package:beaza/domain/use_cases/data_export.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/features/account/view_models/account_view_model.dart';
import 'package:beaza/ui/features/account/views/account_widgets.dart';
import 'package:beaza/ui/features/account/views/google_log_in_view.dart';
import 'package:beaza/ui/features/account/views/log_in_view.dart';
import 'package:beaza/ui/features/account/views/sign_up_view.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Signed out: what an account is for, and how to make one or log in.
/// Signed in: sync status, what the server holds (right of access), log
/// out, and delete the account (right to erasure, withdrawal of consent).
class AccountView extends StatefulWidget {
  const AccountView({
    super.key,
    required this.repository,
    this.sync,
    this.export,
  });

  final AccountRepository repository;

  /// Null hides the sync section (tests of the account alone).
  final SyncRepository? sync;

  /// Saves a copy of all data to a file; null hides the card.
  final DataExport? export;

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
          if (widget.repository.googleAvailable) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('googleButton'),
              onPressed: vm.busy ? null : () => _google(context),
              icon: const Icon(Icons.g_mobiledata, size: 28),
              label: Text(l10n.continueWithGoogle),
            ),
            const SizedBox(height: 8),
            AccountStatus(viewModel: vm),
          ],
          const SizedBox(height: 16),
          const LegalLinks(),
          if (widget.sync case final sync?) OtherPhonesCard(sync: sync),
          if (widget.export case final export?) ...[
            const SizedBox(height: 8),
            ExportCard(export: export),
          ],
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
        if (widget.sync case final sync?) ...[
          const SizedBox(height: 8),
          SyncSection(
            sync: sync,
            onSynced: vm.loadInfo,
            onLogOut: vm.busy ? null : vm.logOut,
          ),
        ],
        if (widget.export case final export?) ...[
          const SizedBox(height: 8),
          ExportCard(export: export),
        ],
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

  /// Google's picker, then log in (account exists) or sign up.
  Future<void> _google(BuildContext context) async {
    final start = await vm.startGoogle();
    if (start == null || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => start.exists
          ? GoogleLogInView(viewModel: vm, start: start)
          : SignUpView(viewModel: vm, google: start),
    ));
  }

  Future<void> _delete(BuildContext context, AppLocalizations l10n) async {
    if (widget.repository.current?.google ?? false) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.deleteAccount),
          content: Text(l10n.deleteGoogleConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            TextButton(
              key: const Key('deleteGoogleConfirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.deleteAccount),
            ),
          ],
        ),
      );
      if (sure != true) return;
      final ok = await vm.deleteGoogleAccount();
      if (ok && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.accountDeleted)));
      }
      return;
    }
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

/// When this phone last synced, why the last sync failed, and a button to
/// sync now.
class SyncSection extends StatelessWidget {
  const SyncSection({
    super.key,
    required this.sync,
    this.onSynced,
    this.onLogOut,
  });

  final SyncRepository sync;

  /// Called after a sync started with the button succeeds.
  final VoidCallback? onSynced;

  /// "Log out instead" when asked whether to add this phone's data.
  final VoidCallback? onLogOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final merge = sync.mergeCount;
        if (merge != null) return _askMerge(context, l10n, merge);
        final failure = sync.failure;
        final last = sync.lastSynced;
        final Widget status;
        if (sync.syncing) {
          status = Row(children: [
            const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text(l10n.syncing),
          ]);
        } else if (failure != null) {
          status = Text(
            l10n.syncFailed(accountProblemText(l10n, failure)),
            style: TextStyle(color: theme.colorScheme.error),
          );
        } else if (last != null) {
          status = Text(l10n.lastSynced(
              DateFormat.yMMMd(locale).add_jm().format(last.toLocal())));
        } else {
          status = Text(l10n.notSyncedYet);
        }
        return Column(
          key: const Key('syncSection'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.syncExplain, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            KeyedSubtree(key: const Key('syncStatus'), child: status),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('syncNowButton'),
              icon: const Icon(Icons.sync),
              label: Text(l10n.syncNow),
              onPressed: sync.syncing
                  ? null
                  : () async {
                      if (await sync.syncNow()) onSynced?.call();
                    },
            ),
          ],
        );
      },
    );
  }

  /// Asked once when this phone holds data and was signed in to an account
  /// it never synced with. Nothing is sent or fetched until the answer.
  Widget _askMerge(BuildContext context, AppLocalizations l10n, int count) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('mergeCard'),
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.mergeTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(l10n.mergeBody(count)),
            const SizedBox(height: 4),
            Text(l10n.mergeWarning, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('mergeConfirm'),
              onPressed: () async {
                if (await sync.approveMerge()) onSynced?.call();
              },
              child: Text(l10n.mergeConfirm),
            ),
            const SizedBox(height: 4),
            OutlinedButton(
              key: const Key('mergeLogOut'),
              onPressed: onLogOut,
              child: Text(l10n.mergeLogOut),
            ),
          ],
        ),
      ),
    );
  }
}

/// Signed out: offers to remove, from this phone only, transactions that
/// came from other phones (the undo for signing in to the wrong account).
/// Hidden when there are none.
class OtherPhonesCard extends StatefulWidget {
  const OtherPhonesCard({super.key, required this.sync});

  final SyncRepository sync;

  @override
  State<OtherPhonesCard> createState() => _OtherPhonesCardState();
}

class _OtherPhonesCardState extends State<OtherPhonesCard> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    widget.sync.countFromOtherPhones().then((n) {
      if (mounted) setState(() => _count = n);
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        key: const Key('otherPhonesCard'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.otherPhonesBody(_count)),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('removeOtherPhones'),
                style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error),
                onPressed: () => _remove(context, l10n),
                child: Text(l10n.removeOtherPhones),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _remove(BuildContext context, AppLocalizations l10n) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.removeOtherPhonesConfirm(_count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('confirmRemoveOtherPhones'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.removeOtherPhones),
          ),
        ],
      ),
    );
    if (sure != true) return;
    final removed = await widget.sync.removeFromOtherPhones();
    if (!mounted) return;
    setState(() => _count = 0);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.removedOtherPhones(removed))));
    }
  }
}

/// Right to a copy of one's data: saves every transaction and the settings
/// as a JSON file the person chooses where to keep. Works signed in or out.
class ExportCard extends StatefulWidget {
  const ExportCard({super.key, required this.export});

  final DataExport export;

  @override
  State<ExportCard> createState() => _ExportCardState();
}

class _ExportCardState extends State<ExportCard> {
  bool _busy = false;

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    bool? saved;
    try {
      saved = await widget.export.save();
    } on Exception {
      saved = null;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    // Cancelling the save dialog is not a failure: say nothing.
    if (saved == false) return;
    messenger.showSnackBar(SnackBar(
      content: Text(saved == true ? l10n.exportSaved : l10n.exportFailed),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      key: const Key('exportCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.exportTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(l10n.exportBody),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('exportButton'),
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.download_outlined),
              label: Text(l10n.exportButton),
            ),
          ],
        ),
      ),
    );
  }
}
