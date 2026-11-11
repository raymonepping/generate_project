#!/usr/bin/env bash
set -euo pipefail

# 📌 Usage & Notes
usage() {
  cat <<'USAGE'
Usage:
  generate_project --project <name> [--type <docker|podman|node|python|terraform|go>]
                   [--prefix <prefix>] [--private] [--no-github] [--no-claude]
                   [--claude-template <dir>] [--no-codex] [--codex-template <dir>]
  generate_project --claude-only [<existing-project-dir>] [--prefix <prefix>]
  generate_project --codex-only [<existing-project-dir>] [--type <type>] [--prefix <prefix>]
  generate_project --project <existing-project-dir> --codex-only [--prefix <prefix>]

Options:
  --project <name>          Create ./<name>, or add missing type files to an existing project.
  --type <type>             docker, podman, node, python, terraform or go; existing files are preserved.
  --prefix <prefix>         Resource prefix for containers, VMs and namespaces (e.g. srot or srot-).
                            Written into assistant instructions to scope resource operations.
  --private                 Create the GitHub repository as private (default: public).
  --no-github               Create and commit locally only; skip GitHub.
  --no-claude               Do not add a .claude folder.
  --claude-template <dir>   Template for .claude (default: ~/.config/generate_project/claude,
                            or $GENERATE_PROJECT_CLAUDE_TEMPLATE).
  --claude-only [<dir>]     Add or repair .claude in an existing project (default: current dir).
                            Never overwrites existing files; replaces broken skill links.
  --no-codex                Do not add Codex instructions, skills or config.
  --codex-template <dir>    Codex template (default: ~/.config/generate_project/codex,
                            then bundled tpl/codex; override: $GENERATE_PROJECT_CODEX_TEMPLATE).
  --codex-only [<dir>]      Add or repair Codex support in an existing project.
                            Preserves existing files; --type sets starter commands.
                            With --project <dir>, retrofit that existing directory.
                            A positional directory and --project cannot be combined.
  -h, --help                Show this help.
  --version                 Show the installed generate_project version.

The .claude folder gets agents/, skills/, settings.local.json and a starter CLAUDE.md.
Codex gets root AGENTS.md, .agents/skills/ and optional .codex/config.toml.
AI folders and AGENTS.md / AGENTS.override.md are added to .gitignore,
.dockerignore and ~/.gitignore_global, and the first commit refuses to include them.

Types:
  docker     Minimal Dockerfile-only repo.
  podman     Podman-first Containerfile and Makefile (build, run, clean).
  node       Minimal Node app with package.json and index.js.
  python     Minimal Python app with app.py.
  terraform  Minimal main.tf with required_version.
  go         Minimal Go CLI (cmd/<app>/main.go, go.mod, Makefile, .golangci.yml).
             Go projects do NOT include a Dockerfile or .dockerignore: the template targets
             native CLI builds and Homebrew releases.
USAGE
}

PROJECT_NAME=""
TYPE=""
VISIBILITY="public"
USE_GITHUB=true
USE_CLAUDE=true
USE_CODEX=true
CODEX_ONLY=false
CODEX_ONLY_DIR="."
CODEX_ONLY_DIR_SET=false
CLAUDE_ONLY=false
CLAUDE_ONLY_DIR="."
CLAUDE_ONLY_DIR_SET=false
PREFIX=""
CLAUDE_TEMPLATE="${GENERATE_PROJECT_CLAUDE_TEMPLATE:-$HOME/.config/generate_project/claude}"

# Resolve bundled assets before entering the generated project.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLED_CODEX_TEMPLATE="$SCRIPT_DIR/../tpl/codex"
VERSION="unknown"
for version_file in "$SCRIPT_DIR/.version" "$SCRIPT_DIR/../.version"; do
  if [[ -f "$version_file" ]]; then
    IFS= read -r VERSION < "$version_file"
    break
  fi
