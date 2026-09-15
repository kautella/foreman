# Foreman Architecture

**Status:** Approved
**Companion documents:** `prd.md`, `upstream-map.md`

## Architectural intent

Foreman is a Bash-based execution-supervision system for coding-agent work in Git repositories.

It accepts explicit work plans, creates isolated task environments, operates and supervises coding-agent workers, validates results, retains durable evidence, and applies the project's selected delivery policy.

Foreman is not a coding agent, terminal emulator, Git host, or general plugin platform. It coordinates those concerns through built-in adapters.

```text
direct plan / external handover / guided drafting
                        |
                        v
              reviewed execution plan
                        |
                        v
Foreman core ──────────── project policy ── durable state
     |               |
     |               +── delivery and merge authority
     |
     +── agent adapter ─── Claude Code / Codex CLI / Gemini CLI / OpenCode / Pi
     +── runtime adapter ─ tmux / Herdr
     +── remote adapter ── GitHub / GitLab / absent
```

The core owns task lifecycle, configuration, policy enforcement, worktree safety, recovery, and validation. Provider-specific executables are invoked only by their respective adapters.

## System boundaries

### Core

The provider-neutral core:

- registers and validates managed projects;
- resolves effective configuration and policy;
- creates and protects Git worktrees;
- owns task identity, state transitions, locks, events, and recovery;
- dispatches validated operations to adapters;
- evaluates delivery and merge gates;
- renders human-readable status, handoff, and research artifacts.

The core must not invoke `tmux`, `herdr`, `claude`, `codex`, `gemini`, `opencode`, `pi`, `gh`, or `glab` directly.

### Adapters

Adapters contain all provider-specific behavior:

- agent adapters know how to discover, validate, launch, resume, and interpret an agent CLI;
- runtime adapters know how to create, inspect, communicate with, and close worker endpoints;
- remote adapters know how to identify a remote, authenticate, create or observe change requests, evaluate checks, and merge when policy permits it.

Adapters return normalized results to the core. Unknown, malformed, or ambiguous adapter output fails closed.

### Repository under management

A managed repository remains the owner of its source code, Git history, project instructions, and development tooling.

Foreman never writes operational state or reports into that repository unless an explicit task delivery requests it.

## Access modes and installation

Foreman has two access modes over one command and implementation surface:

```text
Codex in the cloned checkout ── repository instructions ──┐
                                                         ├── ./foreman ── src/main.sh ── Foreman core
external caller ── repository path or explicit link ─────┘
```

The tracked `scripts/install.sh` generates the ignored root `foreman` launcher. Repository instructions allow Codex to run that installer when an operational request needs the launcher and it is absent. External callers may invoke the generated launcher by its repository path or ask the installer to create a link in an explicit absolute executable directory.

The launcher contains no product behavior or state semantics. It resolves its repository checkout and delegates to `src/main.sh`, so a linked command and an agent operating in the checkout always execute the same tracked code.

Installation is a fail-closed replacement operation. The installer may refresh only a regular launcher bearing its ownership marker. It refuses to replace an unowned file, symbolic link, directory, special file, or occupied external link path. It never selects an external executable directory implicitly.

## Foreman home and state ownership

Foreman uses `~/.foreman/` as its default operational home. `FOREMAN_HOME` provides an explicit override for users who need another location.

The home is distinct from both Foreman's source checkout and managed repositories.

```text
~/.foreman/
  config.json
  projects/
    <project-slug>/
      project.json
      plans/
        <plan-id>/
          plan.json
          plan-{slug}.html
          completion.json
      state/
        project.lock
        events.jsonl
      tasks/
        <task-id>/
          task.json
          brief.md
          events.jsonl
          result.json
          validation/
          delivery/
          reports/
            report-{slug}.html
      worktrees/
```

The configured worktree root may be outside this directory. The layout above is the default when the project uses Foreman-managed worktrees.

Each project receives a unique, user-confirmed project name, normalized to a storage-safe slug. A collision is an initialization error, never an automatically suffixed folder. The project configuration binds that slug to the canonical target repository identity and path.

## Configuration model

Foreman uses JSON for global and project configuration. JSON is deliberately preferred over YAML because it has strict, well-defined parsing rules, no implicit typing, anchors, tags, or implementation-specific interpretation.

`jq` is a core Foreman prerequisite. Bootstrap and `doctor` validate it before reading or writing configuration. Foreman never sources configuration as shell code and does not maintain a hand-written JSON parser.

Configuration is schema-versioned, declarative, strictly validated, and atomically written. It contains no credentials, agent sessions, task history, or transient runtime state. Credentials remain managed by the relevant agent or remote provider.

The global `config.json` holds home-wide settings and defaults. A project's `project.json` holds its actual execution authority. A project configuration records at least:

