# Foreman Upstream Map

**Status:** Approved
**Purpose:** Define how Foreman may learn from and selectively import FirstMate while remaining an independent product.

## 1. Migration posture

Foreman preserves useful orchestration outcomes and safety properties from FirstMate. It does not preserve FirstMate's product identity, terminology, commands, operational-home layout, configuration format, delivery assumptions, or compatibility promises.

The governing product definitions are:

- `prd.md`
- `architecture.md`

When this map conflicts with either document, the PRD and Architecture take precedence.

## 2. Baseline and provenance

| Field | Value |
|---|---|
| Upstream | `https://github.com/kunchenguid/firstmate` |
| Initial source revision | `3f035336f9df7331e195bc6279cc1577e1cf4b49` |
| Revision date | `2026-08-21T01:00:26-07:00` |
| Revision subject | `fix: bound recovery announcements and preserve supervision (#2733)` |
| Upstream license | MIT |

The initial Foreman import is fixed at `3f035336f9df7331e195bc6279cc1577e1cf4b49`. This pin provides a reproducible, auditable starting point. It does not freeze Foreman's relationship with FirstMate.

Foreman maintains a one-way, selective upstream-intake process. FirstMate remains an active source of fixes, tests, operational lessons, and feature candidates. Foreman remains the owner of its architecture, vocabulary, policies, schemas, and release decisions.

The first intake review covers every relevant upstream change after the initial import pin. Later reviews cover the range from the last reviewed upstream revision to the newly observed revision.

A separate read-only upstream mirror, outside the Foreman working tree, is the source of record for current upstream discovery. A local reference checkout is a convenience copy only. Neither is Foreman product state, runtime configuration, or a repository artifact.

Foreman may adapt selected source behavior from the pinned reference without importing Git history or a full source snapshot. When source material is incorporated into Foreman-owned code, it must retain the upstream MIT copyright and permission notice, including `Copyright (c) 2026 Kun Chen`, where required by the license.

## 3. Migration rules

1. Preserve outcomes and safety contracts, not source names or file structure.
2. Foreman has no runtime, command, configuration, or state compatibility obligation with FirstMate.
3. A source artifact may be retained, redesigned, replaced, or removed. Every imported behavior and test must receive one of those dispositions.
4. Foreman's canonical state lives under `FOREMAN_HOME`, defaulting to `~/.foreman/`. It never reads or migrates a FirstMate operational home.
5. FirstMate-specific wording must not remain in active product code, schemas, fixtures, user prompts, reports, instructions, or documentation.
6. Source tests that can delete or mutate files may run only in an expendable clone. They must never run against a user repository, the Foreman checkout, or the reference checkout.
7. Foreman's current architecture wins whenever the upstream structure suggests a different boundary.

## 4. Source-to-target map

