# Contributing to DebridHub

Thanks for helping improve DebridHub.

This project is intentionally scoped to a narrow, lower-risk feature set:

- OAuth2 device flow authentication
- `/rest/1.0/user` account status
- local reminders
- local diagnostics

Please keep contributions aligned with that boundary.

## Accepted Contribution Areas

Contributions are welcome for:

- bug fixes
- tests and reliability improvements
- Android and iOS UX improvements
- documentation quality
- CI and release-gate reliability

## Out of Scope Without Compliance Review

Do not add these without explicit maintainer approval and compliance review:

- `/unrestrict/*` integrations
- `/downloads/*` integrations
- `/torrents/*` integrations
- `/streaming/*` integrations
- multi-account or delegated account management
- backend token sync or remote job execution

See `docs/compliance.md` for boundary details.

## Development and Verification

Common commands:

```bash
make shared-test
make android-debug
make ios-run
make verify-rc
```

For deterministic device preparation:

```bash
VERIFY_PROFILE=ci-pr make provision-devices
```

## Pull Request Expectations

Before opening a PR, ensure:

- the change behavior is consistent on Android and iOS when cross-platform logic is touched
- shared tests pass (`make shared-test`)
- affected platform build/test checks pass
- release-gate relevant changes were validated (`make verify-rc` when applicable)
- docs are updated when behavior or policy changed

## Communication and Safety

- For project conduct expectations, see `CODE_OF_CONDUCT.md`.
- For private vulnerability reporting, see `SECURITY.md`.
