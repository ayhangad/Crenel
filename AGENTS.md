# Crenel çalışma kuralları

- Her işe başlamadan önce `PRODUCT_PLAN.md` ve `ARCHITECTURE.md` dosyalarını oku.
- Üstlenilen checklist maddesini `PRODUCT_PLAN.md` kurallarına göre devam ediyor olarak
  işaretle; doğrulama tamamlanınca `[x]` yap.
- Xcode proje ayarları için yalnızca `macos/project.yml` dosyasını değiştir.
- `macos/Crenel.xcodeproj/project.pbxproj` dosyasını elle düzenleme.
- `macos/project.yml` değişikliğinden sonra `macos/` içinde `xcodegen generate` çalıştır.
- Depo monorepo'dur: macOS uygulaması `macos/`, Chrome uzantısı `browser-extension/`,
  web sitesi `website/` altındadır.
- Tamamlanan kod değişikliklerinden sonra ilgili build ve testleri çalıştır.
- `project-overview.md` teknik araştırma notudur; ürün kapsamı için `PRODUCT_PLAN.md`,
  uygulama sınırları için `ARCHITECTURE.md` önceliklidir.
