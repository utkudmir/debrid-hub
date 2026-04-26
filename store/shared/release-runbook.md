# Release Runbook

## Preconditions

- RC verification passed locally and in CI
- manual sign-off recorded
- approved tag created (`vX.Y.Z`)
- signed release candidate artifacts built with SHA-256 checksums
- App Store review submission prepared as a manual submit
- Play closed testing requirement completed
- support email is `support.cue.app@gmail.com`
- iOS privacy manifest and export-compliance answers are present

## Credential Handling

- Store signing and upload credentials live only in protected GitHub Environments.
- `production-app-store` contains App Store Connect and Apple signing secrets.
- `production-play-store` contains Android upload-key and Play service-account secrets.
- Do not commit signing material, service-account JSON, screenshots with secrets, or
  release evidence to git.
- Rotate or revoke credentials immediately if any value appears in a public issue,
  PR, log, artifact, or commit.

## Release Candidate Build

1. Run the full RC gate on the candidate commit.
2. Record local redacted evidence under `build/rc-verify/<run_id>/evidence/`.
3. Record release-owner sign-off.
4. Create the approved `vX.Y.Z` tag.
5. Run `build-release-candidate` for the approved tag.
6. Confirm both candidate artifacts include `SHA256SUMS` and are retained for 30 days.

## Store Upload

- `release-to-stores` must download the exact signed candidate artifacts and verify
  `SHA256SUMS` before upload.
- App Store upload is draft/manual-submit only.
- Google Play upload targets closed testing before production rollout.

## Launch Day

1. Set `site/data/launch-state.json` to `live` with store URLs.
2. Verify Pages deployment is complete.
3. Trigger App Store manual release.
4. Trigger Google Play production staged rollout at 20%.
5. Publish GitHub release notes for the tagged source release.
6. After 24-48 hours of clean Android Vitals, reviews, and support email, increase
   Google Play production rollout to 100%.

## Hotfix Policy

Default to fix-forward with a new tag and a new signed candidate.
Only unpublish or pull a release for a severe blocker.
