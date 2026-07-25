# MeetingNotch — Product Development Plan

Bu dosya MeetingNotch v1 tamamlanana kadar kullanılacak ortak ilerleme planıdır.
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

## Ürün özeti

MeetingNotch, macOS notch çevresinde Dynamic Island benzeri çalışan hafif bir toplantı
kayıt uygulamasıdır. Takvim ve yerel macOS sinyalleriyle desteklenen toplantıyı algılar,
toplantının başladığını/bittiğini kullanıcıya görünür biçimde bildirir, yalnızca toplantıya
ait sesi kaydeder ve kaydı konuşmacı ayrımlı transkript ile kısa özete dönüştürür. Kullanıcı
geçmiş toplantılarına erişebilir ve notch içinden basit bir görev listesi yönetebilir.

V1'in tek uzak bağımlılığı ElevenLabs Scribe v2'dir. Kullanıcı yalnızca kendi ElevenLabs
API anahtarını girer; provider seçmez, başka bir bulut hesabı bağlamaz ve ikinci bir API
anahtarı yönetmez. EventKit, Core Audio, AVFoundation ve gerektiğinde macOS Accessibility
yerel işletim sistemi sınırlarıdır; uzak entegrasyon sayılmaz ve servis hesabı gerektirmez.

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
- **Dar destek yüzeyi:** İlk kalite kapısı Zoom Workplace native istemcisidir. Google Meet
  (Chrome) ancak privacy testinde tarayıcının toplantı dışı sesini kaydetmediği veya bu sınır
  kullanıcıya güvenli biçimde yönetilebildiği doğrulanırsa ikinci adaptör olur. Microsoft
  Teams ve diğer istemciler V1'i bloke etmez.
- **Gizli otomasyon yok:** Algılama kaydı kendiliğinden ve habersiz başlatmaz. Güçlü
  başlangıç sinyali notch üzerinde kayıt teklifini açar. Güçlü bitiş sinyali kayıt sırasında
  iptal edilebilir kısa geri sayım sonrası kaydı durdurabilir; sinyal belirsizse kullanıcıya
  sorulur.

### Toplantı yaşam döngüsü sözleşmesi

Takvim zamanı tek başına gerçek toplantı başlangıcı veya bitişi sayılmaz. Yeni session
detector aşağıdaki bağımsız sinyalleri birleştirir:

1. EventKit etkinliği ve toplantı URL'si yalnızca planlanmış bağlamı verir.
2. Tanınan meeting process'inin açılması ve Core Audio `isRunningInput` /
   `isRunningOutput` durumu gerçek istemci aktivitesine aday sinyal verir.
3. İstemci adaptörünün Accessibility ağacında meeting window/call controls bulması güçlü
   katılım sinyalidir.
4. Kullanıcının MeetingNotch içindeki `Katıl` aksiyonu toplantı URL'si ile process/window
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
  yeni oturumda varsayılan olarak kapalı başlar.
- Privacy kabul testi, mute iken söylenen benzersiz test cümlesinin ne ham mikrofon
  parçasında ne birleşik M4A'da ne de transkriptte bulunmadığını doğrular.

### Minimal/techy UI yönü

- 420 px'e kadar büyüyen kart yığını yerine hedef genişlik 344–368 px; dış padding 12 px,
  bölüm aralığı 8–10 px ve corner radius 10–12 px.
- Görsel ikonlar çoğunlukla 11–13 pt olur; tıklama hedefleri macOS için 28–32 px korunur.
  Küçük görünmek, küçük veya erişilemez hit target anlamına gelmez.
- Nötr siyah/gri yüzey, tek hairline border ve yalnızca durum renginde vurgu kullanılır.
  Dekoratif gradient, büyük gölge ve iç içe kartlar kaldırılır.
- Başlıklar 13–14 pt semibold, ikincil metin 11–12 pt, süre/sayaçlar monospaced digit olur.
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
- [ ] Zoom için process, meeting window ve call controls algılayan yerel adaptör prototipi
  yapmak; Accessibility izni yok/reddedilmiş davranışı tasarlamak.
- [ ] Takvim, `Katıl` aksiyonu, process audio ve client adapter sinyallerini deterministic
  confidence kurallarıyla birleştirmek.
- [ ] Güçlü başlangıçta kayıt teklifini; güçlü bitişte iptal edilebilir auto-stop geri
  sayımını; belirsiz bitişte manuel onayı uygulamak.
- [ ] Planlanmamış toplantı, geciken toplantı, erken katılma, ara verme, sessizlik,
  uygulamanın açık kalması ve arka arkaya çağrı senaryolarını fixture testleriyle kapsamak.

**B çıkış kriteri:** Zoom gerçek cihaz testinde başlangıç ve hang-up beşer ardışık koşuda
doğru algılanır; yalnız sessizlik yanlış bitiş üretmez; izin yokken manuel kayıt çalışır.

#### C — Privacy-first toplantı sesi

- [ ] Global system tap yerine belirlenen meeting process'lerini içeren private Core Audio
  process tap oluşturmak; MeetingNotch ve toplantı dışı uygulama sesini dışarıda bırakmak.
- [ ] `MeetingMicrophoneGate` state machine ve timestamp'li gate event modelini oluşturmak.
- [ ] Zoom mute control adaptörünü `open/closed/unknown` üretecek şekilde bağlamak.
- [ ] Mikrofon writer'ında `closed/unknown` sample'larını encode öncesi sıfırlamak, gate
  değişiminde click üretmeyen kısa fade uygulamak ve ortak timeline'ı korumak.
- [ ] Görünür notch toggle + global shortcut fallback'i eklemek; her kayıtta kapalı başlatmak.
- [ ] Ham mic, system track, birleşik M4A ve transkript üzerinde unique-phrase privacy
  testini; hızlı mute/unmute, kulaklık ve cihaz değişimi senaryolarını çalıştırmak.
- [ ] Meeting process'i değişir veya adapter kaybolursa gate'i fail-closed yapmak ve
  kullanıcıya anında görünür uyarı vermek.

**C çıkış kriteri:** Mute/unknown aralıklarında kullanıcı sesi hiçbir kalıcı çıktıya girmez;
unmute aralıkları anlaşılırdır; toplantı dışı uygulama sesi process-scope testinde yoktur.

#### D — Minimal UI dönüşümü

- [ ] Renk, tipografi, spacing, radius, icon ve control-size token'larını tek theme dosyasında
  tanımlamak.
- [ ] Kompakt notch'u session/gate/kayıt süresi etrafında yeniden tasarlamak.
- [ ] Geniş paneli tek ana status surface + ince geçmiş listesi olarak yeniden tasarlamak;
  gereksiz kart, gölge ve büyük ikonları kaldırmak.
- [ ] Settings ve onboarding'i tek API ve yeni Accessibility/mute sınırlarıyla yenilemek.
- [ ] Toplantı detayını daha yoğun header, sade playback bar ve okunaklı transcript düzenine
  geçirmek.
- [ ] Koyu/açık, Increase Contrast, Reduce Motion, klavye ve VoiceOver durumlarını snapshot
  veya preview matrisiyle doğrulamak.

**D çıkış kriteri:** Tüm ana durumlar aynı token setini kullanır; 344–368 px panelde taşma
yoktur; görsel ikonlar küçülürken kontroller klavye ve VoiceOver ile kullanılabilir kalır.

#### E — Çalışan V1 ve release hardening

- [ ] 60+ dakikalık Zoom toplantısında process-scope system audio, gated mic, finalize,
  ElevenLabs upload, diarization, özet ve detay akışını uçtan uca tamamlamak.
- [ ] İnternet kesintisi, 401/429/5xx, disk dolması, force quit, sleep/wake ve audio device
  değişimi recovery matrisini geçirmek.
- [ ] Google Meet/Chrome adaptörünü privacy kriterlerine karşı prototiplemek; geçerse ayrı
  destek etiketiyle eklemek, geçmezse manuel mod olarak açıkça sınırlandırmak.
- [ ] İmzalı/notarize release candidate'ı temiz kullanıcı hesabında notch ve harici ekranda
  doğrulamak.

**E çıkış kriteri:** İlk kurulumdan sonuç ekranına gerçek toplantı akışı veri sızıntısı
olmadan tamamlanır ve V1 tamamlanma tanımındaki bütün maddeler geçer.

## Faz 0 — Temel ürün tanımı ve proje hazırlığı

### 0.1 Mevcut başlangıç noktası

- [x] Ürünün ana fikrini ve v1 kapsamını `project-overview.md` içinde belgelemek.
- [x] Temel macOS Xcode projesini oluşturmak.
- [x] Bu dosyayı geliştirme boyunca tek ana ilerleme planı olarak benimsemek.
- [x] `ARCHITECTURE.md` oluşturup mevcut ürün belgelerinden türetilen uygulama katmanlarını
  ve bağımlılık kurallarını belgelemek.
- [x] `project.yml` dosyasını Xcode projesinin tek yapılandırma kaynağı yapmak ve
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
- [x] Menüye `MeetingNotch'u Aç`, `Kaydı Başlat`, `Ayarlar` ve `Çıkış` aksiyonlarını eklemek.
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
- [ ] Açık/koyu tema ve yüksek kontrast görünümünü doğrulamak.
- [ ] Mock verilerle tüm notch durumlarının preview'larını hazırlamak.

### 2.4 Minimal/techy görsel sistem dönüşümü

- [ ] Ortak UI token setini tanımlamak: yüzey, hairline, durum renkleri, 11–14 pt type
  scale, 8/10/12 px spacing, 10–12 px radius ve 28–32 px control target.
- [ ] 42 px ikon ağırlıklı sekme/pin kontrollerini daha küçük glyph ve yoğun macOS
  kontrollerine dönüştürmek.
- [ ] İç içe kartları, dekoratif büyük gölgeleri ve yinelenen başlıkları kaldırmak.
- [ ] Kompakt notch'a meeting detection confidence ve mic gate durumunu eklemek.
- [ ] Geniş paneli 344–368 px hedef genişlikte toplantı yaşam döngüsü merkezli yenilemek.
- [ ] Ayarlar, onboarding ve meeting detail yüzeylerini aynı token setine taşımak.

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

