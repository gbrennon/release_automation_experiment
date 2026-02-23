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

check_gitea_token() {
  local token_file="${HOME}/.config/gitea/token"
  if [[ -z "${GITEA_TOKEN:-}" ]] && [[ ! -f "$token_file" ]]; then
    ERRORS+=("GITEA_TOKEN is not set and ${token_file} does not exist — export GITEA_TOKEN or store your token there")
  fi
}

check_gitea_reachable() {
  local host="${GITEA_HOST:-codeberg.org}"
  if ! curl -sSf "https://${host}/api/swagger" -o /dev/null 2>/dev/null; then
    ERRORS+=("Cannot reach https://${host} — check your network or set GITEA_HOST")
  fi
}

# --- Run ---

check_main_branch
check_clean_worktree
check_tool "curl" "install curl (https://curl.se)"
check_tool "jq"   "install jq (https://jqlang.github.io/jq/)"
# git-cliff is NOT required locally — it runs in CI via changelog.yml

check_gitea_token
check_gitea_reachable

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Pre-flight checks failed:" >&2
  for err in "${ERRORS[@]}"; do
    echo "  ✗ $err" >&2
  done
  exit 1
fi

echo "✓ All pre-flight checks passed"
