# Release Gate (RC)

This document defines the release-candidate (RC) gate for DebridHub.

## Decision Rule

- Gate mode is all-or-nothing across Android and iOS.
- A critical flow failure on either platform is `NO-GO`.
- `Warning` findings are reported but do not fail the technical gate.
- Manual release sign-off is required after technical verification.

## Official References

- Real-Debrid API docs: `https://api-1.real-debrid.com/#device_auth`
- Real-Debrid Terms: `https://real-debrid.com/terms`
- Apple App Store Review Guidelines:
  `https://developer.apple.com/app-store/review/guidelines/`

If an official source conflicts with repository docs or implementation, treat
official source as highest priority and update code/docs accordingly.

## Required Automated Checks

Run:

```bash
make verify-rc
```

Optional profile selection:

```bash
VERIFY_PROFILE=ci-pr make verify-rc
```

CI workflow profile mapping (`.github/workflows/verify-rc.yml`):

- `pull_request` -> `VERIFY_PROFILE=ci-pr`
- `push` on `main` -> `VERIFY_PROFILE=ci-pr`
- `schedule` (weekdays 03:00 UTC) -> `VERIFY_PROFILE=rc-full`
- `workflow_dispatch` -> default `VERIFY_PROFILE=rc-full` (input ile `ci-pr` veya `ci-nightly` secilebilir)

Schedule control:

- `rc-full` schedule run is gated by repository variable `ENABLE_RC_FULL_SCHEDULE`
- To activate schedule execution, set `ENABLE_RC_FULL_SCHEDULE=true`
- Workflow logs explicit skip reason when schedule is disabled

PR trigger behavior:

- PR event types: `opened`, `synchronize`, `reopened`, `ready_for_review`
- Draft PRs are skipped at job level; verification runs after PR is ready

CI execution behavior:

- Runner strategy is optimized per phase:
  - `schedule-gate` and `verify-gate` run on `ubuntu-24.04`
  - `verify-shared`, `verify-android`, `verify-ios` run on `macos-15`
- Workflow is split into job-level phases: `verify-shared`, `verify-android`,
  `verify-ios`, `verify-gate`
- Platform jobs run before final gate; `verify-gate` requires successful
  completion of both Android and iOS verification jobs
- Job timeouts: `verify-shared` 90m, `verify-android` 180m, `verify-ios` 180m,
  `verify-gate` 60m
- `cancel-in-progress` is enabled only for `pull_request` runs
- Workflow prints explicit context logs for event/ref/profile/runner before
  provisioning and verification steps

Provision the canonical pool for a profile before running the gate in CI:

```bash
VERIFY_PROFILE=ci-pr make provision-devices
```

When provisioning only one platform target family:

```bash
VERIFY_PROFILE=ci-pr PROVISION_TARGETS=android make provision-devices
VERIFY_PROFILE=ci-pr PROVISION_TARGETS=ios make provision-devices
```

`PROVISION_TARGETS` supports `all` (default), `android`, `ios`.

Profiles are defined in `ci/device-pool.yml`. Profile includes are merged first,
then the active profile overrides matching labels.

Profiles are phone-only by intent. iOS targets resolve to iPhone simulator
classes (`latest-phone`, `small-phone`, `large-phone`) and Android targets
resolve to phone AVD recipes.

`verify-rc` validates profile completeness before expensive steps. If the selected
profile does not resolve to at least one Android target and one iOS target, the
run fails early.

`provision-devices` with default `PROVISION_TARGETS=all` enforces the same rule
and fails immediately when a selected profile is missing either Android or iOS
targets. When `PROVISION_TARGETS` is set to `android` or `ios`, only that
platform target set is required.

Android pool entries support technical fields (`api`, `abi`, `system_image`,
`device_profile`), and iOS entries support (`runtime`, `device_type`) to keep
CI hosts deterministic.

When runtime/device type fields are omitted for an iOS profile target,
provisioning uses dynamic iPhone resolution. It first selects an available
simulator in the requested class and creates one when needed.

