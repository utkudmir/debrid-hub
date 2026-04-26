# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
for tagged releases.

## [Unreleased]

- Placeholder section for upcoming changes after v1.0.0.

## [1.0.0] - 2026-04-26

### Added

- Initial Cue release for Real-Debrid renewal reminders.
- Official OAuth device-flow connection with premium status visibility.
- Local reminder scheduling, diagnostics preview/export, and disconnect cleanup.
- Demo mode for store reviewers without sharing live account credentials.
- Local-first privacy surfaces, support pages, and store release assets.

### Security

- iOS auth state remains Keychain-backed with legacy defaults migration.
- Android release signing is designed for Play App Signing with a dedicated upload key.
- Release workflows use protected environment secrets and signed candidate artifacts.
