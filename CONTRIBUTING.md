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
make localization-generate
make localization-check
make shared-test
make android-debug
make ios-run
make verify-rc
```

For deterministic device preparation:

```bash
VERIFY_PROFILE=ci-pr make provision-devices
```

For iOS local runs, dynamic phone-class selection is the default. Optional
overrides:

```bash
IOS_DEVICE_CLASS=latest-phone make ios-run
IOS_SIMULATOR_NAME="<available-simulator-name>" make ios-run
```

Before sharing local `build/rc-verify` artifacts in issues or reviews, create a
redacted copy:

```bash
scripts/redact-shareable-report.sh build/rc-verify
```

## Pull Request Expectations

Before opening a PR, ensure:

- the change behavior is consistent on Android and iOS when cross-platform logic is touched
- shared tests pass (`make shared-test`)
- affected platform build/test checks pass
- release-gate relevant changes were validated (`make verify-rc` when applicable)
- docs are updated when behavior or policy changed

## Localization Contributions

DebridHub localization is managed from a single canonical YAML catalog in
`localization/strings.yml`.

- Update the YAML source instead of editing generated outputs by hand.
- Re-generate outputs with `make localization-generate`.
- Validate parity and generated files with `make localization-check`.
- New locales should use valid BCP-47 tags and stay key-complete with `en`.
- If you open a new language PR, include whether native-speaker review was
  available and whether store metadata is also needed.

## Communication and Safety

- For project conduct expectations, see `CODE_OF_CONDUCT.md`.
- For private vulnerability reporting, see `SECURITY.md`.
