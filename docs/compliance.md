# Compliance Notes

This document records the current feature boundary of DebridHub against
Real-Debrid's public API documentation and published Terms of Service.

It is a project note for engineering decisions, not legal advice.

## Official References

- Real-Debrid API documentation:
  `https://api-1.real-debrid.com/#device_auth`
- Real-Debrid Terms of Service:
  `https://real-debrid.com/terms`

## Current Integration Scope

DebridHub currently uses:

- the documented OAuth2 device flow for open-source apps
- the authenticated `/rest/1.0/user` endpoint
- local notifications
- local diagnostics export

That is the current intended boundary.

## Why the Current Scope Looks Lower Risk

The current app:

- does not generate unrestricted links
- does not add or manage torrents
- does not read download history
- does not stream media
- does not resell or manage someone else's account
- does not share generated links
- does not run a backend that stores user credentials

From a product-behavior perspective, it is an account-status and reminder app.

## Terms Relevant to Product Decisions

Real-Debrid's published terms currently state that:

- the account is for personal use only
- account sharing can lead to suspension
- generated-link sharing can lead to suspension
- the user is not allowed to resell a premium account or manage it for someone
  else without explicit permission
- dedicated server, VPS, or cloud-service use is restricted except where
  Real-Debrid explicitly allows it through remote traffic

Those points matter because they constrain which future features are safe to
build around the service.

## Guardrails for Future Features

Before adding any of the following, do a fresh compliance review:

1. Link-unrestriction or download workflows
   This includes `/unrestrict/*`, `/downloads/*`, or anything that turns the
   app into a delivery client.
2. Torrent-management workflows
   This includes `/torrents/*`, magnet submission, or file selection features.
3. Streaming features
   This includes `/streaming/*` or any in-app playback integration.
4. Multi-account or delegated account management
   Anything that helps a user manage another person's account or operate shared
   credentials raises clear terms risk.
5. Backend sync or remote job execution
   Syncing tokens to a server, automating refreshes remotely, or running on a
   cloud/VPS host materially changes the compliance posture.

## Current Residual Risks

- The service terms can change, so this note should be revisited over time.
- Users can still misuse their Real-Debrid accounts outside the app; DebridHub
  does not control that behavior.
- iOS auth storage is Keychain-backed; migration from legacy
  `NSUserDefaults` data should remain verified as the app evolves.
