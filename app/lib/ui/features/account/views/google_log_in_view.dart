import 'package:beaza/data/repositories/account_repository.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/features/account/view_models/account_view_model.dart';
import 'package:beaza/ui/features/account/views/account_widgets.dart';
import 'package:flutter/material.dart';

/// Logging in to a Google account on this phone. Google has confirmed the
/// person; the recovery key opens their data (it is the only lock on a
/// Google account, and the server never sees it).
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

  AccountViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.forgetFailure();
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final ok = await vm.logInWithGoogle(widget.start, _key.text);
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
              Text(l10n.googleLogInIntro),
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
