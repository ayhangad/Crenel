# Chrome Web Store listeleme metni

## Ad

MeetingNotch for Google Meet

## Kısa açıklama

Yalnız seçtiğiniz Google Meet sekmesinin sesini yerel MeetingNotch uygulamasına bağlar.

## Ayrıntılı açıklama

MeetingNotch for Google Meet, macOS MeetingNotch uygulamasının Google Meet görüşme sesini
sekme düzeyinde ve kullanıcı kontrolünde almasını sağlar.

- Yalnız aktif `meet.google.com` görüşme sekmesinde çalışır.
- Ses yakalama ancak uzantı popup'ındaki “Meet sekmesini bağla” düğmesine bastığınızda başlar.
- Seçili sekmenin sesi size geri oynatılmaya devam eder.
- Başka Chrome sekmelerinin veya uygulamaların sesini yakalamaz.
- Sekme, Chrome veya yerel MeetingNotch bağlantısı kapanırsa yakalamayı durdurur.
- Reklam, analytics, izleyici veya uzaktan çalıştırılan kod içermez.

Uzantının çalışması için macOS MeetingNotch uygulamasının kurulu ve açık olması gerekir.
Uzantı tek başına ses dosyası veya transkript oluşturmaz.

## Tek amaç beyanı

Kullanıcının açıkça seçtiği Google Meet görüşme sekmesinin sesini, toplantı kaydına dahil
edilmek üzere aynı cihazdaki MeetingNotch macOS uygulamasına güvenli biçimde aktarmak.

## İzin gerekçeleri

- `activeTab`: Kullanıcının popup'ı açtığı anda seçili sekmenin desteklenen bir Google Meet
  görüşmesi olduğunu doğrulamak; kalıcı site erişimi istenmez.
- `tabCapture`: Yalnız kullanıcı tarafından seçilen Meet sekmesinin ses akışını almak.
- `offscreen`: Sekme ses akışını işlerken sesi yerel çıkışa geri oynatmak ve AudioContext'i
  görünmez extension belgesinde çalıştırmak.
- `nativeMessaging`: Doğrulanmış PCM sesini aynı cihazdaki MeetingNotch uygulamasına iletmek.

`host_permissions` istenmez; uzantı sayfa içeriği veya DOM okumaz.

## Privacy Practices formu

- İşlenen veri: seçili sekmenin sesi / kişisel iletişim; aktif sekme URL'si yalnız canonical
  Meet doğrulaması için bellekte kullanılır.
- Verinin amacı: uzantının yukarıdaki tek kullanıcı özelliği.
- Satış, reklam, kredi değerlendirme, kişiselleştirme veya analytics: yok.
- Extension tarafından kalıcı saklama: yok.
- Yerel uygulamaya aktarım: var; aynı bilgisayardaki native messaging host üzerinden.
- Üçüncü tarafa aktarım: extension doğrudan yapmaz. MeetingNotch uygulaması, kullanıcı kayıt
  başlattıysa birleşik kaydı daha sonra transkript için ElevenLabs Scribe v2'ye gönderebilir;
  bu sınır popup ve macOS onboarding üzerinde açıklanır.
- Limited Use sertifikasyonu: evet.

## Dashboard alanları — yayın öncesi doldurulacak

- Ana sayfa URL'si: `YAYIN_ONCESI_DOLDUR`
- Gizlilik politikası URL'si: `YAYIN_ONCESI_DOLDUR`
- Destek URL'si/e-postası: `YAYIN_ONCESI_DOLDUR`
- Kategori: Productivity
- Dil: Turkish (gerekirse İngilizce lokalizasyon ayrıca eklenir)
