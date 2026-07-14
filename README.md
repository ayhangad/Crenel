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
ister. İzin değişikliğinden sonra macOS uygulamanın yeniden açılmasını isteyebilir.
Tamamlanan kayıtlar aşağıdaki klasörde iki ayrı ham M4A kaynak dosyası, ortak timeline'a
birleştirilmiş `recording.m4a` ve JSON metadata ile tutulur:

```text
~/Library/Application Support/MeetingNotch/Temporary/<session-id>/
```

Ham kaynaklar finalize hatalarında kurtarma için korunur. Uzun kayıtlardaki clock drift
düzeltmesi ve otomatik recovery akışı Faz 7.4'te açık görevdir.
