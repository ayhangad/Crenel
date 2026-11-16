# Crenel tasarım önerisi — "enstrüman"

Durum: öneri. Yalnızca **Bugün** ekranı ve kapalı notch durumları çizildi
(`artifacts/ui-audit/proposal/`). Onaydan sonra aşağıdaki plana göre tüm ekranlara
uygulanacak. Kod: `MeetingNotch/Features/Design/Proposal/`.

## İlkeler

1. **Bir bakışta okunur araç.** Her ekran tek bir soruya cevap verir; cevaba hizmet
   etmeyen öğe yoktur. "Bu olmasa ne kaybederiz?" sorusunun cevabı yoksa çıkar.
2. **Renk = durum.** Arayüz nötr gri. Renk yalnızca anlam taşır:
   - `signal` (amber): seni bekleyen şey — 10 dk içindeki toplantı, devam eden görev.
   - `live` (kırmızı): canlı kayıt, bloke görev, hata.
   - `ok` (yeşil): yalnızca bağlantı/izin onayı. Dekor olarak hiç kullanılmaz.
   Takvim renkleri, kart gradyanları, renkli butonlar yok. Birincil eylem beyaz.
3. **İki yazı.** Kelimeler Inter (13 medium satır, 15 semibold odak başlığı, 12 regular
   ikincil). Sayılar, saatler ve küçük BÜYÜK HARF etiketler SF Mono (10 pt, +1.1 izleme).
   Toplam beş stil; başka boyut yok.
4. **Tek ikon ailesi.** 16 birim ızgara, 1.5 çizgi, kare uç, keskin köşe. İkon hiçbir
   zaman daire ya da kutu içine alınmaz; satırın metin renginde, yüzeyde durur.
   Görev için onay işareti yok: durum doluluk seviyesiyle anlatılır (boş · yarım · dolu,
   bloke için çizgi).
5. **HUD izleri, kostüm değil.** Yalnızca dört araç: mono büyük harf etiket, etiketi
   değere bağlayan noktalı çizgi, segmentli gösterge (toplantıya kalan süre, ses seviyesi,
   işlem adımı) ve klavye kısayolu ipuçları (`¹ ²`, `⌘R`). Piksel ikon, dither, tarama
   çizgisi yok.
6. **Hiçbir şey zıplamaz.** Satır 32 pt sabit, içerik girintisi her durumda aynı. Hover
   yalnızca altına düz bir dolgu serer (opaklık 0 → 5.5 %, 120 ms). Ölçek, kenarlık,
   kalınlık değişimi yok. Kapalı notch'ta iki kulak her durumda 64 pt — içerik değişince
   notch genişliği değişmez.
7. **Hareket tek eğri.** Yerinde değişimler `smooth 240 ms`; notch biçim değişimi
   sönümlü yay (0.4 s, 0.92), taşma yok. Segmentler tek tek yanar.

## Yerleşim iskeleti (açık notch)

- **Kulaklar:** sekmeler kamera yuvasının iki yanında — sol `Bugün¹`, sağ `Görevler² 3`.
  Seçili sekme parlak ve altında 14 pt çizgi; ⌘1/⌘2 ile geçilir.
- **Gövde:** 480 pt, 20 pt kenar boşluğu, tek sütun.
- **Alt çubuk:** ince çizgi, solda hayalet buton (bağlama göre `Geçmiş` / `Tümü`),
  sağda pencere ve sabitle ikonları.

## Ekranlar ve durumları

