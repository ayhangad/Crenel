# MeetingNotch

MeetingNotch, macOS notch çevresinde Dynamic Island benzeri çalışan bir toplantı
kayıt uygulamasıdır. Hedef V1, desteklenen istemcide toplantının başlangıç/bitişini
yerel sinyallerle algılar; toplantı process sesini ve yalnız meeting mikrofonu açıkken
kullanıcının sesini kaydeder. Kayıt tek uzak servis olan ElevenLabs Scribe v2 ile
konuşmacı ayrımlı transkript, kısa özet ve aksiyon maddelerine dönüştürülür.

2026-07-25 ürün odağının ayrıntıları ve mevcut uygulamadan geçiş sırası
[`PRODUCT_PLAN.md`](PRODUCT_PLAN.md) içindeki “V1 odak kararı” bölümündedir. Güncel build;
gerçek meeting session detector, Zoom private process tap, fail-closed microphone gate ve
görünür manuel fallback'i içerir. Google Meet/Chrome için kullanıcı gesture'ıyla yalnız
aktif görüşme sekmesini alan MV3 extension, native messaging helper ve kullanıcıya özel
uygulama IPC hattı bulunur; köprü bağlı değilse sistem sesi kaydı bilinçli olarak başlatılmaz.

## Belgeler

- [Ürün geliştirme planı](PRODUCT_PLAN.md)
- [Mimari rehber](ARCHITECTURE.md)
- [Ortak geliştirme kuralları](AGENTS.md)
- [V1 release doğrulama runbook'u](QA/V1_RELEASE_RUNBOOK.md)
- [İlk araştırma notları](project-overview.md)

## Gereksinimler

- macOS 14.4+
- Güncel Xcode
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.45.4+

Homebrew ile XcodeGen kurulumu:

```sh
brew install xcodegen
```

## Projeyi üretme

```sh
xcodegen generate
open MeetingNotch.xcodeproj
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
~/Library/Application Support/MeetingNotch/Meetings/<session-id>/
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
Tek ElevenLabs API anahtarı tercih modelinin parçası değildir; generic-password öğesi
olarak yalnızca macOS Keychain'de saklanır. Eski provider-scoped `elevenLabs` hesabı ilk
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

MeetingNotch V1 canlı transkript üretmez. Kayıt durdurulduktan ve birleşik M4A güvenle
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
yazılır. UI'da ikinci provider, ikinci API anahtarı veya OpenAI seçeneği bulunmaz.

Finalize edilen toplantılar `ProcessingQueue/queue.json` dosyasına atomik olarak eklenir.
Her toplantının idempotency anahtarı yeniden denemelerde korunur; aynı kayıt paralel iki
kez claim edilemez. Uygulama yeniden açıldığında yarım kalan işler bekleme durumuna döner,
bozuk kuyruk silinmeden Recovery alanına taşınır ve başarısız iş notch listesinden tekrar
denenebilir. Arka plan worker'ı işi claim eder, aynı idempotency anahtarıyla sınırlı retry
uygular ve başarılı normalize sonucu toplantı klasöründeki sürümlü `transcript.json`
dosyasına atomik yazar. Sonuç güvenle yazıldıktan sonra ayrı mikrofon/sistem ham parçaları
silinir; dinleme ve export için birleşik M4A korunur. Multipart upload gövdesi istek sonunda
silinir, force-quit artıkları sonraki uygulama açılışında temizlenir.

Transkripsiyonun ardından ikinci bir bulut modeli çağrılmaz. Yerel extractive not servisi
yalnızca transkriptte açıkça bulunan cümlelerden kısa özet, kararlar ve aksiyon maddeleri
çıkarır; sorumlu veya tarih belirsizse alanı boş bırakır. Bu adım başarısız olsa bile
transkript tamamlanmış sonuç olarak saklanır.

## Toplantı sonucu

Notch içindeki bir geçmiş toplantıya tıklamak panel içinde genişleyen detay görünümünü açar.
Birleşik M4A aynı pencerede oynatılabilir; konuşmacı ayrımlı transcript segmentleri `LazyVStack` ile
gösterilir ve timestamp düğmesi oynatıcıyı ilgili noktaya taşır. Transkript düz metin
olarak panoya kopyalanabilir, ses Finder'da gösterilebilir, başarısız işlem yeniden
denenebilir ve toplantı güçlü onay sonrasında bağlı dosyalarıyla silinebilir. Aynı ekranda
kısa özet, kararlar ve aksiyon maddeleri gösterilir. Tam sonuç `meeting.md` olarak toplantı
klasöründe saklanır; Markdown panoya kopyalanabilir veya kullanıcının seçtiği konuma
`.md` dosyası olarak kaydedilebilir.
