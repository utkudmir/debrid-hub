#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY_PROFILE="${VERIFY_PROFILE:-ci-pr}"
PROVISION_TARGETS="${PROVISION_TARGETS:-all}"
DEVICE_POOL_FILE="$ROOT_DIR/ci/device-pool.yml"
IOS_RESOLVER_SCRIPT="$ROOT_DIR/scripts/resolve-ios-simulator.py"
TMP_DIR="$(mktemp -d)"
PROFILE_ANDROID_FILE="$TMP_DIR/profile-android.tsv"
PROFILE_IOS_FILE="$TMP_DIR/profile-ios.tsv"

ANDROID_FAILURES=0
IOS_FAILURES=0
WANT_ANDROID=0
WANT_IOS=0

case "$PROVISION_TARGETS" in
  all)
    WANT_ANDROID=1
    WANT_IOS=1
    ;;
  android)
    WANT_ANDROID=1
    ;;
  ios)
    WANT_IOS=1
    ;;
  *)
    echo "Unsupported PROVISION_TARGETS '$PROVISION_TARGETS'. Expected one of: all, android, ios" >&2
    exit 1
    ;;
esac

trap 'rm -rf "$TMP_DIR"' EXIT

if ! command -v ruby >/dev/null 2>&1; then
  echo "ruby is required to parse device pool" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required to inspect iOS simulator JSON" >&2
  exit 1
fi

if [[ ! -x "$IOS_RESOLVER_SCRIPT" ]]; then
  echo "resolve-ios-simulator script is required: $IOS_RESOLVER_SCRIPT" >&2
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
    device_class = entry["class"].to_s
    simulator = device_class if simulator.empty?
    next if label.empty? && simulator.empty?

    fallbacks = Array(entry["fallbacks"]).map(&:to_s).join("|")
    runtime = entry["runtime"].to_s
    device_type = entry["device_type"].to_s

    file.puts([label, simulator, fallbacks, runtime, device_type, device_class].join("\t"))
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

android_avd_exists_via_avdmanager() {
  local avd_name="$1"
  "$AVDMANAGER_BIN" list avd | awk -v target="$avd_name" '
    /^[[:space:]]*Name:/ {
      value = $0
      sub(/^[[:space:]]*Name:[[:space:]]*/, "", value)
      if (value == target) {
        found = 1
      }
    }
    END { exit found ? 0 : 1 }
  '
}

android_avd_exists_on_disk() {
  local avd_name="$1"
  local avd_home
  local -a candidate_homes=()

  if [[ -n "${ANDROID_AVD_HOME:-}" ]]; then
    candidate_homes+=("$ANDROID_AVD_HOME")
  fi
  candidate_homes+=("$HOME/.android/avd" "$HOME/.config/.android/avd")

  for avd_home in "${candidate_homes[@]}"; do
    if [[ -f "$avd_home/$avd_name.ini" || -d "$avd_home/$avd_name.avd" ]]; then
      return 0
    fi
  done

  return 1
}

android_host_arch() {
  local arch
  arch="$(uname -m 2>/dev/null || printf 'unknown')"
  case "$arch" in
    arm64|aarch64)
      printf 'arm64-v8a\n'
      ;;
    x86_64|amd64)
      printf 'x86_64\n'
      ;;
    *)
      printf 'x86_64\n'
      ;;
  esac
}

android_target_abi_for_host() {
  local requested_abi="${1:-}"
  local preferred_abi
  preferred_abi="$(android_host_arch)"

  case "$requested_abi" in
    arm64-v8a|x86_64)
      printf '%s\n' "$preferred_abi"
      ;;
    '')
      printf '%s\n' "$preferred_abi"
      ;;
    *)
      printf '%s\n' "$requested_abi"
      ;;
  esac
}

android_system_image_for_abi() {
  local system_image="${1:-}"
  local target_abi="${2:-}"

  if [[ -z "$system_image" || -z "$target_abi" ]]; then
    printf '%s\n' "$system_image"
    return
  fi

  printf '%s\n' "$system_image" | sed -E "s/(^|;)(x86_64|arm64-v8a)$/\\1${target_abi}/"
}

android_effective_avd_name() {
  local avd_name="${1:-}"
  local requested_abi="${2:-}"
  local target_abi="${3:-}"

  if [[ -z "$avd_name" || -z "$target_abi" || "$requested_abi" == "$target_abi" ]]; then
    printf '%s\n' "$avd_name"
    return
  fi

  printf '%s-%s\n' "$avd_name" "$target_abi"
}

