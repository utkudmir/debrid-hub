#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/generate-ios-project.sh"
open "$ROOT_DIR/iosApp/DebridHubHost.xcodeproj"
