#!/usr/bin/env bash
# scripts/next-version.sh
#
# Computes the next semantic version based on the latest git tag and a bump type.
# Prints the bare version string (no 'v' prefix) to stdout so callers can capture it.
#
# Usage:
#   ./scripts/next-version.sh <bump>
#
# Arguments:
#   bump   One of: patch | minor | major
#
# Environment:
#   RC     If set to any non-empty value, appends an -rc<N> prerelease suffix.
#          N is auto-incremented from the current tag's rc number (or starts at 1).
#
# Examples:
#   ./scripts/next-version.sh patch          # 1.2.3 → 1.2.4
#   ./scripts/next-version.sh minor          # 1.2.3 → 1.3.0
#   ./scripts/next-version.sh major          # 1.2.3 → 2.0.0
#   RC=1 ./scripts/next-version.sh patch     # 1.2.3 → 1.2.4-rc1
#   RC=1 ./scripts/next-version.sh patch     # 1.2.4-rc1 → 1.2.4-rc2
#
# NOTE: does not fetch from remote. The caller is responsible for running
#       git fetch --tags before calling this script.

set -euo pipefail

# --- Helpers (stderr only — stdout is reserved for the version string) ---

step()    { echo ""        >&2; echo "▶ $*" >&2; }
info()    { echo "  · $*"  >&2; }
success() { echo "  ✓ $*"  >&2; }
fail()    { echo "  ✗ $*"  >&2; }

# --- Args ---

step "Parsing arguments"

BUMP="${1:-}"

if [[ -z "$BUMP" ]]; then
  fail "Usage: $0 <patch|minor|major>"
  exit 1
fi

if [[ ! "$BUMP" =~ ^(patch|minor|major)$ ]]; then
  fail "bump must be one of: patch, minor, major (got: '$BUMP')"
  exit 1
fi

info "bump: $BUMP"
info "RC  : ${RC:-<none>}"

# --- Resolve latest local tag ---

step "Resolving latest tag"

LATEST_TAG=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
LATEST_TAG="${LATEST_TAG:-v0.0.0}"
info "latest tag: $LATEST_TAG"

# Strip leading 'v' and split into base + prerelease
RAW="${LATEST_TAG#v}"
BASE_VERSION="${RAW%%-*}"
PRERELEASE=$(echo "$RAW" | grep -oE '(rc|alpha|beta|preview|dev)[0-9]*' || true)

IFS='.' read -r MAJOR MINOR PATCH <<< "$BASE_VERSION"
MAJOR="${MAJOR:-0}"
MINOR="${MINOR:-0}"
PATCH="${PATCH:-0}"

# --- Apply bump ---

step "Applying $BUMP bump"

case "$BUMP" in
  patch) PATCH=$((PATCH + 1)) ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
esac

NEXT_VERSION="${MAJOR}.${MINOR}.${PATCH}"

# --- Append RC suffix if requested ---

if [[ -n "${RC:-}" ]]; then
  RC_NUM=$(echo "$PRERELEASE" | grep -oE '[0-9]+$' || echo "0")
  RC_NUM=$((RC_NUM + 1))
  NEXT_VERSION="${NEXT_VERSION}-rc${RC_NUM}"
  info "RC suffix applied: -rc${RC_NUM}"
fi

success "next version: v${NEXT_VERSION}"

# Print bare version to stdout for callers to capture
echo "$NEXT_VERSION"
