# Crenel tasarım dili — "gece sürüşü"

Durum: prototipte (2026-11-17; masaüstü, butonlar, göstergeler ve ikon ikinci turda
yenilendi), Swift'e aktarılmayı bekliyor. Kaynak:
`docs/design/crenel-prototype.html`. Uygulanan önceki dil ("enstrüman", `Hud*`), bu
belgeye göre güncellenecek. Aşağıdaki ölçüler prototipteki CSS ve çizim kodunun
karşılığıdır. Çelişki olursa prototip esastır.

## Fikir

Çağdaş bir ürün yapısı içinde retro gösterge ayrıntıları kullanılır. İskelet bugünün
macOS ürünü gibidir: tek font, cümle düzeni, bol boşluk, tek birincil eylem, tuş ipuçları.
Karakteri 70–80'lerin dijital gösterge panellerinden gelen birkaç ayrıntı verir: ışıklı
segment rakamlar, tik halkaları, gösterge lambaları, ölçek cetvelleri. Bu ayrıntılar süs
değildir; her biri bir veriyi taşır. Retro yalnızca "imza anlarında" görünür.

Notch karanlık bir gösterge yuvasıdır. Bilgi çizilmez, yakılır. Yanmayan parçalar da
görünür kalır (hayalet). Böylece boş bir gösterge bile şeklini korur.

## İlkeler

1. **Her yüzeyde bir kahraman sayı.** Geri sayım, geçen süre ya da sayaç gibi en önemli
   sayı segment rakamla yazılır. Geri kalan her şey Geist'tir. Bir yüzeyde ikinci bir
   segment sayı yalnızca ölçüm kartlarında (Ready ekranı gibi) olabilir.
