# Crenel — Product Development Plan

Bu dosya Crenel v1 tamamlanana kadar kullanılacak ortak ilerleme planıdır.
Yeni bir sohbet veya geliştirici çalışmaya başlamadan önce bu dosyayı okumalı,
uygun görevi seçmeli ve çalışmanın durumunu yine bu dosyada güncellemelidir.

## Ortak çalışma kuralları

- `[ ]` başlanmamış görev
- `[x]` tamamlanmış ve doğrulanmış görev
- Devam eden görev, checkbox işaretlenmeden satır sonuna
  `— 🚧 Devam ediyor: <tarih / sohbet>` notu eklenerek rezerve edilir.
- Bloke görev, satır sonuna `— ⛔ Bloke: <sebep>` notu eklenerek açıklanır.
- Bir görev yalnızca kodu, ilgili doğrulaması ve gerekli dokümantasyonu tamamlandığında
  `[x]` yapılır.
- Her sohbet önce devam eden bir görev olup olmadığını kontrol eder. Başka bir sohbetin
  devam eden görevini üstlenmez.
- Görev sırasında kapsam veya ürün kararı değişirse önce bu plan güncellenir.
- Geçici teknik araştırma sonuçları nihai ürün kararı sayılmaz. Ürün deneyimini en iyi
  karşılayan uygulanabilir çözüm seçilir.
- Büyük görevler tek seferde tamamlanamıyorsa bu dosyada daha küçük alt görevlere bölünür.
- Plan sıralıdır. Bir fazın çıkış kriterleri tamamlanmadan ona bağımlı sonraki faz
  tamamlanmış sayılmaz.

## 2026-11-16 — Crenel: Apple yardımcısı (güncel öncelik)

Bu bölüm aşağıdaki tüm eski öncelik kararlarının (V1 odak kararı, "toplantı-first",
"tek bulut API", "yeni görev özelliği geliştirilmez", "cihaz üstü transkripsiyon ve canlı
transkript kapsam dışı") yerine geçer. Eski checklist'ler geçmiş kanıt olarak korunur.

### Ürün tanımı

Crenel, notch içinden kontrol edilen, açık kaynak, minimal bir macOS Apple yardımcısıdır.
Ad: *crenel*, sur dişleri arasındaki çentik (notch). Dört yetenek tek notch yüzeyinde
birleşir; her biri az girdi ve sıfır ek uğraş ilkesine uyar:

1. **Takvim yardımcısı** — Yaklaşan toplantı ve etkinlikler doğrudan Apple Takvim'den
   (EventKit) okunur. Kapalı notch'un sağında kalan süre ("12 dk", başladıktan sonra
   "25 dk kaldı") görünür. Google/Exchange/iCloud hesapları macOS İnternet Hesapları
   üzerinden gelir; ayrı Google OAuth kaldırılır. E-posta davetleri (Gmail'in takvime
   eklediği davetler, iCloud/Exchange bekleyen davetleri) yanıt bekliyor olarak gösterilir.
2. **Akıllı dikte** — Kısayol (basılı tut veya aç/kapa, Fn/Globe desteği) ile konuşma,
   imlecin olduğu uygulamaya yazılır. Ses cihazda yazıya çevrilir (Apple SpeechAnalyzer);
   kayıt diske yazılmaz. Agent metni temizler, noktalar, uygulamaya göre üslup uygular.
3. **Toplantı kaydı** — Mevcut güvenli kayıt, transkript ve özet akışı korunur; kayıtlar
   yerelde kalır. Yerel transkripsiyon seçeneği eklenir.
4. **Görevler** — Tek liste, tek satır giriş. Yazarken altta tarih/tekrar/öncelik önerisi
   çıkar; Tab ile kabul edilir, Enter düz kaydeder. Görevler Apple Hatırlatıcılar'da
   uygulamaya ait tek listede saklanır; "üzerinde çalışılıyor" ve sıralama gibi Mac'e özel
   bilgiler yerel yan dosyada tutulur. İzin yoksa yerel dosya yedek depo olur. Tamamlanan
   görev otomatik arşivlenmez; gün boyunca üstü çizili kalır, sonra Tamamlananlar'a geçer.

### Kararlar

- Minimum sistem macOS 26. SpeechAnalyzer ve Foundation Models doğrudan kullanılır.
- Dikte yerel çalışır. Agent sağlayıcısı: yerel Apple Foundation Models (varsayılan),
  kullanıcının kendi OpenAI veya Anthropic anahtarı (isteğe bağlı, Keychain'de).
- Toplantı transkripsiyonu: ElevenLabs, Deepgram (2026-11-18, kullanıcı isteği) veya yerel
  SpeechAnalyzer.
- Takvim tek kaynak: EventKit. Google OAuth kodu ve ayarları kaldırılır.
- Görev deposu: Apple Hatırlatıcılar (EventKit reminders) + yerel yan veri; izin yoksa
  yerel JSON. Eski görevler bir defalık taşınır, eski dosya yedek olarak bırakılır.
- Tasarım son aşamada kullanıcıyla birlikte güncellenir. O zamana kadar yeni yüzeyler mevcut
  `CrenelTheme` diline uyar.
- Ad değişimi: görünen ad ve ürün adı Crenel olur. Bundle kimliği, Keychain servisleri ve
  veri klasörü, macOS izinleri ve kullanıcı verisi kaybolmasın diye yayın hazırlığına kadar
  korunur. Kod içi `Crenel` adlandırması kademeli olarak değişir.

### C0 — Kapsam ve temel

- [x] Crenel ürün kapsamını, kararları ve faz planını belgelemek.
- [x] macOS 26 hedefi, Crenel görünen adı, Hatırlatıcılar/konuşma/Input Monitoring izin
  metinlerini `macos/project.yml` üzerinden uygulamak. — ✅ 2026-11-16
- [x] Mimari belgeye Crenel katmanlarını (Dictation, Agent, Reminders, takvim
  sınıflandırması) eklemek. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)

### C1 — Apple Takvim yardımcısı

- [x] EventKit sağlayıcısının tüm etkinlikleri (linksiz, fiziksel, tüm gün) okuması;
  toplantı/etkinlik/tüm gün sınıflandırması; reddedilen ve "boş" etkinlikleri gizlemek,
  yanıt bekleyen daveti işaretlemek. — ✅ 2026-11-16
- [x] Kapalı notch'ta sıradaki etkinlik geri sayımı ve süren etkinlikte kalan süre. — ✅ 2026-11-16
- [x] Notch Bugün görünümünde günün kalan etkinlikleri; katıl / Takvim'de aç aksiyonları. — ✅ 2026-11-16
- [x] Google OAuth sağlayıcısını, ayarlarını ve Info.plist anahtarlarını kaldırmak;
  hesap yoksa İnternet Hesapları kısayolunu göstermek. — ✅ 2026-11-16
- [x] Sınıflandırma, geri sayım ve kaldırma için testler. — ✅ 2026-11-16

### C2 — Görevler yeniden tasarımı

- [x] Görev modelini sadeleştirmek: açık / üzerinde çalışılıyor / tamamlandı; son tarih,
  tekrar, öncelik, kaynak toplantı. Eski 5 durumlu veriyi kayıpsız taşımak. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Türkçe/İngilizce akıllı giriş çözümleyicisi (tarih, saat, göreli gün, tekrar,
  öncelik) ve kapsamlı testleri. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Yazarken alt satırda öneri; Tab kabul, Enter düz kayıt. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Apple Hatırlatıcılar deposu (uygulama listesi, alarm, tekrar, öncelik, deep link)
  + yerel yan veri; izin yoksa yerel JSON yedeği; eski görevleri taşıma. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Tamamlananların gün sonuna kadar görünmesi, Tamamlananlar geçmişi, erteleme,
  üzerinde çalışılan görevin kapalı notch'ta görünmesi. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Toplantı aksiyonunu göreve aktarmanın yeni modele uyarlanması. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)

### C3 — Akıllı dikte

- [x] Dikte kısayolu: basılı tut / aç-kapa; Fn/Globe ve değiştirici tuş desteği
  (CGEventTap); ayarlardan seçim. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Bellek içi mikrofon akışı ve yerel SpeechAnalyzer transkripsiyonu; dil seçimi. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] İmlece yazma: Accessibility ile doğrudan, olmazsa panoya kopyala + ⌘V ve panoyu
  geri yükleme. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Notch dikte görünümü: dinleme, işleniyor, eklendi; ses seviyesi. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Toplantı kaydı sırasında dikte politikası: kayıt mikrofonunu bozmadan dikte
  kullanılabilir, dikte sesi toplantı kaydına girmez. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Yerelde dikte geçmişi (son N kayıt, kopyala/yeniden ekle) ve kişisel sözlük. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)

### C4 — Agent

- [x] Sağlayıcı soyutlaması: Foundation Models, OpenAI, Anthropic; anahtarlar Keychain'de. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Dikte temizleme: dolgu sözcükleri, noktalama, kendini düzeltme; uygulamaya göre
  üslup (Mail, Slack/Messages, kod editörü). — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Komut modu: seçili metni sesle dönüştürme ("daha kısa yap"). — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Dikteyle görev ekleme ("görev ekle ...") ve akıllı giriş çözümleyicisine bağlama. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Agent yokken veya hata olduğunda ham metne güvenli düşüş. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Varsayılan ve önerilen sağlayıcı "Otomatik": tek API anahtarı yeter (önce Anthropic
  Claude Haiku, yoksa OpenAI); anahtar yoksa cihazdaki Apple modeli. Anthropic varsayılan
  modeli `claude-haiku-5-5`. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] İsteyen kullanıcı Ayarlar'dan bilgisayarındaki Claude Code veya Codex
  oturumunu sağlayıcı olarak seçebilsin (API anahtarı gerekmeden). Süreç başına saniyeler
  sürdüğü için yalnız özet ve agent işleri; dikte deterministik temizlikle kalır. — ✅ 2026-11-17 (otomatik test + gerçek Claude Code CLI duman testi; Codex komutu elle doğrulandı)

### C3.1 — Dikte düzeltmeleri (2026-11-16 kararları)

- [x] Fn dikte tuşuyken macOS "🌐 tuşuna basınca" ayarı Crenel tarafından "Hiçbir şey
  yapma"ya alınır; kullanıcının eski değeri saklanır, dikte kapanınca, tuş değişince veya
  uygulama kapanınca geri yüklenir. Kullanıcı başka kısayol seçebilir. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] İmlece yazmada uygulama listesi kaldırıldı: doğrudan yazma yalnızca sonucu
  doğrulanabildiğinde, aksi her durumda ⌘V + pano geri yükleme. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)

### C5 — Toplantı iyileştirmeleri

