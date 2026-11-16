# Crenel

Crenel, notch içinden kontrol edilen, açık kaynak, minimal bir macOS Apple yardımcısıdır.
Adı, sur dişleri arasındaki çentikten (*crenel*) gelir. Dört şeyi tek yüzeyde toplar:

- **Takvim:** Apple Takvim’deki (iCloud, Google, Exchange hesapları dahil) toplantı ve
  etkinlikler notch’ta görünür. Notch kapalıyken sağ tarafta sıradaki etkinliğe kalan
  süre ya da süren etkinliğin bitmesine kalan süre yazar. Mailden gelen davetler
  “Yanıt bekliyor” olarak işaretlenir.
- **Akıllı dikte:** Fn (🌐) tuşunu basılı tutup konuşun; metin imlecin olduğu uygulamaya
  yazılır. Ses cihazda yazıya çevrilir ve diske yazılmaz. Agent (cihazdaki Apple modeli
  ya da kendi OpenAI/Anthropic anahtarınız) metni temizler; seçili metni sesli komutla
  düzenler; “görev ekle …” ile görev oluşturur.
- **Görevler:** Tek satır yazıp Enter’a basın. “yarın 15te”, “next Monday”, “her pazartesi”,
  “acil” gibi ifadeler yazarken öneri olarak çıkar, Tab ile eklenir. Görevler Apple
  Hatırlatıcılar’daki “Crenel” listesinde saklanır ve iPhone/Watch’ta da görünür.
- **Toplantı kaydı:** Desteklenen istemcide (Zoom, Google Meet/Chrome) yalnız toplantı sesi
  ve yalnız toplantı mikrofonu açıkken kullanıcının sesi kaydedilir; konuşmacı ayrımlı
  transkript ve özet üretilir. Kayıtlar yerelde kalır.

Güncel kapsam ve ilerleme [`PRODUCT_PLAN.md`](PRODUCT_PLAN.md) içindeki
“2026-11-16 — Crenel” bölümündedir.

## Masaüstü çalışma alanı

Uygulama ilk açıldığında notch çalışır. Notch’taki pencere düğmesi veya menü çubuğundaki
**Crenel** menüsüyle masaüstünü açın. Pencere kapatıldığında notch ve varsa kayıt çalışmayı
sürdürür. Ayarlar bu pencerenin içindedir: **Genel, Dikte, Görevler, Yapay zekâ, Takvim,
Kayıt, Veri**.

## İzinler

Tüm izinler ilk açılışta tek bir kurulum ekranında listelenir; **Hepsini aç** sistem
pencerelerini sırayla gösterir. Takvim veya Hatırlatıcılar izni geldiği anda ilgili özellik
kendiliğinden bağlanır; modülleri ayrıca ayarlamak gerekmez. Daha önce reddedilen izin için
satır doğrudan Sistem Ayarları’ndaki ilgili bölmeyi açar.

| İzin | Neden | Vermezseniz |
|---|---|---|
| Takvim | Etkinlikleri ve geri sayımı göstermek | Takvim bölümü boş kalır |
| Hatırlatıcılar | Görevleri senkronlamak | Görevler yalnız bu Mac’te tutulur |
| Mikrofon | Dikte ve toplantı kaydı | Dikte ve kayıt çalışmaz |
| Girdi İzleme | Dikte kısayolunu (Fn) dinlemek | Kısayol çalışmaz |
| Erişilebilirlik | Metni imlece yazmak, toplantı mute durumunu okumak | Dikte metni panoya kopyalanır |
| Ses yakalama | Toplantının sistem sesini kaydetmek | Toplantı sesi kaydedilmez |

## Belgeler

