#!/usr/bin/env bash
#
# Orchestrates a full release:
#   1. Computes the next version
#   2. Creates a release branch
#   3. Runs the pre-release hook (if present)
#   4. Generates CHANGELOG.md via git-cliff
#   5. Commits and pushes the branch
#   6. Opens a GitHub PR
#
# CHANGELOG.md is generated locally before the commit.
# git-cliff must be installed (checked by preflight.sh).
#
# Callers are expected to have run preflight.sh beforehand.
#
# Usage:
#   ./scripts/release.sh <bump>
#
# Arguments:
#   bump   One of: patch | minor | major
#
# Environment:
#   RC     If set, passed through to next-version.sh for rc<N> suffix.
#   DEBUG  If set to 1, enables bash trace output (set -x).
#
# Hooks:
#   scripts/hooks/pre-release.sh   Run after branch creation, before the commit.
#                                  Receives <bump> and <tag> as arguments.
#                                  Any files it modifies will be included in the
#                                  release commit.

set -euo pipefail
[[ "${DEBUG:-0}" == "1" ]] && set -x

# --- Helpers (all output to stderr so progress never pollutes captured stdout) ---

step()    { echo ""                  >&2; echo "▶ $*" >&2; }
info()    { echo "  · $*"            >&2; }
success() { echo "  ✓ $*"            >&2; }
fail()    { echo "  ✗ $*"            >&2; }

# --- Bootstrap ---

step "Initialising"
REPO_ROOT="$(git rev-parse --show-toplevel)"
SCRIPT_DIR="${REPO_ROOT}/scripts"
PRE_RELEASE_HOOK="${SCRIPT_DIR}/hooks/pre-release.sh"
info "repo root : $REPO_ROOT"
info "script dir: $SCRIPT_DIR"

# --- Args ---

BUMP="${1:-}"

if [[ -z "$BUMP" ]]; then
  echo "Usage: $0 <patch|minor|major>" >&2
  exit 1
fi

# --- Compute next version ---

step "Computing next version"
info "bump type : $BUMP"
info "RC suffix : ${RC:-<none>}"
info "fetching remote tags..."
git fetch --tags --quiet
NEXT_VERSION=$(RC="${RC:-}" "$SCRIPT_DIR/next-version.sh" "$BUMP")
TAG="v${NEXT_VERSION}"
BRANCH_NAME="release/${TAG}"

info "latest tag: $(git tag --sort=-v:refname | grep -E '^v[0-9]' | head -n1 || echo '<none>')"
success "next version : $TAG"
success "release branch: $BRANCH_NAME"

# --- Guard: abort if remote branch or open PR already exists ---

step "Checking for existing release"
if git ls-remote --exit-code origin "refs/heads/$BRANCH_NAME" &>/dev/null; then
  fail "Remote branch '$BRANCH_NAME' already exists."
  fail "Close/delete the existing PR and branch, then re-run."
  exit 1
fi
if gh pr list --repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)" \
     --head "$BRANCH_NAME" --state open --json number -q '.[0].number' \
   | grep -q '^[0-9]'; then
  fail "An open PR for '$BRANCH_NAME' already exists."
  fail "Close it and delete the remote branch, then re-run."
  exit 1
fi
success "no existing release branch or PR found"

# --- Create release branch ---

step "Creating release branch"
git checkout -b "$BRANCH_NAME"
success "on branch $BRANCH_NAME"

# Restore original branch on failure
cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    fail "Release failed — cleaning up branch '$BRANCH_NAME'"
    git checkout main
    git branch -D "$BRANCH_NAME" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# --- Run pre-release hook (if present) ---

step "Pre-release hook"
if [[ -x "$PRE_RELEASE_HOOK" ]]; then
  info "running $PRE_RELEASE_HOOK $BUMP $TAG"
  "$PRE_RELEASE_HOOK" "$BUMP" "$TAG"
  success "hook completed"
else
  info "no executable hook at $PRE_RELEASE_HOOK — skipping"
fi

# --- Generate CHANGELOG.md ---

step "Generating CHANGELOG.md"
CLIFF_CONFIG="${REPO_ROOT}/.cliff.toml"
info "config : $CLIFF_CONFIG"
info "tag    : $TAG"
git-cliff --config "$CLIFF_CONFIG" --tag "$TAG" -vvv > "${REPO_ROOT}/CHANGELOG.md"
success "CHANGELOG.md written"

# --- Commit and push ---

step "Committing and pushing"
git add --all
git status --short
git commit --allow-empty -m "chore(release): ${TAG}"
info "pushing $BRANCH_NAME..."
git push origin "$BRANCH_NAME"
success "branch pushed"

# --- Ensure the 'release' label exists ---

step "Ensuring 'release' label exists"
gh label create release \
  --description "Release PR" \
  --color 0075ca \
  2>/dev/null && success "label created" || info "label already exists"

# --- Open GitHub PR ---

step "Opening PR"
PR_URL=$(gh pr create \
  --title "chore(release): ${TAG}" \
  --body  "_Release notes will be posted by CI shortly..._" \
  --base  main \
  --head  "$BRANCH_NAME" \
  --label release)
success "PR opened: $PR_URL"

# --- Return to main ---

step "Cleaning up"
git checkout main
git branch -D "$BRANCH_NAME"
info "returned to main, local branch deleted"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ Release PR ready: $TAG"
echo "  $PR_URL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
