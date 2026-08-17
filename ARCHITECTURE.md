# MeetingNotch Architecture

Bu belge ürün vizyonunu uygulama yapısına dönüştüren yaşayan mimari rehberdir.
Ürün kapsamının ana kaynağı `PRODUCT_PLAN.md`, araştırma notlarının kaynağı ise
`project-overview.md` dosyasıdır. Teknik detaylar ürün deneyimi gerektirdiğinde
değiştirilebilir.

## Proje üretimi

- Xcode projesinin tek yapılandırma kaynağı `project.yml` dosyasıdır.
- `MeetingNotch.xcodeproj/project.pbxproj` elle düzenlenmez.
- Proje değişikliklerinden sonra kök dizinde `xcodegen generate` çalıştırılır.
- DynamicNotchKit sürümü `project.yml` içinde sabit bir alt sınırla tanımlanır.
- Minimum sistem sürümü macOS 14.4'tür.
- Uygulama `LSUIElement` agent olarak çalışır ve App Sandbox kapalıdır. V1 dağıtımı
  Developer ID imzası ve notarization ile doğrudan yapılır; Mac App Store hedeflenmez.
- Debug uygulaması sabit development team ile Apple Development imzası taşır; bu kimlik
  macOS TCC izinlerinin yeniden build'ler arasında aynı uygulamayla ilişkilendirilmesini
  sağlar. Hardened Runtime mikrofon erişimi dar kapsamlı audio-input entitlement'ıyla açılır.

## Katmanlar

```text
MeetingNotch/
  App/              Uygulama yaşam döngüsü, AppDelegate ve ortak AppState
  Domain/           Saf ürün modelleri ve durum makinesi
  Features/
    Notch/          Kompakt/genişletilmiş notch deneyimi
    Meetings/       Yaklaşan toplantı, kayıt ve toplantı geçmişi UI'ı
    Tasks/          Aktif görevler ve arşiv UI'ı
    Settings/       Onboarding, izinler ve tercihler
  Services/
    Audio/          Mikrofon, sistem sesi, senkronizasyon ve encode
    Calendar/       EventKit sorguları ve planlanmış meeting bağlamı
    Meeting/        İstemci/process sinyalleri, session detector ve mute adapter'ları
    Transcription/  Tek ElevenLabs servisi ve test edilebilir HTTP sınırı
    Summary/        Özet, karar ve aksiyon maddesi üretimi
  Infrastructure/
    Persistence/    Dosya tabanlı repository'ler ve recovery
    Security/       Keychain ve hassas veri kuralları
    Logging/        Hassas veri içermeyen tanılama
  Resources/        Asset ve lokalizasyon kaynakları
```

Klasörler ihtiyaç oldukça açılır; boş mimari katman oluşturulmaz.

## Bağımlılık kuralları

- View'lar doğrudan dosya sistemi, EventKit, Core Audio veya uzak API çağırmaz.
- Feature katmanı domain modellerini ve protokolleri kullanır.
- ElevenLabs response modelleri servis sınırının dışına çıkmaz.
- Domain katmanı DynamicNotchKit, AppKit ve ağ istemcilerinden bağımsız kalır.
- Ana UI durumu `AppState` üzerinden gözlemlenir; gerçek iş servisler tarafından yapılır.
- Uzun işler iptal edilebilir `async` operasyonlar olarak tasarlanır.
- Tek ElevenLabs API anahtarı yalnızca Keychain'de tutulur.
- Meeting client adapter'ları Accessibility UI metinlerini domain'e taşımaz; yalnız
  normalize kanıt ve `open/closed/unknown` mute durumu üretir.
- Algılama belirsizliği UI'da kesin duruma yükseltilmez. Mikrofon gate'i belirsizlikte
  fail-closed davranır.

## Ana ürün akışı

İlk açılış sırası tanıtım → mikrofon → sistem sesi → isteğe bağlı takvim → bulut işleme
bilgilendirmesidir. Onboarding kararı ayar belgesinde saklanır ve Ayarlar'dan sıfırlanabilir.
İzin reddi manuel kayıt erişimini gizlemez; kayıt öncesi doğrulama kullanıcıyı ilgili düzeltme
aksiyonuna yönlendirir.

```text
idle
  -> upcomingMeeting
  -> preparingRecording
  -> recording
  -> finalizingAudio
  -> uploading
  -> transcribing
  -> summarizing
  -> completed
```

Her aşama `cancelled` veya `failed(retryable:)` durumuna geçebilir. UI bu akışın
görünümüdür; kayıt ve işleme yaşam döngüsü UI penceresinin açık olmasına bağlı değildir.

## Toplantı session algılama sınırı

Takvim etkinliği yalnız planlanmış bağlamdır; gerçek çağrı yaşam döngüsünün kanıtı değildir.
Session detector dört yerel kaynaktan normalize kanıt toplar:

