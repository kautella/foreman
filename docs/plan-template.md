# Foreman Plan Template

Use this structure when preparing a direct plan or handing work to Foreman from another system. Clear boundaries and observable acceptance criteria produce the most reliable execution.

## Plan

- **Title:** A short durable name.
- **Objective:** The outcome to achieve and why it matters.
- **Included scope:** Work that belongs in the plan.
- **Excluded scope:** Nearby work that must not be included.
- **Constraints:** Safety, architecture, compatibility, or process boundaries.
- **Acceptance criteria:** Observable conditions that define complete work.
- **Assumptions:** Statements currently treated as true.
- **Risks:** A risk and its proposed mitigation.
- **Missing information:** Information still needed.
- **Unresolved decisions:** A clear question and whether it blocks approval.
- **References:** Labelled source links or durable identifiers.

## Tasks

For every task provide:

- a stable lowercase identifier;
- `change` or `research` as its type;
- a short title and bounded objective;
- identifiers of tasks it depends on;
- task-specific acceptance criteria;
- validation commands or evidence requirements;
- `project-default`, `draft-handoff`, or `automated-change-request` as the delivery expectation;
- an optional worker-profile hint containing agent, model, and reasoning or effort.

The machine-readable example at [`contracts/plan/examples/direct-plan.json`](../contracts/plan/examples/direct-plan.json) is the authoritative input shape. An external coordinator wraps that shape using [`contracts/plan/examples/external-handover.json`](../contracts/plan/examples/external-handover.json).

Plan provenance never grants delivery, merge, discard, or execution authority. Foreman applies the registered project policy and requires explicit approval after rendering the review artifact.
