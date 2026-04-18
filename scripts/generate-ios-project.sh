#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_SPEC="$ROOT_DIR/iosApp/project.yml"
PROJECT_FILE="$ROOT_DIR/iosApp/DebridHubHost.xcodeproj"

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

cd "$ROOT_DIR/iosApp"
xcodegen generate --spec "$PROJECT_SPEC"

echo "Generated $PROJECT_FILE"
