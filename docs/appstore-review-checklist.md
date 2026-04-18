# App Store Review Checklist

Use this checklist before iOS submission and during RC sign-off.

## Core Product Clarity

- [ ] First-run makes app purpose clear (account status + reminders + diagnostics).
- [ ] Reviewer can complete core flow without hidden prerequisites.
- [ ] Error states are actionable (network, auth, permissions).

## Privacy and Data Handling

- [ ] App remains local-first (no DebridHub backend token sync).
- [ ] No analytics/tracking SDK added without explicit policy update.
- [ ] Diagnostics export excludes secrets and personal data.
- [ ] iOS auth storage remains Keychain-backed (legacy defaults migration only).

## Permissions and Platform Use

- [ ] Notification permission request is contextual and optional.
- [ ] No unused sensitive permissions (camera, mic, location, photos, tracking).
- [ ] `Info.plist` usage descriptions are present for any requested sensitive APIs.

## Account and Authentication

- [ ] OAuth uses Real-Debrid official device flow only.
- [ ] Disconnect clears local auth artifacts and reminders.
- [ ] No social login additions that trigger Sign in with Apple requirements.

## Payments and External Links

- [ ] No external digital purchase flow added.
- [ ] No subscription/IAP claims unless implemented and reviewable.
- [ ] External links do not mislead about app capabilities.

## Content and Policy Boundary

- [ ] App scope remains account/status/reminder/diagnostics only.
- [ ] No integration of `/unrestrict/*`, `/downloads/*`, `/torrents/*`, `/streaming/*`.
- [ ] No feature that encourages account sharing or delegated account management.

## Reviewer Experience

- [ ] Build launches reliably on current simulator runtime.
- [ ] Reviewer steps are documented in App Review Notes.
- [ ] Any known limitations are clearly stated and reproducible.

## References

- Apple App Store Review Guidelines:
  `https://developer.apple.com/app-store/review/guidelines/`
- Real-Debrid docs and terms:
  `https://api-1.real-debrid.com/#device_auth`
  `https://real-debrid.com/terms`
