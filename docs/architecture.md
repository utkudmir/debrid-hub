# Architecture Overview

DebridHub is a Kotlin Multiplatform project that shares business logic across
Android and iOS while keeping the presentation layer native on each platform.
The app is intentionally small in scope:

- authenticate with Real-Debrid using the official OAuth2 device flow for
  open-source apps
- fetch the authenticated user's account status
- compute expiry state
- schedule local reminders
- export non-sensitive diagnostics on demand

The app does not have a backend.

## Repository Layout

```text
debrid-hub/
├── shared/       # Shared KMP domain, data, auth, reminders, diagnostics
├── androidApp/   # Active Android app (Jetpack Compose)
├── iosApp/       # Active iOS host app (SwiftUI + Xcode project)
├── composeApp/   # Legacy shared-UI experiment, not in the active build
└── docs/         # Project documentation
```

## Active Modules

### `shared`

This is the core of the application. It contains:

- `domain.model`
  Immutable app models such as `AccountStatus`, `ReminderConfig`,
  `StoredAuthState`, and `DiagnosticsBundle`.
- `domain.repository`
  Interfaces for auth, account status, reminders, and diagnostics.
- `data.remote`
  `RealDebridApi`, the shared Ktor client for Real-Debrid OAuth and REST
  calls.
- `data.repository`
  Concrete repository implementations that orchestrate auth, account refresh,
  reminder scheduling, and diagnostics collection.
- `platform`
  Cross-platform interfaces such as `SecureTokenStore`,
  `NotificationScheduler`, `ReminderConfigStore`, and `FileExporter`, plus
  platform-specific `androidMain` and `iosMain` implementations.
- `reminders`
  Reminder planning logic that turns account expiry data into notification
  timestamps.
- `usecase`
  Orchestration use cases such as diagnostics export.

Notable shared behavior:

- OAuth2 device-flow support for Real-Debrid's open-source-app workflow
- API host failover between `api.real-debrid.com` and `api-1.real-debrid.com`
- access-token refresh using the documented Real-Debrid refresh contract
- local-only diagnostics export

### `androidApp`

The Android app is the active Android runtime target. It uses:

- `MainActivity` as the launcher activity
- `DebridHubViewModel` for UI state and auth/reminder orchestration
- Jetpack Compose UI defined in `DebridHubApp.kt`
- `EncryptedSharedPreferences` for auth state storage
- `AlarmManager` plus `BroadcastReceiver` notifications for reminders

Android currently opens the Real-Debrid authorization page externally and keeps
polling in the app while the user authorizes.

### `iosApp`

The iOS app is an active native SwiftUI host application that links the shared
framework produced by the `shared` module. It uses:

- `IOSAppViewModel` as the SwiftUI view model bridge
- `ContentView.swift` for the primary native UI
- an in-app Safari sheet for the authorization page
- the shared `DebridHubController` from the KMP layer

Current iOS storage note:

- reminder preferences use `NSUserDefaults`
- auth state uses iOS Keychain via `SecureTokenStore.ios.kt`
- legacy `NSUserDefaults` auth state is migrated to Keychain on first read

### `composeApp`

`composeApp` is leftover from an earlier shared-UI experiment. It is not part
of the active Gradle build in `settings.gradle.kts` and is not the current
runtime path for either platform.

## Authentication Flow

DebridHub follows Real-Debrid's documented OAuth2 workflow for open-source
apps:

1. Request a device code with `new_credentials=yes`.
2. Show the returned `user_code`.
3. Direct the user to the authorization page.
4. Poll `/oauth/v2/device/credentials` until Real-Debrid returns a
   user-bound `client_id` and `client_secret`.
5. Exchange the `device_code` for an access token and refresh token.
6. Refresh the access token later using the saved refresh token.

On iOS, the authorization page is opened inside the app with Safari Services.
On Android, the page is opened via a normal browser intent.

## Account and Reminder Flow

Once authenticated:

1. `AccountRepositoryImpl` requests `/rest/1.0/user`.
2. The response is mapped into `AccountStatus`.
3. `ComputeExpiryStateUseCase` derives `ACTIVE`, `EXPIRING_SOON`, `EXPIRED`,
   or `UNKNOWN`.
4. `ReminderPlanner` converts the status and user preferences into
   `ScheduledReminder` values.
5. Each platform's `NotificationScheduler` schedules those reminders locally.

## Diagnostics Flow

Diagnostics are collected only when the user explicitly exports them.

The current payload contains:

- app version
- OS string
- last successful sync timestamp, if any
- account expiry-state label
- extra flags such as whether notifications are enabled

No access token, refresh token, username, email address, file names, or
download history is included.

## Compliance Boundary

The current architecture intentionally avoids Real-Debrid endpoints that would
move the project into a much riskier policy area, including:

- `/unrestrict/*`
- `/downloads/*`
- `/torrents/*`
- `/streaming/*`

That boundary should remain in place unless future feature work includes a
fresh compliance review.
