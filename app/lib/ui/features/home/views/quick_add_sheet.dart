import 'package:beaza/data/services/voice_input.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/category_style.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Type or say cash expenses in everyday words; they are read on the phone
/// (beaza_assistant) and only saved when the person taps Add.
Future<void> showQuickAdd(BuildContext context, HomeViewModel viewModel) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => QuickAddSheet(viewModel: viewModel),
    );

class QuickAddSheet extends StatefulWidget {
  const QuickAddSheet({super.key, required this.viewModel});

  final HomeViewModel viewModel;

  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  final TextEditingController _text = TextEditingController();
  bool _listening = false;

  /// Speech is Bahraini Arabic unless the person switches to English; the
  /// app's own language does not decide it (an English screen made Google
  /// hear "كرك بربيتين" as "Karak do Rupaiya").
  bool _arabicSpeech = true;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _speak() async {
    final voice = widget.viewModel.voice;
    if (voice == null || _listening) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final language = speechLanguage(_arabicSpeech ? 'ar' : 'en');
    setState(() => _listening = true);
    try {
      final said = await voice.listen(language: language);
      if (said != null && said.trim().isNotEmpty) {
        final before = _text.text.trim();
        // A new line per recording: each one is its own item.
        _text.text = before.isEmpty ? said : '$before\n$said';
      }
    } on PlatformException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.voiceUnavailable)));
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final drafts = widget.viewModel.draftsFrom(_text.text);
    final total = drafts.fold<int>(0, (a, d) => a + d.amountFils);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.quickAddTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            key: const Key('quickAddText'),
            controller: _text,
            autofocus: widget.viewModel.voice == null,
            minLines: 1,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: l10n.quickAddHint,
              border: const OutlineInputBorder(),
              suffixIcon: widget.viewModel.voice == null
                  ? null
                  : IconButton(
                      key: const Key('quickAddSpeak'),
                      tooltip: l10n.quickAddSpeak,
                      icon: Icon(_listening
                          ? Icons.hearing
                          : Icons.keyboard_voice_outlined),
                      onPressed: _speak,
                    ),
            ),
          ),
          if (widget.viewModel.voice != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l10n.quickAddSpeechLanguage,
                    style: theme.textTheme.bodySmall),
                ChoiceChip(
                  key: const Key('speechArabic'),
                  label: const Text('عربي'),
                  selected: _arabicSpeech,
                  onSelected: (_) => setState(() => _arabicSpeech = true),
                ),
                ChoiceChip(
                  key: const Key('speechEnglish'),
                  label: const Text('English'),
                  selected: !_arabicSpeech,
                  onSelected: (_) => setState(() => _arabicSpeech = false),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(l10n.quickAddPrivacy, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          if (drafts.isEmpty && _text.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l10n.quickAddNone, key: const Key('quickAddNone')),
            ),
          for (var i = 0; i < drafts.length; i++)
            ListTile(
              key: Key('draft_$i'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(categoryIcon(drafts[i].category ?? 'unsorted')),
              title: Text(drafts[i].merchantRaw ?? l10n.quickAddUnnamed),
              subtitle: drafts[i].amountGuessed ? Text(l10n.quickAddCheck) : null,
              trailing: Text(l10n.bhd(formatFils(drafts[i].amountFils)),
                  style: theme.textTheme.titleSmall),
            ),
          if (drafts.length > 1)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(l10n.quickAddTotal(l10n.bhd(formatFils(total)))),
            ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('quickAddSave'),
            onPressed: drafts.isEmpty
                ? null
                : () async {
                    final navigator = Navigator.of(context);
                    await widget.viewModel.addDrafts(drafts);
                    navigator.pop();
                  },
            child: Text(l10n.quickAddSave),
          ),
        ],
      ),
    );
  }
}
