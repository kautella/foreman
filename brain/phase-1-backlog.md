# Foreman Phase 1 Backlog

**Status:** Approved
**Objective:** Establish an independent, safe Foreman foundation: auditable upstream provenance, contained test evidence, reviewed configuration, plan intake, HTML plan review, and enforceable core boundaries.

Phase 1 does not launch coding agents, create task worktrees, or mutate remotes. Its output is the trustworthy gateway through which future execution work enters Foreman.

## Phase 1 outcome

At exit, Foreman can:

1. Verify its prerequisites and initialize `FOREMAN_HOME`.
2. Register a Git project through an explicit reviewed configuration transaction.
3. Accept a direct plan, external handover, or guided-drafting proposal.
4. Normalize accepted input to versioned execution-plan JSON.
5. Render a standalone `plan-{slug}.html` review artifact.
6. Require explicit approval before any future task initialization.
7. Validate built-in adapter contracts without invoking provider executables from the core.
8. Use a verified external FirstMate reference and safe test evidence.
9. Support both Codex-operated checkout use and direct executable use through one generated launcher and tracked implementation.

It must not claim worker, runtime, remote, delivery, or merge functionality before those capabilities have implementation and evidence.

## Planning principles

- The initial upstream source revision remains `3f035336f9df7331e195bc6279cc1577e1cf4b49`.
- The FirstMate source baseline is an external development reference. No copied source tree, source instruction, source state, or reference location is committed to this repository.
- The upstream root `AGENTS.md` must never enter a Foreman instruction surface.
- Foreman's active implementation lives under `src/`, with developer and installation utilities under `scripts/` and validation under `tests/`.
- `jq`, Bash, and Git are initial core prerequisites.
- JSON is the only configuration and mechanically consumed state format.
- The active codebase contains no FirstMate terminology, compatibility aliases, or provider calls outside their adapters.
- Source tests with cleanup behavior run only in an expendable clone.

## Backlog

| ID | Work | Acceptance criteria |
|---|---|---|
| F1-001 | Verify external source reference | Verify the source URL, pinned revision, license, archive checksum, and full inventory outside the Foreman repository. Exclude upstream `AGENTS.md` from Foreman instruction surfaces. Do not commit a source snapshot, source instructions, source state, or external reference location. |
| F1-002 | Contain inherited test execution | Reproduce the existing fixture-cleanup risk only in an expendable clone. Define validated temporary roots, exact ownership markers, control-directory survival checks, interruption cleanup, and refusal for broad or ambiguous paths. |
| F1-003 | Produce a trustworthy baseline report | Record syntax, portable-test, lint, tool-version, and known-failure evidence for the pinned source revision. Separate harness defects, gated tests, and product defects. |
| F1-004 | Create the active Foreman skeleton | Establish the approved `src/` implementation layout, neutral CLI surface, Foreman-owned root project instructions, generated root launcher, test layout, and documentation routing. Codex can operate from the checkout, and external callers can use the same executable surface. No FirstMate executable path or instruction becomes an active Foreman surface. |
| F1-005 | Define configuration contracts | Create strict versioned schemas for global and project JSON configuration, including project identity, canonical paths, worker profile, runtime, delivery policy, merge authority, and validation requirements. |
| F1-006 | Implement reviewed initialization | Implement `foreman init` and `foreman doctor`. Initialization canonicalizes the target path, detects Git and remote capability read-only, resolves missing worker-profile choices, renders effective configuration, and persists only after explicit confirmation. |
| F1-007 | Implement path and state safety | Reject unsafe home, project, worktree, symlink, nested-root, and identity combinations. Use atomic writes and fail closed on malformed or unsupported configuration. |
| F1-008 | Define plan-exchange contracts | Create the human plan template, machine-readable schema and example, external-handover envelope, normalization rules, validation diagnostics, and unresolved-decision model. |
| F1-009 | Implement plan review | Create deterministic plan IDs, canonical `plan.json`, and standalone semantic `plan-{slug}.html` artifacts with embedded CSS. Plans remain unexecutable until explicit approval. |
| F1-010 | Define adapter contracts | Create versioned agent, runtime, and remote adapter manifests plus normalized input and output contracts. The core validates identities, operations, capabilities, and structured results without direct provider calls. |
| F1-011 | Enforce active-code boundaries | Add provider-boundary, prohibited-terminology, external-source, and compatibility-path scans. Scans cover shell, Python, JavaScript, TypeScript, instructions, hooks, schemas, and fixtures. |
| F1-012 | Establish development checks | Add repository-appropriate pre-commit checks, portable test entry points, formatting and syntax validation, installer and launcher safety tests, and a contributor workflow for safe fixtures, schemas, and adapter boundaries. |
| F1-013 | Start upstream intake | Create the first read-only upstream discovery record covering changes after `3f03533`. Classify findings as adopt, defer, decline, or inform, without importing later changes automatically. |
| F1-014 | Produce Phase 1 readiness evidence | Produce an HTML readiness report confirming provenance, containment, initialization, plan review, contract validation, boundary scans, and all remaining blockers. |

