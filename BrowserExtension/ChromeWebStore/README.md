# Chrome Web Store yayın paketi

`LISTING_TR.md` dashboard metinlerini, `PRIVACY_POLICY_TR.md` yayımlanacak gizlilik
politikasını, `assets/` ise yükleme varlıklarını taşır. Kod ZIP'i şu komutla üretilir:

```sh
Scripts/chrome-web-store-package.sh
```

Yayın sırası:

1. Üretilen ZIP'i Developer Dashboard'a taslak olarak yükleyin; henüz yayınlamayın.
2. Dashboard item ID'sinin `cdoilhpndmdimjbnagfgldhkjojjjjha` olduğunu doğrulayın.
3. Farklıysa dashboard `View public key` değerini `manifest.json` içindeki `key` alanına
   alın; Swift origin allowlist'i ve protokol testini aynı ID ile güncelleyin. ID eşleşmeden
   yayınlamayın.
4. Gizlilik politikasını herkese açık HTTPS sayfasında yayımlayıp placeholder alanlarını
   gerçek geliştirici ve destek bilgileriyle doldurun.
5. Fiziksel Chrome popup/Meet bağlantısı sırasında 1280×800 gerçek ekran görüntüsü alın;
   test toplantısı dışında kişi, başlık veya transkript göstermeyin.
6. `assets/store-icon-128.png`, `assets/small-promo-440x280.png`, gerçek ekran görüntüsü,
   listeleme metni, izin gerekçeleri ve Privacy Practices formunu dashboard'a girin.
7. Trusted testers ile iki sekmeli canary ve köprü kopma testini tamamlayın; ardından review
   gönderin.

Store hesabı, HTTPS politika adresi, gerçek ekran görüntüsü ve reviewer gönderimi dış
hesap/insan doğrulaması gerektirdiği için repository otomasyonu bunları PASS saymaz.
