import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza_extraction/beaza_extraction.dart';

/// What a transaction is called in a list. The shop when the message names
/// one; otherwise what kind of payment it was, so a transfer, a cash
/// withdrawal and a typed-in expense can be told apart. (Bank messages for
/// transfers carry no names on purpose: the extractor never keeps them.)
String entryTitle(AppLocalizations l10n, ExtractionResult r) {
  final merchant = r.merchantRaw?.trim();
  if (merchant != null && merchant.isNotEmpty) return merchant;
  if (r.templateVersion == InMemoryLedgerRepository.manualTemplate) {
    return l10n.entryManual;
  }
  if (r.type == TxnType.transferOut || r.channel == Channel.transfer) {
    final to = r.counterpartyLast4;
    return to == null ? l10n.entryTransfer : l10n.entryTransferTo(to);
  }
  return switch (r.type) {
    TxnType.atmWithdrawal => l10n.entryCash,
    TxnType.bill => l10n.entryBill,
    TxnType.refund => l10n.entryRefund,
    _ => switch (r.channel) {
        Channel.card => l10n.entryCard,
        Channel.wallet => l10n.entryWallet,
        Channel.atm => l10n.entryCash,
        _ => l10n.entryDebit,
      },
  };
}

/// Time, bank and the last digits of the card or account, for example
/// "00:45 · Al Salam Bank · ••5678".
String entrySubtitle(AppLocalizations l10n, ExtractionResult r) {
  final at = r.timestamp;
  final bank = bankName(l10n, r.templateVersion);
  final last4 = r.last4;
  return [
    if (at != null) formatBahrainTime(at),
    if (bank != null) bank,
    if (last4 != null && last4.isNotEmpty) '••$last4',
  ].join(' · ');
}

/// The bank or wallet whose message this came from, read from the template
/// name (for example `alsalam.debit@3`). Null for typed-in expenses.
String? bankName(AppLocalizations l10n, String templateVersion) {
  final family = templateVersion.split('.').first;
  return switch (family) {
    'bisb' => l10n.bankBisb,
    'ila' => l10n.bankIla,
    'alsalam' => l10n.bankAlSalam,
    'nbb' => l10n.bankNbb,
    'benefitpay' => l10n.bankBenefitPay,
    _ => null,
  };
}