- schema version and project identity;
- canonical repository and worktree-root paths;
- detected remote identity and supported remote adapter, if any;
- default worker profile;
- selected runtime;
- delivery policy;
- merge-authority setting;
- applicable validation and delivery requirements.

The effective configuration is the resolved combination of global defaults and project values. Foreman always presents effective values, never merely the raw project file, before initialization or a configuration change is accepted.

## Project initialization and reconfiguration

Project initialization is a reviewed transaction, not a sequence of implicit defaults.

1. Resolve or initialize the Foreman home.
2. Obtain the project name and target project folder.
3. Canonicalize the folder and verify Git identity.
4. Detect remote capability without treating a remote URL as permission to mutate it.
5. Resolve the worker profile: agent adapter, model, and reasoning or effort.
6. Resolve runtime, worktree root, delivery policy, and merge-authority setting.
7. Validate the selected adapter combination and required capabilities.
8. Render the complete effective configuration.
9. Require explicit confirmation.
10. Atomically persist configuration and register the project.

The current working directory may be offered as an explicit default, but Foreman must not silently adopt it.

Later configuration changes follow the same model: render a diff, validate it, require confirmation, then atomically replace the relevant configuration. Existing tasks retain their configuration snapshot, so a later project-default change cannot reinterpret past work.

## Plan intake and exchange

Foreman accepts three sources of execution plans after a project is registered:

- a direct plan supplied by the user;
- a versioned handover supplied by an external agent or system;
- guided drafting, in which Foreman helps the user turn partial intent into an executable proposal.

Foreman provides a human-readable plan template, a machine-readable schema and example, and validation feedback that identifies the information needed for reliable execution. A direct plan may be authored in a human-readable format, but the accepted canonical plan is versioned JSON.

Guided drafting may inspect the registered project read-only and ask focused questions. It may use the selected agent profile to help formulate an execution proposal, but it does not own product strategy. It must not create worktrees, launch implementation workers, mutate the repository or remote, or execute the proposal before approval.

All intake paths converge on a canonical execution plan. At minimum it records:

- source and provenance references;
- objective, scope, constraints, and explicitly excluded work;
- task definitions and dependencies;
- acceptance criteria and required validation;
- delivery expectation and worker-profile hints;
- assumptions, risks, missing information, and unresolved decisions.

The source of a plan is provenance, not authority. An external handover cannot enable delivery, merge, discard, or any other action excluded by the registered project policy.

Foreman renders every proposed plan as `plan-{slug}.html`, a standalone semantic HTML document with embedded CSS and an always-dark presentation. It makes scope, dependencies, acceptance criteria, policy implications, risks, missing information, and unresolved decisions reviewable before execution. Explicit user approval promotes the plan into task initialization.

Plan-level `completion.json` provides a stable machine-readable aggregate result for an upstream coordinator or automation. Each task retains its own `result.json`; human-readable handoffs and research reports remain linked artifacts rather than a substitute for structured results.

## Task model and durable lifecycle

Foreman has two initial task shapes:

- **Change task:** produces validated committed work on an isolated branch.
- **Research task:** produces a durable HTML report and optional linked artifacts.

Every task has a generated immutable identifier, an explicit task brief, a configuration snapshot, and exact Git, worker, runtime, and delivery identity. Presentation labels never authorize mutation.

```text
planned
  -> approved
  -> prepared
  -> running
  -> awaiting-reconciliation
  -> validated
  -> delivery-ready | change-request-ready
  -> landed
  -> teardown-ready
  -> closed
```

A research task follows the same preparation, execution, validation, and recovery model, but reaches `report-ready` rather than delivery. Its report is written under the owning Foreman project directory as `report-{slug}.html`.

Blocked, failed, missing, unreachable, and unknown are distinct conditions. None permits automatic teardown, discard, replacement, or delivery.

A future persistent supervisory task may use the same task model with an isolated Foreman home and explicit charter. It is never silently created as a recovery fallback.

## Worktree, concurrency, and recovery safety

Each change task receives:

- an isolated Git worktree;
- an explicit branch and base identity;
- a unique task-owned runtime endpoint;
- a task-scoped lock and durable task record.

Project-level locks serialize operations that could conflict, such as registration, configuration changes, shared worktree allocation, delivery, and teardown. Task-level locks prevent competing supervisors from adopting or mutating the same worker.

Recovery reconciles durable state against:

- exact worktree and Git identity;
- runtime endpoint identity;
- agent process state;
- task configuration snapshot;
- remote change-request state when applicable.

Ambiguity preserves work. Teardown requires confirmed landing or explicit discard authority for the exact task and worktree.

## Agent and runtime adapters

The initial built-in agent adapters are:

- Claude Code
- Codex CLI
- Gemini CLI
- OpenCode
- Pi

