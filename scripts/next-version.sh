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

set -euo pipefail

# --- Args ---

BUMP="${1:-}"

if [[ -z "$BUMP" ]]; then
  echo "Usage: $0 <patch|minor|major>" >&2
  exit 1
fi

if [[ ! "$BUMP" =~ ^(patch|minor|major)$ ]]; then
  echo "Error: bump must be one of: patch, minor, major (got: '$BUMP')" >&2
  exit 1
fi

# --- Resolve latest tag ---

git fetch --tags --quiet

LATEST_TAG=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
LATEST_TAG="${LATEST_TAG:-v0.0.0}"

# Strip leading 'v' and split into base + prerelease
RAW="${LATEST_TAG#v}"
BASE_VERSION="${RAW%%-*}"                                               # e.g. 1.2.3
PRERELEASE=$(echo "$RAW" | grep -oE '(rc|alpha|beta|preview|dev)[0-9]*' || true)  # e.g. rc1

IFS='.' read -r MAJOR MINOR PATCH <<< "$BASE_VERSION"
MAJOR="${MAJOR:-0}"
MINOR="${MINOR:-0}"
PATCH="${PATCH:-0}"

# --- Apply bump ---

case "$BUMP" in
  patch) PATCH=$((PATCH + 1)) ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
esac

NEXT_VERSION="${MAJOR}.${MINOR}.${PATCH}"

# --- Append RC suffix if requested ---
#
# RC suffix format: rc<N> (no dot separator) — must match the semver pattern
# in .cliff.toml: (-(?P<prerelease>(rc|alpha|beta|preview|dev)\d*))?

if [[ -n "${RC:-}" ]]; then
  RC_NUM=$(echo "$PRERELEASE" | grep -oE '[0-9]+$' || echo "0")
  RC_NUM=$((RC_NUM + 1))
  NEXT_VERSION="${NEXT_VERSION}-rc${RC_NUM}"
fi

echo "$NEXT_VERSION"
