# Why I Built generate_project: From Repeatable Setup to Claude Code and Codex

*The same idea behind my Docker Compose, Terraform, container-build and
folder-structure articles now extends to the context coding agents need.*

Create a directory. Copy the ignore files. Add a README and a licence.
Initialize Git, name the branch, create the GitHub repository and push the
first commit. Then remember the formatting checks, the container exclusions
and the documentation that explain what belongs where.

Each step is small. Together, they are a setup routine I kept repeating
across infrastructure experiments and application projects. I wanted that
routine written down in something I could run, inspect and improve.

That is why I built
[`generate_project`](https://github.com/raymonepping/generate_project). It
turns my preferred starting sequence into a Bash command, while leaving
room for the different things a Terraform project, a Node application or a
Go CLI actually needs.

Claude Code and Codex are the latest addition to that sequence. Once a coding
agent joins the workflow, a repository also needs discoverable instructions:
which checks matter, where the project context lives, and which resources
belong to this project. Preparing those instructions belongs alongside the
other setup steps I do not want to reconstruct every time.

## Four earlier articles explain the motivation

In *Automating Docker Compose project setup and Git Integration*
(July 31, 2024), I focused on the repetitive mechanics: create a consistent
layout, initialize the repository and connect it to GitHub. The separate
commit helper handled later changes. The useful boundary was already there:
project creation and ongoing development need different operations.

*End-to-End Project Bootstrapping: Quality Checks Meet Terraform Automation*
(June 27, 2025) added another reason to automate the start. A consistent
folder structure is only part of the job; formatting and linting need to
be part of the normal workflow too. That article connected `generate_project`,
`sanity_check`, Terraform scaffolding and `commit_gh`, so checks were less
dependent on remembering another command before a commit.

The next article, *Streamlining Project Creation and Container Builds with
HashiCorp Packer and Automation* (June 28, 2025), followed the repository
into image builds, versioning and scanning. The motivation was traceability:
being able to relate the source, the build and the scan output. Those are
adjacent tools in a larger workflow; today's `generate_project` does not
itself implement the Packer build or the entire scanning pipeline.

*Automating Project Structure Insights with Folder_Tree* (June 30, 2025)
addressed what happens after files start accumulating. A readable, filtered
view of the repository helps explain the relationship between infrastructure,
application code and supporting files. `folder_tree` made that overview
another repeatable step rather than documentation I had to assemble by hand.

Together, those articles describe what I want from the toolbox: repeatable
setup, checks close to the work, traceable changes and a structure I can
understand when I return to it. The tools stay separate because their jobs
are different. The generator connects the pieces available on my machine.

## The next session also needs context

A folder tree helps a reader find the code. It does not tell a coding agent
which test is a placeholder, how to run a meaningful check, or which Podman
containers it may operate on. I was now repeating that context at the start
of sessions, just as I had once repeated the Git setup.

Claude added support for its workspace files. Extending the same project
for Codex made the next requirement clear: prepare a shared project
convention in each tool's native layout. The command should give a new
session useful context without replacing an existing project's instructions.

## Start with a local project

Here is a small Node example:

```sh
generate_project --project demo_crypto --type node --prefix demo --no-github
```

This creates `./demo_crypto`, writes the starter application, prepares the
assistant files and makes an initial Git commit on `main`. `--no-github`
skips remote publication. It does not promise a completely offline run:
the script still attempts to download the GPL-3.0 licence text.

The supported types are Node, Python, Terraform, Docker, Podman and Go. They are
deliberately small starting points. The Podman scaffold uses a `Containerfile`,
`.containerignore` and Make targets for building, running and removing its
project-scoped image. The Node test initially prints `ok`;
it is not evidence that an application has meaningful test coverage. The
Go scaffold targets a native CLI, so it gets neither a Dockerfile nor a
Docker ignore file.

To publish immediately, the command can use an authenticated GitHub CLI:

```sh
generate_project --project demo_crypto --type node --prefix demo --private
```

Use a fresh name or directory when trying these examples. Creation refuses
an existing nonempty project. Remote repositories default to public unless
`--private` is supplied, so I prefer to make that choice explicit.

## Put context where each agent reads it

The local assistant layout looks like this:

```text
demo_crypto/
├── package.json
├── index.js
├── README.md
├── AGENTS.md
├── .agents/
│   └── skills/
│       ├── project-checks/SKILL.md
│       └── scoped-resources/SKILL.md
├── .codex/
│   └── config.toml
└── .claude/
    ├── CLAUDE.md
    └── ...personal template content, when configured
```

For Codex, root `AGENTS.md` carries the project guidance, `.agents/skills/`
holds reusable workflows, and `.codex/config.toml` holds optional project
settings. Those roles and locations follow the official guides for
[instructions](https://learn.chatgpt.com/docs/agent-configuration/agents-md),
[skills](https://learn.chatgpt.com/docs/build-skills), and
[configuration](https://learn.chatgpt.com/docs/config-file/config-basic).

The generated Codex configuration is intentionally just comments. It does
not choose a model, weaken approval settings, or configure a remote service.
Personal defaults remain inherited, and project configuration still follows
Codex's normal trust rules.

Claude's template uses `.claude/CLAUDE.md` and may include skills, subagents
and local settings. Claude documents both project instruction files and
their discovery in its [memory guide](https://code.claude.com/docs/en/memory).
Its hooks and agent definitions need review before being carried into a
different tool. Copying a directory name does not translate those contracts.

## Keep the instructions short and the skills specific

The generated instructions contain the stack, starter commands and a
resource prefix. The two bundled Codex skills handle recurring tasks that
need a little more explanation.

`project-checks` tells the agent to inspect the actual build configuration.
It calls out details such as the placeholder Node test and the Go lint
target that can succeed while skipping an unavailable linter. That helps
the final report distinguish a check that passed from one that never ran.

`scoped-resources` explains how to use the recorded prefix when operating
containers, Multipass VMs and OpenShift resources. Matching a name scopes
the target; it does not grant permission to delete it.

I would rather maintain those focused workflows than install a large skill
collection into every repository. Frontend design skills, for example, can
be valuable in a UI project, but they need their scripts, references and
tool assumptions reviewed before becoming part of a default template.

## Give resources an explicit prefix

The `--prefix demo` option records this instruction:

```text
- Resource prefix: `demo-`. Filter every podman, multipass and oc command by it; never touch resources with another prefix.
```

The accepted value is one to twelve lowercase letters or digits, starting
with a letter. `demo` and `demo-` normalize to `demo-`. Values such as `Demo`
or `Bad!` are rejected. Without the flag, the starter instruction leaves a
visible placeholder asking for a prefix.

This is a convention for the agent to follow, not an access-control
boundary. Podman permissions, cluster RBAC and the execution environment
still enforce actual authority. The value also needs to describe the
project's real resources; inventing a different prefix for an existing lab
can make the guidance misleading.

## Existing repositories need a different operation

Creating a starter project and adding assistant context to an established
project are different jobs. Retrofit has its own mode:

```sh
generate_project --codex-only ./existing-project --prefix demo
```

The equivalent explicit target selection is:

```sh
generate_project --project existing-project --codex-only --prefix demo
```

The target must already exist. Retrofit does not scaffold the application,
commit its changes or publish it. With no target, it uses the current
directory. To create a new project with Codex and skip Claude, use
`--project <name> --no-claude` instead.

That distinction exposed the first important bug: `--codex-only` originally
used the current directory even when `--project` was present. The command
looked successful while preparing the parent folder. The corrected parser
honors the named target and rejects conflicting target arguments.

A second bug appeared in the generator's own handwritten `AGENTS.md`. It
had an Operate section but no `- Stack:` line, which prefix insertion had
assumed would exist. The command warned that I needed to add the line
myself, then printed its normal completion message.

The fix made prefix recording work with existing layouts: fill a known
placeholder, insert after Stack when present, otherwise insert under
Operate, or append an Operate section. Existing concrete prefixes remain
unchanged. The same handling now reaches an existing root `CLAUDE.md`.

These were small failures, but both mattered because the application code
was fine. A scaffold can generate valid files and still prepare the wrong
context for the next session.

## Repair conservatively

Retrofit preserves existing configuration and skill directories. It can
repair a broken skill symlink or a file stub left by a bad copy, and source
skill links are dereferenced when new copies are installed.

It is an additive repair operation, not a synchronization service. If an
installed skill directory already exists, a newer template does not replace
it or merge new files into it. That protects local edits, but it also means
template upgrades need a deliberate procedure.

For Codex, a personal template at
`~/.config/generate_project/codex/` takes precedence over the bundled
`tpl/codex/`. An environment variable or `--codex-template` can select
another location. Claude's private template lives separately at
`~/.config/generate_project/claude/`.

This keeps personal third-party content outside the generator's source
distribution while letting the first-party Codex template travel with the
package.

## Make the publication boundary visible

This project chooses to keep generated assistant guidance local. Other
teams may reasonably commit shared guidance; that is a repository policy,
not a requirement imposed by Codex or Claude.

For new projects, the generator writes assistant exclusions into Git and
Docker ignore files where applicable. Before making the initial commit,
it also checks the staged paths and refuses assistant tooling. In an
existing Git repository, retrofit adds local rules in `.git/info/exclude`.

That last detail matters: [Git's ignore rules](https://git-scm.com/docs/gitignore)
do not untrack files already in the repository. The tool warns about those
files instead of silently removing them from version control.

Ignoring a file also does not prevent an assistant service from receiving
its content. These rules control ordinary Git staging and build contexts;
they do not provide encryption or a data-sharing policy.

## Test the lifecycle, including the fallback paths

The integration suite uses temporary workspaces and HOME directories,
real local Git repositories, and a stub that blocks the licence download.
It avoids publishing test repositories or running optional machine-wide
helpers. The current nine test methods include scenarios for every scaffold
type, target selection, prefix normalization, custom templates, repair,
opt-out and repeated runs.

```sh
python3 -m unittest discover -s tests -v
bash -n bin/generate_project.sh
shellcheck bin/generate_project.sh
```

The review also found an important gap: the normal test fixture supplies
an ignore template containing `.env`. With no global template, the current
fallback can commit the initially empty `.env`, and its Docker fallback
does not exclude environment files. That needs a built-in exclusion
baseline and clean-home regression coverage before treating the defaults
as a complete secret-protection setup.

There are other follow-ups: preserve inherited pre-commit hooks rather than
replacing them, validate all inputs before global writes, and run the
behavioral suite in CI alongside secret scanning. The detailed
[project analysis](https://github.com/raymonepping/generate_project/blob/main/docs/project-analysis.md)
records those findings and their priority.

## Package the context with the command

A standalone script is convenient, but copying only the executable loses
the bundled templates. The Homebrew formula therefore installs `bin` and
`tpl` together and writes a wrapper that invokes Homebrew Bash. Its source
archive is pinned with a verified SHA-256 checksum.

For a manual user-local installation, the same relationship can be kept
explicit:

```sh
git clone https://github.com/raymonepping/generate_project.git
cd generate_project

mkdir -p "$HOME/bin" "$HOME/.config/generate_project/codex"
cp -R tpl/codex/. "$HOME/.config/generate_project/codex/"
cp bin/generate_project.sh "$HOME/bin/generate_project"
chmod 755 "$HOME/bin/generate_project"
export PATH="$HOME/bin:$PATH"
```

The template-copy step is for a first installation. Review an existing
personal template before replacing it. Making the PATH change persistent
is a separate shell configuration choice.

The initial commit inside a newly generated project currently uses `git`
and `gh` directly. Maintaining the generator itself uses `commit_gh` in my
workflow; detecting that helper inside the script is not the same as
delegating every generated commit to it.

The reason I keep extending this tool is the same reason I wrote the earlier
scripts. Once I have decided how I want to start and explain a project, I
want that decision to survive beyond the terminal session where I made it.

The first version remembered the repository setup. The surrounding tools
added checks, build records and a readable structure. This version also
remembers the context Claude Code and Codex need when they open the project.
I can still inspect every generated file, and the next improvement can start
with a concrete failure and a test instead of another setup checklist.