## Required execution order

```text
F1-001
   |
   +--> F1-002 --> F1-003
   |
   +--> F1-004 --> F1-005 --> F1-006 --> F1-007
   |                              |
   |                              +--> F1-008 --> F1-009
   |
   +--> F1-010 --> F1-011 --> F1-012
   |
   +--> F1-013
                \
                 --> F1-014
```

F1-003 must complete before any inherited source test becomes evidence for Foreman behavior. F1-009 and F1-011 must complete before Phase 2 can initialize a task or invoke a worker.

## Phase 1 exit criteria

- The pinned FirstMate source reference and its license are auditable without a copied source tree in the repository.
- Upstream `AGENTS.md` is absent from Foreman instruction surfaces, and all active Foreman project instructions are Foreman-owned.
- Destructive inherited tests are contained in disposable environments.
- Foreman configuration is schema-validated, path-safe, atomically persisted, and explicitly confirmed.
- Direct plans, external handovers, and guided drafting produce validated canonical plan JSON.
- Every proposed plan receives a portable HTML review artifact and cannot execute before approval.
- The core validates adapter contracts without directly invoking agent, runtime, or remote executables.
- Boundary scans reject active nautical terminology, FirstMate compatibility paths, and direct provider calls outside adapters.
- Development checks and contributor guidance are active.
- The ignored root launcher is reproducibly generated, safely refreshed, usable through an explicit external link, and refuses unowned replacement targets.
- The first ongoing-upstream intake record exists.
- No Phase 2 blocker is unresolved.

## Explicitly deferred

- Git worktree allocation and task execution.
- Launching or supervising any coding agent.
- tmux and Herdr implementations.
- All supported agent implementations.
- Change-task commits, research-task execution, delivery, teardown, recovery, and status operations.
- GitHub or GitLab authentication and remote mutation.
- Automated change requests and merge autonomy.
- Persistent supervisory tasks and the remaining orchestration parity surface.

## Later phases

| Phase | Objective | Exit outcome |
|---|---|---|
| Phase 2 | Local-only vertical slice | A Codex CLI and tmux reference path completes approved change and research tasks: isolated worktree, validation, durable result, draft handoff, manual local landing, recovery, and safe teardown. |
| Phase 3 | Adapter support matrix | Herdr and the remaining supported agent adapters reach their contract and lifecycle evidence. Missing or unavailable adapters always fail clearly, never silently substitute. |
| Phase 4 | Remote delivery parity | GitHub and GitLab support draft handoff, automated change requests, checks or pipelines, landing observation, explicit merge authority, and separately enabled merge autonomy. |
| Phase 5 | Remaining orchestration parity | Neutral status, resume, away supervision, checkpointing, updates, persistent supervisory tasks, durable handoffs, and the remaining retained FirstMate outcomes are implemented. |
| Phase 6 | Release hardening | Cross-platform, concurrency, security, upgrade, soak, source-intake, documentation, and complete release-acceptance evidence are complete. |

Upstream discovery continues through every phase. Candidate adoption is sequenced into the appropriate phase rather than allowed to bypass the architecture or current safety work.
