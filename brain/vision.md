# Foreman Vision

## Why Foreman exists

Coordinating coding agents across Git repositories creates real operational work: turning intent into bounded tasks, isolating concurrent work, supervising execution, preserving context through interruptions, validating results, and delivering changes safely.

Foreman exists to make that work durable, inspectable, and governed by explicit policy.

It is an open-source, provider-neutral execution-supervision system for coding-agent work. It coordinates the operational layer of software delivery without taking ownership of product strategy.

## Intended role

Foreman accepts approved execution plans, including direct plans, external handovers, and guided-drafting proposals that have been reviewed and approved. It turns those plans into bounded tasks, provisions isolated task environments, supervises coding-agent workers, validates results, preserves durable evidence, and applies the registered project delivery policy.

It is not a coding agent, terminal emulator, Git host, or general plugin platform. It coordinates those concerns through a small built-in set of explicit adapters.

Foreman may help users formulate an execution plan, but it does not decide product strategy or execute an unapproved proposal.

## The intended outcome

A Foreman-managed project should be able to:

- operate as a complete local-Git workflow without a hosted remote;
- coordinate concurrent change and research tasks without task, worktree, or ownership collisions;
- survive lost terminals, restarts, and interrupted supervision without relying on conversation memory;
- make task status, validation evidence, risks, decisions, and delivery state durable and reviewable;
- use supported coding-agent, runtime, and remote providers without allowing their differences to leak into the core;
- deliver through a policy chosen explicitly for each project;
- preserve human control over consequential actions while allowing narrowly authorized automation.

## Product principles

1. **Plans are reviewed before execution.** Direct plans, external handovers, and guided drafting converge on a validated canonical plan. Approval is required before task initialization.

2. **Local Git is complete.** A repository without GitHub, GitLab, or any remote is a fully supported project state.

3. **Authority is explicit.** Evidence, recommendations, a remote URL, or an upstream handover never authorize publication, landing, discard, or merge. Delivery automation and merge autonomy are separately selected project policies.

4. **Safety fails closed.** Ambiguous identity, ownership, liveness, validation, delivery, or landing state prevents mutation and preserves work.

5. **Durable state beats conversation memory.** Foreman records project configuration, plan approval, task identity, events, validation, results, and delivery state outside the managed repository.

6. **Adapters express real differences.** Agent, runtime, and remote-specific behavior belongs to built-in adapters. The core owns lifecycle, policy, safety, recovery, and durable state.

7. **Built-in capabilities earn support.** A provider is supported only when its adapter, compatibility constraints, and verification evidence ship with Foreman.

8. **Communication is neutral.** Foreman prescribes no persona, form of address, roleplay, or branded vocabulary. Effective user and project instructions govern communication; otherwise workers use their normal communication style.

9. **Outcomes matter more than upstream mechanics.** FirstMate is a valuable source of code, tests, fixes, and operational lessons. Foreman adopts only what fits its own product requirements and architecture, without compatibility promises.

10. **Upstream learning is continuous, not automatic.** Foreman reviews new FirstMate changes through a deliberate intake process. Useful changes are adopted as Foreman-owned work; incompatible ones are declined.

## Product boundaries

Foreman does not:

- own product strategy or silently convert partial intent into implementation;
- preserve FirstMate commands, state, storage, schemas, terminology, agent instructions, or persona;
- write operational state or reports into a managed repository without explicit task delivery;
- infer remote delivery, local landing, discard, merge, or merge autonomy;
- make GitHub or GitLab a bootstrap requirement;
- retain unsupported agents, runtimes, relays, public-follow-up systems, or review-session integrations;
- become a generic third-party adapter marketplace in its initial product scope.

## Enduring design commitments

- The coordinator core is implemented in Bash during the initial product evolution.
- Global and project configuration use strict, versioned JSON and require `jq`.
- Foreman's operational home is separate from both its own source checkout and every managed repository.
- Agent adapters initially support Claude Code, Codex CLI, Gemini CLI, OpenCode, and Pi.
- Runtime adapters initially support tmux and Herdr.
- GitHub and GitLab, including supported self-hosted GitLab instances, are optional remote adapters.
- FirstMate provenance remains auditable through the pinned baseline, license notice, upstream map, and ongoing intake records.

## Definition of success

Foreman succeeds when it gives a user or an upstream planning system a reliable execution layer: one that makes multi-agent work easier to supervise without obscuring authority, safety, evidence, or control.

Detailed requirements, architecture, source mapping, and implementation sequencing belong respectively to `prd.md`, `architecture.md`, `upstream-map.md`, and `phase-1-backlog.md`.
