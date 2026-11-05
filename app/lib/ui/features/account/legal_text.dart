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
  version: '2026-11-05.2',
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
        'بدون حساب، لا يغادر هاتفك أي شيء، إلا ما تختار أن تقوله بصوتك، والمجاميع وأسماء أكثر المحلات التي تختار إرسالها لخطة التوفير بالذكاء الاصطناعي (القسمان التاليان).',
      ],
    ),
    LegalSection(
      'إضافة مصروف بالصوت (اختياري)',
      [
        'إذا ضغطت على المايكروفون في «إضافة سريعة»، يطلب بيزة صلاحية المايكروفون من أندرويد ولا يستمع إلا أثناء ظهور أنه يستمع على الشاشة. يمرّر أندرويد الصوت إلى خدمة الكلام في هاتفك (غالبًا خدمة Google)، فتحوّله إلى نص وقد تفعل ذلك عبر الإنترنت.',
        'يحتفظ بيزة بالنص فقط، ويمكنك تعديله قبل الحفظ. ولا يحفظ الصوت أبدًا. لا يتحكم بيزة بما تفعله خدمة الكلام بالصوت، فهذا تحكمه شروط الخصوصية الخاصة بها. وإن لم ترغب في استخدامها فاكتب بدلًا من ذلك؛ لا شيء آخر في بيزة يحتاج المايكروفون.',
      ],
    ),
    LegalSection(
      'النقاط والعروض التجريبية',
      [
        'تُحسب النقاط على هاتفك من بياناتك أنت (الأيام التي بقيت فيها تحت حدك، والمشتريات التي تركتها بعد الانتظار). المحلات والعروض والأكواد وهمية لهذا النموذج التجريبي؛ لا يشارك أي محل أو بنك أو علامة تجارية حقيقية، ولا تُشارك أي بيانات مع أحد.',
      ],
    ),
    LegalSection(
      'خطة التوفير بالذكاء الاصطناعي (اختيارية، بموافقة منفصلة)',
      [
        'فقط إذا وافقت في شاشة خطة الذكاء الاصطناعي، يرسل بيزة إلى خادمه هذه المجاميع المحسوبة على هاتفك: مصروفك في آخر 7 أيام والـ7 التي قبلها، وحدك اليومي وعدد الأيام التي تجاوزته فيها، وعدد مشترياتك الصغيرة ومجموعها، ومجموع كل صنف ونسبته، وأسماء ما يصل إلى 5 محلات صرفت فيها أكثر في آخر 7 أيام مع ما صرفته فيها وعدد المرات (تُحذف الأرقام من الأسماء، ولا تُرسل التحويلات إلى أشخاص)، وعدد مشترياتك في آخر الليل (من 10 مساءً إلى 3 فجرًا) ومجموعها، وما صرفته يومي الجمعة والسبت، وإذا كان حدك محسوبًا من دخلك: المبلغ الباقي للشهر وعدد الأيام الباقية (ولا يُرسل الدخل نفسه أبدًا). تعرض لك الشاشة القائمة نفسها قبل أن توافق. لا يُرسل نص رسالة بنك ولا رقم حساب أو بطاقة ولا رقم مرجعي ولا اسم مستلم تحويل ولا تاريخ، ويرفض الخادم أي حقل آخر. لا يلزم حساب، ولا يُربط الطلب بأي حساب.',
        'يطلب الخادم من نموذج ذكاء اصطناعي (Gemma، تشغّله Cloudflare Workers AI نيابةً عنا) كتابة خطة قصيرة من هذه المجاميع وأسماء المحلات، ويتحقق أن كل رقم في الخطة من الأرقام التي أُعطيت له. تذكر Cloudflare أنها لا تحتفظ بهذه الطلبات بعد الرد ولا تستخدمها لتدريب النماذج، ولا تذكر في أي دولة يعمل النموذج. لا يحفظ بيزة شيئًا عن الطلب سوى عدد الخطط المطلوبة في ذلك اليوم، دون ربطه بك. الأساس القانوني هو موافقتك، ويمكنك سحبها في أي وقت من شاشة الخطة، وسحبها يوقف أي إرسال لاحق.',
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
        'لا إعلانات، ولا تحليلات، ولا بيع أو مشاركة للبيانات، ولا تنميط، ولا قرارات آلية بشأنك. استثناء واحد على هاتفك فقط: إذا شغّلت «العروض حسب صرفي» في العروض التجريبية (أدناه)، تُعرض العروض الوهمية لأكثر أصنافك صرفًا أولًا. ولا يغادر هاتفك شيء من ذلك.',
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
        'Without an account, nothing leaves your phone, except what you choose to say by voice and the totals and top shop names you choose to send for an AI savings plan (next sections).',
      ],
    ),
    LegalSection(
      'Adding an expense by voice (optional)',
      [
        'If you tap the microphone in Quick add, Beaza asks Android for microphone access and listens only while the screen shows that it is listening. Android hands the audio to the speech service on your phone (usually Google\'s), which turns it into text and may do so over the internet.',
        'Beaza keeps only the text, which you can edit before saving. It never saves the audio. Beaza does not control what the speech service does with the audio: that is covered by its own privacy terms. If you would rather not use it, type instead; nothing else in Beaza needs the microphone.',
      ],
    ),
    LegalSection(
      'Demo points and offers',
      [
        'Points are counted on your phone from your own data (days within your limit and purchases skipped after waiting). The partners, offers and codes are invented for this prototype; no real shop, bank or brand takes part, and no data is shared with anyone.',
      ],
    ),
    LegalSection(
      'AI savings plan (optional, separate consent)',
      [
        'Only if you agree on the AI plan screen, Beaza sends these totals, worked out on your phone, to its server: what you spent in the last 7 days and the 7 before, your daily limit and on how many days you passed it, how many small purchases you made and their total, a total and share per category, and the names of up to 5 shops where you spent most in the last 7 days, with what you spent there and how many times (digits are removed from the names; transfers to people are left out), how many purchases you made late at night (10 pm to 3 am) and their total, what you spent on Friday and Saturday, and, if your limit is worked out from your income, the money left for the month and the days left (never the income itself). The screen shows you the exact list before you agree. No bank message, account or card number, reference, transfer recipient or date is sent, and the server refuses any other field. No account is needed and none is linked to the request.',
        'The server asks an AI model (Gemma, run by Cloudflare Workers AI, Cloudflare acting for us) to write a short plan from those totals and shop names, and checks that every number in the plan is one it was given. Cloudflare states that it does not keep these requests after answering or use them to train models; it does not state in which country the model runs. Beaza stores nothing about the request except how many plans were asked for that day, with no link to you. The legal basis is your consent, which you can withdraw at any time on the plan screen; withdrawing stops any further sending.',
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
        'No advertising, no analytics, no selling or sharing of data, no profiling and no automated decisions about you. One exception, on your phone only: if you turn on "offers by my spending" in the demo offers (below), invented offers for your biggest categories are shown first. Nothing about it leaves your phone.',
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