- EventKit meeting kimliği, URL'si, başlangıç/bitiş aralığı.
- MeetingNotch `Katıl` aksiyonunun açtığı URL ve ardından görülen process/window.
- Core Audio process nesnesinin bundle ID/PID ve `isRunningInput` / `isRunningOutput`
  değişiklikleri.
- Desteklenen istemciye ait Accessibility adapter'ının meeting window, call controls ve
  mute control durumu.

`MeetingSession` domain modeli `scheduled`, `candidate`, `ready`, `recording`,
`endSuspected`, `ended` durumlarını; `unknown`, `probable`, `confirmed` güven seviyesini ve
kanıt setini taşır. Kurallar deterministic ve fixture-test edilebilir olur. Tek başına
takvim saati, process'in açık olması veya uzun sessizlik `confirmed` başlangıç/bitiş
üretmez.

`CoreAudioProcessMonitor`, HAL process object listesini bundle ID/PID ile normalize eder ve
`isRunningInput` / `isRunningOutput` snapshot'ını yalnız değiştiğinde yayınlar. Polling
yaşam döngüsü UI'dan bağımsızdır; session coordinator yalnız desteklenen bundle ID'leri
kanıta dönüştürür. Bu sinyal mute durumu olarak yorumlanmaz.

`AccessibilityMeetingClientAdapter`, Core Audio snapshot'ındaki bundle ID/PID'yi Zoom
Workplace veya Google Meet/Chrome istemcisine eşler. Sistem güveni yoksa ağaç okunmaz;
adapter `accessibilityPermissionRequired`, görünmeyen UI kanıtı ve `unknown` mikrofon
durumuyla fail-closed snapshot üretir. İzin istemi yalnız kullanıcı aksiyonuyla
`promptForAccessibility` açıldığında tetiklenir; desteklenmeyen process izin istemez.

İzin varken Accessibility ağacı derinlik ve node sayısı sınırıyla bellekte taranır. Ham
başlık, açıklama, URL veya control metni loglanmaz ve domain'e taşınmaz; adapter yalnız
`meetingWindowPresent`, `callControlsPresent` ve `open/closed/unknown` normalize sonucunu
yayınlar. Zoom meeting/end/microphone kontrolleri istemci penceresinde, Google Meet ise
`meet.google.com`/Google Meet bağlamı bulunan Chrome penceresinde aranır. Sıradan Chrome
penceresi veya yalnız “mute” benzeri ilgisiz bir web kontrolü meeting kanıtı sayılmaz.

V1'in zorunlu kalite kapıları Zoom Workplace native istemcisi ve Google Meet/Chrome'dur.
Her ikisi için gerçek başlangıç/bitiş, call controls ve mute durumu normalize adapter
kanıtlarıyla üretilir. Chrome process'i birden fazla sekmenin sesini taşıyabildiğinden,
Google Meet kaydı toplantı sekmesi dışındaki sesi dışladığını canary-audio testiyle
kanıtlamadan global veya process-wide kayda sessizce düşmez. İzolasyon kaybolursa kayıt
fail-closed olur ve UI güvenli fallback'i açıkça gösterir. Diğer istemciler manuel kayıt
moduna düşer; UI otomatik algılama iddiasında bulunmaz.

Google Meet system audio izolasyonu Chrome'un process sınırından çıkarılamaz. Bu istemcide
tek güvenli production yolu ayrı Manifest V3 extension'dır: kullanıcı aktif Meet sekmesinde
extension action'ı açar; popup seçili sekme sesinin yerel uygulamada nasıl işleneceğini ve
kayıt sonrası ElevenLabs sınırını yakalama öncesi açıkça gösterir. Kullanıcının `Meet sekmesini
bağla` onayıyla `chrome.tabCapture.getMediaStreamId()` yalnız o sekme için stream üretir ve
offscreen document stream'i tüketirken sesi tekrar yerel çıkışa bağlar. Extension ID'si
sabittir; başka origin, kullanıcı gesture'ı olmayan başlangıç veya native bridge kaybı
capture başlatmaz ya da anında fail-closed durdurur. Store ZIP'i yalnız runtime dosyalarını
taşır; ikonlar ve checksum deterministik paket betiğiyle üretilir. Web Store item ID'si native
host allowlist'iyle eşleşmeden production yayını yapılmaz.

Offscreen audio worklet 48 kHz hedefli küçük PCM S16LE frame'leri sıra numarası ve rastgele
session UUID ile üretir. Frame'ler yalnız sabit origin allowlist'li Chrome native messaging
host'una gider. Helper mesaj boyutu, sample rate, kanal, sıra, session nonce ve backpressure
kurallarını doğruladıktan sonra uygulamanın kullanıcıya özel IPC kanalına aktarır; extension
veya helper tek başına kalıcı toplantı dosyası seçemez. Meeting URL'sinin path'i, başlık,
DOM metni ve ses içeriği loglanmaz. Chrome Web Store kurulumu ve action tıklaması onboarding
üzerinde açık bir Google Meet önkoşuludur.

