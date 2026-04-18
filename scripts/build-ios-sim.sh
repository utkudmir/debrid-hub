#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/ios-derived-data}"
SIMULATOR_NAME="${IOS_SIMULATOR_NAME:-iPhone 17 Pro Max}"
SIMULATOR_UDID="${IOS_SIMULATOR_UDID:-}"
if [[ -z "${JAVA_HOME:-}" || ! -x "$JAVA_HOME/bin/java" ]]; then
  export JAVA_HOME="$("/usr/libexec/java_home" -v 21 2>/dev/null)"
fi

"$ROOT_DIR/scripts/generate-ios-project.sh"

if [[ -n "$SIMULATOR_UDID" ]]; then
  DESTINATION="platform=iOS Simulator,id=$SIMULATOR_UDID"
else
  DESTINATION="platform=iOS Simulator,name=$SIMULATOR_NAME"
fi

xcodebuild \
  -project "$ROOT_DIR/iosApp/DebridHubHost.xcodeproj" \
  -scheme DebridHubHost \
  -configuration Debug \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build
