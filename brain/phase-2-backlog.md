# Foreman Phase 2 Backlog

**Status:** Approved
**Objective:** Deliver one safe, local-only vertical slice: an approved task runs through Codex CLI in tmux, preserves durable evidence, produces either a change handoff or research report, and can be reconciled and safely torn down.

## Phase boundary

Phase 2 supports:

- Codex CLI and tmux only.
- Local-only projects with `draft-handoff`; no remote tooling is required or used.
- One active task per project at a time.
- Change and research tasks.
- Explicit local commit authority within an approved, task-owned change branch.
- Durable task state, validation evidence, local handoff, interruption recovery, and safe teardown.

Phase 2 does not support:

- Herdr or any other agent or runtime adapter.
- Parallel task execution.
- GitHub or GitLab mutation, change requests, merges, or automated delivery.
- Automatic local landing or automatic teardown.
- Persistent supervision after the current Foreman invocation ends.

## Execution model

- A change task receives a task-owned branch and isolated worktree at an exact base commit. Codex runs there with the least writable sandbox needed.
- A research task receives an isolated, detached worktree at an exact base commit. Codex runs read-only; unexpected edits fail the task and preserve the worktree for inspection.
- Foreman writes the task brief, configuration snapshot, event log, validation evidence, result, handoff, and report. Workers do not write Foreman state directly.
- The Codex adapter owns Codex discovery, launch arguments, profile resolution, and JSONL interpretation. The tmux adapter owns session creation, inspection, bounded capture, and owned-endpoint closure. The core owns lifecycle and safety decisions.
- A task begins only after Foreman has persisted its immutable identity, configuration snapshot, worktree identity, and runtime endpoint reservation.

## Backlog

| ID | Work | Acceptance criteria |
|---|---|---|
| P2-000 | Complete — record the pre-Phase-2 upstream intake | Dark external report created for `b182d0f..9ad5fc4`, with all 22 commits classified and the identity-before-launch and validation-state lessons recorded. No external source code was imported. |
| P2-001 | Complete — define task contracts and lifecycle | Added strict JSON schemas, examples, closed-shape validators, and portable transition evidence for task metadata, configuration snapshots, runtime endpoints, events, validation records, results, local handoffs, and research findings. `blocked`, `failed`, `missing`, `unreachable`, and `unknown` remain separate non-completion conditions. |
| P2-002 | Complete — add lock and durable-state safety | Implemented exact-owner project and task locks, stale-lock refusal, symbolic-link-safe atomic writes, and lock-protected append-only JSONL events with contiguous sequence and unique identity checks. Portable evidence passed on stock macOS Bash 3.2. |
| P2-003 | Complete — allocate isolated task environments | Implemented project-lock-protected change and detached research worktree allocation from exact full base commits, with external strict ownership markers. Portable fixtures prove clean setup and refuse unsafe roots, dirty or ambiguous repositories, collisions, nested targets, in-worktree markers, and unowned resources. |
| P2-004 | Complete — implement the Codex CLI adapter | Implemented portable Codex executable and authentication diagnosis, exact profile-to-launch-spec resolution, task-type sandbox selection, and bounded JSONL plus structured final-output collection. The adapter remains `implemented-unverified`; no real Codex task has been run. |
| P2-005 | Complete — implement the tmux adapter | Implemented portable tmux diagnosis, exact endpoint reservation, validated-spec launch through an owned runner, liveness inspection, 64 KiB capture, and proven-owned session closure. The adapter remains `implemented-unverified`; tmux is unavailable on the current host. |
| P2-006 | Complete — launch and reconcile approved tasks | Added the neutral `task start`, `task status`, and `task reconcile` surface. It starts only one approved local Codex/tmux task after identity, configuration, worktree, endpoint, and event evidence are durable; it refuses unapproved plans, unavailable adapters, unsafe references, mismatched identities, and ambiguous state. |
| P2-007 | Complete — validate and prepare local handoffs | Added terminal-evidence collection, declared validation records, exact Git checks, local change handoffs, and standalone dark research reports. The path does not push, publish, merge, land, discard, or tear down work. |
| P2-008 | Complete — recover and tear down safely | Reconciliation now verifies the exact task marker, Git worktree identity, runtime state, and available structured worker evidence before altering lifecycle state. `task teardown` preserves uncertainty and accepts only a verified local landing commit or explicit `--discard` for the exact task; it retains a strict durable teardown record after removal. Portable landed, discard, recovery, and refusal paths pass. |
| P2-009 | Active — establish verification evidence | The portable fakes and disposable Git fixtures now cover isolation, locks, recovery, validation, handoff, refusal, and the opt-in live-harness contract. `scripts/live-check.sh` adds durable caller-selected evidence for a real tmux lifecycle with a harmless fake worker and a separately explicit real Codex research task. The real checks remain pending: tmux is absent on the current host, Codex CLI is not authenticated, and the Codex run needs explicit usage approval at execution time. |
| P2-010 | Publish Phase 2 readiness evidence | Generate a dark external readiness report showing the complete local-only change and research paths, remaining limitations, and verification results. |

## Required sequence

```text
P2-000
   ↓
P2-001 → P2-002 → P2-003
                    ↓
             P2-004 + P2-005
                    ↓
                  P2-006
                    ↓
                  P2-007
                    ↓
                  P2-008
                    ↓
                  P2-009 → P2-010
```

## Phase 2 exit criteria

- A local-only approved change task receives an isolated task branch and worktree, completes through the Codex CLI and tmux adapters, records validation, and produces a draft handoff without remote mutation or local landing.
- A local-only approved research task runs read-only from an isolated exact-base worktree and produces a standalone, always-dark report.
- Task identity, configuration snapshot, runtime endpoint, events, validation, result, and handoff survive an interrupted Foreman invocation and reconcile without unsafe replacement or teardown.
- Project and task locks prevent conflicting mutation. Worktree, endpoint, branch, ownership, and landing ambiguity preserve work and block mutation.
- Codex and tmux have portable contract tests and opt-in live evidence. Neither is represented as supported before that evidence exists.
- All Phase 1 boundary, terminology, contract, installation, and portability checks continue to pass.

## Prerequisites

- tmux must be available on the execution host before live tmux evidence can run.
- Portable tests use fakes. A real Codex end-to-end check consumes account usage and requires explicit approval at the time it is run.
- The complete upstream-intake record in P2-000 must exist before worker, worktree, recovery, or teardown implementation begins.

## Later-phase boundary

Phase 3 adds Herdr and the remaining approved agent adapters. Phase 4 adds remote delivery. Phase 5 adds broader supervision and concurrency outcomes. No Phase 2 task may bypass those boundaries.