Native sınır iki ayrı doğrulamadan oluşur. `MeetingNotchBrowserAudioHost`, Chrome'un 4-byte
little-endian framed stdio mesajını sabit extension origin, session UUID, sequence, PCM boyutu,
sample rate ve kanal sayısıyla doğrular. Doğrulanmış event, yalnız o kullanıcı için `0700`
geçici dizin ve `0600` Unix socket üzerinden `BrowserAudioIPCServer`'a taşınır; socket yazımı
`SO_NOSIGPIPE` ile uygulama sürecini kopuk peer'dan korur. `BrowserAudioStreamBroker` session
ve sequence'i yeniden doğrular; `BrowserAudioCaptureSource` yalnız aktif broker session'ında
PCM'i 48 kHz mono AAC M4A'ya dönüştürür. Host/IPC/tab kopması `.pipelineStalled` üretip mevcut
güvenli-finalize yolunu tetikler. Uygulama paketi helper'ı `Contents/Library/LaunchServices`
altında taşır ve Chrome native-host manifestini yalnız sabit origin ile kullanıcı hesabına
kurar. UI `kullanılamıyor / sekme bekleniyor / bağlı / kayıt hattına bağlı` durumunu gösterir.

Algılama kaydı habersiz başlatmaz. `confirmed` başlangıç kayıt teklifini görünür yapar.
Kayıt sürerken `confirmed` bitiş iptal edilebilir kısa geri sayım başlatır; `probable`
bitiş yalnız kullanıcıya sorulur. Manuel başlat/durdur her durumda kullanılabilir kalır.

## Notch yaşam döngüsü

- Uygulama açıldığında desteklenen cihazda kompakt notch görünümü hazırlanır.
- Menü çubuğu ikonu notch görünür olmadığında da ürüne erişim sağlar.
- Fiziksel notch bulunmayan ekranda DynamicNotchKit floating görünümü kullanılır.
- Floating görünüm kompakt modu desteklemez; menü veya hover aksiyonu paneli genişletir,
  kompakt duruma dönüş paneli gizler ve menü çubuğu erişimi kalıcı olarak korur.
- Öncelik sırası: kayıt > işleme/hata > yaklaşan toplantı > görev rozeti > boşta.
- Kompakt görünüm hazırlama, finalize, upload, transkripsiyon ve özet aşamalarını kendi
  ilerleme göstergesiyle taşır; daha düşük öncelikli toplantı veya görev bilgisi işleme
  durumunu örtemez. Başarı ve hata paneli otomatik açılır; etkileşim yoksa 8 saniye sonra
  kompakt duruma döner, başarı akışı boşta durumuna sıfırlanırken hata kurtarma için korunur.
- Geniş panel aktif ekranın görünür alanına göre toplantı/görev kökünde en fazla 424 piksel,
  uzun transkript taşıyan notch içi detail drill-down'ında en fazla 520 piksel genişlik ve
  600 piksel içerik yüksekliği kullanır; daha küçük alanlarda içerik kaydırılır. Sekmeler
  ok tuşları ve Komut-1/Komut-2 ile değiştirilebilir.
- DynamicNotchKit açılma, kapanma ve kompakt/geniş dönüşümleri uygulamanın hareket profiliyle
  yapılandırılır. macOS Reduce Motion değişikliği canlı izlenir ve etkin olduğunda hem panel
  içi hem pencere geçişleri algılanabilir hareket üretmeyecek kadar kısaltılır.
- 2026-07-29 görsel yönü kök panelde 404–424, detail'da 480–520 piksel akışkan genişlik;
  8 piksel yatay / 10 piksel dikey dış padding, 12–14 piksel bölüm aralığı, 10–12 piksel
  radius ve 11–14 pt type scale kullanır. Başlıklar sans, metadata/süre/sayaçlar mono olur.
  İkon glyph'leri 11–13 pt olur; erişilebilir macOS hit target'ları 28–32 piksel korunur.
- Yüzeyler nötr koyu/açık zemin, tek hairline ve yalnız durum rengi vurgusuyla çalışır.
  Büyük dekoratif gölgeler ve iç içe kartlar kullanılmaz. Kompakt görünüm session durumu,
  kayıt süresi ve meeting mic gate'ini tek bakışta taşır.
- DynamicNotchKit fiziksel notch yüzeyini daima siyah çizdiği için bu ekrandaki expanded ve
  compact içerik açık sistem temasında da koyu `ColorScheme` kullanır. Notch olmayan floating
  panel sistem görünümünü miras almaya devam eder. Sekme layout'u seçili durum animasyonunda
  yeniden ölçülmez; iki sekme her frame'de görünür kalır, yalnız renk ve yüzey durumu değişir.

## Veri yaklaşımı

