#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="$ROOT_DIR/.swiftlint.yml"

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "swiftlint is required. Install it first or let CI provision it." >&2
  exit 1
fi

swiftlint lint --strict --config "$CONFIG_PATH"
