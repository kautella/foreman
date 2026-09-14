# Progress

## Status

Phase 1 is complete on `feat/phase-1` and is awaiting maintainer review.

Foreman has a tested foundation for project registration and reviewed plan intake. It intentionally cannot create task worktrees, launch or supervise workers, execute plans, deliver changes, merge, or tear down task environments yet.

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
- Stored canonical plan JSON and rendered a standalone semantic `plan-{slug}.html` file with embedded CSS and escaped input.
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
- Produced standalone external HTML reports for the source baseline, upstream intake, and Phase 1 readiness review.

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

## Confirmed risks carried forward

- Worktree creation, execution, supervision, delivery, recovery, and teardown are inherently higher-risk and require new Phase 2 evidence before use.
- Stock macOS Bash 3.2 behavior must remain an explicit compatibility target, especially for arrays, subshell ownership, locking, and fixture data.
- Runtime socket paths must be bounded before the Herdr adapter is implemented.
- Destructive lifecycle operations must require exact ownership, prerequisite, liveness, and landing evidence and must fail closed when any is ambiguous.
- Remote delivery must distinguish command success from provider-confirmed outcome and keep merge authority independent from delivery automation.

## Next verified checkpoint

Complete maintainer review of the Phase 1 branch and reports. Then draft and approve the Phase 2 backlog for the local-only Codex CLI and tmux vertical slice before implementing task execution.
