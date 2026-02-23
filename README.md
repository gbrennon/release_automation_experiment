# Release Automation

Automated semantic versioning, changelog generation, and release creation for Go modules (v2+).

The flow is split into two phases: **local** (developer machine) and **remote** (CI). The local phase creates the release branch and PR; CI handles changelog generation, tagging, and the release itself after merge.

Two CI backends are supported:

| Platform | Workflow files |
|---|---|
| GitHub | `.github/workflows/` + `scripts/` |
| Codeberg / Gitea | `.woodpecker/` |

---

## Release flow

```
Developer (local)                         CI (remote — after PR merge)
─────────────────                         ────────────────────────────
make release
  │
  ├─ preflight checks
  │   ├─ must be on main
  │   ├─ worktree must be clean
  │   ├─ gh CLI installed
  │   └─ git-cliff installed
  │
  ├─ compute next version
  │   └─ reads latest git tag → bumps semver
  │
  ├─ create branch release/vX.Y.Z
  │
  ├─ run pre-release hook (if present)
  │   └─ e.g. rewrite go.mod on major bumps
  │
  ├─ generate CHANGELOG.md (git-cliff)
  │
  ├─ commit + push branch
  │   └─ includes CHANGELOG.md
  │
  └─ open PR
      title: "chore(release): vX.Y.Z"
                                            on: pull_request opened/updated
                                              └─ update PR body with release
                                                 notes preview (git-cliff)

                                            on: PR merged into main
                                              ├─ create + push git tag vX.Y.Z
                                              └─ create GitHub / Gitea release
```

---

## Requirements

