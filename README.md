# Foreman

Foreman is an open-source execution-supervision system for coding-agent work in Git repositories.

It turns approved execution plans into bounded tasks, isolates concurrent work, supervises workers, preserves durable evidence, validates results, and applies explicit delivery policy.

> **Status: early development.** Foreman is not yet usable for production orchestration.

## Two ways to use the repository

Foreman supports the same product surface from two entry paths:

- Clone the repository, open it with Codex, and work from the checkout. Repository instructions tell Codex to generate the local `./foreman` launcher when it is needed.
- Generate the launcher yourself and call it from this checkout or through an optional link in your preferred executable directory.

```sh
./scripts/install.sh
./foreman --help
```

To make the command available elsewhere, choose an absolute executable directory:

```sh
./scripts/install.sh --link /absolute/path/to/bin
```

The root `foreman` file is generated and ignored by Git. It always delegates to the tracked implementation under `src/`, so both entry paths run the same code.

## Why Foreman

Coordinating coding agents across several tasks requires reliable worktree isolation, worker supervision, recovery, validation, delivery controls, and durable state.

Foreman is designed to make that operational layer inspectable and safe without taking ownership of product strategy.

## Intended capabilities

Foreman is being built to provide:

- reviewed plan intake from direct user plans, external handovers, or guided drafting;
- isolated change and research tasks;
- durable task state, validation evidence, reports, and recovery information;
- complete local-Git workflows with no hosted remote required;
- built-in adapters for Claude Code, Codex CLI, Gemini CLI, OpenCode, and Pi;
- tmux and Herdr runtime adapters;
- optional GitHub and GitLab delivery capabilities;
- explicit delivery policy and separately controlled merge autonomy;
- standalone HTML plan-review and research-report artifacts.

A capability is not considered supported until it has implementation and verification evidence.

## Principles

- Local Git is a complete workflow.
- Plans are reviewed before execution.
- Authority is explicit.
- Ambiguity preserves work and blocks mutation.
- Durable state beats conversation memory.
- Provider-specific behavior remains behind adapters.
- Communication is neutral and ordinary.

## Project documentation

To try the currently implemented initialization and plan-review surface, see [Getting started](docs/getting-started.md).

The canonical project documentation lives in [`brain/`](brain/README.md):

- [Vision](brain/vision.md)
- [Product requirements](brain/prd.md)
- [Architecture](brain/architecture.md)
- [Upstream map](brain/upstream-map.md)
- [Phase 1 backlog](brain/phase-1-backlog.md)
- [Current focus](brain/current-focus.md)
- [Progress](brain/progress.md)

## Opt-in live verification

Portable tests use disposable fakes and never consume coding-agent usage. Phase 2's local Codex-and-tmux execution path has both portable and real-environment evidence. The adapter manifests remain `implemented-unverified`: broader declared operations such as resume and interrupt are not implemented or verified in this local-only vertical slice.

When the host has tmux, exercise the real tmux adapter with a harmless fake worker and retain the resulting evidence in a new directory:

```sh
./scripts/live-check.sh --tmux --evidence-dir /absolute/new/evidence-directory
```

One real, read-only Codex CLI task is separately gated because it consumes account usage. Supply the exact model and reasoning level and the explicit usage flag only when that run is intended:

```sh
./scripts/live-check.sh --codex-task --allow-codex-usage \
  --model MODEL --reasoning REASONING \
  --evidence-dir /absolute/new/evidence-directory
```

The script creates a disposable Git repository inside the evidence directory, preserves all evidence on success or failure, never contacts a remote, and tears down only its exact task-owned worktree after the research report is produced.

## Provenance

Foreman is an independent project. Its initial design and selected implementation work draw on FirstMate as a reference for orchestration behavior, safety properties, and operational lessons.

Foreman is not a fork and does not provide FirstMate compatibility. Its source relationship and ongoing upstream-intake policy are documented in [`brain/upstream-map.md`](brain/upstream-map.md).

## License

[MIT](LICENSE)