android_device_profile_exists() {
  local avdmanager_bin="$1"
  local target_profile="$2"

  [[ -n "$target_profile" ]] || return 1

  "$avdmanager_bin" list device | awk -v target="$target_profile" '
    / or "/ {
      value = $0
      sub(/^.* or "/, "", value)
      sub(/".*$/, "", value)
      if (value == target) {
        found = 1
      }
    }
    END { exit found ? 0 : 1 }
  '
}

android_first_device_profile() {
  local avdmanager_bin="$1"

  "$avdmanager_bin" list device | awk '
    / or "/ {
      value = $0
      sub(/^.* or "/, "", value)
      sub(/".*$/, "", value)
      print value
      exit
    }
  '
}

android_resolve_device_profile() {
  local avdmanager_bin="$1"
  local requested_profile="${2:-}"
  local fallback_profile="pixel"
  local first_profile

  if [[ -n "$requested_profile" ]] && android_device_profile_exists "$avdmanager_bin" "$requested_profile"; then
    printf '%s\n' "$requested_profile"
    return 0
  fi

  if android_device_profile_exists "$avdmanager_bin" "$fallback_profile"; then
    printf '%s\n' "$fallback_profile"
    return 0
  fi

  first_profile="$(android_first_device_profile "$avdmanager_bin")"
  if [[ -n "$first_profile" ]]; then
    printf '%s\n' "$first_profile"
    return 0
  fi

  return 1
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
  local target_abi
  local target_system_image
  local effective_avd_name
  local resolved_device_profile
  local avd_home

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

    if [[ -z "$system_image" ]]; then
      echo "[android][$label] missing system_image for $avd_name" >&2
      ANDROID_FAILURES=$((ANDROID_FAILURES + 1))
      continue
    fi

    target_abi="$(android_target_abi_for_host "$abi")"
    target_system_image="$(android_system_image_for_abi "$system_image" "$target_abi")"
    effective_avd_name="$(android_effective_avd_name "$avd_name" "$abi" "$target_abi")"
    [[ -z "$effective_avd_name" ]] && effective_avd_name="$avd_name"

    resolved_device_profile="$(android_resolve_device_profile "$AVDMANAGER_BIN" "$device_profile" || true)"
    if [[ -z "$resolved_device_profile" ]]; then
      echo "[android][$label] unable to resolve device profile (requested=${device_profile:-<empty>})" >&2
      ANDROID_FAILURES=$((ANDROID_FAILURES + 1))
      continue
    fi
    if [[ -n "$device_profile" && "$resolved_device_profile" != "$device_profile" ]]; then
      echo "[android][$label] device profile '$device_profile' unavailable; using '$resolved_device_profile'"
    fi

    if android_avd_exists "$effective_avd_name" || android_avd_exists_via_avdmanager "$effective_avd_name" || android_avd_exists_on_disk "$effective_avd_name"; then
      echo "[android][$label] exists: $effective_avd_name"
      continue
    fi

    echo "[android][$label] installing image: $target_system_image"
    set +o pipefail
    if ! yes | "$SDKMANAGER_BIN" --install "$target_system_image" >/dev/null; then
      set -o pipefail
      echo "[android][$label] failed to install image: $target_system_image" >&2
      ANDROID_FAILURES=$((ANDROID_FAILURES + 1))
      continue
    fi
    set -o pipefail

    echo "[android][$label] creating avd: $effective_avd_name"
    if ! printf 'no\n' | "$AVDMANAGER_BIN" create avd -n "$effective_avd_name" -k "$target_system_image" --abi "$target_abi" -d "$resolved_device_profile" --force; then
      echo "[android][$label] avdmanager create failed with profile '$resolved_device_profile'; retrying without explicit device profile" >&2
      if ! printf 'no\n' | "$AVDMANAGER_BIN" create avd -n "$effective_avd_name" -k "$target_system_image" --abi "$target_abi" --force; then
        echo "[android][$label] avdmanager create failed for $effective_avd_name (image=$target_system_image abi=$target_abi)" >&2
        "$AVDMANAGER_BIN" list avd >&2 || true
        ANDROID_FAILURES=$((ANDROID_FAILURES + 1))
        continue
      fi
    fi

    if android_avd_exists "$effective_avd_name" || android_avd_exists_via_avdmanager "$effective_avd_name" || android_avd_exists_on_disk "$effective_avd_name"; then
      echo "[android][$label] provisioned: $effective_avd_name"
    else
      echo "[android][$label] failed to provision: $effective_avd_name" >&2
      "$AVDMANAGER_BIN" list avd >&2 || true
      for avd_home in "${ANDROID_AVD_HOME:-}" "$HOME/.android/avd" "$HOME/.config/.android/avd"; do
        [[ -z "$avd_home" ]] && continue
        if [[ -d "$avd_home" ]]; then
          echo "[android][$label] listing AVD home: $avd_home" >&2
          ls -la "$avd_home" >&2 || true
        fi
      done
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

ios_device_class_from_label() {
  local label="${1:-}"
  local class_hint="${2:-}"
  local normalized

  normalized="$(printf '%s' "$class_hint" | tr '[:upper:]' '[:lower:]')"
  case "$normalized" in
    latest-phone|small-phone|large-phone)
      printf '%s\n' "$normalized"
      return
      ;;
  esac

  normalized="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')"
  if [[ "$normalized" == *"small"* ]]; then
    printf 'small-phone\n'
    return
  fi
  if [[ "$normalized" == *"large"* ]]; then
    printf 'large-phone\n'
    return
  fi
  printf 'latest-phone\n'
}

resolve_ios_target() {
  local label="$1"
  local primary="$2"
  local fallback_list="$3"
  local runtime="$4"
  local device_type="$5"
  local class_hint="$6"
  local device_class
  local resolver_output

  device_class="$(ios_device_class_from_label "$label" "$class_hint")"
  if ! resolver_output="$(python3 "$IOS_RESOLVER_SCRIPT" --label "$label" --name "$primary" --fallbacks "$fallback_list" --runtime "$runtime" --device-type "$device_type" --device-class "$device_class" 2>/dev/null)"; then
    return 1
  fi

  IOS_RESOLVED_NAME="$(printf '%s' "$resolver_output" | awk -F '\t' '{print $1}')"
  IOS_RESOLVED_UDID="$(printf '%s' "$resolver_output" | awk -F '\t' '{print $2}')"
  IOS_RESOLVED_RUNTIME="$(printf '%s' "$resolver_output" | awk -F '\t' '{print $3}')"
  IOS_RESOLVED_DEVICE_TYPE="$(printf '%s' "$resolver_output" | awk -F '\t' '{print $4}')"
  IOS_RESOLVED_CLASS="$(printf '%s' "$resolver_output" | awk -F '\t' '{print $6}')"

  [[ -n "$IOS_RESOLVED_NAME" && -n "$IOS_RESOLVED_UDID" ]]
}

provision_ios_targets() {
  local row
  local label
  local simulator_name
  local fallback_list
  local runtime
  local device_type
  local class_hint

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
    class_hint="$(printf '%s' "$row" | awk -F '\t' '{print $6}')"

    if ! resolve_ios_target "$label" "$simulator_name" "$fallback_list" "$runtime" "$device_type" "$class_hint"; then
      echo "[ios][$label] failed to resolve simulator dynamically" >&2
      IOS_FAILURES=$((IOS_FAILURES + 1))
      continue
    fi

    if ios_simulator_exists "$IOS_RESOLVED_NAME" "$IOS_RESOLVED_RUNTIME"; then
      echo "[ios][$label] resolved: $IOS_RESOLVED_NAME ($IOS_RESOLVED_CLASS)"
    else
      echo "[ios][$label] resolved simulator missing after creation: $IOS_RESOLVED_NAME" >&2
      IOS_FAILURES=$((IOS_FAILURES + 1))
    fi
  done < "$PROFILE_IOS_FILE"
}

resolve_device_pool

ANDROID_TARGET_COUNT="$(awk 'NF { count += 1 } END { print count + 0 }' "$PROFILE_ANDROID_FILE")"
IOS_TARGET_COUNT="$(awk 'NF { count += 1 } END { print count + 0 }' "$PROFILE_IOS_FILE")"

if [[ "$WANT_ANDROID" -eq 1 && "$ANDROID_TARGET_COUNT" -eq 0 ]]; then
  echo "Profile '$VERIFY_PROFILE' has no Android targets" >&2
  exit 1
fi

if [[ "$WANT_IOS" -eq 1 && "$IOS_TARGET_COUNT" -eq 0 ]]; then
  echo "Profile '$VERIFY_PROFILE' has no iOS targets" >&2
  exit 1
fi

if [[ "$WANT_ANDROID" -eq 1 && -s "$PROFILE_ANDROID_FILE" ]]; then
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

if [[ "$WANT_IOS" -eq 1 && -s "$PROFILE_IOS_FILE" ]]; then
  provision_ios_targets
fi

if [[ "$ANDROID_FAILURES" -ne 0 || "$IOS_FAILURES" -ne 0 ]]; then
  echo "Provisioning completed with failures (android=$ANDROID_FAILURES, ios=$IOS_FAILURES)" >&2
  exit 1
fi

echo "Provisioning completed successfully for profile: $VERIFY_PROFILE (targets=$PROVISION_TARGETS)"
