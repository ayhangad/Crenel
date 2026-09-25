# Arayüz ve etkileşim incelemesi — 25 Eylül 2026

Yerel galeri: [Önce / sonra ve durum matrisi](../artifacts/ui-audit/index.html).
Görseller sentetik verilerle gerçek SwiftUI view'larından üretilmiştir; ürün mockup'ı değildir.
`artifacts/` git dışında tutulur. Aşağıdaki testler görselleri yeniden üretebilir.

## Son parlaklık düzeltmesi

| Before | After |
| --- | --- |
| Arka plan %16 gri | #171717 (%9) |
| Sidebar %13 gri | #131313 (%7,5) |
| Kart %20 gri | #202020 (%12,5) |

Bu değerler önceki nötr renk parlaklıklarının yerini alır; alt ton eklenmez.

## Kullanıcı düzeltmesi — nötr renkler

| Before | After |
| --- | --- |
| Workspace RGB 0.15/0.16/0.18, sidebar 0.12/0.13/0.15 | Nötr gri 0.16 ve 0.13 |
| Kart RGB 0.19/0.20/0.22 | Nötr gri 0.20 |
| Son turda eklenen cyan ana düğmeler | Nötr gri 0.82 |

Bu düzeltme aşağıdaki ikinci tur renk kararının yerini alır. UX değişiklikleri korunur.

## İkinci tur — UX sadeleştirmesi

Aşağıdaki değişiklikler önceki turdaki ilgili tasarım kararlarının yerini alır.

| Before | After |
| --- | --- |
| Çok koyu siyah masaüstü ve tam beyaz vurgular | Mavi-gri yüzeyler, kırık beyaz metin, masaüstüne özel soluk cyan ana eylemler |
| Pencere ideal içerik boyutuyla büyüyor, eski ölçüsünü restore ediyordu | 1120×680 açılış, 960×540 minimum, hosting otomatik boyut kısıtları kapalı |
| Sekme değişiminde içerik id'si ve tüm panel animasyonu değişiyordu | Scroll kabı korunuyor; içerik layout geçişi kapalı, seçim göstergesi bağımsız |
| Aksiyon başına başlık, boş sorumlu açıklaması ve ayrı geniş buton satırı | Tek kompakt liste, ilk 6 madde, kalanlar açılır; satır içi aktarım ve kaynak |
| Ayar kartları başlıkların altında katmanlı ve servisler üst üste | Başlık kartın içinde, AI servisleri genişlik uygunsa yan yana |
| Mikrofon seçimi, cihaz sayısı ve kaydet ayrı satırlarda | Seçim/kaydet aynı satır; gereksiz cihaz sayacı kaldırıldı |
| İzinlerde açıklama ve çok sayıda ayrı aksiyon | Kompakt durum/izin satırı; ek sistem sesi işlemleri menüde |
| Bağlanılamayan Google servisi için sürekli açıklama kartı | Yalnız doğrudan bağlantı yapılandırılmışsa Google kartı; sistem takvimi eylemleri duruyor |
| Veri işlemleri dikey buton yığını | Uyarlanabilir yatay eylem grubu |
| Sayfa alt yazıları, sidebar sloganı/durum yazısı, uzun servis footer'ları | Kaldırıldı; boş detay yalnız “Bir toplantı seçin” |
| Notch başlangıç saati ve uzun boş geçmiş açıklaması | Tek kayıt durumu; “Henüz kayıt yok” |
| Uzun onboarding açıklamaları, tekrarlı analiz/speaker açıklamaları | Kısa izin odaklı metin; yinelenen bilgiler kaldırıldı |
| Başarılı eski pencere testi yalnız minimum ayarını okuyordu | Gerçek pencere 960×540'a küçültülüyor ve layout sonrası ölçüsü doğrulanıyor |
| Tek aksiyonlu detay fixture'ı | 9 maddeli fixture ile 6 satır + “Diğer 3 madde” görseli |

İkinci tur tam suite: 333 test, 3 opt-in atlandı, 0 hata. Son görsel düzenlemeler:
25 UI testi, 0 hata. Loglar `/tmp/MeetingNotch-ux-tests.log` ve
`/tmp/MeetingNotch-ux-final.log`. Fiziksel notch üzerinde animasyon akıcılığı ayrıca
ölçülmedi; ek sekme/scroll kararlılığı testi son kodla geçti (1 test, 0 hata).
`/tmp/MeetingNotch-ux-tabs-final.log`; son imzalı build: `/tmp/MeetingNotch-ux-signed.log`.

## Kapsam ve kanıt

- Notch: idle, upcoming, preparing, recording, finalizing, uploading, transcribing,
  summarizing, completed, cancelled, network-error. Her biri 600 ve 360 pt genişlikte;
  ayrıca 11 kompakt görünüm.
