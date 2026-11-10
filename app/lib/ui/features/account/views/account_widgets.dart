import 'package:beaza/data/repositories/account_repository.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/features/account/legal_text.dart';
import 'package:beaza/ui/features/account/view_models/account_view_model.dart';
import 'package:flutter/material.dart';

final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
const int minPasswordLength = 10;

String? validateEmail(AppLocalizations l10n, String? value) =>
    _emailPattern.hasMatch((value ?? '').trim()) ? null : l10n.invalidEmail;

String? validatePassword(AppLocalizations l10n, String? value) =>
    (value ?? '').length >= minPasswordLength ? null : l10n.passwordTooShort;

String accountProblemText(AppLocalizations l10n, AccountFailure failure) =>
    switch (failure.problem) {
      AccountProblem.wrongCredentials => l10n.errorWrongCredentials,
      AccountProblem.emailTaken => l10n.errorEmailTaken,
      AccountProblem.rateLimited => l10n.errorRateLimited(
          ((failure.retryAfterSeconds ?? 60) / 60).ceil()),
      AccountProblem.network => l10n.errorNetwork,
      AccountProblem.weakServerSettings => l10n.errorWeakServer,
      AccountProblem.recoveryKeyTypo => l10n.errorKeyTypo,
      AccountProblem.recoveryKeyFormat => l10n.errorKeyFormat,
      AccountProblem.wrongRecoveryKey => l10n.errorWrongKey,
      AccountProblem.documentsOutdated => l10n.errorOutdated,
      AccountProblem.sessionExpired => l10n.errorSessionExpired,
      AccountProblem.google => failure.code == null
          ? l10n.errorGoogle
          : '${l10n.errorGoogle} (${failure.code})',
      AccountProblem.server => failure.code == null
          ? l10n.errorServer
          : '${l10n.errorServer} (${failure.code})',
    };

/// Progress line while busy, or the reason the last action failed.
class AccountStatus extends StatelessWidget {
  const AccountStatus({super.key, required this.viewModel, this.busyText});

  final AccountViewModel viewModel;
  final String? busyText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final failure = viewModel.failure;
    if (viewModel.busy) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LinearProgressIndicator(),
          if (busyText != null) ...[
            const SizedBox(height: 8),
            Text(busyText!, textAlign: TextAlign.center),
          ],
        ],
      );
    }
    if (failure == null) return const SizedBox.shrink();
    return Text(
      accountProblemText(l10n, failure),
      key: const Key('accountError'),
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}

/// A password box with a show/hide button.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.helper,
    this.validator,
    this.autofillHint = AutofillHints.password,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final FormFieldValidator<String>? validator;
  final String autofillHint;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controller,
        obscureText: _hidden,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: [widget.autofillHint],
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helper,
          helperMaxLines: 3,
          suffixIcon: IconButton(
            icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _hidden = !_hidden),
          ),
        ),
        validator: widget.validator,
      );
}

class EmailField extends StatelessWidget {
  const EmailField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextFormField(
      key: const Key('emailField'),
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      autofillHints: const [AutofillHints.email],
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(labelText: l10n.emailLabel),
      validator: (v) => validateEmail(l10n, v),
    );
  }
}

/// Links to the privacy notice and the terms of use.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        TextButton(
          key: const Key('openPrivacy'),
          onPressed: () => openLegal(context, privacyNotice),
          child: Text(l10n.privacyNotice),
        ),
        TextButton(
          key: const Key('openTerms'),
          onPressed: () => openLegal(context, termsOfUse),
          child: Text(l10n.termsOfUse),
        ),
      ],
    );
  }
}

/// Opens [document], scrolled to its section number [section] (0-based,
/// the same in both languages) when given.
Future<void> openLegal(
  BuildContext context,
  LegalDocument document, {
  int? section,
}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LegalView(document: document, section: section),
    ));

/// Where each optional AI feature is explained in the privacy notice.
const int kPrivacyCoachSection = 4;
const int kPrivacyMediaSection = 6;

/// Where the online leaderboard is explained.
const int kPrivacyBoardSection = 7;

/// The full text of the privacy notice or the terms, in the app's language.
/// Readable before agreeing, without internet.
class LegalView extends StatefulWidget {
  const LegalView({super.key, required this.document, this.section});

  final LegalDocument document;
  final int? section;

  @override
  State<LegalView> createState() => _LegalViewState();
}

class _LegalViewState extends State<LegalView> {
  final _target = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.section != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _target.currentContext;
        if (c != null) Scrollable.ensureVisible(c);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final document = widget.document;
    final sections = document.sections(language);
    return Scaffold(
      appBar: AppBar(title: Text(document.title(language))),
      // A Column, not a lazy ListView, so the section to jump to is built.
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.legalVersion(document.version), style: text.bodySmall),
          for (final (i, section) in sections.indexed) ...[
            const SizedBox(height: 20),
            Text(
              section.title,
              key: i == widget.section ? _target : null,
              style: text.titleMedium,
            ),
            for (final p in section.paragraphs)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(p, style: text.bodyMedium?.copyWith(height: 1.5)),
              ),
          ],
        ],
        ),
      ),
    );
  }
}
