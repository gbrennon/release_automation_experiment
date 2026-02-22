#!/usr/bin/env bash
# scripts/preflight.sh
#
# Validates the local environment before attempting a release.
# Exits non-zero on the first failure.
#
# Usage:
#   ./scripts/preflight.sh

set -euo pipefail

ERRORS=()

# --- Checks ---

check_main_branch() {
  local current_branch
  current_branch=$(git branch --show-current)
  if [[ "$current_branch" != "main" ]]; then
    ERRORS+=("Must be on 'main' branch (currently on: '$current_branch')")
  fi
}

check_clean_worktree() {
  if [[ -n "$(git status --porcelain)" ]]; then
    ERRORS+=("Working tree is not clean — commit or stash your changes first")
  fi
}

check_tool() {
  local cmd="$1"
  local hint="$2"
  if ! command -v "$cmd" &>/dev/null; then
    ERRORS+=("'$cmd' is not installed — $hint")
  fi
}

# --- Run ---

check_main_branch
check_clean_worktree
check_tool "gh" "see https://cli.github.com"
# git-cliff is NOT required locally — it runs in CI via changelog.yml

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Pre-flight checks failed:" >&2
  for err in "${ERRORS[@]}"; do
    echo "  ✗ $err" >&2
  done
  exit 1
fi

echo "✓ All pre-flight checks passed"
