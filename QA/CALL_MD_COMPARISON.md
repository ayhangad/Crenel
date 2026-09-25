# Call.md / MeetingNotch — 25 Eylül 2026

Karşılaştırma Call.md'nin yayımlanmış [README ve teknoloji açıklamasına](https://github.com/video-db/call.md#readme),
MeetingNotch'un yerel kaynak koduna, `PRODUCT_PLAN.md` ve `ARCHITECTURE.md` belgelerine dayanır.
Call.md çalıştırılmadı; performans, doğruluk veya animasyon kalitesine ilişkin ölçüm yapılmadı.

| Boyut | Call.md | MeetingNotch |
| --- | --- | --- |
| Ana deneyim | Toplantı sırasında canlı yardım ve ajan araçları | Notch üzerinden kayıt kontrolü; masaüstünde arşiv, sonuçlar ve görevler |
| Arayüz teknolojisi | Electron, React, Tailwind/shadcn | Native SwiftUI/AppKit, DynamicNotchKit |
| Transkript | VideoDB ile canlı, mikrofon/sistem ayrı kanalları | Kayıt sonrası ElevenLabs Scribe v2 ve konuşmacı ayrımı |
| Yapay zekâ | Canlı öneriler, konuşma metrikleri, coaching, MCP araç tetikleme | Ayrı OpenAI bağlantısıyla kaynak doğrulamalı özet, karar ve görevler |
| Otomasyon | Webhook ile n8n/Zapier/CRM aktarımı | Yerel görevler, kullanıcı kontrollü aktarım ve Markdown |
| Hazırlık | AI toplantı hazırlığı ve checklist | Takvim, hatırlatma, katılma ve kayıt önerisi |
| Saklama | Yerel SQLite; AI için ağ bağlantısı | Yerel kayıt/arşiv; ses ElevenLabs'e, metin OpenAI'ye; ayrı Keychain anahtarları |
| Platform | macOS; Windows x64 kaynak build'inde kayıt | macOS 14.4+ |

Call.md özellik açıklamalarının kaynağı: [proje README'si](https://github.com/video-db/call.md#features).

## Bu proje için çıkarım

MeetingNotch'un güçlü yönü, kullanıcıyı görüşmeden uzaklaştırmadan kayıt durumunu ve
mikrofonun gerçekten kayda dahil olup olmadığını görünür kılabilmesi. Bu çalışmada
öncelik bu avantajı tamamlayan tutarlı notch, açık durum metinleri, hızlı görev erişimi
ve okunabilir toplantı sonucuna verildi.

Call.md'den ileride değerlendirilebilecek fikirler: önemli an işaretleme, toplantı öncesi
hazırlık ve kullanıcı kontrollü dışa aktarım hedefleri. Canlı koçluk/MCP eklemek mevcut
batch transkript mimarisinin üzerine yalnız bir ekran eklemek değildir; yeni veri akışı,
izin modeli, gecikme ve maliyet değerlendirmesi gerektirir. Bu UI çalışmasına böyle bir
ürün kapsamı değişikliği dahil edilmedi.

Karşılaştırma, iki uygulamanın hız veya sonuç kalitesinde birbirinden üstün olduğunu
kanıtlamaz; bunun için aynı ses kaydı, aynı dil ve aynı görevlerle karşılaştırmalı test gerekir.
