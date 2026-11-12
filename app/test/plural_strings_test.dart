import 'package:beaza/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts in sentences must take the right noun form: "مرة وحدة", not "1 مرات";
/// "17 يوم", not "17 أيام"; "once", not "1 times".
void main() {
  test('Arabic counts use singular, dual, few and other forms', () async {
    final ar = await AppLocalizations.delegate.load(const Locale('ar'));
    expect(ar.dealFit('1.000', 1, '0.100'), contains('(مرة وحدة)'));
    expect(ar.dealFit('1.000', 2, '0.100'), contains('(مرتين)'));
    expect(ar.dealFit('1.000', 3, '0.100'), contains('(3 مرات)'));
    expect(ar.coachSendShop('X', '1.000', 1), contains('(مرة وحدة)'));
    expect(ar.buyDays(17), 'يساوي حدك اليومي لـ 17 يوم.');
    expect(ar.buyDays(5), 'يساوي حدك اليومي لـ 5 أيام.');
    expect(ar.buyDays(1), 'يساوي حدك اليومي لـ يوم واحد.');
    expect(ar.voucherDaysLeft(2), 'صالح يومين');
  });

  test('English counts say once and 1 day', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(en.dealFit('1.000', 1, '0.100'), contains('(once)'));
    expect(en.dealFit('1.000', 4, '0.100'), contains('(4 times)'));
    expect(en.buyDays(1), 'It equals 1 day of your daily limit.');
    expect(en.voucherDaysLeft(7), 'Valid 7 days');
  });
}
