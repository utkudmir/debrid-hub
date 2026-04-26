# Store Release Setup

This checklist prepares Cue for a first paid release on Apple App Store and
Google Play without storing credentials in git or any public location.

## Decisions

- Publisher type: individual.
- Commercial model: paid upfront, no IAP or subscriptions.
- Price: 4.99 USD with automatic local pricing.
- App identity: `com.utkudemir.cue` for iOS bundle ID and Android package ID.
- Store name: `Cue: Renewal Reminder`; device name: `Cue`.
- Device scope: phone-only v1.
- Apple category: Utilities.
- Google Play category: Tools.
- Rating target: Apple 4+, Google Everyone; not designed for children.
- Reviewer access: demo mode only; do not share Real-Debrid credentials.
- Support email: `support.cue.app@gmail.com`.
- Legal URLs: GitHub Pages v1 privacy/support/review pages.

## Account Security Baseline

- Enable hardware-key, passkey, or authenticator-based 2FA for Apple, Google,
  GitHub, and support email accounts.
- Do not use SMS as the only second factor.
- Do not share personal account passwords with CI, fastlane, collaborators, or
  issue trackers.
- Use dedicated machine credentials for CI:
  - App Store Connect API key for Apple uploads.
  - Google Play service account JSON for Play uploads.
- Store all CI credentials only in protected GitHub Environments.
- Revoke and rotate any credential that appears in a public issue, PR, log,
  artifact, or commit.

## GitHub Setup

Create protected environments:

- `production-app-store`
- `production-play-store`

Require the release owner as reviewer for both environments.

Use the dry-run helper before changing GitHub settings:

```bash
make github-release-controls
```

Apply environment creation only after checking the dry-run output:

```bash
scripts/setup-github-release-controls.sh --apply --release-owner <github-login>
```

Add repository rulesets before creating release tags:

- `main` ruleset:
  - require pull requests
  - require verification checks
  - block force pushes
  - block branch deletion
- `v*` tag ruleset:
  - restrict tag creation to the release owner
  - require signed annotated tags when available
  - block tag deletion and force updates

Enable GitHub secret scanning and push protection when available for the repo.

## GitHub Environment Variables and Secrets

`production-app-store` variables:

- `APPLE_DEVELOPMENT_TEAM_ID`

`production-app-store` secrets:

- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_BASE64`
- `APPLE_SIGNING_CERTIFICATE_BASE64`
- `APPLE_SIGNING_CERTIFICATE_PASSWORD`
- `APPLE_PROVISIONING_PROFILE_BASE64`
- `APPLE_PROVISIONING_PROFILE_NAME`
- `APPLE_EXPORT_OPTIONS_PLIST_BASE64`

`production-play-store` secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64`

Do not add these values to `.env`, `.env.release.example`, README files, issues,
or workflow logs.

### Where Each GitHub Secret Comes From

Use macOS base64 without line wrapping when converting files:

```bash
base64 -i path/to/file -o path/to/file.base64
```

Copy the generated `.base64` file contents into GitHub Environment Secrets, then
delete the temporary `.base64` file after confirming the secret was saved.

| GitHub name | Type | Source | How to get it |
| --- | --- | --- | --- |
| `APPLE_DEVELOPMENT_TEAM_ID` | Environment variable | Apple Developer membership | Apple Developer account team ID. Find it in Apple Developer account membership details or App Store Connect team information. This is not secret, but keep it as an environment variable. |
| `APP_STORE_CONNECT_API_KEY_ID` | Secret | App Store Connect API key | App Store Connect -> Users and Access -> Integrations -> App Store Connect API -> Keys. Create key `Cue CI Upload`; copy the Key ID. |
| `APP_STORE_CONNECT_ISSUER_ID` | Secret | App Store Connect API key page | Same API Keys page. Copy the Issuer ID shown above the keys list. |
| `APP_STORE_CONNECT_API_KEY_BASE64` | Secret | Downloaded App Store Connect `.p8` key | Download the `.p8` once when creating the API key. Store the original in the vault. Base64-encode the `.p8` file and paste the encoded content. |
| `APPLE_SIGNING_CERTIFICATE_BASE64` | Secret | Apple Distribution certificate exported from Keychain as `.p12` | Create/download Apple Distribution cert in Apple Developer, import into Keychain, export certificate plus private key as `.p12`, then base64-encode the `.p12`. |
| `APPLE_SIGNING_CERTIFICATE_PASSWORD` | Secret | Password chosen during `.p12` export | This is the password you set when exporting the `.p12` from Keychain. Store it in the vault and paste the value into GitHub. |
| `APPLE_PROVISIONING_PROFILE_BASE64` | Secret | Apple Developer App Store provisioning profile | Apple Developer -> Profiles -> create App Store profile for `com.utkudemir.cue` using the Apple Distribution cert. Download `.mobileprovision`, then base64-encode it. |
| `APPLE_PROVISIONING_PROFILE_NAME` | Secret | Provisioning profile name | The exact profile name you entered in Apple Developer, for example `Cue App Store`. It must match `ExportOptions.plist`. |
| `APPLE_EXPORT_OPTIONS_PLIST_BASE64` | Secret | Locally created `ExportOptions.plist` | Create an App Store export options plist with method `app-store-connect`, team ID, manual signing, and provisioning profile mapping for `com.utkudemir.cue`. Base64-encode the plist. |
| `ANDROID_KEYSTORE_BASE64` | Secret | Locally generated Android upload keystore `.jks` | Generate a dedicated upload keystore with `keytool`. Store the original `.jks` in the vault. Base64-encode the `.jks` for GitHub. |
| `ANDROID_KEYSTORE_PASSWORD` | Secret | Password chosen when creating `.jks` | The keystore password entered during `keytool -genkeypair`. Store it in the vault and paste it into GitHub. |
| `ANDROID_KEY_ALIAS` | Secret | Alias chosen when creating `.jks` | The alias passed to `keytool -alias`, recommended value: `cue-upload`. |
| `ANDROID_KEY_PASSWORD` | Secret | Key password chosen when creating `.jks` | The key password entered during `keytool -genkeypair`. It may be the same as the keystore password, but store and enter it separately. |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64` | Secret | Google Cloud service account JSON key | Google Play Console -> Setup -> API access -> linked Google Cloud project -> service account. Create JSON key, store original in vault, base64-encode JSON for GitHub. |

Recommended local temporary layout, outside the repository:

```text
~/CueReleaseSecrets/
  apple/
    AuthKey_<KEY_ID>.p8
    CueDistribution.p12
    Cue_App_Store.mobileprovision
    ExportOptions.plist
  android/
    cue-upload.jks
    google-play-service-account.json
