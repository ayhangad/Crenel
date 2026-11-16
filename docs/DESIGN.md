# Crenel tasarım dili — "enstrüman"

Durum: uygulandı (2026-11-16). Kod: `MeetingNotch/Features/Design/System/` (`Hud*`).
Eski `Crenel*` token/bileşen adları çağrı yerlerinde duruyor ama değerlerini `Hud`'dan
alıyor. `MeetingNotchTheme` ve Figma görselleri kaldırıldı.

## İlkeler

1. **Önce tasarım, sonra metin.** Bilgiyi konum, ikon ve renk verir. Metin yalnızca
   başka hiçbir şey söyleyemediğinde kullanılır. Açıklama cümlesi ve sayaç tekrarı yok.
2. **Tek font, doğal aralık.** Yalnızca gömülü Geist (OFL) kullanılır:

   | Stil | Boyut ve ağırlık | Kullanım |
   | --- | --- | --- |
   | `.title` | 15 semibold | |
   | `.body` | 13.5 medium | |
   | `.label` | 12.5 medium | grup başlığı, sekme, buton |
   | `.meta` | 12 regular | ikinci satır |
   | `.display` | 22 semibold | sayaç |

   Harf aralığı artırılmaz, büyük harf kullanılmaz, mono font yoktur. Rakamlar tabulardır.
3. **Tek gri skala.**
   - Metin ve ikon: eşit kanallı saf griler (0.95 / 0.66 / 0.45 / 0.30).
   - Yüzey: aynı beyazın düşük opaklıkları (hover %6, seçili %10, basılı %12, iz %9).
   - Renk yalnızca durum içindir:

     | Renk | Anlamı |
     | --- | --- |
     | amber (`signal`) | seni bekliyor: yaklaşan toplantı, davet, öncelik, devam eden görev |
     | kırmızı (`live`) | canlı kayıt, bloke iş, hata |
     | yeşil (`ok`) | yalnızca bağlı / hazır onayı |

4. **Çizgi yok.** Gruplar boşlukla ayrılır. Ayırıcı, noktalı çizgi, kenarlık ve kart
   çerçevesi kullanılmaz. Gerekirse yalnızca hafif bir dolgu (`Hud.Ink.hover`).
5. **Tek ikon ailesi.**
   - 16 birimlik ızgara, 1.5 çizgi, kare uç.
   - İkon asla daire veya kutu içine alınmaz.
   - Durum için onay işareti kullanılmaz.
6. **Ferah ama kompakt.**
   - Panel 490 pt.
   - Metin duvardan 30 pt içeride; hover zemini metnin 10 pt dışına taşar.
   - İki satırlı satır 48 pt, görev satırı 38 pt.
7. **Hiçbir şey zıplamaz.**
   - Satır yüksekliği ve girintiler her durumda aynıdır; hover dolguyu değiştirmez.
   - Tek bir hover zemini satırlar arasında kayar.
8. **Akışkanlık.**
   - Notch tek şekildir ve içeriğini kapsar (taşanı keser). Şekil yayla büyür; içerik
     ondan sonra belirir.
   - Sekme seçimi kayan zemindir. Geri sayımlar rakam rakam döner.
   - Kayıt noktası nefes alır, ses çubukları seviyeyle yükselir.

## Ekranlar

- **Kapalı notch.**
  - Kamera yuvasının iki yanında eşit iki kulak bulunur. İçerik kulağında ortalıdır;
    genişlik duruma göre değişir.
  - Alt yarıçap 10.
  - Durumlar:

    | Durum | Sol kulak | Sağ kulak |
    | --- | --- | --- |
    | Toplantı | tür ikonu + saat | kalan dk; 10 dk içinde amber |
    | Kayıt | kırmızı nabız + süre | seviye çubukları; mikrofon kapalıysa mic-off |
    | Dikte | mikrofon | seviye çubukları ya da 3 adım |
    | İşleme | yazılan sayfa (nefes alır) | 4 adımlı ilerleme |
    | Görevler | kuyruk ikonu | sayı |
    | Boşta | — | — |

    Boşta notch, donanım notch'unun boyutundadır.
- **Araç çubuğu.** Ortada sekmeler: Today · Tasks (rozetli). Solda Kayıtlar (geçmiş).
  Sağda pencere ve sabitle.
- **Today.**
  - Odak bloğunda etiket ve buton yoktur:
    - tür ikonu, başlık, sağda kalan dk ya da saat;
    - altında mekân ve saat aralığı ya da gün;
    - 60 dk içinde segmentli çubuk.
  - Gruplar yalnızca **Today** ve **Later**. Satır: başlık | başlangıç; alt satırda
    mekân | bitiş ya da gün.
  - Davetin saati amber yazılır.
  - Tıklayınca bağlantı ya da Takvim açılır. Katıl veya Kayıt butonu yoktur; "Record
    now" bağlam menüsündedir.
- **Kayıtlar (geçmiş).** Gün gruplu liste:
  - satır: başlık | saat;
  - alt satır: yalnızca dikkat isteyen durum | süre.
- **Tasks.**
  - Giriş alanı en üsttedir. Yazarken tarih, tekrar ve öncelik canlı tanınır ve alanın
    altında gösterilir; tıklayınca o değer düşer.
  - Daha önceki başlıklar satır içinde tamamlanır (Tab). Hiçbir şey tanınmadıysa hızlı
    seçenekler çıkar: Today, Tomorrow, Priority.
  - Gruplar **Today**, **Later** ve **Done**. Durum işareti doluluk seviyesidir; bloke
    için bir çubuk vardır.
  - Kart yerinde açılır.
- **Kayıt (açık notch).** Nabız ve büyük süre; sağda mikrofon ve durdur ikon butonları.
  Kaynak satırlarında segmentli seviye göstergesi vardır; kapatılan kaynak sönükleşir.
  Uyarılar tek satırdır.
- **İşleme.**
  - Dört adım: Saving audio, Uploading, Transcribing, Summarizing. Aktif adım beyazdır
    ve segmentli gösterge taşır; bitenler gri, sıradakiler koyu gridir.
  - Sonuç satırı: Ready / hata ve tek birincil eylem.
- **İstemler.** Tek satır, hafif dolgulu.
  - Algılanan toplantı: "Not now" · "Record".
  - Bitiş: geri sayım · "Keep" · "Stop".
- **Masaüstü, toplantı detayı, kurulum, ayarlar.** Aynı satır sistemini, sade grup
  başlıklarını, hayalet ve tek birincil butonu kullanır. Pencere zemini 0.06, kenar
  çubuğu 0.04.

## İnceleme

`touch /tmp/MeetingNotchExportUIAudit` sonrası `CrenelDesignGalleryTests` ve
`DesktopWorkspaceTests` çalıştırılırsa render'lar `artifacts/ui-audit/` altına yazılır.
