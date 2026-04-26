#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=1
RELEASE_OWNER="${RELEASE_OWNER:-}"

usage() {
  cat <<'EOF'
Usage: scripts/setup-github-release-controls.sh [--apply] [--release-owner <github-login>]

Creates the protected GitHub Environments required by the release workflows.
Rulesets and secrets still require manual review in GitHub Settings.

Defaults to dry-run. No secrets are read, printed, or written by this script.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      DRY_RUN=0
      shift
      ;;
    --release-owner)
      RELEASE_OWNER="${2:-}"
      if [[ -z "$RELEASE_OWNER" ]]; then
        echo "--release-owner requires a GitHub login" >&2
        exit 2
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

cd "$ROOT_DIR"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required." >&2
  exit 1
fi

repo_full_name="$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')"
if [[ -z "$RELEASE_OWNER" ]]; then
  RELEASE_OWNER="$(gh api user --jq '.login')"
fi
release_owner_id="$(gh api "users/$RELEASE_OWNER" --jq '.id')"

environment_payload() {
  cat <<JSON
{
  "wait_timer": 0,
  "prevent_self_review": false,
  "reviewers": [
    {
      "type": "User",
      "id": $release_owner_id
    }
  ]
}
JSON
}

create_environment() {
  local name="$1"
  echo "== environment: $name =="
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY RUN: would create or update $name in $repo_full_name with required reviewer $RELEASE_OWNER."
    environment_payload
    return
  fi

  environment_payload | gh api \
    --method PUT \
    "repos/$repo_full_name/environments/$name" \
    --input - >/dev/null
  echo "Updated $name."
}

create_environment "production-app-store"
create_environment "production-play-store"

echo ""
echo "== required manual follow-up =="
cat <<EOF
1. Add environment variable in production-app-store:
   APPLE_DEVELOPMENT_TEAM_ID

2. Add environment secrets in production-app-store:
   APP_STORE_CONNECT_API_KEY_ID
   APP_STORE_CONNECT_ISSUER_ID
   APP_STORE_CONNECT_API_KEY_BASE64
   APPLE_SIGNING_CERTIFICATE_BASE64
   APPLE_SIGNING_CERTIFICATE_PASSWORD
   APPLE_PROVISIONING_PROFILE_BASE64
   APPLE_PROVISIONING_PROFILE_NAME
   APPLE_EXPORT_OPTIONS_PLIST_BASE64

3. Add environment secrets in production-play-store:
   ANDROID_KEYSTORE_BASE64
   ANDROID_KEYSTORE_PASSWORD
   ANDROID_KEY_ALIAS
   ANDROID_KEY_PASSWORD
   GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64

4. Create repository rulesets in GitHub Settings:
   - protect main: PR required, verification required, no force push/delete
   - protect v* tags: release owner only, signed annotated tags, no deletion/update

Never paste secret values into issues, PRs, commits, logs, or this script.
EOF

echo ""
echo "Existing repository rulesets:"
gh ruleset list --limit 20 || true
