#!/usr/bin/env bash
set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNS_ROOT="$ROOT_DIR/build/rc-verify"
RUN_ID_BASE="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_ID="$RUN_ID_BASE"
if [[ -n "${VERIFY_RC_SCOPE:-}" && "${VERIFY_RC_SCOPE:-full}" != "full" ]]; then
  RUN_ID="${RUN_ID}-${VERIFY_RC_SCOPE}"
fi
if [[ -e "$RUNS_ROOT/$RUN_ID" ]]; then
  RUN_ID="${RUN_ID}-$$"
fi
RUN_DIR="$RUNS_ROOT/$RUN_ID"
LOG_DIR="$RUN_DIR/logs"
EVIDENCE_DIR="$RUN_DIR/evidence"
RESULTS_TSV="$RUN_DIR/results.tsv"
RESULT_JSON="$RUN_DIR/result.json"
SUMMARY_FILE="$RUN_DIR/summary.txt"
VERIFY_PROFILE="${VERIFY_PROFILE:-local-fast}"
DEVICE_POOL_FILE="$ROOT_DIR/ci/device-pool.yml"
IOS_RESOLVER_SCRIPT="$ROOT_DIR/scripts/resolve-ios-simulator.py"
PROFILE_META_FILE="$RUN_DIR/profile-meta.env"
PROFILE_ANDROID_FILE="$RUN_DIR/profile-android.tsv"
PROFILE_IOS_FILE="$RUN_DIR/profile-ios.tsv"
DEVICE_ROOT_DIR="$RUN_DIR/devices"
DEVICE_INDEX_FILE="$RUN_DIR/device-index.tsv"
STEP_LOG_DIR=""

MAX_ENV_RETRIES=2
ENV_RETRY_WAIT_SECONDS=60
KEEP_RUN_COUNT=5
STEP_COMMAND_TIMEOUT_SECONDS="${STEP_COMMAND_TIMEOUT_SECONDS:-2400}"
VERIFY_RC_SCOPE="${VERIFY_RC_SCOPE:-full}"

ANDROID_PACKAGE="app.debridhub"
IOS_BUNDLE_ID="app.debridhub.ios"
ALLOWED_SIGNOFF_REVIEWER="release-manager"

OVERALL_FAIL=0
ANDROID_DEVICE_ID=""
ANDROID_AVD_NAME_EFFECTIVE=""
ANDROID_ABI_EFFECTIVE=""
ANDROID_SYSTEM_IMAGE_EFFECTIVE=""
ANDROID_LABEL_EFFECTIVE=""
IOS_SIMULATOR_UDID=""
IOS_SIMULATOR_NAME_EFFECTIVE="${IOS_SIMULATOR_NAME:-}"
IOS_RUNTIME_EFFECTIVE=""
IOS_DEVICE_TYPE_EFFECTIVE=""
IOS_DEVICE_CLASS_EFFECTIVE=""
IOS_LABEL_EFFECTIVE=""
LAST_ERROR=""

mkdir -p "$LOG_DIR" "$EVIDENCE_DIR"
: > "$RESULTS_TSV"
: > "$DEVICE_INDEX_FILE"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for verify-rc" >&2
  exit 1
fi

if [[ ! -x "$IOS_RESOLVER_SCRIPT" ]]; then
  echo "resolve-ios-simulator script is required for verify-rc: $IOS_RESOLVER_SCRIPT" >&2
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

reason_in_csv() {
  local target="${1:-}"
  local csv="${2:-}"
  local entry

  if [[ -z "$target" || -z "$csv" ]]; then
    return 1
  fi

  IFS=',' read -r -a entries <<< "$csv"
  for entry in "${entries[@]}"; do
    entry="$(printf '%s' "$entry" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
    [[ -z "$entry" ]] && continue
    if [[ "$entry" == "$target" ]]; then
      return 0
    fi
  done

  return 1
}