- Mikrofon açık/kapalı/bilinmiyor; kayıt teklifi, belirsiz bitiş ve otomatik durdurma.
- Masaüstü toplantı arşivi ve görevler; beş ayar kategorisi minimum pencerede.
- Yedi onboarding adımı; sistem açık görünümdeyken siyah notch.
- Aktif/arşiv görevlerin boş ve dolu halleri; dört izin durumu; dört toplantı detay durumu.
- Toplam 59 ek matris görseli, mevcut ana yüzey görselleri ve önce/sonra karşılaştırması.

Tam regresyon: **333 test, 3 opt-in fiziksel ses testi atlandı, 0 hata**.
Son görsel düzeltmelerden sonra **25 notch/masaüstü testi, 0 hata**.
Son development imzalı Debug build başarılı. `git diff --check` temiz.

Loglar: `/tmp/MeetingNotch-ui-full.log`, `/tmp/MeetingNotch-ui-final.log`,
`/tmp/MeetingNotch-ui-signed.log`.

Fiziksel toplantı, gerçek ekran çentiği üzerinde yeni build'in tüm geçişleri,
VoiceOver ile uçtan uca kullanım ve sistem Reduce Motion anahtarının fiziksel testi bu
çalışmada yapılmadı. Reduce Motion dalları ve erişilebilirlik sözleşmeleri kod/test
seviyesinde kontrol edildi. Statik görseller animasyon akıcılığı veya gerçek ses IO
kanıtı değildir. İncelenen açık uygulama eski build idi; çalışan uygulama değiştirilmedi.
AppDelegate'deki mevcut weak-capture derleyici uyarıları bu UI değişikliklerinin dışındadır.

## Ortak sistem

| Before | After |
| --- | --- |
| İkincil metin 138/255, başarı rengi aşırı doygun yeşil | Theme: metin 163/255; başarı 95/216/151 |
| Masaüstü yüzeyleri ve başlık ölçeği dağınık | Ortak workspace/sidebar renkleri, 26 pt sayfa başlığı |
| Özel düğmelerde değişken hover/odak geri bildirimi | Ortak hover, focus, contrast, disabled davranışı; 0.96 basış ölçeği |
| Input yüzeyleri farklı, özel odak çizgisi eksik | 44 pt ortak field yüzeyi, açık FocusState bağlantısı ve cyan odak çizgisi |
| Ekranlarda tekrarlanan boş/hata görünümleri | Ortak EmptyState, Feedback ve seçilebilir RowButtonStyle |
| Sabit yatay aksiyon grupları | ViewThatFits ile yatay/dikey aksiyon grubu |
| Dağınık geçiş süreleri | 0.14 sn etkileşim, 0.24 sn zıplamasız gezinme, Reduce Motion uyumu |

## Notch

| Before | After |
| --- | --- |
| 32 pt sekme hedefi | 40 pt hedef; dar panelde yalnız ikon; ayrı hit alanları |
| Seçim arka planı doğrudan değişiyordu | Matched geometry seçim kapsülü; aktif pin cyan geri bildirimi |
| Yinelenen özel header/stop/action stilleri | Ortak Theme stilleri doğrudan kullanılıyor; wrapper ortam uyarıları kaldırıldı |
| Kayıt sırasında da “Yaklaşan” başlığı | Akışa göre canlı kayıt/işleniyor vb. bağlamsal başlık |
| Dar görünümde kayıt/aksiyon sıkışması | 440 pt altında dikey kayıt düzeni; takvim ve toplantı aksiyonları uyarlanıyor |
| Baskın düz kırmızı durdurma | Tonal danger yüzeyi, template ikon ve okunabilir süre |
| Kapalı mikrofon da uyarı gibi sunuluyordu | Kapalı nötr, açık başarı, bilinmiyor uyarı; kayda dahil olma açık metinle anlatılıyor |
| Mikrofon kısayolu açıklamaya karışıyordu | Ayrı tuş etiketi, ortak basış/hover geri bildirimi |
| Seviye ve mikrofon değişimleri sertti | Yerel seviye yumuşatma; kompakt mikrofon opacity geçişi |
| Bağlı browser köprüsü de uyarı görünümündeydi | Yalnız bekleyen/kullanılamayan bağlantı uyarı alıyor |
| Boş geçmiş başarı check'i, genel başlık | Nötr saat ikonu ve “Son toplantılar”; geçmiş durum ikonlarında semantic tint |
| Görev seçiliyken kompakt sol ikon eşleşmiyordu | Resolver görev durumunda görev ikonu |
| İşleniyor/yükleniyor kompakt geri bildirimi zayıftı | Mini ilerleme göstergesi, cyan yüzde ve faz geçişi |
| Bazı menü hedefleri küçüktü | En az 40 pt kontrol alanları |

## Masaüstü ve toplantı detayı

