# Crenel dağıtım planı: imza, otomatik güncelleme, DMG

Durum: 2026-11-17. Checklist `PRODUCT_PLAN.md` › **C10** bölümündedir; bu belge o maddelerin
arka planını, araştırma sonuçlarını ve sıradaki adımları toplar. Yeni bir oturum buradan
devam edebilir.

## Bugüne kadar yapılanlar (2026-11-17)

- Uygulama her yerde **Crenel** oldu. Paket kimliği `gad.Crenel`, native host
  `com.gad.crenel.browser_audio`, Keychain servisleri `gad.Crenel.*`, veri klasörü
  `~/Library/Application Support/Crenel`.
- İlk açılışta `LegacyIdentityMigration` eski kimlikteki veriyi bir kez taşır: veri klasörü,
  defaults, Keychain anahtarları, eski Chrome native host manifesti. Eski ad yalnız bu
  dosyada ve testinde geçer.
- Sistem izinleri (mikrofon, takvim, hatırlatıcılar, erişilebilirlik) yeni kimlik için bir kez
  yeniden verilir.
- Depo monorepo oldu: `macos/`, `browser-extension/`, `docs/`, `website/` (yakında).
  GitHub: `ayhangad/Crenel` (private). Yerel klasör: `~/projects/Crenel`.
- 576 test geçti; uzantı, gizlilik ve oturum betik testleri geçti.
- **Henüz denenmedi:** migration'ın kullanıcının gerçek verisiyle ilk açılışı. İlk açılışta
  kayıtların ve ayarların yerinde olduğu kontrol edilmeli.

## Kararlar (kullanıcı onaylı)

| Konu | Karar |
| --- | --- |
| Dağıtım | Developer ID imzası + Apple notarization, doğrudan indirme. Mac App Store yok. |
| Güncelleme | Sparkle 2. DMG'ler GitHub Releases'ta, appcast GitHub Pages'te. |
| Güncelleme davranışı | Arka planda kendiliğinden iner. Hazır olunca amber "Update ready · Restart" hatırlatması. Kayıt sürerken asla yeniden başlatmaz. |
| "Coming soon" | OpenAI/Deepgram gibi sağlayıcılar disable halde, "coming soon" yazısıyla görünür kalır. |
| Applications'a taşıma | Uygulama Applications dışından (ör. DMG içinden çift tıklanarak) açılırsa "Applications'a taşıyayım mı?" diye sorar. Sürükleyerek kuranlar bunu hiç görmez. |
| DMG tasarımı | Koyu "notch'tan düşen ikon" konsepti. Önce prototip; etiketler okunmazsa açık zemine geçilir. (Kullanıcı henüz kesin onay vermedi, prototip sonrası bakacak.) |

## Neden "taşıyayım mı" sorusu?

DMG'yi açıp ikona çift tıklayan kullanıcıda uygulama `/Volumes/Crenel/` içinden çalışır:

1. Chrome köprüsü (`BrowserAudioNativeHostInstaller`) Chrome'a bu yolu yazar; DMG
   çıkarılınca Meet kaydı bozulur.
2. Sparkle salt okunur diskteki uygulamayı güncelleyemez.
3. DMG çıkarılınca uygulama kaybolur.

## Sıradaki adımlar

Kullanıcının elle yapacağı adımlar **teker teker** verilir. Her adımdan sonra kullanıcı haber
verir, sonuç kontrol edilir ve sonraki adıma geçilir.

### 1. Developer ID sertifikası (kullanıcı) — sıradaki adım

Kullanıcının Apple Developer hesabı var (yayında bir iOS uygulaması mevcut). Keychain'de şu
an yalnız `Apple Development` sertifikası var; bu yalnız geliştirme içindir.

Kullanıcıya verilecek adım:
Xcode › Settings… (`⌘,`) › Accounts › Apple ID › takım › **Manage Certificates…** › sol alttaki
**+** › **Developer ID Application**.

Kontrol: `security find-identity -v -p codesigning` içinde `Developer ID Application:` satırı.

### 2. Notarization profili (kullanıcı)

