#!/usr/bin/env bash
set -euo pipefail

# 📌 Usage & Notes
if [[ "${1:-}" != "--project" || -z "${2:-}" ]]; then
  cat <<'USAGE'
Usage: generate_project.sh --project <project-name> [--type <docker|node|python|terraform|go>]

Types:
  docker     Minimal Dockerfile-only repo.
  node       Minimal Node app with package.json and index.js.
  python     Minimal Python app with app.py.
  terraform  Minimal main.tf with required_version.
  go         Minimal Go CLI (cmd/<app>/main.go, go.mod, Makefile, .golangci.yml).

Important:
  - Go projects do NOT include Dockerfile or .dockerignore by default.
    Reason: the Go template targets native CLI builds and Homebrew releases.
    If you want containers later, add a Dockerfile yourself or rerun with --type docker.
USAGE
  exit 1
fi

# --- GitHub authentication check ---
if ! gh auth status 2>&1 | grep -q "Logged in to github.com"; then
  echo "❌ GitHub CLI is not authenticated."
  echo "👉 Run: gh auth login"
  exit 1
fi

PROJECT_NAME="$2"
TYPE="${4:-}"  # Optional --type argument
SANITY_CHECK_CMD="sanity_check"
DEFAULT_GITIGNORE="/Users/raymon.epping/.gitignore_global"
DEFAULT_DOCKERIGNORE="$HOME/.dockerignore_global"
COMMIT_SCRIPT_NAME="commit_gh"
COMMIT_SCRIPT_FALLBACK="$HOME/bin/commit_gh"

# 🔧 Prerequisites
for bin in git gh; do
  if ! command -v "$bin" &>/dev/null; then
    echo "❌ Required tool missing: $bin"
    exit 1
  fi
done

# 🏗️ Create structure
mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME"

# --- Language/Type specific bootstraps ---
case "$TYPE" in
  terraform)
    echo "🌱 Creating minimal main.tf with required_version"
    cat > main.tf <<'EOF'
terraform {
  required_version = ">= 1.0.0"
}
EOF
    ;;
  node)
    echo "🌱 Creating minimal Node scaffold"
    cat > package.json <<'EOF'
{
  "name": "app",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "start": "node index.js",
    "test": "node -e \"console.log('ok')\""
  }
}
EOF
    echo "console.log('hello');" > index.js
    ;;
  python)
    echo "🌱 Creating minimal Python scaffold"
    echo "print('hello')" > app.py
    ;;
  docker)
    echo "🌱 Creating minimal Dockerfile"
    cat > Dockerfile <<'EOF'
FROM alpine:3
CMD ["sh","-c","echo hello"]
EOF
    ;;
  go)
    echo "🌱 Creating minimal Go scaffold (no Docker)"
    GO_VERSION="${GO_VERSION:-1.22}"
    GOMODULE_PATH="github.com/raymonepping/${PROJECT_NAME}"

    # go.mod
    cat > go.mod <<EOF
module ${GOMODULE_PATH}

go ${GO_VERSION}
EOF

    # main.go
    mkdir -p cmd/${PROJECT_NAME}
    cat > cmd/${PROJECT_NAME}/main.go <<'EOF'
package main

import (
	"fmt"
	"os"
)

var (
	Version = "0.1.0"
)

func main() {
	if len(os.Args) > 1 && (os.Args[1] == "-V" || os.Args[1] == "--version") {
		fmt.Println(Version)
		return
	}
	fmt.Println("hello")
	if v := os.Getenv("APP_ENV"); v != "" {
		fmt.Printf("APP_ENV=%s\n", v)
	}
}
EOF

    # Makefile
    cat > Makefile <<'EOF'
APP := $(shell basename $(CURDIR))
GOFLAGS := -trimpath
LDFLAGS := -s -w -X 'main.Version=$(shell git describe --tags --always 2>/dev/null || echo dev)'

.PHONY: all build run test fmt lint clean

all: build

build:
	@mkdir -p bin
	go build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o bin/$(APP) ./cmd/$(APP)

run: build
	./bin/$(APP)

test:
	go test ./...

fmt:
	go fmt ./...