Current profile intent:

- `local-fast`: one Android + one iOS target
- `ci-pr`: Android min-edge + latest, iOS latest-phone
- `ci-nightly`: Android min-edge + mid + latest, iOS small-screen + large-screen
- `rc-full`: includes `ci-pr` and `ci-nightly`

The gate script writes artifacts to `build/rc-verify/<run_id>/` and includes:

- per-step logs (redacted)
- `result.json` (machine-readable report)
- `summary.txt` (human-readable report)
- per-device logs in `devices/<platform>/<label>/`

Before sharing local artifacts outside your machine, create a redacted copy:

```bash
scripts/redact-shareable-report.sh build/rc-verify/<run_id>
```

CI uploads these run directories per phase as:

- `rc-verify-shared-artifacts`
- `rc-verify-android-artifacts`
- `rc-verify-ios-artifacts`
- `rc-verify-gate-artifacts`

The script retains only the latest 5 runs.

Long-running command steps now stream output to CI logs while writing to local
step logs. A per-command timeout is enforced by
`STEP_COMMAND_TIMEOUT_SECONDS` (default `2400`).

## Technical Pass Criteria

Minimum automated pass requirements:

1. `make shared-test`
2. `./gradlew :androidApp:lint :androidApp:testDebugUnitTest`
3. `make coverage`
4. `make android-debug`
5. Android install + smoke launch
6. `make ios-build`
7. `make ios-test`
8. `make ios-run`
9. iOS smoke launch
10. Real-Debrid boundary scan (no forbidden endpoint integration in code)

Coverage baseline:

- JVM-measurable unit coverage must stay at or above `70%` line coverage.
- JVM-measurable unit coverage must stay at or above `55%` branch coverage.
- Coverage report is generated by `:androidApp:jacocoDebugUnitTestReport` and currently includes Android app logic plus shared Kotlin logic exercised by Android unit tests.

## Critical Failures (Blockers)

Any of these means `NO-GO`:

- crash, freeze, or non-functional core flow
- OAuth flow cannot complete or stores invalid auth state
- reminder scheduling behavior is incorrect
- diagnostics preview/export does not work
- disconnect leaves auth/reminder artifacts behind
- Android and iOS core behavior diverges materially
- policy/guideline violation (Real-Debrid or Apple App Store)

## Manual Evidence Requirements

For each platform, provide evidence for:

- OAuth device-flow success
- account refresh
- reminder config update + sync
- diagnostics preview + export
- disconnect cleanup behavior

Evidence format per platform:

- one short screen recording (preferred), or
- 3-5 timestamped screenshots

Keep evidence local in `build/rc-verify/<run_id>/evidence/` and record paths in
the sign-off table. Do not commit evidence files to git.

## Sign-Off (Single Owner)

Only the configured `release-manager` reviewer can approve release sign-off.

If a different reviewer name appears in sign-off, decision is automatically
`NO-GO`.

Required fields:

- `candidate_commit`
- `verify_rc_run_id`
- `reviewer`
- `date_utc`
- `decision` (`GO` or `NO-GO`)
- `notes`

## Sign-Off Record Template

| candidate_commit | verify_rc_run_id | reviewer | date_utc | decision | notes |
| --- | --- | --- | --- | --- | --- |
| `<sha>` | `<run_id>` | `release-manager` | `<YYYY-MM-DDTHH:MM:SSZ>` | `GO/NO-GO` | `<policy + App Store notes + evidence paths>` |

## Tagging and Release Notes

After a `GO` sign-off, create a semantic version tag on the approved
`candidate_commit` and publish release notes.

Policy:

- Tags use `vMAJOR.MINOR.PATCH` format (for example `v1.2.3`).
- `CHANGELOG.md` must be updated from `[Unreleased]` before publishing.
- GitHub release notes should summarize user-visible changes and any known
  limitations.
- If a late blocker appears after tag preparation, do not publish; record
  `NO-GO`, fix forward, and re-run `make verify-rc`.