- V1'de veritabanı yoktur; toplantı ve görevler Application Support altında saklanır.
- Bir toplantı belgesi kararlı kimlik, başlık, başlangıç/bitiş, kaynak takvim kimliği ve URL,
  işlem durumu, normalize hata kodu ve ilişkili dosya adlarını taşır. Normalize
  transkript konuşmacı ve zaman damgalı segmentleri; özet çıktısı genel özet, kararlar ve
  sorumlu/tarih bilgisi uydurulmadan çıkarılan aksiyon maddelerini taşır.
- Yazımlar atomik yapılır ve yarım kayıtlar Recovery alanında korunur.
- Her toplantı kararlı bir UUID ile ses, metadata ve Markdown çıktısını ilişkilendirir.
- Başarılı işleme, normalize `transcript.json` yanında kullanıcı tarafından doğrudan
  açılabilen `meeting.md` üretir. Markdown toplantı metadata'sı, kısa notlar, kararlar,
  aksiyonlar ve konuşmacı-zaman damgalı tam transkripti aynı UUID altında taşır.
- Repository formatları şema sürümü taşır.
- Tek ElevenLabs API anahtarı generic-password öğesi olarak yalnız macOS Keychain'deki
  `elevenlabs-api-key` hesabında ve `ThisDeviceOnly` erişilebilirlik sınıfında tutulur. Eski
  provider kimlikli `elevenLabs` hesabı yeni öğe başarıyla yazıldıktan sonra kayıpsız
  migrate edilir ve eski öğe silinir.
- API anahtarları tercih modellerine ve hata değerlerine eklenmez; serbest biçimli hata
  ayrıntıları OSLog'a hiç gönderilmez. Tanılama yalnızca sabit operasyon kodu, hata tipi,
  akış fazı ve hassas olmayan sayaçları taşır; kalıcı işleme hataları da serbest provider
  mesajı yerine normalize edilmiş hata kodu saklar. V1'de analytics SDK'sı yoktur.
- Fiziksel session kabulünde kullanılan `meeting-session` OSLog kategorisi yalnız rastgele
  session UUID'si, normalize state/confidence/client/microphone ve evidence türlerini taşır.
  PID, takvim kimliği, meeting URL'si, pencere/rol metni veya görüşme içeriği loglanmaz.
  QA collector bu kayıtları geçici NDJSON kanıtına çevirir; production analytics veya kalıcı
  kullanıcı profili oluşturmaz.
- Toplantı saklama politikası ayar belgesinde tutulur ve eksik alan süresiz saklama olarak
  geriye uyumlu okunur. Süre seçilmişse açılışta ve 24 saatte bir çalışan servis, bitiş
  zamanı eşik öncesinde kalan toplantı klasörlerini repository üzerinden serialize ederek
  siler; kısmi silme hataları kalan kayıtların temizliğini durdurmaz.
- Birleşik M4A varsayılan olarak toplantıyla süresiz saklanır; kullanıcı tüm toplantı
  verileri için 7, 30 veya 90 gün seçebilir. Ayrı ham kaynak parçaları yalnızca başarılı
  işleme sonrasında silinir, kurtarılabilir hata halinde korunur.
- Finalize edilen her kayıt `ProcessingQueue/queue.json` içindeki sürümlü ve atomik kuyruğa
  kararlı bir idempotency anahtarıyla bir kez eklenir. Kuyruk actor'ı claim öncesinde işi
  bellekte rezerve eder; böylece actor reentrancy sırasında aynı toplantı paralel iki kez
  işlenemez. Uygulama açılışında yarım kalan `running` işler `queued` durumuna alınır,
  bozuk kuyruk belgesi Recovery alanında korunur ve başarısız işler içerik taşımayan hata
  koduyla kullanıcıya tekrar deneme olanağı verir.
- Kuyruk worker'ına tek `TranscriptionServicing` bağımlılığı enjekte edilir; production
  implementasyonu ElevenLabs'tir ve protokol yalnız test doubles için korunur. Worker meeting
  repository'den birleşik M4A'yı alır ve aynı anda yalnızca claim edilmiş işi yürütür.
  Normalize sonuç önce sürümlü
  `transcript.json`, sonra tamamlandı durumu olarak atomik yazılır; bu sıra force-quit
  sonrasında aynı idempotency anahtarıyla güvenli yeniden işlemeye izin verir. Başarıdan
  sonra ayrı ham kaynak parçaları silinir, birleşik kayıt korunur.
- Kullanıcı kayıt hazırlığını veya henüz kalıcı olmayan aktif kaydı yalnızca açık onaydan
  sonra iptal edebilir; bu yol geçici parçaları siler. Upload/transkripsiyon/özet iptali ise
  kalıcı birleşik sesi silmez, çalışan işi `cancelled` hata koduyla tekrar denenebilir halde
  tutar ve kuyruktaki ilgisiz toplantıların işlenmesine yeni worker göreviyle devam eder.