lint:
	@if command -v golangci-lint >/dev/null 2>&1; then golangci-lint run ./...; else echo "golangci-lint not installed, skipping"; fi

clean:
	rm -rf bin
EOF

    # .golangci.yml
    cat > .golangci.yml <<'EOF'
run:
  timeout: 3m
linters:
  enable:
    - govet
    - staticcheck
    - gosimple
    - ineffassign
    - errcheck
issues:
  exclude-use-default: false
EOF
    ;;
  "")
    ;;
  *)
    echo "⚠️ Unknown project type '$TYPE'. Proceeding with generic scaffold."
    ;;
esac

echo "📁 Created project: $PROJECT_NAME"

# 📄 .gitignore (fallback logic)
if [[ -f "$DEFAULT_GITIGNORE" ]]; then
  cp "$DEFAULT_GITIGNORE" .gitignore
else
  echo "# Auto-generated .gitignore" > .gitignore
fi

# Add Go ignores if type is go
if [[ "$TYPE" == "go" ]]; then
  cat >> .gitignore <<'EOF'

# Go
bin/
*.test
*.out
*.log
coverage.*
EOF
fi

# 📄 .dockerignore
# For Go we SKIP creating .dockerignore and any Dockerfile on purpose.
if [[ "$TYPE" != "go" ]]; then
  if [[ -f "$DEFAULT_DOCKERIGNORE" ]]; then
    echo "📁 Using global .dockerignore from $DEFAULT_DOCKERIGNORE"
    cp "$DEFAULT_DOCKERIGNORE" .dockerignore
  else
    echo "ℹ️ No default .dockerignore found. Creating minimal one."
    cat > .dockerignore <<'EOF'
.git
.github
bin
*.log
*.out
node_modules
__pycache__
EOF
  fi
fi

# ✅ Validate resulting ignore files (quiet mode)
if command -v validate_ignore &>/dev/null; then
  echo ""
  echo "🔎 Running post-generation validation on ignore files..."
  SANITY_MD="sanity_check.md" validate_ignore --quiet || true
  echo ""
else
  echo "ℹ️ 'validate_ignore' command not found — skipping validation"
  echo ""
fi

# 📄 LICENSE + README
curl -s https://www.gnu.org/licenses/gpl-3.0.txt > LICENSE

if [[ "$TYPE" == "go" ]]; then
  cat > README.md <<EOF
# $PROJECT_NAME

Go CLI scaffold.

## Why no Docker here
This template targets native Go binaries and Homebrew releases.
Add a Dockerfile later only if you plan to run this CLI in containers.

## Quickstart
make build
./bin/$PROJECT_NAME -V

EOF
else
  cat > README.md <<EOF
# $PROJECT_NAME

Auto-scaffolded project.

## Quickstart

EOF
fi

touch .env

# 📦 Dependabot config
mkdir -p .github
DEPENDABOT_FILE=".github/dependabot.yml"

case "$TYPE" in
  terraform)
    cat > "$DEPENDABOT_FILE" <<'EOF'
version: 2
updates:
  - package-ecosystem: "terraform"
    directory: "/"
    schedule:
      interval: "weekly"
EOF
    ;;
  node)
    cat > "$DEPENDABOT_FILE" <<'EOF'
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    commit-message:
      prefix: "deps"
      include: "scope"
EOF
    ;;
  docker)
    cat > "$DEPENDABOT_FILE" <<'EOF'
version: 2
updates:
  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "weekly"
    commit-message:
      prefix: "deps"
      include: "scope"
EOF
    ;;
  python)
    cat > "$DEPENDABOT_FILE" <<'EOF'
version: 2
updates:
  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "weekly"
    commit-message:
      prefix: "deps"
      include: "scope"
EOF
    ;;
  go)
    cat > "$DEPENDABOT_FILE" <<'EOF'
version: 2
updates:
  - package-ecosystem: "gomod"
    directory: "/"
    schedule:
      interval: "weekly"
    commit-message:
      prefix: "deps"
      include: "scope"
EOF
    ;;
  *)
    echo "ℹ️ Skipping dependabot config for unknown type."
    ;;
esac

echo "🔐 Added .github/dependabot.yml"

