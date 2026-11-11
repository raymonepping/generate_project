---
name: project-context
description: Inspect a project and populate or refresh its Codex project context in AGENTS.md from repository evidence, preserving user-authored instructions.
---

# Build project context from evidence

Use this skill when the user asks to analyze, onboard, document, or refresh the
project's Codex instructions. It is an explicit analysis workflow; the project
generator does not invoke a model or run this skill automatically.

## Inspect

Read the active instruction files and relevant project sources. Start with the
README and inspect files that exist, such as Makefiles, package manifests,
language or infrastructure manifests, Dockerfiles/Containerfiles, CI workflows,
and the source tree. Follow references only as needed to verify architecture
and commands. Do not read secret files such as `.env`, credentials, private keys,
or Terraform state. Do not execute commands or tests unless the user asks for
verification.

Base each fact on repository evidence. Distinguish commands declared in files
from commands actually run; this workflow normally runs none. Do not infer
features, deployment behavior, security guarantees, resource ownership, or
working checks from a project type or filename alone. If evidence is missing,
contradictory, placeholder text, or unclear, say so briefly instead of guessing.
Never copy project-specific assumptions from another repository.

## Update instructions

Use the root `AGENTS.override.md` if it exists; otherwise use root `AGENTS.md`.
Do not create a competing `AGENTS.md` when an override exists. If the active
instruction file is missing, ask before creating one. Preserve all content
outside this exact managed region:

```markdown
<!-- BEGIN GENERATED PROJECT CONTEXT -->
...evidence-based project facts...
<!-- END GENERATED PROJECT CONTEXT -->
```

Replace only the content between a single valid pair of markers when refreshing
it. If markers are missing, append one managed region after the existing
content. If either marker is duplicated, unmatched, or reversed, stop and
report the problem rather than risk overwriting instructions. Keep the section
concise (target under 6 KiB) and useful across tasks. Include only applicable,
evidence-backed details:

- Project purpose and major components, with source paths.
- Important entry points, data/configuration flow, and boundaries.
- Commands declared by project files, naming their source file; flag
  placeholders and unverified commands.
- Relevant validation and CI behavior, including gaps or skipped checks.
- Material project-specific constraints that are explicit in repository docs
  or configuration.
- Unresolved facts that would otherwise invite unsafe or misleading guesses.

Do not duplicate the generic operating rules, the full README, or entire config
files. Do not include secret values, personal machine paths, or speculative
recommendations. Keep the generated region in the active instruction file so
Codex can discover it; arbitrary documentation files are not loaded as project
instructions unless those instructions point Codex to them.

After editing, summarize the main facts added, cite the files that support
them, and call out uncertainty. Do not claim checks ran unless they did.
