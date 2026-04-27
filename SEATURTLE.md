# SEATURTLE.md

This file provides guidance to CT (ct) when working with code in this repository.

## Repository state

- As of 2026-04-26, this repository contains only Git metadata under `.git/`.
- No application source files, README, package manifests, build configuration, test configuration, Cursor rules, or Copilot instructions are present yet.

## Commands

There are currently no project commands to run.

Before assuming build, lint, or test workflows exist, check for newly added manifests/config such as:

- `package.json`
- `pyproject.toml`
- `Cargo.toml`
- `go.mod`
- `Makefile`
- `README.md`
- `.github/copilot-instructions.md`
- `.cursorrules` or `.cursor/rules/`

## Architecture

There is no codebase to summarize yet.

Once code is added, update this file with:

- the primary runtime/framework
- the entry points and top-level app flow
- where core domain logic lives versus UI/integration code
- the authoritative build/lint/test commands
- any non-obvious project-specific instructions from README/Cursor/Copilot files

## Agent Behavioral Directives (Feedback)
- **Do not be overconfident:** Validate assumptions before claiming a feature is complete or production-ready.
- **Test rigorously against intent:** Don't just finish the task mechanically; ensure the end result actually works for the user's intended use case.
- **Check upstream research/documentation:** If an API behaves unexpectedly (like Apple's `Translation` framework), consult the official documentation instead of guessing or hand-waving the issue away as "finicky."
- **Focus on robustness:** Ensure architectural resilience (e.g., transcripts shouldn't disappear just because the translation API throws an error).