# 📄 Type-specific scan_on_pr.yml workflow
if [[ -n "$TYPE" ]]; then
  SCAN_SOURCE_FILE="$HOME/.${TYPE}_scan_on_pr.yml"
  SCAN_TARGET_DIR=".github/workflows"
  SCAN_TARGET_FILE="${SCAN_TARGET_DIR}/scan_on_pr.yml"
  mkdir -p "$SCAN_TARGET_DIR"
  if [[ -f "$SCAN_SOURCE_FILE" ]]; then
    cp "$SCAN_SOURCE_FILE" "$SCAN_TARGET_FILE"
    echo "📄 Added $TYPE scan workflow to $SCAN_TARGET_FILE"
  else
    echo "ℹ️ Missing scan workflow template: $SCAN_SOURCE_FILE — skipping"
  fi
fi

# 📜 Optional commit script
if command -v "$COMMIT_SCRIPT_NAME" &>/dev/null; then
  echo "✅ Using global $COMMIT_SCRIPT_NAME"
elif [[ -x "$COMMIT_SCRIPT_FALLBACK" ]]; then
  cp "$COMMIT_SCRIPT_FALLBACK" ./
  echo "✅ Copied fallback $COMMIT_SCRIPT_NAME"
else
  echo "ℹ️ $COMMIT_SCRIPT_NAME not available"
fi

# 🧪 Run sanity_check
if command -v "$SANITY_CHECK_CMD" &>/dev/null; then
  echo "🧪 Running sanity_check..."
  find . -type f \( -name "*.sh" -o -name "*.py" -o -name "*.js" -o -name "*.tf" -o -name "Dockerfile" -o -name "*.go" \) \
    -exec "$SANITY_CHECK_CMD" --fix --report {} +
else
  echo "ℹ️ $SANITY_CHECK_CMD not found — skipping"
fi

# 🌀 Git + GitHub
git init

# 🪝 Git hook for sanity_check
HOOK_PATH=".git/hooks/pre-commit"
if command -v "$SANITY_CHECK_CMD" &>/dev/null; then
  echo "🪝 Installing pre-commit git hook..."
  cat > "$HOOK_PATH" <<'EOF'
#!/bin/bash
set -euo pipefail
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.sh$|\.py$|\.js$|\.tf$|Dockerfile$|\.go$' || true)
if [[ -n "$STAGED_FILES" ]]; then
  echo "🔍 Pre-commit: running sanity_check on staged files..."
  echo "$STAGED_FILES" | xargs sanity_check --fix --quiet
fi
EOF
  chmod +x "$HOOK_PATH"
else
  echo "ℹ️ sanity_check not available, skipping git hook setup"
fi

git add .
git commit -m "Initial commit for $PROJECT_NAME"
gh repo create "$PROJECT_NAME" --public --source=. --remote=origin --push
git branch -M main
git push -u origin main

# 🚀 Optional: Trigger scan_on_pr workflow (if it exists)
if gh workflow list | grep -q "scan_on_pr"; then
  echo "🌀 Triggering scan_on_pr GitHub Action workflow..."
  gh workflow run scan_on_pr.yml || echo "ℹ️ Failed to trigger workflow"
else
  echo "ℹ️ scan_on_pr.yml workflow not found in repo — skipping workflow run"
fi

# 📌 Optional: Trigger PR-based scan
if [[ -n "$TYPE" && -x "$(command -v trigger_git_scan)" ]]; then
  echo ""
  echo "🚀 Initiating GitHub PR scan via trigger_git_scan..."
  trigger_git_scan || echo "ℹ️ trigger_git_scan failed"
else
  echo "ℹ️ Skipping trigger_git_scan — not enabled or missing."
fi

echo -e "\n✅ Project '$PROJECT_NAME' scaffolded, sanity-checked, and pushed to GitHub!"

# 🌳 Folder tree
if command -v folder_tree &>/dev/null; then
  echo ""
  echo "🌳 Generating FOLDER_TREE.md for $PROJECT_NAME..."
  folder_tree --preset node,nuxt --output markdown "$PWD" || echo "ℹ️ folder_tree failed"
else
  echo "ℹ️ folder_tree not found — skipping FOLDER_TREE.md generation"
fi

echo -e "\n🎉 All done!"
