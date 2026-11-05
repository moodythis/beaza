// The two documents people agree to at sign-up, served at /privacy and
// /terms (Google Play needs a public privacy link) and shown in the app.
// They are agreed to separately: consent to data processing must not be
// bundled with other terms (GDPR Art. 7(2)).
//
// When a text changes in a way that matters, raise its version: the server
// then refuses sign-ups with the old version and the app shows the new one.
//
// Keep in step with app/lib/ui/features/account/legal_text.dart.
//
// Drafted for a graduation project; a lawyer should review them before a
// public release.

export const PRIVACY_VERSION = '2026-11-05.8';
export const TERMS_VERSION = '2026-11-03';

type Section = { title: string; body: string[] };

const en: Section[] = [
  {
    title: 'Who we are',
    body: [
      'Beaza (بيزة) is a daily spending guardrail made as a graduation project in Bahrain. The person who runs the sync server is the data controller.',
    ],
  },
  {
    title: 'What never leaves your phone',
    body: [
      'The text of bank messages is never stored or sent anywhere. The app reads it, keeps only the amount, merchant, time and type, and stores those in an encrypted database on your phone.',
      'Without an account, nothing leaves your phone, except what you choose to say by voice and the spending details you choose to send for an AI savings plan (next sections).',
    ],
  },
  {
    title: 'Adding an expense by voice (optional)',
    body: [
      'If you tap the microphone in Quick add, Beaza asks Android for microphone access and listens only while the screen shows that it is listening. Android hands the audio to the speech service on your phone (usually Google\'s), which turns it into text and may do so over the internet.',
      'Beaza keeps only the text, which you can edit before saving. It never saves the audio. Beaza does not control what the speech service does with the audio: that is covered by its own privacy terms. If you would rather not use it, type instead; nothing else in Beaza needs the microphone.',
    ],
  },
  {
    title: 'Demo points and offers',
    body: [
      'Points are counted on your phone from your own data (days within your limit and purchases skipped after waiting). The partners, offers and codes are invented for this prototype; no real shop, bank or brand takes part, and no data is shared with anyone.',
    ],
  },
  {
    title: 'AI savings plan (optional, separate consent)',
    body: [
      'Only if you agree on the AI plan screen, Beaza sends these totals, worked out on your phone, to its server: what you spent in the last 7 days and the 7 before, your daily limit and on how many days you passed it, how many small purchases you made and their total, a total and share per category, the names of up to 5 shops where you spent most in the last 7 days with what you spent there and how many times, each purchase of the last 7 days (up to 40) with its weekday, hour, amount, category and shop name, how many purchases you made late at night (10 pm to 3 am) and their total, what you spent on Friday and Saturday, and, if your limit is worked out from your income, the money left for the month and the days left (never the income itself). The screen shows you the exact list before you agree. Nothing that identifies you is sent: no bank message, account or card number, phone number, CPR, reference, calendar date or name of a person you transferred to (digits are removed from shop names and transfers are left out), and the server refuses any other field. No account is needed and none is linked to the request.',
      'The server asks an AI model (see "Which AI models") to write a short plan from this information, and checks that every number in the plan is one it was given. What the AI provider may do with the request is set out under "Which AI models". Beaza stores nothing about the request except how many plans were asked for that day, with no link to you. The legal basis is your consent, which you can withdraw at any time on the plan screen; withdrawing stops any further sending.',
    ],
  },
  {
    title: 'Sorting purchases with AI (optional, separate consent)',
    body: [
      'Only if you turn it on in the history screen, Beaza sends the names of shops it could not sort itself (digits removed) to its server, which asks the same AI model to pick a category for each. Nothing else is sent: no amount, date, account or card number, message text, or anything about you, and the server refuses any other field. The category is saved on your phone and you can change it at any time. Beaza stores nothing about the request except the daily count. You can turn it off at any time in the same place.',
    ],
  },
  {
    title: 'Receipt photos and voice read with AI (optional, separate consent)',
    body: [
      'Only if you turn it on in the receipt or quick add screen: a receipt photo (made smaller on your phone) or a voice recording of up to 60 seconds is sent to Beaza\'s server, which asks an AI model to read it (see "Which AI models"). A photo can show whatever is on the receipt, such as the last digits of a card, so crop or cover anything you do not want to send. Beaza does not store the photo, the recording or the text: you see what was read and change it before anything is saved. Without this, photos are read on your phone and speech goes to your phone\'s own speech service. You can turn it off at any time in the same place.',
    ],
  },
  {
    title: 'Which AI models',
    body: [
      'Beaza\'s server first sends each AI request (savings plan, sorting, receipt photos, voice) to Google\'s Gemini model through Google\'s free tier. On the free tier, Google may keep what is sent and the answer, use them to improve its products and models, and people at Google may read them; Google says it first separates them from Beaza\'s account. If Gemini does not answer (for example when the free daily allowance is used up), no other AI is asked: the plan is written by rules and photos and speech are read on your phone. No account, name or phone number is sent with an AI request. Because of Google\'s free-tier terms, send nothing you would not want a person to read, and cover card digits on a receipt photo.',
    ],
  },
  {
    title: 'What the sync server receives if you create an account',
    body: [
      'Your email address.',
      'A hash of a key made from your password on your phone. Your password itself is never sent.',
      'A hash of a proof made from your recovery key. The recovery key itself is never sent.',
      'Your data key, locked so that only your password or your recovery key can open it.',
      'Your transactions and settings, encrypted on your phone before sending. We cannot read the amounts, merchants, dates or limits.',
      'The version of this notice you agreed to and when; hashes of session tokens; counts of wrong log-in attempts stored under keyed hashes (no email or IP address in them).',
    ],
  },
  {
    title: 'Why, and on what basis',
    body: [
      'Only to keep your data in step between your own phones. The legal basis is your consent (GDPR Art. 6(1)(a); Bahrain Law No. 30 of 2018).',
      'No advertising, no analytics, no selling or sharing of data, no profiling and no automated decisions about you. One exception, on your phone only: if you turn on "offers by my spending" in the demo offers (below), invented offers for your biggest categories are shown first. Nothing about it leaves your phone.',
    ],
  },
  {
    title: 'Where it is kept',
    body: [
      'The server runs on Cloudflare, which processes the data on our behalf. The database is kept in the European Union, which is on Bahrain\'s list of countries with adequate protection.',
      'Cloudflare handles each request at a nearby location and may process your IP address to deliver the service and block attacks. Beaza itself does not store IP addresses.',
    ],
  },
  {
    title: 'How long',
    body: [
      'Until you delete your account. Sessions end after 60 days. Wrong-attempt counters reset within an hour.',
      'Deleting your account removes everything from the database at once. Cloudflare\'s point-in-time recovery may hold deleted data for up to 30 days, after which it is gone.',
    ],
  },
  {
    title: 'Your rights',
    body: [
      'See what the server holds about you: Account screen in the app.',
      'Delete your account and all synced data: Account screen in the app. This also withdraws your consent; it does not affect what was done before.',
      'Your data remains on your phone and is yours to keep.',
      'You can complain to Bahrain\'s Personal Data Protection Authority (its duties are currently carried out by the Ministry of Justice, Islamic Affairs and Endowments) or, if you are in the EU, to your local supervisory authority.',
    ],
  },
  {
    title: 'Security',
    body: [
      'End-to-end encryption (XChaCha20-Poly1305; Argon2id for the password), an encrypted database on the phone, limits on wrong log-in attempts, and no cloud backup of the app.',
      'If a breach affected you, we would notify the Authority within 72 hours and tell you. Because your records are encrypted on your phone, a server breach could expose email addresses but not your spending.',
    ],
  },
  {
    title: 'Age',
    body: ['Accounts are for people aged 18 or over.'],
  },
  {
    title: 'Changes',
    body: [
      'If this notice changes in a way that matters, the app asks you to agree again before syncing.',
    ],
  },
];