done
CODEX_TEMPLATE="${GENERATE_PROJECT_CODEX_TEMPLATE:-$HOME/.config/generate_project/codex}"
if [[ -z "${GENERATE_PROJECT_CODEX_TEMPLATE:-}" && ! -d "$CODEX_TEMPLATE" && -d "$BUNDLED_CODEX_TEMPLATE" ]]; then
  CODEX_TEMPLATE="$BUNDLED_CODEX_TEMPLATE"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT_NAME="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --type) TYPE="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --prefix) PREFIX="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --private) VISIBILITY="private"; shift ;;
    --public) VISIBILITY="public"; shift ;;
    --no-github) USE_GITHUB=false; shift ;;
    --no-claude) USE_CLAUDE=false; shift ;;
    --no-codex) USE_CODEX=false; shift ;;
    --codex-template) CODEX_TEMPLATE="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --codex-only)
      CODEX_ONLY=true
      if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then CODEX_ONLY_DIR="$2"; CODEX_ONLY_DIR_SET=true; shift 2; else shift; fi
      ;;
    --claude-template) CLAUDE_TEMPLATE="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --version) printf 'generate_project %s\n' "$VERSION"; exit 0 ;;
    --claude-only)
      CLAUDE_ONLY=true
      if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then CLAUDE_ONLY_DIR="$2"; CLAUDE_ONLY_DIR_SET=true; shift 2; else shift; fi
      ;;
    -h|--help) usage; exit 0 ;;
    *)
      # In --claude-only mode the project folder may follow other options.
      if [[ "$CLAUDE_ONLY" == true && "$CLAUDE_ONLY_DIR_SET" == false && "${1:0:1}" != "-" ]]; then
        CLAUDE_ONLY_DIR="$1"; CLAUDE_ONLY_DIR_SET=true; shift
      elif [[ "$CODEX_ONLY" == true && "$CODEX_ONLY_DIR_SET" == false && "${1:0:1}" != "-" ]]; then
        CODEX_ONLY_DIR="$1"; CODEX_ONLY_DIR_SET=true; shift
      else
        echo "❌ Unknown argument: $1"; usage; exit 1
      fi
      ;;
  esac
done

if [[ "$CLAUDE_ONLY" == true && "$CODEX_ONLY" == true ]]; then
  echo "❌ Use --claude-only and --codex-only separately."
  exit 1
fi
if [[ "$CODEX_ONLY" == true && "$USE_CODEX" == false ]]; then
  echo "❌ --codex-only cannot be combined with --no-codex."
  exit 1
fi
# In retrofit mode, --project names the existing target, never the parent cwd.
# Reject two target arguments, even an explicit ".", rather than guessing.
if [[ -n "$PROJECT_NAME" ]]; then
  if [[ "$CODEX_ONLY" == true ]]; then
    if [[ "$CODEX_ONLY_DIR_SET" == true ]]; then
      echo "❌ Use either --project <dir> or --codex-only <dir>, not both."
      exit 1
    fi
    CODEX_ONLY_DIR="$PROJECT_NAME"
  elif [[ "$CLAUDE_ONLY" == true ]]; then
    if [[ "$CLAUDE_ONLY_DIR_SET" == true ]]; then
      echo "❌ Use either --project <dir> or --claude-only <dir>, not both."
      exit 1
    fi
    CLAUDE_ONLY_DIR="$PROJECT_NAME"
  fi
fi

# Custom template paths may be relative to the invocation directory.
if [[ -d "$CODEX_TEMPLATE" ]]; then CODEX_TEMPLATE="$(cd "$CODEX_TEMPLATE" && pwd)"; fi

# A new Podman scaffold needs a concrete, project-scoped resource prefix even
# when the caller omits --prefix. Normalize its project name to a safe default.
if [[ "$TYPE" == "podman" && -z "$PREFIX" && "$CODEX_ONLY" != true && "$CLAUDE_ONLY" != true && ( ! -d "$PROJECT_NAME" || -z "$(ls -A "$PROJECT_NAME" 2>/dev/null)" ) ]]; then
  PREFIX="$(printf '%s' "$PROJECT_NAME" | LC_ALL=C tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
  [[ "$PREFIX" =~ ^[a-z] ]] || PREFIX="p${PREFIX}"
  PREFIX="${PREFIX:0:12}"
  echo "ℹ️ Using project-derived Podman resource prefix: ${PREFIX}- (check for collisions before use)"
fi

# Prefix: lowercase letters and digits, starting with a letter, always ending in "-".
if [[ -n "$PREFIX" ]]; then
  PREFIX="${PREFIX%-}"
  if [[ ! "$PREFIX" =~ ^[a-z][a-z0-9]{0,11}$ ]]; then
    echo "❌ --prefix must be 1-12 lowercase letters or digits, starting with a letter (e.g. srot or srot-)."
    exit 1
  fi
  PREFIX="${PREFIX}-"
fi

