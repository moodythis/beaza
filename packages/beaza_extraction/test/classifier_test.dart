import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:test/test.dart';

void main() {
  const c = MessageClassifier();
  const tx = MessageKind.transaction;
  MessageKind kindOf(String s) => c.classify(s).kind;

  // Formats modelled on real Bahraini messages (names and numbers changed).
  // BisB style
  test('BisB Fawri+ out', () => expect(kindOf('Fawri+ payment BHD2.900, ref: BIB103KAA000AAAA was credited to IBAN ending 4411 on 2026/10/30 00:59. Balance BHD9.999. Tel: 17515151'), tx));
  test('BisB Fawri+ in', () => expect(kindOf('Fawri+ payment BHD8.800 received from IBAN 5522 to IBAN 6633 ref. BIB103KAB000BBBB on 2026/10/25 06:15. Balance BHD9.999. Tel 17515151'), tx));
  test('Al Salam VISA prepaid card', () => expect(kindOf('Thank you for using your VISA PREPAID card XXXX1234 for BHD 3.500 at SAMPLE SHOP on 29-Apr ? 19:43 .Bal: AED 99.99'), tx));
  test('BisB debit card', () => expect(kindOf('Dear CLIENT, thank you for using your Debit card 7744 for BHD 0.300 at SAMPLE BAKERY - MAL BAH BH-000001 on 15/10 @16:31. Avail Bal BHD 9.999. Tel 17515151'), tx));
  // ila style
  test('BisB Fawri in, second wording', () => expect(kindOf('Fawri payment BHD400.000 received from IBAN ending 5522 credited to IBAN ending 6633 ref. NBB101126TEST0A1 on 2026/11/10 15:09. Balance BHD9.999. Tel: 17515151'), tx));
  test('ila Fawri+ in', () => expect(kindOf('Success! Fawri+ transfer of BHD 50.000 from IBAN ****0777 credited to BHD Ac on 02/11/2026 12:11 Ref ALS103KAC000CCCC Balance BHD 9.999 Enquiry 17123456'), tx));
  test('ila Fawri+ out', () => expect(kindOf('Success! Fawri+ transfer of BHD 49.000 to IBAN ****9966 is completed on 01/11/2026 20:45 Ref ABCO260000000001 Balance BHD 9.999 Enquiry 17123456'), tx));
  test('ila purchase', () => expect(kindOf('Success! Purchase at SAMPLE TRADING CO W using card ****8855 for BHD 1.500 on 29/10/2026 15:42 debited from BHD Ac Balance BHD 9.999 Enquiry 17123456'), tx));
  test('ila purchase without Success', () => expect(kindOf('Purchase at SAMPLE MARKET ISA TOWN BH using card ****8855 for BHD 14.900 on 14/10/2026 17:37 debited from BHD Ac Balance BHD 9.999 Enquiry 17123456'), tx));
  test('ila purchase with &amp;', () => expect(kindOf('Success! Purchase at INFO &amp; SAMPLE AUTHOR using card ****8855 for BHD 5.000 on 14/10/2026 17:16 debited from BHD Ac Balance BHD 9.999 Enquiry 17123456'), tx));
  test('ila DECLINED', () => expect(kindOf('DECLINED. Your BHD account has insufficient funds. Please fund it and try again. Card ****8855 for BHD 1.500 on 29/10/2026 15:41 Enquiry 17123456'), MessageKind.declined));
  // Al Salam style
  test('Al Salam debit', () => expect(kindOf('Dear Client, BHD 0.400 has been debited from your account XXXX10100777. Your balance is BHD 9.999 on 30/10/26 at 01:27. Thank you, Al Salam Bank.'), tx));
  test('Al Salam Fawri+ in', () => expect(kindOf('Fawri+ BHD 6.000 ref BIB103KAD000DDDD from IBAN BH35BIBBXXXXXXXXXXXX27 credited to acct XXX10100777. Bal: BHD 9.999 on 26/10/26 at 15:39. Tel 17005500'), tx));
  // Arabic transactions
  test('Arabic debit', () => expect(kindOf('تم خصم 12.500 BHD من بطاقتك لدى CAFE ROMA'), tx));
  test('Arabic deposit', () => expect(kindOf('تم إيداع 50.000 BHD في حسابك'), tx));
  test('Arabic purchase', () => expect(kindOf('تمت عملية شراء بقيمة 4.250 BHD لدى TALABAT'), tx));
  // BenefitPay-style notifications (wording to be confirmed on real ones)
  test('BenefitPay approved', () => expect(kindOf('عملية مقبولة بمبلغ 2.500 BHD لدى COSTA COFFEE'), tx));
  test('BenefitPay succeeded', () => expect(kindOf('نجحت العملية: 5.000 BHD'), tx));
  test('BenefitPay received', () => expect(kindOf('تم استلام 10.000 BHD من أحمد'), tx));
  test('BenefitPay not accepted is declined', () => expect(kindOf('عملية غير مقبولة بمبلغ 2.500 BHD'), MessageKind.declined));
  test('Request received without amount', () => expect(kindOf('تم استلام طلبك وسيتم التواصل معك'), MessageKind.unknown));
  test('English approved', () => expect(kindOf('Transaction approved for BHD 3.000 at SHOP'), tx));
  // OTP and security notices
  test('OTP wins over payment words', () => expect(kindOf('Your OTP for card payment BHD 5.000 at SHOP is 123456. Do not share it.'), MessageKind.otp));
  test('Arabic OTP', () => expect(kindOf('رمز التحقق 123456 لا تشاركه مع أحد'), MessageKind.otp));
  test('Awareness message is not OTP', () => expect(kindOf('Beware of phishing. Never share your PIN or OTP with anyone.'), MessageKind.securityNotice));
  test('Never share only', () => expect(kindOf('Never share your OTP with anyone'), MessageKind.securityNotice));
  test('New device login', () => expect(kindOf('Security alert: new device login to your account'), MessageKind.securityNotice));
  test('Arabic security alert', () => expect(kindOf('تنبيه أمني: لا تشارك رمز التحقق مع أحد'), MessageKind.securityNotice));
  test('Fraud alert beats transaction', () => expect(kindOf('Fraud alert: unauthorized purchase of BHD 50.000 at SHOP'), MessageKind.securityNotice));
  test('Footer warning keeps transaction', () => expect(kindOf('Purchase at SHOP using card ****8855 for BHD 3.000 debited from BHD Ac. Never share your PIN. Enquiry 17123456'), tx));
  // Other non-transactions
  test('Promotion', () => expect(kindOf('Get 20% cashback offer at Costa Coffee until 30/11. Terms apply'), MessageKind.promotion));
  test('Promotion wins over purchase', () => expect(kindOf('Make a purchase of BHD 10 and get 10% cashback offer'), MessageKind.promotion));
  // Real ila Bank messages received on 11-12 November 2026 (Arabic marketing).
  test('ila Arabic prize draw with an amount is a promotion', () => expect(kindOf('قدّم على بطاقة "إلى" بلاك أو "إلى" وايت الائتمانية للفوز بسيارة لاند روفر ديفيندر 2026! للدخول في السحب، أنفق 800 BHD أو أكثر باستخدام بطاقة "إلى" بلاك أو "إلى" وايت الائتمانية قبل 31 ديسمبر 2026. تطبق الشروط والأحكام.'), MessageKind.promotion));
  test('ila Arabic gold draw is a promotion', () => expect(kindOf('سيربح 5 فائزين سبائك ذهب! لدخول السحب، أنفق 500 BHD أو أكثر على المجوهرات والذهب باستخدام بطاقات بنك "إلى" للخصم المباشر من 1 - 30 نوفمبر 2026. تطبق الشروط والأحكام.'), MessageKind.promotion));
  test('ila Arabic treasure draw is a promotion', () => expect(kindOf('اليوم هو آخر يوم للمشاركة في السحب على جائزة الكنز لشهر أكتوبر بقيمة 100,000\$! قم بالإيداع الآن في حساب الكنز.'), MessageKind.promotion));
  test('Al Salam account credit', () => expect(kindOf('Dear Client, BHD 1.000 has been credited to your account XXXX23150000. Your balance is BHD 0.000 on 01/11/26 at 00:15. Thank you, Al Salam Bank.'), tx));
  test('A cash withdrawal is still a transaction', () => expect(kindOf('تم سحب 20.000 BHD من حسابك'), tx));
  test('Arabic promotion', () => expect(kindOf('عرض خاص: اربح قسيمة شراء بقيمة 10 BHD'), MessageKind.promotion));
  test('Statement', () => expect(kindOf('Your e-statement for October is ready'), MessageKind.statement));
  test('Arabic statement', () => expect(kindOf('كشف حسابك لشهر أكتوبر جاهز'), MessageKind.statement));
  test('Balance inquiry', () => expect(kindOf('Your available balance is BHD 5.000 as of 02/11/2026'), MessageKind.balanceInquiry));
  test('Arabic balance', () => expect(kindOf('رصيدك المتاح هو 5.000 BHD'), MessageKind.balanceInquiry));
  test('Arabic declined', () => expect(kindOf('تم رفض العملية بسبب عدم كفاية الرصيد'), MessageKind.declined));
  test('Cue without amount is unknown', () => expect(kindOf('Your card purchase was successful'), MessageKind.unknown));
  test('Greeting is information', () => expect(kindOf('Hello from your bank'), MessageKind.information));
  test('Empty is information', () => expect(kindOf(''), MessageKind.information));
  test('Maintenance notice is information', () => expect(kindOf('System maintenance on 16 October 2026 from 2:00 to 6:00 AM.'), MessageKind.information));
  test('Loan campaign is a promotion', () => expect(kindOf('Apply for a loan, up to BHD20,000. Campaign period ends soon.'), MessageKind.promotion));
  test('NBB card use is a transaction', () => expect(kindOf('Thank you for using NBB Debit Card at REDTAG MANAMA for BHD6.930 on 27/10/2026 20:37, A/C ending 4810 balance BHD9.999.'), tx));
  test('A promotion word inside a merchant name does not hide a purchase', () => expect(kindOf('Thank you for using NBB Debit Card at DAY TO DAY DISCOUNT CEMANAMA for BHD5.085 on 30/10/2026 21:55, A/C ending 4810 balance BHD9.999.'), tx));
  // ClassificationResult
  final fawri = c.classify('Fawri+ payment BHD2.900, ref: BIB103KAA000AAAA was credited to IBAN ending 4411 on 2026/10/30 00:59. Balance BHD9.999. Tel: 17515151');
  test('isTransaction true', () => expect(fawri.isTransaction, true));
  test('Two cues give 0.85', () => expect(fawri.confidence, 0.85));
  test('Rule name', () => expect(fawri.rule, 'transaction'));
  final single = c.classify('Dear Client, BHD 0.400 has been debited from your account XXXX10100777. Your balance is BHD 9.999 on 30/10/26 at 01:27. Thank you, Al Salam Bank.');
  test('One cue gives 0.70', () => expect(single.confidence, 0.70));
  final otp = c.classify('Your OTP is 123456');
  test('isTransaction false for OTP', () => expect(otp.isTransaction, false));
  test('OTP confidence', () => expect(otp.confidence, 0.95));
  final none = c.classify('Your card purchase was successful');
  test('Unknown confidence is 0', () => expect(none.confidence, 0.0));
  test('Unknown isTransaction false', () => expect(none.isTransaction, false));
}