| Tool | Purpose | Install |
|---|---|---|
| Git | branch and tag operations | [git-scm.com](https://git-scm.com) |
| Make | task runner | system package manager |
| GitHub CLI (`gh`) | open PRs | [cli.github.com](https://cli.github.com) |
| git-cliff | changelog generation | [git-cliff.org/docs/installation](https://git-cliff.org/docs/installation) |
| Go | pre-release hook (`go mod tidy`) | [go.dev/dl](https://go.dev/dl) |

Authenticate the GitHub CLI before your first release:

```bash
gh auth login
```

---

## Usage

All release commands must run from the `main` branch with a clean working tree.

### Patch — `1.2.3 → 1.2.4`

```bash
make release
```

### Minor — `1.2.3 → 1.3.0`

```bash
make release-minor
```

### Major — `1.2.3 → 2.0.0`

```bash
make release-major
```

On a major bump, `scripts/hooks/pre-release.sh` automatically rewrites the Go module path in `go.mod` and all internal import paths (e.g. `github.com/user/repo/v2` → `github.com/user/repo/v3`), then runs `go mod tidy` to verify the build.

### Release candidates

Append `RC=1` to any target. The RC number auto-increments from the latest tag.

```bash
make release RC=1          # 1.2.3 → 1.2.4-rc1
make release-minor RC=1    # 1.2.3 → 1.3.0-rc1
make release-major RC=1    # 1.2.3 → 2.0.0-rc1

# If the latest tag is already v1.2.4-rc1:
make release RC=1          # → 1.2.4-rc2
```

RC releases are automatically marked as pre-releases (any version containing `-` triggers this).

---

## Commit conventions

Changelog sections are driven by [Conventional Commits](https://www.conventionalcommits.org). The commit type prefix determines which section appears in `CHANGELOG.md` and the release body.

| Prefix | Changelog section |
|---|---|
| `feat!` | Breaking Changes |
| `feat` | Features |
| `fix` | Bug Fixes |
| `refactor` | Refactoring |
| `docs` | Documentation |
| `test` | Testing |
| `build`, `ci` | Build / CI |
| anything else | Other Changes |

Examples:

```
feat: add support for batch processing
fix: handle nil pointer in middleware chain
feat!: remove deprecated Config.Timeout field
chore(release): v1.3.0          ← written by release.sh, never manually
```

---

## Repository layout

```
.cliff.toml                         # git-cliff config: commit parsers, changelog template
.github/workflows/
  changelog.yml                     # CI: PR preview — updates PR body with release notes
  release.yml                       # CI: post-merge — CHANGELOG.md, tag, GitHub Release
.woodpecker/
  changelog.yml                     # Codeberg equivalent of .github/workflows/changelog.yml
  release.yml                       # Codeberg equivalent of .github/workflows/release.yml
scripts/
  preflight.sh                      # validates local environment before release
  next-version.sh                   # computes next semver from latest git tag
  release.sh                        # orchestrates the full local release flow
  hooks/
    pre-release.sh                  # Go-specific: rewrites go.mod on major bumps
Makefile                            # thin entrypoint — delegates to scripts/
```

---

## Script reference

### `scripts/preflight.sh`

Validates the local environment. Collects all failures before exiting.

```bash
./scripts/preflight.sh
# or via Make:
make preflight
```

Checks: on `main` branch · clean worktree · `gh` installed · `git-cliff` installed.

### `scripts/next-version.sh`

Reads the latest git tag and prints the next version to stdout (no `v` prefix). Safe to run standalone to preview the next version without starting a release.

```bash
./scripts/next-version.sh patch       # 1.2.3 → 1.2.4
./scripts/next-version.sh minor       # 1.2.3 → 1.3.0
./scripts/next-version.sh major       # 1.2.3 → 2.0.0
RC=1 ./scripts/next-version.sh patch  # 1.2.3 → 1.2.4-rc1
```

### `scripts/release.sh`

Orchestrates the full local release flow. Expects `preflight.sh` to have already passed. On failure, the release branch is deleted and you are returned to `main`.

```bash
RC=<value> ./scripts/release.sh <patch|minor|major>
```

### `scripts/hooks/pre-release.sh`

Called by `release.sh` after the branch is created, before the commit. Receives `<bump>` and `<tag>` as arguments. Any files it modifies are included in the release commit.

For `patch` and `minor` bumps it exits immediately. For `major` it rewrites `go.mod` and all `.go` import paths, then verifies with `go mod tidy`.

---

## CI reference

### On pull request (`changelog.yml`)

Triggered when a PR is opened or updated. Skips non-`release/v*` branches.

1. Runs `git-cliff --tag vX.Y.Z --latest --strip all` to generate release notes for the commits on the branch.
2. Updates the PR body with those release notes via the GitHub / Gitea API.

### On merge to `main` (`release.yml`)

Triggered by a push to `main` whose commit message contains `chore(release): vX.Y.Z`.

1. Creates and pushes the git tag `vX.Y.Z`.
2. Runs `git-cliff --latest --strip all` to generate per-version release notes.
3. Creates the GitHub / Gitea release with those notes as the body.

`CHANGELOG.md` is already present in the commit — it was generated locally by `release.sh`.

---

## Changelog configuration

`git-cliff` is configured via `.cliff.toml`. Key settings:

- Tag pattern matches `v`-prefixed semver including prerelease suffixes: `v1.0.0`, `v1.0.0-rc1`, etc.
- `[skip ci]` commits (e.g. the CHANGELOG.md commit itself) are excluded from output.

To customise the changelog for a project, place a `.cliff.toml` in the repo root. Both CI backends prefer a repo-local config and fall back to the bundled `.woodpecker/.cliff.toml`.

---

## Go module versioning (v2+)

Per the [Go module compatibility spec](https://go.dev/blog/v2-go-modules), v2+ modules require a `/vN` suffix in the module path. The pre-release hook handles this automatically on `make release-major`:

1. Reads the current module path from `go.mod`
2. Computes the next `/vN` suffix
3. Rewrites `go.mod` and all internal `.go` import paths
4. Runs `go mod tidy` — failure aborts the release before any tag is created

| Transition | Module path |
|---|---|
| v1 → v2 | `github.com/user/repo` → `github.com/user/repo/v2` |
| v2 → v3 | `github.com/user/repo/v2` → `github.com/user/repo/v3` |

