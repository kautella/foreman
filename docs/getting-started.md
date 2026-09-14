# Getting Started

Foreman's current Phase 1 command surface registers projects and reviews execution plans. It does not launch workers, create task worktrees, or deliver changes.

## Prerequisites

Foreman currently requires Bash, Git, and `jq`. Project initialization also verifies that the selected agent and runtime commands are available without invoking them.

Generate the ignored repository-local launcher after cloning:

```sh
./scripts/install.sh
```

Codex operating from this checkout may do this automatically when `./foreman` is first needed. The launcher delegates to the tracked implementation in `src/` and can be regenerated safely at any time.

## Register a project

Run `foreman init` with the project name and repository root. Foreman asks for any required choice that is not supplied, prints the complete proposed configuration, and saves it only after confirmation.

```sh
./foreman init \
  --name "Example Project" \
  --project /absolute/path/to/repository \
  --agent codex \
  --model model-identifier \
  --reasoning high \
  --runtime tmux
```

The default home is `~/.foreman`. It contains the global `config.json` and an isolated `projects/<project-slug>/` directory for every registered project. Set `FOREMAN_HOME` to an absolute path to use a different home.

Run a read-only configuration and project identity check with:

```sh
./foreman doctor --project example-project
```

## Prepare a plan

View the recommended input structure:

```sh
./foreman plan template
```

A direct machine-readable plan uses the structure in [`src/contracts/plan/examples/direct-plan.json`](../src/contracts/plan/examples/direct-plan.json):

```sh
./foreman plan create \
  --project example-project \
  --file /absolute/path/to/plan.json
```

An external system can use the versioned envelope in [`src/contracts/plan/examples/external-handover.json`](../src/contracts/plan/examples/external-handover.json):

```sh
./foreman plan handover \
  --project example-project \
  --file /absolute/path/to/handover.json
```

For a small one-task proposal, Foreman can ask focused questions:

```sh
./foreman plan guided --project example-project
```

All three routes validate the input, apply the registered project policy, create deterministic canonical plan JSON, and produce a standalone `plan-{slug}.html` review under the project's Foreman state. They do not change the managed repository.

## Approve a reviewed plan

Resolve all missing information and blocking decisions before approval. Then approve the exact stored plan ID:

```sh
./foreman plan approve \
  --project example-project \
  --plan plan-0123456789ab
```

Approval is durable but deliberately non-executable in Phase 1. Worker execution begins in a later phase after its isolation, supervision, recovery, and validation guarantees exist.
