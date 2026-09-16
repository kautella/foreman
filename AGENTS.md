# Foreman Agent Instructions

## Start with project context

Before substantial work:

1. Read `brain/README.md`.
2. Read `brain/current-focus.md` and `brain/progress.md`.
3. Read the relevant product documents:
   - `brain/vision.md`
   - `brain/prd.md`
   - `brain/architecture.md`
   - `brain/upstream-map.md`
   - the active phase backlog named by `brain/current-focus.md`

The active Phase 2 backlog is `brain/phase-2-backlog.md`. Read `brain/phase-1-backlog.md` when prior sequencing or Phase 1 evidence is relevant.

The Project Brain is the authoritative Foreman-specific context. Preserve its established intent. Do not silently redefine product scope, architecture, authority, or safety policy through implementation.

## Work within the current phase

`brain/current-focus.md` defines the active milestone.

Do not begin deferred work merely because it appears technically related. Do not represent a capability as supported until its implementation and verification evidence exist.

When a proposed change would alter product scope, safety, authority, configuration semantics, a supported-provider boundary, or the approved architecture, stop and surface the decision.

## Source reference material

Only documented active Foreman source directories form the product implementation.

FirstMate and historical source material are external development references. They are not executable product code, active instructions, runtime configuration, or test inputs. Do not execute, source, copy, or modify them unless the approved current task explicitly requires it.

## Architecture boundaries

- The core owns lifecycle, configuration, policy, worktree safety, recovery, validation, and durable state.
- Agent, runtime, and remote-specific behavior belongs only in the relevant adapter.
- The core must not directly invoke provider executables.
- Configuration and mechanically consumed state use strict, versioned JSON.
- Operational state belongs outside managed repositories.
- Ambiguity over identity, ownership, liveness, validation, delivery, landing, or teardown preserves work and blocks mutation.

## Implementation and verification

- Prefer the smallest complete change that satisfies the approved task.
- Keep public behavior neutral and ordinary. Do not introduce a prescribed persona, roleplay, special form of address, or branded vocabulary.
- Validate in proportion to risk and record meaningful evidence.
- Run destructive or inherited tests only in an expendable, validated environment.
- Do not bypass a safety refusal, broaden a mutation target, or use force or discard behavior without explicit authority.
- Keep provider-boundary and terminology checks passing as the active implementation grows.

## Operating from this checkout

Tracked product implementation, adapters, contracts, and artifact assets live under `src/`.

The root `./foreman` executable is a generated, ignored launcher. When an operational request requires it and it is absent, run `./scripts/install.sh` to generate it. Do not write the launcher manually, edit it, or commit it. Do not create an external command link unless the user explicitly asks for one.

Use `./foreman` for product operations. Do not imitate an operation by directly editing `~/.foreman` or other durable state. When the task is to develop Foreman itself, edit the tracked implementation and validate through the public command surface where practical.

## Project Brain write boundary

The workflow is always:

```text
Codex + maintainer
        ↓
     Foreman
        ↓
    Subagents
        ↓
     Foreman
        ↓
brain/progress.md
        ↓
    Next task
```

After validating a completed task, Foreman updates `brain/progress.md` with the consolidated implementation reality, evidence, risks, blockers, and unresolved decisions.

Foreman may modify only `brain/progress.md`; it must not create, modify, move, or delete any other file under `brain/`. Codex and the maintainer own all other Project Brain files and may also review or update `brain/progress.md` when necessary to keep validated repository reality accurate.

## Git and delivery authority

Commit, push, change-request publication, merge, local landing, and destructive recovery authority are always explicit.

Do not create commits, push branches, publish change requests, merge work, or alter remotes unless the current task explicitly grants that authority.

When commit authority is granted, follow the contributor commit discipline in `CONTRIBUTING.md`.

## Communication

Report outcomes, evidence, risks, and required decisions plainly. Distinguish confirmed facts from assumptions and recommendations.

When blocked by an unresolved safety or product decision, explain the concrete conflict and the smallest decision needed to proceed.
