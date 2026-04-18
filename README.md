# DebridHub

DebridHub is a local-only mobile companion app for Real-Debrid subscribers.
Its current scope is intentionally narrow: authenticate with Real-Debrid using
the official OAuth2 device flow, read the authenticated user's subscription
status, show the premium expiry date, and schedule local reminder
notifications before the subscription lapses.

The project is built as a Kotlin Multiplatform app with native presentation on
each platform:

- Android uses Jetpack Compose.
- iOS uses SwiftUI.
- Shared business logic lives in `shared/`.

There is no backend service, no cloud sync, and no analytics SDK. The app only
talks directly to Real-Debrid's official API hosts.

## Current Features

- **Official Real-Debrid OAuth2 device flow for open-source apps.**
  The app uses the documented `/oauth/v2/device/code`,
  `/oauth/v2/device/credentials`, and `/oauth/v2/token` endpoints.
- **Account status view.**
  Shows username, premium state, expiry date, and remaining days from the
  `/rest/1.0/user` endpoint.
- **Reminder scheduling.**
  Lets the user configure local notifications before expiry, on expiry day,
  and after expiry.
- **Copyable authorization code.**
  The device-flow code is shown in-app and can be copied while the user
  authorizes the app.
- **Diagnostics export.**
  Generates a local JSON file containing non-sensitive debugging information.
- **API host failover.**
  The shared client can retry against `https://api-1.real-debrid.com` if the
  default API hostname is blocked or downgraded by the current network.

## Project Structure

| Path | Purpose |
| --- | --- |
| `shared/` | Shared domain, data, auth, reminder, diagnostics, and platform abstraction code. |
| `androidApp/` | Active Android app built with Jetpack Compose. |
| `iosApp/` | Active native SwiftUI iOS host app and Xcode project definition. |
| `composeApp/` | Legacy shared-UI experiment kept in the repo, but not part of the active build. |
| `docs/` | Architecture, auth, privacy, threat model, iOS setup, diagnostics example, and compliance notes. |

See [docs/architecture.md](docs/architecture.md) for the implementation
layout and [docs/compliance.md](docs/compliance.md) for current policy
boundaries.

## Build and Run

Run shared tests:

```bash
make shared-test
```

Build the Android debug app:

```bash
make android-debug
```

Generate and open the iOS project:

```bash
make ios-open
```

Build and run the iOS simulator app:

```bash
make ios-run
```

Run the release-candidate verification gate:

```bash
make verify-rc
```

Use a specific device-pool profile when needed:

```bash
VERIFY_PROFILE=ci-pr make verify-rc
```

Device pools are defined in `ci/device-pool.yml`.

Provision canonical simulators/AVDs for a profile:

```bash
VERIFY_PROFILE=ci-pr make provision-devices
```

Requirements:

- macOS
- Xcode 15 or newer
- JDK 21
- Android SDK for Android builds
- `xcodegen` for the helper iOS commands

See [docs/ios-setup.md](docs/ios-setup.md) for the iOS workflow.
See [docs/release-gate.md](docs/release-gate.md) for RC gate policy and evidence requirements.

CI quick notes:

- Scheduled `rc-full` runs are guarded by repository variable `ENABLE_RC_FULL_SCHEDULE`; set it to `true` to enable weekday schedule execution.
- Manual GitHub Actions runs (`workflow_dispatch`) expose `verify_profile` choices: `ci-pr`, `ci-nightly`, `rc-full`.

## Security and Privacy

DebridHub is designed to stay local-first:

For private vulnerability reporting, follow [SECURITY.md](SECURITY.md).

1. **No backend.**
   Requests go directly from the device to Real-Debrid.
2. **No private token paste flow.**
   Authentication uses the official OAuth2 device flow.
3. **Minimal permissions.**
   The app only needs internet access and notification permission.
4. **Manual diagnostics only.**
   Diagnostics are exported only when the user chooses to do so.

Current storage reality:

- Android stores auth state with `EncryptedSharedPreferences`.
- iOS stores auth state in Keychain and migrates legacy `NSUserDefaults` data.

The docs in this repository describe the current implementation as it exists
today.

## Compliance Scope

The app currently stays within a narrow, lower-risk integration surface:

- official OAuth2 device authentication
- account-status reads
- local reminders
- local diagnostics

It does **not** currently call Real-Debrid endpoints for unrestricting links,
downloads, torrents, streaming, or remote traffic management. That boundary is
intentional. See [docs/compliance.md](docs/compliance.md) for the current audit
notes and feature guardrails.

## Contributing

Pull requests that improve security, testing, correctness, or UX are welcome.
See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution flow,
validation expectations, and scope guardrails.

Community behavior expectations are in
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
Private vulnerability reporting is documented in [SECURITY.md](SECURITY.md).

Contributing quick links:

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- [SECURITY.md](SECURITY.md)
- [docs/compliance.md](docs/compliance.md)
- [docs/release-gate.md](docs/release-gate.md)

Please avoid adding features that:

- manage accounts for other people
- encourage account sharing
- automate link generation or download workflows
- use torrent, streaming, downloads, or unrestrict endpoints without an
  explicit compliance review

## License

This project is provided under the MIT License. See [LICENSE](LICENSE).
