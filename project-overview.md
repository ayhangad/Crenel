# Crenel — Mimari Özet

> Aktif ürün geliştirme planı ve ortak checklist: [PRODUCT_PLAN.md](PRODUCT_PLAN.md)

Notch (Dynamic Island tarzı) üzerinden çalışan, mikrofon + sistem sesini eş zamanlı
kaydeden, buluta yükleyip konuşmacı ayrımlı transkript alan, takvim entegrasyonlu
ve mini bir görev takibi içeren macOS menü çubuğu uygulaması.

## Tech Stack

- SwiftUI + AppKit (menu bar agent, `LSUIElement = YES`, dock ikonu yok)
- DynamicNotchKit — notch pencere konteyneri (hover ile açılıp kapanma)
- AVAudioEngine (mikrofon) + Core Audio Process Tap (sistem sesi)
- EventKit — takvim
- Transkripsiyon: protokol tabanlı provider katmanı
- Depolama: düz dosya sistemi, v1'de veritabanı yok (SwiftData/Core Data kullanılmıyor)
- Deployment target: macOS 14.4+

## Notch UI Yapısı

İki sekme, hover ile açılan tek panelde:

1. **Toplantılar** — durum makinesi
2. **Görevler** — düz aktif liste + arşiv

Boşta durumunda notch varsayılan olarak aktif görev sayısını küçük bir rozet
olarak gösterir. Toplantı bildirimi veya kayıt durumu geçici olarak bu rozetin
yerini alır, aynı küçük alanı paylaşırlar.

## Toplantılar Sekmesi — Durum Makinesi

```
Boşta → Toplantı Yakın → Kayıt → İşleniyor → Tamamlandı → (Boşta'ya döner)
```

- **Boşta**: küçük pil, görev sayısı rozeti görünür
- **Toplantı Yakın**: EventKit ile algılanan etkinlik. "Toplantı" sayılma kriteri:
  etkinliğin location/url/notes alanlarında zoom.us, meet.google.com veya
  teams.microsoft.com gibi bir pattern geçmesi. Başlamadan X dakika önce notch
  bildirim durumuna geçer.
- **Kayıt**: mikrofon (`AVAudioEngine.inputNode`) ve sistem sesi (Core Audio
  Process Tap) paralel yakalanır. Notch sağında canlı süre sayacı gösterilir.
- **İşleniyor**: iki ses akışı aynı sample rate'e getirilip tek `.m4a` dosyasında
  birleştirilir (basit interleave/toplama, karmaşık bir mixer gerekmiyor),
  seçili transkripsiyon provider'ına yüklenir.
- **Tamamlandı**: diarized transkript Markdown olarak diske kaydedilir, kısa bir
  özet gösterilir, ardından Boşta durumuna döner.

## Görevler Sekmesi

Proje kavramı yok, tek aktif liste + arşiv:

- Yeni görev: serbest metin satırı olarak eklenir
- Check'leme: satır `active.md`'den silinip `archive.md`'ye taşınır
- Görev sayacı uygulama açılışında dosyadan bir kere okunup bellekte
  (`@Published var activeTasks: [Task]`) tutulur, her render'da dosya
  okunmaz; ekleme/check'leme hem diziyi hem dosyayı günceller

## Depolama Düzeni

```
~/Library/Application Support/<AppAdı>/
  Meetings/
    2026-07-14-standup.m4a
    2026-07-14-standup.md
  Tasks/
    active.md
    archive.md
```

Task satır formatı (markdown checkbox): `- [ ] Cityloft mobil uygulama tasarımı bitir`

## Transkripsiyon Provider Katmanı

`TranscriptionProvider` protokolü, iki implementasyon:

- **ElevenLabsProvider** (varsayılan): Scribe v2, `diarize=true`, 32 konuşmacıya
  kadar destek, 10 saate kadar dosya, `use_speaker_library` ile tekrarlayan
  katılımcıları otomatik tanıma
- **OpenAIProvider** (alternatif): `gpt-4o-transcribe-diarize`, dosya başına
  25MB sınırı var, kayıt önce m4a/AAC'ye sıkıştırılmalı ya da `chunking_strategy`
  ile parçalanmalı

İleride local bir model (ör. Whisper) eklenmek istenirse üçüncü bir
implementasyon olarak eklenir, sistemin geri kalanı değişmez.

## Bilinen Teknik Kısıtlar

- `AVAudioEngine` process tap'e doğrudan bağlanamaz; process tap için
  `AudioDeviceCreateIOProcIDWithBlock` aggregate device üzerinde ayrıca
  çağrılmalı
- Gerekli Info.plist anahtarları: `NSMicrophoneUsageDescription`,
  `NSAudioCaptureUsageDescription`, `NSCalendarsUsageDescription`
- App Sandbox kapalı olmalı, Process Tap sandbox altında güvenilir çalışmıyor
- Calendar erişimi: `EKEventStore.requestFullAccessToEvents`

## Kapsam Dışı (v1)

- SwiftData veya başka bir veritabanı
- Bulut senkronizasyonu
- Cihaz üstü (local) transkripsiyon modeli
- Proje bazlı görev organizasyonu, tarih/gün bazlı gruplama
