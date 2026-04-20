#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_SPEC="$ROOT_DIR/iosApp/project.yml"
PROJECT_FILE="$ROOT_DIR/iosApp/DebridHubHost.xcodeproj"
PBXPROJ_FILE="$PROJECT_FILE/project.pbxproj"
FORCE_GENERATE="${FORCE_IOS_PROJECT_GENERATE:-0}"
GENERATED_LOCALIZATION_DIRS=(
  "$ROOT_DIR/iosApp/DebridHubHost/Generated"
  "$ROOT_DIR/iosApp/DebridHubHost/Resources"
)

generated_localizations_changed_since_project() {
  local directory
  for directory in "${GENERATED_LOCALIZATION_DIRS[@]}"; do
    if [[ -d "$directory" ]] && find "$directory" -type f -newer "$PBXPROJ_FILE" | grep -q .; then
      return 0
    fi
  done

  return 1
}

if ! command -v xcodegen >/dev/null 2>&1; then
  if [[ -d "$PROJECT_FILE" ]]; then
    echo "xcodegen not found; using existing $PROJECT_FILE" >&2
    echo "Install xcodegen to regenerate from $PROJECT_SPEC (brew install xcodegen)." >&2
    exit 0
  fi

  echo "xcodegen is required to generate $PROJECT_FILE from $PROJECT_SPEC." >&2
  echo "Install it with: brew install xcodegen" >&2
  exit 1
fi

if [[ "$FORCE_GENERATE" != "1" && -f "$PBXPROJ_FILE" && "$PBXPROJ_FILE" -nt "$PROJECT_SPEC" ]] && ! generated_localizations_changed_since_project; then
  echo "Xcode project is up to date: $PROJECT_FILE"
  exit 0
fi

cd "$ROOT_DIR/iosApp"
xcodegen generate --spec "$PROJECT_SPEC"

echo "Generated $PROJECT_FILE"
