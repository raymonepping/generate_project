# generate_project

Scaffold a new project, commit it and publish it on GitHub in one command,
with local Claude Code and Codex workspaces.

```sh
generate_project --project f_Ray_grance --type node
```

This creates `./f_Ray_grance`: type-specific starter files, `.gitignore` and
`.dockerignore` from your global templates, a GPL-3.0 `LICENSE`, `README.md`,
an empty `.env`, Dependabot config, the matching `scan_on_pr` workflow, a
`sanity_check` pre-commit hook, `.claude/`, root `AGENTS.md`,
`.agents/skills/` and `.codex/config.toml`. It then makes the
first commit on `main` and creates the GitHub repository.

## Options

| Option | Effect |
| --- | --- |
| `--type <docker\|node\|python\|terraform\|go>` | Starter files and Dependabot ecosystem. Go gets no Dockerfile. |
| `--prefix <prefix>` | Resource prefix (e.g. `srot`, stored as `srot-`) written into assistant instructions to scope container, VM and namespace operations. Works with both retrofit modes. |
| `--private` | Create the GitHub repository as private (default public). |
| `--no-github` | Commit locally only. |
| `--no-claude` | Skip the `.claude/` folder. |
| `--claude-template <dir>` | Use another `.claude` template. |
| `--claude-only [<dir>]` | Add or repair `.claude/` in an existing project. |
| `--no-codex` | Skip Codex files. |
| `--codex-template <dir>` | Use another Codex template. |
| `--codex-only [<dir>]` | Add or repair Codex support; accepts `--type` and `--prefix`. |

## The `.claude` folder

The template lives in `~/.config/generate_project/claude/` (override with
`GENERATE_PROJECT_CLAUDE_TEMPLATE`), outside this repository because its skills
come from third parties:

```text
agents/               subagents
skills/               real skill folders, no symlinks
settings.local.json   project hooks
CLAUDE.md.tpl         starter CLAUDE.md (__PROJECT__, __TYPE__, __PREFIX__, __COMMANDS__)
```

A new project gets a copy plus a `CLAUDE.md` filled in for its type.
`--claude-only` never overwrites existing files. It does replace a skill that is
a broken symlink or a small stub file, which is what copying symlinked skills
leaves behind. Running it twice changes nothing.

To update every future project, edit the template. To update an existing
project, run `generate_project --claude-only <dir>`.

## Codex support

Codex uses root `AGENTS.md`, `.agents/skills/`, and optional
`.codex/config.toml`. The bundled template includes `project-checks` and
`scoped-resources` skills. It inherits your personal model, approvals, sandbox,
and MCP settings. Claude hooks and agents require translation before use in Codex.

```sh
generate_project --codex-only ./existing-project --type terraform --prefix demo
```

The template defaults to `~/.config/generate_project/codex/` if present, then
the bundled `tpl/codex/`. Override it with `GENERATE_PROJECT_CODEX_TEMPLATE`
or `--codex-template`. Retrofit preserves existing instructions, skills and
config, with the same prefix-placeholder repair as Claude. See
[Codex support](docs/codex-support.md) for discovery, migration and privacy details.

## Keeping AI tooling private

`.claude/`, `.agents/`, `.codex/`, `.impeccable/`, `AGENTS.md` and
`AGENTS.override.md` are added to the new
project's `.gitignore` and `.dockerignore`, and to `~/.gitignore_global`
(git's global excludes file on this Mac). The first commit refuses to proceed
if any of them is staged. In `--claude-only` mode, a repository that does not
ignore `.claude/` gets it in `.git/info/exclude`, which stays local.
`--codex-only` also uses local Git excludes and warns about already tracked files.

## Install

```sh
mkdir -p ~/.config/generate_project/codex
cp -R tpl/codex/. ~/.config/generate_project/codex/
cp bin/generate_project.sh /usr/local/bin/generate_project
chmod 755 /usr/local/bin/generate_project
```

Requires `git`; publishing also needs an authenticated `gh`. `sanity_check`,
`validate_ignore`, `commit_gh`, `trigger_git_scan` and `folder_tree` are used
when present.

Homebrew installs the script and bundled Codex templates together using
`Formula/generate_project.rb`. Its wrapper always uses Homebrew Bash.

Run the offline integration checks with:

```sh
python3 -m unittest discover -s tests -v
shellcheck bin/generate_project.sh
```
