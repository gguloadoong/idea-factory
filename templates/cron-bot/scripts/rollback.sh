#!/usr/bin/env bash
# rollback.sh — Roll back to a previous deployment version (git tag).
# Usage: rollback.sh <VERSION_TAG>
# Exit codes: 0 success, 1 invalid args / tag not found, 2 rollback failure

set -euo pipefail

VERSION="${1:-}"

# --- Input validation ---
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <VERSION_TAG>" >&2
  echo "  VERSION_TAG  A git tag identifying the target deployment (e.g. v1.2.3)" >&2
  exit 1
fi

# --- Confirm target tag exists ---
if ! git rev-parse --verify "refs/tags/$VERSION" >/dev/null 2>&1; then
  echo "Error: git tag '$VERSION' not found in this repository." >&2
  echo "Available tags:" >&2
  git tag --sort=-creatordate | head -20 >&2
  exit 1
fi

TARGET_SHA=$(git rev-parse "refs/tags/$VERSION")
CURRENT_SHA=$(git rev-parse HEAD)
ROLLBACK_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "Rolling back to $VERSION ($TARGET_SHA)"
echo "Current HEAD: $CURRENT_SHA"

# --- Prepare audit directory ---
AUDIT_DIR=".omc/audit"
mkdir -p "$AUDIT_DIR"
AUDIT_FILE="$AUDIT_DIR/rollbacks.jsonl"

# --- Placeholder: actual rollback steps ---
# Replace the block below with the real rollback procedure for this project.
# Common patterns:
#   git checkout "$VERSION"          # switch code
#   npm ci --production              # reinstall deps for that version
#   npm run db:migrate:down          # revert DB migrations if needed
#   systemctl restart myservice      # restart the process
#
# Example (uncomment and adapt):
# git checkout "$VERSION" || { echo "Error: git checkout failed" >&2; exit 2; }

echo "Rollback commands would run here (placeholder — edit scripts/rollback.sh for this project)."

# --- Log rollback to audit trail ---
printf '{"ts":"%s","version":"%s","target_sha":"%s","previous_sha":"%s","operator":"%s","status":"success"}\n' \
  "$ROLLBACK_TS" "$VERSION" "$TARGET_SHA" "$CURRENT_SHA" "${USER:-unknown}" \
  >> "$AUDIT_FILE"

echo "Rollback to $VERSION complete. Audit record appended to $AUDIT_FILE"
exit 0
