# Crenel Chrome extension

Bu Manifest V3 extension yalnız kullanıcının action tıklamasıyla aktif, canonical
`meet.google.com` çağrı sekmesinin audio stream'ini açar. Başka origin veya Meet ana sayfası
capture edilemez. Tab sesi kullanıcıya yerel olarak geri oynatılır; 20 ms PCM chunk'ları
`com.gad.crenel.browser_audio` native messaging host'una sıra/backpressure protokolüyle
gönderilir. Host yoksa veya ACK zinciri koparsa capture fail-closed durur.

Development extension ID: `cdoilhpndmdimjbnagfgldhkjojjjjha`.

## Yerel doğrulama

```sh
npm test
```

Native host uygulama paketindeki `Contents/Library/LaunchServices` klasörüne gömülür;
Crenel açılışta sabit extension origin allowlist'li Chrome native-host manifestini
kullanıcı hesabına kurar. Yerel uçtan uca deneme için:

1. Crenel Debug uygulamasını bir kez açın.
2. `chrome://extensions` sayfasında Developer mode'u açıp `Load unpacked` ile bu klasörü seçin.
3. Canonical bir `meet.google.com/abc-defg-hij` görüşme sekmesini aktif edin.
4. Crenel extension action'ını açın, veri kullanımı açıklamasını okuyup `Meet sekmesini
   bağla` düğmesine basın; badge `REC`, Ayarlar durumu `Sekme bağlı` olmalı.
5. Başka bir sekmede canary ses çalarken yalnız Meet sekmesinin kayda girdiğini doğrulayın.

Unpacked yükleme yalnız geliştirme/QA içindir. Store metni, gizlilik politikası, varlıklar ve
paket betiği `browser-extension/chrome-web-store` altında hazırlanmıştır. Production dağıtımı
dashboard ID eşleştirmesi, herkese açık politika URL'si ve fiziksel privacy canary
tamamlanana kadar release blocker olarak kalır.