- Transkripsiyon tamamlandığında yerel extractive özet servisi yalnızca transkriptte açıkça
  bulunan cümlelerden kısa özet, karar ve aksiyon adayları çıkarır. Ayrı bir uzak model veya
  ikinci API anahtarı kullanmaz; özetleme hatası transkriptin kaydedilmesini engellemez.
- Görevler `backlog`, `todo`, `inProgress`, `completed` ve `blocked` durumlarını; durumdan
  bağımsız `archivedAt` zaman damgasını tek sürümlü `Tasks/tasks.json` belgesinde tutar.
  `completed` geçişi aynı actor yazımında otomatik arşivler; manuel arşivleme mevcut durumu
  değiştirmez. Tamamlanmış bir görevi aktife geri almak onu `todo` durumuna döndürür. Şema
  v1'deki `completedAt` kayıtları `completed + archivedAt` olarak kayıpsız migrate edilir.
  V1 görünüm sırası oluşturulma zamanıdır; manuel reordering yoktur.

## İzin yaşam döngüsü

- Takvim entegrasyonu doğrudan Google/Gmail OAuth'u kullanmaz. EventKit, yalnız kullanıcının
  macOS İnternet Hesapları'na ekleyip Takvim için etkinleştirdiği iCloud, Google, Exchange,
  CalDAV ve yerel kaynakları okur; MeetingNotch Gmail gelen kutusuna veya e-posta içeriğine
  erişmez. Ayarlar kaynak türü ve takvim sayısını gösterir fakat hesap adı/e-posta adresini
  domain'e, loglara veya kalıcı dosyalara taşımaz.
- Yetkili EventKit sorgusu son 1 saat ile sonraki 24 saati kapsar; okunabilir takvim,
  taranan etkinlik, eşleşen çevrim içi toplantı ve son yenileme zamanını tek bağlantı sağlık
  snapshot'ı olarak yayınlar. İzin reddi, sorgu hatası ve Google hesabının macOS'ta görünmemesi
  farklı düzeltme aksiyonları üretir. Hızlı EventKit/timezone/poll tetikleri devam eden sorguya
  ek bir takip yenilemesi olarak coalesce edilir; eski sorgu entegrasyon kapatıldıktan sonra
  UI'a veri yayınlayamaz.
- Calendar URL matcher desteklenen doğrudan HTTPS linklerine ek olarak şemasız linkleri,
  HTML entity/percent encoding'i ve yalnız bilinen Google/Outlook redirect host'larındaki
  iç içe toplantı URL'lerini normalize eder. Eşleşen occurrence kimliği deterministik UUID
  üretir; yinelenen takvim kopyaları başlık/zaman/URL anahtarıyla tek toplantıya iner. En yakın
  toplantı ana durum yüzeyinde, sonraki üç çakışan/arka arkaya toplantı ince listede gösterilir.
- Mikrofon durumu AVFoundation sınırından okunur ve kayıt başlamadan doğrulanır. Sistem
  sesinin audio-only TCC izni için güvenilir bir preflight API bulunmadığından UI bu durumu
  `verificationRequired` olarak taşır; kesin karar Core Audio Process Tap hazırlanırken
  sistem tarafından verilir.
- Mevcut sistem sesi altyapısı izin probunda `NSAudioCaptureUsageDescription` ile global,
  private ve unmuted Core Audio Process Tap kullanabilir. Gerçek desteklenen toplantı
  kaydında aynı altyapı yalnız doğrulanmış meeting process nesnelerini içeren private tap
  kurar; sessizce global capture'a düşmez. Tap özel aggregate device üzerinden Objective-C++
  realtime callback'ine bağlanır ve M4A/AAC dosyasına yazılır. Akış ekran görüntüsü veya
  ekran kaydı iznine bağlı değildir.
- Kullanıcının açık `İzin Ver` aksiyonu, tap içeren geçici aggregate device'ın IO akışını kısa
  süre gerçekten başlatır; macOS TCC kaydı ve yerel sistem istemi bu noktada oluşur. Probe
  dosyası hemen silinir ve eşzamanlı yinelenen istekler tek çağrıyla sınırlandırılır. Ret
  sonucunda uygulama doğru Sistem Sesini Kaydetme panelini açar.
- Sistem sesi ayar bağlantısı Gizlilik ve Güvenlik altındaki Sistem Sesini Kaydetme panelini
  (`Privacy_AudioCapture`) açar. İzin reddedilirse gerçek kayıt başlangıcı normalize edilmiş
  izin hatası üretir ve kullanıcı bu panele yönlendirilir.
- Açık Sistem Ayarları'ndan dönüşte TCC kararının gecikmeli görünmesine karşı kısa süreli
  polling yapılır. macOS çalışan proseste eski kararı tutarsa kullanıcı uygulamayı Ayarlar
  içinden kontrollü biçimde yeniden başlatabilir.
- İzin değişikliği için kontrollü relaunch istendiğinde çalışan kesin bundle URL'si korunur;
  ayrı yardımcı mevcut proses tamamen kapandıktan sonra aynı yolu yeni instance olarak açar.
  Böylece LaunchServices'ın bellekteki eski build'i öne getirmesi engellenir.
