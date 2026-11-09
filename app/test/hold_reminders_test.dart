import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:beaza/data/services/hold_reminders.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeReminders implements HoldReminders {
  final scheduled = <String>[];
  final cancelled = <String>[];

  @override
  Future<void> schedule(Hold hold) async => scheduled.add(hold.name);

  @override
  Future<void> cancel(Hold hold) async => cancelled.add(hold.name);
}

void main() {
  test('a hold sets its reminder; deciding or removing it cancels it',
      () async {
    var now = DateTime.utc(2026, 11, 9, 10);
    final reminders = FakeReminders();
    final repo = SavingsRepository(MemoryPreferencesStore(),
        clock: () => now, reminders: reminders);
    final a = await repo.addHold('Sneakers', 45000);
    final b = await repo.addHold('Headphones', 30000);
    expect(reminders.scheduled, ['Sneakers', 'Headphones']);
    now = now.add(const Duration(hours: 25));
    await repo.decide(a.id, 'skipped');
    await repo.removeHold(b.id);
    expect(reminders.cancelled, ['Sneakers', 'Headphones']);
  });

  test('the reminder says what and how much, in the app language', () {
    final h = Hold(
        id: '1',
        name: 'Sneakers',
        amountFils: 45000,
        createdAt: DateTime.utc(2026, 11, 9));
    expect(reminderText(h, 'en').$2, contains('Sneakers (BHD 45.000)'));
    expect(reminderText(h, 'ar').$1, 'قرّرت؟');
    expect(reminderId(h), greaterThanOrEqualTo(100000));
  });
}
