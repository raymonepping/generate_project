---
name: project-checks
description: Choose and run validation for changes in a project scaffolded by generate_project, using its actual stack and build configuration.
---

Read the root instructions and build configuration. The scaffold's starter
commands are hints; use the current scripts and targets when they differ.

- Node: inspect `package.json`; its initial `npm test` only prints `ok`, so it
  does not establish application correctness. Run meaningful checks available
  for the changed behavior and report if tests are still placeholders.
- Python: the starter has `app.py` and no test framework. Use existing project
  checks if present; do not claim that running the starter proves test coverage.
- Go: the generated Makefile provides `build`, `test`, and `lint`. Its lint
  target can succeed while skipping a missing `golangci-lint`; disclose that skip.
- Terraform: use `terraform fmt -check`; validation uses
  `terraform init -backend=false` then `terraform validate`. Initialization may
  need network access. Validation does not require applying infrastructure.
- Containers: the starter uses Podman, Docker format, and arm64 images. Read
  the Dockerfile and build configuration for the correct context and image name;
  follow the recorded resource prefix when naming resources.

Report which checks ran, their results, and any unavailable checks or placeholder
tests. Distinguish environment failures from failures introduced by the change.
