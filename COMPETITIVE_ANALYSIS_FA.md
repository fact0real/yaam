<div dir="rtl">

# ارزیابی رقابتی YAAM در بازار نرم‌افزارهای لاگ آماتور رادیویی

تاریخ بازنگری: ۲۲ اوت ۲۰۲۶

## جمع‌بندی مدیریتی

YAAM اکنون یک ابزار ساده برای نمایش ADIF نیست. مجموعه قابلیت‌های فعلی آن شامل پایگاه داده محلی، پروفایل‌های ایستگاه، ورود سریع QSO، تشخیص تکراری، همگام‌سازی تأییدها، پیگیری QRZ Rank، تقویم مسابقات، میز کار اپراتور، مانیتور ۶ متر، DX Cluster، DXpedition Advisor، جوایز QRZ و LoTW و تحلیل آماری است.

با این حال YAAM هنوز جایگزین کامل نرم‌افزارهای بالغی مانند Log4OM، Ham Radio Deluxe، RUMlogNG، MacLoggerDX یا N1MM Logger+ نیست. مهم‌ترین فاصله در گستردگی کنترل سخت‌افزار، پشتیبانی مسابقه‌ای عمیق، تعداد موتورهای جایزه، چندکاربره بودن و بلوغ اتصال زنده به اکوسیستم دیجیتال است.

جایگاه واقع‌بینانه فعلی YAAM چنین است:

> یک لاگ‌بوک بومی macOS با تمرکز متمایز بر کیفیت داده، هوشمندی تأیید تماس، پیگیری QRZ/LoTW، تحلیل رقبا و تصمیم‌یار عملیاتی برای اپراتور.

## جدول مقایسه به‌روز

