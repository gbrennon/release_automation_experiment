.PHONY: test coverage check-coverage clean release release-minor release-major

all: test

# --- Release targets ---
#
# Bump patch version:  1.2.3 → 1.2.4
# Add RC=1 for a release candidate:  1.2.4-rc1, 1.2.4-rc2, ...
release:
	@./scripts/preflight.sh
	@RC=$(RC) ./scripts/release.sh patch

# Bump minor version:  1.2.3 → 1.3.0
release-minor:
	@./scripts/preflight.sh
	@RC=$(RC) ./scripts/release.sh minor

# Bump major version:  1.2.3 → 2.0.0  (rewrites go.mod module path)
release-major:
	@./scripts/preflight.sh
	@RC=$(RC) ./scripts/release.sh major

preflight:
	@./scripts/preflight.sh

# --- Dev targets ---

test:
	@go test ./...

coverage:
	@go test -coverprofile=coverage.out ./...
	@go tool cover -html=coverage.out -o coverage.html

check-coverage:
	@go test -coverprofile=coverage.out ./...
	@go tool cover -func=coverage.out

clean:
	@rm -f coverage.out coverage.html
