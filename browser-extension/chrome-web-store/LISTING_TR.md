# Chrome Web Store listeleme metni

## Ad

Crenel for Google Meet

## Kısa açıklama

Yalnız seçtiğiniz Google Meet sekmesinin sesini yerel Crenel uygulamasına bağlar.

## Ayrıntılı açıklama

Crenel for Google Meet, macOS Crenel uygulamasının Google Meet görüşme sesini
sekme düzeyinde ve kullanıcı kontrolünde almasını sağlar.

- Yalnız aktif `meet.google.com` görüşme sekmesinde çalışır.
- Ses yakalama ancak uzantı popup'ındaki “Meet sekmesini bağla” düğmesine bastığınızda başlar.
- Seçili sekmenin sesi size geri oynatılmaya devam eder.
- Başka Chrome sekmelerinin veya uygulamaların sesini yakalamaz.
- Sekme, Chrome veya yerel Crenel bağlantısı kapanırsa yakalamayı durdurur.
- Reklam, analytics, izleyici veya uzaktan çalıştırılan kod içermez.

Uzantının çalışması için macOS Crenel uygulamasının kurulu ve açık olması gerekir.
Uzantı tek başına ses dosyası veya transkript oluşturmaz.

## Tek amaç beyanı

Kullanıcının açıkça seçtiği Google Meet görüşme sekmesinin sesini, toplantı kaydına dahil
edilmek üzere aynı cihazdaki Crenel macOS uygulamasına güvenli biçimde aktarmak.

## İzin gerekçeleri

- `activeTab`: Kullanıcının popup'ı açtığı anda seçili sekmenin desteklenen bir Google Meet
  görüşmesi olduğunu doğrulamak; kalıcı site erişimi istenmez.
- `tabCapture`: Yalnız kullanıcı tarafından seçilen Meet sekmesinin ses akışını almak.
- `offscreen`: Sekme ses akışını işlerken sesi yerel çıkışa geri oynatmak ve AudioContext'i
  görünmez extension belgesinde çalıştırmak.
- `nativeMessaging`: Doğrulanmış PCM sesini aynı cihazdaki Crenel uygulamasına iletmek.

`host_permissions` istenmez; uzantı sayfa içeriği veya DOM okumaz.

## Privacy Practices formu

- İşlenen veri: seçili sekmenin sesi / kişisel iletişim; aktif sekme URL'si yalnız canonical
  Meet doğrulaması için bellekte kullanılır.
- Verinin amacı: uzantının yukarıdaki tek kullanıcı özelliği.
- Satış, reklam, kredi değerlendirme, kişiselleştirme veya analytics: yok.
- Extension tarafından kalıcı saklama: yok.
- Yerel uygulamaya aktarım: var; aynı bilgisayardaki native messaging host üzerinden.
- Üçüncü tarafa aktarım: extension doğrudan yapmaz. Crenel uygulaması, kullanıcı kayıt
  başlattıysa birleşik kaydı daha sonra transkript için ElevenLabs Scribe v2'ye gönderebilir;
  özet ve görevler için OpenAI seçilirse transkript OpenAI’a, Anthropic API veya Claude Code
  seçilirse Anthropic’e gönderilir. Apple modelleri sesi ve metni Mac’te işler.
- Limited Use sertifikasyonu: evet.

## Dashboard alanları

- Ana sayfa URL'si: https://crenel.ayhan.fyi
- Gizlilik politikası URL'si: https://github.com/ayhangad/Crenel/blob/main/browser-extension/chrome-web-store/PRIVACY_POLICY_TR.md
- Destek URL'si: https://x.com/ayhangad (e-posta yok, destek yalnız X üzerinden)
- Kategori: Productivity
- Dil: Turkish (gerekirse İngilizce lokalizasyon ayrıca eklenir)
