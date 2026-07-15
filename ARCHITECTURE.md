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
    Calendar/       EventKit sorguları ve meeting URL algılama
    Transcription/  Provider protokolü ve provider adaptörleri
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
- Provider'a özel response modelleri servis adaptörünün dışına çıkmaz.
- Domain katmanı DynamicNotchKit, AppKit ve ağ istemcilerinden bağımsız kalır.
- Ana UI durumu `AppState` üzerinden gözlemlenir; gerçek iş servisler tarafından yapılır.
- Uzun işler iptal edilebilir `async` operasyonlar olarak tasarlanır.
- API anahtarları yalnızca Keychain'de tutulur.

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

## Notch yaşam döngüsü

- Uygulama açıldığında desteklenen cihazda kompakt notch görünümü hazırlanır.
- Menü çubuğu ikonu notch görünür olmadığında da ürüne erişim sağlar.
- Fiziksel notch bulunmayan ekranda DynamicNotchKit floating görünümü kullanılır.
- Floating görünüm kompakt modu desteklemez; menü veya hover aksiyonu paneli genişletir,
  kompakt duruma dönüş paneli gizler ve menü çubuğu erişimi kalıcı olarak korur.
- Öncelik sırası: kayıt > işleme/hata > yaklaşan toplantı > görev rozeti > boşta.

## Veri yaklaşımı

- V1'de veritabanı yoktur; toplantı ve görevler Application Support altında saklanır.
- Bir toplantı belgesi kararlı kimlik, başlık, başlangıç/bitiş, kaynak takvim kimliği ve URL,
  işlem/provider durumu, normalize hata kodu ve ilişkili dosya adlarını taşır. Normalize
  transkript konuşmacı ve zaman damgalı segmentleri; özet çıktısı genel özet, kararlar ve
  sorumlu/tarih bilgisi uydurulmadan çıkarılan aksiyon maddelerini taşır.
- Yazımlar atomik yapılır ve yarım kayıtlar Recovery alanında korunur.
- Her toplantı kararlı bir UUID ile ses, metadata ve Markdown çıktısını ilişkilendirir.
- Repository formatları şema sürümü taşır.
- Provider API anahtarları provider kimliğiyle ayrılmış generic-password öğeleri olarak
  yalnızca macOS Keychain'de ve `ThisDeviceOnly` erişilebilirlik sınıfında tutulur.
- API anahtarları tercih modellerine ve hata değerlerine eklenmez; serbest biçimli hata
  ayrıntıları OSLog'a hiç gönderilmez. Tanılama yalnızca sabit operasyon kodu, hata tipi,
  akış fazı ve hassas olmayan sayaçları taşır; kalıcı işleme hataları da serbest provider
  mesajı yerine normalize edilmiş hata kodu saklar. V1'de analytics SDK'sı yoktur.
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
- Kuyruk worker'ı seçili provider adaptörünü çözer, meeting repository'den birleşik M4A'yı
  alır ve aynı anda yalnızca claim edilmiş işi yürütür. Normalize sonuç önce sürümlü
  `transcript.json`, sonra tamamlandı durumu olarak atomik yazılır; bu sıra force-quit
  sonrasında aynı idempotency anahtarıyla güvenli yeniden işlemeye izin verir. Başarıdan
  sonra provider'a gerekmeyen ayrı ham kaynak parçaları silinir, birleşik kayıt korunur.
- Görevler aktif ve arşiv durumlarını ayrı dosyalar arasında taşımak yerine tek sürümlü
  `Tasks/tasks.json` belgesinde tutar. Completion timestamp ekleme/kaldırma tek actor içinde
  tek atomik yazımdır. V1 görünüm sırası oluşturulma zamanıdır; manuel reordering yoktur.

## İzin yaşam döngüsü

- Mikrofon durumu AVFoundation sınırından okunur ve kayıt başlamadan doğrulanır. Sistem
  sesinin audio-only TCC izni için güvenilir bir preflight API bulunmadığından UI bu durumu
  `verificationRequired` olarak taşır; kesin karar Core Audio Process Tap hazırlanırken
  sistem tarafından verilir.
