#!/usr/bin/env bash
set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNS_ROOT="$ROOT_DIR/build/rc-verify"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$RUNS_ROOT/$RUN_ID"
LOG_DIR="$RUN_DIR/logs"
EVIDENCE_DIR="$RUN_DIR/evidence"
RESULTS_TSV="$RUN_DIR/results.tsv"
RESULT_JSON="$RUN_DIR/result.json"
SUMMARY_FILE="$RUN_DIR/summary.txt"
VERIFY_PROFILE="${VERIFY_PROFILE:-local-fast}"
DEVICE_POOL_FILE="$ROOT_DIR/ci/device-pool.yml"
PROFILE_META_FILE="$RUN_DIR/profile-meta.env"
PROFILE_ANDROID_FILE="$RUN_DIR/profile-android.tsv"
PROFILE_IOS_FILE="$RUN_DIR/profile-ios.tsv"
DEVICE_ROOT_DIR="$RUN_DIR/devices"
DEVICE_INDEX_FILE="$RUN_DIR/device-index.tsv"
STEP_LOG_DIR=""

MAX_ENV_RETRIES=2
ENV_RETRY_WAIT_SECONDS=60
KEEP_RUN_COUNT=5

ANDROID_PACKAGE="com.utku.debridhub"
IOS_BUNDLE_ID="com.utku.debridhub.ios"
ALLOWED_SIGNOFF_REVIEWER="utkudemir"

OVERALL_FAIL=0
ANDROID_DEVICE_ID=""
ANDROID_AVD_NAME_EFFECTIVE=""
ANDROID_LABEL_EFFECTIVE=""
IOS_SIMULATOR_UDID=""
IOS_SIMULATOR_NAME_EFFECTIVE="${IOS_SIMULATOR_NAME:-iPhone 17 Pro Max}"
IOS_LABEL_EFFECTIVE=""
LAST_ERROR=""

mkdir -p "$LOG_DIR" "$EVIDENCE_DIR"
: > "$RESULTS_TSV"
: > "$DEVICE_INDEX_FILE"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for verify-rc" >&2
  exit 1
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

sanitize_field() {
  printf '%s' "$1" | tr '\t\r\n' '   '
}

slugify() {
  local value="$1"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//')"
  if [[ -z "$value" ]]; then
    value="default"
  fi
  printf '%s' "$value"
}

current_log_dir() {
  if [[ -n "$STEP_LOG_DIR" ]]; then
    printf '%s' "$STEP_LOG_DIR"
  else
    printf '%s' "$LOG_DIR"
  fi
}

record_device_index() {
  local platform
  local slug
  local label
  local target
  local runtime_id
  local log_dir

  platform="$(sanitize_field "$1")"
  slug="$(sanitize_field "$2")"
  label="$(sanitize_field "$3")"
  target="$(sanitize_field "$4")"
  runtime_id="$(sanitize_field "$5")"
  log_dir="$(sanitize_field "$6")"

  if [[ -z "$runtime_id" ]]; then
    runtime_id="-"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$platform" "$slug" "$label" "$target" "$runtime_id" "$log_dir" >> "$DEVICE_INDEX_FILE"
}

redact_file() {
  local file_path="$1"
  python3 - "$file_path" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8", errors="replace")

patterns = [
    (re.compile(r'(?i)(Authorization\s*:\s*Bearer\s+)[^\s"\']+'), r'\1***REDACTED***'),
    (re.compile(r'(?i)(\bBearer\s+)[A-Za-z0-9._\-~+/]+=*'), r'\1***REDACTED***'),
    (re.compile(r'(?i)([?&](?:code|token|secret|client_secret|refresh_token|access_token|device_code|user_code)=)[^&\s]+'), r'\1***REDACTED***'),
    (re.compile(r'(?i)("?(?:access_token|refresh_token|client_secret|device_code|user_code)"?\s*[:=]\s*"?)[^",\s]+("?)'), r'\1***REDACTED***\2'),
    (re.compile(r'(?i)(\b(?:access_token|refresh_token|client_secret|device_code|user_code)\b\s*[:=]\s*)[^,\s]+'), r'\1***REDACTED***'),
]

for regex, replacement in patterns:
    text = regex.sub(replacement, text)

path.write_text(text, encoding="utf-8")
PY
}

add_result() {
  local key
  local label
  local status
  local retries
  local log_path
  local reason

  key="$(sanitize_field "$1")"
  label="$(sanitize_field "$2")"
  status="$(sanitize_field "$3")"
  retries="$(sanitize_field "$4")"
  log_path="$(sanitize_field "$5")"
  reason="$(sanitize_field "$6")"

  if [[ -z "$log_path" ]]; then
    log_path="-"
  fi
  if [[ -z "$reason" ]]; then
    reason="-"
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$key" "$label" "$status" "$retries" "$log_path" "$reason" >> "$RESULTS_TSV"

  if [[ "$status" == "FAIL" ]]; then
    OVERALL_FAIL=1
  fi
}

complete_step() {
  local key="$1"
  local label="$2"
  local status="$3"
  local retries="$4"
  local log_path="$5"
  local reason="$6"

  if [[ ! -f "$log_path" ]]; then
    : > "$log_path"
  fi

  if ! redact_file "$log_path"; then
    status="FAIL"
    reason="redaction_failed"
  fi

  add_result "$key" "$label" "$status" "$retries" "$log_path" "$reason"
}

