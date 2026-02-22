# Release Automation

Automated semantic versioning, changelog generation, and GitHub Release creation for Go modules (v2+). Built to be validated in a single repo, then extracted into a shared reusable workflow.

---

## How it works

The release flow is split across two boundaries: **local** (developer machine) and **CI** (GitHub Actions). Each owns a distinct part of the process so neither has to trust the other to do its job.

```
Developer (local)                    GitHub Actions (CI)
─────────────────                    ───────────────────
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
  │   └─ e.g. rewrite go.mod module path on major bumps
  │
  ├─ generate CHANGELOG.md (git-cliff)
  │
  ├─ commit + push branch
  │
  └─ open PR (gh pr create)
       body = changelog for this version
                                          on: pull_request merged into main
                                            │
                                            ├─ extract version from branch name
                                            ├─ run pre-release hook (if present)
                                            ├─ create + push git tag
                                            ├─ generate release notes (git-cliff --latest)
                                            └─ create GitHub Release
```

---

## Repository layout

```
.cliff.toml                         # git-cliff config: commit parsers, changelog template
.github/workflows/
  release.yml                       # CI: triggers on release/v* PR merge
scripts/
  preflight.sh                      # validates local environment before release
  next-version.sh                   # computes next semver from latest git tag
  release.sh                        # orchestrates the full local release flow
  hooks/
    pre-release.sh                  # project-specific hook (Go: rewrites go.mod on major)
Makefile                            # thin entrypoint — delegates to scripts/
```

---

## Requirements

