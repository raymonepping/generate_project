# generate_project: project analysis

Reviewed 2026-11-03. Baseline: commit `5a3e4b7`, release 2.1.1; this review
also covers the prefix-layout fix prepared for 2.1.2. This is a source review
with isolated local reproductions, not a live publishing or cloud-security audit.

## What the project does

`bin/generate_project.sh` is a standalone Bash CLI with two execution paths:

1. **Create:** generate a small type-specific project, install optional assistant
   workspaces, initialize Git on `main`, make an initial commit, and optionally
   publish with `gh repo create --source=. --push`. Repositories default public;
   `--private` changes visibility and `--no-github` keeps publishing local.
2. **Retrofit:** add or repair one assistant workspace in an existing directory.
   `--project <dir>` selects the same target as the positional retrofit argument.
   It does not scaffold the application, commit it, or publish it.

Supported types are Docker, Node, Python, Terraform and Go, with a generic
fallback. Go targets a native CLI and intentionally omits Docker files. Node's
starter test prints `ok`; Python has no generated test framework. Dependabot
configuration alone does not prove an ecosystem manifest or meaningful tests exist.

The generator depends on shell utilities beyond Git: notably `awk`, `grep`,
`find`, `mktemp`, `cp` and `curl`. Publishing additionally requires authenticated
`gh`. This fits the intended macOS environment; it is not a portable Windows CLI.

## Architecture and ownership

| Component | Responsibility and review result |
| --- | --- |
| `bin/generate_project.sh` | Parsing, validation, templates, privacy rules, scaffolding, commits and publishing. Easy to install; increasingly dense as these responsibilities accumulate. |
| `tpl/codex/` | First-party instructions, optional config and two focused skills; copied into the assistant's native discovery locations. No model, sandbox, approval or trust settings are imposed. |
| External Claude template | Private `~/.config/generate_project/claude/` content; agents, skills, settings and instruction template. Missing templates degrade to minimal instructions with a warning. |
| `tests/test_generate_project.py` | Offline integration tests using temporary HOME/workspaces, real Git, a blocked licence download and no optional global helpers. Tests run the system Bash explicitly. |
| `Formula/generate_project.rb` | Installs `bin` and `tpl` together and writes a wrapper using Homebrew Bash. Source archives are pinned with SHA-256. Install/test blocks were exercised in a temporary prefix. |
| `.github/workflows/` | Secret scanning and tagged releases. No behavioral-test or ShellCheck workflow exists at the review baseline. |
| Local `AGENTS.md`, `.agents/`, `.codex/` | Working-copy assistant context; ignored rather than distributed as project source. The committed `tpl/codex` content supplies future projects. |

The generator detects an installed `commit_gh`, or copies its fallback, but
does not invoke it for a generated project's initial commit. That path uses
`git` and `gh` directly. Maintenance of this repository uses `commit_gh` by
the owner's instruction. These are separate workflows.

## What is working well

- **Native assistant layouts.** Claude and Codex get separate instruction,
  skill and config locations instead of a mechanical folder rename. Existing
  `AGENTS.override.md` takes precedence and is left unchanged.
- **Conservative retrofit.** Existing skill directories and config are kept;
  broken skill links and file stubs can be repaired. Copies dereference source
  skill links. Repeated retrofit is stable in the tested scenarios.
- **Explicit target selection.** The 2.1.1 fix prevents `--project` from being
  silently ignored in retrofit mode. Ambiguous targets and missing retrofit
  directories are rejected before global/project changes.
- **Layered assistant exclusions.** New projects get Git and, except for Go,
  Docker exclusions. Retrofit uses local Git excludes. Before the initial
  commit, staged assistant paths are checked explicitly.
- **Small reusable skills.** `project-checks` distinguishes meaningful tests
  from placeholders; `scoped-resources` documents project resource boundaries.
  Neither skill installs dependencies or grants additional permissions.
- **Packaging matches runtime discovery.** Installing templates with the
  script preserves the fallback from personal templates to bundled assets.

## Prefix defect fixed with this review

The reported command succeeded overall but could not record a prefix in a
handwritten `AGENTS.md` without `- Stack:`. Its caller then printed "Codex
ready", even though the requested instruction was absent.

Prefix recording now follows this order:

1. Preserve an existing concrete prefix, warning if it differs.
2. Fill the generator's unset-prefix placeholder.
3. Insert after an existing `- Stack:` line.
4. Otherwise insert under an existing `## Operate` heading.
5. Otherwise append an Operate section, keeping the original text.