const ar: Section[] = [
  {
    title: 'من نحن',
    body: [
      'بيزة (Beaza) أداة لضبط المصروف اليومي، صُمّمت مشروعَ تخرج في البحرين. الشخص الذي يشغّل خادم المزامنة هو المتحكم في البيانات.',
    ],
  },
  {
    title: 'ما لا يغادر هاتفك أبدًا',
    body: [
      'نص رسائل البنك لا يُحفظ ولا يُرسل إلى أي مكان. يقرؤه التطبيق ويحتفظ فقط بالمبلغ والتاجر والوقت والنوع، ويخزنها في قاعدة بيانات مشفرة على هاتفك.',
      'بدون حساب، لا يغادر هاتفك أي شيء، إلا ما تختار أن تقوله بصوتك، وتفاصيل الصرف التي تختار إرسالها لخطة التوفير بالذكاء الاصطناعي (القسمان التاليان).',
    ],
  },
  {
    title: 'إضافة مصروف بالصوت (اختياري)',
    body: [
      'إذا ضغطت على المايكروفون في «إضافة سريعة»، يطلب بيزة صلاحية المايكروفون من أندرويد ولا يستمع إلا أثناء ظهور أنه يستمع على الشاشة. يمرّر أندرويد الصوت إلى خدمة الكلام في هاتفك (غالبًا خدمة Google)، فتحوّله إلى نص وقد تفعل ذلك عبر الإنترنت.',
      'يحتفظ بيزة بالنص فقط، ويمكنك تعديله قبل الحفظ. ولا يحفظ الصوت أبدًا. لا يتحكم بيزة بما تفعله خدمة الكلام بالصوت، فهذا تحكمه شروط الخصوصية الخاصة بها. وإن لم ترغب في استخدامها فاكتب بدلًا من ذلك؛ لا شيء آخر في بيزة يحتاج المايكروفون.',
    ],
  },
  {
    title: 'النقاط والعروض التجريبية',
    body: [
      'تُحسب النقاط على هاتفك من بياناتك أنت (الأيام التي بقيت فيها تحت حدك، والمشتريات التي تركتها بعد الانتظار). المحلات والعروض والأكواد وهمية لهذا النموذج التجريبي؛ لا يشارك أي محل أو بنك أو علامة تجارية حقيقية، ولا تُشارك أي بيانات مع أحد.',
    ],
  },
  {
    title: 'خطة التوفير بالذكاء الاصطناعي (اختيارية، بموافقة منفصلة)',
    body: [
      'فقط إذا وافقت في شاشة خطة الذكاء الاصطناعي، يرسل بيزة إلى خادمه هذه المجاميع المحسوبة على هاتفك: مصروفك في آخر 7 أيام والـ7 التي قبلها، وحدك اليومي وعدد الأيام التي تجاوزته فيها، وعدد مشترياتك الصغيرة ومجموعها، ومجموع كل صنف ونسبته، وأسماء ما يصل إلى 5 محلات صرفت فيها أكثر في آخر 7 أيام مع ما صرفته فيها وعدد المرات، وكل عملية شراء في آخر 7 أيام (حتى 40) مع يوم الأسبوع والساعة والمبلغ والصنف واسم المحل، وعدد مشترياتك في آخر الليل (من 10 مساءً إلى 3 فجرًا) ومجموعها، وما صرفته يومي الجمعة والسبت، وإذا كان حدك محسوبًا من دخلك: المبلغ الباقي للشهر وعدد الأيام الباقية (ولا يُرسل الدخل نفسه أبدًا). تعرض لك الشاشة القائمة نفسها قبل أن توافق. لا يُرسل أي شيء يعرّف بك: لا نص رسالة بنك ولا رقم حساب أو بطاقة ولا رقم هاتف ولا رقم شخصي (CPR) ولا رقم مرجعي ولا تاريخ ولا اسم شخص حوّلت له (تُحذف الأرقام من أسماء المحلات ولا تُرسل التحويلات)، ويرفض الخادم أي حقل آخر. لا يلزم حساب، ولا يُربط الطلب بأي حساب.',
      'يطلب الخادم من نموذج ذكاء اصطناعي (انظر «نماذج الذكاء الاصطناعي») كتابة خطة قصيرة من هذه المعلومات، ويتحقق أن كل رقم في الخطة من الأرقام التي أُعطيت له. ما قد يفعله مزوّد الذكاء الاصطناعي بالطلب مبيّن في «نماذج الذكاء الاصطناعي». لا يحفظ بيزة شيئًا عن الطلب سوى عدد الخطط المطلوبة في ذلك اليوم، دون ربطه بك. الأساس القانوني هو موافقتك، ويمكنك سحبها في أي وقت من شاشة الخطة، وسحبها يوقف أي إرسال لاحق.',
    ],
  },
  {
    title: 'تصنيف المشتريات بالذكاء الاصطناعي (اختياري، بموافقة منفصلة)',
    body: [
      'فقط إذا شغّلته من شاشة السجل، يرسل بيزة إلى خادمه أسماء المحلات التي لم يستطع تصنيفها بنفسه (بعد حذف الأرقام)، ويطلب الخادم من نموذج الذكاء الاصطناعي نفسه اختيار صنف لكل محل. لا يُرسل أي شيء آخر: لا مبلغ ولا تاريخ ولا رقم حساب أو بطاقة ولا نص رسالة ولا أي شيء عنك، ويرفض الخادم أي حقل آخر. يُحفظ الصنف على هاتفك ويمكنك تغييره في أي وقت. لا يحفظ بيزة شيئًا عن الطلب سوى العدد اليومي. ويمكنك إيقافه في أي وقت من المكان نفسه.',
    ],
  },
  {
    title: 'قراءة صور الإيصالات والصوت بالذكاء الاصطناعي (اختيارية، بموافقة منفصلة)',
    body: [
      'فقط إذا شغّلتها من شاشة الإيصال أو الإضافة السريعة: تُرسل صورة الإيصال (بعد تصغيرها على هاتفك) أو تسجيل صوتي حتى 60 ثانية إلى خادم بيزة، الذي يطلب من نموذج ذكاء اصطناعي قراءتها (انظر «نماذج الذكاء الاصطناعي»). قد تُظهر الصورة كل ما في الإيصال، مثل آخر أرقام البطاقة، فقص أو غطِّ ما لا تريد إرساله. لا يحفظ بيزة الصورة ولا التسجيل ولا النص: ترى ما قُرئ وتعدّله قبل الحفظ. بدون هذا الخيار، تُقرأ الصور على هاتفك ويذهب الكلام إلى خدمة الكلام في هاتفك. ويمكنك إيقافها في أي وقت من المكان نفسه.',
    ],
  },
  {
    title: 'نماذج الذكاء الاصطناعي',
    body: [
      'يرسل خادم بيزة كل طلب ذكاء اصطناعي (خطة التوفير، التصنيف، صور الإيصالات، الصوت) أولًا إلى نموذج Gemini من Google عبر خدمتها المجانية. في الخدمة المجانية قد تحتفظ Google بما يُرسل وبالرد، وتستخدمهما لتحسين منتجاتها ونماذجها، وقد يقرؤهما موظفون لديها؛ وتذكر Google أنها تفصلهما أولًا عن حساب بيزة. إذا لم يرد Gemini (مثلًا عند انتهاء الحصة المجانية اليومية)، لا يُسأل أي ذكاء اصطناعي آخر: تُكتب الخطة بالقواعد وتُقرأ الصور والكلام على هاتفك. لا يُرسل مع طلب الذكاء الاصطناعي أي حساب أو اسم أو رقم هاتف. وبسبب شروط Google المجانية، لا ترسل ما لا تريد أن يقرأه شخص، وغطِّ أرقام البطاقة في صورة الإيصال.',
    ],
  },
  {
    title: 'ما يستلمه خادم المزامنة إذا أنشأت حسابًا',
    body: [
      'بريدك الإلكتروني.',
      'بصمة (hash) لمفتاح يُشتق من كلمة السر على هاتفك. كلمة السر نفسها لا تُرسل أبدًا.',
      'بصمة لإثبات يُشتق من مفتاح الاسترجاع. مفتاح الاسترجاع نفسه لا يُرسل أبدًا.',
      'مفتاح بياناتك مقفلًا، بحيث لا يفتحه إلا كلمة السر أو مفتاح الاسترجاع.',
      'معاملاتك وإعداداتك، مشفرة على هاتفك قبل الإرسال. لا نستطيع قراءة المبالغ أو التجار أو التواريخ أو الحدود.',
      'نسخة هذا الإشعار التي وافقت عليها ووقت الموافقة، وبصمات رموز الجلسات، وعدد محاولات الدخول الخاطئة محفوظًا تحت بصمات مفتاحية (بدون بريد أو عنوان IP).',
    ],
  },
  {
    title: 'لماذا، وعلى أي أساس',
    body: [
      'فقط لمزامنة بياناتك بين هواتفك. الأساس القانوني هو موافقتك (المادة 6(1)(أ) من اللائحة الأوروبية GDPR، والقانون البحريني رقم 30 لسنة 2018).',
      'لا إعلانات، ولا تحليلات، ولا بيع أو مشاركة للبيانات، ولا تنميط، ولا قرارات آلية بشأنك. استثناء واحد على هاتفك فقط: إذا شغّلت «العروض حسب صرفي» في العروض التجريبية (أدناه)، تُعرض العروض الوهمية لأكثر أصنافك صرفًا أولًا. ولا يغادر هاتفك شيء من ذلك.',
    ],
  },
  {
    title: 'أين تُحفظ',
    body: [
      'يعمل الخادم على Cloudflare التي تعالج البيانات نيابةً عنا. تُحفظ قاعدة البيانات داخل الاتحاد الأوروبي، وهو ضمن قائمة البحرين للدول ذات الحماية الكافية.',
      'تعالج Cloudflare كل طلب في أقرب موقع، وقد تعالج عنوان IP لتقديم الخدمة وصد الهجمات. بيزة نفسها لا تحفظ عناوين IP.',
    ],
  },
  {
    title: 'المدة',
    body: [
      'حتى تحذف حسابك. تنتهي الجلسات بعد 60 يومًا، وتُصفّر عدادات المحاولات الخاطئة خلال ساعة.',
      'حذف الحساب يمسح كل شيء من قاعدة البيانات فورًا. قد يحتفظ نظام الاسترجاع الزمني في Cloudflare بالبيانات المحذوفة حتى 30 يومًا، ثم تُزال.',
    ],
  },
  {
    title: 'حقوقك',
    body: [
      'الاطلاع على ما يحفظه الخادم عنك: شاشة الحساب في التطبيق.',
      'حذف حسابك وكل بياناتك المتزامنة: شاشة الحساب في التطبيق. وهذا يسحب موافقتك أيضًا، ولا يؤثر على ما تم قبله.',
      'بياناتك تبقى على هاتفك وهي ملكك.',
      'يحق لك تقديم شكوى إلى هيئة حماية البيانات الشخصية في البحرين (تتولى مهامها حاليًا وزارة العدل والشؤون الإسلامية والأوقاف)، أو إلى السلطة الرقابية في بلدك إن كنت في الاتحاد الأوروبي.',
    ],
  },
  {
    title: 'الأمان',
    body: [
      'تشفير من الطرفين (XChaCha20-Poly1305، وArgon2id لكلمة السر)، وقاعدة بيانات مشفرة على الهاتف، وحد لمحاولات الدخول الخاطئة، ولا نسخ احتياطي سحابي للتطبيق.',
      'إذا تأثرت بأي اختراق، نبلّغ الهيئة خلال 72 ساعة ونخبرك. ولأن سجلاتك مشفرة على هاتفك، فاختراق الخادم قد يكشف البريد الإلكتروني لا مصروفاتك.',
    ],
  },
  {
    title: 'العمر',
    body: ['الحسابات لمن عمره 18 سنة فأكثر.'],
  },
  {
    title: 'التغييرات',
    body: ['إذا تغيّر هذا الإشعار تغييرًا مهمًا، يطلب منك التطبيق الموافقة من جديد قبل المزامنة.'],
  },
];

