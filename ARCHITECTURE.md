# MeetingNotch Architecture

Bu belge ürün vizyonunu uygulama yapısına dönüştüren yaşayan mimari rehberdir.
Ürün kapsamının ana kaynağı `PRODUCT_PLAN.md`, araştırma notlarının kaynağı ise
`project-overview.md` dosyasıdır. Teknik detaylar ürün deneyimi gerektirdiğinde
değiştirilebilir.

## 2026-11-16 — Crenel mimarisi (güncel)

Bu bölüm aşağıdaki eski kararların takvim, görev ve yapay zekâ ile ilgili kısımlarının
yerine geçer. Ürün adı Crenel'dir; Swift modül adı, bundle kimliği, Keychain servisleri ve
`Application Support/MeetingNotch` veri klasörü, izinler ve kullanıcı verisi kaybolmasın diye
yayın hazırlığına (C6) kadar korunur. `project.yml`: `PRODUCT_NAME: Crenel`,
`PRODUCT_MODULE_NAME: MeetingNotch`, test hedefinin `TEST_HOST` değeri Crenel.app'tir.
Minimum sistem macOS 26'dır.

### Katmanlar

```text
App/
  AppDelegate          Yaşam döngüsü ve bağlantılar (incelmesi hedeflenir)
  TaskCoordinator      Görev aksiyonları, Hatırlatıcılar/yerel depo, dış değişiklikleri izleme
  DictationCoordinator Dikte motoru ↔ tercihler, agent, görevler, AppState
Domain/
  Tasks/               TaskItem (3 durum), TaskInputParser, TaskListPresentation, tekrar kuralı
  Dictation/           DictationState, tetik ayarları, DictationRefinement sözleşmesi
  Agent/               AgentPreferences, LanguageModelProvider sözleşmesi
  NotchAgenda          Geri sayım çözümü, biçimlendirme, Takvim deep link
Services/
  Dictation/           CGEventTap tetik, bellek içi ses, SpeechAnalyzer, imlece yazma
  Agent/               Foundation Models / OpenAI / Anthropic / Claude Code / Codex sağlayıcıları, DictationRefiner
Infrastructure/Persistence/Reminders/
  EventKitReminderStore, ReminderTaskMapping, RemindersTaskRepository, TaskRepositoryRouter
Features/Shared/CrenelActions  Yeni özelliklerin aksiyonları (SwiftUI environment)
```

Yeni özellik aksiyonları view init'lerine closure olarak eklenmez; kökte
`.environment(\.crenelActions, …)` ile verilir. View'lar AppKit/EventKit/Keychain çağırmaz.

### Takvim

Tek kaynak EventKit'tir; Google OAuth sağlayıcısı kaldırıldı. Google/Exchange hesapları
macOS İnternet Hesapları üzerinden gelir. Eski sürümden kalan Google refresh token'ı
“Tüm verileri sil” akışında `LegacyGoogleCalendarCleanup` ile silinir.
`EventKitMeetingProvider` iptal edilmemiş ve kullanıcının reddetmediği tüm etkinlikleri
`Meeting` olarak döndürür: `kind` (`onlineMeeting` link var, `meeting` başka katılımcı var,
`event` kişisel), `isAllDay`, `responseStatus` (`pending` = yanıt bekleyen davet),
`isSuggestion` (belgelenmemiş `EKCalendarType` 5, Siri önerileri), takvim adı/rengi ve
`eventIdentifier`. Eski JSON'lar migration gerektirmeden çözülür. Kayıt teklifi, hatırlatma
akışı ve “katıl” bildirimleri yalnız `isReminderCandidate` (toplantı, tüm gün değil, öneri
değil) öğeler içindir. Kapalı notch geri sayımı `NotchAgendaStatus.resolve` ile tüm
zamanlı öğelerden hesaplanır: 12 saatlik ufuk; süren öğe varsa sıradaki öğe başlamadan
10 dk önce devralır; çakışan süren öğelerden en son başlayan gösterilir.

### Notch motoru ve tasarım sistemi (2026-11-16, C9)

