# Session Handoff

## Current Status

- Active release-readiness work is on branch `chore/store-release-readiness` and PR #20.
- GitHub Environments exist for `production-app-store` and `production-play-store`.
- Store upload secrets and `APPLE_DEVELOPMENT_TEAM_ID` have been added by name and verified through GitHub CLI.
- GitHub rulesets exist for `main` and `v*` tags. Before tagging, ensure the tag ruleset does not block all tag creation.
- Support email is `support.cue.app@gmail.com` across docs, site, and shared external links.
- iOS privacy manifest is present at `iosApp/CueHost/PrivacyInfo.xcprivacy` and included in the Xcode project resources.
- Release sign-off owner is `utkudmir` via `ci/device-pool.yml`.

## Latest Local Verification

- `make ios-project` -> PASS
- `make ios-build` -> PASS
- `make security-scan-secrets` -> PASS
- Workflow YAML parse via Ruby -> PASS
- `ruby -c fastlane/Fastfile` -> PASS
- `bash -n scripts/setup-github-release-controls.sh` -> PASS
- `make github-release-controls` dry-run -> PASS
- `git diff --check` -> PASS

## Release Readiness Scope

- App identity remains `com.utkudemir.cue` on iOS and Android.
- Commercial model is paid upfront, no IAP/subscription in v1.
- Store price target is 4.99 USD with automatic local pricing.
- Store listing locale is `en-US` for v1.
- Device scope is phone-only v1.
- Reviewer access is demo mode only; do not share Real-Debrid credentials.
- Legal URLs remain GitHub Pages v1.

## Next Steps

1. Merge PR #20 after CI passes.
2. Confirm GitHub tag ruleset permits the release owner to create signed `v*` tags.
3. Confirm App Store Connect app setup manually:
   - Bundle ID `com.utkudemir.cue`
   - paid app agreements/tax/banking complete
   - price 4.99 USD with automatic local pricing
   - App Privacy and export compliance complete
   - review notes use `store/app-store/review-notes.md`
4. Confirm Google Play Console setup manually:
   - package `com.utkudemir.cue`
   - Play App Signing enabled
   - paid app setup complete
   - Data Safety/content rating/target audience complete
   - internal and closed testing tracks ready
5. Select a candidate commit and run `VERIFY_PROFILE=rc-full make verify-rc` or the equivalent CI manual run.
6. Record local redacted evidence under `build/rc-verify/<run_id>/evidence/`.
7. Create signed release tag only after GO sign-off.
8. Run `build-release-candidate`, then `release-to-stores` for the same tag.

## Verification Commands

- `make shared-test`
- `./gradlew :androidApp:lint :androidApp:testDebugUnitTest`
- `make coverage`
- `make android-debug`
- `make ios-build`
- `make ios-test`
- `make security-scan-secrets`
- `VERIFY_PROFILE=rc-full make verify-rc`

## Technical Guardrails

- Active Gradle modules: `:shared` and `:androidApp`.
- iOS project source of truth: `iosApp/project.yml`; regenerate with `make ios-project` after iOS project config edits.
- iOS runtime: `CueApp.swift` -> `IOSAppViewModel.swift` -> `IosAppGraph` -> shared `CueController`.
- Shared orchestration: `shared/src/commonMain/kotlin/com/utkudemir/cue/shared/CueController.kt`.
- Current product boundary: OAuth device flow + `/rest/1.0/user` + local reminders/diagnostics.
- Do not add `/unrestrict/*`, `/downloads/*`, `/torrents/*`, or `/streaming/*` integrations without fresh compliance review.
- Do not commit signing material, service-account JSON, release evidence, or generated base64 secret files.
