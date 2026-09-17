# Progress

## Status

Phase 1 merged to `main` through pull request #1 as `65cbfb1`. Phase 2 is approved and active on `feat/phase-2`.

Foreman has a tested foundation for project registration, reviewed plan intake, task launch, reconciliation, local terminal-result validation, safe local task-worktree teardown, and opt-in live-verification harnesses. It intentionally cannot yet represent Codex CLI or tmux as supported, deliver changes remotely, or merge work. P2-000 through P2-008 are complete; P2-009's portable evidence is complete and its live evidence remains active.

## Completed product foundation

- Established Foreman as an independent, provider-neutral execution-supervision project.
- Added the neutral `foreman` command with help, version, `init`, `doctor`, and `plan` command families.
- Consolidated all tracked product implementation, adapters, contracts, and artifact assets under `src/`; kept development and installation utilities under `scripts/`, and retained `tests/`, `docs/`, and `brain/` as focused top-level surfaces.
- Added a tracked installer that safely generates the ignored root `foreman` launcher and can create an explicitly requested link in an absolute executable directory.
- Made Codex-operated checkout use and direct executable use converge on the same `src/main.sh` entry point, with no product logic in the generated launcher.
- Added strict versioned JSON schemas for global configuration, project configuration, worker profiles, direct plan input, external handover, canonical plans, adapter manifests, adapter requests, and adapter results.
- Kept the supported agent set closed to Claude Code, Codex CLI, Gemini CLI, OpenCode, and Pi.
- Added contract-only manifests for those five agents, tmux, Herdr, GitHub, and GitLab without representing any provider as implemented.
- Kept provider host matching inside remote-adapter boundaries and rejected unknown identities, operations, capabilities, and malformed results.

## Completed initialization and safety

- Implemented reviewed project initialization that obtains the project name and root, exact Git identity, worker agent, model, reasoning level, runtime, worktree root, delivery policy, merge authority, validation requirements, and remote selection where applicable.
- Rendered the complete proposed global and project configuration before persistence and required explicit confirmation.
- Added read-only Git and remote detection. Remote presence never grants mutation authority.
- Added canonical absolute-path handling and rejected broad, relative, traversing, symbolic-link, nested, overlapping, duplicate, or identity-conflicting locations.
- Added atomic private configuration writes and fail-closed validation for malformed or unsupported state.
- Ensured rejected or incomplete initialization creates no Foreman home.
- Added `foreman doctor` checks for prerequisites, configuration, repository identity, paths, and selected contract identities.

## Completed plan gateway

- Added a human plan template, strict direct-plan and handover schemas, examples, normalization rules, diagnostics, and unresolved-decision handling.
- Implemented direct-plan intake, external handover, and guided drafting as three inputs to the same canonical plan contract.
- Added deterministic plan IDs and duplicate protection.
- Stored canonical plan JSON and rendered a standalone semantic `plan-{slug}.html` file with embedded CSS, an always-dark presentation, and escaped input.
- Prevented plan input from increasing project delivery or merge authority.
- Blocked invalid dependencies, dependency cycles, missing information, unresolved blocking decisions, and incomplete plans.
- Required explicit approval of the exact stored plan and recorded approval without creating tasks or starting work.

## Completed boundaries and development checks

- Added active-code scans that reject prohibited source terminology, compatibility paths, local source-reference paths, unexpected nested instructions, and direct provider invocation outside adapters.
- Added portable checks for the command surface, configuration contracts, initialization, path and state safety, plan review, adapter contracts, and source boundaries.
- Added portable installation checks for launcher generation, safe refresh, linked invocation, and refusal to overwrite an unowned launcher.
- Added JSON validation, Bash syntax validation, whitespace checks, IDE metadata checks, contributor guidance, and a pre-commit hook that cleanly calls the shared check runner.
- Verified all eight portable test files, the boundary scan, all tracked JSON, Bash syntax, generated-launcher ignore status, and diff checks.

## Completed source and upstream evidence

