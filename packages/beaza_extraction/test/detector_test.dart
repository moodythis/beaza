import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:test/test.dart';

void main() {
  group('language', () {
    const d = LanguageDetector();

    test('Arabic message, BHD token ignored', () {
      expect(d.detect('تم خصم 12.500 BHD من بطاقتك'), MessageLanguage.arabic);
    });

    test('English message', () {
      expect(d.detect('Purchase of BHD 5.000 at CAFE ROMA'),
          MessageLanguage.english);
    });

    test('English message with Arabic merchant is mixed', () {
      expect(d.detect('Paid 5.000 BHD at مقهى النخيل'), MessageLanguage.mixed);
    });

    test('Arabic message with a Latin acronym stays Arabic', () {
      expect(d.detect('تم الشراء بقيمة 3.000 BHD عبر POS من مقهى'),
          MessageLanguage.arabic);
    });

    test('no letters is unknown', () {
      expect(d.detect('12.500 BHD'), MessageLanguage.unknown);
      expect(d.detect(''), MessageLanguage.unknown);
    });

    test('strict mixed rule is optional', () {
      const strictMixed = LanguageDetector(minMixedLetters: 3);
      expect(strictMixed.detect('تم الشراء بقيمة 3.000 BHD عبر POS من مقهى'),
          MessageLanguage.mixed);
    });

    test('details expose ratios', () {
      final r = const LanguageDetector().detectDetailed('تم خصم 12.500 BHD');
      expect(r.arabicRatio, 1.0);
    });

    test('thresholds are configurable', () {
      const strict = LanguageDetector(arabicThreshold: 0.95);
      expect(strict.detect('تم الشراء بقيمة 3.000 BHD عبر POS من مقهى'),
          MessageLanguage.mixed);
    });
  });

  group('sender family', () {
    final s = SenderFamilyDetector();

    test('example families', () {
      expect(s.detect('BenefitPay'), SenderFamily.benefitPay);
      expect(s.detect('BENEFIT PAY'), SenderFamily.benefitPay);
      expect(s.detect('NBB'), SenderFamily.nbb);
      expect(s.detect('nbb'), SenderFamily.nbb);
      expect(s.detect('BBK'), SenderFamily.bbk);
      expect(s.detect('BisB'), SenderFamily.bisb);
      expect(s.detect('ila'), SenderFamily.ila);
      expect(s.detect('ILA Bank'), SenderFamily.ila);
      expect(s.detect('AUB'), SenderFamily.aub);
      expect(s.detect('AlSalam'), SenderFamily.alSalam);
      expect(s.detect('Al-Salam Bank'), SenderFamily.alSalam);
      expect(s.detect('KFH'), SenderFamily.kfh);
    });

    test('unknown senders', () {
      expect(s.detect('XYZ'), SenderFamily.unknown);
      expect(s.detect(''), SenderFamily.unknown);
      expect(s.detect('+97317000000'), SenderFamily.unknown);
      expect(s.detect('NBBX'), SenderFamily.unknown);
      expect(s.detect('Zain_BH'), SenderFamily.unknown);
    });

    test('suffixes and Arabic names', () {
      expect(s.detect('BBK_Alerts'), SenderFamily.bbk);
      expect(s.detect('KFH-BH'), SenderFamily.kfh);
      expect(s.detect('بنك البحرين الوطني'), SenderFamily.nbb);
      expect(s.detect('بنك إلى'), SenderFamily.ila);
      expect(s.detect('تحويل إلى'), SenderFamily.unknown);
    });

    test('custom aliases', () {
      final custom = SenderFamilyDetector(aliases: {
        SenderFamily.nbb: ['NBB-ALERT'],
      });
      expect(custom.detect('nbb alert'), SenderFamily.nbb);
      expect(custom.detect('NBB'), SenderFamily.unknown);
    });
  });

  group('combined', () {
    test('Detector returns both results', () {
      final result = Detector().detect('تم خصم 12.500 BHD', 'NBB');
      expect(result.language, MessageLanguage.arabic);
      expect(result.senderFamily, SenderFamily.nbb);
    });
  });
}
