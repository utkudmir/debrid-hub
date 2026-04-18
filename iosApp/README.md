# iOS Host App

This directory contains the native SwiftUI host app for DebridHub.

The repository now keeps iOS in-repo rather than as an external placeholder:

1. `project.yml` defines the Xcode project and target layout.
2. `DebridHubHost/` contains the native SwiftUI app source.
3. The Xcode target builds `shared` through `:shared:embedAndSignAppleFrameworkForXcode`.
4. The app imports `Shared.framework` from the repo-local build output.

From the repo root:

```bash
make ios-project
make ios-open
make ios-run
```

See [docs/ios-setup.md](../docs/ios-setup.md) for the full workflow.
