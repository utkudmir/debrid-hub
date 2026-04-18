# Privacy Policy

DebridHub is designed to keep user data on-device whenever possible. This
document describes the data the app handles in its current implementation.

## Data the App Uses

### Real-Debrid Auth State

DebridHub uses Real-Debrid's official OAuth2 device flow to obtain:

- an access token
- a refresh token
- user-bound OAuth client credentials

Current storage implementation:

- Android stores auth state with `EncryptedSharedPreferences`.
- iOS stores auth state in Keychain and migrates legacy `NSUserDefaults` data.

The app does not ask the user to paste their private Real-Debrid token.

### Account Status

When the user refreshes the account, the app requests the authenticated
Real-Debrid `/rest/1.0/user` endpoint and reads:

- username
- premium type/status
- remaining premium time
- expiration timestamp

This information is used to build the local `AccountStatus` model and drive the
reminder planner. It is not uploaded to any DebridHub server.

### Reminder Preferences

The app stores local reminder settings such as:

- whether reminders are enabled
- which day offsets should trigger reminders
- whether to notify on expiry day
- whether to notify after expiry

These preferences stay on-device.

### Diagnostics Export

If the user explicitly exports diagnostics, DebridHub writes a local JSON file
containing high-level information such as:

- app version
- OS string
- last sync time
- expiry-state label
- flags such as whether notifications are enabled

The app does not automatically upload this file anywhere.

## Data the App Does Not Use

DebridHub does not currently collect or transmit:

- download history
- generated links
- torrent metadata
- streaming metadata
- watch history
- advertising identifiers
- analytics events

## Network Behavior

The app talks directly to Real-Debrid's official API hosts.

Current API hosts:

- `https://api.real-debrid.com`
- `https://api-1.real-debrid.com` as a fallback when needed

There is no DebridHub backend and no third-party analytics endpoint.

## User Control

The user can:

- disconnect the Real-Debrid account
- disable reminders
- delete the app and its local data
- inspect diagnostics before sharing them

Disconnect clears locally stored auth state and cancels scheduled reminders.

## Current Limitations

The docs in this repository describe the app as implemented today, including
the current Keychain-backed iOS auth storage and legacy migration behavior.
