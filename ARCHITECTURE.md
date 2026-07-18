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
- Kompakt görünüm hazırlama, finalize, upload, transkripsiyon ve özet aşamalarını kendi
  ilerleme göstergesiyle taşır; daha düşük öncelikli toplantı veya görev bilgisi işleme
  durumunu örtemez. Başarı ve hata paneli otomatik açılır; etkileşim yoksa 8 saniye sonra
  kompakt duruma döner, başarı akışı boşta durumuna sıfırlanırken hata kurtarma için korunur.
- Geniş panel aktif ekranın görünür alanına göre en fazla 420 piksel genişlik ve 500 piksel
  içerik yüksekliği kullanır; daha küçük alanlarda içerik kaydırılır. Sekmeler ok tuşları
  ve Komut-1/Komut-2 ile değiştirilebilir.
- DynamicNotchKit açılma, kapanma ve kompakt/geniş dönüşümleri uygulamanın hareket profiliyle
  yapılandırılır. macOS Reduce Motion değişikliği canlı izlenir ve etkin olduğunda hem panel
  içi hem pencere geçişleri algılanabilir hareket üretmeyecek kadar kısaltılır.

## Veri yaklaşımı

- V1'de veritabanı yoktur; toplantı ve görevler Application Support altında saklanır.
- Bir toplantı belgesi kararlı kimlik, başlık, başlangıç/bitiş, kaynak takvim kimliği ve URL,
  işlem/provider durumu, normalize hata kodu ve ilişkili dosya adlarını taşır. Normalize
  transkript konuşmacı ve zaman damgalı segmentleri; özet çıktısı genel özet, kararlar ve
  sorumlu/tarih bilgisi uydurulmadan çıkarılan aksiyon maddelerini taşır.
- Yazımlar atomik yapılır ve yarım kayıtlar Recovery alanında korunur.
- Her toplantı kararlı bir UUID ile ses, metadata ve Markdown çıktısını ilişkilendirir.
- Başarılı işleme, normalize `transcript.json` yanında kullanıcı tarafından doğrudan
  açılabilen `meeting.md` üretir. Markdown toplantı metadata'sı, kısa notlar, kararlar,
  aksiyonlar ve konuşmacı-zaman damgalı tam transkripti aynı UUID altında taşır.
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
- Transkripsiyon tamamlandığında yerel extractive özet servisi yalnızca transkriptte açıkça
  bulunan cümlelerden kısa özet, karar ve aksiyon adayları çıkarır. Ayrı bir uzak model veya
  ikinci API anahtarı kullanmaz; özetleme hatası transkriptin kaydedilmesini engellemez.
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

## Mikrofon cihaz yaşam döngüsü

- Kullanılabilir ses girişleri AVFoundation discovery session ile listelenir; sistem
  varsayılanı ayrıca işaretlenir. Bağlanma ve ayrılma bildirimleri uygulama yaşamı boyunca
  izlenir ve Ayarlar listesi açıkken de canlı güncellenir.
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

## Sonuç ve görev yüzeyleri

- `AppDelegate` repository işlemlerini koordine eder; notch view'ları doğrudan dosya
  sistemine erişmez. `AppState`, aktif/arşiv görevlerini ve kompakt rozet sayısını yayınlar.
- Toplantı satırı AppKit tarafından tutulan ayrı bir SwiftUI detay penceresi açar. Detay
  penceresi normalize transcript'i ve birleşik audio URL'sini alır; dosya silme, Finder,
  retry ve pano aksiyonlarını coordinator closure'ları üzerinden yürütür.
- AVPlayer tabanlı audio controller timestamp seek ve süre ilerlemesini yönetir. Segmentler
  uzun transcript'te eager view üretmemek için `ScrollView` içindeki `LazyVStack` ile çizilir.

## Transkripsiyon sınırı

- V1 batch çalışır: kayıt sırasında canlı transkript üretilmez. Mikrofon ve sistem sesi
  durdurma/finalize sonrasında tek M4A olarak kalıcı kuyruğa girer. ElevenLabs'in ayrı
  `scribe_v2_realtime` WebSocket modeli V1 sonrası kapsamındadır.

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

## Özet ve Markdown sınırı

- `MeetingSummaryGenerating` transkripsiyon provider'ından bağımsızdır. V1 uygulaması
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
- Calendar matcher ve provider parser gerçek servis olmadan fixture ile test edilir.
- Ses yakalama ve notch davranışı gerçek macOS donanımında entegrasyon testi gerektirir.
- Gerçek mikrofon testi `MEETINGNOTCH_RUN_AUDIO_INTEGRATION_TESTS=1` opt-in anahtarıyla
  `MicrophoneCaptureSource` sınırını coordinator'dan bağımsız çalıştırır; normal regresyon
  koşularında TCC istemi oluşturmamak için atlanır.
- Gerçek sistem sesi testi aynı opt-in anahtarıyla harici bir sistem sesi oynatır ve
  `SystemAudioCaptureSource` çıktısının seviye, timestamp, süre, audio track ve M4A dosya
  bütünlüğünü doğrular; normal regresyon koşularında TCC istemi oluşturmamak için atlanır.
