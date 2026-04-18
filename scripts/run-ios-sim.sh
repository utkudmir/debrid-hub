#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/ios-derived-data}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/DebridHub.app"
BUNDLE_ID="com.utku.debridhub.ios"
SIMULATOR_NAME="${IOS_SIMULATOR_NAME:-iPhone 17 Pro Max}"

find_simulator_udid() {
  xcrun simctl list devices available | awk -v target="$SIMULATOR_NAME" '
    $0 ~ target {
      if (match($0, /\(([0-9A-F-]+)\)/)) {
        value = substr($0, RSTART + 1, RLENGTH - 2)
        print value
        exit
      }
    }
  '
}

SIMULATOR_UDID="$(find_simulator_udid)"

if [[ -z "$SIMULATOR_UDID" ]]; then
  echo "Simulator \"$SIMULATOR_NAME\" was not found. Set IOS_SIMULATOR_NAME to an available device." >&2
  exit 1
fi

open -a Simulator
xcrun simctl boot "$SIMULATOR_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIMULATOR_UDID" -b

IOS_SIMULATOR_NAME="$SIMULATOR_NAME" IOS_SIMULATOR_UDID="$SIMULATOR_UDID" "$ROOT_DIR/scripts/build-ios-sim.sh"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH" >&2
  exit 1
fi

xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"
xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID"
