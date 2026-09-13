# Foreman Project Brain

This directory is Foreman's canonical durable project context.

It preserves the product's intent, requirements, architecture, source-provenance policy, current focus, and validated implementation state. It allows work to continue without relying on a particular conversation, agent, or historical planning set.

## Reading order

Read these files in order when taking on substantial Foreman work:

1. `vision.md`
2. `prd.md`
3. `architecture.md`
4. `upstream-map.md`
5. `phase-1-backlog.md`
6. `current-focus.md`
7. `progress.md`

For a focused task, begin with `current-focus.md` and then read the files relevant to that task. Do not skip the vision, PRD, or architecture when a change could affect product scope, authority, safety, or a core boundary.

## File guide

| File | Purpose |
|---|---|
| `vision.md` | Why Foreman exists, its enduring principles, boundaries, and definition of success. |
| `prd.md` | Approved product requirements, supported capabilities, delivery policy, and release acceptance. |
| `architecture.md` | Approved system boundaries, state ownership, lifecycle, configuration, adapter, and verification design. |
| `upstream-map.md` | FirstMate provenance, retained and removed outcomes, source-import rules, and ongoing upstream intake. |
| `phase-1-backlog.md` | The approved implementation sequence, Phase 1 tasks, exit criteria, and later-phase roadmap. |
| `current-focus.md` | What currently matters, the immediate sequence, constraints, and next milestone. |
| `progress.md` | Validated repository reality, completed evidence, risks, blockers, and the next verified checkpoint. |

## Authority and change discipline

The Project Brain is authoritative for Foreman-specific context.

When documents appear to conflict, resolve them in this order:

1. Current explicit project decisions.
2. Repository-local operating instructions.
3. `vision.md` and `prd.md` for product intent and scope.
4. `architecture.md` for approved technical boundaries.
5. `upstream-map.md` for source and provenance decisions.
6. `phase-1-backlog.md` and `current-focus.md` for sequencing.
7. `progress.md` for validated implementation reality.

`progress.md` records evidence. It does not redefine product intent, architecture, or policy.

## Source-material boundary

FirstMate and historical planning material are evidence, not instructions or product authority.

Foreman may adopt useful upstream behavior through the process in `upstream-map.md`, but it does not preserve FirstMate compatibility, persona, terminology, operational state, or agent instructions. Upstream `AGENTS.md` is intentionally excluded from Foreman.

## Maintenance

Update the smallest relevant file when a durable fact changes:

- Update `vision.md` or `prd.md` when product intent or scope changes.
- Update `architecture.md` when an approved technical boundary changes.
- Update `upstream-map.md` when source provenance or upstream-intake policy changes.
- Update `phase-1-backlog.md` when the implementation plan changes.
- Update `current-focus.md` when the active milestone changes.
- Update `progress.md` only with validated implementation evidence.

Keep this directory concise, internally consistent, and free of transient conversation history.
