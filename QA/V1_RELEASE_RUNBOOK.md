# MeetingNotch V1 release doğrulama runbook'u

Bu belge `PRODUCT_PLAN.md` içindeki B/C gerçek istemci kapılarını ve E release-hardening
matrisini tekrar edilebilir biçimde çalıştırmak içindir. Otomatik test geçişi fiziksel
toplantı, TCC, ağ, ekran ve notarization kanıtının yerine geçmez.

## Kanıt kuralı

Her koşu için `QA/Evidence/<YYYY-MM-DD>/<case-id>/` altında şu dosyaları saklayın:

- `result.md`: tarih, cihaz, macOS, uygulama commit/hash, istemci sürümü ve PASS/FAIL/BLOCKED.
- `timeline.md`: toplantıya katılma, kayıt, mute/unmute, hang-up ve sonuç zamanları.
- `metadata-redacted.json`: gate event zamanları/kaynakları; toplantı içeriği ve API anahtarı yok.
- `checksums.txt`: kalıcı M4A, transcript ve Markdown için `shasum -a 256` çıktısı.
- Gerekliyse ekran görüntüsü; gerçek kişi adı, toplantı başlığı ve transkript karartılmış olmalı.

Testlerde gerçek kullanıcı/toplantı verisi kullanmayın. Her canary koşusunda yeni, anlamsız
bir test cümlesi ve sabit 997 Hz ses kullanın.

## 1. Baseline

```sh
xcodegen generate
xcodebuild test \
  -project MeetingNotch.xcodeproj \
  -scheme MeetingNotch \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Beklenti: tüm normal testler geçer; yalnız opt-in donanım testleri atlanır. Ardından:

```sh
Scripts/audio-integration-tests.sh
```

Betiğin `/tmp` opt-in işareti `trap` ile her çıkış yolunda kaldırılır; test çıktıları da
test teardown'unda silinir.

Google Meet extension protokolü için:

```sh
Scripts/chrome-extension-tests.sh
Scripts/chrome-web-store-package.sh
```

İkinci komut extension testlerinden sonra `artifacts/chrome-store/` altında Store'a
yüklenecek kök-manifestli ZIP ve SHA-256 üretir. Store metni, gizlilik politikası taslağı ve
görsel varlıklar `BrowserExtension/ChromeWebStore/` altındadır; dashboard item ID/public key
eşleştirmesi, public HTTPS politika adresi ve gerçek Chrome ekran görüntüsü manuel kapıdır.

## 2. Session detector kabulü

Zoom Workplace ve Google Meet/Chrome için aşağıdaki senaryoları ayrı ayrı beş ardışık kez
çalıştırın. Tek yanlış başlangıç/bitiş release blocker'dır.

1. Planlı toplantıya erken katılım.
2. Planlı toplantıya geç katılım.
3. Takvimsiz toplantı.
4. Görüşme içinde 60 saniye sessizlik/ara; kayıt bitmemeli.
5. Hang-up sonrası istemci açık kalır; toplantı bitişi yine algılanmalı.
6. Arka arkaya ikinci çağrı; ilk oturum kanıtı ikinciye taşınmamalı.
7. Accessibility izni kapalı; otomatik iddia yapılmamalı, manuel kayıt erişilebilir kalmalı.

Her istemci/senaryonun beş koşusunu ayrı bir zaman penceresinde yapın. Koşular bittikten
hemen sonra normalize session loglarını toplayıp doğrulayın:

```sh
Scripts/session-acceptance-collect.sh \
  --client zoom \
  --last 30m \
  --required-runs 5 \
  --output-dir QA/Evidence/2026-08-11/zoom-early-join-5x

Scripts/session-acceptance-collect.sh \
  --client googleMeetChrome \
  --last 30m \
  --required-runs 5 \
  --output-dir QA/Evidence/2026-08-11/meet-early-join-5x