DynamicNotchKit kaldırıldı. `Features/Notch/Engine/CrenelNotchController` ekranın üst
ortasında kenarlıksız, etkinleştirmeyen tek bir `CrenelNotchPanel` (tüm Space'lerde,
`.statusBar` seviyesinde) açar. `CrenelNotchRootView` tek bir `CrenelNotchShape` çizer
(üstte dışa kıvrılan, altta yuvarlak; iki yarıçap da animasyonlu). Şeklin boyutu o anki
içerikten gelir: içerik son boyutunda belirir, şekil onu kırparak yay animasyonuyla büyür
veya küçülür; bu sayede kompakt ↔ açık geçişi notch'un kendisi biçim değiştiriyormuş gibi
okunur. Kompakt içerik `NotchFlankLayout` ile kamera yuvasının iki yanına eşit genişlikte
yerleşir; söyleyecek bir şey yoksa şekil tam donanım notch'u boyutundadır. Pencere fareyi
yalnız görünen şeklin içinde alır (`ignoresMouseEvents` global/yerel fare izleyicileriyle
güncellenir); hover bölgesi şekil + kamera yuvasıdır (notch'suz ekranda üst ortada 200 pt).
API önceki kütüphaneyle aynıdır: `expand(on:)`, `compact(on:)`, `hide()`, `isHovering`.

Tasarım dili ("gece sürüşü", 2026-11-17) `Features/Design/System/` altındadır;
`docs/DESIGN.md`'de tarif edilir, kaynağı `docs/design/crenel-prototype.html`'dir. API
başvurusu aynı klasördeki `README.md`'dir. Kaynak `Hud`'dur: `HudTokens` (sıcak mürekkep
skalası, lamba renkleri ve sıcak çekirdekleri, pencere katmanları, Geist yazı stilleri,
yarıçaplar, notch/pencere ölçüleri, hareket eğrileri), `HudSVGPath` + `HudIcons`
(prototipin sprite'ından birebir taşınan çizgi ve dolu ikonlar, rozetler, işaret),
`HudLamps` (lamba, hücreler, durum şekilleri, durum kelimeleri, uyarı lambası ikonları,
görev işaretleri), `HudButtons` (tuş butonlar, tuş kapağı, topuz, eylem satırı, konsol),
`HudComponents` (lambalı sekmeler ve ray, satırlar ve kayan hover zemini, anahtar, seçim,
alanlar, çipler, segment kontrol, mod göstergesi, çerçeve, kuyu, panel), göstergeler:
`HudSegmentDigits`, `HudGauge`, `HudInstruments` (fitil, VU, merdiven, şerit kaydedici,
tarayıcı, LED yığını, nokta matrisi, kapsüller, kapasite ölçeği, istasyonlar) ve
`HudScales` (gün cetveli, yükselen bant, radyo ölçeği, dalga formu, sistem şeması).
`CrenelTokens`/`CrenelComponents`/`CrenelIcons` eski çağrı yerleri için korunur ve
değerlerini `Hud`'dan alır. Ekranlar yeni dile aşamalı taşınıyor; o zamana dek açık notch
490 pt'dir (hedef 560), alt köşe yarıçapı açıkken 20, kapalıyken 10'dur; şekil içeriği
yayla kapsar, içerik şekilden sonra belirir.

### Kurulum ve izinler (C9)

`SetupCoordinator` tüm izinleri (`SetupCapability`: takvim, hatırlatıcılar, mikrofon,
bildirimler, sistem sesi, erişilebilirlik, girdi izleme) tek modelde okur. `request` hiç
sorulmamış izinde uygulamayı öne alıp sistem penceresini, reddedilmiş izinde ilgili Sistem
Ayarları bölmesini açar; `requestAll` sistem pencerelerini sırayla gösterip ilk manuel
izin için Ayarlar'ı açar. Ayarlar'dan gelen izinler kısa süreli yoklamayla yakalanır.
`onGranted` izni ilgili özelliğe bağlar: takvim → `MeetingMonitor.requestAccess`,
hatırlatıcılar → `TaskCoordinator.activate(preferReminders: true)`. Hardened Runtime
altında EventKit için `com.apple.security.personal-information.calendars` entitlement'ı
zorunludur; yokken izin penceresi hiç çıkmadan reddedilir.

### Kapalı notch önceliği

`NotchStatusResolver.compactStatus`: dikte (geçici, en yüksek) > toplantı akışı (kayıt,
işleme, tamamlandı, hata, hatırlatma) > yaklaşan/süren takvim öğesi (yakınsa veya süren
toplantıysa) > üzerinde çalışılan görev > sakin takvim öğesi > açık görev sayısı > boş.

### Görevler

`TaskStatus`: `open` (Yapılacak), `inProgress` (Devam ediyor), `blocked` (Bloke),
`completed` (Bitti); eski `backlog`/`todo` değerleri Yapılacak olarak çözülür. "Başlatma"
aksiyonu yoktur; durum, görev halkasından açılan seçiciden seçilir ve bir görevin durumunu
değiştirmek başka görevi değiştirmez. Satıra dokunmak satır içi metin düzenleme yerine
görev kartını açar (başlık, durum, tarih, öncelik, not). Bloke bilgisi Hatırlatıcılar'da
karşılığı olmadığından yan dosyada (`isBlocked`) tutulur.
Tamamlama arşivlemez: tamamlanan görev gün bitene kadar “Bugün tamamlananlar”da kalır,
sonra Geçmiş'e geçer; `archive` yalnız tamamlanmış görevi listeden erken kaldırmak için
kullanıcı aksiyonudur. Bölümler (`TaskListPresentation`) kullanıcı seçimi değildir: durum
ve son tarihten türetilir. Birden fazla görev aynı anda “devam ediyor” olabilir; kapalı notch en son başlatılanı gösterir. Tekrarlayan
görev tamamlanınca tamamlanmış bir geçmiş kaydı oluşur ve görev sonraki tarihe ilerler.

Depo: `TaskRepositoryRouter` tercihe ve izne göre Apple Hatırlatıcılar ya da yerel JSON
seçer; izin yoksa sessizce yerelde çalışır, UI bağlantı teklif eder. Hatırlatıcılar'da
uygulamaya ait “Crenel” listesi kullanılır. Başlık, not, son tarih (saatli/gün düzeyi),
öncelik (EventKit 1/5/9), tekrar kuralı, tamamlandı ve alarm (saatli görevlerde) Hatırlatıcılar'da;
görev kimliği, üzerinde çalışılıyor, sıralama, arşiv ve toplantı kaynağı
`Tasks/reminders-sidecar.json` yan dosyasında, hatırlatıcı kimliğine bağlı tutulur.
Dışarıda (iPhone, Siri) oluşturulan hatırlatıcı, kimliğinden türetilen kararlı UUID alır.
Toplantı kaynağı ayrıca `crenel://meeting/<id>` URL'si olarak yazılır. Yerel görevler
ilk bağlantıda bir defa taşınır (açık + son 30 gün tamamlanan); yerel dosya yedek olarak
değiştirilmeden kalır. `EKEventStoreChanged` 250 ms birleştirilerek yeniden yükleme yapar.
Akıllı giriş `TaskInputParser` kurallı, deterministik ve yerel çalışır (Türkçe/İngilizce);
öneriler yazarken gösterilir, Tab ile kabul edilir, Enter düz kaydeder.

### Dikte

Tetik `CGEventTap` (yalnız dinler; Input Monitoring izni) ile Fn/sağ ⌥/sağ ⌘ basılı tut veya
aç-kapa; Esc iptal. Ses `AVAudioEngine` ile bellekte kalır, diske yazılmaz.
`SpeechAnalyzer` + `SpeechTranscriber` (yoksa `DictationTranscriber`) cihazda çalışır;
model `AssetInventory` ile indirilir. Metin önce Accessibility ile seçili metin alanına
yazılır; olmazsa pano + ⌘V ve pano geri yüklenir; odakta alan yoksa panoda bırakılır.
Güvenli (şifre) alanlara asla yazılmaz. Geçmiş yalnız bellekte tutulur (son 20).
Toplantı kaydı sürerken dikte dinlemeye başlarsa toplantı mikrofon gate'i kapatılır ve
dikte bitince geri açılır; dikte sesi toplantı kaydına girmez.

### Agent

`LanguageModelProvider`: cihazdaki Apple Foundation Models (varsayılan), OpenAI (mevcut
Keychain anahtarı) veya Anthropic (ayrı Keychain servisi). `DictationRefiner` önce
deterministik temizlik ve niyet tespiti yapar (“görev ekle …” → görev), sonra modelle
temizler. Transkript sınırlandırılmış veri olarak verilir; model araç kullanamaz ve
transkriptteki talimatları yürütmez. Komut modu bilinçli istisnadır: seçili metin varken
kullanıcının sözlü komutu talimattır, seçili metin yine veri olarak sınırlandırılır. Süre
bütçesi (cihaz 2.5 sn, bulut 4 sn), aşırı uzun/alakasız çıktı veya hata durumunda
deterministik sonuca düşülür; komut başarısızsa seçili metin değiştirilmez.

Claude Code ve Codex sağlayıcıları (`CLIAgentProvider`) kullanıcının bu Mac'te oturum açmış
`claude` / `codex` komut satırı aracını API anahtarı olmadan çalıştırır. Araç bulunamazsa
yaygın kurulum klasörlerine, en son giriş kabuğuna bakılır. Her istek boş bir geçici klasörde,
araçlar kapalı (`--tools ""`, Codex için salt okunur sandbox) ve oturum kaydetmeden çalışır;
metin standart girdiden gider, çıktı ve hata metni hiçbir yerde gösterilmez veya kaydedilmez.
Her istek bir süreç başlattığı için (saniyeler) dikte bu sağlayıcıları kullanmaz,
deterministik temizlikle devam eder; toplantı özeti büyük bağlam profiliyle çalışır.

Toplantı aksiyon maddeleri yalnızca kaydı yapan kişiye aittir (`MeetingOwner`). Özet
istemine sahip satırı (macOS hesap adı, yerel transkriptte mikrofon izi “You”) eklenir ve
model yalnızca onun görevlerini döndürür; `MeetingSummaryRouter` her servisten sonra başka
bir kişiye ya da adı verilmiş başka bir konuşmacıya açıkça atanmış maddeleri ayıklar.
Sahibi belirsiz maddeler (ad yok, “Speaker 2” gibi etiket) korunur. Ek konuşmacı tanıma
yapılmaz.

## Masaüstü ve notch birlikte çalışma sözleşmesi

Açılışta yalnız notch başlatılır; masaüstü pencere otomatik restore edilmez.
`DesktopWindowController` kullanıcı aksiyonuyla tek, yeniden kullanılabilir NSWindow
oluşturur. Masaüstü açıkken activation policy regular, kapatıldığında accessory olur;
pencere kapanması kayıt veya worker’ları durdurmaz. Menü, notch düğmesi ve uygulamanın
tekrar açılması aynı pencereye yönlenir. Ayarlar bağımsız Settings scene’i yerine
masaüstünde kategorili sunulur; bağlamsal bağlantılar ilgili kategoriye gider.

Masaüstü ve notch aynı AppState/repository/action katmanını kullanır. Masaüstünün toplantı
seçimi ve detay yükleme durumu ayrıdır; geç kalan async sonuçlar yeni seçimi değiştiremez.
Ses oynatma detaydan ayrılınca veya masaüstü kapanınca duraklar, ses kaydı devam eder.

## UX sadeleştirmesi — 25 Eylül 2026, ikinci tur

Bu bölüm önceki UI turundaki ilgili kararların yerini alır. Masaüstü arka planı
nötr #171717, sidebar #131313 ve ortak kart yüzeyi #202020'dir.
Parlaklık kullanıcı isteğiyle koyulaştırılmıştır; ilk siyaha yakın temaya küçük bir yumuşatma uygulanır.
Notch'un MainPanel siyah paleti korunur. Masaüstü ana eylemleri environment üzerinden
nötr gri 0.82 kullanır; ana metin tam beyaz yerine 0.90 gridir.
Kullanıcı düzeltmesi: yüzeylere mavi alt ton eklenmez.

DesktopWindowController 1120×680 içerik boyutuyla açılır, 960×540'a küçültülebilir.
NSHostingView.sizingOptions boş bırakılır: SwiftUI ideal/minimum içerik ölçüsü pencereyi
kilitlemez. Eski autosave boyutu yüklenmez; aynı oturumda pencere yeniden kullanılır.

Notch sekme seçiminde tüm içerik animasyona alınmaz. ScrollView kimliği korunur,
sekmeye bağlı root id kaldırılmıştır. İçerik transaction'ı layout animasyonunu kapatır;
seçim kapsülünün animasyonu başlıkta kalır. Göstergeler gizlidir.

Toplantı aksiyonları tek kompakt liste halinde ilk altı satırla gösterilir. Kalanlar
kullanıcı eylemiyle açılır/kapanır; kaynak oynatma ve göreve aktarma satır içindedir.
Ayar servisleri uyarlanabilir sütunlara yerleşir; izinler tek satır durum/eylemdir.
Sürekli yardım paragrafları kaldırılır. Ücret, izin, sesin kayda dahil edilmesi ve geri
alınamaz silme bilgileri korunur; ikincil kullanım açıklamaları tooltip'e taşınır.

## 2026-09-25 arayüz ve hareket sözleşmesi

Ortak yüzeyler, tipografi, durum renkleri, düğmeler, satırlar, boş durumlar ve geri
bildirimler `MeetingNotchTheme` katmanından gelir. İkincil metin RGB 163/255,
başarı rengi RGB 95/216/151; workspace/sidebar yüzeyleri sırasıyla 0.035/0.055 gri.
Özel düğme ve sekmeler en az 40 pt, metin alanları en az 44 pt yüksekliğindedir.
Hover, klavye odağı, disabled ve basış geri bildirimi ortak modifier'lardadır.
Alan odağı çağıran view'ın FocusState değeriyle açıkça bağlanır.

`MeetingNotchMotion` etkileşim (0.14 sn) ve gezinme (0.24 sn, zıplamasız) geçişlerini
merkezileştirir. Yeni hareketler Reduce Motion durumunda kapanır. Notch sekmesi
seçim kapsülü eşleşen geometriyle, kompakt mikrofon durumu opacity ile geçiş yapar.
Ses seviyesi animasyonu yalnız seviye değişimine bağlıdır; tüm panel sürekli animasyon almaz.

600 pt notch yanında 360 pt dar görünüm doğrulanır; 440 pt altında sekmeler ikonla,
kayıt içerikleri dikey yerleşimle sunulur. Aksiyonlar ViewThatFits ile alt satıra geçer.
Masaüstü minimum genişlikte test edilir; ayarlar ve onboarding uzun içeriklerini kaydırır.
İzin açıklamaları ile aksiyonlar ayrı satırdır. Transkript LazyVStack olarak kalır;
oynatıcı zamanı yalnız oynatıcı alt görünümünü günceller. Zaman/kaynak düğmesi sesi
seçilen andan oynatır. Slider sürüklemesi yerel önizleme, bırakıldığında seek uygular;
klavye değişiklikleri doğrudan seek yapar. Kopyalama bildirimi tekrarlanan tıklamalarda
iptal edilebilir bir task ile sıfırlanır.

Sentetik ekran matrisi `NotchPresentationTests` ve `DesktopWorkspaceTests` içindedir.
İnceleme kapsamı ve sınırları: `QA/UI_POLISH_AUDIT.md`.

## 2026-09-14 hibrit mimari kararı

Bu bölüm aşağıdaki eski tek servis/extractive-only sözleşmelerini günceller.
Ses yalnız ElevenLabs'e, özet için konuşmacı/zaman/segment kimlikli metin yalnız OpenAI'ye
gönderilir. OpenAI key ayrı Keychain service'inde tutulur; eski ElevenLabs key değişmez.
Transkript özetten ÖNCE kalıcılaştırılır; retry mevcut transkripti kullanır. OpenAI
bağlantısı yoksa transkript kullanılabilir kalır, detayda özet bağlantı durumu açıklanır.
AI çıktıları JSON şeması ve yerel segment/konuşmacı/tarih doğrulamasından geçer. Transkript
metni talimat olarak yürütülmez; modelin araç erişimi yoktur. Kullanıcı kişi eşleştirmeleri
kalıcıdır. Görev aktarımı deterministik kaynak kimliğiyle yinelenmez.
Meeting UI polling ses IO değişikliklerinden bağımsızdır; okunamayan/kaybolan süreç
sinyali önceki açık mikrofon gate'ini koruyamaz. Takvim bağlantısı ile boş gün farklı UI
durumlarıdır. Yerel bildirimler yalnız kullanıcı izin aksiyonundan sonra zamanlanır.
Takvim router’ı EventKit veya Google Calendar REST sağlayıcısını seçer. Google PKCE
Desktop OAuth bağlantısı yayıncı client kimliğiyle yapılandırılır; refresh token ayrı
Keychain service’inde saklanır. Kalender seçimleri ve bağlantı tercihi AppPreferences’ta
kalıcıdır. Yeni isteğe bağlı model alanları eski JSON belgelerini migration gerektirmeden
okur. Kayıt tamamlandı durumu ile `summaryNeedsAttention` birbirinden ayrıdır.

## Proje üretimi

- Xcode projesinin tek yapılandırma kaynağı `project.yml` dosyasıdır.
- `MeetingNotch.xcodeproj/project.pbxproj` elle düzenlenmez.
- Proje değişikliklerinden sonra kök dizinde `xcodegen generate` çalıştırılır.
- DynamicNotchKit sürümü `project.yml` içinde sabit bir alt sınırla tanımlanır.
- Minimum sistem sürümü macOS 26'dır (Crenel kararı, 2026-11-16).
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
    Calendar/       EventKit sorguları ve planlanmış meeting bağlamı
    Meeting/        İstemci/process sinyalleri, session detector ve mute adapter'ları
    Transcription/  Tek ElevenLabs servisi ve test edilebilir HTTP sınırı
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
- ElevenLabs response modelleri servis sınırının dışına çıkmaz.
- Domain katmanı DynamicNotchKit, AppKit ve ağ istemcilerinden bağımsız kalır.
- Ana UI durumu `AppState` üzerinden gözlemlenir; gerçek iş servisler tarafından yapılır.
- Uzun işler iptal edilebilir `async` operasyonlar olarak tasarlanır.
- Tek ElevenLabs API anahtarı yalnızca Keychain'de tutulur.
- Meeting client adapter'ları Accessibility UI metinlerini domain'e taşımaz; yalnız
  normalize kanıt ve `open/closed/unknown` mute durumu üretir.
- Algılama belirsizliği UI'da kesin duruma yükseltilmez. Mikrofon gate'i belirsizlikte
  fail-closed davranır.

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

## Toplantı session algılama sınırı

Takvim etkinliği yalnız planlanmış bağlamdır; gerçek çağrı yaşam döngüsünün kanıtı değildir.
Session detector dört yerel kaynaktan normalize kanıt toplar:

- EventKit meeting kimliği, URL'si, başlangıç/bitiş aralığı.
- MeetingNotch `Katıl` aksiyonunun açtığı URL ve ardından görülen process/window.
- Core Audio process nesnesinin bundle ID/PID ve `isRunningInput` / `isRunningOutput`
  değişiklikleri.
- Desteklenen istemciye ait Accessibility adapter'ının meeting window, call controls ve
  mute control durumu.

`MeetingSession` domain modeli `scheduled`, `candidate`, `ready`, `recording`,
`endSuspected`, `ended` durumlarını; `unknown`, `probable`, `confirmed` güven seviyesini ve
kanıt setini taşır. Kurallar deterministic ve fixture-test edilebilir olur. Tek başına
takvim saati, process'in açık olması veya uzun sessizlik `confirmed` başlangıç/bitiş
üretmez.

`CoreAudioProcessMonitor`, HAL process object listesini bundle ID/PID ile normalize eder ve
`isRunningInput` / `isRunningOutput` snapshot'ını yalnız değiştiğinde yayınlar. Polling
yaşam döngüsü UI'dan bağımsızdır; session coordinator yalnız desteklenen bundle ID'leri
kanıta dönüştürür. Bu sinyal mute durumu olarak yorumlanmaz.

`AccessibilityMeetingClientAdapter`, Core Audio snapshot'ındaki bundle ID/PID'yi Zoom
Workplace veya Google Meet/Chrome istemcisine eşler. Sistem güveni yoksa ağaç okunmaz;
adapter `accessibilityPermissionRequired`, görünmeyen UI kanıtı ve `unknown` mikrofon
durumuyla fail-closed snapshot üretir. İzin istemi yalnız kullanıcı aksiyonuyla
`promptForAccessibility` açıldığında tetiklenir; desteklenmeyen process izin istemez.

İzin varken Accessibility ağacı derinlik ve node sayısı sınırıyla bellekte taranır. Ham
başlık, açıklama, URL veya control metni loglanmaz ve domain'e taşınmaz; adapter yalnız
`meetingWindowPresent`, `callControlsPresent` ve `open/closed/unknown` normalize sonucunu
yayınlar. Zoom meeting/end/microphone kontrolleri istemci penceresinde, Google Meet ise
`meet.google.com`/Google Meet bağlamı bulunan Chrome penceresinde aranır. Sıradan Chrome
penceresi veya yalnız “mute” benzeri ilgisiz bir web kontrolü meeting kanıtı sayılmaz.

V1'in zorunlu kalite kapıları Zoom Workplace native istemcisi ve Google Meet/Chrome'dur.
Her ikisi için gerçek başlangıç/bitiş, call controls ve mute durumu normalize adapter
kanıtlarıyla üretilir. Chrome process'i birden fazla sekmenin sesini taşıyabildiğinden,
Google Meet kaydı toplantı sekmesi dışındaki sesi dışladığını canary-audio testiyle
kanıtlamadan global veya process-wide kayda sessizce düşmez. İzolasyon kaybolursa kayıt
fail-closed olur ve UI güvenli fallback'i açıkça gösterir. Diğer istemciler manuel kayıt
moduna düşer; UI otomatik algılama iddiasında bulunmaz.

Google Meet system audio izolasyonu Chrome'un process sınırından çıkarılamaz. Bu istemcide
tek güvenli production yolu ayrı Manifest V3 extension'dır: kullanıcı aktif Meet sekmesinde
extension action'ı açar; popup seçili sekme sesinin yerel uygulamada nasıl işleneceğini ve
kayıt sonrası ElevenLabs sınırını yakalama öncesi açıkça gösterir. Kullanıcının `Meet sekmesini
bağla` onayıyla `chrome.tabCapture.getMediaStreamId()` yalnız o sekme için stream üretir ve
offscreen document stream'i tüketirken sesi tekrar yerel çıkışa bağlar. Extension ID'si
sabittir; başka origin, kullanıcı gesture'ı olmayan başlangıç veya native bridge kaybı
capture başlatmaz ya da anında fail-closed durdurur. Store ZIP'i yalnız runtime dosyalarını
taşır; ikonlar ve checksum deterministik paket betiğiyle üretilir. Web Store item ID'si native
host allowlist'iyle eşleşmeden production yayını yapılmaz.

Offscreen audio worklet 48 kHz hedefli küçük PCM S16LE frame'leri sıra numarası ve rastgele
session UUID ile üretir. Frame'ler yalnız sabit origin allowlist'li Chrome native messaging
host'una gider. Helper mesaj boyutu, sample rate, kanal, sıra, session nonce ve backpressure
kurallarını doğruladıktan sonra uygulamanın kullanıcıya özel IPC kanalına aktarır; extension
veya helper tek başına kalıcı toplantı dosyası seçemez. Meeting URL'sinin path'i, başlık,
DOM metni ve ses içeriği loglanmaz. Chrome Web Store kurulumu ve action tıklaması onboarding
üzerinde açık bir Google Meet önkoşuludur.

Native sınır iki ayrı doğrulamadan oluşur. `MeetingNotchBrowserAudioHost`, Chrome'un 4-byte
little-endian framed stdio mesajını sabit extension origin, session UUID, sequence, PCM boyutu,
sample rate ve kanal sayısıyla doğrular. Doğrulanmış event, yalnız o kullanıcı için `0700`
geçici dizin ve `0600` Unix socket üzerinden `BrowserAudioIPCServer`'a taşınır; socket yazımı
`SO_NOSIGPIPE` ile uygulama sürecini kopuk peer'dan korur. `BrowserAudioStreamBroker` session
ve sequence'i yeniden doğrular; `BrowserAudioCaptureSource` yalnız aktif broker session'ında
PCM'i 48 kHz mono AAC M4A'ya dönüştürür. Host/IPC/tab kopması `.pipelineStalled` üretip mevcut
güvenli-finalize yolunu tetikler. Uygulama paketi helper'ı `Contents/Library/LaunchServices`
altında taşır ve Chrome native-host manifestini yalnız sabit origin ile kullanıcı hesabına
kurar. UI `kullanılamıyor / sekme bekleniyor / bağlı / kayıt hattına bağlı` durumunu gösterir.

Algılama kaydı habersiz başlatmaz. `confirmed` başlangıç kayıt teklifini görünür yapar.
Kayıt sürerken `confirmed` bitiş iptal edilebilir kısa geri sayım başlatır; `probable`
bitiş yalnız kullanıcıya sorulur. Manuel başlat/durdur her durumda kullanılabilir kalır.

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
- Geniş panel aktif ekranın görünür alanı elverdiğinde toplantı/görev kökü ve uzun transkript
  taşıyan notch içi detail drill-down'ında değişmeyen 600 piksel genişlik kullanır. İçerik
  alanı 600 piksele kadar doğal yüksekliğinde kalır; yalnız bu üst sınırı
  aştığında kaydırılır. Daha küçük ekranlarda görünür alan sınırı aynı davranışın üst
  yüksekliği olur. Sekmeler ok tuşları ve Komut-1/Komut-2 ile değiştirilebilir.
- DynamicNotchKit açılma, kapanma ve kompakt/geniş dönüşümleri uygulamanın hareket profiliyle
  yapılandırılır. macOS Reduce Motion değişikliği canlı izlenir ve etkin olduğunda hem panel
  içi hem pencere geçişleri algılanabilir hareket üretmeyecek kadar kısaltılır.
- 2026-08-19 Figma yönü kök panel ve detail'da sabit 600 piksel genişlik; 12 piksel dış yatay
  padding, hover yüzeyli liste satırlarında 8 piksel iç yatay padding, 20/12/10/4 piksel
  bölüm-içerik-satır ritmi, 24/22/16 piksel radius hiyerarşisi ve 12–20 pt SF Pro Display type
  scale kullanır. Satır ikonları 20 piksel grid'e oturur; görünen kontrol kompakt kalsa da
  genişletilmiş content shape erişilebilirliği korur.
- Ana panel saf siyah zemin, `#121212` yüzey ve yalnız durum rengi vurgusuyla çalışır;
  danger `#FE4B4B`, warning `#FEC84B`, cyan `#14D4FF`, success `#14FF2B` kullanılır.
  Kayıt kartının mikrofon gate bölümü `#261E0B` ile ayrılır. Kompakt görünüm session durumu,
  kayıt süresi ve meeting mic gate'ini tek bakışta taşır.
- Figma ana paneli açık sistem temasından bağımsız siyah tasarlandığı için fiziksel notch,
  floating expanded ve compact içerik koyu `ColorScheme` kullanır. Sekme layout'u seçili
  durum animasyonunda yeniden ölçülmez; iki sekme her frame'de görünür kalır, yalnız renk ve
  yüzey durumu değişir.
- Aynı Figma sistemi yalnız ana panelle sınırlı değildir: meeting detail, kayıt yaşam döngüsü
  ve hata/kurtarma yüzeyleri, compact notch, görev arşivi/düzenleyicisi, onboarding, Ayarlar
  ve Chrome uzantısı popup'ı siyah tuval, `#121212` kart, 20/12/10 piksel boşluk,
  22/16 piksel radius ve 12–20 pt SF Pro ölçeğini paylaşır. Ayarlar 600×760 kaydırılabilir,
  onboarding 600×500 adımlı yüzeydir; notch içeriği ise 600 piksel üst sınıra kadar doğal
  yüksekliğinde kalır.
- Figma'dan dışa aktarılan 19 SVG ikon asset catalog'da `Figma*` adlarıyla tutulur ve aynı
  export'lardan gerekli dört ikon Chrome popup paketine de eklenir. Uygulama içi görünür
  durum/aksiyon ikonlarında bu set tercih edilir; Finder, kaydet, sistem ayarı ve native menü
  komutları gibi Figma karşılığı bulunmayan platform işlemleri macOS SF Symbols kullanır.
  Etkileşimli kontroller en az 40 piksel hedef, basışta 0.96 ölçek ve Reduce Motion uyumlu
  kısa geçiş kullanır.

## Veri yaklaşımı

- V1'de veritabanı yoktur; toplantı ve görevler Application Support altında saklanır.
- Bir toplantı belgesi kararlı kimlik, başlık, başlangıç/bitiş, kaynak takvim kimliği ve URL,
  işlem durumu, normalize hata kodu ve ilişkili dosya adlarını taşır. Normalize
  transkript konuşmacı ve zaman damgalı segmentleri; özet çıktısı genel özet, kararlar ve
  sorumlu/tarih bilgisi uydurulmadan çıkarılan aksiyon maddelerini taşır.
- Yazımlar atomik yapılır ve yarım kayıtlar Recovery alanında korunur.
- Her toplantı kararlı bir UUID ile ses, metadata ve Markdown çıktısını ilişkilendirir.
- Başarılı işleme, normalize `transcript.json` yanında kullanıcı tarafından doğrudan
  açılabilen `meeting.md` üretir. Markdown toplantı metadata'sı, kısa notlar, kararlar,
  aksiyonlar ve konuşmacı-zaman damgalı tam transkripti aynı UUID altında taşır.
- Repository formatları şema sürümü taşır.
- Tek ElevenLabs API anahtarı generic-password öğesi olarak yalnız macOS Keychain'deki
  `elevenlabs-api-key` hesabında ve `ThisDeviceOnly` erişilebilirlik sınıfında tutulur. Eski
  provider kimlikli `elevenLabs` hesabı yeni öğe başarıyla yazıldıktan sonra kayıpsız
  migrate edilir ve eski öğe silinir.
- API anahtarları tercih modellerine ve hata değerlerine eklenmez; serbest biçimli hata
  ayrıntıları OSLog'a hiç gönderilmez. Tanılama yalnızca sabit operasyon kodu, hata tipi,
  akış fazı ve hassas olmayan sayaçları taşır; kalıcı işleme hataları da serbest provider
  mesajı yerine normalize edilmiş hata kodu saklar. V1'de analytics SDK'sı yoktur.
- Fiziksel session kabulünde kullanılan `meeting-session` OSLog kategorisi yalnız rastgele
  session UUID'si, normalize state/confidence/client/microphone ve evidence türlerini taşır.
  PID, takvim kimliği, meeting URL'si, pencere/rol metni veya görüşme içeriği loglanmaz.
  QA collector bu kayıtları geçici NDJSON kanıtına çevirir; production analytics veya kalıcı
  kullanıcı profili oluşturmaz.
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
- Kuyruk worker'ına tek `TranscriptionServicing` bağımlılığı enjekte edilir; production
  implementasyonu ElevenLabs'tir ve protokol yalnız test doubles için korunur. Worker meeting
  repository'den birleşik M4A'yı alır ve aynı anda yalnızca claim edilmiş işi yürütür.
  Normalize sonuç önce sürümlü
  `transcript.json`, sonra tamamlandı durumu olarak atomik yazılır; bu sıra force-quit
  sonrasında aynı idempotency anahtarıyla güvenli yeniden işlemeye izin verir. Başarıdan
  sonra ayrı ham kaynak parçaları silinir, birleşik kayıt korunur.
- Kullanıcı kayıt hazırlığını veya henüz kalıcı olmayan aktif kaydı yalnızca açık onaydan
  sonra iptal edebilir; bu yol geçici parçaları siler. Upload/transkripsiyon/özet iptali ise
  kalıcı birleşik sesi silmez, çalışan işi `cancelled` hata koduyla tekrar denenebilir halde
  tutar ve kuyruktaki ilgisiz toplantıların işlenmesine yeni worker göreviyle devam eder.
- Transkripsiyon tamamlandığında yerel extractive özet servisi yalnızca transkriptte açıkça
  bulunan cümlelerden kısa özet, karar ve aksiyon adayları çıkarır. Ayrı bir uzak model veya
  ikinci API anahtarı kullanmaz; özetleme hatası transkriptin kaydedilmesini engellemez.
- Görevler `backlog`, `todo`, `inProgress`, `completed` ve `blocked` durumlarını; durumdan
  bağımsız `archivedAt` zaman damgasını tek sürümlü `Tasks/tasks.json` belgesinde tutar.
  `completed` geçişi aynı actor yazımında otomatik arşivler; manuel arşivleme mevcut durumu
  değiştirmez. Tamamlanmış bir görevi aktife geri almak onu `todo` durumuna döndürür. Şema
  v1'deki `completedAt` kayıtları `completed + archivedAt` olarak kayıpsız migrate edilir.
  V1 görünüm sırası oluşturulma zamanıdır; manuel reordering yoktur.

## İzin yaşam döngüsü

- Takvim entegrasyonu doğrudan Google/Gmail OAuth'u kullanmaz. EventKit, yalnız kullanıcının
  macOS İnternet Hesapları'na ekleyip Takvim için etkinleştirdiği iCloud, Google, Exchange,
  CalDAV ve yerel kaynakları okur; MeetingNotch Gmail gelen kutusuna veya e-posta içeriğine
  erişmez. Ayarlar kaynak türü ve takvim sayısını gösterir fakat hesap adı/e-posta adresini
  domain'e, loglara veya kalıcı dosyalara taşımaz.
- Yetkili EventKit sorgusu son 1 saat ile sonraki 24 saati kapsar; okunabilir takvim,
  taranan etkinlik, eşleşen çevrim içi toplantı ve son yenileme zamanını tek bağlantı sağlık
  snapshot'ı olarak yayınlar. İzin reddi, sorgu hatası ve Google hesabının macOS'ta görünmemesi
  farklı düzeltme aksiyonları üretir. Hızlı EventKit/timezone/poll tetikleri devam eden sorguya
  ek bir takip yenilemesi olarak coalesce edilir; eski sorgu entegrasyon kapatıldıktan sonra
  UI'a veri yayınlayamaz.
- Calendar URL matcher desteklenen doğrudan HTTPS linklerine ek olarak şemasız linkleri,
  HTML entity/percent encoding'i ve yalnız bilinen Google/Outlook redirect host'larındaki
  iç içe toplantı URL'lerini normalize eder. Eşleşen occurrence kimliği deterministik UUID
  üretir; yinelenen takvim kopyaları başlık/zaman/URL anahtarıyla tek toplantıya iner. En yakın
  toplantı ana durum yüzeyinde, sonraki üç çakışan/arka arkaya toplantı ince listede gösterilir.
- Mikrofon durumu AVFoundation sınırından okunur ve kayıt başlamadan doğrulanır. Sistem
  sesinin audio-only TCC izni için güvenilir bir preflight API bulunmadığından UI bu durumu
  `verificationRequired` olarak taşır; kesin karar Core Audio Process Tap hazırlanırken
  sistem tarafından verilir.
- Mevcut sistem sesi altyapısı izin probunda `NSAudioCaptureUsageDescription` ile global,
  private ve unmuted Core Audio Process Tap kullanabilir. Gerçek desteklenen toplantı
  kaydında aynı altyapı yalnız doğrulanmış meeting process nesnelerini içeren private tap
  kurar; sessizce global capture'a düşmez. Tap özel aggregate device üzerinden Objective-C++
  realtime callback'ine bağlanır ve M4A/AAC dosyasına yazılır. Akış ekran görüntüsü veya
  ekran kaydı iznine bağlı değildir.
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
- Accessibility izni yalnız desteklenen istemcide meeting window/call control ve mute
  durumunu yerel olarak okumak için istenir. Ret veya sonradan kaldırılma kayıt erişimini
  kapatmaz; session detector düşük güvene, microphone gate ise `unknown → closed` durumuna
  düşer ve manuel fallback'i görünür yapar.

## Mikrofon cihaz yaşam döngüsü

- Kullanılabilir ses girişleri AVFoundation discovery session ile listelenir; sistem
  varsayılanı ayrıca işaretlenir. Bağlanma ve ayrılma bildirimleri uygulama yaşamı boyunca
  izlenir ve Ayarlar listesi açıkken de canlı güncellenir.
- AVFoundation cihaz keşfi CMIO extension/provider zincirini de uyandırabildiği için ana
  actor üzerinde çalıştırılmaz. Keşif utility-priority detached işte normalize
  `MicrophoneDevice` değerlerine dönüştürülür; yalnız sonuç ana actor üzerinden yayınlanır.
  CMIO provider'ı gecikir veya geçersiz bağlantı döndürürse notch UI ve toplantı detayı
  bekletilmez. Audio discovery için yalnız `.microphone` device type kullanılır; daha geniş
  `.external` taraması eklenmez. AVFoundation bu dar kapsamda da CMIO provider'larını
  başlatabildiğinden sistem logları tamamen kaybolmayabilir; güvenlik sınırı UI izolasyonudur.
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
- Mikrofon sample buffer'ları, AirPods gibi 24 kHz Bluetooth girişleri ve kayıt ortasındaki
  format değişimleri doğrudan M4A writer'a verilmeden önce 48 kHz mono float PCM'e normalize
  edilir. AAC dosyası bu kararlı client formatından üretilir; ilk dönüştürme/yazma hatası
  kaynağa ait terminal hata olarak tutulur ve sonraki her buffer için yinelenen log üretilmez.

## Toplantı sesi ve mikrofon gate sınırı

- Mevcut global system tap V1 hedefinde gerçek toplantı kaydı için kullanılmaz. Zoom meeting
  session bir bundle ID/PID setine çözüldüğünde private `CATapDescription` yalnız bu process
  nesnelerinin output sesini yakalar. Google Meet system audio yalnız yukarıdaki extension
  tab stream'inden gelir. MeetingNotch kendi sesi ve diğer uygulama/Chrome sekmesi sesleri
  capture dışında kalır.
- Meeting process'i restart olur veya child process değiştirirse session detector yeni PID
  setini doğrular. Yeniden bağlama sırasında uygulama sessizce global tap'e düşmez; kullanıcı
  uyarılır ve gerekiyorsa kayıt güvenli biçimde finalize edilir.
- `kAudioProcessPropertyIsRunningInput`, input stream aktivitesini bildirir fakat istemci
  mute durumunu kanıtlamaz. Gate'i tek başına açması yasaktır.
- `MeetingMicrophoneGate` `open`, `closed`, `unknown` durumlarını taşır ve her kayıt
  `closed` başlar. Desteklenen Accessibility adapter'ından doğrulanmış unmute veya kullanıcının
  görünür manuel kontrolü `open` üretebilir.
- `closed` ve `unknown` aralıklarında mikrofon PCM frame'leri encode edilmeden önce zero
  fill edilir. Frame sayısı ve timestamp korunur; ortak timeline kaymaz. Gate sınırında kısa
  fade click'i önler; konuşma pre-roll'u tutulmaz.
- Gate geçişleri session metadata'sına timestamp, normalize source ve confidence ile
  yazılır. UI metni, konuşma içeriği veya Accessibility ağacı kalıcılaştırılmaz.
- Adapter/Accessibility kaybı anında `unknown`, ardından fail-closed davranış üretir.
  Notch kayıt boyunca `Açık/Kapalı/Bilinmiyor` durumunu ve manuel shortcut'ı görünür tutar.
- Privacy testi mute aralığında söylenen benzersiz canary phrase'i ham mic, birleşik M4A ve
  transkriptte arar. Bu test geçmeden bir client adapter'ı “desteklenen” sayılamaz.

## Sonuç ve görev yüzeyleri

- `AppDelegate` repository işlemlerini koordine eder; notch view'ları doğrudan dosya
  sistemine erişmez. `AppState`, aktif/arşiv görevlerini, durum başına aktif sayıları ve
  kompakt rozet için toplam aktif sayıyı yayınlar.
- Toplantı satırı ayrı pencere açmaz; `AppDelegate` repository'den normalize transcript,
  kalıcı Markdown ve birleşik audio URL'sini yükleyip `AppState` üzerindeki geçici detail
  içeriğine taşır. Geniş notch paneli sekmelerden toplantı detail drill-down'ına akışkan
  geçer; geri aksiyonu kullanıcıyı aynı panelde geçmiş listesine döndürür.
- Detail üst satırında düz metin ve Markdown pano aksiyonları doğrudan erişilebilirdir.
  Markdown dosyası kaydetme, Finder, retry ve silme gibi seyrek/dış etki üreten işlemler tek
  taşma menüsünde toplanır ve coordinator closure'ları üzerinden yürür; notch view'ları dosya
  sistemine doğrudan erişmez.
- Görevler yüzeyi iç içe kart kullanmaz; sabit durum ikonu kolonu, divider tabanlı satırlar,
  sans başlık ve mono tarih/sayaç rolleriyle toplantı listesiyle aynı optik grid'i paylaşır.
  Üst satır toplam “aktif” metni yerine backlog/todo/in-progress/blocked ikonlarıyla durum
  sayılarını gösterir. Satırdaki durum ikonu beş durum arasında seçim açar; `completed`
  seçimi görevi otomatik arşive taşır. Manuel arşivleme context menu'de ayrı kalır. Arşiv
  ana listenin altında açılmaz; sağ üstteki kompakt `archivebox` düğmesi aynı yüzeyde ayrı
  arşiv görünümüne geçer. Geri alma, düzenleme, silme ve arşiv temizleme kalıcı katmana
  coordinator closure'ları üzerinden ulaşır; destructive işlemler onay ister.
- AVPlayer tabanlı audio controller timestamp seek ve süre ilerlemesini yönetir. İlerleme
  yayınlarını yalnızca kompakt player gözlemler; saniyelik zaman güncellemeleri detail ağacını
  ve transkript satırlarını yeniden değerlendirmez. Segmentler sabit 600 px detail panelinde
  `ScrollView`'un tek dış `LazyVStack`'ına doğrudan çocuk olarak eklenir;
  transkripti tek eager alt ağaç yapan iç içe stack kullanılmaz. Kısa transkriptlerde satır içi
  metin seçimi korunur; uzun transkriptlerde yüzlerce native seçim köprüsü oluşturmamak için
  satır seçimi kapatılır ve segment bazlı context-menu kopyalama ile üstteki tüm-transkript
  kopyalama aksiyonu kullanılabilir.
- DynamicNotchKit'in 15 pt pencere içi güvenli alanı içinde kalmak için hover sırasında 20 pt'e
  büyüyen gölge kullanılmaz; panel sabit 10 pt gölgeyle çizilir ve alt fade pencere sınırında
  kesilmez.
- DynamicNotchKit 1.1.0 geniş panel host penceresini hedef ekranın yarı genişlik ve yarı
  yüksekliğinde oluşturur. `NotchHostViewport` fiziksel notch veya floating chrome inset'lerini
  bu host ölçüsünden çıkarır; `NotchPanelLayout` toolbar, bölüm aralığı ve dış padding'i ayrıca
  rezerve ettikten sonra scroll viewport'unu en fazla 600 pt ile sınırlar. Böylece kısa içerik
  doğal yüksekliğinde kalır, uzun detail içeriği başlığı maskelenmeden kayar ve son işlem satırı
  20 pt scroll sonu payıyla bütünüyle görünür.

## Transkripsiyon sınırı

- V1 batch çalışır: kayıt sırasında canlı transkript üretilmez. Mikrofon ve sistem sesi
  durdurma/finalize sonrasında tek M4A olarak kalıcı kuyruğa girer. ElevenLabs'in ayrı
  `scribe_v2_realtime` WebSocket modeli V1 sonrası kapsamındadır.

- Production'da yalnız `ElevenLabsTranscriptionService` bulunur. Dar
  `TranscriptionServicing` sözleşmesi ağ implementasyonunu test double'dan ayırır; runtime
  provider seçimi veya plugin noktası değildir.
- Capability doğrulaması ElevenLabs'in desteklenen formatını, dosya boyutu sınırını,
  diarization ve otomatik dil algılama gereksinimlerini istek başlamadan kontrol eder.
- Transport ve HTTP hataları authentication, rate limit, timeout, bağlantı, provider ve
  decoding kategorilerine normalize edilir; provider response gövdesi domain hata sınırına
  taşınmaz.
- Retry yalnızca geçici hatalarda sınırlı sayıda çalışır ve tüm denemelerde aynı request
  idempotency anahtarını korur. Upload callback'i `TranscriptionProgressBridge` üzerinden
  toplantı durum makinesinin `.uploading(progress:)` durumuna bağlanır.
- `ElevenLabsTranscriptionService`, resmi `POST /v1/speech-to-text` sınırında
  `scribe_v2`, `diarize=true`, word timestamp ve isteğe bağlı ISO dil kodu kullanır. Boş
  dil kodu provider'ın otomatik algılamasını etkin bırakır; Ayarlar Türkçe için `tr`
  gönderir. Yanıtın `words` dizisi ardışık speaker kimliklerine göre domain segmentlerine
  birleştirilir. Provider response gövdesi hata veya log nesnesine taşınmaz.
- Multipart gövde büyük sesi belleğe almamak için geçici dosyaya parça parça yazılır;
  URLSession delegate'i gerçek gönderilen byte oranını yayınlar. Dosya başarı/hata/iptalde
  silinir, force-quit artıkları uygulama açılışında sabit güvenli prefix ile temizlenir.
- API anahtarı Ayarlar'da `POST /v1/single-use-token/realtime_scribe` üzerinden kullanılmadan
  süresi dolacak geçici bir Scribe token'ı istenerek doğrulanır. Bu istek ses yüklemez ve
  ücretli transkripsiyon oluşturmaz; batch endpoint'inin eksik dosya için değişebilen hata
  biçimine bağlı kalmadan `speech_to_text` kapsamı verilmiş kısıtlı anahtarları destekler.
  Dönen token yalnızca yanıt bütünlüğünü doğrulamak için bellekte görülür, saklanmaz veya
  loglanmaz. Anahtar ancak başarıdan sonra Keychain'e kaydedilir; kimlik doğrulama nedeniyle
  bekleyen işler atomik olarak yeniden kuyruğa alınır. UI'da provider seçici veya alternatif
  servis gösterilmez.

## Özet ve Markdown sınırı

- `MeetingSummaryGenerating` transkripsiyon HTTP servisinden bağımsızdır. V1 uygulaması
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
- Calendar matcher, meeting session detector, mute adapter ve ElevenLabs parser gerçek
  servis olmadan fixture ile test edilir.
- Ses yakalama ve notch davranışı gerçek macOS donanımında entegrasyon testi gerektirir.
- Gerçek mikrofon testi `Scripts/audio-integration-tests.sh` opt-in runner'ıyla
  `MicrophoneCaptureSource` sınırını coordinator'dan bağımsız çalıştırır; runner yalnız test
  süresince `/tmp` sentinel'i oluşturur ve her çıkış yolunda temizler. Normal regresyon
  koşularında TCC istemi oluşturmamak için test atlanır.
- Gerçek sistem sesi testi aynı runner ile harici bir sistem sesi oynatır ve
  `SystemAudioCaptureSource` çıktısının seviye, timestamp, süre, audio track ve M4A dosya
  bütünlüğünü doğrular; normal regresyon koşularında TCC istemi oluşturmamak için atlanır.
- Otomatik recovery matrisi `Scripts/recovery-matrix-tests.sh` ile disk, capture recovery,
  queue restore/idempotency, transport retry, cihaz/gate kesintisi, pipeline heartbeat,
  drift/limiter ve privacy canary testlerini tek koşuda toplar; log ile sonuç özetini
  `artifacts/qa/` altında üretir.
- Browser audio otomasyonu extension origin/URL/backpressure testlerine ek olarak gerçek gömülü
  native-host executable'ını framed stdin/stdout, kullanıcı socket'i, broker ve M4A writer
  üzerinden uçtan uca çalıştırır. Bu test gerçek Chrome `tabCapture` ve iki sekmeli fiziksel
  privacy canary'nin yerine geçmez.
- Gerçek client privacy testleri opt-in çalışır: Zoom ile Google Meet/Chrome çağrılarında
  mute/unmute ve hang-up geçişlerini, güvenli system-audio kapsamını, canary phrase
  sızıntısını ve Google Meet için toplantı dışı sekme canary-audio izolasyonunu birlikte
  doğrular.

## Dil

Geliştirme dili İngilizce (`project.yml` → `developmentLanguage: en`); arayüz metinleri kodda
İngilizce yazılır. Türkçe ve diğer diller String Catalog çevirisi olarak eklenecek. Tarih ve
sayı biçimleri arayüz diliyle eşleşsin diye `AppLanguage.locale` kullanır. Kullanıcı girdisini
tanıyan kod (görev ayrıştırıcı, dikte komutları, özet kalıpları) Türkçe ve İngilizce ifadeleri
tanımaya devam eder; LLM özetleri dökümün dilinde yazılır.