İlk adım doğrulanınca verilecek: appleid.apple.com'da uygulamaya özel parola oluşturulur,
ardından şu komut çalıştırılır:

```sh
xcrun notarytool store-credentials Crenel-Notary --apple-id <apple id> --team-id <Team ID>
```

Team ID developer.apple.com › Membership sayfasındadır.

Kontrol: `xcrun notarytool history --keychain-profile Crenel-Notary`.

`macos/Scripts/release-candidate.sh` bu profili bekler (`CRENEL_NOTARY_PROFILE` ile
değiştirilebilir).

### 3. Applications'a taşıma önerisi (kod)

### 4. Sparkle 2 entegrasyonu (kod)

### 5. Release hattı (kod)

### 6. DMG tasarımı ve prototip (kod + kullanıcı bakışı)

Bu adımların teknik ayrıntısı aşağıdadır.

## Araştırma: Sparkle 2 (Kasım 2026)

- Güncel kararlı sürüm **2.10.1** (2026-10-25). 2.11.0-beta.1 2026-11-17'de çıktı.
  SwiftPM: `https://github.com/sparkle-project/Sparkle` → `macos/project.yml` `packages:`.
- Apple'ın Developer ID uygulamaları için kendi güncelleme sistemi yok; Sparkle bu işin standart aracı.
- **Info.plist:** `SUFeedURL`, `SUPublicEDKey` (zorunlu), `SUEnableAutomaticChecks = YES`,
  `SUAutomaticallyUpdate = YES`, `SUVerifyUpdateBeforeExtraction = YES`,
  isteğe bağlı `SURequireSignedFeed`. Kontrol aralığı varsayılan 1 gün.
- **Anahtar:** `generate_keys` EdDSA özel anahtarını login Keychain'e koyar ve açık anahtarı
  yazar. `-x` dışa aktarır (CI secret için). CI'da `generate_appcast --ed-key-file -` stdin'den okur.
- **Menü çubuğu uygulaması:** `SPUStandardUserDriverDelegate.supportsGentleScheduledUpdateReminders = true`.
  - `standardUserDriverShouldHandleShowingScheduledUpdate` / `standardUserDriverWillHandleShowingUpdate`
    ile kendi göstergemizi gösteririz (notch/Ayarlar'da amber lamba).
  - `standardUserDriverDidReceiveUserAttention` ile göstergeyi kaldırırız.
  - Uyarı penceresi açıkken activation policy geçici olarak `.regular` yapılabilir.
  - Uygulama nadiren kapandığı için sessiz kurulum gecikir; hatırlatma bu yüzden şart.
- **Kayıt sırasında erteleme:** Sparkle'ın yeniden başlatma erteleme delegate'i
  kullanılır; kayıt bitmeden yeniden başlatma yapılmaz.
- **İmza:** Sandbox kapalı olduğu için XPC servisleri gerekmez. Xcode'un Developer ID export'u
  Sparkle'ın iç parçalarını (Autoupdate, Updater.app) yeniden imzalar. Elle imzalanacaksa
  içten dışa imzalanır, `--deep` kullanılmaz.
- **Arşiv:** Notarize edilmiş, imzalı DMG hem ilk kurulum hem güncelleme dosyası olur.
  - Delta güncellemeler `.app` paketlerinden üretilir. DMG ile nasıl çalıştığı doğrulanmadı.
- **Appcast:** `generate_appcast` klasördeki arşivleri imzalar, aynı adlı `.md`/`.html` sürüm
  notunu ekler. Ek seçenekler:
  - `--channel beta` beta kanalı,
  - `sparkle:minimumSystemVersion` (`26.0.0`),
  - `sparkle:phasedRolloutInterval` kademeli dağıtım,
  - `sparkle:criticalUpdate` kritik güncelleme.
- **Barındırma:** `--download-url-prefix https://github.com/ayhangad/Crenel/releases/download/<tag>/`;
  appcast GitHub Pages'te. Repo şu an **private**; private repoda Releases ve Pages herkese açık
  olmaz. Yayından önce repo public yapılmalı veya appcast ve DMG'ler başka yerde (ör. Cloudflare R2,
  web sitesi) barındırılmalı. **Bu karar kullanıcıya sorulmalı.**