const termsEn: Section[] = [
  {
    title: 'What Beaza is',
    body: [
      'Beaza helps you keep to a daily spending limit by reading bank messages on your phone and alerting you. It is free, and it is a graduation project, not a bank, a payment service or financial advice.',
    ],
  },
  {
    title: 'Accuracy',
    body: [
      'Beaza reads bank messages automatically and can make mistakes: a message may be missed, read wrongly or counted twice. Check important figures against your bank. Decisions about your money remain yours.',
    ],
  },
  {
    title: 'Your account and keys',
    body: [
      'You must be 18 or over to create an account, and an account is for one person\'s own data.',
      'Keep your password and recovery key safe. Because your data is encrypted on your phone, nobody, including us, can open your synced data without them. If you lose both and every signed-in phone, the synced copy cannot be recovered.',
    ],
  },
  {
    title: 'Fair use',
    body: [
      'Do not try to break, overload or get around the security of the server, or use it to store anything other than Beaza\'s own data. Accounts that do so may be closed.',
    ],
  },
  {
    title: 'Availability',
    body: [
      'We try to keep sync running but cannot promise it will always be available. If the service is going to stop, we will say so in the app in advance. Your data always remains on your phone, and the app keeps working without sync.',
    ],
  },
  {
    title: 'Ending',
    body: [
      'You can delete your account at any time from the Account screen. This deletes your synced data; the data on your phone stays until you remove the app.',
    ],
  },
  {
    title: 'Liability',
    body: [
      'Beaza is provided as it is. As far as the law allows, we are not liable for losses that come from relying on its figures or alerts. Nothing here limits rights you have by law.',
    ],
  },
  {
    title: 'Law and changes',
    body: [
      'These terms are governed by the laws of the Kingdom of Bahrain. If they change in a way that matters, the app asks you to agree again before syncing. How we handle personal data is described separately in the privacy notice.',
    ],
  },
];

