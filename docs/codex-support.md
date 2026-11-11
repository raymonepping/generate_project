# Codex support

Codex discovers repository instructions in root `AGENTS.md` (or the higher
priority `AGENTS.override.md`), skills in `.agents/skills/<name>/SKILL.md`, and
trusted project configuration in `.codex/config.toml`. A `.codex/AGENTS.md` file
does not replace root instructions. Skills are selected by their descriptions
or explicitly with `$project-checks` and `$scoped-resources`.

The generator uses `~/.config/generate_project/codex/` when present, otherwise
its bundled `tpl/codex/`. Override this with `GENERATE_PROJECT_CODEX_TEMPLATE`
or `--codex-template`. The template contains `AGENTS.md.tpl`, optional
`config.toml`, and `skills/`. Instructions accept `__PROJECT__`, `__TYPE__`,
and whole-line `__PREFIX__` and `__COMMANDS__` markers.

```sh
generate_project --codex-only ./existing-project --type terraform --prefix demo
generate_project --project demo-app --type node --no-github
generate_project --project claude-app --type python --no-codex
```

In retrofit mode, `--project <dir>` is an alias for the positional target
directory. Do not supply both. The target must already exist; missing targets
are refused before any ignore files or assistant files are changed. With no
target argument, retrofit still defaults to the current directory.

Retrofit adds missing files and repairs broken skill symlinks or file stubs.
Existing skill directories and config are preserved; it is not an upgrade that
overwrites installed skills. Existing instructions are preserved except for
recording a requested resource prefix when `--prefix` is given. The generator
fills an unset prefix line, inserts after `- Stack:`, inserts under `## Operate`,
or appends an Operate section if neither marker exists. Existing different
prefixes are preserved with a warning. Root `CLAUDE.md` files receive the same
prefix handling in Claude retrofit mode.
An existing `AGENTS.override.md` is left untouched and suppresses generation
of a competing `AGENTS.md`. Copies dereference template skill symlinks so each
project remains independent of the template.

The bundled skills cover project-context analysis, stack checks,
prefix-scoped resource operations, frontend design, and prose editing. The
`frontend-design` and `stop-slop` skills come from third-party repositories;
their MIT license files are included in each copy. `project-context` is also installed from the
bundled template when a selected private or custom template does not yet contain
it; an existing project-owned skill with that name is preserved. It is invoked
explicitly (for example, `$project-context`) and maintains a bounded,
evidence-based section inside the active root instruction file. The generator
does not call a model or analyze project files itself.

The skills do not add dependencies, connect services, set a model, change
approval settings, or grant resource permissions. The empty configuration
inherits personal settings. Trust the project through Codex's normal flow to
enable project configuration; the generator does not edit global trust.

### Project-specific context

Ask Codex to run `$project-context` after a scaffold is created or when an
existing project needs its instructions refreshed. The skill inspects repository
documentation and configuration, avoids secret files and command execution,
and distinguishes commands declared in files from checks actually run. It
preserves instructions outside its marked section and refuses malformed markers.
It does not guess missing architecture or validations. This keeps the Bash
scaffolder deterministic and avoids silently invoking a model during project
creation.

The generated section belongs in `AGENTS.md` (or `AGENTS.override.md` when that
is active), since arbitrary documentation files are not automatically loaded as
Codex instructions. Retrofit continues to preserve existing skills; the bundled
`project-context` skill is added if a selected older template lacks it.

## Mapping the Claude workspace

| Claude source | Codex equivalent |
| --- | --- |
| `.claude/CLAUDE.md` | Root `AGENTS.md` |
| `.claude/skills/` | `.agents/skills/` with reviewed `SKILL.md` instructions |
| `.claude/settings.local.json` | Native Codex config/hooks; requires translation |
| `.claude/agents/` | Native Codex subagent configuration or reusable skill procedures; requires translation |

The private Claude template currently includes design-taste-frontend,
no-ai-slop, and Impeccable. These are not blindly copied into Codex: their
instructions and references need review for Claude paths, tools, hook behavior,
and subagent dependencies. For a portable, reviewed skill, copy the entire
folder (including scripts, references, assets and license) into your Codex
template's `skills/`, then retrofit the target project. Retain third-party
license notices and avoid distributing private template content in this repo.

## Local-only behavior

New scaffolds exclude assistant directories and `AGENTS.md` /
`AGENTS.override.md` from Git and, except for Go's native-only scaffold, Docker
build contexts. The initial commit checks staged paths and refuses to include
assistant tooling even if ignore rules were overridden. Retrofit adds local
Git excludes; existing tracked files remain tracked and produce a warning.
Existing Docker ignore rules are not rewritten during retrofit: add the same
patterns there before building an existing container project.

## Official references

- [Instructions and discovery](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Skill format and discovery](https://learn.chatgpt.com/docs/build-skills)
- [Trusted project configuration](https://learn.chatgpt.com/docs/config-file/config-basic)