The related Claude path previously noticed root `CLAUDE.md` but tried to
record the prefix only in `.claude/CLAUDE.md`. It now updates the existing
root file when no nested instruction file exists. Tests cover both layouts,
repeated runs, preservation of a different prefix, and missing final newlines.

This remains a small Markdown convention, not a general Markdown editor.
Arbitrary prose such as "our containers use xyz" is not parsed as a resource
declaration. Check for existing project-specific naming before choosing a
prefix. An instruction line is advisory guidance, not an enforced sandbox.

## Open findings, ordered by practical impact

### 1. Built-in environment-file exclusions are incomplete — high priority

**Confirmed in an isolated clean HOME:** removing `.gitignore_global`, then
generating a Node project with `--no-github --no-claude --no-codex`, causes
`git ls-files` to contain `.env`. The generated file is initially empty, so
this test did not expose a secret. Tracking it makes future accidental secret
commits more likely. The fallback `.dockerignore` also lacks `.env` patterns.

The current test fixture always supplies a global ignore containing `.env`,
which masks this missing-default case.

**Recommended change:** enforce a minimal environment/credential exclusion
baseline independently of personal templates, decide how example files are
handled, and add clean-HOME tests for both the index and build-context rules.
Do not assume a global template is installed on another developer's machine.
This is recorded, not silently fixed as part of the prefix patch.

### 2. Initial hook installation can replace a supplied security hook — high priority

After `git init`, the generator writes `.git/hooks/pre-commit` whenever
`sanity_check` is available. A hook supplied through Git's template directory
can therefore be replaced. The new hook runs `sanity_check --fix`; it does
not explicitly chain the previous hook or separately invoke Gitleaks.

The generated hook also fixes working-tree files after staging without
explicitly restaging them. A fixed working tree need not match the committed
index. Exact behavior depends on the installed helper, which is outside this
repository. Filenames are passed through newline splitting and `xargs`.

**Recommended change:** preserve/chain existing hooks, specify whether hooks
validate or mutate, handle staged content deliberately, and test filenames
with spaces plus an inherited secret-scanning hook using isolated fixtures.

### 3. Global ignore mutation precedes some validation — medium priority

**Confirmed in isolation:** `--project bad/name --no-github` rejects the name
but first adds assistant exclusions to an existing global ignore file.
Missing/conflicting retrofit targets are already checked earlier; ordinary
new-project validation and prerequisite checks still occur later.

**Recommended change:** complete argument, target and prerequisite validation
before any write. Add assertions that rejected invocations change neither
the target nor HOME. Extend parsing tests for missing option values, duplicate
target options and contradictory flags (`--claude-only --no-claude` currently
has no equivalent rejection to the Codex combination).

### 4. Global privacy rules depend on local Git configuration — medium priority

The script edits an existing `~/.gitignore_global`; it neither creates it when
absent nor establishes that `core.excludesFile` points there. A file at that
path is not automatically an active Git exclusion on every computer.

**Recommended change:** inspect the effective configuration, report what is
active, and prefer explicit local exclusions without silently changing a
machine-wide Git preference. Decide whether global mutation should be opt-in.
Broad global `AGENTS.md` exclusions can also hide guidance users intend to
share in unrelated repositories.

### 5. Retrofit privacy is narrower than new-project privacy — medium priority

Retrofit adds local Git rules, but does not rewrite an existing Docker ignore
file. Ignore rules do not remove already-tracked files. A Codex retrofit also
adds exclusions for the other assistant directories. Documentation now needs
to be read as distinct creation and retrofit contracts.

**Recommended change:** report effective ignore coverage and tracked-tooling
warnings clearly. If build-context repair is added, make its file edits
explicit and preserve user rules. Do not present Git ignores as encryption,
data-loss prevention, or a restriction on what an assistant provider receives.

### 6. Behavioral checks are local, not enforced by CI — medium priority

The suite covers scaffold types, target selection, opt-out, fallback,
custom templates, symlink repair, prefix layouts and repeatability. It does
not currently exercise successful/failed GitHub publishing, inherited hooks,
the staged-path guard under forced staging, or partial failures and recovery.
Secret scanning in Actions does not exercise these behaviors.

**Recommended change:** run the offline suite, ShellCheck and formula syntax
checks on Linux/macOS in CI. Use deterministic `gh`/helper stubs for publishing
and failure scenarios instead of creating real repositories during tests.

### 7. Template repair is additive, not an update manager — lower priority