```

Uygulama yalnız rastgele session UUID'si, normalize state/confidence/client/microphone ve
evidence türlerini `meeting-session` OSLog kategorisine yazar; PID, takvim kimliği, toplantı
başlığı, URL veya UI metni yazılmaz. Collector ham `session.ndjson`, ortam özeti,
`session-audit.json` ve `session-audit.md` üretir. Her koşuda `ready/confirmed` sonrasında
`ended/confirmed` görülmeli ve terminal state gerilememelidir. Audit gerçek hang-up zamanı,
60 saniyelik sessizlik veya izin kapalı UI davranışını bilemez; bunlar `timeline.md` üzerinde
ayrıca işaretlenir.

## 3. 60+ dakika uçtan uca kayıt

Her istemci için en az 65 dakikalık sentetik görüşme yapın. 5., 20., 40. ve 60. dakikada
mute/unmute uygulayın; bir kez mikrofon/kulaklık değiştirin. Sonunda hang-up kullanın.

PASS ölçütleri:

- Kompakt notch istemciyi, canlı süreyi ve gate durumunu kesintisiz gösterir.
- Gate her kayıt başında `closed`; yalnız doğrulanmış veya manuel `open` aralıkları mic içerir.
- System track sadece doğrulanmış toplantı kapsamını içerir.
- Final M4A okunur ve beklenen süre farkı en fazla 2 saniyedir.
- `capture.json` içindeki ilk/son kaynak timestamp'leriyle final süre karşılaştırılır;
  60+ dakikada %2'yi aşmayan clock drift pitch korunarak normalize edilmiş olmalıdır.
- Eşzamanlı yüksek seviye mic/system canary'sinde final PCM peak değeri 1.0'ı aşmamalı ve
  belirgin clipping duyulmamalıdır.
- ElevenLabs Scribe v2 yüklemesi, diarization, yerel özet ve notch içi detay tamamlanır.
- Uygulama yeniden açıldığında toplantı, transkript, Markdown ve playback kullanılabilir kalır.

Google Meet/Chrome koşusundan önce Debug/RC uygulamasını bir kez açın. Uygulama, gömülü native
host manifestini kullanıcı hesabına kurar. Development doğrulamasında `chrome://extensions`
üzerinden Developer mode'u açıp `BrowserExtension/MeetingNotchChrome` klasörünü `Load unpacked`
ile yükleyin. Görüşme sekmesini aktif edip uzantı action'ını açın; veri kullanımı açıklamasını
okuyup `Meet sekmesini bağla` düğmesine basın. Badge `REC`, Ayarlar'daki `Meet sekme bağlantısı`
ise `Sekme bağlı` olmalıdır. Bağlantı yoksa kayıt
`browserMeetingAudioIsolationUnavailable` ile fail-closed kalmalıdır.

Bu extension yolu Chrome `tabCapture` kullansa da fiziksel canary geçmeden izolasyon kanıtlanmış
sayılmaz. Chrome Web Store paketi ve gerçek iki sekmeli koşu tamamlanana kadar Google Meet
60+ dakika maddesi release blocker'dır.

## 4. Privacy canary

Her istemcide şu sıralamayı uygulayın:

1. Gate `closed`: benzersiz cümleyi iki kez söyleyin.
2. Gate `open`: farklı kontrol cümlesini söyleyin.
3. Gate `unknown`: Accessibility iznini veya istemci adaptörünü kesin ve ilk cümleyi tekrarlayın.
4. Gate'i hızlı biçimde en az 10 kez değiştirin; 24/48 kHz cihaz geçişi yapın.
5. Ayrı bir uygulamada 997 Hz canary ve müzik/bildirim sesi oynatın.

Google Meet'te 5. adımı aynı Chrome profili içindeki ikinci sekmede de tekrarlayın. Meet
sekmesinin sesi yerel hoparlörde kesintisiz duyulmalı; ikinci sekmenin 997 Hz canary'si ham
system, final M4A ve transcript'in hiçbirinde bulunmamalıdır. Uzantıyı veya Chrome'u kayıt
sırasında kapatınca notch görünür güvenlik uyarısıyla finalize'a geçmelidir.

Ham microphone, ham system, final M4A ve transcript ayrı ayrı incelenir. `closed/unknown`
cümlesinin herhangi birinde bulunması veya toplantı dışı canary'nin system/final/transcript'e
girmesi release blocker'dır. Gate geçişlerinde click, zaman kayması ya da süre kısalması
olmamalıdır.

Başarılı processing ham track'leri ürün saklama politikasına göre sildiği için privacy
koşusunu önce geçersiz/test ElevenLabs anahtarıyla finalize edin. Retry yapmadan önce yalnız
sentetik koşuya ait ham microphone, ham system ve final M4A'yı kanıt klasörüne kopyalayın;
gerçek kişi veya toplantı verisi kopyalamayın. Ardından doğru test anahtarını bağlayıp Retry
ile transcript'i üretin.

997 Hz sızıntısı, süre ve transcript cümlesi için gerçek çıktıları otomatik denetleyin:

```sh
Scripts/privacy-canary-audit.sh \
  --report-dir QA/Evidence/2026-08-11/meet-canary-01 \
  --audio /path/to/copied-system.m4a \
  --audio /path/to/copied-final.m4a \
  --transcript /path/to/transcript.json \
  --forbidden-phrase "koşuya özel anlamsız cümle" \
  --tone-hz 997 \
  --max-tone-amplitude 0.02 \
  --minimum-duration-seconds 3900
```

