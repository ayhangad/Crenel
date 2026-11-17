# Katkı rehberi

Crenel'e katkı verdiğiniz için teşekkürler. Bu rehber projeyi kendi Mac'inizde derlemeyi,
değişikliği doğrulamayı ve gönderirken uyulacak kuralları anlatır.

## Başlamadan önce

- [`PRODUCT_PLAN.md`](PRODUCT_PLAN.md) güncel kapsamı ve kimin neyle uğraştığını gösterir.
  "🚧 Devam ediyor" notu olan bir maddeyi üstlenmeyin; yeni bir işe başlarken maddeyi aynı
  biçimde işaretleyin.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) katman sınırlarını, [`docs/DESIGN.md`](docs/DESIGN.md)
  tasarım dilini anlatır. Arayüz değişiklikleri bu dile uymalıdır.
- [`AGENTS.md`](AGENTS.md) insan ve yapay zekâ katkıcılar için ortak kurallardır.

## Kurulum

Gereksinimler: macOS 26+, güncel Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
2.45.4+ (`brew install xcodegen`).

1. İmza takımınızı yerel ayara yazın. Takım kimliği depoda tutulmaz:

   ```sh
   cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
   # dosyadaki DEVELOPMENT_TEAM değerini kendi takım kimliğinizle değiştirin
   ```

   `Config/Signing.local.xcconfig` git'e girmez. Takım vermezseniz Xcode derlerken sorar;
   yalnızca test için imzasız derleme de yapabilirsiniz (aşağıda).

2. Projeyi üretip açın:

   ```sh
   xcodegen generate
   open MeetingNotch.xcodeproj
   ```

## Kurallar

- Xcode ayarlarını yalnızca `project.yml` üzerinden değiştirin ve ardından
  `xcodegen generate` çalıştırın. `MeetingNotch.xcodeproj/project.pbxproj` elle düzenlenmez.
- Kullanıcı verisi (ses, transkript, takvim, görev) uygulamadan yalnızca kullanıcının seçtiği
  sağlayıcıya gider. Günlüklere, hata mesajlarına ve testlere gerçek kişisel veri yazmayın.
- API anahtarları yalnızca Keychain'de tutulur.
- Arayüz metinleri İngilizce yazılır. Çeviri desteği henüz yok; eklenecek dil String Catalog
  ile gelecek.
- Davranış değiştiren her değişiklik test içerir. Arayüz değişikliklerinde ekran dışı render
  testlerini (`CrenelDesignGalleryTests`) güncelleyin.

## Doğrulama

```sh
xcodebuild \
  -project MeetingNotch.xcodeproj \
  -scheme MeetingNotch \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build test
```

Arayüz değişikliğinin görüntülerini almak için `touch /tmp/MeetingNotchExportUIAudit`
çalıştırıp testleri koşun; görüntüler `artifacts/ui-audit/` altına yazılır.

İzin, takvim hesabı, dikte modeli veya başka uygulamaya yazma gerektiren davranışlar otomatik
testle doğrulanamaz. Bunları elle denediyseniz değişiklik açıklamasında nasıl denediğinizi
yazın; denemediyseniz açıkça belirtin.

## Gönderme

- Değişikliği küçük ve tek konulu tutun. Commit mesajı ne değiştiğini ve neden değiştiğini
  söylesin.
- Değişiklik açıklamasında doğrulama sonucunu (komut ve sonuç) paylaşın.
- Lisans: katkılarınız [MIT](LICENSE) lisansıyla yayımlanır.
