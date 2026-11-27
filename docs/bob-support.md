# Bob support

Bob loads project guidance from several places. The generator creates only the
part that no other assistant support already provides.

| Bob reads | Created by |
| --- | --- |
| Root `AGENTS.md` (every mode) | Codex support |
| `.agents/skills/<name>/SKILL.md` | Codex support |
| `.claude/skills/<name>/SKILL.md` | Claude support |
| `.bob/mcp.json` | Bob support (this document) |
| `.bob/custom_modes.yaml` | Bob support (this document) |

Skill discovery order is `.bob`, then `.agents`, then `.claude`; the first skill
with a given name wins. Bob's own documentation names `.bob/skills/` and
`~/.bob/skills/`; the `.agents` and `.claude` fallbacks come from Bob's
skill-authoring guidance, so check them once in a real project.

## What a new project gets

```text
.bob/mcp.json            {"mcpServers": {}}
.bob/custom_modes.yaml   customModes: [] with a commented example
```

Both are empty on purpose. The generator cannot know which MCP servers or
modes a project needs, and an MCP server that touches a credential should be a
deliberate choice.

## Why skills and rules are not copied

- `AGENTS.md` already reaches Bob as workspace rules. A second copy under
  `.bob/rules/` would drift from it.
- `.agents/skills/` already reaches Bob. Copying it into `.bob/skills/` would
  duplicate every skill and make the project copy shadow the original.
- The generated `AGENTS.md` still mentions `$project-context` and `.codex/`.
  Those are Codex phrasings that read fine for Bob, so the shared template is
  left alone.

A project that wants a Bob-only skill, rule or mode can add it to
`.bob/` itself, or to a custom template (see below).

## Template

The generator uses `~/.config/generate_project/bob/` when it exists, otherwise
the bundled `tpl/bob/`. Override either with `GENERATE_PROJECT_BOB_TEMPLATE` or
`--bob-template <dir>`.

Every regular file under the template is copied to the same relative path in
`.bob/`, so a custom template can also carry `rules/`, `rules-<mode>/`, `skills/`
or `settings.json`. Existing files are never overwritten, and a missing template
directory produces a warning, not an error.

## Retrofit

```sh
generate_project --bob-only ./existing-project
generate_project --project existing-project --bob-only
```

Retrofit adds missing files only. It adds `.bob/` to the repository's
`.git/info/exclude` (never to a tracked ignore file) and warns when `.bob/`
files are already tracked, since ignore rules do not untrack them. A positional
directory and `--project` cannot be combined, and `--bob-only` cannot be
combined with `--no-bob`, `--claude-only` or `--codex-only`.

## Privacy

`.bob/` is treated like the other assistant folders: it is added to
`.gitignore`, `.dockerignore`, `.containerignore` (Podman) and
`~/.gitignore_global`, and the first commit refuses to include it. Bob's own
documentation describes project `.bob/` files as shareable through version
control; a repository that wants that can remove the ignore line and commit
the folder. Project settings, modes and skills only load in folders that Bob
trusts.