The initial runtimes are tmux and Herdr.

Each agent adapter declares a versioned capability manifest and implements:

- executable and version detection;
- authentication diagnostics;
- supported model and reasoning or effort options;
- worker launch and, where reliable, resume specifications;
- trust and project-instruction requirements;
- completion, interruption, and liveness semantics.

Each runtime adapter implements:

- runtime detection and readiness checks;
- creation of an exact worker endpoint;
- safe literal input and bounded output capture;
- worker-state inspection;
- event waiting or bounded polling;
- exact worker closure and owned-endpoint enumeration.

An unavailable configured adapter is an actionable failure. Foreman must not silently substitute an agent or runtime.

## Remote adapters and delivery

Git is core infrastructure. GitHub and GitLab, including supported self-hosted GitLab instances, are optional remote adapters.

A remote adapter implements normalized operations for:

- remote detection and canonical identity;
- provider-scoped authentication diagnostics;
- change-request creation and observation;
- check or pipeline normalization;
- readiness reporting;
- merge execution;
- confirmed landing observation.

The core speaks in neutral change-request concepts. The adapter presents provider-native terms, such as pull request or merge request, to the user.

### Draft handoff

`draft-handoff` is always available and mandatory for local-only projects.

Foreman creates a durable handoff artifact containing the exact branch and base identity, validation evidence, risks, and provider-native title and description where relevant. It does not push, publish, merge, or locally land work.

### Automated change request

`automated-change-request` is available only for a verified GitHub or GitLab project.

Foreman may push a validated branch, create and publish the change request, monitor it, and preserve its canonical remote identity. Every mutation is gated by the persisted project policy, exact repository identity, validated task state, and live provider diagnostics.

### Merge autonomy

Merge autonomy is an independent project setting and is disabled by default.

When enabled, Foreman may merge only a green, in-scope change request through its verified remote adapter. Unknown or failing checks, ambiguous identity, security-sensitive work, destructive operations, or policy exclusions block the merge. Local-only work is never autonomously landed.

## Supervision and reports

Supervision uses runtime-native events when the selected runtime and agent provide reliable semantics. Otherwise it uses bounded polling and adapter-defined classification.

Append-only events are wake signals and audit evidence, not current-state truth. Current state is always reconciled from durable task metadata, Git, runtime inspection, adapter semantics, and remote state.

Research reports are standalone semantic HTML with embedded CSS and an always-dark presentation that does not vary with the viewer's system theme. They remain readable without a live session, third-party service, or external stylesheet. Their owning task records the report's canonical path and collision-safe slug.

## Repository layout

```text
foreman                  # generated by scripts/install.sh; ignored

src/
  main.sh
  cli.sh
  configuration/
  projects/
  plans/
  state/
  artifacts/
  adapters/
    agents/
    runtimes/
    remotes/
  contracts/
    configuration/
    plan/
    adapter/

scripts/
  install.sh
  check.sh
  check-boundaries.sh
  test.sh

tests/
  portable/
  integration/
  live/

docs/

brain/
```

`src/` is the only tracked product-implementation root. Direct placement under `src/` avoids a redundant `src/foreman/` wrapper in a single-product repository. Adapters and contracts live below it because they are shipped product inputs, while developer and installation utilities live under `scripts/`. `artifacts/` names the code and assets responsible for durable human-readable outputs rather than describing only the rendering mechanism.

The generated root executable keeps clone-local operation obvious without adding a tracked `bin/` directory. Optional command discovery is an installation concern handled by an explicit link, not by a second copy of the implementation.

The command names are neutral and functional. No FirstMate command names or compatibility aliases are retained.

## Verification architecture

Portable tests cover:

- configuration parsing, validation, review, and atomic persistence;
- project identity and path safety;
- task state transitions, locks, recovery, and teardown refusal;
- worktree isolation and unlanded-work protection;
- adapter contracts and malformed-output behavior;
- delivery and merge-policy gates;
- direct-plan, external-handover, and guided-drafting validation and approval gates;
- standalone HTML plan-review generation;
- HTML report creation and collision handling;
- provider-boundary and nautical-terminology scans.

Live tests are opt-in for local development and required as release evidence for supported adapters, tmux and Herdr lifecycle behavior, and GitHub and GitLab delivery paths.

## Provenance and evolution

Foreman is an independent MIT-licensed project that may import and adapt selected FirstMate code from a pinned external reference. Attribution remains auditable through `LICENSE`, `upstream-map.md`, and any notices required when source material is incorporated.

FirstMate behavior is preserved only when it supports Foreman's approved product requirements. No FirstMate state, command, vocabulary, persona, configuration, or compatibility promise enters the target architecture.

Third-party adapter loading and a graphical interface remain outside the initial architecture.