### 1. Kapalı notch (çizildi)
| Durum | Sol kulak | Sağ kulak |
|---|---|---|
| Sıradaki toplantı (≤ 60 dk) | takvim ikonu + saat | kalan dk (≤ 10 dk amber) |
| Kayıt | kırmızı nokta + süre | 5 sütunluk ses göstergesi |
| Dikte | mikrofon | ses göstergesi |
| İşleniyor | spark | adım adı + 5 segment |
| Boşta, açık görev var | kuyruk ikonu | görev sayısı |
| Hiçbir şey yok | — (donanım notch'u, genişlemez) | — |
Hata: sağ kulakta kırmızı kısa metin; tıklayınca panel açılır.

### 2. Bugün (çizildi)
Soru: *Sıradaki ne, şimdi bir şey yapmam gerekiyor mu?*
- **Odak bloğu** (kart değil): `SIRADAKİ ···· 8 DK`, başlık, `15:00–15:45 · Google Meet`.
  60 dk içinde 24 segmentlik gösterge kalan süreyle boşalır; toplantı başlayınca
  `ŞİMDİ ···· 33 DK KALDI` olur ve gösterge geçen süreyle dolar.
  `Katıl` (beyaz) yalnızca link varsa ve ≤ 10 dk / canlıysa; `Kaydet ⌘R` hayalet.
  Uzak toplantıda (bugün değil) gösterge ve butonlar yok, sadece `YARIN`.
- **Ajanda:** günlere göre gruplu (`BUGÜN · 15 KAS PAZ ···· 1`), satır: mono saat ·
  başlık · (link varsa video ikonu) · süre. Odak toplantı listede tekrar etmez.
  Aynı başlık+saatteki etkinlikler tek satır (iki takvimden gelen kopyalar).
- **Görevler ve son kayıtlar bu ekranda yok.** Geçmiş alt çubuktaki butonla açılır.
- Boş durumlar: takvim bağlı değil → tek satır açıklama + `Takvimi bağla` hayalet;
  7 günde hiç etkinlik yok → `Önümüzdeki 7 gün boş.` metni.

### 3. Görevler
Soru: *Şu an ne üzerinde çalışıyorum, sırada ne var?*
- Gruplar mono etiketle: `DEVAM EDİYOR · BLOKE · YAPILACAK · BİTTİ (son 5)`.
- Satır: durum işareti · başlık · (sağda) öncelik `!!` mono, tarih mono, kaynak ikonu.
- Durum işaretine tıklama: işaretin hemen sağında dört durumlu yatay seçici satır içinde
  açılır (satır yüksekliği değişmez, başlık sağa kayarak yer açar). 1–4 tuşları.
- Satıra tıklama: panel yatayda detay sayfasına kayar (aşağıda), liste genişlemez.
- Üstte tek satır hızlı ekleme: `+ Görev ekle` alanı; yazarken "yarın", "!!" gibi
  ayrıştırılan değerler mono etiket olarak satır sonunda belirir.

### 4. Görev detayı
- Başlık (düzenlenebilir, 15 semibold). Altında etiket–değer satırları noktalı çizgiyle:
  `DURUM ···· Devam ediyor`, `TARİH ···· Yarın 10:00`, `TEKRAR ···· Her hafta`,
  `ÖNCELİK ···· Yüksek`, `KAYNAK ···· Hatırlatıcılar`. Değere tıklayınca satır içi seçici.
- Not alanı: düz metin, çerçevesiz. Alt çubuk: `← Görevler` ve `Sil`.

### 5. Kayıt (açık notch)
- `KAYIT ···· CANLI` (kırmızı), büyük mono süre `12:34`, toplantı adı.
- Kaynak satırları: `MİKROFON ···· [segment göstergesi] MacBook Mikrofonu`,
  `SİSTEM SESİ ···· [gösterge] Google Meet`. Mikrofon kapatıldığında satır sönükleşir.
- Eylemler: `Durdur` (beyaz), `Mikrofonu kapat ⌘M` hayalet.
- Otomatik durdurma uyarısı: aynı yerde `30 sn içinde duracak` + segment geri sayım.

### 6. İşleme (sonlandırma → yükleme → yazıya çevirme → özet)
- Dört adım mono liste; aktif adım beyaz + segment ilerleme, bitenler gri, sıradakiler
  koyu gri. Tamamlanınca `TOPLANTI HAZIR` + `Aç` (beyaz) + `Kapat`.
- Hata: `İŞLEM DURDU` kırmızı etiket, tek cümle sebep, `Tekrar dene` / `Kaydı göster`.

### 7. Dikte
- Kapalı notch'ta mikrofon + seviye. Konuştukça notch aşağı doğru tek satırlık canlı
  metin şeridine genişler (sabit yükseklik, metin soldan kayar).
- Sonuç: `EKLENDİ ···· Notes` ya da `GÖREV OLUŞTURULDU` 2 sn görünür, sonra kapanır.
- Hata: kırmızı etiket + tek cümle + varsa `Ayarları aç`.

### 8. Toplantı istemleri (kayıt teklifi, bitiş onayı)
- Kapalı notch'tan aşağı inen tek satırlık şerit: `Google Meet algılandı` ·
  `Kaydet` (beyaz) · `Yoksay`. Ayrı pencere yok.

### 9. Geçmiş
- Bugün ekranının alt çubuğundan açılan sayfa. Gün gruplu liste: mono saat · başlık ·
  süre. İkon yok, onay işareti yok. Satıra tıklama → toplantı detayı (masaüstü penceresi).

### 10. Toplantı detayı (masaüstü penceresi)
- Sol: başlık, tarih/süre mono satırı, sekmeler `Özet · Kararlar · Görevler · Döküm`
  (metin, ikon yok). Döküm satırları: mono zaman damgası · konuşmacı · metin.
- Ses oynatıcı: segmentli ilerleme çubuğu + mono süre.
- Özetten görev oluşturma: satır sonunda `+ Görev` hayalet.

### 11. Masaüstü çalışma alanı
- Sol kenar çubuğu: `Toplantılar · Görevler · Ayarlar` metin listesi, mono sayılar.
- İçerik: Geçmiş ile aynı satır sistemi, daha geniş.

### 12. Kurulum (onboarding) ve Ayarlar
- Tek pencere, 520 pt. İzin satırı: ikon · ad · tek satır açıklama · sağda durum
  (`Bağlı` yeşil mono / `Aç` hayalet buton). Gruplar mono etiketle: `TAKVİM VE GÖREVLER`,
  `SES`, `KLAVYE`. Üstte segmentli ilerleme `4/7`.
- Ayarlar aynı satır sistemini kullanır; kartlar yerine etiketli gruplar ve çizgiler.

## Uygulama sırası (onaydan sonra)
1. Token, ikon ve bileşenleri `Crenel` sisteminin yerine geçir; eski Figma asset'leri ve
   `MeetingNotchTheme` kaldır.
2. Kapalı notch + Bugün + Geçmiş.
3. Görevler + detay.
4. Kayıt, işleme, istemler, dikte şeridi.
5. Masaüstü, toplantı detayı, kurulum, ayarlar.
Her adımda tüm durumların render'ı alınıp kontrol edilir.
