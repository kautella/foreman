# Adapters

Provider-specific behavior belongs under this directory. The Foreman core communicates with adapters through versioned manifests and normalized JSON results.

An adapter is not supported merely because its directory or contract exists. `contract-only` means no implementation exists; `implemented-unverified` means an implementation has portable evidence but lacks required live evidence; only `supported` requires both implementation and the required verification evidence.