- `CFBundleVersion` her sürümde artmalı; Sparkle sürümleri bununla karşılaştırır.

Kaynaklar: sparkle-project.org/documentation (customization, gentle-reminders, publishing,
sandboxing, delta-updates), github.com/sparkle-project/Sparkle/releases.

## Araştırma: DMG (Kasım 2026)

### Araçlar

| Araç | Durum | Not |
| --- | --- | --- |
| **dmgbuild** (Python) — **seçilen** | v2.0.0, 2026-11-16 | `.DS_Store`'u doğrudan yazar, Finder/AppleScript gerekmez, CI'da çalışır. 2.0'da `hdiutil` yerine `diskutil` (macOS 27'de hdiutil deprecated), varsayılan format ULFO. Sürüm sabitlenmeli. `SetFile` için Command Line Tools ister. |
| create-dmg (shell) | v1.3.0, 2026-07 | Finder'ı AppleScript ile sürer. GUI oturumu ister. |
| sindresorhus/create-dmg | v8.1.0 | appdmg sarmalayıcısı, az özelleştirilebilir. |
| appdmg | 2023'ten beri durgun | — |
| DropDMG / DMG Canvas | ücretli GUI | macOS 27 destekli. |

### Teknik gerçekler

- Arka plan **tek durağan resimdir**; animasyon yok. Aside'daki "hareket" çizimdir.
- Retina: dmgbuild `background.png` yanındaki `background@2x.png`'yi `tiffutil -cathidpicheck`
  ile birleştirir.
- Pencere boyutuna başlık çubuğu dahildir ve yüksekliği macOS sürümüne göre değişir.
  macOS 26 ve 27'de test edilmeli.
- dmgbuild varsayılanları: ikon 128, yazı 16, araç çubuğu, kenar çubuğu ve durum çubuğu kapalı.
- Applications bağlantısı symlink'tir (`symlinks = {"Applications": "/Applications"}`).
- Gizli dosyalar (`.background`, `.VolumeIcon.icns`) "gizli dosyaları göster" açık
  kullanıcılarda görünür; pencere dışına yerleştirilir.

### macOS 26/27 riskleri

