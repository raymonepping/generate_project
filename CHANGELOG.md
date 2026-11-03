# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.1.1] - 2026-11-03

### Fixed
- Honor `--project <dir>` in Codex and Claude retrofit modes instead of silently
  modifying the current directory. Reject ambiguous or missing targets before
  changing any files.
- Correct the Homebrew formula to install generate_project and its bundled Codex
  templates from the verified v2.1.0 archive, instead of tfc_controller.

## [2.1.0] - 2026-11-03

### Added
- Local Codex workspaces with root instructions, discoverable skills, optional
  project config, custom templates, opt-out and idempotent retrofit options.
- Project validation and prefix-scoped resource skills, plus migration guidance.
- Offline integration coverage for every scaffold type and retrofit behavior.
- Claude workspace templates, retrofit support and resource prefix instructions.

### Changed
- Keep Codex instruction files out of generated commits and container builds.
