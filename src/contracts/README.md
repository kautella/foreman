# Contracts

This directory contains strict, versioned JSON schemas and examples for Foreman configuration, plans, tasks, adapters, and normalized results.

Plan input, external handover, and canonical review contracts live under `plan/`. Durable task-state contracts live under `task/`.

Mechanically consumed state must validate against an applicable contract before the core accepts it.
