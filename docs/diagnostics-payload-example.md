# Diagnostics Payload Example

DebridHub can export a local JSON diagnostics file when the user explicitly
asks for it. The file is intended for manual troubleshooting and is not sent
automatically anywhere.

## Included Fields

The current payload contains:

- `appVersion`
- `os`
- `lastSync`
- `accountState`
- `additionalInfo`

`additionalInfo` currently includes simple flags such as whether notifications
are enabled.

## Excluded Fields

The diagnostics export does **not** include:

- access tokens
- refresh tokens
- OAuth client secrets
- username
- email address
- generated links
- torrent names
- download history

## Example Payload

```json
{
  "appVersion": "1.0.0",
  "os": "Android 14",
  "lastSync": "2026-04-08T19:22:13Z",
  "accountState": "ACTIVE",
  "additionalInfo": {
    "notificationsEnabled": "true"
  }
}
```

This example matches the structure produced by `ExportDiagnosticsUseCase` in the
current codebase.
