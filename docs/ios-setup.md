# iOS Setup

DebridHub keeps the iOS app inside the same repository under `iosApp/`. The
shared Kotlin Multiplatform code lives in `shared/`, and the native SwiftUI
host app links the generated `Shared.framework` during the Xcode build.

## Requirements

- macOS with Xcode 15 or newer
- JDK 21
- `xcodegen` installed with `brew install xcodegen`

## Root-level commands

Generate the Xcode project:

```bash
make ios-project
```

Open the iOS project in Xcode:

```bash
make ios-open
```

Build for the current simulator from the repo root:

```bash
make ios-build
```

Build, install, and launch the app on the simulator:

```bash
make ios-run
```

You can override the simulator name if needed:

```bash
IOS_SIMULATOR_NAME="iPhone 17 Pro Max" make ios-run
```

## How the integration works

1. `iosApp/DebridHubHost.xcodeproj` is generated from `iosApp/project.yml`.
2. The Xcode target runs `./gradlew :shared:embedAndSignAppleFrameworkForXcode`
   in a pre-build script.
3. The generated `Shared.framework` is linked from
   `shared/build/xcode-frameworks/$(CONFIGURATION)/$(SDK_NAME)`.
4. The SwiftUI host app imports `Shared` and uses the KMP controller and graph
   types exposed by the `shared` module.