- Accessibility izni yalnız desteklenen istemcide meeting window/call control ve mute
  durumunu yerel olarak okumak için istenir. Ret veya sonradan kaldırılma kayıt erişimini
  kapatmaz; session detector düşük güvene, microphone gate ise `unknown → closed` durumuna
  düşer ve manuel fallback'i görünür yapar.

## Mikrofon cihaz yaşam döngüsü

- Kullanılabilir ses girişleri AVFoundation discovery session ile listelenir; sistem
  varsayılanı ayrıca işaretlenir. Bağlanma ve ayrılma bildirimleri uygulama yaşamı boyunca
  izlenir ve Ayarlar listesi açıkken de canlı güncellenir.
- AVFoundation cihaz keşfi CMIO extension/provider zincirini de uyandırabildiği için ana
  actor üzerinde çalıştırılmaz. Keşif utility-priority detached işte normalize
  `MicrophoneDevice` değerlerine dönüştürülür; yalnız sonuç ana actor üzerinden yayınlanır.
  CMIO provider'ı gecikir veya geçersiz bağlantı döndürürse notch UI ve toplantı detayı
  bekletilmez. Audio discovery için yalnız `.microphone` device type kullanılır; daha geniş
  `.external` taraması eklenmez. AVFoundation bu dar kapsamda da CMIO provider'larını
  başlatabildiğinden sistem logları tamamen kaybolmayabilir; güvenlik sınırı UI izolasyonudur.
- Kullanıcı tercihi cihazın kararlı AVFoundation `uniqueID` değeri olarak yerel ayar
  belgesinde saklanır; `nil` sistem varsayılanını ifade eder. Eski ayar belgelerinde alanın
  bulunmaması geriye uyumlu biçimde sistem varsayılanına karşılık gelir.
- Her kayıt başlangıcında tercih yeniden çözülür. Seçili cihaz bağlı değilse kayıt
  engellenmez; mevcut sistem varsayılanına, o da yoksa ilk kullanılabilir girişe düşülür ve
  notch üzerinde hangi mikrofonla devam edildiği gösterilir.
- Aktif mikrofon bağlantısı kayıt sırasında kesilirse capture session aynı timeline içinde
  seçili cihazı veya güvenli fallback'i yeniden bağlamayı dener. Fallback bulunamazsa sistem
  sesi kaydı korunurken mikrofon kaynağı `bağlı değil` durumuna geçer; notch otomatik açılır
  ve kullanıcı yeniden bağlama ya da kaydı durdurma aksiyonuna yönlendirilir. Seçili cihaz
  yeniden gelirse aktif input tekrar yapılandırılır.
- Mikrofon sample buffer'ları, AirPods gibi 24 kHz Bluetooth girişleri ve kayıt ortasındaki
  format değişimleri doğrudan M4A writer'a verilmeden önce 48 kHz mono float PCM'e normalize
  edilir. AAC dosyası bu kararlı client formatından üretilir; ilk dönüştürme/yazma hatası
  kaynağa ait terminal hata olarak tutulur ve sonraki her buffer için yinelenen log üretilmez.

## Toplantı sesi ve mikrofon gate sınırı

- Mevcut global system tap V1 hedefinde gerçek toplantı kaydı için kullanılmaz. Zoom meeting
  session bir bundle ID/PID setine çözüldüğünde private `CATapDescription` yalnız bu process
  nesnelerinin output sesini yakalar. Google Meet system audio yalnız yukarıdaki extension
  tab stream'inden gelir. MeetingNotch kendi sesi ve diğer uygulama/Chrome sekmesi sesleri
  capture dışında kalır.
- Meeting process'i restart olur veya child process değiştirirse session detector yeni PID
  setini doğrular. Yeniden bağlama sırasında uygulama sessizce global tap'e düşmez; kullanıcı
  uyarılır ve gerekiyorsa kayıt güvenli biçimde finalize edilir.
- `kAudioProcessPropertyIsRunningInput`, input stream aktivitesini bildirir fakat istemci
  mute durumunu kanıtlamaz. Gate'i tek başına açması yasaktır.
- `MeetingMicrophoneGate` `open`, `closed`, `unknown` durumlarını taşır ve her kayıt
  `closed` başlar. Desteklenen Accessibility adapter'ından doğrulanmış unmute veya kullanıcının
  görünür manuel kontrolü `open` üretebilir.
- `closed` ve `unknown` aralıklarında mikrofon PCM frame'leri encode edilmeden önce zero
  fill edilir. Frame sayısı ve timestamp korunur; ortak timeline kaymaz. Gate sınırında kısa
  fade click'i önler; konuşma pre-roll'u tutulmaz.
- Gate geçişleri session metadata'sına timestamp, normalize source ve confidence ile
  yazılır. UI metni, konuşma içeriği veya Accessibility ağacı kalıcılaştırılmaz.
