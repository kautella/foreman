# Progress

## Status

Foreman is in documentation initialization.

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

## Not started

- The first repository commit.
- `NOTICE.md` and the provenance manifest.
- The inert FirstMate source import.
- Inherited test containment or baseline reproduction.
- `FOREMAN_HOME`, configuration, plan intake, adapter contracts, task lifecycle, and provider implementations.
- The first upstream discovery record.

## Confirmed risk

Existing source investigation found that FirstMate fixture cleanup can remove its disposable checkout under some inherited test-harness conditions.

No inherited test suite may run in the Foreman checkout or another non-disposable repository. The behavior must be reproduced and contained before inherited tests become evidence for Foreman.

## Current constraints

- No imported source is active Foreman code merely because it exists for provenance.
- No capability is represented as supported without implementation and verification evidence.
- No provider executable may be invoked from the Foreman core.
- No upstream change bypasses the approved intake, planning, validation, and delivery process.
- Ambiguous identity, ownership, liveness, delivery, or landing state must preserve work and block mutation.

## Next verified checkpoint

Create the first project commit.

Then begin F1-001: establish the source baseline, attribution, provenance manifest, and inert-import boundary.
