# Session Handoff

## Durum Ozeti
- CI billing/spending limiti acilana kadar CI/workflow tarafini parkta tutuyoruz.
- Uygulama kodu ve testlerde Android/iOS parity + stability + coverage odaginda ilerliyoruz.
- Coverage gate aktif: `LINE >= 70`, `BRANCH >= 55`.
- iOS native XCTest altyapisi aktif ve `IOSAppViewModel` senaryo paritesi Android ile hizalandi.

## Son Tamamlanan Isler

### 1) Pushlanan parity + auth stabilizasyonu
- Commit: `67a360b` (`origin/main`)
- iOS keychain `status=-50` gibi hatalarda sessiz self-heal.
- iOS onboarding/polling terminal state cleanup.
- Android/iOS akis ve mesaj parity iyilestirmeleri.

### 2) Pushlanan coverage/test guclendirme
- Commit: `d261431` (`origin/main`)
- Jacoco report + verification eklendi.
- Baseline korumasi: `LINE >= 70`, `BRANCH >= 55`.
- Shared + Android test kapsamı genisletildi.

### 3) Pushlanan iOS native test boslugu kapatma
- Commit: `41a162a` (`origin/main`)
- `iosApp/project.yml` uzerinden XCTest target eklendi.
- Xcode proje regenerate edildi.
- `IOSAppViewModel` icin temel state-transition testleri eklendi.

### 4) Pushlanan Android/iOS test parity hizalama
- Commit: `ea1b832` (`origin/main`)
- `IOSAppViewModelTests` kapsamı Android ViewModel senaryo seti ile hizalandi.
- Mevcut durumda ViewModel test sayisi parity: Android 16 / iOS 16.

### 5) Pushlanan lock-step TDD genisletmesi
- Commit: `bf72f37` (`origin/main`)
- `make ios-test` komutu ve `scripts/test-ios-sim.sh` eklendi.
- Cancel authorization safety slice'i Android+iOS icin eklendi.
- Diagnostics preview success slice'i Android+iOS icin eklendi.

### 6) Pushlanan authenticated bootstrap lock-step slice
- Commit: `8022b2a` (`origin/main`)
- Android + iOS authenticated startup refresh/sync/preview davranisi testlendi.
- ViewModel parity test matrisi bir sonraki faza hazirlandi.

### 7) Bu tur tamamlanan kalan parity testleri
- Duplicate/in-flight guardlari tamamlandi (`startAuthorization`, `loadDiagnosticsPreview`).
- Reminder mutation matrix tamamlandi (`day toggles`, notify flagleri, invalid input no-op).
- Notification edge parity tamamlandi (granted/denied/failure/already-enabled etkileri).
- iOS tarafinda `openAppSettings` delegasyonu da native test ile guvenceye alindi.
- Son test sayilari: Android ViewModel 28, iOS ViewModel 29 (iOS'ta 1 ek native delegasyon testi).

## Dogrulama Sonuclari (Son Session)
- `make shared-test` -> PASS
- `./gradlew :androidApp:lint :androidApp:testDebugUnitTest` -> PASS
- `make ios-test` -> PASS
- `make coverage` -> PASS
- `make ios-build` -> PASS
- `xcodebuild ... -scheme DebridHubHost ... test` -> PASS

## Mevcut Local Durum
- Calisma agaci temiz hedeflenir; yeni ise baslarken `git status` ile dogrula.
- CI/workflow dosyalarina dokunma (billing limiti acilana kadar).

## Sonraki Plan (Test Sonrasi)
Kalan ana is paketi coverage esigini kontrollu artirmak.

1. Coverage uplift hazirlik:
   - Mevcut test matrisinde flakey risklerini gozle.
   - Gerekirse sadece stabilite odakli kucuk refactor/test duzeltmeleri yap.
2. Coverage hedef artisi (ayri degisiklik):
   - `LINE >= 75`
   - `BRANCH >= 60`
3. Hedef artisindan sonra tam dogrulama:
   - `make shared-test`
   - `./gradlew :androidApp:lint :androidApp:testDebugUnitTest`
   - `make ios-test`
   - `make coverage`

## Coverage Hedefi (Bir Sonraki Esik)
- Mevcut baseline korunurken testler stabilize oldugunda bir sonraki hedef:
  - `LINE >= 75`
  - `BRANCH >= 60`

## Teknik Notlar / Guardrail
- Aktif Gradle modulleri: `:shared` ve `:androidApp` (`composeApp/` legacy).
- iOS proje source of truth: `iosApp/project.yml` (xcodeproj regenerate edilir).
- iOS runtime: `DebridHubApp.swift` -> `IOSAppViewModel.swift` -> `IosAppGraph` -> shared `DebridHubController`.
- Shared orchestration: `shared/src/commonMain/kotlin/app/debridhub/shared/DebridHubController.kt`.
- Product boundary koru: OAuth device flow + `/rest/1.0/user` + local reminders/diagnostics.
- Eklenmeyecek alanlar: `/unrestrict/*`, `/downloads/*`, `/torrents/*`, `/streaming/*`.

## Yeni Session Baslatma Promptu (Kopyala-Yapistir)
```text
Bu repo icin once docs/session-handoff.md dosyasini oku ve sadece oradaki plan uzerinden devam et.
CI billing limiti acilana kadar CI/workflow tarafina dokunma; yalnizca uygulama kodu ve testlere odaklan.

Android ve iOS testlerini TDD (RED->GREEN->REFACTOR) ve lock-step parity ile ilerlet.
Her slice sonunda Android unit test, iOS XCTest ve coverage baseline dogrulamalarini calistir.

Coverage baseline'i koru: line >= 70, branch >= 55.
Slice'lar stabilize olunca 75/60 esigine gecis icin ayri bir degisiklik oner.
```