- Adapter/Accessibility kaybı anında `unknown`, ardından fail-closed davranış üretir.
  Notch kayıt boyunca `Açık/Kapalı/Bilinmiyor` durumunu ve manuel shortcut'ı görünür tutar.
- Privacy testi mute aralığında söylenen benzersiz canary phrase'i ham mic, birleşik M4A ve
  transkriptte arar. Bu test geçmeden bir client adapter'ı “desteklenen” sayılamaz.

## Sonuç ve görev yüzeyleri

- `AppDelegate` repository işlemlerini koordine eder; notch view'ları doğrudan dosya
  sistemine erişmez. `AppState`, aktif/arşiv görevlerini, durum başına aktif sayıları ve
  kompakt rozet için toplam aktif sayıyı yayınlar.
- Toplantı satırı ayrı pencere açmaz; `AppDelegate` repository'den normalize transcript,
  kalıcı Markdown ve birleşik audio URL'sini yükleyip `AppState` üzerindeki geçici detail
  içeriğine taşır. Geniş notch paneli sekmelerden toplantı detail drill-down'ına akışkan
  geçer; geri aksiyonu kullanıcıyı aynı panelde geçmiş listesine döndürür.
- Detail üst satırında düz metin ve Markdown pano aksiyonları doğrudan erişilebilirdir.
  Markdown dosyası kaydetme, Finder, retry ve silme gibi seyrek/dış etki üreten işlemler tek
  taşma menüsünde toplanır ve coordinator closure'ları üzerinden yürür; notch view'ları dosya
  sistemine doğrudan erişmez.
- Görevler yüzeyi iç içe kart kullanmaz; sabit durum ikonu kolonu, divider tabanlı satırlar,
  sans başlık ve mono tarih/sayaç rolleriyle toplantı listesiyle aynı optik grid'i paylaşır.
  Üst satır toplam “aktif” metni yerine backlog/todo/in-progress/blocked ikonlarıyla durum
  sayılarını gösterir. Satırdaki durum ikonu beş durum arasında seçim açar; `completed`
  seçimi görevi otomatik arşive taşır. Manuel arşivleme context menu'de ayrı kalır. Arşiv
  ana listenin altında açılmaz; sağ üstteki kompakt `archivebox` düğmesi aynı yüzeyde ayrı
  arşiv görünümüne geçer. Geri alma, düzenleme, silme ve arşiv temizleme kalıcı katmana
  coordinator closure'ları üzerinden ulaşır; destructive işlemler onay ister.
- AVPlayer tabanlı audio controller timestamp seek ve süre ilerlemesini yönetir. İlerleme
  yayınlarını yalnızca kompakt player gözlemler; saniyelik zaman güncellemeleri detail ağacını
  ve transkript satırlarını yeniden değerlendirmez. Segmentler 520 px'e kadar genişleyen
  detail panelinde `ScrollView`'un tek dış `LazyVStack`'ına doğrudan çocuk olarak eklenir;
  transkripti tek eager alt ağaç yapan iç içe stack kullanılmaz. Kısa transkriptlerde satır içi
  metin seçimi korunur; uzun transkriptlerde yüzlerce native seçim köprüsü oluşturmamak için
  satır seçimi kapatılır ve segment bazlı context-menu kopyalama ile üstteki tüm-transkript
  kopyalama aksiyonu kullanılabilir.
- DynamicNotchKit'in 15 pt pencere içi güvenli alanı içinde kalmak için hover sırasında 20 pt'e
  büyüyen gölge kullanılmaz; panel sabit 10 pt gölgeyle çizilir ve alt fade pencere sınırında
  kesilmez.

## Transkripsiyon sınırı

- V1 batch çalışır: kayıt sırasında canlı transkript üretilmez. Mikrofon ve sistem sesi
  durdurma/finalize sonrasında tek M4A olarak kalıcı kuyruğa girer. ElevenLabs'in ayrı
  `scribe_v2_realtime` WebSocket modeli V1 sonrası kapsamındadır.

- Production'da yalnız `ElevenLabsTranscriptionService` bulunur. Dar
  `TranscriptionServicing` sözleşmesi ağ implementasyonunu test double'dan ayırır; runtime
  provider seçimi veya plugin noktası değildir.
- Capability doğrulaması ElevenLabs'in desteklenen formatını, dosya boyutu sınırını,
  diarization ve otomatik dil algılama gereksinimlerini istek başlamadan kontrol eder.
- Transport ve HTTP hataları authentication, rate limit, timeout, bağlantı, provider ve
  decoding kategorilerine normalize edilir; provider response gövdesi domain hata sınırına
  taşınmaz.
- Retry yalnızca geçici hatalarda sınırlı sayıda çalışır ve tüm denemelerde aynı request
  idempotency anahtarını korur. Upload callback'i `TranscriptionProgressBridge` üzerinden
  toplantı durum makinesinin `.uploading(progress:)` durumuna bağlanır.