| Before | After |
| --- | --- |
| Sidebar ve içerik hiyerarşisi zayıftı | Marka, çalışma alanı başlığı, 44 pt gezinme, sayaçlar, alt notch bağlantısı |
| Arşiv satırları ve boş alanlar farklı görünüyordu | Seçim yüzeyi, düzenli padding, ortak boş/hata durumu; 206/294 pt sidebar/arşiv |
| Arama ve yeni kayıt eylemi görsel olarak zayıftı | Odak çizgisi, 40 pt temizleme/yeni kayıt, erişilebilir etiketler |
| Görev çalışma alanında yaygın boşluk | Başlık/açıklama, 900 pt içerik sınırı, 32 pt çevre boşluğu |
| Geç kalan detay hatası yeni seçimi etkileyebiliyordu | Hata sonucunda da meeting kimliği doğrulanıyor |
| Analiz eylemleri özetin önündeydi | Önce sonuç/özet, ardından işlem araçları; yinelenen OpenAI açıklaması kaldırıldı |
| Zaman/kaynak eylemi yalnız seek yapıyordu | Seçili noktadan ses oynatılıyor |
| Sürüklerken oynatıcı zamanı slider ile yarışıyordu | Yerel scrub değeri, bırakmada seek; klavye seek korunuyor |
| Uzun süreler dar zaman alanına sığıyordu | Bir saat ve üzeri için 62 pt alan |
| Kopyalama bildirimi tekrar tıklamada erken kaybolabiliyordu | İptal edilebilir task ile 1.6 sn geri bildirim; not kopyalama da durum gösteriyor |
| Konuşmacı sheet'i ve hata mesajı ayrışıyordu | Ortak koyu yüzey/input, boş ad doğrulaması, busy durumu, Return/Escape, ayrı hata/başarı |
| Transkript eylemleri ve okunurluk zayıftı | 4 pt satır arası, 40 pt timestamp/kopyalama; lazy/equatable yapı korunuyor |
| Toolbar/metaveri hiyerarşisi sertti | Tam başlık tooltip'i, doğal tarih yazımı, “bölüm” metni, optik play hizası |

## Görevler, ayarlar ve onboarding

| Before | After |
| --- | --- |
| Yeni görev ve düzenleme odağı belirsizdi | 48 pt yeni görev yüzeyi, 40 pt submit, odak çizgisi, Escape ile düzenleme iptali |
| Uzun görev başlığı ve metadata yarışıyordu | İki satır başlık, küçük metadata, animasyonlu hover ve 40 pt menüler |
| Sıfır sayaçları kalabalık oluşturuyordu | Yalnız dolu aktif durumlar; arşiv sayacı, dar alanda özet fallback |
| Görev statü ikonları sabitti | Template tint; arşiv düğmesinin hit alanı büyütüldü |
| Ayar kategorileri sıkışıktı | İkonlu 40 pt uyarlanabilir gezinme ve içerik geçişi |
| Kart/button/input dili ayrışıyordu | Ortak kart yarıçapları, düğmeler, switch toggle, odaklı 44 pt SecureField |
| Kaydetme mesajı düğmelerle sıkışıyordu | Feedback ayrı satır; veri aksiyonları dikey, silme belirgin |
| İzin butonları dar alanda iki satıra kırılıyordu | Açıklama ve eylemler ayrı satır; erişilebilir çocuk kontroller korunuyor |
| OpenAI anahtar durumu yüklenmeden eylem açıktı | Anahtar kontrolü/loading durumu, bu sırada bağlantı eylemi disabled |
| Google/OpenAI/bildirim kartları farklıydı | Ortak stiller ve hata/başarı metinleri; çok satırlı açıklamalar |
| ElevenLabs bağlantısı minimum genişlikte taşıyordu | Plain link stili; yatay taşma testi geçiyor |
| Gelişmiş kayıt/izin anlatımı teknik ve karışıktı | Türkçe erişilebilirlik açıklaması, yalnız bağlı görüşme sekmesi vurgusu |
| Kurulum ekranlarında adım ve footer düzeni zayıftı | Marka + 1/7 ilerleme, kaydırılabilir içerik, sabit footer, 28 pt çevre |
| Büyük tam sayfa kayma | Küçük 12 pt giriş geçişi; Reduce Motion uyumu |
| Bilgi açıklamaları uyarı gibi görünüyordu | Nötr bilgi yüzeyi ve bağlamsal ikonlar |
| Verilmiş izin tekrar istenebiliyordu | Mevcut izinde devam eylemi; izin metinleri sadeleştirildi |

## Test altyapısı değişiklikleri

| Before | After |
| --- | --- |
| Görsel matris bazı akışlarla sınırlıydı | Üç yeni test: tüm lifecycle/genişlikler; tüm onboarding; görev/izin/detay varyantları |
| NSHostingView ideal ölçüsü test penceresini yeniden boyutlandırabiliyordu | Sabit viewport, sizingOptions boş; kompakt timer için container hosting |
| Upcoming fixture yalnız flow oluşturuyordu | Upcoming meetings listesi ve authorized takvim durumu da kuruluyor |
| Sekme testi 32 pt sabitini doğruluyordu | 40 pt minimum hit alanı sözleşmesi |

Görsel export için `/tmp/MeetingNotchExportUIAudit` dosyasını oluşturup
`NotchPresentationTests` ve `DesktopWorkspaceTests` çalıştırın. Test bitince sentinel'ı
kaldırın. App ayarları, gerçek kayıtlar veya API anahtarları fixture olarak kullanılmaz.
