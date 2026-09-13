# Progress

## Status

Foreman is in Phase 1, producing a contained baseline of the pinned source reference.

The approved product contract, architecture, upstream map, Phase 1 backlog, and Project Brain routing are complete and live under `brain/`.

The active Foreman product skeleton exists with a neutral command surface, approved source layout, and portable test entry point. It intentionally exposes no worker, runtime, remote, or delivery operation. Source-validation tooling remains outside the repository because it is local implementation support, not part of Foreman.

## Completed

- Defined Foreman as an independent, provider-neutral execution-supervision system.
- Approved the product requirements, architecture, source-provenance policy, and Phase 1 backlog.
- Established the initial supported agent adapters, runtime adapters, remote adapters, and delivery-policy boundaries.
- Defined reviewed plan intake for direct plans, external handovers, and guided drafting.
- Defined durable standalone HTML artifacts for plan review and research reports.
- Defined selective ongoing FirstMate intake without automatic adoption.
- Recorded FirstMate baseline `3f035336f9df7331e195bc6279cc1577e1cf4b49` as the reproducible initial source revision.
- Recorded that upstream `AGENTS.md` is intentionally excluded from Foreman.
- Moved the canonical project contract into the Project Brain and aligned the Brain's vision, focus, and routing.
- Added Foreman-owned repository guidance, public documentation, contributor guidance, local IDE exclusions, and the initial development-check runner and pre-commit hook.
- Reviewed the initialized repository baseline: its documentation links and terminology boundaries are coherent, all untracked files are intentional, and the configured checks pass.
- Created the initial repository commit `1cde061`.
- Completed F1-001: verified the pinned FirstMate revision as an external development reference, recorded its MIT license, full source inventory, archive checksum, and excluded upstream `AGENTS.md` from Foreman instruction surfaces. No source snapshot is tracked in this repository.
- Completed F1-002 outside the repository: established a local disposable-repository harness with validated temporary roots, exact root and control markers, isolated home and temporary paths, exact revision verification, interruption cleanup, and fail-closed deletion.
- Reproduced the historical fixture helper's command-substitution self-deletion at `d0461e4b489c518eb744430742af62d73e2a16d0` only inside the disposable harness.
- Verified that the pinned source revision `3f035336f9df7331e195bc6279cc1577e1cf4b49` preserves the fixture root for the same behavioral check.
- Verified containment behavior for normal execution, broad and ambiguous path refusal, ownership-marker tampering, checkout self-deletion, control-directory survival, and signal interruption.
- Completed F1-004: established the active `bin/`, `lib/`, `contracts/`, `adapters/`, `rendering/`, `tests/`, and `docs/` layout.
- Added the neutral `foreman` command with stable help, version output, clear refusal of unknown commands, and no inherited executable or compatibility path.
- Added a portable Foreman-owned test runner and initial command-surface tests.
- Completed F1-005: added strict versioned JSON schemas and runtime validation for global configuration, project configuration, and worker profiles.
- Configuration now requires canonical project and worktree paths, Git identity, explicit agent/model/reasoning selection, runtime, delivery policy, merge authority, and validation requirements.
- Contract checks reject unknown fields, unsupported agent identities, duplicate validation commands, and remote delivery or merge authority for local-only projects.

## Not started

- The pinned source baseline report.
- `FOREMAN_HOME`, configuration, plan intake, adapter contracts, task lifecycle, and provider implementations.
- The first upstream discovery record.

## Confirmed risk

The historical fixture helper removed a newly created fixture root when called through command substitution because its exit trap ran in the subshell. The pinned revision contains an upstream repair.

The external disposable-repository harness contains accidental mutation by relocating the checkout and common home and temporary paths, but it is not an operating-system security sandbox. Inherited source is treated as trusted-but-risky test code, never as hostile code.

No inherited test suite may run in the Foreman checkout, the source reference, or another non-disposable repository. Inherited results are source-baseline evidence only and never become Foreman behavior evidence by implication.

## Current constraints

- No external source reference is active Foreman code, instructions, configuration, or test input.
- No capability is represented as supported without implementation and verification evidence.
- No provider executable may be invoked from the Foreman core.
- No upstream change bypasses the approved intake, planning, validation, and delivery process.
- Ambiguous identity, ownership, liveness, delivery, or landing state must preserve work and block mutation.

## Next verified checkpoint

Complete F1-003: produce a trustworthy source-baseline report through the validated disposable-repository harness. Separate syntax and lint evidence, portable test results, environment-gated checks, harness defects, and product defects.