SANITY_CHECK_CMD="sanity_check"
DEFAULT_GITIGNORE="$HOME/.gitignore_global"
DEFAULT_DOCKERIGNORE="$HOME/.dockerignore_global"
COMMIT_SCRIPT_NAME="commit_gh"
COMMIT_SCRIPT_FALLBACK="$HOME/bin/commit_gh"
# Local AI tooling: never committed, never sent into image builds.
AI_TOOL_DIRS=(.claude/ .agents/ .codex/ .impeccable/ AGENTS.md AGENTS.override.md)

# Append the AI tooling block to an ignore file, once.
ensure_ai_ignored() {
  local file="$1" missing=() entry
  [[ -f "$file" ]] || touch "$file"
  for entry in "${AI_TOOL_DIRS[@]}"; do
    grep -qxF "$entry" "$file" || missing+=("$entry")
  done
  [[ ${#missing[@]} -eq 0 ]] && return 0
  {
    printf '\n# AI assistant tooling (local only)\n'
    printf '%s\n' "${missing[@]}"
  } >> "$file"
  echo "🙈 Ignored ${missing[*]} in $file"
}

# Starter commands per project type, for both assistants.
# shellcheck disable=SC2016
project_commands() {
  case "$1" in
    node) echo '- Run: `npm start`. Test: `npm test`.' ;;
    python) echo '- Run: `python app.py`.' ;;
    terraform) echo '- Check: `terraform fmt -check`, `terraform init -backend=false && terraform validate`.' ;;
    docker) echo '- Build: `podman build --format docker -t <name> .` (images must be arm64).' ;;
    podman) echo '- Check Podman with `make check`; build with `make build`, run with `make run`, and remove this project image with `make clean`.' ;;
    go) echo '- Build: `make build`. Test: `make test`. Lint: `make lint`.' ;;
    *) echo '- Commands: <how to run, test and lint this project>.' ;;
  esac
}

# Existing project type additions never replace files already owned by the repo.
type_file_available() {
  local path="$1"
  if [[ "$TYPE_RETROFIT" == true && ( -e "$path" || -L "$path" ) ]]; then
    echo "↪ Keeping existing $path"
    return 1
  fi
  return 0
}

# The instruction line that states the resource prefix, or asks for one.
PREFIX_MARKER="- Resource prefix:"
# shellcheck disable=SC2016
project_prefix_line() {
  if [[ -n "$PREFIX" ]]; then
    printf '%s `%s`. Filter every podman, multipass and oc command by it; never touch resources with another prefix.\n' "$PREFIX_MARKER" "$PREFIX"
  else
    printf '%s <none yet: choose one, e.g. `abc-`, and record it here>.\n' "$PREFIX_MARKER"
  fi
}

# Record the prefix without requiring a particular instruction-file layout.
# Prefer the Stack line, then Operate, then append an Operate section.
# A file that already names a prefix is left alone.
record_prefix() {
  local file="$1" line current tmp
  [[ -n "$PREFIX" && -f "$file" ]] || return 0
  line="$(project_prefix_line)"
  current="$(grep -F -- "$PREFIX_MARKER" "$file" | head -1 || true)"
  if [[ "$current" == "$line" ]]; then
    return 0
  elif [[ -n "$current" && "$current" != *"<none yet"* ]]; then
    echo "⚠️ $file already names a prefix; left unchanged: $current"
    return 0
  fi
  tmp="$(mktemp)"
  if [[ -n "$current" ]]; then
    awk -v m="$PREFIX_MARKER" -v l="$line" 'index($0, m) == 1 && !done { print l; done = 1; next } { print }' "$file" > "$tmp"
  elif grep -q '^- Stack:' "$file"; then
    awk -v l="$line" '{ print } /^- Stack:/ && !done { print l; done = 1 }' "$file" > "$tmp"
  elif grep -Eq '^## Operate[[:space:]]*$' "$file"; then
    awk -v l="$line" '{ print } /^## Operate[[:space:]]*$/ && !done { print ""; print l; done = 1 }' "$file" > "$tmp"
  else
    cat "$file" > "$tmp"
    printf '\n\n## Operate\n\n%s\n' "$line" >> "$tmp"
  fi
  cat "$tmp" > "$file" && rm -f -- "$tmp"
  echo "🏷️ Recorded prefix $PREFIX in $file"
}

