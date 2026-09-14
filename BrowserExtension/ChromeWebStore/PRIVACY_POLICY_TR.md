# MeetingNotch for Google Meet — Gizlilik Politikası

Son güncelleme: 14 Eylül 2026

Bu politika, MeetingNotch for Google Meet Chrome uzantısının verileri nasıl işlediğini
açıklar. Yayın öncesinde geliştirici adı, iletişim adresi ve bu belgenin herkese açık HTTPS
URL'si eklenmelidir.

## Uzantının tek amacı

Uzantı yalnız kullanıcının seçtiği Google Meet görüşme sekmesinin sesini, aynı bilgisayarda
çalışan MeetingNotch macOS uygulamasına aktarır. Başka bir amaçla veri toplamaz.

## İşlenen veriler

- Kullanıcı “Meet sekmesini bağla” düğmesine bastığında seçili Google Meet sekmesinin sesi.
- Aktif sekmenin URL'si; yalnız adresin canonical bir `https://meet.google.com` görüşmesi
  olduğunu bellekte doğrulamak için.
- Rastgele oturum kimliği ile ses frame sıra numaraları; yalnız yerel bağlantı bütünlüğü ve
  backpressure denetimi için.

Uzantı toplantı başlığını, sayfa DOM'unu, çerezleri, hesap bilgisini veya tarama geçmişini
okumaz. `host_permissions` istemez.

## Kullanım, aktarım ve saklama

Seçili sekme sesi yalnız Chrome native messaging üzerinden aynı cihazdaki MeetingNotch
uygulamasına gönderilir. Uzantı ses verisini kalıcı olarak saklamaz, bir geliştirici
sunucusuna göndermez ve analytics/telemetry üretmez.

MeetingNotch kullanıcısı uygulamada kayıt başlattıysa yerel uygulama bu sesi toplantı
kaydına ekleyebilir. Kayıt bittikten sonra birleşik ses, kullanıcının kendi API anahtarıyla
konuşmacı ayrımlı transkript üretmek amacıyla ElevenLabs Scribe v2'ye gönderilebilir. Bu
işlem uzantının değil, kullanıcı kontrolündeki MeetingNotch uygulamasının kayıt ve işleme
akışıdır; uygulama onboarding'i ve uzantı popup'ı bu sınırı yakalama başlamadan açıklar.
OpenAI bağlantısı açıksa yerel uygulama transkript metnini, konuşmacı adlarını ve zaman
bilgilerini özet, karar ve görev oluşturmak için kullanıcının OpenAI API anahtarıyla
OpenAI’ye gönderir. Uzantı bu servislerle doğrudan iletişim kurmaz. API anahtarları
yalnız yerel uygulamanın macOS Keychain alanında saklanır.

## Paylaşım ve yasak kullanımlar

Veri satılmaz; reklam, yeniden hedefleme, kredi değerlendirme veya kullanıcı profilleme
için kullanılmaz. İnsanların kullanıcı sesini okumasına/dinlemesine izin verilmez. Veri
yalnız uzantının açıklanan tek amacını sağlamak için işlenir.

Bilgilerin kullanımı Chrome Web Store User Data Policy ve Limited Use gereklerine uyar.

## Kullanıcı kontrolü

Kullanıcı popup'taki “Bağlantıyı kes” düğmesiyle aktarımı durdurabilir. Sekmenin kapanması,
başka adrese gitmesi, Chrome'un kapanması veya yerel köprünün kopması da aktarımı otomatik
olarak durdurur. Uzantı kaldırıldığında uzantıda saklanan kullanıcı verisi yoktur.

## İletişim — yayın öncesi doldurulacak

Geliştirici: `YAYIN_ONCESI_DOLDUR`

E-posta: `YAYIN_ONCESI_DOLDUR`
