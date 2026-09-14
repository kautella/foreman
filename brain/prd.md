# Foreman Product Requirements Document

**Status:** Approved
**License:** MIT

## Product summary

Foreman is a provider-neutral execution-supervision system for coordinating coding agents across Git repositories.

It accepts, validates, and can guide the drafting of explicit execution plans, creates isolated task environments, supervises bounded coding-agent workers, validates their results, preserves durable state, and delivers work through an explicitly selected project policy.

Foreman does not own product strategy.
It executes explicit, bounded work while making execution state, validation evidence, risks, and decisions durable and inspectable.

Foreman is independently developed using FirstMate as an MIT-licensed code and behavioral reference.
It preserves proven safety outcomes without promising compatibility with FirstMate commands, state, configuration, terminology, or delivery behavior.

## Problem

Coordinating several coding agents requires a person to manage task boundaries, worktrees, terminal sessions, progress, recovery, validation, and delivery manually.

Foreman reduces that operational work while making consequential Git actions governed by explicit, inspectable policy rather than inference.

## Goals

Foreman must:

1. Coordinate bounded change and research tasks through isolated Git worktrees.
2. Preserve durable task identity, state, decisions, validation evidence, research reports, and recovery information.
3. Support local-only repositories as complete workflows, not degraded remote-less cases.
4. Support built-in agent and runtime adapters behind explicit contracts.
5. Support optional GitHub and GitLab remote capabilities without making either a bootstrap dependency.
6. Support both user-published and automated remote change-request delivery.
7. Keep merge autonomy independent from task delivery and disabled by default.
8. Preserve safe recovery, teardown, and unlanded-work protections.
9. Use neutral communication without a prescribed persona, form of address, roleplay, or branded vocabulary.
10. Retain Bash during the initial parity and extraction work.
11. Maintain a configurable Foreman home with global configuration and isolated, durable state for each managed project.
12. Accept, exchange, and guide the drafting of reviewable execution plans without taking ownership of product strategy or executing unapproved work.
13. Provide the same command surface to Codex operating from a cloned checkout and to external callers invoking a Foreman executable.

## Delivery policy and merge authority

Every project has an explicit delivery policy.

### Draft handoff

`draft-handoff` is available for every project and is required for local-only projects.

Foreman validates the task branch and prepares the material required for the user to deliver it:

- for a remote-backed project, a provider-native pull-request or merge-request draft;
- for a local-only project, a local delivery draft containing the branch identity, base identity, validation evidence, risks, and instructions for manual landing.

The user pushes branches, publishes change requests, and lands work.

### Automated change request

`automated-change-request` is available only when GitHub or GitLab capabilities are verified for the registered project.

Foreman may push the validated branch, create and publish the provider-native pull request or merge request, monitor checks, report readiness, and preserve the resulting remote identity in durable task state.

### Merge authority

Merge authority is a separate, explicit project setting.

With merge autonomy disabled, Foreman stops at a green, ready change request and waits for the user to merge it.

With merge autonomy enabled, Foreman may merge a green, in-scope remote change request through the verified provider adapter.
It must never merge a red, ambiguous, security-sensitive, destructive, or otherwise policy-excluded change request.

Merge autonomy does not apply to local-only projects.
Local landing always remains user-controlled.

## Research tasks

A research task produces a durable, standalone `report-{slug}.html` document within the owning project's Foreman-managed task state under `projects/<project-name>/`.
It does not write the report into the target repository unless the user explicitly directs that delivery.

The report uses semantic HTML and embedded CSS only.
It has no external stylesheets, scripts, services, or session dependency, so it remains readable after the task and its runtime end.

The report records:

- the question, scope, and assumptions;
- evidence and method;
- findings and their confidence or limitations;
- a recommendation;
- unresolved questions and required decisions.

Task-owned artifacts may accompany the report in the same project state and are linked from it.
The report must remain understandable without an external review integration.

The report slug is normalized from the task's durable title and must not overwrite an existing report.
Task metadata records the report's canonical path.

## Product principles

1. **Local Git is complete.** No remote is a valid, fully supported state.
2. **Authority is explicit.** Evidence, validation, and recommendations never authorize publication, landing, discard, or destructive recovery. Automated delivery and autonomous merging require separately selected policy.
3. **Safety fails closed.** Ambiguous identity, liveness, delivery, landing, or ownership prevents mutation.
4. **Durable state beats conversation memory.** Work must survive restarts, lost context, and interrupted supervision.
5. **Adapters express real differences.** Agent, runtime, and remote behavior stays outside the provider-neutral core.
6. **Built-in before plugins.** Initial supported adapters ship with the repository and have verification evidence.
7. **Preserve outcomes, not FirstMate mechanics.** FirstMate is a reference and donor, not a compatibility contract.
8. **Communication is neutral.** Effective user and project instructions govern communication.

## Functional requirements

### Bootstrap and projects

