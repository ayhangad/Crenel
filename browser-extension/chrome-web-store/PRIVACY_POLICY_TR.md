# Crenel for Google Meet gizlilik politikası

Son güncelleme: 18 Kasım 2026

Bu politika, Crenel for Google Meet Chrome uzantısının verileri nasıl işlediğini
açıklar.

## Uzantının tek amacı

Uzantı yalnız kullanıcının seçtiği Google Meet görüşme sekmesinin sesini, aynı bilgisayarda
çalışan Crenel macOS uygulamasına aktarır. Başka bir amaçla veri toplamaz.

## İşlenen veriler

- Kullanıcı “Meet sekmesini bağla” düğmesine bastığında seçili Google Meet sekmesinin sesi.
- Aktif sekmenin URL'si; yalnız adresin canonical bir `https://meet.google.com` görüşmesi
  olduğunu bellekte doğrulamak için.
- Rastgele oturum kimliği ile ses frame sıra numaraları; yalnız yerel bağlantı bütünlüğü ve
  backpressure denetimi için.

Uzantı toplantı başlığını, sayfa DOM'unu, çerezleri, hesap bilgisini veya tarama geçmişini
okumaz. `host_permissions` istemez.

## Kullanım, aktarım ve saklama

Seçili sekme sesi yalnız Chrome native messaging üzerinden aynı cihazdaki Crenel
uygulamasına gönderilir. Uzantı ses verisini kalıcı olarak saklamaz, bir geliştirici
sunucusuna göndermez ve analytics/telemetry üretmez.

Kayıt başlatıldığında Crenel birleşik toplantı sesini Mac'te saklar. Transkripsiyon için
Apple Speech seçilirse ses Mac'te işlenir. ElevenLabs Scribe v2 seçilirse birleşik ses
ElevenLabs'a, Deepgram seçilirse Deepgram'a gönderilir.

Özet ve görevler için transkript metni, konuşmacı etiketleri ve zaman bilgileri seçilen
sağlayıcıda işlenir. Apple modeli Mac'te çalışır. OpenAI seçilirse metin OpenAI'a,
Anthropic API veya Claude Code seçilirse Anthropic'e gönderilir. Claude Code, Mac'teki
mevcut oturumunu kullanır. API anahtarları macOS Keychain'de saklanır.

## Paylaşım ve yasak kullanımlar

Veri satılmaz; reklam, yeniden hedefleme, kredi değerlendirme veya kullanıcı profilleme
için kullanılmaz. İnsanların kullanıcı sesini okumasına/dinlemesine izin verilmez. Veri
yalnız uzantının açıklanan tek amacını sağlamak için işlenir.

Bilgilerin kullanımı Chrome Web Store User Data Policy ve Limited Use gereklerine uyar.

## Kullanıcı kontrolü

Kullanıcı popup'taki “Bağlantıyı kes” düğmesiyle aktarımı durdurabilir. Sekmenin kapanması,
başka adrese gitmesi, Chrome'un kapanması veya yerel köprünün kopması da aktarımı otomatik
olarak durdurur. Uzantı kaldırıldığında uzantıda saklanan kullanıcı verisi yoktur.

## İletişim

Geliştiriciye [X üzerinden ulaşabilirsiniz](https://x.com/ayhangad).