run_command_step() {
  local key="$1"
  local label="$2"
  local command="$3"
  local log_path
  local status="PASS"
  local reason=""

  mkdir -p "$(current_log_dir)"
  log_path="$(current_log_dir)/$key.log"

  {
    printf '$ %s\n\n' "$command"
    (
      cd "$ROOT_DIR"
      eval "$command"
    )
  } > "$log_path" 2>&1 || {
    status="FAIL"
    reason="command_failed"
  }

  complete_step "$key" "$label" "$status" "0" "$log_path" "$reason"
}

run_skip_step() {
  local key="$1"
  local label="$2"
  local reason="$3"
  local log_path

  mkdir -p "$(current_log_dir)"
  log_path="$(current_log_dir)/$key.log"

  printf 'Step skipped: %s\n' "$reason" > "$log_path"
  complete_step "$key" "$label" "SKIP" "0" "$log_path" "$reason"
}

run_warning_step() {
  local key="$1"
  local label="$2"
  local reason="$3"
  local log_path

  mkdir -p "$(current_log_dir)"
  log_path="$(current_log_dir)/$key.log"

  printf 'Step warning: %s\n' "$reason" > "$log_path"
  complete_step "$key" "$label" "WARN" "0" "$log_path" "$reason"
}

run_fail_step() {
  local key="$1"
  local label="$2"
  local reason="$3"
  local message="$4"
  local log_path

  mkdir -p "$(current_log_dir)"
  log_path="$(current_log_dir)/$key.log"

  printf '%s\n' "$message" > "$log_path"
  complete_step "$key" "$label" "FAIL" "0" "$log_path" "$reason"
}

get_step_status() {
  local key="$1"
  awk -F '\t' -v target="$key" '$1 == target { value = $3 } END { print value }' "$RESULTS_TSV"
}

load_device_pool_profile() {
  if [[ ! -f "$DEVICE_POOL_FILE" ]]; then
    LAST_ERROR="device_pool_missing"
    return 1
  fi

  if ! ruby - "$DEVICE_POOL_FILE" "$VERIFY_PROFILE" "$PROFILE_META_FILE" "$PROFILE_ANDROID_FILE" "$PROFILE_IOS_FILE" <<'RUBY'
require "yaml"

device_pool_file, verify_profile, profile_meta_file, profile_android_file, profile_ios_file = ARGV

data = YAML.load_file(device_pool_file) || {}
profiles = data.fetch("profiles", {})
defaults = data.fetch("defaults", {})

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

File.write(
  profile_meta_file,
  [
    "VERIFY_PROFILE=#{verify_profile}",
    "SIGNOFF_OWNER=#{defaults["signoff_owner"]}",
    "ANDROID_PACKAGE=#{defaults["android_package"]}",
    "IOS_BUNDLE_ID=#{defaults["ios_bundle_id"]}"
  ].join("\n") + "\n"
)

File.open(profile_android_file, "w") do |file|
  resolved["android"].each do |entry|
    label = entry["label"].to_s
    primary = entry["avd"].to_s
    next if primary.empty?

    fallbacks = Array(entry["fallbacks"]).map(&:to_s).join("|")
    api = entry["api"].to_s
    abi = entry["abi"].to_s
    system_image = entry["system_image"].to_s
    device_profile = entry["device_profile"].to_s

    file.puts([label, primary, fallbacks, api, abi, system_image, device_profile].join("\t"))
  end
end

File.open(profile_ios_file, "w") do |file|
  resolved["ios"].each do |entry|
    label = entry["label"].to_s
    primary = entry["simulator"].to_s
    next if primary.empty?

    fallbacks = Array(entry["fallbacks"]).map(&:to_s).join("|")
    runtime = entry["runtime"].to_s
    device_type = entry["device_type"].to_s

    file.puts([label, primary, fallbacks, runtime, device_type].join("\t"))
  end
end
RUBY
  then
    LAST_ERROR="profile_parse_failed"
    return 1
  fi
}

run_profile_load_step() {
  local key="profile_load"
  local label="Load device pool profile"
  local log_path="$LOG_DIR/$key.log"
  local status="PASS"
  local reason=""

  {
    echo "verify profile: $VERIFY_PROFILE"
    echo "device pool file: $DEVICE_POOL_FILE"
    if ! load_device_pool_profile; then
      status="FAIL"
      reason="${LAST_ERROR:-profile_load_failed}"
    fi
    if [[ -f "$PROFILE_META_FILE" ]]; then
      cat "$PROFILE_META_FILE"
    fi
    if [[ -f "$PROFILE_ANDROID_FILE" ]]; then
      echo "android targets:"
      cat "$PROFILE_ANDROID_FILE"
    fi
    if [[ -f "$PROFILE_IOS_FILE" ]]; then
      echo "ios targets:"
      cat "$PROFILE_IOS_FILE"
    fi
  } > "$log_path" 2>&1

  if [[ -f "$PROFILE_META_FILE" ]]; then
    while IFS='=' read -r key_name value; do
      case "$key_name" in
        SIGNOFF_OWNER)
          if [[ -n "$value" ]]; then
            ALLOWED_SIGNOFF_REVIEWER="$value"
          fi
          ;;
        ANDROID_PACKAGE)
          if [[ -n "$value" ]]; then
            ANDROID_PACKAGE="$value"
          fi
          ;;
        IOS_BUNDLE_ID)
          if [[ -n "$value" ]]; then
            IOS_BUNDLE_ID="$value"
          fi
          ;;
      esac
    done < "$PROFILE_META_FILE"
  fi

  complete_step "$key" "$label" "$status" "0" "$log_path" "$reason"
}

