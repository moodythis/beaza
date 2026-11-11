import 'package:beaza/data/repositories/account_repository.dart';
import 'package:beaza/data/services/sync_api.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/features/account/legal_text.dart';
import 'package:beaza/ui/features/account/view_models/account_view_model.dart';
import 'package:beaza/ui/features/account/views/account_widgets.dart';
import 'package:beaza/ui/features/account/views/recovery_key_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Email, password, and three separate, unticked agreements: the privacy
/// notice (consent to processing), the terms of use, and the age statement.
/// None of them is pre-ticked or bundled with another (GDPR Art. 7).
/// With [google] the Google account replaces the email and password; the
/// agreements are the same.
class SignUpView extends StatefulWidget {
  const SignUpView({super.key, required this.viewModel, this.google, this.replace = false});

  final AccountViewModel viewModel;
  final GoogleStart? google;

  /// With [google]: the email is held by an account never linked to Google;
  /// the new account replaces it.
  final bool replace;

  @override
  State<SignUpView> createState() => _SignUpViewState();
}

class _SignUpViewState extends State<SignUpView> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _privacy = false;
  bool _terms = false;
  bool _adult = false;

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
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final consent = Consent(
      privacyVersion: privacyNotice.version,
      termsVersion: termsOfUse.version,
      adult: _adult,
    );
    final google = widget.google;
    final key = google != null
        ? await vm.signUpWithGoogle(google, consent, replace: widget.replace)
        : await vm.signUp(
            email: _email.text,
            password: _password.text,
            consent: consent,
          );
    if (key == null || !mounted) return;
    TextInput.finishAutofillContext();
    await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => RecoveryKeyView(recoveryKey: key),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.createAccount)),
      body: ListenableBuilder(
        listenable: vm,
        builder: (context, _) => Form(
          key: _form,
          child: AutofillGroup(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.google case final google?) ...[
                  ListTile(
                    key: const Key('googleAccount'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.account_circle_outlined),
                    title: Text(l10n.googleAccountAs(google.email)),
                  ),
                  Text(l10n.googleSignUpIntro),
                ] else ...[
                  EmailField(controller: _email),
                  const SizedBox(height: 12),
                  PasswordField(
                    key: const Key('passwordField'),
                    controller: _password,
                    label: l10n.passwordLabel,
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
                ],
                const SizedBox(height: 16),
                _Agreement(
                  key: const Key('consentPrivacy'),
                  value: _privacy,
                  onChanged: (v) => setState(() => _privacy = v),
                  text: l10n.consentPrivacy,
                  read: () => openLegal(context, privacyNotice),
                  readLabel: l10n.privacyNotice,
                ),
                _Agreement(
                  key: const Key('consentTerms'),
                  value: _terms,
                  onChanged: (v) => setState(() => _terms = v),
                  text: l10n.consentTerms,
                  read: () => openLegal(context, termsOfUse),
                  readLabel: l10n.termsOfUse,
                ),
                _Agreement(
                  key: const Key('consentAdult'),
                  value: _adult,
                  onChanged: (v) => setState(() => _adult = v),
                  text: l10n.consentAdult,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('signUpSubmit'),
                  onPressed: (_privacy && _terms && _adult && !vm.busy)
                      ? _submit
                      : null,
                  child: Text(l10n.createAccount),
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

class _Agreement extends StatelessWidget {
  const _Agreement({
    super.key,
    required this.value,
    required this.onChanged,
    required this.text,
    this.read,
    this.readLabel,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String text;
  final VoidCallback? read;
  final String? readLabel;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
        value: value,
        onChanged: (v) => onChanged(v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: Text(text),
        subtitle: read == null
            ? null
            : Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: read,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(readLabel!),
                ),
              ),
      );
}
