# Current Focus

## Current objective

Complete F1-003 and F1-008: finish the contained source baseline and define the plan-exchange contracts.

## Established state

The following documents are approved and define the current project contract:

- `prd.md`
- `architecture.md`
- `upstream-map.md`
- `phase-1-backlog.md`
- `brain/vision.md`

The active Foreman skeleton now exists with a neutral command surface, approved source layout, and portable test entry point. It exposes only help and version information; no orchestration capability is represented as implemented.

The initial repository baseline is committed as `1cde061`.

F1-001 is complete: the pinned FirstMate revision has been verified as an external development reference, with its license, archive checksum, complete inventory, and the exclusion of upstream `AGENTS.md` recorded outside this repository.

F1-002 is complete: the historical command-substitution fixture-cleanup defect was reproduced at revision `d0461e4b489c518eb744430742af62d73e2a16d0` and shown repaired at the pinned revision. Both checks ran through a local disposable-repository harness outside Foreman, with exact ownership markers, control-directory survival checks, signal cleanup, and fail-closed target validation.

No Foreman operational home, project configuration, task state, adapter implementation, worktree, worker, or remote-delivery path exists yet.

The historical planning material outside this repository is no longer a project contract. It may be consulted only as source evidence when the approved documents require it.

## Current sequence

1. Complete F1-003: produce source-baseline evidence through the validated disposable-repository harness.
2. Define direct-plan, external-handover, and guided-drafting exchange contracts.
3. Continue the remaining Phase 1 work in the approved dependency order.

## Immediate Phase 1 priorities

1. Reproduce and contain inherited test cleanup only in expendable environments.
2. Produce trustworthy source-baseline evidence.
3. Establish the active Foreman repository layout and neutral command namespace.
4. Implement strict JSON configuration, reviewed project initialization, and path safety.
5. Implement plan intake, normalization, approval, and standalone HTML plan review.
6. Define adapter contracts and enforce core, adapter, provider, terminology, and provenance boundaries.
7. Begin the standing upstream-intake process without automatically adopting later changes.

## Constraints

- The source baseline remains `3f035336f9df7331e195bc6279cc1577e1cf4b49`.
- Upstream `AGENTS.md` must never enter a Foreman instruction surface.
- Inherited tests must not run in the Foreman checkout or any non-disposable repository.
- No provider executable may be invoked from the Foreman core.
- No agent, runtime, remote, delivery, or merge capability is considered implemented until its contracts and evidence exist.
- Upstream changes are evaluated through the approved intake process. They do not bypass the Phase 1 sequence.

## Next milestone

The next milestone is a trustworthy pinned-source baseline report that distinguishes harness defects, environment-gated checks, and product defects. The Phase 1 readiness report, not functional parity or worker execution, remains the first implementation milestone.
