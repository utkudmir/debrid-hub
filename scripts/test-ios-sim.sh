#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/ios-derived-data}"
IOS_TEST_DESTINATION_TIMEOUT="${IOS_TEST_DESTINATION_TIMEOUT:-180}"
SIMULATOR_NAME="${IOS_SIMULATOR_NAME:-}"
SIMULATOR_UDID="${IOS_SIMULATOR_UDID:-}"
IOS_DEVICE_CLASS="${IOS_DEVICE_CLASS:-latest-phone}"
IOS_RESOLVER_SCRIPT="$ROOT_DIR/scripts/resolve-ios-simulator.py"
BUNDLE_ID="app.debridhub.ios"

if [[ -z "${JAVA_HOME:-}" || ! -x "$JAVA_HOME/bin/java" ]]; then
  export JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null)"
fi

"$ROOT_DIR/scripts/generate-ios-project.sh"

if [[ -z "$SIMULATOR_UDID" && -z "$SIMULATOR_NAME" ]]; then
  if [[ ! -x "$IOS_RESOLVER_SCRIPT" ]]; then
    echo "resolve-ios-simulator script is missing: $IOS_RESOLVER_SCRIPT" >&2
    exit 1
  fi
  if ! resolver_output="$(python3 "$IOS_RESOLVER_SCRIPT" --label "$IOS_DEVICE_CLASS" 2>/dev/null)"; then
    echo "Unable to resolve iPhone simulator dynamically. Set IOS_SIMULATOR_NAME or IOS_SIMULATOR_UDID." >&2
    exit 1
  fi
  SIMULATOR_NAME="$(printf '%s' "$resolver_output" | awk -F '\t' '{print $1}')"
  SIMULATOR_UDID="$(printf '%s' "$resolver_output" | awk -F '\t' '{print $2}')"
fi

if [[ -z "$SIMULATOR_UDID" && -n "$SIMULATOR_NAME" ]]; then
  if [[ ! -x "$IOS_RESOLVER_SCRIPT" ]]; then
    echo "resolve-ios-simulator script is missing: $IOS_RESOLVER_SCRIPT" >&2
    exit 1
  fi
  if ! resolver_output="$(python3 "$IOS_RESOLVER_SCRIPT" --label "$IOS_DEVICE_CLASS" --name "$SIMULATOR_NAME" 2>/dev/null)"; then
    echo "Unable to resolve simulator UDID for '$SIMULATOR_NAME'." >&2
    exit 1
  fi
  SIMULATOR_NAME="$(printf '%s' "$resolver_output" | awk -F '\t' '{print $1}')"
  SIMULATOR_UDID="$(printf '%s' "$resolver_output" | awk -F '\t' '{print $2}')"
fi

if [[ -n "$SIMULATOR_UDID" ]]; then
  DESTINATION="platform=iOS Simulator,id=$SIMULATOR_UDID"
elif [[ -n "$SIMULATOR_NAME" ]]; then
  DESTINATION="platform=iOS Simulator,name=$SIMULATOR_NAME"
else
  echo "IOS_SIMULATOR_UDID or IOS_SIMULATOR_NAME must be set for iOS simulator tests." >&2
  exit 1
fi

open -a Simulator >/dev/null 2>&1 || true
if [[ -n "$SIMULATOR_UDID" ]]; then
  xcrun simctl shutdown "$SIMULATOR_UDID" >/dev/null 2>&1 || true
  xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$SIMULATOR_UDID" -b
  xcrun simctl terminate "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$SIMULATOR_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

xcodebuild \
  -project "$ROOT_DIR/iosApp/DebridHubHost.xcodeproj" \
  -scheme DebridHubHost \
  -configuration Debug \
  -destination "$DESTINATION" \
  -destination-timeout "$IOS_TEST_DESTINATION_TIMEOUT" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  test