android_boot_log_has_accel_error() {
  local boot_log_path="${1:-}"

  [[ -n "$boot_log_path" ]] || return 1
  [[ -f "$boot_log_path" ]] || return 1

  grep -Eq \
    "HVF error: HV_UNSUPPORTED|failed to initialize HVF|failed to initialize KVM|/dev/kvm|requires hardware acceleration" \
    "$boot_log_path" 2>/dev/null
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
  local timeout_seconds="${4:-$STEP_COMMAND_TIMEOUT_SECONDS}"
  local log_path
  local status="PASS"
  local reason=""
  local rc=0

  mkdir -p "$(current_log_dir)"
  log_path="$(current_log_dir)/$key.log"

  printf '$ %s\n\n' "$command" > "$log_path"

  python3 - "$ROOT_DIR" "$command" "$log_path" "$timeout_seconds" <<'PY' || rc=$?
import os
import select
import signal
import subprocess
import sys
import time

root_dir, command, log_path, timeout_seconds_raw = sys.argv[1:5]

try:
    timeout_seconds = int(timeout_seconds_raw)
except ValueError:
    timeout_seconds = 2400

start = time.monotonic()

with open(log_path, "a", encoding="utf-8") as log_file:
    process = subprocess.Popen(
        ["/bin/bash", "-lc", command],
        cwd=root_dir,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        preexec_fn=os.setsid,
    )

    timed_out = False

    while True:
        if process.stdout is None:
            break

        ready, _, _ = select.select([process.stdout], [], [], 1.0)
        if ready:
            line = process.stdout.readline()
            if line:
                sys.stdout.write(line)
                sys.stdout.flush()
                log_file.write(line)
                log_file.flush()

        if process.poll() is not None:
            break

        if time.monotonic() - start > timeout_seconds:
            timed_out = True
            timeout_message = f"\n[verify-rc] command timed out after {timeout_seconds}s\n"
            sys.stdout.write(timeout_message)
            sys.stdout.flush()
            log_file.write(timeout_message)
            log_file.flush()

            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

            grace_deadline = time.monotonic() + 5
            while process.poll() is None and time.monotonic() < grace_deadline:
                time.sleep(0.1)

            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            break

    if process.stdout is not None:
        remainder = process.stdout.read()
        if remainder:
            sys.stdout.write(remainder)
            sys.stdout.flush()
            log_file.write(remainder)
            log_file.flush()

    if timed_out:
        raise SystemExit(124)

    raise SystemExit(process.returncode if process.returncode is not None else 1)
PY

  if [[ "$rc" -ne 0 ]]; then
    status="FAIL"
    if [[ "$rc" -eq 124 ]]; then
      reason="command_timeout"
    else
      reason="command_failed"
    fi
  fi

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
    device_class = entry["class"].to_s
    primary = device_class if primary.empty?
    next if label.empty? && primary.empty?

    fallbacks = Array(entry["fallbacks"]).map(&:to_s).join("|")
    runtime = entry["runtime"].to_s
    device_type = entry["device_type"].to_s

    file.puts([label, primary, fallbacks, runtime, device_type, device_class].join("\t"))
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

android_wait_for_device_ready() {
  local device_id="${1:-}"
  local deadline=$((SECONDS + 180))
  local boot_completed
  local dev_bootcomplete
  local logged_wait=0

  if [[ -z "$device_id" ]]; then
    LAST_ERROR="android_device_missing"
    return 1
  fi

  adb -s "$device_id" wait-for-device >/dev/null 2>&1 || true

  while [[ $SECONDS -lt $deadline ]]; do
    boot_completed="$(adb -s "$device_id" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    dev_bootcomplete="$(adb -s "$device_id" shell getprop dev.bootcomplete 2>/dev/null | tr -d '\r')"

    if [[ "$boot_completed" == "1" && ( -z "$dev_bootcomplete" || "$dev_bootcomplete" == "1" ) ]]; then
      if adb -s "$device_id" shell pm path android >/dev/null 2>&1; then
        echo "Android device ready: $device_id"
        return 0
      fi
    fi

    if (( logged_wait % 5 == 0 )); then
      echo "Waiting for Android services on $device_id (sys.boot_completed=${boot_completed:-<empty>} dev.bootcomplete=${dev_bootcomplete:-<empty>})"
    fi
    logged_wait=$((logged_wait + 1))

    sleep 2
  done

  LAST_ERROR="android_device_services_timeout"
  return 1
}

android_avd_exists() {
  local emulator_bin="$1"
  local avd_name="$2"
  "$emulator_bin" -list-avds | awk -v target="$avd_name" '$0 == target { found = 1 } END { exit found ? 0 : 1 }'
}

ensure_android_avd_from_profile() {
  local avd_name="$1"
  local requested_avd_base
  local source_avd_name
  local sdk_root
  local emulator_bin
  local sdkmanager_bin
  local avdmanager_bin
  local row
  local row_avd
  local api
  local abi
  local system_image
  local device_profile
  local target_abi
  local target_system_image
  local effective_avd_name

  requested_avd_base="$(printf '%s' "$avd_name" | sed -E 's/-(arm64-v8a|x86_64)$//')"

  sdk_root="$(find_android_sdk_root || true)"
  if [[ -z "$sdk_root" ]]; then
    LAST_ERROR="android_sdk_root_not_found"
    return 1
  fi

  emulator_bin="$sdk_root/emulator/emulator"
  sdkmanager_bin="$(find_android_tool "$sdk_root" sdkmanager || true)"
  avdmanager_bin="$(find_android_tool "$sdk_root" avdmanager || true)"

  if [[ ! -x "$emulator_bin" || -z "$sdkmanager_bin" || -z "$avdmanager_bin" ]]; then
    LAST_ERROR="android_tools_missing"
    return 1
  fi

  if [[ ! -s "$PROFILE_ANDROID_FILE" ]]; then
    LAST_ERROR="no_android_profile_targets"
    return 1
  fi

  api=""
  abi=""
  system_image=""
  device_profile=""

  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    row_avd="$(printf '%s' "$row" | awk -F '\t' '{print $2}')"
    [[ "$row_avd" != "$avd_name" && "$row_avd" != "$requested_avd_base" ]] && continue
    api="$(printf '%s' "$row" | awk -F '\t' '{print $4}')"
    abi="$(printf '%s' "$row" | awk -F '\t' '{print $5}')"
    system_image="$(printf '%s' "$row" | awk -F '\t' '{print $6}')"
    device_profile="$(printf '%s' "$row" | awk -F '\t' '{print $7}')"
    break
  done < "$PROFILE_ANDROID_FILE"

  if [[ -z "$system_image" ]]; then
    LAST_ERROR="android_profile_missing_system_image"
    return 1
  fi

  target_abi="$(android_target_abi_for_host "$abi")"
  target_system_image="$(android_system_image_for_abi "$system_image" "$target_abi")"
  source_avd_name="$row_avd"
  if [[ -z "$source_avd_name" ]]; then
    source_avd_name="$requested_avd_base"
  fi
  if [[ -z "$source_avd_name" ]]; then
    source_avd_name="$avd_name"
  fi
  effective_avd_name="$(android_effective_avd_name "$source_avd_name" "$abi" "$target_abi")"

  if [[ -z "$effective_avd_name" ]]; then
    effective_avd_name="$avd_name"
  fi

  ANDROID_AVD_NAME_EFFECTIVE="$effective_avd_name"
  ANDROID_ABI_EFFECTIVE="$target_abi"
  ANDROID_SYSTEM_IMAGE_EFFECTIVE="$target_system_image"

  if android_avd_exists "$emulator_bin" "$effective_avd_name"; then
    return 0
  fi

  if [[ -z "$device_profile" ]]; then
    device_profile="pixel"
  fi

  set +o pipefail
  if ! yes | "$sdkmanager_bin" --install "$target_system_image" >/dev/null; then
    set -o pipefail
    LAST_ERROR="android_system_image_install_failed"
    return 1
  fi
  set -o pipefail

  if ! printf 'no\n' | "$avdmanager_bin" create avd -n "$effective_avd_name" -k "$target_system_image" --abi "$target_abi" -d "$device_profile" --force >/dev/null; then
    LAST_ERROR="android_avd_create_failed"
    return 1
  fi

  if ! android_avd_exists "$emulator_bin" "$effective_avd_name"; then
    LAST_ERROR="android_avd_missing_after_create"
    return 1
  fi

  return 0
}

resolve_android_avd_from_profile() {
  local sdk_root
  local emulator_bin
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

  sdk_root="$(find_android_sdk_root || true)"
  if [[ -z "$sdk_root" ]]; then
    LAST_ERROR="android_sdk_root_not_found"
    return 1
  fi

  emulator_bin="$sdk_root/emulator/emulator"
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
  local runtime
  local device_type
  local class_hint

  if [[ ! -s "$PROFILE_IOS_FILE" ]]; then
    LAST_ERROR="no_ios_profile_targets"
    return 1
  fi

  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    label="$(printf '%s' "$row" | awk -F '\t' '{print $1}')"
    primary="$(printf '%s' "$row" | awk -F '\t' '{print $2}')"
    fallback_list="$(printf '%s' "$row" | awk -F '\t' '{print $3}')"
    runtime="$(printf '%s' "$row" | awk -F '\t' '{print $4}')"
    device_type="$(printf '%s' "$row" | awk -F '\t' '{print $5}')"
    class_hint="$(printf '%s' "$row" | awk -F '\t' '{print $6}')"

    if resolve_ios_target "$label" "$primary" "$fallback_list" "$runtime" "$device_type" "$class_hint"; then
      IOS_LABEL_EFFECTIVE="${label:-default}"
      return 0
    fi
  done < "$PROFILE_IOS_FILE"

  LAST_ERROR="no_ios_simulator_for_profile"
  return 1
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
  local label="${1:-latest-phone}"
  local primary="${2:-}"
  local fallback_list="${3:-}"
  local runtime="${4:-}"
  local device_type="${5:-}"
  local class_hint="${6:-}"
  local device_class
  local resolver_output

  if [[ ! -x "$IOS_RESOLVER_SCRIPT" ]]; then
    LAST_ERROR="ios_resolver_missing"
    return 1
  fi

  device_class="$(ios_device_class_from_label "$label" "$class_hint")"

  if ! resolver_output="$(python3 "$IOS_RESOLVER_SCRIPT" --label "$label" --name "$primary" --fallbacks "$fallback_list" --runtime "$runtime" --device-type "$device_type" --device-class "$device_class" 2>/dev/null)"; then
    LAST_ERROR="ios_resolve_failed"
    return 1
  fi

  IOS_SIMULATOR_NAME_EFFECTIVE="$(printf '%s' "$resolver_output" | awk -F '\t' '{print $1}')"
  IOS_SIMULATOR_UDID="$(printf '%s' "$resolver_output" | awk -F '\t' '{print $2}')"
  IOS_RUNTIME_EFFECTIVE="$(printf '%s' "$resolver_output" | awk -F '\t' '{print $3}')"
  IOS_DEVICE_TYPE_EFFECTIVE="$(printf '%s' "$resolver_output" | awk -F '\t' '{print $4}')"
  IOS_DEVICE_CLASS_EFFECTIVE="$(printf '%s' "$resolver_output" | awk -F '\t' '{print $6}')"

  if [[ -z "$IOS_SIMULATOR_NAME_EFFECTIVE" || -z "$IOS_SIMULATOR_UDID" ]]; then
    LAST_ERROR="ios_resolve_incomplete"
    return 1
  fi

  return 0
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

  printf 'default\t\t\n'
}

select_android_candidate() {
  local primary="$1"
  local fallback_list="$2"
  local sdk_root
  local emulator_bin
  local available_avds
  local candidates
  local candidate

  sdk_root="$(find_android_sdk_root || true)"
  if [[ -z "$sdk_root" ]]; then
    LAST_ERROR="android_sdk_root_not_found"
    return 1
  fi

  emulator_bin="$sdk_root/emulator/emulator"
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

    if ensure_android_avd_from_profile "$candidate"; then
      printf '%s\n' "${ANDROID_AVD_NAME_EFFECTIVE:-$candidate}"
      return 0
    fi
  done

  LAST_ERROR="no_android_avd_for_label"
  return 1
}

select_ios_candidate() {
  local label="$1"
  local primary="$2"
  local fallback_list="$3"
  local runtime="$4"
  local device_type="$5"
  local class_hint="${6:-}"

  if resolve_ios_target "$label" "$primary" "$fallback_list" "$runtime" "$device_type" "$class_hint"; then
    printf '%s\n' "$IOS_SIMULATOR_NAME_EFFECTIVE"
    return 0
  fi

  LAST_ERROR="${LAST_ERROR:-no_ios_simulator_for_label}"
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

shutdown_other_android_emulators() {
  local target_avd="${1:-}"
  local device_id
  local running_avd

  while read -r device_id; do
    [[ -z "$device_id" ]] && continue
    [[ "$device_id" != emulator-* ]] && continue

    running_avd="$(adb -s "$device_id" emu avd name 2>/dev/null | tr -d '\r' | awk 'NF { print; exit }')"
    if [[ -n "$target_avd" && "$running_avd" == "$target_avd" ]]; then
      continue
    fi

    echo "Stopping other Android emulator: ${running_avd:-unknown} ($device_id)"
    adb -s "$device_id" emu kill >/dev/null 2>&1 || true
  done < <(adb devices | awk 'NR > 1 && $1 ~ /^emulator-/ { print $1 }')

  sleep 3
}

ensure_android_environment() {
  local requested_avd="${1:-}"
  local sdk_root
  local emulator_bin
  local avd_name
  local deadline
  local device_id
  local existing_device_id

  if ! ensure_adb_on_path; then
    return 1
  fi

  sdk_root="$(find_android_sdk_root || true)"
  if [[ -z "$sdk_root" ]]; then
    LAST_ERROR="android_sdk_root_not_found"
    return 1
  fi

  emulator_bin="$sdk_root/emulator/emulator"
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

  echo "Preparing Android environment for requested AVD: $avd_name"

  if ! ensure_android_avd_from_profile "$avd_name"; then
    return 1
  fi

  if [[ -n "$ANDROID_AVD_NAME_EFFECTIVE" ]]; then
    avd_name="$ANDROID_AVD_NAME_EFFECTIVE"
  fi

  echo "Using Android AVD: $avd_name"
  echo "Host-compatible ABI: ${ANDROID_ABI_EFFECTIVE:-unknown}"
  echo "System image: ${ANDROID_SYSTEM_IMAGE_EFFECTIVE:-unknown}"

  ANDROID_AVD_NAME_EFFECTIVE="$avd_name"

  existing_device_id="$(find_booted_device_for_avd "$avd_name" || true)"
  if [[ -n "$existing_device_id" ]]; then
    echo "Android AVD already booted: $avd_name ($existing_device_id)"
    if ! android_wait_for_device_ready "$existing_device_id"; then
      return 1
    fi
    ANDROID_DEVICE_ID="$existing_device_id"
    return 0
  fi

  shutdown_other_android_emulators "$avd_name"

  mkdir -p "$(current_log_dir)"
  local boot_log_path
  local emulator_pid
  local -a emulator_args
  local emulator_accel_mode
  local boot_timeout_seconds=300
  local retried_without_accel=0
  boot_log_path="$(current_log_dir)/android_emulator_boot.log"
  emulator_accel_mode="${ANDROID_EMULATOR_ACCEL_MODE:-auto}"
  if [[ "${GITHUB_ACTIONS:-}" == "true" && "$emulator_accel_mode" == "auto" && "$(uname -s)" == "Darwin" ]]; then
    emulator_accel_mode="off"
  fi

  while :; do
    emulator_args=(
      -avd "$avd_name"
      -no-snapshot-load
      -no-snapshot-save
      -no-boot-anim
      -noaudio
      -camera-back none
      -camera-front none
    )
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
      emulator_args+=(
        -no-window
        -gpu swiftshader_indirect
      )
    fi
    if [[ "$emulator_accel_mode" == "off" ]]; then
      emulator_args+=(
        -accel off
      )
      boot_timeout_seconds=900
    else
      boot_timeout_seconds=300
    fi

    : > "$boot_log_path"
    "$emulator_bin" "${emulator_args[@]}" > "$boot_log_path" 2>&1 &
    emulator_pid=$!
    echo "Started Android emulator pid=$emulator_pid avd=$avd_name accel=$emulator_accel_mode"
    echo "Android emulator boot log: $boot_log_path"
    sleep 5

    deadline=$((SECONDS + boot_timeout_seconds))
    while [[ $SECONDS -lt $deadline ]]; do
      if ! kill -0 "$emulator_pid" 2>/dev/null; then
        if android_boot_log_has_accel_error "$boot_log_path"; then
          if [[ "$emulator_accel_mode" != "off" && $retried_without_accel -eq 0 ]]; then
            echo "Hardware acceleration unavailable; retrying Android emulator with software acceleration (-accel off)."
            emulator_accel_mode="off"
            retried_without_accel=1
            continue 2
          fi
          LAST_ERROR="android_emulator_accel_unavailable"
        elif grep -q "CPU Architecture .* is not supported" "$boot_log_path" 2>/dev/null; then
          LAST_ERROR="android_emulator_incompatible_abi"
        elif grep -q "FATAL" "$boot_log_path" 2>/dev/null; then
          LAST_ERROR="android_emulator_start_failed"
        else
          LAST_ERROR="android_emulator_exited"
        fi
        echo "Android emulator exited early: $LAST_ERROR"
        return 1
      fi

      device_id="$(find_booted_device_for_avd "$avd_name" || true)"
      if [[ -n "$device_id" ]]; then
        echo "Android emulator reported booted device: $device_id"
        if ! android_wait_for_device_ready "$device_id"; then
          return 1
        fi
        ANDROID_DEVICE_ID="$device_id"
        return 0
      fi
      echo "Waiting for Android emulator to boot: $avd_name"
      sleep 2
    done

    if [[ "$emulator_accel_mode" != "off" && $retried_without_accel -eq 0 ]] && android_boot_log_has_accel_error "$boot_log_path"; then
      if kill -0 "$emulator_pid" 2>/dev/null; then
        kill "$emulator_pid" >/dev/null 2>&1 || true
      fi
      echo "Hardware acceleration unavailable during boot; retrying Android emulator with software acceleration (-accel off)."
      emulator_accel_mode="off"
      retried_without_accel=1
      continue
    fi

    LAST_ERROR="android_boot_timeout"
    if kill -0 "$emulator_pid" 2>/dev/null; then
      kill "$emulator_pid" >/dev/null 2>&1 || true
      sleep 2
      if kill -0 "$emulator_pid" 2>/dev/null; then
        kill -9 "$emulator_pid" >/dev/null 2>&1 || true
      fi
    fi
    return 1
  done
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

  if ! command -v xcrun >/dev/null 2>&1; then
    LAST_ERROR="xcrun_not_found"
    return 1
  fi

  if [[ -n "${IOS_SIMULATOR_UDID:-}" ]]; then
    IOS_SIMULATOR_UDID="$IOS_SIMULATOR_UDID"
    if [[ -z "$IOS_SIMULATOR_NAME_EFFECTIVE" ]]; then
      IOS_SIMULATOR_NAME_EFFECTIVE="$requested_name"
    fi
  elif [[ -n "$requested_name" ]]; then
    IOS_SIMULATOR_NAME_EFFECTIVE="$requested_name"
    IOS_SIMULATOR_UDID="$(find_ios_simulator_udid_by_name "$requested_name")"
  elif [[ -n "${IOS_SIMULATOR_NAME:-}" ]]; then
    requested_name="$IOS_SIMULATOR_NAME"
    IOS_SIMULATOR_NAME_EFFECTIVE="$requested_name"
    IOS_SIMULATOR_UDID="$(find_ios_simulator_udid_by_name "$requested_name")"
  fi

  if [[ -z "$IOS_SIMULATOR_UDID" ]]; then
    LAST_ERROR="ios_simulator_not_found"
    return 1
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
  local warn_reasons_csv="${ENV_FAIL_AS_WARN_REASONS:-}"

  mkdir -p "$(current_log_dir)"
  log_path="$(current_log_dir)/$key.log"

  : > "$log_path"
  while [[ $attempt -le $MAX_ENV_RETRIES ]]; do
    local pipe_path
    local tee_pid
    local attempt_exit

    pipe_path="$(mktemp -u)"
    mkfifo "$pipe_path"
    tee -a "$log_path" < "$pipe_path" &
    tee_pid=$!

    set +e
    {
      echo "Attempt $((attempt + 1))/$((MAX_ENV_RETRIES + 1))"
      LAST_ERROR=""
      "$function_name" "$@"
    } > "$pipe_path" 2>&1
    attempt_exit=$?
    set -e

    wait "$tee_pid"
    rm -f "$pipe_path"

    if [[ $attempt_exit -eq 0 ]]; then
      status="PASS"
      retries="$attempt"
      reason=""
      break
    fi

    reason="${LAST_ERROR:-env_not_ready}"
    if [[ $attempt -lt $MAX_ENV_RETRIES ]]; then
      echo "Transient environment issue: $reason" | tee -a "$log_path"
      echo "Sleeping ${ENV_RETRY_WAIT_SECONDS}s before retry" | tee -a "$log_path"
      sleep "$ENV_RETRY_WAIT_SECONDS"
    fi
    attempt=$((attempt + 1))
  done

  if [[ "$status" == "FAIL" ]] && reason_in_csv "$reason" "$warn_reasons_csv"; then
    status="WARN"
    {
      echo "Downgrading environment failure to warning: $reason"
      echo "Downgrade policy: $warn_reasons_csv"
    } >> "$log_path"
  fi

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
  local android_rows_file
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
  local env_warn_reasons=""

  if [[ "${GITHUB_ACTIONS:-}" == "true" && "$(uname -s)" == "Darwin" ]]; then
    env_warn_reasons="android_emulator_accel_unavailable"
  fi

  dependency_status="$(get_step_status "android_debug_build")"
  android_rows_file="$(mktemp)"
  emit_android_target_rows > "$android_rows_file"

  exec 3< "$android_rows_file"
  while IFS= read -r row <&3; do
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
      ENV_FAIL_AS_WARN_REASONS="$env_warn_reasons" run_env_step_with_retry "${key_prefix}_env_ready" "Android [$label] environment readiness" "ensure_android_environment" "$selected_avd"
      env_status="$(get_step_status "${key_prefix}_env_ready")"
      device_runtime_id=""
      if [[ "$env_status" == "PASS" ]]; then
        device_runtime_id="$ANDROID_DEVICE_ID"
      fi
      record_device_index "android" "$slug" "$label" "${ANDROID_AVD_NAME_EFFECTIVE:-$selected_avd}" "$device_runtime_id" "$device_dir"
    else
      run_fail_step "${key_prefix}_env_ready" "Android [$label] environment readiness" "${LAST_ERROR:-android_target_unavailable}" "No available Android AVD for label '$label'."
      record_device_index "android" "$slug" "$label" "${primary:-<none>}" "" "$device_dir"
      run_skip_step "${key_prefix}_install" "Android [$label] install debug" "dependency_failed"
      run_skip_step "${key_prefix}_smoke" "Android [$label] launch smoke" "dependency_failed"
      STEP_LOG_DIR=""
      continue
    fi

    if [[ "$dependency_status" == "PASS" && "$(get_step_status "${key_prefix}_env_ready")" == "PASS" ]]; then
      run_command_step "${key_prefix}_install" "Android [$label] install debug" "ANDROID_SERIAL=\"$ANDROID_DEVICE_ID\" ./gradlew :androidApp:installDebug"
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
  done
  exec 3<&-
  rm -f "$android_rows_file"
}

run_ios_device_matrix() {
  local ios_rows_file
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
  local runtime
  local device_type
  local class_hint

  ios_rows_file="$(mktemp)"
  emit_ios_target_rows > "$ios_rows_file"

  exec 3< "$ios_rows_file"
  while IFS= read -r row <&3; do
    [[ -z "$row" ]] && continue
    label="$(printf '%s' "$row" | awk -F '\t' '{print $1}')"
    primary="$(printf '%s' "$row" | awk -F '\t' '{print $2}')"
    fallback_list="$(printf '%s' "$row" | awk -F '\t' '{print $3}')"
    runtime="$(printf '%s' "$row" | awk -F '\t' '{print $4}')"
    device_type="$(printf '%s' "$row" | awk -F '\t' '{print $5}')"
    class_hint="$(printf '%s' "$row" | awk -F '\t' '{print $6}')"
    label="${label:-default}"
    slug="$(slugify "$label")"
    device_dir="$DEVICE_ROOT_DIR/ios/$slug"
    key_prefix="ios_${slug}"
    mkdir -p "$device_dir"
    STEP_LOG_DIR="$device_dir"

    selected_simulator=""
    if selected_simulator="$(select_ios_candidate "$label" "$primary" "$fallback_list" "$runtime" "$device_type" "$class_hint")"; then
      run_env_step_with_retry "${key_prefix}_env_ready" "iOS [$label] simulator readiness" "ensure_ios_environment" "$selected_simulator"
      env_status="$(get_step_status "${key_prefix}_env_ready")"
      simulator_udid=""
      if [[ "$env_status" == "PASS" ]]; then
        simulator_udid="$IOS_SIMULATOR_UDID"
      fi
      record_device_index "ios" "$slug" "$label" "${selected_simulator} (${IOS_DEVICE_CLASS_EFFECTIVE:-latest-phone})" "$simulator_udid" "$device_dir"
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
      run_command_step "${key_prefix}_run" "iOS [$label] simulator run" "IOS_SIMULATOR_NAME=\"$IOS_SIMULATOR_NAME_EFFECTIVE\" IOS_SIMULATOR_UDID=\"$IOS_SIMULATOR_UDID\" IOS_SKIP_BUILD=1 make ios-run"
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
  done
  exec 3<&-
  rm -f "$ios_rows_file"
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
echo "[verify-rc] scope: $VERIFY_RC_SCOPE"

run_profile_load_step
run_profile_target_guard_step

if [[ "$(get_step_status "profile_load")" == "PASS" && "$(get_step_status "profile_target_guard")" == "PASS" ]]; then
  STEP_LOG_DIR=""
  case "$VERIFY_RC_SCOPE" in
    full)
      run_command_step "shared_test" "Shared module tests" "make shared-test"
      run_command_step "android_lint_unit" "Android lint and unit tests" "./gradlew :androidApp:lint :androidApp:testDebugUnitTest"
      run_command_step "android_debug_build" "Android debug build" "make android-debug"
      run_android_device_matrix
      run_ios_device_matrix
      STEP_LOG_DIR=""
      run_policy_scan_step
      run_manual_signoff_step
      ;;
    shared)
      run_command_step "shared_test" "Shared module tests" "make shared-test"
      ;;
    android)
      run_command_step "android_lint_unit" "Android lint and unit tests" "./gradlew :androidApp:lint :androidApp:testDebugUnitTest"
      run_command_step "android_debug_build" "Android debug build" "make android-debug"
      run_android_device_matrix
      ;;
    ios)
      run_ios_device_matrix
      ;;
    gate)
      run_policy_scan_step
      run_manual_signoff_step
      ;;
    *)
      run_fail_step "verify_scope" "Validate verify-rc scope" "invalid_verify_scope" "Unsupported VERIFY_RC_SCOPE '$VERIFY_RC_SCOPE'. Expected one of: full, shared, android, ios, gate."
      ;;
  esac
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
