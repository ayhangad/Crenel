# Crenel tasarım dili — "gece sürüşü"

Durum: prototipte (2026-11-17), Swift'e aktarılmayı bekliyor. Kaynak:
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
   | yeşil `#5fe0b4` | hazır, bağlı, eklendi |
   | beyaz `#f3f1ec` | etkin, seçili, o an çalışan |
   | kapalı `rgba(255,255,255,.09)` | yok, sırada |

   Yanan lambanın kendi renginde 6–7 pt hafif bir parıltısı vardır.
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
8. **Tek birincil eylem ve tuşu.** Her yüzeyde en fazla bir birincil (açık zeminli) buton
   olur ve tuş ipucunu taşır (`↩`, `⌘J`, `⌘Z`). İkinciller hayalet ya da sessiz butondur.

## İkon ailesi

- 16 birimlik ızgara, 1.5 çizgi, yuvarlak uç ve birleşim.
- Bir ikonda en fazla bir dolu "lamba" ayrıntısı olur: takvimde bugünün karesi, konumda
  merkez, görevlerde ilk kutu.
- İkon asla daire veya kutu içine alınmaz. Durum için onay işareti kullanılmaz.
- Kayıtlar kaset (`i-tape`), tekrar iki ok (`i-repeat`) ile gösterilir.
- Görev işaretleri doluluk düzeyiyle konuşur: açık halka, amber yarım dolu, kırmızı çubuklu,
  koyu dolu.
- Öncelik, sinyal çubuğu gibi 3 artan çubukla gösterilir (`.pri`).

## Göstergeler (Swift'te `Shape` olarak)

- **Segment rakam (`.segd`).**
  - 10×18 birimlik hücre, 2 birim kalınlık. Altıgen segmentlerin uçları sivridir ve
    aralarında 0.55 boşluk bulunur.
  - 7° italik (`skewX(-7)`).
  - Basamak adımı 13, iki nokta adımı 5.
  - Yanan segmentin hafif parıltısı vardır; hayalet segment %7.5 opaktır.
  - Boyutlar: kulakta 13 pt, açık panel kahramanında 24 pt, kayıt süresinde 34 pt.
  - Değer değişince yalnızca segmentler değişir; yerleşim kaymaz.
- **Tik halkası (`.gauge`).**
  - 270° tarama, birim başına bir tik. Her 15. tik ana tiktir: daha uzun ve kalın.
  - Değer, baştan (sol alt) başlayarak yanan tik sayısıdır.
  - Toplantıya kalan süre: son 60 dakika, dakika başına bir tik. Toplantı sürerken kalan
    payı gösterir.
  - Ortada kahraman sayı ve altında micro birim bulunur. Arkasında göstergenin renginde
    %9'luk bir ışık sızması vardır (`.bleed`).
- **Gün cetveli (`.ruler`).**
  - 08–20 aralığında yarım saatte bir tik, saatte bir uzun tik ve her iki saatte bir
    etiket bulunur.
  - Etkinlikler cetvelin üstünde 6 pt'lik ışıklı bloklardır:
    - odakta ink-1,
    - yakında amber,
    - davet amber dış çizgi,
    - kişisel sönük.
  - "Şimdi" amber bir iğnedir. Geçmiş bölüm karartılır.
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
  | Başlıyor | şerit: "Starting now" · Later · **Join ↩** | | |
  | Arama algılandı | şerit: "Record this call?" · Not now · **Record ↩** | | |
  | Kayıt | kırmızı nabız + süre | merdiven; mic kapalıysa mic-off | |
  | Bitti sanılıyor / otomatik durdurma | şerit, kırmızı fitil, segment geri sayım | | |
  | Dikte | şerit: konuştukça akan metin, eskisi solda solar, ışıklı imleç | | |
  | Dikte yazılıyor | metin söner, üstünden tarayıcı geçer | 3 hücre | |
  | Dikte eklendi | yeşil lamba + uygulama | | Undo ⌘Z |
  | İşleme | adım kelimesi | 4 istasyon hücresi; canlı olan yanıp söner | |
  | Sonuç | şerit: "Notes and 3 action items" · **Open ↩** | | |
  | Görev | ilerleme işareti + başlık | dakika | |
  | Görevler | kuyruk ikonu + "Today" | sayı | |

- **Today.**
  - Kahraman: tik halkası, başlık (hero), saat aralığı · sağlayıcı ve katılımcılar.
  - Join yalnızca 10 dk içinde veya toplantı sürerken buton olur; Record onun yanında
    hayalet buton olarak durur.
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
- **Sonuç.** Üç okuma (süre · konuşmacı · sana düşen) ve **Open notes ↩**.
- **Kayıtlar.**
  - Üstte haftalık gösterge bulunur: toplam saat ve gün çubukları, bugün yanar.
  - Satırlar tarife düzenindedir (saat / süre). Lamba yalnızca dikkat isteyen satırda
    görünür.
- **Toplantı detayı.**
  - Dalga formu çubuklarıyla tüm toplantı gösterilir. Çalınan kısım ink-1'dir, amber iğne
    konumu gösterir; tıklamak o noktaya atlar. Altında konuşma süresi çubuğu ve
    konuşmacılar bulunur.
  - Summary · Decided (numaralı) · For you (+ ile Görevlere ekler) · Transcript (zaman
    damgası solda) bölümleri gelir.
- **Görevler.**
  - Giriş 44 pt yüksekliğindedir ve sağında `↩` tuş ipucu bulunur. Ayrıştırılan
    değerler lambalı çiplerle gösterilir; çipe tıklamak değeri düşürür. Tamamlama
    hayalet metinle ve `tab` ipucuyla sunulur.
  - Today grubunun sağında günün ilerlemesi hücrelerle gösterilir (biten / toplam).
  - Satır 38 pt'dir. Sağda süre (segment), öncelik çubukları, tekrar ikonu ve tarih
    bulunur.
  - Altta depo lambası yer alır: Reminders (yeşil) ya da On this Mac (kapalı).
- **Masaüstü, ayarlar, onboarding.**
  - Aynı satır sistemi, tarife listeleri ve lambalı durum kelimeleri kullanılır.
  - Anahtarın topuzunda açıkken yanan yeşil bir lamba vardır.
  - Onboarding bir kontak kontrolüdür: hoş geldin ekranında büyük tik halkası tarar.
    İzin listesindeki her satır bir lambayla biter; "Turn on all" lambaları sırayla yakar.

## İnceleme

- Prototip: tarayıcıda açılır, sağdaki menüden her duruma gidilir. `[`/`]` ile adım
  atılır; Flows bir senaryoyu oynatır.
- Swift render'ları: `touch /tmp/MeetingNotchExportUIAudit` sonrası
  `CrenelDesignGalleryTests` ve `DesktopWorkspaceTests` çalıştırılırsa `artifacts/ui-audit/`
  altına yazılır.