- Verified the pinned FirstMate revision `3f035336f9df7331e195bc6279cc1577e1cf4b49` as an external development reference, including its repository identity, MIT license, complete archive inventory, and archive checksum.
- Excluded the upstream root `AGENTS.md` from the inert reference so it cannot become a Foreman instruction surface.
- Kept the source snapshot, manifest, validation harness, test output, reports, and external reference location outside this repository.
- Reproduced the historical fixture cleanup defect only in a marked disposable repository and confirmed the pinned revision preserves the fixture root.
- Verified the disposable harness refuses broad, ambiguous, unowned, or tampered cleanup targets and preserves its control directory during normal and interrupted runs.
- Parsed 304 source shell files with no syntax failures and completed the source's pinned ShellCheck and workflow lint successfully.
- Mapped all 152 source tests: 140 portable scripts and 12 separately gated Herdr tests.
- Ran all 140 portable source tests in disposable clones. Of those, 129 passed and 11 failed; 25 expected environment or live gates were skipped within the executed scripts.
- Re-ran all 11 failures in a fresh disposable clone and reproduced every failure identically.
- Classified the failures into harness limitations, a missing prerequisite gate, relevant source safety defects, and defects in features excluded from Foreman. These are source evidence only, not Foreman failures.
- Completed the first ongoing upstream discovery review over 201 commits after the pin through `b182d0f908b78d08c7ccb8dce3775bdca8c5d657`.
- Routed useful compatibility, locking, teardown, delivery-truth, recovery, worker-profile, and testing lessons to future Foreman phases. No upstream change was imported automatically.
- Produced standalone external HTML reports for the source baseline, upstream intake, and Phase 1 readiness review; all Foreman plan and research reports now use an always-dark embedded presentation that does not vary with the viewer's system theme.

## Phase 1 verification

All F1-001 through F1-014 acceptance areas have evidence:

- provenance and instruction exclusion;
- disposable test containment;
- source syntax, lint, tool, coverage, gated-test, and failure classification;
- active Foreman structure and command namespace;
- repository-local and externally linked access through one safely generated executable;
- strict configuration and reviewed initialization;
- path, identity, and atomic-state safety;
- plan exchange, HTML review, and explicit approval;
- adapter contracts and provider boundaries;
- development checks and contributor workflow;
- selective upstream intake;
- final readiness assessment.

No unresolved Phase 1 blocker remains.

## Phase 2 evidence

