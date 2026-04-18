#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY_PROFILE="${VERIFY_PROFILE:-ci-pr}"
DEVICE_POOL_FILE="$ROOT_DIR/ci/device-pool.yml"
TMP_DIR="$(mktemp -d)"
PROFILE_ANDROID_FILE="$TMP_DIR/profile-android.tsv"
PROFILE_IOS_FILE="$TMP_DIR/profile-ios.tsv"

ANDROID_FAILURES=0
IOS_FAILURES=0

trap 'rm -rf "$TMP_DIR"' EXIT

if ! command -v ruby >/dev/null 2>&1; then
  echo "ruby is required to parse device pool" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to inspect iOS simulator JSON" >&2
  exit 1
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if [[ ! -f "$DEVICE_POOL_FILE" ]]; then
  echo "Device pool file not found: $DEVICE_POOL_FILE" >&2
  exit 1
fi

resolve_device_pool() {
  ruby - "$DEVICE_POOL_FILE" "$VERIFY_PROFILE" "$PROFILE_ANDROID_FILE" "$PROFILE_IOS_FILE" <<'RUBY'
require "yaml"

device_pool_file, verify_profile, profile_android_file, profile_ios_file = ARGV

data = YAML.load_file(device_pool_file) || {}
profiles = data.fetch("profiles", {})

def normalize_entries(entries)
  normalized_entries = []

  Array(entries).each do |entry|
    next unless entry.is_a?(Hash)

    normalized = {}
    entry.each { |key, value| normalized[key.to_s] = value }
    normalized_entries << normalized
  end

  normalized_entries
end

def merge_entries(base_entries, override_entries)
  merged = base_entries.map(&:dup)
  label_index = {}

  merged.each_with_index do |entry, idx|
    label = entry["label"]&.to_s
    next if label.nil? || label.empty?

    label_index[label] = idx
  end

  normalize_entries(override_entries).each do |entry|
    label = entry["label"]&.to_s
    if label && !label.empty? && label_index.key?(label)
      merged[label_index[label]] = entry
    else
      merged << entry
      label_index[label] = merged.length - 1 if label && !label.empty?
    end
  end

  merged
end

def resolve_profile(name, profiles, stack = [])
  raise "profile_not_found:#{name}" unless profiles.key?(name)
  raise "profile_cycle:#{(stack + [name]).join("->")}" if stack.include?(name)

  profile = profiles[name] || {}
  resolved = {
    "android" => [],
    "ios" => []
  }

  Array(profile["includes"]).each do |included_name|
    included = resolve_profile(included_name, profiles, stack + [name])
    resolved["android"] = merge_entries(resolved["android"], included["android"])
    resolved["ios"] = merge_entries(resolved["ios"], included["ios"])
  end

  resolved["android"] = merge_entries(resolved["android"], profile["android"])
  resolved["ios"] = merge_entries(resolved["ios"], profile["ios"])

  resolved
end

resolved = resolve_profile(verify_profile, profiles)

File.open(profile_android_file, "w") do |file|
  resolved["android"].each do |entry|
    label = entry["label"].to_s
    avd = entry["avd"].to_s
    next if avd.empty?

    fallbacks = Array(entry["fallbacks"]).map(&:to_s).join("|")
    api = entry["api"].to_s
    abi = entry["abi"].to_s
    system_image = entry["system_image"].to_s
    device_profile = entry["device_profile"].to_s

    file.puts([label, avd, fallbacks, api, abi, system_image, device_profile].join("\t"))
  end
end

File.open(profile_ios_file, "w") do |file|
  resolved["ios"].each do |entry|
    label = entry["label"].to_s
    simulator = entry["simulator"].to_s
    next if simulator.empty?

    fallbacks = Array(entry["fallbacks"]).map(&:to_s).join("|")
    runtime = entry["runtime"].to_s
    device_type = entry["device_type"].to_s

    file.puts([label, simulator, fallbacks, runtime, device_type].join("\t"))
  end
end
RUBY
}

find_android_sdk_root() {
  if [[ -n "${ANDROID_SDK_ROOT:-}" && -d "$ANDROID_SDK_ROOT" ]]; then
    printf '%s\n' "$ANDROID_SDK_ROOT"
    return 0
  fi

  if [[ -n "${ANDROID_HOME:-}" && -d "$ANDROID_HOME" ]]; then
    printf '%s\n' "$ANDROID_HOME"
    return 0
  fi

  if [[ -d "$HOME/Library/Android/sdk" ]]; then
    printf '%s\n' "$HOME/Library/Android/sdk"
    return 0
  fi

  return 1
}

