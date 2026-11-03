/// The language model behind an interface, so the app can plug in a hosted
/// model (through Beaza's server, so no key is on the phone) and tests use
/// [MockLlmClient]. With no client, or no consent, the assistant answers
/// with its own sentences.
library;

import 'dart:async';
import 'dart:convert';

import 'text.dart';

class LlmPrompt {
  const LlmPrompt({required this.system, required this.context});

  final String system;

  /// From AiContextSanitizer.context: nothing else is sent.
  final Map<String, Object?> context;

  String get contextJson => jsonEncode(context);
}

abstract interface class AiLlmClient {
  /// The model's reply text. May throw; the assistant then answers locally.
  Future<String> complete(LlmPrompt prompt);
}

/// Answers with a fixed function and remembers every prompt (for tests).
class MockLlmClient implements AiLlmClient {
  MockLlmClient(this.answer);

  final FutureOr<String> Function(LlmPrompt prompt) answer;
  final List<LlmPrompt> prompts = [];

  @override
  Future<String> complete(LlmPrompt prompt) async {
    prompts.add(prompt);
    return answer(prompt);
  }
}

/// The model may only reword. Every number in its reply must already be in
/// [allowedFrom] (the metrics' display text, the draft reply and the
/// question); otherwise the reply is thrown away.
class NumberGuard {
  const NumberGuard({this.maxLength = 400});

  final int maxLength;

  static final RegExp _num = RegExp(r'\d+(?:\.\d+)?');

  static Set<String> numbersIn(String text) =>
      {for (final m in _num.allMatches(normalizeText(text))) _canon(m[0]!)};

  /// "2.500" and "2.5" are the same number; "07" and "7" too.
  static String _canon(String n) {
    if (!n.contains('.')) return int.parse(n).toString();
    var s = n.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    final p = s.split('.');
    final whole = int.parse(p[0]).toString();
    return p.length == 1 ? whole : '$whole.${p[1]}';
  }

  bool allows(String reply, Iterable<String> allowedFrom) {
    final r = reply.trim();
    if (r.isEmpty || r.length > maxLength) return false;
    final allowed = <String>{};
    for (final a in allowedFrom) {
      allowed.addAll(numbersIn(a));
    }
    return numbersIn(r).every(allowed.contains);
  }
}
