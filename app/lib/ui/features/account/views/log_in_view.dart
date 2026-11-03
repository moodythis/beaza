import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/features/account/view_models/account_view_model.dart';
import 'package:beaza/ui/features/account/views/account_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LogInView extends StatefulWidget {
  const LogInView({super.key, required this.viewModel});

  final AccountViewModel viewModel;

  @override
  State<LogInView> createState() => _LogInViewState();
}

class _LogInViewState extends State<LogInView> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  AccountViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.forgetFailure();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final ok = await vm.logIn(email: _email.text, password: _password.text);
    if (ok && mounted) {
      TextInput.finishAutofillContext();
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _forgot() async {
    final recovered = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => RecoverView(viewModel: vm)),
    );
    if (recovered == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.logIn)),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => Form(
          key: _form,
          child: AutofillGroup(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                EmailField(controller: _email),
                const SizedBox(height: 12),
                PasswordField(
                  key: const Key('passwordField'),
                  controller: _password,
                  label: l10n.passwordLabel,
                  validator: (v) =>
                      (v ?? '').isEmpty ? l10n.passwordTooShort : null,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('logInSubmit'),
                  onPressed: vm.busy ? null : _submit,
                  child: Text(l10n.logIn),
                ),
                TextButton(
                  key: const Key('forgotPassword'),
                  onPressed: vm.busy ? null : _forgot,
                  child: Text(l10n.forgotPassword),
                ),
                const SizedBox(height: 12),
                AccountStatus(viewModel: vm, busyText: l10n.makingKeys),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Forgot the password: recovery key plus a new password.
class RecoverView extends StatefulWidget {
  const RecoverView({super.key, required this.viewModel});

  final AccountViewModel viewModel;

  @override
  State<RecoverView> createState() => _RecoverViewState();
}

class _RecoverViewState extends State<RecoverView> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _key = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();

  AccountViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.forgetFailure();
  }

  @override
  void dispose() {
    for (final c in [_email, _key, _password, _repeat]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final ok = await vm.recover(
      email: _email.text,
      recoveryKey: _key.text,
      newPassword: _password.text,
    );
    if (ok && mounted) {
      TextInput.finishAutofillContext();
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.recoverTitle)),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => Form(
          key: _form,
          child: AutofillGroup(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(l10n.recoverIntro),
                const SizedBox(height: 12),
                EmailField(controller: _email),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('recoveryKeyField'),
                  controller: _key,
                  autocorrect: false,
                  enableSuggestions: false,
                  textDirection: TextDirection.ltr,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: l10n.recoveryKeyLabel,
                    hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? l10n.errorKeyFormat : null,
                ),
                const SizedBox(height: 12),
                PasswordField(
                  key: const Key('passwordField'),
                  controller: _password,
                  label: l10n.newPasswordLabel,
                  helper: l10n.passwordHelp,
                  autofillHint: AutofillHints.newPassword,
                  validator: (v) => validatePassword(l10n, v),
                ),
                const SizedBox(height: 12),
                PasswordField(
                  key: const Key('repeatField'),
                  controller: _repeat,
                  label: l10n.repeatPasswordLabel,
                  autofillHint: AutofillHints.newPassword,
                  validator: (v) =>
                      v == _password.text ? null : l10n.passwordsDiffer,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('recoverSubmit'),
                  onPressed: vm.busy ? null : _submit,
                  child: Text(l10n.recoverButton),
                ),
                const SizedBox(height: 12),
                AccountStatus(viewModel: vm, busyText: l10n.makingKeys),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
