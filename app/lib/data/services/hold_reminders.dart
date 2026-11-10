import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:beaza/domain/use_cases/daily_close.dart';
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

/// The next Saturday 21:00 Bahrain time (the end of Bahrain's week) after
/// [now], as a UTC instant.
DateTime nextWeekEnd(DateTime now) {
  final local = now.toUtc().add(const Duration(hours: 3));
  var d = DateTime.utc(local.year, local.month, local.day, 21);
  while (d.weekday != DateTime.saturday || !d.isAfter(local)) {
    d = d.add(const Duration(days: 1));
  }
  return d.subtract(const Duration(hours: 3));
}

/// "Your weekly report is ready", each Saturday at 21:00. Set again every
/// time the app opens, so it moves to the next week by itself. The amounts
/// are not in it: they are not known when the alarm is set, and the lock
/// screen is no place for them.
Future<void> scheduleWeeklyReport(String language, {DateTime? now}) async {
  final ar = language == 'ar';
  await const MethodChannel('beaza/notify').invokeMethod<void>('schedule', {
    'id': 99,
    'atMs': nextWeekEnd(now ?? DateTime.now()).millisecondsSinceEpoch,
    'title': ar ? 'تقرير الأسبوع جاهز' : 'Your weekly report is ready',
    'body': ar
        ? 'شوف كم يوم التزمت بحدك ووين راحت فلوسك. افتح بيزة ← اليوم ← تقرير الأسبوع.'
        : 'See how many days you kept to your limit and where it went. Open Beaza, Today, Weekly report.',
  });
}

/// "Time to close your day", at 21:30 Bahrain time on the next day that is
/// not closed yet. Set again when the app opens and after a close. No
/// amount is in it: the lock screen is no place for one, and what is left
/// can still change after the alarm is set.
Future<void> scheduleDailyClose(String language,
    {required bool closedToday, DateTime? now}) async {
  final ar = language == 'ar';
  await const MethodChannel('beaza/notify').invokeMethod<void>('schedule', {
    'id': 98,
    'atMs': nextCloseReminder(now ?? DateTime.now(), closedToday: closedToday)
        .millisecondsSinceEpoch,
    'title': ar ? 'وقت تقفيلة اليوم' : 'Time to close your day',
    'body': ar
        ? 'إذا بقى شي من حد اليوم، افتح بيزة وودّه لهدف التوفير أو رحّله لباجر.'
        : 'If some of today\'s limit is left, open Beaza and send it to your goal or carry it to tomorrow.',
  });
}
