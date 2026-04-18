# DebridHub Agent Notes

## Repo Truths That Matter
- Active Gradle modules are only `:shared` and `:androidApp` (`settings.gradle.kts`); `composeApp/` is legacy and not part of the active build.
- iOS project files are generated from `iosApp/project.yml` via `xcodegen` (`scripts/generate-ios-project.sh`). Treat `project.yml` as source of truth; regenerate after iOS project config edits.
- If docs and code disagree, trust executable sources (`Makefile`, Gradle files, scripts, code). Current docs still contain stale claims about iOS auth storage.

## Real Entrypoints / Wiring
- Android runtime path: `androidApp/src/main/java/com/utku/debridhub/android/MainActivity.kt` -> `buildAndroidAppGraph` (`AndroidAppGraph.kt`) -> `DebridHubViewModel`.
- iOS runtime path: `iosApp/DebridHubHost/DebridHubApp.swift` -> `IOSAppViewModel.swift` -> `IosAppGraph` -> shared `DebridHubController`.
- Shared app orchestration lives in `shared/src/commonMain/kotlin/com/utku/debridhub/shared/DebridHubController.kt`; when adding cross-platform behavior, wire both app graphs.

## Commands (Verified from Makefile/Gradle)
- Preferred local commands:
  - `make shared-test` (runs `:shared:allTests`)
  - `make android-debug` (runs `:androidApp:assembleDebug`)
  - `make ios-project`, `make ios-open`, `make ios-build`, `make ios-run`
- Focused verification:
  - Single shared test (example): `./gradlew :shared:iosSimulatorArm64Test --tests "com.utku.debridhub.shared.core.RealDebridErrorMessagesTest"`
  - Android lint + unit tests: `./gradlew :androidApp:lint :androidApp:testDebugUnitTest`

## Toolchain / iOS Script Quirks
- JDK 21 is required; Make/iOS scripts auto-resolve `JAVA_HOME` with `/usr/libexec/java_home -v 21`.
- iOS scripts default to simulator `iPhone 17 Pro Max`; override with `IOS_SIMULATOR_NAME="<device>"`.
- `make ios-run` builds to `build/ios-derived-data` by default; override with `DERIVED_DATA_PATH` if needed.
- `iosApp/project.yml` targets iOS `18.0`; ensure your Xcode/simulator runtime matches.

## Non-Obvious Behavior To Preserve
- Real-Debrid API client intentionally supports host failover between `https://api.real-debrid.com` and `https://api-1.real-debrid.com` (`RealDebridApi.kt`).
- Both platform HTTP clients intentionally disable proxies during API calls (Android `Proxy.NO_PROXY`, iOS `connectionProxyDictionary`) to avoid TLS/proxy handshake issues.
- iOS auth storage is Keychain-backed in `SecureTokenStore.ios.kt` with migration from legacy `NSUserDefaults`; do not reintroduce defaults-only token storage.

## Product Boundary Guardrail
- Current intended API scope is OAuth device flow + `/rest/1.0/user` + local reminders/diagnostics.
- Do not add `/unrestrict/*`, `/downloads/*`, `/torrents/*`, or `/streaming/*` integrations without explicit compliance review (see `docs/compliance.md`).