# Copy the .claude template into a project. Existing files are kept; a skill that is
# a broken link or a stub file (left over from copying symlinks) is replaced.
install_claude_dir() {
  local dir="$1" name="$2" type="${3:-}" item target added=0 repaired=0
  if [[ ! -d "$CLAUDE_TEMPLATE" ]]; then
    echo "⚠️ No .claude template at $CLAUDE_TEMPLATE; creating .claude with CLAUDE.md only."
  fi
  mkdir -p "$dir/.claude"

  if [[ -d "$CLAUDE_TEMPLATE" ]]; then
    for item in agents skills; do
      [[ -d "$CLAUDE_TEMPLATE/$item" ]] || continue
      mkdir -p "$dir/.claude/$item"
      for src in "$CLAUDE_TEMPLATE/$item"/*; do
        [[ -e "$src" ]] || continue
        target="$dir/.claude/$item/$(basename "$src")"
        if [[ -d "$src" && ( -L "$target" || -f "$target" ) && ! -d "$target" ]]; then
          rm -f -- "$target"
          repaired=$((repaired + 1))
        elif [[ -L "$target" && ! -e "$target" ]]; then
          rm -f -- "$target"
          repaired=$((repaired + 1))
        elif [[ -e "$target" ]]; then
          continue
        else
          added=$((added + 1))
        fi
        cp -RL "$src" "$target"
      done
    done
    if [[ -f "$CLAUDE_TEMPLATE/settings.local.json" && ! -e "$dir/.claude/settings.local.json" ]]; then
      cp "$CLAUDE_TEMPLATE/settings.local.json" "$dir/.claude/settings.local.json"
      added=$((added + 1))
    fi
  fi

  if [[ ! -e "$dir/.claude/CLAUDE.md" && ! -e "$dir/CLAUDE.md" ]]; then
    local tpl="$CLAUDE_TEMPLATE/CLAUDE.md.tpl" commands prefix_line
    commands="$(project_commands "$type")"
    prefix_line="$(project_prefix_line)"
    if [[ -f "$tpl" ]]; then
      awk -v p="$name" -v t="${type:-generic}" -v c="$commands" -v x="$prefix_line" '
        { gsub(/__PROJECT__/, p); gsub(/__TYPE__/, t) }
        /^__COMMANDS__$/ { print c; next }
        /^__PREFIX__$/ { print x; next }
        { print }
      ' "$tpl" > "$dir/.claude/CLAUDE.md"
      # Templates written before --prefix existed have no __PREFIX__ line.
      grep -qF -- "$PREFIX_MARKER" "$dir/.claude/CLAUDE.md" || record_prefix "$dir/.claude/CLAUDE.md"
    else
      printf '# %s\n\n## Operate\n\n- Stack: %s.\n%s\n%s\n' "$name" "${type:-generic}" "$prefix_line" "$commands" > "$dir/.claude/CLAUDE.md"
    fi
    added=$((added + 1))
  else
    # Existing instructions are never overwritten; only the prefix line is recorded.
    if [[ -f "$dir/.claude/CLAUDE.md" ]]; then
      record_prefix "$dir/.claude/CLAUDE.md"
    else
      record_prefix "$dir/CLAUDE.md"
    fi
  fi

  command -v xattr &>/dev/null && xattr -rc "$dir/.claude" 2>/dev/null || true
  echo "🤖 .claude ready in $dir ($added added, $repaired repaired)"
}

# Codex uses root instructions and .agents/skills, rather than .codex/AGENTS.md.
install_codex_dir() {
  local dir="$1" name="$2" type="${3:-}" src target tpl commands prefix_line
  local added=0 repaired=0
  if [[ ! -d "$CODEX_TEMPLATE" ]]; then
    echo "⚠️ No Codex template at $CODEX_TEMPLATE; creating AGENTS.md only (no skills)."
  fi
  if [[ -d "$CODEX_TEMPLATE/skills" ]]; then
    mkdir -p "$dir/.agents/skills"
    for src in "$CODEX_TEMPLATE/skills"/*; do
      [[ -d "$src" && -f "$src/SKILL.md" ]] || continue
      target="$dir/.agents/skills/$(basename "$src")"
      if [[ -L "$target" && ! -e "$target" ]] || [[ -f "$target" && ! -d "$target" ]]; then
        rm -f -- "$target"
        repaired=$((repaired + 1))
      elif [[ -e "$target" || -L "$target" ]]; then
        continue
      else
        added=$((added + 1))
      fi
      cp -RL "$src" "$target"
    done
  fi
  # Keep the bundled project-analysis workflow available even when a private
  # or custom template predates it. Never replace a project-owned skill.
  src="$BUNDLED_CODEX_TEMPLATE/skills/project-context"
  target="$dir/.agents/skills/project-context"
  if [[ -d "$src" && -f "$src/SKILL.md" ]]; then
    if [[ -L "$target" && ! -e "$target" ]] || [[ -f "$target" && ! -d "$target" ]]; then
      rm -f -- "$target"
      repaired=$((repaired + 1))
    fi
    if [[ ! -e "$target" && ! -L "$target" ]]; then
      mkdir -p "$dir/.agents/skills"
      cp -RL "$src" "$target"
      added=$((added + 1))
    fi
  fi
  if [[ -f "$CODEX_TEMPLATE/config.toml" && ! -e "$dir/.codex/config.toml" && ! -L "$dir/.codex/config.toml" ]]; then
    mkdir -p "$dir/.codex"
    cp "$CODEX_TEMPLATE/config.toml" "$dir/.codex/config.toml"
    added=$((added + 1))
  fi
  # An override takes precedence over AGENTS.md. Never create competing guidance.
  if [[ -e "$dir/AGENTS.override.md" || -L "$dir/AGENTS.override.md" ]]; then
    echo "ℹ️ Existing AGENTS.override.md takes precedence; instructions left unchanged."
  elif [[ -e "$dir/AGENTS.md" || -L "$dir/AGENTS.md" ]]; then
    record_prefix "$dir/AGENTS.md"
  else
    tpl="$CODEX_TEMPLATE/AGENTS.md.tpl"
    commands="$(project_commands "$type")"
    prefix_line="$(project_prefix_line)"
    if [[ -f "$tpl" ]]; then
      # Use environment values so awk cannot reinterpret backslashes in paths.
      GP_PROJECT="$name" GP_TYPE="${type:-generic}" GP_COMMANDS="$commands" GP_PREFIX="$prefix_line" awk '
        { gsub(/__PROJECT__/, ENVIRON["GP_PROJECT"]); gsub(/__TYPE__/, ENVIRON["GP_TYPE"]) }
        /^__COMMANDS__$/ { print ENVIRON["GP_COMMANDS"]; next }
        /^__PREFIX__$/ { print ENVIRON["GP_PREFIX"]; next }
        { print }
      ' "$tpl" > "$dir/AGENTS.md"
      grep -qF -- "$PREFIX_MARKER" "$dir/AGENTS.md" || record_prefix "$dir/AGENTS.md"
    else
      printf '# %s\n\n## Operate\n\n- Stack: %s.\n%s\n%s\n' "$name" "${type:-generic}" "$prefix_line" "$commands" > "$dir/AGENTS.md"
    fi
    added=$((added + 1))
  fi
  echo "🤖 Codex ready in $dir ($added added, $repaired repaired)"
}

# Reject missing retrofit targets before changing global or project files.
if [[ "$CODEX_ONLY" == true && ! -d "$CODEX_ONLY_DIR" ]]; then
  echo "❌ Not a directory: $CODEX_ONLY_DIR"
  exit 1
fi
if [[ "$CLAUDE_ONLY" == true && ! -d "$CLAUDE_ONLY_DIR" ]]; then
  echo "❌ Not a directory: $CLAUDE_ONLY_DIR"
  exit 1
fi

# Keep the global excludes file in step, so every repo on this machine ignores AI tooling.
if [[ -f "$DEFAULT_GITIGNORE" ]]; then
  ensure_ai_ignored "$DEFAULT_GITIGNORE"
fi

# Retrofit never commits or publishes, and keeps ignore changes local to the repo.
if [[ "$CODEX_ONLY" == true ]]; then
  [[ -d "$CODEX_ONLY_DIR" ]] || { echo "❌ Not a directory: $CODEX_ONLY_DIR"; exit 1; }
  CODEX_ONLY_DIR="$(cd "$CODEX_ONLY_DIR" && pwd)"
  if git -C "$CODEX_ONLY_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    exclude="$(git -C "$CODEX_ONLY_DIR" rev-parse --git-path info/exclude)"
    [[ "$exclude" = /* ]] || exclude="$CODEX_ONLY_DIR/$exclude"
    mkdir -p "$(dirname "$exclude")"
    ensure_ai_ignored "$exclude"
    if [[ -n "$(git -C "$CODEX_ONLY_DIR" ls-files .agents .codex AGENTS.md AGENTS.override.md)" ]]; then
      echo "⚠️ Codex files are already tracked; ignore rules do not untrack them."
    fi
  fi
  install_codex_dir "$CODEX_ONLY_DIR" "$(basename "$CODEX_ONLY_DIR")" "$TYPE"
  exit 0
fi

# 🔧 Retrofit mode: add or repair .claude in an existing project.
if [[ "$CLAUDE_ONLY" == true ]]; then
  [[ -d "$CLAUDE_ONLY_DIR" ]] || { echo "❌ Not a directory: $CLAUDE_ONLY_DIR"; exit 1; }
  CLAUDE_ONLY_DIR="$(cd "$CLAUDE_ONLY_DIR" && pwd)"
  install_claude_dir "$CLAUDE_ONLY_DIR" "$(basename "$CLAUDE_ONLY_DIR")" ""
  if git -C "$CLAUDE_ONLY_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    if git -C "$CLAUDE_ONLY_DIR" check-ignore -q .claude/CLAUDE.md; then
      echo "🙈 .claude is ignored by git"
    else
      exclude="$(git -C "$CLAUDE_ONLY_DIR" rev-parse --git-path info/exclude)"
      [[ "$exclude" = /* ]] || exclude="$CLAUDE_ONLY_DIR/$exclude"
      mkdir -p "$(dirname "$exclude")"
      ensure_ai_ignored "$exclude"
    fi
    if [[ -n "$(git -C "$CLAUDE_ONLY_DIR" ls-files .claude)" ]]; then
      echo "⚠️ Some .claude files are already tracked by git; ignore rules do not untrack them."
    fi
  fi
  exit 0
fi

# 📌 Validate input
if [[ -z "$PROJECT_NAME" ]]; then
  usage
  exit 1
fi
if [[ ! "$PROJECT_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "❌ Project name may only contain letters, digits, '.', '_' and '-'."
  exit 1
fi
case "$TYPE" in
  ""|docker|podman|node|python|terraform|go) ;;
  *)
    if [[ -d "$PROJECT_NAME" && -n "$(ls -A "$PROJECT_NAME" 2>/dev/null)" ]]; then
      echo "❌ Cannot add unknown type '$TYPE' to an existing project."
      exit 1
    fi
    echo "⚠️ Unknown project type '$TYPE'. Proceeding with generic scaffold."
    ;;
esac
TYPE_RETROFIT=false
if [[ -d "$PROJECT_NAME" && -n "$(ls -A "$PROJECT_NAME" 2>/dev/null)" ]]; then
  if [[ -z "$TYPE" ]]; then
    echo "❌ '$PROJECT_NAME' already exists and is not empty. Set --type to add missing type files, or use --claude-only/--codex-only for assistant support."
    exit 1
  fi
  TYPE_RETROFIT=true
  if [[ "$TYPE" == "podman" && -z "$PREFIX" ]]; then
    echo "❌ Adding Podman files to an existing project requires --prefix. Use the prefix already recorded for this project."
    exit 1
  fi
  echo "ℹ️ Existing project detected. Adding missing $TYPE files only; no files will be overwritten or committed."
elif [[ -e "$PROJECT_NAME" ]]; then
  echo "❌ '$PROJECT_NAME' exists and is not a directory."
  exit 1
fi

# 🔧 Prerequisites
if [[ "$TYPE_RETROFIT" != true ]]; then
  command -v git &>/dev/null || { echo "❌ Required tool missing: git"; exit 1; }
fi
if [[ "$TYPE_RETROFIT" != true && "$USE_GITHUB" == true ]]; then
  command -v gh &>/dev/null || { echo "❌ Required tool missing: gh (or use --no-github)"; exit 1; }
  # --- GitHub authentication check ---
  if ! gh auth status 2>&1 | grep -q "Logged in to github.com"; then
    echo "❌ GitHub CLI is not authenticated."
    echo "👉 Run: gh auth login (or use --no-github)"
    exit 1
  fi
fi

# 🏗️ Create structure
mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME"

# --- Language/Type specific bootstraps ---
case "$TYPE" in
  terraform)
    if type_file_available main.tf; then
      echo "🌱 Creating minimal main.tf with required_version"
      cat > main.tf <<'EOF'
terraform {
  required_version = ">= 1.0.0"
}
EOF
    fi
    ;;
  node)
    if type_file_available package.json; then
      echo "🌱 Creating minimal Node package.json"
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
    fi
    if type_file_available index.js; then
      echo "console.log('hello');" > index.js
    fi
    ;;
  python)
    if type_file_available app.py; then
      echo "🌱 Creating minimal Python scaffold"
      echo "print('hello')" > app.py
    fi
    ;;
  docker)
    if type_file_available Dockerfile; then
      echo "🌱 Creating minimal Dockerfile"
      cat > Dockerfile <<'EOF'
FROM alpine:3
CMD ["sh","-c","echo hello"]
EOF
    fi
    ;;
  podman)
    if type_file_available Containerfile; then
      echo "🌱 Creating Podman Containerfile"
      cat > Containerfile <<'EOF'
FROM docker.io/library/alpine:3
CMD ["sh", "-c", "echo hello from Podman"]
EOF
    fi
    if type_file_available Makefile; then
      echo "🌱 Creating Podman Makefile"
    cat > Makefile <<EOF
.DEFAULT_GOAL := build

PREFIX := ${PREFIX}
IMAGE := \$(PREFIX)demo:local
CONTAINER := \$(PREFIX)demo-run

.PHONY: check build run clean

check: ## Verify the Podman CLI is installed
	@command -v podman >/dev/null 2>&1 || { echo "podman is required" >&2; exit 1; }
	@podman --version

build: check ## Build this project's Containerfile
	@podman build --tag "\$(IMAGE)" --file Containerfile .

run: build ## Run the demo container and remove it when it exits
	@podman run --rm --name "\$(CONTAINER)" "\$(IMAGE)"

clean: ## Remove only this project's generated image
	@podman image rm "\$(IMAGE)"
EOF
    fi
    ;;
  go)
    echo "🌱 Creating minimal Go scaffold (no Docker)"
    GO_VERSION="${GO_VERSION:-1.22}"
    GOMODULE_PATH="github.com/raymonepping/${PROJECT_NAME}"

    # go.mod
    if type_file_available go.mod; then
      cat > go.mod <<EOF
module ${GOMODULE_PATH}

go ${GO_VERSION}
EOF
    fi

    # main.go
    if type_file_available "cmd/${PROJECT_NAME}/main.go"; then
      mkdir -p "cmd/${PROJECT_NAME}"
      cat > "cmd/${PROJECT_NAME}/main.go" <<'EOF'
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
    fi

    # Makefile
    if type_file_available Makefile; then
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
    fi

    # .golangci.yml
    if type_file_available .golangci.yml; then
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
    fi
    ;;
esac

if [[ "$TYPE_RETROFIT" == true ]]; then
  if [[ "$TYPE" == "podman" ]] && type_file_available .containerignore; then
    if [[ -f .dockerignore ]]; then
      cp .dockerignore .containerignore
    elif [[ -f "$DEFAULT_DOCKERIGNORE" ]]; then
      cp "$DEFAULT_DOCKERIGNORE" .containerignore
    else
      cat > .containerignore <<'EOF'
.git
.github
node_modules
__pycache__
EOF
    fi
    ensure_ai_ignored .containerignore
  fi
  echo "✅ Added missing $TYPE starter files in $PWD. Existing files, project settings, Git history, and remotes were left untouched."
  exit 0
fi

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
ensure_ai_ignored .gitignore

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
  ensure_ai_ignored .dockerignore
fi

if [[ "$TYPE" == "podman" ]]; then
  # Podman prefers .containerignore when both it and .dockerignore exist.
  cp .dockerignore .containerignore
  ensure_ai_ignored .containerignore
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
if ! curl -fsS https://www.gnu.org/licenses/gpl-3.0.txt -o LICENSE; then
  echo "⚠️ Could not download the GPL-3.0 licence; add LICENSE yourself."
  rm -f LICENSE
fi

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
elif [[ "$TYPE" == "podman" ]]; then
  cat > README.md <<EOF
# $PROJECT_NAME

Podman-first container scaffold. Its project resource prefix is \`${PREFIX}\`.
Check that the prefix is unused before running the Make targets. On macOS,
start your Podman machine before building or running the image.

## Quickstart

\`make check\` verifies the Podman CLI is installed. Then use \`make build\` to build
the image, \`make run\` to run the short demo, and \`make clean\` to remove
only this project's generated image. The run target removes its container on
exit; the image remains until you clean it.
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
  docker|podman)
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

[[ -f "$DEPENDABOT_FILE" ]] && echo "🔐 Added .github/dependabot.yml"

# 📄 Type-specific scan_on_pr.yml workflow
if [[ -n "$TYPE" ]]; then
  SCAN_SOURCE_FILE="$HOME/.${TYPE}_scan_on_pr.yml"
  SCAN_TARGET_DIR=".github/workflows"
  SCAN_TARGET_FILE="${SCAN_TARGET_DIR}/scan_on_pr.yml"
  if [[ -f "$SCAN_SOURCE_FILE" ]]; then
    mkdir -p "$SCAN_TARGET_DIR"
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

# 🤖 Claude Code workspace
if [[ "$USE_CLAUDE" == true ]]; then
  install_claude_dir "$PWD" "$PROJECT_NAME" "$TYPE"
fi

if [[ "$USE_CODEX" == true ]]; then
  install_codex_dir "$PWD" "$PROJECT_NAME" "$TYPE"
fi

# 🧪 Run sanity_check on project files only (never on local tooling such as skill scripts)
if command -v "$SANITY_CHECK_CMD" &>/dev/null; then
  echo "🧪 Running sanity_check..."
  find . \( -path ./.git -o -path ./.claude -o -path ./.agents -o -path ./.codex -o -path ./.impeccable -o -name node_modules \) -prune -o \
    -type f \( -name "*.sh" -o -name "*.py" -o -name "*.js" -o -name "*.tf" -o -name "Dockerfile" -o -name "Containerfile" -o -name "*.go" \) \
    -exec "$SANITY_CHECK_CMD" --fix --report {} +
else
  echo "ℹ️ $SANITY_CHECK_CMD not found — skipping"
fi

# 🌀 Git + GitHub
git init -q -b main

# 🪝 Git hook for sanity_check
HOOK_PATH=".git/hooks/pre-commit"
if command -v "$SANITY_CHECK_CMD" &>/dev/null; then
  echo "🪝 Installing pre-commit git hook..."
  cat > "$HOOK_PATH" <<'EOF'
#!/bin/bash
set -euo pipefail
STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.sh$|\.py$|\.js$|\.tf$|Dockerfile$|Containerfile$|\.go$' || true)
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
# The first commit of a public repo must never carry local AI tooling.
LEAKED="$(git diff --cached --name-only | grep -E '(^|/)(\.(claude|agents|codex|impeccable)/|AGENTS(\.override)?\.md$)' || true)"
if [[ -n "$LEAKED" ]]; then
  echo "❌ Refusing to commit local AI tooling:"
  echo "$LEAKED" | head -5
  exit 1
fi
git commit -q -m "Initial commit for $PROJECT_NAME"
echo "✅ Initial commit created"

if [[ "$USE_GITHUB" == true ]]; then
  gh repo create "$PROJECT_NAME" "--$VISIBILITY" --source=. --remote=origin --push

  # 🚀 Optional: Trigger scan_on_pr workflow (if it exists)
  WORKFLOWS="$(gh workflow list 2>/dev/null || true)"
  if grep -q "scan_on_pr" <<<"$WORKFLOWS"; then
    echo "🌀 Triggering scan_on_pr GitHub Action workflow..."
    gh workflow run scan_on_pr.yml || echo "ℹ️ Failed to trigger workflow"
  else
    echo "ℹ️ scan_on_pr.yml workflow not found in repo — skipping workflow run"
  fi

  # 📌 Optional: Trigger PR-based scan
  if [[ -n "$TYPE" ]] && command -v trigger_git_scan &>/dev/null; then
    echo ""
    echo "🚀 Initiating GitHub PR scan via trigger_git_scan..."
    trigger_git_scan || echo "ℹ️ trigger_git_scan failed"
  else
    echo "ℹ️ Skipping trigger_git_scan — not enabled or missing."
  fi

  echo -e "\n✅ Project '$PROJECT_NAME' scaffolded, sanity-checked, and pushed to GitHub ($VISIBILITY)!"
else
  echo -e "\n✅ Project '$PROJECT_NAME' scaffolded and committed locally (GitHub skipped)."
fi

# 🌳 Folder tree
if command -v folder_tree &>/dev/null; then
  echo ""
  echo "🌳 Generating FOLDER_TREE.md for $PROJECT_NAME..."
  folder_tree --preset node,nuxt --output markdown "$PWD" || echo "ℹ️ folder_tree failed"
else
  echo "ℹ️ folder_tree not found — skipping FOLDER_TREE.md generation"
fi

echo -e "\n🎉 All done!"
