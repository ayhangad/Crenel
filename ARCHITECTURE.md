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
- Uygulama `LSUIElement` agent olarak çalışır ve App Sandbox kapalıdır.

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
- Öncelik sırası: kayıt > işleme/hata > yaklaşan toplantı > görev rozeti > boşta.

## Veri yaklaşımı

- V1'de veritabanı yoktur; toplantı ve görevler Application Support altında saklanır.
- Yazımlar atomik yapılır ve yarım kayıtlar Recovery alanında korunur.
- Her toplantı kararlı bir UUID ile ses, metadata ve Markdown çıktısını ilişkilendirir.
- Repository formatları şema sürümü taşır.
- Provider API anahtarları provider kimliğiyle ayrılmış generic-password öğeleri olarak
  yalnızca macOS Keychain'de ve `ThisDeviceOnly` erişilebilirlik sınıfında tutulur.
- API anahtarları tercih modellerine ve hata değerlerine eklenmez; serbest biçimli hata
  ayrıntıları OSLog'da açık metin yerine özel, hash-maskeli veri olarak işaretlenir.
- Toplantı saklama politikası ayar belgesinde tutulur ve eksik alan süresiz saklama olarak
  geriye uyumlu okunur. Süre seçilmişse açılışta ve 24 saatte bir çalışan servis, bitiş
  zamanı eşik öncesinde kalan toplantı klasörlerini repository üzerinden serialize ederek
  siler; kısmi silme hataları kalan kayıtların temizliğini durdurmaz.

## Test sınırları

- Domain durum geçişleri ve repository'ler birim testleriyle korunur.
- Calendar matcher ve provider parser gerçek servis olmadan fixture ile test edilir.
- Ses yakalama ve notch davranışı gerçek macOS donanımında entegrasyon testi gerektirir.