| FirstMate source family | Foreman target | Disposition | Required outcome |
|---|---|---|---|
| `AGENTS.md`, skills, operational documentation | Foreman-specific instructions and docs | Rewrite | Clear neutral behavior with no prescribed persona or form of address. |
| `FM_HOME`, `data/`, `state/`, `config/`, `projects/` | `FOREMAN_HOME`, `config.json`, `projects/<project>/` | Replace | Strict, schema-versioned JSON configuration and durable state under Foreman ownership. |
| Primary-agent liaison | One authoritative coordination surface | Redesign | Accept direct user plans and external handovers without requiring a particular chat agent to be the sole liaison. |
| Bootstrap, home seeding, diagnostics | `foreman init`, `doctor`, configuration review | Redesign | Reviewed initialization, prerequisite checks, and atomic configuration persistence. |
| Project clones and Treehouse worktree handling | Registered target repositories, optional explicit acquisition, and direct Git worktrees | Replace | Isolated task worktrees without a Treehouse dependency or competing worktree owner. |
| Briefs, backlog handoffs, task inboxes | Versioned execution plans, task briefs, task results | Redesign | Direct plans, external handovers, and guided drafting converge on approved plan JSON. |
| Markdown backlog | Optional human-readable task projection | Redesign/defer | Canonical plan and task state remain validated JSON; a Markdown view cannot become the authoritative machine record. |
| Plan and task reports | `plan-{slug}.html`, `report-{slug}.html` | Add/redesign | Standalone semantic HTML with embedded CSS, stored in Foreman-owned project state. |
| Spawn, watch, state classification, locks, wake queues, teardown | Foreman core lifecycle and contracts | Retain/redesign | Exact task identity, durable events, recovery, fail-closed ambiguity, and safe cleanup. |
| tmux backend | `src/adapters/runtimes/tmux/` | Retain/redesign | Full lifecycle control and exact endpoint safety. |
| Herdr backend and helpers | `src/adapters/runtimes/herdr/` | Retain/redesign | Version-gated lifecycle, recovery, and stability evidence. |
| Zellij, cmux, Orca, Codex App paths | None | Remove | No code, schema, tests, fixtures, docs, or fallback branches remain. |
| Claude Code, Codex CLI, OpenCode, Pi harnesses | Built-in agent adapters | Retain/redesign | Adapter-owned discovery, launch, supervision, recovery, and profile validation. |
| Gemini CLI | `src/adapters/agents/gemini/` | Add | Equivalent lifecycle support and live verification before release support. |
| `pi-signed`, Grok, Kimi, Cursor, Muse | None | Remove | No adapter, compatibility shim, fixture, documentation, or runtime branch remains. |
| GitHub PR scripts | GitHub remote adapter | Redesign | Policy-gated draft handoff, automated change-request delivery, status, and optional merge execution. |
| Partial GitLab support | GitLab remote adapter | Redesign/add | GitLab.com and supported self-hosted GitLab lifecycle parity, including creation, pipeline status, and permitted merge execution. |
| Global GitHub bootstrap requirement | Adapter-scoped remote diagnostics | Remove | Local-only projects work with neither GitHub nor GitLab tooling installed. |
| `no-mistakes` delivery pipeline | Optional future validation integration | Redesign/defer | Foreman owns a provider-neutral validation contract and must not make one external pipeline its universal delivery policy. |
| Quota-based dispatch | Optional future worker-profile adviser | Redesign/defer | It may provide explicit, inspectable recommendations but cannot silently substitute a worker, model, or reasoning level. |
| Interactive visual review sessions | Standalone HTML artifacts, with optional future collaboration integration | Redesign/defer | Plan and research reports remain readable without a session, service, or third-party dependency. |
| Away, resume, status, checkpoint, update outcomes | Neutral Foreman operations | Retain/redesign | Equivalent supervisory outcomes under Foreman-defined neutral commands. |
| Persistent secondary coordinators | Future persistent supervisory tasks | Redesign/defer | Isolated homes, explicit charters, durable handoffs, and no unsafe fallback. |
| Relay, public follow-up, conversational review sessions, Lavish-specific hooks | None | Remove | No public-reply, relay, or review-session machinery in the product core. |
| Source test harness and lint scripts | Foreman test and validation architecture | Port/rewrite/add | Safety guarantees remain tested without inheriting unsafe or obsolete harness assumptions. |

## 5. Explicit removals

Foreman must completely remove FirstMate's nautical theme and persona outside required legal attribution. This includes names, commands, status language, role labels, schema values, configuration keys, fixture values, generated artifacts, tests, examples, documentation, and compatibility aliases.

The following are excluded from Foreman:

- Nautical roles, addresses, names, commands, metaphors, and presentation language.
- FirstMate operational-home and state compatibility, including migration tooling.
- Zellij, cmux, Orca, and Codex App runtime paths.
- `pi-signed`, Grok, Kimi, Cursor Agent CLI, and Muse adapters.
- Treehouse as a Foreman dependency or worktree provider.
- Relay, X or Discord public communication, public follow-ups, and review-session integrations.
- Globally required GitHub authentication or remote tooling.
- Any implicit remote mutation, push, change-request publication, local landing, merge, discard, or merge autonomy.

## 6. Optional future integrations

Foreman initially has no runtime dependency on Treehouse, `no-mistakes`, quota tooling, or an interactive visual-review service.

Treehouse is excluded from Foreman altogether. Its source behavior may inform Git worktree-safety tests, but it has no adapter, configuration, documentation, or active execution path.

`no-mistakes`, quota tooling, and interactive review may be evaluated later as optional integrations only when they have a Foreman-owned contract, explicit configuration, and verification evidence. They cannot become bootstrap requirements, authoritative task state, silent profile-selection mechanisms, or required readers for durable HTML artifacts.

## 7. Import and containment procedure

1. Verify the selected source revision and a clean source tree.
2. Record source identity, file inventory, license, and checksum evidence in the external development reference.
3. Reproduce the inherited test harness only in an expendable clone. Existing evidence shows fixture cleanup can remove its checkout.
4. Build a complete source-artifact and test-disposition inventory before treating imported code as Foreman behavior.
5. Port or rewrite only the selected behavior into Foreman-owned source, preserving required license material.
6. Validate the resulting Foreman-owned code against boundary scans, terminology removal, configuration replacement, and adapted tests.
7. Do not read source configuration, source operational state, or source project storage as Foreman input.