Komut `canary-audit.json` ve `canary-audit.md` üretir, herhangi bir ses dosyasında 997 Hz
eşiği aşılırsa, süre 65 dakikadan kısaysa veya yasaklı cümle transcript'te bulunursa non-zero
çıkar. Konuşma cümlesinin ham mic/final seste yokluğu dinleme veya ayrı speech-recognition
ile; Meet sesinin yerel çıkışta sürdüğü ve bridge kopmasının görünür finalize ürettiği ise
fiziksel olarak ayrıca doğrulanır.

## 5. Recovery matrisi

Önce otomatik recovery kanıt paketini üretin:

```sh
Scripts/recovery-matrix-tests.sh
```

Komut `artifacts/qa/recovery-<UTC>/` altında tam `xcodebuild.log` ve kısa `result.md`
oluşturur. Bu paket aşağıdaki fiziksel/destructive satırların yerine geçmez; hangi domain ve
repository güvencelerinin koşudan önce yeşil olduğunu sabitler.

| Case | Uygulama | Beklenen sonuç |
| --- | --- | --- |
| İnternet kesintisi | Upload sırasında ağı kapat, sonra aç ve Retry | Ses kalır; aynı idempotency key ile tamamlanır |
| 401 | Geçersiz test anahtarı | Anahtar güncelleme aksiyonu; ses ve iş korunur |
| 429/5xx/timeout | Fixture testlerini ve kontrollü test endpoint'ini çalıştır | Sınırlı retry; kalıcı iş kaybolmaz |
| Disk alanı | Birim testte düşük kapasiteyi enjekte et; fiziksel koşuda güvenli test volume kullan | Başlangıç reddedilir; kayıt sırasında kritikleşirse 30 sn içinde görünür uyarı ve güvenli finalize tetiklenir |
| Recording force quit | Kayıt sırasında yalnız test uygulamasını `kill -9` ile kapat, yeniden aç | Yarım kayıt otomatik finalize edilir veya Recovery'ye taşınır |
| Upload force quit | Upload sırasında kapat, yeniden aç | `running` iş `queued` olur; idempotency key değişmez |
| Sleep/wake/lock | Kayıt sırasında Mac'i uyut; ayrı koşuda ekranı kilitle veya kullanıcı oturumunu pasifleştir | Gate `systemInterruption` ile unknown; kayıt finalize edilir; dönüşte izin/cihaz/session yenilenir |
| Audio device | USB/Bluetooth mic çıkar/tak ve sample-rate değiştir | Uyarı görünür; gate kendi kendine açılmaz; system frame heartbeat sürer veya kayıt görünür uyarıyla güvenli finalize edilir |
| Process restart | Zoom'u kayıt sırasında kapat/yeniden aç | Gate unknown; eski private tap global kayda düşmez; uyarı görünür |

System audio doğrulamasında seviye değerinin sıfır olması tek başına kopma sayılmaz. Core Audio
callback frame sayacı ilerlediği sürece gerçek sessizlik sağlıklı kabul edilir. Sayaç üç saniye
boyunca ilerlemezse veya async writer hata döndürürse `pipelineStalled` üretilmeli; kalıcı kayıt
global kapsama düşmeden görünür uyarıyla güvenli finalize edilmelidir.

Sistem diskini doldurmayın. Disk hatasını önce `RecordingCoordinatorTests` ve geçici test
köküyle doğrulayın; fiziksel koşu yalnız disposable test hesabı/volume üzerinde yapılır.

## 6. Release candidate ve temiz hesap

Önkoşullar:

- Keychain'de `Developer ID Application` sertifikası.
- `xcrun notarytool store-credentials MeetingNotch-Notary ...` ile kaydedilmiş profil.
- Temiz git durumu ve release için seçilmiş commit/tag.

```sh
MEETINGNOTCH_NOTARY_PROFILE=MeetingNotch-Notary Scripts/release-candidate.sh
```

Betiğin archive, Developer ID imzası, hardened runtime, notarization, staple ve Gatekeeper
kontrollerinin tamamı geçmelidir. Üretilen ZIP'i yeni bir macOS kullanıcı hesabına taşıyın;
ilk onboarding'den ilk başarılı transkripte kadar test edin. Fiziksel notch, notch olmayan
harici ekran, çoklu ekran, tam ekran, light/dark, Reduce Motion ve Increase Contrast
durumlarını kanıtlayın.

## Release kararı

E maddesi yalnızca tüm satırlar PASS olduğunda kapanır. Güvenli biçimde reddedilen Google
Meet kapsamı, eksik Developer ID/notary profili veya temiz hesap kanıtı BLOCKED sayılır;
otomatik test başarısı bunları PASS'e çeviremez.
