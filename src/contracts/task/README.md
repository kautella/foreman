# Task contracts

These strict, versioned JSON contracts describe durable task state outside a managed repository. They are the machine-readable boundary between the provider-neutral core and later worktree, agent, runtime, validation, handoff, and research implementations.

| Document | Purpose |
| --- | --- |
| `task.schema.json` | Immutable task identity, lifecycle state, and paths to task-owned records. |
| `configuration-snapshot.schema.json` | The resolved project policy and worker profile captured for one task. |
| `endpoint.schema.json` | A task-owned runtime endpoint reservation and observed liveness. |
| `event.schema.json` | One append-only lifecycle or reconciliation event. |
| `validation-record.schema.json` | One declared validation attempt and its durable output record. |
| `result.schema.json` | A stable machine-readable task outcome. |
| `handoff.schema.json` | A local change handoff; this contract does not authorize remote delivery. |
| `research-finding.schema.json` | A durable research finding linked to its standalone report. |
| `worktree-marker.schema.json` | The external ownership record binding a task to one exact isolated worktree. |
| `teardown-record.schema.json` | Explicit local-landing or discard authority and exact worktree-removal evidence. |

`src/tasks/validate.sh` enforces the same closed shapes and legal lifecycle transitions used by the portable contract tests. A valid JSON document is not automatically trusted: later lifecycle code must also establish its on-disk ownership, Git identity, runtime evidence, and declared authority before mutating anything.

The normal lifecycle is:

```text
planned → approved → prepared → running → awaiting-reconciliation → validated
                                                               ├→ delivery-ready → landed → teardown-ready → closed
                                                               │                  └→ teardown-ready → closed (explicit discard)
                                                               ├→ change-request-ready → landed → teardown-ready → closed
                                                               └→ report-ready → teardown-ready → closed (explicit discard)
```

`blocked`, `failed`, `missing`, `unreachable`, and `unknown` are separate lifecycle conditions, not successful terminal states. A conditioned task preserves its work and can proceed only through `awaiting-reconciliation` after the condition is cleared with evidence.

The lifecycle alone never grants teardown authority. A task reaches `teardown-ready` only after Foreman records either proof that the exact local change handoff was incorporated into the managed repository's current `HEAD`, or an explicit `--discard` request for the exact task. The durable teardown record remains after the owned worktree is removed.