Existing directories are kept wholesale, so new files inside an already
installed skill are not merged. An explicit but missing Codex template path
warns and falls back to minimal instructions. Valid linked destination skill
directories are kept rather than converted into independent copies. Source
templates may contain executable hooks/scripts, so template choice is a trust
decision. Claude-specific hooks and agents are not translated automatically.

**Recommended change:** distinguish "added", "repaired", "preserved", "skipped"
and "degraded" outcomes, document a deliberate update procedure, and consider
failing on an explicitly requested nonexistent template. Avoid overwriting
user customizations in the name of synchronization.

### 8. Scaffolds and publication are opinionated and partially dependent on HOME

Go modules hardcode `github.com/raymonepping/<project>` and default to Go 1.22;
lint configuration may need review against the installed golangci-lint.
Node's generated test is a placeholder. Python's Dependabot configuration has
no accompanying dependency manifest. Unknown types produce a generic project
after a warning. Licence download failure is nonfatal, and `--no-github` still
attempts that download. Optional scan workflows come from HOME and may be absent.

Publishing failures leave an already-created local project; there is no
resume mode or rollback transaction. `folder_tree` runs after the initial
commit, so its output may remain uncommitted. At this review's 2.1.2 baseline,
the script had no version flag for comparing the installed binary to `.version`.

**Recommended change:** make repository owner/module paths configurable,
clarify minimal versus production-ready scaffolds, report optional omissions,
and document recovery from a failed remote publication. The version command is
implemented in 2.1.3; installation parity checks remain a follow-up.

### 9. Unrelated inherited files remain — housekeeping

`bin/CHANGELOG_tfc_controller.md`, `tpl/report.md.tpl`, and ignored
`reload_version.sh` refer to Terraform Cloud reporting/release workflows.
The pre-existing untracked `lib/document.sh` implements a Terraform Cloud
report renderer. No generator references to that renderer/template were
found. `.backup.yaml`'s narrow include list also predates the current layout;
it does not explicitly list the tests, formula, docs or Codex assets.

**Recommended change:** confirm provenance and callers before removing these
files; update backup scope to include the actual source distribution. They
were preserved during this review. They are not part of the article's
claimed generator architecture or the formula's installed runtime.

## Verification performed

- Nine integration test methods passed on macOS system Bash, with additional
  scenarios/subtests for types and instruction layouts.
- `bash -n bin/generate_project.sh` and ShellCheck passed.
- Isolated experiments confirmed the missing `.env` exclusions, global write
  on invalid new-project input, and the original root-Claude prefix defect.
- Previous packaging validation loaded the formula with Homebrew libraries
  and exercised its install/test blocks using the actual release archive in
  a temporary prefix. The 2.1.2 archive passed the same check, including a handwritten
  instruction file without a Stack line.
- No real GitHub publication, cloud resources, real secrets or
  sibling project services were used for the analysis experiments.

## Suggested sequence after the prefix patch

1. Fix mandatory ignores and hook preservation, with clean-HOME/index tests.
2. Validate every execution path before writes; clarify global ignore policy.
3. Add CI for the existing meaningful tests and publishing/helper stubs.
4. Improve install/version diagnostics and template outcome reporting.
5. Revisit configurable scaffold defaults and remove inherited files only
   after confirming ownership.

The Medium draft in `article/01_generate_project.md` explains the implemented
workflow and these practical boundaries. It is not a claim that every open
finding has been resolved.

## Editorial source material

The Medium draft uses the owner's four prior articles as historical context
and motivation. These local reference copies are ignored in `input/`; they
are not required to run or package the generator. Their historical examples
are not treated as proof of current behavior.

| Local source | Article | Contribution to the new draft |
| --- | --- | --- |
| `input/03.md` | Automating Docker Compose project setup and Git Integration, 2024-07-31 | Repetitive setup, consistent layouts, initial publication versus subsequent commits. |
| `input/01.md` | End-to-End Project Bootstrapping: Quality Checks Meet Terraform Automation, 2025-06-27 | Integrating checks with creation and keeping Terraform scaffolding modular. |
| `input/02.md` | Streamlining Project Creation and Container Builds with HashiCorp Packer and Automation, 2025-06-28 | Traceability across source, builds, versioning and scans; adjacent tooling remains separate. |
| `input/04.md` | Automating Project Structure Insights with Folder_Tree, 2025-06-30 | Understandable structure and documentation as an ongoing workflow. |

The new article extends that history to reusable agent context, retaining
current-code qualifications rather than repeating earlier blanket claims
about guaranteed quality, security or reproducibility.
