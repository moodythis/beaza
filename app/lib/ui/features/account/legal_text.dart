// GENERATED from server/src/legal.ts by server/scripts/legal-dart.ts.
// Do not edit by hand: change the server file and run the script.

class LegalSection {
  const LegalSection(this.title, this.paragraphs);
  final String title;
  final List<String> paragraphs;
}

class LegalDocument {
  const LegalDocument({
    required this.version,
    required this.titleAr,
    required this.titleEn,
    required this.ar,
    required this.en,
  });

  final String version;
  final String titleAr;
  final String titleEn;
  final List<LegalSection> ar;
  final List<LegalSection> en;

  String title(String language) => language == 'ar' ? titleAr : titleEn;
  List<LegalSection> sections(String language) => language == 'ar' ? ar : en;
}

const privacyNotice = LegalDocument(
  version: '2026-11-03',
  titleAr: 'إشعار الخصوصية لتطبيق بيزة',
  titleEn: 'Beaza privacy notice',
  ar: [
    LegalSection(
      'من نحن',
      [
        'بيزة (Beaza) أداة لضبط المصروف اليومي، صُمّمت مشروعَ تخرج في البحرين. الشخص الذي يشغّل خادم المزامنة هو المتحكم في البيانات.',
      ],
    ),
    LegalSection(
      'ما لا يغادر هاتفك أبدًا',
      [
        'نص رسائل البنك لا يُحفظ ولا يُرسل إلى أي مكان. يقرؤه التطبيق ويحتفظ فقط بالمبلغ والتاجر والوقت والنوع، ويخزنها في قاعدة بيانات مشفرة على هاتفك.',
        'بدون حساب، لا يغادر هاتفك أي شيء.',
      ],
    ),
    LegalSection(
      'ما يستلمه خادم المزامنة إذا أنشأت حسابًا',
      [
        'بريدك الإلكتروني.',
        'بصمة (hash) لمفتاح يُشتق من كلمة السر على هاتفك. كلمة السر نفسها لا تُرسل أبدًا.',
        'بصمة لإثبات يُشتق من مفتاح الاسترجاع. مفتاح الاسترجاع نفسه لا يُرسل أبدًا.',
        'مفتاح بياناتك مقفلًا، بحيث لا يفتحه إلا كلمة السر أو مفتاح الاسترجاع.',
        'معاملاتك وإعداداتك، مشفرة على هاتفك قبل الإرسال. لا نستطيع قراءة المبالغ أو التجار أو التواريخ أو الحدود.',
        'نسخة هذا الإشعار التي وافقت عليها ووقت الموافقة، وبصمات رموز الجلسات، وعدد محاولات الدخول الخاطئة محفوظًا تحت بصمات مفتاحية (بدون بريد أو عنوان IP).',
      ],
    ),
    LegalSection(
      'لماذا، وعلى أي أساس',
      [
        'فقط لمزامنة بياناتك بين هواتفك. الأساس القانوني هو موافقتك (المادة 6(1)(أ) من اللائحة الأوروبية GDPR، والقانون البحريني رقم 30 لسنة 2018).',
        'لا إعلانات، ولا تحليلات، ولا بيع أو مشاركة للبيانات، ولا تنميط، ولا قرارات آلية بشأنك.',
      ],
    ),
    LegalSection(
      'أين تُحفظ',
      [
        'يعمل الخادم على Cloudflare التي تعالج البيانات نيابةً عنا. تُحفظ قاعدة البيانات داخل الاتحاد الأوروبي، وهو ضمن قائمة البحرين للدول ذات الحماية الكافية.',
        'تعالج Cloudflare كل طلب في أقرب موقع، وقد تعالج عنوان IP لتقديم الخدمة وصد الهجمات. بيزة نفسها لا تحفظ عناوين IP.',
      ],
    ),
    LegalSection(
      'المدة',
      [
        'حتى تحذف حسابك. تنتهي الجلسات بعد 60 يومًا، وتُصفّر عدادات المحاولات الخاطئة خلال ساعة.',
        'حذف الحساب يمسح كل شيء من قاعدة البيانات فورًا. قد يحتفظ نظام الاسترجاع الزمني في Cloudflare بالبيانات المحذوفة حتى 30 يومًا، ثم تُزال.',
      ],
    ),
    LegalSection(
      'حقوقك',
      [
        'الاطلاع على ما يحفظه الخادم عنك: شاشة الحساب في التطبيق.',
        'حذف حسابك وكل بياناتك المتزامنة: شاشة الحساب في التطبيق. وهذا يسحب موافقتك أيضًا، ولا يؤثر على ما تم قبله.',
        'بياناتك تبقى على هاتفك وهي ملكك.',
        'يحق لك تقديم شكوى إلى هيئة حماية البيانات الشخصية في البحرين (تتولى مهامها حاليًا وزارة العدل والشؤون الإسلامية والأوقاف)، أو إلى السلطة الرقابية في بلدك إن كنت في الاتحاد الأوروبي.',
      ],
    ),
    LegalSection(
      'الأمان',
      [
        'تشفير من الطرفين (XChaCha20-Poly1305، وArgon2id لكلمة السر)، وقاعدة بيانات مشفرة على الهاتف، وحد لمحاولات الدخول الخاطئة، ولا نسخ احتياطي سحابي للتطبيق.',
        'إذا تأثرت بأي اختراق، نبلّغ الهيئة خلال 72 ساعة ونخبرك. ولأن سجلاتك مشفرة على هاتفك، فاختراق الخادم قد يكشف البريد الإلكتروني لا مصروفاتك.',
      ],
    ),
    LegalSection(
      'العمر',
      [
        'الحسابات لمن عمره 18 سنة فأكثر.',
      ],
    ),
    LegalSection(
      'التغييرات',
      [
        'إذا تغيّر هذا الإشعار تغييرًا مهمًا، يطلب منك التطبيق الموافقة من جديد قبل المزامنة.',
      ],
    ),
  ],
  en: [
    LegalSection(
      'Who we are',
      [
        'Beaza (بيزة) is a daily spending guardrail made as a graduation project in Bahrain. The person who runs the sync server is the data controller.',
      ],
    ),
    LegalSection(
      'What never leaves your phone',
      [
        'The text of bank messages is never stored or sent anywhere. The app reads it, keeps only the amount, merchant, time and type, and stores those in an encrypted database on your phone.',
        'Without an account, nothing leaves your phone at all.',
      ],
    ),
    LegalSection(
      'What the sync server receives if you create an account',
      [
        'Your email address.',
        'A hash of a key made from your password on your phone. Your password itself is never sent.',
        'A hash of a proof made from your recovery key. The recovery key itself is never sent.',
        'Your data key, locked so that only your password or your recovery key can open it.',
        'Your transactions and settings, encrypted on your phone before sending. We cannot read the amounts, merchants, dates or limits.',
        'The version of this notice you agreed to and when; hashes of session tokens; counts of wrong log-in attempts stored under keyed hashes (no email or IP address in them).',
      ],
    ),
    LegalSection(
      'Why, and on what basis',
      [
        'Only to keep your data in step between your own phones. The legal basis is your consent (GDPR Art. 6(1)(a); Bahrain Law No. 30 of 2018).',
        'No advertising, no analytics, no selling or sharing of data, no profiling and no automated decisions about you.',
      ],
    ),
    LegalSection(
      'Where it is kept',
      [
        'The server runs on Cloudflare, which processes the data on our behalf. The database is kept in the European Union, which is on Bahrain\'s list of countries with adequate protection.',
        'Cloudflare handles each request at a nearby location and may process your IP address to deliver the service and block attacks. Beaza itself does not store IP addresses.',
      ],
    ),
    LegalSection(
      'How long',
      [
        'Until you delete your account. Sessions end after 60 days. Wrong-attempt counters reset within an hour.',
        'Deleting your account removes everything from the database at once. Cloudflare\'s point-in-time recovery may hold deleted data for up to 30 days, after which it is gone.',
      ],
    ),
    LegalSection(
      'Your rights',
      [
        'See what the server holds about you: Account screen in the app.',
        'Delete your account and all synced data: Account screen in the app. This also withdraws your consent; it does not affect what was done before.',
        'Your data remains on your phone and is yours to keep.',
        'You can complain to Bahrain\'s Personal Data Protection Authority (its duties are currently carried out by the Ministry of Justice, Islamic Affairs and Endowments) or, if you are in the EU, to your local supervisory authority.',
      ],
    ),
    LegalSection(
      'Security',
      [
        'End-to-end encryption (XChaCha20-Poly1305; Argon2id for the password), an encrypted database on the phone, limits on wrong log-in attempts, and no cloud backup of the app.',
        'If a breach affected you, we would notify the Authority within 72 hours and tell you. Because your records are encrypted on your phone, a server breach could expose email addresses but not your spending.',
      ],
    ),
    LegalSection(
      'Age',
      [
        'Accounts are for people aged 18 or over.',
      ],
    ),
    LegalSection(
      'Changes',
      [
        'If this notice changes in a way that matters, the app asks you to agree again before syncing.',
      ],
    ),
  ],
);