run_profile_target_guard_step() {
  local key="profile_target_guard"
  local label="Validate Android+iOS profile targets"
  local log_path="$LOG_DIR/$key.log"
  local status="PASS"
  local reason=""
  local android_target_count="0"
  local ios_target_count="0"

  if [[ -f "$PROFILE_ANDROID_FILE" ]]; then
    android_target_count="$(awk 'NF { count += 1 } END { print count + 0 }' "$PROFILE_ANDROID_FILE")"
  fi

  if [[ -f "$PROFILE_IOS_FILE" ]]; then
    ios_target_count="$(awk 'NF { count += 1 } END { print count + 0 }' "$PROFILE_IOS_FILE")"
  fi

  {
    echo "verify profile: $VERIFY_PROFILE"
    echo "android targets: $android_target_count"
    echo "ios targets: $ios_target_count"
  } > "$log_path"

  if [[ "$android_target_count" -eq 0 && "$ios_target_count" -eq 0 ]]; then
    status="FAIL"
    reason="profile_missing_android_ios_targets"
  elif [[ "$android_target_count" -eq 0 ]]; then
    status="FAIL"
    reason="profile_missing_android_targets"
  elif [[ "$ios_target_count" -eq 0 ]]; then
    status="FAIL"
    reason="profile_missing_ios_targets"
  fi

  complete_step "$key" "$label" "$status" "0" "$log_path" "$reason"
}

resolve_android_avd_from_profile() {
  local emulator_bin="$HOME/Library/Android/sdk/emulator/emulator"
  local available_avds
  local row
  local label
  local primary
  local fallback_list
  local candidates
  local candidate

  if [[ ! -s "$PROFILE_ANDROID_FILE" ]]; then
    LAST_ERROR="no_android_profile_targets"
    return 1
  fi

  if [[ ! -x "$emulator_bin" ]]; then
    LAST_ERROR="android_emulator_not_found"
    return 1
  fi

  available_avds="$($emulator_bin -list-avds)"

  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    label="$(printf '%s' "$row" | awk -F '\t' '{print $1}')"
    primary="$(printf '%s' "$row" | awk -F '\t' '{print $2}')"
    fallback_list="$(printf '%s' "$row" | awk -F '\t' '{print $3}')"
    [[ -z "$primary" ]] && continue
    candidates="$primary"
    if [[ -n "$fallback_list" ]]; then
      candidates="$candidates|$fallback_list"
    fi

    IFS='|' read -r -a candidate_array <<< "$candidates"
    for candidate in "${candidate_array[@]}"; do
      candidate="$(printf '%s' "$candidate" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
      [[ -z "$candidate" ]] && continue

      if printf '%s\n' "$available_avds" | awk -v target="$candidate" '$0 == target { found = 1 } END { exit found ? 0 : 1 }'; then
        ANDROID_AVD_NAME_EFFECTIVE="$candidate"
        ANDROID_LABEL_EFFECTIVE="${label:-default}"
        return 0
      fi
    done
  done < "$PROFILE_ANDROID_FILE"

  LAST_ERROR="no_android_avd_for_profile"
  return 1
}

resolve_ios_simulator_from_profile() {
  local row
  local label
  local primary
  local fallback_list
  local candidates
  local candidate
  local candidate_udid

  if [[ ! -s "$PROFILE_IOS_FILE" ]]; then
    LAST_ERROR="no_ios_profile_targets"
    return 1
  fi

  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    label="$(printf '%s' "$row" | awk -F '\t' '{print $1}')"
    primary="$(printf '%s' "$row" | awk -F '\t' '{print $2}')"
    fallback_list="$(printf '%s' "$row" | awk -F '\t' '{print $3}')"
    [[ -z "$primary" ]] && continue
    candidates="$primary"
    if [[ -n "$fallback_list" ]]; then
      candidates="$candidates|$fallback_list"
    fi

    IFS='|' read -r -a candidate_array <<< "$candidates"
    for candidate in "${candidate_array[@]}"; do
      candidate="$(printf '%s' "$candidate" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
      [[ -z "$candidate" ]] && continue

      candidate_udid="$(find_ios_simulator_udid_by_name "$candidate")"
      if [[ -n "$candidate_udid" ]]; then
        IOS_SIMULATOR_NAME_EFFECTIVE="$candidate"
        IOS_LABEL_EFFECTIVE="${label:-default}"
        return 0
      fi
    done
  done < "$PROFILE_IOS_FILE"

  LAST_ERROR="no_ios_simulator_for_profile"
  return 1
}

emit_android_target_rows() {
  if [[ -n "${ANDROID_AVD_NAME:-}" ]]; then
    printf 'env-override\t%s\t\n' "$ANDROID_AVD_NAME"
    return
  fi

  if [[ -s "$PROFILE_ANDROID_FILE" ]]; then
    cat "$PROFILE_ANDROID_FILE"
    return
  fi

  printf 'default\t\t\n'
}

