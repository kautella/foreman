# Current Focus

## Current objective

Review the completed Phase 1 foundation and its readiness evidence before defining Phase 2 implementation work.

## Established state

The following approved documents remain the project contract:

- `vision.md`
- `prd.md`
- `architecture.md`
- `upstream-map.md`
- `phase-1-backlog.md`

Phase 1 is complete on the feature branch. Foreman now provides:

- a neutral command surface with `init`, `doctor`, and reviewed `plan` workflows;
- strict versioned configuration, plan, handover, and adapter contracts;
- reviewed, atomic project initialization with Git identity and path-safety checks;
- direct-plan, external-handover, and guided-drafting intake that converges on canonical JSON;
- deterministic plan identity, standalone HTML review, blocking-decision handling, and explicit approval;
- contract-only definitions for the approved agent, runtime, and remote adapters;
- active-code boundary scans, portable tests, syntax and data validation, contributor guidance, and a clean pre-commit entry point;
- external source-baseline, upstream-intake, and Phase 1 readiness evidence.

The source reference remains pinned at `3f035336f9df7331e195bc6279cc1577e1cf4b49`. Its archive, license, inventory, contained tests, and known failures are recorded outside this repository. The first ongoing upstream discovery review covers 201 later commits through `b182d0f908b78d08c7ccb8dce3775bdca8c5d657` without automatically importing any change.

## Review boundary

The current branch is ready for maintainer review. Phase 2 has not started.

The review should confirm:

1. The initialization choices and rendered configuration match the intended user experience.
2. The three plan-intake routes and explicit approval boundary are the correct gateway to future execution.
3. The source-baseline failure classifications and upstream adoption candidates are reasonable.
4. The Phase 1 implementation is ready to become the base for Phase 2 planning.

## Constraints

- Phase 1 does not create task worktrees, launch workers, execute approved plans, or mutate remotes.
- Agent, runtime, and remote manifests remain `contract-only`; they do not claim provider support.
- No provider executable may be invoked from the Foreman core.
- No external source reference is active Foreman code, instructions, configuration, or test input.
- Upstream changes remain subject to explicit intake, architecture review, Foreman-native implementation, and Foreman-owned evidence.
- Ambiguous identity, ownership, liveness, delivery, or landing state must preserve work and block mutation.

## Next milestone

After maintainer review, define the Phase 2 backlog for the local-only Codex CLI and tmux vertical slice. Do not begin worker execution, worktree allocation, delivery, recovery, or teardown implementation before that plan is approved.
