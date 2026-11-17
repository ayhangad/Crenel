# Hibrit sürüm — kurulum ve kabul

14 Eylül 2026. Bu rehber güncel hibrit akışı anlatır; eski tek servis notlarının yerine geçer.

## Kullanıcı kurulumu

1. Uygulamayı açın, onboarding’de mikrofon, sistem sesi ve desteklenen istemcinin
   toplantı kontrolleri için Accessibility izinlerini tamamlayın.
2. Ayarlar’daki Transkripsiyon bölümüne kendi ElevenLabs anahtarınızı girip kaydedin.
3. Toplantı Notları bölümünde kendi OpenAI anahtarınızı bağlayın. Bağlantı doğrulaması
   küçük bir ücretli metin isteğidir; gerçek kayıt kullanılmaz. OpenAI API bakiyesi gerekir.
4. Bu Mac’in takvimlerini kullanmak için İnternet Hesapları’na hesabınızı ekleyin,
   Takvim’i etkinleştirin. Uygulamada takvim erişimini açın, izni verin, yenileyin.
   Takvim kaynağını değiştirdikten sonra ayarları kaydedin; ardından izlenecek takvimleri seçin.
5. Bildirimler bölümünden macOS iznini verin. Seçili hatırlatma süresinde ve bir dakika
   önce bildirim planlanır. Katıl ve beş dakika ertele aksiyonları kullanılabilir.
   Takvim değişikliklerini takip edebilmesi için uygulama çalışıyor olmalıdır.
6. Google Meet için Chrome köprüsünü kurup görüşme sekmesini uzantı popup’ından bağlayın.
   Otomatik toplantı algılama, tarayıcının bu kullanıcı iznini ortadan kaldırmaz.

Kayıt sonrası ses ElevenLabs’e, oluşan transkript OpenAI’ye gider. OpenAI bağlantısı
olmasa da transkript korunur. Ses kaydı sırasında internet gerekmez; sonraki işleme için
bağlantı ve sağlayıcı kotası gerekir. Anahtarlar/tokenlar ayrı macOS Keychain öğelerindedir.

Geçmiş toplantıyı açıp “OpenAI ile özetle” ile eski kaydı özetleyebilirsiniz. Yeniden
özetleme sesi tekrar yüklemez. Uzun transkriptin bütün parçaları işlenir. Kişiler menüsünde
konuşmacı adı verilebilir; görevlerde sorumlu ve kaynak ses zamanı görünür. “Görevlere ekle”
aynı kaynak aksiyonu tekrar eklemez. Yeniden üretilmiş farklı ifadeli görevleri kullanıcı
kontrol etmelidir; anlamsal olarak benzer bütün görevleri birleştirme garantisi yoktur.

## Google doğrudan bağlantısı — yayıncı kurulumu

Bu işlem bir kez uygulama yayıncısı tarafından yapılır; son kullanıcının Google Cloud
projesi oluşturması gerekmez. Yapılandırma yoksa uygulama açıkça macOS hesabı yolunu sunar.

1. Yayıncının Google Cloud projesinde Calendar API’yi açın ve OAuth consent ekranını
   uygulamanın adı, destek adresi ve yayınlanmış gizlilik politikasıyla yapılandırın.
2. Desktop app türünde OAuth client oluşturun. Test aşamasında deneme hesaplarını ekleyin.
3. Build’e `CRENEL_GOOGLE_CLIENT_ID` ve Google’ın desktop credential’ında varsa
   `CRENEL_GOOGLE_CLIENT_SECRET` ayarlarını verin. Bunların Info.plist karşılıkları
   project.yml içinde tanımlıdır. pbxproj dosyasını elle düzenlemeyin.
4. İstenen kapsamlar `calendar.events.readonly` ve `calendar.calendarlist.readonly`.
   Gmail veya etkinlik yazma izni istenmez. Genel dağıtımdan önce gerekli Google
   consent/verification sürecini tamamlayın.
5. Yapılandırılmış build’de Google hesabını bağlayın. Sistem tarayıcısı, PKCE-S256,
   rastgele state ve `127.0.0.1` üzerinde geçici callback portu kullanılır. Token yenileme
   ve sayfalanmış takvim listesi desteklenir. Bağlantıyı kaldırmak bu Mac’teki tokenı siler;
   Google hesabındaki uygulama yetkisi Google hesap ayarlarından ayrıca kaldırılabilir.

Desktop client bilgisi dağıtılan uygulamadan okunabilir; sunucu sırrı olarak kabul edilmez.
OAuth akışı ve doğrulama gereksinimleri için
[Google’ın yerel uygulama rehberi](https://developers.google.com/identity/protocols/oauth2/native-app),
izinler için [Calendar kapsamları](https://developers.google.com/workspace/calendar/api/auth).

## Doğrulama sınırı ve fiziksel kabul

Otomatik testler gerçek servis hesabı veya kullanıcı kaydı kullanmaz. Bunlar eski veri
decode’u, kaynak doğrulama, görev aktarımı, yeniden özetlemede upload yapılmaması,
konuşmacı adının yeniden yüklenmesi, takvim yönlendirme/seçim, OAuth callback/PKCE,
token yenileme/sayfalama ve bildirim planını sentetik verilerle doğrular.

Yayın öncesi gerçek cihazda tamamlanacaklar:

- Temiz macOS hesabında izin reddetme, izin verme, yeniden başlatma ve Keychain kilidi.
- Gerçek OpenAI/ElevenLabs anahtarlarıyla Türkçe ve İngilizce toplantı analizi; kaynak,
  kişi, tarih ve karar doğruluğunun elle karşılaştırılması.
- 65–90 dakika kayıt: ağ kesintisi, uygulama kapanması, disk dolması ve geri dönüş;
  ses/transkript süre uyumu, RAM/disk tüketimi. Kullanıcının 41:57, 52:24, 56:43 kayıtları
  mevcut gerçek kullanım kanıtıdır; 60+ dakika kabulü henüz yapılmamıştır.
- Zoom/Meet başlangıç, mute/unmute, ayrılma ve arka planda ilgisiz sesin dışarıda kalması.
- Gerçek takvim hesabında etkinliği taşıma/silme, takvim seçimini kalıcılaştırma,
  bildirim katıl/ertele ve uykudan uyanma; Google’da token iptali/yeniden bağlantı.
- Developer ID, notarization, Chrome Web Store yayını ve temiz Mac kurulumu.

Bu adımlar geçmeden sürüm genel dağıtım için tamamlanmış kabul edilmez.
