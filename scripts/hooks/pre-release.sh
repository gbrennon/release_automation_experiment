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

# --- Helpers ---

step()    { echo ""        >&2; echo "▶ $*" >&2; }
info()    { echo "  · $*"  >&2; }
success() { echo "  ✓ $*"  >&2; }
fail()    { echo "  ✗ $*"  >&2; }

# --- Args ---

step "Pre-release hook"

BUMP="${1:-}"
TAG="${2:-}"

if [[ -z "$BUMP" || -z "$TAG" ]]; then
  fail "Usage: $0 <bump> <tag>"
  exit 1
fi

info "bump : $BUMP"
info "tag  : $TAG"

# Only major bumps require module path changes
if [[ "$BUMP" != "major" ]]; then
  success "$BUMP release — no module path changes needed"
  exit 0
fi

# --- Bootstrap ---

step "Rewriting Go module path"

REPO_ROOT="$(git rev-parse --show-toplevel)"
GOMOD="${REPO_ROOT}/go.mod"

if [[ ! -f "$GOMOD" ]]; then
  fail "go.mod not found at $GOMOD"
  exit 1
fi

# --- Extract current and next major version ---

CURRENT_MODULE=$(grep -E '^module ' "$GOMOD" | awk '{print $2}')
info "current module: $CURRENT_MODULE"

CURRENT_MAJOR=$(echo "$CURRENT_MODULE" | grep -oE '/v[0-9]+$' | grep -oE '[0-9]+' || echo "1")
NEXT_MAJOR=$((CURRENT_MAJOR + 1))

CURRENT_SUFFIX="/v${CURRENT_MAJOR}"
NEXT_SUFFIX="/v${NEXT_MAJOR}"

if [[ "$CURRENT_MAJOR" -eq 1 ]]; then
  CURRENT_PATH="$CURRENT_MODULE"
  NEXT_MODULE="${CURRENT_MODULE}/v2"
  NEXT_SUFFIX="/v2"
else
  CURRENT_PATH="$CURRENT_MODULE"
  NEXT_MODULE="${CURRENT_MODULE%${CURRENT_SUFFIX}}${NEXT_SUFFIX}"
fi

info "next module   : $NEXT_MODULE"

# --- Rewrite go.mod ---

step "Updating go.mod"
sed -i "s|^module ${CURRENT_PATH}$|module ${NEXT_MODULE}|" "$GOMOD"
success "go.mod updated"

# --- Rewrite all internal import paths ---

step "Rewriting import paths"
GO_FILES=$(find "$REPO_ROOT" -name "*.go" -not -path "*/vendor/*")
COUNT=0

while IFS= read -r file; do
  if grep -q "$CURRENT_PATH" "$file"; then
    sed -i "s|${CURRENT_PATH}|${NEXT_MODULE}|g" "$file"
    COUNT=$((COUNT + 1))
  fi
done <<< "$GO_FILES"

success "updated $COUNT .go file(s)"

# --- Verify the module still builds ---

step "Running go mod tidy"
cd "$REPO_ROOT" && go mod tidy
success "go mod tidy passed"
