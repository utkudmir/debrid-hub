# Session Handoff

## Durum Ozeti
- CI billing/spending limiti acilana kadar CI calismalarini parkta tutuyoruz.
- Uygulama tarafinda parity + stability + test coverage odakli ilerliyoruz.
- iOS keychain edge-case self-heal ve Android/iOS akis parity duzeltmeleri `main`'e pushlandi.
- Coverage altyapisi ve yeni testler localde hazir; bu degisiklikler henuz commit/push edilmedi.

## Son Tamamlanan Isler

### 1) Pushlanan parity ve iOS auth stabilizasyonu
- Commit: `67a360b` (`origin/main`)
- iOS keychain `status=-50` gibi hatalarda teknik hata gostermek yerine sessiz self-heal.
- iOS onboarding/polling terminal state cleanup.
- iOS/Android UI metin ve akislarini daha yakin parity seviyesine cekme.

### 2) Localde tamamlanan coverage/test guclendirme (commitlenmedi)
- Jacoco tabanli coverage report + verification eklendi (Android unit test tabanli).
- Coverage baseline: `LINE >= 70%`, `BRANCH >= 55%`.
- `make coverage` target eklendi.
- Shared + Android test kapsamı genisletildi.
- Android instrumentation smoke test eklendi.

## Dogrulama Sonuclari
- `make shared-test` -> PASS
- `./gradlew :androidApp:lint :androidApp:testDebugUnitTest` -> PASS
- `make coverage` -> PASS
- `make ios-build` -> PASS
- Android emulator kullanimi fiilen dogrulandi:
  - `VERIFY_PROFILE=local-fast VERIFY_RC_SCOPE=android make verify-rc` calismasinda `emulator-5554` ile install+smoke PASS
  - `make android-connected-test` -> PASS

## Mevcut Local Degisiklikler (Commitlenmedi)
- `Makefile`
- `androidApp/build.gradle.kts`
- `androidApp/src/test/java/app/debridhub/android/DebridHubViewModelTest.kt`
- `docs/release-gate.md`
- `shared/build.gradle.kts`
- `androidApp/src/androidTest/java/app/debridhub/android/MainActivitySmokeTest.kt`
- `androidApp/src/test/java/app/debridhub/android/SharedLogicCoverageTest.kt`
- `shared/src/commonTest/kotlin/app/debridhub/shared/DebridHubControllerTest.kt`
- `shared/src/commonTest/kotlin/app/debridhub/shared/data/remote/RealDebridApiTest.kt`
- `shared/src/commonTest/kotlin/app/debridhub/shared/data/repository/AccountRepositoryImplTest.kt`
- `shared/src/commonTest/kotlin/app/debridhub/shared/data/repository/ReminderRepositoryImplTest.kt`
- `shared/src/commonTest/kotlin/app/debridhub/shared/domain/usecase/ComputeExpiryStateUseCaseTest.kt`
- `shared/src/commonTest/kotlin/app/debridhub/shared/domain/usecase/ScheduleRemindersUseCaseTest.kt`
- `docs/session-handoff.md`

## Planda Kalan Maddeler (Sonraki Session)
1. Localde hazir coverage/test degisikliklerini son bir kez diff uzerinden gozden gecir.
2. Tek mantikli commit olarak al (veya gerekiyorsa 2 mantikli commit'e bol), sonra `main`e pushla.
3. Native iOS XCTest boslugunu kapat:
   - `iosApp/project.yml` icinde test target ekle.
   - `scripts/generate-ios-project.sh` ile proje regenerate et.
   - `IOSAppViewModel` icin temel state-transition testleri yaz.
4. iOS test + build dogrulamasini tekrar kos.
5. iOS testleri oturunca coverage hedefini bir sonraki esige tasimayi degerlendir (`line 75`, `branch 60`).

## Teknik Notlar / Guardrail
- Aktif Gradle modulleri: `:shared` ve `:androidApp` (`composeApp/` legacy).
- iOS proje source of truth: `iosApp/project.yml` (xcodeproj regenerate edilir).
- iOS runtime akisi:
  - `iosApp/DebridHubHost/DebridHubApp.swift`
  - `iosApp/DebridHubHost/IOSAppViewModel.swift`
  - `shared/src/iosMain/kotlin/app/debridhub/shared/IosAppGraph.kt`
- Shared orchestration: `shared/src/commonMain/kotlin/app/debridhub/shared/DebridHubController.kt`
- Product boundary koru: sadece OAuth device flow + `/rest/1.0/user` + local reminders/diagnostics.
- Eklenmeyecek alanlar: `/unrestrict/*`, `/downloads/*`, `/torrents/*`, `/streaming/*`.

## Yeni Session Baslatma Promptu (Kopyala-Yapistir)
```
Bu repo icin once docs/session-handoff.md dosyasini oku ve sadece oradaki plan uzerinden devam et.
CI billing limiti acilana kadar CI/workflow tarafina dokunma; yalnizca uygulama kodu ve testlere odaklan.

Ilk is olarak localde bekleyen coverage/test degisikliklerini gozden gecir, mantikli commit(ler) halinde tamamla ve pushla.
Ardindan iOS native test boslugunu kapatmak icin iosApp/project.yml uzerinden XCTest target ekle, projeyi regenerate et, IOSAppViewModel state-transition testleri yaz ve iOS build/test dogrula.

Mevcut coverage baseline'i koru: line >= 70, branch >= 55. iOS testler oturursa bir sonraki adim olarak 75/60 artisini oner.
``` 
