# Progress

## Status

Foreman is in Phase 1, following verification of the external source reference.

The approved product contract, architecture, upstream map, Phase 1 backlog, and Project Brain routing are complete and live under `brain/`.

No active Foreman implementation exists.

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

## Not started

- Inherited test containment or baseline reproduction.
- `FOREMAN_HOME`, configuration, plan intake, adapter contracts, task lifecycle, and provider implementations.
- The first upstream discovery record.

## Confirmed risk

Existing source investigation found that FirstMate fixture cleanup can remove its disposable checkout under some inherited test-harness conditions.

No inherited test suite may run in the Foreman checkout or another non-disposable repository. The behavior must be reproduced and contained before inherited tests become evidence for Foreman.

## Current constraints

- No external source reference is active Foreman code, instructions, configuration, or test input.
- No capability is represented as supported without implementation and verification evidence.
- No provider executable may be invoked from the Foreman core.
- No upstream change bypasses the approved intake, planning, validation, and delivery process.
- Ambiguous identity, ownership, liveness, delivery, or landing state must preserve work and block mutation.

## Next verified checkpoint

Complete F1-002: reproduce and contain inherited test execution in a validated expendable environment.

Then complete F1-003: produce a trustworthy source-baseline report without treating inherited tests as Foreman evidence until containment is proven.
