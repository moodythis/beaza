import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:flutter/services.dart';

/// "Did you decide?" when a 24-hour hold ends. Scheduled on the phone with
/// Android's alarm; nothing leaves the phone.
abstract class HoldReminders {
  Future<void> schedule(Hold hold);
  Future<void> cancel(Hold hold);
}

/// The notification id of a hold's reminder, apart from the guardrail's.
int reminderId(Hold h) => 100000 + (h.id.hashCode & 0x3fffff);

/// The reminder's words, in the app's language.
(String, String) reminderText(Hold h, String language) {
  final f = h.amountFils;
  final amount = '${f ~/ 1000}.${(f % 1000).toString().padLeft(3, '0')}';
  final name = h.name.isEmpty ? (language == 'ar' ? 'الشي' : 'it') : h.name;
  return language == 'ar'
      ? ('قرّرت؟', 'خلصت 24 ساعة على $name ($amount د.ب). اشتريته ولا تركته؟ قرّر من التوفير.')
      : ('Did you decide?', '24 hours are up for $name (BHD $amount). Bought it or skipped it? Decide in Saving.');
}

class PlatformHoldReminders implements HoldReminders {
  PlatformHoldReminders(this.language, {this.askPermission});

  static const _channel = MethodChannel('beaza/notify');

  /// The app's language code now ('ar' or 'en').
  final String Function() language;

  /// Asks Android 13+ for the notification permission first.
  final Future<bool> Function()? askPermission;

  @override
  Future<void> schedule(Hold hold) async {
    await askPermission?.call();
    final (title, body) = reminderText(hold, language());
    await _channel.invokeMethod<void>('schedule', {
      'id': reminderId(hold),
      'atMs': hold.createdAt.add(kCoolingOff).millisecondsSinceEpoch,
      'title': title,
      'body': body,
    });
  }

  @override
  Future<void> cancel(Hold hold) =>
      _channel.invokeMethod<void>('cancel', {'id': reminderId(hold)});
}