- `ElevenLabsTranscriptionService`, resmi `POST /v1/speech-to-text` sınırında
  `scribe_v2`, `diarize=true`, word timestamp ve isteğe bağlı ISO dil kodu kullanır. Boş
  dil kodu provider'ın otomatik algılamasını etkin bırakır; Ayarlar Türkçe için `tr`
  gönderir. Yanıtın `words` dizisi ardışık speaker kimliklerine göre domain segmentlerine
  birleştirilir. Provider response gövdesi hata veya log nesnesine taşınmaz.
- Multipart gövde büyük sesi belleğe almamak için geçici dosyaya parça parça yazılır;
  URLSession delegate'i gerçek gönderilen byte oranını yayınlar. Dosya başarı/hata/iptalde
  silinir, force-quit artıkları uygulama açılışında sabit güvenli prefix ile temizlenir.
- API anahtarı Ayarlar'da `POST /v1/single-use-token/realtime_scribe` üzerinden kullanılmadan
  süresi dolacak geçici bir Scribe token'ı istenerek doğrulanır. Bu istek ses yüklemez ve
  ücretli transkripsiyon oluşturmaz; batch endpoint'inin eksik dosya için değişebilen hata
  biçimine bağlı kalmadan `speech_to_text` kapsamı verilmiş kısıtlı anahtarları destekler.
  Dönen token yalnızca yanıt bütünlüğünü doğrulamak için bellekte görülür, saklanmaz veya
  loglanmaz. Anahtar ancak başarıdan sonra Keychain'e kaydedilir; kimlik doğrulama nedeniyle
  bekleyen işler atomik olarak yeniden kuyruğa alınır. UI'da provider seçici veya alternatif
  servis gösterilmez.

## Özet ve Markdown sınırı

- `MeetingSummaryGenerating` transkripsiyon HTTP servisinden bağımsızdır. V1 uygulaması
  `ExtractiveMeetingSummaryService` ile çalışır; uzak servise ikinci kez içerik göndermez.
- Overview en fazla ilk üç anlamlı transkript cümlesinden oluşur. Karar ve aksiyonlar yalnızca
  Türkçe/İngilizce açık ifadeler eşleştiğinde eklenir. Sorumlu sadece birinci tekil şahıs
  ifadesiyle birlikte segmentte konuşmacı adı varsa, tarih yalnızca Foundation açık bir tarih
  algıladığında yazılır; eksik bilgi `nil` kalır.
- Repository önce sürümlü `transcript.json`, sonra `meeting.md`, en son tamamlanmış metadata
  durumunu atomik yazar. UI kalıcı Markdown'ı panoya kopyalayabilir veya `NSSavePanel` ile
  kullanıcının seçtiği konuma `.md` olarak yazabilir.

## Test sınırları

- Domain durum geçişleri ve repository'ler birim testleriyle korunur.
- Calendar matcher, meeting session detector, mute adapter ve ElevenLabs parser gerçek
  servis olmadan fixture ile test edilir.
- Ses yakalama ve notch davranışı gerçek macOS donanımında entegrasyon testi gerektirir.
- Gerçek mikrofon testi `Scripts/audio-integration-tests.sh` opt-in runner'ıyla
  `MicrophoneCaptureSource` sınırını coordinator'dan bağımsız çalıştırır; runner yalnız test
  süresince `/tmp` sentinel'i oluşturur ve her çıkış yolunda temizler. Normal regresyon
  koşularında TCC istemi oluşturmamak için test atlanır.
- Gerçek sistem sesi testi aynı runner ile harici bir sistem sesi oynatır ve
  `SystemAudioCaptureSource` çıktısının seviye, timestamp, süre, audio track ve M4A dosya
  bütünlüğünü doğrular; normal regresyon koşularında TCC istemi oluşturmamak için atlanır.
- Otomatik recovery matrisi `Scripts/recovery-matrix-tests.sh` ile disk, capture recovery,
  queue restore/idempotency, transport retry, cihaz/gate kesintisi, pipeline heartbeat,
  drift/limiter ve privacy canary testlerini tek koşuda toplar; log ile sonuç özetini
  `artifacts/qa/` altında üretir.
- Browser audio otomasyonu extension origin/URL/backpressure testlerine ek olarak gerçek gömülü
  native-host executable'ını framed stdin/stdout, kullanıcı socket'i, broker ve M4A writer
  üzerinden uçtan uca çalıştırır. Bu test gerçek Chrome `tabCapture` ve iki sekmeli fiziksel
  privacy canary'nin yerine geçmez.
- Gerçek client privacy testleri opt-in çalışır: Zoom ile Google Meet/Chrome çağrılarında
  mute/unmute ve hang-up geçişlerini, güvenli system-audio kapsamını, canary phrase
  sızıntısını ve Google Meet için toplantı dışı sekme canary-audio izolasyonunu birlikte
  doğrular.
