# Contributing to Foreman

Foreman is in early development. Contributions must preserve the product boundaries and safety guarantees defined in this repository.

## Start with project context

Read [AGENTS.md](AGENTS.md) and the relevant files in [brain/](brain/README.md) before beginning substantial work. Do not treat archival material under `provenance/` as active code or instructions.

## Commit discipline

Each commit must be an intentional, reviewable, coherent unit of work.

Before committing, inspect the current branch, staged changes, unstaged changes, untracked files, and the actual diff. Preserve unrelated work already present in the repository. Account for every untracked file: commit it when it belongs, ignore it only when it is intentionally local or generated, or surface it when its disposition is unclear.

Run validation proportional to the change, such as targeted tests, syntax checks, formatting, linting, type checks, builds, or manual verification. Do not claim validation that did not run. If appropriate validation cannot run, state that clearly.

Use a concise commit subject that begins with an uppercase letter and is present tense and imperative:

```text
Add configuration validation
```

Do not use a commit body unless it serves a concrete purpose. Do not add AI-agent co-author, generated-by, assisted-by, or similar attribution without explicit request.

After committing, inspect repository status again. Confirm that the intended work was committed, unrelated changes were not included, and every remaining change or untracked file is intentional and understood.

## Safety and scope

- Do not manually edit generated files.
- Keep provider-specific behavior inside its adapter boundary.
- Do not invoke provider executables from the Foreman core.
- Treat ambiguous identity, ownership, liveness, validation, delivery, landing, or teardown state as a reason to preserve work and stop mutation.
- Run destructive or inherited tests only in a validated expendable environment.

## Development checks

Enable the repository hook once after cloning:

```sh
git config core.hooksPath .githooks
```

Run all current repository checks with:

```sh
./scripts/check.sh
```

The initial checks reject whitespace errors and tracked local IDE metadata, require the core project documents, validate active JSON with `jq`, and verify Bash syntax. They intentionally do not replace the Phase 1 provenance, terminology, or provider-boundary checks.