- [ ] Takvim bağlamından bağımsız meeting session domain modelini ve state machine'i
  oluşturmak.
- [ ] Core Audio process input/output aktivitesini bundle ID ve PID ile izlemek.
- [ ] Zoom process/window/call-control adaptörünü Accessibility üzerinden prototiplemek.
- [ ] Takvim, `Katıl`, process IO ve client adapter kanıtlarını confidence skoruna
  dönüştürmek.
- [ ] Başlangıç, bitiş şüphesi ve doğrulanmış bitiş davranışlarını notch'a bağlamak.
- [ ] Manuel toplantı kaydını tüm algılama/Accessibility hata durumlarında korumak.

### 6.5 Destek matrisi

- [ ] Zoom Workplace native: planlı/plansız, erken/geç katılım, mute/unmute, hang-up ve
  uygulamanın açık kalması senaryolarını gerçek cihazda doğrulamak.
- [ ] Google Meet/Chrome: process-scope ve mute state doğruluğunu privacy spike ile ölçmek;
  toplantı dışı tarayıcı sesi izolasyonu kanıtlanamazsa V1 desteğine almamak.
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
- [ ] Maksimum kayıt süresi veya disk dolması sınırlarını yönetmek.

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
- [ ] Sessizlik ile kopmuş audio pipeline durumunu mümkün olduğunca ayırt etmek.
- [ ] Çıkış cihazı veya sample rate değişimini ele almak.
- [x] Core Audio Process Tap, aggregate device ve dosya kaynaklarını her bitiş/hata yolunda
  temizlemek.
- [ ] Global tap'i desteklenen toplantı process'leriyle sınırlı private process tap'e
  dönüştürmek.
- [ ] Meeting process'i kapanır/değişirse tap'i güvenli yeniden bağlamak veya kaydı görünür
  uyarıyla durdurmak.

### 7.4 Senkronizasyon ve dosya üretimi

- [x] İki ses kaynağı için ortak timeline stratejisini uygulamak.
- [x] Başlangıç offset'ini ele almak.
- [ ] Uzun süreli clock drift'ini ele almak.
- [x] Sample rate ve kanal düzenini normalize etmek.
- [x] Kaynak gain dengesini uygulamak.
- [ ] Limiter uygulayarak clipping'i önlemek.
- [x] Provider için tek ve geçerli M4A/AAC dosyası üretmek.
- [x] Nihai dosyanın süresini ve okunabilirliğini doğrulamak.
- [x] Finalize işlemi başarısız olursa kaynak geçici dosyaları korumak.
- [x] Çökme sonrası yarım kaydı finalize etme kurtarma akışı oluşturmak.

### 7.5 Kayıt kontrolleri

- [x] Notch üzerinde canlı süre göstermek.
- [x] Mikrofon/system audio durum göstergelerini sunmak.
- [x] Kaydı durdurma kontrolü eklemek.
- [x] İptal kontrolünü yanlış dokunmayı önleyecek şekilde sunmak.
- [ ] İsteğe bağlı pause/resume özelliğini ürün kararına göre uygulamak.
- [ ] Kayıt sürerken uykuya geçme ve ekran kilidi davranışını belirlemek.

### 7.6 Meeting mikrofon gate'i

- [ ] `open/closed/unknown` durumlu, varsayılanı `closed` olan gate state machine'i
  oluşturmak.
- [ ] Client mute detector sonucunu gate'e bağlamak; Core Audio input aktivitesini yalnız
  destekleyici kanıt olarak kullanmak.
- [ ] `closed/unknown` sample'larını writer öncesinde sıfırlayıp timeline'ı korumak.
- [ ] Gate geçişlerini timestamp + kaynakla kayıt metadata'sına yazmak.
- [ ] Notch toggle ve global shortcut manuel fallback'i eklemek.
- [ ] Adapter kaybı, Accessibility izni kaybı ve bilinmeyen durumda fail-closed davranmak.
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
- [ ] Uzun transkriptlerde performanslı kaydırmayı doğrulamak.

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
- [ ] Meeting client bulunamadı, Accessibility izni reddedildi ve mute state `unknown`
  senaryolarında mikrofonun fail-closed kaldığını test etmek.
- [ ] Meeting client hang-up, crash, process restart ve meeting window kapanma senaryolarını
  test etmek.
- [ ] Mute iken söylenen canary phrase'in hiçbir kalıcı ses/transkript çıktısına girmediğini
  otomatik doğrulamak.
- [ ] Process-scope tap sırasında müzik/bildirim/tarayıcı gibi toplantı dışı seslerin kayda
  girmediğini doğrulamak.

### 10.2 Performans ve kaynak kullanımı

- [ ] Boşta CPU ve enerji kullanımını ölçmek.
- [ ] Hover panel kapalıyken gereksiz render/polling olmadığını doğrulamak.
- [ ] Kayıt sırasında memory kullanımını uzun süre izlemek.
- [ ] Büyük transkript açılış ve kaydırma performansını ölçmek.
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
  saatinden ayrı gerçek meeting session detector, Zoom-first istemci adaptörü,
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