## 8. Test migration policy

Each inherited test receives exactly one classification:

| Classification | Meaning |
|---|---|
| Port | Preserve the same safety or lifecycle contract under Foreman structure. |
| Rewrite | Preserve the guarantee while replacing source-specific implementation assumptions. |
| Replace | Supersede a source-specific test with an adapter or core contract test. |
| Remove | Delete because it tests an explicitly excluded capability. |
| Add | Create new evidence required by Foreman's PRD or Architecture. |

New Foreman evidence must cover at least:

- reviewed project initialization and effective configuration;
- direct plan, external handover, guided drafting, approval refusal, and HTML plan review;
- local-only change and research flows;
- the supported agent and runtime adapter matrix;
- GitHub and GitLab delivery-policy combinations;
- merge-authority and merge-autonomy refusal and approval behavior;
- exact worktree, lock, endpoint, recovery, and unlanded-work safety;
- removal of prohibited terminology, adapters, runtimes, and integrations.

## 9. Ongoing upstream intake

### Cadence

During active migration, perform a lightweight upstream discovery scan daily and a fuller adoption review weekly. Also perform a review before starting a major Foreman phase, cutting a release, or responding to a relevant defect.

After Foreman reaches stable release status, reduce the regular review to weekly while retaining immediate review for security, data-loss, worktree-safety, recovery, or supported-adapter incidents.

A discovery scan is read-only. It fetches upstream references, records the newly observed head, and identifies changes since the previous reviewed revision. It does not change Foreman source code, configuration, or plans.

### Triage

Each upstream commit or related group of commits is classified as one of:

| Classification | Meaning |
|---|---|
| Adopt | A useful bug fix, safety improvement, test, or in-scope capability worth implementing in Foreman. |
| Defer | Potentially useful, but blocked by Foreman's current phase, missing architecture, or insufficient evidence. |
| Decline | Incompatible with Foreman's PRD, architecture, supported adapters, or explicit exclusions. |
| Inform | Useful context or design evidence that does not justify a code change. |

Feature additions require a fit review against Foreman's PRD and Architecture. They do not become requirements merely because FirstMate implemented them.

Fixes affecting retained safety properties, such as worktree protection, recovery, durable state, endpoint identity, or supervision, receive priority triage.

### Adoption procedure

For every adopted upstream change:

1. Record the upstream commit or range, affected source files, and the behavior being preserved.
2. Map the source behavior to Foreman's core or adapter boundary.
3. Port or rewrite the relevant safety tests before or alongside the implementation.
4. Implement the change as Foreman-owned code, without importing FirstMate naming, configuration, state, or compatibility behavior.
5. Validate it against Foreman's local-only and applicable adapter contracts.
6. Record the adoption, divergence, and remaining limitations in the upstream intake record.

Foreman never performs a blind merge, rebase, or bulk cherry-pick from FirstMate. A source patch is evidence and an implementation donor, not an authority over Foreman's design.

### Durable records

`upstream-map.md` defines the standing policy and source-family mapping.

Each discovery or adoption review records:

- reviewed source range and observed upstream head;
- commits or themes considered;
- adopt, defer, decline, or inform decisions;
- reasoning and affected Foreman surfaces;
- source tests and Foreman evidence;
- the next review starting point.

Once Foreman can supervise this process itself, these reviews become Foreman research tasks. Their standalone HTML reports live in Foreman's own managed-project state, not in the target repository.

### Automation boundary

Upstream discovery may become a scheduled read-only monitoring task. Adoption never becomes automatic: every imported behavior still requires explicit triage, a Foreman execution plan, normal validation, and the project's delivery policy.

## 10. Completion criteria

The upstream migration is complete only when:

- every retained outcome has Foreman-owned implementation and evidence;
- every imported source artifact and test has a documented disposition;
- every excluded feature has no active implementation, schema, fixture, documentation, or compatibility path;
- local-only operation succeeds without remote tooling;
- GitHub and GitLab satisfy Foreman's normalized remote contract;
- only Claude Code, Codex CLI, Gemini CLI, OpenCode, Pi, tmux, and Herdr remain supported;
- all active terminology is neutral and ordinary;
- legal attribution and source provenance are complete;
- subsequent upstream changes have an active, documented intake path.