- Sistem sesi yakalama `NSAudioCaptureUsageDescription` ile global, private ve unmuted bir
  Core Audio Process Tap oluşturur. Uygulamanın kendi audio process'i tap dışında bırakılır;
  tap özel aggregate device üzerinden Objective-C++ realtime callback'ine bağlanır ve M4A/AAC
  dosyasına yazılır. Akış ekran görüntüsü veya ekran kaydı iznine bağlı değildir.
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

## Sonuç ve görev yüzeyleri

- `AppDelegate` repository işlemlerini koordine eder; notch view'ları doğrudan dosya
  sistemine erişmez. `AppState`, aktif/arşiv görevlerini ve kompakt rozet sayısını yayınlar.
- Toplantı satırı AppKit tarafından tutulan ayrı bir SwiftUI detay penceresi açar. Detay
  penceresi normalize transcript'i ve birleşik audio URL'sini alır; dosya silme, Finder,
  retry ve pano aksiyonlarını coordinator closure'ları üzerinden yürütür.
- AVPlayer tabanlı audio controller timestamp seek ve süre ilerlemesini yönetir. Segmentler
  uzun transcript'te eager view üretmemek için `ScrollView` içindeki `LazyVStack` ile çizilir.

## Transkripsiyon sınırı

- Provider adaptörleri ortak `TranscriptionProvider` sözleşmesini uygular ve sonucu domain
  `Transcript`/`TranscriptSegment` modellerine normalize eder.
- Capability modeli desteklenen formatı, dosya boyutu sınırını, diarization ve otomatik dil
  algılama desteğini adaptör başlamadan doğrular.
- Transport ve HTTP hataları authentication, rate limit, timeout, bağlantı, provider ve
  decoding kategorilerine normalize edilir; provider response gövdesi domain hata sınırına
  taşınmaz.
- Retry yalnızca geçici hatalarda sınırlı sayıda çalışır ve tüm denemelerde aynı request
  idempotency anahtarını korur. Upload callback'i `TranscriptionProgressBridge` üzerinden
  toplantı durum makinesinin `.uploading(progress:)` durumuna bağlanır.
- Birincil `ElevenLabsTranscriptionProvider`, resmi `POST /v1/speech-to-text` sınırında
  `scribe_v2`, `diarize=true`, word timestamp ve isteğe bağlı ISO dil kodu kullanır. Boş
  dil kodu provider'ın otomatik algılamasını etkin bırakır; Ayarlar Türkçe için `tr`
  gönderir. Yanıtın `words` dizisi ardışık speaker kimliklerine göre domain segmentlerine
  birleştirilir. Provider response gövdesi hata veya log nesnesine taşınmaz.
- Multipart gövde büyük sesi belleğe almamak için geçici dosyaya parça parça yazılır;
  URLSession delegate'i gerçek gönderilen byte oranını yayınlar. Dosya başarı/hata/iptalde
  silinir, force-quit artıkları uygulama açılışında sabit güvenli prefix ile temizlenir.
- API anahtarı Ayarlar'da resmi `/v1/models` isteğiyle doğrulanır ve ancak başarıdan sonra
  Keychain'e kaydedilir. Alternatif OpenAI adaptörü tamamlanana kadar UI'da açıkça devre dışıdır.

## Test sınırları

- Domain durum geçişleri ve repository'ler birim testleriyle korunur.
- Calendar matcher ve provider parser gerçek servis olmadan fixture ile test edilir.
- Ses yakalama ve notch davranışı gerçek macOS donanımında entegrasyon testi gerektirir.
- Gerçek mikrofon testi `MEETINGNOTCH_RUN_AUDIO_INTEGRATION_TESTS=1` opt-in anahtarıyla
  `MicrophoneCaptureSource` sınırını coordinator'dan bağımsız çalıştırır; normal regresyon
  koşularında TCC istemi oluşturmamak için atlanır.
- Gerçek sistem sesi testi aynı opt-in anahtarıyla harici bir sistem sesi oynatır ve
  `SystemAudioCaptureSource` çıktısının seviye, timestamp, süre, audio track ve M4A dosya
  bütünlüğünü doğrular; normal regresyon koşularında TCC istemi oluşturmamak için atlanır.
