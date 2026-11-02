import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/features/review/view_models/review_view_model.dart';
import 'package:flutter/material.dart';

/// Bank messages that could not be read safely, with the reason. Shown only
/// on this phone; nothing is saved or sent.
class ReviewView extends StatefulWidget {
  const ReviewView({super.key, required this.viewModel});

  final ReviewViewModel viewModel;

  @override
  State<ReviewView> createState() => _ReviewViewState();
}

class _ReviewViewState extends State<ReviewView> {
  @override
  void dispose() {
    widget.viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.reviewTitle)),
      body: ListenableBuilder(
        listenable: widget.viewModel,
        builder: (context, _) {
          final items = widget.viewModel.items;
          if (widget.viewModel.failed) {
            return Center(child: Text(l10n.loadError));
          }
          if (items == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(l10n.reviewNote, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(l10n.reviewEmpty, textAlign: TextAlign.center),
                ),
              for (final m in items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${m.sender} · ${formatBahrainTime(m.receivedAt)}',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.reviewReasons(m.reasons.join(', ')),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.error),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          m.text,
                          textDirection: TextDirection.ltr,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
