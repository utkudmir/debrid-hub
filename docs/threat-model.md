# Threat Model

This document summarizes the main security assumptions and current known gaps in
DebridHub.

## Assets

- Real-Debrid access token
- Real-Debrid refresh token
- user-bound OAuth client credentials
- reminder preferences
- exported diagnostics files

## Threats Considered

1. **Local data exposure**
   Another app or a compromised device attempts to read locally stored auth
   state.
2. **Network interception**
   A hostile or misconfigured network interferes with HTTPS requests to
   Real-Debrid.
3. **Unexpected API failures**
   Real-Debrid returns errors, invalid responses, or a host becomes
   temporarily unreachable.
4. **Feature creep into risky endpoints**
   Future development adds download, torrent, or link-generation behavior that
   changes the app's compliance and security posture.

## Mitigations in the Current Project

### Local-Only Architecture

DebridHub has no backend. Tokens are not forwarded to any DebridHub service
because no such service exists.

### OAuth2 Device Flow

The app uses Real-Debrid's documented device flow for open-source apps. The
user authorizes on a Real-Debrid page instead of entering account credentials
directly into DebridHub.

### Android Secure Storage

On Android, auth state is stored with `EncryptedSharedPreferences`.

### API Host Failover

The shared client can retry against `api-1.real-debrid.com` when transport
failures occur against `api.real-debrid.com`. This helps when only one official
hostname is blocked or downgraded by the current network.

### Local Notifications

Reminders are local notifications. They do not depend on a remote push service.

### Minimal Permissions

The app requests internet access and notification permission. It does not
request location, contacts, photos, or microphone access.

## Known Gaps

### iOS Legacy Auth Migration Surface

On iOS, auth state is stored in Keychain. For backward compatibility, the app
still reads a legacy `NSUserDefaults` value and migrates it to Keychain, then
clears the legacy entry. That migration path should remain covered by tests and
manual regression checks.

### Network Middleboxes Can Still Break Access

Fallback between official Real-Debrid API hosts improves resilience, but a
network that blocks or downgrades both hosts can still prevent the app from
working.

### Development Logging

Temporary auth-flow logs may exist in development builds while debugging
integration issues. Those logs should be removed or minimized before any
production release.

## Out of Scope

- a rooted or jailbroken device
- malware with full device compromise
- phishing on the Real-Debrid website itself
- illegal or infringing use of a user's Real-Debrid account outside this app

## Feature Guardrail

Any future work that touches these endpoint groups should trigger a fresh
security and compliance review:

- `/unrestrict/*`
- `/downloads/*`
- `/torrents/*`
- `/streaming/*`
