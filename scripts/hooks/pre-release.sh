#!/usr/bin/env bash
# scripts/hooks/pre-release.sh
#
# Go-specific pre-release hook.
#
# For v2+ modules, a major version bump requires updating the module path in
# go.mod and all internal import paths to reflect the new major version suffix
# (e.g. github.com/user/repo/v2 → github.com/user/repo/v3).
#
# Patch and minor releases require no changes — this hook exits early.
#
# Usage (called by release.sh):
#   ./scripts/hooks/pre-release.sh <bump> <tag>
#
# Arguments:
#   bump   One of: patch | minor | major
#   tag    Full version tag, e.g. v3.0.0

set -euo pipefail

BUMP="${1:-}"
TAG="${2:-}"

if [[ -z "$BUMP" || -z "$TAG" ]]; then
  echo "Usage: $0 <bump> <tag>" >&2
  exit 1
fi

# Only major bumps require module path changes
if [[ "$BUMP" != "major" ]]; then
  echo "  ✓ $BUMP release — no module path changes needed"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GOMOD="${REPO_ROOT}/go.mod"

if [[ ! -f "$GOMOD" ]]; then
  echo "Error: go.mod not found at $GOMOD" >&2
  exit 1
fi

# --- Extract current and next major version ---

# Read the current module path from go.mod (first line: module github.com/user/repo/vN)
CURRENT_MODULE=$(grep -E '^module ' "$GOMOD" | awk '{print $2}')
echo "  current module: $CURRENT_MODULE"

# Extract the current major version suffix (e.g. /v2 → 2). Defaults to 1 if no suffix.
CURRENT_MAJOR=$(echo "$CURRENT_MODULE" | grep -oE '/v[0-9]+$' | grep -oE '[0-9]+' || echo "1")
NEXT_MAJOR=$((CURRENT_MAJOR + 1))

CURRENT_SUFFIX="/v${CURRENT_MAJOR}"
NEXT_SUFFIX="/v${NEXT_MAJOR}"

# For v1 modules the path has no suffix — the new path just appends /v2
if [[ "$CURRENT_MAJOR" -eq 1 ]]; then
  CURRENT_PATH="$CURRENT_MODULE"
  NEXT_MODULE="${CURRENT_MODULE}/v2"
  NEXT_SUFFIX="/v2"
else
  CURRENT_PATH="$CURRENT_MODULE"
  NEXT_MODULE="${CURRENT_MODULE%${CURRENT_SUFFIX}}${NEXT_SUFFIX}"
fi

echo "  next module   : $NEXT_MODULE"

# --- Rewrite go.mod ---

sed -i "s|^module ${CURRENT_PATH}$|module ${NEXT_MODULE}|" "$GOMOD"
echo "  ✓ Updated go.mod"

# --- Rewrite all internal import paths ---
#
# Find all .go files and replace any import of the old module path with the new one.
# Uses a temp file to handle sed -i portability across Linux and macOS.

GO_FILES=$(find "$REPO_ROOT" -name "*.go" -not -path "*/vendor/*")
COUNT=0

while IFS= read -r file; do
  if grep -q "$CURRENT_PATH" "$file"; then
    sed -i "s|${CURRENT_PATH}|${NEXT_MODULE}|g" "$file"
    COUNT=$((COUNT + 1))
  fi
done <<< "$GO_FILES"

echo "  ✓ Updated $COUNT .go file(s) with new import path"

# --- Verify the module still builds ---

echo "  → Running go mod tidy..."
cd "$REPO_ROOT" && go mod tidy
echo "  ✓ go mod tidy passed"