emit_ios_target_rows() {
  if [[ -n "${IOS_SIMULATOR_NAME:-}" ]]; then
    printf 'env-override\t%s\t\n' "$IOS_SIMULATOR_NAME"
    return
  fi

  if [[ -s "$PROFILE_IOS_FILE" ]]; then
    cat "$PROFILE_IOS_FILE"
    return
  fi

  printf 'default\tiPhone 17 Pro Max\t\n'
}

select_android_candidate() {
  local primary="$1"
  local fallback_list="$2"
  local emulator_bin="$HOME/Library/Android/sdk/emulator/emulator"
  local available_avds
  local candidates
  local candidate

  if [[ ! -x "$emulator_bin" ]]; then
    LAST_ERROR="android_emulator_not_found"
    return 1
  fi

  available_avds="$($emulator_bin -list-avds)"
  candidates="$primary"
  if [[ -n "$fallback_list" ]]; then
    if [[ -n "$candidates" ]]; then
      candidates="$candidates|$fallback_list"
    else
      candidates="$fallback_list"
    fi
  fi

  if [[ -z "$candidates" ]]; then
    candidate="$(printf '%s\n' "$available_avds" | awk 'NF { print; exit }')"
    if [[ -n "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    LAST_ERROR="no_android_avd"
    return 1
  fi

  IFS='|' read -r -a candidate_array <<< "$candidates"
  for candidate in "${candidate_array[@]}"; do
    candidate="$(printf '%s' "$candidate" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [[ -z "$candidate" ]] && continue
    if printf '%s\n' "$available_avds" | awk -v target="$candidate" '$0 == target { found = 1 } END { exit found ? 0 : 1 }'; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  LAST_ERROR="no_android_avd_for_label"
  return 1
}

select_ios_candidate() {
  local primary="$1"
  local fallback_list="$2"
  local candidates
  local candidate
  local candidate_udid

  candidates="$primary"
  if [[ -n "$fallback_list" ]]; then
    if [[ -n "$candidates" ]]; then
      candidates="$candidates|$fallback_list"
    else
      candidates="$fallback_list"
    fi
  fi

  if [[ -z "$candidates" ]]; then
    candidates="iPhone 17 Pro Max"
  fi

  IFS='|' read -r -a candidate_array <<< "$candidates"
  for candidate in "${candidate_array[@]}"; do
    candidate="$(printf '%s' "$candidate" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [[ -z "$candidate" ]] && continue
    candidate_udid="$(find_ios_simulator_udid_by_name "$candidate")"
    if [[ -n "$candidate_udid" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  LAST_ERROR="no_ios_simulator_for_label"
  return 1
}

ensure_adb_on_path() {
  if command -v adb >/dev/null 2>&1; then
    return 0
  fi

  if [[ -x "$HOME/Library/Android/sdk/platform-tools/adb" ]]; then
    export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
    return 0
  fi

  LAST_ERROR="adb_not_found"
  return 1
}

find_booted_device_for_avd() {
  local target_avd="$1"
  local device_id
  local running_avd
  local boot_completed

  while read -r device_id; do
    [[ -z "$device_id" ]] && continue
    boot_completed="$(adb -s "$device_id" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    [[ "$boot_completed" != "1" ]] && continue

    if [[ -z "$target_avd" ]]; then
      printf '%s\n' "$device_id"
      return 0
    fi

    if [[ "$device_id" == emulator-* ]]; then
      running_avd="$(adb -s "$device_id" emu avd name 2>/dev/null | tr -d '\r' | awk 'NF { print; exit }')"
      if [[ "$running_avd" == "$target_avd" ]]; then
        printf '%s\n' "$device_id"
        return 0
      fi
    fi
  done < <(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')

  return 1
}

ensure_android_environment() {
  local requested_avd="${1:-}"
  local emulator_bin
  local avd_name
  local deadline
  local device_id
  local existing_device_id

  if ! ensure_adb_on_path; then
    return 1
  fi

  emulator_bin="$HOME/Library/Android/sdk/emulator/emulator"
  if [[ ! -x "$emulator_bin" ]]; then
    LAST_ERROR="android_emulator_not_found"
    return 1
  fi

  if [[ -n "$requested_avd" ]]; then
    avd_name="$requested_avd"
  elif [[ -n "${ANDROID_AVD_NAME:-}" ]]; then
    avd_name="$ANDROID_AVD_NAME"
  else
    if resolve_android_avd_from_profile; then
      avd_name="$ANDROID_AVD_NAME_EFFECTIVE"
    else
      if [[ -s "$PROFILE_ANDROID_FILE" ]]; then
        return 1
      fi
      avd_name="$($emulator_bin -list-avds | awk 'NF { print; exit }')"
      ANDROID_AVD_NAME_EFFECTIVE="$avd_name"
      ANDROID_LABEL_EFFECTIVE="default"
    fi
  fi

  if [[ -z "$avd_name" ]]; then
    LAST_ERROR="no_android_avd"
    return 1
  fi

  ANDROID_AVD_NAME_EFFECTIVE="$avd_name"

  existing_device_id="$(find_booted_device_for_avd "$avd_name" || true)"
  if [[ -n "$existing_device_id" ]]; then
    ANDROID_DEVICE_ID="$existing_device_id"
    return 0
  fi

  mkdir -p "$(current_log_dir)"
  "$emulator_bin" -avd "$avd_name" -no-snapshot-load > "$(current_log_dir)/android_emulator_boot.log" 2>&1 &
  sleep 5

  deadline=$((SECONDS + 300))
  while [[ $SECONDS -lt $deadline ]]; do
    device_id="$(find_booted_device_for_avd "$avd_name" || true)"
    if [[ -n "$device_id" ]]; then
      ANDROID_DEVICE_ID="$device_id"
      return 0
    fi
    sleep 2
  done

  LAST_ERROR="android_boot_timeout"
  return 1
}

find_ios_simulator_udid_by_name() {
  local target_name="$1"
  xcrun simctl list devices available | awk -v target="$target_name" '
    $0 ~ target {
      if (match($0, /\(([0-9A-F-]+)\)/)) {
        value = substr($0, RSTART + 1, RLENGTH - 2)
        print value
        exit
      }
    }
  '
}

ensure_ios_environment() {
  local requested_name="${1:-}"
  local fallback_line

  if ! command -v xcrun >/dev/null 2>&1; then
    LAST_ERROR="xcrun_not_found"
    return 1
  fi

  if [[ -n "$requested_name" ]]; then
    IOS_SIMULATOR_NAME_EFFECTIVE="$requested_name"
  elif [[ -n "${IOS_SIMULATOR_NAME:-}" ]]; then
    requested_name="$IOS_SIMULATOR_NAME"
    IOS_SIMULATOR_NAME_EFFECTIVE="$requested_name"
  else
    if resolve_ios_simulator_from_profile; then
      requested_name="$IOS_SIMULATOR_NAME_EFFECTIVE"
    else
      if [[ -s "$PROFILE_IOS_FILE" ]]; then
        return 1
      fi
      requested_name="iPhone 17 Pro Max"
      IOS_SIMULATOR_NAME_EFFECTIVE="$requested_name"
    fi
  fi

  IOS_SIMULATOR_UDID="$(find_ios_simulator_udid_by_name "$requested_name")"

  if [[ -z "$IOS_SIMULATOR_UDID" ]]; then
    fallback_line="$(xcrun simctl list devices available | awk '/iPhone/ && match($0, /\(([0-9A-F-]+)\)/) { print; exit }')"
    if [[ -z "$fallback_line" ]]; then
      LAST_ERROR="ios_simulator_not_found"
      return 1
    fi

    IOS_SIMULATOR_UDID="$(printf '%s\n' "$fallback_line" | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')"
    IOS_SIMULATOR_NAME_EFFECTIVE="$(printf '%s\n' "$fallback_line" | sed -E 's/^[[:space:]]*([^()]+) \([0-9A-F-]+\).*/\1/' | sed -E 's/[[:space:]]+$//')"
  fi

  open -a Simulator >/dev/null 2>&1 || true
  xcrun simctl boot "$IOS_SIMULATOR_UDID" >/dev/null 2>&1 || true
  if ! xcrun simctl bootstatus "$IOS_SIMULATOR_UDID" -b; then
    LAST_ERROR="ios_boot_timeout"
    return 1
  fi

  return 0
}

run_env_step_with_retry() {
  local key="$1"
  local label="$2"
  local function_name="$3"
  shift 3
  local log_path
  local attempt=0
  local status="FAIL"
  local reason=""
  local retries="$MAX_ENV_RETRIES"

  mkdir -p "$(current_log_dir)"
  log_path="$(current_log_dir)/$key.log"

  : > "$log_path"
  while [[ $attempt -le $MAX_ENV_RETRIES ]]; do
    {
      echo "Attempt $((attempt + 1))/$((MAX_ENV_RETRIES + 1))"
      LAST_ERROR=""
      "$function_name" "$@"
    } >> "$log_path" 2>&1 && {
      status="PASS"
      retries="$attempt"
      reason=""
      break
    }

    reason="${LAST_ERROR:-env_not_ready}"
    if [[ $attempt -lt $MAX_ENV_RETRIES ]]; then
      echo "Transient environment issue: $reason" >> "$log_path"
      echo "Sleeping ${ENV_RETRY_WAIT_SECONDS}s before retry" >> "$log_path"
      sleep "$ENV_RETRY_WAIT_SECONDS"
    fi
    attempt=$((attempt + 1))
  done

  complete_step "$key" "$label" "$status" "$retries" "$log_path" "$reason"
}

run_android_smoke_step() {
  local key="$1"
  local label="$2"
  local device_id="$3"
  local package_name="$4"
  local log_path
  local status="PASS"
  local reason=""
  local pid

  mkdir -p "$(current_log_dir)"
  log_path="$(current_log_dir)/$key.log"

  if [[ -z "$device_id" ]]; then
    printf 'Android device id is empty.\n' > "$log_path"
    status="FAIL"
    reason="android_device_missing"
  else
    {
      local attempt
      local launch_component
      launch_component="$(adb -s "$device_id" shell cmd package resolve-activity --brief "$package_name" 2>/dev/null | tr -d '\r' | awk 'NF { line = $0 } END { print line }')"
      if [[ -z "$launch_component" || "$launch_component" == *"No activity"* ]]; then
        echo "Could not resolve launcher activity for $package_name"
        false
      fi
      echo "Resolved launcher: $launch_component"
      adb -s "$device_id" shell am start -W -n "$launch_component"
      pid=""
      for attempt in {1..10}; do
        pid="$(adb -s "$device_id" shell pidof "$package_name" 2>/dev/null | tr -d '\r' | tr -d '\n')"
        if [[ -n "$pid" ]]; then
          break
        fi
        sleep 1
      done
      if [[ -z "$pid" ]]; then
        echo "Could not find running process for $package_name"
      else
        echo "Process id: $pid"
      fi
      [[ -n "$pid" ]]
    } > "$log_path" 2>&1 || {
      status="FAIL"
      reason="android_smoke_failed"
    }
  fi

  complete_step "$key" "$label" "$status" "0" "$log_path" "$reason"
}

run_ios_smoke_step() {
  local key="$1"
  local label="$2"
  local simulator_udid="$3"
  local bundle_id="$4"
  local log_path
  local status="PASS"
  local reason=""

  mkdir -p "$(current_log_dir)"
  log_path="$(current_log_dir)/$key.log"

  if [[ -z "$simulator_udid" ]]; then
    printf 'iOS simulator udid is empty.\n' > "$log_path"
    status="FAIL"
    reason="ios_simulator_missing"
  else
    {
      xcrun simctl get_app_container "$simulator_udid" "$bundle_id" app
      xcrun simctl launch "$simulator_udid" "$bundle_id"
    } > "$log_path" 2>&1 || {
      status="FAIL"
      reason="ios_smoke_failed"
    }
  fi

  complete_step "$key" "$label" "$status" "0" "$log_path" "$reason"
}

run_android_device_matrix() {
  local dependency_status
  local row
  local label
  local primary
  local fallback_list
  local slug
  local device_dir
  local key_prefix
  local selected_avd
  local env_status
  local install_status
  local device_runtime_id

  dependency_status="$(get_step_status "android_debug_build")"

  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    label="$(printf '%s' "$row" | awk -F '\t' '{print $1}')"
    primary="$(printf '%s' "$row" | awk -F '\t' '{print $2}')"
    fallback_list="$(printf '%s' "$row" | awk -F '\t' '{print $3}')"
    label="${label:-default}"
    slug="$(slugify "$label")"
    device_dir="$DEVICE_ROOT_DIR/android/$slug"
    key_prefix="android_${slug}"
    mkdir -p "$device_dir"
    STEP_LOG_DIR="$device_dir"

    selected_avd=""
    if selected_avd="$(select_android_candidate "$primary" "$fallback_list")"; then
      run_env_step_with_retry "${key_prefix}_env_ready" "Android [$label] environment readiness" "ensure_android_environment" "$selected_avd"
      env_status="$(get_step_status "${key_prefix}_env_ready")"
      device_runtime_id=""
      if [[ "$env_status" == "PASS" ]]; then
        device_runtime_id="$ANDROID_DEVICE_ID"
      fi
      record_device_index "android" "$slug" "$label" "$selected_avd" "$device_runtime_id" "$device_dir"
    else
      run_fail_step "${key_prefix}_env_ready" "Android [$label] environment readiness" "${LAST_ERROR:-android_target_unavailable}" "No available Android AVD for label '$label'."
      record_device_index "android" "$slug" "$label" "${primary:-<none>}" "" "$device_dir"
      run_skip_step "${key_prefix}_install" "Android [$label] install debug" "dependency_failed"
      run_skip_step "${key_prefix}_smoke" "Android [$label] launch smoke" "dependency_failed"
      STEP_LOG_DIR=""
      continue
    fi

    if [[ "$dependency_status" == "PASS" && "$(get_step_status "${key_prefix}_env_ready")" == "PASS" ]]; then
      run_command_step "${key_prefix}_install" "Android [$label] install debug" "./gradlew :androidApp:installDebug"
    else
      run_skip_step "${key_prefix}_install" "Android [$label] install debug" "dependency_failed"
    fi

    install_status="$(get_step_status "${key_prefix}_install")"
    if [[ "$install_status" == "PASS" ]]; then
      run_android_smoke_step "${key_prefix}_smoke" "Android [$label] launch smoke" "$ANDROID_DEVICE_ID" "$ANDROID_PACKAGE"
    else
      run_skip_step "${key_prefix}_smoke" "Android [$label] launch smoke" "dependency_failed"
    fi

    STEP_LOG_DIR=""
  done < <(emit_android_target_rows)
}

run_ios_device_matrix() {
  local row
  local label
  local primary
  local fallback_list
  local slug
  local device_dir
  local key_prefix
  local selected_simulator
  local env_status
  local run_status
  local simulator_udid

  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    label="$(printf '%s' "$row" | awk -F '\t' '{print $1}')"
    primary="$(printf '%s' "$row" | awk -F '\t' '{print $2}')"
    fallback_list="$(printf '%s' "$row" | awk -F '\t' '{print $3}')"
    label="${label:-default}"
    slug="$(slugify "$label")"
    device_dir="$DEVICE_ROOT_DIR/ios/$slug"
    key_prefix="ios_${slug}"
    mkdir -p "$device_dir"
    STEP_LOG_DIR="$device_dir"

    selected_simulator=""
    if selected_simulator="$(select_ios_candidate "$primary" "$fallback_list")"; then
      run_env_step_with_retry "${key_prefix}_env_ready" "iOS [$label] simulator readiness" "ensure_ios_environment" "$selected_simulator"
      env_status="$(get_step_status "${key_prefix}_env_ready")"
      simulator_udid=""
      if [[ "$env_status" == "PASS" ]]; then
        simulator_udid="$IOS_SIMULATOR_UDID"
      fi
      record_device_index "ios" "$slug" "$label" "$selected_simulator" "$simulator_udid" "$device_dir"
    else
      run_fail_step "${key_prefix}_env_ready" "iOS [$label] simulator readiness" "${LAST_ERROR:-ios_target_unavailable}" "No available iOS simulator for label '$label'."
      record_device_index "ios" "$slug" "$label" "${primary:-<none>}" "" "$device_dir"
      run_skip_step "${key_prefix}_build" "iOS [$label] simulator build" "dependency_failed"
      run_skip_step "${key_prefix}_run" "iOS [$label] simulator run" "dependency_failed"
      run_skip_step "${key_prefix}_smoke" "iOS [$label] launch smoke" "dependency_failed"
      STEP_LOG_DIR=""
      continue
    fi

    if [[ "$(get_step_status "${key_prefix}_env_ready")" == "PASS" ]]; then
      run_command_step "${key_prefix}_build" "iOS [$label] simulator build" "IOS_SIMULATOR_NAME=\"$IOS_SIMULATOR_NAME_EFFECTIVE\" IOS_SIMULATOR_UDID=\"$IOS_SIMULATOR_UDID\" make ios-build"
      run_command_step "${key_prefix}_run" "iOS [$label] simulator run" "IOS_SIMULATOR_NAME=\"$IOS_SIMULATOR_NAME_EFFECTIVE\" make ios-run"
    else
      run_skip_step "${key_prefix}_build" "iOS [$label] simulator build" "dependency_failed"
      run_skip_step "${key_prefix}_run" "iOS [$label] simulator run" "dependency_failed"
    fi

    run_status="$(get_step_status "${key_prefix}_run")"
    if [[ "$run_status" == "PASS" ]]; then
      run_ios_smoke_step "${key_prefix}_smoke" "iOS [$label] launch smoke" "$IOS_SIMULATOR_UDID" "$IOS_BUNDLE_ID"
    else
      run_skip_step "${key_prefix}_smoke" "iOS [$label] launch smoke" "dependency_failed"
    fi

    STEP_LOG_DIR=""
  done < <(emit_ios_target_rows)
}

run_policy_scan_step() {
  local key="policy_scan"
  local label="Forbidden endpoint integration scan"
  local log_path
  local status="PASS"
  local reason=""

  mkdir -p "$(current_log_dir)"
  log_path="$(current_log_dir)/$key.log"

  python3 - "$ROOT_DIR" > "$log_path" 2>&1 <<'PY' || {
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
extensions = {".kt", ".swift", ".java", ".kts"}
forbidden = ["/unrestrict/", "/downloads/", "/torrents/", "/streaming/"]

hits = []
for path in root.rglob("*"):
    if not path.is_file():
        continue
    if path.suffix not in extensions:
        continue
    rel = path.relative_to(root)
    if str(rel).startswith("build/"):
        continue

    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    for idx, line in enumerate(lines, start=1):
        for marker in forbidden:
            if marker in line:
                hits.append(f"{rel}:{idx}: {line.strip()}")

if hits:
    print("Forbidden endpoint markers found in active code:")
    for hit in hits:
        print(hit)
    sys.exit(1)

print("No forbidden endpoint markers found in active code.")
PY
    status="FAIL"
    reason="forbidden_endpoint_found"
  }

  complete_step "$key" "$label" "$status" "0" "$log_path" "$reason"
}

run_manual_signoff_step() {
  local key="manual_signoff"
  local label="Manual GO/NO-GO sign-off"
  local reviewer="${SIGNOFF_REVIEWER:-}"
  local decision="${SIGNOFF_DECISION:-}"
  local log_path

  mkdir -p "$(current_log_dir)"
  log_path="$(current_log_dir)/$key.log"

  {
    echo "Allowed reviewer: $ALLOWED_SIGNOFF_REVIEWER"
    echo "Provided reviewer: ${reviewer:-<none>}"
    echo "Provided decision: ${decision:-<none>}"
  } > "$log_path"

  if [[ -z "$reviewer" ]]; then
    run_warning_step "$key" "$label" "signoff_pending"
    return
  fi

  if [[ "$reviewer" != "$ALLOWED_SIGNOFF_REVIEWER" ]]; then
    complete_step "$key" "$label" "FAIL" "0" "$log_path" "unauthorized_signoff_reviewer"
    return
  fi

  if [[ -z "$decision" ]]; then
    run_warning_step "$key" "$label" "signoff_decision_pending"
    return
  fi

  case "$decision" in
    GO)
      complete_step "$key" "$label" "PASS" "0" "$log_path" ""
      ;;
    NO-GO)
      complete_step "$key" "$label" "FAIL" "0" "$log_path" "manual_no_go"
      ;;
    *)
      complete_step "$key" "$label" "FAIL" "0" "$log_path" "invalid_signoff_decision"
      ;;
  esac
}

cleanup_old_runs() {
  python3 - "$RUNS_ROOT" "$KEEP_RUN_COUNT" <<'PY'
import pathlib
import shutil
import sys

runs_root = pathlib.Path(sys.argv[1])
keep_count = int(sys.argv[2])

if not runs_root.exists():
    raise SystemExit(0)

entries = [p for p in runs_root.iterdir() if p.is_dir()]
entries.sort(key=lambda p: p.stat().st_mtime, reverse=True)

for path in entries[keep_count:]:
    shutil.rmtree(path, ignore_errors=True)
PY
}

write_reports() {
  python3 - "$RESULTS_TSV" "$DEVICE_INDEX_FILE" "$RESULT_JSON" "$SUMMARY_FILE" "$RUN_ID" "$RUN_DIR" "$VERIFY_PROFILE" <<'PY'
import json
import pathlib
import re
import sys

results_tsv = pathlib.Path(sys.argv[1])
device_index_file = pathlib.Path(sys.argv[2])
result_json = pathlib.Path(sys.argv[3])
summary_file = pathlib.Path(sys.argv[4])
run_id = sys.argv[5]
run_dir = sys.argv[6]
verify_profile = sys.argv[7]

steps = []
counts = {"PASS": 0, "FAIL": 0, "WARN": 0, "SKIP": 0}
device_steps = {}
step_pattern = re.compile(r'^(android|ios)_([a-z0-9_]+)_(.+)$')

for line in results_tsv.read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    key, label, status, retries, log_path, reason = line.split("\t", 5)
    steps.append(
        {
            "key": key,
            "label": label,
            "status": status,
            "retries": int(retries) if retries.isdigit() else retries,
            "log": log_path,
            "reason": None if reason == "-" else reason,
        }
    )
    counts.setdefault(status, 0)
    counts[status] += 1

    match = step_pattern.match(key)
    if match:
        platform, slug, short_key = match.groups()
        device_steps.setdefault((platform, slug), []).append(
            {
                "key": short_key,
                "status": status,
                "retries": int(retries) if retries.isdigit() else retries,
                "reason": None if reason == "-" else reason,
                "log": log_path,
            }
        )

device_rows = []
if device_index_file.exists():
    for line in device_index_file.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        platform, slug, label, target, runtime_id, log_dir = line.split("\t", 5)
        device_rows.append(
            {
                "platform": platform,
                "slug": slug,
                "label": label,
                "target": target,
                "runtime_id": None if runtime_id == "-" else runtime_id,
                "log_dir": log_dir,
                "steps": device_steps.get((platform, slug), []),
            }
        )

technical_verdict = "PASS" if counts.get("FAIL", 0) == 0 else "FAIL"
manual_step = next((step for step in steps if step["key"] == "manual_signoff"), None)

release_decision = "NO-GO"
if technical_verdict == "PASS" and manual_step and manual_step["status"] == "PASS":
    release_decision = "GO"

payload = {
    "run_id": run_id,
    "run_dir": run_dir,
    "verify_profile": verify_profile,
    "technical_verdict": technical_verdict,
    "release_decision": release_decision,
    "counts": counts,
    "devices": device_rows,
    "steps": steps,
    "manual_evidence_dir": f"{run_dir}/evidence",
}

result_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

summary_lines = [
    f"run_id: {run_id}",
    f"run_dir: {run_dir}",
    f"verify_profile: {verify_profile}",
    f"technical_verdict: {technical_verdict}",
    f"release_decision: {release_decision}",
    "",
    "counts:",
]
for key in ("PASS", "FAIL", "WARN", "SKIP"):
    summary_lines.append(f"  {key}: {counts.get(key, 0)}")

summary_lines.extend(
    [
        "",
        "devices:",
    ]
)

if not device_rows:
    summary_lines.append("  - none")
else:
    for row in device_rows:
        summary_lines.append(
            f"  - {row['platform']}.{row['label']}: target={row['target']}, runtime={row['runtime_id'] or '-'}"
        )

summary_lines.extend(["", "steps:"])

for step in steps:
    reason = step["reason"] or "-"
    summary_lines.append(
        f"  - {step['key']}: {step['status']} (retries={step['retries']}, reason={reason})"
    )

summary_file.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")
PY
}

echo "[verify-rc] run id: $RUN_ID"
echo "[verify-rc] output: $RUN_DIR"

run_profile_load_step
run_profile_target_guard_step

if [[ "$(get_step_status "profile_load")" == "PASS" && "$(get_step_status "profile_target_guard")" == "PASS" ]]; then
  STEP_LOG_DIR=""
  run_command_step "shared_test" "Shared module tests" "make shared-test"
  run_command_step "android_lint_unit" "Android lint and unit tests" "./gradlew :androidApp:lint :androidApp:testDebugUnitTest"
  run_command_step "android_debug_build" "Android debug build" "make android-debug"

  run_android_device_matrix
  run_ios_device_matrix

  STEP_LOG_DIR=""
  run_policy_scan_step
  run_manual_signoff_step
else
  echo "[verify-rc] profile validation failed; skipping remaining steps."
fi

write_reports
cleanup_old_runs

echo ""
echo "[verify-rc] summary"
cat "$SUMMARY_FILE"
echo "[verify-rc] machine report: $RESULT_JSON"

if [[ "$OVERALL_FAIL" -ne 0 ]]; then
  exit 1
fi

exit 0