| Tool | Purpose | Install |
|---|---|---|
| Git | tag and branch operations | [git-scm.com](https://git-scm.com) |
| Make | task runner entrypoint | system package manager |
| GitHub CLI (`gh`) | open PRs and create releases | [cli.github.com](https://cli.github.com) |
| git-cliff | changelog generation | [git-cliff.org/docs/installation](https://git-cliff.org/docs/installation) |
| Go | required by the pre-release hook (`go mod tidy`) | [go.dev/dl](https://go.dev/dl) |

Authenticate the GitHub CLI before your first release:

```bash
gh auth login
```

---

## Usage

All release commands must be run from the `main` branch with a clean working tree.

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

On a major bump, `scripts/hooks/pre-release.sh` automatically rewrites the Go module path in `go.mod` and all internal import paths (e.g. `github.com/user/repo/v2` → `github.com/user/repo/v3`), then runs `go mod tidy` to verify the module still builds.

### Release candidates

Append `RC=1` to any target. The RC number is auto-incremented from the latest tag.

```bash
make release RC=1          # 1.2.3 → 1.2.4-rc1
make release-minor RC=1    # 1.2.3 → 1.3.0-rc1
make release-major RC=1    # 1.2.3 → 2.0.0-rc1

# If the latest tag is already v1.2.4-rc1:
make release RC=1          # → 1.2.4-rc2
```

RC releases are automatically marked as pre-releases on GitHub (any version containing `-` triggers this).

---

## Commit conventions

Changelog sections are driven by [Conventional Commits](https://www.conventionalcommits.org). The commit type prefix determines which section it appears under in `CHANGELOG.md` and the GitHub Release body.

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
chore(release): v1.3.0          ← generated automatically, do not write manually
```

The `chore(release): vX.Y.Z` commit is created by `release.sh` and should never be written manually.

---

## Script reference

### `scripts/preflight.sh`

Validates the local environment. Collects all failures before exiting so you can fix everything in one pass.

```bash
./scripts/preflight.sh
```

Checks: on `main` branch, clean worktree, `gh` installed, `git-cliff` installed.

### `scripts/next-version.sh`

Reads the latest git tag and computes the next version. Prints the bare version string to stdout (no `v` prefix). Safe to run standalone to preview without triggering a release.

```bash
./scripts/next-version.sh <patch|minor|major>
RC=1 ./scripts/next-version.sh patch    # appends -rc<N>

# Preview the next minor version:
$ ./scripts/next-version.sh minor
1.4.0
```

### `scripts/release.sh`

Orchestrates the full local release flow. Expects `preflight.sh` to have already passed. If it fails mid-flight, the release branch is automatically deleted and you are returned to `main`.

```bash
RC=<value> ./scripts/release.sh <patch|minor|major>
```

### `scripts/hooks/pre-release.sh`

Called by `release.sh` locally and by the CI workflow before the git tag is created. Receives `<bump>` and `<tag>` as positional arguments. Any files it modifies are included in the release commit.

```bash
# Called automatically — not meant to be run directly.
# Signature:
./scripts/hooks/pre-release.sh <bump> <tag>
# e.g.
./scripts/hooks/pre-release.sh major v3.0.0
```

For `patch` and `minor` bumps it exits immediately. For `major` it rewrites `go.mod` and all `.go` import paths, then verifies with `go mod tidy`.

---

## CI workflow

The workflow in `.github/workflows/release.yml` triggers **only** when a `release/v*` branch is merged into `main`. It does not run on other PRs or direct pushes.

### Steps

1. Derives the version and bump type from the merged branch name (`release/v1.3.0` → `v1.3.0`, bump=`minor`)
2. Runs `scripts/hooks/pre-release.sh` if present — same hook, same contract as local
3. Creates and pushes the git tag
4. Generates release notes via `git-cliff --latest --strip all`
5. Creates the GitHub Release with those notes as the body

### Why the hook runs in CI too

The pre-release hook may commit files (e.g. an updated `go.mod`). Those commits must land before the tag is pushed so they are included in the tagged tree. Running the hook only locally is not sufficient — it must also run in CI against the actual merged state of `main`.

### Bump type derivation in CI

The CI workflow has no bump input — it derives it from the version string:

| Version pattern | Derived bump |
|---|---|
| `vX.0.0` (minor=0, patch=0) | `major` |
| `vX.Y.0` (patch=0) | `minor` |
| anything else | `patch` |

---

## Changelog configuration

`git-cliff` is configured via `.cliff.toml`. Key settings:

- `unreleased = false` — only commits belonging to a tagged release are included. Unreleased commits between the latest tag and HEAD are never emitted.
- `filter_unmerged = true` — excludes commits not merged into the target branch.
- Tag pattern matches `v`-prefixed semver including prerelease suffixes: `v1.0.0`, `v1.0.0-rc1`, `v1.0.0-alpha`, etc.

To customise the changelog for a specific project, place a `.cliff.toml` in the repo root.

The CI workflow prefers the repo-local config over any shared fallback.

---

## Go module versioning (v2+)

Per the [Go module compatibility spec](https://go.dev/blog/v2-go-modules), a v2+ major version requires the module path to carry a `/vN` suffix. The pre-release hook handles this automatically on `make release-major`:

1. Reads the current module path from `go.mod`
2. Computes the next `/vN` suffix
3. Rewrites `go.mod`
4. Rewrites all internal `.go` import paths
5. Runs `go mod tidy` — if this fails, the release is aborted before any tag is created

For v1 → v2, the path goes from `github.com/user/repo` to `github.com/user/repo/v2`. For v2 → v3, from `.../v2` to `.../v3`, and so on.

---

## Future: shared reusable workflow

Once validated, the scripts and CI workflow can be moved to a dedicated repo (`gbrennon/release_automation_golang`) so any project can consume them without copy-pasting.

The reusable workflow uses `github.action_repository` to self-reference, so it works regardless of the repo name.

Consumer repos pin to a specific tag for stability:

```yaml
# .github/workflows/release.yml in any consumer repo
uses: gbrennon/release_automation_golang/.github/workflows/release.yml@v1.0.0
with:
  version: ${{ needs.prepare.outputs.version }}
  automation-ref: v1.0.0
secrets:
  token: ${{ secrets.GITHUB_TOKEN }}
```

Until that point, all files live in the project repo itself — no submodules, no external dependencies at runtime.
