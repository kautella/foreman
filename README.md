# Foreman

Foreman is an open-source execution-supervision system for coding-agent work in Git repositories.

It turns approved execution plans into bounded tasks, isolates concurrent work, supervises workers, preserves durable evidence, validates results, and applies explicit delivery policy.

> **Status: early development.** Foreman is not yet usable for production orchestration.

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

The canonical project documentation lives in [`brain/`](brain/README.md):

- [Vision](brain/vision.md)
- [Product requirements](brain/prd.md)
- [Architecture](brain/architecture.md)
- [Upstream map](brain/upstream-map.md)
- [Phase 1 backlog](brain/phase-1-backlog.md)
- [Current focus](brain/current-focus.md)
- [Progress](brain/progress.md)

## Provenance

Foreman is an independent project. Its initial design and selected implementation work draw on FirstMate as a reference for orchestration behavior, safety properties, and operational lessons.

Foreman is not a fork and does not provide FirstMate compatibility. Exact source provenance, attribution, and ongoing upstream-intake policy are documented in [`brain/upstream-map.md`](brain/upstream-map.md). Required license attribution will be recorded in `NOTICE.md` before any source import.

## License

[MIT](LICENSE)
