# V1 doğrulama sonucu

- Case ID:
- Sonuç: `PASS | FAIL | BLOCKED`
- Tarih/saat:
- Test eden:
- Git commit:
- macOS / cihaz:
- Meeting client / sürüm:
- Chrome extension ID / sürüm (Meet koşusunda):
- MeetingNotch sürüm / build:

## Zaman çizelgesi

| Olay | Zaman | Beklenen | Gözlenen |
| --- | --- | --- | --- |
| Katılma | | | |
| Kayıt başlangıcı | | Gate closed | |
| Meet sekme bağlantısı | | Popup onayı + badge REC + Sekme bağlı | |
| Mute/unmute | | Gate ile eşleşir | |
| Cihaz/process değişimi | | Fail-closed | |
| Hang-up | | Güvenli bitiş | |
| Finalize | | M4A okunur | |
| Transkript/özet | | Tamamlandı | |

## Privacy kontrolleri

- Closed/unknown canary ham mic'te yok:
- Closed/unknown canary final M4A'da yok:
- Closed/unknown canary transcript'te yok:
- Toplantı dışı audio ham system/final/transcript'te yok:
- Meet sekmesi sesi yerel çıkışta kesintisiz:
- İkinci Chrome sekmesindeki 997 Hz canary tüm çıktılarda yok:
- Extension/native bridge kopması görünür fail-closed finalize üretti:
- Gate event metadata doğru:

## Artefaktlar

- Redacted metadata:
- Checksums:
- Canary audit JSON / Markdown:
- Session NDJSON / audit JSON / Markdown:
- Ekran görüntüsü / log:
- Hata veya blocker:
