# MeetingNotch çalışma kuralları

- Her işe başlamadan önce `PRODUCT_PLAN.md` ve `ARCHITECTURE.md` dosyalarını oku.
- Üstlenilen checklist maddesini `PRODUCT_PLAN.md` kurallarına göre devam ediyor olarak
  işaretle; doğrulama tamamlanınca `[x]` yap.
- Xcode proje ayarları için yalnızca `project.yml` dosyasını değiştir.
- `MeetingNotch.xcodeproj/project.pbxproj` dosyasını elle düzenleme.
- `project.yml` değişikliğinden sonra `xcodegen generate` çalıştır.
- Tamamlanan kod değişikliklerinden sonra ilgili build ve testleri çalıştır.
- `project-overview.md` teknik araştırma notudur; ürün kapsamı için `PRODUCT_PLAN.md`,
  uygulama sınırları için `ARCHITECTURE.md` önceliklidir.