- macOS 26.2'de arka plan görünmeme hatası dmgbuild 1.6.7'de düzeldi (#273).
- Applications symlink ikonunun boş görünmesi: macOS hatası, açık
  (create-dmg #202). Gerçek makinede test edilecek.
- Finder'ın özel arka planda ikon yazısını hangi renkte çizdiği **doğrulanamadı**. Bazı
  raporlar her modda siyah diyor. Koyu tasarımın riski budur, prototipte bakılacak.
- macOS 27'de `diskutil image create blank` HFS+ desteklemiyor (dmgbuild #302). APFS kullanılmalı.

### İmza ve notarization sırası

1. Uygulama Developer ID + hardened runtime ile imzalanır (`--deep` yok).
2. Uygulama notarize edilir ve damgalanır (staple). Uygulama sıkıştırılmış DMG içine girdikten
   sonra damgalanamaz.
3. dmgbuild ile DMG (ULFO veya UDZO; Apple aşırı sıkıştırmadan kaçınmayı önerir).
4. `codesign` ile DMG imzalanır.
5. DMG için `xcrun notarytool submit --wait`, ardından `xcrun stapler staple` ve
   `stapler validate`.
6. Checksum damgalamadan sonra alınır.

## Release hattı (hedef)

`macos/Scripts/release-candidate.sh` şu an zip üretiyor; şu hale getirilecek:

1. `xcodegen generate` → testler → `xcodebuild archive` → Developer ID export.
2. Uygulamayı notarize et ve damgala.
3. dmgbuild ile DMG; arka plan @1x/@2x, sürüm numarası arka plana basılı.
4. DMG imza → notarize → damgala → doğrula.
5. `generate_appcast` (EdDSA anahtarı Keychain'den, CI'da secret'tan).
6. GitHub Release'e DMG yükle; appcast'i Pages'e yayınla.

Daha sonra GitHub Actions'a taşınabilir:
- `.p12` sertifika geçici keychain'e alınır,
- notarytool App Store Connect API anahtarıyla (`--key/--key-id/--issuer`) çalışır,
- EdDSA anahtarı secret olarak tutulur.

## DMG tasarımı

### Örneklerin analizi

- **Aside (en iyisi):**
  - Dikey yön ve küçük pencere (yaklaşık 400×520), gözün gideceği tek hat.
  - Tek ışık kaynağı: ikondan klasöre açılan mavi koni, ok gerekmiyor.
  - Hareket izi: soluktan nete giden el imleçleri; animasyon değil, hareketin fotoğrafı.
  - Hafif nokta ızgarası ve minik telif satırı zanaat izi taşıyor.
- **Threads:** soluktan parlağa ok dizisi; Aside'daki izin yatay hali.
- **Grok:** tek büyük görsel ve yukarı ok; çarpıcı ama ürünle bağı zayıf.
- **Wonder:** pullar ve el çizimi okla kişilik var ama kalabalık.

### Öneri: "Notch'tan düşen ikon"

`docs/DESIGN.md` "gece sürüşü" diliyle:

```
┌──────────────────────────────────┐
│ ● ● ●        Crenel              │
├──────────────────────────────────┤
│          ▄▄▄▄▄▄▄▄▄▄▄▄            │  ← notch silüeti, pencerenin tepesinden sarkar
│           ┌──────────┐           │
│           │  Crenel  │           │  ← uygulama ikonu, notch'tan inmiş gibi
│           └──────────┘           │
│              Crenel              │
│                ▫                 │  ← hayalet hücre (%8)
│                ▫                 │
│                ▪                 │  ← yanmaya başlıyor
│                ■                 │  ← turkuaz #34e6cb, sıcak çekirdek
│           ░░░░░▓▓▓░░░░░          │  ← turkuaz ışık havuzu (Aside'ın konisinin karşılığı)
│          [Applications]          │
│           Applications           │
│   Crenel 1.0 · open source       │  ← Geist 10, ink-4, cümle düzeni
└──────────────────────────────────┘
```

- **Pencere ve zemin:** yaklaşık 440×540 pt. Zemin `#0b0b0b`, üzerinde %6 opak nokta
  ızgarası (hayaletler ilkesi).
- **Hareket izi:** lamba hücreleri hayaletten turkuaza yanar ("bilgi çizilmez, yakılır").
- **Yazı:** Geist; büyük harf ve harf aralığı açma yok (DESIGN.md kuralı).
- **Kaynak:** arka plan `docs/design/` altında kod olarak tutulur, @1x/@2x PNG üretilir,
  sürüm numarası release'de otomatik basılır.
- **B planı:** etiketler koyu zeminde okunmazsa Aside gibi açık zemin. Sıcak kâğıt
  `#f3f1ec` üstünde aynı turkuaz lambalar.

## Uygulama tarafında açık kalanlar

Bunlar başka bir oturumdan devreden işlerdir; dağıtımdan bağımsızdır.

- **Canlı ekranda bakılacaklar:**
  - menü çubuğu ikonu (açık ve koyu çubuk),
  - satırlar arası hover geçişi,
  - cetvelde bloğun üstüne gelince adın tam yazılması,
  - kapalı notch'taki "2h 37m".
- **Tasarımda olup verisi olmayanlar:**
  - katılımcılar ve daveti gönderen (sıradaki önerilen iş),
  - bloke nedeni,
  - dikte Undo ⌘Z,
  - aksiyon sayısı,
  - PDF/düz metin dışa aktarma,
  - mikrofon seviye testi,
  - "your usual" işareti.
- **Küçük eksikler:**
  - `esc`/`↩` yalnız notch paneli odaktayken çalışıyor,
  - `docs/DESIGN.md` bugünkü AI ayarları ve Recordings satır düzeniyle eşitlenmedi.

## Açık sorular (kullanıcıya)

1. Repo private. Güncellemeler için public mi yapılacak, yoksa DMG/appcast başka yerde
   (web sitesi, Cloudflare R2) mi barındırılacak?
2. DMG konsepti: prototipten sonra kesin onay.