- [x] Yerel SpeechAnalyzer toplantı transkripsiyonu seçeneği. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Özet için agent sağlayıcısını (yerel / OpenAI / Anthropic) kullanmak. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Karar (2026-11-16): aksiyon maddeleri yalnızca kullanıcının kendisine yöneltilenler;
  başkalarının aksiyonları ilk sürümde gösterilmez. Kişi ayrımı için ek efor yok. — ✅ 2026-11-17
  (istem + `MeetingOwner` süzgeci; sahibi belirsiz maddeler korunur; gerçek toplantı kabulü C8'de)

### C6 — Açık kaynak ve yayın hazırlığı

- [x] LICENSE: MIT (kullanıcı kararı 2026-11-16). — ✅ 2026-11-16
- [x] Katkı rehberi (CONTRIBUTING). — ✅ 2026-11-17
- [x] README'nin Crenel kapsamıyla yenilenmesi. — ✅ 2026-11-16
- [x] `macos/project.yml` içindeki kişisel `DEVELOPMENT_TEAM` değerinin katkıcıların kendi
  takımını verebileceği yerel bir ayara taşınması (`macos/Config/Signing.local.xcconfig`, git dışı). — ✅ 2026-11-17
- [x] Bundle kimliği (`gad.Crenel`), veri klasörü, defaults, Keychain servisleri ve Chrome
  native host adının Crenel'e taşınması; ilk açılışta tek seferlik migration
  (`LegacyIdentityMigration`). Depo monorepo yapısına geçti: `macos/`, `browser-extension/`,
  `website/` (yakında). — ✅ 2026-11-17
- [x] Web sitesi (`website/`, Astro): ana sayfa (canlı notch, boyut seçici, özellik hikâyesi,
  gizlilik, SSS) ve `docs/releases/*.md`'den beslenen sürüm sayfası. Dokploy'da (host.gad.works,
  proje "Crenel") `https://crenel.ayhan.fyi`; `main`'e push `website/**` veya
  `docs/releases/**` değişince otomatik yayınlanır. Alan adı `SITE_URL` build argümanıyla.
  İletişim yalnızca X (@ayhangad). — ✅ 2026-11-18

### C10 — Dağıtım: imza, otomatik güncelleme, DMG (2026-11-17 kararları)

Ayrıntı, araştırma ve sıradaki adımlar: `docs/DISTRIBUTION.md`.

Kararlar: Developer ID + notarization ile doğrudan dağıtım. Güncellemeler Sparkle 2 ile;
DMG'ler GitHub Releases'ta, appcast GitHub Pages'te. Güncelleme arka planda iner,
hazır olunca amber "Update ready · Restart" hatırlatması çıkar; kayıt sürerken yeniden
başlatılmaz. "Coming soon" sağlayıcılar disable halde görünür kalır. Uygulama
Applications dışından (ör. DMG içinden) açılırsa Applications'a taşımayı önerir.

- [ ] Developer ID Application sertifikası ve `Crenel-Notary` notarytool profili.
  — ⛔ Bloke: kullanıcının Apple hesabında adım adım yapılacak.
- [x] Notch'ta güncelleme durumları (`docs/design/update-mock.html`): iniyor (yüzde + fitil),
  hazırlanıyor, hazır şeridi (Later · Restart), kayıt sırasında bekliyor, yeniden başlıyor,
  güncellendi şeridi; açık panelde "Restart to update". Sparkle'dan bağımsız durum modeli,
  Debug'da sahte güncelleme kaynağı. — ✅ 2026-11-17 (578 test, 5 atlandı, 0 hata; yedi
  durumun render'ı incelendi; Sparkle bağlantısı ayrı madde)
- [x] Applications dışından açılınca taşıma önerisi (`ApplicationsMover`: DMG, App
  Translocation ve diğer yerler; eski kopya Çöp'e, yeni yerden yeniden açılış; Debug'da
  kapalı). — ✅ 2026-11-17 (birim testleri ve Release build; gerçek DMG'den açılış C8'de)
- [ ] Sparkle 2 entegrasyonu (EdDSA anahtarı, appcast, nazik hatırlatma, kayıt sırasında erteleme,
  Ayarlar › About'ta "Check for Updates"). — 🚧 Devam ediyor: 2026-11-17. Kod tamam: Sparkle
  2.10.1 (SPM, tam sürüm), `SparkleAppUpdater` özel `SPUUserDriver` ile notch durumlarını
  sürer, Restart kayıt sırasında reddedilir; EdDSA anahtarı login Keychain'de (hesap
  `gad.Crenel`), açık anahtar `project.yml`'de; feed `https://ayhangad.github.io/Crenel/appcast.xml`.
  Kalan: imzalı iki sürümle gerçek güncelleme denemesi (release hattından sonra).
- [ ] Release hattı: archive → notarize → dmgbuild DMG → DMG imza/notarize/staple →
  `generate_appcast` → GitHub Release + Pages. — 🚧 Devam ediyor: 2026-11-17.
  `Scripts/release-candidate.sh <sürüm> [--publish | --unsigned]` yazıldı; `--unsigned` uçtan
  uca geçti (testler, Release build, DMG). İmzalı yol Developer ID sertifikası ve notary
  profili gelince denenecek.
- [x] DMG tasarımı: koyu "notch'tan düşen ikon" prototipi; açık/koyu modda etiket okunurluk
  testi (macOS 26 ve 27), okunmazsa açık zemine geçiş. — ✅ 2026-11-17 (kullanıcı Finder'da
  onayladı; macOS 27'de denendi, macOS 26 denemesi C8'de).
  `Scripts/dmg/background.swift` + `settings.py`. İlk denemede Finder etiketleri koyu
  zeminde siyah çizildi ve pencere istenenden uzun açılıp alt kısım beyaz kaldı; arka plan
  1100 pt uzun çiziliyor, etiketlerin altına açık zemin kondu; pencere 600 pt, yerleşim 480 pt.

### C11 · Yayın öncesi son düzeltmeler (2026-11-18)

- [x] Denetimin tam metni, çalışma kuralları ve açık kabul ölçütleri [tek devir raporunda](docs/DENETIM-2026-11-18.md) toplandı. 25 madde, kaynak bağlantıları ve ilk denetim metninin korunduğu doğrulandı.

- [x] Notch hover düzeltmesini ve 01-07, 09-25 bulgularının kod düzeltmelerini davranış testleriyle doğrulamak. 18 Kasım 2026. Tam macOS koşusunda 666 test, 5 atlama, 0 hata. Chrome uzantısında 10, sitede 4 tarayıcı testi geçti. Bulgulara karşılık gelen testler ve performans ölçümü [denetim raporunda](docs/DENETIM-2026-11-18.md).
- [ ] A. Gerçek imleçle, notch’tan hızla listenin altına indikten ve içerik kısaldıktan sonra kapanma kabulü. Kullanıcı doğrulayacak.
- [ ] 01. İzinli gerçek toplantıda dikte, sessize alma, erişim kaybı ve kayıt başlangıcı sırasında ham mikrofon ve birleşik ses kabulü.
- [ ] 05 ve 06. Gerçek Chrome'da Meet sekmesini yenileme, başka kökene geçiş ve yakalama başlarken durdurma kabulü.
- [x] 08. Herkese açık 1.0 DMG ve Sparkle beslemesi. 18 Kasım 2026: v1.0 (150) GitHub Releases'ta, appcast gh-pages'te yayında, `release-availability-test.py 1.0` geçti. Kullanıcı 87 → 148 → 149 → 150 yerel Sparkle güncellemesini, izinleri ve pencere davranışını kendi Mac'inde doğruladı.
- [ ] 08, 15, 16 ve 19. Dağıtım imzasıyla temiz Mac'te noter, Applications'a taşıma, yerel yardımcı ve iki imzalı sürüm arasında güncelleme kabulü.
- [x] Astra düzeltmelerinin incelemesinde çıkan ikinci tur: 04, 06, 07, 11, 14, 15, 18, 19, 20, 21, 23. 18 Kasım 2026. Tam macOS koşusu 672 test, 5 atlama, 0 hata. Uzantı 10, site 5 test geçti. Claude Code argümanları gerçek CLI'de doğrulandı. [Denetim raporu](docs/DENETIM-2026-11-18.md)
- [ ] 11 ve 04 cihaz kabulü: iCloud'da veri silme sonrası aynı Crenel listesinin bulunması, bozuk ayar uyarısı ve sıfırlama.
- [x] Güvenlik, gizlilik, performans ve ürün kalitesini monorepo genelinde denetleyip tek raporda belgelemek. 18 Kasım 2026. [Denetim raporu](docs/DENETIM-2026-11-18.md)

- [x] Çoklu ekran: kullanıcı notch'u tutup başka ekranın üstüne sürükleyebilsin; bıraktığı
  ekranda çalışsın ve seçim (ekran UUID'si) hatırlansın. Ekran çıkarılınca fiziksel notch'lu
  ekrana düşer, geri takılınca seçtiği ekrana döner. — ✅ 2026-11-18 (kullanıcı iki ekranda denedi)
- [x] Önceki hover denemesindeki 0,6 saniyelik süreyi açılış boyunca geçerli geometri takibiyle değiştirmek. Cihaz kabulü yukarıda açık.
- [x] Deepgram'ı ElevenLabs'e alternatif toplantı transkripsiyon sağlayıcısı olarak bağlamak: Nova-3, konuşmacı ayrımı, ayrı Keychain anahtarı, Ayarlar › AI › Voice seçimi ve anahtar doğrulama. — ✅ 2026-11-18 (tam macOS koşusu 682 test, 5 atlama, 0 hata; gerçek anahtarla Türkçe toplantı kabulü aşağıda açık)
- [x] Deepgram gerçek anahtar kabulü. — ✅ 2026-11-18 (kullanıcı Debug build'de denedi, çalışıyor)
- [x] 1.1 yayını: imzalı DMG, GitHub Release (`Crenel.dmg` dahil), appcast. — ✅ 2026-11-18 (v1.1 build 154 Latest; `release-availability-test.py 1.1` geçti; site indirme bağlantısı 1.1 DMG'sini veriyor. İlk deneme, test sırasında build klasörleri silindiği için yayınlanmadan durdu.)

### C12 · Test kullanıcısı geri bildirimi (2026-11-20)

Bir test kullanıcısı dört sorun bildirdi; kullanıcı ayrıca kaydın mikrofonu açık başlatmasını
istedi. Karar (2026-11-20): toplantı mikrofonu her kayıtta açık başlar, isteyen kapatır. Bu,
aşağıdaki “Mikrofon gizlilik sözleşmesi”ndeki varsayılan kapalı kuralının yerine geçer.

- [x] Takvim izni ilk açılışta çalışmıyor, yeniden başlatınca çalışıyordu: izin gelince
  EventKit store'u yeniden kurmak (takvim ve Hatırlatıcılar). — ✅ 2026-11-20 (otomatik test)
- [x] Fn dikte tuşuyken Crenel kapandıktan sonra 🌐 tuşu Mac yeniden başlatılana dek
  çalışmıyordu: ayarı HIToolbox ile canlı yazıp geri yüklemek. — ✅ 2026-11-20 (otomatik test)
- [x] Slack huddle'da “toplantı yok” deyip kayıt başlamıyordu: eski oturum, Meet olmayan
  Chrome sesi, boşta Zoom ve takvim linki kaydı engellemesin; sistem sesinin tamamıyla
  kaydetsin. — ✅ 2026-11-20 (otomatik test)
- [x] Kayıt hiçbir zaman engellenmez (karar 2026-11-24, V1 "Chrome'da global sese düşmez"
  kuralının yerine geçer): Meet sekmesi uzantıyla bağlı değilse veya Zoom süreci
  eşleşmiyorsa kayıt sistem sesinin tamamıyla başlar. — ✅ 2026-11-24 (otomatik test; tam koşu 692 test, 5 atlama, 0 hata)
- [x] Mikrofon ve diğer izinler sürekli düşüyordu: Debug build ve testler aynı `gad.Crenel`
  kimliğini farklı sertifikayla kullanıp yayın sürümünün TCC kaydını eziyordu. Debug artık
  `gad.Crenel.dev` / "Crenel Dev". — ✅ 2026-11-24 (build ayarları doğrulandı; tam koşu geçti)
- [x] Takvim izni verildikten sonra ajanda dakikalarca boş kalıyordu: izin varken takvim
  görmeyen EventKit store'u her sorguda yeniden kurmak; uygulama öne gelince izinleri ve
  takvimi hemen yenilemek. — ✅ 2026-11-24 (tam koşu geçti)
- [x] Takvim/Hatırlatıcılar izni verildiği halde uygulama "Allow" göstermeye devam ediyordu:
  `EKEventStore.authorizationStatus` süreç içinde önbellekte kalıyor; `EventKitAccess` bu
  oturumda alınan izni ve yeni store ile okuma denemesini de sayıyor. — ✅ 2026-11-24 (tam koşu 693 test)
- [x] Tek Record: Today'de sayaç satırının sağında her zaman aynı buton (toplantı olsun
  olmasın); Meet konsolu ayrı Record göstermez. Kayıt tamamlandı, hata, iptal ve işleme
  durumlarından da başlıyor. — ✅ 2026-11-24 (otomatik test)
- [ ] Cihaz kabulü: Meet sekmesi uzantıya bağlı değilken kayıt sistem sesiyle başlıyor;
  Xcode koşusundan sonra yüklü Crenel'in mikrofon izni duruyor; takvim izni verilince ajanda
  yeniden açmadan doluyor ve "Connected" görünüyor; Today'deki tek Record her durumda
  sayaç satırında. Kullanıcı doğrulayacak.
- [x] Notch'taki Cancel/Stop işe yaramıyordu: onayı sistem alert'i yerine notch içinde
  sormak. — ✅ 2026-11-20 (otomatik test; tam koşu 691 test, 5 atlama, 0 hata)
- [x] Kayıt mikrofonu varsayılan açık; mute sinyali kapatır, belirsizlik değiştirmez. — ✅ 2026-11-20 (otomatik test)
- [x] 1.2 yayını: imzalı ve noter onaylı DMG, GitHub Release (`Crenel.dmg` dahil), appcast. — ✅ 2026-11-20 (v1.2 build 157 Latest; `release-availability-test.py 1.2` geçti)
- [ ] Cihaz kabulü: temiz izinle takvim bağlantısı; Fn ile dil değiştirme Crenel kapanınca
  hemen geri geliyor; Slack huddle kaydında iki taraf da duyuluyor; notch'ta Cancel ve
  Stop processing onayı. Kullanıcı ve test kullanıcısı doğrulayacak.

### C13 · Ölçü sistemi ve rafine arayüz (2026-11-22)

Kullanıcı kararı: stil, ikonlar ve akış aynı kalır; boşluk, hiza ve tipografi
`docs/design/notch-refine-study.html` (tur 6) çalışmasındaki ölçü modeliyle bütün uygulamaya
uygulanır. Model: görünen boşluk (harf yüksekliği/taban çizgisi ve ikon mürekkebi), referans
ritmi (başlık ↔ meta 7, öğeden öğeye 20, etiket → grup 20, bölüm 28, kenar 20), iki satır tipi
(ikonlu satır payı 10; karolu satırda karo etrafında 4), tek hover köşesi 10, etiket sayacı
“Label · n”, alan yüksekliği 34.

- [x] Ölçü token'ları, yazı kırpma ve satır tiplerini `Hud`'a eklemek; notch, masaüstü ve
  Ayarlar ekranlarını bu modele taşımak; galeri render'larıyla doğrulamak. — ✅ 2026-11-22
  (tam macOS koşusu 691 test, 5 atlama, 0 hata; galeriler piksel ölçümüyle kontrol edildi)
- [ ] Kullanıcının uygulamada gözden geçirmesi.
- [x] 1.3 yayını: imzalı ve noter onaylı DMG, GitHub Release (`Crenel.dmg` dahil), appcast. — ✅ 2026-11-22 (v1.3 Latest; `release-availability-test.py 1.3` geçti)

### C8 — Gerçek cihaz kabulü

Otomatik testler gerçek izinleri, EventKit/Hatırlatıcılar hesaplarını, event tap'i,
SpeechAnalyzer modelini ve başka uygulamalara yazmayı çalıştıramaz. Bunlar elle doğrulanır.

- [ ] Takvim: iCloud + İnternet Hesapları'ndan Google; Gmail daveti, iCloud daveti,
  Siri önerisi; kapalı notch geri sayımı ve süren etkinlikte kalan süre.
- [ ] Hatırlatıcılar: ilk bağlantı ve yerel görev taşıma; iPhone'da ekle/tamamla → notch;
  saatli görev bildirimi; tekrarlayan görev tamamlama.
- [ ] Dikte: Fn basılı tut / çift dokunuş; Türkçe ve İngilizce model indirme; Notes, Mail,
  Slack, Chrome, VS Code, Terminal'e yazma; şifre alanında reddetme; Esc iptal.
- [ ] Agent: cihazda model, OpenAI ve Anthropic anahtarıyla temizlik ve komut modu.
- [ ] Toplantı kaydı sırasında dikte: dikte sesi kayda girmiyor, gate geri açılıyor.

Doğrulama (2026-11-16): `xcodebuild test` 488 test, 4 opt-in test atlandı, 0 hata.
Yeni ekranlar (görevler, notch etkinlik listesi, kapalı notch geri sayımı/dikte, Ayarlar ›
Dikte/Görevler/Yapay zekâ) ekran dışı render ile incelendi; Debug uygulaması açıldı ve
hata kaydı olmadan çalıştı. Gerçek izinli cihaz kabulü C8'de.

### C7 — Tasarım (kullanıcıyla birlikte, en son)

- [x] Notch ve masaüstü tasarımının birlikte güncellenmesi ("enstrüman" dili, `docs/DESIGN.md`).

### C9 — Bütünsel deneyim yeniden yapımı (2026-11-16 kullanıcı kararı)

Kullanıcı geri bildirimi: takvim izni verilemiyor; Hatırlatıcılar ayrıca Görevler'den
bağlanıyor; "görevi başlat" anlamsız; satıra basınca metin düzenleme açılıyor; tasarım
düz, sabit boyutlu, design system yok; notch akışkan değil. Karar: modüller tek tek
ayarlanmaz, tek onboarding hepsini kurar; görevin basit durumu vardır; notch tek bir
şekil olarak her amaca göre biçimlenir. C7'nin yerine geçer.

- [x] Takvim/Hatırlatıcılar izninin Hardened Runtime altında sessizce reddedilmesini
  düzeltmek (`com.apple.security.personal-information.calendars`), izin öncesi
  uygulamayı öne almak. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Görev durumu: Yapılacak / Devam ediyor / Bloke / Bitti; "başlat" aksiyonu yok,
  durum glifinden seçilir; satır dokunuşu detay kartı açar (satır içi metin düzenleme
  yok); eski veri kayıpsız. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Tek onboarding: tüm izinler tek ekranda, "Hepsini aç"; Hatırlatıcılar varsayılan
  depo ve izin verilince otomatik bağlanır; Görevler'de bağlantı çağrısı yok. Mevcut kullanıcılara bir defa gösterilir. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Design system: boşluk/tipografi/renk/radius/hareket token'ları, özel çizim ikonlar,
  Metal shader'lar, ortak bileşenler. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [x] Notch motoru: DynamicNotchKit yerine tek şekil, kompakt ↔ geniş yay morph'u,
  içerik boyutuna göre esneyen yerleşim, hover/hit-test. — ✅ 2026-11-16 (otomatik test; gerçek cihaz kabulü C8'de)
- [ ] Notch yüzeylerinin yeni sistemle yeniden yapılması. — 🚧 Devam ediyor: 2026-11-16
  - [x] Kompakt durumlar (dikte nokta küresi + seviye, kayıt, işleme, ajanda halkası,
    devam eden görev), Bugün (ışıklı sıradaki etkinlik kartı + ajanda + görev özeti),
    Görevler, canlı kayıt kartı, panel başlığı. — ✅ 2026-11-16 (ekran dışı render + test)
  - [x] Dikte için genişleyen "canlı" ara boyut (orb + canlı transkript). — ✅ 2026-11-17 (626 test,
    5 atlandı, 0 hata; ekran dışı render incelendi, orb shader'ı gerçek notch'ta kabul bekliyor)
  - [x] Açık panelde sekmeler kamera bandının altında kendi satırında; Recordings ikon
    değil üçüncü sekme (Today · Recordings · Tasks, ⌘1/⌘2/⌘3). — ✅ 2026-11-17 (571 test,
    5 atlandı, 0 hata; band render'ları incelendi; gerçek notch'ta kullanıcı kabulü bekliyor)
  - [x] Recordings satırları (`docs/design/recordings-mock.html`): ay grupları, segment gün
    karosu metin yüksekliğinde, başlık + saat · platform · aksiyon/durum + özetten tek satır,
    süre ve gerçek dalga formu; hover'da Play/Open; satırlar arası boşluk, zeminler çakışmaz. — ✅ 2026-11-17
    (572 test, 5 atlandı, 0 hata; normal ve hover galerisi render'ları incelendi; gerçek
    notch'ta kullanıcı kabulü bekliyor)
  - [x] Recordings lambası yalnız dikkat isteyen kayıtta; dalga formu çizilmiş desen (ses
    okunmaz, panel takılmaz). Today listesi aynı satır dilinde (tarih karosu, süre, hover
    Join, davette amber lamba). Kapalı notch boşta kapanmaz: işaret + görev sayısı, yoksa
    başka gündeki ilk etkinlik, yoksa dikte tuşu. — ✅ 2026-11-17 (572 test, 5 atlandı,
    0 hata; Today ve kapalı notch render'ları incelendi; gerçek notch'ta kabul bekliyor)
  - [x] Bugünkü etkinliklerin karosunda yalnız saat; karo içeriğine göre yükselir (6 pt
    üst/alt), satırlar ortalı; hover düğmeleri satırın kendi hover'ıyla anında, Today
    listesi hover'ı kadranı yeniden çizdirmez. — ✅ 2026-11-17 (572 test, 5 atlandı, 0 hata;
    Today ve Recordings render'ları incelendi; gerçek notch'ta kabul bekliyor)
  - [x] Tab geçişi performansı: tablar bellekte kalır, gizli tab'ın döngü ve kısayolları
    `HudVisibility` ile durur, tab seçimi ayrı `PanelNavigation`'da; hover'da
    `ignoresMouseEvents` yalnız değişince yazılır. "Nothing else today" satırı sıradaki
    etkinliği yazmaz, o Later listesinde kalır. — ✅ 2026-11-17 (Instruments: ilk kare
    50–67 ms → 9–12 ms; 572 test, 5 atlandı, 0 hata)
  - [x] Toplantı detayı, işleme/hata/teklif yüzeyleri ve kurtarma uyarısının yeni sisteme
    taşınması. — ✅ 2026-11-16 (`9dc6708`)
  - [x] Masaüstü çalışma alanı ve Ayarlar'ın yeni sistemle yeniden yapılması. — ✅ 2026-11-16 (`9dc6708`)
  - [x] HTML prototipin yeni dille yeniden tasarlanması: çağdaş ürün yapısı içinde retro
    gösterge ayrıntıları (hayalet segmentli rakamlar, tarama göstergeleri, gösterge
    lambaları), üç boyutlu notch (kompakt / şerit / açık), yeni ikon ailesi, hareket dili;
    `docs/DESIGN.md` güncel spesifikasyon. — ✅ 2026-11-17 (110 durum headless tarayıcıda
    hatasız render edildi; hover/sekme/görev/dikte/geri sayım etkileşimleri Playwright ile sürüldü)
  - [x] Prototipte ikinci tur: masaüstü penceresinin yeniden kurulması (Today gösterge
    panosu, Meetings sayfa + ray, Tasks rayı, Dictation bölümü, Settings ikinci ray ve
    sayfa başlıkları, kayan ray lambası, Systems lamba paneli), secondary/danger buton ve
    tuş kapağı sistemi, "eylemler sağ kenarda biter" yerleşim kuralları (notch konsolu,
    şeritler, sonuç/hata/işleme eylem satırları), göstergelerin ışık modeli (head, tail,
    halo, iç noktalar, sıcak çekirdekli lambalar, kuyu, LED yığını). — ✅ 2026-11-17
    (112 durum headless tarayıcıda hatasız; etkileşim testi geçti)
  - [x] Kullanıcının lamba-mazgal ikonunun uygulama ikonu yapılması: Icon Composer
    `macos/Crenel/AppIcon.icon` (boş `AppIcon.appiconset` kaldırıldı), "hazır" lambası
    ikonun turkuazına çekildi. — ✅ 2026-11-17 (`ictool` render incelendi; Debug build
    başarılı, paket `AppIcon.icns` + `CFBundleIconName` içeriyor)
  - [x] Prototipte üçüncü tur: köşeli ikon seti (Remix dilinde, pahlı köşeler; her ikonun
    çizgi ve oyulmuş dolu hali, değiştirici rozetler, sistem parantezi), uyarı lambası ve
    karosu, pahlı görev işaretleri; referans panolardan basılı bölgeler, ölçek sayıları,
    yükselen bant, radyo ölçeği, nokta matrisi, kapsüller, kapasite ölçeği, mod
    göstergesi, çerçeve ve onboarding sistem şeması. Her biri az yerde, mevcut bir satırın
    yerine. — ✅ 2026-11-17 (112 durum headless tarayıcıda hatasız; şema ve izin
    etkileşimi Playwright ile doğrulandı)
  - [x] Durum şekilleri: dikkat isteyen her durum renk dışında bir şekille de okunur
    (üçgen başarısız, elmas senden bekliyor, sekizgen izin kapalı, koşan hücreler
    çalışıyor, kum saati sırada, kare durduruldu); hata panellerinde ışıklı kuyuda büyük
    şekil. Etkinlik satırları ve kahramanda yalnızca başlangıç saati. — ✅ 2026-11-17
    (112 durum headless tarayıcıda hatasız; etkileşim testi geçti)
  - [x] Görev satırı eylemleri: tıklayınca satır kendi zeminiyle birlikte tek parça
    sola kayar ve sağ kenarına yapışık isimli durumlar · Edit · Delete içeri girer, fare çıkınca geri kayar; Edit kartı yalnızca içerik ve Done. Açık
    notch bandında sekmelerden önce işaret + "Crenel"; açık panel 560 pt. — ✅ 2026-11-17
    (açma, ayrılınca kapanma, durum seçme, Edit ve marka yerleşimi Playwright ile
    doğrulandı; 112 durum hatasız)
  - [x] Kullanıcının HTML prototipindeki (`docs/design/crenel-prototype.html`) son tasarımın
    ("gece sürüşü", `docs/DESIGN.md`) uygulamaya geçirilmesi. — ✅ 2026-11-17 (574 test, 5 atlandı, 0 hata; her yüzeyin
    durumları ekran dışı render edilip prototip görüntüleriyle karşılaştırıldı; canlı
    etkileşim ve animasyonlar gerçek ekranda kullanıcı kabulünü bekliyor)
    - [x] Temel: `Hud` token'ları, ikon ailesi (çizgi + dolu), lambalar, durum şekilleri,
      tuş butonlar, segment rakam, tik halkası ve diğer göstergeler. — ✅ 2026-11-17
      (`Features/Design/System/README.md` API başvurusu; `HudFoundationGalleryTests`
      render'ları prototip görüntüleriyle karşılaştırıldı; 521 test, 0 hata)
    - [x] Notch: üç boy (kompakt / şerit / açık 560), bant, hareket. İstemler, canlı dikte ve
      sonuçlar şerit olarak gösterilir; paneli kendiliğinden açmaz.
    - [x] Today, kayıt, işleme ve sonuç yüzeyleri.
    - [x] Kayıtlar ve toplantı detayı (gerçek ses dosyasından dalga formu, konuşma süresi).
    - [x] Görevler (satır eylemleri, Edit kartı).
    - [x] Masaüstü penceresi 1240×760 (Today panosu, Meetings, Tasks, Dictation).
    - [x] Ayarlar ve onboarding.
    - [x] Tasarımın istediği ama uygulamada verisi olmayan parçalar: toplantı katılımcıları
      ve davet eden, görevde bloke nedeni, dikte geri alma (Undo), sonuç şeridinde aksiyon
      sayısı, PDF/düz metin dışa aktarma, mikrofon seviye testi, "your usual" dikte düzeyi. — ✅ 2026-11-17
      (626 test, 5 atlandı, 0 hata; eski çıkarıcı notları yeniden yazım için işaretlenir; gerçek
      cihazda Undo, mikrofon testi ve PDF görünümü C8'de denenecek)

## 2026-09-25 — Koyu tema parlaklık düzeltmesi

- [x] Nötr yüzeyleri koyulaştırmak: arka plan #171717, sidebar #131313, kart #202020.

Doğrulama: 3 masaüstü testi ve imzalı Debug build başarılı; güncel ayar görseli incelendi.

## 2026-09-25 — Nötr renk düzeltmesi

- [x] Son turda eklenen mavi alt tonları kaldırmak; açık koyu yüzeyleri nötr griye ve ana eylemleri nötr renge çevirmek.

Doğrulama: 3 masaüstü testi geçti; imzalı Debug build başarılı. Ayar görselinde nötr yüzeyler kontrol edildi.

## 2026-09-25 — UX sadeleştirme ve yerleşim düzeltmeleri

- [x] Gereksiz açıklamaları kaldırmak; masaüstü paletini, ayar yapısını ve kompakt aksiyon listesini yenilemek.
- [x] Notch sekme/scroll titremesini ve masaüstü açılış/minimum boyutunu düzeltip doğrulamak.

Doğrulama: 333 test (3 opt-in atlandı), 0 hata; son 25 görsel UI testi ve yeni
sekme/scroll regresyon testi ayrıca geçti. Gerçek NSWindow 1120×680 açılış ve
960×540 küçültme doğrulandı. İmzalı Debug build başarılı. Fiziksel notch hareket
akıcılığı henüz canlı toplantıda doğrulanmadı. Ayrıntılar: `macos/QA/UI_POLISH_AUDIT.md`.

## 2026-09-25 — Arayüz ve etkileşim kalitesi

Notch’un kompakt/geniş tüm yaşam döngüsü durumları, masaüstü çalışma alanı,
toplantı detayı, görevler, ayarlar ve onboarding birlikte gözden geçirilir.
Mevcut siyah/nötr tasarım dili; tutarlı yüzey, tipografi, ikon, klavye odağı,
hover/basış geri bildirimi ve Reduce Motion uyumlu geçişlerle geliştirilir.

- [x] Ekran/durum envanteri ve görsel incelemeyi tamamlamak.
- [x] Ortak tasarım sistemi, notch ve masaüstü ekranlarındaki iyileştirmeleri uygulamak.
- [x] Görsel durum matrisi, erişilebilirlik ve build/test doğrulamasını tamamlamak.

Doğrulama: 333 test, 3 opt-in fiziksel ses testi atlandı, 0 hata. Son görsel
düzeltmelerden sonra 25 UI testi tekrar geçti; development imzalı Debug build başarılı.
59 ek durum görseli ve önce/sonra galerisi üretildi. Erişilebilirlik kontrolü kod/test
seviyesindedir; fiziksel VoiceOver, yeni build ile gerçek toplantı ve hareket akıcılığı
kapsamı ayrı kalır. Ayrıntılar: `macos/QA/UI_POLISH_AUDIT.md`.

## 2026-09-14 — Masaüstü çalışma alanı

Notch varsayılan açılış olarak kalır. Kullanıcı istediğinde ayrıca tek bir masaüstü
penceresi açar; toplantılar, görevler ve kategorili ayarlar aynı veri katmanını kullanır.
Pencereyi kapatmak uygulamayı veya kaydı sonlandırmaz.

- [x] Masaüstü pencere yaşam döngüsü, menü/yeniden açma ve ayar yönlendirmesi.
- [x] Aranabilir toplantı arşivi, detay, yaklaşan toplantılar ve görev çalışma alanı.
- [x] Kategorili ve kompakt ayarlar, görsel doğrulama ve regresyon testleri.

Doğrulama: 330 XCTest, 3 fiziksel ses testi opt-in nedeniyle atlandı, 0 hata.
Arama ve kapalı başlangıç/pencere yaşam döngüsü test edildi. Toplantı/görev yüzeyleri ve
beş ayar kategorisi sentetik verilerle render edilip incelendi; minimum pencere
genişliğinde yatay taşma testi geçti.

## 2026-09-14 — Hibrit ürünleştirme (güncel öncelik)

Kullanıcı araştırma önerisini uygulamayı onayladı. Bu bölüm eski tek-API/tek-key ve
extractive-only kararlarının yerine geçer; tarihsel checklist'ler geçmiş kanıtı korur.
ElevenLabs Scribe v2 ses/transkript/diarization için kalır. OpenAI, kullanıcının ayrı
Keychain anahtarı ve açık bağlantı aksiyonuyla metinden özet, karar ve kaynaklı görev üretir.
Eski kayıtlar korunur; özet tekrarında ses yeniden yüklenmez. Kişi eşleştirmesi kullanıcı
kontrolündedir; kanıtsız kişi/tarih atanmaz. OpenAI-only yol, karşılaştırmalı ses testi
sonrasına bırakılır. 41:57, 52:24, 56:43 kayıtlar kullanıcı tarafından gerçek kullanımda
bildirildi; fiziksel uzun kayıt kapsamı sıfırdan başlamıyor.

- [x] Takvim durumları, bağlantı rehberi, takvim seçimi ve macOS bildirim/katıl/ertele akışını tamamlamak.
- [x] Toplantı/mute arayüzünü ses süreçlerinden bağımsız yenilemek; kayıp sinyali fail-closed yapmak.
- [x] OpenAI Keychain bağlantısı, şemalı/kaynak doğrulamalı özet servisi ve kalıcı transkript checkpoint'i eklemek.
- [x] Kişi eşleştirme, kaynaklı/sorumlulu/tarihli görev aktarımı ve eski toplantıyı yeniden özetleme eklemek.
- [x] Hybrid onboarding, hata/kota açıklamaları, migration/regresyon testleri ve build doğrulamasını tamamlamak.
- [x] Doğrudan Google OAuth kodu: PKCE/state, loopback, token yenileme, sayfalama ve takvim seçimi; sentetik testlerle doğrulandı.
- [ ] Google publisher client ID, consent/verification ve gerçek hesap kabulünü tamamlamak.
- [ ] Gerçek Zoom/Meet uçtan uca ses ve API kalite testleri, Store yayını, Developer ID/notarization ve temiz hesap kabulünü tamamlamak.

Doğrulama: 327 XCTest, 3 fiziksel ses testi opt-in nedeniyle atlandı, 0 hata;
Chrome köprüsü 6/6 test ve paket doğrulaması başarılı. Apple Development imzalı Debug
build başarılı; sentetik Ayarlar ve toplantı detay render’ları incelendi. Gerçek API
çağrısı/kayıt kalite testi yapılmadı. Kurulum ve kalan fiziksel kabul: `macos/QA/HYBRID_SETUP.md`.

## Ürün özeti

Crenel, macOS notch çevresinde Dynamic Island benzeri çalışan hafif bir toplantı
kayıt uygulamasıdır. Takvim ve yerel macOS sinyalleriyle desteklenen toplantıyı algılar,
toplantının başladığını/bittiğini kullanıcıya görünür biçimde bildirir, yalnızca toplantıya
ait sesi kaydeder ve kaydı konuşmacı ayrımlı transkript ile kısa özete dönüştürür. Kullanıcı
geçmiş toplantılarına erişebilir ve notch içinden basit bir görev listesi yönetebilir.

Güncel sürüm ses için ElevenLabs Scribe v2, toplantı analizi için OpenAI kullanır.
Anahtarlar kullanıcıya aittir ve ayrı Keychain öğelerinde tutulur. Takvim varsayılan
olarak EventKit üzerinden bağlanır; yayıncı yapılandırmasıyla doğrudan Google OAuth
da desteklenir. Core Audio, AVFoundation ve Accessibility yerel macOS sınırlarıdır.

## V1 tamamlanma tanımı

V1 aşağıdakilerin tamamı gerçek bir macOS cihazında çalıştığında bitmiş sayılır:

- Notch veya notch olmayan Mac üzerinde uygulamanın temel paneli kullanılabilir.
- Arayüz kompakt, düşük görsel gürültülü ve toplantı durumunu tek bakışta anlatır.
- Kullanıcı gerekli izinleri anlayarak verebilir ve reddettiğinde uygulama bozulmaz.
- Kullanıcı manuel olarak toplantı kaydı başlatıp durdurabilir.
- Desteklenen toplantı istemcisinde toplantının başlangıç ve bitişi yerel sinyallerle
  algılanır; belirsiz durum kullanıcıya kesinmiş gibi sunulmaz.
- Desteklenen toplantı istemcisinin sistem sesi mümkün olduğunda yalnızca ilgili process
  üzerinden, mikrofon ise yalnızca toplantı mikrofonu açıkken kaydedilir.
- Toplantı mikrofon durumu bilinmiyorsa privacy-first davranışla mikrofon sesinin kalıcı
  kayda girmesi engellenir; kullanıcıya görünür durum ve güvenli manuel kontrol sunulur.
- Yaklaşan çevrim içi toplantılar takvimden algılanıp gösterilir.
- Kayıt tek uzak servis olan ElevenLabs Scribe v2 ile konuşmacı ayrımlı transkripte
  dönüştürülür ve yalnızca bir kullanıcı API anahtarı gerekir.
- Kullanıcı kısa özet, transkript ve kayıt dosyasına geçmiş ekranından ulaşabilir.
- Başarısız yükleme veya işleme işlemi veri kaybetmeden tekrar denenebilir.
- Aktif görevler eklenebilir, tamamlanabilir ve arşivlenebilir.
- Ayarlar, veri silme, gizlilik ve ElevenLabs API anahtarı yapılandırması kullanılabilir.
- Temel erişilebilirlik, hata senaryoları, uzun kayıt ve cihaz değişimi testleri geçer.
- İmzalanmış ve notarize edilmiş dağıtılabilir sürüm hazırlanır.

## 2026-07-25 V1 odak kararı

Bu bölüm tamamlanana kadar uygulama sırasının ana kaynağıdır. Eski fazlardaki tamamlanmış
maddeler korunur; aşağıdaki sıra, numaralı faz sırasından daha yüksek önceliklidir.

### Ürün sınırı

- **Tek bulut API:** ElevenLabs Scribe v2. UI'da provider seçici, OpenAI seçeneği veya
  gelecekteki provider vaadi gösterilmez.
- **Tek credential:** Bir ElevenLabs API key. Anahtar Keychain'de tutulur; dil ve saklama
  seçenekleri yerel tercihlerdir.
- **Toplantı-first:** Kayıt, toplantı algılama, güvenli ses kapsamı, transkript ve sonuç
  akışı release blocker'dır. Görevler çalışır halde korunur fakat yeni görev özelliği
  geliştirilmez.
- **Dar destek yüzeyi:** V1'in iki zorunlu kalite kapısı Zoom Workplace native istemcisi ve
  Google Meet/Chrome'dur. Her ikisi için başlangıç/bitiş algılama, mute durumu ve yalnızca
  toplantı sesini kapsayan privacy-first kayıt doğrulanır. Chrome'da toplantı sekmesi
  güvenle izole edilemiyorsa kayıt global sese sessizce düşmez; kullanıcıya açıkça gösterilen
  güvenli fallback uygulanır. Microsoft Teams ve diğer istemciler V1'i bloke etmez.
- **Gizli otomasyon yok:** Algılama kaydı kendiliğinden ve habersiz başlatmaz. Güçlü
  başlangıç sinyali notch üzerinde kayıt teklifini açar. Güçlü bitiş sinyali kayıt sırasında
  iptal edilebilir kısa geri sayım sonrası kaydı durdurabilir; sinyal belirsizse kullanıcıya
  sorulur.
- [x] Zoom Workplace ve Google Meet/Chrome'u başlangıç/bitiş algılama, mute gate, güvenli
  sistem sesi ve gerçek cihaz testleri bakımından eşit zorunlu V1 destek yüzeyi yapmak.
  — ✅ Tamamlandı: 2026-07-29 / V1 support scope

### Toplantı yaşam döngüsü sözleşmesi

Takvim zamanı tek başına gerçek toplantı başlangıcı veya bitişi sayılmaz. Yeni session
detector aşağıdaki bağımsız sinyalleri birleştirir:

1. EventKit etkinliği ve toplantı URL'si yalnızca planlanmış bağlamı verir.
2. Tanınan meeting process'inin açılması ve Core Audio `isRunningInput` /
   `isRunningOutput` durumu gerçek istemci aktivitesine aday sinyal verir.
3. İstemci adaptörünün Accessibility ağacında meeting window/call controls bulması güçlü
   katılım sinyalidir.
4. Kullanıcının Crenel içindeki `Katıl` aksiyonu toplantı URL'si ile process/window
   ilişkilendirmesini güçlendirir.
5. Meeting UI'ın kaybolması, ilgili process audio IO'nun durması ve takvim bağlamı birlikte
   bitiş güvenini yükseltir. Yalnızca sessizlik bitiş sayılmaz.

Domain durumları `scheduled → candidate → ready → recording → endSuspected → ended`
olarak modellenir. Her snapshot `confidence`, `evidence`, `clientID`, `processID`,
`calendarMeetingID` ve son değişim zamanını taşır. UI yalnızca `confirmed` durumda
“Toplantı başladı/bitti” der; daha düşük güven “Toplantı olabilir” olarak gösterilir.

### Mikrofon gizlilik sözleşmesi

- `isRunningInput`, toplantı process'inin bir input stream kullandığını gösterir; toplantı
  uygulamasındaki mute düğmesinin kesin durumu değildir ve tek başına mikrofon gate'ini
  açamaz.
- Desteklenen istemci adaptörü mute/unmute durumunu erişilebilir call control durumundan
  çıkarır. Adapter sonucu `open`, `closed` veya `unknown` olur.
- `closed` ve `unknown` durumlarında mikrofon sample'ları dosyaya yazılmadan önce sıfırlanır;
  timeline korunur fakat kullanıcının ortam konuşması kalıcı sese girmez.
- `open` yalnızca doğrulanmış unmute sinyali veya kullanıcının görünür manuel “Toplantı
  mikrofonu açık” kontrolüyle oluşur. Voice activity detection kullanıcının niyetini
  tahmin etmek için kullanılmaz.
- Her gate geçişi kayıt metadata'sına timestamp ve kaynakla yazılır; ham konuşma veya UI
  metni loglanmaz.
- Manuel fallback global shortcut ve notch kontrolüyle çalışır, kayıt boyunca görünürdür ve
  yeni oturumda varsayılan olarak kapalı başlar. (2026-11-20: C12 kararıyla varsayılan açık.)
- Privacy kabul testi, mute iken söylenen benzersiz test cümlesinin ne ham mikrofon
  parçasında ne birleşik M4A'da ne de transkriptte bulunmadığını doğrular.

### Minimal/techy UI yönü

- Ana toplantı/görev paneli ve uzun transkript taşıyan notch içi detay ekran alanı uygunsa
  sabit 600 px olur; ana panelde dış yatay padding 12 px, bölüm aralığı 20 px, içerik aralığı
  12 px, satır aralığı 4 px ve corner radius hiyerarşisi 24/22/16 px olur. Hover yüzeyli
  toplantı/görev satırlarının iç yatay padding'i 8 px olur. Kompaktlık
  içerik alanını daraltmak değil,
  gereksiz yüzey/padding kaybını azaltmaktır.
- Ana panelin görsel ikonları 20 px grid'e oturur; tıklama hedefleri macOS için genişletilir.
  Küçük görünmek, küçük veya erişilemez hit target anlamına gelmez.
- Nötr siyah/gri yüzey, tek hairline border ve yalnızca durum renginde vurgu kullanılır.
  Dekoratif gradient, büyük gölge ve iç içe kartlar kaldırılır.
- Bölüm başlıkları 20 pt medium, satır başlıkları 14 pt medium, ikincil metin 14 pt regular,
  kompakt kayıt/görev sayaçları 12 pt olur; süre ve sayaçlar monospaced digit kullanır.
- Kompakt notch yalnızca durum glyph'i, canlı süre ve mikrofon gate durumunu taşır.
- Geniş panelin ilk satırı toplantı yaşam döngüsüdür: istemci + güven durumu, kayıt süresi,
  meeting mic `Açık/Kapalı/Bilinmiyor`; ana aksiyon tek ve nettir.
- Provider seçici kaldırılır. Ayarlar; `ElevenLabs API Key`, transkript dili, toplantı
  algılama/Accessibility, mikrofon, takvim, saklama ve başlangıç tercihlerinden oluşur.
- Görevler ikincil sekme olarak kalır; toplantı akışından daha yüksek görsel ağırlık taşımaz.

### Uygulama sırası ve kalite kapıları

#### A — Baseline ve tek API sadeleştirmesi

- [x] Mevcut tüm birim testlerini ve imzalı Debug build'i güncel toolchain'de baseline
  olarak çalıştırmak.
- [x] UI'dan provider seçimini ve OpenAI “yakında” yüzeyini kaldırmak.
- [x] `TranscriptionProviderID`/resolver kullanımını ürün modelinden çıkarmak; yalnızca eski
  ayar ve queue belgelerini ElevenLabs'e migrate etmek için dar uyumluluk kodu bırakmak.
- [x] Tek ElevenLabs Keychain kaydı için eski provider-scoped anahtarı kayıpsız migrate
  etmek; doğrula, değiştir ve bağlantıyı kaldır akışlarını test etmek.
- [x] Processing worker'a tek `TranscriptionServicing` bağımlılığı enjekte etmek; protokolü
  çoklu provider özelliği için değil test doubles için korumak.

**A çıkış kriteri:** Uygulamada tek API adı ve tek anahtar vardır; eski kullanıcı verisi
açılır; fixture testleri, queue recovery ve gerçek anahtar doğrulama akışı bozulmaz.

#### B — Toplantı session detector

- [x] `MeetingSession`, `MeetingClientID`, `MeetingEvidence`, `DetectionConfidence` ve
  yaşam döngüsü state machine'ini UI ve EventKit'ten bağımsız oluşturmak.
- [x] Core Audio process listesini bundle ID/PID ile izleyen, input/output IO değişikliklerini
  yayınlayan `AudioProcessMonitor` prototipini yapmak.
- [x] Zoom ve Google Meet/Chrome için process, meeting window/tab ve call controls algılayan
  yerel adaptör prototipleri yapmak; Accessibility izni yok/reddedilmiş davranışı tasarlamak.
  — ✅ Tamamlandı: 2026-07-29 / Zoom + Google Meet Accessibility adapters
- [x] Takvim, `Katıl` aksiyonu, process audio ve client adapter sinyallerini deterministic
  confidence kurallarıyla birleştirmek.
  — ✅ Tamamlandı: 2026-08-11 / deterministic session coordinator
- [x] Güçlü başlangıçta kayıt teklifini; güçlü bitişte iptal edilebilir auto-stop geri
  sayımını; belirsiz bitişte manuel onayı uygulamak.
  — ✅ Tamamlandı: 2026-08-11 / lifecycle prompts and safe auto-stop
- [x] Planlanmamış toplantı, geciken toplantı, erken katılma, ara verme, sessizlik,
  uygulamanın açık kalması ve arka arkaya çağrı senaryolarını fixture testleriyle kapsamak.
  — ✅ Tamamlandı: 2026-08-11 / session lifecycle fixture matrix

**B çıkış kriteri:** Zoom ve Google Meet/Chrome gerçek cihaz testlerinde başlangıç ve
hang-up ayrı ayrı beşer ardışık koşuda doğru algılanır; yalnız sessizlik yanlış bitiş
üretmez; izin yokken manuel kayıt çalışır.

— 🧪 Fiziksel kanıt hattı hazır: 2026-08-11 / privacy-safe OSLog collector + 4/4 Swift ve
CLI pass/fail session auditor; istemci/senaryo başına gerçek 5× koşular bekliyor
— ⛔ Bloke: Kullanıcı kontrollü sentetik Zoom/Meet görüşmeleri ve `macos/QA/Evidence` fiziksel
kanıtları yok; uygulama görüşmeye veya kullanıcı hesabına kendiliğinden katılamaz

#### C — Privacy-first toplantı sesi

- [x] Global system tap yerine belirlenen meeting process'lerini içeren private Core Audio
  process tap oluşturmak; Crenel ve toplantı dışı uygulama sesini dışarıda bırakmak.
  — ✅ Tamamlandı: 2026-08-11 / private meeting-process tap and fail-closed scope
- [x] `MeetingMicrophoneGate` state machine ve timestamp'li gate event modelini oluşturmak.
  — ✅ Tamamlandı: 2026-08-11 / fail-closed microphone gate domain
- [x] Zoom ve Google Meet/Chrome mute control adaptörlerini `open/closed/unknown` üretecek
  şekilde bağlamak.
  — ✅ Tamamlandı: 2026-08-11 / live adapter-to-recording gate bridge
- [x] Mikrofon writer'ında `closed/unknown` sample'larını encode öncesi sıfırlamak, gate
  değişiminde click üretmeyen kısa fade uygulamak ve ortak timeline'ı korumak.
  — ✅ Tamamlandı: 2026-08-11 / zero-fill PCM gate with boundary fades
- [x] Görünür notch toggle + global shortcut fallback'i eklemek; her kayıtta kapalı başlatmak.
  — ✅ Tamamlandı: 2026-08-11 / visible gate control and ⌥⌘M hotkey
- [ ] Ham mic, system track, birleşik M4A ve transkript üzerinde unique-phrase privacy
  testini; hızlı mute/unmute, kulaklık ve cihaz değişimi senaryolarını çalıştırmak.
  — ⛔ Bloke: Otomasyon hazır; gerçek cihazda kullanıcının sesli canary onayı, kulaklık ve
  cihaz değişimi koşusu bekliyor
- [x] Meeting process'i değişir veya adapter kaybolursa gate'i fail-closed yapmak ve
  kullanıcıya anında görünür uyarı vermek.
  — ✅ Tamamlandı: 2026-08-11 / fail-closed runtime interruption warning

**C çıkış kriteri:** Mute/unknown aralıklarında kullanıcı sesi hiçbir kalıcı çıktıya girmez;
unmute aralıkları anlaşılırdır; toplantı dışı uygulama sesi process-scope testinde yoktur.

#### D — Minimal UI dönüşümü

- [x] Fiziksel notch/floating panel appearance regresyonunu gidermek; aktif ve pasif
  sekmeleri her görünümde okunur tutmak, ana yüzeylerin kontrast/hiyerarşi/hover-focus
  durumlarını yeniden cilalamak ve görsel sözleşme testleriyle korumak.
  — ✅ Tamamlandı: 2026-08-11 / physical-notch appearance and stable tab layout
- [x] Renk, tipografi, spacing, radius, icon ve control-size token'larını tek theme dosyasında
  tanımlamak.
- [x] Kompakt notch'u session/gate/kayıt süresi etrafında yeniden tasarlamak.
  — ✅ Tamamlandı: 2026-08-11 / session client, live duration and microphone gate
- [x] Geniş paneli tek ana status surface + ince geçmiş listesi olarak yeniden tasarlamak;
  gereksiz kart, gölge ve büyük ikonları kaldırmak.
- [x] Settings ve onboarding'i tek API ve yeni Accessibility/mute sınırlarıyla yenilemek.
  — ✅ Tamamlandı: 2026-08-11 / single ElevenLabs boundary and Accessibility consent
- [x] Toplantı detayını daha yoğun header, sade playback bar ve okunaklı transcript düzenine
  geçirmek; detay, ayrı pencere yerine notch içi drill-down olarak açılmalı ve düz metin /
  Markdown kopyalama aksiyonları ilk satırdan erişilebilir olmalı.
- [x] Koyu/açık, Increase Contrast, Reduce Motion, klavye ve VoiceOver durumlarını snapshot
  veya preview matrisiyle doğrulamak.
  — ✅ Tamamlandı: 2026-08-11 / six-state preview and accessibility contract matrix

- [x] Ana panel ve toplantı detayını ekran uygunsa değişmeyen 600 px genişlikte taşıyan
  layout'u; 12 px yatay dış padding ve 20 px dikey bölüm ritmiyle uygulamak.
  — ✅ Tamamlandı: 2026-07-29 / precision UI polish
- [x] Notch içindeki başlıkları sans, metadata/süre/sayaçları mono rollerine ayırmak;
  recent ve detail satırlarında optik ikon-metin hizasını düzeltmek.
  — ✅ Tamamlandı: 2026-07-29 / precision UI polish
- [x] Görevler sekmesini aynı yüzey/type token'larıyla yeniden tasarlamak; satır içi kalıcı
  silme ikonlarını kaldırıp destructive aksiyonları context menu + onaya taşımak.
  — ✅ Tamamlandı: 2026-07-29 / precision UI polish
- [x] Figma `18:2785` içindeki Meetings, boş toplantı, aktif kayıt ve Tasks frame'lerini;
  600 px ana panel, SF Pro Display rolleri, özgün durum renkleri, 20/12/10/4 px spacing
  ritmi, 20 px ikon grid'i ve 24/22/16 px radius hiyerarşisiyle SwiftUI'a taşımak.
  — ✅ Tamamlandı: 2026-08-19 / Figma ana panel uygulaması
- [x] Ana panel içeriğini 600 px üst sınıra kadar doğal yüksekliğinde göstermek; yalnızca
  içerik bu sınırı aştığında kaydırmayı etkinleştirmek.
  — ✅ Tamamlandı: 2026-08-19 / fit-content panel yüksekliği
- [x] Uzun meeting detail içeriğinde üst başlığın güvenli alanda kalmasını ve son
  “Diğer işlemler” satırının scroll ile bütünüyle görünmesini sağlamak.
  — ✅ Tamamlandı: 2026-08-19 / host viewport + detail scroll sonu payı
- [x] Tüm notch ekranlarını sabit 600 px genişlikte tutmak; panel yatay padding'ini 12 px'e
  indirip hover yüzeyli toplantı/görev satırlarına 8 px iç yatay padding vermek.
  — ✅ Tamamlandı: 2026-08-19 / sabit genişlik ve liste hover padding'i

**D çıkış kriteri:** Tüm ana durumlar aynı token setini kullanır; ana panel ve detail ekran
uygunsa sabit 600 px genişlikte taşmadan çalışır; 20 px görsel ikonlar kullanılırken
kontroller klavye ve VoiceOver ile kullanılabilir kalır.

#### E — Çalışan V1 ve release hardening

- [ ] Zoom ve Google Meet/Chrome'da ayrı ayrı 60+ dakikalık toplantıda güvenli kapsamlı
  system audio, gated mic, finalize, ElevenLabs upload, diarization, özet ve detay akışını
  uçtan uca tamamlamak.
  — ⛔ Bloke: `macos/QA/V1_RELEASE_RUNBOOK.md` hazır; kullanıcı kontrollü iki fiziksel 65 dk
  görüşme ve test ElevenLabs anahtarı bekliyor
- [ ] İnternet kesintisi, 401/429/5xx, disk dolması, force quit, sleep/wake ve audio device
  değişimi recovery matrisini geçirmek.
  — ⛔ Bloke: Automation 102/102 + canary/session CLI + 3/3 physical audio smoke geçti;
  ağ/uyku/force-quit ve disposable volume testleri için kullanıcı onayı bekleniyor
- [ ] Google Meet/Chrome'da toplantı sekmesi dışındaki tarayıcı sesinin kalıcı sistem
  kaydına veya transkripte girmediğini canary-audio privacy testiyle doğrulamak; izolasyon
  kaybolduğunda kaydı fail-closed duruma geçirmek ve görünür güvenli fallback sunmak.
  — ⛔ Bloke: MV3/native bridge hazır; gerçek Meet görüşmesi ve ikinci sekme sesli canary
  koşusu kullanıcı etkileşimi bekliyor
  - [ ] Kullanıcının extension action tıklamasıyla yalnız aktif `meet.google.com` sekmesini
    alan MV3 `tabCapture` + offscreen audio katmanını uygulamak; tab sesini kullanıcıya geri
    oynatmak ve başka origin/tab için fail-closed davranmak.
    — ⛔ Bloke: static+protocol+consent 6/6; gerçek Chrome/Meet tab koşusu bekliyor
  - [x] Sabit extension origin allowlist'i, session nonce, sequence/backpressure ve PCM
    doğrulaması olan native messaging helper + uygulama IPC köprüsünü uygulamak.
    — ✅ Tamamlandı: 2026-08-11 / embedded host + user-scoped IPC + M4A source; 9/9
  - [ ] Extension kurulum/onboarding, canlı bağlantı durumu, kopmada görünür güvenli durdurma
    ve Chrome Web Store dağıtım yolunu tamamlamak.
    — ⛔ Bloke: disclosure popup, onboarding/status ve Store ZIP/metin/varlık hazır;
    publisher hesabı, dashboard ID, public HTTPS policy/support bilgileri ve review bekliyor
  - [ ] Toplantı sekmesi + ikinci Chrome sekmesi canary-audio koşusunu ham system, final M4A
    ve transkriptte fiziksel olarak doğrulamak.
    — ⛔ Bloke: Swift 4/4 + CLI auditor hazır; fiziksel iki sekmeli koşu bekliyor
- [ ] İmzalı/notarize release candidate'ı temiz kullanıcı hesabında notch ve harici ekranda
  doğrulamak.
  — ⛔ Bloke: RC script + evidence template hazır; Keychain'de Developer ID Application
  sertifikası ve `Crenel-Notary` profili yok, temiz hesap fiziksel testi bekliyor

**E çıkış kriteri:** İlk kurulumdan sonuç ekranına gerçek toplantı akışı veri sızıntısı
olmadan tamamlanır ve V1 tamamlanma tanımındaki bütün maddeler geçer.

## Faz 0 — Temel ürün tanımı ve proje hazırlığı

### 0.1 Mevcut başlangıç noktası

- [x] Ürünün ana fikrini ve v1 kapsamını `project-overview.md` içinde belgelemek.
- [x] Temel macOS Xcode projesini oluşturmak.
- [x] Bu dosyayı geliştirme boyunca tek ana ilerleme planı olarak benimsemek.
- [x] `ARCHITECTURE.md` oluşturup mevcut ürün belgelerinden türetilen uygulama katmanlarını
  ve bağımlılık kurallarını belgelemek.
- [x] `macos/project.yml` dosyasını Xcode projesinin tek yapılandırma kaynağı yapmak ve
  `project.pbxproj` dosyasını yalnızca XcodeGen ile üretmek.
- [x] `README.md` oluşturup ürün özeti, geliştirme gereksinimleri ve plan bağlantısını eklemek.
- [x] Kaynak kontrolüne girmemesi gereken kullanıcı/Xcode dosyaları için `.gitignore` hazırlamak.
- [x] Debug ve Release yapılandırmalarının temel farklarını belirlemek.
- [x] Uygulamanın görünen adı, bundle identifier ve sürümleme yaklaşımını kesinleştirmek.

### 0.2 V1 ürün kararları

> [!IMPORTANT]
> Bu bölüm 2026-07-25 tarihli ürün sadeleştirmesi kapsamında güncellenmiştir.

- [x] V1'i tek transkripsiyon servisi, güvenli toplantı yaşam döngüsü ve privacy-first
  mikrofon geçitleme etrafında yeniden planlamak; kalan işleri çalışan ürün önceliğine göre
  sıralamak.

V1 için birincil akış şöyledir: kullanıcı ilk açılışta ürünün kayıt ve bulut işleme
sınırlarını görür; mikrofon ve sistem sesi izinlerini bağlam içinde, isteğe bağlı takvim
iznini bunların ardından verir. Panelden yaklaşan toplantıyı açar veya her zaman erişilebilir
manuel kaydı başlatır, görünür kayıt göstergesi üzerinden kaydı durdurur ve yerel ses
güvenceye alındıktan sonra arka plandaki transkripsiyon sonucuna geçmişten ulaşır. İzin ya
da ağ hatası bu akışı kilitlemez; kullanıcı ayarı düzeltebilir veya kaybolmayan kayıt için
tekrar deneyebilir.

Tamamlanan işlem notch üzerinde 8 saniye gösterilir; kullanıcı etkileşimi yoksa panel
kompakt duruma döner. Geçmiş kaydı kararlı kimlik, başlık, başlangıç/bitiş ve süre, kaynak
takvim kimliği ve toplantı URL'si, işlem/provider durumu ve normalize hata kodu, birleşik
M4A dosya adı, konuşmacı-zaman damgalı transkript, genel özet, kararlar ve aksiyon
maddeleriyle saklanır. Şema sürümü bütün kalıcı belgelerde bulunur.

V1 arayüz dili Türkçedir. Transkript dili otomatik algılama, Türkçe veya İngilizce olarak
seçilebilir; arayüz lokalizasyonu ile transkript dili birbirinden bağımsızdır. Özet; kısa
genel özet, açıkça ifade edilen kararlar ve varsa sorumlu/tarih bilgili aksiyon maddelerinden
oluşur, belirsiz bilgi uydurulmaz.

Birleşik M4A kayıt toplantı verisinin parçasıdır ve varsayılan olarak süresiz saklanır;
kullanıcı tüm toplantı verileri için 7, 30 veya 90 günlük otomatik silme seçebilir. Ayrı
mikrofon/sistem ham parçaları başarılı işlemeden sonra silinir, hata veya kurtarma halinde
yeniden işleme için korunur. V1, sandbox gerektirmeyen ses yakalama yolundan ötürü Developer
ID ile imzalanıp notarize edilen doğrudan dağıtımı hedefler; Mac App Store bu sürümün dağıtım
kanalı değildir.

- [x] Birincil kullanıcı akışını yazmak: ilk açılış → izinler → toplantı → kayıt → sonuç.
- [x] Meeting kaydını ürünün ana modülü, görevleri ikincil araç olarak konumlandırmak.
- [x] Manuel kayıt başlatmanın her durumda erişilebilir olacağını kesinleştirmek.
- [x] Takvimden otomatik kayıt yerine 10 dakika ve 1 dakika kala notch hatırlatmaları
  kullanılacağını kararlaştırmak.
- [x] Kayıt sırasında minimum notch üzerinde kayıt göstergesi ve canlı süre gösterileceğini
  kesinleştirmek.
- [x] Tamamlanan toplantının kullanıcıya ne kadar süre gösterileceğini belirlemek.
- [x] Geçmiş toplantılarda saklanacak alanları belirlemek.
- [x] Kısa özetin kapsamını belirlemek: genel özet, kararlar ve aksiyon maddeleri.
- [x] V1'in destekleyeceği dilleri belirlemek; arayüz ve transkript dili kararlarını ayırmak.
- [x] Ham sesin varsayılan saklama ve otomatik silme politikasını belirlemek.
- [x] Ana dağıtım kanalını kesinleştirmek: doğrudan dağıtım veya Mac App Store.
- [x] V1 uzak servis sınırını yalnızca ElevenLabs Scribe v2 ve tek kullanıcı API anahtarı
  olarak kesinleştirmek.
- [x] Toplantı algılama ile otomatik/gizli kayıt başlatmayı ayırmak; başlangıçta görünür
  teklif, güçlü bitişte iptal edilebilir auto-stop yaklaşımını kesinleştirmek.
- [x] Mute durumu bilinmediğinde mikrofonu fail-closed tutan privacy sözleşmesini
  kesinleştirmek.

### 0.3 Teknik risk prototipleri

- [x] Notch penceresinin farklı Mac modellerinde açılma/kapanma prototipini yapmak.
- [x] Notch bulunmayan cihaz için floating panel davranışını doğrulamak.
- [x] Mikrofon kaydını bağımsız bir teknik prototiple doğrulamak.
- [x] Sistem sesi kaydını bağımsız bir teknik prototiple doğrulamak.
- [ ] Mikrofon ve sistem sesinin 30–60 dakikalık eş zamanlı kaydını test etmek.
- [ ] Hoparlör, kablolu kulaklık ve Bluetooth kulaklık senaryolarını karşılaştırmak.
- [ ] Ses cihazı toplantı sırasında değiştiğinde uygulanacak davranışı belirlemek.
- [ ] Sandbox açık ve kapalı yapılandırmalarda gerekli özellikleri deneyerek dağıtım
  kararını doğrulamak.
- [ ] En az bir transkripsiyon provider'ına örnek kayıt yükleyip Türkçe/İngilizce
  diarization kalitesini değerlendirmek.

### Faz 0 çıkış kriterleri

- [ ] Kritik ürün kararları belgelenmiş.
- [ ] Ses yakalama ve notch UI için uygulanabilir teknik yol doğrulanmış.
- [ ] Dağıtım ve sandbox stratejisi kararlaştırılmış.
- [ ] V1 kapsamını engelleyen bilinmeyen teknik risk kalmamış.

## Faz 1 — Uygulama temeli ve mimari iskelet

### 1.1 Uygulama yaşam döngüsü

- [x] Standart `WindowGroup` başlangıcını menü çubuğu/agent uygulaması yapısına dönüştürmek.
- [x] Dock ikonunun gösterilip gösterilmeyeceğini ürün kararına göre yapılandırmak.
- [x] Menü çubuğu ikonunu ve temel menüyü eklemek.
- [x] Menüye `Crenel'u Aç`, `Kaydı Başlat`, `Ayarlar` ve `Çıkış` aksiyonlarını eklemek.
- [x] Kayıt devam ederken çıkış davranışını güvenli şekilde ele almak.
- [x] Uygulamanın login sırasında otomatik açılma seçeneği için altyapı hazırlamak.
- [x] Tek uygulama instance'ı ve temel app coordinator yapısını oluşturmak.

### 1.2 Katmanlar ve modeller

- [x] Toplantı domain modelini oluşturmak.
- [x] Kayıt oturumu domain modelini oluşturmak.
- [x] Transcript, konuşmacı segmenti, özet ve aksiyon maddesi modellerini oluşturmak.
- [x] Görev ve arşivlenmiş görev modellerini oluşturmak.
- [x] Provider ayarları ve uygulama tercihleri modellerini oluşturmak.
- [x] UI, domain servisleri ve dosya erişimi sorumluluklarını ayırmak.
- [x] Ana uygulama state'ini tek bir gözlemlenebilir store/coordinator altında toplamak.
- [x] Uzun süren işleri Swift concurrency ile iptal edilebilir şekilde modellemek.

### 1.3 Durum makinesi

- [x] Toplantı/kayıt akışının tüm durumlarını enum veya eşdeğer domain modeliyle tanımlamak.
- [x] Boşta durumunu uygulamak.
- [x] Yaklaşan toplantı durumunu uygulamak.
- [x] İzin/kayıt hazırlama durumunu uygulamak.
- [x] Kayıt durumunu uygulamak.
- [x] Ses dosyasını sonlandırma durumunu uygulamak.
- [x] Yükleme ve transkripsiyon durumlarını uygulamak.
- [x] Tamamlandı durumunu uygulamak.
- [x] İptal ve tekrar denenebilir hata durumlarını uygulamak.
- [x] Geçersiz durum geçişlerini engelleyen testler yazmak.

### 1.4 Uygulama içi hata sistemi

- [x] Kullanıcıya gösterilecek hata modeli oluşturmak.
- [x] İzin, kayıt, dosya, ağ, provider ve veri çözümleme hatalarını sınıflandırmak.
- [x] Tekrar denenebilir ve kalıcı hataları ayırmak.
- [x] Hata mesajlarında uygulanabilir kullanıcı aksiyonu göstermek.
- [x] Hassas veri içermeyen debug log sistemi oluşturmak.

### Faz 1 çıkış kriterleri

- [ ] Uygulama agent/menu bar olarak açılıyor ve güvenli kapanıyor.
- [x] Domain modelleri ve durum makinesi UI'dan bağımsız test edilebiliyor.
- [ ] Boş mock servislerle tüm ana durumlar simüle edilebiliyor.

## Faz 2 — Notch ve Dynamic Island deneyimi

### 2.1 Notch konteyneri

- [x] Seçilen notch UI çözümünü projeye entegre etmek.
- [x] DynamicNotchKit paket çözümlemesini temiz checkout, Xcode IDE oturumu, test ve Debug
  build ile doğrulamak.
- [x] Fiziksel notch ölçülerini ve aktif ekranı algılamak.
- [x] Notch olmayan Mac'lerde floating panel fallback'i uygulamak.
- [x] Çoklu ekran kullanımında panelin hangi ekranda açılacağını belirlemek.
- [x] Hover ile açılma ve gecikmeli kapanma davranışını uygulamak.
- [x] Panel içindeyken yanlışlıkla kapanmayı engellemek.
- [x] Tıklayarak sabitleme veya açık tutma ihtiyacını ürün kararına göre uygulamak.
- [ ] Tam ekran uygulamalar ve farklı Space'lerde pencere davranışını test etmek.

### 2.2 Kompakt durum görünümü

- [x] Boşta kompakt görünümü meeting-first olacak şekilde tasarlamak ve uygulamak.
- [x] Görev bilgisini yalnızca ikincil Görevler sekmesinde göstermek.
- [x] Yaklaşan toplantı göstergesini kompakt notch üzerinde göstermek.
- [x] Kayıt durumunda canlı süre ve kırmızı kayıt göstergesi sunmak.
- [x] İşleme/yükleme durumunda ilerleme göstermek.
- [x] Tamamlandı veya hata durumunu kısa süreli göstermek.
- [x] Durum önceliklendirme kurallarını test etmek.

### 2.3 Genişletilmiş panel

- [x] Toplantılar ve Görevler sekmeleri arasında geçişi uygulamak.
- [x] Sekmeleri görünür ve anlaşılır kılan, meeting-first görsel hiyerarşiye sahip panel
  arayüzünü uygulamak.
- [x] Klavye ile sekme geçişini desteklemek.
- [x] Panel boyutlarını içerik ve ekran alanına göre sınırlandırmak.
- [x] Açılma, kapanma ve durum değişimi animasyonlarını uygulamak.
- [x] Animasyon azaltma erişilebilirlik ayarına uymak.
- [x] Açık/koyu tema ve yüksek kontrast görünümünü doğrulamak.
- [x] Mock verilerle tüm notch durumlarının preview'larını hazırlamak.

### 2.4 Minimal/techy görsel sistem dönüşümü

- [x] Ortak Figma UI token setini tanımlamak: siyah tuval, `#121212` yüzey, durum renkleri,
  12–20 pt type scale, 20/12/10/4 px spacing, 24/22/16 px radius ve en az 40 px control
  target.
- [x] 42 px ikon ağırlıklı sekme/pin kontrollerini daha küçük glyph ve yoğun macOS
  kontrollerine dönüştürmek.
- [x] İç içe kartları, dekoratif büyük gölgeleri ve yinelenen başlıkları kaldırmak.
- [ ] Kompakt notch'a meeting detection confidence ve mic gate durumunu eklemek.
- [x] Geniş paneli ve toplantı detayını sabit 600 px hedef genişlikte toplantı yaşam
  döngüsü merkezli ve ekran alanına göre akışkan yenilemek.
- [x] Ayarlar, onboarding, meeting detail, görev alt durumları, Chrome popup ve kalan
  compact/notch durum yüzeylerini aynı Figma token ve ikon sistemine taşımak.

### Faz 2 çıkış kriterleri

- [ ] Notch paneli desteklenen cihazlarda kararlı çalışıyor.
- [ ] Notch olmayan cihazda temel ürün tamamen kullanılabiliyor.
- [ ] Tüm durumlar kompakt ve genişletilmiş görünümde anlaşılır.

## Faz 3 — Onboarding, izinler ve ayarlar

### 3.1 İlk açılış deneyimi

- [x] Kısa ürün tanıtım ekranını hazırlamak.
- [x] Mikrofon izninin neden gerektiğini açıklamak.
- [x] Sistem sesi yakalama izninin neden gerektiğini açıklamak.
- [x] Takvim izninin isteğe bağlı faydasını açıklamak.
- [x] Bulut transkripsiyonunda sesin üçüncü taraf servise yükleneceğini açıklamak.
- [x] İzinleri bağlam içinde ve sırayla istemek.
- [x] Kullanıcı takvim iznini reddetse bile manuel kayıtla devam edebilmek.
- [x] Onboarding tamamlandı durumunu saklamak.

### 3.2 İzin yönetimi

- [x] Mikrofon yetki durumunu okumak ve değişiklikleri UI'a yansıtmak.
- [x] Sistem sesi yakalama yetki durumunu yönetmek.
- [x] Takvim full-access yetki durumunu yönetmek.
- [x] Gerekli Info.plist açıklamalarını eklemek.
- [x] Gerekli entitlement'ları dağıtım stratejisine göre eklemek.
- [x] Reddedilen veya sonradan kaldırılan izin için Sistem Ayarları bağlantısı sunmak.
- [x] Kayıt öncesi gerekli izinleri tekrar doğrulamak.
- [x] Sistem sesi izni sonrası yeniden başlatmanın çalışan güncel build'i açmasını ve
  audio-only capture akışını screen-capture preflight bağımlılığından çıkarmak.
- [x] Sistem sesi `İzin Ver` aksiyonunun gerçek Process Tap TCC isteğini tetiklemesini ve
  development build'inin Sistem Sesini Kaydetme listesine otomatik eklenmesini sağlamak.

### 3.3 Ayarlar ekranı

- [x] Genel ayarlar bölümünü oluşturmak.
- [x] Seçili mikrofon ayarını eklemek.
- [x] Transkripsiyon provider seçimini eklemek. 2026-07-25 ürünü sadeleştirme kararıyla bu
  yüzey kaldırılacak; tamamlanmış madde yalnızca geçmiş uygulama durumunu belgeler.
- [x] Provider API anahtarı girişini ve doğrulamasını eklemek.
- [x] Transkript dili otomatik algılama/sabit dil seçimini eklemek.
- [x] Toplantı öncesi hatırlatma süresi ayarını eklemek.
- [x] Takvim entegrasyonunu açma/kapatma seçeneğini eklemek.
- [x] Otomatik açılış seçeneğini eklemek.
- [x] Kayıt ve transkript saklama seçeneklerini eklemek.
- [x] Veri klasörünü Finder'da açma aksiyonu eklemek.
- [x] Tüm verileri silme aksiyonunu onay diyaloğuyla eklemek.
- [x] Onboarding'i yeniden gösterme aksiyonu eklemek.
- [ ] Provider picker'ı kaldırıp tek `ElevenLabs API Key` bağlantı yüzeyini uygulamak.
- [ ] Accessibility iznini toplantı/mute algılama faydası, reddetme sonucu ve manuel
  fallback ile bağlam içinde açıklamak.

### Faz 3 çıkış kriterleri

- [ ] Yeni kullanıcı izinleri anlayarak tamamlayabiliyor.
- [ ] İzin reddi uygulamayı kullanılamaz veya kilitli bırakmıyor.
- [ ] Tüm temel tercihler ayarlardan değiştirilebiliyor.

## Faz 4 — Yerel depolama ve veri güvenliği

### 4.1 Dosya düzeni

- [x] Application Support altındaki uygulama klasörünü güvenli şekilde oluşturmak.
- [x] Meetings, Tasks, Temporary ve Recovery klasörlerini tanımlamak.
- [x] Çakışmayacak ve okunabilir meeting dosya adı standardı belirlemek.
- [x] Her toplantı için metadata dosyası formatı belirlemek.
- [x] Şema sürümü ekleyerek ileride migration yapılabilmesini sağlamak.
- [x] Dosya adlarında geçersiz karakterleri ve çok uzun başlıkları ele almak.

### 4.2 Repository katmanı

- [x] Meeting repository oluşturmak.
- [x] Task repository oluşturmak.
- [x] App settings repository oluşturmak.
- [x] Tüm dosya yazımlarını atomik yapmak.
- [x] Bozuk veya yarım dosyaları güvenli şekilde ele almak.
- [x] Harici dosya değişikliği desteklenmeyecekse bunu belgelemek; desteklenecekse reload
  davranışını uygulamak.
- [x] Aynı anda gelen yazma işlemlerini serialize etmek.
- [x] Repository birim testleri yazmak.

### 4.3 Güvenlik ve yaşam döngüsü

- [x] API anahtarlarını macOS Keychain'de saklamak.
- [x] API anahtarlarının log veya ayar dosyasına yazılmadığını doğrulamak.
- [x] Geçici ham ses dosyalarını başarılı işlem sonrasında temizlemek.
- [x] Kullanıcının tek bir toplantıyı tüm bağlı dosyalarıyla silebilmesini sağlamak.
- [x] Otomatik saklama süresi seçilmişse periyodik temizleme uygulamak.
- [x] Uygulama çökmesi sonrası kurtarılabilir dosyaları tespit etmek.
- [x] Hassas içeriklerin hata ve analytics kayıtlarına girmediğini doğrulamak.

### Faz 4 çıkış kriterleri

- [ ] Uygulama yeniden başlatıldığında toplantı ve görev verileri korunuyor.
- [ ] Yarım yazma veya çökme mevcut veriyi bozmuyor.
- [ ] Anahtarlar ve toplantı içeriği güvenli sınırlar içinde tutuluyor.

## Faz 5 — Görevler özelliği

### 5.1 Aktif görevler

- [x] Görev yaşam döngüsünü `backlog / todo / in progress / completed / blocked`
  durumlarıyla modellemek; tamamlananı otomatik arşivlerken manuel arşivlemeyi ayrı tutmak
  ve görev özetini durum ikonlarıyla göstermek.
  — ✅ Tamamlandı: 2026-08-17 / task states, separate archive and status summary
- [x] Yeni görev ekleme alanını oluşturmak.
- [x] Boş veya yalnızca whitespace içeren görevleri engellemek.
- [x] Her göreve kararlı benzersiz kimlik vermek.
- [x] Aktif görevleri belleğe yüklemek ve UI'da göstermek.
- [x] Görevi tamamlandı olarak işaretlemeyi uygulamak.
- [x] Görevi düzenlemeyi uygulamak.
- [x] Görevi silmeyi onay veya geri alma davranışıyla uygulamak.
- [x] Görev sırasını değiştirme ihtiyacını ürün kararına göre uygulamak.
- [x] Aktif görev sayısını kompakt notch rozetine bağlamak.

### 5.2 Arşiv

- [x] Tamamlanan görevi completion timestamp ile arşivlemek.
- [x] Arşiv listesini göstermek.
- [x] Arşivlenmiş görevi tekrar aktife almayı uygulamak.
- [x] Tek görevi veya tüm arşivi silmeyi uygulamak.
- [x] Aktif dosya ile arşiv dosyası arasındaki taşıma işlemini atomik hale getirmek.

### 5.3 Görev testleri

- [x] Aynı metne sahip birden fazla görevi test etmek.
- [x] Özel karakter, emoji ve çok uzun görev metinlerini test etmek.
- [x] Hızlı art arda ekleme/tamamlama işlemlerini test etmek.
- [x] Bozuk görev dosyası kurtarma davranışını test etmek.

### Faz 5 çıkış kriterleri

- [x] Kullanıcı notch panelinden görev yaşam döngüsünü yönetebiliyor.
- [x] Görev sayısı her durumda doğru.
- [ ] Dosya hatasında görevler sessizce kaybolmuyor.

## Faz 6 — Takvim ve toplantı algılama

### 6.1 EventKit altyapısı

- [x] Takvim bağlantı sağlığını kaynak türleri, okunabilir takvim/etkinlik/toplantı sayıları
  ve son yenileme zamanı ile görünür yapmak; Google hesabı yok, izin reddi ve sorgu hatasını
  ayrı düzeltme aksiyonlarına bağlamak.
  — ✅ Tamamlandı: 2026-08-17 / calendar reliability and account diagnostics
- [x] Tek ve uzun ömürlü EventKit store oluşturmak.
- [x] Yaklaşan etkinlikler için sorgu zaman aralığını belirlemek.
- [x] Takvim değişiklik bildirimlerini dinlemek.
- [x] Etkinlik listesini periyodik ve değişiklik bazlı yenilemek.
- [x] İptal edilmiş, reddedilmiş ve tüm gün etkinliklerini filtrelemek.
- [x] Tekrarlayan etkinlik örneklerini doğru ele almak.
- [x] Saat dilimi değişikliklerini ele almak.

### 6.2 Çevrim içi toplantı tespiti

- [x] URL, location ve notes alanlarından toplantı linki çıkarmak.
- [x] Zoom linklerini tanımak.
- [x] Google Meet linklerini tanımak.
- [x] Microsoft Teams linklerini tanımak.
- [x] Yaygın alternatif meeting URL'leri için genişletilebilir matcher yapısı oluşturmak.
- [x] Büyük/küçük harf, URL encoding ve tracking parametrelerini test etmek.
- [x] Aynı etkinlikte birden fazla link olduğunda seçim kuralını belirlemek.
- [ ] Link içermeyen etkinliği manuel olarak toplantı kabul etme seçeneğini değerlendirmek.

### 6.3 Yaklaşan toplantı deneyimi

- [x] En yakın toplantıyı 10 dakika ve 1 dakika eşiklerinde notch üzerinde göstermek.
- [x] Toplantı başlığı ve kalan süreyi göstermek.
- [x] Toplantı linkini açma aksiyonu eklemek.
- [x] Toplantı için kayıt başlatma aksiyonu eklemek.
- [x] Hatırlatmayı sessize alma veya geçme aksiyonu eklemek.
- [x] Çakışan toplantılarda en erken başlayanı seçmek.
- [x] Takvim etkinliği güncellendiğinde notch state'ini yenilemek.

### 6.4 Gerçek toplantı session algılama

- [x] Takvim bağlamından bağımsız meeting session domain modelini ve state machine'i
  oluşturmak.
- [x] Core Audio process input/output aktivitesini bundle ID ve PID ile izlemek.
- [x] Zoom process/window ve Google Meet Chrome window/tab/call-control adaptörlerini
  Accessibility üzerinden prototiplemek.
- [x] Takvim, `Katıl`, process IO ve client adapter kanıtlarını confidence skoruna
  dönüştürmek.
- [x] Başlangıç, bitiş şüphesi ve doğrulanmış bitiş davranışlarını notch'a bağlamak.
- [x] Manuel toplantı kaydını tüm algılama/Accessibility hata durumlarında korumak.

### 6.5 Destek matrisi

- [ ] Zoom Workplace native: planlı/plansız, erken/geç katılım, mute/unmute, hang-up ve
  uygulamanın açık kalması senaryolarını gerçek cihazda doğrulamak.
- [ ] Google Meet/Chrome: planlı/plansız, erken/geç katılım, mute/unmute, hang-up ve
  uygulamanın açık kalması senaryolarını gerçek cihazda doğrulamak.
- [ ] Google Meet/Chrome'da toplantı sekmesi dışındaki tarayıcı sesini canary-audio ile
  doğrulamak; izolasyon kaybolduğunda global kayda düşmeyen fail-closed fallback'i test etmek.
- [ ] Desteklenmeyen istemcide “otomatik algılandı” iddiası yerine açık manuel mod sunmak.

### Faz 6 çıkış kriterleri

- [ ] Desteklenen servislerde yaklaşan toplantılar güvenilir biçimde algılanıyor.
- [x] Takvim özelliği kapalı veya izinsizken manuel kayıt etkilenmiyor.
- [ ] Çakışma, iptal ve değişiklik senaryoları ele alınıyor.
- [ ] Desteklenen istemcide gerçek başlangıç ve bitiş yalnız takvim saatine dayanmadan
  güvenilir biçimde algılanıyor.

## Faz 7 — Ses kayıt motoru

### 7.1 Kayıt oturumu

- [x] Kayıt başlatma/durdurma işlemlerini yöneten recording coordinator oluşturmak.
- [x] Oturum kimliği, başlangıç zamanı ve kaynak toplantı metadata'sını kaydetmek.
- [x] Kayıt başlamadan önce disk alanını ve izinleri kontrol etmek.
- [x] Mikrofon ve sistem sesi kaynaklarını eş zamanlı hazırlamak.
- [x] Kayıt başladığını yalnızca iki kaynak hazır olduğunda UI'a bildirmek.
- [x] Manuel durdurmayı uygulamak.
- [x] Güvenli iptal ve dosya temizleme davranışını uygulamak.
- [x] Maksimum kayıt süresi veya disk dolması sınırlarını yönetmek.
  — ✅ Tamamlandı: 2026-08-11 / kayıt sırasında periyodik disk güvenlik denetimi ve güvenli finalize

### 7.2 Mikrofon yakalama

- [x] Bluetooth/24 kHz mikrofon buffer'larının M4A writer'da sıfır bayt dosya ve
  `kCMSampleBufferError_RequiredParameterMissing` üretmesini engellemek.
- [x] Kullanılabilir mikrofonları listelemek.
- [x] Varsayılan veya kullanıcı seçili mikrofonu kullanmak.
- [x] Mikrofon buffer'larını timestamp bilgisiyle kaydetmek.
- [x] Mikrofon seviye ölçümünü UI için üretmek.
- [x] Mikrofon bağlantısı kesildiğinde kullanıcıyı uyarmak.
- [x] Mikrofon değişikliği sonrası yeniden bağlanma davranışını uygulamak.

### 7.3 Sistem sesi yakalama

- [x] Process Tap veya seçilen sistem sesi çözümünü production yapısına taşımak.
- [x] Yakalanacak process/global audio davranışını belirlemek.
- [x] Uygulamanın kendi bildirim sesini gerekiyorsa capture dışında bırakmak.
- [x] Sistem sesi buffer'larını timestamp bilgisiyle kaydetmek.
- [x] Sessizlik ile kopmuş audio pipeline durumunu mümkün olduğunca ayırt etmek.
  — ✅ Tamamlandı: 2026-08-11 / frame heartbeat, writer error ve fail-closed güvenli durdurma
- [x] Çıkış cihazı veya sample rate değişimini ele almak.
  — ✅ Tamamlandı: 2026-08-11 / normalize-or-fail-closed device policy
- [x] Core Audio Process Tap, aggregate device ve dosya kaynaklarını her bitiş/hata yolunda
  temizlemek.
- [x] Global tap'i desteklenen toplantı process'leriyle sınırlı private process tap'e
  dönüştürmek.
- [x] Meeting process'i kapanır/değişirse tap'i güvenli yeniden bağlamak veya kaydı görünür
  uyarıyla durdurmak.

### 7.4 Senkronizasyon ve dosya üretimi

- [x] İki ses kaynağı için ortak timeline stratejisini uygulamak.
- [x] Başlangıç offset'ini ele almak.
- [x] Uzun süreli clock drift'ini ele almak.
  — ✅ Tamamlandı: 2026-08-11 / bounded timestamp-based time-pitch correction
- [x] Sample rate ve kanal düzenini normalize etmek.
- [x] Kaynak gain dengesini uygulamak.
- [x] Limiter uygulayarak clipping'i önlemek.
  — ✅ Tamamlandı: 2026-08-11 / offline mix soft limiter
- [x] Provider için tek ve geçerli M4A/AAC dosyası üretmek.
- [x] Nihai dosyanın süresini ve okunabilirliğini doğrulamak.
- [x] Finalize işlemi başarısız olursa kaynak geçici dosyaları korumak.
- [x] Çökme sonrası yarım kaydı finalize etme kurtarma akışı oluşturmak.

### 7.5 Kayıt kontrolleri

- [x] Notch üzerinde canlı süre göstermek.
- [x] Mikrofon/system audio durum göstergelerini sunmak.
- [x] Kaydı durdurma kontrolü eklemek.
- [x] İptal kontrolünü yanlış dokunmayı önleyecek şekilde sunmak.
- [x] İsteğe bağlı pause/resume özelliğini ürün kararına göre uygulamak.
  — ✅ Ürün kararı: 2026-08-11 / V1 dışında; timeline ve privacy gate karmaşıklığı ertelendi
- [x] Kayıt sürerken uykuya geçme ve ekran kilidi davranışını belirlemek.
  — ✅ Tamamlandı: 2026-08-11 / sleep, screen sleep and session resign fail-closed

### 7.6 Meeting mikrofon gate'i

- [x] `open/closed/unknown` durumlu, varsayılanı `closed` olan gate state machine'i
  oluşturmak.
- [x] Client mute detector sonucunu gate'e bağlamak; Core Audio input aktivitesini yalnız
  destekleyici kanıt olarak kullanmak.
- [x] `closed/unknown` sample'larını writer öncesinde sıfırlayıp timeline'ı korumak.
- [x] Gate geçişlerini timestamp + kaynakla kayıt metadata'sına yazmak.
- [x] Notch toggle ve global shortcut manuel fallback'i eklemek.
- [x] Adapter kaybı, Accessibility izni kaybı ve bilinmeyen durumda fail-closed davranmak.
- [ ] Mute sırasında söylenen benzersiz cümlenin ham/birleşik/transkript çıktılarında
  bulunmadığı privacy testini geçirmek.

### Faz 7 çıkış kriterleri

- [ ] Farklı ses cihazlarıyla en az 60 dakikalık kayıt bozulmadan tamamlanıyor.
- [ ] Mikrofon ve sistem sesi dinlenebilir, senkron ve provider'a uygun.
- [ ] Cihaz değişimi, disk sorunu ve uygulama kapanması veri kaybını minimize ediyor.
- [ ] Mikrofon yalnız toplantıya gönderildiği doğrulanmış aralıklarda kayda giriyor.
- [ ] Desteklenen istemcide toplantı dışı uygulama sesi kayda girmiyor.

## Faz 8 — Transkripsiyon, diarization ve özet

### 8.1 Test edilebilir transkripsiyon hizmeti sözleşmesi

- [x] Transcription protokolünü tanımlamak.
- [x] Normalize edilmiş transcript ve segment sonuçlarını kullanmak.
- [x] Provider capability modelini tanımlamak.
- [x] Dosya boyutu/format uygunluk kontrolünü ortak katmana eklemek.
- [x] Upload progress bildirimini state machine'e bağlamak.
- [x] Timeout, iptal, authentication ve rate-limit hatalarını normalize etmek.
- [x] Retry politikasını idempotent ve sınırlı yapmak.

### 8.2 Tek uzak servis: ElevenLabs Scribe v2

- [x] ElevenLabs anahtar probunun production API'deki eksik dosya yanıt varyantlarına
  bağlı kalmamasını ve yanıltıcı provider hatası üretmemesini sağlamak.
- [x] ElevenLabs API anahtarı doğrulama, Keychain saklama ve arka plan worker kullanımını
  gerçek Scribe API sözleşmesiyle uçtan uca sağlamlaştırmak.
- [x] Birincil provider client'ını uygulamak.
- [x] API anahtarını Keychain'den kullanmak.
- [x] Dosya upload isteğini ve progress takibini uygulamak.
- [x] Diarization seçeneğini etkinleştirmek.
- [x] Türkçe ve otomatik dil algılamayı doğrulamak.
- [x] Provider yanıtını ortak transcript modeline dönüştürmek.
- [x] Provider hatalarını kullanıcı dostu hale getirmek.
- [x] Fixture/mock yanıtlarla birim testleri yazmak.

### 8.3 Tek servis ürün sınırı

- [x] `TranscriptionProviderID` ve provider resolver'ı yeni ürün modelinden kaldırmak.
- [x] Eski preferences/queue belgelerindeki provider alanını ElevenLabs'e kayıpsız migrate
  edip yeni yazımlarda kaldırmak.
- [x] Eski provider-scoped Keychain kaydını tek ElevenLabs credential kaydına migrate etmek.
- [x] UI, onboarding, hata ve gizlilik metinlerinden provider seçimi/OpenAI vaadini
  kaldırmak.
- [x] Protocol/capability sınırlarını yalnız test doubles ve ElevenLabs request doğrulaması
  için gereken minimum yüzeye indirmek.

### 8.4 Özet ve aksiyon maddeleri

- [x] Özet üretim servisinin provider'dan ayrı mı ortak mı olacağını kesinleştirmek.
- [x] Kısa genel özet üretmek.
- [x] Alınan kararları çıkarmak.
- [x] Aksiyon maddelerini çıkarmak.
- [x] Varsa sorumlu kişi ve tarih bilgisini güvenli biçimde ayrıştırmak.
- [x] Model yapılandırması veya yanıt sorunu olduğunda transkripti yine de kaydetmek.
- [x] Özet sonucunu yapılandırılmış modele dönüştürmek.
- [x] Özet/aksiyon maddelerini toplantı Markdown dosyasına yazmak.

### 8.5 İşleme kuyruğu ve kurtarma

- [x] Finalize edilmiş kayıtları kalıcı işleme kuyruğuna eklemek.
- [x] Uygulama yeniden açıldığında yarım kalan işlemleri göstermek.
- [x] Başarısız upload/transkripsiyon için `Tekrar Dene` aksiyonu sunmak.
- [x] Aynı kaydın yanlışlıkla paralel iki kez işlenmesini engellemek.
- [x] Kalıcı kuyruğu tek ElevenLabs servisini çalıştıran arka plan worker'ına bağlamak.
- [x] Normalize transkript sonucunu toplantı dizinine atomik olarak kaydetmek.
- [x] Başarılı işlemden sonra geçici parçaları temizlemek.

### Faz 8 çıkış kriterleri

- [ ] Gerçek toplantı kaydı konuşmacı ayrımlı transkripte dönüşüyor.
- [x] Özet, kararlar ve aksiyon maddeleri kullanıcıya gösterilebiliyor.
- [x] Ağ veya provider hatası kaydı kaybettirmiyor ve tekrar denenebiliyor.
- [x] Ürün yalnız ElevenLabs ve tek API anahtarıyla uçtan uca çalışıyor; ikinci provider'a
  ait kullanıcı yüzeyi veya aktif runtime dalı bulunmuyor.

## Faz 9 — Toplantı geçmişi ve sonuç deneyimi

### 9.1 Toplantı listesi

- [x] Toplantılar sekmesinde son toplantıları listelemek.
- [x] Tarih, başlık, süre ve işlem durumunu göstermek.
- [x] İşlenmekte veya hata vermiş toplantıları listede ayırt etmek.
- [x] Listeyi tarih sırasına göre düzenlemek.
- [x] Boş durum görünümü hazırlamak.
- [ ] Gerekirse basit arama eklemek.

### 9.2 Toplantı detay ekranı

- [x] Özet bölümünü göstermek.
- [x] Kararlar bölümünü göstermek.
- [x] Aksiyon maddeleri bölümünü göstermek.
- [x] Konuşmacı ayrımlı transkripti göstermek.
- [ ] Konuşmacı adlarını kullanıcı tarafından düzenlenebilir yapmak.
- [x] Segment timestamp'ine tıklayarak kayıtta ilgili noktaya gitmeyi uygulamak.
- [x] Ses oynatma kontrollerini eklemek.
- [x] Uzun transkriptlerde performanslı kaydırmayı doğrulamak.
  — ✅ Tamamlandı: 2026-08-17 / 390 segment scroll regression and unclipped notch shadow

### 9.3 Dışa aktarma ve yönetim

- [x] Transkripti Markdown olarak dışa aktarmak.
- [x] Transkripti düz metin olarak kopyalamak.
- [x] Özet ve aksiyon maddelerini kopyalamak.
- [x] Ses dosyasını Finder'da göstermek.
- [ ] Toplantı dosyalarını kullanıcı seçtiği konuma export etmek.
- [x] Toplantıyı ve bağlı verileri silmek.
- [x] Silme sonrası geri alma veya güçlü onay davranışı sunmak.
- [x] Transkripsiyonu yeniden deneme aksiyonu eklemek.

### 9.4 Tamamlandı deneyimi

- [x] İşlem bitince notch üzerinde kısa başarı durumu göstermek.
- [x] Başarı durumundan toplantı detayına geçiş sağlamak.
- [ ] Panel kapalıysa yerel bildirim seçeneğini uygulamak.
- [ ] Bildirime tıklanınca doğru toplantıyı açmak.

### Faz 9 çıkış kriterleri

- [x] Kullanıcı eski toplantıyı bulabiliyor, okuyabiliyor, dinleyebiliyor ve silebiliyor.
- [x] Sonuçlar uygulama yeniden başlatıldığında doğru yükleniyor.
- [x] Dışa aktarma çıktıları başka uygulamalarda kullanılabilir.

## Faz 10 — Dayanıklılık, performans ve erişilebilirlik

### 10.1 Hata ve edge-case testleri

- [x] Mikrofon izni reddi ve sonradan kaldırılmasını test etmek.
- [x] Sistem sesi izni reddi ve sonradan kaldırılmasını test etmek.
- [ ] Takvim izni reddini test etmek.
- [x] Geçersiz API anahtarını test etmek.
- [ ] İnternet kesintisi ve bağlantının geri gelmesini test etmek.
- [x] Provider 401, 429, 5xx ve timeout yanıtlarını test etmek.
- [ ] Kayıt sırasında ses cihazı değişimini test etmek.
- [ ] Kayıt sırasında uyku/uyanma ve ekran kilidini test etmek.
- [ ] Disk dolması veya yazma hatasını test etmek.
- [ ] Kayıt, upload ve save sırasında force quit sonrası kurtarmayı test etmek.
- [ ] Çok uzun toplantı adı ve transkriptini test etmek.
- [ ] Aynı anda yaklaşan iki toplantıyı test etmek.
- [x] Meeting client bulunamadı, Accessibility izni reddedildi ve mute state `unknown`
  senaryolarında mikrofonun fail-closed kaldığını test etmek.
- [x] Meeting client hang-up, crash, process restart ve meeting window kapanma senaryolarını
  test etmek.
- [x] Mute iken söylenen canary phrase'in hiçbir kalıcı ses/transkript çıktısına girmediğini
  otomatik doğrulamak.
- [ ] Process-scope tap sırasında müzik/bildirim/tarayıcı gibi toplantı dışı seslerin kayda
  girmediğini doğrulamak.

### 10.2 Performans ve kaynak kullanımı

- [ ] Boşta CPU ve enerji kullanımını ölçmek.
- [ ] Hover panel kapalıyken gereksiz render/polling olmadığını doğrulamak.
- [ ] Kayıt sırasında memory kullanımını uzun süre izlemek.
- [ ] Büyük transkript açılış ve kaydırma performansını ölçmek.
- [x] Mikrofon cihaz keşfini CMIO/AVFoundation provider arızasında ana thread'i
  bloklamayacak şekilde izole etmek.
  — ✅ Tamamlandı: 2026-07-29 / CMIO hang hardening
- [ ] Dosya erişimini ana thread dışında tutmak.
- [ ] Ses realtime callback'lerinde allocation ve bloklayan işlem olmadığını doğrulamak.
- [ ] Instruments ile temel leak ve retain-cycle taraması yapmak.

### 10.3 Erişilebilirlik

- [ ] Tüm interaktif öğelere anlamlı accessibility label eklemek.
- [ ] VoiceOver ile onboarding, kayıt ve toplantı detay akışını test etmek.
- [ ] Yalnızca renkle ifade edilen durumları kaldırmak.
- [ ] Klavye navigasyonu ve focus sırasını test etmek.
- [ ] Reduce Motion ve Increase Contrast ayarlarına uymak.
- [ ] Metinlerin uzun veya lokalize karşılıklarında taşmadığını doğrulamak.

### 10.4 Otomatik test kapsamı

- [ ] State machine birim testlerini tamamlamak.
- [ ] Repository ve migration testlerini tamamlamak.
- [ ] Calendar matcher testlerini tamamlamak.
- [x] Provider response parsing testlerini tamamlamak.
- [ ] Audio utility ve timeline hesaplama testlerini tamamlamak.
- [ ] Kritik onboarding ve kayıt akışı için UI testleri eklemek.
- [x] Test fixture'larında gerçek kullanıcı veya hassas toplantı verisi kullanmamak.

### Faz 10 çıkış kriterleri

- [ ] Kritik edge-case test matrisi geçiyor.
- [ ] Uzun kullanımda kabul edilemez CPU, memory veya enerji sorunu yok.
- [ ] Temel ürün akışları klavye ve VoiceOver ile kullanılabilir.
- [ ] Kritik domain ve veri işlemleri otomatik testlerle korunuyor.

## Faz 11 — Gizlilik, ürün metinleri ve yayın hazırlığı

### 11.1 Gizlilik ve güven

- [ ] Açık kayıt göstergesinin kayıt boyunca görünür olduğunu doğrulamak.
- [ ] Kullanıcıya sesin ElevenLabs Scribe v2'ye gönderildiğini göstermek.
- [ ] Kayıt boyunca meeting mic gate durumunu `Açık/Kapalı/Bilinmiyor` olarak görünür
  tutmak.
- [ ] Kayıt öncesi gerekli yasal/etik bilgilendirme metnini hazırlamak.
- [ ] Gizlilik politikası hazırlamak.
- [ ] Kaydedilen yerel ve uzak veri türlerini açıkça belgelemek.
- [ ] ElevenLabs veri saklama ve zero-retention seçeneklerini güncel resmi sözleşmeye göre
  belgelemek.
- [ ] Kullanıcı verisi silme akışını uçtan uca doğrulamak.
- [ ] Uygulamanın gizli veya kullanıcıdan habersiz kayıt başlatmadığını doğrulamak.

### 11.2 Ürün metinleri ve görseller

- [ ] Uygulama adı ve kısa açıklamayı kesinleştirmek.
- [ ] Menü, onboarding, izin ve hata metinlerini gözden geçirmek.
- [ ] Uygulama ikonunu hazırlamak.
- [ ] Menü çubuğu template ikonunu hazırlamak.
- [ ] Boş durum ve hata görsellerini gerekiyorsa hazırlamak.
- [ ] About ekranı ve sürüm bilgisini eklemek.

### 11.3 Build ve dağıtım

- [ ] Minimum desteklenen macOS sürümünü proje ayarlarında kesinleştirmek.
- [ ] Debug ve Release için doğru entitlement/permission ayarlarını doğrulamak.
- [ ] Hardened Runtime ayarlarını doğrulamak.
- [ ] Developer ID veya App Store signing yapılandırmasını tamamlamak.
- [ ] Release archive oluşturmak.
- [ ] Notarization sürecini tamamlamak.
- [ ] Notarized uygulamayı temiz bir Mac kullanıcı hesabında test etmek.
- [ ] Otomatik güncelleme kullanılacaksa update altyapısını uygulamak.
- [ ] Sürüm notlarını hazırlamak.
- [ ] Destek ve hata bildirim kanalını belirlemek.

### 11.4 Release candidate doğrulaması

- [ ] İlk kurulumdan ilk başarılı transkripte kadar temiz kurulum testi yapmak.
- [ ] Intel desteği hedefleniyorsa Intel Mac üzerinde test etmek.
- [ ] Apple Silicon üzerinde desteklenen macOS sürümlerini test etmek.
- [ ] Notch ve notch olmayan ekranlarda test etmek.
- [ ] Çoklu ekran ve tam ekran senaryosunu test etmek.
- [ ] 60+ dakikalık gerçekçi toplantı kaydı ve işlemesini tamamlamak.
- [ ] Veri silme ve uygulama kaldırma davranışını doğrulamak.
- [ ] Kritik açık hata kalmadığını doğrulamak.

### Faz 11 çıkış kriterleri

- [ ] Gizlilik, izin ve kayıt davranışları kullanıcıya açık.
- [ ] Release candidate imzalı, notarize ve temiz sistemde çalışıyor.
- [ ] V1 tamamlanma tanımındaki bütün maddeler karşılanıyor.

## V1 sonrası — Şimdilik kapsam dışı fikirler

Bu bölümdeki maddeler v1 tamamlanmasını engellemez ve v1 görevlerinin arasına alınmaz.

- [ ] Timeline ve privacy gate semantiğiyle birlikte kayıt pause/resume özelliği.
- [ ] Cihazlar arası bulut senkronizasyonu.
- [ ] Tamamen cihaz üstü transkripsiyon.
- [ ] Canlı transkript.
- [ ] Otomatik toplantı botu veya görüşmeye katılan sanal katılımcı.
- [ ] Proje/etiket bazlı görev organizasyonu.
- [ ] Takımdaki kişilerle transkript paylaşımı ve ortak düzenleme.
- [ ] Slack, Notion, Linear veya proje yönetimi entegrasyonları.
- [ ] Gelişmiş semantik arama ve tüm toplantılara soru sorma.
- [ ] Mobil veya web companion uygulaması.
- [ ] Ekip/workspace ve yönetici özellikleri.

## İlerleme günlüğü

Tamamlanan önemli kilometre taşları buraya en yeniden eskiye doğru kısa şekilde eklenir.

- 2026-08-19 — Ana paneldeki 200 px yapay içerik tabanı kaldırıldı. Meetings, Tasks ve
  detail içerikleri 600 px'e kadar doğal yüksekliğinde kalıyor; aktif ekran daha kısaysa
  onun güvenli sınırı, içerik uzunsa ScrollView kullanılıyor. Kısa ve uzun içerik ölçülerini
  doğrulayan regresyon testi eklendi; tam pakette 307 testten 304'ü geçti, üç opt-in donanım
  testi beklendiği gibi atlandı ve Apple Development imzalı Debug build tamamlandı.

- 2026-08-17 — Toplantı detayındaki transkript satırları iç içe lazy stack'ten çıkarılıp
  scroll yüzeyinin tek dış `LazyVStack`'ına doğrudan bağlandı. Uzun transkriptlerde yüzlerce
  native text-selection köprüsü yerine segment context-menu ve tüm-transkript kopyalama
  kullanılıyor; audio ilerleme yayınlarını yalnız player gözlemliyor ve tüm detail ağacı
  saniyede dört kez yeniden değerlendirilmiyor. Ekran görüntüsündeki alt gölge kesilmesinin,
  DynamicNotchKit'in 15 pt güvenli alanında hover gölgesini 20 pt'e büyütmesinden geldiği
  doğrulandı; stabil 10 pt gölgeye dönüldü. 390 segment ve 64 scroll-wheel olaylı regresyon
  0,24 saniyede geçti. Tam pakette 304 testten 301'i geçti, üç opt-in donanım testi beklendiği
  gibi atlandı; Apple Development imzalı Debug build strict/deep codesign doğrulamasından geçti.

- 2026-08-17 — EventKit takvim bağlantısı kaynak türü ve takvim sayısı, taranan etkinlik,
  eşleşen çevrim içi toplantı, son yenileme ve canlı refresh durumuyla gözlemlenebilir hale
  getirildi. Ayarlar izin verme, Takvim gizlilik paneli, macOS İnternet Hesapları ve sorguyu
  tekrar deneme yollarını ayrı aksiyonlarla sunuyor; Google Calendar'ın sistem hesabından
  okunduğu ve Gmail e-postalarına erişilmediği onboarding/README'de açıklandı. Google ve
  Outlook redirect'leri, HTML/percent encoded ve şemasız Zoom/Meet/Teams linkleri HTTPS'e
  normalize ediliyor; tekrar eden event'ler eleniyor, occurrence kimlikleri refresh'ler
  arasında stabil ve sonraki üç toplantı notch'ta görünüyor. Burst refresh'ler coalesce
  ediliyor. Tam pakette 301 testten 298'i geçti, üç opt-in donanım testi beklendiği gibi
  atlandı; Apple Development imzalı Debug build strict/deep codesign doğrulamasından geçti.

- 2026-08-19 — Figma `18:2785` içindeki dört ana panel frame'i SwiftUI'a taşındı. Ana panel
  600 px'e çıktı; 20/12/10/4 px spacing ritmi, 24/22/16 px radius hiyerarşisi, 12–20 pt
  SF Pro rolleri ve tasarımdaki 19 özgün SVG ikon asset catalog'a eklendi. Yaklaşan/boş
  toplantı, aktif kayıt ve görev görünümleri işlevleri korunarak yeniden kuruldu; koyu panel
  fiziksel notch ve floating sunumda aynı görsel sonucu üretir hale getirildi. Dört durum
  Figma frame yüksekliklerinde offscreen bitmap smoke testiyle render edildi; tam pakette
  306 testten 303'ü geçti, üç opt-in donanım testi beklendiği gibi atlandı.

- 2026-08-17 — Görevler backlog, todo, in progress, completed ve blocked durumlarına
  ayrıldı. Durum ile arşiv bağımsız modellendi; completed geçişi atomik olarak otomatik
  arşivlerken diğer durumlar manuel arşivlenebiliyor ve tamamlanmış görev geri alındığında
  todo'ya dönüyor. Eski completion timestamp verisi tasks şema v2'ye kayıpsız migrate
  ediliyor. Görev başlığındaki toplam aktif/arşiv metni durum ikonları ve sayılarıyla
  değiştirildi; arşiv alttaki açılır bölümden sağ üstteki kompakt düğmeyle açılan ayrı
  görünüme taşındı. Tam pakette 289 testten 286'sı geçti, üç opt-in donanım testi beklendiği
  gibi atlandı; imzalı Debug build strict/deep codesign doğrulamasından geçti.

- 2026-08-11 — Fiziksel notch UI appearance regresyonu giderildi. DynamicNotchKit'in siyah
  yüzeyinde sistem açık teması miras alıp pasif sekme ve ikincil metni karartması engellendi;
  fiziksel notch expanded/compact içerikleri koyu görünümü kullanırken floating panel sistem
  temasını koruyor. Sekme seçiminin ilk frame'de layout'u daraltabilen matched-geometry
  arka planı kaldırıldı; iki sekme sabit genişlikte her zaman görünür, pasif/hover/seçili
  durumlar ayrı kontrast ve yüzey token'larıyla çalışıyor. Pin kontrolünün pasif vurgusu,
  status surface hiyerarşisi ve konsantrik tab radius'ları da düzeltildi. Açık sistem teması
  + siyah fiziksel-notch zemini offscreen PNG smoke testiyle render edildi; tam pakette 287
  testten 284'ü geçti, üç opt-in donanım testi beklendiği gibi atlandı ve imzalı Debug build
  üretildi.

- 2026-08-11 — V1 completion/blocker audit'i yapıldı. `macos/QA/Evidence` altında gerçek Zoom/Meet
  kabul kanıtı bulunmadı; kurulu Zoom Workplace 6.7.7 ve Chrome 151 fiziksel görüşme için
  kullanıcı hesabı/etkileşimi bekliyor. Keychain'de yalnız Apple Development kimliği var;
  Developer ID Application sertifikası ve `Crenel-Notary` profili bulunmuyor. Chrome
  Web Store publisher/dashboard ID ile public HTTPS gizlilik, destek ve geliştirici alanları
  da dış hesap bilgisi bekliyor. Kod, otomasyon, kanıt collector'ları ve imzalı Debug kapısı
  yeşil kaldı; fiziksel ses kaydı, destructive sistem koşulları veya hesap yayını kullanıcı
  onayı olmadan başlatılmadı.

- 2026-08-11 — Google Meet sekme izolasyonunun production hattı hazırlandı. Kullanıcı
  onaylı MV3 popup yalnız canonical Meet sekmesini `tabCapture` ile offscreen audio'ya
  bağlıyor, sesi yerel çıkışa geri oynatıyor ve sabit extension origin'li native messaging
  helper üzerinden kullanıcıya özel Unix socket'e iletiyor. Sequence/backpressure, framing,
  PCM ve kopma sınırları iki kez doğrulanıyor; gerçek gömülü helper stdin → socket → broker
  → ACK akışı ve PCM → M4A encode testi geçti. Uygulama/onboarding canlı `bekleniyor / bağlı /
  kayıt hattında` durumunu ve fail-closed güvenlik durdurmasını gösteriyor. Ağustos 2026
  Chrome veri açıklama kuralı için yakalama öncesi açık onay popup'ı, minimum izin
  gerekçeleri, gizlilik politikası taslağı, Store metni, ikon/promosyon varlıkları ve
  checksum'lı v0.1.0 ZIP üretimi eklendi. Gerçek ham/final M4A'yı belleğe bütünüyle almadan
  997 Hz tone, minimum süre ve transcript canary cümlesi için JSON/Markdown kanıta dönüştüren
  auditor da eklendi; temiz/sızıntılı CLI fixture'ları ayrı exit code'larla doğrulandı.
  Session acceptance collector ise privacy-safe unified loglardan istemci/senaryo başına
  beşli `ready/confirmed → ended/confirmed` zincirini ve terminal state regresyonunu denetliyor.
  Extension testleri 6/6, recovery paketi 102/102 ve tam macOS paketi 283 testten 280 geçiş +
  üç opt-in donanım skip ile yeşil. Helper yalnız
  `Contents/Library/LaunchServices` altında bulunuyor; uygulama/helper Apple Development
  Hardened Runtime imzaları strict/deep doğrulamadan geçti. Gerçek Chrome iki sekmeli
  canary, Store dashboard ID/public policy/review, 65 dakikalık istemci koşuları ve
  Developer ID notarization açık.

- 2026-08-11 — Minimal UI ve release-hardening hazırlığı tamamlandı. Kompakt notch Zoom/Meet
  istemcisi, kayıt süresi ve fail-closed mic gate'i gösteriyor; ayarlar/onboarding tek
  ElevenLabs sınırını ve Accessibility rızasını açıklıyor. Light/dark, contrast, reduced
  motion, keyboard ve VoiceOver sözleşmelerini kapsayan altı preview durumu eklendi.
  Recovery otomasyonu ağ geri dönüşü, aynı idempotency key ile retry, sleep sırasında
  `systemInterruption` fail-closed/finalize, force-quit queue/capture ve cihaz değişimini
  kapsıyor. Kayıt sırasında 30 saniyelik disk güvenlik denetimi kritik alanda görünür
  uyarıyla finalize ediyor; Core Audio frame heartbeat'i gerçek sessizliği kopmuş pipeline
  ve writer hatasından ayırıp fail-closed durduruyor. V1 fiziksel test runbook'u, kanıt
  şablonu ve Developer ID + notarization RC betiği hazırlandı. Timestamp tabanlı bounded
  drift düzeltmesi pitch'i koruyor; offline soft limiter sıcak miksleri 1.0 altında tutuyor.
  Ekran uyku/oturum pasif olayları da güvenli finalize'a bağlı. 257 testten 254'ü geçti, üç
  opt-in donanım testi normal pakette atlandı; düzeltilen opt-in runner ile fiziksel mic,
  system audio M4A ve izin/tap probu ayrıca 3/3 geçti. Apple
  Development imzalı Debug build ve universal unsigned Release archive geçti. Developer ID
  sertifikası/notary profili, gerçek 65 dakika koşuları ve güvenli Chrome tab izolasyonu açık.

- 2026-08-11 — Privacy-first mikrofon hattı tamamlandı: her kayıt kapalı gate ile başlıyor;
  Zoom/Meet adapter durumları timestamp'li metadata event'lerine bağlanıyor; `closed/unknown`
  PCM frame'leri encode öncesi sıfırlanıyor ve beş milisaniyelik sınır fade'leri timeline'ı
  koruyor. Notch kontrolü ile sistem genelindeki ⌥⌘M kısayolu manuel fallback sağlıyor;
  process/Accessibility kaybı gate'i `unknown` yapıp notch uyarısını açıyor. Sentetik canary
  ham mic, system ve birleşik M4A'da sızıntı göstermedi; hızlı gate ve 24/48 kHz geçişleri
  geçti. Toplam 243 testten 240'ı geçti, üç opt-in donanım testi atlandı; imzalı Debug build
  ve strict codesign doğrulandı. Gerçek konuşma/kulaklık/transkript privacy koşusu açık.

- 2026-08-11 — Gerçek toplantı kaydının sistem sesi private Core Audio process tap'e
  taşındı. Doğrulanmış Zoom audio process nesnesi doğrudan tap kapsamına veriliyor;
  process kaybolur/eşleşmezse global capture'a düşmeden kayıt engelleniyor. Google Meet'te
  Chrome process-wide kapsamı sekme izolasyonu kanıtlanana kadar fail-closed tutuluyor;
  yalnız kullanıcının toplantı bağlamı dışındaki açık manuel kaydı ayrı global kapsamı
  kullanabiliyor. Toplam 224 testten 221'i geçti, üç opt-in donanım testi atlandı; imzalı
  Debug build ve strict codesign doğrulaması geçti.

- 2026-08-11 — Session fixture matrisi planlı/plansız toplantı, takvim aralığından önce ve
  sonra katılım, sessizlik/ara, client process'inin görüşme sonrasında açık kalması,
  Accessibility olmadan manuel kayıt ve aynı PID üzerinde arka arkaya görüşmeleri kapsayacak
  şekilde genişletildi. Sessizlik bitiş üretmiyor; takvimsiz belirsiz hang-up kullanıcı
  onayında kalıyor; yeni call controls aynı process üzerinde yeni session kimliği açıyor.
  Toplam 218 testten 215'i geçti, üç opt-in donanım testi atlandı; imzalı Debug build ve
  codesign bütünlüğü doğrulandı. Zoom ve Google Meet gerçek çağrı beşli koşuları fiziksel
  kalite kapısı olarak açık tutuldu.

- 2026-08-11 — Confirmed meeting başlangıcı tek seferlik görünür kayıt teklifine; probable
  bitiş manuel kullanıcı onayına; confirmed bitiş ise beş saniyelik iptal edilebilir
  auto-stop akışına bağlandı. Kullanıcının “Kayda Devam Et” seçimi aynı session için yeni
  otomatik durdurma baskısını engelliyor; sayaç ve karar aksiyonları notch ana yüzeyinde
  görünür kalıyor. Toplam 211 testten 208'i geçti, üç opt-in donanım testi atlandı; imzalı
  Debug build ve codesign bütünlüğü doğrulandı.

- 2026-08-11 — Takvim, Crenel `Katıl` aksiyonu, Core Audio process IO ve normalize
  Accessibility adapter snapshot'larını tek deterministic `MeetingSessionCoordinator`
  altında birleştiren production hattı tamamlandı. Meeting controls, mevcut session PID'si,
  URL ile eşleşen istemci ve aktif IO için kararlı seçim sırası uygulandı; sıradan boşta
  Chrome penceresi ile tek başına takvim bağlamı confirmed toplantıya yükseltilmiyor.
  Coordinator AppState, kayıt başlangıç/bitişi ve gerçek URL açma akışına bağlandı. Toplam
  205 testten 202'si geçti, üç opt-in donanım testi atlandı; imzalı Debug build ve codesign
  bütünlüğü doğrulandı.

- 2026-07-29 — Apple kamera extension provider'ının ürettiği CMIO bağlantı hataları
  toplantı detayı açıkken UI'ı bekletebiliyordu. Mikrofon cihaz keşfi ana actor'dan
  utility-priority detached işe taşındı, tekrar eden refresh istekleri birleştirildi ve
  gereksiz `.external` device type kaldırıldı. Aynı CMIO hata dizisi test ortamında yeniden
  üretilirken 500 ms geciken keşfin UI başlangıcını bloklamadığı doğrulandı. 199 testten
  196'sı geçti, üç opt-in donanım testi atlandı; focused Thread Sanitizer, static analyze,
  imzalı Debug build, codesign ve canlı main-thread sample kontrolleri geçti.

- 2026-07-29 — Zoom Workplace ve Google Meet/Chrome için ortak, fixture-test edilebilir
  Accessibility adapter sınırı tamamlandı. Bundle ID/PID eşleme, sınırlı AX tree taraması,
  meeting window/tab, call controls ve `open/closed/unknown` mikrofon sonucu normalize
  ediliyor. İzin yokken ağaç okunmadan fail-closed snapshot üretiliyor; desteklenmeyen
  process izin istemiyor ve sıradan Chrome penceresi Meet sayılmıyor. İmzalı Debug build ile
  197 test geçti; üç opt-in donanım testi beklendiği gibi atlandı.

- 2026-07-29 — Google Meet/Chrome, Zoom Workplace ile eşit zorunlu V1 destek yüzeyi yapıldı.
  Session algılama, mute gate, 60+ dakika uçtan uca test ve privacy kabulü iki istemci için
  ayrı ayrı zorunlu. Chrome toplantı sekmesi dışındaki ses izole edilemezse global kayda
  sessizce düşmeyen fail-closed güvenli fallback ürün sözleşmesine eklendi.

- 2026-07-29 — Notch arayüzünün precision UI geçişi tamamlandı. Ana panel 424 px'e,
  transkript detayı 520 px'e akışkan genişliyor; yatay padding 8 px'e inerken bölüm ritmi
  12–14 px'e çıkarıldı. Başlık/gövde için sans, tarih/süre/sayaç için mono roller ayrıldı;
  Recent ve Görevler satırları ortak sabit ikon grid'i ve divider yapısına taşındı.
  Görünür satır içi silme ikonları kaldırıldı; destructive işlemler context/taşma menüsü ve
  onay üzerinden çalışıyor. Markdown/TXT kopyalama notch detail içinde kalıyor. İmzalı Debug
  build ile 189 test geçti; üç opt-in donanım testi beklendiği gibi atlandı.

- 2026-07-25 — Tek API sadeleştirmesinin uygulama dilimi tamamlandı. Provider seçici ve
  OpenAI yüzeyi kaldırıldı; `TranscriptionProviderID` ile runtime resolver silindi ve worker
  doğrudan tek `TranscriptionServicing` bağımlılığı kullanıyor. Preferences ve processing
  queue belgeleri şema v2'ye yükseltilerek eski provider alanları okunup yeni yazımlardan
  çıkarılıyor. Eski `elevenLabs` Keychain hesabı save-first olarak tek
  `elevenlabs-api-key` hesabına migrate ediliyor; doğrulama, değiştirme ve bağlantıyı
  kaldırma akışları korundu. 176 testten 173'ü geçti, üç opt-in donanım testi atlandı.

- 2026-07-25 — Meeting session detector'ın domain çekirdeği eklendi. Calendar, join,
  process, Core Audio IO, client UI ve manuel kayıt kanıtları normalize edilerek
  `scheduled → candidate → ready → recording → endSuspected → ended` akışına indirgeniyor;
  sessizlik tek başına bitiş üretmiyor ve bitmiş session terminal kalıyor. Core Audio process
  listesi bundle ID/PID ile okunuyor, input/output IO değişiklikleri yalnız snapshot
  değiştiğinde yayınlanıyor. Tam pakette 188 testten 185'i geçti; üç opt-in donanım testi
  atlandı.

- 2026-07-25 — V1 odağı tek uzak servis/tek credential olarak ElevenLabs Scribe v2'ye
  daraltıldı; provider seçimi ve OpenAI yüzeyi kaldırılacak işler arasına alındı. Takvim
  saatinden ayrı gerçek meeting session detector, Zoom + Google Meet istemci adaptörleri,
  process-scope sistem sesi ve mute/unknown aralıklarını encode öncesi sıfırlayan
  privacy-first mikrofon gate'i ana release hattı yapıldı. Minimal/techy UI için yoğunluk,
  ikon, type, spacing ve surface token hedefleri belirlendi; görevler yeni özellik almayan
  ikincil yüzey olarak konumlandı. Güncel Xcode ile 172 testten 169'u geçti, üç opt-in
  donanım testi atlandı; Apple Development imzalı Debug build'in codesign bütünlüğü geçti.

- 2026-07-20 — AirPods gibi 24 kHz Bluetooth mikrofonlarda kaydı sıfır bayt bırakan
  `kCMSampleBufferError_RequiredParameterMissing` giderildi. Capture sample'ları artık
  retained `AudioBufferList` üzerinden güvenle sahipli PCM buffer'a kopyalanıyor; hem seviye
  göstergesi hem writer aynı yolu kullanıyor. Değişen giriş formatları 48 kHz mono PCM'e
  normalize edilip kararlı AAC/M4A'ya yazılıyor ve terminal hata yalnızca bir kez raporlanıyor.
  Gerçek AirPods ile opt-in fiziksel mikrofon testi ve toplam 172 test geçti; üç ilgisiz
  opt-in donanım testi atlandı.

- 2026-07-20 — ElevenLabs ayarlarında görülen “Provider yanıtı beklenen biçimde değildi”
  regresyonu giderildi. Değişken eksik-dosya yanıtına dayanan batch probu yerine resmi
  `POST /v1/single-use-token/realtime_scribe` sınırında ses yüklemeyen, ücretli işlem
  oluşturmayan ve `speech_to_text` kapsamını doğrulayan istek kullanılıyor; kısa ömürlü
  token saklanmıyor veya loglanmıyor. Geçersiz anahtarın production'da `401` kaldığı,
  toplam 171 testten 168'inin geçtiği ve üç opt-in donanım testinin atlandığı doğrulandı;
  Apple Development imzalı Debug build ve imza bütünlüğü de geçti.

- 2026-07-20 — Kayıt ve işleme iptali veri yaşam döngüsüne uygun hale getirildi. Aktif
  kaydı silme ile hazırlık/finalize iptali artık açık kullanıcı onayı gerektiriyor. Upload,
  transkripsiyon veya özet iptalinde worker gerçekten duruyor, çalışan kuyruk işi kalıcı
  `cancelled` koduyla tekrar denenebilir duruma alınıyor, birleşik M4A korunuyor ve ilgisiz
  kuyruk işleri yeni worker ile devam ediyor. Toplam 170 test geçti, üç opt-in donanım
  testi atlandı; Apple Development imzalı Debug build ve imza bütünlüğü doğrulandı.

- 2026-07-20 — ElevenLabs anahtar akışı restricted API key desteğiyle düzeltildi. Genel
  `/v1/models` kontrolü yerine doğrudan `/v1/speech-to-text` üzerinde dosyasız ve ücret
  üretmeyen Scribe yetki probu kullanılıyor; geçersiz veya Speech-to-Text yetkisi olmayan
  anahtarlar normalize kimlik hatası veriyor. Başarılı Keychain kaydından sonra daha önce
  authentication nedeniyle durmuş işler kimlikleri korunarak atomik biçimde yeniden
  kuyruğa alınıyor ve kullanıcıya yeniden işlenen kayıt sayısı gösteriliyor. Toplam 169
  test geçti, üç opt-in donanım testi atlandı ve Apple Development imzalı Debug build
  doğrulandı.

- 2026-07-18 — Meeting ana sonuç akışı tamamlandı: Ayarlar artık ElevenLabs Scribe v2'nin
  bulutta ve kayıt durduktan sonra çalıştığını, API anahtarının nasıl oluşturulup doğrulanarak
  Keychain'e bağlandığını açıklıyor. Transkripsiyon sonrası provider'dan bağımsız yerel
  extractive not servisi kısa özet, açık karar ve aksiyonları güvenli sorumlu/tarih alanlarıyla
  üretiyor; hata halinde transkript korunuyor. Sonuç `transcript.json` yanında atomik
  `meeting.md` olarak saklanıyor; detay ekranında notlar gösteriliyor, tam Markdown veya
  yalnızca notlar kopyalanabiliyor ve seçilen konuma `.md` export edilebiliyor. Toplam 167
  test ve Apple Development imzalı Debug build geçti; üç opt-in donanım testi normal
  regresyonda atlandı.

- 2026-07-18 — Ayarlar'a canlı AVFoundation cihaz listesi, sistem varsayılanı ve kalıcı
  mikrofon seçimi eklendi. Her kayıt seçimi yeniden çözüyor; bağlı olmayan cihaz güvenli
  fallback'e düşüyor. Kayıt sırasında mikrofon ayrılırsa aktif input fallback veya yeniden
  bağlanan seçili cihazla yapılandırılıyor; sonuç notch üzerinde erişilebilir uyarı ve
  kaynak durumu olarak gösteriliyor. Geriye uyumlu ayar saklama, seçim/fallback politikası
  ve coordinator olayları test edildi; toplam 162 test ve imzalı Debug build geçti.

- 2026-07-18 — Kompakt notch durumları kayıt > işleme/hata > toplantı > görev > boşta
  önceliğiyle test edilebilir hale getirildi; hazırlama, finalize, upload, transkripsiyon ve
  özet aşamaları görünür ilerleme taşıyor. Başarı/hata sonucu 8 saniyelik etkileşim duyarlı
  sunuma, doğru toplantı detay aksiyonuna ve güvenli kompakt dönüşe bağlandı. Panel aktif
  ekran alanına göre sınırlandı, Komut-1/2 ve ok tuşu sekme geçişleri eklendi; pencere ve
  içerik animasyonları canlı Reduce Motion ayarına uyarlandı. Toplam 154 test ve imzalı
  Debug build geçti.

- 2026-07-15 — Xcode'un yarıda kalan Swift Package Manager çalışma kopyası sonrası bellekte
  tuttuğu DynamicNotchKit çözümleme hatası, proje yeniden üretimi ve temiz IDE oturumuyla
  giderildi. Uzak `1.1.0` etiketi, Xcode workspace build'i, 144 test ve imzalı Debug build
  doğrulandı.

- 2026-07-15 — Sistem sesi `İzin Ver` ve izin hatası kurtarma aksiyonları, tap içeren geçici
  aggregate device'ı gerçekten başlatan TCC probuna bağlandı. Böylece DerivedData'dan çalışan
  development build'i elle `+` ile seçilmeden Sistem Sesini Kaydetme listesine kaydoluyor;
  ret durumunda doğru ayar paneli otomatik açılıyor. Uygulamaya özel `AudioCapture` kaydı
  sıfırlandıktan sonra gerçek izin entegrasyonu yeniden geçti; toplam 144 test ve imzalı
  Debug build doğrulandı.

- 2026-07-15 — Sistem sesi yakalama, ekran kaydı iznine bağlı ScreenCaptureKit yolundan
  `NSAudioCaptureUsageDescription` kullanan Core Audio Process Tap altyapısına taşındı.
  Audio-only izin durumu kayıt başlangıcında doğrulanıyor ve Sistem Ayarları doğru Sistem
  Sesini Kaydetme panelini açıyor. Gerçek cihazda harici sistem sesi üretilerek seviye,
  timestamp, süre, audio track ve dosya boyutu kontrollerinden geçen M4A doğrulandı; toplam
  143 test ve imzalı Debug build geçti.

- 2026-07-15 — Sistem sesi izni sonrası relaunch, eski proses kapanmadan LaunchServices'a
  yeni instance açtırmak yerine proses çıkışını bekleyen yardımcı üzerinden çalışan kesin
  bundle yolunu açacak şekilde düzeltildi. Eski çalışan proses güncel imzalı Debug build ile
  değiştirildi; relaunch/izin testleri dahil 142 test geçti.

- 2026-07-15 — Mikrofon kaynağı recording coordinator'dan bağımsız, opt-in donanım
  entegrasyon testiyle gerçek cihazda doğrulandı. Fiziksel mikrofondan üç saniyelik buffer
  akışı, normalize seviye callback'leri ve süre/track/timestamp/boyut kontrollerinden geçen
  okunabilir M4A üretildi; 140 regresyon testi ve imzalı Debug build geçti.

- 2026-07-15 — Notch olmayan ekran fallback seçimi ile DynamicNotchKit floating panelinin
  gerçek AppKit penceresinde açılma, kompakt isteğinde gizlenme ve yeniden açılma davranışı
  doğrulandı. Floating modun menü/hover ile genişleyip kapanışta gizlendiği mimariye
  kaydedildi; toplam 139 test geçti.

- 2026-07-15 — Notch açılma/kapanma prototipi yaygın 13/14/15/16 inç MacBook ekran
  geometrileri, negatif koordinatlı harici ekranlar, tekrarlı hover döngüleri ve iptal
  davranışıyla genişletildi. M4 MacBook Air `Mac16,13` üzerinde fiziksel notch algısı ve
  imzalı agent pencere yaşam döngüsü doğrulandı; toplam 137 test geçti.

- 2026-07-15 — V1 birincil akışı, sonuç süresi, geçmiş alanları, özet/dil/saklama ve
  doğrudan dağıtım kararları belgelendi. Beş adımlı izin ve bulut bilgilendirmeli onboarding,
  kalıcı tamamlanma durumu ve yeniden gösterme akışı eklendi. Genel Ayarlar artık gerçek
  takvim polling/hatırlatma yapılandırmasını, ServiceManagement login item'ını, 7/30/90 gün
  saklamayı, Finder erişimini ve toplantı/görev/kuyruk/UserDefaults/Keychain'i kapsayan güçlü
  onaylı tüm veri silmeyi yönetiyor. Toplam 132 test ve imzalı Debug build geçti.

- 2026-07-15 — Debug uygulaması kararlı Apple Development kimliği ve Hardened Runtime
  audio-input entitlement'ıyla imzalandı; sistem sesi izin dönüşü polling, açık yeniden
  isteme ve kontrollü relaunch akışıyla sağlamlaştırıldı. Görevler sekmesi aktif/arşiv
  yaşam döngüsüyle tamamlandı. Geçmiş toplantılar artık konuşmacı ayrımlı transkript,
  timestamp seek, audio player, kopyalama, Finder, retry ve güçlü silme onayı içeren detay
  penceresinde açılıyor. Toplam 128 test ve imzalı Debug build geçti.

- 2026-07-15 — ElevenLabs `scribe_v2` birincil provider adaptörü; Keychain anahtarı ve
  resmi endpoint ile doğrulanan Ayarlar akışı, multipart upload progress, diarization,
  Türkçe/otomatik dil, speaker segment parser'ı ve normalize hata matrisiyle tamamlandı.
  Kalıcı queue gerçek arka plan worker'ına bağlandı; sürümlü `transcript.json` atomik
  kaydediliyor, başarıda ham parçalar ve geçici upload gövdeleri temizleniyor. Toplam 119
  test ve Debug test build geçti.
- 2026-07-15 — Provider bağımsız transkripsiyon sözleşmesi, capability/dosya doğrulama,
  güvenli hata normalizasyonu, sınırlı idempotent retry ve state-machine upload progress
  köprüsü kuruldu. Finalize kayıtları atomik kalıcı kuyruğa alan, açılışta yarım işi
  kurtaran, paralel çift claim'i engelleyen ve hata için Tekrar Dene sunan işleme iskeleti
  tamamlandı; ham hata/toplantı içeriği tanılama kayıtlarından çıkarıldı ve uzun işler
  iptal edilebilir modellendi. Toplam 109 test ve Debug build geçti.
- 2026-07-15 — Geriye uyumlu toplantı saklama politikası ve açılışta/günlük çalışan
  otomatik temizleme eklendi; varsayılan süresiz bırakıldı, kısmi silme hataları izole
  edildi. Toplam 90 test ve Debug build geçti.
- 2026-07-15 — Provider bazında ayrıştırılmış, `ThisDeviceOnly` macOS Keychain API anahtarı
  repository'si eklendi; anahtarların ayar belgesine ve açık metin loglara girmediği hata
  sınırı ve testlerle doğrulandı. Toplam 84 test ve Debug build geçti.
- 2026-07-15 — API anahtarlarını kapsam dışında tutan sürümlü UserDefaults ayar
  repository'si, bozuk veriyi kurtarma anahtarında koruma ve reset davranışıyla eklendi;
  toplam 76 test ve Debug build ile doğrulandı.
- 2026-07-15 — Aktif ve arşivlenmiş görevleri tek sürümlü belgede atomik saklayan,
  eşzamanlı yazmaları serialize eden ve bozuk dosyayı silmeden Recovery alanına taşıyan
  task repository 70 test ve Debug build ile tamamlandı.
- 2026-07-14 — Genişletilmiş notch paneli; belirgin Toplantılar/Görevler sekmeleri,
  meeting-first durum kartı, hiyerarşik aksiyonlar, erişilebilir hedef alanları ve azaltılmış
  hareket desteğiyle yenilendi; koyu görünüm render QA'sı ve 63 testle doğrulandı.
- 2026-07-14 — Mikrofon ve sistem sesi izinlerinin canlı durum yönetimi, modern Ayarlar
  menüsü, doğru Sistem Ayarları yönlendirmesi, kayıt öncesi doğrulama ve ayrıntılı kayıt
  hata logları 63 testle tamamlandı.
- 2026-07-14 — Fiziksel notch/floating stil seçimi, imleç odaklı çoklu ekran yönlendirmesi,
  ekran değişiminde güvenli yeniden konumlandırma ve paneli açık tutan pin kontrolü 58 testle
  tamamlandı.
- 2026-07-14 — Notch için niyet gecikmeli hover açılması, panelden çıkışta toleranslı
  kapanma, kesintisiz kompakt/geniş geçiş ve daha anlamlı kompakt durum 50 testle
  tamamlandı.
- 2026-07-14 — Çökme sonrası kayıt taraması, ham kaynaklardan otomatik yeniden finalize,
  arşive geri alma ve kurtarılamayan dosyaları kullanıcıya gösterme akışı 46 testle
  tamamlandı.
- 2026-07-14 — Kalıcı toplantı arşivi, atomik ve sürümlü metadata repository'si,
  bozuk/yarım kayıt kurtarma, güvenli silme ve notch içindeki Son Kayıtlar listesi 43
  testle tamamlandı.
- 2026-07-14 — ScreenCaptureKit sistem sesi ve AVCaptureSession mikrofon kaydı gerçek
  başlat/durdur akışına bağlandı; timestamp offset'li tek M4A üretimi, kaynak göstergeleri,
  atomik metadata ve hata kurtarma davranışı 36 testle doğrulandı.
- 2026-07-14 — Domain modelleri, kayıt durum makinesi, sınıflandırılmış hata sistemi,
  güvenli çıkış ve tüm durumlara bağlı notch sunumu 16 testle tamamlandı.
- 2026-07-14 — XcodeGen tabanlı proje üretimi, DynamicNotchKit bağımlılığı, agent/menu bar
  iskeleti, temel notch paneli ve ilk AppState testleri tamamlandı.
- 2026-07-14 — Ürün vizyonu netleştirildi ve ortak geliştirme planı oluşturuldu.