const termsAr: Section[] = [
  {
    title: 'ما هي بيزة',
    body: [
      'تساعدك بيزة على الالتزام بحد يومي للصرف، فتقرأ رسائل البنك على هاتفك وتنبهك. التطبيق مجاني، وهو مشروع تخرج، وليس بنكًا ولا خدمة دفع ولا نصيحة مالية.',
    ],
  },
  {
    title: 'الدقة',
    body: [
      'تقرأ بيزة رسائل البنك تلقائيًا وقد تخطئ: قد تفوتها رسالة، أو تقرأها خطأ، أو تحسبها مرتين. راجع الأرقام المهمة مع بنكك. والقرارات المتعلقة بمالك تبقى قراراتك.',
    ],
  },
  {
    title: 'حسابك ومفاتيحك',
    body: [
      'يجب أن يكون عمرك 18 سنة فأكثر لإنشاء حساب، والحساب لبيانات شخص واحد فقط.',
      'احفظ كلمة السر ومفتاح الاسترجاع في مكان آمن. لأن بياناتك مشفرة على هاتفك، لا يستطيع أحد، ولا نحن، فتح بياناتك المتزامنة بدونهما. إذا فقدتهما معًا وفقدت كل الهواتف المسجلة، لا يمكن استرجاع النسخة المتزامنة.',
    ],
  },
  {
    title: 'الاستخدام العادل',
    body: [
      'لا تحاول تعطيل الخادم أو إثقاله أو تجاوز حمايته، ولا تستخدمه لتخزين أي شيء غير بيانات بيزة. قد تُغلق الحسابات التي تفعل ذلك.',
    ],
  },
  {
    title: 'التوفر',
    body: [
      'نحاول إبقاء المزامنة تعمل، لكن لا نضمن توفرها دائمًا. إذا كانت الخدمة ستتوقف، نعلن ذلك في التطبيق مسبقًا. تبقى بياناتك دائمًا على هاتفك، ويعمل التطبيق بدون مزامنة.',
    ],
  },
  {
    title: 'إنهاء الحساب',
    body: [
      'يمكنك حذف حسابك في أي وقت من شاشة الحساب. يحذف ذلك بياناتك المتزامنة، وتبقى البيانات على هاتفك حتى تزيل التطبيق.',
    ],
  },
  {
    title: 'المسؤولية',
    body: [
      'تُقدَّم بيزة كما هي. وبالقدر الذي يسمح به القانون، لا نتحمل مسؤولية خسائر ناتجة عن الاعتماد على أرقامها أو تنبيهاتها. ولا شيء هنا يحدّ من حقوقك بموجب القانون.',
    ],
  },
  {
    title: 'القانون والتغييرات',
    body: [
      'تخضع هذه الشروط لقوانين مملكة البحرين. إذا تغيّرت تغييرًا مهمًا، يطلب منك التطبيق الموافقة من جديد قبل المزامنة. أما طريقة تعاملنا مع البيانات الشخصية فموضحة بشكل منفصل في إشعار الخصوصية.',
    ],
  },
];

