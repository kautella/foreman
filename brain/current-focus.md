# Current Focus

## Current objective

Execute the approved Phase 2 local-only Codex CLI and tmux vertical slice. P2-000 upstream intake through P2-008 recovery and safe teardown are complete. P2-009's portable evidence, live harness, and live tmux evidence are complete; its real Codex task evidence remains active pending explicit usage approval.

## Established state

The following approved documents remain the project contract:

- `vision.md`
- `prd.md`
- `architecture.md`
- `upstream-map.md`
- `phase-1-backlog.md`
- `phase-2-backlog.md`

Phase 1 merged to `main` as `65cbfb1` through pull request #1. Foreman now provides:

- a single tracked product tree under `src/`, a generated ignored root launcher, and a safe installer with an optional explicit executable-directory link;
- a neutral command surface with `init`, `doctor`, and reviewed `plan` workflows;
- strict versioned configuration, plan, handover, and adapter contracts;
- reviewed, atomic project initialization with Git identity and path-safety checks;
- direct-plan, external-handover, and guided-drafting intake that converges on canonical JSON;
- deterministic plan identity, standalone always-dark HTML review, blocking-decision handling, and explicit approval;
- contract-only definitions for the approved agent, runtime, and remote adapters;
- active-code boundary scans, portable tests, syntax and data validation, contributor guidance, and a clean pre-commit entry point;
- external source-baseline, upstream-intake, and Phase 1 readiness evidence.

The source reference remains pinned at `3f035336f9df7331e195bc6279cc1577e1cf4b49`. Its archive, license, inventory, contained tests, and known failures are recorded outside this repository. The first ongoing upstream discovery review covered 201 later commits through `b182d0f908b78d08c7ccb8dce3775bdca8c5d657` without automatically importing any change. P2-000 reviewed the next 22 commits through `9ad5fc4258c6c840958eabc15b41ad4bd3558739`, recorded every disposition in `~/.foreman/projects/foreman/reports/report-upstream-intake-2026-09-16.html`, and adopted only the identity-before-launch and durable-validation-state requirements.

## Approved Phase 2 boundary

Phase 2 is active on `feat/phase-2`. It implements one local-only vertical slice with Codex CLI and tmux only:

- one active local-only task per project at a time;
- change and research task flows with durable state and task-owned environments;
- Codex CLI and tmux implementations behind their adapter boundaries;
- validation evidence, local draft handoffs, recovery, and safe teardown;
- portable fakes plus opt-in live evidence before either adapter is represented as supported.

## Constraints

- GitHub, GitLab, Herdr, and all non-Codex agents remain deferred.
- No remote tooling, push, change-request publication, merge, automatic local landing, or automatic teardown is in scope.
- A change task may create local commits only on its exact task-owned branch; approval never authorizes rewriting unowned commits or landing work.
- A research task uses a detached, exact-base worktree and a read-only worker sandbox. Unexpected edits fail the task and preserve the worktree.
- The core must not invoke `codex` or `tmux` directly; the relevant adapter owns every provider call.
- Ambiguous identity, ownership, liveness, validation, delivery, landing, or teardown state preserves work and blocks mutation.
- Live tmux evidence must use a unique adapter-owned tmux server so it cannot adopt or affect an existing user session.

## Current sequence

1. P2-000 is complete: the full pre-Phase-2 upstream disposition is recorded as a dark external report.
2. P2-001 is complete: strict durable task contracts and lifecycle transition checks have portable evidence.
3. P2-002 is complete: exact-owner locks, atomic state writes, and append-only task events have portable evidence on stock macOS Bash 3.2.
4. P2-003 is complete: isolated exact-base change and detached research worktrees have external ownership markers and portable Git-fixture evidence.
5. P2-004 is complete: Codex diagnosis, profile-to-launch-spec resolution, and bounded structured-output collection have portable evidence.
6. P2-005 is complete: tmux endpoint reservation, launch, inspection, bounded capture, and exact-owned closure have portable evidence.
7. P2-006 is complete: the public task command starts, observes, and reconciles one durably identified local task.
8. P2-007 is complete: terminal worker evidence, declared validation, local handoffs, and dark research reports are durable.
9. P2-008 is complete: reconciliation verifies task-owned Git identity and available worker evidence, while teardown requires either proven local landing or an explicit exact-task discard authority.
10. P2-009 has added a portable live-harness contract and durable evidence layout. The real tmux lifecycle passed on 17 September 2026; one real Codex research task still needs current explicit usage approval.
11. P2-010 publishes the Phase 2 readiness evidence after P2-009's live results are available.

## Current verification boundary

The host has tmux `3.7c` and Codex CLI `0.147.0`. The real tmux lifecycle passed with a harmless fake worker; its durable evidence is at `~/.foreman/projects/foreman/evidence/live-tmux-2026-09-17-retry-2/`. The harness now selects a unique short tmux server name through the adapter, avoiding macOS Unix-socket path limits while staying isolated from user sessions. The maintainer reports the Codex CLI is authenticated; the real task preflight will record that status before any worker begins.

Do not run the real Codex mode until the maintainer explicitly authorizes that usage at the time of execution. Do not represent Codex CLI as supported until the live task passes and its evidence is reviewed.