| نیاز اپراتور | وضعیت واقعی YAAM | معیار و مزیت رقبا | شکاف YAAM | اولویت |
|---|---|---|---|---|
| ورود سریع QSO هنگام کار | Quick Log، انتقال از DX Spot، کنترل تکراری و تکمیل از QRZ/HAMQTH دارد | HRD، Log4OM، RUMlogNG و MacLoggerDX سال‌ها گردش‌کار ثبت زنده و اتصال رادیو را پالایش کرده‌اند | فرم زنده YAAM جدیدتر است و به آزمون گسترده با رادیوها و شیوه‌های کاری مختلف نیاز دارد | P0 |
| CAT و دریافت Frequency/Mode | Hamlib rigctld و مسیر اولیه اتصال شبکه‌ای Icom دارد | HRD و MacLoggerDX کنترل یکپارچه تجهیزات دارند؛ Log4OM و RUMlogNG پوشش CAT وسیع و آزموده دارند | پوشش مدل‌ها، کنترل پنل، rotor/keyer و بازیابی خطا هنوز محدودتر است | P0 |
| WSJT-X/JTDX و FT8 زنده | ورودی دیجیتال، پایش فایل و میز FT8 در مسیر محصول وجود دارد | Log4OM در UDP و multicast بسیار منعطف است؛ GridTracker نمایش زنده ترافیک، roster و هشدارهای قوی دارد | پایداری UDP، بازخورد Worked/New لحظه‌ای و پوشش سناریوهای شبکه‌ای باید عمیق‌تر شود | P0 |
| اصلاح، غنی‌سازی و تبدیل ADIF | یکی از بخش‌های قوی YAAM است؛ فیلتر، تبدیل، تکمیل داده و ورود SmartSDR دارد | ابزارهای مطرح معمولاً واردات و ویرایش ADIF را دارند، اما تمرکز YAAM بر پاک‌سازی و غنی‌سازی متمایز است | نیاز به گزارش ممیزی تغییرات و undo سطح رکورد دارد | P1 |
| جلوگیری و حذف Duplicate | کلید دقیق QSO، جلوگیری هنگام import و ابزار بازبینی دارد | رقبا تشخیص قابل تنظیم و کنترل تعارض دارند | باید similarity score، ادغام فیلد به فیلد و پیش‌نمایش تصمیم بهتر شود | P1 |
| دریافت تأییدهای LoTW و QRZ | QSL Hub، Sync و Full History دارد و وضعیت محلی را نگه می‌دارد | HRD، Log4OM و RUMlogNG اتصال‌های دوطرفه چندسرویسی بالغ‌تری دارند | تطبیق شمارش ابری و محلی، resume و گزارش علت رکوردهای unmatched باید دائماً آزموده شود | P0 |
| eQSL و Club Log | تنظیمات و گردش‌کار سرویس در محصول وجود دارد | در HRD، Log4OM و RUMlogNG این سرویس‌ها بخشی جاافتاده از گردش‌کار روزانه‌اند | عمق دریافت، ارسال، گزارش اختلاف و retry باید هم‌سطح QRZ/LoTW شود | P1 |
| Award Tracking | QRZ Awards، وضعیت LoTW و پیشرفت محلی DXCC/WAS/6m دارد | HRD بیش از ۲۰۰ جایزه، Log4OM بیش از ۴۰ جایزه و Wavelog بیش از ۲۰ جایزه را اعلام می‌کنند؛ موتورهای قابل تنظیم نیز دارند | موتور قواعد عمومی، creditهای submitted/granted و برنامه‌های IOTA/POTA/SOTA/VUCC کامل نیست | P0 |
| ارزش تأیید هر QSO | ستون‌های BAND CREDIT و GRID CREDIT و ماتریس Country Bands اکنون موجود است | بیشتر رقبا Worked/Confirmed/Needed را در سطح جایزه یا spot نشان می‌دهند | این بخش فرصت تمایز YAAM است و باید به صف اقدام و امتیاز اولویت تبدیل شود | مزیت YAAM |
| DX Cluster و RBN | DX Cluster، watchlist و انتقال spot به Quick Log دارد | HRD، Log4OM، MacLoggerDX و GridTracker bandmap، roster و هشدارهای بالغ‌تری دارند | RBN کامل، نقشه باند تعاملی و overlay نیازهای award هنوز محدود است | P1 |
| پیش‌بینی انتشار | داشبورد انتشار، PSK Reporter، شواهد ۶ متر و تمرکز خاورمیانه دارد | Log4OM از VOACAP استفاده می‌کند؛ رقبا نقشه و grayline جاافتاده‌تری دارند | مدل مسیر نقطه‌به‌نقطه، احتمال زمانی و اعتبارسنجی پیش‌بینی با داده زنده لازم است | P1 |
| مسابقه | تقویم، علاقه‌مندی، workspace، dupe check، serial/exchange و Cabrillo دارد | N1MM Logger+ و RUMlogNG دارای scoring، multiplier، ESM، شبکه چنداپراتوری و پوشش گسترده مسابقات‌اند | YAAM هنوز contest logger تخصصی نیست؛ قواعد رسمی و امتیاز زنده کم است | P0 برای بازار Contest، وگرنه P2 |
| POTA/SOTA/IOTA/VUCC | داده‌های عمومی ADIF را نگه می‌دارد، اما موتور جامع اختصاصی ندارد | Wavelog، HRD و برخی رقبا گردش‌کارهای فعالیت و award اختصاصی دارند | فرم فعال‌سازی، reference lookup، spot و گزارش award لازم است | P1 |
| چند Station Profile و QTH | پروفایل‌های مستقل با callsign، مکان، بازه زمانی و هویت سرویس دارد | Wavelog پروفایل ایستگاه و چندکاربر را در معماری وب ارائه می‌کند | همگام‌سازی بین دستگاه‌ها و تاریخچه نسخه‌دار پروفایل وجود ندارد | P1 |
| Cloud، موبایل و Multi-Op | داده محلی و ابزارهای cloud logbook دارد | Wavelog ذاتاً وب و چندکاربره است؛ N1MM شبکه مسابقه‌ای و HRD اشتراک شبکه دارد | اپ همراه، همگام‌سازی امن چندمک و ویرایش همزمان وجود ندارد | P1 |
| پیگیری تأیید و ارتباط انسانی | incoming QRZ، ایمیل درخواست جزئیات، QSL Card، follow-up و قالب‌های شخصی دارد | این زنجیره در بسیاری از رقبا پراکنده یا کمتر یکپارچه است | باید به inbox عملیاتی با وضعیت ارسال، پاسخ و reminder تبدیل شود | مزیت YAAM |
| رتبه و رقابت QRZ | تاریخچه روزانه، rival tracking، مقایسه فاصله و بازخورد عملکرد دارد | قابلیت مشابه یکپارچه در لاگ‌بوک‌های اصلی کمتر دیده می‌شود | کیفیت snapshot، تفسیر تغییر رتبه و حفظ تاریخچه بلندمدت باید تضمین شود | مزیت YAAM |
| امنیت و مالکیت داده | SQLite محلی، backup/restore، restore point و Keychain دارد | برنامه‌های دسکتاپ نیز محلی‌اند؛ Wavelog امکان self-hosting می‌دهد | export قابل ممیزی، رمزنگاری backup و تست بازیابی خودکار قابل تقویت است | P1 |
| راهنما و onboarding | راهنمای تصویری/مرحله‌ای درون برنامه برای گردش‌کارهای اصلی دارد | رقبا مستندات چندساله و جامعه کاربری بزرگ‌تری دارند | جست‌وجوی راهنما، ویدئوی کوتاه، troubleshooting و نمونه تنظیم تجهیزات لازم است | P1 |

## مزیت‌هایی که رقبا دارند و YAAM هنوز ندارد

### P0: مانع جایگزینی لاگر اصلی