const termsOfUse = LegalDocument(
  version: '2026-11-03',
  titleAr: 'شروط استخدام بيزة',
  titleEn: 'Beaza terms of use',
  ar: [
    LegalSection(
      'ما هي بيزة',
      [
        'تساعدك بيزة على الالتزام بحد يومي للصرف، فتقرأ رسائل البنك على هاتفك وتنبهك. التطبيق مجاني، وهو مشروع تخرج، وليس بنكًا ولا خدمة دفع ولا نصيحة مالية.',
      ],
    ),
    LegalSection(
      'الدقة',
      [
        'تقرأ بيزة رسائل البنك تلقائيًا وقد تخطئ: قد تفوتها رسالة، أو تقرأها خطأ، أو تحسبها مرتين. راجع الأرقام المهمة مع بنكك. والقرارات المتعلقة بمالك تبقى قراراتك.',
      ],
    ),
    LegalSection(
      'حسابك ومفاتيحك',
      [
        'يجب أن يكون عمرك 18 سنة فأكثر لإنشاء حساب، والحساب لبيانات شخص واحد فقط.',
        'احفظ كلمة السر ومفتاح الاسترجاع في مكان آمن. لأن بياناتك مشفرة على هاتفك، لا يستطيع أحد، ولا نحن، فتح بياناتك المتزامنة بدونهما. إذا فقدتهما معًا وفقدت كل الهواتف المسجلة، لا يمكن استرجاع النسخة المتزامنة.',
      ],
    ),
    LegalSection(
      'الاستخدام العادل',
      [
        'لا تحاول تعطيل الخادم أو إثقاله أو تجاوز حمايته، ولا تستخدمه لتخزين أي شيء غير بيانات بيزة. قد تُغلق الحسابات التي تفعل ذلك.',
      ],
    ),
    LegalSection(
      'التوفر',
      [
        'نحاول إبقاء المزامنة تعمل، لكن لا نضمن توفرها دائمًا. إذا كانت الخدمة ستتوقف، نعلن ذلك في التطبيق مسبقًا. تبقى بياناتك دائمًا على هاتفك، ويعمل التطبيق بدون مزامنة.',
      ],
    ),
    LegalSection(
      'إنهاء الحساب',
      [
        'يمكنك حذف حسابك في أي وقت من شاشة الحساب. يحذف ذلك بياناتك المتزامنة، وتبقى البيانات على هاتفك حتى تزيل التطبيق.',
      ],
    ),
    LegalSection(
      'المسؤولية',
      [
        'تُقدَّم بيزة كما هي. وبالقدر الذي يسمح به القانون، لا نتحمل مسؤولية خسائر ناتجة عن الاعتماد على أرقامها أو تنبيهاتها. ولا شيء هنا يحدّ من حقوقك بموجب القانون.',
      ],
    ),
    LegalSection(
      'القانون والتغييرات',
      [
        'تخضع هذه الشروط لقوانين مملكة البحرين. إذا تغيّرت تغييرًا مهمًا، يطلب منك التطبيق الموافقة من جديد قبل المزامنة. أما طريقة تعاملنا مع البيانات الشخصية فموضحة بشكل منفصل في إشعار الخصوصية.',
      ],
    ),
  ],
  en: [
    LegalSection(
      'What Beaza is',
      [
        'Beaza helps you keep to a daily spending limit by reading bank messages on your phone and alerting you. It is free, and it is a graduation project, not a bank, a payment service or financial advice.',
      ],
    ),
    LegalSection(
      'Accuracy',
      [
        'Beaza reads bank messages automatically and can make mistakes: a message may be missed, read wrongly or counted twice. Check important figures against your bank. Decisions about your money remain yours.',
      ],
    ),
    LegalSection(
      'Your account and keys',
      [
        'You must be 18 or over to create an account, and an account is for one person\'s own data.',
        'Keep your password and recovery key safe. Because your data is encrypted on your phone, nobody, including us, can open your synced data without them. If you lose both and every signed-in phone, the synced copy cannot be recovered.',
      ],
    ),
    LegalSection(
      'Fair use',
      [
        'Do not try to break, overload or get around the security of the server, or use it to store anything other than Beaza\'s own data. Accounts that do so may be closed.',
      ],
    ),
    LegalSection(
      'Availability',
      [
        'We try to keep sync running but cannot promise it will always be available. If the service is going to stop, we will say so in the app in advance. Your data always remains on your phone, and the app keeps working without sync.',
      ],
    ),
    LegalSection(
      'Ending',
      [
        'You can delete your account at any time from the Account screen. This deletes your synced data; the data on your phone stays until you remove the app.',
      ],
    ),
    LegalSection(
      'Liability',
      [
        'Beaza is provided as it is. As far as the law allows, we are not liable for losses that come from relying on its figures or alerts. Nothing here limits rights you have by law.',
      ],
    ),
    LegalSection(
      'Law and changes',
      [
        'These terms are governed by the laws of the Kingdom of Bahrain. If they change in a way that matters, the app asks you to agree again before syncing. How we handle personal data is described separately in the privacy notice.',
      ],
    ),
  ],
);
