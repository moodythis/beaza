import 'dart:async';

import 'package:beaza/data/services/media_ai_api.dart';
import 'package:beaza/data/services/voice_input.dart';
import 'package:beaza/ui/core/media_consent.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/category_style.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/features/home/view_models/home_view_model.dart';
import 'package:flutter/material.dart';
import 'package:beaza_assistant/beaza_assistant.dart' show DraftTransaction;
import 'package:flutter/services.dart';

/// Type or say cash expenses in everyday words; they are read on the phone
/// (beaza_assistant) and only saved when the person taps Add. With voice,
/// listening starts as soon as the sheet opens.
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

  /// Words heard so far while listening.
  String _partial = '';
  StreamSubscription<String>? _partials;

  /// Photos and voice with AI: on after the person agreed.
  bool _aiOn = false;

  /// Waiting for the AI to write down or understand what was said.
  bool _aiBusy = false;

  /// What the AI understood, for the text it was given; typing anything
  /// else goes back to the phone's own reading.
  List<DraftTransaction>? _aiDrafts;
  String? _aiText;

  bool get _canAi =>
      widget.viewModel.mediaAi != null && widget.viewModel.mediaConsent != null;

  @override
  void initState() {
    super.initState();
    // Whether to record for the AI or use the phone's speech service is
    // known only once the consent is read; listening starts after that.
    final consent = widget.viewModel.mediaConsent?.isOn() ?? Future.value(false);
    final voice = widget.viewModel.voice;
    if (voice != null) {
      _partials = voice.partials.listen((p) {
        if (mounted && _listening) setState(() => _partial = p);
      }, onError: (Object _) {});
    }
    consent.then((on) {
      if (!mounted) return;
      setState(() => _aiOn = on && _canAi);
      if (voice != null) _speak();
    }, onError: (Object _) {
      if (mounted && voice != null) _speak();
    });
  }

  @override
  void dispose() {
    _partials?.cancel();
    if (_listening) {
      if (_aiOn) {
        widget.viewModel.recorder?.cancel();
      } else {
        widget.viewModel.voice?.stop();
      }
    }
    _text.dispose();
    super.dispose();
  }

  String get _lang => _arabicSpeech ? 'ar' : 'en';

  /// With AI on: record, then the AI writes it down and finds the expenses.
  Future<void> _record() async {
    final recorder = widget.viewModel.recorder!;
    final ai = widget.viewModel.mediaAi!;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!_listening) {
      try {
        await recorder.start();
        setState(() => _listening = true);
      } on PlatformException catch (e) {
        messenger.showSnackBar(SnackBar(
            content: Text(e.code == 'no_permission'
                ? l10n.voiceNoPermission
                : l10n.voiceUnavailable)));
      }
      return;
    }
    setState(() {
      _listening = false;
      _aiBusy = true;
    });
    try {
      final audio = await recorder.stop();
      if (audio == null) return;
      final heard = await ai.readVoice(audio, _lang);
      if (!mounted) return;
      if (heard.text.trim().isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.aiHeardNothing)));
        return;
      }
      final before = _text.text.trim();
      _text.text = before.isEmpty ? heard.text : '$before\n${heard.text}';
      _useAiDrafts(heard.drafts);
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.aiFailed)));
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  /// With AI on: what was typed (or said) understood by the AI.
  Future<void> _understand() async {
    final ai = widget.viewModel.mediaAi;
    final text = _text.text.trim();
    if (ai == null || text.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _aiBusy = true);
    try {
      _useAiDrafts(await ai.readExpenses(text, _lang));
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l10n.aiFailed)));
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  void _useAiDrafts(List<AiDraft> drafts) {
    final now = widget.viewModel.now();
    setState(() {
      _aiText = _text.text;
      _aiDrafts = [
        for (final d in drafts)
          DraftTransaction(
            amountFils: d.fils,
            timestamp: now,
            merchantRaw: d.item.isEmpty ? null : d.item,
            category: d.category,
          ),
      ];
    });
  }

  Future<void> _speak() async {
    if (_aiOn && _canAi && widget.viewModel.recorder != null) return _record();
    final voice = widget.viewModel.voice;
    if (voice == null) return;
    if (_listening) {
      // Second tap: done talking.
      await voice.stop();
      return;
    }
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final language = speechLanguage(_arabicSpeech ? 'ar' : 'en');
    setState(() {
      _listening = true;
      _partial = '';
    });
    try {
      final said = await voice.listen(language: language);
      if (said != null && said.trim().isNotEmpty) {
        final before = _text.text.trim();
        // A new line per recording: each one is its own item.
        _text.text = before.isEmpty ? said : '$before\n$said';
      }
    } on PlatformException catch (e) {
      final message = switch (e.code) {
        'no_permission' => l10n.voiceNoPermission,
        'network' => l10n.voiceNetwork,
        _ => l10n.voiceUnavailable,
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          _listening = false;
          _partial = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final fromAi = _aiDrafts != null && _aiText == _text.text;
    final drafts =
        fromAi ? _aiDrafts! : widget.viewModel.draftsFrom(_text.text);
    final total = drafts.fold<int>(0, (a, d) => a + d.amountFils);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
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
            ),
          ),
          if (widget.viewModel.voice != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const Key('quickAddSpeak'),
              onPressed: _speak,
              style: _listening
                  ? FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.errorContainer,
                      foregroundColor: theme.colorScheme.onErrorContainer,
                    )
                  : null,
              icon: Icon(_listening ? Icons.stop_circle_outlined : Icons.mic),
              label: Text(_listening
                  ? (_aiOn ? l10n.aiRecording : l10n.quickAddListening)
                  : l10n.quickAddSpeak),
            ),
            if (_aiBusy)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(key: Key('aiBusy')),
              ),
            if (_listening && _partial.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _partial,
                  key: const Key('quickAddPartial'),
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontStyle: FontStyle.italic),
                ),
              ),
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
            Text(_aiOn ? l10n.aiVoicePrivacy : l10n.quickAddPrivacy,
                style: theme.textTheme.bodySmall),
          ],
          if (_canAi) ...[
            MediaAiSwitch(
              consent: widget.viewModel.mediaConsent!,
              onChanged: (on) => setState(() => _aiOn = on),
            ),
            if (_aiOn && _text.text.trim().isNotEmpty && !fromAi)
              OutlinedButton.icon(
                key: const Key('quickAddAi'),
                onPressed: _aiBusy ? null : _understand,
                icon: const Icon(Icons.auto_awesome),
                label: Text(l10n.aiUnderstand),
              ),
          ],
          if (fromAi)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(l10n.aiDraftsNote,
                  key: const Key('aiDraftsNote'),
                  style: theme.textTheme.bodySmall),
            ),
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
      ),
    );
  }
}