1. **کنترل سخت‌افزار بالغ و گسترده**: ماتریس آزموده رادیو، rotor، keyer، modem و خطاهای اتصال.
2. **مسابقه حرفه‌ای**: scoring و multiplier زنده، ESM، قواعد exchange، شبکه Multi-Op و پوشش تعداد زیادی contest.
3. **موتور award عمومی**: تعریف داده‌محور جایزه، creditهای worked/confirmed/submitted/granted و ده‌ها برنامه رسمی.
4. **همگام‌سازی تأیید قابل حسابرسی**: شمارنده ابری و محلی، فهرست unmatched، علت رد تطبیق، resume و retry قابل مشاهده.
5. **اتصال دیجیتال لحظه‌ای بالغ**: UDP/multicast، roster زنده، bandmap و Worked/New feedback با تأخیر بسیار کم.

### P1: مانع رشد روزانه

1. همگام‌سازی امن چند دستگاه و تجربه موبایل.
2. اتصال عمیق RBN و DX Cluster با bandmap و هشدار نیاز جایزه.
3. موتورهای اختصاصی POTA، SOTA، IOTA و VUCC.
4. propagation نقطه‌به‌نقطه با مدل VOACAP و اعتبارسنجی بر اساس reception report.
5. undo و audit trail کامل برای import، merge، enrichment و حذف.

### P2: بلوغ محصول

1. افزونه‌ها، API عمومی پایدار و اتوماسیون کاربر.
2. dashboard قابل شخصی‌سازی و layoutهای ذخیره‌شدنی.
3. مستندات troubleshooting گسترده، ویدئو و جامعه کاربری.

## مزیت رقابتی پیشنهادی برای سرمایه‌گذاری اکنون

### Next Credit Engine

بهترین سرمایه‌گذاری کوتاه‌مدت YAAM تقلید کامل از همه قابلیت‌های رقبا نیست. پیشنهاد اصلی، تبدیل هوشمندی فعلی تأیید تماس به یک موتور تصمیم‌یار کامل است:

1. هر QSO تأییدنشده بر اساس ارزش احتمالی امتیاز بگیرد: کشور جدید، country-band جدید، grid جدید، award credit و کمیابی تماس.
2. یک **Confirmation Opportunity Queue** بسازد و بهترین تماس‌ها را برای پیگیری در ابتدای فهرست قرار دهد.
3. برای هر مورد به زبان ساده توضیح دهد: «تأیید این تماس، اولین تأیید کامرون روی ۱۷ متر و یک grid جدید است.»
4. اقدام یک‌کلیکی برای ایمیل، کارت QSL، QRZ Incoming یا یادآوری ارائه کند و تاریخچه تماس انسانی را نگه دارد.
5. همان intelligence را روی DX Cluster، FT8 roster و DXpeditionها نمایش دهد تا اپراتور پیش از QSO بداند کدام تماس بیشترین ارزش را دارد.
6. در مرحله بعد قواعد awardهای DXCC، WAS، VUCC، IOTA، POTA و SOTA را به همین امتیاز متصل کند.

دو ستون جدید و ماتریس Country Bands، نسخه نخست و قابل استفاده این مسیر هستند. این جهت‌گیری با هویت فعلی YAAM هماهنگ است و به جای رقابت مستقیم با دهه‌ها توسعه CAT و Contest، مزیتی می‌سازد که برای اپراتور قابل فهم، روزانه و قابل اقدام است.

## نتیجه نهایی

YAAM از نظر مدیریت و تحلیل پس از تماس، دیگر یک پروژه ابتدایی نیست و در چند حوزه مانند پیگیری QRZ Rank، تأیید هدفمند، incoming follow-up و تحلیل ۶ متر خاورمیانه ویژگی‌های کم‌رقیب دارد. در عین حال برای معرفی به عنوان «جایگزین کامل لاگر اصلی» هنوز زود است. مناسب‌ترین پیام محصول در وضعیت فعلی این است:

> YAAM یک لاگ‌بوک هوشمند macOS برای تبدیل داده تماس و تأییدها به تصمیم بعدی اپراتور است.

## منابع رسمی مقایسه

- [Log4OM Features](https://www.log4om.com/features/)، [Award Centered](https://www.log4om.com/award-centered/) و [Integrated](https://www.log4om.com/integrated/)
- [Ham Radio Deluxe Logbook](https://www.hamradiodeluxe.com/features/logbook/) و [Awards Tracking](https://support.hamradiodeluxe.com/support/solutions/articles/51000052700-awards-tracking)
- [RUMlogNG Documentation](https://dl2rum.de/RUMlogNG/docs/en/) و [Online Functions](https://dl2rum.de/RUMlogNG/docs/en/pages/Online-Funktionen.html)
- [MacLoggerDX Help](https://www.dogparksoftware.com/MacLoggerDX%20Help/)
- [Wavelog](https://www.wavelog.org/)، [Dashboard Guide](https://docs.wavelog.org/user-guide/logbook/dashboard/) و [Source Repository](https://github.com/wavelog/wavelog)
- [N1MM Logger+ Features](https://n1mmwp.hamdocs.com/n1mm-features/)
- [GridTracker](https://gridtracker.org/) و [Control Panel Guide](https://docs.gridtracker.org/latest/GridTracker-Overview/Control-Panel.html)

</div>