- [Ürün geliştirme planı](PRODUCT_PLAN.md)
- [Mimari rehber](ARCHITECTURE.md)
- [Ortak geliştirme kuralları](AGENTS.md)
- [Hibrit sürüm kurulumu ve kabul kontrolleri](QA/HYBRID_SETUP.md)
- [V1 release doğrulama runbook'u](QA/V1_RELEASE_RUNBOOK.md)
- [İlk araştırma notları](project-overview.md)

## Gereksinimler

- macOS 26+
- Güncel Xcode
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.45.4+
- Metal Toolchain (SwiftUI shader'ları için): `xcodebuild -downloadComponent MetalToolchain`

Homebrew ile XcodeGen kurulumu:

```sh
brew install xcodegen
```

## Projeyi üretme

```sh
xcodegen generate
open MeetingNotch.xcodeproj   # ürün adı Crenel; proje dosyası adı geçiş sürecinde korunuyor
```

`project.yml` Xcode projesinin tek yapılandırma kaynağıdır.
`MeetingNotch.xcodeproj/project.pbxproj` elle düzenlenmemelidir.
Debug uygulaması proje takımının Apple Development sertifikasıyla kararlı biçimde
imzalanır. Hardened Runtime açıktır ve mikrofon kaydı için yalnızca gerekli
`com.apple.security.device.audio-input` entitlement'ı kullanılır.

Notch paneli fiziksel notch bulunan ekranı otomatik algılar. Menü çubuğundan açma ve
toplantı hatırlatmaları imlecin bulunduğu ekranda gösterilir; notch olmayan ekranda aynı
içerik floating panel olarak açılır. Genişletilmiş paneldeki pin düğmesi paneli hover
sonrasında da açık tutar.

## Takvim: Apple Takvim, Google ve mail davetleri

Crenel takvimleri yalnızca Apple’ın EventKit altyapısıyla okur; ayrı Google girişi yoktur.
Gmail gelen kutusunu da okumaz.

1. Google, Exchange veya Outlook takvimleri için Sistem Ayarları › İnternet Hesapları’nda
   hesabı ekleyip **Takvimler**’i açın. iCloud takvimleri kendiliğinden gelir.
2. Crenel’de takvim iznini verin. Ayarlar › Takvim kaynak türlerini ve takvim sayısını gösterir;
   Google kaynağı görünmüyorsa **Hesapları Aç** düğmesi İnternet Hesapları’nı açar.
3. Mailden gelen davetler: Gmail davetleri Google Calendar’ın “Davetleri takvime ekle” ayarı
   açıksa takvime düşer; iCloud/Exchange davetleri Takvim’e yanıt bekleyen davet olarak gelir.
   Crenel bunları “Yanıt bekliyor” diye işaretler. Apple Mail’in bulduğu etkinlikler (Siri
   önerileri) soluk ve “Mail’den öneri” olarak gösterilir.

Linkli toplantılar (Zoom, Google Meet, Microsoft Teams), katılımcılı toplantılar ve kişisel
etkinlikler ayrı simgelerle gösterilir. Kayıt teklifi ve “katıl” bildirimleri yalnız
toplantılar içindir; kişisel etkinlikler ve tüm gün etkinlikleri yalnız listede ve geri
sayımda görünür. Reddedilen ve iptal edilen etkinlikler gizlenir.

İzlenecek takvimleri Ayarlar’da seçip kaydedebilirsiniz. Bildirim iznini ayrıca açınca
seçtiğiniz süre ve bir dakika önce macOS bildirimi gelir; bildirimin katıl/ertele
aksiyonları vardır. Uygulama yaklaşan etkinlikleri yenilemek için çalışıyor olmalıdır.

Doğrudan Google hesabı bağlantısı da uygulanmıştır. Bu seçenek yalnız yayıncının
Google OAuth Desktop client kimliği build’e tanımlandığında görünür. Son kullanıcıdan
Google geliştirici projesi oluşturması istenmez; yayıncı kurulumu [rehberdedir](QA/HYBRID_SETUP.md).

## Doğrulama

```sh
xcodebuild \
  -project MeetingNotch.xcodeproj \
  -scheme MeetingNotch \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build test
```

Google Meet extension protokolü ve Chrome Web Store kod paketi için:

```sh
Scripts/chrome-extension-tests.sh
Scripts/chrome-web-store-package.sh
```

İkinci komut checksum'lı Store ZIP'ini `artifacts/chrome-store/` altında üretir. Listeleme
metni, gizlilik politikası taslağı, ikon/promosyon varlıkları ve yayın checklist'i
`BrowserExtension/ChromeWebStore/` altındadır.

Gerçek privacy canary çıktılarını 997 Hz, minimum süre ve yasaklı transcript cümlesi için
denetlemek üzere `Scripts/privacy-canary-audit.sh --help` kullanılabilir. Araç 65+ dakikalık
dosyaları belleğe bütünüyle almadan parça parça okur ve JSON + Markdown kanıtı üretir.

Gerçek Zoom/Meet session başlangıç–bitiş koşularından sonra privacy-safe OSLog kanıtını
toplayıp beşli `ready/confirmed → ended/confirmed` zincirini doğrulamak için
`Scripts/session-acceptance-collect.sh --help` kullanılabilir.

## Yerel kayıt prototipi

`Kaydı Başlat` ilk kullanımda mikrofon ile Ekran ve Sistem Sesi Kaydı izinlerini
ister. Menü çubuğundaki `Ayarlar…` ekranı iki iznin güncel durumunu gösterir ve reddedilen
izin için hem isteği yeniden çalıştırır hem ilgili Sistem Ayarları bölümünü açar. Sistem
ayarından uygulamaya dönüldüğünde izin birkaç saniye yeniden kontrol edilir. macOS çalışan
proseste eski TCC kararını tutarsa Ayarlar'daki yeniden başlat düğmesi yeni izni etkinleştirir.
Önceki ad-hoc Debug build'inden geçerken macOS yeni kararlı imzayı farklı uygulama olarak
görebilir; bu durumda sistem sesi iznini bir kez yeniden verip uygulamayı yeniden başlatın.
Kayıt sürerken dosyalar `Temporary` altında tutulur. Başarıyla tamamlanan her toplantı,
iki ayrı ham M4A kaynak dosyası, ortak timeline'a birleştirilmiş okunabilir adlı M4A ve
sürümlü `metadata.json` ile kalıcı arşive atomik olarak taşınır:

```text
~/Library/Application Support/MeetingNotch/Meetings/<session-id>/   (klasör adı geçiş sürecinde korunuyor)
```

Yarım kalan yazımlar ve bozuk metadata kayıtları veri kaybını önlemek için `Recovery`
klasörüne alınır. Uygulama dışından arşiv dosyalarını değiştirmek desteklenmez; değişen
veya eksilen toplantılar güvenli biçimde arşiv listesinden çıkarılıp kurtarmaya taşınır.
Uygulama yeniden açıldığında yarım kalan kayıtlar otomatik taranır: geçerli ham sesler
yeniden finalize edilir, tamamlanmış kayıtlar arşive alınır ve okunamayan kaynaklar
silinmeden `Recovery` altında korunur. Uzun kayıtlardaki clock drift, pitch'i koruyan sınırlı
time-pitch düzeltmesiyle normalize edilir; sıcak miksler offline soft limiter'dan geçer.

Görevler `Tasks/tasks.json` içinde aktif/arşiv durumu ve şema sürümüyle atomik olarak
saklanır. Bozuk görev belgesi veri kaybını önlemek için silinmeden `Recovery` klasörüne
taşınır; uygulama dışından bu dosyayı değiştirmek desteklenmez. Notch içinden görev
ekleme, düzenleme, tamamlama, arşivden geri alma ve onaylı silme kullanılabilir. Aktif ve
arşivlenmiş görevler tek belgede bulunduğu için durum geçişi tek atomik yazımdır; V1'de
manuel sıralama yerine kararlı oluşturulma sırası kullanılır.

Hassas olmayan uygulama tercihleri sürümlü bir belge olarak UserDefaults'ta tutulur.
ElevenLabs ve OpenAI anahtarları tercih modelinin parçası değildir; ayrı Keychain
service’lerinde saklanır. Google OAuth tokenları da ayrı bir Keychain öğesindedir. Eski provider-scoped `elevenLabs` hesabı ilk
erişimde save-first olarak tek `elevenlabs-api-key` hesabına kayıpsız migrate edilir.
Keychain öğesi `ThisDeviceOnly` erişilebilirlik
sınıfını kullanır ve Mac kilitliyken okunamaz. Anahtar değeri hata metinlerine eklenmez.
Ham `localizedDescription`, uzak servis response metni,
toplantı başlığı ve transkript tanılama kayıtlarına gönderilmez; loglar yalnızca sabit
operasyon kodu, hata tipi, akış fazı ve hassas olmayan sayaçları içerir. Uygulamada şu an
bir analytics SDK'sı bulunmaz.

Toplantı saklama politikası varsayılan olarak süresizdir. Pozitif bir gün sayısı seçilmişse
uygulama açılışta ve ardından 24 saatte bir toplantı bitiş zamanlarını kontrol eder; süresi
dolan toplantı klasörünü tüm bağlı dosyalarıyla siler. Tek bir kaydın silinememesi diğer
süresi dolmuş kayıtların temizlenmesini engellemez. Saklama süresi Ayarlar'dan 7/30/90 gün
veya süresiz olarak seçilebilir.

## Transkripsiyon ve işleme kuyruğu

Crenel toplantılar için canlı transkript üretmez (dikte ise canlı ve cihaz üzerindedir). Kayıt durdurulduktan ve birleşik M4A güvenle
saklandıktan sonra arka plan kuyruğu sesi ElevenLabs bulutundaki `scribe_v2` modeline
gönderir. Kayıt sırasında ağ gerekmez; upload/transkripsiyon hatasında ses korunur ve
toplantı tekrar işlenebilir.

Dar transkripsiyon hizmeti sözleşmesi; normalize transcript sonucu, format/boyut
doğrulaması, upload progress callback'i, güvenli hata normalizasyonu ve geçici hatalar için
sınırlı retry politikası sunar. Bu protokol provider seçimi için değil test doubles içindir.
Production servisi,
[ElevenLabs Speech to Text](https://elevenlabs.io/docs/api-reference/speech-to-text/convert)
üzerinde `scribe_v2`, speaker diarization ve word timestamp kullanır. Dil Ayarlar'dan
otomatik algılama, Türkçe veya İngilizce seçilebilir. API anahtarı ses yüklemeyen resmi
`/v1/single-use-token/realtime_scribe` isteğiyle doğrulandıktan sonra yalnızca Keychain'e
yazılır. OpenAI, Ayarlar → Toplantı Notları bölümünden ayrı bağlanır; doğrulama küçük
bir ücretli metin isteği gönderir. ChatGPT aboneliği API bakiyesi yerine geçmez.

Finalize edilen toplantılar `ProcessingQueue/queue.json` dosyasına atomik olarak eklenir.
Her toplantının idempotency anahtarı yeniden denemelerde korunur; aynı kayıt paralel iki
kez claim edilemez. Uygulama yeniden açıldığında yarım kalan işler bekleme durumuna döner,
bozuk kuyruk silinmeden Recovery alanına taşınır ve başarısız iş notch listesinden tekrar
denenebilir. Arka plan worker'ı işi claim eder, aynı idempotency anahtarıyla sınırlı retry
uygular ve başarılı normalize sonucu toplantı klasöründeki sürümlü `transcript.json`
dosyasına atomik yazar. Sonuç güvenle yazıldıktan sonra ayrı mikrofon/sistem ham parçaları
silinir; dinleme ve export için birleşik M4A korunur. Multipart upload gövdesi istek sonunda
silinir, force-quit artıkları sonraki uygulama açılışında temizlenir.

Transkript önce diske yazılır, ardından OpenAI Responses API (`gpt-5-mini`) çağrılır.
Uzun transkriptin bütün parçaları işlenir ve bölüm özetleri birleştirilir. Görevlerin kaynak
segmenti ve konuşmacı kimliği yerelde doğrulanır; belirsiz sorumlu/tarih boş bırakılır.
OpenAI anahtarı yoksa veya özet isteği başarısızsa transkript ve ses korunur; geçmişte
“Özet bekliyor” görünür. Detaydaki özet düğmesi mevcut transkripti kullanır ve sesi
ElevenLabs’e yeniden göndermez. Yenileme başarısızsa önceki özet de korunur.
`store:false` kullanılır; bu, sağlayıcının tüm veri saklama politikalarını geçersiz kılmaz.

## Toplantı sonucu

Notch içindeki bir geçmiş toplantıya tıklamak panel içinde genişleyen detay görünümünü açar.
Birleşik M4A aynı pencerede oynatılabilir; konuşmacı ayrımlı transcript segmentleri `LazyVStack` ile
gösterilir ve timestamp düğmesi oynatıcıyı ilgili noktaya taşır. Transkript düz metin
olarak panoya kopyalanabilir, ses Finder'da gösterilebilir, başarısız işlem yeniden
denenebilir ve toplantı güçlü onay sonrasında bağlı dosyalarıyla silinebilir. Aynı ekranda
kısa özet, kararlar ve aksiyon maddeleri gösterilir. Tam sonuç `meeting.md` olarak toplantı
klasöründe saklanır; Markdown panoya kopyalanabilir veya kullanıcının seçtiği konuma
`.md` dosyası olarak kaydedilebilir.

Konuşmacılar detay ekranından adlandırılabilir. Adlar transkripte, Markdown’a ve bağlı
görevlere yansır. Aksiyonlar sorumlu, tarih ve kaynaktaki ses zamanıyla gösterilir;
“Görevlere ekle” aynı aksiyonu ikinci kez oluşturmaz. AI çıktısı kullanıcı tarafından
kontrol edilmelidir; kaynak bağlantısı doğrulama için sunulur.

## Lisans

MIT — ayrıntılar için [LICENSE](LICENSE).
