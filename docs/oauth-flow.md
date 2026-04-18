# Real-Debrid OAuth Device Flow

This document describes the authentication flow used by DebridHub.

The app uses Real-Debrid's documented OAuth2 **device flow for open-source
apps**, not a username/password login flow and not the private API token paste
flow. The relevant public documentation is available at:

- `https://api-1.real-debrid.com/#device_auth`
- `https://api.real-debrid.com/`

## Why This Flow

Real-Debrid provides a special workflow for open-source apps and scripts that
cannot safely ship a global `client_secret`. In that workflow:

- the app starts with the public client id
- Real-Debrid returns a short-lived device code and user code
- the user authorizes the app on a Real-Debrid web page
- the app polls for user-bound client credentials
- the app exchanges the device code for tokens using those user-bound
  credentials

This keeps the user's Real-Debrid password and private token out of the app.

## Current DebridHub Flow

1. **Request a device code**

   DebridHub calls:

   ```text
   GET /oauth/v2/device/code?client_id={clientId}&new_credentials=yes
   ```

   The response contains:

   - `device_code`
   - `user_code`
   - `verification_url`
   - `interval`
   - `expires_in`

   In practice, Real-Debrid may also return `direct_verification_url`. When
   present, DebridHub prefers it because it takes the user directly to the app
   authorization page.

2. **Show the code**

   The app displays the `user_code` in the UI and provides a copy action.

3. **Open the authorization page**

   - iOS opens the authorization page inside the app with Safari Services.
   - Android opens the authorization page in the system browser.

4. **Poll for credentials**

   DebridHub polls:

   ```text
   GET /oauth/v2/device/credentials?client_id={clientId}&code={deviceCode}
   ```

   until Real-Debrid returns a user-bound `client_id` and `client_secret`.

5. **Exchange for tokens**

   DebridHub posts to:

   ```text
   POST /oauth/v2/token
   ```

   with:

   - `client_id`
   - `client_secret`
   - `code={device_code}`
   - `grant_type=http://oauth.net/grant_type/device/1.0`

   The response returns:

   - `access_token`
   - `refresh_token`
   - `expires_in`

6. **Refresh later**

   Real-Debrid documents refresh through the same token endpoint using:

   - `client_id`
   - `client_secret`
   - `code={refresh_token}`
   - `grant_type=http://oauth.net/grant_type/device/1.0`

   DebridHub follows that contract.

7. **Disconnect**

   Disconnect clears locally stored auth state and cancels reminders.

## API Hosts

DebridHub primarily targets:

- `https://api.real-debrid.com`

It can also retry against:

- `https://api-1.real-debrid.com`

The fallback exists because some networks interfere with only one of the
official API hostnames. The app does not fall back to any non-Real-Debrid
service.

## Security Notes

- The user authorizes on a Real-Debrid page, not by typing their password into
  the app.
- Tokens stay local to the device.
- The app does not send tokens to a DebridHub backend because there is no
  backend.

Current implementation note:

- Android stores auth state with `EncryptedSharedPreferences`.
- iOS stores auth state in Keychain and migrates legacy `NSUserDefaults` data.

## Compliance Notes

This auth flow is part of Real-Debrid's public API documentation and is the
intended integration path for mobile or open-source clients. DebridHub's
current use of the flow is limited to account authentication and account-status
checks; it does not currently invoke link-unrestriction, torrent, streaming, or
download-management endpoints.
