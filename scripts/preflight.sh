#!/usr/bin/env bash
#
# Validates the local environment before attempting a release.
# Exits non-zero on the first failure.
#
# Usage:
#   ./scripts/preflight.sh

set -euo pipefail

# --- Helpers ---

step()    { echo ""        >&2; echo "▶ $*" >&2; }
info()    { echo "  · $*"  >&2; }
success() { echo "  ✓ $*"  >&2; }
fail()    { echo "  ✗ $*"  >&2; }

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

step "Preflight checks"

info "checking branch..."
check_main_branch

info "checking worktree..."
check_clean_worktree

info "checking required tools..."
check_tool "gh"        "see https://cli.github.com"
check_tool "git-cliff" "see https://git-cliff.org/docs/installation"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "" >&2
  fail "Pre-flight checks failed:"
  for err in "${ERRORS[@]}"; do
    fail "$err"
  done
  exit 1
fi

success "all pre-flight checks passed"