2. **Durum lambayla söylenir.** "Connected" veya "Failed" gibi renkli metin yerine 8×4
   bir lamba ve sade bir kelime kullanılır. Renkler:

   | Lamba | Anlamı |
   | --- | --- |
   | amber `#ffad33` | seni bekliyor: yaklaşan toplantı, davet, öncelik, devam eden görev, uyarı |
   | kırmızı `#ff5a47` | canlı kayıt, hata, bloke |
   | turkuaz `#34e6cb` | hazır, bağlı, eklendi (uygulama ikonunun rengi) |
   | beyaz `#f3f1ec` | etkin, seçili, o an çalışan |
   | kapalı `rgba(255,255,255,.09)` | yok, sırada |

   Yanan lambanın sıcak bir çekirdeği vardır: ortası açık tonda (amber `#ffe2b3`,
   kırmızı `#ffc2b8`, turkuaz `#b9fff3`, beyaz `#fff`), kenara doğru kendi rengine iner
   (radyal, %72'de tam renk). Işığı iki katmandır: 6 pt sıkı parıltı (%65–75) ve 16 pt
   geniş sızma (%20–24). Kapalı lambanın %5 opak ince bir kenarı vardır.
3. **Hayaletler.** Yanmayan segment, tik ve hücreler %6–13 opaklıkla görünür kalır. Segment
   rakamın her basamağı bir hayalet "8" üzerinde durur. Baştaki boş basamaklar boş değil,
   hayalettir (`data-cells`).
4. **Tipografi.** Yalnızca Geist (OFL) kullanılır. Büyük harf, harf aralığı açma ve
   "eyebrow" yoktur. Büyük boyutlarda aralık daraltılır, hiçbir zaman açılmaz. Rakamlar
   tabulardır.

   | Stil | Boyut ve ağırlık | Kullanım |
   | --- | --- | --- |
   | hero | 17 / 600, −0.012em | odaktaki etkinlik, detay başlığı |
   | title | 15 / 600, −0.006em | kart ve sonuç başlığı |
   | body | 13 / 500 | satır başlığı |
   | label | 12.5 / 500 | sekme, buton, grup başlığı |
   | meta | 11.5 / 400, ink-3 | ikinci satır |
   | micro | 10 / 500, ink-4 | ölçek etiketi, birim altı |
   | unit | 11 / 500, ink-3 | segment sayının yanındaki birim ("min", "left", "%") |
   | read | 13 / 400, satır 1.6 | özet, transkript |

5. **Mürekkep.** Arkadan aydınlatılmış yüz gibi çok hafif sıcaktır; saf gri kullanılmaz.
   ink-1 `#f3f1ec` · ink-2 `#aaa7a1` · ink-3 `#76736e` · ink-4 `#4c4a47` · ink-5 `#2e2d2b`.
   Yüzey dolguları beyazın düşük opaklıklarıdır: hover zemini %5.5, alan %5.5, sessiz
   buton %7, seçili %10.
6. **Çizgi yok, ölçek var.** Satırlar arasında ayırıcı yoktur. İnce çizgi yalnızca bir
   ölçeğin parçası olarak görünür: cetvel tikleri, gösterge halkası, iğne.
7. **Hiçbir şey zıplamaz.** Satır yüksekliği ve metin konumu hover'da değişmez. Bir listede
   tek bir hover zemini satırlar arasında kayar (0.18 sn, `cubic-bezier(.2,.8,.2,1)`).
8. **Eylemler sağ kenarda biter.** Bilgi solda, eylem sağdadır. Birincil buton en
   sağdadır; ikincil hemen solunda durur. Butonlar asla soldan yan yana dizilmez. Ayrıntı
   için "Butonlar ve eylem yerleşimi" bölümüne bak.

## Butonlar ve eylem yerleşimi

Butonlar tıklanan kelimeler değil, basılan tuşlardır. Yalnızca metinden oluşan eylem
butonu yoktur.

| Tür | Görünüş | Kullanım |
| --- | --- | --- |
| primary | yanan tuş: `#fdfcf9 → #e2dfd8` dikey degrade, üstte 1 pt beyaz iç ışık, altta %14 gölge çizgisi, 0.5 pt koyu çerçeve, 16 pt %9 ink parıltı | yüzeyde en fazla bir tane, her zaman tuş kapağıyla |
| secondary | karanlıkta kabarık tuş: beyaz %8.8 → %4.6 dikey degrade, 1 pt %7 iç halka, üstte 1 pt %7.5 ışık, altta 2 pt gölge | diğer bütün eylemler |
| danger | secondary gövdesi, kırmızı mürekkep `#ff6b59` | silme, kaldırma; birincilin yanında asla durmaz |
| ghost | yalnızca metin | listelerin içindeki üçüncül gezinme (ör. Rename) |
| icon framed | secondary gövdeli kare ikon butonu | araç çubuğunda "daha fazla", kopyala |

- **Boylar.** Normal 28 pt (yarıçap 8), sm 26 pt, xs 22 pt (yarıçap 6, 11.5 pt yazı),
  lg 32 pt (yarıçap 9). Basınca 0.5 pt aşağı iner ve iç gölge alır.
- **Tuş kapağı (`.kbd`).** Kısayol, butonun içinde küçük bir tuş olarak çizilir: 16 pt
  (sm/xs'te 15 pt), yarıçap 4, 10.5 pt yazı. Altında 1 pt koyu kenar vardır. Birincilde
  siyah %6 zemin ve %50 siyah yazı, ikincilde beyaz %5.5 zemin ve ink-3 yazı kullanılır.
- **Yerleşim kuralları.**
  1. Eylem satırı (`.actions`): solda durum notu (lamba + meta), sağda butonlar.
  2. Sıra soldan sağa: danger · secondary · primary. Danger ile primary arasında her
     zaman bir secondary ya da boşluk bulunur.
  3. Vazgeçme butonu `esc`, birincil `↩` taşır. Başka kısayollar kendi tuşunu taşır
     (`⌘J`, `⌘R`, `⌘Z`, `⇧⌘C`).
  4. Tek eylemli boş durumlarda düzeltme butonu cümlenin altında değil, satırın sağ
     ucunda ve dikey ortadadır.
  5. Notch'taki konsol (`.console`, 44 pt, yarıçap 13, beyaz %4.5 → %2.5): toplantı
     yaklaşınca kahramanın altında açılır. Solda lambalı durum ("Crenel will ask to record
     when it starts", "Not being recorded", Meet köprüsü), sağda **Record ⌘R** (secondary)
     ve **Join ⌘J** (primary).

## Uygulama ikonu

- Altı lamba bir mazgal (crenel) gülümsemesi çizer. Bu, notch'taki lamba dilinin
  kendisidir. Kaynak: `MeetingNotch/AppIcon.icon` (Icon Composer, macOS 26).
- Zemin: `#131313 → #030303` doğrusal degrade, sol üstten sağ alta.
- Lambalar: 472×296 birimlik glif, 118 birimlik kareler, her biri radyal degradeli
  (orta `#3BFFE8`, %38'de `#05F0D2`, kenar `#00A891`; sağdaki en parlak lamba camgöbeği:
  `#8AFFFF → #0CF6F6 → #00AFC0`). Lamba opaklıkları .70 · .76 · .50 · .65 · .56 · .95'tir.
  Bu opaklıklar markanın parçasıdır.
- Cam efekti kapalıdır (lambalar net kalsın diye). Gölge `layer-color`, %60.
- Uygulama içinde aynı glif `i-mark` sembolüdür. 26 pt'lik siyah karo (`.app-tile`)
  içinde `#14f0d4` renginde ve 2.5 pt parıltıyla kullanılır. Bu yüzden "hazır" lambasının
  rengi ikonun turkuazına çekildi.

## İkon ailesi

- **Geometri.** 16 birimlik ızgara, 1.5 çizgi, kare uç ve sivri birleşim (Remix
  dilinde). Yuvarlak köşe yoktur; köşeler 45° pahla kırılır. Açılar 0°, 45° ve 90°'dir.
- **İki hal.** Yanabilen her ikonun iki çizimi vardır ve ikisi aynı kalıbı paylaşır.
  - Çizgi hali (`i-*`): dinlenme ve "kapalı" durumu.
  - Dolu hali (`f-*`): tam siluet, ayrıntılar içinden kesilir (mikrofonun ızgara
    yarıkları, takvimin gün karesi, transkriptin satırları). Yanan durum budur.
  - Seçili gezinme öğesinin ikonu dolu hale geçer.
- **Uyarı lambası (`.tt`).** Yanmayan ikon %20 beyaz çizgi hali, yanan ikon kendi
  renginde dolu hali ve iki katmanlı parıltıyla görünür.
  - `paren` hali glifin iki yanına açılı parantez koyar. Anlamı "sistem/izin sorunu":
    mikrofon izni yok, mute durumu okunamıyor, çağrı sesi kapalı.
  - `mod` sağ alttaki 6.75'lik yuvaya rozet koyar (`!` ya da `×`). Rozet glife yüzey
    renginde 1.5'luk bir boşlukla kesilir (`--surface`).
- **Uyarı karosu (`.ttile`).** Renkli bir kare ve içinden oyulmuş glif. Yalnızca
  kaçırılmaması gereken durumlarda kullanılır; şu an tek kullanımı işleme hatası
  kulağıdır.
- **Görev işaretleri.** Pahlı kare, doluluk düzeyiyle durum söyler: boş çerçeve, amber
  yarım, kırmızı çubuk, koyu dolu. Onay işareti yoktur.
- Öncelik, sinyal çubuğu gibi 3 artan çubukla gösterilir (`.pri`).

## Göstergeler (Swift'te `Shape` olarak)

- **Segment rakam (`.segd`).**
  - 10×18 birimlik hücre, 2 birim kalınlık. Altıgen segmentlerin uçları sivridir ve
    aralarında 0.55 boşluk bulunur.
  - 7° italik (`skewX(-7)`).
  - Basamak adımı 13, iki nokta adımı 5.
  - Yanan segmentin iki katmanlı ışığı vardır: 1.5 pt %60 çekirdek ve 7 pt %24 sızma.
    Hayalet segment %7.5 opaktır.
  - Boyutlar: kulakta 13 pt, açık panel kahramanında 24 pt, kayıt süresinde 34 pt.
  - Değer değişince yalnızca segmentler değişir; yerleşim kaymaz.
- **Tik halkası (`.gauge`).**
  - 270° tarama, birim başına bir tik. Her 15. tik ana tiktir: daha uzun ve kalın.
  - Değer, baştan (sol alt) başlayarak yanan tik sayısıdır.
  - Toplantıya kalan süre: son 60 dakika, dakika başına bir tik. Toplantı sürerken kalan
    payı gösterir.
  - Ortada kahraman sayı ve altında micro birim bulunur. Arkasında göstergenin renginde
    radyal bir ışık sızması vardır (`.bleed`: merkezde %10, %60'ta %3, sonra sıfır).
  - Işık modeli (birebir aktarılmalı):

    | Katman | Ne |
    | --- | --- |
    | ghost | yanmayan tik, %13 |
    | lit | yanan tikler, 1.6 pt çekirdek parıltı |
    | head | son yanan tik: rengin %55'i beyazla karışık, 1.2 pt daha uzun, çift parıltı (2 pt + 6 pt) |
    | tail | head'den sonraki 3 tik %42 · %27 · %17 kalır (fosfor art ışığı) |
    | halo | yanan aralığın arkasında boyutun %10'u kalınlığında, boyutun %4.5'i kadar bulanık bir yay, %20 |
    | dots | iç halkada her ana tik için bir nokta; geçilmişse %90, değilse %22 (96 pt üstü göstergelerde) |
- **Gün cetveli (`.ruler`).**
  - 08–20 aralığında yarım saatte bir tik, saatte bir uzun tik ve her iki saatte bir
    etiket bulunur.
  - Etkinlikler cetvelin üstünde 6 pt'lik ışıklı bloklardır:
    - odakta ink-1,
    - yakında amber,
    - davet amber dış çizgi,
    - kişisel sönük.
  - "Şimdi" amber bir iğnedir. Geçmiş bölüm karartılır.
  - Geniş cetvel (masaüstü, `.ruler.wide`, 62 pt): etkinlik adları bloklarının altında
    micro yazıyla durur. Geçmiş etkinlikler maskeyle değil %35 opaklıkla söner.
- **Kuyu (`.well`).** Göstergelerin oturduğu çukur ekran penceresidir: `#050505 → #0a0a09`,
  içte 2 pt koyu gölge, 1 pt %4.5 halka, altta 1 pt %3.5 ışık. Okumalar (Ready, Dictation,
  ayar başlıkları), oynatıcı ve canlı kayıt kartı kuyunun içindedir. Kuyu içindeki
  bölmeler çizgiyle değil, %4'lük 1 pt gölgeyle ayrılır.
- **LED yığını (`.stack`).** Hücrelerden oluşan çubuk grafiktir. Masaüstünde gün başına 8
  hücre (18×3), notch'ta 6 hücre (10×2) kullanılır. Bugün beyaz ve parıltılıdır, geçmiş
  günler ink-3, gelecek günler hayalettir.
- **VU metre (`.vu`).**
  - 24–30 hücre; son %14'ü kırmızı bölgedir.
  - Tepe hücresi 0.7 sn asılı kalıp sonra düşer (peak hold).
  - Kapalı kaynakta tüm hücreler hayalettir.
- **Merdiven (`.ladder`).** Kulak için 6 sütun × 4 hücrelik seviye göstergesi.
- **Şerit kaydedici (`.chart`).** Son iki dakikanın sesi, sola akan ince çubuklarla
  gösterilir. En yeni çubuk beyaz, sol kenar solar.
- **Tarayıcı (`.scanner`).** Süresi bilinmeyen işlerde metnin ya da alanın üstünde gidip
  gelen bir ışık bandı geçer. Süresi biliniyorsa sayı gösterilir, tarayıcı gösterilmez.
- **Fitil.**
  - Kapalı notch'un alt kenarındaki 2 pt'lik ışıklı çizgidir; köşe yarıçapları
    arasında kalır.
  - Boyu, kalan payı gösterir:
    - toplantıya 60 dk'dan az kaldıysa dakika/60,
    - 10 dk ve altında dakika/10 (amber),
    - otomatik durdurmada 12 sn (kırmızı).
  - Doğrusal olarak kısalır.

- **Basılı bölgeler (`data-zones`).** Geri sayım kadranında son 10 dakika amber, son 2
  dakika kırmızı bölgedir. Bölge, tiklerin içinde 1.5'luk ince bir yay olarak her zaman
  basılıdır. Bölgedeki tik yandığında bölgenin rengini alır; yanmadığında %26'lık renkli
  hayalettir.
- **Ölçek sayıları (`data-labels`).** Yalnızca 140 pt üstü kadranlarda (masaüstü
  kahramanı) kullanılır: ana tiklerde 0 · 15 · 30 · 45. Geçilmiş sayı %85, kalan %32.
- **Yükselen bant (`.ramp`).** Kayıtta geçen süreyi planlanan süreye göre gösterir.
  Bant yükseldikçe kalınlaşır (2 → 11 pt). Altında 5 dakikada bir basamak tik, 15
  dakikada bir uzun tik bulunur. Planın ötesi basılı kırmızı bölgedir; süre oraya
  geçerse bant kırmızı yanar. Ölçek planın 1.25 katıdır. Yanında yalnızca "of 60 min"
  yazar.
- **Radyo ölçeği (`.tuner`).** Notch oynatıcısında dalga formunun altında yer alır:
  dakikada bir tik, 10 dakikada bir etiketli uzun tik. İğne ölçeğin içine kadar iner. O
  anki zaman düğmenin altında micro yazıyla durur.
- **Nokta matrisi (`.dots`).** 3 satır, sütun sütun dolar, 4 pt lamba ve 3 pt aralık.
  Küçük bir üçgen "your usual" düzeyini işaretler. Yalnızca masaüstündeki Dictation
  karosunda kullanılır.
- **Kapsüller (`.caps`).** 12×6 kapsüller: bitti beyaz, sürüyor amber yarım dolu, sırada
  hayalet. Yalnızca masaüstündeki Tasks karosunda kullanılır.
- **Kapasite ölçeği (`.cap`).** İki ucu etiketli ölçektir (−60 … 0 dB); glif ortaya
  basılır. Hücrelerin altında beyaz, amber ve kırmızı bölge şeridi bulunur. Yalnızca
  Ayarlar › Recording › Level'da kullanılır.
- **Mod göstergesi (`.annun`).** Basılı kelimelerden seçili olan yanar (ink-1 + 8 pt
  parıltı), diğerleri hayalettir (`#3a3936`). Sentence case yazılır, harf aralığı
  açılmaz. Kullanım yerleri: Meetings filtresi, Dictation modu.
- **Çerçeve (`.frame`).** 1 pt %8'lik basılı çerçeve, etiketi içeride sol üstte. Yalnızca
  toplantı detayındaki Details grubu için kullanılır.
- **Sistem şeması (`.schem`).** Mac'in çizgi çizimidir (150×92). Notch ve mikrofon
  baştan yanar. Bildirim, hoparlör ızgaraları, `fn` tuşu ve metin imleci ilgili izin
  açılınca turkuaz yanar. "Turn on all" sırasında üstünden tarayıcı geçer ve parçalar
  lambalarla aynı anda (0.42 sn arayla) yanar. Onboarding izin adımındadır.

Bu eklemelerin her biri bir ya da iki yerde durur. Yeni bilgi eklemezler, mevcut bir
satırın ya da göstergenin yerini alırlar. Başka yüzeylere yayılmaları gerekmez.

## Notch: üç boy

| Boy | Ölçü | Ne zaman |
| --- | --- | --- |
| Kompakt | iki eşit kulak + 186 kamera boşluğu, yükseklik 32, alt yarıçap 10 | süreklilik bilgisi |
| Şerit | genişlik 440, kulaklar + 38 pt bir satır, alt yarıçap 18 | istemler, canlı dikte, sonuç |
| Açık | genişlik 480, alt yarıçap 24, omuz 14 | panel |

- **Kulaklar.** Sol kulak *ne* olduğunu (ikon + başlık, en fazla 118 pt), sağ kulak *sayıyı*
  söyler (segment + birim). Boşta notch, donanım notch'u boyutundadır.
- **Şerit.**
  - Paneli asla kendiliğinden açmaz. Altta tek bir satır açılır: bir cümle, bir meta ve
    en fazla iki buton.
  - Üzerine gelmek paneli açmaz, çünkü şeridin butonları vardır; kulaklara tıklamak açar.
  - Sonuç şeritleri 8 sn sonra, "eklendi" şeridi 3 sn sonra kapanır.
- **Açık panelin bandı.**
  - Kamera bandı panelin krom alanıdır: solda sekmeler (Today · Tasks), sağda Kayıtlar,
    pencere ve sabitle.
  - Seçili sekmenin altındaki ışıklı çizgi (lamba) sekmeler arasında yaylı kayar.
  - Band kaydırmada yapışık kalır.

### Hareket

- **Şekil.** Genişlik ve yükseklik yaylı değişir: 0.52 sn, `cubic-bezier(.3,1.16,.4,1)`.
  İçerik şekilden sonra belirir (0.11–0.12 sn gecikmeyle 0.18 sn).
- **Yaklaşma.** İmleç kompakt notch'a girince şekil 14×4 pt büyür, 180 ms sonra açılır.
- **Kademeli giriş.** Panel açılınca veya ekran değişince bölümler 28 ms arayla 5 pt
  yukarıdan süzülerek gelir.
- **Kontak.** Panel kapalıdan açılınca tik halkaları önce tama tarar (0.42 sn), sonra
  değerine iner (0.52 sn). VU metreler de tamdan başlayıp düşer. Bu, panel her
  açıldığında bir kez olur; sekme değişiminde olmaz.
  Masaüstünde de aynısı sayfa değiştiğinde bir kez olur. Aynı sayfanın başka bir
  durumuna geçmek taramayı tekrarlamaz.
- **Nabız ve yanıp sönme.** Kayıt lambası 1.4 sn'de nefes alır. Bekleyen lamba 1.1 sn'lik
  adımlarla yanıp söner.
- **Lamba yanışı.** Onboarding'de "Turn on all" lambaları 0.42 sn arayla, kısa bir parlama
  ile sırayla yakar.

## Ekranlar

- **Kapalı notch durumları.**

  | Durum | Sol kulak | Sağ kulak | Ek |
  | --- | --- | --- | --- |
  | Toplantı (bugün, > 60 dk) | tür ikonu + başlık | başlangıç saati | |
  | Toplantı (≤ 60 dk) | aynı | dakika + "min" | beyaz fitil |
  | Toplantı (≤ 10 dk) | amber ikon | amber dakika | amber fitil |
  | Süren toplantı | amber lamba + başlık | kalan + "left" | fitil |
  | Başlıyor | şerit: "Starting now" · Later `esc` · **Join ↩** | | |
  | Arama algılandı | amber yanan video ikonu; şerit: "Record this call?" · Not now `esc` · **Record ↩** | | |
  | Kayıt | kırmızı nabız + süre | merdiven; mute okunamıyorsa amber parantezli mic | |
  | Bitti sanılıyor / otomatik durdurma | şerit, kırmızı fitil, segment geri sayım | | |
  | Dikte | şerit: konuştukça akan metin, eskisi solda solar, ışıklı imleç | | |
  | Dikte yazılıyor | metin söner, üstünden tarayıcı geçer | 3 hücre | |
  | Dikte eklendi | yeşil lamba + uygulama | | Undo ⌘Z |
  | İşleme | adım kelimesi | 4 istasyon hücresi; canlı olan yanıp söner | |
  | Sonuç | şerit: "Notes and 3 action items" · Later `esc` · **Open ↩** | | |
  | Hata | kırmızı uyarı karosu + başlık; şerit: neden + "audio is saved" · **Retry ↩** | | |
  | Dikte izni yok | kırmızı parantezli mic; şerit: neden · Settings | | |
  | Görev | ilerleme işareti + başlık | dakika | |
  | Görevler | kuyruk ikonu + "Today" | sayı | |

- **Today.**
  - Kahraman: tik halkası, başlık (hero), saat aralığı · sağlayıcı ve katılımcılar.
  - Join yalnızca 10 dk içinde veya toplantı sürerken görünür. O zaman kahramanın altında
    konsol açılır: solda lambalı durum, sağda Record ⌘R ve **Join ⌘J**.
  - Altında gün cetveli, sonra tarife düzeni bir liste gelir. Solda 42 pt'lik saat sütunu
    vardır: başlangıç ink-1, bitiş meta. Gruplar Today ve Later'dır, yanlarında sönük
    sayılar bulunur. Davet, satırın sağında amber lamba + "Invite" ile gösterilir.
  - Boş durumlar: dinlenen bir gösterge (`--:--`), bir cümle ve tek bir düzeltme.
- **Kayıt.**
  - 34 pt segment süre gösterilir, arkasında kırmızı ışık sızması vardır. Sağda iki
    itme düğmesi bulunur: mikrofon (altında lamba) ve durdur.
  - Altında şerit kaydedici, kaynak başına peak-hold VU ve "mic follows mute" lamba
    satırı yer alır. Uyarılar tek satırdır.
- **İşleme.**
  - Tek raydaki dört istasyon: Saved, Uploaded, Transcribing, Notes. Canlı istasyonun
    hücresi yanıp söner.
  - Altında canlı istasyonun ayrıntısı vardır: yükleme yüzdesi segmentle, belirsiz
    süreler tarayıcıyla gösterilir.
- **İşleme.** Altta eylem satırı bulunur: solda "The audio is already safe on this Mac",
  sağda Stop `esc`.
- **Sonuç.** Üç okuma tek bir kuyuda durur (süre · konuşmacı · sana düşen). Eylem
  satırında solda "Kept in Recordings", sağda Done `esc` · **Open notes ↩** bulunur.
  Hatada: Recordings · **Try again ↩**.
- **Kayıtlar.**
  - Üstte haftalık gösterge bulunur: toplam saat ve gün çubukları, bugün yanar.
  - Satırlar tarife düzenindedir (saat / süre). Lamba yalnızca dikkat isteyen satırda
    görünür.
- **Toplantı detayı.**
  - Dalga formu çubuklarıyla tüm toplantı gösterilir. Çalınan kısım ink-1'dir, amber iğne
    konumu gösterir; tıklamak o noktaya atlar. Altında konuşma süresi çubuğu ve
    konuşmacılar bulunur.
  - Summary (sağında Rewrite xs) · Decided (numaralı) · For you · Transcript bölümleri
    gelir. For you ve Transcript aynı düzeni kullanır: zaman damgası solda, eylem sağda.
    Eklenmemiş madde **+ Add** (xs secondary) taşır; eklenince yerinde turkuaz lambalı
    "In Tasks" bir kez parlayarak belirir.
- **Görevler.**
  - Giriş 44 pt yüksekliğindedir ve sağında `↩` tuş ipucu bulunur. Ayrıştırılan
    değerler lambalı çiplerle gösterilir; çipe tıklamak değeri düşürür. Tamamlama
    hayalet metinle ve `tab` ipucuyla sunulur.
  - Today grubunun sağında günün ilerlemesi hücrelerle gösterilir (biten / toplam).
  - Satır 38 pt'dir. Sağda süre (segment), öncelik çubukları, tekrar ikonu ve tarih
    bulunur.
  - Altta eylem satırı bulunur. Solda depo lambası ("Synced with Reminders" ya da "On
    this Mac only"), sağda Finished ya da Connect Reminders. Finished görünümünde:
    Clear (danger) · Open tasks.
  - Görev kartının altında solda kaynak çipi bulunur, sağda Delete (danger) ve
    Close `esc` durur.

## Masaüstü penceresi

1240×760. Üç katman vardır: kenar çubuğu (`#080807`), pencere zemini (`#0e0e0d`) ve
detay sayfası (`#121211`, bir kat yukarıda, yarıçap 14).

- **Kenar çubuğu (224 pt).**
  - Marka satırında ikon karosu, "Crenel" ve sönük segment saat bulunur.
  - Ray (`.rail`): Today · Meetings · Tasks · Dictation; altta Settings. Seçili öğenin
    solunda 3×14 pt'lik ışıklı bir lamba vardır ve öğeler arasında yaylı kayar (0.34 sn,
    `cubic-bezier(.3,1.2,.4,1)`). Satırın sağında sönük bir okuma durur: "in 33 min",
    sayılar, "fn".
  - Kayıt sürerken rayın altında bir kuyu kartı açılır: lamba, merdiven, segment süre,
    mic ve Stop.
  - **Systems paneli:** tek satırda altı uyarı lambası ikonu durur, metin etiketi yoktur
    (Calendar, Reminders, Microphone, Call audio, Mute sync, Keyboard). Adları tooltip'te
    görünür. Sorunlu olan parantezli ya da rozetli yanar. Her biri kendi ayar sayfasına
    götürür. Başlığın sağında "6 of 6 on" ya da amber "needs you" yazar.
- **Araç çubuğu (60 pt).** Solda sayfa başlığı (17/600) ve meta, sağda sayfanın
  eylemleri (secondary, tuş kapaklı) ve arama alanı (30 pt, çukur) bulunur.
- **Today (gösterge panosu).**
  - Kahraman paneli: 148 pt tik halkası (dakika; basılı bölgeler ve ölçek sayıları), "Next meeting" başlığı (22/600), saat ·
    sağlayıcı, yüz yığını ve katılımcılar bulunur. Sağ kenarda yukarıda "Join opens at
    11:05" lambası, aşağıda Copy link · Calendar butonları yer alır.
  - Altında etiketli geniş gün cetveli bulunur.
  - Üç gösterge karosu: Tasks (açık sayı + hücreler + 3 satır), On tape (haftalık saat +
    LED yığınları), Dictation (bugünkü kelime + şerit kaydedici + son cümle).
  - Recent meetings paneli: sağ üstte All meetings (xs).
- **Meetings.**
  - Solda liste (300 pt): All · Needs you · For you segment kontrolü ve gruplar. Seçili
    satırın solunda ışıklı lamba çizgisi vardır.
  - Sağda detay sayfası:
    - Başlık (22/600), meta çipleri (tarih, süre, sağlayıcı, kişiler).
    - Sağda ⋯ · Export ▾ · Copy notes ⇧⌘C.
    - Oynatıcı kuyusu: düğme, segment zaman, dalga formu, altında konuşmacı şeridi,
      hız butonu.
    - Gövde iki sütundur: solda Summary/Decided/Transcript, sağda 232 pt ray (For you +
      Add, Talk time çubukları, Details anahtar-değer).
- **Tasks.** Solda ortak görev listesi bulunur. Sağda ray yer alır: günün turkuaz tik
  halkası (biten/toplam), Due (lamba + segment saat) ve Reminders senkron paneli.
- **Dictation.**
  - Kahraman panelinde 76×72 pt'lik basılı bir `fn` tuş kapağı (üstünde turkuaz lamba),
    açıklama, mod/dil/yer çipleri ve kuyuda iki okuma (words today, dictations) bulunur.
  - Altında Recent listesi (saat/uygulama sütunu, kopyala ikon butonu) ve Words to know
    paneli yer alır.
- **Settings.**
  - İkinci bir ray (200 pt) bulunur ve her bölümün sağında durum lambası vardır.
  - Her sayfa bir başlıkla açılır: 40 pt kabarık ikon karosu, başlık, bir cümle ve
    sağda bir okuma:
    - AI'da yedek zinciri lambaları (Anthropic › OpenAI › This Mac),
    - Calendar ve Data'da kuyu içinde segment sayılar.
  - Gruplar 14 pt yarıçaplı, hafif kabarık kartlardır. Grup başlığı kartın içindedir.
  - Anahtar girişinin yanında Verify and save (secondary) bulunur. Remove (danger) durum
    satırında durur, kaydetme butonunun yanında değil.
- **Onboarding.**
  - Bir kontak kontrolüdür: hoş geldin ekranında büyük tik halkasının içinde turkuaz
    işaret tarar.
  - İzin satırları secondary Allow/Open taşır ve bir lambayla biter.
  - Altta Not now `esc` · **Turn on all ↩** butonları bulunur.
- **Anahtar.** Topuzunda, açıkken yanan turkuaz bir lamba vardır.

## İnceleme

- Prototip: tarayıcıda açılır, sağdaki menüden her duruma gidilir. `[`/`]` ile adım
  atılır; Flows bir senaryoyu oynatır.
- Swift render'ları: `touch /tmp/MeetingNotchExportUIAudit` sonrası
  `CrenelDesignGalleryTests` ve `DesktopWorkspaceTests` çalıştırılırsa `artifacts/ui-audit/`
  altına yazılır.