```

Do not keep this directory in iCloud Drive, Dropbox, Google Drive, the repo, or
the Desktop long term. Prefer an encrypted DMG or password manager attachment for
the master copies.

Example Android upload keystore generation:

```bash
keytool -genkeypair \
  -v \
  -keystore cue-upload.jks \
  -alias cue-upload \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000
```

Example `ExportOptions.plist` template:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>teamID</key>
  <string>YOUR_TEAM_ID</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>com.utkudemir.cue</key>
    <string>Cue App Store</string>
  </dict>
</dict>
</plist>
```

## Apple Developer Setup

1. Confirm Apple Developer Program membership is active for the individual owner.
2. Confirm paid-app agreements, tax, and banking are complete.
3. Create the explicit App ID `com.utkudemir.cue`.
4. Leave capabilities at the default set for v1.
5. Create an Apple Distribution certificate.
6. Create an App Store provisioning profile for `com.utkudemir.cue`.
7. Export the certificate as `.p12` and store the master copy in an encrypted
   password manager or vault.
8. Base64-encode the `.p12`, provisioning profile, and export options plist for
   GitHub Environment Secrets.
9. Create an App Store Connect API key with the least privilege that supports
   `deliver` and `pilot` uploads.
10. Store the `.p8` key only as `APP_STORE_CONNECT_API_KEY_BASE64` in the
    protected GitHub Environment.

## App Store Connect App Setup

1. Create the app with bundle ID `com.utkudemir.cue`.
2. Set primary locale to `en-US`.
3. Set name to `Cue: Renewal Reminder`.
4. Set category to Utilities.
5. Set pricing to paid, 4.99 USD, automatic local pricing.
6. Use GitHub Pages URLs for privacy, support, and review guide pages.
7. Fill App Privacy with conservative accurate answers:
   - no tracking
   - no analytics
   - no developer backend collection
   - auth/account status used only for app functionality
8. Complete export-compliance answers for standard HTTPS/OAuth encryption.
9. Use review notes from `store/app-store/review-notes.md`.
10. Submit manually after CI uploads metadata and build.
11. Release manually after approval.

## Google Play Console Setup

1. Confirm Google Play developer account is active for the individual owner.
2. Confirm payment profile, tax, and banking are complete.
3. Create the app with package ID `com.utkudemir.cue`.
4. Set title to `Cue: Renewal Reminder`.
5. Set category to Tools.
6. Set pricing to paid, 4.99 USD, automatic local pricing.
7. Enable Play App Signing.
8. Generate a dedicated upload keystore locally on a trusted machine.
9. Store the keystore master copy in an encrypted password manager or vault.
10. Base64-encode only the CI copy for `ANDROID_KEYSTORE_BASE64`.
11. Create a dedicated Google Play service account.
12. Grant access only to this app and only to the permissions required for listing
    and release uploads.
13. Store the service account JSON only as
    `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64` in the protected environment.
14. Complete Data Safety with no tracking, no ads, no analytics, and no developer
    backend collection.
15. Complete target audience as adults/not children and do not enroll in Families.
16. Run internal testing for smoke validation.
17. Run mandatory closed testing before production if the account is subject to
    the 20 tester / 14 day requirement.
18. Start production staged rollout at 20%, then move to 100% after clean signals.

## CI/CD Release Flow

1. Select a candidate commit.
2. Freeze release scope; only P0/P1 fixes can change the candidate.
3. Run `VERIFY_PROFILE=rc-full make verify-rc` or the equivalent CI manual run.
4. Run manual App Store review checklist and screenshot visual QA.
5. Store local redacted evidence under `build/rc-verify/<run_id>/evidence/`.
6. Record release-owner sign-off.
7. Create protected signed tag `vX.Y.Z`.
8. Run `build-release-candidate` for the tag.
9. Confirm Android and iOS artifacts include `SHA256SUMS`.
10. Run `release-to-stores` for the same tag.
11. Manually submit App Store review.
12. Move Google Play from internal to closed testing, then production staged
    rollout after eligibility.
13. When both stores are ready, update `site/data/launch-state.json` with live
    store URLs and publish GitHub release notes.

## No-Go Conditions

- Any credential appears in a public or git-tracked location.
- `PrivacyInfo.xcprivacy` is missing from the iOS app bundle.
- RC full verification fails.
- Manual evidence or release-owner sign-off is missing.
- Candidate artifact checksum verification fails.
- Store metadata contradicts actual app behavior.
- Unapproved Real-Debrid endpoint integrations appear in active code.