find_android_tool() {
  local sdk_root="$1"
  local tool_name="$2"
  local candidate

  for candidate in \
    "$sdk_root/cmdline-tools/latest/bin/$tool_name" \
    "$sdk_root/cmdline-tools/bin/$tool_name" \
    "$sdk_root/tools/bin/$tool_name"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

android_avd_exists() {
  local avd_name="$1"
  "$EMULATOR_BIN" -list-avds | awk -v target="$avd_name" '$0 == target { found = 1 } END { exit found ? 0 : 1 }'
}

provision_android_targets() {
  local row
  local label
  local avd_name
  local fallback_list
  local api
  local abi
  local system_image
  local device_profile

  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    label="$(printf '%s' "$row" | awk -F '\t' '{print $1}')"
    avd_name="$(printf '%s' "$row" | awk -F '\t' '{print $2}')"
    fallback_list="$(printf '%s' "$row" | awk -F '\t' '{print $3}')"
    api="$(printf '%s' "$row" | awk -F '\t' '{print $4}')"
    abi="$(printf '%s' "$row" | awk -F '\t' '{print $5}')"
    system_image="$(printf '%s' "$row" | awk -F '\t' '{print $6}')"
    device_profile="$(printf '%s' "$row" | awk -F '\t' '{print $7}')"
    [[ -z "$avd_name" ]] && continue

    if android_avd_exists "$avd_name"; then
      echo "[android][$label] exists: $avd_name"
      continue
    fi

    if [[ -z "$system_image" ]]; then
      echo "[android][$label] missing system_image for $avd_name" >&2
      ANDROID_FAILURES=$((ANDROID_FAILURES + 1))
      continue
    fi

    if [[ -z "$abi" ]]; then
      abi="x86_64"
    fi

    if [[ -z "$device_profile" ]]; then
      device_profile="pixel"
    fi

    echo "[android][$label] installing image: $system_image"
    set +o pipefail
    if ! yes | "$SDKMANAGER_BIN" --install "$system_image" >/dev/null; then
      set -o pipefail
      echo "[android][$label] failed to install image: $system_image" >&2
      ANDROID_FAILURES=$((ANDROID_FAILURES + 1))
      continue
    fi
    set -o pipefail

    echo "[android][$label] creating avd: $avd_name"
    printf 'no\n' | "$AVDMANAGER_BIN" create avd -n "$avd_name" -k "$system_image" --abi "$abi" -d "$device_profile" --force >/dev/null

    if android_avd_exists "$avd_name"; then
      echo "[android][$label] provisioned: $avd_name"
    else
      echo "[android][$label] failed to provision: $avd_name" >&2
      ANDROID_FAILURES=$((ANDROID_FAILURES + 1))
    fi
  done < "$PROFILE_ANDROID_FILE"
}

ios_simulator_exists() {
  local simulator_name="$1"
  local runtime_id="$2"
  local devices_json

  devices_json="$(DEVELOPER_DIR="$DEVELOPER_DIR" xcrun simctl list devices available -j 2>/dev/null || true)"
  if [[ -z "$devices_json" ]]; then
    return 1
  fi

  python3 - "$simulator_name" "$runtime_id" "$devices_json" <<'PY'
import json
import sys

target_name = sys.argv[1]
runtime = sys.argv[2]
devices_json = sys.argv[3]

data = json.loads(devices_json)
devices = data.get("devices", {})

for runtime_key, entries in devices.items():
    if runtime and runtime_key != runtime:
        continue
    for entry in entries:
        if entry.get("name") == target_name and entry.get("isAvailable", False):
            raise SystemExit(0)

raise SystemExit(1)
PY
}

select_existing_ios_simulator() {
  local primary="$1"
  local fallback_list="$2"
  local runtime_id="$3"
  local candidates
  local candidate

  candidates="$primary"
  if [[ -n "$fallback_list" ]]; then
    if [[ -n "$candidates" ]]; then
      candidates="$candidates|$fallback_list"
    else
      candidates="$fallback_list"
    fi
  fi

  IFS='|' read -r -a candidate_array <<< "$candidates"
  for candidate in "${candidate_array[@]}"; do
    candidate="$(printf '%s' "$candidate" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [[ -z "$candidate" ]] && continue

    if ios_simulator_exists "$candidate" "$runtime_id"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

provision_ios_targets() {
  local row
  local label
  local simulator_name
  local fallback_list
  local runtime
  local device_type
  local existing_simulator

  if ! command -v xcrun >/dev/null 2>&1; then
    echo "xcrun not found; skipping iOS provisioning" >&2
    IOS_FAILURES=$((IOS_FAILURES + 1))
    return
  fi

  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    label="$(printf '%s' "$row" | awk -F '\t' '{print $1}')"
    simulator_name="$(printf '%s' "$row" | awk -F '\t' '{print $2}')"
    fallback_list="$(printf '%s' "$row" | awk -F '\t' '{print $3}')"
    runtime="$(printf '%s' "$row" | awk -F '\t' '{print $4}')"
    device_type="$(printf '%s' "$row" | awk -F '\t' '{print $5}')"
    [[ -z "$simulator_name" ]] && continue

    existing_simulator=""
    if existing_simulator="$(select_existing_ios_simulator "$simulator_name" "$fallback_list" "$runtime")"; then
      echo "[ios][$label] exists: $existing_simulator"
      continue
    fi

    if [[ -z "$runtime" || -z "$device_type" ]]; then
      echo "[ios][$label] missing runtime/device_type for $simulator_name" >&2
      IOS_FAILURES=$((IOS_FAILURES + 1))
      continue
    fi

    echo "[ios][$label] creating simulator: $simulator_name"
    if ! DEVELOPER_DIR="$DEVELOPER_DIR" xcrun simctl create "$simulator_name" "$device_type" "$runtime" >/dev/null; then
      echo "[ios][$label] failed to create simulator: $simulator_name" >&2
      IOS_FAILURES=$((IOS_FAILURES + 1))
      continue
    fi

    if ios_simulator_exists "$simulator_name" "$runtime"; then
      echo "[ios][$label] provisioned: $simulator_name"
    else
      echo "[ios][$label] create command returned but simulator missing: $simulator_name" >&2
      IOS_FAILURES=$((IOS_FAILURES + 1))
    fi
  done < "$PROFILE_IOS_FILE"
}

resolve_device_pool

ANDROID_TARGET_COUNT="$(awk 'NF { count += 1 } END { print count + 0 }' "$PROFILE_ANDROID_FILE")"
IOS_TARGET_COUNT="$(awk 'NF { count += 1 } END { print count + 0 }' "$PROFILE_IOS_FILE")"

if [[ "$ANDROID_TARGET_COUNT" -eq 0 && "$IOS_TARGET_COUNT" -eq 0 ]]; then
  echo "Profile '$VERIFY_PROFILE' has no Android or iOS targets" >&2
  exit 1
fi

if [[ "$ANDROID_TARGET_COUNT" -eq 0 ]]; then
  echo "Profile '$VERIFY_PROFILE' has no Android targets" >&2
  exit 1
fi

if [[ "$IOS_TARGET_COUNT" -eq 0 ]]; then
  echo "Profile '$VERIFY_PROFILE' has no iOS targets" >&2
  exit 1
fi

if [[ -s "$PROFILE_ANDROID_FILE" ]]; then
  ANDROID_SDK_ROOT="$(find_android_sdk_root || true)"
  if [[ -z "$ANDROID_SDK_ROOT" ]]; then
    echo "Android SDK root not found; cannot provision Android pool" >&2
    ANDROID_FAILURES=$((ANDROID_FAILURES + 1))
  else
    export ANDROID_SDK_ROOT
    SDKMANAGER_BIN="$(find_android_tool "$ANDROID_SDK_ROOT" sdkmanager || true)"
    AVDMANAGER_BIN="$(find_android_tool "$ANDROID_SDK_ROOT" avdmanager || true)"
    EMULATOR_BIN="$ANDROID_SDK_ROOT/emulator/emulator"

    if [[ -z "$SDKMANAGER_BIN" || -z "$AVDMANAGER_BIN" || ! -x "$EMULATOR_BIN" ]]; then
      echo "Android cmdline-tools/emulator binaries are missing under $ANDROID_SDK_ROOT" >&2
      ANDROID_FAILURES=$((ANDROID_FAILURES + 1))
    else
      provision_android_targets
    fi
  fi
fi

if [[ -s "$PROFILE_IOS_FILE" ]]; then
  provision_ios_targets
fi

if [[ "$ANDROID_FAILURES" -ne 0 || "$IOS_FAILURES" -ne 0 ]]; then
  echo "Provisioning completed with failures (android=$ANDROID_FAILURES, ios=$IOS_FAILURES)" >&2
  exit 1
fi

echo "Provisioning completed successfully for profile: $VERIFY_PROFILE"
