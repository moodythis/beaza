import 'package:beaza/data/repositories/account_repository.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/features/account/view_models/account_view_model.dart';
import 'package:beaza/ui/features/account/views/account_widgets.dart';
import 'package:flutter/material.dart';

/// Logging in with Google on this phone. Google has confirmed the person;
/// their data still needs its own key, which the server never has: the
/// password when the account has one (an email account with the same Gmail
/// is linked this way), otherwise the recovery key.
class GoogleLogInView extends StatefulWidget {
  const GoogleLogInView({
    super.key,
    required this.viewModel,
    required this.start,
  });

  final AccountViewModel viewModel;
  final GoogleStart start;

  @override
  State<GoogleLogInView> createState() => _GoogleLogInViewState();
}

class _GoogleLogInViewState extends State<GoogleLogInView> {
  final _form = GlobalKey<FormState>();
  final _key = TextEditingController();
  final _password = TextEditingController();

  /// Password accounts may use the recovery key instead (forgot password).
  late bool _usePassword = widget.start.hasPassword;

  AccountViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.forgetFailure();
  }

  @override
  void dispose() {
    _key.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final ok = _usePassword
        ? await vm.logInWithGoogle(widget.start, password: _password.text)
        : await vm.logInWithGoogle(widget.start, recoveryKey: _key.text);
    if (ok && mounted) Navigator.of(context).pop(true);
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
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(l10n.googleAccountAs(widget.start.email)),
              ),
              Text(_usePassword
                  ? l10n.googlePasswordIntro
                  : l10n.googleLogInIntro),
              const SizedBox(height: 12),
              if (_usePassword)
                PasswordField(
                  key: const Key('passwordField'),
                  controller: _password,
                  label: l10n.passwordLabel,
                  validator: (v) =>
                      (v ?? '').isEmpty ? l10n.passwordTooShort : null,
                )
              else
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
              if (widget.start.hasPassword)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: const Key('switchKeyType'),
                    onPressed: () => setState(() {
                      _usePassword = !_usePassword;
                      vm.forgetFailure();
                    }),
                    child: Text(_usePassword
                        ? l10n.useRecoveryKeyInstead
                        : l10n.usePasswordInstead),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('googleLogInSubmit'),
                onPressed: vm.busy ? null : _submit,
                child: Text(l10n.logIn),
              ),
              const SizedBox(height: 12),
              AccountStatus(viewModel: vm),
            ],
          ),
        ),
      ),
    );
  }
}
