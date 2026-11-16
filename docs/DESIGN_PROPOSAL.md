# Crenel tasarım önerisi — "enstrüman"

Durum: öneri. Yalnızca **Bugün** ekranı ve kapalı notch durumları çizildi
(`artifacts/ui-audit/proposal/`). Onaydan sonra aşağıdaki plana göre tüm ekranlara
uygulanacak. Kod: `MeetingNotch/Features/Design/Proposal/`.

## Canlı önizleme

`open Crenel.app --args -CrenelProposal YES` — öneri gerçek notch konumunda çalışır
(normal notch bu modda gösterilmez). Üzerine gelince açılır; kapalıyken durumlar 4 sn'de
bir döner (toplantı → kayıt → dikte → işleme → görevler).

## İlkeler (revizyon 2)

1. **Önce tasarım, sonra metin.** Bilgi konum, ikon ve renkle verilir; metin yalnızca
   başka hiçbir şey söyleyemediğinde. Etiket, açıklama, sayaç tekrarı yok.
2. **Tek font, doğal aralık.** Yalnızca Inter: 16 semibold odak başlığı, 13.5 medium satır,
   12.5 medium grup başlığı/buton, 12 regular ikincil. Harf aralığı artırılmaz, büyük harf
   yok. Rakamlar tabular (saatler kaymaz). Mono font kullanılmaz.
3. **Tek gri skala.** Eşit kanallı saf griler (0.95 / 0.66 / 0.45 / 0.30) ve aynı beyazın
   düşük opaklıkları (hover 6 %, seçili 10 %). Renk yalnızca durum: amber = seni bekleyen,
   kırmızı = canlı / bloke, yeşil = onay.
4. **Çizgi yok.** Gruplar boşlukla ayrılır; ayırıcı çizgi, noktalı çizgi, kenarlık yok.
5. **Ferah ama kompakt.** 500 pt panel, 30 pt kenar boşluğu, iki satırlı 50 pt satır,
   başlık–alt satır arası 5–6 pt, bloklar arası 24 pt.
6. **Akışkanlık.**
   - Notch tek şekil: kapalı ↔ açık yay ile biçim değiştirir, içerik ölçekle ve opaklıkla
     gelir.
   - Sekme seçimi ve satır hover'ı tek bir zemin olarak öğeler arasında kayar.
   - Sekme içeriği yönlü kayarak değişir; geri sayımlar rakam rakam döner; kayıt noktası
     nefes alır; ses çubukları seviyeyle yükselir; işleme adımı uzayarak ilerler.
7. **Hiçbir şey zıplamaz.** Satır yüksekliği ve girintiler her durumda aynı; kapalı notch'un
   iki kulağı her durumda 70 pt.

## Yerleşim

- **Sekmeler:** kameranın hemen altında ortalı; ikon + kelime, seçili sekmede kayan yumuşak
  zemin. Numara yok.
- **Gövde:** odak bloğu → `Bugün` → `Sonra` → alt çubuk (`Geçmiş` · pencere · sabitle).

## Ekranlar ve durumları

### 1. Kapalı notch (çizildi)
Sıradaki toplantı: takvim ikonu + saat | kalan dk (≤ 10 dk amber). Kayıt: nefes alan
kırmızı nokta + süre | ses çubukları. Dikte: mikrofon | ses çubukları. İşleme: nabız atan
spark | 4 adımlı ilerleme. Görevler: kuyruk ikonu | sayı. Boşta: donanım notch'u.

### 2. Bugün (çizildi)
- **Odak bloğu:** etiket yok. Solda başlık + mekân (ikon + tek kelime), sağda kalan süre
  (amber) + saat aralığı. 60 dk içinde segmentli çubuk ve `Katıl` + kayıt butonu.
  Uzaktaysa sağda saat + gün, çubuk ve buton yok.
- **Gruplar:** yalnızca `Bugün` ve `Sonra`. Satır: başlık | başlangıç saati; alt satırda
  mekân | bitiş saati (Bugün) ya da gün (Sonra).

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
