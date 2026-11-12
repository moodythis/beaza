import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/entry_text.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final at = DateTime.utc(2026, 11, 2, 21, 45); // 00:45 on 3 Nov in Bahrain

ExtractionResult msg({
  TxnType? type = TxnType.purchase,
  TxDirection direction = TxDirection.outgoing,
  Channel? channel,
  String? merchant,
  String? norm,
  String? last4,
  String? to,
  String template = '',
}) =>
    ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: 500,
      currency: 'BHD',
      type: type,
      direction: direction,
      merchantRaw: merchant,
      merchantNorm: norm,
      channel: channel,
      last4: last4,
      counterpartyLast4: to,
      timestamp: at,
      templateVersion: template,
    );

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  test('the shop name wins when the message has one', () {
    expect(entryTitle(en, msg(merchant: 'PETRO MART WLL')), 'PETRO MART WLL');
  });

  test('the clean shop name is shown when there is one', () {
    expect(
        entryTitle(en, msg(merchant: 'ABED BAKERY MANAMA', norm: 'Abed Bakery')),
        'Abed Bakery');
  });

  test('without a shop, the kind of payment is named', () {
    expect(entryTitle(en, msg(type: TxnType.transferOut, channel: Channel.transfer)),
        'Transfer sent');
    expect(entryTitle(en, msg(type: TxnType.transferOut, to: '4321')),
        'Transfer to account ending 4321');
    expect(entryTitle(en, msg(type: TxnType.atmWithdrawal)), 'Cash withdrawal');
    expect(entryTitle(en, msg(channel: Channel.card)), 'Card purchase');
    expect(entryTitle(en, msg(template: 'alsalam.debit@3')),
        'Debit from your account');
    expect(
        entryTitle(en, msg(template: InMemoryLedgerRepository.manualTemplate)),
        'Added by you');
    expect(entryTitle(ar, msg(type: TxnType.transferOut)), 'تحويل مرسل');
  });

  test('a transfer received says from, not to', () {
    // Al Salam Fawri+ credit seen on a real phone, 12 November 2026.
    expect(
        entryTitle(ar, msg(type: TxnType.transferIn, direction: TxDirection.incoming, channel: Channel.transfer, to: '0095')),
        'تحويل من حساب ينتهي بـ 0095');
    expect(
        entryTitle(en, msg(type: TxnType.transferIn, direction: TxDirection.incoming, to: '0095')),
        'Transfer from account ending 0095');
    expect(
        entryTitle(en, msg(type: TxnType.transferIn, direction: TxDirection.incoming)),
        'Transfer received');
  });

  test('the subtitle has the time, the bank and the last digits', () {
    expect(entrySubtitle(en, msg(template: 'alsalam.debit@3', last4: '5678')),
        '00:45 · Al Salam Bank · ••5678');
    expect(entrySubtitle(ar, msg(template: 'bisb.card@3')),
        '00:45 · بنك البحرين الإسلامي');
    expect(
        entrySubtitle(en, msg(template: InMemoryLedgerRepository.manualTemplate)),
        '00:45');
  });
}