function escape(text: string): string {
  return text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

function render(sections: Section[], heading: string, lang: string, dir: string): string {
  const body = sections
    .map(
      (s) =>
        `<h2>${escape(s.title)}</h2>${s.body.map((p) => `<p>${escape(p)}</p>`).join('')}`,
    )
    .join('');
  return `<section lang="${lang}" dir="${dir}"><h1>${escape(heading)}</h1>${body}</section>`;
}

export const documents = {
  privacy: {
    version: PRIVACY_VERSION,
    title: { ar: 'إشعار الخصوصية لتطبيق بيزة', en: 'Beaza privacy notice' },
    ar,
    en,
  },
  terms: {
    version: TERMS_VERSION,
    title: { ar: 'شروط استخدام بيزة', en: 'Beaza terms of use' },
    ar: termsAr,
    en: termsEn,
  },
};

export type LegalDocument = keyof typeof documents;

export function legalPage(kind: LegalDocument, contact?: string): string {
  const doc = documents[kind];
  const contactEn = contact ? `<p>Contact: ${escape(contact)}</p>` : '';
  const contactAr = contact ? `<p dir="rtl">للتواصل: ${escape(contact)}</p>` : '';
  const other = kind === 'privacy' ? 'terms' : 'privacy';
  const otherTitle = documents[other].title;
  return `<!doctype html>
<html lang="ar">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(doc.title.en)} · ${escape(doc.title.ar)}</title>
<style>
  :root { color-scheme: light dark; --fg: #1d1d1f; --bg: #fafaf7; --muted: #5f6368; --link: #0b57d0; }
  @media (prefers-color-scheme: dark) { :root { --fg: #ececec; --bg: #161616; --muted: #a0a4a8; --link: #a8c7fa; } }
  body { margin: 0 auto; max-width: 720px; padding: 24px 16px 64px; font: 16px/1.6 system-ui, sans-serif; color: var(--fg); background: var(--bg); }
  h1 { font-size: 1.5rem; margin-top: 2rem; }
  h2 { font-size: 1.05rem; margin: 1.6rem 0 .3rem; }
  p { margin: .4rem 0; }
  a { color: var(--link); }
  .meta { color: var(--muted); font-size: .9rem; }
  hr { border: 0; border-top: 1px solid var(--muted); opacity: .3; margin: 2.5rem 0; }
</style>
</head>
<body>
<p class="meta">Version ${doc.version} · <a href="/${other}">${escape(otherTitle.ar)} · ${escape(otherTitle.en)}</a></p>
${render(doc.ar, doc.title.ar, 'ar', 'rtl')}
${contactAr}
<hr>
${render(doc.en, doc.title.en, 'en', 'ltr')}
${contactEn}
</body>
</html>`;
}
