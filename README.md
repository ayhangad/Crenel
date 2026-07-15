# MeetingNotch

MeetingNotch, macOS notch çevresinde Dynamic Island benzeri çalışan bir toplantı
kayıt uygulamasıdır. Mikrofon ve sistem sesini kaydeder; kaydı konuşmacı ayrımlı
transkript, kısa özet ve aksiyon maddelerine dönüştürür.

## Belgeler

- [Ürün geliştirme planı](PRODUCT_PLAN.md)
- [Mimari rehber](ARCHITECTURE.md)
- [Ortak geliştirme kuralları](AGENTS.md)
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

## Yerel kayıt prototipi

`Kaydı Başlat` ilk kullanımda mikrofon ile Ekran ve Sistem Sesi Kaydı izinlerini
ister. Menü çubuğundaki `Ayarlar…` ekranı iki iznin güncel durumunu gösterir ve reddedilen
izin için doğrudan ilgili Sistem Ayarları bölümünü açar. İzin değişikliğinden sonra macOS
uygulamanın yeniden açılmasını isteyebilir.
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
silinmeden `Recovery` altında korunur. Uzun kayıtlardaki clock drift düzeltmesi Faz
7.4'te açık görevdir.

Görevler `Tasks/tasks.json` içinde aktif/arşiv durumu ve şema sürümüyle atomik olarak
saklanır. Bozuk görev belgesi veri kaybını önlemek için silinmeden `Recovery` klasörüne
taşınır; uygulama dışından bu dosyayı değiştirmek desteklenmez.

Hassas olmayan uygulama tercihleri sürümlü bir belge olarak UserDefaults'ta tutulur.
Provider API anahtarları tercih modelinin parçası değildir; provider kimliğiyle ayrılmış
generic-password öğeleri olarak yalnızca macOS Keychain'de saklanır. Keychain öğeleri
`ThisDeviceOnly` erişilebilirlik sınıfını kullanır ve Mac kilitliyken okunamaz. Anahtar
değerleri hata metinlerine eklenmez; dinamik hata ayrıntıları OSLog'a açık metin yerine
özel, hash-maskeli veri olarak gönderilir.

Toplantı saklama politikası varsayılan olarak süresizdir. Pozitif bir gün sayısı seçilmişse
uygulama açılışta ve ardından 24 saatte bir toplantı bitiş zamanlarını kontrol eder; süresi
dolan toplantı klasörünü tüm bağlı dosyalarıyla siler. Tek bir kaydın silinememesi diğer
süresi dolmuş kayıtların temizlenmesini engellemez. Ayarlar UI'ından politika seçimi Faz
3.3 kapsamındaki açık görevdir.