- Bootstrap works with Git plus one supported agent and runtime.
- A cloned Foreman checkout is directly operable by Codex through repository instructions. If the repository-local `foreman` executable is absent, the tracked installer generates it before product operations begin.
- `scripts/install.sh` generates an ignored `foreman` executable at the repository root. It may also create an explicitly requested link in an absolute user-selected executable directory. It never silently chooses or modifies an external executable directory.
- The generated executable contains no product logic. It delegates to the tracked implementation under `src/`, and both repository-local and externally linked invocation use that same implementation.
- Installation refuses to overwrite a root executable or external link it cannot prove it owns.
- Foreman has a configurable home root, distinct from its source checkout and from managed repositories. A global configuration file in that root governs home-wide defaults and settings.
- The Foreman home contains a `projects/` directory. Each managed project has an isolated `projects/<project-name>/` directory that contains its project configuration and all project-owned Foreman state.
- Project initialization explicitly obtains a project name and target project folder. Foreman canonicalizes the target as an absolute path, verifies its Git identity, and binds that identity to the selected project name. It must not silently adopt the current working directory.
- Project initialization resolves and persists a default worker profile for subagents: supported agent adapter, model identifier, and reasoning or effort setting. The user may supply these values during initialization; if any required value is absent, Foreman asks for it before initialization completes.
- Foreman validates the worker-profile combination against the selected adapter's supported capabilities and reports unsupported or unavailable selections with actionable diagnostics. Each task records the resolved worker profile it used.
- Projects and task-worktree roots are independently configurable and persisted as canonical absolute paths.
- Existing repositories are adoptable without relocation.
- Project registration detects Git, remote capability, delivery policy, and merge authority without treating a URL or label as mutation authority.
- An unsupported or absent remote remains a valid local-only project state.
- Initialization generates and presents the complete effective project configuration for explicit user confirmation before persisting it or continuing with project operations. Configuration contains no credentials, task history, or ephemeral runtime state.
- Any configuration change is presented as a diff and requires explicit user confirmation before it takes effect.

### Plan intake and exchange

- Before task initialization, Foreman accepts direct user-provided plans, versioned external execution handovers, and guided drafting.
- Foreman provides a human-readable plan template, machine-readable schema and example, and actionable validation that identifies incomplete or ambiguous input.
- Guided drafting may inspect registered project context read-only and ask focused questions. It must not create worktrees, launch workers, mutate a repository or remote, or execute work before explicit plan approval.
- All accepted input is normalized into a versioned execution-plan JSON document that records scope, tasks and dependencies, constraints, acceptance criteria, delivery expectations, worker-profile hints, references, and unresolved decisions.
- A plan's origin, including an external agent handover, is provenance only. It cannot grant delivery, merge, discard, or other authority beyond the registered project policy.
- Foreman renders each proposed plan as a durable standalone `plan-{slug}.html` artifact using semantic HTML and embedded CSS. The review presents the proposed scope, tasks, dependencies, acceptance criteria, policy implications, risks, missing information, and unresolved decisions.
- Explicit user approval of the reviewed plan is required before Foreman initializes its tasks.

### Task lifecycle

- Every change task uses an isolated Git worktree and an explicit branch.
- Every research task produces the durable report defined above.
- Tasks have durable metadata, append-only status events, exact endpoint identity, and recoverable state.
- Concurrent workers cannot collide in worktrees or task ownership.
- A completed change reaches the terminal state defined by its delivery policy: handoff-ready, change-request-ready, or landed.
- Each completed task exposes a durable machine-readable result alongside its applicable human-readable handoff, change-request, or research artifacts.
- Uncommitted or unlanded work is preserved until the applicable delivery or discard authority is confirmed.
- Teardown requires confirmed landing or explicit discard authority.

### Delivery

- A draft handoff includes the exact branch and base identity, validation evidence, unresolved risks, and the relevant local or provider-native draft.
- An automated change request includes the resulting canonical URL, remote head identity, checks or pipeline state, and readiness outcome.
- Foreman may observe known remote change requests, their checks, and confirmed landing state.
- Delivery behavior is rejected when the selected policy, remote capability, task state, or required authority is missing or ambiguous.

### Agent and runtime adapters

Initial supported coding-agent adapters are:

- Claude Code
- Codex CLI
- Gemini CLI
- OpenCode
- Pi

Initial supported runtimes are tmux and Herdr.

Every supported adapter declares versioned identity and capabilities, including its supported worker-profile options.
Provider-specific launch, trust, authentication, lifecycle, and recovery behavior remains within the relevant adapter.

### Remote adapters

GitHub and GitLab, including supported self-hosted GitLab instances, are optional remote adapters.

For verified remote-backed projects, adapters may provide repository identity, canonical URL handling, head and base identity, authentication diagnostics, pull-request or merge-request creation, checks or pipeline status, readiness reporting, merge execution, and landing observation.

Remote mutation operations are available only to the explicitly selected automated delivery and merge-authority policies.

## Out of scope

- Inferred or unconfigured branch pushes, change-request publication, merges, local landing, or merge autonomy.
- Retaining any FirstMate nautical persona, terminology, commands, compatibility aliases, schemas, configuration, documentation, fixtures, or active implementation paths, except where required for license or provenance.
- FirstMate public-relay, public-follow-up, and conversational review-session integrations.
- Third-party adapter discovery or a marketplace.
- Zellij, cmux, Orca, Muse, Grok CLI, Kimi CLI, Cursor Agent CLI, and Codex App runtimes or adapters.
- A TypeScript rewrite of the coordinator core.
- Migration tooling for existing FirstMate homes.
- A graphical product interface.

## Release acceptance

The initial stable release requires:

1. Local-only change, research, recovery, draft-handoff, manual local landing, and teardown lifecycle evidence without GitHub or GitLab tools installed.
2. Verified support for Claude Code, Codex CLI, Gemini CLI, OpenCode, and Pi.
3. Verified tmux and Herdr lifecycle evidence.
4. Durable restart and unlanded-work safety scenarios.
5. Provider-boundary enforcement in CI.
6. GitHub and GitLab evidence for draft handoff, automated change-request delivery, explicit merge authority, merge-autonomy refusal, and enabled merge-autonomy behavior.
7. No active FirstMate nautical theme, persona, terminology, or compatibility promise outside required attribution.
8. Complete MIT attribution and auditable baseline provenance.
9. Direct-plan, external-handover, and guided-drafting evidence, including approval refusal and standalone HTML plan review artifacts.
10. Repository-local installation, safe refresh, unowned-file refusal, and explicitly selected external-link evidence.
