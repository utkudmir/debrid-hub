# Localization

DebridHub localization is managed from a single canonical YAML catalog:

- `localization/strings.yml`

Generated outputs are checked into the repository so changes stay reviewable:

- Android resources in `androidApp/src/main/res/values*/strings.xml`
- iOS generated localizer and bundle resources under `iosApp/DebridHubHost/`
- Shared Kotlin localization catalog under `shared/src/commonMain/kotlin/.../localization/`

## Workflow

1. Edit `localization/strings.yml`.
2. Run `make localization-generate`.
3. Run `make localization-check`.
4. Run affected tests and platform validation.

## Supported Languages

- English (`en`) as base locale
- Spanish (`es`)
- French (`fr`)
- German (`de`)
- Turkish (`tr`)

## Rules

- `en` is the canonical base locale.
- All locales must stay key-complete with `en`.
- Placeholder shape and plural shape must match across locales.
- Runtime fallback uses `en` when the current locale is unsupported.

## GitHub Intake

Language requests should use the dedicated GitHub issue template.

Recommended labels:

- `i18n`
- `language-request`
- `needs-native-review`

Store metadata scope can be tracked in issues and PRs, but the first technical
rollout focuses on in-app localization.