- P2-000 completed on 16 September 2026. `~/.foreman/projects/foreman/reports/report-upstream-intake-2026-09-16.html` is a standalone, always-dark HTML report covering all 22 upstream commits from `b182d0f..9ad5fc4`.
- The intake adopted two Foreman-native requirements: persist task identity before a worker starts, and preserve an interrupted or paused validation outcome as non-completion. It deferred 12 changes to later phases, declined 6 as outside Foreman's approved boundary, and recorded 2 as informational. No external source code, tests, instructions, or configuration was imported.
- P2-001 completed on 16 September 2026. Added strict versioned JSON contracts and examples for task metadata, configuration snapshots, runtime endpoints, append-only events, validation records, results, local handoffs, and research findings under `src/contracts/task/`.
- `src/tasks/validate.sh` rejects malformed, incomplete, or authority-incompatible task records and enforces the normal lifecycle plus distinct `blocked`, `failed`, `missing`, `unreachable`, and `unknown` conditions. The new portable task-contract suite verifies normal and refused transitions, identity and reservation requirements, local-only handoffs, research results, and non-success validation outcomes. `./scripts/check.sh` passed with nine portable test files.
- P2-002 completed on 16 September 2026. `src/state/lock.sh` creates project and task lock directories through atomic `mkdir`, persists strict owner records, requires the exact acquiring process to release, and refuses automatic recovery for existing, stale, remote, malformed, or otherwise ambiguous locks.
- `src/state/events.sh` creates private event logs without following symbolic links and appends only validated, task-owned, bounded JSONL records with contiguous sequence numbers and unique event identities. `src/state/atomic.sh` now also rejects symbolic-link sources. The state-safety suite covers all of those refusal and preservation paths; the full suite passed on the host's stock macOS Bash 3.2 with ten portable test files.
- P2-003 completed on 16 September 2026. `src/tasks/worktree.sh` allocates a task-owned change branch or detached research worktree only from an exact full base commit under a project lock. It preserves ambiguous partial work rather than removing it and writes its ownership marker outside the managed repository and worktree.
- The worktree-safety suite proves clean change and research setup, exact branch and base binding, external marker validation, and refusal of dirty repositories, existing branches or targets, nested worktree roots, and markers inside a worktree root. The full suite passed with eleven portable test files.
- P2-004 completed on 16 September 2026. The Codex manifest is `implemented-unverified`; `src/adapters/agents/codex/adapter.sh` owns executable and authentication diagnosis, exact model and reasoning launch-spec resolution, task-type sandbox selection, and bounded JSONL plus structured-final-output collection.
- The portable adapter suite uses a Codex test double to prove authenticated and unauthenticated diagnostics, tamper and overwrite refusal, change `workspace-write` versus research `read-only` launch specs, and durable ambiguity when a completed terminal event or structured final output is missing. The full suite passed with twelve portable test files. An earlier non-mutating probe found the installed Codex CLI unauthenticated; the maintainer reports it has since been authenticated, and the pending real task will retain a current preflight record.
- P2-005 completed on 16 September 2026. The tmux manifest is `implemented-unverified`; `src/adapters/runtimes/tmux/adapter.sh` owns exact endpoint reservations, generated owned runners, launch only from a validated Codex specification, liveness inspection, 64 KiB capture, and closure only after endpoint and owner-marker proof.
- The portable tmux suite uses a disposable runtime double to prove normalized diagnosis, reservation, launch, active inspection, bounded capture, closure, and refusal to adopt a pre-existing session. JSONL and stderr are separate launch artifacts. The full suite passed with thirteen portable test files. The real lifecycle now also passes with tmux `3.7c`, a harmless fake worker, and a unique adapter-owned server; evidence is retained at `~/.foreman/projects/foreman/evidence/live-tmux-2026-09-17-retry-2/`.
- P2-006 completed on 16 September 2026. `foreman task start` now requires an approved local-only plan task, an explicit new change branch or branchless research task, an available authenticated Codex CLI and tmux runtime, and an idle managed project before any task state is created.
- Start persists the immutable task identity, configuration snapshot, exact-base worktree marker, owned endpoint reservation, launch specification, task metadata, and append-only lifecycle events before creating the tmux session. `task status` remains read-only; `task reconcile` records missing or unreachable conditions without cleanup and resumes supervision only after exact endpoint liveness is proven. Task references must remain inside the exact task directory and retain their recorded SHA-256 identity. The portable task-command suite covers normal start, branch and approval refusal, unavailable adapters, read-only status, missing-endpoint preservation, proven recovery, and redirected-state refusal. The full suite passed with fourteen portable test files.
- P2-007 completed on 16 September 2026. `foreman task validate` requires a non-active task endpoint and a bounded, structured Codex terminal result before it clears an earlier condition or progresses the lifecycle. It runs the registered and task-declared validation commands in the exact task worktree, preserving command, output, exit status, hash, and evidence as versioned records.
- A successful change task must retain a clean task-owned branch with a commit beyond its exact base. Foreman produces a local handoff and result only; it does not push, publish, merge, land, discard, or tear down the worktree. A successful research task must remain clean and at its exact detached base; it receives a structured finding and a standalone report named `report-{slug}.html` with embedded always-dark CSS. Portable end-to-end fakes prove both flows, and the full suite continues to pass with fourteen portable test files.
- P2-008 completed on 17 September 2026. `task reconcile` now proves the external ownership marker, exact Git worktree root, common Git directory, branch or detached state, base ancestry, and available structured Codex output before reporting recovery. A mismatched worktree becomes an `unknown` condition and remains preserved; an absent endpoint records whether terminal worker evidence is available for `task validate`.
- `task teardown` accepts only `--landed-at` for a change task whose exact handoff commit is proven incorporated in the clean managed repository current `HEAD`, or explicit `--discard` for that exact task. Research tasks have no landing path and require explicit discard. Teardown refuses active, unknown, or otherwise unproven endpoints; retains task metadata, ownership marker, append-only events, and a strict teardown record; and can finish a prior interrupted removal only after proving that the exact worktree is already absent and unregistered. The portable suite proves authority refusal, false-landing refusal, locally landed teardown, forceful exact-worktree discard, closed-task recovery, and durable record validation. All fourteen portable test files pass.
- P2-009's portable portion completed on 17 September 2026. `scripts/live-check.sh` has two explicit modes: `--tmux` exercises the real tmux adapter with a harmless fake worker and retains diagnosis, endpoint, capture, and closure evidence; `--codex-task` creates a disposable repository and runs one real read-only research task through Foreman. The latter requires `--allow-codex-usage` plus an explicit model and reasoning value, retains every result on failure or timeout, and never contacts a remote.
- The harness contract has a dedicated portable test, bringing the full suite to fifteen portable test files. The real tmux check initially exposed a macOS Unix-socket path-limit failure; the harness now chooses a unique short adapter-owned server name and the corrected check passed. The first explicitly authorized Codex attempt confirmed authentication and retained full evidence at `~/.foreman/projects/foreman/evidence/live-codex-2026-09-17/`, but Codex rejected the output schema before a worker result was produced because it does not permit `uniqueItems`. The external schema now omits that keyword while Foreman's own final-output validator continues to reject duplicate values. P2-009 remains active until a newly authorized real Codex task completes and its durable evidence is reviewed.

## Confirmed risks carried forward

- Worktree creation, execution, supervision, delivery, recovery, and teardown are inherently higher-risk and require new Phase 2 evidence before use.
- Stock macOS Bash 3.2 behavior must remain an explicit compatibility target, especially for arrays, subshell ownership, locking, and fixture data.
- Runtime socket paths must be bounded before the Herdr adapter is implemented.
- Destructive lifecycle operations must require exact ownership, prerequisite, liveness, and landing evidence and must fail closed when any is ambiguous.
- Remote delivery must distinguish command success from provider-confirmed outcome and keep merge authority independent from delivery automation.

## Next verified checkpoint

Obtain and review P2-009's explicitly authorized real Codex evidence. Do not represent Codex CLI as supported until that check passes.
